import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../domain/net_worth_point.dart';

/// `GET /networth/history` — one snapshot row per month
/// (`netWorth`, `assets`, `liabilities`, and the account/holdings/stocks split).
///
/// Snapshots are written by a server-side job; there is no way to create one
/// from the client, so this repository is read-only.
class NetWorthRepository {
  const NetWorthRepository(this._api);

  final ApiClient _api;

  /// Oldest first, so the list can be fed straight to a trend chart and
  /// `.last` is always the current snapshot.
  ///
  /// [days] is the look-back window; the web client asks for 365.
  Future<List<NetWorthPoint>> history({int days = 365}) async {
    final json = await _api.getJson(
      Endpoints.netWorthHistory,
      query: {'days': days},
    );
    // The live endpoint returns a bare array; tolerate an envelope as well.
    final raw = json is Map ? (json['items'] ?? json['history']) : json;
    final points = J.list(raw, NetWorthPoint.fromJson)
      ..sort((a, b) => a.date.compareTo(b.date));
    return points;
  }
}

final netWorthRepositoryProvider = Provider<NetWorthRepository>(
  (ref) => NetWorthRepository(ref.watch(apiClientProvider)),
);

final netWorthHistoryProvider = FutureProvider<List<NetWorthPoint>>(
  (ref) => ref.watch(netWorthRepositoryProvider).history(),
);

/// The same series over a chosen window, for the range selector on the trend
/// chart.
final netWorthHistoryRangeProvider = FutureProvider.autoDispose
    .family<List<NetWorthPoint>, int>(
      (ref, days) => ref.watch(netWorthRepositoryProvider).history(days: days),
    );

/// The most recent snapshot, or null before the job has ever run. The headline
/// figures on the Net Worth screen come from here.
final netWorthLatestProvider = FutureProvider<NetWorthPoint?>((ref) async {
  final points = await ref.watch(netWorthHistoryProvider.future);
  return points.isEmpty ? null : points.last;
});
