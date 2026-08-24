import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/enums.dart';
import '../../../core/api/paginated.dart';
import '../../../core/utils/date_x.dart';
import '../data/transactions_repository.dart';
import '../domain/transaction.dart';

// ─── one-shot reads ────────────────────────────────────────────────────────

/// The filter set the Transactions screen is currently showing. Writing to it
/// makes [transactionsListProvider] reload.
final transactionQueryProvider = StateProvider<TransactionQuery>(
  (ref) => const TransactionQuery(),
);

/// A single page, keyed by its query. Use this for one-shot reads (dashboard
/// "Recent transactions", a day drill-down). For the infinite-scrolling screen
/// use [transactionsListProvider] instead.
final transactionsPageProvider =
    FutureProvider.family<Paginated<Transaction>, TransactionQuery>(
      (ref, query) => ref.watch(transactionsRepositoryProvider).list(query),
    );

/// Family arg for [transactionsSummaryProvider]. Records compare by value, so
/// the same window reuses the same cache entry.
typedef TransactionDateRange = ({DateTime from, DateTime to});

final transactionsSummaryProvider =
    FutureProvider.family<TransactionSummary, ({DateTime from, DateTime to})>(
      (ref, range) => ref
          .watch(transactionsRepositoryProvider)
          .summary(from: range.from, to: range.to),
    );

final transactionBalanceProvider = FutureProvider<BalanceSnapshot>(
  (ref) => ref.watch(transactionsRepositoryProvider).balance(),
);

final transactionTagsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(transactionsRepositoryProvider).tags(),
);

// ─── accumulating list (infinite scroll) ───────────────────────────────────

@immutable
class TransactionsListState {
  const TransactionsListState({
    this.items = const [],
    this.query = const TransactionQuery(),
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.hasMore = false,
    this.page = 1,
    this.total = 0,
  });

  /// Every row loaded so far, newest first, across all fetched pages.
  final List<Transaction> items;
  final TransactionQuery query;

  /// A first-page load is in flight (initial load, refresh, filter change).
  final bool loading;

  /// A next-page load is in flight — render a footer spinner, not a shimmer.
  final bool loadingMore;

  /// The last failure, normally an [ApiException].
  final Object? error;
  final bool hasMore;

  /// Highest page number successfully loaded.
  final int page;

  /// Server-reported match count for the current query.
  final int total;

  bool get isEmpty => items.isEmpty;
  bool get hasError => error != null;

  /// True only for the very first load — screens show a shimmer here and a
  /// pull-to-refresh spinner otherwise.
  bool get isInitialLoad => loading && items.isEmpty;

  /// Nothing to show and nothing wrong — render the empty state.
  bool get showEmptyState => !loading && !hasError && items.isEmpty;

  String? get errorMessage => switch (error) {
    ApiException(:final message) => message,
    null => null,
    final other => other.toString(),
  };

  TransactionsListState copyWith({
    List<Transaction>? items,
    TransactionQuery? query,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
    bool? hasMore,
    int? page,
    int? total,
  }) {
    return TransactionsListState(
      items: items ?? this.items,
      query: query ?? this.query,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      total: total ?? this.total,
    );
  }
}

/// Owns the accumulating page list behind the Transactions screen.
///
/// Every fetch is stamped with a request id so a slow page-2 response can never
/// overwrite a newer refresh — the common cause of duplicated rows when a user
/// scrolls and pulls to refresh at the same time.
class TransactionsListController extends StateNotifier<TransactionsListState> {
  TransactionsListController({
    required this.repository,
    TransactionQuery query = const TransactionQuery(),
    this.onQueryChanged,
  }) : _query = query.firstPage(),
       super(TransactionsListState(query: query.firstPage(), loading: true)) {
    refresh();
  }

  final TransactionsRepository repository;

  /// Called whenever [applyQuery] changes the filters, so the shared
  /// [transactionQueryProvider] can be kept in step.
  final void Function(TransactionQuery query)? onQueryChanged;

  TransactionQuery _query;
  int _requestId = 0;

  TransactionQuery get query => _query;

  /// Reloads page one, keeping the existing rows on screen while it runs so
  /// pull-to-refresh doesn't blank the list.
  Future<void> refresh() async {
    final id = ++_requestId;
    state = state.copyWith(
      loading: true,
      loadingMore: false,
      clearError: true,
      query: _query,
    );
    try {
      final result = await repository.list(_query.firstPage());
      if (!mounted || id != _requestId) return;
      state = state.copyWith(
        items: result.items,
        loading: false,
        hasMore: result.hasMore,
        page: 1,
        total: result.total,
        clearError: true,
      );
    } catch (error) {
      if (!mounted || id != _requestId) return;
      state = state.copyWith(loading: false, error: ApiException.from(error));
    }
  }

  /// Appends the next page. Safe to call on every scroll tick — it no-ops while
  /// a fetch is in flight or when the server said there is nothing left.
  Future<void> loadMore() async {
    final current = state;
    if (current.loading || current.loadingMore || !current.hasMore) return;

    final id = ++_requestId;
    final next = current.page + 1;
    state = current.copyWith(loadingMore: true, clearError: true);
    try {
      final result = await repository.list(_query.copyWith(page: next));
      if (!mounted || id != _requestId) return;
      state = state.copyWith(
        items: [...state.items, ...result.items],
        loadingMore: false,
        hasMore: result.hasMore,
        page: result.page > current.page ? result.page : next,
        total: result.total,
        clearError: true,
      );
    } catch (error) {
      if (!mounted || id != _requestId) return;
      state = state.copyWith(
        loadingMore: false,
        error: ApiException.from(error),
      );
    }
  }

  /// Swaps the filter set and reloads from page one. No-ops when the query is
  /// unchanged, which is also what stops the round-trip with
  /// [transactionQueryProvider] from looping.
  void applyQuery(TransactionQuery query) {
    final next = query.firstPage();
    if (next == _query) return;
    _query = next;
    state = state.copyWith(query: next, hasMore: false, page: 1);
    onQueryChanged?.call(next);
    refresh();
  }

  /// Optimistic delete. Returns the removed row so the caller can offer undo
  /// (`restore` + [insertLocal]); null when the id was not on screen.
  Transaction? deleteLocal(String id) {
    final index = state.items.indexWhere((t) => t.id == id);
    if (index < 0) return null;
    final removed = state.items[index];
    final items = [...state.items]..removeAt(index);
    state = state.copyWith(
      items: items,
      total: state.total > 0 ? state.total - 1 : 0,
    );
    return removed;
  }

  /// Optimistic insert, placed by date so a back-dated entry lands correctly.
  /// An id already on screen is treated as an update instead of a duplicate.
  void insertLocal(Transaction transaction) {
    if (state.items.any((t) => t.id == transaction.id)) {
      updateLocal(transaction);
      return;
    }
    final items = [...state.items];
    final key = _sortKey(transaction);
    var at = items.length;
    for (var i = 0; i < items.length; i++) {
      if (_sortKey(items[i]) < key) {
        at = i;
        break;
      }
    }
    items.insert(at, transaction);
    state = state.copyWith(items: items, total: state.total + 1);
  }

  /// Optimistic edit — re-places the row when its date changed.
  void updateLocal(Transaction transaction) {
    final index = state.items.indexWhere((t) => t.id == transaction.id);
    if (index < 0) return;
    final items = [...state.items]..removeAt(index);
    final key = _sortKey(transaction);
    var at = items.length;
    for (var i = 0; i < items.length; i++) {
      if (_sortKey(items[i]) < key) {
        at = i;
        break;
      }
    }
    items.insert(at, transaction);
    state = state.copyWith(items: items);
  }

  static int _sortKey(Transaction t) =>
      (t.date ?? t.createdAt)?.millisecondsSinceEpoch ?? 0;
}

/// Not a family — it reads [transactionQueryProvider] and reloads when it
/// changes, so the whole screen shares one accumulating list.
final transactionsListProvider =
    StateNotifierProvider<TransactionsListController, TransactionsListState>((
      ref,
    ) {
      final controller = TransactionsListController(
        repository: ref.watch(transactionsRepositoryProvider),
        query: ref.read(transactionQueryProvider),
        // Keep the shared filter state in step when a screen drives the
        // controller directly. `applyQuery` no-ops on an unchanged query, so
        // this cannot ping-pong with the listener below.
        onQueryChanged: (query) =>
            ref.read(transactionQueryProvider.notifier).state = query,
      );

      ref.listen<TransactionQuery>(
        transactionQueryProvider,
        (_, next) => controller.applyQuery(next),
      );

      return controller;
    });

// ─── day grouping ──────────────────────────────────────────────────────────

/// One calendar day of rows plus that day's net, for the list's day headers.
typedef TransactionDayGroup = ({
  DateTime day,
  List<Transaction> items,
  num net,
});

/// Groups [transactions] by calendar day, newest day first and newest row first
/// within each day.
///
/// `net` counts income as positive and expense as negative; transfers move
/// money between your own accounts, so they contribute nothing.
List<TransactionDayGroup> groupTransactionsByDay(
  List<Transaction> transactions,
) {
  final buckets = <DateTime, List<Transaction>>{};
  for (final transaction in transactions) {
    final stamp = transaction.date ?? transaction.createdAt;
    if (stamp == null) continue;
    final day = stamp.startOfDay;
    (buckets[day] ??= <Transaction>[]).add(transaction);
  }

  final days = buckets.keys.toList()..sort((a, b) => b.compareTo(a));

  final groups = <TransactionDayGroup>[];
  for (final day in days) {
    final items = buckets[day]!
      ..sort(
        (a, b) => TransactionsListController._sortKey(
          b,
        ).compareTo(TransactionsListController._sortKey(a)),
      );
    groups.add((
      day: day,
      items: items,
      net: items.fold<num>(0, (sum, t) => sum + _netContribution(t)),
    ));
  }
  return groups;
}

num _netContribution(Transaction t) => switch (t.type) {
  TransactionType.income => t.amount,
  TransactionType.expense => -t.amount,
  TransactionType.transfer => 0,
};
