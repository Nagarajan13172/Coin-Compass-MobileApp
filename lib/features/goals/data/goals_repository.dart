import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../../../core/state/optimistic.dart';
import '../domain/goal.dart';

class GoalsRepository {
  const GoalsRepository(this._api);

  final ApiClient _api;

  Future<List<Goal>> list() async {
    final json = await _api.getJson(Endpoints.goals);
    return Envelope.rows(json, const ['goals']).map(Goal.fromJson).toList();
  }

  /// [body] uses wire field names — see `Goal.toWriteJson()`.
  Future<Goal> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.goals, body: body);
    return Goal.fromJson(Envelope.document(json, const ['goal']));
  }

  Future<Goal> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.goal(id), body: body);
    return Goal.fromJson(Envelope.document(json, const ['goal']));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.goal(id));

  /// Adds to `savedAmount` server-side and returns the updated goal. The
  /// endpoint takes the amount alone — a contribution moves the goal, it does
  /// not post a transaction, so it needs no account or category.
  Future<Goal> contribute(String id, num amount) async {
    final json = await _api.postJson(
      Endpoints.goalContribute(id),
      body: {'amount': amount},
    );
    return Goal.fromJson(Envelope.document(json, const ['goal']));
  }
}

final goalsRepositoryProvider = Provider<GoalsRepository>(
  (ref) => GoalsRepository(ref.watch(apiClientProvider)),
);

// ─── 6.4: the optimistic overlay ───────────────────────────────────────────
//
// The server's list moves to `<x>FetchProvider`; the public name stays on the
// composed view, so every existing `ref.watch` site gains optimism unedited.
// See lib/core/state/optimistic.dart.

/// The server's own list. Read this only to **refetch** it.
final goalsFetchProvider = FutureProvider<List<Goal>>(
  (ref) => ref.watch(goalsRepositoryProvider).list(),
);

/// In-flight optimistic edits and deletes on `/goals`.
///
/// `POST /goals/:id/contribute` is deliberately **not** routed through here —
/// savedAmount, remaining, percent, complete and monthsLeft are all re-derived
/// server-side. See `GoalContributeSheet`.
final goalsWritesProvider =
    StateNotifierProvider<OptimisticCollection<Goal>, PendingWrites<Goal>>(
      (ref) => OptimisticCollection<Goal>(idOf: (goal) => goal.id),
    );

final goalsProvider = Provider<AsyncValue<List<Goal>>>(
  (ref) =>
      ref.watch(goalsWritesProvider).applyTo(ref.watch(goalsFetchProvider)),
);

/// The settle step for a goals write.
Future<void> settleGoals(ProviderContainer container) =>
    settleFetch(container, goalsFetchProvider);
