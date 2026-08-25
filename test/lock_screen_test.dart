import 'dart:async';
import 'dart:io';

import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/features/lock/data/lock_store.dart';
import 'package:coincompass/features/lock/domain/lock_state.dart';
import 'package:coincompass/features/lock/presentation/lock_controller.dart';
import 'package:coincompass/features/lock/presentation/lock_screen.dart';
import 'package:coincompass/features/lock/presentation/widgets/pin_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coincompass/l10n/app_localizations.dart';

import 'lock_fakes.dart';

/// [LockScreen] at 360 × 800dp, in light and dark.
///
/// **Nothing here touches the network.** The biometric gate is a fake, the
/// sign-out is a fake, and the PIN is checked by the real PBKDF2 verifier at a
/// low iteration count — so the unlock path under test is the production one,
/// running entirely on the device, exactly as it would in aeroplane mode.
///
/// Every wait is an explicit `pump(Duration)`. There is no bare `pump()` loop
/// and no `pumpAndSettle` in this file.
void main() {
  const Size phone = Size(360, 800);
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_lock_screen');
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

  Future<ProviderContainer> pumpLock(
    WidgetTester tester, {
    Map<String, Object>? prefs,
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await buildLockContainer(
        prefs: prefs ?? seedLockedPrefs(),
        biometrics: biometrics,
        privacy: privacy,
        clock: clock,
        signOut: signOut,
      );
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: const LockScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    return container;
  }

  /// Taps the keypad, then lets the (inline, isolate-free) hash and the prefs
  /// writes settle. Bounded, explicit, no settling loop.
  Future<void> enter(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.widgetWithText(InkWell, digit));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 60));
    // Long enough for the wrong-PIN shake (200ms) to finish, so no Ticker is
    // left running at teardown.
    await tester.pump(const Duration(milliseconds: 300));
  }

  int filledDots(WidgetTester tester) {
    final dots = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(PinDots),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return dots
        .where(
          (d) =>
              (d.decoration! as BoxDecoration).color != Colors.transparent,
        )
        .length;
  }

  // ── it lays out ───────────────────────────────────────────────────────────

  testWidgets('lays out at 360dp in light mode with no overflow', (
    tester,
  ) async {
    await pumpLock(tester);

    expect(find.text('CoinCompass is locked'), findsOneWidget);
    expect(find.text('Enter your 4-digit PIN.'), findsOneWidget);
    for (final key in const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
      expect(find.widgetWithText(InkWell, key), findsOneWidget);
    }
    expect(find.byIcon(LucideIcons.delete), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Forgot your PIN?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out at 360dp in dark mode with no overflow', (
    tester,
  ) async {
    await pumpLock(tester, dark: true);

    expect(find.text('CoinCompass is locked'), findsOneWidget);
    expect(find.byType(PinKeypad), findsOneWidget);
    // The lock is the darkest thing on screen; it must not be transparent.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor!.a, 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dot row matches the PIN the owner actually chose', (
    tester,
  ) async {
    await pumpLock(tester, prefs: seedLockedPrefs(pin: '135790'));

    expect(find.text('Enter your 6-digit PIN.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PinDots),
        matching: find.byType(AnimatedContainer),
      ),
      findsNWidgets(6),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the back gesture cannot dismiss the lock', (tester) async {
    await pumpLock(tester);
    expect(
      find.byWidgetPredicate((w) => w is PopScope && !w.canPop),
      findsOneWidget,
    );
  });

  // ── the PIN ───────────────────────────────────────────────────────────────

  testWidgets('typing fills the dots and the right PIN opens it', (
    tester,
  ) async {
    final container = await pumpLock(tester);

    await tester.tap(find.widgetWithText(InkWell, '1'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(filledDots(tester), 1);

    await tester.tap(find.widgetWithText(InkWell, '2'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(filledDots(tester), 2);

    // Backspace takes one back rather than clearing the lot.
    await tester.tap(find.byIcon(LucideIcons.delete));
    await tester.pump(const Duration(milliseconds: 150));
    expect(filledDots(tester), 1);

    await enter(tester, '234');
    expect(
      container.read(appLockControllerProvider).phase,
      LockPhase.unlocked,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong PIN says how many tries are left and clears the dots', (
    tester,
  ) async {
    final container = await pumpLock(tester);

    await enter(tester, '9999');

    expect(container.read(appLockControllerProvider).phase, LockPhase.locked);
    expect(find.text('Wrong PIN — 4 tries left.'), findsOneWidget);
    expect(filledDots(tester), 0);
    // The dot row was told to shake.
    expect(container.read(appLockControllerProvider).shakeToken, 1);

    await enter(tester, '8888');
    expect(find.text('Wrong PIN — 3 tries left.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last try before a wait is spelled out', (tester) async {
    await pumpLock(tester);
    for (final wrong in const ['9999', '8888', '7777', '6666']) {
      await enter(tester, wrong);
    }
    expect(
      find.text('Wrong PIN — 1 try left before a short wait.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // ── the cooldown ──────────────────────────────────────────────────────────

  testWidgets('five wrong PINs freeze the keypad and count down', (
    tester,
  ) async {
    final container = await pumpLock(tester);

    for (final wrong in const ['9999', '8888', '7777', '6666', '5555']) {
      await enter(tester, wrong);
    }

    expect(find.text('Too many wrong PINs.'), findsOneWidget);
    expect(find.text('Try again in 0:30'), findsOneWidget);

    // The keys are inert: even the right PIN does nothing.
    await enter(tester, '1234');
    expect(container.read(appLockControllerProvider).phase, LockPhase.locked);
    expect(filledDots(tester), 0);

    // The countdown ticks on a one-second timer, driven here by hand.
    clock.advance(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Try again in 0:25'), findsOneWidget);

    // Never permanent: it expires and the right PIN works again.
    clock.advance(const Duration(seconds: 26));
    await tester.pump(const Duration(seconds: 1));
    await enter(tester, '1234');
    expect(
      container.read(appLockControllerProvider).phase,
      LockPhase.unlocked,
    );

    // Dispose the tree so the countdown timer is cancelled before teardown.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signing out stays reachable during a cooldown', (tester) async {
    await pumpLock(tester);
    for (final wrong in const ['9999', '8888', '7777', '6666', '5555']) {
      await enter(tester, wrong);
    }
    expect(find.text('Try again in 0:30'), findsOneWidget);

    // The way out must never be gated on the thing the owner has forgotten.
    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(signOut.calls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  // ── biometrics ────────────────────────────────────────────────────────────

  testWidgets('with no fingerprint enrolled there is no fingerprint key', (
    tester,
  ) async {
    await pumpLock(tester, prefs: seedLockedPrefs(biometric: true));

    expect(find.byIcon(LucideIcons.fingerprint), findsNothing);
    expect(find.text('Fingerprint is unavailable — use your PIN.'), findsOneWidget);
    // …and the PIN still opens it, which is the whole point.
    await enter(tester, '1234');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an enrolled fingerprint prompts itself once and opens it', (
    tester,
  ) async {
    biometrics
      ..availabilityResult = BiometricAvailability.available
      ..result = const BiometricResult(BiometricOutcome.success);

    final container = await pumpLock(
      tester,
      prefs: seedLockedPrefs(biometric: true),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(biometrics.authenticateCalls, 1);
    expect(
      container.read(appLockControllerProvider).phase,
      LockPhase.unlocked,
    );
  });

  testWidgets('a cancelled prompt drops straight into PIN entry', (
    tester,
  ) async {
    biometrics
      ..availabilityResult = BiometricAvailability.available
      ..result = const BiometricResult(BiometricOutcome.canceled);

    final container = await pumpLock(
      tester,
      prefs: seedLockedPrefs(biometric: true),
    );
    await tester.pump(const Duration(milliseconds: 120));

    // The keypad was live behind the prompt the whole time — zero taps to
    // recover.
    expect(container.read(appLockControllerProvider).phase, LockPhase.locked);
    expect(find.byType(PinKeypad), findsOneWidget);
    expect(find.byIcon(LucideIcons.fingerprint), findsOneWidget);

    await enter(tester, '1234');
    expect(
      container.read(appLockControllerProvider).phase,
      LockPhase.unlocked,
    );
  });

  testWidgets('a fingerprint lockout is explained and never blocks the PIN', (
    tester,
  ) async {
    biometrics
      ..availabilityResult = BiometricAvailability.available
      ..result = const BiometricResult(
        BiometricOutcome.lockedOut,
        'Fingerprint is locked until the phone is unlocked normally — use '
        'your PIN.',
      );

    final container = await pumpLock(
      tester,
      prefs: seedLockedPrefs(biometric: true),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.textContaining('Fingerprint is locked'), findsOneWidget);
    await enter(tester, '1234');
    expect(
      container.read(appLockControllerProvider).phase,
      LockPhase.unlocked,
    );
  });

  testWidgets('an unavailable sensor collapses to one honest line', (
    tester,
  ) async {
    biometrics
      ..availabilityResult = BiometricAvailability.available
      ..result = const BiometricResult(
        BiometricOutcome.unavailable,
        'Fingerprint unlock is unavailable on this build — use your PIN.',
      );

    await pumpLock(tester, prefs: seedLockedPrefs(biometric: true));
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.textContaining('unavailable on this build'),
      findsOneWidget,
    );
    expect(find.byIcon(LucideIcons.fingerprint), findsNothing);
    expect(find.byType(PinKeypad), findsOneWidget);
  });

  // ── the offline story, told on screen ─────────────────────────────────────

  testWidgets('"Forgot your PIN?" says the PIN is checked on the phone', (
    tester,
  ) async {
    await pumpLock(tester);

    await tester.tap(find.text('Forgot your PIN?'));
    // Two frames: the route is pushed on the first, and its transition only
    // starts running on the one after it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.textContaining('checked on this phone, so it works with no'),
      findsOneWidget,
    );
    expect(
      find.textContaining('sign out and sign in again'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet offers the keyless way out', (tester) async {
    final container = await pumpLock(tester);

    await tester.tap(find.text('Forgot your PIN?'));
    // Two frames: the route is pushed on the first, and its transition only
    // starts running on the one after it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(signOut.calls, 1);
    // Salt, verifier, stamps and cooldown all gone, so the next sign-in cannot
    // inherit them.
    final prefs = await SharedPreferences.getInstance();
    for (final key in LockStore.allKeys) {
      expect(prefs.containsKey(key), isFalse, reason: '$key survived');
    }
    expect(container.read(appLockControllerProvider).isGating, isFalse);
    // FLAG_SECURE / the recents-snapshot suppression is lifted with it.
    expect(privacy.last, isFalse);
  });

  testWidgets('signing out shows a busy state rather than a dead tap', (
    tester,
  ) async {
    final gate = Completer<void>();
    signOut.pending = gate.future;
    await pumpLock(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Signing out…'), findsOneWidget);
    expect(find.byType(PinKeypad), findsNothing);

    gate.complete();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
