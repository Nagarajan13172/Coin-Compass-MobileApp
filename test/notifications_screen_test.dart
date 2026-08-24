import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/core/widgets/app_scaffold.dart';
import 'package:coincompass/core/widgets/empty_state.dart';
import 'package:coincompass/features/notifications/data/notifications_repository.dart';
import 'package:coincompass/features/notifications/domain/app_notification.dart';
import 'package:coincompass/features/notifications/presentation/notifications_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Notifications screen at 360 × 800dp, plus the two pure functions it
/// leans on (link mapping and day grouping).
///
/// SAFETY: nothing here reaches the live API. Every request goes through
/// [_FakeApi], a Dio adapter that answers from `test/fixtures/notifications.json`
/// and records the verb + path of anything else. The four mutations
/// (`POST /notifications/:id/read`, `POST /notifications/read-all`,
/// `DELETE /notifications/:id`, `DELETE /notifications`) are asserted only as
/// recorded calls against that fake — they have never been fired at the
/// owner's real feed, which still holds its six genuinely unread rows.
void main() {
  const Size phone = Size(360, 800);
  const String firstId = '6a712b80cf44dc86406a55f7';

  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('coincompass_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String fixture() =>
      File('test/fixtures/notifications.json').readAsStringSync();

  // ───────────────────────────────────────────────────────────────────────────
  // link mapping
  // ───────────────────────────────────────────────────────────────────────────

  group('notificationRoute — web link to mobile route', () {
    test('the two links the live feed actually carries', () {
      // Verbatim from test/fixtures/notifications.json.
      expect(
        notificationRoute('/recurring', wealthVisible: true),
        '/recurring',
      );
      // Mobile has no account detail screen; the list is where that account is.
      expect(
        notificationRoute(
          '/accounts/6a4669f861d974fd74ab42a0',
          wealthVisible: true,
        ),
        '/accounts',
      );
    });

    test('a deep route wins over its parent', () {
      expect(
        notificationRoute('/net-worth/holdings', wealthVisible: true),
        '/net-worth/holdings',
      );
      expect(
        notificationRoute('/net-worth', wealthVisible: true),
        '/net-worth',
      );
    });

    test('web-only paths redirect to the screen that carries them here', () {
      expect(
        notificationRoute('/people', wealthVisible: true),
        '/credits/people',
      );
      expect(
        notificationRoute('/splits', wealthVisible: true),
        '/credits/splits',
      );
      expect(
        notificationRoute('/holdings', wealthVisible: true),
        '/net-worth/holdings',
      );
      expect(notificationRoute('/dashboard', wealthVisible: true), '/');
    });

    test('query strings are dropped, not forwarded as a guess', () {
      expect(
        notificationRoute(
          '/transactions?from=2026-08-01&type=expense',
          wealthVisible: true,
        ),
        '/transactions',
      );
    });

    test('anything unroutable is a no-op rather than a 404 screen', () {
      expect(notificationRoute(null, wealthVisible: true), isNull);
      expect(notificationRoute('', wealthVisible: true), isNull);
      expect(notificationRoute('   ', wealthVisible: true), isNull);
      expect(notificationRoute('/nowhere-at-all', wealthVisible: true), isNull);
      // Absolute URLs are not in-app links.
      expect(
        notificationRoute(
          'https://coincompass.app/recurring',
          wealthVisible: true,
        ),
        isNull,
      );
      expect(notificationRoute('recurring', wealthVisible: true), isNull);
    });

    test('a bare slash is the dashboard', () {
      expect(notificationRoute('/', wealthVisible: true), '/');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // day grouping
  // ───────────────────────────────────────────────────────────────────────────

  group('groupNotificationsByDay', () {
    List<AppNotification> live() =>
        NotificationFeed.fromJson(jsonDecode(fixture())).items;

    test('the live feed buckets into three days, order preserved', () {
      final days = groupNotificationsByDay(live());
      // Two rows minted at the same instant on 4 Aug, three on 1 Aug, one in
      // July. Each cluster shares an instant, so the split is the same in every
      // timezone the suite might run under.
      expect(days.map((d) => d.items.length), [2, 3, 1]);
      expect(days.first.items.first.id, firstId);
      expect(days.first.unread, 2);
    });

    test('an empty feed produces no groups', () {
      expect(groupNotificationsByDay(const []), isEmpty);
    });

    test(
      'rows with no createdAt are kept, in an Earlier bucket at the end',
      () {
        final undated = AppNotification.fromJson(const {
          '_id': 'x1',
          'type': 'recurring.ended',
          'params': {'ruleTitle': 'Rent'},
        });
        final days = groupNotificationsByDay([...live(), undated]);
        expect(days.length, 4);
        expect(days.last.day, isNull);
        expect(days.last.items.single.id, 'x1');
        expect(notificationDayLabel(days.last.day), 'Earlier');
      },
    );

    test(
      'day labels name today and yesterday, and keep the year after that',
      () {
        final now = DateTime(2026, 8, 24, 9);
        expect(
          notificationDayLabel(DateTime(2026, 8, 24, 1), now: now),
          'Today',
        );
        expect(
          notificationDayLabel(DateTime(2026, 8, 23, 23), now: now),
          'Yesterday',
        );
        // "04 Aug" alone would not say which August on a feed going back months.
        expect(
          notificationDayLabel(DateTime(2026, 8, 4), now: now),
          '04 Aug 2026',
        );
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // the screen
  // ───────────────────────────────────────────────────────────────────────────

  Future<_FakeApi> pump(
    WidgetTester tester, {
    String? body,
    int status = 200,
    ThemeData? theme,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    late _FakeApi fake;
    await tester.runAsync(() async {
      final api = await ApiClient.create();
      fake = _FakeApi(body: body ?? fixture(), status: status);
      api.dio.httpClientAdapter = fake;
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      // Held open for the life of the test so the screen mounts against a
      // resolved provider rather than refetching under the fake clock.
      container.listen<Object?>(notificationFeedProvider, (a, b) {});
      await container
          .read(notificationFeedProvider.future)
          .catchError((Object _) => const NotificationFeed());
    });
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const Scaffold(body: NotificationsScreen()),
        ),
        GoRoute(
          path: '/recurring',
          builder: (_, _) => const Scaffold(body: Text('RECURRING SCREEN')),
        ),
        GoRoute(
          path: '/accounts',
          builder: (_, _) => const Scaffold(body: Text('ACCOUNTS SCREEN')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: theme ?? AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    // Explicit durations only: the loading skeleton and the per-row busy
    // spinner are indeterminate animations, and pumpAndSettle on either never
    // returns.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return fake;
  }

  /// Advances a bounded number of frames. Every animation on this screen is
  /// either a 250ms sheet transition or a Dio round trip on a zero-duration
  /// timer, so a fixed budget is enough — and unlike `pumpAndSettle` it cannot
  /// hang on the indeterminate spinner a busy row shows.
  Future<void> pumpFrames(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Drives the bottom sheet's entry animation without settling.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Scrolls [finder] into the viewport without animating — the rows below the
  /// fold are off-screen at 360 × 800dp.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 8; i++) {
      await tester.drag(scrollable, const Offset(0, -320));
      await tester.pump();
    }
  }

  testWidgets('loaded — the real feed at 360dp, grouped by day', (
    tester,
  ) async {
    final fake = await pump(tester);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('6 unread of 6 notifications'), findsOneWidget);

    // Titles are the type's fixed heading, never the rule's own name — every
    // one of these six rows has params.ruleTitle "Recurring" or account "Cash".
    expect(find.text('Recurring posted'), findsNWidgets(2));
    expect(find.text('Coming up'), findsNWidgets(2));
    expect(find.text('Low balance'), findsNWidgets(2));

    // Bodies are composed from (type, params), money in the row's own currency
    // and the U+2212 minus the web uses.
    expect(
      find.text('Recurring posted 1 transaction (₹12,312).'),
      findsOneWidget,
    );
    expect(find.text('Cash is overdrawn (−₹7,50,633).'), findsNWidgets(2));
    expect(
      find.text('Recurring is scheduled for 04 Aug 2026 (₹12,312).'),
      findsOneWidget,
    );

    // Three day headers, each carrying its own unread count.
    expect(find.text('2 new'), findsOneWidget);
    expect(find.text('3 new'), findsOneWidget);
    expect(find.text('1 new'), findsOneWidget);

    // The link destination is named on the row, already mapped to the mobile
    // route: four rows link to /recurring, two to /accounts/{id} -> /accounts.
    expect(find.text('Recurring'), findsNWidgets(4));
    expect(find.text('Accounts'), findsNWidgets(2));

    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
    // A pure read: one GET and nothing else.
    expect(fake.calls, ['GET /notifications']);
  });

  testWidgets('loaded — dark mode renders without an overflow', (tester) async {
    await pump(tester, theme: AppTheme.dark());
    expect(find.text('Recurring posted'), findsWidgets);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty — the caught-up state, with both bulk actions off', (
    tester,
  ) async {
    final fake = await pump(tester, body: '{"items":[],"unread":0}');

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text("You're all caught up"), findsOneWidget);
    expect(find.text('6 unread of 6 notifications'), findsNothing);

    // Both header buttons exist but are disabled — tapping raises no sheet.
    await tester.tap(find.text('Mark all read'));
    await openSheet(tester);
    expect(find.text('Mark all as read?'), findsNothing);
    await tester.tap(find.text('Clear all'));
    await openSheet(tester);
    expect(find.text('Delete every notification?'), findsNothing);

    expect(tester.takeException(), isNull);
    expect(fake.calls, ['GET /notifications']);
  });

  testWidgets('error — the feed fails and offers a retry', (tester) async {
    final fake = await pump(tester, body: '{"error":"nope"}', status: 500);

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // The header still renders, so the screen is not a blank page.
    expect(find.text('Notifications'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await pumpFrames(tester);
    expect(fake.calls.length, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('degenerate — unknown type, no params, no link, no timestamp', (
    tester,
  ) async {
    // Everything the composer can be handed and still has to render: a type
    // this build predates, an empty params bag, a null link, a missing
    // createdAt, and a rule title long enough to wrap twice at 360dp.
    final long = 'Standing instruction — ${'Bengaluru ' * 12}rent';
    final body = jsonEncode({
      'items': [
        {
          '_id': 'u1',
          'type': 'goal.milestone_reached',
          'params': {'goal': 'Emergency fund'},
          'read': false,
          'link': '/goals',
        },
        {
          '_id': 'u2',
          'type': 'budget.exceeded',
          'params': const <String, dynamic>{},
          'read': true,
          'link': '/nowhere',
          'createdAt': '2026-08-24T04:00:00.000Z',
        },
        {
          '_id': 'u3',
          'type': 'recurring.overdue',
          'params': {
            'ruleTitle': long,
            'amount': 123456789,
            'currency': 'USD',
            'date': '2026-07-04T00:00:00.000Z',
          },
          'read': false,
        },
      ],
      'unread': 2,
    });

    await pump(tester, body: body);

    // The unknown type is humanised, not printed as an i18n key.
    expect(find.text('Milestone reached'), findsOneWidget);
    expect(find.textContaining('types.'), findsNothing);
    // An empty params bag still renders a sentence, with empty interpolations —
    // the same thing the web produces.
    expect(find.text('Budget exceeded'), findsOneWidget);
    // A row with no createdAt lands in Earlier rather than being dropped.
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    // Nine figures in a foreign currency, on a title that wraps: still no clip.
    expect(find.textContaining(r'$12,34,56,789'), findsOneWidget);

    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mark all read — cancelling the ConfirmSheet sends nothing', (
    tester,
  ) async {
    final fake = await pump(tester);

    await tester.tap(find.text('Mark all read'));
    await openSheet(tester);
    expect(find.text('Mark all as read?'), findsOneWidget);
    expect(
      find.textContaining('6 notifications will be marked read'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await pumpFrames(tester);

    expect(fake.calls, ['GET /notifications']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mark all read — confirming posts read-all and refetches', (
    tester,
  ) async {
    final fake = await pump(tester);

    await tester.tap(find.text('Mark all read'));
    await openSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Mark all read'));
    await pumpFrames(tester);

    expect(fake.calls, contains('POST /notifications/read-all'));
    // No optimistic update on the web either — it just invalidates and refetches.
    expect(
      fake.calls.where((c) => c == 'GET /notifications').length,
      greaterThanOrEqualTo(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear all — confirming deletes the whole feed', (tester) async {
    final fake = await pump(tester);

    await tester.tap(find.text('Clear all'));
    await openSheet(tester);
    expect(find.text('Delete every notification?'), findsOneWidget);
    expect(
      find.textContaining('All 6 notifications are permanently deleted'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Delete all'));
    await pumpFrames(tester);

    expect(fake.calls, contains('DELETE /notifications'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismiss — the per-row X confirms, then deletes just that one', (
    tester,
  ) async {
    final fake = await pump(tester);

    await tester.tap(find.byIcon(LucideIcons.x).first);
    await openSheet(tester);
    expect(find.text('Dismiss this notification?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
    await pumpFrames(tester);

    expect(fake.calls, contains('DELETE /notifications/$firstId'));
    expect(fake.calls, isNot(contains('DELETE /notifications')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('row tap — marks read and follows the link to a mobile route', (
    tester,
  ) async {
    final fake = await pump(tester);

    await tester.tap(find.text('Recurring posted').first);
    await pumpFrames(tester);

    expect(fake.calls, contains('POST /notifications/$firstId/read'));
    // `/recurring` exists here verbatim.
    expect(find.text('RECURRING SCREEN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row tap — an account link lands on the accounts list', (
    tester,
  ) async {
    final fake = await pump(tester);

    final row = find.text('Low balance').first;
    await reveal(tester, row);
    await tester.tap(row);
    await pumpFrames(tester);

    expect(find.text('ACCOUNTS SCREEN'), findsOneWidget);
    expect(fake.calls.any((c) => c.startsWith('POST /notifications/')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shell bell carries the feed unread count, capped at 9+', (
    tester,
  ) async {
    Future<void> mountShell(String body) async {
      tester.view
        ..physicalSize = phone
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late ProviderContainer container;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final api = await ApiClient.create();
        api.dio.httpClientAdapter = _FakeApi(body: body);
        container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
        );
        container.listen<Object?>(notificationFeedProvider, (a, b) {});
        await container
            .read(notificationFeedProvider.future)
            .catchError((Object _) => const NotificationFeed());
      });
      addTearDown(container.dispose);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const AppScaffold(location: '/', child: SizedBox.shrink()),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // The owner's real feed: six unread.
    await mountShell(fixture());
    expect(find.text('6'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Server-supplied count, not a tally of the rows returned — and capped.
    await mountShell('{"items":[],"unread":42}');
    expect(find.text('9+'), findsOneWidget);

    // Nothing unread means no badge at all, the same as the web.
    await mountShell('{"items":[],"unread":0}');
    expect(find.text('9+'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row tap — an already-read row with no route stays put', (
    tester,
  ) async {
    final fake = await pump(
      tester,
      body: jsonEncode({
        'items': [
          {
            '_id': 'r1',
            'type': 'recurring.ended',
            'params': {'ruleTitle': 'Netflix'},
            'read': true,
            'link': '/nowhere',
            'createdAt': '2026-08-24T04:00:00.000Z',
          },
        ],
        'unread': 0,
      }),
    );

    expect(find.text('1 notification · all read'), findsOneWidget);
    await tester.tap(find.text('Recurring ended'));
    await pumpFrames(tester);

    // Already read, so no mark-read; unroutable, so no navigation.
    expect(fake.calls, ['GET /notifications']);
    expect(find.text('Recurring ended'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Answers `GET /notifications` from a canned body and every mutation with an
/// empty 200, recording "VERB /path" for each. Nothing here talks to a network.
class _FakeApi implements HttpClientAdapter {
  _FakeApi({required this.body, this.status = 200});

  final String body;
  final int status;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    calls.add('${options.method} $path');

    if (options.method == 'GET' && path == '/notifications') {
      return _json(body, status);
    }
    if (path == '/notifications' || path.startsWith('/notifications/')) {
      return _json('{"ok":true}', 200);
    }
    return _json('{"error":"not found"}', 404);
  }

  ResponseBody _json(String payload, int code) => ResponseBody.fromString(
    payload,
    code,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
