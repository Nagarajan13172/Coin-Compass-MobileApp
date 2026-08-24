import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../categories/domain/category.dart';
import '../../domain/budget.dart';

/// Amber has no token of its own — the palette carries only income green and
/// expense red — so the near-limit warning colour is pinned here, matching the
/// web app's `amber-500`.
const Color _warning = Color(0xFFF59E0B);

/// One budget: what it caps, how much of it is gone, and how much is left.
///
/// A budget has no name server-side, so the row is titled by the category it
/// caps — or "All spending" when it caps everything.
///
/// [spent] is null while the window's spending is still loading, which is the
/// common case on first paint — the limit comes from `/budgets` but the spend
/// comes from `/reports/*` unless the server sent its own figure.
class BudgetTile extends StatelessWidget {
  const BudgetTile({
    super.key,
    required this.budget,
    required this.category,
    required this.spent,
    this.daysLeft,
    this.onTap,
  });

  final Budget budget;

  /// The budget's category, already resolved by the caller — `/budgets` sends
  /// it as a bare id whenever it isn't populated. Null caps all spending.
  final Category? category;
  final num? spent;
  final int? daysLeft;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final amount = budget.amount;
    final used = spent;
    // The bar is clamped at full; `percent` keeps the true figure, which the
    // server reports as a whole number (1331 = 1331% of the limit).
    final progress = budget.barValue(used);
    final percent = budget.percentUsed(used);
    final over = budget.isOver(used);
    final nearLimit = budget.isNearLimit(used);
    final accent = over ? c.expense : (nearLimit ? _warning : c.income);

    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (category != null)
                CategoryAvatar(icon: category!.icon, colorHex: category!.color)
              else
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.wallet, size: 20, color: c.primary),
                ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (used == null)
                    const LoadingShimmer(width: 74, height: 15)
                  else
                    MoneyText(
                      used,
                      compactAbove: Money.crore,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: over ? c.expense : c.foreground,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    'of ${Money.compact(amount)}',
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: c.secondary,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          if (used != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _StatusChip(
                  label: over
                      ? 'Over budget'
                      : (nearLimit ? 'Near limit' : 'On track'),
                  color: accent,
                ),
                if (percent != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${percent.round()}% used',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
                const Spacer(),
                Flexible(
                  child: Text(
                    _trailing(used, amount, over),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Budgets carry no name, so the category is the title — else all spending.
  String get _title {
    final categoryName = category?.name.trim();
    if (categoryName != null && categoryName.isNotEmpty) return categoryName;
    return 'All spending';
  }

  /// The period, plus where its window actually starts when the server anchored
  /// one — a monthly budget need not run with the calendar month.
  String get _subtitle {
    final start = budget.periodRange?.start ?? budget.startDate;
    if (start == null) return budget.period.label;
    return '${budget.period.label} · from ${DateX.shortDay(start)}';
  }

  String _trailing(num used, num amount, bool over) {
    final headline = over
        ? 'Over by ${Money.compact(used - amount)}'
        : '${Money.compact(amount - used)} left';
    final days = daysLeft;
    if (days == null || days <= 0) return headline;
    return '$headline · $days ${days == 1 ? 'day' : 'days'} to go';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
