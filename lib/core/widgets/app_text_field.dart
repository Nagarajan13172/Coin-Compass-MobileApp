import '../ui.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Labelled field matching the web app's form rows: a 14sp label above the
/// input, optional trailing action on the label row (e.g. "Forgot password?").
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.suffix,
    this.prefix,
    this.labelAction,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.inputFormatters,
    this.autofillHints,
  });

  final String? label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final Widget? prefix;
  final Widget? labelAction;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null || labelAction != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const Spacer(),
                ?labelAction,
              ],
            ),
          ),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          autofocus: autofocus,
          maxLines: obscure ? 1 : maxLines,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          style: TextStyle(fontSize: 15.5, color: c.foreground),
          decoration: InputDecoration(
            // Phase 7.1 — InputDecoration renders these itself, so the app's
            // translating `Text` never sees them. Translated explicitly, which
            // is the whole reason `tr` exists.
            hintText: tr(context, hint),
            errorText: errorText == null ? null : tr(context, errorText),
            prefixIcon: prefix,
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}
