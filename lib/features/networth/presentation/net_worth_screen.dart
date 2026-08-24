import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../../holdings/data/holdings_repository.dart';
import '../../holdings/presentation/holdings_screen.dart';
import '../../loans/data/loans_repository.dart';
import '../data/networth_repository.dart';
import 'networth_providers.dart';
import 'widgets/breakdown_card.dart';
import 'widgets/net_worth_chart.dart';

/// `/net-worth` — the hero figure, its trend, and where it comes from.
///
/// Body only; [AppScaffold] supplies the app bar and bottom nav.
///
/// Every figure is read from the newest `/networth/history` snapshot. That
/// number is routinely **negative** on a real wallet (a ₹2Cr home loan against
/// almost no assets), so nothing here assumes growth, a positive base, or more
/// than a single snapshot.
class NetWorthScreen extends ConsumerWidget {
  const NetWorthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(netWorthSeriesProvider);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'Net Worth',
            subtitle: 'Your assets, investments and loans in one place',
            actions: [
              ScreenHeaderAction(
                label: 'Manage holdings',
                icon: LucideIcons.piggyBank,
                primary: false,
                onPressed: () => context.go(HoldingsScreen.routePath),
              ),
            ],
          ),
          switch (series) {
            // Stale-while-revalidate. The range pills, hero figure and totals
            // all live inside `_Body`, so swapping it for placeholders on every
            // reload blanks the very control the user just tapped. Riverpod
            // carries the previous value through the reload, but an
            // `AsyncData` pattern will not match the `AsyncLoading` that holds
            // it — match on the value instead. An error still shows below when
            // there is nothing cached to fall back to.
            AsyncValue(:final valueOrNull?) => _Body(series: valueOrNull),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(netWorthHistoryRangeProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 3),
                  SizedBox(height: 12),
                  LoadingCard(lines: 2),
                  SizedBox(height: 12),
                  LoadingCard(lines: 5),
                ],
              ),
            ),
          },
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(netWorthHistoryProvider)
      ..invalidate(netWorthHistoryRangeProvider)
      ..invalidate(holdingsProvider)
      ..invalidate(loansProvider);
    try {
      await ref.read(netWorthSeriesProvider.future);
    } catch (_) {
      // The failure is rendered from the provider; the spinner just stops.
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.series});

  final NetWorthSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(netWorthBreakdownViewProvider);

    return Column(
      children: [
        const SizedBox(height: 12),
        _Padded(child: _HeroCard(series: series)),
        const SizedBox(height: 12),
        _Padded(child: _AssetsCard(series: series)),
        const SizedBox(height: 12),
        _Padded(child: _LiabilitiesCard(series: series)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedPeriodSelector<BreakdownView>(
                options: [
                  for (final option in BreakdownView.values)
                    SegmentOption(option, option.label),
                ],
                value: view,
                onChanged: (next) => ref
                    .read(netWorthBreakdownViewProvider.notifier)
                    .state = next,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (view != BreakdownView.liabilities) ...[
          _Padded(child: _TrendCard(series: series)),
          const SizedBox(height: 12),
        ],
        _Padded(
          child: BreakdownCard(
            series: series,
            view: view,
            onManageHoldings: () => context.go(HoldingsScreen.routePath),
            onViewLoans: () => context.go('/loans'),
          ),
        ),
        const SizedBox(height: 12),
        _Padded(child: _GrowthCard(series: series)),
        const SizedBox(height: 12),
        const _Padded(child: _HoldingsLink()),
      ],
    );
  }
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

/// The headline figure, its movement over the selected window, and a plain
/// sentence saying what it means.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.series});

  final NetWorthSeries series;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = series.netWorth;
    final negative = value < 0;
    final accent = negative ? c.expense : c.income;
    final delta = series.delta;

    return AppCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(accent.withValues(alpha: 0.09), c.card),
          c.card,
        ],
      ),
      borderColor: accent.withValues(alpha: 0.22),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Net worth',
                  style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  negative ? LucideIcons.trendingDown : LucideIcons.trendingUp,
                  size: 17,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // −₹2,00,00,000 is fourteen glyphs at 32sp; scaling down beats
          // clipping the minus sign off a negative figure.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (delta != null)
            Row(
              children: [
                Icon(
                  delta >= 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                  size: 15,
                  color: delta >= 0 ? c.income : c.expense,
                ),
                const SizedBox(width: 6),
                MoneyText(
                  delta,
                  tone: delta >= 0 ? MoneyTone.income : MoneyTone.expense,
                  signed: true,
                  compact: true,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                // The percentage and the window read as one caption, and one
                // Flexible child is what keeps a nine-figure swing from
                // pushing the line off the card.
                Flexible(
                  child: Text(
                    series.deltaPercent == null
                        ? 'over ${series.range.description}'
                        : '(${Money.signedPercent(series.deltaPercent)}) '
                              'over ${series.range.description}',
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
          if (delta != null) const SizedBox(height: 8),
          Text(
            negative
                ? 'You owe more than you own — paying down loans lifts this.'
                : 'Everything you own, minus everything you owe.',
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _AssetsCard extends ConsumerWidget {
  const _AssetsCard({required this.series});

  final NetWorthSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final holdings = ref.watch(holdingsProvider).valueOrNull;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Total assets',
            actionLabel: 'Accounts →',
            onAction: () => context.go('/accounts'),
          ),
          const SizedBox(height: 6),
          // The exact figure, the way the web app states it. FittedBox is what
          // keeps a ten-figure balance on one line; compacting this to "₹2Cr"
          // would hide the very number the card exists to show. Dense rows,
          // where a label has to share the width, keep compactAbove.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              series.assets,
              tone: series.assets < 0 ? MoneyTone.expense : MoneyTone.income,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          _MiniRow(label: 'Accounts', value: series.accountsTotal),
          _MiniRow(
            label: 'Holdings',
            value: series.holdingsTotal,
            // "none yet" only when there really is nothing recorded — a real
            // holding worth ₹0 still deserves a ₹0.
            emptyLabel: (holdings == null || holdings.isEmpty)
                ? 'none yet'
                : null,
          ),
          _MiniRow(
            label: 'Stocks',
            value: series.stocksTotal,
            emptyLabel: 'none yet',
          ),
          if (series.hasOtherAssets)
            _MiniRow(label: 'Other', value: series.otherAssets),
          if (series.accountsTotal < 0) ...[
            const SizedBox(height: 8),
            Text(
              'One or more accounts are overdrawn, which pulls assets below zero.',
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiabilitiesCard extends ConsumerWidget {
  const _LiabilitiesCard({required this.series});

  final NetWorthSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final loans = ref.watch(loansProvider).valueOrNull;
    final active = loans?.where((loan) => loan.isActive).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Total liabilities',
            actionLabel: 'Loans →',
            onAction: () => context.go('/loans'),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              series.liabilities,
              tone: series.liabilities > 0
                  ? MoneyTone.expense
                  : MoneyTone.neutral,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            switch (active) {
              null => 'Outstanding across every loan',
              0 => 'No active loans',
              1 => 'Outstanding across 1 active loan',
              _ => 'Outstanding across $active active loans',
            },
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({required this.label, required this.value, this.emptyLabel});

  final String label;
  final num value;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blank = value == 0 && emptyLabel != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
            ),
          ),
          if (blank)
            Text(
              emptyLabel!,
              style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
            )
          else
            MoneyText(
              value,
              tone: value < 0 ? MoneyTone.expense : MoneyTone.neutral,
              compactAbove: Money.crore,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Net worth over time" — the range pills and the line itself.
class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.series});

  final NetWorthSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final selected = ref.watch(netWorthRangeProvider);
    final delta = series.delta;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Net worth over time',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              _RangePills(
                selected: selected,
                onChanged: (range) =>
                    ref.read(netWorthRangeProvider.notifier).state = range,
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              series.netWorth,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: series.netWorth < 0 ? c.expense : c.income,
              ),
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                MoneyText(
                  delta,
                  tone: delta >= 0 ? MoneyTone.income : MoneyTone.expense,
                  signed: true,
                  compact: true,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (series.deltaPercent != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(${Money.signedPercent(series.deltaPercent)})',
                    style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                  ),
                ],
              ],
            ),
          ] else if (series.points.length == 1) ...[
            const SizedBox(height: 2),
            Text(
              'One snapshot so far — a trend needs two.',
              style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
            ),
          ],
          const SizedBox(height: 14),
          NetWorthChart(points: series.points),
        ],
      ),
    );
  }
}

class _RangePills extends StatelessWidget {
  const _RangePills({required this.selected, required this.onChanged});

  final NetWorthRange selected;
  final ValueChanged<NetWorthRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final range in NetWorthRange.values)
            GestureDetector(
              onTap: range == selected ? null : () => onChanged(range),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: range == selected ? c.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  range.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: range == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: range == selected
                        ? c.foreground
                        : c.mutedForeground,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How the figure has moved, in words rather than pixels.
class _GrowthCard extends StatelessWidget {
  const _GrowthCard({required this.series});

  final NetWorthSeries series;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final delta = series.delta;

    if (delta == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Growth',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              series.isEmpty
                  ? 'No snapshots yet. Net worth is recorded automatically as '
                        'your accounts, holdings and loans change.'
                  : 'Only one snapshot in ${series.range.description} — growth '
                        'appears once there are two to compare.',
              style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
            ),
          ],
        ),
      );
    }

    final best = series.bestStep;
    final worst = series.worstStep;
    final showExtremes = series.points.length >= 3 && best != null &&
        worst != null && best.to.date != worst.to.date;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Growth',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'last ${series.range.description}',
                style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GrowthRow(
            label: 'Change',
            value: delta,
            signed: true,
            trailing: series.deltaPercent == null
                ? null
                : Money.signedPercent(series.deltaPercent),
          ),
          _GrowthRow(
            label: 'Started at',
            value: series.first!.netWorth,
            trailing: DateX.shortDay(series.first!.date),
          ),
          _GrowthRow(
            label: 'Now',
            value: series.last!.netWorth,
            trailing: DateX.shortDay(series.last!.date),
          ),
          if (series.perMonth != null)
            _GrowthRow(
              label: 'Average per month',
              value: series.perMonth!,
              signed: true,
              trailing: '${series.spanDays} days tracked',
            ),
          if (showExtremes) ...[
            const SizedBox(height: 6),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 6),
            _GrowthRow(
              label: 'Best move',
              value: best.delta,
              signed: true,
              trailing: DateX.shortDay(best.to.date),
            ),
            _GrowthRow(
              label: 'Weakest move',
              value: worst.delta,
              signed: true,
              trailing: DateX.shortDay(worst.to.date),
            ),
          ],
        ],
      ),
    );
  }
}

class _GrowthRow extends StatelessWidget {
  const _GrowthRow({
    required this.label,
    required this.value,
    this.signed = false,
    this.trailing,
  });

  final String label;
  final num value;
  final bool signed;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14)),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MoneyText(
            value,
            tone: signed
                ? (value >= 0 ? MoneyTone.income : MoneyTone.expense)
                : (value < 0 ? MoneyTone.expense : MoneyTone.neutral),
            signed: signed,
            compactAbove: Money.crore,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The way into the holdings list from here, mirroring the header action for
/// anyone who has scrolled past it.
class _HoldingsLink extends ConsumerWidget {
  const _HoldingsLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final holdings = ref.watch(holdingsProvider).valueOrNull;
    final count = holdings?.length;
    final total = holdings?.fold<num>(0, (sum, h) => sum + h.value);

    return AppCard(
      onTap: () => context.go(HoldingsScreen.routePath),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(LucideIcons.piggyBank, size: 19, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manage holdings',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  switch (count) {
                    null => 'Savings and investments',
                    0 => 'Add your first saving or investment',
                    1 => '1 holding · ${Money.compact(total ?? 0)}',
                    _ => '$count holdings · ${Money.compact(total ?? 0)}',
                  },
                  style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: c.mutedForeground),
        ],
      ),
    );
  }
}
