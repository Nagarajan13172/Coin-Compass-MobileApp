import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../../../core/state/optimistic.dart';
import '../domain/split.dart';

class SplitsRepository {
  const SplitsRepository(this._api);

  final ApiClient _api;

  Future<List<Split>> list() async {
    final json = await _api.getJson(Endpoints.splits);
    return Envelope.rows(json, const ['splits']).map(Split.fromJson).toList();
  }

  /// [body] uses wire field names — see `Split.toWriteJson()`.
  Future<Split> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.splits, body: body);
    return Split.fromJson(Envelope.document(json, const ['split']));
  }

  Future<Split> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.split(id), body: body);
    return Split.fromJson(Envelope.document(json, const ['split']));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.split(id));
}

final splitsRepositoryProvider = Provider<SplitsRepository>(
  (ref) => SplitsRepository(ref.watch(apiClientProvider)),
);

// ─── 6.4: the optimistic overlay ───────────────────────────────────────────
//
// The server's list moves to `<x>FetchProvider`; the public name stays on the
// composed view, so every existing `ref.watch` site gains optimism unedited.
// See lib/core/state/optimistic.dart.

/// The server's own list. Read this only to **refetch** it.
final splitsFetchProvider = FutureProvider<List<Split>>(
  (ref) => ref.watch(splitsRepositoryProvider).list(),
);

/// In-flight optimistic edits and deletes on `/splits`.
final splitsWritesProvider =
    StateNotifierProvider<OptimisticCollection<Split>, PendingWrites<Split>>(
      (ref) => OptimisticCollection<Split>(idOf: (split) => split.id),
    );

final splitsProvider = Provider<AsyncValue<List<Split>>>(
  (ref) =>
      ref.watch(splitsWritesProvider).applyTo(ref.watch(splitsFetchProvider)),
);

/// The settle step for a splits write.
Future<void> settleSplits(ProviderContainer container) =>
    settleFetch(container, splitsFetchProvider);
