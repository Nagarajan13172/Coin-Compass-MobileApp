import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/app_settings.dart';
import 'security_sheets.dart';
import 'settings_providers.dart';

/// PIN lock, Net Worth lock and two-factor status.
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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Security'),
          const SizedBox(height: 12),

          _SecurityRow(
            icon: LucideIcons.lockKeyhole,
            enabled: settings.pinEnabled,
            title: 'PIN lock',
            description: settings.pinEnabled
                ? 'A 4–8 digit PIN is asked for every time the app starts.'
                : 'Ask for a short PIN before the app opens.',
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
            description: settings.wealthLockEnabled
                ? 'Net Worth and Stocks stay hidden until the passcode is '
                      'entered.'
                : 'Hide Net Worth and Stocks behind a passcode.',
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
            'These locks only gate the app on your devices. Your data stays '
            'exactly as it is, and neither one is your account password.',
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  Future<void> _disablePin(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Turn off the PIN lock?',
      message:
          'The app will open without asking for a PIN. You can set a new one '
          'at any time.',
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
