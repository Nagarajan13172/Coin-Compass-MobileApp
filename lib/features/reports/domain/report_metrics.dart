import 'report_models.dart';

/// The six figures the Reports stat cards show that the API does **not**
/// return. Every one is transcribed from the deployed web bundle (`YZ`, offset
/// 1023354) rather than re-derived, because three of them are easy to get
/// subtly wrong:
///
///  * [daysElapsed] counts *calendar days so far*, so a partial month is not
///    divided by a full 30;
///  * [savingsRate] divides by `consumption`, not `expense` — money moved into
///    a goal or a deposit is not "spent";
///  * both percentages are null, not zero, when there is nothing to divide by.
///    A screen that renders 0% there is lying; the web renders an em dash.
///
/// Pure functions on plain values — no Riverpod, no clock beyond the [now] you
/// pass — so `test/phase5_data_test.dart` pins them directly.
class ReportMetrics {
  const ReportMetrics._();

  /// Whole days of [start, end) that have already happened, today included.
  ///
  /// [end] is the exclusive end of a [PeriodRange], so the last instant inside
  /// the window is a millisecond before it — that is the web's `rangeEnd`, and
  /// using [end] itself would count one day too many for every past period.
  /// Never less than 1: a window that has not started yet still divides by a
  /// day rather than by zero.
  static int daysElapsed(DateTime start, DateTime end, {DateTime? now}) {
    final lastInstant = end.subtract(const Duration(milliseconds: 1));
    final at = now ?? DateTime.now();
    final effectiveEnd = at.isBefore(lastInstant) ? at : lastInstant;
    final days = _calendarDays(start, effectiveEnd) + 1;
    return days < 1 ? 1 : days;
  }

  /// `expense / daysElapsed` — deliberately **not** rounded. The web renders
  /// ₹554.67 here (Insights is the one that rounds its avg-per-day to ₹555).
  static num avgDailySpend(
    ReportSummary summary,
    DateTime start,
    DateTime end, {
    DateTime? now,
  }) => summary.expense / daysElapsed(start, end, now: now);

  /// `(income − consumption) ÷ income × 100`, rounded. Null when there was no
  /// income to keep a share of — the card then shows an em dash.
  static int? savingsRate(ReportSummary summary) {
    if (summary.income <= 0) return null;
    return ((summary.income - summary.consumption) / summary.income * 100)
        .round();
  }

  /// Percentage change against the previous period, rounded. Null when the
  /// previous period was zero: "infinitely more" is not a number to render.
  static int? changeVsPrevious(num current, num previous) {
    if (previous <= 0) return null;
    return ((current - previous) / previous * 100).round();
  }

  /// The biggest slice, or null for an empty window. The Reports card always
  /// reads from the **expense** breakdown, whatever the Expense/Income toggle
  /// below it is set to.
  static CategorySlice? biggest(List<CategorySlice> slices) {
    if (slices.isEmpty) return null;
    var top = slices.first;
    for (final slice in slices.skip(1)) {
      if (slice.total > top.total) top = slice;
    }
    return top;
  }

  /// Calendar days between two instants, ignoring the time of day, so
  /// 1 Aug 00:00 -> 24 Aug 18:30 is 23 and not 23.77.
  static int _calendarDays(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}
