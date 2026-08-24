import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/money_text.dart';
import '../networth_providers.dart';

/// Where the headline figure comes from: the three asset components the
/// snapshot carries (`accountsTotal`, `holdingsTotal`, `stocksTotal`) against
/// the single liability figure.
///
/// Every share is measured against the **gross** — assets plus liabilities,
/// both as magnitudes — so one denominator serves both halves and the bars can
/// be compared across the divide. A component can legitimately be negative (an
/// overdrawn account pulled the recorded `accountsTotal` to −₹7.5L), so a row
/// draws its bar from the magnitude and shows the signed amount beside it.
class BreakdownCard extends StatelessWidget {
  const BreakdownCard({
    super.key,
    required this.series,
    required this.view,
    this.onManageHoldings,
    this.onViewLoans,
  });

  final NetWorthSeries series;
  final BreakdownView view;
  final VoidCallback? onManageHoldings;
  final VoidCallback? onViewLoans;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final assets = series.assets;
    final liabilities = series.liabilities;
    final gross = assets.abs() + liabilities.abs();

    final showAssets = view != BreakdownView.liabilities;
    final showLiabilities = view != BreakdownView.assets;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Assets vs liabilities',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            gross == 0
                ? 'Nothing recorded on either side yet.'
                : 'Every share is measured against ${Money.format(gross)} of gross value.',
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 14),
          _SplitBar(assets: assets, liabilities: liabilities),
          const SizedBox(height: 18),
          if (showAssets) ...[
            _GroupHeader(
              label: 'Assets',
              total: assets,
              accent: c.income,
              icon: LucideIcons.arrowUpRight,
            ),
            const SizedBox(height: 10),
            _BreakdownRow(
              label: 'Accounts',
              icon: LucideIcons.wallet,
              value: series.accountsTotal,
              gross: gross,
              accent: c.income,
            ),
            _BreakdownRow(
              label: 'Holdings',
              icon: LucideIcons.piggyBank,
              value: series.holdingsTotal,
              gross: gross,
              accent: c.income,
              emptyLabel: 'none yet',
              onTap: onManageHoldings,
            ),
            _BreakdownRow(
              label: 'Stocks',
              icon: LucideIcons.chartNoAxesCombined,
              value: series.stocksTotal,
              gross: gross,
              accent: c.income,
              emptyLabel: 'none yet',
            ),
            // Older snapshots predate `stocksTotal` entirely, so the three
            // named components need not add up to `assets`. Say so rather than
            // folding the difference into one of them.
            if (series.hasOtherAssets)
              _BreakdownRow(
                label: 'Other assets',
                icon: LucideIcons.layers,
                value: series.otherAssets,
                gross: gross,
                accent: c.income,
              ),
          ],
          if (showAssets && showLiabilities) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 14),
          ],
          if (showLiabilities) ...[
            _GroupHeader(
              label: 'Liabilities',
              total: liabilities,
              accent: c.expense,
              icon: LucideIcons.arrowDownRight,
            ),
            const SizedBox(height: 10),
            _BreakdownRow(
              label: 'Loans outstanding',
              icon: LucideIcons.landmark,
              value: liabilities,
              gross: gross,
              accent: c.expense,
              emptyLabel: 'none yet',
              onTap: onViewLoans,
            ),
          ],
        ],
      ),
    );
  }
}

/// A single track split between the two sides, so the imbalance is legible
/// before any number is read.
class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.assets, required this.liabilities});

  final num assets;
  final num liabilities;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gross = assets.abs() + liabilities.abs();
    final assetShare = gross == 0 ? 0.0 : assets.abs() / gross;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                Expanded(
                  flex: (assetShare * 1000).round().clamp(0, 1000),
                  child: ColoredBox(color: c.income),
                ),
                Expanded(
                  flex: (1000 - (assetShare * 1000).round()).clamp(0, 1000),
                  child: ColoredBox(
                    // Nothing on either side: an empty grey track reads as
                    // "no data", which is exactly the situation.
                    color: gross == 0 ? c.secondary : c.expense,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Legend(
                color: c.income,
                label: 'Assets',
                share: gross == 0 ? null : assetShare * 100,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Legend(
                color: gross == 0 ? c.secondary : c.expense,
                label: 'Liabilities',
                share: gross == 0 ? null : (1 - assetShare) * 100,
                alignEnd: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    this.share,
    this.alignEnd = false,
  });

  final Color color;
  final String label;
  final num? share;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      // The two legends share one row, so the label yields before the share
      // figure does — a wide text scale must never push the percentage out of
      // the card.
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        if (share != null) ...[
          const SizedBox(width: 5),
          Text(
            Money.percent(share, alreadyScaled: true, decimals: 0),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.total,
    required this.accent,
    required this.icon,
  });

  final String label;
  final num total;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: accent),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
        ),
        MoneyText(
          total,
          compactAbove: Money.crore,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.gross,
    required this.accent,
    this.emptyLabel,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final num value;

  /// Assets + liabilities, both as magnitudes. Zero when nothing is recorded.
  final num gross;
  final Color accent;

  /// Shown in place of `₹0` when the component holds no records at all —
  /// "none yet" says *nothing exists*, where ₹0 says *it exists and is empty*.
  final String? emptyLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final share = gross == 0 ? 0.0 : (value.abs() / gross).clamp(0.0, 1.0);
    final blank = value == 0 && emptyLabel != null;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: c.mutedForeground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (!blank && gross != 0) ...[
                Text(
                  Money.percent(share * 100, alreadyScaled: true, decimals: 0),
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                const SizedBox(width: 8),
              ],
              if (blank)
                Text(
                  emptyLabel!,
                  style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
                )
              else
                MoneyText(
                  value,
                  tone: value < 0 ? MoneyTone.expense : MoneyTone.neutral,
                  compactAbove: Money.crore,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: c.mutedForeground,
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: share.toDouble(),
              minHeight: 6,
              backgroundColor: c.secondary,
              // A negative component is still shown at its magnitude, tinted
              // as a loss so the bar is not read as something you own.
              valueColor: AlwaysStoppedAnimation<Color>(
                value < 0 ? c.expense : accent,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}
