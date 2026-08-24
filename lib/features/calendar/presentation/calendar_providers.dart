import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/enums.dart';
import '../../../core/utils/date_x.dart';
import '../../transactions/data/transactions_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/presentation/transactions_providers.dart';

/// Which month the grid is showing. Always the first of the month, so it is a
/// stable key for [calendarMonthProvider].
final calendarMonthAnchorProvider = StateProvider<DateTime>(
  (ref) => DateTime.now().startOfMonth,
);

/// The day the detail card below the grid is describing.
final calendarSelectedDayProvider = StateProvider<DateTime>(
  (ref) => DateTime.now().startOfDay,
);

/// What happened on one calendar day.
@immutable
class DayTotals {
  const DayTotals({
    this.income = 0,
    this.expense = 0,
    this.count = 0,
    this.hasRecurring = false,
  });

  final num income;
  final num expense;
  final int count;

  /// True when a rule posted at least one of the day's rows — the grid marks
  /// those days the way the web app does.
  final bool hasRecurring;

  /// Transfers move money between the user's own accounts, so they leave the
  /// net alone — the same rule the ledger's day headers use.
  num get net => income - expense;

  bool get isEmpty => count == 0;
}

/// A month of transactions, bucketed by day for the grid.
@immutable
class CalendarMonth {
  const CalendarMonth({
    required this.month,
    required this.byDay,
    required this.itemsByDay,
    required this.truncated,
  });

  final DateTime month;
  final Map<DateTime, DayTotals> byDay;
  final Map<DateTime, List<Transaction>> itemsByDay;

  /// True when the month has more rows than [_maxPages] could carry, so the
  /// figures shown are a floor rather than the whole month.
  final bool truncated;

  DayTotals totalsFor(DateTime day) =>
      byDay[day.startOfDay] ?? const DayTotals();

  List<Transaction> itemsFor(DateTime day) =>
      itemsByDay[day.startOfDay] ?? const [];

  num get income => byDay.values.fold<num>(0, (sum, d) => sum + d.income);
  num get expense => byDay.values.fold<num>(0, (sum, d) => sum + d.expense);

  static CalendarMonth from(
    DateTime month,
    List<Transaction> transactions, {
    bool truncated = false,
  }) {
    final byDay = <DateTime, DayTotals>{};
    final itemsByDay = <DateTime, List<Transaction>>{};

    for (final transaction in transactions) {
      final stamp = transaction.date ?? transaction.createdAt;
      if (stamp == null) continue;
      final day = stamp.startOfDay;

      (itemsByDay[day] ??= <Transaction>[]).add(transaction);
      final current = byDay[day] ?? const DayTotals();
      byDay[day] = DayTotals(
        income:
            current.income +
            (transaction.type == TransactionType.income
                ? transaction.amount
                : 0),
        expense:
            current.expense +
            (transaction.type == TransactionType.expense
                ? transaction.amount
                : 0),
        count: current.count + 1,
        hasRecurring: current.hasRecurring || transaction.isRecurring,
      );
    }

    for (final rows in itemsByDay.values) {
      rows.sort((a, b) => _stamp(b).compareTo(_stamp(a)));
    }

    return CalendarMonth(
      month: month.startOfMonth,
      byDay: byDay,
      itemsByDay: itemsByDay,
      truncated: truncated,
    );
  }

  static int _stamp(Transaction t) =>
      (t.date ?? t.createdAt)?.millisecondsSinceEpoch ?? 0;
}

/// Rows per request. A month rarely fills one page, and the grid needs the
/// whole month before it can total a single day.
const int _pageSize = 200;

/// Ceiling on paging, so a pathological month cannot spin forever. Anything
/// past it sets `truncated` and the screen says so rather than quietly
/// under-reporting.
const int _maxPages = 5;

/// The visible month's transactions, bucketed by day.
///
/// Page one comes from [transactionsPageProvider] rather than the repository,
/// so the invalidation every write already performs on that family refreshes
/// the calendar too.
final calendarMonthProvider = FutureProvider.autoDispose
    .family<CalendarMonth, DateTime>((ref, month) async {
      final start = month.startOfMonth;
      final end = month.endOfMonth;

      TransactionQuery queryFor(int page) =>
          TransactionQuery(page: page, limit: _pageSize, from: start, to: end);

      final first = await ref.watch(
        transactionsPageProvider(queryFor(1)).future,
      );
      final items = [...first.items];

      var hasMore = first.hasMore;
      var page = 1;
      final repository = ref.watch(transactionsRepositoryProvider);
      while (hasMore && page < _maxPages) {
        page++;
        final next = await repository.list(queryFor(page));
        items.addAll(next.items);
        hasMore = next.hasMore;
      }

      return CalendarMonth.from(start, items, truncated: hasMore);
    });
