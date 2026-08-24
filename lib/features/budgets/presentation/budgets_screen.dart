import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../categories/data/categories_repository.dart';
import '../data/budgets_repository.dart';
import '../domain/budget.dart';
import 'budget_form_sheet.dart';
import 'budgets_providers.dart';
import 'widgets/budget_tile.dart';
import '../../../core/router/route_refresh.dart';

/// `/budgets` — one card per spending limit with its progress for the current
/// window. Body only; [AppScaffold] supplies the chrome.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'Budgets',
            subtitle: 'Set spending limits and track progress',
            actions: [
              ScreenHeaderAction(
                label: 'New budget',
                icon: LucideIcons.plus,
                onPressed: () => _openForm(context),
              ),
            ],
          ),
          switch (budgets) {
            AsyncData(:final value) when value.isEmpty => _EmptyBudgets(
              onAdd: () => _openForm(context),
            ),
            AsyncData(:final value) => _BudgetList(budgets: value),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(budgetsFetchProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 3),
                  SizedBox(height: 12),
                  LoadingCard(lines: 3),
                  SizedBox(height: 12),
                  LoadingCard(lines: 3),
                ],
              ),
            ),
          },
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) => refreshCurrentRoute(ref, '/budgets');

  Future<void> _openForm(BuildContext context, {Budget? budget}) =>
      BudgetFormSheet.show(context, budget: budget);
}

class _EmptyBudgets extends StatelessWidget {
  const _EmptyBudgets({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DashedBox(
        child: EmptyState(
          icon: LucideIcons.target,
          title: 'No budgets yet',
          message: 'Create a budget to keep your spending on track.',
          actionLabel: 'New budget',
          onAction: onAdd,
        ),
      ),
    );
  }
}

/// The totals card plus the per-period sections.
class _BudgetList extends ConsumerWidget {
  const _BudgetList({required this.budgets});

  final List<Budget> budgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final byId = {for (final category in categories) category.id: category};

    // One request pair per distinct period, shared by every row that uses it.
    final periods = budgets.map((b) => b.period).toSet();
    final spends = <BudgetPeriod, BudgetSpend?>{
      for (final period in periods)
        period: ref.watch(budgetSpendProvider(period)).valueOrNull,
    };

    num? spentFor(Budget budget) =>
        budget.spent ?? spends[budget.period]?.forBudget(budget);

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: _TotalsCard(
          budgets: budgets,
          spent: {
            for (final budget in budgets)
              if (spentFor(budget) != null) budget.id: spentFor(budget)!,
          },
        ),
      ),
    ];

    for (final period in BudgetPeriod.values) {
      final group = budgets.where((b) => b.period == period).toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
      if (group.isEmpty) continue;

      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: _GroupHeader(label: period.label, count: group.length),
        ),
      );
      children.addAll([
        for (final budget in group)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: BudgetTile(
              budget: budget,
              category: budget.category ?? byId[budget.categoryId],
              spent: spentFor(budget),
              // The server's own window wins when it sent one; the reports
              // window is the fallback for rows it did not compute.
              daysLeft:
                  budget.periodRange?.daysLeft ??
                  spends[budget.period]?.daysLeft,
              onTap: () => BudgetFormSheet.show(context, budget: budget),
            ),
          ),
      ]);
    }

    return Column(children: children);
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: c.mutedForeground,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: c.mutedForeground,
          ),
        ),
      ],
    );
  }
}

/// Budgeted / spent / left across every budget, each measured in its own
/// window. Rows whose spend has not landed yet are simply not counted, so the
/// card fills in rather than jumping between wrong totals.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.budgets, required this.spent});

  final List<Budget> budgets;
  final Map<String, num> spent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final budgeted = budgets.fold<num>(0, (sum, b) => sum + b.amount);
    final used = spent.values.fold<num>(0, (sum, value) => sum + value);
    final left = budgeted - used;
    final resolved = spent.length == budgets.length;
    // `over` is the server's verdict when it sent one, else a comparison
    // against the spend measured from /reports/*.
    final over = budgets.where((b) => b.isOver(spent[b.id])).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Budgeted',
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
          const SizedBox(height: 4),
          MoneyText(
            budgeted,
            compactAbove: Money.crore,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Split(
                  label: 'Spent',
                  amount: used,
                  tone: MoneyTone.expense,
                  icon: LucideIcons.trendingDown,
                  accent: c.expense,
                  pending: !resolved,
                ),
              ),
              Container(width: 1, height: 34, color: c.border),
              Expanded(
                child: _Split(
                  label: 'Left',
                  amount: left,
                  tone: left < 0 ? MoneyTone.expense : MoneyTone.income,
                  icon: LucideIcons.piggyBank,
                  accent: left < 0 ? c.expense : c.income,
                  pending: !resolved,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            over == 0
                ? 'Across ${budgets.length} ${budgets.length == 1 ? 'budget' : 'budgets'}'
                : 'Across ${budgets.length} budgets · $over over limit',
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _Split extends StatelessWidget {
  const _Split({
    required this.label,
    required this.amount,
    required this.tone,
    required this.icon,
    required this.accent,
    required this.pending,
  });

  final String label;
  final num amount;
  final MoneyTone tone;
  final IconData icon;
  final Color accent;

  /// True while some rows' spend is still loading — the figure so far is shown
  /// dimmed rather than presented as final.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: accent),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
                ),
                if (pending)
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: LoadingShimmer(width: 60, height: 13),
                  )
                else
                  MoneyText(
                    amount,
                    tone: tone,
                    compactAbove: 1000000,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
