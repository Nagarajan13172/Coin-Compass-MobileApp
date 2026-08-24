import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';
import '../../categories/domain/category.dart';

class Budget {
  const Budget({
    required this.id,
    required this.amount,
    this.name,
    this.categoryId,
    this.category,
    this.period = BudgetPeriod.monthly,
    this.rollover = false,
    this.spent,
    this.remaining,
    this.percent,
    this.currency = 'INR',
    this.startDate,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final num amount;
  final String? name;
  final String? categoryId;
  final Category? category;
  final BudgetPeriod period;
  final bool rollover;

  /// Server-computed when present; otherwise derive from /reports/by-category.
  final num? spent;
  final num? remaining;
  final num? percent;
  final String currency;
  final DateTime? startDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  num get spentOrZero => spent ?? 0;
  num get progress => amount <= 0 ? 0 : (spentOrZero / amount).clamp(0, 1);
  bool get isOver => spentOrZero > amount;
  bool get isNearLimit => !isOver && progress >= 0.8;

  factory Budget.fromJson(Map<String, dynamic> json) {
    final categoryObject = J.refObject(json['category']);
    return Budget(
      id: J.id(json['_id']),
      amount: J.number(json['amount']),
      name: J.strOrNull(json['name']),
      categoryId: J.refId(json['category']),
      category: categoryObject == null
          ? null
          : Category.fromJson(categoryObject),
      period: BudgetPeriod.fromApi(J.strOrNull(json['period'])),
      rollover: J.boolean(json['rollover']),
      spent: J.numberOrNull(json['spent']),
      remaining: J.numberOrNull(json['remaining']),
      percent: J.numberOrNull(json['percent']),
      currency: J.str(json['currency'], 'INR'),
      startDate: J.date(json['startDate']),
      createdAt: J.date(json['createdAt']),
      updatedAt: J.date(json['updatedAt']),
    );
  }

  Map<String, dynamic> toWriteJson() => {
    'amount': amount,
    if (name != null) 'name': name,
    if (categoryId != null) 'category': categoryId,
    'period': period.api,
    'rollover': rollover,
    'currency': currency,
  };
}
