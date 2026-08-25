import '../../../core/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../domain/lock_state.dart';
import 'lock_controller.dart';

enum AppLockSetupMode { enable, change }

/// Turns the app lock on, or changes its PIN.
///
/// **This sheet issues zero HTTP requests.** The PIN is hashed and stored on
/// the device, so the lock can be armed with no connection at all — and
/// crucially it does *not* call `POST /settings/pin`, which would arm the lock
/// on the owner's **web** client as a side effect of turning on a phone
/// feature. The two surfaces are deliberately independent.
class AppLockSetupSheet extends ConsumerStatefulWidget {
  const AppLockSetupSheet._({required this.mode});

  final AppLockSetupMode mode;

  /// Resolves true when the lock was armed or the PIN changed.
  static Future<bool> show(
    BuildContext context, {
    required AppLockSetupMode mode,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AppLockSetupSheet._(mode: mode),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<AppLockSetupSheet> createState() => _AppLockSetupSheetState();
}

class _AppLockSetupSheetState extends ConsumerState<AppLockSetupSheet> {
  final _current = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();

  static final RegExp _digits = RegExp(r'^\d{4,8}$');

  bool _biometric = false;
  bool _busy = false;
  String? _error;

  bool get _isChange => widget.mode == AppLockSetupMode.change;

  @override
  void initState() {
    super.initState();
    // Availability drives whether the fingerprint row is offered at all. It is
    // a probe, not an unlock — no prompt is shown here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(appLockControllerProvider.notifier).refreshAvailability();
      }
    });
  }

  @override
  void dispose() {
    _current.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final controller = ref.read(appLockControllerProvider.notifier);
    final pin = _pin.text;

    if (!_digits.hasMatch(pin)) {
      setState(() => _error = 'The PIN must be 4 to 8 digits.');
      return;
    }
    if (pin != _confirm.text) {
      setState(() => _error = "The two PINs don't match.");
      return;
    }

    setState(() {
      _error = null;
      _busy = true;
    });

    if (_isChange) {
      // Checked locally against the stored verifier — never over the wire.
      final ok = await controller.verifyPinLocally(_current.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'That is not your current PIN.';
        });
        return;
      }
      await controller.changePin(pin);
    } else {
      await controller.enable(pin: pin, biometric: _biometric);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// Runs one real prompt when the switch goes on, so the owner sees the
  /// fingerprint work before trusting it. Nothing is armed if it fails.
  Future<void> _toggleBiometric(bool value) async {
    if (!value) {
      setState(() => _biometric = false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(biometricGateProvider)
        .authenticate('Confirm your fingerprint for CoinCompass');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _biometric = result.isSuccess;
      _error = result.isSuccess
          ? null
          : (result.message ??
                'That did not work — you can still use your PIN.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lock = ref.watch(appLockControllerProvider);
    final canOfferBiometric =
        lock.biometricAvailability == BiometricAvailability.available;

    return FormSheetScaffold(
      title: _isChange ? 'Change your app PIN' : 'Set up the app lock',
      submitLabel: _isChange ? 'Change PIN' : 'Turn on app lock',
      submitting: _busy,
      onSubmit: _submit,
      formError: _error,
      footnote:
          'Checked on this phone, so it works with no signal. It is not your '
          'account password and it changes nothing on the web.',
      children: [
        Text(
          _isChange
              ? 'Choose 4 to 8 new digits. You will be asked for them when '
                    'CoinCompass opens on this phone.'
              : 'Choose 4 to 8 digits. CoinCompass will ask for them when it '
                    'opens on this phone, and again after 30 seconds away.',
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        if (_isChange) ...[
          AppTextField(
            label: 'Current PIN',
            controller: _current,
            obscure: true,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
          ),
          const SizedBox(height: 14),
        ],
        AppTextField(
          label: _isChange ? 'New PIN' : 'PIN',
          controller: _pin,
          obscure: true,
          autofocus: !_isChange,
          enabled: !_busy,
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
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submit(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
        ),
        if (!_isChange && canOfferBiometric) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Also unlock with your fingerprint',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Checked by Android on this phone. Your PIN always '
                      'works too.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch.adaptive(
                value: _biometric,
                onChanged: _busy ? null : _toggleBiometric,
              ),
            ],
          ),
        ],
        if (!_isChange) ...[
          const SizedBox(height: 8),
          Text(
            'While the app lock is on, CoinCompass is hidden from the '
            'app-switcher preview. On Android 12 and older, screenshots of the '
            'app are blocked too.',
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ],
      ],
    );
  }
}

/// Asks for the current app PIN (or a fingerprint) before a change that would
/// weaken the lock — turning it off, mainly.
///
/// A lock that anyone holding the unlocked phone can switch off from Settings
/// is not a lock. Local check only; no network.
class AppLockConfirmSheet extends ConsumerStatefulWidget {
  const AppLockConfirmSheet._({required this.title, required this.action});

  final String title;
  final String action;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String action,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AppLockConfirmSheet._(title: title, action: action),
    );
    return ok ?? false;
  }

  @override
  ConsumerState<AppLockConfirmSheet> createState() =>
      _AppLockConfirmSheetState();
}

class _AppLockConfirmSheetState extends ConsumerState<AppLockConfirmSheet> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(appLockControllerProvider.notifier)
        .verifyPinLocally(_pin.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'That PIN is not right.';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _useBiometric() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(biometricGateProvider)
        .authenticate('Confirm it is you');
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lock = ref.watch(appLockControllerProvider);

    return FormSheetScaffold(
      title: widget.title,
      submitLabel: widget.action,
      submitting: _busy,
      onSubmit: _submit,
      formError: _error,
      children: [
        Text(
          'Enter your app PIN to confirm.',
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'App PIN',
          controller: _pin,
          obscure: true,
          autofocus: true,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submit(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
        ),
        if (lock.biometricOffered) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _useBiometric,
              child: const Text('Use your fingerprint instead'),
            ),
          ),
        ],
      ],
    );
  }
}
