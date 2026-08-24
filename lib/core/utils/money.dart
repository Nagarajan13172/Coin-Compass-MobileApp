import 'package:intl/intl.dart';

/// INR formatting with Indian digit grouping (1,23,456 — not 123,456).
/// The backend stores whole rupees, so decimals are shown only when present.
class Money {
  const Money._();

  static const String rupee = '₹';

  /// 1,00,00,000 — the point past which a full figure stops fitting in a
  /// dense row. See `MoneyText.compactAbove`.
  static const num crore = 10000000;
  static const String minus = '−'; // real minus sign, matches the web app

  /// Symbols for the four currencies the backend seeds. Only a fallback: when
  /// the settings document has loaded, prefer the symbol it carries in
  /// `currencies[]` (see `currencySymbolProvider`). Used directly where no
  /// settings read is available — a notification carries its own `currency`
  /// code, and the web formats it with that currency rather than the base one.
  static const Map<String, String> seededSymbols = {
    'INR': rupee,
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
  };

  /// The symbol for an ISO code, falling back to the rupee — which is the base
  /// currency of the account this app ships against.
  static String symbolFor(String? code) =>
      code == null ? rupee : (seededSymbols[code.toUpperCase()] ?? rupee);

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
  ///
  /// [signed] adds a leading `+` to a positive value, matching [format] — an
  /// income row reads `+₹1.5L`, not `₹1.5L`.
  ///
  /// [decimals] fixes how many digits follow the point. Left null the value is
  /// trimmed to at most two, which is what every screen before Phase 5 wanted.
  /// The two call sites that need something else are on Reports and Insights:
  /// the delta pill compacts money with **0** decimals (`₹13K`, matching JS
  /// `Intl` with `maximumFractionDigits: 0`) while a chart's Y axis uses **1**
  /// (`13.3K`). Two different roundings of the same number on one screen — the
  /// web does exactly this, so the knob is the parity, not a convenience.
  static String compact(
    num amount, {
    String symbol = rupee,
    bool signed = false,
    int? decimals,
  }) {
    final abs = amount.abs();
    final sign = amount < 0
        ? minus
        : (signed && amount > 0 ? '+' : '');

    String scaled(num value) =>
        decimals == null ? _trim(value) : _round(value, decimals);

    String body;
    if (abs >= 10000000) {
      body = '${scaled(abs / 10000000)}Cr';
    } else if (abs >= 100000) {
      body = '${scaled(abs / 100000)}L';
    } else if (abs >= 1000) {
      body = '${scaled(abs / 1000)}K';
    } else {
      body = abs % 1 == 0 ? abs.toStringAsFixed(0) : scaled(abs);
    }
    return '$sign$symbol$body';
  }

  /// The dense-row convention, in one place: state the amount in **full**
  /// until it stops fitting, then compact it.
  ///
  /// `dense(13278)` -> `₹13,278`, `dense(123456789)` -> `₹12.35Cr`.
  ///
  /// Hero figures (a StatCard, an Insights headline) are never compacted at
  /// all; chart axes always are. This is for everything in between — a tile
  /// caption, a "Last month: …" line, a mover row — where a nine-figure value
  /// would push its own label off the row but ₹13,278 must stay exact. It is
  /// the string form of [MoneyText]'s `compactAbove: Money.crore`; two Phase-5
  /// screens had each written their own copy of it.
  static String dense(
    num amount, {
    num threshold = crore,
    String symbol = rupee,
    bool signed = false,
  }) => amount.abs() >= threshold
      ? compact(amount, symbol: symbol, signed: signed)
      : format(amount, symbol: symbol, signed: signed);

  /// Same as [compact] without the currency symbol — for chart axis labels,
  /// which the web renders with one decimal (`13.3K`).
  static String compactPlain(num amount, {int? decimals}) =>
      compact(amount, symbol: '', decimals: decimals);

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

  /// Rounds to [decimals] places and drops a trailing `.0`, so 13.35 -> `13.4`
  /// at one decimal and 13 -> `13`, never `13.0`.
  static String _round(num v, int decimals) {
    final s = v.toStringAsFixed(decimals);
    return decimals == 0 ? s : s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
