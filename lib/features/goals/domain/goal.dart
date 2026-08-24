import '../../../core/api/json.dart';

/// A savings goal. `POST /goals` declares only name, targetAmount,
/// savedAmount, targetDate, monthlyContribution, color, icon and currency —
/// a `note` was being typed and silently dropped, so it is gone
/// (docs/WRITE_SCHEMAS.md).
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.targetAmount,
    this.savedAmount = 0,
    this.targetDate,
    this.monthlyContribution = 0,
    this.color = '#6366F1',
    this.icon = 'goal',
    this.currency = 'INR',
    this.achievedAt,
    this.remaining,
    this.percentFromServer,
    this.completeFromServer,
    this.monthsLeft,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final num targetAmount;
  final num savedAmount;
  final DateTime? targetDate;
  final num monthlyContribution;
  final String color;
  final String icon;
  final String currency;
  final DateTime? achievedAt;

  // The server returns these computed fields on create/list.
  final num? remaining;
  final num? percentFromServer;
  final bool? completeFromServer;
  final num? monthsLeft;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  num get remainingOrComputed =>
      remaining ?? (targetAmount - savedAmount).clamp(0, targetAmount);

  /// 0..1 for progress indicators.
  double get progress => targetAmount <= 0
      ? 0
      : (savedAmount / targetAmount).clamp(0, 1).toDouble();

  num get percent => percentFromServer ?? (progress * 100);
  bool get isComplete =>
      completeFromServer ?? (savedAmount >= targetAmount && targetAmount > 0);

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: J.id(json['_id']),
    name: J.str(json['name']),
    targetAmount: J.number(json['targetAmount']),
    savedAmount: J.number(json['savedAmount']),
    targetDate: J.date(json['targetDate']),
    monthlyContribution: J.number(json['monthlyContribution']),
    color: J.str(json['color'], '#6366F1'),
    icon: J.str(json['icon'], 'goal'),
    currency: J.str(json['currency'], 'INR'),
    achievedAt: J.date(json['achievedAt']),
    remaining: J.numberOrNull(json['remaining']),
    percentFromServer: J.numberOrNull(json['percent']),
    completeFromServer: json['complete'] == null
        ? null
        : J.boolean(json['complete']),
    monthsLeft: J.numberOrNull(json['monthsLeft']),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  Map<String, dynamic> toWriteJson() => {
    'name': name,
    'targetAmount': targetAmount,
    'savedAmount': savedAmount,
    if (targetDate != null) 'targetDate': targetDate!.toUtc().toIso8601String(),
    'monthlyContribution': monthlyContribution,
    'color': color,
    'icon': icon,
    'currency': currency,
  };
}
