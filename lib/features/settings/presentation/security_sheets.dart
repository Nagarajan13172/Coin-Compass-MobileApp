import '../../../core/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import 'settings_providers.dart';
import '../../../l10n/app_localizations.dart';

/// Set or change the **web** client's PIN lock.
///
/// This is not the phone's lock. The app lock is a separate PIN, chosen and
/// checked on the device (see `features/lock/`), and the two are deliberately
/// independent: arming one must not arm the other.
///
/// The web asks for the new PIN twice and nothing else — there is no
/// "current PIN" field even in change mode, because the session is already
/// unlocked. Same rules as the deployed client: digits only, 4–8 of them, both
/// fields must match.
///
/// ⚠️ Submitting fires `POST /settings/pin`, which arms a lock screen on the
/// owner's real device. Nothing in this project may submit it on their behalf.
class PinSheet extends ConsumerStatefulWidget {
  const PinSheet._({required this.change});

  final bool change;

  /// Resolves true when a PIN was actually set.
  static Future<bool> show(BuildContext context, {required bool change}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PinSheet._(change: change),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends ConsumerState<PinSheet> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  static final RegExp _digits = RegExp(r'^\d{4,8}$');

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pin.text;
    if (!_digits.hasMatch(pin)) {
      setState(() => _error = L.of(context).settingsSecPinMustDigits);
      return;
    }
    if (pin != _confirm.text) {
      setState(() => _error = L.of(context).settingsSecTwoPinsDontMatch);
      return;
    }
    setState(() => _error = null);

    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .setPin(pin);
    if (!mounted) return;
    if (failure != null) {
      setState(() => _error = failure);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy =
        ref.watch(settingsWriteControllerProvider) == SettingsWrite.pin;

    return FormSheetScaffold(
      title: widget.change ? L.of(context).settingsSecChangePin : L.of(context).settingsSecSetPin,
      submitLabel: widget.change ? L.of(context).settingsSecChangePinAction : L.of(context).settingsSecTurnPinLock,
      submitting: busy,
      onSubmit: _submit,
      formError: _error,
      // Honest copy. This PIN is stored server-side and gates the CoinCompass
      // *web* client. The phone has its own lock now, with its own PIN — so the
      // copy has to say which surface this one covers, and point at the other.
      footnote:
          L.of(context).settingsSecDataStaysExactlyAs,
      children: [
        Text(
          L.of(context).settingsSecChooseDigitsPinProtects,
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: L.of(context).settingsSecNewPin,
          controller: _pin,
          obscure: true,
          autofocus: true,
          enabled: !busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: L.of(context).settingsSecConfirmPin,
          controller: _confirm,
          obscure: true,
          enabled: !busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => busy ? null : _submit(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
        ),
      ],
    );
  }
}

/// Set or change the Net Worth passcode.
///
/// Unlike the PIN this one is free text, 4–32 characters, matching the web's
/// own validation. Entered twice, no current-passcode field.
///
/// ⚠️ Submitting fires `POST /settings/wealth-passcode`, which hides Net
/// Worth, Savings & Investments and Stocks behind a passcode on the owner's
/// live account — in this app and in a browser.
class WealthPasscodeSheet extends ConsumerStatefulWidget {
  const WealthPasscodeSheet._({required this.change});

  final bool change;

  static Future<bool> show(BuildContext context, {required bool change}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WealthPasscodeSheet._(change: change),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<WealthPasscodeSheet> createState() =>
      _WealthPasscodeSheetState();
}

class _WealthPasscodeSheetState extends ConsumerState<WealthPasscodeSheet> {
  final _passcode = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _reveal = false;

  @override
  void dispose() {
    _passcode.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final passcode = _passcode.text;
    if (passcode.length < 4 || passcode.length > 32) {
      setState(() => _error = L.of(context).settingsSecPasscodeMustCharacters);
      return;
    }
    if (passcode != _confirm.text) {
      setState(() => _error = L.of(context).settingsSecTwoPasscodesDontMatch);
      return;
    }
    setState(() => _error = null);

    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .setWealthPasscode(passcode);
    if (!mounted) return;
    if (failure != null) {
      setState(() => _error = failure);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy =
        ref.watch(settingsWriteControllerProvider) ==
        SettingsWrite.wealthPasscode;

    return FormSheetScaffold(
      title: widget.change ? L.of(context).settingsSecChangePasscode : L.of(context).settingsSecSetPasscode,
      submitLabel: widget.change ? L.of(context).settingsSecChangePasscodeAction : L.of(context).settingsSecLockNetWorth,
      submitting: busy,
      onSubmit: _submit,
      formError: _error,
      // Scope, and the consequence of forgetting. The passcode lives on the
      // account, but unlocking is per sign-in — `/auth/unlock-wealth` elevates
      // the current session rather than clearing the account flag. And a
      // forgotten passcode is a real dead end in this app: while locked the
      // Settings row offers only "Unlock", so there is no "clear it" to reach.
      // Saying so before they choose one is the whole fix.
      footnote:
          L.of(context).settingsSecNetWorthSavingsInvestments,
      children: [
        Text(
          L.of(context).settingsSecBetweenCharactersLettersDigits,
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: L.of(context).settingsSecWealthPasscode,
          controller: _passcode,
          obscure: !_reveal,
          autofocus: true,
          enabled: !busy,
          textInputAction: TextInputAction.next,
          inputFormatters: [LengthLimitingTextInputFormatter(32)],
          labelAction: TextButton(
            onPressed: busy ? null : () => setState(() => _reveal = !_reveal),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_reveal ? L.of(context).settingsSecHide : L.of(context).settingsSecShow),
          ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: L.of(context).settingsSecConfirmPasscode,
          controller: _confirm,
          obscure: !_reveal,
          enabled: !busy,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => busy ? null : _submit(),
          inputFormatters: [LengthLimitingTextInputFormatter(32)],
        ),
      ],
    );
  }
}
