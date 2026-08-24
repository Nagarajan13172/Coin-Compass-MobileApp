import 'dart:io';

import 'package:coincompass/core/api/api_exception.dart';
import 'package:coincompass/core/router/app_router.dart';
import 'package:coincompass/core/router/destinations.dart';
import 'package:coincompass/features/auth/data/auth_repository.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:coincompass/features/dashboard/presentation/widgets/net_worth_card.dart';
import 'package:coincompass/features/holdings/presentation/holdings_screen.dart';
import 'package:coincompass/features/networth/presentation/net_worth_screen.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:coincompass/features/settings/domain/app_settings.dart';
import 'package:coincompass/features/stocks/presentation/stocks_screen.dart';
import 'package:coincompass/features/wealth_lock/domain/wealth_lock.dart';
import 'package:coincompass/features/wealth_lock/presentation/wealth_lock_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wealth_lock_fakes.dart';

/// Phase 6.2 — the Net Worth gate's decision logic, its redirect, its nav
/// filtering, and the one thing that must never happen.
///
/// Everything here runs against fakes: a repository fake whose `lockWealth()`
/// fails the test, and a transport fake that fails the test on any of the
/// never-call endpoints. No socket is opened.
void main() {
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_wealth_lock');
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

  // ── which paths are gated ────────────────────────────────────────────────

  group('isWealthGatedPath', () {
    test('gates exactly the web routes, plus holdings', () {
      expect(isWealthGatedPath('/net-worth'), isTrue);
      expect(isWealthGatedPath('/stocks'), isTrue);
      // The web has no /holdings route — it renders holdings inside
      // /net-worth — but it drops the `holdings` query key on every lock, and
      // an open sub-route here would be a hole straight through the gate.
      expect(isWealthGatedPath('/net-worth/holdings'), isTrue);
      expect(isWealthGatedPath(HoldingsScreen.routePath), isTrue);
    });

    test('leaves everything else alone', () {
      for (final path in const [
        '/',
        '/transactions',
        '/accounts',
        '/reports',
        '/insights',
        '/loans',
        '/gold',
        '/settings',
        '/credits/splits',
      ]) {
        expect(isWealthGatedPath(path), isFalse, reason: path);
      }
    });

    test('a query string or a trailing slash is not a way round it', () {
      expect(isWealthGatedPath('/stocks?tab=sales'), isTrue);
      expect(isWealthGatedPath('/net-worth/'), isTrue);
      expect(isWealthGatedPath('/stocks#lots'), isTrue);
      // Sub-paths are gated by construction, so a future screen under
      // /stocks does not depend on someone remembering to add it.
      expect(isWealthGatedPath('/stocks/anything'), isTrue);
    });

    test('a lookalike prefix is not gated', () {
      expect(isWealthGatedPath('/net-worthless'), isFalse);
      expect(isWealthGatedPath('/stocksomething'), isFalse);
      expect(isWealthGatedPath(''), isFalse);
    });
  });

  // ── the predicate, copied from the bundle ────────────────────────────────

  group('wealthVisibilityFor — the web predicate', () {
    test('locked when the flag is on', () {
      expect(
        wealthVisibilityFor(mode: 'user', lockEnabled: true, refreshing: false),
        WealthVisibility.locked,
      );
    });

    test('superadmin bypasses the lock entirely', () {
      // `e.mode === "superadmin" || !e.wealthLockEnabled`
      expect(
        wealthVisibilityFor(
          mode: 'superadmin',
          lockEnabled: true,
          refreshing: false,
        ),
        WealthVisibility.visible,
      );
    });

    test('a locked flag wins over an in-flight refresh', () {
      expect(
        wealthVisibilityFor(mode: 'user', lockEnabled: true, refreshing: true),
        WealthVisibility.locked,
      );
    });

    test('unlocked but refreshing is "checking", never a figure', () {
      expect(
        wealthVisibilityFor(mode: 'user', lockEnabled: false, refreshing: true),
        WealthVisibility.checking,
      );
    });

    test('unlocked and settled is visible', () {
      expect(
        wealthVisibilityFor(
          mode: 'user',
          lockEnabled: false,
          refreshing: false,
        ),
        WealthVisibility.visible,
      );
    });
  });

  // ── the provider ─────────────────────────────────────────────────────────

  group('wealthVisibilityProvider', () {
    ProviderContainer harness(FakeAuthRepository repo) {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          settingsProvider.overrideWith((ref) async => const AppSettings()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is inert while signed out — the shell is not on screen', () async {
      // Not a fail-open: the router sends a signed-out user to /login before
      // any gated surface mounts. Returning `locked` here would fire the gate
      // during the sign-in screen's own build.
      final container = harness(FakeAuthRepository(user: null));
      await container.read(authControllerProvider.notifier).restore();

      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedOut,
      );
      expect(
        container.read(wealthVisibilityProvider),
        WealthVisibility.visible,
      );
    });

    test('locked when the signed-in user carries the flag', () async {
      final container = harness(
        FakeAuthRepository(user: fakeUser(wealthLockEnabled: true)),
      );
      await container.read(authControllerProvider.notifier).restore();

      expect(container.read(wealthVisibilityProvider), WealthVisibility.locked);
    });

    test('superadmin sees it even with the flag on', () async {
      final container = harness(
        FakeAuthRepository(
          user: fakeUser(wealthLockEnabled: true, mode: 'superadmin'),
        ),
      );
      await container.read(authControllerProvider.notifier).restore();

      expect(
        container.read(wealthVisibilityProvider),
        WealthVisibility.visible,
      );
    });

    test(
      'a network failure keeps the last known flag, it does not guess',
      () async {
        final repo = FakeAuthRepository(
          user: fakeUser(wealthLockEnabled: true),
        );
        final container = harness(repo);
        await container.read(authControllerProvider.notifier).restore();
        expect(
          container.read(wealthVisibilityProvider),
          WealthVisibility.locked,
        );

        // The phone goes through a tunnel and the resume re-read fails.
        repo.meError = offlineFailure;
        await container.read(authControllerProvider.notifier).refreshUser();

        // Still locked. Guessing "unlocked" would expose the figures because a
        // request timed out.
        expect(
          container.read(wealthVisibilityProvider),
          WealthVisibility.locked,
        );
        expect(container.read(authControllerProvider).refreshing, isFalse);
      },
    );

    test(
      'a 401 on the resume re-read signs out rather than pretending',
      () async {
        final repo = FakeAuthRepository(user: fakeUser());
        final container = harness(repo);
        await container.read(authControllerProvider.notifier).restore();

        repo.user = null; // AuthRepository.me() turns 401/403 into null
        await container.read(authControllerProvider.notifier).refreshUser();

        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedOut,
        );
      },
    );
  });

  // ── nav filtering ────────────────────────────────────────────────────────

  group('visibleMoreDestinations', () {
    test('removes the two gated rows rather than disabling them', () {
      final locked = visibleMoreDestinations(false);
      final paths = locked.map((d) => d.path).toList();

      expect(paths, isNot(contains('/net-worth')));
      expect(paths, isNot(contains('/stocks')));
      expect(locked.length, moreDestinations.length - 2);
    });

    test('keeps every other destination, in order', () {
      final locked = visibleMoreDestinations(false);
      final expected = moreDestinations
          .where((d) => d.path != '/net-worth' && d.path != '/stocks')
          .map((d) => d.path)
          .toList();
      expect(locked.map((d) => d.path).toList(), expected);
    });

    test('is the full list when unlocked', () {
      expect(visibleMoreDestinations(true), moreDestinations);
    });
  });

  // ── unlocking ────────────────────────────────────────────────────────────

  group('WealthLockController.unlock', () {
    ProviderContainer harness(
      FakeAuthRepository repo, {
      bool wealthLockEnabled = true,
    }) {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          settingsProvider.overrideWith(
            (ref) async => AppSettings(wealthLockEnabled: wealthLockEnabled),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a wrong passcode says so, and stays on the field', () async {
      final repo = FakeAuthRepository(
        user: fakeUser(wealthLockEnabled: true),
        unlockError: wrongPasscodeFailure,
      );
      final container = harness(repo);
      await container.read(authControllerProvider.notifier).restore();

      final ok = await container
          .read(wealthLockControllerProvider.notifier)
          .unlock('nope');

      expect(ok, isFalse);
      expect(repo.unlockAttempts, ['nope']);
      final state = container.read(wealthLockControllerProvider);
      expect(state.phase, WealthUnlockPhase.ready);
      expect(state.error, "That passcode didn't match.");
      // Still locked, and this process has no unlock credit.
      expect(container.read(wealthVisibilityProvider), WealthVisibility.locked);
      expect(container.read(wealthUnlockedHereProvider), isFalse);
    });

    test('a rate limit names who is refusing', () async {
      final repo = FakeAuthRepository(
        user: fakeUser(wealthLockEnabled: true),
        unlockError: ApiException(message: 'slow down', statusCode: 429),
      );
      final container = harness(repo);
      await container.read(authControllerProvider.notifier).restore();

      await container
          .read(wealthLockControllerProvider.notifier)
          .unlock('secret');

      expect(
        container.read(wealthLockControllerProvider).error,
        contains('it is the server refusing new tries, not this app'),
      );
    });

    test('offline shows the offline panel, not a passcode field', () async {
      final repo = FakeAuthRepository(
        user: fakeUser(wealthLockEnabled: true),
        unlockError: offlineFailure,
      );
      final container = harness(repo);
      await container.read(authControllerProvider.notifier).restore();

      await container
          .read(wealthLockControllerProvider.notifier)
          .unlock('secret');

      final state = container.read(wealthLockControllerProvider);
      expect(state.phase, WealthUnlockPhase.offline);
      // No error text: the panel's own copy explains that the passcode is
      // checked by the server, so there is nothing to unlock with offline.
      expect(state.error, isNull);
    });

    test(
      'the preflight goes offline rather than offering a dead field',
      () async {
        final repo = FakeAuthRepository(
          user: fakeUser(wealthLockEnabled: true),
          meError: offlineFailure,
        );
        final container = harness(repo);
        await container.read(authControllerProvider.notifier).restore();

        await container.read(wealthLockControllerProvider.notifier).preflight();

        expect(
          container.read(wealthLockControllerProvider).phase,
          WealthUnlockPhase.offline,
        );
      },
    );

    test('the preflight closes down when the lock is already off', () async {
      final repo = FakeAuthRepository(user: fakeUser());
      final container = harness(repo);
      await container.read(authControllerProvider.notifier).restore();

      await container.read(wealthLockControllerProvider.notifier).preflight();

      expect(
        container.read(wealthLockControllerProvider).phase,
        WealthUnlockPhase.alreadyUnlocked,
      );
    });

    test(
      'success re-gates the app, drops the caches and credits this process',
      () async {
        final repo = FakeAuthRepository(
          user: fakeUser(wealthLockEnabled: true),
        );
        final container = harness(repo);
        await container.read(authControllerProvider.notifier).restore();
        expect(
          container.read(wealthVisibilityProvider),
          WealthVisibility.locked,
        );

        // Something cached from before the transition.
        var settingsBuilds = 0;
        final probe = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(repo),
            settingsProvider.overrideWith((ref) async {
              settingsBuilds++;
              return const AppSettings(wealthLockEnabled: true);
            }),
          ],
        );
        addTearDown(probe.dispose);
        await probe.read(authControllerProvider.notifier).restore();
        await probe.read(settingsProvider.future);
        expect(settingsBuilds, 1);

        final ok = await probe
            .read(wealthLockControllerProvider.notifier)
            .unlock('correct horse');

        expect(ok, isTrue);
        expect(repo.unlockAttempts.last, 'correct horse');
        // The returned user is what re-gates the app — exactly what the web does
        // with `pe.setQueryData(["me"], e)`.
        expect(probe.read(wealthVisibilityProvider), WealthVisibility.visible);
        expect(probe.read(wealthUnlockedHereProvider), isTrue);
        // Settings was dropped, so the Settings row cannot keep offering the
        // buttons that belong to the other state.
        await probe.read(settingsProvider.future);
        expect(settingsBuilds, 2);
      },
    );
  });

  // ── the trap ─────────────────────────────────────────────────────────────

  group('POST /auth/lock-wealth — the stranding trap', () {
    test('is refused outright when no passcode is known to exist', () async {
      // The owner's live state: wealthLockEnabled false, no passcode. The
      // endpoint takes no body, so it would succeed — and could hide Net Worth
      // on both clients with nothing that reopens it.
      final repo = FakeAuthRepository(user: fakeUser());
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          settingsProvider.overrideWith((ref) async => const AppSettings()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).restore();
      await container.read(settingsProvider.future);

      final failure = await container
          .read(wealthLockControllerProvider.notifier)
          .lockNow();

      expect(failure, kNoPasscodeRefusal);
      // Nothing was sent. `FakeAuthRepository.lockWealth` would have failed the
      // test anyway; this asserts the refusal happened before it.
      expect(repo.lockCalls, 0);
      expect(container.read(canRelockProvider), isFalse);
    });

    test(
      'is refused while already locked — there is nothing to lock',
      () async {
        final repo = FakeAuthRepository(
          user: fakeUser(wealthLockEnabled: true),
        );
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(repo),
            settingsProvider.overrideWith(
              (ref) async => const AppSettings(wealthLockEnabled: true),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.notifier).restore();
        await container.read(settingsProvider.future);

        expect(container.read(canRelockProvider), isFalse);
        expect(
          await container.read(wealthLockControllerProvider.notifier).lockNow(),
          kNoPasscodeRefusal,
        );
        expect(repo.lockCalls, 0);
      },
    );

    test(
      'is allowed only when a passcode exists and the figures show',
      () async {
        final repo = FakeAuthRepository(user: fakeUser(), allowLock: true);
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(repo),
            settingsProvider.overrideWith(
              // A passcode exists on the account; this session unlocked it.
              (ref) async => const AppSettings(wealthLockEnabled: true),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.notifier).restore();
        await container.read(settingsProvider.future);

        expect(container.read(canRelockProvider), isTrue);
        expect(
          await container.read(wealthLockControllerProvider.notifier).lockNow(),
          isNull,
        );
        expect(repo.lockCalls, 1);
        expect(
          container.read(wealthVisibilityProvider),
          WealthVisibility.locked,
        );
        expect(container.read(wealthUnlockedHereProvider), isFalse);
      },
    );
  });

  // ── the redirect, and the reads it prevents ──────────────────────────────

  group('the gate, driven through the real router', () {
    testWidgets('a deep link to a gated route is redirected home', (
      tester,
    ) async {
      final adapter = WealthFixtureAdapter(wealthLockEnabled: true);
      final container = await bootWealthApp(tester, adapter: adapter);
      final router = container.read(routerProvider);

      for (final path in const [
        '/net-worth',
        '/stocks',
        '/net-worth/holdings',
      ]) {
        router.go(path);
        await settleWealth(tester);
        expect(
          router.state.matchedLocation,
          '/',
          reason: '$path should have redirected home while locked',
        );
      }

      // And no gated screen was ever built.
      expect(find.byType(NetWorthScreen), findsNothing);
      expect(find.byType(StocksScreen), findsNothing);
      expect(find.byType(HoldingsScreen), findsNothing);
    });

    testWidgets('the same routes open normally when unlocked', (tester) async {
      final adapter = WealthFixtureAdapter();
      final container = await bootWealthApp(tester, adapter: adapter);
      final router = container.read(routerProvider);

      router.go('/net-worth');
      await settleWealth(tester);
      expect(find.byType(NetWorthScreen), findsOneWidget);

      router.go('/stocks');
      await settleWealth(tester);
      expect(find.byType(StocksScreen), findsOneWidget);

      router.go('/net-worth/holdings');
      await settleWealth(tester);
      expect(find.byType(HoldingsScreen), findsOneWidget);
    });

    testWidgets(
      'zero gated GETs while locked — even when the payloads are real',
      (tester) async {
        // Branch one of the server assumption: the lock is only a curtain and
        // the server still answers with the owner's real figures. The app must
        // still not ask, because it would then be holding numbers it is not
        // allowed to paint.
        final adapter = WealthFixtureAdapter(
          wealthLockEnabled: true,
          redactWhileLocked: false,
        );
        final container = await bootWealthApp(tester, adapter: adapter);
        final router = container.read(routerProvider);

        for (final path in const [
          '/net-worth',
          '/stocks',
          '/net-worth/holdings',
          '/',
          '/accounts',
          '/reports',
        ]) {
          router.go(path);
          await settleWealth(tester);
        }

        for (final gated in kGatedReadPaths) {
          expect(
            adapter.countOf(gated),
            0,
            reason: '$gated was requested while the lock was on',
          );
        }
        // The ungated reads still happen — this is a gate, not an outage.
        expect(adapter.countOf('/reports/summary'), greaterThan(0));
        expect(adapter.countOf('/accounts'), greaterThan(0));
      },
    );

    testWidgets(
      'zero gated GETs while locked — and no redacted zero is ever painted',
      (tester) async {
        // Branch two: the server withholds, answering with empty series and a
        // netWorth of 0. `NetWorthCard` falls back to `value = 0` when the
        // history is empty and nothing errored, so without the gate this is
        // exactly the frame that would state "₹0" as the owner's net worth —
        // when the truth is −₹2,00,00,000.
        final adapter = WealthFixtureAdapter(
          wealthLockEnabled: true,
          redactWhileLocked: true,
        );
        await bootWealthApp(tester, adapter: adapter);

        for (final gated in kGatedReadPaths) {
          expect(adapter.countOf(gated), 0, reason: gated);
        }
        // The card is gone entirely — not blanked, not zeroed, not replaced
        // with a "hidden" placeholder that would advertise the lock.
        expect(find.byType(NetWorthCard), findsNothing);
        expect(find.text('Net worth'), findsNothing);
        expect(find.text('Breakdown'), findsNothing);

        // And the gate is not an outage: everything the web keeps visible
        // while locked is still on screen.
        expect(find.text('Income'), findsWidgets);
        expect(find.text('Expense'), findsWidgets);
      },
    );

    testWidgets('unlocked, the dashboard does read and show the figure', (
      tester,
    ) async {
      // Keeps the two assertions above from being vacuous.
      final adapter = WealthFixtureAdapter();
      await bootWealthApp(tester, adapter: adapter);

      expect(adapter.countOf('/networth/history'), greaterThan(0));
      expect(find.text('Net worth'), findsOneWidget);
      expect(find.text('Breakdown'), findsOneWidget);
    });
  });
}
