import 'package:local_auth/local_auth.dart';

import '../domain/lock_state.dart';

/// The only file in `lib/` that imports `package:local_auth`.
///
/// ## The 3.x API is not the 2.x API
///
/// `local_auth` 3.0.0 replaced the `PlatformException` + `AuthenticationOptions`
/// surface with a typed [LocalAuthException] carrying a [LocalAuthExceptionCode],
/// and renamed `stickyAuth` to `persistAcrossBackgrounding`. `useErrorDialogs`
/// is gone with **no replacement** — `LocalAuthentication.authenticate`
/// hard-codes it false — so the OS will never show a "go and enrol a
/// fingerprint" helper. Every not-enrolled / lockout / no-hardware state has to
/// be rendered by our own lock screen or the owner is left staring at a dead
/// button. That is what the mapping below is for.
abstract class BiometricGate {
  const BiometricGate();

  /// Drives Settings copy only. It cannot reliably tell "nothing enrolled" from
  /// "locked out" — several OEMs report `HW_UNAVAILABLE` during a lockout — so
  /// the lock screen takes its wording from [authenticate]'s failure instead.
  Future<BiometricAvailability> availability();

  Future<BiometricResult> authenticate(String reason);

  /// Best-effort cancel of an outstanding prompt.
  Future<void> cancel();
}

class LocalAuthGate extends BiometricGate {
  LocalAuthGate([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricAvailability> availability() async {
    // Each call gets its own try/catch: getAvailableBiometrics() itself throws
    // LocalAuthException(uiUnavailable, 'No Activity available.') when the
    // plugin has no Activity, and a plain MissingPluginException on a test
    // host.
    bool supported;
    try {
      supported = await _auth.isDeviceSupported();
    } on Object {
      return BiometricAvailability.unknown;
    }
    // isDeviceSupported() is `isDeviceSecure() || canAuthenticate(WEAK)` — the
    // only honest answer to "is there any system credential at all".
    if (!supported) return BiometricAvailability.unsupported;

    bool hasHardware;
    try {
      hasHardware = await _auth.canCheckBiometrics;
    } on Object {
      return BiometricAvailability.unknown;
    }
    if (!hasHardware) return BiometricAvailability.noHardware;

    try {
      final enrolled = await _auth.getAvailableBiometrics();
      // On Android this list is only ever [weak]/[strong] — never `fingerprint`
      // or `face`. Never write copy naming a modality from it.
      return enrolled.isEmpty
          ? BiometricAvailability.notEnrolled
          : BiometricAvailability.available;
    } on Object {
      return BiometricAvailability.unknown;
    }
  }

  @override
  Future<BiometricResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // false on purpose. `biometricOnly: true` drops DEVICE_CREDENTIAL from
        // allowedAuthenticators, so a fingerprint lockout would leave the owner
        // with no way in but sign-out. With it false the same system prompt
        // offers "Use PIN" and falls through to the device credential, which
        // also clears a biometric lockout.
        biometricOnly: false,
        // Also false on purpose. When sticky is on, the plugin swallows
        // ERROR_CANCELED on pause and re-arms a brand-new BiometricPrompt on
        // every resume; since the lock controller already owns re-prompting,
        // that produces a double prompt and an outstanding native dialog the
        // Dart state machine cannot reconcile.
        persistAcrossBackgrounding: false,
      );
      return ok
          ? const BiometricResult(BiometricOutcome.success)
          : const BiometricResult(
              BiometricOutcome.failed,
              'Not recognised. Try again or use your PIN.',
            );
    } on LocalAuthException catch (error) {
      return _map(error);
    } on Object {
      // MissingPluginException on a host without the plugin, anything else.
      return const BiometricResult(
        BiometricOutcome.unavailable,
        'Fingerprint unlock is unavailable on this build — use your PIN.',
      );
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _auth.stopAuthentication();
    } on Object {
      // Not supported everywhere, and never worth failing an unlock over.
    }
  }

  /// Never exhaustive on purpose: the enum's own docs say new values are not a
  /// breaking change, so the default branch has to be real.
  static BiometricResult _map(LocalAuthException error) {
    // A switch *expression* with a wildcard, not an exhaustive switch: the
    // enum's own docs say adding values is not a breaking change, so the
    // fallback branch is load-bearing rather than decoration.
    return switch (error.code) {
      // Silent — the PIN keypad is already live behind the dismissed prompt.
      LocalAuthExceptionCode.userCanceled ||
      LocalAuthExceptionCode.systemCanceled ||
      LocalAuthExceptionCode.timeout ||
      LocalAuthExceptionCode.userRequestedFallback ||
      LocalAuthExceptionCode.authInProgress => const BiometricResult(
        BiometricOutcome.canceled,
      ),
      // Two causes, both carrying a description: "No Activity available." and
      // "The current Activity must be a FragmentActivity." The second is what
      // an un-fixed MainActivity produces — a silent typed failure, not the
      // crash you might expect.
      LocalAuthExceptionCode.uiUnavailable => const BiometricResult(
        BiometricOutcome.unavailable,
        'Fingerprint unlock is unavailable on this build — use your PIN.',
      ),
      LocalAuthExceptionCode.noCredentialsSet => const BiometricResult(
        BiometricOutcome.unavailable,
        'This phone has no screen lock, so there is no fingerprint to check — '
            'use your PIN.',
      ),
      LocalAuthExceptionCode.noBiometricsEnrolled => const BiometricResult(
        BiometricOutcome.unavailable,
        'No fingerprint or face is enrolled on this phone — use your PIN.',
      ),
      LocalAuthExceptionCode.noBiometricHardware => const BiometricResult(
        BiometricOutcome.unavailable,
        'This phone has no biometric sensor — use your PIN.',
      ),
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
        const BiometricResult(
          BiometricOutcome.unavailable,
          'The sensor is busy — use your PIN.',
        ),
      LocalAuthExceptionCode.temporaryLockout => const BiometricResult(
        BiometricOutcome.lockedOut,
        'Too many fingerprint attempts. Wait about 30 seconds, or use your PIN.',
      ),
      LocalAuthExceptionCode.biometricLockout => const BiometricResult(
        BiometricOutcome.lockedOut,
        'Fingerprint is locked until the phone is unlocked normally — use your '
            'PIN.',
      ),
      _ => BiometricResult(
        BiometricOutcome.error,
        error.description ?? 'Fingerprint unlock failed — use your PIN.',
      ),
    };
  }
}
