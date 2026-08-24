import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import 'wealth_lock_providers.dart';

/// What the sheet says when there is no way to reach the server.
///
/// This is the sharpest difference from the app lock in `features/lock/`, and
/// it is stated rather than hidden: that lock never touches the network and
/// works in aeroplane mode; this one cannot work at all without a connection,
/// because the passcode only exists server-side. Inventing a local unlock would
/// let this phone and the browser disagree about whether the owner's net worth
/// is visible, which is the one failure the lock exists to prevent. So the
/// sheet says so, instead of offering a field that cannot possibly work.
const String kOfflineUnlockMessage =
    'The wealth passcode is checked by the server, so Net Worth cannot be '
    'unlocked while this phone is offline. Nothing is stored on this phone '
    'that could unlock it.';

/// Enter the wealth passcode and `POST /auth/unlock-wealth`.
///
/// ## Why this is not 6.1's keypad
///
/// The brief asked for the app lock's `PinKeypad` to be reused. It cannot be,
/// and reusing it would be a correctness bug: the app lock's PIN is 4–8
/// **digits**, while the wealth passcode is 4–32 characters of free text —
/// letters, digits and symbols — validated that way by the web and by
/// `SettingsRepository.setWealthPasscode`. A 3×4 digit pad cannot enter most
/// valid passcodes. What *is* shared is the language: the same Show/Hide label
/// action the passcode-setting sheet uses, and failure copy that names who is
/// refusing.
///
/// There is also no local cooldown, deliberately. 6.1 escalates on consecutive
/// wrong PINs because nothing else can — the check is on the device. Here every
/// attempt is already a server round trip behind the auth limiter (10 requests
/// / 900s), so a second cooldown in the client would only lock the owner out
/// earlier than the server does, and would lie about who was refusing.
class WealthUnlockSheet extends ConsumerStatefulWidget {
  const WealthUnlockSheet._();

  /// Opens the sheet. Resolves true when the lock was actually opened.
  static Future<bool> show(BuildContext context) async {
    final unlocked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const WealthUnlockSheet._(),
    );
    return unlocked ?? false;
  }

  @override
  ConsumerState<WealthUnlockSheet> createState() => _WealthUnlockSheetState();
}

class _WealthUnlockSheetState extends ConsumerState<WealthUnlockSheet> {
  final _passcode = TextEditingController();
  bool _reveal = false;

  @override
  void initState() {
    super.initState();
    // Post-frame: the preflight writes to a provider, and mutating one during
    // the first build throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(wealthLockControllerProvider.notifier).preflight();
    });
  }

  @override
  void dispose() {
    _passcode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await ref
        .read(wealthLockControllerProvider.notifier)
        .unlock(_passcode.text);
    if (!ok || !mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(wealthLockControllerProvider);

    return switch (state.phase) {
      WealthUnlockPhase.checking => FormSheetScaffold(
        title: 'Unlock Net Worth',
        submitLabel: 'Unlock',
        submitting: true,
        onSubmit: null,
        children: [
          Text(
            'Checking whether Net Worth is unlocked…',
            style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
          ),
        ],
      ),
      // The preflight found the lock already off — it was never on, or a
      // browser opened it while this sheet was loading. Say so rather than ask
      // for a passcode that would not be checked against anything. Not an
      // auto-dismiss: a sheet that vanishes on its own reads as a crash.
      WealthUnlockPhase.alreadyUnlocked => FormSheetScaffold(
        title: 'Unlock Net Worth',
        submitLabel: 'Close',
        onSubmit: () => Navigator.of(context).pop(false),
        children: [
          Text(
            'Net Worth is already unlocked. Nothing to enter.',
            style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
          ),
        ],
      ),
      // Two different failures shared one panel: no connection, and a session
      // the server has stopped accepting. The second was shown with a Wi-Fi-off
      // icon and a "Try again" that could only repeat the same 401, under the
      // instruction "please sign in again" — which this sheet gave no way to
      // follow. Signing in again is a sign-OUT first, so offer it.
      WealthUnlockPhase.offline => FormSheetScaffold(
        title: state.expiredSession
            ? 'Signed out'
            : (state.error == null ? 'No connection' : "Can't unlock"),
        submitLabel: state.expiredSession ? 'Sign out' : 'Try again',
        submitting: state.busy,
        onSubmit: () async {
          final notifier = ref.read(wealthLockControllerProvider.notifier);
          if (!state.expiredSession) {
            await notifier.preflight();
            return;
          }
          await notifier.signOut();
          if (context.mounted) Navigator.of(context).pop(false);
        },
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                state.expiredSession
                    ? LucideIcons.logOut
                    : LucideIcons.wifiOff,
                size: 18,
                color: c.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.error ?? kOfflineUnlockMessage,
                  style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
                ),
              ),
            ],
          ),
        ],
      ),
      WealthUnlockPhase.ready => FormSheetScaffold(
        title: 'Unlock Net Worth',
        submitLabel: state.busy ? 'Unlocking…' : 'Unlock',
        submitting: state.busy,
        onSubmit: _submit,
        formError: state.error,
        // Scope, stated where the owner is about to act on it. Unlocking is
        // PER SIGN-IN: `/auth/unlock-wealth` elevates this session, it does not
        // clear the account flag. This footnote used to claim a browser would
        // also reveal — promising protection the app cannot deliver, and the
        // inverse of the truth.
        footnote:
            'Unlocking reveals Net Worth, Savings & Investments and Stocks in '
            'this app until you lock them again. Anywhere else you are signed '
            'in stays as it is.',
        children: [
          Text(
            'Enter your wealth passcode. It is checked by the server, so '
            'unlocking needs a connection.',
            style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Wealth passcode',
            controller: _passcode,
            obscure: !_reveal,
            autofocus: true,
            enabled: !state.busy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => state.busy ? null : _submit(),
            // Found on the device: after a rejected attempt, "That passcode
            // didn't match." stayed on screen the whole time the owner was
            // typing the next one — a red error about a passcode they had
            // already replaced. The controller has always had `clearError()`;
            // nothing called it. Guarded so an untouched field does not
            // rebuild the sheet on every keystroke.
            onChanged: (_) {
              if (state.error == null) return;
              ref.read(wealthLockControllerProvider.notifier).clearError();
            },
            inputFormatters: [LengthLimitingTextInputFormatter(32)],
            labelAction: TextButton(
              onPressed: state.busy
                  ? null
                  : () => setState(() => _reveal = !_reveal),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(_reveal ? 'Hide' : 'Show'),
            ),
          ),
        ],
      ),
    };
  }
}

/// Opens the unlock sheet and reports the outcome in a SnackBar.
///
/// Shared by the three places that offer an unlock — the Settings row, the
/// "More" sheet and the locked-screen panel — so the wording of the
/// consequence cannot drift between them.
Future<bool> unlockWealthFlow(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final unlocked = await WealthUnlockSheet.show(context);
  if (unlocked) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Net Worth unlocked in this app until you lock it again.',
          ),
        ),
      );
  }
  return unlocked;
}
