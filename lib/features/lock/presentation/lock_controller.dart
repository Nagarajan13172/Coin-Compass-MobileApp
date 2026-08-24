import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/theme_controller.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/biometric_gate.dart';
import '../data/isolate_pin_hasher.dart';
import '../data/lock_store.dart';
import '../data/privacy_screen.dart';
import '../domain/lock_state.dart';
import '../domain/pin_verifier.dart';

/// The app lock's brain: what is locked, when it re-locks, and what a typed PIN
/// is checked against.
///
/// ## Threat model, in one paragraph
///
/// This lock defends against exactly one thing: a person who physically picks
/// up the owner's already-unlocked phone — a colleague at a desk, a relative on
/// the sofa, someone reading the task-switcher card over a shoulder — and opens
/// or resumes CoinCompass to read a net worth, a loan balance or a transaction
/// list. It buys friction and time on an unattended, running device, nothing
/// more. It explicitly does NOT defend against anyone with root, a debugger,
/// `adb backup` or the extracted app sandbox, because the `mt_session` httpOnly
/// cookie already sits in `PersistCookieJar`'s files on disk and reads the whole
/// account straight from the API without ever touching this app; nor against a
/// co-resident malicious app; nor against the owner forgetting the PIN (that is
/// a sign-out, not a wipe). Because the data is already gated by a session
/// cookie, this is a privacy curtain, not a security boundary — which is why it
/// fails OPEN on corrupt local state, always offers a keyless way out, and
/// never, under any circumstance, depends on the network to let the owner back
/// in.
///
/// ## Why the unlock never touches the network
///
/// `POST /settings/pin/verify` round-trips to the server. A lock that can only
/// be opened by that endpoint locks the owner out of their own app on a plane,
/// in a lift or on the Underground — a worse failure than having no lock at
/// all. So the app lock has its own PIN, chosen on the device, hashed on the
/// device, checked on the device. There is **no HTTP call anywhere on the
/// unlock path, in any state**. The server's `settings.pinEnabled` flag gates
/// the *web* client and is deliberately unrelated: arming a phone lock has no
/// business changing how a browser behaves, and disabling the web PIN must not
/// silently unlock the phone.
class AppLockController extends StateNotifier<AppLockState> {
  AppLockController({
    required this.store,
    required this.biometrics,
    required this.hasher,
    required this.privacy,
    required this.onSignOut,
    DateTime Function()? now,
    this.iterations = kDefaultPbkdf2Iterations,
    bool observeLifecycle = true,
  }) : clock = now ?? DateTime.now,
       super(const AppLockState()) {
    _bootstrap();
    if (observeLifecycle) {
      // AppLifecycleListener, not WidgetsBindingObserver: it names the
      // transitions instead of making this diff states, and it disposes
      // cleanly. It lives on the controller rather than a widget so lock state
      // is not tied to a widget's mount, and so tests can drive the same
      // public methods directly.
      _listener = AppLifecycleListener(
        onInactive: handleInactive,
        onHide: handleHidden,
        onPause: handleHidden,
        onResume: handleResumed,
      );
    }
  }

  /// Public because Dart has no private named initializing formals and this
  /// codebase keeps `flutter analyze` at zero issues. Treat them as internal.
  final LockStore store;
  final BiometricGate biometrics;
  final PinHasher hasher;
  final PrivacyScreen privacy;
  final Future<void> Function() onSignOut;
  final DateTime Function() clock;

  /// PBKDF2 work factor used when a PIN is written. Persisted per install
  /// alongside the verifier, so raising it later never invalidates a PIN
  /// someone already set. Lowered in tests so no test has to do 120,000 rounds
  /// of HMAC to check a state machine.
  final int iterations;

  AppLifecycleListener? _listener;

  /// Suppresses every lifecycle callback while a biometric prompt is up.
  ///
  /// Android's BiometricPrompt takes window focus, so showing it fires
  /// `inactive` and on some OEM skins (ColorOS, i.e. the CPH2569 this ships
  /// against) `paused`. Without this guard the prompt would background the app,
  /// which would re-arm the prompt on the resume that follows — a loop the
  /// owner cannot escape except by force-stopping.
  bool _authInFlight = false;

  /// The fingerprint prompt fires itself once per lock episode and never again.
  /// A second prompt is always a deliberate tap, which is the other half of the
  /// anti-loop guarantee.
  bool _autoPrompted = false;

  int get _nowMs => clock().millisecondsSinceEpoch;

  void _bootstrap() {
    // Relax the host's fail-closed privacy flag when the lock is off. The
    // Kotlin side starts private at onCreate because the recents snapshot is
    // taken when the activity stops and Dart has not read prefs yet.
    unawaited(privacy.setEnabled(store.enabled));

    if (!store.enabled) return;

    if (!store.hasCredential) {
      // Fail OPEN. `enabled: true` with no verifier means the prefs were
      // partially wiped or a restore went wrong; there is no key in the world
      // that opens this lock. Failing closed here would brick the owner out of
      // an app whose data is already behind an httpOnly cookie, to defend
      // against a threat that is not in the model. Settings shows a banner.
      unawaited(store.clear());
      unawaited(privacy.setEnabled(false));
      state = const AppLockState(failedOpen: true);
      return;
    }

    final locked = shouldLockAt(_nowMs);
    state = AppLockState(
      enabled: true,
      phase: locked ? LockPhase.locked : LockPhase.unlocked,
      pinLength: store.pinLength,
      biometricEnabled: store.biometricEnabled,
      failures: store.failures,
      lockedUntilMs: store.lockedUntilMs,
    );
    unawaited(refreshAvailability());
  }

  /// The one grace rule, used by both the cold start and every resume.
  ///
  /// Note the deliberate consequence: relaunching from the launcher within the
  /// grace window does **not** re-prompt. Any real cold start is minutes or
  /// hours later and always locks; within the window the owner was holding the
  /// phone seconds ago, and this makes "resume" and "launch" behave identically
  /// instead of depending on whether Android happened to keep the process.
  @visibleForTesting
  bool shouldLockAt(int nowMs) {
    final last = store.lastActiveAtMs;
    if (last == null) return true; // never used, or wiped: lock.
    if (nowMs < last) return true; // clock moved backwards: lock.
    return nowMs - last >= store.graceSeconds * 1000;
  }

  // ── lifecycle ─────────────────────────────────────────────────────────────

  /// The notification shade coming down, a system dialog taking focus, the
  /// start of the recents gesture. Cover the app immediately: a covering frame
  /// has to be in before Android snapshots.
  void handleInactive() => _markAway();

  void handleHidden() => _markAway();

  /// Marks the app away and stamps the moment.
  ///
  /// The stamp is written here as well as at `hidden` on purpose. If it were
  /// only written at `hidden`, a shade pull-down would shield the app and the
  /// following resume would measure elapsed time from whenever the app was last
  /// *backgrounded* — potentially hours — and lock the owner out of a session
  /// they never left.
  void _markAway() {
    if (_authInFlight) return;
    if (!state.enabled) return;
    // NEVER refresh the stamp while the lock is already showing. It used to be
    // written unconditionally, which meant: lock screen up -> background or
    // kill the app -> reopen within the grace window -> `shouldLockAt` measured
    // from a stamp written *by the lock screen itself* and the app opened
    // UNLOCKED. The lock handed the dashboard to whoever was holding the phone.
    if (state.phase == LockPhase.locked) return;
    unawaited(store.setLastActiveAt(_nowMs));
    if (state.phase == LockPhase.unlocked) {
      state = state.copyWith(phase: LockPhase.shielded);
    }
  }

  void handleResumed() {
    if (_authInFlight) return;
    if (!state.enabled) return;
    if (state.phase == LockPhase.locked) return;

    if (shouldLockAt(_nowMs)) {
      _enterLocked();
    } else {
      state = state.copyWith(phase: LockPhase.unlocked);
    }
  }

  /// "Lock now" from Settings, so the owner can prove to themself it works.
  void lockNow() {
    if (!state.enabled) return;
    _enterLocked();
  }

  void _enterLocked() {
    _autoPrompted = false;
    // Burn the stamp as we lock. Belt and braces alongside the guard in
    // `_markAway`: whatever happens to the process from here — a kill, a crash,
    // an OEM task-killer — the next cold start reads a null stamp and
    // `shouldLockAt` returns true. Being locked is a fact that must survive
    // process death, not a timer that a restart can outrun.
    unawaited(store.clearLastActiveAt());
    state = state.copyWith(
      phase: LockPhase.locked,
      verifying: false,
      clearMessage: true,
    );
  }

  // ── unlocking ─────────────────────────────────────────────────────────────

  /// Verifies [pin] entirely on this device and drops the gate on a match.
  ///
  /// Runs PBKDF2 through the injected hasher (an isolate in the app, inline in
  /// tests) and compares in constant time. No network, no "waiting for
  /// connection", no degraded mode — this behaves byte for byte the same in
  /// aeroplane mode as it does on wifi.
  Future<bool> unlockWithPin(String pin) async {
    if (state.verifying) return false;
    final nowMs = _nowMs;
    if (state.isCoolingDown(nowMs)) return false;

    final salt = store.salt;
    final expected = store.verifier;
    if (salt == null || expected == null) {
      await _failOpen();
      return true;
    }

    state = state.copyWith(verifying: true, clearMessage: true);
    final Uint8List derived;
    try {
      derived = await hasher.derive(
        Pbkdf2Request(
          pin: pin,
          salt: salt,
          iterations: store.iterations,
          keyLength: expected.length,
        ),
      );
    } catch (_) {
      // The production hasher spawns an isolate; a spawn failure under memory
      // pressure used to leave `verifying: true` forever, disabling the keypad
      // with no way back short of reinstalling. Surface it and let them retry.
      if (!mounted) return false;
      state = state.copyWith(
        verifying: false,
        message: 'Could not check that PIN. Try again.',
      );
      return false;
    }
    if (!mounted) return false;

    if (constantTimeEquals(derived, expected)) {
      await store.setFailures(0);
      await store.setLockedUntil(null);
      if (!mounted) return true;
      _completeUnlock();
      return true;
    }

    final failures = state.failures + 1;
    await store.setFailures(failures);
    final cooldown = cooldownForFailures(failures);
    final until = cooldown == null ? null : nowMs + cooldown.inMilliseconds;
    await store.setLockedUntil(until);
    if (!mounted) return false;

    state = state.copyWith(
      verifying: false,
      failures: failures,
      lockedUntilMs: until,
      clearLockedUntil: until == null,
      message: until == null
          ? _triesLeftMessage(failures)
          : 'Too many wrong PINs. Try again in '
                '${_spellSeconds(cooldown!.inSeconds)}.',
      shakeToken: state.shakeToken + 1,
    );
    return false;
  }

  static String _triesLeftMessage(int failures) {
    final left = triesBeforeCooldown(failures);
    return left == 1
        ? 'Wrong PIN — 1 try left before a short wait.'
        : 'Wrong PIN — $left tries left.';
  }

  static String _spellSeconds(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    final minutes = seconds ~/ 60;
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  /// Fires the fingerprint prompt once, automatically, on entering the lock.
  ///
  /// Deliberately not gated on the PIN cooldown: the OS counts fingerprint
  /// failures separately, and an owner with an enrolled finger must not be
  /// punished for a stranger's guesses at the keypad.
  Future<void> maybeAutoPromptBiometric() async {
    if (_autoPrompted) return;
    if (state.phase != LockPhase.locked) return;
    if (!state.biometricOffered) return;
    _autoPrompted = true;
    await tryBiometric();
  }

  Future<void> tryBiometric() async {
    if (_authInFlight) return;
    if (!state.biometricEnabled) return;

    _authInFlight = true;
    try {
      final result = await biometrics.authenticate('Unlock CoinCompass');
      if (!mounted) return;
      if (result.isSuccess) {
        await store.setFailures(0);
        await store.setLockedUntil(null);
        if (!mounted) return;
        _completeUnlock();
        return;
      }
      switch (result.outcome) {
        case BiometricOutcome.canceled:
          // Silent. The keypad is already live behind the dismissed prompt.
          break;
        case BiometricOutcome.unavailable:
          // Collapse the fingerprint affordance to one honest line and never
          // block PIN entry.
          state = state.copyWith(
            message: result.message,
            biometricAvailability: BiometricAvailability.notEnrolled,
          );
        case BiometricOutcome.failed:
        case BiometricOutcome.lockedOut:
        case BiometricOutcome.error:
          state = state.copyWith(message: result.message);
        case BiometricOutcome.success:
          break;
      }
    } finally {
      _authInFlight = false;
    }
  }

  void _completeUnlock() {
    unawaited(store.setLastActiveAt(_nowMs));
    _autoPrompted = false;
    state = state.copyWith(
      phase: LockPhase.unlocked,
      verifying: false,
      failures: 0,
      clearLockedUntil: true,
      clearMessage: true,
    );
  }

  Future<void> _failOpen() async {
    await store.clear();
    await privacy.setEnabled(false);
    if (!mounted) return;
    state = const AppLockState(failedOpen: true);
  }

  /// Clears the "the lock turned itself off" banner once Settings has shown it.
  void acknowledgeFailOpen() {
    if (!state.failedOpen) return;
    state = state.copyWith(failedOpen: false);
  }

  // ── setup, from Settings only ─────────────────────────────────────────────

  /// Arms the lock. **The only code path in the app that writes
  /// `applock.enabled: true`.** `settings.pinEnabled` arriving true from the
  /// server does not and cannot reach here — pinned by a test named after that
  /// sentence.
  ///
  /// Issues zero HTTP requests: the PIN is hashed and stored locally, so the
  /// lock can be armed with no connection at all.
  Future<void> enable({required String pin, required bool biometric}) async {
    final salt = newSalt();
    final verifier = await hasher.derive(
      Pbkdf2Request(pin: pin, salt: salt, iterations: iterations),
    );
    await store.writeCredential(
      salt: salt,
      verifier: verifier,
      iterations: iterations,
      pinLength: pin.length,
    );
    await store.setBiometricEnabled(biometric);
    await store.setFailures(0);
    await store.setLockedUntil(null);
    await store.setLastActiveAt(_nowMs);
    await store.setEnabled(true);
    await privacy.setEnabled(true);
    if (!mounted) return;

    // Deliberately does not lock straight away: the owner is standing right
    // there, having just typed it twice.
    state = state.copyWith(
      enabled: true,
      phase: LockPhase.unlocked,
      pinLength: pin.length,
      biometricEnabled: biometric,
      failures: 0,
      clearLockedUntil: true,
      clearMessage: true,
      failedOpen: false,
    );
    await refreshAvailability();
  }

  /// Replaces the PIN. The current one is checked locally by the caller — never
  /// over the wire.
  Future<void> changePin(String pin) async {
    final salt = newSalt();
    final verifier = await hasher.derive(
      Pbkdf2Request(pin: pin, salt: salt, iterations: iterations),
    );
    await store.writeCredential(
      salt: salt,
      verifier: verifier,
      iterations: iterations,
      pinLength: pin.length,
    );
    await store.setFailures(0);
    await store.setLockedUntil(null);
    if (!mounted) return;
    state = state.copyWith(
      pinLength: pin.length,
      failures: 0,
      clearLockedUntil: true,
      clearMessage: true,
    );
  }

  /// Turns the lock off and wipes the salt, the verifier and the timestamps.
  Future<void> disable() async {
    await store.clear();
    await privacy.setEnabled(false);
    if (!mounted) return;
    state = AppLockState(biometricAvailability: state.biometricAvailability);
  }

  Future<void> setBiometricEnabled(bool value) async {
    await store.setBiometricEnabled(value);
    if (!mounted) return;
    state = state.copyWith(biometricEnabled: value);
  }

  /// Checks a PIN against the stored verifier without changing lock state.
  /// Used by "Turn off" and "Change PIN", which must not be doable by anyone
  /// who merely picked the phone up unlocked.
  Future<bool> verifyPinLocally(String pin) async {
    final salt = store.salt;
    final expected = store.verifier;
    if (salt == null || expected == null) return false;
    final derived = await hasher.derive(
      Pbkdf2Request(
        pin: pin,
        salt: salt,
        iterations: store.iterations,
        keyLength: expected.length,
      ),
    );
    return constantTimeEquals(derived, expected);
  }

  Future<void> refreshAvailability() async {
    final availability = await biometrics.availability();
    if (!mounted) return;
    state = state.copyWith(biometricAvailability: availability);
  }

  /// The way out that needs no PIN.
  ///
  /// `AuthRepository.signOut()` posts `/auth/logout` inside a `try` and clears
  /// the cookie jar in a `finally`, so an **offline** sign-out still wipes
  /// `ApiClient.clearSession()`. Forgetting a PIN costs a re-login, never data.
  Future<void> signOutFromLock() async {
    if (state.signingOut) return;
    state = state.copyWith(signingOut: true);
    try {
      await onSignOut();
    } finally {
      await store.clear();
      await privacy.setEnabled(false);
      if (mounted) state = const AppLockState();
    }
  }

  @override
  void dispose() {
    _listener?.dispose();
    unawaited(biometrics.cancel());
    super.dispose();
  }
}

final lockStoreProvider = Provider<LockStore>(
  (ref) => LockStore(ref.watch(sharedPreferencesProvider)),
);

final biometricGateProvider = Provider<BiometricGate>(
  (ref) => LocalAuthGate(),
);

final pinHasherProvider = Provider<PinHasher>(
  (ref) => const IsolatePinHasher(),
);

final privacyScreenProvider = Provider<PrivacyScreen>(
  (ref) => const PrivacyScreen(),
);

/// The wall clock the lock reads. Injected so grace-window and cooldown tests
/// can move time without sleeping and without an unbounded pump.
final lockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Injected so the lock screen's sign-out can be driven by a fake in tests —
/// `POST /auth/logout` kills the session this project depends on and must never
/// be fired by a test.
final lockSignOutProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    // `AuthRepository.signOut()` posts `/auth/logout` inside a `try` and wipes
    // the cookie jar in its `finally`, so this works offline — the failed POST
    // is swallowed and the session still goes. The extra `clearSession()` is
    // belt-and-braces and idempotent, and it is what makes "the lock screen's
    // way out clears the cookie jar" true by inspection rather than by
    // following two files.
    await ref.read(authControllerProvider.notifier).signOut();
    await ref.read(apiClientProvider).clearSession();
  },
);

final appLockControllerProvider =
    StateNotifierProvider<AppLockController, AppLockState>(
      (ref) => AppLockController(
        store: ref.watch(lockStoreProvider),
        biometrics: ref.watch(biometricGateProvider),
        hasher: ref.watch(pinHasherProvider),
        privacy: ref.watch(privacyScreenProvider),
        onSignOut: ref.watch(lockSignOutProvider),
        now: ref.watch(lockClockProvider),
      ),
    );
