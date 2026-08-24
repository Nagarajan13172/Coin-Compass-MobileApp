import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';
import '../../accounts/domain/account.dart';
import '../../categories/domain/category.dart';

class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.type,
    required this.amount,
    this.accountId,
    this.account,
    this.toAccountId,
    this.categoryId,
    this.category,
    this.note = '',
    this.payee = '',
    this.tags = const [],
    this.currency = 'INR',
    this.loanId,
    this.frequency = Frequency.monthly,
    this.interval = 1,
    this.startDate,
    this.nextRun,
    this.endDate,
    this.lastRun,
    this.active = true,
    this.upcoming = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final TransactionType type;
  final num amount;
  final String? accountId;
  final Account? account;
  final String? toAccountId;
  final String? categoryId;
  final Category? category;
  final String note;
  final String payee;
  final List<String> tags;
  final String currency;
  final String? loanId;
  final Frequency frequency;
  final int interval;
  final DateTime? startDate;
  final DateTime? nextRun;
  final DateTime? endDate;
  final DateTime? lastRun;
  final bool active;

  /// The server projects the next few occurrences.
  final List<DateTime> upcoming;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get title {
    if (payee.isNotEmpty) return payee;
    if (category != null && category!.name.isNotEmpty) return category!.name;
    if (note.isNotEmpty) return note;
    return type.label;
  }

  /// `Monthly` / `Every 2 months`
  String get cadenceLabel =>
      interval <= 1 ? frequency.label : 'Every $interval ${_unit()}';

  String _unit() => switch (frequency) {
    Frequency.daily => 'days',
    Frequency.weekly => 'weeks',
    Frequency.monthly => 'months',
    Frequency.yearly => 'years',
  };

  factory RecurringRule.fromJson(Map<String, dynamic> json) {
    final categoryObject = J.refObject(json['category']);
    final accountObject = J.refObject(json['account']);
    final raw = json['upcoming'];
    return RecurringRule(
      id: J.id(json['_id']),
      type: TransactionType.fromApi(J.strOrNull(json['type'])),
      amount: J.number(json['amount']),
      accountId: J.refId(json['account']),
      account: accountObject == null ? null : Account.fromJson(accountObject),
      toAccountId: J.refId(json['toAccount']),
      categoryId: J.refId(json['category']),
      category: categoryObject == null
          ? null
          : Category.fromJson(categoryObject),
      note: J.str(json['note']),
      payee: J.str(json['payee']),
      tags: J.stringList(json['tags']),
      currency: J.str(json['currency'], 'INR'),
      loanId: J.refId(json['loan']),
      frequency: Frequency.fromApi(J.strOrNull(json['frequency'])),
      interval: J.integer(json['interval'], 1),
      startDate: J.date(json['startDate']),
      nextRun: J.date(json['nextRun']),
      endDate: J.date(json['endDate']),
      lastRun: J.date(json['lastRun']),
      active: J.boolean(json['active'], true),
      upcoming: raw is List
          ? raw.map(J.date).whereType<DateTime>().toList()
          : const [],
      createdAt: J.date(json['createdAt']),
      updatedAt: J.date(json['updatedAt']),
    );
  }

  Map<String, dynamic> toWriteJson() => {
    'type': type.api,
    'amount': amount,
    if (accountId != null) 'account': accountId,
    if (toAccountId != null) 'toAccount': toAccountId,
    if (categoryId != null) 'category': categoryId,
    'note': note,
    'payee': payee,
    if (tags.isNotEmpty) 'tags': tags,
    'currency': currency,
    'frequency': frequency.api,
    'interval': interval,
    if (startDate != null) 'startDate': startDate!.toUtc().toIso8601String(),
    if (endDate != null) 'endDate': endDate!.toUtc().toIso8601String(),
    'active': active,
  };
}
