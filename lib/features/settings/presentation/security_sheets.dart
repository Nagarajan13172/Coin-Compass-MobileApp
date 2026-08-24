import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import 'settings_providers.dart';

/// Set or change the app's PIN lock.
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
      setState(() => _error = 'The PIN must be 4 to 8 digits.');
      return;
    }
    if (pin != _confirm.text) {
      setState(() => _error = "The two PINs don't match.");
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
      title: widget.change ? 'Change your PIN' : 'Set a PIN',
      submitLabel: widget.change ? 'Change PIN' : 'Turn on PIN lock',
      submitting: busy,
      onSubmit: _submit,
      formError: _error,
      // Honest copy. The PIN is stored server-side and currently gates the
      // CoinCompass *web* app; this app has no lock screen yet, so promising
      // "you will be asked every time the app starts" would be false on the
      // device the owner is reading it on. The gate ships in Phase 6 — when it
      // does, this wording changes with it.
      footnote:
          'Your data stays exactly as it is, and this is not your password.',
      children: [
        Text(
          'Choose 4 to 8 digits. This PIN protects CoinCompass on the web '
          'today — this app does not lock yet, so it will not ask you for it.',
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'New PIN',
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
          label: 'Confirm PIN',
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
/// ⚠️ Submitting fires `POST /settings/wealth-passcode`, which hides the Net
/// Worth and Stocks screens behind a passcode on the owner's live account.
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
      setState(() => _error = 'The passcode must be 4 to 32 characters.');
      return;
    }
    if (passcode != _confirm.text) {
      setState(() => _error = "The two passcodes don't match.");
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
      title: widget.change ? 'Change the passcode' : 'Set a passcode',
      submitLabel: widget.change ? 'Change passcode' : 'Lock Net Worth',
      submitting: busy,
      onSubmit: _submit,
      formError: _error,
      footnote:
          'Net Worth and Stocks stay hidden until this passcode is entered, '
          'once per session.',
      children: [
        Text(
          'Between 4 and 32 characters. Letters, digits and symbols all count.',
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Wealth passcode',
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
            child: Text(_reveal ? 'Hide' : 'Show'),
          ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Confirm passcode',
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
