import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../domain/net_worth_point.dart';

/// `GET /networth/history` — one snapshot row per month
/// (`netWorth`, `assets`, `liabilities`, and the account/holdings/stocks split).
class NetWorthRepository {
  const NetWorthRepository(this._api);

  final ApiClient _api;

  /// Oldest first, so the list can be fed straight to a trend chart and
  /// `.last` is always the current snapshot.
  Future<List<NetWorthPoint>> history() async {
    final json = await _api.getJson(Endpoints.netWorthHistory);
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
