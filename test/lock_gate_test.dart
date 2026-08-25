import 'dart:io';

import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:coincompass/features/lock/domain/lock_state.dart';
import 'package:coincompass/features/lock/presentation/app_lock_gate.dart';
import 'package:coincompass/features/lock/presentation/lock_controller.dart';
import 'package:coincompass/features/lock/presentation/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coincompass/l10n/app_localizations.dart';

import 'lock_fakes.dart';

/// [AppLockGate] — the leak proofs.
///
/// The feature exists to stop a frame of the owner's net worth reaching a
/// screen or a task-switcher card, so these assert on the widget tree rather
/// than on copy: on a cold start the app's content must not be in the tree at
/// all, and on a warm lock it must be present but covered, frozen and hidden
/// from a screen reader.
///
/// Every pump uses an explicit duration. There is no bare `pump()` loop and no
/// `pumpAndSettle` anywhere in this file.
void main() {
  const Size phone = Size(360, 800);
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_lock_gate');
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
    // Off unless a test asks for it, so the gate tests are about the gate.
    biometrics = FakeBiometricGate(
      availabilityResult: BiometricAvailability.notEnrolled,
    );
    privacy = FakePrivacyScreen();
    signOut = FakeSignOut();
    _DashboardProbe.builds = 0;
  });

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await buildLockContainer(
        prefs: prefs,
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
          // Exactly the wiring main.dart uses.
          builder: (context, child) => AppLockGate(child: child),
          home: const _DashboardProbe(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    return container;
  }

  // ── the lock is off ───────────────────────────────────────────────────────

  testWidgets('with the lock off the gate is a pure pass-through', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.byType(_DashboardProbe), findsOneWidget);
    expect(find.text('₹12,34,567'), findsOneWidget);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(LockShield), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ── cold start ────────────────────────────────────────────────────────────

  testWidgets(
    'a locked cold start never builds the app behind it — not one frame',
    (tester) async {
      await pumpApp(tester, prefs: seedLockedPrefs());

      expect(find.byType(LockScreen), findsOneWidget);
      // The strongest form of the claim: the content widget is not in the tree
      // at all, so no screen mounted, no provider fired a GET, and there is no
      // pixel of net worth to leak.
      expect(find.byType(_DashboardProbe), findsNothing);
      expect(_DashboardProbe.builds, 0);
      expect(find.text('₹12,34,567'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the lock fills the screen and is opaque', (tester) async {
    await pumpApp(tester, prefs: seedLockedPrefs());

    expect(tester.getRect(find.byType(LockScreen)), Offset.zero & phone);
    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(LockScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.backgroundColor, isNotNull);
    expect(scaffold.backgroundColor!.a, 1.0, reason: 'must not be see-through');
  });

  testWidgets('a locked cold start is opaque in dark mode too', (tester) async {
    await pumpApp(tester, prefs: seedLockedPrefs(), dark: true);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(_DashboardProbe), findsNothing);
    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(LockScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.backgroundColor!.a, 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlocking hands the app over', (tester) async {
    final container = await pumpApp(tester, prefs: seedLockedPrefs());
    expect(find.byType(_DashboardProbe), findsNothing);

    await container
        .read(appLockControllerProvider.notifier)
        .unlockWithPin('1234');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(_DashboardProbe), findsOneWidget);
    expect(find.text('₹12,34,567'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── warm lock ─────────────────────────────────────────────────────────────

  testWidgets(
    'a warm lock keeps the app mounted but covered, frozen and silent',
    (tester) async {
      final container = await pumpApp(
        tester,
        prefs: seedLockedPrefs(lastActiveAtMs: clock.millis),
      );
      // Within the grace window: the app is up.
      expect(find.byType(_DashboardProbe), findsOneWidget);

      container.read(appLockControllerProvider.notifier).lockNow();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(LockScreen), findsOneWidget);
      // Still mounted — a half-typed form survives being locked…
      expect(find.byType(_DashboardProbe), findsOneWidget);
      // …but covered by a full-bleed opaque lock…
      expect(tester.getRect(find.byType(LockScreen)), Offset.zero & phone);
      // …frozen (one of the enclosing TickerModes is switched off; the other
      // is MaterialApp's own)…
      expect(
        tester
            .widgetList<TickerMode>(
              find.ancestor(
                of: find.byType(_DashboardProbe),
                matching: find.byType(TickerMode),
              ),
            )
            .any((mode) => !mode.enabled),
        isTrue,
      );
      // …and invisible to TalkBack, which matters as much as the paint.
      expect(
        find.ancestor(
          of: find.byType(_DashboardProbe),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byType(_DashboardProbe),
          matching: find.byType(ExcludeFocus),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backgrounding raises a shield with no controls on it', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      prefs: seedLockedPrefs(lastActiveAtMs: clock.millis),
    );
    final controller = container.read(appLockControllerProvider.notifier);

    controller.handleInactive();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(appLockControllerProvider).phase,
      LockPhase.shielded,
    );
    expect(find.byType(LockShield), findsOneWidget);
    // No keypad, no buttons, nothing readable — and not the full lock screen
    // either, because no decision has been made yet.
    expect(find.byType(LockScreen), findsNothing);
    expect(find.text('₹12,34,567'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(_DashboardProbe),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short trip away drops the shield without a prompt', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      prefs: seedLockedPrefs(lastActiveAtMs: clock.millis),
    );
    final controller = container.read(appLockControllerProvider.notifier);

    controller.handleHidden();
    clock.advance(const Duration(seconds: 6));
    controller.handleResumed();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(LockShield), findsNothing);
    expect(find.byType(_DashboardProbe), findsOneWidget);
  });

  testWidgets('ten minutes on a desk comes back to the lock screen', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      prefs: seedLockedPrefs(lastActiveAtMs: clock.millis),
    );
    final controller = container.read(appLockControllerProvider.notifier);

    controller.handleHidden();
    clock.advance(const Duration(minutes: 10));
    controller.handleResumed();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LockScreen), findsOneWidget);
    expect(tester.getRect(find.byType(LockScreen)), Offset.zero & phone);
    expect(tester.takeException(), isNull);
  });

  // ── the gate stays out of the way ─────────────────────────────────────────

  testWidgets('a signed-out session is never gated', (tester) async {
    // Nothing to hide behind a login form, and it keeps the offline cold start
    // sane: AuthController.restore() resolves to signedOut when the network is
    // gone.
    final container = await pumpApp(tester, prefs: seedLockedPrefs());
    expect(find.byType(LockScreen), findsOneWidget);

    container.read(authControllerProvider.notifier).state = const AuthState(
      status: AuthStatus.signedOut,
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(_DashboardProbe), findsOneWidget);
  });

  testWidgets('an armed lock with no verifier fails open, not shut', (
    tester,
  ) async {
    await pumpApp(tester, prefs: const {'applock.enabled': true});

    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(_DashboardProbe), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Stands in for the router subtree. Counts its own builds so a test can claim
/// "never built", not just "not found".
class _DashboardProbe extends StatelessWidget {
  const _DashboardProbe();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return const Scaffold(body: Center(child: Text('₹12,34,567')));
  }
}
