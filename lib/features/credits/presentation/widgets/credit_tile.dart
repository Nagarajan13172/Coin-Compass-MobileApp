import '../../../../core/ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../domain/credit.dart';

/// What the row's overflow menu can do to a credit. There is no settle action:
/// `settled` is not a key `POST`/`PATCH /credits` declares, so flipping it was
/// a no-op — a closed loan is recorded as the matching `received` / `repaid`
/// entry instead.
enum CreditAction { edit, delete }

/// One entry in the credits ledger: who it involves, which way the money went,
/// and how much it was.
class CreditTile extends StatelessWidget {
  const CreditTile({
    super.key,
    required this.credit,
    required this.onAction,
    this.onTap,
    this.busy = false,
  });

  final Credit credit;
  final ValueChanged<CreditAction> onAction;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Tone follows the cash flow: money you handed over reads as an expense,
    // money that came to you as income. Which side is still owed is the
    // summary card's job, not the row's.
    final outgoing = credit.direction.isOutgoing;
    final signed = outgoing
        ? -credit.outstandingOrAmount
        : credit.outstandingOrAmount;

    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          PersonAvatar(
            name: credit.displayName,
            seed: credit.personId ?? credit.displayName,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  credit.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: _DirectionChip(direction: credit.direction),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoneyText(
            signed,
            tone: outgoing ? MoneyTone.expense : MoneyTone.income,
            compactAbove: Money.crore,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
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
            PopupMenuButton<CreditAction>(
              onSelected: onAction,
              tooltip: tr(context, 'Credit actions'),
              color: c.popover,
              icon: Icon(
                LucideIcons.ellipsisVertical,
                size: 18,
                color: c.mutedForeground,
              ),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: CreditAction.edit,
                  child: _MenuRow(icon: LucideIcons.pencil, label: 'Edit'),
                ),
                PopupMenuItem(
                  value: CreditAction.delete,
                  child: _MenuRow(
                    icon: LucideIcons.trash2,
                    label: 'Delete',
                    color: c.destructive,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    if (credit.date != null) parts.add(DateX.shortDay(credit.date!));
    final note = credit.note?.trim();
    if (note != null && note.isNotEmpty) parts.add(note);
    return parts.isEmpty ? credit.direction.label : parts.join(' · ');
  }
}

class _DirectionChip extends StatelessWidget {
  const _DirectionChip({required this.direction});

  final CreditDirection direction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = direction.isOutgoing ? c.expense : c.income;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        direction.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
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
