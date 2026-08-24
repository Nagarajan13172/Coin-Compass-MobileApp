import '../../../core/api/json.dart';

/// `GET /stocks/portfolio`
class StockPortfolio {
  const StockPortfolio({
    this.configured = false,
    this.positions = const [],
    this.totals = const StockTotals(),
    this.pricedAt,
    this.anyStale = false,
  });

  final bool configured;
  final List<StockPosition> positions;
  final StockTotals totals;
  final DateTime? pricedAt;
  final bool anyStale;

  factory StockPortfolio.fromJson(Map<String, dynamic> json) => StockPortfolio(
    configured: J.boolean(json['configured']),
    positions: J.list(json['positions'], StockPosition.fromJson),
    totals: StockTotals.fromJson(J.map(json['totals'])),
    pricedAt: J.date(json['pricedAt']),
    anyStale: J.boolean(json['anyStale']),
  );
}

class StockTotals {
  const StockTotals({
    this.marketValue = 0,
    this.investedCost = 0,
    this.unrealized = 0,
    this.unrealizedPct = 0,
    this.dayChange = 0,
    this.realizedPL = 0,
    this.realizedShortTerm = 0,
    this.realizedLongTerm = 0,
  });

  final num marketValue;
  final num investedCost;
  final num unrealized;
  final num unrealizedPct;
  final num dayChange;
  final num realizedPL;
  final num realizedShortTerm;
  final num realizedLongTerm;

  factory StockTotals.fromJson(Map<String, dynamic> json) => StockTotals(
    marketValue: J.number(json['marketValue']),
    investedCost: J.number(json['investedCost']),
    unrealized: J.number(json['unrealized']),
    unrealizedPct: J.number(json['unrealizedPct']),
    dayChange: J.number(json['dayChange']),
    realizedPL: J.number(json['realizedPL']),
    realizedShortTerm: J.number(json['realizedShortTerm']),
    realizedLongTerm: J.number(json['realizedLongTerm']),
  );
}

class StockPosition {
  const StockPosition({
    required this.symbol,
    this.name,
    this.exchange,
    this.demat,
    this.qty = 0,
    this.avgCost = 0,
    this.lastPrice = 0,
    this.marketValue = 0,
    this.investedCost = 0,
    this.unrealized = 0,
    this.unrealizedPct = 0,
    this.dayChange = 0,
    this.dayChangePct = 0,
    this.currency = 'INR',
    this.pricedAt,
    this.stale = false,
    this.lots = const [],
  });

  final String symbol;
  final String? name;
  final String? exchange;
  final String? demat;
  final num qty;
  final num avgCost;
  final num lastPrice;
  final num marketValue;
  final num investedCost;
  final num unrealized;
  final num unrealizedPct;
  final num dayChange;
  final num dayChangePct;
  final String currency;
  final DateTime? pricedAt;
  final bool stale;
  final List<StockLot> lots;

  bool get isUp => unrealized >= 0;

  factory StockPosition.fromJson(Map<String, dynamic> json) => StockPosition(
    symbol: J.str(json['symbol']),
    name: J.strOrNull(json['name']),
    exchange: J.strOrNull(json['exchange']),
    demat: J.refId(json['demat']),
    qty: J.number(json['qty']),
    avgCost: J.number(json['avgCost']),
    lastPrice: J.number(json['lastPrice']),
    marketValue: J.number(json['marketValue']),
    investedCost: J.number(json['investedCost']),
    unrealized: J.number(json['unrealized']),
    unrealizedPct: J.number(json['unrealizedPct']),
    dayChange: J.number(json['dayChange']),
    dayChangePct: J.number(json['dayChangePct']),
    currency: J.str(json['currency'], 'INR'),
    pricedAt: J.date(json['pricedAt']),
    stale: J.boolean(json['stale']),
    lots: J.list(json['lots'], StockLot.fromJson),
  );
}

class StockLot {
  const StockLot({
    required this.id,
    this.symbol,
    this.qty = 0,
    this.buyPrice = 0,
    this.buyDate,
    this.demat,
  });

  final String id;
  final String? symbol;
  final num qty;
  final num buyPrice;
  final DateTime? buyDate;
  final String? demat;

  factory StockLot.fromJson(Map<String, dynamic> json) => StockLot(
    id: J.id(json['_id']),
    symbol: J.strOrNull(json['symbol']),
    qty: J.number(json['qty']),
    buyPrice: J.number(json['buyPrice']),
    buyDate: J.date(json['buyDate'] ?? json['date']),
    demat: J.refId(json['demat']),
  );
}

class StockSale {
  const StockSale({
    required this.id,
    this.symbol,
    this.qty = 0,
    this.sellPrice = 0,
    this.buyPrice = 0,
    this.realized = 0,
    this.term,
    this.sellDate,
    this.buyDate,
  });

  final String id;
  final String? symbol;
  final num qty;
  final num sellPrice;
  final num buyPrice;
  final num realized;

  /// 'short' | 'long' — the API tags capital-gains term.
  final String? term;
  final DateTime? sellDate;
  final DateTime? buyDate;

  factory StockSale.fromJson(Map<String, dynamic> json) => StockSale(
    id: J.id(json['_id']),
    symbol: J.strOrNull(json['symbol']),
    qty: J.number(json['qty']),
    sellPrice: J.number(json['sellPrice']),
    buyPrice: J.number(json['buyPrice']),
    realized: J.number(json['realized'] ?? json['realizedPL']),
    term: J.strOrNull(json['term']),
    sellDate: J.date(json['sellDate'] ?? json['date']),
    buyDate: J.date(json['buyDate']),
  );
}

/// `GET /stocks/search?q=`
class StockQuote {
  const StockQuote({
    required this.symbol,
    this.name,
    this.exchange,
    this.lastPrice,
    this.currency = 'INR',
  });

  final String symbol;
  final String? name;
  final String? exchange;
  final num? lastPrice;
  final String currency;

  factory StockQuote.fromJson(Map<String, dynamic> json) => StockQuote(
    symbol: J.str(json['symbol']),
    name: J.strOrNull(json['name'] ?? json['shortname']),
    exchange: J.strOrNull(json['exchange']),
    lastPrice: J.numberOrNull(json['lastPrice'] ?? json['price']),
    currency: J.str(json['currency'], 'INR'),
  );
}
