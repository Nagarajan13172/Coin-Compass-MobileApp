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

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen>
    with AuthErrorReset {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _confirmError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _confirmError = null);
    if (_password.text != _confirm.text) {
      setState(() => _confirmError = 'Passwords do not match');
      return;
    }
    await ref
        .read(authControllerProvider.notifier)
        .signUp(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(authControllerProvider);
    final error = state.error;

    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Start tracking your money',
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
              label: 'Name',
              controller: _name,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              errorText: error?.fieldError('name'),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              errorText: error?.fieldError('email'),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Password',
              controller: _password,
              obscure: _obscure,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              errorText: error?.fieldError('password'),
              suffix: IconButton(
                icon: Icon(
                  _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                  size: 18,
                  color: c.mutedForeground,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Confirm password',
              controller: _confirm,
              obscure: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              errorText: _confirmError,
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Create account',
              busy: state.busy,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),
            // Wrap, not Row: at large system font scales the prompt and the
            // link no longer fit on one 280dp line, and a Row would overflow.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: TextStyle(fontSize: 14, color: c.mutedForeground),
                ),
                GestureDetector(
                  onTap: () {
                    clearAuthError();
                    context.go('/login');
                  },
                  child: Text(
                    'Sign in',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
