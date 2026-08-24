import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/money_text.dart';
import '../../domain/holding.dart';

/// One saving or investment: what it is, which of the nine subtypes it belongs
/// to, what it is worth, and when it matures.
///
/// There is deliberately no cost basis, institution or rate of return on this
/// row — `POST /holdings` strips all three, so a holding has exactly one money
/// figure and inventing a second would be showing the user a number the server
/// never stored (docs/WRITE_SCHEMAS.md).
class HoldingTile extends StatelessWidget {
  const HoldingTile({super.key, required this.holding, this.onTap});

  final Holding holding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = holding.isSaving ? c.income : c.primary;
    final maturity = holding.maturityDate;

    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(subtypeIcon(holding.subtype), size: 19, color: accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holding.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(child: _SubtypeChip(subtype: holding.subtype)),
                    if (maturity != null) ...[
                      const SizedBox(width: 7),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              holding.isMatured
                                  ? LucideIcons.circleAlert
                                  : LucideIcons.calendarClock,
                              size: 12,
                              color: holding.isMatured
                                  ? c.expense
                                  : c.mutedForeground,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                holding.isMatured
                                    ? 'Matured ${DateX.shortDay(maturity)}'
                                    : 'Matures ${DateX.shortDay(maturity)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: holding.isMatured
                                      ? c.expense
                                      : c.mutedForeground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoneyText(
            holding.value,
            compactAbove: Money.crore,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SubtypeChip extends StatelessWidget {
  const _SubtypeChip({required this.subtype});

  final HoldingSubtype subtype;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        subtype.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: c.mutedForeground,
        ),
      ),
    );
  }
}

/// A glyph for each of the nine subtypes the backend's enum declares.
IconData subtypeIcon(HoldingSubtype subtype) => switch (subtype) {
  HoldingSubtype.fixedDeposit => LucideIcons.landmark,
  HoldingSubtype.recurringDeposit => LucideIcons.repeat,
  HoldingSubtype.emergencyFund => LucideIcons.shieldCheck,
  HoldingSubtype.retirementFund => LucideIcons.umbrella,
  HoldingSubtype.stocks => LucideIcons.chartNoAxesCombined,
  HoldingSubtype.mutualFunds => LucideIcons.chartPie,
  HoldingSubtype.realEstate => LucideIcons.building2,
  HoldingSubtype.bonds => LucideIcons.receipt,
  HoldingSubtype.gold => LucideIcons.gem,
};
