import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/route_refresh.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/domain/report_models.dart';
import '../../reports/presentation/period.dart';
import '../../transactions/data/transactions_repository.dart';
import '../../wealth_lock/presentation/wealth_gate.dart';
import 'widgets/accounts_preview_card.dart';
import 'widgets/greeting_header.dart';
import 'widgets/income_expense_chart.dart';
import 'widgets/metals_card.dart';
import 'widgets/net_worth_card.dart';
import 'widgets/quick_stats_card.dart';
import 'widgets/recent_transactions_card.dart';
import 'widgets/spending_donut_card.dart';
import 'widgets/summary_cards.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard reads
//
// Each card watches its own provider so a single failing endpoint degrades one
// card instead of blanking the screen. Every provider derives its window from
// [periodRangeProvider], so flipping Week/Month/Year refetches the whole page
// without any card having to be told.
// ─────────────────────────────────────────────────────────────────────────────

/// `/reports/summary` for the selected window — income, expense, net, counts.
final dashboardSummaryProvider = FutureProvider.autoDispose<ReportSummary>((
  ref,
) {
  final range = ref.watch(periodRangeProvider);
  return ref
      .watch(reportsRepositoryProvider)
      .summary(from: range.start, to: range.end);
});

/// `/reports/trend` for the income-vs-expense chart. A week or a month is
/// bucketed by day; a year by month, otherwise the line would have 365 points.
final dashboardTrendProvider = FutureProvider.autoDispose<List<TrendPoint>>((
  ref,
) {
  final range = ref.watch(periodRangeProvider);
  final granularity = range.kind == PeriodKind.year
      ? TrendGranularity.month
      : TrendGranularity.day;
  return ref
      .watch(reportsRepositoryProvider)
      .trend(from: range.start, to: range.end, granularity: granularity);
});

/// `/reports/by-category` (expenses) — feeds the donut and "Biggest category".
final dashboardCategoryProvider =
    FutureProvider.autoDispose<List<CategorySlice>>((ref) {
      final range = ref.watch(periodRangeProvider);
      return ref
          .watch(reportsRepositoryProvider)
          .byCategory(from: range.start, to: range.end, type: 'expense');
    });

/// The five newest rows behind the "Recent" card. Deliberately *not* windowed:
/// an empty month should still show the last thing you logged.
const TransactionQuery recentTransactionsQuery = TransactionQuery(limit: 5);

/// Height of the bottom nav bar in [AppScaffold]; the list has to clear it
/// because the shell renders with `extendBody: true`.
const double _navBarHeight = 62;

/// Overhang of the raised centre FAB plus a little breathing room.
const double _fabClearance = 28;

/// The Dashboard body. [AppScaffold] supplies the app bar and bottom nav, so
/// this is a bare scrollable — no Scaffold of its own.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final kind = ref.watch(periodKindProvider);
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;

    return RefreshIndicator(
      color: c.primary,
      backgroundColor: c.card,
      onRefresh: () => refreshCurrentRoute(ref, '/'),
      child: ListView(
        // Always scrollable, otherwise pull-to-refresh dies on a short page.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          _navBarHeight + systemInset + _fabClearance,
        ),
        children: [
          const GreetingHeader(),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedPeriodSelector<PeriodKind>(
              value: kind,
              options: [
                for (final k in PeriodKind.values)
                  SegmentOption(k, k.shortLabel),
              ],
              onChanged: (next) =>
                  ref.read(periodKindProvider.notifier).state = next,
            ),
          ),
          const SizedBox(height: 16),
          const SummaryCards(),
          const SizedBox(height: 12),
          const _GatedNetWorthCard(),
          const QuickStatsCard(),
          const SizedBox(height: 12),
          const IncomeExpenseChart(),
          const SizedBox(height: 12),
          const AccountsPreviewCard(),
          const SizedBox(height: 12),
          // Carries its own bottom gap: the card disappears entirely when the
          // deployment has no metals provider, and a fixed SizedBox here would
          // leave a hole behind it.
          const MetalsCard(),
          const SpendingDonutCard(),
          const SizedBox(height: 12),
          const RecentTransactionsCard(),
        ],
      ),
    );
  }
}

/// The dashboard's one gated surface: the gradient net-worth hero, its
/// "Breakdown" link and its "everything you own, minus what you owe" line.
///
/// The web hides exactly this card and nothing else on the dashboard —
/// `f && <Card className="surface-gradient …">`, bundle @798903 — so income,
/// expense, net, the chart, the accounts preview and the category donut all
/// stay. Nothing takes its place while locked: a "Net Worth is hidden"
/// placeholder would advertise the lock to the very person the everyday login
/// is meant to be shareable with.
///
/// Carries its own trailing gap, the same way [MetalsCard] does, so removing
/// it leaves no hole in the column.
class _GatedNetWorthCard extends StatelessWidget {
  const _GatedNetWorthCard();

  @override
  Widget build(BuildContext context) {
    return WealthGate(
      locked: const SizedBox.shrink(),
      checking: const Column(
        children: [LoadingCard(lines: 2), SizedBox(height: 12)],
      ),
      builder: (_) =>
          const Column(children: [NetWorthCard(), SizedBox(height: 12)]),
    );
  }
}

