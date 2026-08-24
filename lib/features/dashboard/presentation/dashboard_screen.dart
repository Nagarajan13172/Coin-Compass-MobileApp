import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../gold/data/metals_repository.dart';
import '../../networth/data/networth_repository.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/domain/report_models.dart';
import '../../reports/presentation/period.dart';
import '../../transactions/data/transactions_repository.dart';
import '../../transactions/presentation/transactions_providers.dart';
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
      onRefresh: () => refreshDashboard(ref),
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
          const NetWorthCard(),
          const SizedBox(height: 12),
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

/// Pull-to-refresh: drop every cached read, then wait for them all to settle.
/// Failures are swallowed here because each card renders its own [ErrorRetry] —
/// the spinner should stop either way.
Future<void> refreshDashboard(WidgetRef ref) async {
  ref
    ..invalidate(dashboardSummaryProvider)
    ..invalidate(dashboardTrendProvider)
    ..invalidate(dashboardCategoryProvider)
    ..invalidate(accountsProvider)
    ..invalidate(metalsLatestProvider)
    ..invalidate(netWorthHistoryProvider)
    ..invalidate(transactionBalanceProvider)
    ..invalidate(transactionsPageProvider);

  await Future.wait(<Future<void>>[
    _settle(ref.read(dashboardSummaryProvider.future)),
    _settle(ref.read(dashboardTrendProvider.future)),
    _settle(ref.read(dashboardCategoryProvider.future)),
    _settle(ref.read(accountsProvider.future)),
    _settle(ref.read(metalsLatestProvider.future)),
    _settle(ref.read(netWorthHistoryProvider.future)),
    _settle(ref.read(transactionsPageProvider(recentTransactionsQuery).future)),
  ]);
}

Future<void> _settle(Future<Object?> future) async {
  try {
    await future;
  } catch (_) {
    // Handled by the card that owns the read.
  }
}
