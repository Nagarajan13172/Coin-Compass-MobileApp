import 'dart:convert';
import 'dart:typed_data';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/features/lock/data/biometric_gate.dart';
import 'package:coincompass/features/lock/data/lock_store.dart';
import 'package:coincompass/features/lock/data/privacy_screen.dart';
import 'package:coincompass/features/lock/domain/lock_state.dart';
import 'package:coincompass/features/lock/domain/pin_verifier.dart';
import 'package:coincompass/features/lock/presentation/lock_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared fakes for the four app-lock test files.
///
/// Not named `*_test.dart` on purpose — `flutter test` would try to run it.
///
/// Everything the app lock touches at unlock time is faked here **except** the
/// hashing, which runs for real (inline, at a low iteration count). Nothing in
/// this file, and nothing any test using it does, can reach the network: the
/// lock has no repository, no Dio and no ApiClient anywhere on its path.

/// Iterations used by every test. Real enough to exercise the loop, cheap
/// enough that a widget test does not stall.
const int kTestIterations = 1000;

/// A scripted [BiometricGate]. Never touches a platform channel.
class FakeBiometricGate extends BiometricGate {
  FakeBiometricGate({
    this.availabilityResult = BiometricAvailability.available,
    this.result = const BiometricResult(BiometricOutcome.success),
  });

  BiometricAvailability availabilityResult;
  BiometricResult result;

  /// When set, [authenticate] parks until it is completed — used to prove the
  /// in-flight guard stops a lifecycle event from re-arming the prompt.
  Future<BiometricResult>? pending;

  int authenticateCalls = 0;
  int cancelCalls = 0;

  @override
  Future<BiometricAvailability> availability() async => availabilityResult;

  @override
  Future<BiometricResult> authenticate(String reason) {
    authenticateCalls++;
    return pending ?? Future<BiometricResult>.value(result);
  }

  @override
  Future<void> cancel() async => cancelCalls++;
}

/// Records the FLAG_SECURE / recents-snapshot toggle instead of invoking the
/// MethodChannel.
class FakePrivacyScreen extends PrivacyScreen {
  FakePrivacyScreen();

  final List<bool> calls = <bool>[];

  bool? get last => calls.isEmpty ? null : calls.last;

  @override
  Future<void> setEnabled(bool enabled) async => calls.add(enabled);
}

/// A clock the test moves by hand. No sleeping, no unbounded pumps.
class FakeClock {
  FakeClock([DateTime? start])
    : _now = start ?? DateTime.utc(2026, 8, 24, 12);

  DateTime _now;

  DateTime call() => _now;

  int get millis => _now.millisecondsSinceEpoch;

  void advance(Duration by) => _now = _now.add(by);

  void rewind(Duration by) => _now = _now.subtract(by);
}

/// Records that the lock's sign-out ran, without going anywhere near
/// `AuthRepository` — `POST /auth/logout` kills the session this project runs
/// on and must never be fired by a test.
class FakeSignOut {
  int calls = 0;

  /// When set, [call] parks until it completes — lets a test look at the
  /// "Signing out…" state instead of racing past it.
  Future<void>? pending;

  Future<void> call() {
    calls++;
    return pending ?? Future<void>.value();
  }
}

/// Prefs seeded as if the owner had already armed the lock with [pin].
///
/// Builds a real salted PBKDF2 verifier so the unlock path under test is the
/// production one, not a stub.
Map<String, Object> seedLockedPrefs({
  String pin = '1234',
  bool biometric = false,
  int? lastActiveAtMs,
  int graceSeconds = LockStore.defaultGraceSeconds,
  int failures = 0,
  int? lockedUntilMs,
}) {
  final salt = Uint8List.fromList(List<int>.generate(16, (i) => i * 7 % 251));
  final verifier = pbkdf2HmacSha256(
    Pbkdf2Request(pin: pin, salt: salt, iterations: kTestIterations),
  );
  return <String, Object>{
    LockStore.keyEnabled: true,
    LockStore.keySalt: base64Encode(salt),
    LockStore.keyVerifier: base64Encode(verifier),
    LockStore.keyIterations: kTestIterations,
    LockStore.keyPinLength: pin.length,
    LockStore.keyBiometric: biometric,
    LockStore.keyGraceSeconds: graceSeconds,
    LockStore.keyFailures: failures,
    LockStore.keyLastActiveAt: ?lastActiveAtMs,
    LockStore.keyLockedUntil: ?lockedUntilMs,
  };
}

/// A container wired for the app lock's widget tests.
///
/// `apiClientProvider` is overridden with a real (never-used) [ApiClient]
/// purely because `authControllerProvider` — which [AppLockGate] watches to
/// stay out of the way on the login screen — constructs an [AuthRepository].
/// No request is ever issued: the fixture never calls `restore`, and
/// [lockSignOutProvider] is faked so `POST /auth/logout` cannot fire.
///
/// The controller is rebuilt here with a low iteration count and
/// `observeLifecycle: false`, so widget tests drive `handleHidden` /
/// `handleResumed` by hand instead of waiting on real lifecycle events.
Future<ProviderContainer> buildLockContainer({
  Map<String, Object> prefs = const {},
  required FakeBiometricGate biometrics,
  required FakePrivacyScreen privacy,
  required FakeClock clock,
  required FakeSignOut signOut,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storedPrefs = await SharedPreferences.getInstance();
  final api = await ApiClient.create();

  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      sharedPreferencesProvider.overrideWithValue(storedPrefs),
      biometricGateProvider.overrideWithValue(biometrics),
      pinHasherProvider.overrideWithValue(const InlinePinHasher()),
      privacyScreenProvider.overrideWithValue(privacy),
      lockClockProvider.overrideWithValue(clock.call),
      lockSignOutProvider.overrideWithValue(signOut.call),
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
}
