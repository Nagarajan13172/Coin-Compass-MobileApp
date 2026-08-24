import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../../../core/widgets/stat_card.dart';
import '../../transactions/data/transactions_repository.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../domain/report_metrics.dart';
import '../domain/report_models.dart';
import 'export_csv_sheet.dart';
import 'period.dart';
import 'reports_providers.dart';
import 'widgets/by_account_card.dart';
import 'widgets/category_breakdown_card.dart';
import 'widgets/reports_charts.dart';

/// `/reports` — income and spending for one window, from six `/reports/*`
/// reads.
///
/// Body only; [AppScaffold] supplies the app bar and bottom nav.
///
/// Written for this account's real data first: two transactions, one category,
/// **no accounts**, no previous period. So "By account" is empty, the trend is
/// a single bucket, the savings rate has no income to divide by and the
/// month-on-month comparison has no baseline. Every one of those renders an
/// em dash or an empty state rather than a fake zero — a screen that says
/// "0%" where it means "there is nothing to compare" is lying.
///
/// PARITY NOTES (deliberate divergences, all documented in the phase report):
///
///  * The period here is [reportsPeriodKindProvider], the screen's own state —
///    the web keeps Reports, Insights and the Dashboard on three independent
///    periods, and flipping this one must not move the Dashboard.
///  * The window honours `settings.firstDayOfWeek`; the web hard-codes Monday
///    on this screen (see [reportsRangeProvider]).
///  * Pull-to-refresh is a mobile addition — react-query refetches on focus.
///  * The Export popover is a bottom sheet, and the chart tooltips are bound
///    to tap rather than hover.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  static const String routePath = '/reports';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final range = ref.watch(reportsRangeProvider);

    return RefreshIndicator(
      color: c.primary,
      backgroundColor: c.card,
      onRefresh: () => refreshReports(ref),
      child: ListView(
        // Always scrollable, or pull-to-refresh dies on a short page.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: shellBottomInset(context)),
        children: [
          ScreenHeader(
            title: 'Reports',
            subtitle: 'Analyse your income and spending',
            actions: [
              ScreenHeaderAction(
                label: 'Export CSV',
                icon: LucideIcons.download,
                primary: false,
                onPressed: () => ExportCsvSheet.show(context, range: range),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _Padded(child: _PeriodBar()),
          const SizedBox(height: 10),
          const _Padded(child: _Caption()),
          const SizedBox(height: 14),
          const _Padded(child: _SummarySection()),
          const SizedBox(height: 12),
          _Padded(
            child: CategoryBreakdownCard(
              summary: ref.watch(reportsSummaryProvider(range)).valueOrNull,
              onOpenCategory: (categoryId, type) => openTransactions(
                context,
                ref,
                range: range,
                type: TransactionType.fromApi(type),
                categoryId: categoryId,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _Padded(child: _TrendCard()),
          const SizedBox(height: 12),
          _Padded(
            child: ByAccountCard(
              onOpenAccount: (accountId) => openTransactions(
                context,
                ref,
                range: range,
                accountId: accountId,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _Padded(child: _NetCashFlowCard()),
        ],
      ),
    );
  }
}

/// Drill-through into the ledger.
///
/// The Transactions screen takes no route query parameters — it reads the
/// shared [transactionQueryProvider] — so the filter is written there and the
/// navigation is a plain `go`. It also re-stamps `from`/`to` from
/// [transactionsMonthProvider] on mount, which is why the month is set too.
///
/// KNOWN LIMIT: for a Week or Year window that re-stamp widens the window to
/// the containing month. The type/category/account filter survives intact; the
/// dates do not. Fixing it properly means teaching the Transactions screen
/// about an incoming window, which is that screen's file, not this one's.
///
/// Does nothing when there is no router above this widget, which is how the
/// widget tests mount the screen.
@visibleForTesting
void openTransactions(
  BuildContext context,
  WidgetRef ref, {
  required PeriodRange range,
  TransactionType? type,
  String? categoryId,
  String? accountId,
}) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  ref.read(transactionsMonthProvider.notifier).state = range.start.startOfMonth;
  ref.read(transactionQueryProvider.notifier).state = TransactionQuery(
    from: range.start,
    to: range.end,
    type: type,
    categoryId: categoryId,
    accountId: accountId,
  );
  router.go('/transactions');
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: child,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Period bar
// ─────────────────────────────────────────────────────────────────────────────

/// Week | Month | Year, plus the ‹ label › pager. Both together are ~440dp, so
/// at 360dp the Wrap drops the pager onto its own line — which is exactly what
/// the web's `flex-wrap` row does at the same width.
class _PeriodBar extends ConsumerWidget {
  const _PeriodBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(reportsPeriodKindProvider);
    final range = ref.watch(reportsRangeProvider);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedPeriodSelector<PeriodKind>(
          value: kind,
          options: [
            for (final k in PeriodKind.values) SegmentOption(k, k.shortLabel),
          ],
          onChanged: (next) {
            // Re-anchor on the equivalent instant so switching Month -> Week
            // lands in the week you were already reading, not today's.
            ref.read(reportsPeriodKindProvider.notifier).state = next;
          },
        ),
        _Pager(range: range),
      ],
    );
  }
}

class _Pager extends ConsumerWidget {
  const _Pager({required this.range});

  final PeriodRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);

    void step(int by) {
      final shifted = range.shifted(by);
      // The anchor, not the range, is the source of truth — the range is
      // derived from it and from the week-start setting.
      ref.read(reportsAnchorProvider.notifier).state = shifted.start;
    }

    Widget arrow(IconData icon, String tooltip, VoidCallback onTap) => Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          width: 40,
          height: 42,
          child: Icon(icon, size: 18, color: c.foreground),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: radius,
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The web does not clamp the pager to today — you can page into the
          // future and see an empty period. Kept, so the two agree.
          arrow(LucideIcons.chevronLeft, 'Previous period', () => step(-1)),
          SizedBox(
            width: 136,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  range.periodLabel,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          arrow(LucideIcons.chevronRight, 'Next period', () => step(1)),
        ],
      ),
    );
  }
}

/// "Showing **August 2026 · Month view**".
class _Caption extends ConsumerWidget {
  const _Caption();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final range = ref.watch(reportsRangeProvider);
    final kind = ref.watch(reportsPeriodKindProvider);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Showing ',
            style: TextStyle(color: c.mutedForeground),
          ),
          TextSpan(
            // `periodLabel`, not `label`: the web renders the current month as
            // "August 2026" like any other, never "This month".
            text: '${range.periodLabel} · ${kind.viewName}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: c.foreground,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13.5),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary: the three headline figures, the derived metrics, the split and the
// one-sentence insight.
// ─────────────────────────────────────────────────────────────────────────────

class _SummarySection extends ConsumerWidget {
  const _SummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportsRangeProvider);
    final summary = ref.watch(reportsSummaryProvider(range));

    return summary.when(
      loading: () => const Column(
        children: [
          LoadingCard(lines: 2),
          SizedBox(height: 12),
          LoadingCard(lines: 2),
          SizedBox(height: 12),
          LoadingCard(lines: 2),
        ],
      ),
      error: (error, _) => ErrorRetry(
        error: error,
        onRetry: () => ref.invalidate(reportsSummaryProvider(range)),
      ),
      data: (data) => _Summary(summary: data, range: range),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.summary, required this.range});

  final ReportSummary summary;
  final PeriodRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final kind = range.kind;
    final previous = ref.watch(reportsPreviousRangeProvider);
    final previousSummary = ref
        .watch(reportsSummaryProvider(previous))
        .valueOrNull;
    // Always the EXPENSE breakdown, whatever the donut's toggle says.
    final expenseSlices = ref
        .watch(reportsByCategoryProvider(CategoryBreakdownQuery(range)))
        .valueOrNull;

    final net = summary.net;
    final days = ReportMetrics.daysElapsed(range.start, range.end);
    final avgDaily = ReportMetrics.avgDailySpend(summary, range.start, range.end);
    final savingsRate = ReportMetrics.savingsRate(summary);
    final top = ReportMetrics.biggest(expenseSlices ?? const []);
    final momPct = previousSummary == null
        ? null
        : ReportMetrics.changeVsPrevious(summary.expense, previousSummary.expense);

    return Column(
      children: [
        StatCard(
          label: 'Income',
          icon: LucideIcons.arrowDownLeft,
          accent: c.income,
          amount: summary.income,
          tone: MoneyTone.income,
        ),
        const SizedBox(height: 12),
        StatCard(
          label: 'Expense',
          icon: LucideIcons.arrowUpRight,
          accent: c.expense,
          amount: summary.expense,
          tone: MoneyTone.expense,
          subtitle: summary.expenseCount == 1
              ? '1 transaction'
              : '${summary.expenseCount} transactions',
        ),
        const SizedBox(height: 12),
        StatCard(
          label: 'Net',
          icon: LucideIcons.piggyBank,
          accent: net < 0 ? c.expense : c.primary,
          amount: net,
          tone: net < 0
              ? MoneyTone.expense
              : (net > 0 ? MoneyTone.income : MoneyTone.neutral),
          subtitle: summary.income == 0 ? 'No income this period' : null,
        ),
        const SizedBox(height: 12),
        _TilePair(
          left: _MetricTile(
            label: 'Avg daily spend',
            hint: 'Total spent ÷ days elapsed in this period, so a partial '
                'month isn’t divided by a full 30 days.',
            subtitle: days == 1 ? 'over 1 day' : 'over $days days',
            value: MoneyText(
              avgDaily,
              tone: MoneyTone.expense,
              style: _valueStyle,
            ),
          ),
          right: _MetricTile(
            label: 'Savings rate',
            hint: 'Share of income kept after spending: '
                '(income − consumption) ÷ income × 100.',
            subtitle: savingsRate == null ? 'No income to divide by' : null,
            // A null rate is an em dash, never 0% — there was no income to
            // keep a share of.
            value: savingsRate == null
                ? _Dash(style: _valueStyle)
                : Text(
                    savingsRate < -100 ? '< −100%' : '$savingsRate%',
                    style: _valueStyle.copyWith(
                      color: savingsRate >= 0 ? c.income : c.expense,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        _TilePair(
          left: _MetricTile(
            label: 'Biggest expense',
            trailing: top == null
                ? null
                : Icon(
                    LucideIcons.chevronRight,
                    size: 15,
                    color: c.mutedForeground,
                  ),
            onTap: top == null
                ? null
                : () => openTransactions(
                    context,
                    ref,
                    range: range,
                    type: TransactionType.expense,
                    categoryId: top.categoryId,
                  ),
            subtitle: top == null
                ? null
                : '${Money.format(top.total)} · '
                      '${Money.percent(top.percent, alreadyScaled: true)}',
            value: top == null
                ? _Dash(style: _valueStyle)
                : Text(
                    top.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _valueStyle.copyWith(fontSize: 16),
                  ),
          ),
          right: _MetricTile(
            label: 'Spending vs last ${kind.noun}',
            subtitle: previousSummary == null || previousSummary.expense <= 0
                ? null
                : 'Last ${kind.noun}: '
                      '${Money.compact(previousSummary.expense)}',
            value: momPct == null
                ? _Dash(style: _valueStyle)
                : _Change(pct: momPct),
          ),
        ),
        if (summary.expense > 0) ...[
          const SizedBox(height: 12),
          _ConsumptionCard(summary: summary),
        ],
        if (top != null) ...[
          const SizedBox(height: 12),
          _InsightBanner(top: top, kind: kind, momPct: momPct),
        ],
      ],
    );
  }

  static const TextStyle _valueStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
}

/// Two equal-height tiles on one line. [IntrinsicHeight] is what keeps the
/// shorter one from leaving a ragged edge when only one has a subtitle.
class _TilePair extends StatelessWidget {
  const _TilePair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    ),
  );
}

/// One derived figure: label (with an optional tap-to-read hint), a value and
/// an optional caption. 154dp wide at 360dp, so every string is either
/// ellipsised or scaled down rather than allowed to overflow.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.subtitle,
    this.hint,
    this.trailing,
    this.onTap,
  });

  final String label;
  final Widget value;
  final String? subtitle;

  /// The web shows this in a hover tooltip; on a phone it is tap-to-reveal.
  final String? hint;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                ),
              ),
              if (hint != null)
                Tooltip(
                  message: hint!,
                  triggerMode: TooltipTriggerMode.tap,
                  showDuration: const Duration(seconds: 6),
                  preferBelow: false,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  textStyle: TextStyle(
                    fontSize: 12,
                    color: c.primaryForeground,
                  ),
                  child: Semantics(
                    button: true,
                    label: 'About $label',
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, top: 1),
                      child: Icon(
                        LucideIcons.info,
                        size: 14,
                        color: c.mutedForeground,
                      ),
                    ),
                  ),
                ),
              if (trailing != null) ...[const SizedBox(width: 2), trailing!],
            ],
          ),
          const SizedBox(height: 7),
          // Scale down rather than clip: ₹12,34,56,789 at 20sp is wider than
          // the tile, and a truncated amount is worse than a small one.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: value,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

/// The em dash a null metric renders as. Never a zero.
class _Dash extends StatelessWidget {
  const _Dash({required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text(
    '—',
    style: style.copyWith(color: context.colors.mutedForeground),
  );
}

/// "↗ 12% higher" — the month-on-month spending arrow.
class _Change extends StatelessWidget {
  const _Change({required this.pct});

  final int pct;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Spending more is bad, so up is red. Equal is neither.
    final up = pct > 0;
    final color = pct == 0 ? c.mutedForeground : (up ? c.expense : c.income);
    final word = pct == 0 ? 'same' : (up ? 'higher' : 'lower');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          '${pct.abs()}% $word',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// MOBILE ADDITION — the web has no card for this.
///
/// The savings rate above divides by `consumption`, not `expense`, and there
/// is nowhere else in the app that says so. Money moved into a goal or a
/// deposit is spent but not consumed; on a month where the two differ, a
/// savings rate that looks wrong is explained entirely by this split. Shown
/// only when something was actually spent.
class _ConsumptionCard extends StatelessWidget {
  const _ConsumptionCard({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = summary.consumption + summary.nonConsumption;
    final consumedShare = total <= 0
        ? 0.0
        : (summary.consumption / total).clamp(0.0, 1.0).toDouble();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Where it went',
            subtitle: 'Consumed vs set aside',
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: consumedShare,
              minHeight: 8,
              backgroundColor: c.income.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation(c.expense),
            ),
          ),
          const SizedBox(height: 12),
          _SplitRow(
            color: c.expense,
            label: 'Consumed',
            caption: 'Gone for good — the savings-rate denominator',
            amount: summary.consumption,
          ),
          const SizedBox(height: 8),
          _SplitRow(
            color: c.income,
            label: 'Set aside',
            caption: 'Into goals, deposits and savings',
            amount: summary.nonConsumption,
          ),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.color,
    required this.label,
    required this.caption,
    required this.amount,
  });

  final Color color;
  final String label;
  final String caption;
  final num amount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                caption,
                style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        MoneyText(
          amount,
          compactAbove: Money.crore,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// The one-sentence takeaway the web puts under the stat grid.
class _InsightBanner extends StatelessWidget {
  const _InsightBanner({
    required this.top,
    required this.kind,
    required this.momPct,
  });

  final CategorySlice top;
  final PeriodKind kind;
  final int? momPct;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const amber = Color(0xFFF59E0B);

    final spans = <TextSpan>[
      TextSpan(text: 'This ${kind.noun} your biggest expense is '),
      TextSpan(
        text: top.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      TextSpan(
        text: ' (${Money.format(top.total)}, '
            '${Money.percent(top.percent, alreadyScaled: true)} of spending)',
      ),
    ];

    if (momPct != null) {
      final pct = momPct!;
      spans
        ..add(const TextSpan(text: '. Overall spending is '))
        ..add(
          TextSpan(
            text: pct == 0
                ? 'the same'
                : '${pct.abs()}% ${pct > 0 ? 'higher' : 'lower'}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: pct == 0
                  ? c.foreground
                  : (pct > 0 ? c.expense : c.income),
            ),
          ),
        )
        ..add(TextSpan(text: ' than last ${kind.noun}'));
    }
    spans.add(const TextSpan(text: '.'));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.lightbulb, size: 16, color: amber),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(children: spans),
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: c.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The two trend cards
// ─────────────────────────────────────────────────────────────────────────────

class _TrendCard extends ConsumerWidget {
  const _TrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportsRangeProvider);
    final trend = ref.watch(reportsTrendProvider(range));
    final c = context.colors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Income vs Expense',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          trend.when(
            loading: () => const _ChartLoading(),
            error: (error, _) => ErrorRetry(
              error: error,
              compact: true,
              onRetry: () => ref.invalidate(reportsTrendProvider(range)),
            ),
            data: (points) => Column(
              children: [
                IncomeVsExpenseChart(points: points),
                if (points.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LegendDot(color: c.income, label: 'Income'),
                      const SizedBox(width: 18),
                      _LegendDot(color: c.expense, label: 'Expense'),
                    ],
                  ),
                  if (points.length == 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      'One bucket with activity in this period.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NetCashFlowCard extends ConsumerWidget {
  const _NetCashFlowCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportsRangeProvider);
    final trend = ref.watch(reportsTrendProvider(range));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Net cash flow',
            subtitle: 'Income minus expense over time',
          ),
          const SizedBox(height: 12),
          trend.when(
            loading: () => const _ChartLoading(),
            error: (error, _) => ErrorRetry(
              error: error,
              compact: true,
              onRetry: () => ref.invalidate(reportsTrendProvider(range)),
            ),
            data: (points) => NetCashFlowChart(points: points),
          ),
        ],
      ),
    );
  }
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: kReportChartHeight,
    child: Center(child: LoadingShimmer(width: 220, height: 140, radius: 12)),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12.5)),
    ],
  );
}
