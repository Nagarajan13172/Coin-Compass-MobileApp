import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_x.dart';
import '../../settings/data/settings_repository.dart';

/// The Week / Month / Year segmented control on the dashboard and Reports.
enum PeriodKind { week, month, year }

extension PeriodKindX on PeriodKind {
  /// Label for the segmented control.
  String get shortLabel => switch (this) {
    PeriodKind.week => 'Week',
    PeriodKind.month => 'Month',
    PeriodKind.year => 'Year',
  };

  /// The value `/reports/insights?period=` expects.
  String get apiValue => name;

  /// The noun the copy interpolates: "vs last month", "Projected this month".
  String get noun => name;

  /// The Reports caption suffix — "August 2026 · Month view".
  String get viewName => switch (this) {
    PeriodKind.week => 'Week view',
    PeriodKind.month => 'Month view',
    PeriodKind.year => 'Year view',
  };
}

/// Moves a raw anchor instant by [steps] periods, the way the web's pager does
/// (`cd()`: subWeeks/addMonths/addYears). Reports pages a [PeriodRange] with
/// [PeriodRange.shifted]; Insights pages the `ref` instant it sends to the API,
/// which is what this is for.
DateTime shiftAnchor(PeriodKind kind, DateTime anchor, int steps) =>
    switch (kind) {
      PeriodKind.week => anchor.add(Duration(days: 7 * steps)),
      PeriodKind.month => anchor.addMonths(steps),
      PeriodKind.year => anchor.addMonths(12 * steps),
    };

/// A half-open window `[start, end)` — the same convention the backend uses
/// (`/reports/summary` echoes `range: {start: 1 Aug, end: 1 Sep}` for August),
/// so `start`/`end` can be handed to any repository unchanged.
class PeriodRange {
  const PeriodRange(this.kind, this.start, this.end);

  final PeriodKind kind;

  /// Inclusive, local midnight.
  final DateTime start;

  /// Exclusive, local midnight — the first instant of the next period.
  final DateTime end;

  /// 'This month' when the window contains today, otherwise it names the
  /// window: 'August 2026', '2026', 'Week of 04 Aug'.
  String get label {
    if (isCurrent) {
      return switch (kind) {
        PeriodKind.week => 'This week',
        PeriodKind.month => 'This month',
        PeriodKind.year => 'This year',
      };
    }
    return switch (kind) {
      PeriodKind.week => 'Week of ${DateX.shortDay(start)}',
      PeriodKind.month => DateX.monthLabel(start),
      PeriodKind.year => '${start.year}',
    };
  }

  /// '1 Aug – 1 Sep 2026' — the dashboard subtitle, exactly as the web app
  /// renders it (the exclusive end date is shown, matching the server range).
  String get rangeLabel => DateX.rangeLabel(start, end);

  /// The label the **web's period pager** shows on Reports and Insights:
  /// '04 Aug – 10 Aug', 'August 2026', '2026'.
  ///
  /// Deliberately not [label]. That one says 'This month' for the current
  /// window, which the web never does — it renders the current month exactly
  /// like any other. [label] stays as it is because the dashboard's greeting
  /// reads better with it; these two screens use this one.
  ///
  /// The week form names the last day *inside* the window, so the exclusive
  /// [end] is stepped back a day. The separator is an EN DASH (U+2013).
  String get periodLabel {
    switch (kind) {
      case PeriodKind.week:
        final last = end.subtract(const Duration(days: 1));
        return '${DateX.shortDay(start)} \u2013 ${DateX.shortDay(last)}';
      case PeriodKind.month:
        return DateX.monthLabel(start);
      case PeriodKind.year:
        return '${start.year}';
    }
  }

  bool get isCurrent => contains(DateTime.now());

  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  /// The same kind of window, [steps] periods away (−1 = previous).
  PeriodRange shifted(int steps, {int firstDayOfWeek = 1}) {
    if (steps == 0) return this;
    final anchor = switch (kind) {
      PeriodKind.week => DateTime(
        start.year,
        start.month,
        start.day + 7 * steps,
      ),
      PeriodKind.month => DateTime(start.year, start.month + steps, 1),
      PeriodKind.year => DateTime(start.year + steps),
    };
    return PeriodRange.of(kind, anchor: anchor, firstDayOfWeek: firstDayOfWeek);
  }

  /// [firstDayOfWeek] follows `settings.firstDayOfWeek` (1 = Monday …
  /// 7 = Sunday) and only affects [PeriodKind.week].
  static PeriodRange of(
    PeriodKind kind, {
    DateTime? anchor,
    int firstDayOfWeek = 1,
  }) {
    final at = anchor ?? DateTime.now();
    switch (kind) {
      case PeriodKind.week:
        final start = at.startOfWeek(normaliseFirstDayOfWeek(firstDayOfWeek));
        return PeriodRange(
          kind,
          start,
          DateTime(start.year, start.month, start.day + 7),
        );
      case PeriodKind.month:
        final start = at.startOfMonth;
        return PeriodRange(kind, start, DateTime(start.year, start.month + 1));
      case PeriodKind.year:
        final start = at.startOfYear;
        return PeriodRange(kind, start, DateTime(start.year + 1));
    }
  }

  /// Settings should send 1–7, but tolerate 0 (some clients mean Sunday) and
  /// anything out of range by falling back to Monday.
  static int normaliseFirstDayOfWeek(int value) {
    if (value == 0) return DateTime.sunday;
    if (value < 1 || value > 7) return DateTime.monday;
    return value;
  }

  /// Value equality matters: screens pass a range as a `.family` argument, and
  /// an identity-keyed family would spawn a new provider on every rebuild.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeriodRange &&
          other.kind == kind &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => 'PeriodRange(${kind.name}, $start → $end)';
}

/// Which window the dashboard and Reports are showing. Shared so both screens
/// stay in sync.
final periodKindProvider = StateProvider<PeriodKind>((ref) => PeriodKind.month);

/// Optional anchor for paging back through periods; null means "now".
final periodAnchorProvider = StateProvider<DateTime?>((ref) => null);

/// The concrete window, derived from [periodKindProvider] and the user's week
/// start. Read defensively: settings may still be loading (or have failed), in
/// which case we assume Monday.
final periodRangeProvider = Provider<PeriodRange>((ref) {
  final kind = ref.watch(periodKindProvider);
  final anchor = ref.watch(periodAnchorProvider);
  final settings = ref.watch(settingsProvider).valueOrNull;
  return PeriodRange.of(
    kind,
    anchor: anchor,
    firstDayOfWeek: PeriodRange.normaliseFirstDayOfWeek(
      settings?.firstDayOfWeek ?? DateTime.monday,
    ),
  );
});
