import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:coincompass/features/lock/data/lock_store.dart';
import 'package:coincompass/features/lock/domain/lock_state.dart';
import 'package:coincompass/features/lock/domain/pin_verifier.dart';
import 'package:coincompass/features/lock/presentation/app_lock_setup_sheet.dart';
import 'package:coincompass/features/lock/presentation/lock_controller.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:coincompass/features/settings/domain/app_settings.dart';
import 'package:coincompass/features/settings/presentation/security_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lock_fakes.dart';

/// The Settings wiring, and the honesty of what it says.
///
/// The settings document is a **fake** — `settingsProvider` is overridden with
/// a value and `/auth/2fa/status` with a canned one — and the transport under
/// the ApiClient is an adapter that *fails the test* if anything tries to make
/// a request. So this proves, structurally, that arming and disarming the app
/// lock issues no HTTP at all: not `POST /settings/pin`, not
/// `POST /settings/pin/verify`, nothing. The owner's `pinEnabled` and
/// `wealthLockEnabled` cannot be touched by this feature, in either direction.
void main() {
  const Size phone = Size(360, 800);
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_lock_settings');
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

  late FakeClock clock;
  late FakeBiometricGate biometrics;
  late FakePrivacyScreen privacy;
  late FakeSignOut signOut;

  setUp(() {
    clock = FakeClock();
    biometrics = FakeBiometricGate(
      availabilityResult: BiometricAvailability.notEnrolled,
    );
    privacy = FakePrivacyScreen();
    signOut = FakeSignOut();
  });

  Future<ProviderContainer> pumpCard(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    AppSettings settings = const AppSettings(),
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(prefs);
      final storedPrefs = await SharedPreferences.getInstance();
      final api = await ApiClient.create();
      // A real ApiClient, because `authControllerProvider` builds an
      // AuthRepository — with a transport that fails the test rather than
      // reaching the owner's live account.
      api.dio.httpClientAdapter = _NoNetwork();

      container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          sharedPreferencesProvider.overrideWithValue(storedPrefs),
          biometricGateProvider.overrideWithValue(biometrics),
          pinHasherProvider.overrideWithValue(const InlinePinHasher()),
          privacyScreenProvider.overrideWithValue(privacy),
          lockClockProvider.overrideWithValue(clock.call),
          lockSignOutProvider.overrideWithValue(signOut.call),
          settingsProvider.overrideWith((ref) async => settings),
          twoFactorStatusProvider.overrideWith(
            (ref) async => const TwoFactorStatus(),
          ),
          appLockControllerProvider.overrideWith(
            (ref) => AppLockController(
              store: ref.watch(lockStoreProvider),
              biometrics: ref.watch(biometricGateProvider),
              hasher: ref.watch(pinHasherProvider),
              privacy: ref.watch(privacyScreenProvider),
              onSignOut: ref.watch(lockSignOutProvider),
              now: ref.watch(lockClockProvider),
              iterations: kTestIterations,
              observeLifecycle: false,
            ),
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
    await tester.pump(const Duration(milliseconds: 60));
    return container;
  }

  // ── copy ──────────────────────────────────────────────────────────────────

  testWidgets('the security copy is true on this device now', (tester) async {
    await pumpCard(tester);

    // The three sentences Phase 5 wrote because the claim they replaced was
    // false. They are false themselves now, and must be gone.
    expect(find.textContaining('This app does not lock yet'), findsNothing);
    expect(find.textContaining('does not ask for it yet'), findsNothing);
    expect(
      find.textContaining('A 4–8 digit PIN is asked for on the web'),
      findsNothing,
    );

    // What is true instead.
    expect(find.text('App lock (this phone)'), findsOneWidget);
    expect(
      find.textContaining('Checked on the device, so it works offline'),
      findsOneWidget,
    );
    expect(find.text('PIN lock (web)'), findsOneWidget);
    expect(
      find.textContaining('when you open CoinCompass in a browser'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'The app lock covers this phone. The PIN and Net Worth locks cover',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the Net Worth lock copy is left honest, because 6.2 has not shipped',
    (tester) async {
      // The app lock does NOT gate Net Worth or Stocks behind their own
      // passcode. Rewriting this row to imply otherwise would recreate exactly
      // the honesty problem this phase was supposed to end.
      await pumpCard(
        tester,
        settings: const AppSettings(wealthLockEnabled: true),
      );

      expect(
        find.textContaining('This app does not lock them yet'),
        findsOneWidget,
      );
    },
  );

  testWidgets('lays out at 360dp in dark mode', (tester) async {
    await pumpCard(
      tester,
      prefs: seedLockedPrefs(lastActiveAtMs: 0),
      settings: const AppSettings(pinEnabled: true, wealthLockEnabled: true),
      dark: true,
    );
    expect(tester.takeException(), isNull);
  });

  // ── the guard ─────────────────────────────────────────────────────────────

  testWidgets(
    'settings.pinEnabled arriving true NEVER arms the app lock',
    (tester) async {
      final container = await pumpCard(
        tester,
        settings: const AppSettings(pinEnabled: true, wealthLockEnabled: true),
      );

      // The server says the *web* PIN is on. The phone's lock stays off, and
      // its row still offers to set one up.
      expect(container.read(appLockControllerProvider).enabled, isFalse);
      expect(find.text('Set up app lock'), findsOneWidget);
      expect(find.text('Off'), findsWidgets);
    },
  );

  // ── arming ────────────────────────────────────────────────────────────────

  testWidgets('setting up the app lock arms it, with zero HTTP', (
    tester,
  ) async {
    final container = await pumpCard(tester);

    await tester.tap(find.text('Set up app lock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AppLockSetupSheet), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(AppLockSetupSheet),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));

    // Mismatched pair is refused locally.
    await tester.enterText(fields.first, '2468');
    await tester.enterText(fields.at(1), '8642');
    await tester.pump();
    await tester.tap(find.text('Turn on app lock'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("The two PINs don't match."), findsOneWidget);
    expect(container.read(appLockControllerProvider).enabled, isFalse);

    // A matching pair arms it — on the device, and only on the device.
    await tester.enterText(fields.at(1), '2468');
    await tester.pump();
    await tester.tap(find.text('Turn on app lock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final lock = container.read(appLockControllerProvider);
    expect(lock.enabled, isTrue);
    expect(lock.pinLength, 4);
    // It does not slam shut on the owner who just typed it twice.
    expect(lock.phase, LockPhase.unlocked);
    // The recents-snapshot suppression goes on with it.
    expect(privacy.last, isTrue);

    final store = LockStore(await SharedPreferences.getInstance());
    expect(store.enabled, isTrue);
    expect(store.hasCredential, isTrue);
    expect(
      await container
          .read(appLockControllerProvider.notifier)
          .verifyPinLocally('2468'),
      isTrue,
    );
  });

  // ── disarming ─────────────────────────────────────────────────────────────

  testWidgets('turning the app lock off demands the current PIN first', (
    tester,
  ) async {
    // A lock anyone holding the unlocked phone can switch off from Settings is
    // not a lock.
    final container = await pumpCard(
      tester,
      prefs: seedLockedPrefs(lastActiveAtMs: clock.millis),
    );
    expect(container.read(appLockControllerProvider).enabled, isTrue);

    await tester.tap(find.text('Turn off'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Turn off the app lock?'), findsOneWidget);
    final field = find
        .descendant(
          of: find.byType(AppLockConfirmSheet),
          matching: find.byType(TextField),
        )
        .first;

    await tester.enterText(field, '0000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('That PIN is not right.'), findsOneWidget);
    expect(container.read(appLockControllerProvider).enabled, isTrue);

    await tester.enterText(field, '1234');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(appLockControllerProvider).enabled, isFalse);
    expect(privacy.last, isFalse);
    final store = LockStore(await SharedPreferences.getInstance());
    expect(store.hasCredential, isFalse);

    // Let the SnackBar's dismissal timer expire so nothing is pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('"Lock now" closes the lock from Settings', (tester) async {
    final container = await pumpCard(
      tester,
      prefs: seedLockedPrefs(lastActiveAtMs: clock.millis),
    );
    expect(container.read(appLockControllerProvider).phase, LockPhase.unlocked);

    await tester.tap(find.text('Lock now'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(appLockControllerProvider).phase, LockPhase.locked);
  });

  testWidgets('no fingerprint enrolled means no fingerprint switch', (
    tester,
  ) async {
    await pumpCard(tester, prefs: seedLockedPrefs(lastActiveAtMs: 0));
    expect(find.text('Unlock with fingerprint'), findsNothing);
  });

  testWidgets('an enrolled fingerprint gets a switch that arms the fast path', (
    tester,
  ) async {
    biometrics.availabilityResult = BiometricAvailability.available;
    final container = await pumpCard(
      tester,
      prefs: seedLockedPrefs(lastActiveAtMs: 0),
    );
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('Unlock with fingerprint'), findsOneWidget);
    expect(container.read(appLockControllerProvider).biometricEnabled, isFalse);

    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(appLockControllerProvider).biometricEnabled, isTrue);
  });
}

/// Any request at all is a bug in this feature: the app lock has no repository.
class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fail('the app lock made an HTTP request: ${options.method} ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}
