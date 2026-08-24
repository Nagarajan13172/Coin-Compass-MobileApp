import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../domain/budget.dart';

class BudgetsRepository {
  const BudgetsRepository(this._api);

  final ApiClient _api;

  Future<List<Budget>> list() async {
    final json = await _api.getJson(Endpoints.budgets);
    return Envelope.rows(json, const ['budgets']).map(Budget.fromJson).toList();
  }

  /// [body] uses wire field names — see `Budget.toWriteJson()`
  /// (note `category`, not `categoryId`).
  Future<Budget> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.budgets, body: body);
    return Budget.fromJson(Envelope.document(json, const ['budget']));
  }

  Future<Budget> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.budget(id), body: body);
    return Budget.fromJson(Envelope.document(json, const ['budget']));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.budget(id));
}

final budgetsRepositoryProvider = Provider<BudgetsRepository>(
  (ref) => BudgetsRepository(ref.watch(apiClientProvider)),
);

/// Session-cached: the budgets screen and the add sheet both read it.
/// Invalidate after a write with `ref.invalidate(budgetsProvider)`.
final budgetsProvider = FutureProvider<List<Budget>>(
  (ref) => ref.watch(budgetsRepositoryProvider).list(),
);
