import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/auth_repository.dart';
import 'auth_providers.dart';
import 'widgets/auth_scaffold.dart';

/// Second-factor challenge.
///
/// The factor is chosen here and sent to the server as `method` — the wire
/// contract is `POST /auth/2fa/verify {method, code}` with `method` in
/// `totp | backup | email`. Verified by reading the deployed web bundle
/// (assets/index-BCZVpAqp.js): its 2FA page keeps the same three-way state
/// (`c` = "totp" | "backup" | "email"), posts `{method: c, code: E.trim()}`,
/// only offers the email factor when the challenge's `methods` array includes
/// "email", and hides the code field behind an "email me a code" button until
/// that mail has been sent.
///
/// Unverified: none of this could be exercised against the live deployment —
/// the test account has 2FA disabled, so no real challenge, no real
/// verification response and no error shape from this endpoint was observed.
/// The web also reads a pending challenge from `GET /auth/2fa/pending` to
/// survive a page reload; the mobile flow does not need it, because the
/// challenge lives in AuthState and a cold start goes back to /login.
class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen>
    with AuthErrorReset {
  static const _totp = 'totp';
  static const _backup = 'backup';
  static const _email = 'email';

  final _code = TextEditingController();

  /// The factor being verified; goes out as the `method` field.
  String _method = _totp;
  bool _emailSent = false;
  bool _sendingEmail = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref
        .read(authControllerProvider.notifier)
        .verifyTwoFactor(_code.text.trim(), method: _method);
  }

  void _selectMethod(String method) {
    setState(() {
      _method = method;
      _code.clear();
    });
    ref.read(authControllerProvider.notifier).clearError();
  }

  Future<void> _sendEmailCode() async {
    if (_sendingEmail) return;
    setState(() => _sendingEmail = true);
    try {
      await ref.read(authRepositoryProvider).sendTwoFactorEmail();
      if (!mounted) return;
      setState(() {
        _sendingEmail = false;
        _emailSent = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('We emailed you a code.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sendingEmail = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the email. Try again.')),
      );
    }
  }

  String get _subtitle => switch (_method) {
    _backup => 'Enter one of your saved backup codes',
    _email => _emailSent
        ? 'Enter the 6-digit code we emailed you'
        : "We'll email you a 6-digit code",
    _ => 'Enter the 6-digit code from your authenticator app',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(authControllerProvider);
    final error = state.error;
    final isBackup = _method == _backup;
    final isEmail = _method == _email;
    final emailOffered = state.twoFactorEmailFallback;

    return AuthScaffold(
      icon: LucideIcons.shieldCheck,
      title: 'Two-factor authentication',
      subtitle: _subtitle,
      onBack: () {
        clearAuthError();
        context.go('/login');
      },
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null && !error.isValidation)
              AuthErrorBanner(message: error.message),
            if (isEmail && !_emailSent)
              AppButton(
                label: 'Email me a code',
                busy: _sendingEmail,
                onPressed: _sendEmailCode,
              )
            else ...[
              AppTextField(
                label: isBackup ? 'Backup code' : 'Authentication code',
                controller: _code,
                autofocus: true,
                keyboardType: isBackup
                    ? TextInputType.text
                    : TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                errorText: error?.fieldError('code'),
                inputFormatters: isBackup
                    ? [LengthLimitingTextInputFormatter(12)]
                    : [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
              ),
              const SizedBox(height: 20),
              AppButton(label: 'Verify', busy: state.busy, onPressed: _submit),
              if (isEmail)
                AppButton(
                  label: 'Resend the code',
                  variant: AppButtonVariant.text,
                  onPressed: _sendEmailCode,
                ),
            ],
            const SizedBox(height: 10),
            if (_method != _totp)
              AppButton(
                label: 'Use an authenticator code instead',
                variant: AppButtonVariant.text,
                onPressed: () => _selectMethod(_totp),
              ),
            if (emailOffered && !isEmail)
              AppButton(
                label: 'Email me a code instead',
                variant: AppButtonVariant.text,
                onPressed: () => _selectMethod(_email),
              ),
            if (!isBackup)
              AppButton(
                label: 'Use a backup code instead',
                variant: AppButtonVariant.text,
                onPressed: () => _selectMethod(_backup),
              ),
            const SizedBox(height: 4),
            Text(
              'Lost access to your authenticator? Use a backup code, or reset '
              'two-factor from the web app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
