import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../data/categories_repository.dart';
import '../domain/category.dart';
import 'category_form_sheet.dart';
import 'widgets/category_tile.dart';
import '../../../core/router/route_refresh.dart';

/// Height of the bottom nav bar in [AppScaffold]; a scrollable body has to
/// clear it because the shell renders with `extendBody: true`.
const double _navBarHeight = 62;

/// Overhang of the raised centre FAB plus a little breathing room.
const double _fabClearance = 28;

/// Space a scrollable must reserve at its tail to clear the shell's nav bar,
/// the system inset below it and the raised FAB.
///
/// `viewPaddingOf`, not `paddingOf`: inside a body with `extendBody: true`
/// Flutter already folds the nav bar into `MediaQuery.padding.bottom`, so
/// `paddingOf` would count it twice.
double _shellBottomInset(BuildContext context) =>
    _navBarHeight + MediaQuery.viewPaddingOf(context).bottom + _fabClearance;

/// Categories: an Expense / Income switch over the seeded + custom categories,
/// grouped by the API's `group` field. Body only — AppScaffold owns the chrome.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  CategoryType _tab = CategoryType.expense;

  Future<void> _refresh() => refreshCurrentRoute(ref, '/categories');

  Future<void> _openSheet({Category? category}) async {
    final result = await CategoryFormSheet.show(
      context,
      category: category,
      initialType: _tab,
    );
    if (result == null || !mounted) return;
    final message = result == CategorySheetResult.deleted
        ? 'Category deleted'
        : category == null
        ? 'Category created'
        : 'Category updated';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(categoriesProvider);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Not a constant: AppScaffold renders with `extendBody: true`, so a
        // fixed tail leaves the last tile under the FAB once the system inset
        // grows (3-button navigation is 48dp).
        padding: EdgeInsets.fromLTRB(16, 16, 16, _shellBottomInset(context)),
        children: [
          _header(async.valueOrNull),
          ...async.when(
            data: _sections,
            loading: _skeleton,
            error: (error, _) => [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ErrorRetry(
                  error: error,
                  onRetry: () => ref.invalidate(categoriesFetchProvider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(List<Category>? all) {
    final c = context.colors;
    final subtitle = all == null
        ? 'Organise income and expenses'
        : 'Organise income and expenses · '
              '${all.where((x) => x.type == CategoryType.expense).length} expense · '
              '${all.where((x) => x.type == CategoryType.income).length} income';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Categories',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'New category',
            icon: LucideIcons.plus,
            expand: false,
            onPressed: _openSheet,
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedPeriodSelector<CategoryType>(
            value: _tab,
            options: const [
              SegmentOption(CategoryType.expense, 'Expense'),
              SegmentOption(CategoryType.income, 'Income'),
            ],
            onChanged: (value) => setState(() => _tab = value),
          ),
        ),
      ],
    );
  }

  List<Widget> _skeleton() => [
    for (var i = 0; i < 6; i++)
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: LoadingCard(lines: 2),
      ),
  ];

  List<Widget> _sections(List<Category> all) {
    final visible = all.where((x) => x.type == _tab).toList();
    if (visible.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: EmptyState(
            icon: LucideIcons.shapes,
            title: _tab == CategoryType.income
                ? 'No income categories'
                : 'No expense categories',
            message:
                'Add one to start sorting your ${_tab.label.toLowerCase()}'
                ' transactions.',
            actionLabel: 'Add category',
            onAction: _openSheet,
          ),
        ),
      ];
    }

    // Bucket by `group`, then walk categoryGroupLabels in its declared order so
    // the sections land in the same sequence as the web app.
    final buckets = <String, List<Category>>{};
    for (final category in visible) {
      final key = (category.group == null || category.group!.isEmpty)
          ? 'other'
          : category.group!;
      buckets.putIfAbsent(key, () => []).add(category);
    }
    final unknown =
        buckets.keys.where((k) => !categoryGroupLabels.containsKey(k)).toList()
          ..sort();
    final keys = [
      ...categoryGroupLabels.keys.where(buckets.containsKey),
      ...unknown,
    ];

    final widgets = <Widget>[];
    for (final key in keys) {
      final rows = buckets[key]!
        ..sort((a, b) {
          final byOrder = a.order.compareTo(b.order);
          return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
        });
      widgets.add(
        _GroupHeader(
          label: categoryGroupLabels[key] ?? key,
          count: rows.length,
        ),
      );
      for (final category in rows) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CategoryTile(
              category: category,
              onTap: () => _openSheet(category: category),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

/// `Food  3` — smaller and muted, unlike the 17sp SectionHeader used for cards.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: c.mutedForeground,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: c.mutedForeground.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
