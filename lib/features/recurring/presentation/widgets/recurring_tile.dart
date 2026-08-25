import '../../../../core/ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/money_text.dart';
import '../../domain/recurring_rule.dart';

/// What the row's overflow menu can do to a rule.
enum RecurringAction { run, postOne, skip, history, toggleActive, edit, delete }

/// One rule: what it posts, how often, when it next runs, and the menu of
/// things you can do to it.
class RecurringTile extends StatelessWidget {
  const RecurringTile({
    super.key,
    required this.rule,
    required this.onAction,
    this.onTap,
    this.busy = false,
  });

  final RecurringRule rule;
  final ValueChanged<RecurringAction> onAction;
  final VoidCallback? onTap;

  /// True while one of this rule's actions is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = switch (rule.type) {
      TransactionType.income => MoneyTone.income,
      TransactionType.expense => MoneyTone.expense,
      TransactionType.transfer => MoneyTone.neutral,
    };
    final fallbackTint = switch (rule.type) {
      TransactionType.income => c.income,
      TransactionType.expense => c.expense,
      TransactionType.transfer => c.primary,
    };
    final fallbackIcon = switch (rule.type) {
      TransactionType.income => 'trending-up',
      TransactionType.expense => 'receipt',
      TransactionType.transfer => 'arrow-right-left',
    };
    final signed = rule.type == TransactionType.expense
        ? -rule.amount
        : rule.amount;

    return Opacity(
      opacity: rule.active ? 1 : 0.6,
      child: AppCard(
        onTap: onTap,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            CategoryAvatar(
              icon: rule.category?.icon ?? fallbackIcon,
              colorHex: rule.category?.color,
              fallbackColor: fallbackTint,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          rule.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!rule.active) ...[
                        const SizedBox(width: 6),
                        const _PausedChip(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _schedule(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MoneyText(
              signed,
              tone: tone,
              compactAbove: Money.crore,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            else
              PopupMenuButton<RecurringAction>(
                onSelected: onAction,
                tooltip: 'Rule actions',
                color: c.popover,
                icon: Icon(
                  LucideIcons.ellipsisVertical,
                  size: 18,
                  color: c.mutedForeground,
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: RecurringAction.run,
                    child: _MenuRow(icon: LucideIcons.play, label: 'Run now'),
                  ),
                  const PopupMenuItem(
                    value: RecurringAction.postOne,
                    child: _MenuRow(
                      icon: LucideIcons.plus,
                      label: 'Post one now',
                    ),
                  ),
                  const PopupMenuItem(
                    value: RecurringAction.skip,
                    child: _MenuRow(
                      icon: LucideIcons.skipForward,
                      label: 'Skip next',
                    ),
                  ),
                  const PopupMenuItem(
                    value: RecurringAction.history,
                    child: _MenuRow(
                      icon: LucideIcons.history,
                      label: 'View history',
                    ),
                  ),
                  PopupMenuItem(
                    value: RecurringAction.toggleActive,
                    child: _MenuRow(
                      icon: rule.active ? LucideIcons.pause : LucideIcons.play,
                      label: rule.active ? 'Pause' : 'Resume',
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: RecurringAction.edit,
                    child: _MenuRow(
                      icon: LucideIcons.pencil,
                      label: 'Edit rule',
                    ),
                  ),
                  PopupMenuItem(
                    value: RecurringAction.delete,
                    child: _MenuRow(
                      icon: LucideIcons.trash2,
                      label: 'Delete rule',
                      color: c.destructive,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// `Every month · Next 04 Sep 2026 · Last posted 04 Aug 2026`
  String _schedule() {
    final parts = <String>[rule.cadenceLabel];
    if (rule.active && rule.nextRun != null) {
      parts.add('Next ${DateX.shortDay(rule.nextRun!)}');
    } else if (!rule.active) {
      parts.add('Paused');
    }
    if (rule.lastRun != null) {
      parts.add('Last posted ${DateX.shortDay(rule.lastRun!)}');
    }
    return parts.join(' · ');
  }
}

class _PausedChip extends StatelessWidget {
  const _PausedChip();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Paused',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c.mutedForeground,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.foreground;
    return Row(
      children: [
        Icon(icon, size: 17, color: tint),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 14.5, color: tint)),
      ],
    );
  }
}
