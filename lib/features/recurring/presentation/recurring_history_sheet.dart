import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../transactions/domain/transaction.dart';
import '../data/recurring_repository.dart';
import '../domain/recurring_rule.dart';

/// Everything one rule has posted — `GET /recurring/:id/transactions`.
class RecurringHistorySheet extends ConsumerWidget {
  const RecurringHistorySheet({super.key, required this.rule});

  final RecurringRule rule;

  static Future<void> show(
    BuildContext context, {
    required RecurringRule rule,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RecurringHistorySheet(rule: rule),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final history = ref.watch(recurringHistoryProvider(rule.id));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Posted by this rule',
                          style: TextStyle(
                            fontSize: 13,
                            color: c.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: switch (history) {
                AsyncData(:final value) when value.isEmpty => const Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: EmptyState(
                    icon: LucideIcons.history,
                    title: 'Nothing posted yet',
                    message:
                        'Transactions appear here once the rule has run at least once.',
                    compact: true,
                  ),
                ),
                AsyncData(:final value) => ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: value.length,
                  separatorBuilder: (_, _) =>
                      Divider(color: c.border, height: 1),
                  itemBuilder: (_, index) => _HistoryRow(value[index]),
                ),
                AsyncError(:final error) => Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ErrorRetry(
                    error: error,
                    compact: true,
                    onRetry: () =>
                        ref.invalidate(recurringHistoryProvider(rule.id)),
                  ),
                ),
                _ => const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    children: [
                      LoadingShimmer(height: 44),
                      SizedBox(height: 10),
                      LoadingShimmer(height: 44),
                      SizedBox(height: 10),
                      LoadingShimmer(height: 44),
                    ],
                  ),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.transaction);

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = transaction;
    final tone = switch (t.type) {
      TransactionType.income => MoneyTone.income,
      TransactionType.expense => MoneyTone.expense,
      TransactionType.transfer => MoneyTone.neutral,
    };
    final stamp = t.date ?? t.createdAt;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CategoryAvatar(
            icon: t.category?.icon ?? 'repeat',
            colorHex: t.category?.color,
            size: 34,
            fallbackColor: c.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (stamp != null)
                  Text(
                    DateX.shortDay(stamp),
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MoneyText(
            t.signedAmount,
            tone: tone,
            compactAbove: Money.crore,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
