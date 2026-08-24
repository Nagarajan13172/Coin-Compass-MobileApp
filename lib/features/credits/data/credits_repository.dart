import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../../../core/state/optimistic.dart';
import '../domain/credit.dart';

class CreditsRepository {
  const CreditsRepository(this._api);

  final ApiClient _api;

  Future<List<Credit>> list() async {
    final json = await _api.getJson(Endpoints.credits);
    return Envelope.rows(json, const ['credits']).map(Credit.fromJson).toList();
  }

  /// `GET /credits/summary`. On an account with no credits the endpoint answers
  /// with an empty array rather than a zeroed object, so anything that isn't a
  /// map is reported as "no server summary" and the caller totals the list
  /// itself — see [CreditsSummary.fromCredits].
  Future<CreditsSummary?> summary() async {
    final json = await _api.getJson(Endpoints.creditsSummary);
    if (json is! Map) return null;
    return CreditsSummary.fromJson(Envelope.document(json, const ['summary']));
  }

  /// [body] uses wire field names — see `Credit.toWriteJson()`
  /// (`person` carries either an id or a plain name).
  Future<Credit> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.credits, body: body);
    return Credit.fromJson(Envelope.document(json, const ['credit']));
  }

  Future<Credit> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.credit(id), body: body);
    return Credit.fromJson(Envelope.document(json, const ['credit']));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.credit(id));
}

final creditsRepositoryProvider = Provider<CreditsRepository>(
  (ref) => CreditsRepository(ref.watch(apiClientProvider)),
);

// ─── 6.4: the optimistic overlay ───────────────────────────────────────────
//
// The server's list moves to `<x>FetchProvider`; the public name stays on the
// composed view, so every existing `ref.watch` site gains optimism unedited.
// See lib/core/state/optimistic.dart.

/// The server's own list. Read this only to **refetch** it.
final creditsFetchProvider = FutureProvider<List<Credit>>(
  (ref) => ref.watch(creditsRepositoryProvider).list(),
);

/// In-flight optimistic edits and deletes on `/credits`.
final creditsWritesProvider =
    StateNotifierProvider<OptimisticCollection<Credit>, PendingWrites<Credit>>(
      (ref) => OptimisticCollection<Credit>(idOf: (credit) => credit.id),
    );

final creditsProvider = Provider<AsyncValue<List<Credit>>>(
  (ref) =>
      ref.watch(creditsWritesProvider).applyTo(ref.watch(creditsFetchProvider)),
);

/// The settle step for a credits write.
Future<void> settleCredits(ProviderContainer container) =>
    settleFetch(container, creditsFetchProvider);

/// The server's totals when it sends them, otherwise totals derived from the
/// list — so the summary card renders either way.
///
/// 6.4: this reads [creditsFetchProvider], **not** the composed view. It is a
/// separate server aggregate (`GET /credits/summary`), so it lags an optimistic
/// row by exactly one round trip; `PendingWrites.isSettling` is what the card
/// dims on rather than sitting confidently on a superseded number. Deriving it
/// from the view instead would need the fallback restructured off `.future`.
final creditsSummaryProvider = FutureProvider<CreditsSummary>((ref) async {
  final credits = await ref.watch(creditsFetchProvider.future);
  final fromServer = await ref.watch(creditsRepositoryProvider).summary();
  return fromServer ?? CreditsSummary.fromCredits(credits);
});
