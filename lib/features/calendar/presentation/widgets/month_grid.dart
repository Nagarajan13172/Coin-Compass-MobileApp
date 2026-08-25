import '../../../../core/ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../calendar_providers.dart';

/// The month grid: seven columns from the user's week start, six rows so the
/// card never changes height, each day showing its net and a marker when a
/// recurring rule posted that day.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.totals,
    required this.firstDayOfWeek,
    required this.onSelect,
    this.loading = false,
  });

  final DateTime month;
  final DateTime selected;

  /// Per-day figures for the visible month, keyed by local midnight.
  final Map<DateTime, DayTotals> totals;

  /// 1 = Monday … 7 = Sunday, from `settings.firstDayOfWeek`.
  final int firstDayOfWeek;

  final ValueChanged<DateTime> onSelect;

  /// Dims the amounts while the month is still loading — the grid itself is
  /// laid out from the calendar, so it never has to wait.
  final bool loading;

  static const int _rows = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final first = month.startOfMonth;
    final lead = (first.weekday - firstDayOfWeek + 7) % 7;
    final start = DateTime(first.year, first.month, first.day - lead);

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    _weekdayLabel((firstDayOfWeek + i - 1) % 7 + 1),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.mutedForeground,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < _rows; row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: _DayCell(
                    day: DateTime(
                      start.year,
                      start.month,
                      start.day + row * 7 + column,
                    ),
                    month: first,
                    selected: selected,
                    totals: totals,
                    loading: loading,
                    onSelect: onSelect,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// `Mon`, `Tue`, … for a DateTime.weekday value.
  static String _weekdayLabel(int weekday) {
    // 4 Jan 1970 was a Sunday, so this lands on the right day name without
    // needing a real date from the visible month.
    return DateX.weekdayShort(DateTime(1970, 1, 4 + weekday));
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.month,
    required this.selected,
    required this.totals,
    required this.loading,
    required this.onSelect,
  });

  final DateTime day;
  final DateTime month;
  final DateTime selected;
  final Map<DateTime, DayTotals> totals;
  final bool loading;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inMonth = day.year == month.year && day.month == month.month;
    final isToday = day.isToday;
    final isSelected = day.isSameDay(selected);
    final figures = totals[day.startOfDay];
    final net = figures?.net ?? 0;

    return InkWell(
      onTap: () => onSelect(day.startOfDay),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? c.primary : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (figures?.hasRecurring ?? false) ...[
                  Icon(LucideIcons.repeat, size: 9, color: c.mutedForeground),
                  const SizedBox(width: 2),
                ],
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? BoxDecoration(color: c.primary, shape: BoxShape.circle)
                      : null,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isToday || isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isToday
                          ? c.primaryForeground
                          : (inMonth ? c.foreground : c.mutedForeground),
                    ),
                  ),
                ),
              ],
            ),
            if (figures != null && !figures.isEmpty && net != 0)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Opacity(
                  opacity: loading ? 0.4 : 1,
                  child: Text(
                    Money.compact(net),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: net < 0 ? c.expense : c.income,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
