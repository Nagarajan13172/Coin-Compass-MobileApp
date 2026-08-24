import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/enums.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../data/stocks_repository.dart';
import '../domain/stock.dart';

/// Which half of the book the screen is showing.
enum StocksTab { holdings, sold }

final stocksTabProvider = StateProvider<StocksTab>(
  (ref) => StocksTab.holdings,
);

/// Buying and selling both require `demat` — **an account id of type `demat`**,
/// not a broker's name. Until one of these exists the buy sheet has nothing to
/// post, which is why the screen leads with a route to `/accounts`.
final dematAccountsProvider = Provider<List<Account>>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
  return accounts
      .where((a) => a.type == AccountType.demat && !a.archived)
      .toList();
});

/// False while the accounts list is still loading, so the no-demat card only
/// appears once we actually know there is none.
final hasDematAccountProvider = Provider<bool>(
  (ref) => ref.watch(dematAccountsProvider).isNotEmpty,
);

/// Everything a write to `/stocks/*` can move: the book itself, and the demat
/// account whose cash the server adjusts alongside it.
void invalidateStocks(WidgetRef ref) {
  ref
    ..invalidate(stockPortfolioProvider)
    ..invalidate(stockSalesProvider)
    ..invalidate(stockSplitsProvider)
    ..invalidate(accountsProvider);
}

// ─────────────────────────────────────────────────────────────────────────────
// Capital-gains arithmetic
//
// Indian listed equity turns long-term once it has been held for more than
// twelve months — the day after the twelve-month anniversary, which is exactly
// how the web client draws the line. Both are pure functions of two calendar
// days so the sell sheet can preview a sale without asking the server.
// ─────────────────────────────────────────────────────────────────────────────

const int _nearlyLongTermDays = 45;

DateTime _midnight(DateTime date) => DateTime(date.year, date.month, date.day);

/// The first day a lot bought on [buyDate] counts as long-term.
DateTime longTermFrom(DateTime buyDate) {
  final anchor = _midnight(buyDate);
  return DateTime(
    anchor.year,
    anchor.month + 12,
    anchor.day,
  ).add(const Duration(days: 1));
}

bool isLongTermOn(DateTime buyDate, DateTime sellDate) =>
    !_midnight(sellDate).isBefore(longTermFrom(buyDate));

/// Whole days left before a lot bought on [buyDate] turns long-term. 0 once it
/// already has.
int daysToLongTerm(DateTime buyDate, DateTime sellDate) {
  final remaining = longTermFrom(
    buyDate,
  ).difference(_midnight(sellDate)).inMilliseconds;
  if (remaining <= 0) return 0;
  return (remaining / Duration.millisecondsPerDay).ceil();
}

/// One lot a sale eats into.
@immutable
class SellAllocation {
  const SellAllocation({
    required this.lotId,
    required this.qty,
    required this.costBasis,
    required this.buyDate,
    required this.longTerm,
    required this.daysToLongTerm,
  });

  final String lotId;
  final num qty;
  final num costBasis;
  final DateTime? buyDate;
  final bool longTerm;
  final int daysToLongTerm;
}

/// What a sale would realise, before it is recorded.
@immutable
class SellPreview {
  const SellPreview({
    required this.allocations,
    required this.proceeds,
    required this.costBasis,
    required this.realized,
    required this.realizedShortTerm,
    required this.realizedLongTerm,
    required this.shortfall,
    this.nearlyLongTermDays,
  });

  final List<SellAllocation> allocations;
  final num proceeds;
  final num costBasis;
  final num realized;
  final num realizedShortTerm;
  final num realizedLongTerm;

  /// Shares the open lots could not cover — a sale larger than the holding.
  final num shortfall;

  /// Set when part of the gain is within [_nearlyLongTermDays] of turning
  /// long-term, so the sheet can say waiting would be cheaper.
  final int? nearlyLongTermDays;

  bool get isProfit => realized >= 0;
  bool get isSplitTerm => realizedLongTerm != 0 && realizedShortTerm != 0;
}

/// FIFO, the way brokers report it: the oldest open lot goes first, and each
/// slice is tagged long- or short-term by its own purchase date.
///
/// Charges are not part of this: `POST /stocks/sell` declares no `charges` or
/// `brokerage` key and would strip one, so the app never collects a figure it
/// could not send. Charges already booked against a lot on the web do count,
/// through [StockLot.costBasisFor].
SellPreview computeSellPreview({
  required List<StockLot> lots,
  required num qty,
  required num price,
  required DateTime sellDate,
}) {
  final open = lots.where((lot) => lot.qty > 0).toList()
    ..sort((a, b) {
      final left = a.buyDate, right = b.buyDate;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });

  final allocations = <SellAllocation>[];
  var outstanding = qty;

  for (final lot in open) {
    if (outstanding <= 0) break;
    final take = outstanding < lot.qty ? outstanding : lot.qty;
    final buyDate = lot.buyDate;
    allocations.add(
      SellAllocation(
        lotId: lot.id,
        qty: take,
        costBasis: _round(lot.costBasisFor(take)),
        buyDate: buyDate,
        longTerm: buyDate == null
            ? (lot.longTermFromServer ?? false)
            : isLongTermOn(buyDate, sellDate),
        daysToLongTerm: buyDate == null
            ? (lot.daysToLongTermFromServer?.ceil() ?? 0)
            : daysToLongTerm(buyDate, sellDate),
      ),
    );
    outstanding -= take;
  }

  final soldQty = allocations.fold<num>(0, (sum, a) => sum + a.qty);
  final costBasis = _round(allocations.fold<num>(0, (sum, a) => sum + a.costBasis));

  var shortTerm = 0.0;
  var longTerm = 0.0;
  for (final allocation in allocations) {
    final gain = allocation.qty * price - allocation.costBasis;
    if (allocation.longTerm) {
      longTerm += gain;
    } else {
      shortTerm += gain;
    }
  }

  final nearly =
      (allocations
            .where(
              (a) =>
                  !a.longTerm &&
                  a.daysToLongTerm > 0 &&
                  a.daysToLongTerm <= _nearlyLongTermDays,
            )
            .map((a) => a.daysToLongTerm)
            .toList()
        ..sort());

  final realizedShort = _round(shortTerm);
  final realizedLong = _round(longTerm);

  return SellPreview(
    allocations: allocations,
    proceeds: _round(soldQty * price),
    costBasis: costBasis,
    realized: _round(realizedShort + realizedLong),
    realizedShortTerm: realizedShort,
    realizedLongTerm: realizedLong,
    shortfall: outstanding < 1e-9 ? 0 : _round(outstanding),
    nearlyLongTermDays: nearly.isEmpty ? null : nearly.first,
  );
}

/// Two decimals, the precision the API books money at.
num _round(num value) {
  final rounded = (value * 100).round() / 100;
  return rounded % 1 == 0 ? rounded.toInt() : rounded;
}
