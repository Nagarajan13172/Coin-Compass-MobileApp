import '../../../core/api/json.dart';

/// One row of `GET /networth/history`. `date` is a plain `yyyy-MM-dd` string.
class NetWorthPoint {
  const NetWorthPoint({
    required this.id,
    required this.date,
    this.netWorth = 0,
    this.assets = 0,
    this.liabilities = 0,
    this.accountsTotal = 0,
    this.holdingsTotal = 0,
    this.stocksTotal = 0,
    this.investment = 0,
    this.saving = 0,
    this.currency = 'INR',
    this.createdAt,
  });

  final String id;
  final DateTime date;
  final num netWorth;
  final num assets;
  final num liabilities;
  final num accountsTotal;
  final num holdingsTotal;

  /// Added in a later backend revision — absent on older rows.
  final num stocksTotal;
  final num investment;
  final num saving;
  final String currency;
  final DateTime? createdAt;

  factory NetWorthPoint.fromJson(Map<String, dynamic> json) => NetWorthPoint(
    id: J.id(json['_id']),
    date: J.date(json['date']) ?? DateTime.now(),
    netWorth: J.number(json['netWorth']),
    assets: J.number(json['assets']),
    liabilities: J.number(json['liabilities']),
    accountsTotal: J.number(json['accountsTotal']),
    holdingsTotal: J.number(json['holdingsTotal']),
    stocksTotal: J.number(json['stocksTotal']),
    investment: J.number(json['investment']),
    saving: J.number(json['saving']),
    currency: J.str(json['currency'], 'INR'),
    createdAt: J.date(json['createdAt']),
  );
}
