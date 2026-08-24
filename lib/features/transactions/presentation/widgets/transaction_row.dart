import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/money_text.dart';
import '../../data/transactions_repository.dart';
import '../../domain/transaction.dart';
import '../transactions_providers.dart';

/// One ledger line: tinted category avatar, title (+ a repeat glyph when the
/// row was posted by a recurring rule), signed amount and the time below it.
///
/// Swiping right-to-left deletes optimistically — the row leaves the list at
/// once and a snackbar offers Undo, which calls `POST /transactions/:id/restore`.
class TransactionRow extends ConsumerWidget {
  const TransactionRow({super.key, required this.transaction, this.onTap});

  final Transaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = transaction;

    final tone = switch (t.type) {
      TransactionType.income => MoneyTone.income,
      TransactionType.expense => MoneyTone.expense,
      TransactionType.transfer => MoneyTone.neutral,
    };
    final fallbackTint = switch (t.type) {
      TransactionType.income => c.income,
      TransactionType.expense => c.expense,
      TransactionType.transfer => c.primary,
    };
    final fallbackIcon = switch (t.type) {
      TransactionType.income => 'trending-up',
      TransactionType.expense => 'receipt',
      TransactionType.transfer => 'arrow-right-left',
    };

    final subtitle = _subtitle();
    final time = t.date == null ? null : DateX.timeLabel(t.date!);

    return Dismissible(
      key: ValueKey('txn-${t.id}'),
      direction: DismissDirection.endToStart,
      background: _DeleteBackground(color: c.expense),
      onDismissed: (_) => _delete(context, ref),
      child: ColoredBox(
        color: c.background,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
              child: Row(
                children: [
                  CategoryAvatar(
                    icon: t.category?.icon ?? fallbackIcon,
                    colorHex: t.category?.color,
                    fallbackColor: fallbackTint,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (t.isRecurring) ...[
                              const SizedBox(width: 6),
                              Icon(
                                LucideIcons.repeat,
                                size: 14,
                                color: c.mutedForeground,
                              ),
                            ],
                            if (t.oneoff) ...[
                              const SizedBox(width: 6),
                              Icon(
                                LucideIcons.sparkles,
                                size: 14,
                                color: c.mutedForeground,
                              ),
                            ],
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: c.mutedForeground,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MoneyText(
                        t.signedAmount,
                        tone: tone,
                        // Income reads '+₹5,000', expense keeps its own minus.
                        // Transfers are positive too but move nothing on net,
                        // so a '+' there would be a lie — the web row guards it
                        // the same way.
                        signed: !t.isTransfer,
                        compactAbove: Money.crore,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (time != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Second line, only when it adds something the title doesn't already say.
  String? _subtitle() {
    final t = transaction;
    if (t.isTransfer) {
      final from = t.account?.name;
      final to = t.toAccount?.name;
      if (from != null && to != null) return '$from → $to';
      if (from != null) return from;
      if (to != null) return to;
    }
    final category = t.category?.name;
    if (t.payee.isNotEmpty && category != null && category.isNotEmpty) {
      return category;
    }
    if (t.note.isNotEmpty && t.note != t.title) return t.note;
    return null;
  }

  /// Optimistic delete + undo. Everything the callbacks need is captured before
  /// the row leaves the tree, because `ref` and `context` die with it.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(transactionsRepositoryProvider);
    final controller = ref.read(transactionsListProvider.notifier);

    final removed = controller.deleteLocal(transaction.id) ?? transaction;

    try {
      await repository.delete(removed.id);
    } catch (error) {
      controller.insertLocal(removed);
      messenger.showSnackBar(
        SnackBar(content: Text(ApiException.from(error).message)),
      );
      return;
    }

    invalidateTransactionDerived(container, tags: removed.tags.isNotEmpty);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted ${removed.title}'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await repository.restore(removed.id);
                controller.insertLocal(removed);
                invalidateTransactionDerived(
                  container,
                  tags: removed.tags.isNotEmpty,
                );
              } catch (error) {
                messenger.showSnackBar(
                  SnackBar(content: Text(ApiException.from(error).message)),
                );
              }
            },
          ),
        ),
      );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.trash2, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            'Delete',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
