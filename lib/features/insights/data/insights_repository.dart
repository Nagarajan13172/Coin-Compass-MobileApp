import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../../../core/utils/date_x.dart';
import '../domain/insights.dart';

/// `GET /reports/insights` — the single read behind the Insights screen.
///
/// It lives here rather than in ReportsRepository because it does not take
/// the `from`/`to` window every other report does: it takes a **period name**
/// plus an optional anchor instant, and derives both ranges itself. Sending
/// from/to instead is not an error — they are ignored, and you silently get
/// the current month.
class InsightsRepository {
  const InsightsRepository(this._api);

  final ApiClient _api;

  /// [period] is `week`, `month` or `year` (see `PeriodKind.apiValue`).
  ///
  /// [at] is the `ref` param: any instant inside the period you want. Omit it
  /// for the current one. Verified live — `?period=month&ref=2026-07-15T…`
  /// returns `current: 1 Jul → 1 Aug`, `previous: 1 Jun → 1 Jul` and
  /// `pace.isCurrent: false` — so without it the period pager cannot move off
  /// today.
  Future<Insights> fetch({String period = 'month', DateTime? at}) async {
    final json = await _api.getJson(
      Endpoints.reportsInsights,
      query: {'period': period, if (at != null) 'ref': DateX.toApi(at)},
    );
    return Insights.fromJson(J.map(json));
  }
}

final insightsRepositoryProvider = Provider<InsightsRepository>(
  (ref) => InsightsRepository(ref.watch(apiClientProvider)),
);
