import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';

/// The "Quick add" chips on the Transactions screen.
class Template {
  const Template({
    required this.id,
    required this.name,
    this.type = TransactionType.expense,
    this.amount,
    this.accountId,
    this.categoryId,
    this.payee,
    this.note,
    this.tags = const [],
    this.currency = 'INR',
    this.icon,
    this.color,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final TransactionType type;
  final num? amount;
  final String? accountId;
  final String? categoryId;
  final String? payee;
  final String? note;
  final List<String> tags;
  final String currency;
  final String? icon;
  final String? color;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Template.fromJson(Map<String, dynamic> json) => Template(
    id: J.id(json['_id']),
    name: J.str(json['name']),
    type: TransactionType.fromApi(J.strOrNull(json['type'])),
    amount: J.numberOrNull(json['amount']),
    accountId: J.refId(json['account']),
    categoryId: J.refId(json['category']),
    payee: J.strOrNull(json['payee']),
    note: J.strOrNull(json['note']),
    tags: J.stringList(json['tags']),
    currency: J.str(json['currency'], 'INR'),
    icon: J.strOrNull(json['icon']),
    color: J.strOrNull(json['color']),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  Map<String, dynamic> toWriteJson() => {
    'name': name,
    'type': type.api,
    if (amount != null) 'amount': amount,
    if (accountId != null) 'account': accountId,
    if (categoryId != null) 'category': categoryId,
    if (payee != null) 'payee': payee,
    if (note != null) 'note': note,
    if (tags.isNotEmpty) 'tags': tags,
    'currency': currency,
    if (icon != null) 'icon': icon,
    if (color != null) 'color': color,
  };
}
