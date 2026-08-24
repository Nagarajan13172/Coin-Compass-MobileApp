import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/settings_repository.dart';
import '../data/reports_repository.dart';
import '../domain/report_models.dart';
import 'period.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Reports reads
//
// Five requests per view — summary (current), summary (previous), by-category,
// trend, by-account — each behind its own provider so one failing endpoint
// degrades one card instead of blanking the screen.
//
// Every read is a `.family` keyed by the window rather than by the screen's
// state, which buys two things:
//
//   * paging back to a month you already looked at is instant, and
//   * the "Biggest expense" card and the Expense/Income donut collapse into a
//     single request whenever the toggle sits on its default, exactly the way
//     react-query dedupes them on the web.
//
// PARITY NOTE: the web's Reports page keeps its period in local component
// state, independent of the Dashboard's persisted one; Insights keeps a third.
// So these deliberately do NOT reuse [periodKindProvider] — flipping Reports to
// Year must not move the Dashboard. They are session-scoped rather than
// autoDispose, which is the one small divergence: drilling into a filtered
// transaction list and coming back keeps the month you were reading, where the
// web would have remounted the page and snapped back to today.
// ═══════════════════════════════════════════════════════════════════════════

/// Week / Month / Year on the Reports screen only. The web defaults to month.
final reportsPeriodKindProvider = StateProvider<PeriodKind>(
  (ref) => PeriodKind.month,
);

/// The instant the pager is anchored on. Held in state rather than recomputed
/// from `DateTime.now()` so the derived window is stable across rebuilds — a
/// window that changes identity on every frame would refetch forever.
final reportsAnchorProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// The window the screen is showing.
final reportsRangeProvider = Provider<PeriodRange>((ref) {
  final kind = ref.watch(reportsPeriodKindProvider);
  final anchor = ref.watch(reportsAnchorProvider);
  final settings = ref.watch(settingsProvider).valueOrNull;
  return PeriodRange.of(
    kind,
    anchor: anchor,
    // MOBILE-ONLY: the web hard-codes Monday on this screen and never reads
    // settings.firstDayOfWeek (the string does not appear in the bundle at
    // all). Honouring it here keeps every window in this app consistent with
    // the calendar and the budgets, at the cost of a divergence when the
    // setting is not 1.
    firstDayOfWeek: PeriodRange.normaliseFirstDayOfWeek(
      settings?.firstDayOfWeek ?? DateTime.monday,
    ),
  );
});

/// The window one period earlier — the only thing "Spending vs last month" and
/// its `momPct` are computed from.
final reportsPreviousRangeProvider = Provider<PeriodRange>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return ref
      .watch(reportsRangeProvider)
      .shifted(
        -1,
        firstDayOfWeek: PeriodRange.normaliseFirstDayOfWeek(
          settings?.firstDayOfWeek ?? DateTime.monday,
        ),
      );
});

/// Which side of the ledger the donut is showing. Local to the screen on the
/// web too; `expense` is its default.
final reportsBreakdownTypeProvider = StateProvider<String>((ref) => 'expense');

/// Groups | All for the category donut.
enum CategoryGrouping { group, flat }

/// The web persists this to localStorage and shares it with the Dashboard's
/// spending card. Nothing here is persisted yet — it resets on a cold start.
/// Flagged rather than hidden: matching the web means writing it to
/// shared_preferences, which is a separate change.
final categoryGroupingProvider = StateProvider<CategoryGrouping>(
  (ref) => CategoryGrouping.group,
);

/// A `/reports/by-category` request: a window plus the side of the ledger.
/// Value equality is what lets two cards asking for the same breakdown share
/// one request.
@immutable
class CategoryBreakdownQuery {
  const CategoryBreakdownQuery(this.range, {this.type = 'expense'});

  final PeriodRange range;

  /// `expense` or `income`.
  final String type;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryBreakdownQuery &&
          other.range == range &&
          other.type == type;

  @override
  int get hashCode => Object.hash(range, type);

  @override
  String toString() => 'CategoryBreakdownQuery($range, $type)';
}

/// `/reports/summary` for any window. Asked for twice per view: once for the
/// current window, once for [reportsPreviousRangeProvider].
final reportsSummaryProvider = FutureProvider.autoDispose
    .family<ReportSummary, PeriodRange>(
      (ref, range) => ref
          .watch(reportsRepositoryProvider)
          .summary(from: range.start, to: range.end),
    );

final reportsByCategoryProvider = FutureProvider.autoDispose
    .family<List<CategorySlice>, CategoryBreakdownQuery>(
      (ref, query) => ref
          .watch(reportsRepositoryProvider)
          .byCategory(
            from: query.range.start,
            to: query.range.end,
            type: query.type,
          ),
    );

final reportsByAccountProvider = FutureProvider.autoDispose
    .family<List<AccountSlice>, PeriodRange>(
      (ref, range) => ref
          .watch(reportsRepositoryProvider)
          .byAccount(from: range.start, to: range.end),
    );

/// `/reports/trend`. A week or a month is bucketed by day, a year by month —
/// the only two granularities the web ever sends.
final reportsTrendProvider = FutureProvider.autoDispose
    .family<List<TrendPoint>, PeriodRange>(
      (ref, range) => ref
          .watch(reportsRepositoryProvider)
          .trend(
            from: range.start,
            to: range.end,
            granularity: granularityFor(range.kind),
          ),
    );

TrendGranularity granularityFor(PeriodKind kind) => kind == PeriodKind.year
    ? TrendGranularity.month
    : TrendGranularity.day;

/// Pull-to-refresh. The web has none — react-query refetches on focus — so
/// this is a mobile addition. Invalidating the family roots drops every cached
/// window, not just the visible one, which is what a deliberate refresh should
/// do; only the visible reads are awaited so the spinner stops on time.
Future<void> refreshReports(WidgetRef ref) async {
  final range = ref.read(reportsRangeProvider);
  final previous = ref.read(reportsPreviousRangeProvider);
  final type = ref.read(reportsBreakdownTypeProvider);

  ref
    ..invalidate(reportsSummaryProvider)
    ..invalidate(reportsByCategoryProvider)
    ..invalidate(reportsByAccountProvider)
    ..invalidate(reportsTrendProvider);

  await Future.wait(<Future<Object?>>[
    _settle(ref.read(reportsSummaryProvider(range).future)),
    _settle(ref.read(reportsSummaryProvider(previous).future)),
    _settle(
      ref.read(
        reportsByCategoryProvider(
          CategoryBreakdownQuery(range, type: type),
        ).future,
      ),
    ),
    // The "Biggest expense" card always reads the expense breakdown, whatever
    // the toggle says; when the toggle is on its default this is the same
    // family instance as the one above and costs nothing extra.
    _settle(
      ref.read(reportsByCategoryProvider(CategoryBreakdownQuery(range)).future),
    ),
    _settle(ref.read(reportsByAccountProvider(range).future)),
    _settle(ref.read(reportsTrendProvider(range).future)),
  ]);
}

Future<Object?> _settle(Future<Object?> future) async {
  try {
    return await future;
  } catch (_) {
    // Handled by the card that owns the read.
    return null;
  }
}
