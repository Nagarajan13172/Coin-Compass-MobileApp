import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/pin_verifier.dart';

/// Everything the app lock persists, under one `applock.` namespace.
///
/// Reads are **synchronous**. That is the whole reason this exists as a class
/// rather than a set of `await prefs.getBool` calls: `main()` already awaits
/// `SharedPreferences.getInstance()` before `runApp`, so the very first frame
/// can decide whether to paint the lock with no async gap for a dashboard frame
/// to slip through.
///
/// Nothing here is a secret store. `flutter_secure_storage` was removed from
/// this project earlier (it demanded compileSdk 37), and it would not change
/// the threat model anyway: the `mt_session` cookie already sits unencrypted in
/// `PersistCookieJar`'s files next door, and reads the whole account without
/// the PIN. What is stored is a salted PBKDF2 verifier, never the PIN.
class LockStore {
  LockStore(this._prefs);

  final SharedPreferences _prefs;

  static const String keyEnabled = 'applock.enabled';
  static const String keySalt = 'applock.salt';
  static const String keyVerifier = 'applock.verifier';
  static const String keyIterations = 'applock.iterations';
  static const String keyPinLength = 'applock.pinLength';
  static const String keyBiometric = 'applock.biometric';
  static const String keyLastActiveAt = 'applock.lastActiveAtMs';
  static const String keyGraceSeconds = 'applock.graceSeconds';
  static const String keyFailures = 'applock.failures';
  static const String keyLockedUntil = 'applock.lockedUntilMs';

  /// Every key this store owns. `clear()` wipes exactly these and nothing else
  /// — the theme and locale live in the same prefs file.
  static const List<String> allKeys = [
    keyEnabled,
    keySalt,
    keyVerifier,
    keyIterations,
    keyPinLength,
    keyBiometric,
    keyLastActiveAt,
    keyGraceSeconds,
    keyFailures,
    keyLockedUntil,
  ];

  /// Default grace window. 30 seconds is long enough to read a notification and
  /// come back; a phone left on a desk for ten minutes is far past it. Stored
  /// rather than `const` so a later Immediately / 30s / 5min picker lands
  /// without a migration.
  static const int defaultGraceSeconds = 30;

  bool get enabled => _prefs.getBool(keyEnabled) ?? false;

  bool get biometricEnabled => _prefs.getBool(keyBiometric) ?? false;

  int get pinLength {
    final stored = _prefs.getInt(keyPinLength) ?? 4;
    return stored < 4 || stored > 8 ? 4 : stored;
  }

  int get iterations {
    final stored = _prefs.getInt(keyIterations) ?? 0;
    return stored > 0 ? stored : kDefaultPbkdf2Iterations;
  }

  int get graceSeconds {
    final stored = _prefs.getInt(keyGraceSeconds) ?? defaultGraceSeconds;
    return stored < 0 ? defaultGraceSeconds : stored;
  }

  int get failures {
    final stored = _prefs.getInt(keyFailures) ?? 0;
    return stored < 0 ? 0 : stored;
  }

  int? get lockedUntilMs => _prefs.getInt(keyLockedUntil);

  int? get lastActiveAtMs => _prefs.getInt(keyLastActiveAt);

  Uint8List? get salt => _decode(_prefs.getString(keySalt));

  Uint8List? get verifier => _decode(_prefs.getString(keyVerifier));

  /// The lock is armed *and* has something to check a PIN against.
  ///
  /// `enabled && !hasCredential` is the corrupt case — a partial prefs wipe, a
  /// restore gone wrong. It fails **open** (see [AppLockController]): failing
  /// closed with no verifier would brick the owner out of an app whose data is
  /// already behind an httpOnly session cookie. That is the threat model
  /// applied, not a shortcut.
  bool get hasCredential {
    final s = salt;
    final v = verifier;
    return s != null && s.isNotEmpty && v != null && v.isNotEmpty;
  }

  Future<void> writeCredential({
    required Uint8List salt,
    required Uint8List verifier,
    required int iterations,
    required int pinLength,
  }) async {
    await _prefs.setString(keySalt, base64Encode(salt));
    await _prefs.setString(keyVerifier, base64Encode(verifier));
    await _prefs.setInt(keyIterations, iterations);
    await _prefs.setInt(keyPinLength, pinLength);
  }

  Future<void> setEnabled(bool value) => _prefs.setBool(keyEnabled, value);

  Future<void> setBiometricEnabled(bool value) =>
      _prefs.setBool(keyBiometric, value);

  Future<void> setGraceSeconds(int value) =>
      _prefs.setInt(keyGraceSeconds, value);

  /// Written at `hidden`/`paused`. In prefs, not memory, deliberately: Android
  /// kills backgrounded processes constantly, and an owner returning four
  /// seconds later to a restored activity experiences a *resume*, not a launch.
  /// An in-memory timestamp would turn every low-memory kill into an unlock
  /// prompt. The same rule handles the pathological case safely — a crash or a
  /// force-stop leaves a stale timestamp, which fails closed.
  Future<void> setLastActiveAt(int millisecondsSinceEpoch) =>
      _prefs.setInt(keyLastActiveAt, millisecondsSinceEpoch);

  /// Erases the stamp so the next cold start reads null and locks.
  ///
  /// Called the moment the lock is raised. `shouldLockAt` treats a missing
  /// stamp as "lock", so being locked survives process death — a kill from the
  /// lock screen cannot restart inside the grace window.
  Future<void> clearLastActiveAt() => _prefs.remove(keyLastActiveAt);

  Future<void> setFailures(int value) => _prefs.setInt(keyFailures, value);

  Future<void> setLockedUntil(int? millisecondsSinceEpoch) async {
    if (millisecondsSinceEpoch == null) {
      await _prefs.remove(keyLockedUntil);
    } else {
      await _prefs.setInt(keyLockedUntil, millisecondsSinceEpoch);
    }
  }

  /// Wipes salt, verifier, timestamps and the cooldown. Called when the lock is
  /// turned off and on sign-out, so a new sign-in can never inherit the
  /// previous account's PIN or grace window.
  Future<void> clear() async {
    for (final key in allKeys) {
      await _prefs.remove(key);
    }
  }

  static Uint8List? _decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      // Corrupt value: treat it as absent so the fail-open path handles it,
      // rather than throwing on a synchronous first-frame read.
      return null;
    }
  }
}
