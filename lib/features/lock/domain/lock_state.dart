/// The app lock's state machine, as pure Dart.
///
/// No Flutter imports on purpose: the grace-window and cooldown rules are the
/// part most worth unit-testing, and they should not need a widget binding.
library;

/// What the lock is currently doing to the app underneath it.
enum LockPhase {
  /// The app is usable. The gate is a pass-through.
  unlocked,

  /// An opaque cover is up but no decision has been made yet — raised at
  /// `inactive`/`hidden` so Android's task snapshot and the notification
  /// shade never catch a frame of the dashboard. Resolves to [unlocked] or
  /// [locked] on the next resume.
  shielded,

  /// The lock screen owns the app.
  locked,
}

/// What the device can do about biometrics *right now*.
///
/// Derived from the capability probe, which cannot tell "not enrolled" from
/// "locked out" on every OEM — so this drives Settings copy only. The lock
/// screen takes its wording from the authenticate() failure instead, which is
/// specific.
enum BiometricAvailability {
  /// Not probed yet, or the probe itself failed.
  unknown,

  /// Hardware present and something is enrolled.
  available,

  /// Hardware present, nothing usable enrolled.
  notEnrolled,

  /// No biometric sensor at all.
  noHardware,

  /// The device has neither a biometric nor a screen lock, so there is no
  /// system credential to authenticate against.
  unsupported,
}

/// The outcome of one `authenticate()` call, flattened from
/// `LocalAuthExceptionCode` into the handful of things the UI does differently.
enum BiometricOutcome {
  success,

  /// The sensor read a finger and rejected it. The prompt stays up; the plugin
  /// only returns here once the prompt is done.
  failed,

  /// User dismissed it, the system cancelled it, or it timed out. Silent — the
  /// PIN keypad is already behind the prompt.
  canceled,

  /// No sensor, nothing enrolled, no Activity, sensor busy. Collapse the
  /// fingerprint affordance and say why once.
  unavailable,

  /// Too many bad reads. Temporary (~30s) or until a device credential is
  /// used. Never blocks the app's own PIN.
  lockedOut,

  /// Anything else, including future enum values.
  error,
}

/// [BiometricOutcome] plus a line the lock screen can show verbatim.
class BiometricResult {
  const BiometricResult(this.outcome, [this.message]);

  final BiometricOutcome outcome;
  final String? message;

  bool get isSuccess => outcome == BiometricOutcome.success;
}

/// Immutable snapshot the gate, the lock screen and the Settings row all read.
class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.phase = LockPhase.unlocked,
    this.pinLength = 4,
    this.biometricEnabled = false,
    this.biometricAvailability = BiometricAvailability.unknown,
    this.failures = 0,
    this.lockedUntilMs,
    this.verifying = false,
    this.signingOut = false,
    this.message,
    this.shakeToken = 0,
    this.failedOpen = false,
  });

  /// The owner turned the lock on. Written by exactly one code path — the
  /// setup sheet's confirm — and never by anything the server says.
  final bool enabled;

  final LockPhase phase;

  /// 4–8. Sizes the dot row and decides when entry auto-submits.
  final int pinLength;

  /// The owner opted into the fingerprint fast path.
  final bool biometricEnabled;

  final BiometricAvailability biometricAvailability;

  /// Consecutive wrong PINs, persisted so force-stopping does not reset it.
  final int failures;

  /// Wall-clock instant the keypad becomes usable again, or null.
  final int? lockedUntilMs;

  /// PBKDF2 is running. The keypad is frozen so a second submit is impossible.
  final bool verifying;

  final bool signingOut;

  /// The one line under the dots: "Wrong PIN — 3 tries left", a biometric
  /// failure, or null.
  final String? message;

  /// Bumped on every wrong PIN so the dot row can replay its shake without the
  /// screen holding animation state of its own.
  final int shakeToken;

  /// The lock disabled itself because the stored verifier was missing or
  /// unreadable. Settings shows a one-time banner. See
  /// [AppLockState] docs on LockStore for why this fails open.
  final bool failedOpen;

  /// True when the gate must cover the app.
  bool get isGating => enabled && phase != LockPhase.unlocked;

  bool get biometricOffered =>
      biometricEnabled && biometricAvailability == BiometricAvailability.available;

  /// Milliseconds left on the cooldown at [nowMs], or 0.
  /// The longest a cooldown may ever be, in ms. `cooldownForFailures` caps the
  /// duration it *grants*, but the value persisted is an absolute instant — so
  /// a device clock that jumps backwards (a timezone fix, NTP correction, a
  /// manual change) leaves `lockedUntilMs` arbitrarily far in the future and
  /// the keypad refuses the correct PIN for as long as the skew lasts. Clamping
  /// the remaining time to the maximum grant makes the wait self-healing: the
  /// worst case is one full cooldown, never an open-ended lockout.
  static const int maxCooldownMs = 300 * 1000;

  int cooldownRemainingMs(int nowMs) {
    final until = lockedUntilMs;
    if (until == null) return 0;
    final left = until - nowMs;
    if (left <= 0) return 0;
    return left > maxCooldownMs ? maxCooldownMs : left;
  }

  bool isCoolingDown(int nowMs) => cooldownRemainingMs(nowMs) > 0;

  AppLockState copyWith({
    bool? enabled,
    LockPhase? phase,
    int? pinLength,
    bool? biometricEnabled,
    BiometricAvailability? biometricAvailability,
    int? failures,
    int? lockedUntilMs,
    bool clearLockedUntil = false,
    bool? verifying,
    bool? signingOut,
    String? message,
    bool clearMessage = false,
    int? shakeToken,
    bool? failedOpen,
  }) {
    return AppLockState(
      enabled: enabled ?? this.enabled,
      phase: phase ?? this.phase,
      pinLength: pinLength ?? this.pinLength,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricAvailability:
          biometricAvailability ?? this.biometricAvailability,
      failures: failures ?? this.failures,
      lockedUntilMs: clearLockedUntil ? null : (lockedUntilMs ?? this.lockedUntilMs),
      verifying: verifying ?? this.verifying,
      signingOut: signingOut ?? this.signingOut,
      message: clearMessage ? null : (message ?? this.message),
      shakeToken: shakeToken ?? this.shakeToken,
      failedOpen: failedOpen ?? this.failedOpen,
    );
  }
}

/// The escalation ladder for wrong PINs: five strikes buys 30s, the next five
/// 60s, every five after that 300s. Never a wipe, never a permanent lockout —
/// this is a privacy curtain and the owner must always be able to wait it out.
///
/// Returns the cooldown to apply at [failures] consecutive wrong entries, or
/// null when the keypad should stay live.
Duration? cooldownForFailures(int failures) {
  if (failures <= 0 || failures % 5 != 0) return null;
  final tier = failures ~/ 5;
  return switch (tier) {
    1 => const Duration(seconds: 30),
    2 => const Duration(seconds: 60),
    _ => const Duration(seconds: 300),
  };
}

/// Tries left before the next cooldown, given [failures] so far.
int triesBeforeCooldown(int failures) => 5 - (failures % 5);
