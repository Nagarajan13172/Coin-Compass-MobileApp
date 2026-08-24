import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../domain/holding.dart';

/// `/holdings` — savings and investments, the asset half of net worth.
///
/// A holding is deliberately thin: name, class, subtype, current value, dates.
/// `invested`, `institution` and `roi` are stripped by the server (probed —
/// docs/WRITE_SCHEMAS.md), so they are neither sent nor modelled.
class HoldingsRepository {
  const HoldingsRepository(this._api);

  final ApiClient _api;

  Future<List<Holding>> list() async {
    final json = await _api.getJson(Endpoints.holdings);
    return Envelope.rows(
      json,
      const ['holdings'],
    ).map(Holding.fromJson).toList();
  }

  /// [body] uses wire field names — see `Holding.toWriteJson()`.
  Future<Holding> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.holdings, body: body);
    return Holding.fromJson(Envelope.document(json, const ['holding']));
  }

  Future<Holding> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.holding(id), body: body);
    return Holding.fromJson(Envelope.document(json, const ['holding']));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.holding(id));
}

final holdingsRepositoryProvider = Provider<HoldingsRepository>(
  (ref) => HoldingsRepository(ref.watch(apiClientProvider)),
);

/// Cached for the session — read by the holdings screen and by net worth.
/// Invalidate after a write with `ref.invalidate(holdingsProvider)`.
final holdingsProvider = FutureProvider<List<Holding>>(
  (ref) => ref.watch(holdingsRepositoryProvider).list(),
);
