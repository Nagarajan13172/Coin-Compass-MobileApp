import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../../../core/api/json.dart';
import '../domain/stock.dart';

/// `/stocks/*` — the equity book: positions, lots, sales, corporate splits.
///
/// Note the endpoint shapes, all verified live:
///  * `GET /stocks` is a 404. The portfolio lives at `/stocks/portfolio`.
///  * `GET /stocks/splits` lists pending splits, but **`POST /stocks/splits`
///    does not exist** — applying one goes to `/stocks/splits/apply`.
///  * `demat` on buy and sell is an **account id of type `demat`**, not a name.
///    Buying is impossible until such an account exists.
///
/// [buy] and [sell] take typed arguments rather than a map on purpose. Their
/// Zod schemas accept six keys each and silently drop everything else (the web
/// client sends a `fees` the probe does not list, and it goes nowhere), so the
/// body is assembled here where the guard test can read it, and a form sheet
/// has no way to add a field that would vanish.
class StocksRepository {
  const StocksRepository(this._api);

  final ApiClient _api;

  Future<StockPortfolio> portfolio() async {
    final json = await _api.getJson(Endpoints.stocksPortfolio);
    return StockPortfolio.fromJson(J.map(json));
  }

  /// Symbol lookup. Returns matches with no prices — see [StockQuote].
  Future<List<StockQuote>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final json = await _api.getJson(Endpoints.stocksSearch, query: {'q': q});
    return Envelope.rows(json, const [
      'results',
    ]).map(StockQuote.fromJson).toList();
  }

  /// Records a purchase lot. Body: `{symbol, demat, qty, buyPrice, buyDate?,
  /// note?}` — the complete accepted set for `POST /stocks/buy`.
  Future<void> buy({
    required String symbol,
    required String demat,
    required num qty,
    required num buyPrice,
    DateTime? buyDate,
    String? note,
  }) async {
    await _api.postJson(
      Endpoints.stocksBuy,
      body: {
        'symbol': symbol,
        'demat': demat,
        'qty': qty,
        'buyPrice': buyPrice,
        if (buyDate != null) 'buyDate': _apiDay(buyDate),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  /// Sells against the oldest lots (FIFO, server-side) and books the realized
  /// gain. Body: `{symbol, demat, qty, sellPrice, sellDate?, note?}`.
  Future<void> sell({
    required String symbol,
    required String demat,
    required num qty,
    required num sellPrice,
    DateTime? sellDate,
    String? note,
  }) async {
    await _api.postJson(
      Endpoints.stocksSell,
      body: {
        'symbol': symbol,
        'demat': demat,
        'qty': qty,
        'sellPrice': sellPrice,
        if (sellDate != null) 'sellDate': _apiDay(sellDate),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  /// Closed positions, newest first — the realized-gains history.
  Future<List<StockSale>> sales() async {
    final json = await _api.getJson(Endpoints.stocksSales);
    final rows = Envelope.rows(json, const [
      'sales',
    ]).map(StockSale.fromJson).toList();
    rows.sort((a, b) {
      final left = b.sellDate, right = a.sellDate;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
    return rows;
  }

  /// Reverses a sale: the lots it consumed come back and the realized gain is
  /// unbooked.
  Future<void> deleteSale(String id) =>
      _api.deleteJson(Endpoints.stocksSale(id));

  /// Removes a purchase lot outright — used to correct a mis-keyed buy.
  Future<void> deleteLot(String id) => _api.deleteJson(Endpoints.stocksLot(id));

  /// Corporate actions the server has detected but not yet applied.
  Future<List<StockSplit>> splits() async {
    final json = await _api.getJson(Endpoints.stocksSplits);
    return Envelope.rows(json, const [
      'splits',
    ]).map(StockSplit.fromJson).toList();
  }

  /// Applies one detected split, restating the affected lots' quantities and
  /// leaving their cost basis untouched. Identified by `{symbol, date}` — the
  /// date must be echoed back exactly as it arrived, which is why
  /// [StockSplit.date] is kept as a raw string.
  ///
  /// Immediate and irreversible; confirm with the user before calling.
  Future<void> applySplit(StockSplit split) =>
      _api.postJson(Endpoints.stocksSplitsApply, body: split.toApplyJson());

  /// Re-prices every position from the market feed and returns the repriced
  /// portfolio, so the caller can use the response directly instead of
  /// refetching. Takes no body.
  ///
  /// This hits a live quote provider on every call — wire it to an explicit
  /// user action, never to a build or a poll.
  Future<StockPortfolio> refresh() async {
    final json = await _api.postJson(Endpoints.stocksRefresh);
    return StockPortfolio.fromJson(J.map(json));
  }
}

/// A calendar day as the API stores it: UTC midnight. Buy and sell dates decide
/// the short/long-term capital-gains split, so a one-day drift from `toUtc()`
/// on a local midnight would be a real error, not a cosmetic one.
String _apiDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).toIso8601String();

final stocksRepositoryProvider = Provider<StocksRepository>(
  (ref) => StocksRepository(ref.watch(apiClientProvider)),
);

/// The portfolio, cached for the session. Prices are refreshed server-side, so
/// re-reading it does not re-quote; use `StocksRepository.refresh()` for that
/// and then `ref.invalidate(stockPortfolioProvider)`.
final stockPortfolioProvider = FutureProvider<StockPortfolio>(
  (ref) => ref.watch(stocksRepositoryProvider).portfolio(),
);

final stockSalesProvider = FutureProvider<List<StockSale>>(
  (ref) => ref.watch(stocksRepositoryProvider).sales(),
);

/// Usually empty — the banner that offers to apply a split only appears when
/// the server has actually detected one.
final stockSplitsProvider = FutureProvider<List<StockSplit>>(
  (ref) => ref.watch(stocksRepositoryProvider).splits(),
);

/// Symbol search, keyed by query. `autoDispose` so each abandoned search term
/// drops out of the cache instead of pinning a result list per keystroke.
final stockSearchProvider = FutureProvider.autoDispose
    .family<List<StockQuote>, String>(
      (ref, query) => ref.watch(stocksRepositoryProvider).search(query),
    );
