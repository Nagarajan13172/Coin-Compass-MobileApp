import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../../../core/state/optimistic.dart';
import '../domain/account.dart';

class AccountsRepository {
  const AccountsRepository(this._api);

  final ApiClient _api;

  Future<List<Account>> list() async {
    final json = await _api.getJson(Endpoints.accounts);
    return _rows(json).map(Account.fromJson).toList();
  }

  /// [body] uses wire field names — see `Account.toWriteJson()`.
  Future<Account> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.accounts, body: body);
    return Account.fromJson(_document(json));
  }

  Future<Account> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.account(id), body: body);
    return Account.fromJson(_document(json));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.account(id));

  /// `GET /accounts` returns a bare array; tolerate an `{items:[…]}` envelope.
  static List<Map<String, dynamic>> _rows(Object? json) {
    if (json is List) {
      return json
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    final map = J.map(json);
    for (final key in const ['items', 'accounts', 'data']) {
      final nested = map[key];
      if (nested is List) {
        return nested
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    }
    return const [];
  }

  static Map<String, dynamic> _document(Object? json) {
    final map = J.map(json);
    for (final key in const ['account', 'item', 'data']) {
      final nested = map[key];
      if (nested is Map) return J.map(nested);
    }
    return map;
  }
}

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => AccountsRepository(ref.watch(apiClientProvider)),
);

// ─── 6.4: the optimistic overlay ───────────────────────────────────────────
//
// Three providers, one public name. The server's list moves to
// [accountsFetchProvider]; [accountsProvider] keeps its name and becomes the
// *composed* view, so all 20-odd `ref.watch(accountsProvider)` sites gain
// optimism unedited and none of them can accidentally watch the un-optimistic
// one. `Provider<AsyncValue<…>>` has no `.future`, which is what makes the
// compiler find every `invalidate` + `.future` pair that has to move.

/// The server's own list. Read this only to **refetch** it — screens watch
/// [accountsProvider], which folds the in-flight writes on top.
///
/// Cached for the whole session (not autoDispose): accounts are read by the
/// dashboard, the transactions list, every picker and the accounts screen.
final accountsFetchProvider = FutureProvider<List<Account>>(
  (ref) => ref.watch(accountsRepositoryProvider).list(),
);

/// In-flight optimistic edits and deletes on `/accounts`.
final accountsWritesProvider =
    StateNotifierProvider<
      OptimisticCollection<Account>,
      PendingWrites<Account>
    >((ref) => OptimisticCollection<Account>(idOf: (account) => account.id));

/// What every screen watches. With no write in flight this is *literally* the
/// same `AsyncValue` object [accountsFetchProvider] produced.
final accountsProvider = Provider<AsyncValue<List<Account>>>(
  (ref) => ref
      .watch(accountsWritesProvider)
      .applyTo(ref.watch(accountsFetchProvider)),
);

/// The settle step for an accounts write: drop the cached list and wait for the
/// fresh one. Awaiting is what stops a flash of the pre-write row.
Future<void> settleAccounts(ProviderContainer container) =>
    settleFetch(container, accountsFetchProvider);
