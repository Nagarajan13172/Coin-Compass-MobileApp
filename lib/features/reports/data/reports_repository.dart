import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../../../core/utils/date_x.dart';
import '../domain/report_models.dart';

/// The `/reports/*` family: the aggregates behind the dashboard, the Reports
/// screen and Insights.
///
/// Every endpoint takes the same optional `from`/`to` window (ISO-8601 UTC,
/// `from` inclusive / `to` exclusive — the server's own `range` echoes back
/// `{start: 1 Aug, end: 1 Sep}` for a month). Omitting both lets the server
/// pick its default window.
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

  Future<List<AccountSlice>> byAccount({DateTime? from, DateTime? to}) async {
    final json = await _api.getJson(
      Endpoints.reportsByAccount,
      query: _range(from, to),
    );
    return J.list(_items(json), AccountSlice.fromJson);
  }

  /// Income/expense/net per bucket, oldest first.
  /// [bucket] is `day`, `week` or `month`; omit it to let the server size the
  /// buckets from the window.
  ///
  /// The wire key is `granularity`, not `bucket` — `bucket` is only the name of
  /// the *response* field. Verified live: `?granularity=month` returns
  /// `bucket: "2026-08"`, while `?bucket=month` is ignored and falls back to
  /// daily `bucket: "2026-08-04"`.
  Future<List<TrendPoint>> trend({
    DateTime? from,
    DateTime? to,
    String? bucket,
  }) async {
    final json = await _api.getJson(
      Endpoints.reportsTrend,
      query: {..._range(from, to), 'granularity': ?bucket},
    );
    return J.list(_items(json), TrendPoint.fromJson);
  }

  /// Period-over-period deltas, savings rate, pace/projection and movers.
  /// [period] is `week`, `month` or `year` — this endpoint picks its own window
  /// rather than taking from/to.
  Future<Insights> insights({String period = 'month'}) async {
    final json = await _api.getJson(
      Endpoints.reportsInsights,
      query: {'period': period},
    );
    return Insights.fromJson(J.map(json));
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
