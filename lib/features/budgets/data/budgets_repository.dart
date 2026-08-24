import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../../../core/state/optimistic.dart';
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

// ─── 6.4: the optimistic overlay ───────────────────────────────────────────
//
// The server's list moves to `<x>FetchProvider`; the public name stays on the
// composed view, so every existing `ref.watch` site gains optimism unedited.
// See lib/core/state/optimistic.dart.

/// The server's own list. Read this only to **refetch** it.
final budgetsFetchProvider = FutureProvider<List<Budget>>(
  (ref) => ref.watch(budgetsRepositoryProvider).list(),
);

/// In-flight optimistic edits and deletes on `/budgets`.
final budgetsWritesProvider =
    StateNotifierProvider<OptimisticCollection<Budget>, PendingWrites<Budget>>(
      (ref) => OptimisticCollection<Budget>(idOf: (budget) => budget.id),
    );

/// Session-cached: the budgets screen and the add sheet both read it.
final budgetsProvider = Provider<AsyncValue<List<Budget>>>(
  (ref) =>
      ref.watch(budgetsWritesProvider).applyTo(ref.watch(budgetsFetchProvider)),
);

/// The settle step for a budgets write. The spend windows live in
/// `presentation/budgets_providers.dart` and are added by the call site — the
/// data layer does not reach up into presentation.
Future<void> settleBudgets(ProviderContainer container) =>
    settleFetch(container, budgetsFetchProvider);
