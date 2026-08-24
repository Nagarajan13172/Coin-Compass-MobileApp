import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/router/app_router.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/core/widgets/more_sheet.dart';
import 'package:coincompass/features/accounts/presentation/accounts_screen.dart';
import 'package:coincompass/features/auth/data/auth_repository.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:coincompass/features/dashboard/presentation/dashboard_screen.dart';
import 'package:coincompass/features/dashboard/presentation/widgets/net_worth_card.dart';
import 'package:coincompass/features/holdings/presentation/holdings_screen.dart';
import 'package:coincompass/features/lock/domain/lock_state.dart';
import 'package:coincompass/features/lock/domain/pin_verifier.dart';
import 'package:coincompass/features/lock/presentation/lock_controller.dart';
import 'package:coincompass/features/networth/presentation/net_worth_screen.dart';
import 'package:coincompass/features/notifications/domain/app_notification.dart';
import 'package:coincompass/features/notifications/presentation/notifications_screen.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:coincompass/features/settings/domain/app_settings.dart';
import 'package:coincompass/features/settings/presentation/security_card.dart';
import 'package:coincompass/features/stocks/presentation/stocks_screen.dart';
import 'package:coincompass/features/wealth_lock/domain/wealth_lock.dart';
import 'package:coincompass/features/wealth_lock/presentation/wealth_gate.dart';
import 'package:coincompass/features/wealth_lock/presentation/wealth_lock_providers.dart';
import 'package:coincompass/features/wealth_lock/presentation/wealth_unlock_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lock_fakes.dart';
import 'wealth_lock_fakes.dart';

/// Phase 6.2 — what the Net Worth gate looks like, at 360 × 800dp, in both
/// themes.
///
/// Every pump here is bounded. Nothing reaches the network: the whole-app tests
/// run on [WealthFixtureAdapter], and the sheet tests run on
/// [FakeAuthRepository], whose `lockWealth()` fails the test if anything
/// touches it.
void main() {
  const Size phone = Size(360, 800);
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_wealth_gate');
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

  /// Two accounts, because the owner really has none — and the totals card the
  /// gate removes only renders when there is at least one.
  const String twoAccounts =
      '[{"_id":"a1","name":"Salary","type":"bank","balance":42000,'
      '"includeInTotal":true,"currency":"INR"},'
      '{"_id":"a2","name":"Card","type":"card","balance":-8000,'
      '"includeInTotal":true,"currency":"INR"}]';

  /// Mounts one widget with the gate forced into [visibility], with no auth,
  /// no router and no transport at all.
  Future<void> mountGated(
    WidgetTester tester,
    Widget child, {
    required WealthVisibility visibility,
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [wealthVisibilityProvider.overrideWithValue(visibility)],
        child: MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }

  // ── the dashboard card ───────────────────────────────────────────────────

  for (final dark in const [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('locked: the dashboard hides the net-worth card ($theme)', (
      tester,
    ) async {
      final adapter = WealthFixtureAdapter(wealthLockEnabled: true);
      await bootWealthApp(tester, adapter: adapter, dark: dark);

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(NetWorthCard), findsNothing);
      expect(find.text('Net worth'), findsNothing);
      expect(find.text('Breakdown'), findsNothing);
      expect(find.textContaining('minus what you owe'), findsNothing);
      // Everything the web keeps is still there.
      expect(find.text('Income'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unlocked: the dashboard shows it again ($theme)', (
      tester,
    ) async {
      await bootWealthApp(tester, adapter: WealthFixtureAdapter(), dark: dark);

      expect(find.byType(NetWorthCard), findsOneWidget);
      expect(find.text('Net worth'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the net-worth caption describes the figure it sits under', (
    tester,
  ) async {
    // Found on the owner's phone during the 6.10 device pass, on these exact
    // numbers: the fixture is their real snapshot — `accountsTotal: 0`,
    // `assets: 0`, `liabilities: 20000000`, `netWorth: -20000000`, and zero
    // accounts. The card used to print
    //
    //     −₹2,00,00,000
    //     Sum of 0 accounts
    //
    // which is false: the sum of no accounts is ₹0. Every rupee of that figure
    // is the loan. The label was wrong with accounts too — any holding, stock
    // or loan made it a lie — it was just less obvious.
    await bootWealthApp(tester, adapter: WealthFixtureAdapter());

    expect(find.byType(NetWorthCard), findsOneWidget);
    expect(find.textContaining('−₹2,00,00,000'), findsWidgets);

    // The claim that broke, in the shape it broke in.
    expect(
      find.textContaining('Sum of'),
      findsNothing,
      reason: 'net worth is assets MINUS liabilities, never a sum of accounts',
    );
    expect(find.text('Everything you own, minus what you owe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── the accounts totals card ─────────────────────────────────────────────

  testWidgets('locked: Accounts keeps its rows and loses its totals card', (
    tester,
  ) async {
    final adapter = WealthFixtureAdapter(
      wealthLockEnabled: true,
      overrides: const {'/accounts': twoAccounts},
    );
    final container = await bootWealthApp(tester, adapter: adapter);
    container.read(routerProvider).go('/accounts');
    await settleWealth(tester);

    expect(find.byType(AccountsScreen), findsOneWidget);
    // The per-account rows stay: they are sums of numbers already on screen,
    // and the web keeps its own equivalent cards too.
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    // The gradient totals card goes.
    expect(find.text('Total balance'), findsNothing);
    expect(find.text('Assets'), findsNothing);
    expect(find.text('Liabilities'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlocked: Accounts shows its totals card', (tester) async {
    final adapter = WealthFixtureAdapter(
      overrides: const {'/accounts': twoAccounts},
    );
    final container = await bootWealthApp(tester, adapter: adapter);
    container.read(routerProvider).go('/accounts');
    await settleWealth(tester);

    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Liabilities'), findsOneWidget);
  });

  // ── the "More" sheet ─────────────────────────────────────────────────────

  testWidgets('locked: the More sheet drops two rows and gains an unlock', (
    tester,
  ) async {
    await bootWealthApp(
      tester,
      adapter: WealthFixtureAdapter(wealthLockEnabled: true),
    );

    await tester.tap(find.text('More'));
    await settleWealth(tester);

    final sheet = find.byType(MoreSheet);
    expect(sheet, findsOneWidget);
    // The list is taller than the sheet's 78%-of-screen cap, and the unlock
    // row is appended at the end.
    await tester.scrollUntilVisible(
      find.descendant(of: sheet, matching: find.text('Unlock Net Worth')),
      120,
      scrollable: find
          .descendant(of: sheet, matching: find.byType(Scrollable))
          .first,
    );
    await settleWealth(tester);
    expect(
      find.descendant(of: sheet, matching: find.text('Net Worth')),
      findsNothing,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Stocks')),
      findsNothing,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Unlock Net Worth')),
      findsOneWidget,
    );
    // The rest of the nav is untouched.
    expect(
      find.descendant(of: sheet, matching: find.text('Loans')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlocked: the More sheet has both rows and no unlock', (
    tester,
  ) async {
    await bootWealthApp(tester, adapter: WealthFixtureAdapter());

    await tester.tap(find.text('More'));
    await settleWealth(tester);

    final sheet = find.byType(MoreSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('Net Worth')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Unlock Net Worth')),
      findsNothing,
    );
  });

  // ── the gated screens themselves ─────────────────────────────────────────

  group('a gated screen never paints a figure', () {
    for (final entry in <String, Widget>{
      'Net Worth': const NetWorthScreen(),
      'Stocks': const StocksScreen(),
      'Holdings': const HoldingsScreen(),
    }.entries) {
      testWidgets('${entry.key} — locked', (tester) async {
        await mountGated(
          tester,
          WealthGate(builder: (_) => entry.value),
          visibility: WealthVisibility.locked,
        );

        expect(find.byType(WealthLockedPanel), findsOneWidget);
        expect(find.text('Net Worth is locked.'), findsOneWidget);
        expect(find.text('Unlock'), findsOneWidget);
        // Nothing behind the panel was built, so nothing could have painted a
        // figure or fired a request.
        expect(find.textContaining('₹'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${entry.key} — checking', (tester) async {
        // Same wrapper the router mounts: `WealthGate` with the screen-shaped
        // checking placeholder.
        await mountGated(
          tester,
          WealthGate(
            checking: const WealthCheckingScreen(),
            builder: (_) => entry.value,
          ),
          visibility: WealthVisibility.checking,
        );

        // A placeholder, never a value — not even a zero.
        expect(find.textContaining('₹'), findsNothing);
        expect(find.byType(WealthLockedPanel), findsNothing);
        expect(
          find.text('Checking whether Net Worth is unlocked…'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the locked panel says the lock is on the account', (
      tester,
    ) async {
      await mountGated(
        tester,
        WealthGate(builder: (_) => const NetWorthScreen()),
        visibility: WealthVisibility.locked,
        dark: true,
      );

      expect(
        // Unlocking is PER SIGN-IN — /auth/unlock-wealth elevates this
        // session, it does not clear the account flag. This assertion used to
        // pin the opposite claim in place.
        find.textContaining('unlocks them in this app only'),
        findsOneWidget,
      );
    });
  });

  // ── the unlock sheet ─────────────────────────────────────────────────────

  group('the unlock sheet', () {
    Future<ProviderContainer> openSheet(
      WidgetTester tester,
      FakeAuthRepository repo, {
      bool dark = false,
    }) async {
      tester.view
        ..physicalSize = phone
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => unlockWealthFlow(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return container;
    }

    testWidgets('offline says so instead of offering a passcode field', (
      tester,
    ) async {
      await openSheet(
        tester,
        FakeAuthRepository(
          user: fakeUser(wealthLockEnabled: true),
          meError: offlineFailure,
        ),
      );

      expect(find.text('No connection'), findsOneWidget);
      expect(
        find.textContaining('cannot be unlocked while this phone is offline'),
        findsOneWidget,
      );
      // The field must not be there: it could not possibly work.
      expect(find.text('Wealth passcode'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong passcode keeps the field and says what happened', (
      tester,
    ) async {
      final repo = FakeAuthRepository(
        user: fakeUser(wealthLockEnabled: true),
        unlockError: wrongPasscodeFailure,
      );
      await openSheet(tester, repo);

      expect(find.text('Wealth passcode'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'wrong');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text("That passcode didn't match."), findsOneWidget);
      expect(find.text('Wealth passcode'), findsOneWidget);
      expect(repo.unlockAttempts, ['wrong']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rejection clears as soon as the owner types again', (
      tester,
    ) async {
      // Found on the owner's phone during the 6.2 device pass: the red
      // "didn't match" line stayed up the entire time they were typing the
      // replacement, so the sheet was showing an error about a passcode that
      // no longer existed in the field. `clearError()` had been on the
      // controller since 6.2 was written, with no caller.
      final repo = FakeAuthRepository(
        user: fakeUser(wealthLockEnabled: true),
        unlockError: wrongPasscodeFailure,
      );
      await openSheet(tester, repo);

      await tester.enterText(find.byType(TextField).first, 'wrong');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("That passcode didn't match."), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'w');
      await tester.pump();

      expect(find.text("That passcode didn't match."), findsNothing);
      // Clearing the message must not have sent anything.
      expect(repo.unlockAttempts, ['wrong']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sheet says unlocking also unlocks the browser', (
      tester,
    ) async {
      await openSheet(
        tester,
        FakeAuthRepository(user: fakeUser(wealthLockEnabled: true)),
        dark: true,
      );

      expect(
        find.textContaining('Anywhere else you are signed in stays as it is'),
        findsOneWidget,
      );
      expect(
        find.textContaining('unlocking needs a connection'),
        findsOneWidget,
      );
    });

    testWidgets('success closes the sheet and re-gates the app', (
      tester,
    ) async {
      final repo = FakeAuthRepository(user: fakeUser(wealthLockEnabled: true));
      final container = await openSheet(tester, repo);
      expect(container.read(wealthVisibilityProvider), WealthVisibility.locked);

      await tester.enterText(find.byType(TextField).first, 'correct horse');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Wealth passcode'), findsNothing);
      expect(
        container.read(wealthVisibilityProvider),
        WealthVisibility.visible,
      );
      expect(container.read(wealthUnlockedHereProvider), isTrue);
      expect(
        find.textContaining('unlocked in this app until you lock it again'),
        findsOneWidget,
      );
    });

    testWidgets('an already-open lock is said plainly, not asked about', (
      tester,
    ) async {
      await openSheet(tester, FakeAuthRepository(user: fakeUser()));

      expect(
        find.text('Net Worth is already unlocked. Nothing to enter.'),
        findsOneWidget,
      );
      expect(find.text('Wealth passcode'), findsNothing);
    });
  });

  // ── Settings ─────────────────────────────────────────────────────────────

  group('the Settings row', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required WealthVisibility visibility,
      required bool passcodeOnAccount,
      bool dark = false,
    }) async {
      tester.view
        ..physicalSize = phone
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final settings = AppSettings(wealthLockEnabled: passcodeOnAccount);

      late ProviderContainer container;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(const <String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final api = await ApiClient.create();
        // Fails the test on anything it is asked for — the Security card must
        // not issue a request just by being rendered.
        api.dio.httpClientAdapter = WealthFixtureAdapter();

        container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            sharedPreferencesProvider.overrideWithValue(prefs),
            // The app-lock half of the card, faked so nothing touches a
            // platform channel. It is not what this group is about.
            biometricGateProvider.overrideWithValue(
              FakeBiometricGate(
                availabilityResult: BiometricAvailability.notEnrolled,
              ),
            ),
            pinHasherProvider.overrideWithValue(const InlinePinHasher()),
            privacyScreenProvider.overrideWithValue(FakePrivacyScreen()),
            appLockControllerProvider.overrideWith(
              (ref) => AppLockController(
                store: ref.watch(lockStoreProvider),
                biometrics: ref.watch(biometricGateProvider),
                hasher: ref.watch(pinHasherProvider),
                privacy: ref.watch(privacyScreenProvider),
                onSignOut: ref.watch(lockSignOutProvider),
                iterations: kTestIterations,
                observeLifecycle: false,
              ),
            ),
            wealthVisibilityProvider.overrideWithValue(visibility),
            settingsProvider.overrideWith((ref) async => settings),
            twoFactorStatusProvider.overrideWith(
              (ref) async => const TwoFactorStatus(),
            ),
          ],
        );
      });
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SettingsSecurityCard(settings: settings),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }

    testWidgets('locked offers Unlock and nothing else', (tester) async {
      await pumpCard(
        tester,
        visibility: WealthVisibility.locked,
        passcodeOnAccount: true,
      );

      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      // Holding the unlocked phone must not be enough to discard a passcode
      // you do not know.
      expect(find.text('Turn off'), findsNothing);
      expect(find.text('Change passcode'), findsNothing);
      expect(find.text('Lock now'), findsNothing);
    });

    testWidgets('unlocked with a passcode offers all three', (tester) async {
      await pumpCard(
        tester,
        visibility: WealthVisibility.visible,
        passcodeOnAccount: true,
      );

      expect(find.text('Unlocked'), findsOneWidget);
      expect(find.text('Change passcode'), findsOneWidget);
      expect(find.text('Lock now'), findsOneWidget);
      expect(find.text('Turn off'), findsOneWidget);
    });

    testWidgets('no passcode offers only "Set a passcode" — the trap', (
      tester,
    ) async {
      // The owner's live state. `POST /auth/lock-wealth` takes no body and
      // would succeed here, so the control that could send it must not exist.
      await pumpCard(
        tester,
        visibility: WealthVisibility.visible,
        passcodeOnAccount: false,
        dark: true,
      );

      expect(find.text('Off'), findsWidgets);
      expect(find.text('Set a passcode'), findsOneWidget);
      expect(find.text('Lock now'), findsNothing);
      expect(find.text('Unlock'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the obsolete 6.1 sentence is gone', (tester) async {
      await pumpCard(
        tester,
        visibility: WealthVisibility.locked,
        passcodeOnAccount: true,
      );

      expect(
        find.textContaining('This app does not lock them yet'),
        findsNothing,
      );
      // The scope claim, corrected. `/auth/unlock-wealth` elevates the CURRENT
      // SESSION — the web's own menu offers "Hide" only when
      // `wealthLockEnabled && mode == 'superadmin'`, a pair impossible if
      // unlocking cleared the account flag. So a browser is unaffected.
      expect(
        find.textContaining(
          'Unlocking here unlocks them in this app only',
        ),
        findsOneWidget,
      );
      // Narrow, not blanket: the web PIN row legitimately says "in a browser",
      // because that lock really does cover one. What must never reappear is a
      // claim that the WEALTH lock reaches across clients.
      for (final falseClaim in const [
        'also unlocks CoinCompass in a browser',
        'in this app and in a browser',
        'hidden in a browser too',
        'showing in a browser too',
        'hidden everywhere you are signed in',
      ]) {
        expect(
          find.textContaining(falseClaim),
          findsNothing,
          reason:
              'the wealth lock is per sign-in — "$falseClaim" promises '
              'protection the app cannot deliver',
        );
      }
    });
  });

  // ── notifications ────────────────────────────────────────────────────────

  group('a notification pointing at a gated route', () {
    test('resolves to nothing while locked, and to the route when not', () {
      expect(notificationRoute('/net-worth', wealthVisible: false), isNull);
      expect(notificationRoute('/stocks', wealthVisible: false), isNull);
      expect(notificationRoute('/holdings', wealthVisible: false), isNull);
      // Everything else is unaffected.
      expect(
        notificationRoute('/recurring', wealthVisible: false),
        '/recurring',
      );
      expect(
        notificationRoute('/net-worth', wealthVisible: true),
        '/net-worth',
      );
    });

    testWidgets('the row stops promising a screen it cannot open', (
      tester,
    ) async {
      const notification = AppNotification(
        id: 'n1',
        type: 'networth.updated',
        link: '/net-worth',
      );

      await mountGated(
        tester,
        const NotificationRow(
          notification: notification,
          onOpen: _noop,
          onDismiss: _noop,
        ),
        visibility: WealthVisibility.locked,
      );
      expect(find.text('Net Worth'), findsNothing);

      await mountGated(
        tester,
        const NotificationRow(
          notification: notification,
          onOpen: _noop,
          onDismiss: _noop,
        ),
        visibility: WealthVisibility.visible,
      );
      expect(find.text('Net Worth'), findsOneWidget);
    });
  });
}

void _noop() {
  group('scope claims stay honest', () {
    test('no shipped string claims the wealth lock reaches another client', () {
      // A regression net over the SOURCE, not a rendered tree — the earlier
      // copy was wrong in four files at once, and three review lenses only
      // caught it because one of them re-read the bundle. `/auth/unlock-wealth`
      // elevates the CURRENT SESSION; it does not clear the account flag, so
      // unlocking here changes nothing in a browser.
      const banned = [
        'also unlocks CoinCompass in a browser',
        'in this app and in a browser',
        'hidden in a browser too',
        'showing in a browser too',
        'hidden everywhere you are signed in',
        'not on this phone, so unlocking here',
      ];
      const sources = [
        'lib/features/wealth_lock/presentation/wealth_gate.dart',
        'lib/features/wealth_lock/presentation/wealth_unlock_sheet.dart',
        'lib/features/settings/presentation/security_card.dart',
        'lib/features/settings/presentation/security_sheets.dart',
      ];

      for (final path in sources) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        for (final claim in banned) {
          expect(
            source.contains(claim),
            isFalse,
            reason:
                '$path contains "$claim" — the wealth lock is per sign-in, so '
                'that promises protection the app cannot deliver.',
          );
        }
      }
    });
  });
}
