import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/presentation/transactions_providers.dart';
import '../dashboard_screen.dart';

/// The five newest transactions, with a "View all" jump to the full list.
class RecentTransactionsCard extends ConsumerWidget {
  const RecentTransactionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(transactionsPageProvider(recentTransactionsQuery));

    return page.when(
      loading: () => const LoadingCard(lines: 4),
      error: (error, _) => ErrorRetry(
        error: error,
        compact: true,
        onRetry: () =>
            ref.invalidate(transactionsPageProvider(recentTransactionsQuery)),
      ),
      data: (data) => _Card(items: data.items),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.items});

  final List<Transaction> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Recent',
            actionLabel: 'View all',
            onAction: () => context.go('/transactions'),
          ),
          if (items.isEmpty)
            const EmptyState(title: 'No transactions yet', compact: true)
          else
            for (final transaction in items) ...[
              const SizedBox(height: 12),
              _TransactionRow(transaction: transaction),
            ],
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final category = transaction.category;
    final transfer = transaction.isTransfer;

    return InkWell(
      onTap: () => context.go('/transactions'),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            CategoryAvatar(
              icon: category?.icon ?? _fallbackIcon(transaction.type),
              colorHex: category?.color,
              size: 38,
              fallbackColor: c.mutedForeground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      transaction.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (transaction.isRecurring) ...[
                    const SizedBox(width: 6),
                    Icon(
                      LucideIcons.repeat,
                      size: 13,
                      color: c.mutedForeground,
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
                  transfer ? transaction.amount : transaction.signedAmount,
                  tone: transfer ? MoneyTone.muted : MoneyTone.auto,
                  signed: !transfer,
                  compactAbove: Money.crore,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _stamp(transaction),
                  style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Today's rows show a time; anything older shows the day, which is what you
  /// actually need when scanning a week-old entry.
  static String _stamp(Transaction transaction) {
    final when = transaction.date ?? transaction.createdAt;
    if (when == null) return '';
    return when.isToday ? DateX.timeLabel(when) : DateX.shortDay(when);
  }

  static String _fallbackIcon(TransactionType type) => switch (type) {
    TransactionType.income => 'banknote',
    TransactionType.expense => 'shopping-bag',
    TransactionType.transfer => 'arrow-right-left',
  };
}
