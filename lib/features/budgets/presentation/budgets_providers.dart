import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/enums.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/presentation/period.dart';
import '../../settings/data/settings_repository.dart';
import '../domain/budget.dart';

/// What has been spent inside one budget window.
///
/// `/budgets` only carries the limit, so progress is measured against
/// `/reports/*` for the window the budget's period describes — this month for a
/// monthly budget, this week for a weekly one.
@immutable
class BudgetSpend {
  const BudgetSpend({
    required this.range,
    required this.byCategory,
    required this.total,
  });

  final PeriodRange range;

  /// Expense total per category id for the window.
  final Map<String, num> byCategory;

  /// Every expense in the window, including anything uncategorised.
  final num total;

  /// A budget with no category caps all spending, so it measures against the
  /// window total; a category budget measures against its own slice.
  num forBudget(Budget budget) {
    final id = budget.categoryId;
    if (id == null) return total;
    return byCategory[id] ?? 0;
  }

  /// Whole days left in the window, today included. 0 once it has closed.
  int get daysLeft {
    final remaining = range.end.difference(DateTime.now()).inHours / 24;
    return remaining <= 0 ? 0 : remaining.ceil();
  }
}

PeriodKind periodKindOf(BudgetPeriod period) => switch (period) {
  BudgetPeriod.weekly => PeriodKind.week,
  BudgetPeriod.monthly => PeriodKind.month,
  BudgetPeriod.yearly => PeriodKind.year,
};

/// Keyed by period, so a list of monthly budgets costs one pair of requests no
/// matter how many rows it has, and a weekly budget adds one more.
final budgetSpendProvider = FutureProvider.autoDispose
    .family<BudgetSpend, BudgetPeriod>((ref, period) async {
      final settings = ref.watch(settingsProvider).valueOrNull;
      final range = PeriodRange.of(
        periodKindOf(period),
        firstDayOfWeek: PeriodRange.normaliseFirstDayOfWeek(
          settings?.firstDayOfWeek ?? DateTime.monday,
        ),
      );

      final repository = ref.watch(reportsRepositoryProvider);
      // The summary's expense figure counts uncategorised spending too, which
      // the by-category slices leave out — so an "all spending" budget is not
      // quietly flattered by rows the server could not attribute.
      final (summary, slices) = await (
        repository.summary(from: range.start, to: range.end),
        repository.byCategory(
          from: range.start,
          to: range.end,
          type: 'expense',
        ),
      ).wait;

      return BudgetSpend(
        range: range,
        byCategory: {
          for (final slice in slices)
            if (slice.categoryId != null) slice.categoryId!: slice.total,
        },
        total: summary.expense,
      );
    });
