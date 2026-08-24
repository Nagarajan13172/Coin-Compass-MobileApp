import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Date helpers shared across the app. The API speaks ISO-8601 strings.
///
/// `DateFormat` with an explicit locale needs `initializeDateFormatting()` to
/// have run, otherwise it throws LocaleDataException. We guard it lazily here so
/// callers (and tests) never have to remember.
class DateX {
  const DateX._();

  static bool _localeReady = false;

  static void _ensureLocale() {
    if (_localeReady) return;
    initializeDateFormatting();
    _localeReady = true;
  }

  /// Date *patterns* use `en_US`, not `en_IN`. Dart's ICU data for en_IN renders
  /// `Sept` and lowercase `am`/`pm`, whereas the CoinCompass web app (JS Intl
  /// `en-IN`) renders `Sep` and `AM`. en_US matches the web output exactly.
  /// Number grouping stays on en_IN — see [Money], which is unaffected.
  static const String _patternLocale = 'en_US';

  static DateFormat _fmt(String pattern) {
    _ensureLocale();
    return DateFormat(pattern, _patternLocale);
  }

  /// Tolerant parse — the API returns both full ISO stamps and `yyyy-MM-dd`.
  static DateTime? parse(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  static String toApi(DateTime date) => date.toUtc().toIso8601String();
  static String toYmd(DateTime date) => _fmt('yyyy-MM-dd').format(date);

  static String monthLabel(DateTime d) => _fmt('MMMM yyyy').format(d);
  static String dayLabel(DateTime d) => _fmt('EEEE, dd MMM yyyy').format(d);

  /// `Mon`, `Tue`, … — the calendar's weekday header row.
  static String weekdayShort(DateTime d) => _fmt('EEE').format(d);

  /// `M`, `T`, … for very tight layouts.
  static String weekdayNarrow(DateTime d) => _fmt('EEEEE').format(d);

  static String shortDay(DateTime d) => _fmt('dd MMM').format(d);
  static String timeLabel(DateTime d) => _fmt('h:mm a').format(d);

  /// `1 Aug – 1 Sep 2026`, collapsing the year when both ends share it.
  static String rangeLabel(DateTime start, DateTime end) {
    final dash = '–';
    if (start.year == end.year) {
      return '${_fmt('d MMM').format(start)} $dash ${_fmt('d MMM').format(end)} ${end.year}';
    }
    return '${_fmt('d MMM').format(start)} ${start.year} $dash '
        '${_fmt('d MMM').format(end)} ${end.year}';
  }

  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return shortDay(d);
  }
}

extension DateTimeX on DateTime {
  DateTime get startOfDay => DateTime(year, month, day);
  DateTime get endOfDay => DateTime(year, month, day, 23, 59, 59, 999);

  DateTime get startOfMonth => DateTime(year, month);
  DateTime get endOfMonth =>
      DateTime(year, month + 1).subtract(const Duration(milliseconds: 1));

  DateTime get startOfYear => DateTime(year);
  DateTime get endOfYear =>
      DateTime(year + 1).subtract(const Duration(milliseconds: 1));

  /// [firstDayOfWeek] follows the API's `settings.firstDayOfWeek`
  /// (1 = Monday, 7 = Sunday), matching DateTime.weekday.
  DateTime startOfWeek([int firstDayOfWeek = 1]) {
    final delta = (weekday - firstDayOfWeek + 7) % 7;
    return startOfDay.subtract(Duration(days: delta));
  }

  DateTime endOfWeek([int firstDayOfWeek = 1]) => startOfWeek(
    firstDayOfWeek,
  ).add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));

  /// Steps [months] forward (or backward, for a negative value), clamping the
  /// day to the target month's length: `31 Jan + 1 month` -> `28 Feb`.
  ///
  /// The year carry must be *floor* division, not `~/`: Dart truncates toward
  /// zero while `%` stays non-negative, so `~/` would leave January - 1 month
  /// as December of the *same* year instead of the previous one.
  DateTime addMonths(int months) {
    final total = month - 1 + months;
    final y = year + (total - (total % 12)) ~/ 12;
    final m = total % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, day > lastDay ? lastDay : day, hour, minute);
  }

  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  bool get isToday => isSameDay(DateTime.now());
}
