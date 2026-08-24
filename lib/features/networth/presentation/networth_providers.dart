import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/networth_repository.dart';
import '../domain/net_worth_point.dart';

/// The look-back windows offered above the trend chart, matching the web app's
/// `1M / 3M / 1Y / All` pill group.
enum NetWorthRange {
  month1(30, '1M', '1 month'),
  month3(90, '3M', '3 months'),
  year1(365, '1Y', '1 year'),
  all(3650, 'All', 'all time');

  const NetWorthRange(this.days, this.label, this.description);

  final int days;
  final String label;
  final String description;

  bool get isAll => this == NetWorthRange.all;
}

/// Which half of the breakdown the card is showing.
enum BreakdownView {
  overview('Overview'),
  assets('Assets'),
  liabilities('Liabilities');

  const BreakdownView(this.label);
  final String label;
}

final netWorthRangeProvider = StateProvider<NetWorthRange>(
  (ref) => NetWorthRange.month3,
);

final netWorthBreakdownViewProvider = StateProvider<BreakdownView>(
  (ref) => BreakdownView.overview,
);

/// `/networth/history` narrowed to the selected window, plus everything the
/// screen derives from it.
///
/// The window is applied twice on purpose: `days` goes out as a query so the
/// server can narrow the response, and the same cutoff is applied again here
/// because there is no proof the endpoint honours it — the recorded response
/// came back as a bare, unfiltered array.
final netWorthSeriesProvider = FutureProvider.autoDispose<NetWorthSeries>((
  ref,
) async {
  final range = ref.watch(netWorthRangeProvider);
  final points = await ref.watch(
    netWorthHistoryRangeProvider(range.days).future,
  );
  return NetWorthSeries.from(points, range);
});

/// One consecutive step in the series — used by the growth section.
@immutable
class NetWorthStep {
  const NetWorthStep({required this.from, required this.to});

  final NetWorthPoint from;
  final NetWorthPoint to;

  num get delta => to.netWorth - from.netWorth;
}

/// The snapshots inside one window, and the figures the screen reads off them.
///
/// Real data is thin — the recorded account has exactly two snapshots, and the
/// older one predates `stocksTotal` entirely — so every derived figure is
/// nullable rather than faked, and nothing here assumes more than one point.
@immutable
class NetWorthSeries {
  const NetWorthSeries({
    required this.range,
    required this.points,
    required this.latest,
  });

  final NetWorthRange range;

  /// Oldest first. May be empty (no snapshot ever) or hold a single row.
  final List<NetWorthPoint> points;

  /// Newest snapshot in the *whole* history, even when it falls outside the
  /// window — the hero figure must never go blank because of a range pill.
  final NetWorthPoint? latest;

  factory NetWorthSeries.from(List<NetWorthPoint> all, NetWorthRange range) {
    final sorted = [...all]..sort((a, b) => a.date.compareTo(b.date));
    final newest = sorted.isEmpty ? null : sorted.last;

    var window = sorted;
    if (!range.isAll && sorted.isNotEmpty) {
      final cutoff = DateTime.now().subtract(Duration(days: range.days));
      final kept = sorted
          .where((point) => !point.date.isBefore(cutoff))
          .toList();
      // A wallet whose only snapshot predates the window still has something
      // to show; an empty chart would read as "no data" rather than "no
      // movement".
      window = kept.isEmpty ? [sorted.last] : kept;
    }

    return NetWorthSeries(range: range, points: window, latest: newest);
  }

  bool get isEmpty => points.isEmpty;

  /// True once the window holds enough rows to draw a trend.
  bool get hasTrend => points.length >= 2;

  NetWorthPoint? get first => points.isEmpty ? null : points.first;
  NetWorthPoint? get last => points.isEmpty ? null : points.last;

  num get netWorth => latest?.netWorth ?? 0;
  num get assets => latest?.assets ?? 0;
  num get liabilities => latest?.liabilities ?? 0;
  num get accountsTotal => latest?.accountsTotal ?? 0;
  num get holdingsTotal => latest?.holdingsTotal ?? 0;
  num get stocksTotal => latest?.stocksTotal ?? 0;

  /// Whatever `assets` carries that the three named components do not account
  /// for. Older snapshots have no `stocksTotal` at all, so this is how the
  /// card stays honest instead of silently mis-attributing the difference.
  num get otherAssets =>
      assets - accountsTotal - holdingsTotal - stocksTotal;

  bool get hasOtherAssets => otherAssets.abs() >= 1;

  /// Movement across the window, or null when there is nothing to compare.
  num? get delta =>
      hasTrend ? points.last.netWorth - points.first.netWorth : null;

  /// Percent movement, measured against the **magnitude** of the starting
  /// figure: a net worth of −₹2.07Cr rising to −₹2Cr is a 3.6% improvement,
  /// and dividing by a negative base would flip that sign.
  num? get deltaPercent {
    final change = delta;
    if (change == null) return null;
    final base = points.first.netWorth.abs();
    if (base == 0) return null;
    return change / base * 100;
  }

  /// Whole days the window's snapshots span.
  int get spanDays =>
      hasTrend ? points.last.date.difference(points.first.date).inDays : 0;

  /// Average movement per 30 days, or null when the span is too short to mean
  /// anything.
  num? get perMonth {
    final change = delta;
    if (change == null || spanDays < 1) return null;
    return change / spanDays * 30;
  }

  List<NetWorthStep> get steps => [
    for (var i = 1; i < points.length; i++)
      NetWorthStep(from: points[i - 1], to: points[i]),
  ];

  NetWorthStep? get bestStep {
    final all = steps;
    if (all.isEmpty) return null;
    return all.reduce((a, b) => b.delta > a.delta ? b : a);
  }

  NetWorthStep? get worstStep {
    final all = steps;
    if (all.isEmpty) return null;
    return all.reduce((a, b) => b.delta < a.delta ? b : a);
  }
}
