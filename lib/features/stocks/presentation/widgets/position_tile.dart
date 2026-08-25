import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/confirm_sheet.dart';
import '../../../../core/widgets/money_text.dart';
import '../../data/stocks_repository.dart';
import '../../domain/stock.dart';
import '../stock_buy_sheet.dart';
import '../stock_sell_sheet.dart';
import '../stocks_providers.dart';

/// One open position on the Stocks screen.
///
/// Everything that fits on a phone row is here — value, unrealized P&L, last
/// traded price, allocation — and the lot-by-lot detail lives one tap deeper in
/// [PositionDetailSheet], which is also where a lot can be sold or removed.
class PositionTile extends StatelessWidget {
  const PositionTile({
    super.key,
    required this.position,
    required this.portfolioValue,
  });

  final StockPosition position;

  /// Total market value of the book, used to work out this row's share when
  /// the API does not send `allocationPct`.
  final num portfolioValue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final exchange = position.exchangeLabel;
    final allocation = position.allocationOf(portfolioValue);
    final ltcgDays = _daysToNextLongTerm(position);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      onTap: () => PositionDetailSheet.show(context, position: position),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            position.displayTicker,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (exchange != null) ...[
                          const SizedBox(width: 6),
                          _Chip(label: exchange),
                        ],
                        if (position.stale) ...[
                          const SizedBox(width: 6),
                          _Chip(label: 'Stale', outlined: true),
                        ],
                      ],
                    ),
                    if (position.name != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        position.name!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    // One Text, not a Row of them: a dense row has to be able
                    // to ellipsise, and Money.format keeps the grouping.
                    Text(
                      '${_plain(position.qty)} shares · avg '
                      '${Money.format(position.avgCost)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // The figures column is capped and scales its own type down: a
              // nine-figure holding must not eat the name beside it.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 148),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Fit(
                      child: MoneyText(
                        position.marketValue,
                        compactAbove: Money.crore,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    _Fit(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoneyText(
                            position.unrealized,
                            tone: MoneyTone.auto,
                            signed: true,
                            compactAbove: Money.crore,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            ' (${Money.percent(position.unrealizedPct, alreadyScaled: true)})',
                            style: TextStyle(
                              fontSize: 12,
                              color: position.isUp ? c.income : c.expense,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    _Fit(
                      child: Text(
                        'LTP ${Money.format(position.price)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: c.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${Money.percent(allocation, alreadyScaled: true)} of portfolio',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: c.mutedForeground,
                      ),
                    ),
                    // Only the totals carry a day change today; the row shows
                    // one when the payload actually has it.
                    if (position.dayChange != 0) _DayChangeChip(position),
                    if (ltcgDays != null)
                      _Chip(label: 'Long-term in ${ltcgDays}d', outlined: true),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () =>
                    StockSellSheet.show(context, position: position),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Sell'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Days until the *next* short-term lot turns long-term — the soonest one, so
  /// the badge answers "how long until this stops costing me the higher rate".
  static int? _daysToNextLongTerm(StockPosition position) {
    final now = DateTime.now();
    final days = <int>[];
    for (final lot in position.lots) {
      if (lot.qty <= 0) continue;
      final buyDate = lot.buyDate;
      if (buyDate == null) {
        final fromServer = lot.daysToLongTermFromServer;
        if (lot.longTermFromServer == false && fromServer != null) {
          days.add(fromServer.ceil());
        }
        continue;
      }
      if (isLongTermOn(buyDate, now)) continue;
      days.add(daysToLongTerm(buyDate, now));
    }
    if (days.isEmpty) return null;
    days.sort();
    return days.first;
  }

  static String _plain(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

/// The lots behind a position, plus the two things you can do with them.
class PositionDetailSheet extends ConsumerStatefulWidget {
  const PositionDetailSheet({super.key, required this.position});

  final StockPosition position;

  static Future<void> show(
    BuildContext context, {
    required StockPosition position,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PositionDetailSheet(position: position),
    );
  }

  @override
  ConsumerState<PositionDetailSheet> createState() =>
      _PositionDetailSheetState();
}

class _PositionDetailSheetState extends ConsumerState<PositionDetailSheet> {
  /// Lots with a delete in flight.
  final Set<String> _busyLots = {};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final position = widget.position;
    final lots = position.lots.where((lot) => lot.qty > 0).toList()
      ..sort((a, b) {
        final left = a.buyDate, right = b.buyDate;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return left.compareTo(right);
      });

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          position.displayTicker,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (position.name != null)
                          Text(
                            position.name!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      LucideIcons.x,
                      size: 20,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                children: [
                  _StatGrid(position: position),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Purchase lots',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.mutedForeground,
                          ),
                        ),
                      ),
                      Text(
                        '${lots.length} lot(s)',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (lots.isEmpty)
                    Text(
                      'This position has no open lots on record.',
                      style: TextStyle(fontSize: 13, color: c.mutedForeground),
                    )
                  else
                    for (final lot in lots)
                      _LotRow(
                        lot: lot,
                        busy: _busyLots.contains(lot.id),
                        onDelete: () => _deleteLot(lot),
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Buy',
                      variant: AppButtonVariant.outlined,
                      icon: LucideIcons.plus,
                      onPressed: () => _buyMore(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      label: 'Sell',
                      icon: LucideIcons.trendingDown,
                      onPressed: () => _sell(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _buyMore(BuildContext context) async {
    final navigator = Navigator.of(context);
    final position = widget.position;
    final saved = await StockBuySheet.show(
      context,
      preset: StockQuote(
        symbol: position.symbol,
        ticker: position.ticker,
        shortName: position.name,
        exchange: position.exchangeLabel,
      ),
    );
    if (saved == true) navigator.pop();
  }

  Future<void> _sell(BuildContext context) async {
    final navigator = Navigator.of(context);
    final saved = await StockSellSheet.show(context, position: widget.position);
    if (saved == true) navigator.pop();
  }

  /// `DELETE /stocks/lots/:id` — used to undo a mis-keyed purchase. It rewrites
  /// the position's cost basis, so it asks first.
  Future<void> _deleteLot(StockLot lot) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete this purchase?',
      message:
          'The lot is removed and ${widget.position.displayTicker}\'s average '
          'cost is recalculated without it.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyLots.add(lot.id));
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // Deliberately synchronous (6.4): deleting a lot re-derives the
      // position's quantity, average cost and realised P&L through server-side
      // FIFO matching. Nothing here is predictable but the row itself.
      // See lib/core/state/optimistic.dart.
      await ref.read(stocksRepositoryProvider).deleteLot(lot.id);
      invalidateStocks(ref);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Purchase deleted')));
      // The position this sheet was handed is now stale — close it rather than
      // keep showing a lot list the server no longer agrees with.
      if (mounted) navigator.pop();
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ApiException.from(error).message)),
        );
      if (mounted) setState(() => _busyLots.remove(lot.id));
    }
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.position});

  final StockPosition position;

  @override
  Widget build(BuildContext context) {
    final qty = position.qty % 1 == 0
        ? position.qty.toInt().toString()
        : position.qty.toString();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(label: 'Quantity', valueText: qty),
            ),
            Expanded(
              child: _Stat(label: 'Avg cost', amount: position.avgCost),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Stat(label: 'Last price', amount: position.price),
            ),
            Expanded(
              child: _Stat(label: 'Invested', amount: position.investedCost),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Stat(label: 'Market value', amount: position.marketValue),
            ),
            Expanded(
              child: _Stat(
                label: 'Unrealised',
                amount: position.unrealized,
                tone: MoneyTone.auto,
                signed: true,
                caption: Money.percent(
                  position.unrealizedPct,
                  alreadyScaled: true,
                ),
              ),
            ),
          ],
        ),
        if (position.pricedAt != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Priced ${DateX.relative(position.pricedAt!)}'
              '${position.stale ? ' · not a live quote' : ''}',
              style: TextStyle(
                fontSize: 11.5,
                color: context.colors.mutedForeground,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    this.amount,
    this.valueText,
    this.tone = MoneyTone.neutral,
    this.signed = false,
    this.caption,
  });

  final String label;
  final num? amount;
  final String? valueText;
  final MoneyTone tone;
  final bool signed;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
        const SizedBox(height: 2),
        if (valueText != null)
          Text(
            valueText!,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          )
        else
          _Fit(
            alignment: Alignment.centerLeft,
            child: MoneyText(
              amount ?? 0,
              tone: tone,
              signed: signed,
              compactAbove: Money.crore,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        if (caption != null)
          Text(
            caption!,
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
      ],
    );
  }
}

class _LotRow extends StatelessWidget {
  const _LotRow({
    required this.lot,
    required this.busy,
    required this.onDelete,
  });

  final StockLot lot;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final buyDate = lot.buyDate;
    final longTerm = buyDate == null
        ? (lot.longTermFromServer ?? false)
        : isLongTermOn(buyDate, DateTime.now());
    final days = buyDate == null
        ? lot.daysToLongTermFromServer?.ceil()
        : daysToLongTerm(buyDate, DateTime.now());
    final qty = lot.qty % 1 == 0
        ? lot.qty.toInt().toString()
        : lot.qty.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$qty at ${Money.format(lot.buyPrice)}'
                  '${buyDate == null ? '' : ' on ${DateX.shortDay(buyDate)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
                if (lot.note != null)
                  Text(
                    lot.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: longTerm
                ? 'Long-term'
                : (days == null ? 'Short-term' : '${days}d to LTCG'),
            outlined: !longTerm,
          ),
          IconButton(
            onPressed: busy ? null : onDelete,
            tooltip: 'Delete this purchase',
            visualDensity: VisualDensity.compact,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(LucideIcons.trash2, size: 17, color: c.destructive),
          ),
        ],
      ),
    );
  }
}

class _DayChangeChip extends StatelessWidget {
  const _DayChangeChip(this.position);

  final StockPosition position;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final up = position.dayChange >= 0;
    final accent = up ? c.income : c.expense;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
            size: 12,
            color: accent,
          ),
          const SizedBox(width: 4),
          Text(
            '${Money.compact(position.dayChange)}'
            '${position.dayChangePct == 0 ? '' : ' ${Money.percent(position.dayChangePct, alreadyScaled: true)}'}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.outlined = false});

  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: outlined ? null : c.secondary,
        border: outlined ? Border.all(color: c.border) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: c.mutedForeground,
        ),
      ),
    );
  }
}

/// Shrinks a figure to fit its column instead of overflowing it. Under the
/// bundled Inter nothing scales; it only bites on the widest possible payload
/// (a nine-figure holding) or a very large system font.
class _Fit extends StatelessWidget {
  const _Fit({required this.child, this.alignment = Alignment.centerRight});

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);
}
