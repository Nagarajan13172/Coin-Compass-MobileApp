import '../ui.dart';

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
    this.compactAbove,
    this.style,
    this.symbol = Money.rupee,
  });

  final num amount;
  final MoneyTone tone;
  final bool signed;

  /// Always render as `₹12.35Cr` rather than `₹12,34,56,789`.
  final bool compact;

  /// Render compactly only once the amount reaches this magnitude. Dense rows
  /// pass [Money.crore]: a nine-figure figure otherwise grows the amount
  /// column until the label beside it has nothing left to occupy.
  final num? compactAbove;

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

    // `compactAbove` is [Money.dense] — same rule, one implementation, so a
    // widget and a string interpolation of the same amount cannot disagree.
    final threshold = compactAbove;
    final text = compact
        ? Money.compact(amount, symbol: symbol, signed: signed)
        : threshold == null
        ? Money.format(amount, symbol: symbol, signed: signed)
        : Money.dense(
            amount,
            threshold: threshold,
            symbol: symbol,
            signed: signed,
          );

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
