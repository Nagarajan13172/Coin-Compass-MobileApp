import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';

/// One `/accounts` document.
///
/// Two Dart names deliberately differ from their wire names, because the app's
/// vocabulary reads better than the API's:
/// * [openingBalance] is the wire's `initialBalance`.
/// * [excludeFromTotal] is the *inverse* of the wire's `includeInTotal`, which
///   the server defaults to `true` when the key is absent.
///
/// Everything else matches the write schema, which accepts exactly
/// `name, type, initialBalance, includeInTotal, color, icon, currency`
/// (plus `archived`) and silently strips anything else.
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

  /// Wire name: `initialBalance`.
  final num openingBalance;

  /// Present when the server computes it (`/accounts` may include a running
  /// balance); otherwise read it from `/transactions/balance` byAccount.
  final num? balance;
  final String currency;

  // The four fields below are read-only: they are not part of the accounts
  // write schema, so the app never sends them and the current server never
  // returns them. They stay so a document that *does* carry them (an older
  // record, or a future schema addition) still renders instead of being
  // dropped on the floor.
  final String? institution;
  final String? last4;
  final String? note;
  final num? creditLimit;

  final String? color;
  final String? icon;

  /// Wire name: `includeInTotal`, inverted.
  final bool excludeFromTotal;
  final bool archived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isLiability => type == AccountType.card;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: J.id(json['_id']),
    name: J.str(json['name']),
    type: AccountType.fromApi(J.strOrNull(json['type'])),
    openingBalance: J.number(json['initialBalance']),
    balance: J.numberOrNull(json['balance']),
    currency: J.str(json['currency'], 'INR'),
    institution: J.strOrNull(json['institution']),
    last4: J.strOrNull(json['last4']),
    color: J.strOrNull(json['color']),
    icon: J.strOrNull(json['icon']),
    note: J.strOrNull(json['note']),
    // The fallback matters: a document without the key is *included*, so
    // dropping it here would silently exclude every such account.
    excludeFromTotal: !J.boolean(json['includeInTotal'], true),
    archived: J.boolean(json['archived']),
    creditLimit: J.numberOrNull(json['creditLimit']),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  /// Only the keys POST/PATCH `/accounts` actually accepts — anything else is
  /// stripped by the server's schema, which makes a silent data loss.
  Map<String, dynamic> toWriteJson() => {
    'name': name,
    'type': type.api,
    'initialBalance': openingBalance,
    'currency': currency,
    if (color != null) 'color': color,
    if (icon != null) 'icon': icon,
    'includeInTotal': !excludeFromTotal,
  };
}
