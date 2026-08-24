import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import 'auth_providers.dart';
import 'widgets/auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _staySignedIn = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = ref.read(authControllerProvider.notifier);
    final ok = await auth.signIn(
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    if (!ok &&
        ref.read(authControllerProvider).status == AuthStatus.needsTwoFactor) {
      context.go('/login/2fa');
    }
    // On success the router's redirect moves us to the dashboard.
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(authControllerProvider);
    final error = state.error;

    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to your CoinCompass',
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
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              errorText: error?.fieldError('email'),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Password',
              controller: _password,
              obscure: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              autofillHints: const [AutofillHints.password],
              errorText: error?.fieldError('password'),
              labelAction: GestureDetector(
                onTap: () => context.push('/forgot-password'),
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ),
              suffix: IconButton(
                icon: Icon(
                  _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                  size: 18,
                  color: c.mutedForeground,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Stay signed in',
                    style: TextStyle(fontSize: 15, color: c.mutedForeground),
                  ),
                ),
                Switch(
                  value: _staySignedIn,
                  onChanged: (v) => setState(() => _staySignedIn = v),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppButton(label: 'Sign in', busy: state.busy, onPressed: _submit),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Divider(color: c.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or continue with',
                    style: TextStyle(fontSize: 13, color: c.mutedForeground),
                  ),
                ),
                Expanded(child: Divider(color: c.border)),
              ],
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'Google',
              variant: AppButtonVariant.outlined,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Google sign-in is coming soon on mobile.'),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: TextStyle(fontSize: 14, color: c.mutedForeground),
                ),
                GestureDetector(
                  onTap: () => context.push('/signup'),
                  child: Text(
                    'Sign up',
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
