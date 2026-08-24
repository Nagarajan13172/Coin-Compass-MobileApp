import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reports/presentation/period.dart';
import '../data/insights_repository.dart';
import '../domain/insights.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Insights reads
//
// One request per view. As on Reports, the period is local to this screen —
// the web keeps a third independent copy here — so neither the Dashboard nor
// Reports moves when you page through insights.
// ═══════════════════════════════════════════════════════════════════════════

/// What `/reports/insights?period=` and `?ref=` are asked for. Value equality
/// keeps the family instance stable across rebuilds.
@immutable
class InsightsQuery {
  const InsightsQuery({this.kind = PeriodKind.month, required this.at});

  final PeriodKind kind;

  /// Any instant inside the period being asked about.
  final DateTime at;

  InsightsQuery shifted(int steps) =>
      InsightsQuery(kind: kind, at: shiftAnchor(kind, at, steps));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InsightsQuery && other.kind == kind && other.at == at;

  @override
  int get hashCode => Object.hash(kind, at);

  @override
  String toString() => 'InsightsQuery(${kind.name}, $at)';
}

/// Week / Month / Year on the Insights screen only. Defaults to month, as the
/// web does.
final insightsPeriodKindProvider = StateProvider<PeriodKind>(
  (ref) => PeriodKind.month,
);

/// The `ref` instant the pager is on. Held in state so the query key does not
/// change identity on every rebuild.
final insightsAnchorProvider = StateProvider<DateTime>((ref) => DateTime.now());

final insightsQueryProvider = Provider<InsightsQuery>(
  (ref) => InsightsQuery(
    kind: ref.watch(insightsPeriodKindProvider),
    at: ref.watch(insightsAnchorProvider),
  ),
);

/// The window the screen is showing, for the caption above the cards.
///
/// Computed client-side purely for the label: every drill-through uses the
/// server's own `current.start`/`current.end` from the response instead, so a
/// disagreement about where a week starts can never send the transaction list
/// somewhere the numbers did not come from.
final insightsRangeProvider = Provider<PeriodRange>((ref) {
  final query = ref.watch(insightsQueryProvider);
  return PeriodRange.of(query.kind, anchor: query.at);
});

final insightsProvider = FutureProvider.autoDispose
    .family<Insights, InsightsQuery>(
      (ref, query) => ref
          .watch(insightsRepositoryProvider)
          .fetch(period: query.kind.apiValue, at: query.at),
    );

/// The instance the screen is actually showing.
final currentInsightsProvider = FutureProvider.autoDispose<Insights>(
  (ref) => ref.watch(insightsProvider(ref.watch(insightsQueryProvider)).future),
);

/// Pull-to-refresh — a mobile addition; the web refetches on window focus.
Future<void> refreshInsights(WidgetRef ref) async {
  ref.invalidate(insightsProvider);
  try {
    await ref.read(currentInsightsProvider.future);
  } catch (_) {
    // Rendered by the screen's own ErrorRetry.
  }
}
