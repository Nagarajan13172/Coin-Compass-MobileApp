import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/enums.dart';
import '../../../../core/utils/lucide_map.dart';
import '../../../../core/widgets/app_select.dart';
import '../../../accounts/data/accounts_repository.dart';
import '../../../accounts/domain/account.dart';
import '../../../categories/data/categories_repository.dart';
import '../../../categories/domain/category.dart';
import '../../data/transactions_repository.dart';
import '../transactions_providers.dart';

/// The 2×2 filter grid under the search box: type, account, category and a
/// combined tag / one-off selector. Every change rewrites
/// [transactionQueryProvider], which the list controller listens to.
class TransactionFilters extends ConsumerWidget {
  const TransactionFilters({super.key});

  /// Sentinel values for the fourth dropdown, which mixes two query fields.
  static const String _oneoffOnly = 'oneoff:only';
  static const String _oneoffExclude = 'oneoff:exclude';
  static const String _tagPrefix = 'tag:';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(transactionQueryProvider);
    final accounts =
        ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final tags =
        ref.watch(transactionTagsProvider).valueOrNull ?? const <String>[];

    final sortedAccounts = [...accounts]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final sortedCategories = [...categories]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // A value the dropdown has no item for would trip an assert, so anything
    // still loading falls back to "all".
    final accountValue = sortedAccounts.any((a) => a.id == query.accountId)
        ? query.accountId
        : null;
    final categoryValue = sortedCategories.any((c) => c.id == query.categoryId)
        ? query.categoryId
        : null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AppSelect<TransactionType?>(
                value: query.type,
                items: [
                  const SelectItem<TransactionType?>(null, 'All types'),
                  for (final type in TransactionType.values)
                    SelectItem<TransactionType?>(
                      type,
                      type.label,
                      icon: lucideIcon(_typeIcon(type)),
                    ),
                ],
                onChanged: (value) => _set(
                  ref,
                  (q) => value == null
                      ? q.copyWith(clearType: true)
                      : q.copyWith(type: value),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppSelect<String?>(
                value: accountValue,
                items: [
                  const SelectItem<String?>(null, 'All accounts'),
                  for (final account in sortedAccounts)
                    SelectItem<String?>(
                      account.id,
                      account.name,
                      icon: lucideIcon(account.icon ?? account.type.icon),
                    ),
                ],
                onChanged: (value) => _set(
                  ref,
                  (q) => value == null
                      ? q.copyWith(clearAccountId: true)
                      : q.copyWith(accountId: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppSelect<String?>(
                value: categoryValue,
                items: [
                  const SelectItem<String?>(null, 'All categories'),
                  for (final category in sortedCategories)
                    SelectItem<String?>(
                      category.id,
                      category.name,
                      icon: lucideIcon(category.icon),
                    ),
                ],
                onChanged: (value) => _set(
                  ref,
                  (q) => value == null
                      ? q.copyWith(clearCategoryId: true)
                      : q.copyWith(categoryId: value),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppSelect<String?>(
                value: _tagValue(query, tags),
                items: [
                  const SelectItem<String?>(null, 'Tags & one-off'),
                  const SelectItem<String?>(_oneoffOnly, 'One-off only'),
                  const SelectItem<String?>(_oneoffExclude, 'Exclude one-off'),
                  for (final tag in tags)
                    SelectItem<String?>('$_tagPrefix$tag', '#$tag'),
                ],
                onChanged: (value) => _set(ref, (q) => _applyTag(q, value)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String? _tagValue(TransactionQuery query, List<String> tags) {
    if (query.oneoff == true) return _oneoffOnly;
    if (query.oneoff == false) return _oneoffExclude;
    final tag = query.tag;
    if (tag != null && tags.contains(tag)) return '$_tagPrefix$tag';
    return null;
  }

  static TransactionQuery _applyTag(TransactionQuery query, String? value) {
    if (value == null) {
      return query.copyWith(clearTag: true, clearOneoff: true);
    }
    if (value == _oneoffOnly) {
      return query.copyWith(oneoff: true, clearTag: true);
    }
    if (value == _oneoffExclude) {
      return query.copyWith(oneoff: false, clearTag: true);
    }
    return query.copyWith(
      tag: value.substring(_tagPrefix.length),
      clearOneoff: true,
    );
  }

  static String _typeIcon(TransactionType type) => switch (type) {
    TransactionType.income => 'trending-up',
    TransactionType.expense => 'receipt',
    TransactionType.transfer => 'arrow-right-left',
  };

  /// Any filter change goes back to page one — the controller reloads from
  /// there when it sees the new query.
  static void _set(
    WidgetRef ref,
    TransactionQuery Function(TransactionQuery query) update,
  ) {
    final current = ref.read(transactionQueryProvider);
    ref.read(transactionQueryProvider.notifier).state = update(
      current,
    ).firstPage();
  }
}
