import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
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

final creditsProvider = FutureProvider<List<Credit>>(
  (ref) => ref.watch(creditsRepositoryProvider).list(),
);

/// The server's totals when it sends them, otherwise totals derived from the
/// list — so the summary card renders either way.
final creditsSummaryProvider = FutureProvider<CreditsSummary>((ref) async {
  final credits = await ref.watch(creditsProvider.future);
  final fromServer = await ref.watch(creditsRepositoryProvider).summary();
  return fromServer ?? CreditsSummary.fromCredits(credits);
});
