import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';
import '../../categories/domain/category.dart';

/// The window the server measured a budget's `spent` over — `start` inclusive,
/// `end` exclusive (a monthly window ends on the 1st of the next month).
class BudgetPeriodRange {
  const BudgetPeriodRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// Whole days left in the window, today included. 0 once it has closed.
  int get daysLeft {
    final remaining = end.difference(DateTime.now()).inHours / 24;
    return remaining <= 0 ? 0 : remaining.ceil();
  }

  static BudgetPeriodRange? fromJson(Object? value) {
    if (value is! Map) return null;
    final start = J.date(value['start']);
    final end = J.date(value['end']);
    if (start == null || end == null) return null;
    return BudgetPeriodRange(start: start, end: end);
  }
}

/// A spending limit. The server owns the whole write surface: `amount`,
/// `category`, `period`, `currency` and `startDate` — nothing else is declared
/// by its schema, so nothing else is sent (see docs/WRITE_SCHEMAS.md).
class Budget {
  const Budget({
    required this.id,
    required this.amount,
    this.categoryId,
    this.category,
    this.period = BudgetPeriod.monthly,
    this.spent,
    this.remaining,
    this.percent,
    this.over,
    this.periodRange,
    this.currency = 'INR',
    this.startDate,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final num amount;
  final String? categoryId;
  final Category? category;
  final BudgetPeriod period;

  /// Server-computed when present; otherwise derive from /reports/by-category.
  final num? spent;
  final num? remaining;

  /// A **whole-number percentage** of the limit used: `1331` means 1331%,
  /// not 13.31. Never treat it as a 0..1 fraction.
  final num? percent;

  /// The server's own over-limit verdict — authoritative when present.
  final bool? over;

  /// The window `spent` covers, when the server sent one.
  final BudgetPeriodRange? periodRange;

  final String currency;
  final DateTime? startDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whole-number percent of the limit used. The server's figure wins; [used]
  /// covers the rows where the spend was measured from `/reports/*` instead.
  /// Null while nothing has resolved yet.
  num? percentUsed(num? used) {
    if (percent != null) return percent;
    if (used == null || amount <= 0) return null;
    return used / amount * 100;
  }

  /// 0..1 for a progress bar — clamped, so 1331% still paints a full bar while
  /// [percentUsed] reports the true figure.
  double barValue(num? used) =>
      ((percentUsed(used) ?? 0) / 100).clamp(0, 1).toDouble();

  /// The server's verdict when it sent one, else a comparison against [used].
  bool isOver(num? used) => over ?? (used != null && used > amount);

  /// Past 80% of the limit but not over it.
  bool isNearLimit(num? used) {
    if (isOver(used)) return false;
    final percent = percentUsed(used);
    return percent != null && percent >= 80;
  }

  factory Budget.fromJson(Map<String, dynamic> json) {
    final categoryObject = J.refObject(json['category']);
    return Budget(
      id: J.id(json['_id']),
      amount: J.number(json['amount']),
      categoryId: J.refId(json['category']),
      category: categoryObject == null
          ? null
          : Category.fromJson(categoryObject),
      period: BudgetPeriod.fromApi(J.strOrNull(json['period'])),
      spent: J.numberOrNull(json['spent']),
      remaining: J.numberOrNull(json['remaining']),
      percent: J.numberOrNull(json['percent']),
      over: json['over'] == null ? null : J.boolean(json['over']),
      periodRange: BudgetPeriodRange.fromJson(json['periodRange']),
      currency: J.str(json['currency'], 'INR'),
      startDate: J.date(json['startDate']),
      createdAt: J.date(json['createdAt']),
      updatedAt: J.date(json['updatedAt']),
    );
  }

  Map<String, dynamic> toWriteJson() => {
    'amount': amount,
    if (categoryId != null) 'category': categoryId,
    'period': period.api,
    'currency': currency,
    if (startDate != null) 'startDate': startDate!.toUtc().toIso8601String(),
  };
}
