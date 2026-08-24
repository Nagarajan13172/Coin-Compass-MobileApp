import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/money.dart';

/// Renders an amount with the right sign and semantic colour.
/// Income is `income`, expense is `expense`, anything else inherits.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.tone = MoneyTone.neutral,
    this.signed = false,
    this.compact = false,
    this.style,
    this.symbol = Money.rupee,
  });

  final num amount;
  final MoneyTone tone;
  final bool signed;
  final bool compact;
  final TextStyle? style;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (tone) {
      MoneyTone.income => c.income,
      MoneyTone.expense => c.expense,
      MoneyTone.auto => amount < 0 ? c.expense : c.income,
      MoneyTone.muted => c.mutedForeground,
      MoneyTone.neutral => null,
    };

    final text = compact
        ? Money.compact(amount, symbol: symbol)
        : Money.format(amount, symbol: symbol, signed: signed);

    return Text(
      text,
      style: (style ?? DefaultTextStyle.of(context).style).copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

enum MoneyTone { neutral, income, expense, auto, muted }
