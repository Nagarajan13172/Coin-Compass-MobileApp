import '../../../core/api/json.dart';

/// `GET /metals/latest` -> `{configured, gold, silver}`
class MetalsLatest {
  const MetalsLatest({this.configured = false, this.gold, this.silver});

  final bool configured;
  final MetalPrice? gold;
  final MetalPrice? silver;

  factory MetalsLatest.fromJson(Map<String, dynamic> json) {
    final gold = J.refObject(json['gold']);
    final silver = J.refObject(json['silver']);
    return MetalsLatest(
      configured: J.boolean(json['configured']),
      gold: gold == null ? null : MetalPrice.fromJson(gold),
      silver: silver == null ? null : MetalPrice.fromJson(silver),
    );
  }
}

class MetalPrice {
  const MetalPrice({
    required this.metal,
    this.date,
    this.retail18k = 0,
    this.retail22k = 0,
    this.retail24k = 0,
    this.pricePerGram18k = 0,
    this.pricePerGram22k = 0,
    this.pricePerGram24k = 0,
    this.pricePerOunce = 0,
    this.change = 0,
    this.changePct = 0,
    this.prevClose = 0,
    this.source,
    this.retailSource,
    this.currency = 'INR',
    this.fetchedAt,
  });

  /// 'gold' | 'silver'
  final String metal;
  final String? date;
  final num retail18k;
  final num retail22k;
  final num retail24k;
  final num pricePerGram18k;
  final num pricePerGram22k;
  final num pricePerGram24k;
  final num pricePerOunce;
  final num change;
  final num changePct;
  final num prevClose;
  final String? source;
  final String? retailSource;
  final String currency;
  final DateTime? fetchedAt;

  bool get isGold => metal == 'gold';
  bool get isUp => change >= 0;

  /// The headline figure the dashboard card shows: retail 22k for gold,
  /// per-gram for silver (its retail fields come back as 0).
  num get headlinePrice {
    if (isGold) {
      if (retail22k > 0) return retail22k;
      return pricePerGram22k;
    }
    if (retail24k > 0) return retail24k;
    return pricePerGram24k;
  }

  factory MetalPrice.fromJson(Map<String, dynamic> json) => MetalPrice(
    metal: J.str(json['metal']),
    date: J.strOrNull(json['date']),
    retail18k: J.number(json['retail18k']),
    retail22k: J.number(json['retail22k']),
    retail24k: J.number(json['retail24k']),
    pricePerGram18k: J.number(json['pricePerGram18k']),
    pricePerGram22k: J.number(json['pricePerGram22k']),
    pricePerGram24k: J.number(json['pricePerGram24k']),
    pricePerOunce: J.number(json['pricePerOunce']),
    change: J.number(json['change']),
    changePct: J.number(json['changePct']),
    prevClose: J.number(json['prevClose']),
    source: J.strOrNull(json['source']),
    retailSource: J.strOrNull(json['retailSource']),
    currency: J.str(json['currency'], 'INR'),
    fetchedAt: J.date(json['fetchedAt']),
  );
}
