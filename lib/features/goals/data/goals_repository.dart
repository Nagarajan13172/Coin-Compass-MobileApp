import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
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

final goalsProvider = FutureProvider<List<Goal>>(
  (ref) => ref.watch(goalsRepositoryProvider).list(),
);
