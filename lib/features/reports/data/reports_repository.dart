import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../../../core/utils/date_x.dart';
import '../domain/report_models.dart';

/// The `/reports/*` family: the aggregates behind the dashboard and the
/// Reports screen. `/reports/insights` is *not* here — it takes a period, not a
/// window, and lives in `features/insights`.
///
/// Every endpoint takes the same optional `from`/`to` window (ISO-8601 UTC,
/// `from` inclusive / `to` exclusive). Verified live against the deployment:
///
///   from=2026-08-01T00:00:00Z&to=2026-08-04T00:00:00Z -> expense 0
///   from=2026-08-01T00:00:00Z&to=2026-08-04T23:59:59Z -> expense 13312
///
/// so the 4 Aug transactions fall outside a window that ends at their midnight.
/// A **bare** `yyyy-MM-dd` `to` behaves the other way round — the server
/// expands it to the start of the next day, making it inclusive. This app only
/// ever sends full ISO instants, so the half-open reading holds everywhere and
/// [PeriodRange] can be handed over unchanged.
///
/// Omitting both lets the server pick its default window.
class ReportsRepository {
  const ReportsRepository(this._api);

  final ApiClient _api;

  /// `{income, expense, net, counts, consumption/nonConsumption, netWorth}`.
  Future<ReportSummary> summary({DateTime? from, DateTime? to}) async {
    final json = await _api.getJson(
      Endpoints.reportsSummary,
      query: _range(from, to),
    );
    return ReportSummary.fromJson(J.map(json));
  }

  /// Spending (or income) split by category, biggest first.
  /// [type] is `expense` or `income`; omit it for the server default.
  Future<List<CategorySlice>> byCategory({
    DateTime? from,
    DateTime? to,
    String? type,
  }) async {
    final json = await _api.getJson(
      Endpoints.reportsByCategory,
      query: {..._range(from, to), 'type': ?type},
    );
    return J.list(_items(json), CategorySlice.fromJson);
  }

  /// Money in vs out per account. Returns `[]` for an account-less wallet,
  /// which is this owner's actual state.
  Future<List<AccountSlice>> byAccount({DateTime? from, DateTime? to}) async {
    final json = await _api.getJson(
      Endpoints.reportsByAccount,
      query: _range(from, to),
    );
    return J.list(_items(json), AccountSlice.fromJson);
  }

  /// Income/expense/net per bucket, oldest first — and **sparse**: buckets with
  /// no activity are absent, not zero-filled.
  ///
  /// The wire key is `granularity`, not `bucket` — `bucket` is only the name of
  /// the *response* field. Verified live: `?granularity=month` returns
  /// `bucket: "2026-08"`, while `?bucket=month` is ignored and silently falls
  /// back to daily rows. Omit [granularity] to let the server size the buckets.
  Future<List<TrendPoint>> trend({
    DateTime? from,
    DateTime? to,
    TrendGranularity? granularity,
  }) async {
    final json = await _api.getJson(
      Endpoints.reportsTrend,
      query: {..._range(from, to), 'granularity': ?granularity?.api},
    );
    return J.list(_items(json), TrendPoint.fromJson);
  }

  /// Dates go out as ISO-8601 UTC; nulls are dropped rather than sent empty.
  static Map<String, dynamic> _range(DateTime? from, DateTime? to) => {
    if (from != null) 'from': DateX.toApi(from),
    if (to != null) 'to': DateX.toApi(to),
  };

  /// These endpoints return bare arrays; tolerate an envelope as well.
  static Object? _items(Object? json) =>
      json is Map ? (json['items'] ?? json['data']) : json;
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(apiClientProvider)),
);
