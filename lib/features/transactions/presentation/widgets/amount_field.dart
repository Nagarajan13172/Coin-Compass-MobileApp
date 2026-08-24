import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';

/// Keeps an amount field to digits plus a single decimal point, so the value
/// can always be handed to [parseAmount] without a try/catch.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter({this.decimals = 2});

  /// Digits allowed after the point. The backend stores whole rupees, but
  /// paise-level entry is accepted and sent through untouched.
  final int decimals;

  static final RegExp _shape = RegExp(r'^\d*\.?\d*$');

  /// Grouping separators, spaces and the rupee sign — what a figure copied out
  /// of the web app carries with it.
  static final RegExp _noise = RegExp(r'[,\s\u20B9]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    // Sanitise before judging. This used to test the raw text, so pasting
    // "₹50,00,000" copied out of the web app failed on the first comma and the
    // whole paste was dropped — the field simply refused to change, with no
    // hint why. The web's own box accepts it.
    final cleaned = text.replaceAll(_noise, '');
    if (cleaned.isEmpty) return oldValue;
    // Rejecting by returning the old value keeps the caret where it was.
    if (!_shape.hasMatch(cleaned)) return oldValue;
    final point = cleaned.indexOf('.');
    if (point >= 0 && cleaned.length - point - 1 > decimals) return oldValue;
    if (cleaned == text) return newValue;

    // Something was stripped, so the text shrank. Hold the caret the same
    // distance from the END — after a paste that lands it at the end, which is
    // where the user expects it.
    final fromEnd = text.length - newValue.selection.baseOffset;
    final offset = (cleaned.length - fromEnd).clamp(0, cleaned.length);
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Parses what [AmountField] produced. Returns null when there is no usable
/// number yet ('', '.', '12.' while mid-typing).
num? parseAmount(String raw) {
  var text = raw.trim();
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  if (text.isEmpty || text == '.') return null;
  final value = num.tryParse(text);
  if (value == null) return null;
  // Whole rupees go out as ints so the payload matches every other row.
  return value % 1 == 0 ? value.toInt() : value;
}

/// The hero input of the transaction sheet: one big centred number, prefixed
/// with the wallet's currency symbol and tinted by the selected type
/// (expense / income / transfer).
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.symbol,
    required this.tint,
    this.errorText,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;

  /// Base-currency symbol, from `currencySymbolProvider`.
  final String symbol;

  /// `expense` / `income` / `primary` token for the selected type.
  final Color tint;

  final String? errorText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasError = errorText != null;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      borderColor: hasError ? c.destructive : tint.withValues(alpha: 0.30),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [tint.withValues(alpha: 0.10), tint.withValues(alpha: 0.03)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                symbol,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: tint.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(width: 6),
              // IntrinsicWidth lets the field hug its digits so the symbol and
              // the number read as one centred unit.
              Flexible(
                child: IntrinsicWidth(
                  child: TextField(
                    controller: controller,
                    autofocus: autofocus,
                    onChanged: onChanged,
                    textAlign: TextAlign.center,
                    cursorColor: tint,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [AmountInputFormatter()],
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: tint,
                      height: 1.15,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      hintText: '0',
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      hintStyle: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: tint.withValues(alpha: 0.30),
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (hasError) ...[
            const SizedBox(height: 8),
            Text(
              errorText!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: c.destructive),
            ),
          ],
        ],
      ),
    );
  }
}
