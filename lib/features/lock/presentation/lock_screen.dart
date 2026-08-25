import 'dart:async';

import '../../../core/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../domain/lock_state.dart';
import 'lock_controller.dart';
import 'widgets/pin_keypad.dart';

/// The unlock screen.
///
/// **Nothing on this screen touches the network, in any state.** The PIN is
/// checked by PBKDF2 against a verifier on this phone and the fingerprint by
/// the OS keystore, so aeroplane mode, a lift, the Underground and a backend
/// outage are all indistinguishable from wifi. The one thing that always works
/// regardless is the way out: signing out is reachable from every state,
/// including the cooldown, and `AuthRepository.signOut()` clears the cookie jar
/// in a `finally`, so it works offline too.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _entry = '';
  Timer? _ticker;

  /// The "Forgot your PIN?" panel, rendered INLINE rather than as a modal
  /// route. This screen is built from `MaterialApp.builder`, which sits above
  /// the Navigator, so `showModalBottomSheet` threw
  /// "Navigator operation requested with a context that does not include a
  /// Navigator" and the only keyless way out of the lock was dead in
  /// production. A widget test passed because a bare `MaterialApp(home:)`
  /// harness *does* have a Navigator — the real wiring does not.
  bool _helpOpen = false;

  @override
  void initState() {
    super.initState();
    // One automatic prompt per lock episode; every later one is a deliberate
    // tap. That is half the anti-prompt-loop guarantee (the controller's
    // in-flight guard is the other half).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(appLockControllerProvider.notifier).maybeAutoPromptBiometric(),
      );
    });
  }

  /// The cooldown countdown ticks only while there is a cooldown, and cancels
  /// itself the moment it expires. One second, explicit, cancelled in dispose —
  /// there is no unbounded wait anywhere in this screen.
  void _syncTicker(AppLockState lock) {
    final cooling = lock.isCoolingDown(_now.millisecondsSinceEpoch);
    if (cooling && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        final state = ref.read(appLockControllerProvider);
        if (!state.isCoolingDown(_now.millisecondsSinceEpoch)) {
          _ticker?.cancel();
          _ticker = null;
        }
      });
    } else if (!cooling && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime get _now => ref.read(lockClockProvider)();

  Future<void> _onDigit(AppLockState lock, int digit) async {
    if (lock.verifying || lock.isCoolingDown(_now.millisecondsSinceEpoch)) {
      return;
    }
    if (_entry.length >= lock.pinLength) return;
    setState(() => _entry = '$_entry$digit');
    if (_entry.length == lock.pinLength) await _submit();
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    final pin = _entry;
    final ok = await ref
        .read(appLockControllerProvider.notifier)
        .unlockWithPin(pin);
    if (!mounted) return;
    if (!ok) {
      unawaited(HapticFeedback.mediumImpact());
      setState(() => _entry = '');
    }
  }

  Future<void> _signOut() async {
    await ref.read(appLockControllerProvider.notifier).signOutFromLock();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lock = ref.watch(appLockControllerProvider);

    // The capability probe is async, so on a cold start the first frame does
    // not yet know a fingerprint is enrolled. Fire the one automatic prompt the
    // moment it does; `maybeAutoPromptBiometric` is idempotent per episode, so
    // this cannot turn into a prompt loop.
    ref.listen<bool>(
      appLockControllerProvider.select((state) => state.biometricOffered),
      (previous, next) {
        if (!next) return;
        unawaited(
          ref
              .read(appLockControllerProvider.notifier)
              .maybeAutoPromptBiometric(),
        );
      },
    );

    _syncTicker(lock);
    final nowMs = _now.millisecondsSinceEpoch;
    final coolingMs = lock.cooldownRemainingMs(nowMs);
    final cooling = coolingMs > 0;

    // The back gesture must not dismiss the lock.
    // The help panel takes the back gesture first, so a tap into it is
    // escapable without also being a way past the lock.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _helpOpen) setState(() => _helpOpen = false);
      },
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: _helpOpen
              ? _ForgotPinSheet(
                  onSignOut: _signOut,
                  onClose: () => setState(() => _helpOpen = false),
                )
              : lock.signingOut
              ? const _SigningOut()
              : Column(
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                          child: Column(
                            children: [
                              const _BrandMark(),
                              const SizedBox(height: 18),
                              Text(
                                'CoinCompass is locked',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: c.foreground,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                cooling
                                    ? 'Too many wrong PINs.'
                                    : 'Enter your ${lock.pinLength}-digit PIN.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: c.mutedForeground,
                                ),
                              ),
                              const SizedBox(height: 22),
                              PinDots(
                                length: lock.pinLength,
                                filled: _entry.length,
                                shakeToken: lock.shakeToken,
                                tone: lock.message != null && !lock.verifying
                                    ? c.destructive
                                    : c.primary,
                              ),
                              SizedBox(
                                height: 46,
                                child: Center(
                                  child: _StatusLine(
                                    lock: lock,
                                    cooldownMs: coolingMs,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    PinKeypad(
                      enabled: !lock.verifying && !cooling,
                      onDigit: (digit) => _onDigit(lock, digit),
                      onBackspace: _onBackspace,
                      onBiometric: lock.biometricOffered
                          ? () => ref
                                .read(appLockControllerProvider.notifier)
                                .tryBiometric()
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _helpOpen = true),
                              child: const Text('Forgot your PIN?'),
                            ),
                          ),
                          Text('·', style: TextStyle(color: c.mutedForeground)),
                          Flexible(
                            child: TextButton(
                              // Always available, in every state including the
                              // cooldown. Someone who forgets their PIN must
                              // not be permanently bricked.
                              onPressed: _signOut,
                              style: TextButton.styleFrom(
                                foregroundColor: c.destructive,
                              ),
                              child: const Text('Sign out'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

}

/// The single line under the dots. One place, so the states cannot overlap.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.lock, required this.cooldownMs});

  final AppLockState lock;
  final int cooldownMs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (lock.verifying) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
          ),
          const SizedBox(width: 8),
          Text(
            'Checking…',
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
        ],
      );
    }

    if (cooldownMs > 0) {
      final seconds = (cooldownMs / 1000).ceil();
      final minutes = seconds ~/ 60;
      final rest = (seconds % 60).toString().padLeft(2, '0');
      return Text(
        'Try again in $minutes:$rest',
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: c.destructive,
        ),
      );
    }

    final message = lock.message;
    if (message == null) {
      // Only when the fingerprint affordance is gone for a reason the owner
      // has not been told about yet.
      const collapsed = {
        BiometricAvailability.notEnrolled,
        BiometricAvailability.noHardware,
        BiometricAvailability.unsupported,
      };
      if (lock.biometricEnabled &&
          collapsed.contains(lock.biometricAvailability)) {
        return Text(
          'Fingerprint is unavailable — use your PIN.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        );
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        message,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: c.destructive,
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: c.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(LucideIcons.compass, size: 28, color: c.primaryForeground),
    );
  }
}

class _SigningOut extends StatelessWidget {
  const _SigningOut();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 14),
          Text(
            'Signing out…',
            style: TextStyle(fontSize: 14, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// Where the offline truth is told. There is no offline *failure* to report on
/// the unlock path — nothing here touches the network — so this sheet says so
/// plainly and offers the only recovery there is.
class _ForgotPinSheet extends StatelessWidget {
  const _ForgotPinSheet({required this.onSignOut, required this.onClose});

  final Future<void> Function() onSignOut;

  /// Rendered inline, so closing is a setState in the parent — not a pop.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Forgot your PIN?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Your PIN is checked on this phone, so it works with no '
                'signal. There is no way to look it up or reset it here.\n\n'
                'If you have forgotten it, sign out and sign in again — that '
                'works without a connection too, and none of your data is '
                'deleted.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: c.mutedForeground,
                ),
              ),
              const SizedBox(height: 18),
              AppButton(
                label: 'Sign out',
                variant: AppButtonVariant.outlined,
                onPressed: () {
                  // `onClose`, not `Navigator.pop` — this panel is rendered
                  // inline above the lock, not pushed as a route. Popping here
                  // would throw for the same reason opening it as a modal did.
                  onClose();
                  unawaited(onSignOut());
                },
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Back',
                variant: AppButtonVariant.text,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
