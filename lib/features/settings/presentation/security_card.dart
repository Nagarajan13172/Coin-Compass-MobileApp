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
import '../../wealth_lock/domain/wealth_lock.dart';
import '../../wealth_lock/presentation/wealth_lock_providers.dart';
import '../../wealth_lock/presentation/wealth_unlock_sheet.dart';
import '../domain/app_settings.dart';
import 'security_sheets.dart';
import 'settings_providers.dart';
import '../../../l10n/app_localizations.dart';

/// App lock (this phone), PIN lock (browser) and Net Worth lock (the account),
/// plus two-factor status.
///
/// **Three locks, three scopes, and the copy must not blur them.**
///
///   * the app lock is device-local: its PIN is chosen and checked on this
///     phone, it works with no signal, and it changes nothing on the server;
///   * the PIN lock is the web client's, stored server-side, and does nothing
///     on this phone;
///   * the Net Worth lock is one flag on the account, so it covers **both** —
///     unlocking here also reveals Net Worth in a browser.
///
/// The ordering is deliberate: the app lock goes first because it is the one
/// that actually locks the device in the owner's hand.
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
          SectionHeader(title: L.of(context).settingsSecuritySecurity),
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
            title: L.of(context).settingsSecurityAppLockPhone,
            // Only promise the fingerprint when it is actually armed. The
            // setup sheet's biometric toggle is opt-in and defaults to off, so
            // a PIN-only setup was being described as accepting a fingerprint
            // that would never be offered.
            description: lock.enabled
                ? (lock.biometricEnabled
                      ? L.of(context).settingsSecurityCoincompassAsksFingerprintPin
                      : L.of(context).settingsSecurityCoincompassAsksPinWhen)
                : L.of(context).settingsSecurityAskPinBeforeCoincompass,
            actions: lock.enabled
                ? [
                    _SmallButton(
                      label: L.of(context).settingsSecChangePinAction,
                      onPressed: () => AppLockSetupSheet.show(
                        context,
                        mode: AppLockSetupMode.change,
                      ),
                    ),
                    _SmallButton(
                      label: L.of(context).settingsSecurityLockNow,
                      onPressed: () => ref
                          .read(appLockControllerProvider.notifier)
                          .lockNow(),
                    ),
                    _SmallButton(
                      label: L.of(context).settingsSecurityTurnOff,
                      destructive: true,
                      onPressed: () => _disableAppLock(context, ref),
                    ),
                  ]
                : [
                    _SmallButton(
                      label: L.of(context).settingsSecuritySetUpAppLock,
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
                  Expanded(
                    child: Text(
                      L.of(context).settingsSecurityUnlockFingerprint,
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
            title: L.of(context).settingsSecurityPinLockWeb,
            // Still the web client's lock, and still not this app's. The app
            // lock above has its own PIN, chosen and checked on the device;
            // these two are deliberately independent, so the copy must not let
            // either one borrow the other's credit.
            description: settings.pinEnabled
                ? L.of(context).settingsSecurityDigitPinAskedWhen
                : L.of(context).settingsSecurityAskShortPinWhen,
            busy:
                pending == SettingsWrite.pin ||
                pending == SettingsWrite.disablePin,
            actions: settings.pinEnabled
                ? [
                    _SmallButton(
                      label: L.of(context).settingsSecChangePinAction,
                      onPressed: blocked
                          ? null
                          : () => PinSheet.show(context, change: true),
                    ),
                    _SmallButton(
                      label: L.of(context).settingsSecurityTurnOff,
                      destructive: true,
                      onPressed: blocked
                          ? null
                          : () => _disablePin(context, ref),
                    ),
                  ]
                : [
                    _SmallButton(
                      label: L.of(context).settingsSecSetPin,
                      onPressed: blocked
                          ? null
                          : () => PinSheet.show(context, change: false),
                    ),
                  ],
          ),
          Divider(color: c.border, height: 24),

          _WealthLockRow(settings: settings),
          Divider(color: c.border, height: 24),

          const _TwoFactorRow(),

          const SizedBox(height: 12),
          Text(
            // Four locks, four scopes, one sentence each. A reader must be
            // able to tell which covers what without guessing.
            L.of(context).settingsSecurityAppLockCoversPhone,
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
    final l = L.of(context);
    final confirmed = await AppLockConfirmSheet.show(
      context,
      title: l.settingsSecurityTurnOffAppLock,
      action: l.settingsSecurityTurnOff,
    );
    if (!confirmed) return;

    await ref.read(appLockControllerProvider.notifier).disable();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            l.settingsSecurityAppLockTurnedOff,
          ),
        ),
      );
  }

  Future<void> _disablePin(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = L.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: l.settingsSecurityTurnOffWebPin,
      // This row is the SERVER PIN — the one CoinCompass asks for in a browser.
      // The old copy said "the app will open without asking for a PIN", which
      // is false whenever the app lock (the row above) is on: turning this off
      // changes nothing about this phone. Two separate locks, two separate
      // sentences.
      message:
          l.settingsSecurityCoincompassStopAskingPin,
      confirmLabel: l.settingsSecurityTurnOff,
    );
    if (!confirmed) return;

    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .disablePin();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure ?? l.settingsSecurityPinLockTurnedOff)));
  }
}

/// The Net Worth lock row: three states, and only one of them can reach
/// `POST /auth/lock-wealth`.
///
/// | state | pill | actions |
/// |---|---|---|
/// | locked (`user.wealthLockEnabled`) | Locked | **Unlock**, and nothing else |
/// | a passcode exists, currently showing | Unlocked | Change passcode · Lock now · Turn off |
/// | no passcode | Off | Set a passcode |
///
/// Two things this fixes beyond the copy:
///
///  * **"Lock now" cannot exist without a passcode.** `POST /auth/lock-wealth`
///    takes no body, so it would succeed against an account that has never had
///    one — and if the server honours that, the owner is locked out of Net
///    Worth on the phone *and* in the browser with nothing that can open it.
///    The button renders only when [canRelock] holds, and
///    [WealthLockController.lockNow] re-checks the same condition before it
///    sends anything.
///  * **"Turn off" is no longer offered while locked.** It used to be, and it
///    fires `DELETE /settings/wealth-passcode` — so anyone holding the
///    unlocked phone could discard a passcode they did not know. The web shows
///    a non-superadmin "Unlock to manage" for exactly this reason.
class _WealthLockRow extends ConsumerWidget {
  const _WealthLockRow({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final c = context.colors;
    final pending = ref.watch(settingsWriteControllerProvider);
    final blocked = pending != null;
    final visibility = ref.watch(wealthVisibilityProvider);
    final wealthBusy = ref.watch(wealthLockControllerProvider).busy;

    final locked = visibility == WealthVisibility.locked;
    // The same provider `lockNow()` re-checks, so the button and the guard
    // behind it can never disagree about whether a passcode exists.
    final hasPasscode = ref.watch(wealthPasscodeExistsProvider);
    final canLockAgain = ref.watch(canRelockProvider);
    final superadmin = ref.watch(currentUserProvider)?.mode == 'superadmin';

    // SCOPE, stated correctly: the PASSCODE is on the account, but unlocking is
    // per sign-in. `POST /auth/unlock-wealth` elevates the CURRENT SESSION —
    // the web's own menu proves it, offering "Hide" only when
    // `wealthLockEnabled && mode == 'superadmin'`, a pair that could not occur
    // if unlocking cleared the account flag. So unlocking here does NOT reveal
    // anything in a browser, and locking here does NOT hide anything there.
    // Earlier copy claimed both. Promising protection the app cannot deliver is
    // worse than promising none.
    final description = locked
        ? l.settingsSecurityWealthLockedDescription
        : hasPasscode
        ? l.settingsSecurityWealthShowingDescription
        : l.settingsSecurityHideNetWorthSavings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SecurityRow(
          icon: LucideIcons.shieldCheck,
          enabled: hasPasscode,
          // A superadmin's figures stay visible even with the lock armed, so
          // "Unlocked" would be a lie about the account. Say the lock is on
          // and let the line below explain why they can still see it.
          statusLabel: locked
              ? l.settingsSecurityLocked
              : superadmin && settings.wealthLockEnabled
              ? l.settingsSecurityOn
              : hasPasscode
              ? l.settingsSecurityUnlocked
              : l.settingsSecurityOff,
          title: l.settingsSecurityNetWorthLock,
          description: description,
          busy:
              wealthBusy ||
              pending == SettingsWrite.wealthPasscode ||
              pending == SettingsWrite.disableWealthPasscode,
          actions: locked
              // Mirrors the web, which offers a non-superadmin nothing but
              // "Unlock to manage" here.
              ? [
                  _SmallButton(
                    label: l.settingsSecurityUnlock,
                    onPressed: wealthBusy
                        ? null
                        : () => unlockWealthFlow(context),
                  ),
                ]
              : hasPasscode
              ? [
                  _SmallButton(
                    label: l.settingsSecChangePasscodeAction,
                    onPressed: blocked
                        ? null
                        : () => WealthPasscodeSheet.show(context, change: true),
                  ),
                  if (canLockAgain)
                    _SmallButton(
                      label: l.settingsSecurityLockNow,
                      onPressed: blocked || wealthBusy
                          ? null
                          : () => _lockNow(context, ref),
                    ),
                  _SmallButton(
                    label: l.settingsSecurityTurnOff,
                    destructive: true,
                    onPressed: blocked
                        ? null
                        : () => _disableWealthLock(context, ref),
                  ),
                ]
              : [
                  _SmallButton(
                    label: l.settingsSecSetPasscode,
                    onPressed: blocked
                        ? null
                        : () =>
                              WealthPasscodeSheet.show(context, change: false),
                  ),
                ],
        ),
        if (superadmin && settings.wealthLockEnabled)
          Padding(
            padding: const EdgeInsets.only(left: 50, top: 6),
            child: Text(
              // `mode == 'superadmin'` alongside `wealthLockEnabled` is the
              // ORDINARY state after a successful unlock — it marks this
              // session as elevated, not the account as an admin one. Calling
              // it "superadmin mode" alarmed the owner about a role they do
              // not have, in what is the normal post-unlock case.
              l.settingsSecurityUnlockedSignNetWorth,
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
          ),
      ],
    );
  }

  /// The app's **only** call site for `POST /auth/lock-wealth`.
  ///
  /// Reachable only from the "Lock now" button, which only renders when a
  /// passcode is known to exist. [WealthLockController.lockNow] checks the
  /// same thing again and refuses if it does not hold.
  Future<void> _lockNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = L.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: l.settingsSecurityLockNetWorthAgain,
      message:
          l.settingsSecurityWealthRelockWarning,
      confirmLabel: l.settingsSecurityLock,
      destructive: false,
    );
    if (!confirmed) return;

    final failure = await ref
        .read(wealthLockControllerProvider.notifier)
        .lockNow();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failure ?? l.settingsSecurityNetWorthLockedApp,
          ),
        ),
      );
  }

  Future<void> _disableWealthLock(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = L.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: l.settingsSecurityTurnOffNetWorth,
      message:
          l.settingsSecurityWealthTurnOffWarning,
      confirmLabel: l.settingsSecurityTurnOff,
    );
    if (!confirmed) return;

    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .disableWealthPasscode();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(failure ?? l.settingsSecurityNetWorthLockTurned)),
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
    final l = L.of(context);
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
                        label:
                            statusLabel ??
                            (enabled
                                ? l.settingsSecurityOn
                                : l.settingsSecurityOff),
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
    final l = L.of(context);
    final status = ref.watch(twoFactorStatusProvider);

    return switch (status) {
      AsyncData(:final value) => _SecurityRow(
        icon: LucideIcons.smartphone,
        enabled: value.enabled,
        title: l.authTwoFactorTitle,
        description: value.enabled
            ? l.settingsSecurityTwoFactorOn(
                value.emailFallback
                    ? l.settingsSecurityEmailFallbackOn
                    : '',
                value.backupCodesRemaining,
              )
            : l.settingsSecuritySetUpTurnFrom,
      ),
      AsyncError() => _SecurityRow(
        icon: LucideIcons.smartphone,
        enabled: false,
        statusLabel: l.settingsSecurityUnknown,
        title: l.authTwoFactorTitle,
        description: l.settingsSecurityCouldntCheckStatusJust,
        actions: [
          _SmallButton(
            label: l.actionRetry,
            onPressed: () => ref.invalidate(twoFactorStatusProvider),
          ),
        ],
      ),
      _ => _SecurityRow(
        icon: LucideIcons.smartphone,
        enabled: false,
        statusLabel: '…',
        title: l.authTwoFactorTitle,
        description: l.settingsSecurityChecking,
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
              L.of(context).settingsSecurityAppLockTurnedItself,
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
