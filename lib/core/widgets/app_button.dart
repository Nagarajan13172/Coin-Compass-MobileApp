import 'package:flutter/material.dart';

/// Primary / outlined button with a built-in busy state, so callers don't
/// re-implement "disable and swap in a spinner" on every form.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    final handler = busy ? null : onPressed;
    final button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: handler,
        child: child,
      ),
      AppButtonVariant.outlined => OutlinedButton(
        onPressed: handler,
        child: child,
      ),
      AppButtonVariant.text => TextButton(onPressed: handler, child: child),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

enum AppButtonVariant { primary, outlined, text }
