import 'dart:async';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/features/lock/data/lock_store.dart';
import 'package:coincompass/features/lock/domain/lock_state.dart';
import 'package:coincompass/features/lock/domain/pin_verifier.dart';
import 'package:coincompass/features/lock/presentation/lock_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lock_fakes.dart';

/// The app lock's decision logic.
///
/// Grace, cooldown and fail-open are the parts most worth pinning, and they are
/// pure state — so this drives [AppLockController] directly with an injected
/// clock instead of pumping a widget. Nothing here sleeps, nothing waits on an
/// isolate, and **nothing can reach the network**: the controller has no
/// repository, no Dio and no ApiClient in its constructor, and the one test
/// that goes through Riverpod deliberately leaves `apiClientProvider`
/// un-overridden so any accidental request would throw instead of dialling out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeClock clock;
  late FakeBiometricGate biometrics;
  late FakePrivacyScreen privacy;
  late FakeSignOut signOut;

  setUp(() {
    clock = FakeClock();
    biometrics = FakeBiometricGate();
    privacy = FakePrivacyScreen();
    signOut = FakeSignOut();
  });

  Future<(AppLockController, LockStore, SharedPreferences)> build(
    Map<String, Object> prefsValues,
  ) async {
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    final store = LockStore(prefs);
    final controller = AppLockController(
      store: store,
      biometrics: biometrics,
      hasher: const InlinePinHasher(),
      privacy: privacy,
      onSignOut: signOut.call,
      now: clock.call,
      iterations: kTestIterations,
      // Driven by hand: `handleHidden` / `handleResumed` are the same public
      // methods the AppLifecycleListener forwards to, so this tests the real
      // path without a binding's lifecycle events.
      observeLifecycle: false,
    );
    addTearDown(controller.dispose);
    return (controller, store, prefs);
  }

  // ── the lock screen must not refresh its own grace window ────────────────

  group('being locked survives the process', () {
    test('the lock screen does not refresh the stamp it is gating on', () async {
      // The blocker this pins: `_markAway` used to stamp `lastActiveAtMs`
      // unconditionally. Lock screen up -> background/kill -> reopen inside the
      // grace window -> the app measured elapsed time from a stamp the LOCK
      // SCREEN had written, decided it was still fresh, and opened straight
      // onto the dashboard.
      final seeded = clock.millis - 60000;
      final (controller, store, _) = await build(
        seedLockedPrefs(lastActiveAtMs: seeded),
      );

      expect(controller.state.phase, LockPhase.locked,
          reason: 'stale stamp must cold-start locked');

      // Backgrounding from the lock screen must not move the stamp forward.
      clock.advance(const Duration(seconds: 5));
      controller.handleHidden();
      await Future<void>.delayed(Duration.zero);

      expect(store.lastActiveAtMs, seeded,
          reason: 'the lock screen must never refresh the stamp it gates on');

      // Come back one second later — well inside the 30s grace.
      clock.advance(const Duration(seconds: 1));
      controller.handleResumed();

      expect(controller.state.phase, LockPhase.locked,
          reason: 'a kill-and-reopen from the lock screen must stay locked');
    });

    test('raising the lock burns the stamp so a cold start re-locks', () async {
      final (controller, store, _) = await build(
        seedLockedPrefs(lastActiveAtMs: clock.millis),
      );

      controller.lockNow();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, LockPhase.locked);
      expect(store.lastActiveAtMs, isNull,
          reason: 'a null stamp is what makes shouldLockAt fail closed');
    });

    test('a backwards clock cannot strand the keypad indefinitely', () async {
      // An absolute `lockedUntilMs` plus a clock that jumps back used to refuse
      // the correct PIN for the whole skew. The remaining wait is clamped to
      // one maximum cooldown, so it is always self-healing.
      const state = AppLockState(lockedUntilMs: 1 << 42);
      expect(
        state.cooldownRemainingMs(0),
        AppLockState.maxCooldownMs,
        reason: 'a far-future instant must clamp, not wait years',
      );
      expect(state.cooldownRemainingMs(1 << 43), 0);
    });
  });

  // ── cold start ────────────────────────────────────────────────────────────

  group('cold start', () {
    test('is completely inert when the lock has never been turned on', () async {
      final (controller, _, _) = await build(const {});

      expect(controller.state.enabled, isFalse);
      expect(controller.state.isGating, isFalse);
      expect(controller.state.phase, LockPhase.unlocked);
      // The probe is not even run: a disabled lock must not touch local_auth.
      expect(biometrics.authenticateCalls, 0);
      // The host starts fail-closed at onCreate, so Dart has to relax it.
      expect(privacy.last, isFalse);
    });

    test('locks when the lock is on and the app has not been used', () async {
      // No `lastActiveAtMs` at all — a first launch after arming, or after the
      // key was wiped.
      final (controller, _, _) = await build(seedLockedPrefs());

      expect(controller.state.enabled, isTrue);
      expect(controller.state.phase, LockPhase.locked);
      expect(controller.state.isGating, isTrue);
      expect(privacy.last, isTrue);
    });

    test('locks on a real cold start, minutes after the app was last used', () async {
      final (controller, _, _) = await build(
        seedLockedPrefs(
          lastActiveAtMs: clock.millis - const Duration(minutes: 12).inMilliseconds,
        ),
      );

      expect(controller.state.phase, LockPhase.locked);
    });

    test(
      'a relaunch inside the grace window does not demand a re-unlock',
      () async {
        // Android kills backgrounded processes constantly. An owner coming back
        // five seconds later to a *restored* activity experiences a resume, not
        // a launch, and must not be punished for what the OS decided to do with
        // the process.
        final (controller, _, _) = await build(
          seedLockedPrefs(lastActiveAtMs: clock.millis - 5000),
        );

        expect(controller.state.phase, LockPhase.unlocked);
        expect(controller.state.isGating, isFalse);
      },
    );

    test('the pin length is read back so the dot row is right', () async {
      final (controller, _, _) = await build(seedLockedPrefs(pin: '654321'));
      expect(controller.state.pinLength, 6);
    });
  });

  // ── the grace window, both directions ─────────────────────────────────────

  group('grace window', () {
    Future<LockPhase> phaseAfterAway(Duration away) async {
      final (controller, _, _) = await build(
        seedLockedPrefs(lastActiveAtMs: clock.millis - 60000),
      );
      // Start from a known-unlocked session.
      controller.handleResumed();
      expect(controller.state.phase, LockPhase.locked);
      await controller.unlockWithPin('1234');
      expect(controller.state.phase, LockPhase.unlocked);

      controller.handleHidden();
      expect(controller.state.phase, LockPhase.shielded);
      clock.advance(away);
      controller.handleResumed();
      return controller.state.phase;
    }

    test('29 seconds away stays unlocked', () async {
      expect(
        await phaseAfterAway(const Duration(seconds: 29)),
        LockPhase.unlocked,
      );
    });

    test('exactly 30 seconds away locks', () async {
      // The boundary is inclusive: `elapsed >= grace` locks.
      expect(
        await phaseAfterAway(const Duration(seconds: 30)),
        LockPhase.locked,
      );
    });

    test('31 seconds away locks', () async {
      expect(
        await phaseAfterAway(const Duration(seconds: 31)),
        LockPhase.locked,
      );
    });

    test('ten minutes on a desk locks', () async {
      expect(
        await phaseAfterAway(const Duration(minutes: 10)),
        LockPhase.locked,
      );
    });

    test('a few seconds checking a notification does not lock', () async {
      expect(
        await phaseAfterAway(const Duration(seconds: 4)),
        LockPhase.unlocked,
      );
    });

    test('a clock moved backwards locks rather than trusting it', () async {
      final (controller, _, _) = await build(
        seedLockedPrefs(lastActiveAtMs: clock.millis - 60000),
      );
      await controller.unlockWithPin('1234');
      controller.handleHidden();
      clock.rewind(const Duration(hours: 2));
      controller.handleResumed();

      expect(controller.state.phase, LockPhase.locked);
    });

    test(
      'the shield goes up on inactive before any decision is made',
      () async {
        // The notification shade coming down, or the start of the recents
        // gesture. A covering frame has to be in before Android snapshots.
        final (controller, _, _) = await build(
          seedLockedPrefs(lastActiveAtMs: clock.millis - 60000),
        );
        await controller.unlockWithPin('1234');

        controller.handleInactive();
        expect(controller.state.phase, LockPhase.shielded);
        expect(controller.state.isGating, isTrue);
      },
    );

    test(
      'a shade pull-down does not measure elapsed time from hours ago',
      () async {
        // Regression: if the timestamp were only written at `hidden`, an
        // `inactive` would shield the app and the resume that follows would
        // compare against whenever it was last *backgrounded* — locking the
        // owner out of a session they never left.
        final (controller, _, _) = await build(
          seedLockedPrefs(
            lastActiveAtMs: clock.millis - const Duration(hours: 3).inMilliseconds,
          ),
        );
        await controller.unlockWithPin('1234');

        controller.handleInactive();
        clock.advance(const Duration(seconds: 2));
        controller.handleResumed();

        expect(controller.state.phase, LockPhase.unlocked);
      },
    );

    test('the timestamp survives process death', () async {
      // Same prefs, brand-new controller: a force-stop or a crash leaves a
      // stale stamp, which fails closed.
      final seed = seedLockedPrefs(
        lastActiveAtMs: clock.millis - const Duration(minutes: 45).inMilliseconds,
      );
      final (first, _, _) = await build(seed);
      expect(first.state.phase, LockPhase.locked);

      final (second, _, _) = await build(seed);
      expect(second.state.phase, LockPhase.locked);
    });

    test('a custom grace window is honoured', () async {
      final (controller, _, _) = await build(
        seedLockedPrefs(
          graceSeconds: 300,
          lastActiveAtMs: clock.millis - const Duration(minutes: 4).inMilliseconds,
        ),
      );
      expect(controller.state.phase, LockPhase.unlocked);
    });
  });

  // ── the PIN ───────────────────────────────────────────────────────────────

  group('unlocking with the PIN', () {
    test('the right PIN opens it and clears the failure count', () async {
      final (controller, store, _) = await build(
        seedLockedPrefs(failures: 3),
      );

      expect(await controller.unlockWithPin('1234'), isTrue);
      expect(controller.state.phase, LockPhase.unlocked);
      expect(controller.state.failures, 0);
      expect(store.failures, 0);
      expect(controller.state.message, isNull);
    });

    test('a wrong PIN stays locked and counts down the tries', () async {
      final (controller, store, _) = await build(seedLockedPrefs());

      expect(await controller.unlockWithPin('9999'), isFalse);
      expect(controller.state.phase, LockPhase.locked);
      expect(controller.state.failures, 1);
      expect(store.failures, 1, reason: 'must survive a force-stop');
      expect(controller.state.message, 'Wrong PIN — 4 tries left.');
      expect(controller.state.shakeToken, 1);

      await controller.unlockWithPin('9998');
      expect(controller.state.message, 'Wrong PIN — 3 tries left.');
      expect(controller.state.shakeToken, 2);
    });

    test('a PIN of the wrong length is simply wrong, never a crash', () async {
      final (controller, _, _) = await build(seedLockedPrefs());
      expect(await controller.unlockWithPin('12'), isFalse);
      expect(await controller.unlockWithPin('123456789'), isFalse);
      expect(await controller.unlockWithPin(''), isFalse);
      expect(controller.state.phase, LockPhase.locked);
    });
  });

  // ── the cooldown ladder ───────────────────────────────────────────────────

  group('cooldown', () {
    test('escalates 30s, 60s, then 300s and caps there', () {
      expect(cooldownForFailures(1), isNull);
      expect(cooldownForFailures(4), isNull);
      expect(cooldownForFailures(5), const Duration(seconds: 30));
      expect(cooldownForFailures(9), isNull);
      expect(cooldownForFailures(10), const Duration(seconds: 60));
      expect(cooldownForFailures(15), const Duration(seconds: 300));
      expect(cooldownForFailures(20), const Duration(seconds: 300));
      expect(cooldownForFailures(100), const Duration(seconds: 300));
    });

    test('five wrong PINs buy a 30-second wait', () async {
      final (controller, store, _) = await build(seedLockedPrefs());

      for (var i = 0; i < 5; i++) {
        await controller.unlockWithPin('0000');
      }

      expect(controller.state.failures, 5);
      expect(controller.state.isCoolingDown(clock.millis), isTrue);
      expect(
        controller.state.cooldownRemainingMs(clock.millis),
        const Duration(seconds: 30).inMilliseconds,
      );
      expect(controller.state.message, contains('30 seconds'));
      expect(store.lockedUntilMs, isNotNull, reason: 'survives a force-stop');
    });

    test('the right PIN is refused while the cooldown runs', () async {
      final (controller, _, _) = await build(seedLockedPrefs());
      for (var i = 0; i < 5; i++) {
        await controller.unlockWithPin('0000');
      }

      expect(await controller.unlockWithPin('1234'), isFalse);
      expect(controller.state.phase, LockPhase.locked);

      // …and works the moment it expires. Never a wipe, never permanent.
      clock.advance(const Duration(seconds: 31));
      expect(controller.state.isCoolingDown(clock.millis), isFalse);
      expect(await controller.unlockWithPin('1234'), isTrue);
      expect(controller.state.phase, LockPhase.unlocked);
    });

    test('the second and third tiers are 60s and 300s', () async {
      final (controller, _, _) = await build(seedLockedPrefs());

      Future<void> fiveWrong() async {
        for (var i = 0; i < 5; i++) {
          await controller.unlockWithPin('0000');
        }
      }

      await fiveWrong();
      clock.advance(const Duration(seconds: 31));
      await fiveWrong();
      expect(
        controller.state.cooldownRemainingMs(clock.millis),
        const Duration(seconds: 60).inMilliseconds,
      );

      clock.advance(const Duration(seconds: 61));
      await fiveWrong();
      expect(
        controller.state.cooldownRemainingMs(clock.millis),
        const Duration(seconds: 300).inMilliseconds,
      );
    });

    test('a cooldown written before a force-stop is still in force', () async {
      final (controller, _, _) = await build(
        seedLockedPrefs(
          failures: 5,
          lockedUntilMs: clock.millis + 20000,
        ),
      );
      expect(controller.state.isCoolingDown(clock.millis), isTrue);
      expect(await controller.unlockWithPin('1234'), isFalse);
    });
  });

  // ── fail open ─────────────────────────────────────────────────────────────

  group('fail open', () {
    test(
      'an armed lock with no stored verifier turns itself off',
      () async {
        // A partial prefs wipe or a restore gone wrong. There is no key in the
        // world that opens this lock, and the data behind it is already gated
        // by an httpOnly cookie — failing closed would brick the owner to
        // defend against a threat that is not in the model.
        final (controller, store, prefs) = await build(const {
          LockStore.keyEnabled: true,
        });

        expect(controller.state.enabled, isFalse);
        expect(controller.state.isGating, isFalse);
        expect(controller.state.failedOpen, isTrue);
        expect(store.enabled, isFalse);
        expect(prefs.getBool(LockStore.keyEnabled), isNull);
        expect(privacy.last, isFalse);
      },
    );

    test('a corrupt salt is treated as absent, not thrown', () async {
      final seed = Map<String, Object>.from(seedLockedPrefs());
      seed[LockStore.keySalt] = 'not base64 !!!';
      final (controller, _, _) = await build(seed);

      expect(controller.state.enabled, isFalse);
      expect(controller.state.failedOpen, isTrue);
    });

    test('the banner can be dismissed once it has been read', () async {
      final (controller, _, _) = await build(const {
        LockStore.keyEnabled: true,
      });
      controller.acknowledgeFailOpen();
      expect(controller.state.failedOpen, isFalse);
    });
  });

  // ── arming and disarming ──────────────────────────────────────────────────

  group('enable / disable', () {
    test('enabling writes a salted verifier and never the PIN', () async {
      final (controller, store, prefs) = await build(const {});

      await controller.enable(pin: '246813', biometric: false);

      expect(store.enabled, isTrue);
      expect(store.pinLength, 6);
      expect(store.hasCredential, isTrue);
      expect(privacy.last, isTrue);
      // The lock does not slam shut on the owner who just typed it twice.
      expect(controller.state.phase, LockPhase.unlocked);

      // The PIN itself must not be anywhere in the prefs file.
      final dumped = prefs
          .getKeys()
          .map((k) => '$k=${prefs.get(k)}')
          .join('\n');
      expect(dumped, isNot(contains('246813')));

      expect(await controller.verifyPinLocally('246813'), isTrue);
      expect(await controller.verifyPinLocally('246814'), isFalse);
    });

    test('two installs with the same PIN get different verifiers', () async {
      final (first, firstStore, _) = await build(const {});
      await first.enable(pin: '1111', biometric: false);
      final firstVerifier = firstStore.verifier!;

      final (second, secondStore, _) = await build(const {});
      await second.enable(pin: '1111', biometric: false);

      expect(
        constantTimeEquals(firstVerifier, secondStore.verifier!),
        isFalse,
      );
    });

    test('disabling wipes salt, verifier, stamps and the cooldown', () async {
      final (controller, store, prefs) = await build(
        seedLockedPrefs(failures: 4, lockedUntilMs: clock.millis + 5000),
      );

      await controller.disable();

      expect(store.enabled, isFalse);
      expect(store.hasCredential, isFalse);
      expect(store.lastActiveAtMs, isNull);
      expect(store.lockedUntilMs, isNull);
      expect(store.failures, 0);
      for (final key in LockStore.allKeys) {
        expect(prefs.containsKey(key), isFalse, reason: '$key survived');
      }
      expect(privacy.last, isFalse);
      expect(controller.state.isGating, isFalse);
    });

    test('changing the PIN keeps the lock armed', () async {
      final (controller, store, _) = await build(seedLockedPrefs());
      await controller.changePin('98765');

      expect(store.enabled, isTrue);
      expect(store.pinLength, 5);
      expect(await controller.verifyPinLocally('98765'), isTrue);
      expect(await controller.verifyPinLocally('1234'), isFalse);
    });

    test('lock now closes it immediately', () async {
      final (controller, _, _) = await build(
        seedLockedPrefs(lastActiveAtMs: clock.millis),
      );
      expect(controller.state.phase, LockPhase.unlocked);
      controller.lockNow();
      expect(controller.state.phase, LockPhase.locked);
    });

    test('lock now does nothing when the lock is off', () async {
      final (controller, _, _) = await build(const {});
      controller.lockNow();
      expect(controller.state.isGating, isFalse);
    });
  });

  // ── the guard the whole design hangs on ───────────────────────────────────

  group('settings.pinEnabled arriving true NEVER sets applock.enabled', () {
    test('nothing but the setup sheet can arm the lock', () async {
      final (controller, store, prefs) = await build(const {});

      // Everything the app does around a settings refresh, with the server
      // saying the *web* PIN is on. None of it may arm this phone.
      await controller.refreshAvailability();
      controller.handleInactive();
      controller.handleHidden();
      controller.handleResumed();
      controller.lockNow();
      await controller.setBiometricEnabled(true);
      await controller.unlockWithPin('1234');

      expect(store.enabled, isFalse);
      expect(prefs.getBool(LockStore.keyEnabled), isNull);
      expect(controller.state.enabled, isFalse);
    });

    test('only one line of source can write applock.enabled = true', () {
      // A structural pin, not a behavioural one: if a second `setEnabled(true)`
      // call site ever appears — in a settings listener, say — this fails.
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final callSites = <String>[];
      for (final file in sources) {
        for (final line in file.readAsLinesSync()) {
          if (line.contains('store.setEnabled(true)')) {
            callSites.add('${file.path}: ${line.trim()}');
          }
        }
      }

      expect(
        callSites,
        hasLength(1),
        reason: 'applock.enabled may only be written by enable(): $callSites',
      );
      expect(callSites.single, contains('lock_controller.dart'));
    });
  });

  // ── biometrics ────────────────────────────────────────────────────────────

  group('biometrics', () {
    test('a successful read unlocks without touching the PIN', () async {
      final (controller, _, _) = await build(seedLockedPrefs(biometric: true));
      await controller.refreshAvailability();

      await controller.tryBiometric();

      expect(controller.state.phase, LockPhase.unlocked);
      expect(biometrics.authenticateCalls, 1);
    });

    test('a cancelled prompt is silent and leaves the keypad live', () async {
      biometrics.result = const BiometricResult(BiometricOutcome.canceled);
      final (controller, _, _) = await build(seedLockedPrefs(biometric: true));
      await controller.refreshAvailability();

      await controller.tryBiometric();

      expect(controller.state.phase, LockPhase.locked);
      expect(controller.state.message, isNull);
      expect(await controller.unlockWithPin('1234'), isTrue);
    });

    test('an unavailable sensor collapses the affordance with one line', () async {
      biometrics.result = const BiometricResult(
        BiometricOutcome.unavailable,
        'No fingerprint or face is enrolled on this phone — use your PIN.',
      );
      final (controller, _, _) = await build(seedLockedPrefs(biometric: true));
      await controller.refreshAvailability();
      expect(controller.state.biometricOffered, isTrue);

      await controller.tryBiometric();

      expect(controller.state.biometricOffered, isFalse);
      expect(controller.state.message, contains('use your PIN'));
      // …and the PIN still works, which is the whole point.
      expect(await controller.unlockWithPin('1234'), isTrue);
    });

    test('a fingerprint lockout never blocks the PIN', () async {
      biometrics.result = const BiometricResult(
        BiometricOutcome.lockedOut,
        'Fingerprint is locked until the phone is unlocked normally — use your '
        'PIN.',
      );
      final (controller, _, _) = await build(seedLockedPrefs(biometric: true));
      await controller.refreshAvailability();

      await controller.tryBiometric();

      expect(controller.state.phase, LockPhase.locked);
      expect(controller.state.message, contains('PIN'));
      expect(await controller.unlockWithPin('1234'), isTrue);
    });

    test('the prompt fires itself exactly once per lock episode', () async {
      biometrics.result = const BiometricResult(BiometricOutcome.canceled);
      final (controller, _, _) = await build(seedLockedPrefs(biometric: true));
      await controller.refreshAvailability();

      await controller.maybeAutoPromptBiometric();
      await controller.maybeAutoPromptBiometric();
      await controller.maybeAutoPromptBiometric();

      expect(biometrics.authenticateCalls, 1);

      // A fresh lock is a fresh episode.
      controller.lockNow();
      await controller.maybeAutoPromptBiometric();
      expect(biometrics.authenticateCalls, 2);
    });

    test('it never prompts when the owner did not opt in', () async {
      final (controller, _, _) = await build(seedLockedPrefs());
      await controller.refreshAvailability();
      await controller.maybeAutoPromptBiometric();
      await controller.tryBiometric();
      expect(biometrics.authenticateCalls, 0);
    });

    test(
      'a lifecycle event during a prompt cannot re-arm it — no prompt loop',
      () async {
        // ColorOS on the CPH2569 emits `paused`, not just `inactive`, when a
        // system dialog takes focus. Without the in-flight guard the prompt
        // would background the app and re-arm itself on the resume that
        // follows, and the owner could only escape by force-stopping.
        final pending = Completer<BiometricResult>();
        biometrics.pending = pending.future;
        final (controller, store, _) = await build(
          seedLockedPrefs(biometric: true, lastActiveAtMs: clock.millis),
        );
        await controller.refreshAvailability();
        expect(controller.state.phase, LockPhase.unlocked);

        final inFlight = controller.tryBiometric();
        controller.handleInactive();
        controller.handleHidden();
        clock.advance(const Duration(minutes: 5));
        controller.handleResumed();

        // Nothing moved: not the phase, not the stamp.
        expect(controller.state.phase, LockPhase.unlocked);
        expect(store.lastActiveAtMs, isNot(clock.millis));
        expect(biometrics.authenticateCalls, 1);

        pending.complete(const BiometricResult(BiometricOutcome.canceled));
        await inFlight;
        expect(biometrics.authenticateCalls, 1);
      },
    );
  });

  // ── the way out ───────────────────────────────────────────────────────────

  group('sign out from the lock screen', () {
    test('wipes the lock and lifts the privacy flag', () async {
      final (controller, store, prefs) = await build(seedLockedPrefs());

      await controller.signOutFromLock();

      expect(signOut.calls, 1);
      expect(store.enabled, isFalse);
      expect(store.hasCredential, isFalse);
      for (final key in LockStore.allKeys) {
        expect(prefs.containsKey(key), isFalse);
      }
      expect(privacy.last, isFalse);
      expect(controller.state.isGating, isFalse);
    });

    test('still clears the lock when the logout request fails', () async {
      // Offline. `AuthRepository.signOut()` swallows the failed POST and clears
      // the cookie jar in its `finally`, so a forgotten PIN with no signal
      // still reaches a login screen rather than a brick.
      final (controller, store, _) = await build(seedLockedPrefs());
      final failing = AppLockController(
        store: store,
        biometrics: biometrics,
        hasher: const InlinePinHasher(),
        privacy: privacy,
        onSignOut: () => Future<void>.error(const SocketException('offline')),
        now: clock.call,
        iterations: kTestIterations,
        observeLifecycle: false,
      );
      addTearDown(failing.dispose);

      await expectLater(failing.signOutFromLock(), throwsA(isA<SocketException>()));
      expect(store.enabled, isFalse);
      expect(store.hasCredential, isFalse);
    });
  });

  // ── offline, proven structurally ──────────────────────────────────────────

  group('the offline path', () {
    test(
      'unlocking works in a container with no ApiClient at all',
      () async {
        // The strongest honest proof available: `apiClientProvider` is left
        // un-overridden, so it throws StateError the moment anything asks for
        // it. The lock unlocks anyway, because nothing on its path asks.
        SharedPreferences.setMockInitialValues(seedLockedPrefs());
        final prefs = await SharedPreferences.getInstance();

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            biometricGateProvider.overrideWithValue(biometrics),
            pinHasherProvider.overrideWithValue(const InlinePinHasher()),
            privacyScreenProvider.overrideWithValue(privacy),
            lockClockProvider.overrideWithValue(clock.call),
            lockSignOutProvider.overrideWithValue(signOut.call),
          ],
        );
        addTearDown(container.dispose);

        expect(
          () => container.read(apiClientProvider),
          throwsStateError,
          reason: 'the point of this test is that nothing reaches for it',
        );

        final controller = container.read(appLockControllerProvider.notifier);
        expect(controller.state.phase, LockPhase.locked);
        expect(await controller.unlockWithPin('1234'), isTrue);
        expect(
          container.read(appLockControllerProvider).phase,
          LockPhase.unlocked,
        );
      },
    );
  });
}
