import 'package:intl/intl.dart';

/// INR formatting with Indian digit grouping (1,23,456 — not 123,456).
/// The backend stores whole rupees, so decimals are shown only when present.
class Money {
  const Money._();

  static const String rupee = '₹';
  static const String minus = '−'; // real minus sign, matches the web app

  static final NumberFormat _whole = NumberFormat.decimalPattern('en_IN')
    ..maximumFractionDigits = 0;
  static final NumberFormat _decimal = NumberFormat.decimalPattern('en_IN')
    ..minimumFractionDigits = 2
    ..maximumFractionDigits = 2;

  /// `format(13312)` -> `₹13,312`
  /// `format(-13312, signed: true)` -> `−₹13,312`
  /// `format(1234.5)` -> `₹1,234.50`
  static String format(
    num amount, {
    String symbol = rupee,
    bool signed = false,
  }) {
    final abs = amount.abs();
    final isWhole = abs % 1 == 0;
    final digits = isWhole ? _whole.format(abs) : _decimal.format(abs);

    var prefix = '';
    if (amount < 0) {
      prefix = minus;
    } else if (signed && amount > 0) {
      prefix = '+';
    }
    return '$prefix$symbol$digits';
  }

  /// Indian short scale for chart axes and tight rows.
  /// 14000 -> `14K`, 150000 -> `1.5L`, 12500000 -> `1.25Cr`
  static String compact(num amount, {String symbol = rupee}) {
    final abs = amount.abs();
    final sign = amount < 0 ? minus : '';

    String body;
    if (abs >= 10000000) {
      body = '${_trim(abs / 10000000)}Cr';
    } else if (abs >= 100000) {
      body = '${_trim(abs / 100000)}L';
    } else if (abs >= 1000) {
      body = '${_trim(abs / 1000)}K';
    } else {
      body = abs % 1 == 0 ? abs.toStringAsFixed(0) : _trim(abs);
    }
    return '$sign$symbol$body';
  }

  /// Same as [compact] without the currency symbol — for chart axis labels.
  static String compactPlain(num amount) => compact(amount, symbol: '');

  /// `percent(0.4667)` -> `46.7%`; pass alreadyScaled for API values like 46.7.
  static String percent(
    num? value, {
    bool alreadyScaled = false,
    int decimals = 1,
  }) {
    if (value == null) return '—';
    final v = alreadyScaled ? value : value * 100;
    final s = v.abs() % 1 == 0
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(decimals);
    return '$s%';
  }

  /// Signed delta with an arrow, e.g. `↗ +12.4%` / `↘ −3.0%`.
  static String signedPercent(num? value, {bool alreadyScaled = true}) {
    if (value == null) return '—';
    final v = alreadyScaled ? value : value * 100;
    final arrow = v > 0 ? '↗' : (v < 0 ? '↘' : '');
    final sign = v > 0 ? '+' : (v < 0 ? minus : '');
    final s = v.abs() % 1 == 0
        ? v.abs().toStringAsFixed(0)
        : v.abs().toStringAsFixed(2);
    return '$arrow $sign$s%'.trim();
  }

  static String _trim(num v) {
    final s = v.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
