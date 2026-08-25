import '../../../../core/ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/lucide_map.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/money_text.dart';
import '../../domain/goal.dart';
import 'goal_ring.dart';

/// One savings goal: a progress ring, what is saved against the target, and a
/// shortcut to add to it.
class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    this.onTap,
    this.onContribute,
  });

  final Goal goal;
  final VoidCallback? onTap;
  final VoidCallback? onContribute;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = colorFromHex(goal.color) ?? c.primary;
    final complete = goal.isComplete;

    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GoalRing(
            progress: goal.progress,
            color: complete ? c.income : accent,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(lucideIcon(goal.icon), size: 15, color: accent),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        goal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      MoneyText(
                        goal.savedAmount,
                        compactAbove: 100000,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        ' of ${Money.compact(goal.targetAmount)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _caption(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: complete ? c.income : c.mutedForeground,
                    fontWeight: complete ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (onContribute != null && !complete) ...[
            const SizedBox(width: 6),
            IconButton(
              onPressed: onContribute,
              tooltip: 'Add to goal',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.12),
                foregroundColor: accent,
                shape: const CircleBorder(),
              ),
              icon: const Icon(LucideIcons.plus, size: 18),
            ),
          ],
          if (complete) ...[
            const SizedBox(width: 6),
            Icon(LucideIcons.circleCheckBig, size: 20, color: c.income),
          ],
        ],
      ),
    );
  }

  /// `₹40,000 to go · 8 months left`, or the target date when the server did
  /// not project one, or the completion when the goal is met.
  String _caption() {
    if (goal.isComplete) {
      final achieved = goal.achievedAt;
      return achieved == null
          ? 'Goal reached'
          : 'Reached ${DateX.shortDay(achieved)}';
    }

    final parts = <String>['${Money.compact(goal.remainingOrComputed)} to go'];
    final months = goal.monthsLeft;
    if (months != null && months > 0) {
      final rounded = months.round();
      parts.add('$rounded ${rounded == 1 ? 'month' : 'months'} left');
    } else if (goal.targetDate != null) {
      parts.add('by ${DateX.shortDay(goal.targetDate!)}');
    }
    return parts.join(' · ');
  }
}
