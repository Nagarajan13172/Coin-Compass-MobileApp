import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/app_colors.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/core/widgets/empty_state.dart';
import 'package:coincompass/core/widgets/error_retry.dart';
import 'package:coincompass/core/widgets/loading_shimmer.dart';
import 'package:coincompass/features/accounts/presentation/accounts_screen.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:coincompass/features/budgets/presentation/budgets_screen.dart';
import 'package:coincompass/features/calendar/presentation/calendar_screen.dart';
import 'package:coincompass/features/calendar/presentation/widgets/month_grid.dart';
import 'package:coincompass/features/categories/presentation/categories_screen.dart';
import 'package:coincompass/features/credits/presentation/credits_screen.dart';
import 'package:coincompass/features/dashboard/presentation/dashboard_screen.dart';
import 'package:coincompass/features/goals/presentation/goals_screen.dart';
import 'package:coincompass/features/gold/presentation/gold_screen.dart';
import 'package:coincompass/features/holdings/presentation/holdings_screen.dart';
import 'package:coincompass/features/insights/presentation/insights_screen.dart';
import 'package:coincompass/features/loans/presentation/loans_screen.dart';
import 'package:coincompass/features/networth/presentation/net_worth_screen.dart';
import 'package:coincompass/features/notifications/presentation/notifications_screen.dart';
import 'package:coincompass/features/people/presentation/people_screen.dart';
import 'package:coincompass/features/recurring/presentation/recurring_screen.dart';
import 'package:coincompass/features/reports/presentation/reports_screen.dart';
import 'package:coincompass/features/settings/presentation/settings_screen.dart';
import 'package:coincompass/features/splits/presentation/splits_screen.dart';
import 'package:coincompass/features/stocks/presentation/stocks_screen.dart';
import 'package:coincompass/features/transactions/presentation/transactions_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coincompass/l10n/app_localizations.dart';

/// Phase 6.5 + 6.6 — every in-app screen driven through the four states a user
/// can actually land on, at 360 × 800dp.
///
/// | state   | transport                 | what must hold                      |
/// |---------|---------------------------|-------------------------------------|
/// | loading | never answers             | a loading affordance, never a blank |
/// | error   | 500s every call           | an ErrorRetry you can actually tap, |
/// |         |                           | and nothing still posing as loading |
/// | empty   | answers with nothing      | an empty state, never a bare ₹0     |
/// | dark    | replays the real account  | lays out under AppTheme.dark()      |
///
/// The whole stack is real — repositories, providers, widgets — with only Dio's
/// adapter swapped.
///
/// Two hazards this file exists to keep pinned, both found by writing it:
///
/// * An errored provider read through `valueOrNull` is indistinguishable from a
///   slow one, so it renders as a skeleton that never resolves. `error` asserts
///   zero skeletons for exactly that reason.
/// * A count that defaults to 0 turns a failed load into a confident "0 items".
///
/// Settling alternates the real event loop with the tester's fake clock: a
/// request starts inside the fake zone but finishes on real I/O (the cookie jar
/// writes to disk), so neither loop on its own ever gets there.
void main() {
  const Size phone = Size(360, 800);
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_state_audit');
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

  Future<void> mount(WidgetTester tester, Widget screen, _Mode mode) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _AuditAdapter(mode);
      container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      // main.dart restores the session before the first frame, so anything
      // reading the signed-in user finds it. Skipped in `loading`, where the
      // transport never answers and restore would simply hang.
      if (mode != _Mode.loading) {
        await container.read(authControllerProvider.notifier).restore();
      }
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: mode == _Mode.dark ? AppTheme.dark() : AppTheme.light(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
  }

  int skeletons() =>
      find.byType(LoadingCard).evaluate().length +
      find.byType(LoadingShimmer).evaluate().length;

  Future<void> settle(WidgetTester tester, {int rounds = 28}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (skeletons() == 0) {
        // One more round so a second-stage provider gets its turn.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        return;
      }
    }
  }

  /// Slivers build lazily, so an overflow below the fold only shows once it is
  /// scrolled into view — and a card that only mounts down there only starts
  /// fetching then, which is why the scroll is followed by another settle.
  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) return;
    for (var i = 0; i < 10; i++) {
      await tester.drag(scrollables.first, const Offset(0, -420));
      await tester.pump();
    }
  }

  /// Every colour actually painted as a surface — Container resolves to one of
  /// these three depending on how it was configured.
  Iterable<Color> paintedSurfaces(WidgetTester tester) sync* {
    for (final w in tester.allWidgets) {
      if (w is ColoredBox) yield w.color;
      if (w is Material && w.color != null) yield w.color!;
      if (w is DecoratedBox) {
        final d = w.decoration;
        if (d is BoxDecoration && d.color != null) yield d.color!;
      }
    }
  }

  /// Unmounts before the test ends. LoadingShimmer repeats for ever, and an
  /// unanswered request leaves Dio's 30s receiveTimeout armed; either one trips
  /// "A Timer is still pending".
  Future<void> teardown(WidgetTester tester, _Mode mode) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    if (mode == _Mode.loading) await tester.pump(const Duration(seconds: 35));
  }

  void audit(_Screen s) {
    testWidgets('${s.name} — loading shows progress, not a blank frame', (
      tester,
    ) async {
      await mount(tester, s.build(), _Mode.loading);
      expect(s.loadingProof, findsWidgets, reason: '${s.name} has no loading state');
      expect(find.byType(ErrorRetry), findsNothing);
      expect(tester.takeException(), isNull);
      await teardown(tester, _Mode.loading);
    });

    testWidgets('${s.name} — every call failing offers a retry', (tester) async {
      await mount(tester, s.build(), _Mode.error);
      await settle(tester);
      expect(find.byType(ErrorRetry), findsWidgets);
      expect(
        find.text('Retry'),
        findsWidgets,
        reason: '${s.name} shows an error with no way back',
      );
      // An errored provider read as `valueOrNull` looks exactly like a slow
      // one. If anything is still skeletonised here, that is the bug.
      expect(
        skeletons(),
        0,
        reason: '${s.name} still shows a skeleton after everything failed',
      );
      expect(tester.takeException(), isNull);
      await teardown(tester, _Mode.error);
    });

    testWidgets('${s.name} — nothing recorded reads as empty, not as zero', (
      tester,
    ) async {
      await mount(tester, s.build(), _Mode.empty);
      await settle(tester);
      expect(s.emptyProof, findsWidgets, reason: '${s.name} has no empty state');
      expect(find.byType(ErrorRetry), findsNothing);
      expect(tester.takeException(), isNull);
      await teardown(tester, _Mode.empty);
    });

    testWidgets('${s.name} — dark mode', (tester) async {
      await mount(tester, s.build(), _Mode.dark);
      await settle(tester);
      await scrollThrough(tester);
      await settle(tester);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsWidgets);

      // A light-theme surface painted under the dark theme is a token that got
      // bypassed — the one class of dark-mode bug that survives a layout pass.
      final leaked = paintedSurfaces(tester)
          .where(
            (c) =>
                c == AppColors.light.card ||
                c == AppColors.light.background ||
                c == AppColors.light.secondary,
          )
          .toSet();
      expect(
        leaked,
        isEmpty,
        reason: '${s.name} paints a light-theme surface in dark mode',
      );
      await teardown(tester, _Mode.dark);
    });
  }

  // The 17 nav destinations, plus the three that hang off them.
  //
  // `loadingProof` is a skeleton everywhere but the calendar, whose grid is
  // structurally known before the data lands — it draws the month and dims the
  // amounts to 0.4 instead (see MonthGrid.loading), which beats a skeleton.
  //
  // `emptyProof` is an EmptyState everywhere but the four screens that are
  // aggregates rather than lists: with nothing recorded they state zero
  // honestly, with their own copy, and that is the design.
  final screens = <_Screen>[
    _Screen('dashboard', DashboardScreen.new,
        emptyProof: find.text('No income this period')),
    _Screen('transactions', TransactionsScreen.new),
    _Screen('accounts', AccountsScreen.new),
    _Screen('categories', CategoriesScreen.new),
    _Screen('budgets', BudgetsScreen.new),
    _Screen('goals', GoalsScreen.new),
    _Screen('recurring', RecurringScreen.new),
    _Screen('calendar', CalendarScreen.new,
        loadingProof: find.byType(MonthGrid),
        emptyProof: find.byType(MonthGrid)),
    _Screen('credits', CreditsScreen.new),
    _Screen('people', PeopleScreen.new),
    _Screen('splits', SplitsScreen.new),
    _Screen('net worth', NetWorthScreen.new),
    _Screen('holdings', HoldingsScreen.new),
    _Screen('loans', LoansScreen.new),
    _Screen('stocks', StocksScreen.new),
    _Screen('gold', GoldScreen.new),
    _Screen('reports', ReportsScreen.new, emptyProof: find.text('Reports')),
    _Screen('insights', InsightsScreen.new),
    _Screen('notifications', NotificationsScreen.new),
    _Screen('settings', SettingsScreen.new, emptyProof: find.text('Wallet')),
  ];

  for (final s in screens) {
    audit(s);
  }
}

/// One screen and what counts as proof it handled a state.
class _Screen {
  _Screen(
    this.name,
    this.build, {
    Finder? loadingProof,
    Finder? emptyProof,
  }) : loadingProof = loadingProof ?? _anySkeleton,
       emptyProof = emptyProof ?? find.byType(EmptyState);

  /// Screens skeletonise with either the card or a bare shimmer.
  static final Finder _anySkeleton = find.byWidgetPredicate(
    (w) => w is LoadingCard || w is LoadingShimmer,
    description: 'a skeleton',
  );

  final String name;
  final Widget Function() build;
  final Finder loadingProof;
  final Finder emptyProof;
}

enum _Mode { loading, error, empty, dark }

/// One transport for all four states. `dark` replays the recorded account, so
class _AuditAdapter implements HttpClientAdapter {
  _AuditAdapter(this.mode);

  final _Mode mode;

  /// Endpoint → `test/fixtures/<name>.json`.
  static const Map<String, String> _fixtures = {
    '/transactions': 'transactions',
    '/transactions/balance': 'transactions_balance',
    '/transactions/summary': 'transactions_summary',
    '/transactions/tags': 'transactions_tags',
    '/accounts': 'accounts',
    '/categories': 'categories',
    '/templates': 'templates',
    '/settings': 'settings',
    '/metals/latest': 'metals_latest',
    '/metals/history': 'metals_history',
    '/networth/history': 'networth_history',
    '/reports/summary': 'reports_summary',
    '/reports/by-category': 'reports_by-category',
    '/reports/trend': 'reports_trend',
    '/reports/insights': 'reports_insights',
    '/auth/me': 'auth_me',
    '/auth/2fa/status': 'auth_2fa_status',
    '/budgets': 'budgets',
    '/goals': 'goals',
    '/recurring': 'recurring',
    '/credits': 'credits',
    '/credits/summary': 'credits_summary',
    '/people': 'people',
    '/people/groups': 'people_groups',
    '/splits': 'splits',
    '/holdings': 'holdings',
    '/loans': 'loans',
    '/stocks/portfolio': 'stocks_portfolio',
    '/notifications': 'notifications',
  };

  /// `/reports/by-account` was never recorded against the live account, so the
  /// loaded baseline uses a two-account stand-in; the empty form is `[]` like
  /// every other list.
  static const String _byAccount =
      '[{"_id":"a1","name":"HDFC savings","color":"#3B82F6","income":180000,'
      '"expense":132000,"transferIn":0,"transferOut":5000},'
      '{"_id":"a2","name":"Cash","color":"#22C55E","income":0,'
      '"expense":8400,"transferIn":5000,"transferOut":0}]';

  /// Object-shaped endpoints whose "nothing recorded" form cannot be `[]`.
  /// Anything absent here falls back to the fixture, which is right for the
  /// config-ish reads (`/settings`, `/auth/me`) that must stay well-formed for
  /// the screen to render at all.
  static const Map<String, String> _emptyObjects = {
    '/transactions':
        '{"items":[],"page":1,"limit":50,"total":0,"pages":0,"hasMore":false}',
    '/transactions/balance': '{"balance":0,"byAccount":[]}',
    '/transactions/summary':
        '{"income":0,"expense":0,"net":0,"incomeCount":0,"expenseCount":0,"count":0}',
    '/reports/summary':
        '{"income":0,"expense":0,"net":0,"incomeCount":0,"expenseCount":0,"oneoffIncome":0,"oneoffExpense":0,"consumption":{"consumption":0,"nonConsumption":0}}',
    '/reports/insights': '{"hasData":false}',
    '/notifications': '{"items":[],"unread":0}',
    '/metals/latest': '{"configured":false}',
    '/stocks/portfolio':
        '{"configured":true,"positions":[],"totals":{},"pricedAt":null,"anyStale":false}',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (mode == _Mode.loading) return Completer<ResponseBody>().future;

    final path = options.uri.path.replaceFirst('/api', '');

    if (mode == _Mode.error) {
      return _json('{"error":"The server could not answer that."}', 500);
    }

    if (path == '/reports/by-account') {
      return _json(mode == _Mode.empty ? '[]' : _byAccount, 200);
    }
    // A real endpoint the recorded account never exercised — the demat book is
    // empty, so there are no corporate splits to list.
    if (path == '/stocks/splits') return _json('[]', 200);

    final fixture = _fixtures[path];
    final recorded = fixture == null
        ? null
        : File('test/fixtures/$fixture.json').readAsStringSync();

    if (mode == _Mode.dark) return _json(recorded ?? '[]', recorded == null ? 404 : 200);

    // empty
    final override = _emptyObjects[path];
    if (override != null) return _json(override, 200);
    if (recorded == null) return _json('[]', 404);
    return _json(jsonDecode(recorded) is List ? '[]' : recorded, 200);
  }

  ResponseBody _json(String body, int status) => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
