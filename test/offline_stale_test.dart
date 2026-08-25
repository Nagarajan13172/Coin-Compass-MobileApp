import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/api/response_cache.dart';
import 'package:coincompass/core/api/retry_policy.dart';
import 'package:coincompass/core/api/stale_ledger.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/core/widgets/app_scaffold.dart';
import 'package:coincompass/core/widgets/error_retry.dart';
import 'package:coincompass/core/widgets/stale_banner.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:coincompass/features/loans/data/loans_repository.dart';
import 'package:coincompass/features/loans/presentation/loans_screen.dart';
import 'package:coincompass/features/wealth_lock/domain/wealth_lock.dart';
import 'package:coincompass/features/wealth_lock/presentation/wealth_lock_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coincompass/l10n/app_localizations.dart';

/// Phase 6.3 — the honesty surface, end to end.
///
/// The one thing 6.3 has to prove: a screen served from disk shows the owner's
/// real figures **and says when they were saved**, instead of a retry button —
/// and it never claims they are live.
///
/// Nothing here opens a socket. `_Adapter` replaces Dio's transport and refuses
/// every never-call endpoint outright.
void main() {
  late Directory root;
  var seq = 0;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = Directory.systemTemp.createTempSync('cc_offline_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => root.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  ResponseCache freshCache() {
    final dir = Directory('${root.path}/case${seq++}')
      ..createSync(recursive: true);
    return ResponseCache(directory: () async => dir);
  }

  /// Bounded on purpose — this codebase does not allow an unbounded pump.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pump();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. THE BANNER ITSELF
  // ───────────────────────────────────────────────────────────────────────────

  group('StaleBanner', () {
    Future<ProviderContainer> pumpBanner(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
            theme: AppTheme.light(),
            home: const Scaffold(body: StaleBanner()),
          ),
        ),
      );
      return container;
    }

    testWidgets('says nothing at all while everything is live', (tester) async {
      await pumpBanner(tester);
      expect(find.textContaining('Offline'), findsNothing);
    });

    testWidgets('states WHEN, not just that it is old', (tester) async {
      final container = await pumpBanner(tester);
      container
          .read(staleLedgerProvider.notifier)
          .recordServed(
            'k1',
            StaleTag.loans,
            DateTime.now().subtract(const Duration(minutes: 14)),
          );
      await tester.pump();

      expect(find.textContaining('saved 14m ago'), findsOneWidget);
      expect(find.textContaining('Not live'), findsOneWidget);
    });

    testWidgets('names the OLDEST stamp, never the newest', (tester) async {
      // Understating freshness is safe. Overstating it is the lie.
      final container = await pumpBanner(tester);
      final ledger = container.read(staleLedgerProvider.notifier)
        ..recordServed(
          'old',
          StaleTag.loans,
          DateTime.now().subtract(const Duration(hours: 3)),
        )
        ..recordServed(
          'new',
          StaleTag.goals,
          DateTime.now().subtract(const Duration(minutes: 1)),
        );
      await tester.pump();

      expect(find.textContaining('saved 3h ago'), findsOneWidget);
      expect(find.textContaining('1m ago'), findsNothing);

      // And it follows the ledger down.
      ledger.recordLive('old');
      await tester.pump();
      expect(find.textContaining('saved 1m ago'), findsOneWidget);
    });

    testWidgets('vanishes the moment a live read gets through', (tester) async {
      final container = await pumpBanner(tester);
      final ledger = container.read(staleLedgerProvider.notifier)
        ..recordServed(
          'k1',
          StaleTag.loans,
          DateTime.now().subtract(const Duration(minutes: 5)),
        );
      await tester.pump();
      expect(find.textContaining('Offline'), findsOneWidget);

      ledger.recordLive('k1');
      await tester.pump();
      expect(
        find.textContaining('Offline'),
        findsNothing,
        reason: 'not a sticky "you were offline once" flag',
      );
    });

    testWidgets('a future stamp reads "just now", never "-3m ago"', (
      tester,
    ) async {
      // A backwards clock jump must not make the honesty surface print
      // nonsense — the class of bug 6.1's review caught on the lock cooldown.
      final container = await pumpBanner(tester);
      container
          .read(staleLedgerProvider.notifier)
          .recordServed(
            'k1',
            StaleTag.loans,
            DateTime.now().add(const Duration(minutes: 3)),
          );
      await tester.pump();

      expect(find.textContaining('saved just now'), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
    });
  });

  group('StaleStamp', () {
    testWidgets('marks only its own area', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
            theme: AppTheme.light(),
            home: const Scaffold(
              body: Column(
                children: [
                  StaleStamp(StaleTag.loans),
                  StaleStamp(StaleTag.goals),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Saved'), findsNothing);

      container
          .read(staleLedgerProvider.notifier)
          .recordServed(
            'k1',
            StaleTag.loans,
            DateTime.now().subtract(const Duration(hours: 2)),
          );
      await tester.pump();

      expect(find.text('Saved 2h ago'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. A REAL SCREEN, SERVED FROM DISK
  // ───────────────────────────────────────────────────────────────────────────

  group('a screen served from cache', () {
    testWidgets(
      'shows the owner\'s real figures plus the banner, NOT ErrorRetry',
      (tester) async {
        tester.view
          ..physicalSize = const Size(360, 800)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final adapter = _Adapter();
        final cache = freshCache();
        late ProviderContainer container;

        await tester.runAsync(() async {
          final api = await ApiClient.create(
            cache: cache,
            // Nothing sleeps: the schedule is covered by retry_policy_test.
            retry: RetryPolicy(attempts: 0),
          );
          api.dio.httpClientAdapter = adapter;
          final prefs = await SharedPreferences.getInstance();
          container = ProviderContainer(
            overrides: [
              apiClientProvider.overrideWithValue(api),
              sharedPreferencesProvider.overrideWithValue(prefs),
            ],
          );
          // What main() keeps alive from the app root.
          container
            ..listen(wealthCacheScopeProvider, (_, _) {})
            ..listen<void>(cacheEventBridgeProvider, (_, _) {});
          await container.read(authControllerProvider.notifier).restore();
        });
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: L.localizationsDelegates,
              home: const AppScaffold(
                location: '/loans',
                child: LoansScreen(),
              ),
            ),
          ),
        );
        await settle(tester);

        // Online first: the real ₹2,00,00,000 home loan, and no banner.
        expect(find.text('Deena'), findsOneWidget);
        expect(find.textContaining('Offline'), findsNothing);
        expect(find.byType(ErrorRetry), findsNothing);

        // Now the train goes into the tunnel.
        adapter.offline = true;
        container.invalidate(loansFetchProvider);
        await settle(tester);

        expect(
          find.text('Deena'),
          findsOneWidget,
          reason: 'the owner sees their real recent figures',
        );
        expect(
          find.byType(ErrorRetry),
          findsNothing,
          reason: 'the wall of retry buttons is what 6.3 exists to remove',
        );
        expect(
          find.textContaining(kStaleBannerPrefix.trim()),
          findsOneWidget,
          reason: 'and it says so, with when it was fetched',
        );
        expect(find.textContaining('Not live.'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        // Back above ground: the banner goes away by itself.
        adapter.offline = false;
        container.invalidate(loansFetchProvider);
        await settle(tester);

        expect(find.text('Deena'), findsOneWidget);
        expect(find.textContaining('Offline'), findsNothing);
      },
    );

    testWidgets('with nothing cached it still shows ErrorRetry', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(360, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final adapter = _Adapter()..offline = true;
      late ProviderContainer container;

      await tester.runAsync(() async {
        final api = await ApiClient.create(
          cache: freshCache(),
          retry: RetryPolicy(attempts: 0),
        );
        api.dio.httpClientAdapter = adapter;
        final prefs = await SharedPreferences.getInstance();
        container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
        );
      });
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: L.localizationsDelegates,
            home: const AppScaffold(location: '/loans', child: LoansScreen()),
          ),
        ),
      );
      await settle(tester);

      // Nothing was ever saved, so there is nothing honest to show.
      expect(find.byType(ErrorRetry), findsOneWidget);
      expect(find.textContaining(kStaleBannerPrefix.trim()), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. COLD START OFFLINE — the part the cache alone does not fix
  // ───────────────────────────────────────────────────────────────────────────

  group('cold start with no connection', () {
    Future<ProviderContainer> boot(_Adapter adapter) async {
      final api = await ApiClient.create(
        cache: freshCache(),
        retry: RetryPolicy(attempts: 0),
      );
      api.dio.httpClientAdapter = adapter;
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).restore();
      return container;
    }

    test('keeps the session, marked unverified, and invents no user', () async {
      final container = await boot(_Adapter()..offline = true);
      final auth = container.read(authControllerProvider);

      expect(auth.status, AuthStatus.signedIn);
      expect(auth.unverifiedSession, isTrue);
      expect(auth.user, isNull, reason: 'it must invent no user');
      expect(
        auth.isSignedIn,
        isTrue,
        reason: 'so the shell mounts and the cache is reachable',
      );
      expect(container.read(currentUserProvider), isNull);
    });

    test('and Net Worth is gated by code that already existed', () async {
      final container = await boot(_Adapter()..offline = true);
      final visibility = container.read(wealthVisibilityProvider);

      expect(
        visibility,
        WealthVisibility.locked,
        reason:
            'signed-in-with-null-user already resolves to locked: if we are '
            'claiming a session but cannot say whose, we do not paint their '
            'net worth',
      );
      expect(wealthReadAllowed(visibility), isFalse);
      expect(wealthFiguresVisible(visibility), isFalse);
      // And the cache refuses wealth-sensitive bodies in both directions.
      expect(
        container.read(wealthCacheScopeProvider),
        CacheWealthScope.unknown,
      );
    });

    test('a 500 also keeps the session — the server is unreachable', () async {
      final container = await boot(_Adapter()..status = 500);
      expect(container.read(authControllerProvider).unverifiedSession, isTrue);
    });

    test('but a genuine 401 still signs out', () async {
      final container = await boot(_Adapter()..status = 401);
      final auth = container.read(authControllerProvider);

      expect(auth.status, AuthStatus.signedOut);
      expect(auth.unverifiedSession, isFalse);
      expect(auth.isSignedIn, isFalse);
    });

    test('a 403 still signs out', () async {
      final container = await boot(_Adapter()..status = 403);
      expect(container.read(authControllerProvider).isSignedIn, isFalse);
    });

    test('a successful me() clears the flag', () async {
      final adapter = _Adapter()..offline = true;
      final container = await boot(adapter);
      expect(container.read(authControllerProvider).unverifiedSession, isTrue);

      adapter.offline = false;
      await container.read(authControllerProvider.notifier).refreshUser();

      final auth = container.read(authControllerProvider);
      expect(auth.unverifiedSession, isFalse);
      expect(auth.user, isNotNull);
    });

    testWidgets('the shell says the session is unconfirmed', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late ProviderContainer container;
      await tester.runAsync(() async {
        container = await boot(_Adapter()..offline = true);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: L.localizationsDelegates,
            home: const AppScaffold(
              location: '/loans',
              child: SizedBox.shrink(),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(
        find.textContaining("haven't been able to confirm your session"),
        findsOneWidget,
      );
      // The avatar falls back rather than showing a name nobody confirmed.
      expect(find.text('·'), findsOneWidget);
    });
  });
}

/// A fixture-backed transport that can be switched offline.
///
/// **Fails the test on any never-call endpoint**, the same guarantee
/// `wealth_lock_fakes.dart` gives.
class _Adapter implements HttpClientAdapter {
  bool offline = false;
  int status = 200;
  final List<String> calls = <String>[];

  static const List<String> _forbidden = [
    '/auth/lock-wealth',
    '/auth/unlock-wealth',
    '/auth/logout',
    '/settings/pin',
    '/settings/pin/verify',
    '/settings/wealth-passcode',
    '/notifications/read-all',
    '/reports/email-now',
  ];

  static const Map<String, String> _fixtures = {
    '/loans': 'loans',
    '/notifications': 'notifications',
    '/settings': 'settings',
    '/accounts': 'accounts',
    '/transactions': 'transactions',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    calls.add('${options.method} $path');

    if (_forbidden.contains(path)) {
      fail('A test reached $path, which is on the never-call list.');
    }
    if (options.method != 'GET') {
      fail('A test issued a ${options.method} — 6.3 has no write path.');
    }

    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }

    if (status != 200) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'nope'}),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (path == '/auth/me') {
      return _json(
        jsonEncode({
          'user': {
            'id': '6a4669f861d974fd74ab427a',
            'email': 'haridiablo72@gmail.com',
            'name': 'Hari',
            'mode': 'user',
            'wealthLockEnabled': false,
          },
        }),
      );
    }

    final fixture = _fixtures[path];
    if (fixture != null) {
      return _json(File('test/fixtures/$fixture.json').readAsStringSync());
    }
    return _json('[]');
  }

  static ResponseBody _json(String body) => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
