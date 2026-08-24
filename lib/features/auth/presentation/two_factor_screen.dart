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

class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _code = TextEditingController();
  bool _useBackupCode = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref
        .read(authControllerProvider.notifier)
        .verifyTwoFactor(_code.text.trim(), backupCode: _useBackupCode);
  }

  Future<void> _emailCode() async {
    try {
      await ref.read(authRepositoryProvider).sendTwoFactorEmail();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('We emailed you a code.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the email. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(authControllerProvider);
    final error = state.error;

    return AuthScaffold(
      icon: LucideIcons.shieldCheck,
      title: 'Two-factor authentication',
      subtitle: _useBackupCode
          ? 'Enter one of your saved backup codes'
          : 'Enter the 6-digit code from your authenticator app',
      onBack: () => context.go('/login'),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null && !error.isValidation)
              AuthErrorBanner(message: error.message),
            AppTextField(
              label: _useBackupCode ? 'Backup code' : 'Authentication code',
              controller: _code,
              autofocus: true,
              keyboardType: _useBackupCode
                  ? TextInputType.text
                  : TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              errorText: error?.fieldError('code'),
              inputFormatters: _useBackupCode
                  ? null
                  : [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
            ),
            const SizedBox(height: 20),
            AppButton(label: 'Verify', busy: state.busy, onPressed: _submit),
            const SizedBox(height: 10),
            AppButton(
              label: _useBackupCode
                  ? 'Use an authenticator code instead'
                  : 'Use a backup code instead',
              variant: AppButtonVariant.text,
              onPressed: () => setState(() {
                _useBackupCode = !_useBackupCode;
                _code.clear();
              }),
            ),
            if (state.twoFactorEmailFallback)
              AppButton(
                label: 'Email me a code',
                variant: AppButtonVariant.text,
                onPressed: _emailCode,
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
