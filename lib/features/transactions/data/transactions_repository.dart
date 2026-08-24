import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';
import '../../../core/api/paginated.dart';
import '../../../core/utils/date_x.dart';
import '../domain/transaction.dart';

/// Every filter `GET /transactions` accepts.
///
/// The wire names are NOT the Dart names: the API takes `category` and
/// `account`, not `categoryId`/`accountId`. [toQuery] is the only place that
/// mapping lives.
@immutable
class TransactionQuery {
  const TransactionQuery({
    this.page = 1,
    this.limit = 50,
    this.type,
    this.from,
    this.to,
    this.search,
    this.categoryId,
    this.accountId,
    this.tag,
    this.oneoff,
  });

  final int page;
  final int limit;
  final TransactionType? type;
  final DateTime? from;
  final DateTime? to;
  final String? search;
  final String? categoryId;
  final String? accountId;
  final String? tag;
  final bool? oneoff;

  /// True when anything beyond paging is set — drives the filter badge.
  bool get hasFilters =>
      type != null ||
      from != null ||
      to != null ||
      (search != null && search!.trim().isNotEmpty) ||
      categoryId != null ||
      accountId != null ||
      tag != null ||
      oneoff != null;

  /// Query params exactly as the backend accepts them. Nulls and blank strings
  /// are dropped entirely; dates go out as ISO-8601 UTC.
  Map<String, dynamic> toQuery() {
    final query = <String, dynamic>{'page': page, 'limit': limit};

    void put(String key, Object? value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      query[key] = value;
    }

    put('type', type?.api);
    put('from', from == null ? null : DateX.toApi(from!));
    put('to', to == null ? null : DateX.toApi(to!));
    put('search', search?.trim());
    put('category', categoryId);
    put('account', accountId);
    put('tag', tag);
    put('oneoff', oneoff == null ? null : (oneoff! ? 'true' : 'false'));

    return query;
  }

  /// Nullable fields need an explicit `clearX` flag — passing null means
  /// "leave it alone", which is what every caller wants for the common case.
  TransactionQuery copyWith({
    int? page,
    int? limit,
    TransactionType? type,
    bool clearType = false,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    String? search,
    bool clearSearch = false,
    String? categoryId,
    bool clearCategoryId = false,
    String? accountId,
    bool clearAccountId = false,
    String? tag,
    bool clearTag = false,
    bool? oneoff,
    bool clearOneoff = false,
  }) {
    return TransactionQuery(
      page: page ?? this.page,
      limit: limit ?? this.limit,
      type: clearType ? null : (type ?? this.type),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      search: clearSearch ? null : (search ?? this.search),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      tag: clearTag ? null : (tag ?? this.tag),
      oneoff: clearOneoff ? null : (oneoff ?? this.oneoff),
    );
  }

  /// Same filters, back to page one — use whenever a filter changes.
  TransactionQuery firstPage() => copyWith(page: 1);

  /// Keeps only the date window and paging; drops every user-set filter.
  TransactionQuery clearedFilters() =>
      TransactionQuery(page: 1, limit: limit, from: from, to: to);

  // Value equality matters: this type is a `.family` key and the list
  // controller compares queries to decide whether to reload.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionQuery &&
          other.page == page &&
          other.limit == limit &&
          other.type == type &&
          other.from == from &&
          other.to == to &&
          other.search == search &&
          other.categoryId == categoryId &&
          other.accountId == accountId &&
          other.tag == tag &&
          other.oneoff == oneoff;

  @override
  int get hashCode => Object.hash(
    page,
    limit,
    type,
    from,
    to,
    search,
    categoryId,
    accountId,
    tag,
    oneoff,
  );

  @override
  String toString() => 'TransactionQuery(${toQuery()})';
}

class TransactionsRepository {
  const TransactionsRepository(this._api);

  final ApiClient _api;

  Future<Paginated<Transaction>> list(TransactionQuery query) async {
    final json = await _api.getJson(
      Endpoints.transactions,
      query: query.toQuery(),
    );
    return Paginated.fromJson(json, Transaction.fromJson);
  }

  Future<Transaction> create(TransactionDraft draft) async {
    final json = await _api.postJson(
      Endpoints.transactions,
      body: draft.toJson(),
    );
    return Transaction.fromJson(_document(json));
  }

  /// [patch] uses wire field names (`account`, `category`, `toAccount`).
  Future<Transaction> update(String id, Map<String, dynamic> patch) async {
    final json = await _api.patchJson(Endpoints.transaction(id), body: patch);
    return Transaction.fromJson(_document(json));
  }

  /// Soft delete — the row stays recoverable via [restore].
  Future<void> delete(String id) => _api.deleteJson(Endpoints.transaction(id));

  Future<void> restore(String id) =>
      _api.postJson(Endpoints.transactionRestore(id));

  Future<TransactionSummary> summary({DateTime? from, DateTime? to}) async {
    final json = await _api.getJson(
      Endpoints.transactionsSummary,
      query: _range(from, to),
    );
    return TransactionSummary.fromJson(J.map(json));
  }

  Future<BalanceSnapshot> balance() async {
    final json = await _api.getJson(Endpoints.transactionsBalance);
    return BalanceSnapshot.fromJson(J.map(json));
  }

  Future<List<String>> tags() async {
    final json = await _api.getJson(Endpoints.transactionsTags);
    if (json is List) return J.stringList(json);
    final map = J.map(json);
    return J.stringList(map['tags'] ?? map['items']);
  }

  static Map<String, dynamic> _range(DateTime? from, DateTime? to) => {
    if (from != null) 'from': DateX.toApi(from),
    if (to != null) 'to': DateX.toApi(to),
  };

  /// Write endpoints return the bare document, but tolerate an envelope.
  static Map<String, dynamic> _document(Object? json) {
    final map = J.map(json);
    for (final key in const ['transaction', 'item', 'data']) {
      final nested = map[key];
      if (nested is Map) return J.map(nested);
    }
    return map;
  }
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => TransactionsRepository(ref.watch(apiClientProvider)),
);
