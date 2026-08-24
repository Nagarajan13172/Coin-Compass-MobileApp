import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../../../core/api/json.dart';
import '../domain/metal_price.dart';

/// `/metals/*` — gold and silver rates.
///
/// `configured` is false when the deployment has no metals provider wired up;
/// in that case `gold` and `silver` are null and the UI shows an empty state
/// rather than an error.
class MetalsRepository {
  const MetalsRepository(this._api);

  final ApiClient _api;

  Future<MetalsLatest> latest() async {
    final json = await _api.getJson(Endpoints.metalsLatest);
    return MetalsLatest.fromJson(J.map(json));
  }

  /// `GET /metals/history?metal=gold&days=90` — a bare array of rows in exactly
  /// the shape `/metals/latest` nests under `gold`/`silver` (verified live), one
  /// per day the cron captured. Returned **oldest first** so it can be fed
  /// straight to a trend chart.
  ///
  /// [metal] is `gold` or `silver`; [days] matches the web client's default
  /// window of 90.
  Future<List<MetalPrice>> history({
    required String metal,
    int days = 90,
  }) async {
    final json = await _api.getJson(
      Endpoints.metalsHistory,
      query: {'metal': metal, 'days': days},
    );
    final rows = Envelope.rows(json, const [
      'history',
      'prices',
    ]).map(MetalPrice.fromJson).toList();
    // `date` is a plain `yyyy-MM-dd`, so it sorts lexicographically.
    rows.sort((a, b) => (a.date ?? '').compareTo(b.date ?? ''));
    return rows;
  }

  /// Re-fetches today's rates from the upstream provider and returns the fresh
  /// `latest` payload. Takes no body.
  ///
  /// This calls out to a live scraper — wire it to an explicit user action, and
  /// invalidate [metalsLatestProvider] plus any [metalsHistoryProvider] after it
  /// resolves.
  Future<MetalsLatest> refresh() async {
    final json = await _api.postJson(Endpoints.metalsRefresh);
    return MetalsLatest.fromJson(J.map(json));
  }
}

final metalsRepositoryProvider = Provider<MetalsRepository>(
  (ref) => MetalsRepository(ref.watch(apiClientProvider)),
);

/// Prices refresh server-side once a day, so this is cached for the session.
final metalsLatestProvider = FutureProvider<MetalsLatest>(
  (ref) => ref.watch(metalsRepositoryProvider).latest(),
);

/// The history behind one metal's chart, keyed by `(metal, days)`. Records give
/// the family argument value equality for free, so the same pair reuses the
/// cached series instead of refetching.
final metalsHistoryProvider = FutureProvider.autoDispose
    .family<List<MetalPrice>, ({String metal, int days})>(
      (ref, key) => ref
          .watch(metalsRepositoryProvider)
          .history(metal: key.metal, days: key.days),
    );
