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
    this.ticker,
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
    this.allocationPct = 0,
    this.currency = 'INR',
    this.pricedAt,
    this.stale = false,
    this.lots = const [],
  });

  /// The tradeable id with its exchange suffix: `RELIANCE.NS`. This is what
  /// `POST /stocks/buy` and `/stocks/sell` want.
  final String symbol;

  /// The bare ticker the API sends beside it: `RELIANCE`.
  final String? ticker;

  final String? name;
  final String? exchange;
  final String? demat;
  final num qty;
  final num avgCost;

  /// Wire name `price`; older payloads said `lastPrice`. Read [price], which
  /// falls back to the market value per share when neither key is present.
  final num lastPrice;

  final num marketValue;
  final num investedCost;
  final num unrealized;
  final num unrealizedPct;

  /// Only the portfolio totals carry a day change today — a position keeps the
  /// field so a payload that does send one renders, and the row hides it when
  /// it is absent.
  final num dayChange;
  final num dayChangePct;

  /// Share of the whole portfolio, server-computed. [allocationOf] recomputes
  /// it when the payload leaves it out.
  final num allocationPct;

  final String currency;
  final DateTime? pricedAt;
  final bool stale;
  final List<StockLot> lots;

  bool get isUp => unrealized >= 0;

  /// What a row shows first: the plain ticker, never the `.NS` suffix.
  String get displayTicker {
    final t = ticker;
    if (t != null && t.isNotEmpty) return t;
    final dot = symbol.indexOf('.');
    return dot > 0 ? symbol.substring(0, dot) : symbol;
  }

  /// `NSE` / `BSE`, derived from the symbol suffix when the API omits it.
  String? get exchangeLabel {
    final e = exchange;
    if (e != null && e.isNotEmpty) return e;
    if (symbol.endsWith('.NS')) return 'NSE';
    if (symbol.endsWith('.BO')) return 'BSE';
    return null;
  }

  /// Last traded price. Derived from the market value when the feed sent no
  /// price at all, so a row never shows a confident ₹0.
  num get price {
    if (lastPrice > 0) return lastPrice;
    return qty > 0 ? marketValue / qty : 0;
  }

  /// Share of [portfolioValue], preferring the server's own figure.
  num allocationOf(num portfolioValue) {
    if (allocationPct > 0) return allocationPct;
    if (portfolioValue <= 0) return 0;
    return marketValue / portfolioValue * 100;
  }

  factory StockPosition.fromJson(Map<String, dynamic> json) => StockPosition(
    symbol: J.str(json['symbol']),
    ticker: J.strOrNull(json['ticker']),
    name: J.strOrNull(json['name']),
    exchange: J.strOrNull(json['exchange']),
    demat: J.refId(json['demat']),
    qty: J.number(json['qty']),
    avgCost: J.number(json['avgCost']),
    lastPrice: J.number(json['price'] ?? json['lastPrice']),
    marketValue: J.number(json['marketValue']),
    investedCost: J.number(json['investedCost']),
    unrealized: J.number(json['unrealized']),
    unrealizedPct: J.number(json['unrealizedPct']),
    dayChange: J.number(json['dayChange']),
    dayChangePct: J.number(json['dayChangePct']),
    allocationPct: J.number(json['allocationPct']),
    currency: J.str(json['currency'], 'INR'),
    pricedAt: J.date(json['pricedAt'] ?? json['priceDate']),
    stale: J.boolean(json['stale']),
    lots: J.list(json['lots'], StockLot.fromJson),
  );
}

/// One purchase lot inside a position. The wire calls the open quantity
/// `qtyRemaining` — what is left after FIFO sales have eaten into it.
class StockLot {
  const StockLot({
    required this.id,
    this.symbol,
    this.qty = 0,
    this.buyPrice = 0,
    this.fees = 0,
    this.buyDate,
    this.demat,
    this.note,
    this.longTermFromServer,
    this.daysToLongTermFromServer,
  });

  final String id;
  final String? symbol;

  /// Wire name `qtyRemaining`.
  final num qty;

  final num buyPrice;

  /// Charges the server booked with the lot. The app cannot send these —
  /// `POST /stocks/buy` strips a `charges`/`fees` key — but a lot created on
  /// the web carries them, and they belong in the cost basis.
  final num fees;

  final DateTime? buyDate;
  final String? demat;
  final String? note;

  /// The server's own capital-gains tag, when it sends one.
  final bool? longTermFromServer;
  final num? daysToLongTermFromServer;

  /// Cost basis of [quantity] shares from this lot, charges apportioned.
  num costBasisFor(num quantity) {
    final feeShare = qty > 0 ? fees * quantity / qty : 0;
    return quantity * buyPrice + feeShare;
  }

  factory StockLot.fromJson(Map<String, dynamic> json) => StockLot(
    id: J.id(json['_id']),
    symbol: J.strOrNull(json['symbol']),
    qty: J.number(json['qtyRemaining'] ?? json['qty']),
    buyPrice: J.number(json['buyPrice']),
    fees: J.number(json['fees']),
    buyDate: J.date(json['buyDate'] ?? json['date']),
    demat: J.refId(json['demat']),
    note: J.strOrNull(json['note']),
    longTermFromServer: json['longTerm'] is bool
        ? json['longTerm'] as bool
        : null,
    daysToLongTermFromServer: J.numberOrNull(json['daysToLongTerm']),
  );
}

/// One closed position from `GET /stocks/sales`. The realized figure arrives
/// as `realizedPL`, already split into its long- and short-term halves.
class StockSale {
  const StockSale({
    required this.id,
    this.symbol,
    this.ticker,
    this.qty = 0,
    this.sellPrice = 0,
    this.buyPrice = 0,
    this.realized = 0,
    this.realizedLongTerm = 0,
    this.realizedShortTerm = 0,
    this.term,
    this.sellDate,
    this.buyDate,
  });

  final String id;
  final String? symbol;
  final String? ticker;
  final num qty;
  final num sellPrice;
  final num buyPrice;

  /// Wire name `realizedPL`.
  final num realized;

  final num realizedLongTerm;
  final num realizedShortTerm;

  /// 'short' | 'long' when the API tags the whole sale. A sale that straddles
  /// the twelve-month line has neither — read [isLongTerm] instead.
  final String? term;

  final DateTime? sellDate;
  final DateTime? buyDate;

  String get displayTicker {
    final t = ticker;
    if (t != null && t.isNotEmpty) return t;
    final s = symbol ?? '';
    final dot = s.indexOf('.');
    return dot > 0 ? s.substring(0, dot) : s;
  }

  /// True when every rupee of the gain is long-term.
  bool get isLongTerm =>
      term == 'long' || (realizedLongTerm != 0 && realizedShortTerm == 0);

  /// True when every rupee of the gain is short-term.
  bool get isShortTerm =>
      term == 'short' || (realizedShortTerm != 0 && realizedLongTerm == 0);

  factory StockSale.fromJson(Map<String, dynamic> json) => StockSale(
    id: J.id(json['_id']),
    symbol: J.strOrNull(json['symbol']),
    ticker: J.strOrNull(json['ticker']),
    qty: J.number(json['qty']),
    sellPrice: J.number(json['sellPrice']),
    buyPrice: J.number(json['buyPrice']),
    realized: J.number(json['realizedPL'] ?? json['realized']),
    realizedLongTerm: J.number(json['realizedLongTerm']),
    realizedShortTerm: J.number(json['realizedShortTerm']),
    term: J.strOrNull(json['term']),
    sellDate: J.date(json['sellDate'] ?? json['date']),
    buyDate: J.date(json['buyDate']),
  );
}

/// One row of `GET /stocks/search?q=`.
///
/// The live endpoint answers with
/// `{symbol, ticker, exchange, shortName, longName, sector, industry}` — and
/// **no price**. Search is a symbol lookup, not a quote: the buy sheet asks the
/// user for the price. Fields the response never carries are not modelled.
class StockQuote {
  const StockQuote({
    required this.symbol,
    this.ticker,
    this.shortName,
    this.longName,
    this.exchange,
    this.sector,
    this.industry,
  });

  /// The tradeable id, exchange suffix included: `RELIANCE.NS`. This is what
  /// `POST /stocks/buy` wants.
  final String symbol;

  /// The bare ticker without the suffix: `RELIANCE`.
  final String? ticker;
  final String? shortName;
  final String? longName;
  final String? exchange;
  final String? sector;
  final String? industry;

  /// What a result row shows: the trading name, falling back to the symbol.
  String get name => shortName ?? longName ?? symbol;

  /// `NSE · Energy`, skipping whichever half is missing.
  String get subtitle => [
    exchange,
    sector,
  ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');

  factory StockQuote.fromJson(Map<String, dynamic> json) => StockQuote(
    symbol: J.str(json['symbol']),
    ticker: J.strOrNull(json['ticker']),
    shortName: J.strOrNull(json['shortName']),
    longName: J.strOrNull(json['longName']),
    exchange: J.strOrNull(json['exchange']),
    sector: J.strOrNull(json['sector']),
    industry: J.strOrNull(json['industry']),
  );
}

/// One pending corporate action from `GET /stocks/splits`:
/// `{symbol, ticker, label, date, qtyBefore, qtyAfter}`.
///
/// The server detects the split; the client only confirms it. Applying one
/// rewrites the affected lots' quantities and leaves the cost basis alone.
class StockSplit {
  const StockSplit({
    required this.symbol,
    required this.date,
    this.ticker,
    this.label,
    this.qtyBefore = 0,
    this.qtyAfter = 0,
  });

  final String symbol;

  /// Kept as the **raw string the server sent**, because `/stocks/splits/apply`
  /// identifies the split by `{symbol, date}` and the two must match exactly.
  /// Use [day] for display.
  final String date;

  final String? ticker;

  /// The ratio as the server phrases it, e.g. `1:5`.
  final String? label;
  final num qtyBefore;
  final num qtyAfter;

  DateTime? get day => J.date(date);

  factory StockSplit.fromJson(Map<String, dynamic> json) => StockSplit(
    symbol: J.str(json['symbol']),
    date: J.str(json['date']),
    ticker: J.strOrNull(json['ticker']),
    label: J.strOrNull(json['label']),
    qtyBefore: J.number(json['qtyBefore']),
    qtyAfter: J.number(json['qtyAfter']),
  );

  /// The exact body `POST /stocks/splits/apply` takes — the web client sends
  /// these two keys and nothing else.
  Map<String, dynamic> toApplyJson() => {'symbol': symbol, 'date': date};
}
