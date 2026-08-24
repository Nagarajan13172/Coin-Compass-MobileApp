import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../lock/domain/lock_state.dart';
import '../../lock/presentation/app_lock_setup_sheet.dart';
import '../../lock/presentation/lock_controller.dart';
import '../domain/app_settings.dart';
import 'security_sheets.dart';
import 'settings_providers.dart';

/// App lock (this phone), PIN lock and Net Worth lock (both web-only), and
/// two-factor status.
///
/// The ordering is deliberate: the app lock goes first because it is the one
/// that actually locks the device in the owner's hand. The two below it arm the
/// **web** client and are unrelated — arming the phone must not change how
/// coincompass.sathishkumar.cloud behaves in a browser, and turning the web PIN
/// off must not silently unlock this phone.
///
/// Two-factor is read-only here: enrolling needs a QR scan and a 6-digit
/// confirmation, and disabling one the owner relies on is worse than not
/// offering the button. `GET /auth/2fa/status` is what the web renders too —
/// not `AppUser.twoFactorEnabled`.
class SettingsSecurityCard extends ConsumerWidget {
  const SettingsSecurityCard({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final pending = ref.watch(settingsWriteControllerProvider);
    final blocked = pending != null;
    final lock = ref.watch(appLockControllerProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Security'),
          const SizedBox(height: 12),

          if (lock.failedOpen) ...[
            _FailOpenBanner(
              onDismiss: () => ref
                  .read(appLockControllerProvider.notifier)
                  .acknowledgeFailOpen(),
            ),
            const SizedBox(height: 14),
          ],

          _SecurityRow(
            icon: LucideIcons.smartphoneNfc,
            enabled: lock.enabled,
            title: 'App lock (this phone)',
            // Only promise the fingerprint when it is actually armed. The
            // setup sheet's biometric toggle is opt-in and defaults to off, so
            // a PIN-only setup was being described as accepting a fingerprint
            // that would never be offered.
            description: lock.enabled
                ? (lock.biometricEnabled
                      ? 'CoinCompass asks for your fingerprint — or your PIN — '
                            'when you open it, and again after 30 seconds '
                            'away. Checked on this phone, so it works with no '
                            'signal.'
                      : 'CoinCompass asks for your PIN when you open it, and '
                            'again after 30 seconds away. It is checked on '
                            'this phone, so it works with no signal.')
                : 'Ask for a PIN before CoinCompass opens on this phone. '
                      'Checked on the device, so it works offline.',
            actions: lock.enabled
                ? [
                    _SmallButton(
                      label: 'Change PIN',
                      onPressed: () => AppLockSetupSheet.show(
                        context,
                        mode: AppLockSetupMode.change,
                      ),
                    ),
                    _SmallButton(
                      label: 'Lock now',
                      onPressed: () => ref
                          .read(appLockControllerProvider.notifier)
                          .lockNow(),
                    ),
                    _SmallButton(
                      label: 'Turn off',
                      destructive: true,
                      onPressed: () => _disableAppLock(context, ref),
                    ),
                  ]
                : [
                    _SmallButton(
                      label: 'Set up app lock',
                      onPressed: () => AppLockSetupSheet.show(
                        context,
                        mode: AppLockSetupMode.enable,
                      ),
                    ),
                  ],
          ),
          if (lock.enabled &&
              lock.biometricAvailability == BiometricAvailability.available)
            Padding(
              padding: const EdgeInsets.only(left: 50, top: 4),
              // A plain Row, not a SwitchListTile: ListTile paints its ink on
              // the nearest Material, and AppCard puts a coloured DecoratedBox
              // in between, which Flutter flags as a real error in debug.
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Unlock with fingerprint',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: lock.biometricEnabled,
                    onChanged: (value) => ref
                        .read(appLockControllerProvider.notifier)
                        .setBiometricEnabled(value),
                  ),
                ],
              ),
            ),
          Divider(color: c.border, height: 24),

          _SecurityRow(
            icon: LucideIcons.lockKeyhole,
            enabled: settings.pinEnabled,
            title: 'PIN lock (web)',
            // Still the web client's lock, and still not this app's. The app
            // lock above has its own PIN, chosen and checked on the device;
            // these two are deliberately independent, so the copy must not let
            // either one borrow the other's credit.
            description: settings.pinEnabled
                ? 'A 4–8 digit PIN is asked for when you open CoinCompass in a '
                      'browser. The lock on this phone is the row above.'
                : 'Ask for a short PIN when you open CoinCompass in a browser.',
            busy:
                pending == SettingsWrite.pin ||
                pending == SettingsWrite.disablePin,
            actions: settings.pinEnabled
                ? [
                    _SmallButton(
                      label: 'Change PIN',
                      onPressed: blocked
                          ? null
                          : () => PinSheet.show(context, change: true),
                    ),
                    _SmallButton(
                      label: 'Turn off',
                      destructive: true,
                      onPressed: blocked
                          ? null
                          : () => _disablePin(context, ref),
                    ),
                  ]
                : [
                    _SmallButton(
                      label: 'Set a PIN',
                      onPressed: blocked
                          ? null
                          : () => PinSheet.show(context, change: false),
                    ),
                  ],
          ),
          Divider(color: c.border, height: 24),

          _SecurityRow(
            icon: LucideIcons.shieldCheck,
            enabled: settings.wealthLockEnabled,
            title: 'Net Worth lock',
            // This app does not gate Net Worth or Stocks yet — the passcode
            // arms the web client. Say which surface it protects rather than
            // implying this phone is locked when it is not.
            description: settings.wealthLockEnabled
                ? 'Net Worth and Stocks are hidden on the web until the '
                      'passcode is entered. This app does not lock them yet.'
                : 'Hide Net Worth and Stocks behind a passcode on the web.',
            busy:
                pending == SettingsWrite.wealthPasscode ||
                pending == SettingsWrite.disableWealthPasscode,
            actions: settings.wealthLockEnabled
                ? [
                    _SmallButton(
                      label: 'Change',
                      onPressed: blocked
                          ? null
                          : () =>
                                WealthPasscodeSheet.show(context, change: true),
                    ),
                    _SmallButton(
                      label: 'Turn off',
                      destructive: true,
                      onPressed: blocked
                          ? null
                          : () => _disableWealthLock(context, ref),
                    ),
                  ]
                : [
                    _SmallButton(
                      label: 'Set a passcode',
                      onPressed: blocked
                          ? null
                          : () => WealthPasscodeSheet.show(
                              context,
                              change: false,
                            ),
                    ),
                  ],
          ),
          Divider(color: c.border, height: 24),

          const _TwoFactorRow(),

          const SizedBox(height: 12),
          Text(
            'The app lock covers this phone. The PIN and Net Worth locks cover '
            'CoinCompass in a browser. None of them is your account password, '
            'and none of them changes your data.',
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  /// Turning the lock off asks for the current PIN (or a fingerprint) first.
  /// A lock anyone holding the unlocked phone can switch off from Settings is
  /// not a lock. Checked locally — no network.
  Future<void> _disableAppLock(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await AppLockConfirmSheet.show(
      context,
      title: 'Turn off the app lock?',
      action: 'Turn off',
    );
    if (!confirmed) return;

    await ref.read(appLockControllerProvider.notifier).disable();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'App lock turned off. Screenshots and the app-switcher preview '
            'work normally again.',
          ),
        ),
      );
  }

  Future<void> _disablePin(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Turn off the web PIN?',
      // This row is the SERVER PIN — the one CoinCompass asks for in a browser.
      // The old copy said "the app will open without asking for a PIN", which
      // is false whenever the app lock (the row above) is on: turning this off
      // changes nothing about this phone. Two separate locks, two separate
      // sentences.
      message:
          'CoinCompass will stop asking for a PIN when you open it in a '
          'browser. The app lock on this phone is separate and stays as it '
          'is. You can set a new web PIN at any time.',
      confirmLabel: 'Turn off',
    );
    if (!confirmed) return;

    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .disablePin();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure ?? 'PIN lock turned off')));
  }

  Future<void> _disableWealthLock(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Turn off the Net Worth lock?',
      message:
          'Net Worth and Stocks will be visible without a passcode. The old '
          'passcode is discarded.',
      confirmLabel: 'Turn off',
    );
    if (!confirmed) return;

    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .disableWealthPasscode();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(failure ?? 'Net Worth lock turned off')),
      );
  }
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow({
    required this.icon,
    required this.enabled,
    required this.title,
    required this.description,
    this.busy = false,
    this.statusLabel,
    this.actions = const [],
  });

  final IconData icon;
  final bool enabled;
  final String title;
  final String description;
  final bool busy;
  final String? statusLabel;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = enabled ? c.income : c.mutedForeground;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: busy
                  ? SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tone,
                      ),
                    )
                  : Icon(icon, size: 18, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and pill share a row; the title takes what is left
                  // so a wide pill can never push it off the card.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusPill(
                        label: statusLabel ?? (enabled ? 'On' : 'Off'),
                        tone: tone,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 50, top: 10),
            // Wrap, not Row: "Change passcode" + "Turn off" does not fit one
            // 310dp line on every device text scale.
            child: Wrap(spacing: 8, runSpacing: 8, children: actions),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: tone,
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: destructive ? c.destructive : null,
        side: BorderSide(
          color: destructive ? c.destructive.withValues(alpha: 0.4) : c.border,
        ),
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

/// Read-only two-factor status.
class _TwoFactorRow extends ConsumerWidget {
  const _TwoFactorRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(twoFactorStatusProvider);

    return switch (status) {
      AsyncData(:final value) => _SecurityRow(
        icon: LucideIcons.smartphone,
        enabled: value.enabled,
        title: 'Two-factor authentication',
        description: value.enabled
            ? 'Authenticator app is on. '
                  '${value.emailFallback ? 'Email fallback is on. ' : ''}'
                  '${value.backupCodesRemaining} backup '
                  '${value.backupCodesRemaining == 1 ? 'code' : 'codes'} left.'
            : 'Not set up. Turn it on from the web app — enrolling needs a QR '
                  'scan.',
      ),
      AsyncError() => _SecurityRow(
        icon: LucideIcons.smartphone,
        enabled: false,
        statusLabel: 'Unknown',
        title: 'Two-factor authentication',
        description: "Couldn't check the status just now.",
        actions: [
          _SmallButton(
            label: 'Retry',
            onPressed: () => ref.invalidate(twoFactorStatusProvider),
          ),
        ],
      ),
      _ => const _SecurityRow(
        icon: LucideIcons.smartphone,
        enabled: false,
        statusLabel: '…',
        title: 'Two-factor authentication',
        description: 'Checking…',
        busy: true,
      ),
    };
  }
}


/// Shown once when the lock disabled itself because its stored verifier was
/// missing — a partial prefs wipe, a restore gone wrong.
///
/// This fails **open** on purpose, and it will look like a bug to a
/// security-minded reader. It is not: with no verifier there is no key in the
/// world that opens the lock, and the data behind it is already gated by an
/// httpOnly session cookie. Failing closed would brick the owner out of their
/// own app to defend against a threat that is not in the model.
class _FailOpenBanner extends StatelessWidget {
  const _FailOpenBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 17, color: c.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The app lock turned itself off: the saved PIN check was '
              'missing. Set it up again.',
              style: TextStyle(fontSize: 12.5, color: c.foreground),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 16),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
