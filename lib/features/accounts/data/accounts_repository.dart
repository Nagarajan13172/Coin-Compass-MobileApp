import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
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

/// Cached for the whole session (not autoDispose): accounts are read by the
/// dashboard, the transactions list, every picker and the accounts screen.
/// Invalidate it after a write with `ref.invalidate(accountsProvider)`.
final accountsProvider = FutureProvider<List<Account>>(
  (ref) => ref.watch(accountsRepositoryProvider).list(),
);
