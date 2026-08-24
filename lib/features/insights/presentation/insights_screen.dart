import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/period_pager.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../../../core/widgets/stat_card.dart';
import '../../reports/presentation/period.dart';
import '../../transactions/presentation/open_transactions.dart';
import '../domain/insights.dart';
import 'insights_providers.dart';
import '../../../core/router/route_refresh.dart';

/// `/insights` — how this period compares with the last one.
///
/// Body only; [AppScaffold] supplies the app bar and bottom nav.
///
/// The whole screen is driven by one read, `GET /reports/insights`, and the
/// single hardest thing about it is that **every percentage can be null**. The
/// server returns `pct: null` — not 0 — whenever the previous period was zero,
/// and on this account that is currently true of expense, income, net, the
/// savings rate and every mover at once. So a first period with no history is
/// treated here as a *designed* state, not a fallback: the delta pill states
/// the amount instead of a percentage, the sub-line says "nothing last month"
/// rather than printing a dead "Last month: ₹0", and the highlights card ends
/// with a line explaining that comparisons start next period. Nothing on this
/// screen ever divides by [Delta.previous].
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  static const String routePath = '/insights';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(currentInsightsProvider);

    final c = context.colors;

    return RefreshIndicator(
      color: c.primary,
      backgroundColor: c.card,
      onRefresh: () => refreshCurrentRoute(ref, '/insights'),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // The shell's chrome overlaps the body, so the tail pads past the nav
        // bar and the raised FAB — `shellBottomInset`, not a hardcoded 110.
        padding: EdgeInsets.only(bottom: shellBottomInset(context)),
        children: [
          const ScreenHeader(
            title: 'Insights',
            subtitle: 'How your spending is changing, period over period.',
          ),
          const _PeriodBar(),
          const _Caption(),
          switch (insights) {
            // Stale-while-revalidate: paging to another period keeps the last
            // payload on screen until the new one lands, so the pager the user
            // just tapped does not jump around under a skeleton. An
            // `AsyncData` pattern would not match the `AsyncLoading` that
            // carries the previous value, so the value is matched instead.
            AsyncValue(:final valueOrNull?) when valueOrNull.hasData => _Body(
              insights: valueOrNull,
            ),
            AsyncValue(valueOrNull: _?) => const _NotEnoughData(),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(insightsProvider),
              ),
            ),
            _ => const _Skeleton(),
          },
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Chrome: period bar, caption, skeleton, empty
// ═══════════════════════════════════════════════════════════════════════════

/// Week | Month | Year, then the ◀ label ▶ pager. The web keeps both on one
/// wrapping row; at 360dp there is no room for that, so they stack — the same
/// two controls, one above the other.
class _PeriodBar extends ConsumerWidget {
  const _PeriodBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(insightsPeriodKindProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The three pills measure ~215dp, which fits — but a longer label in
          // another language would not, and a clipped segmented control is a
          // dead control.
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedPeriodSelector<PeriodKind>(
                options: [
                  for (final option in PeriodKind.values)
                    SegmentOption(option, option.shortLabel),
                ],
                value: kind,
                onChanged: (next) =>
                    ref.read(insightsPeriodKindProvider.notifier).state = next,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _PeriodPager(),
        ],
      ),
    );
  }
}

/// The shared [PeriodPager], driving this screen's own anchor. Reports uses
/// the same control, so the two screens page identically.
class _PeriodPager extends ConsumerWidget {
  const _PeriodPager();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(insightsPeriodKindProvider);
    final range = ref.watch(insightsRangeProvider);

    void shift(int steps) {
      final anchor = ref.read(insightsAnchorProvider);
      ref.read(insightsAnchorProvider.notifier).state = shiftAnchor(
        kind,
        anchor,
        steps,
      );
    }

    return PeriodPager(
      label: range.periodLabel,
      onPrevious: () => shift(-1),
      onNext: () => shift(1),
    );
  }
}

/// `Showing **August 2026**`. Unlike Reports there is no "· Month view"
/// suffix here — the web omits it on this screen.
class _Caption extends ConsumerWidget {
  const _Caption();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final range = ref.watch(insightsRangeProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text.rich(
        TextSpan(
          text: 'Showing ',
          children: [
            TextSpan(
              text: range.periodLabel,
              style: TextStyle(
                color: c.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Column(
      children: [
        LoadingCard(lines: 2),
        SizedBox(height: 12),
        LoadingCard(lines: 2),
        SizedBox(height: 12),
        LoadingCard(lines: 2),
        SizedBox(height: 12),
        LoadingCard(lines: 3),
        SizedBox(height: 12),
        LoadingCard(lines: 4),
      ],
    ),
  );
}

class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: EmptyState(
      icon: LucideIcons.sparkles,
      title: 'Not enough data yet',
      message:
          'Add a few transactions and insights about your spending will show '
          'up here.',
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Body
// ═══════════════════════════════════════════════════════════════════════════

class _Body extends StatelessWidget {
  const _Body({required this.insights});

  final Insights insights;

  @override
  Widget build(BuildContext context) {
    final noun = _nounOf(insights.period);

    return Column(
      children: [
        const SizedBox(height: 8),
        _Padded(child: _HighlightsCard(insights: insights, noun: noun)),
        _Padded(
          child: _CompareCard(
            label: 'Spending',
            metric: insights.expense,
            noun: noun,
            noBaselineNote: 'nothing spent last $noun',
            hasBaseline: _hasBaseline(insights),
            goodWhenUp: false,
          ),
        ),
        _Padded(
          child: _CompareCard(
            label: 'Income',
            metric: insights.income,
            noun: noun,
            noBaselineNote: 'nothing earned last $noun',
            hasBaseline: _hasBaseline(insights),
            goodWhenUp: true,
          ),
        ),
        _Padded(
          child: _CompareCard(
            label: 'Net',
            metric: insights.net,
            noun: noun,
            noBaselineNote: 'nothing recorded last $noun',
            hasBaseline: _hasBaseline(insights),
            goodWhenUp: true,
          ),
        ),
        _Padded(child: _SavingsRateCard(insights: insights, noun: noun)),
        _Padded(child: _PaceCard(insights: insights, noun: noun)),
        _Padded(child: _MoversCard(insights: insights, noun: noun)),
        _Padded(child: _TopExpensesCard(insights: insights)),
      ],
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: child,
  );
}

/// `week` / `month` / `year`, straight off the response so the copy always
/// names the window the numbers actually came from.
String _nounOf(String period) => switch (period) {
  'week' => 'week',
  'year' => 'year',
  'month' => 'month',
  _ => 'period',
};

/// True once there is something to compare against. Every "vs last …" phrase
/// on this screen is gated on it.
bool _hasBaseline(Insights insights) =>
    insights.expense.previous != 0 ||
    insights.income.previous != 0 ||
    insights.net.previous != 0;

// ── highlights ─────────────────────────────────────────────────────────────

class _Highlight {
  const _Highlight(this.icon, this.color, this.text);

  final IconData icon;
  final Color color;
  final String text;
}

/// Up to three plain-English sentences about the period, in the web's order:
/// what you spent, what rose the most, where the period is heading.
class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.insights, required this.noun});

  final Insights insights;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _build(c);
    final firstPeriod = !_hasBaseline(insights);

    if (rows.isEmpty && !firstPeriod) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(c.primary.withValues(alpha: 0.10), c.card),
          Color.alphaBlend(c.income.withValues(alpha: 0.05), c.card),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(rows[i].icon, size: 16, color: rows[i].color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rows[i].text,
                    style: const TextStyle(fontSize: 13.5, height: 1.35),
                  ),
                ),
              ],
            ),
          ],
          if (firstPeriod) ...[
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 12),
            ],
            Text(
              'This is your first $noun with data — the comparisons fill in '
              'once there is a $noun to compare against.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: c.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_Highlight> _build(AppColors c) {
    final rows = <_Highlight>[];
    final expense = insights.expense;

    // 1 — always a spend line. With no baseline it simply states the amount;
    // there is no percentage to quote and none is invented.
    if (expense.pct == null) {
      rows.add(
        _Highlight(
          LucideIcons.sparkles,
          c.primary,
          "You've spent ${Money.format(expense.current)} this $noun.",
        ),
      );
    } else {
      final up = expense.delta > 0;
      rows.add(
        _Highlight(
          up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
          up ? c.expense : c.income,
          "You've spent ${Money.format(expense.current)} this $noun — "
          '${Money.percent(expense.pct!.abs(), alreadyScaled: true)} '
          '${up ? 'more' : 'less'} than last $noun.',
        ),
      );
    }

    // 2 — the biggest riser, if anything rose.
    final riser = insights.topRiser;
    if (riser != null) {
      rows.add(
        _Highlight(
          LucideIcons.lightbulb,
          // The web's amber lightbulb, via the shared `warning` token — the
          // same one the Reports insight banner and the Notifications warning
          // rows use.
          c.warning,
          riser.pct == null
              // "rose the most" reads oddly against a category that did not
              // exist last period, so a category with no history says so.
              ? '${riser.name} is new this $noun — '
                    '${Money.format(riser.delta)}.'
              : '${riser.name} rose the most — up '
                    '${Money.format(riser.delta)} '
                    '(${Money.percent(riser.pct!.abs(), alreadyScaled: true)}) '
                    'versus last $noun.',
        ),
      );
    }

    // 3 — where the period lands if nothing changes.
    if (insights.pace.isCurrent && insights.pace.projected > 0) {
      rows.add(
        _Highlight(
          LucideIcons.gauge,
          c.primary,
          "At this rate, you'll spend about "
          '${Money.format(insights.pace.projected)} by the end of the $noun.',
        ),
      );
    }

    return rows.length > 3 ? rows.sublist(0, 3) : rows;
  }
}

// ── compare cards ──────────────────────────────────────────────────────────

/// One metric, this period against the last. The value itself is never
/// colour-coded — a negative Net renders in plain foreground, as on the web;
/// only the pill carries the good/bad signal.
class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.label,
    required this.metric,
    required this.noun,
    required this.noBaselineNote,
    required this.hasBaseline,
    required this.goodWhenUp,
  });

  final String label;
  final Delta metric;
  final String noun;

  /// What the line beside the pill says when there is nothing to compare
  /// against — "nothing spent last month" instead of a dead "Last month: ₹0".
  final String noBaselineNote;

  /// Whether the PERIOD had any activity — not whether this one metric did.
  /// A month that earned and spent Rs 50,000 nets exactly 0, and judging the
  /// baseline from `metric.previous` alone made the Net card claim nothing was
  /// recorded last month when in fact Rs 1,00,000 moved through it.
  final bool hasBaseline;
  final bool goodWhenUp;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A zero delta against a real baseline is "no change", not "no history";
    // only a period with no activity at all suppresses the comparison.
    final showComparison = hasBaseline && metric.previous != 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              metric.current,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _DeltaPill(metric: metric, goodWhenUp: goodWhenUp),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  showComparison
                      ? 'vs last $noun'
                      : (hasBaseline
                            ? 'no change vs last $noun'
                            : noBaselineNote),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ),
            ],
          ),
          if (showComparison) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Last $noun: ',
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                Flexible(
                  child: MoneyText(
                    metric.previous,
                    tone: MoneyTone.muted,
                    compactAbove: Money.crore,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The delta chip. Three states, and only one of them shows a percentage:
///
/// * `delta == 0`      → a muted "No change".
/// * `pct == null`     → the compact **amount** ("↗ ₹13K"). This is the branch
///   the owner's account takes on every metric right now.
/// * otherwise         → "↗ 12%".
class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.metric, required this.goodWhenUp});

  final Delta metric;
  final bool goodWhenUp;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flat = metric.delta == 0;
    final up = metric.delta > 0;
    final good = up == goodWhenUp;
    final accent = flat
        ? c.mutedForeground
        : (good ? c.income : c.expense);

    final pct = metric.pct;
    final text = flat
        ? 'No change'
        : (pct == null
              // maximumFractionDigits 0, the way the web compacts this one
              // value — "₹13K", not "₹13.31K".
              ? Money.compact(metric.delta.abs(), decimals: 0)
              : Money.percent(pct.abs(), alreadyScaled: true));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: flat ? c.secondary : accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            flat
                ? LucideIcons.minus
                : (up ? LucideIcons.arrowUpRight : LucideIcons.arrowDownRight),
            size: 13,
            color: accent,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── savings rate ───────────────────────────────────────────────────────────

/// `savingsRate: {current, previous}` — both null whenever the period had no
/// income, which is this account's state today.
///
/// A deliberate mobile addition: the web parses this block on /insights and
/// renders it nowhere (its Reports screen computes its own rate from
/// `/reports/summary` instead).
///
/// ⚠️ CROSS-SCREEN NOTE: this is the **server's** rate; the one on Reports is
/// derived client-side as `(income − consumption) ÷ income`. The server's
/// formula is not recoverable from the bundle and cannot be observed against
/// this account — every period it has ever held has zero income, so both sides
/// render an em dash and agree today. They can only diverge on a period with
/// income *and* non-consumption spending. If that ever shows two different
/// percentages, this card is the one to drop: the web renders no savings rate
/// on Insights at all.
class _SavingsRateCard extends StatelessWidget {
  const _SavingsRateCard({required this.insights, required this.noun});

  final Insights insights;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = insights.savingsRateCurrent;
    final previous = insights.savingsRatePrevious;

    final subtitle = current == null
        ? 'No income this $noun — a savings rate needs income to divide by.'
        : (previous == null
              ? 'No income last $noun, so there is nothing to compare with yet.'
              : 'Last $noun: '
                    '${Money.percent(previous, alreadyScaled: true)}');

    return StatCard(
      label: 'Savings rate',
      icon: LucideIcons.percent,
      accent: current == null || current < 0 ? c.mutedForeground : c.income,
      // Money.percent renders an em dash for null, which is exactly what the
      // web prints for an absent rate.
      valueText: Money.percent(current, alreadyScaled: true),
      subtitle: subtitle,
    );
  }
}

// ── pace ───────────────────────────────────────────────────────────────────

/// How fast the period is being spent. The web lays this out as a three-up
/// grid that collapses to one column on mobile; one column it is, as
/// label-left / value-right rows.
class _PaceCard extends StatelessWidget {
  const _PaceCard({required this.insights, required this.noun});

  final Insights insights;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pace = insights.pace;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Spending pace',
            leading: Icon(
              LucideIcons.gauge,
              size: 17,
              color: c.mutedForeground,
            ),
          ),
          const SizedBox(height: 12),
          _PaceStat(
            label: 'Spent so far',
            value: insights.expense.current,
          ),
          _PaceStat(
            // avgPerDay comes back unrounded (554.6666…); the web rounds this
            // one to whole rupees while the Reports screen's own average keeps
            // its paise. Same number, two deliberate roundings.
            label: 'Avg per day',
            value: pace.avgPerDay.round(),
          ),
          _PaceStat(
            label: pace.isCurrent
                ? 'Projected this $noun'
                : 'Total this $noun',
            value: pace.projected,
            tone: MoneyTone.expense,
          ),
          if (pace.isCurrent && pace.daysInPeriod > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Day ${pace.daysElapsed} of ${pace.daysInPeriod}',
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
                ),
                Text(
                  '${pace.percentElapsed}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.mutedForeground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                // Determinate, always — an indeterminate bar here would spin
                // forever and take every widget test's `pumpAndSettle` with it.
                value: pace.progress,
                minHeight: 8,
                backgroundColor: c.secondary,
                valueColor: AlwaysStoppedAnimation<Color>(c.primary),
              ),
            ),
          ],
          // Only says something when there is a previous period to be ahead
          // of. previousToDate == 0 hides it entirely rather than reporting an
          // infinite percentage.
          if (pace.previousToDate > 0) ...[
            const SizedBox(height: 14),
            _PaceComparison(
              spent: insights.expense.current,
              previousToDate: pace.previousToDate,
              noun: noun,
            ),
          ],
        ],
      ),
    );
  }
}

class _PaceStat extends StatelessWidget {
  const _PaceStat({
    required this.label,
    required this.value,
    this.tone = MoneyTone.neutral,
  });

  final String label;
  final num value;
  final MoneyTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.mutedForeground),
            ),
          ),
          const SizedBox(width: 10),
          // Expanded, not Flexible. A Flexible shrink-wraps to the scaled text,
          // so `centerRight` had nothing to align within and the three values
          // ended at three different x positions instead of on the card edge
          // the progress bar below them defines.
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: MoneyText(
                  value,
                  tone: tone,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaceComparison extends StatelessWidget {
  const _PaceComparison({
    required this.spent,
    required this.previousToDate,
    required this.noun,
  });

  final num spent;
  final num previousToDate;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final diff = spent - previousToDate;
    final pct = (diff / previousToDate * 100).round().abs();

    final (IconData icon, Color color, String text) = switch (diff) {
      > 0 => (
        LucideIcons.trendingUp,
        c.expense,
        '$pct% faster than last $noun at this point',
      ),
      < 0 => (
        LucideIcons.trendingDown,
        c.income,
        '$pct% slower than last $noun at this point',
      ),
      _ => (
        LucideIcons.minus,
        c.mutedForeground,
        "Right on last $noun's pace",
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.3),
          ),
        ),
      ],
    );
  }
}

// ── movers ─────────────────────────────────────────────────────────────────

/// "What changed" — the categories that moved most, each with a diverging bar
/// pinned to a shared centre line.
class _MoversCard extends ConsumerWidget {
  const _MoversCard({required this.insights, required this.noun});

  final Insights insights;
  final String noun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final movers = insights.movers;
    // Floored at 1 so a list of nothing-but-zeros cannot divide by zero.
    final maxAbs = movers.fold<num>(
      1,
      (acc, m) => m.delta.abs() > acc ? m.delta.abs() : acc,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'What changed',
            subtitle: 'Biggest shifts vs last $noun',
            leading: Icon(
              LucideIcons.trendingUp,
              size: 17,
              color: c.mutedForeground,
            ),
          ),
          if (movers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No category changes to show.',
                  style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
                ),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            for (final mover in movers)
              _MoverRow(
                mover: mover,
                maxAbsDelta: maxAbs,
                // The window is the server's own current.start/current.end,
                // so the ledger can never disagree with the figure tapped.
                onTap: () => openTransactionsFiltered(
                  context,
                  ref,
                  from: insights.currentStart,
                  to: insights.currentEnd,
                  type: TransactionType.expense,
                  categoryId: mover.categoryId,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MoverRow extends StatelessWidget {
  const _MoverRow({
    required this.mover,
    required this.maxAbsDelta,
    required this.onTap,
  });

  final Mover mover;
  final num maxAbsDelta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final up = mover.delta > 0;
    final accent = up ? c.expense : c.income;
    final sign = up ? '+' : Money.minus;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryAvatar(
                  icon: mover.icon,
                  colorHex: mover.color,
                  size: 30,
                  fallbackColor: c.mutedForeground,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    mover.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Sign is stated explicitly: the delta is an absolute figure
                // and "₹13,312" alone would not say which way it went. The
                // figure stays exact — only a nine-figure swing, which would
                // squeeze the name to nothing, compacts.
                Text(
                  '$sign${Money.dense(mover.delta.abs())}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      // pct is null when this category had nothing last
                      // period. "New" is what that means, and it is what the
                      // web prints.
                      mover.pct == null
                          ? 'New'
                          : '$sign'
                                '${Money.percent(mover.pct!.abs(), alreadyScaled: true)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: c.mutedForeground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: _DivergingBar(
                delta: mover.delta,
                maxAbsDelta: maxAbsDelta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// A track with a centre tick: increases grow right in expense red, decreases
/// grow left in income green, both scaled against the largest mover.
class _DivergingBar extends StatelessWidget {
  const _DivergingBar({required this.delta, required this.maxAbsDelta});

  final num delta;
  final num maxAbsDelta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final half = width / 2;
        final ceiling = maxAbsDelta <= 0 ? 1 : maxAbsDelta;
        final extent =
            (delta.abs() / ceiling).clamp(0.0, 1.0).toDouble() * half;
        final left = delta > 0 ? half : half - extent;

        return SizedBox(
          height: 6,
          width: width,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.secondary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: half - 0.5,
                top: 0,
                bottom: 0,
                width: 1,
                child: ColoredBox(color: c.border),
              ),
              if (extent > 0)
                Positioned(
                  left: left,
                  top: 0,
                  bottom: 0,
                  width: extent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: delta > 0 ? c.expense : c.income,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── biggest expenses ───────────────────────────────────────────────────────

/// The largest single transactions in the window. Not tappable — the rows
/// carry a category *stub* with no id, so there is nothing to navigate to.
class _TopExpensesCard extends StatelessWidget {
  const _TopExpensesCard({required this.insights});

  final Insights insights;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = insights.topExpenses;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Biggest expenses',
            subtitle: 'Your largest single transactions this period',
            leading: Icon(
              LucideIcons.receipt,
              size: 17,
              color: c.mutedForeground,
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No expenses in this period.',
                  style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
                ),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.border),
              _TopExpenseRow(expense: rows[i]),
            ],
          ],
        ],
      ),
    );
  }
}

class _TopExpenseRow extends StatelessWidget {
  const _TopExpenseRow({required this.expense});

  final TopExpense expense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final category = expense.category;
    final date = expense.date;
    final subtitle = [
      category?.name.isNotEmpty == true ? category!.name : 'Uncategorized',
      if (date != null) DateX.shortDay(date),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CategoryAvatar(
            icon: category?.icon,
            colorHex: category?.color,
            size: 32,
            fallbackColor: c.mutedForeground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoneyText(
            expense.amount,
            tone: MoneyTone.expense,
            compactAbove: Money.crore,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ── drill-through ──────────────────────────────────────────────────────────

