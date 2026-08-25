import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import 'auth_providers.dart';
import 'widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen>
    with AuthErrorReset {
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .forgotPassword(_email.text.trim());
    if (!mounted) return;
    if (ok) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(authControllerProvider);
    final error = state.error;

    if (_sent) {
      return AuthScaffold(
        icon: LucideIcons.mailCheck,
        title: 'Check your inbox',
        subtitle: 'We sent a reset link to ${_email.text.trim()}',
        onBack: () {
          clearAuthError();
          context.pop();
        },
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Open the link on this device to choose a new password. '
                'The link expires shortly for your security.',
                style: TextStyle(fontSize: 14.5, color: c.mutedForeground),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Back to sign in',
                onPressed: () {
                  clearAuthError();
                  context.go('/login');
                },
              ),
            ],
          ),
        ),
      );
    }

    return AuthScaffold(
      icon: LucideIcons.keyRound,
      title: 'Reset your password',
      subtitle: "We'll email you a reset link",
      onBack: () {
        // Popping back to a screen that never unmounted, so clear the shared
        // auth error here rather than relying on the other screen's initState.
        clearAuthError();
        context.pop();
      },
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null && !error.isValidation)
              AuthErrorBanner(message: error.message),
            AppTextField(
              label: 'Email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              autofillHints: const [AutofillHints.email],
              errorText: error?.fieldError('email'),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Send reset link',
              busy: state.busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
