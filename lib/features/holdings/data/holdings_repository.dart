import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../../../core/state/optimistic.dart';
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
    return Envelope.rows(json, const [
      'holdings',
    ]).map(Holding.fromJson).toList();
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

// ─── 6.4: the optimistic overlay ───────────────────────────────────────────
//
// The server's list moves to `<x>FetchProvider`; the public name stays on the
// composed view, so every existing `ref.watch` site gains optimism unedited.
// See lib/core/state/optimistic.dart.

/// The server's own list. Read this only to **refetch** it.
///
/// Cached for the session — read by the holdings screen and by net worth.
final holdingsFetchProvider = FutureProvider<List<Holding>>(
  (ref) => ref.watch(holdingsRepositoryProvider).list(),
);

/// In-flight optimistic edits and deletes on `/holdings`.
final holdingsWritesProvider =
    StateNotifierProvider<
      OptimisticCollection<Holding>,
      PendingWrites<Holding>
    >((ref) => OptimisticCollection<Holding>(idOf: (holding) => holding.id));

final holdingsProvider = Provider<AsyncValue<List<Holding>>>(
  (ref) => ref
      .watch(holdingsWritesProvider)
      .applyTo(ref.watch(holdingsFetchProvider)),
);

/// The settle step for a holdings write. The net-worth series is a separate
/// server aggregate; the call site adds it, and it is refetched, never guessed.
Future<void> settleHoldings(ProviderContainer container) =>
    settleFetch(container, holdingsFetchProvider);
