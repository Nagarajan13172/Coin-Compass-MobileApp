import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.openingBalance = 0,
    this.balance,
    this.currency = 'INR',
    this.institution,
    this.last4,
    this.color,
    this.icon,
    this.note,
    this.excludeFromTotal = false,
    this.archived = false,
    this.creditLimit,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final AccountType type;
  final num openingBalance;

  /// Present when the server computes it (`/accounts` may include a running
  /// balance); otherwise read it from `/transactions/balance` byAccount.
  final num? balance;
  final String currency;
  final String? institution;
  final String? last4;
  final String? color;
  final String? icon;
  final String? note;
  final bool excludeFromTotal;
  final bool archived;
  final num? creditLimit;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isLiability => type == AccountType.card;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: J.id(json['_id']),
    name: J.str(json['name']),
    type: AccountType.fromApi(J.strOrNull(json['type'])),
    openingBalance: J.number(json['openingBalance']),
    balance: J.numberOrNull(json['balance']),
    currency: J.str(json['currency'], 'INR'),
    institution: J.strOrNull(json['institution']),
    last4: J.strOrNull(json['last4']),
    color: J.strOrNull(json['color']),
    icon: J.strOrNull(json['icon']),
    note: J.strOrNull(json['note']),
    excludeFromTotal: J.boolean(json['excludeFromTotal']),
    archived: J.boolean(json['archived']),
    creditLimit: J.numberOrNull(json['creditLimit']),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  Map<String, dynamic> toWriteJson() => {
    'name': name,
    'type': type.api,
    'openingBalance': openingBalance,
    'currency': currency,
    if (institution != null) 'institution': institution,
    if (last4 != null) 'last4': last4,
    if (color != null) 'color': color,
    if (icon != null) 'icon': icon,
    if (note != null) 'note': note,
    'excludeFromTotal': excludeFromTotal,
    if (creditLimit != null) 'creditLimit': creditLimit,
  };
}
