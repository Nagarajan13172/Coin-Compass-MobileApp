import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../data/stocks_repository.dart';
import '../domain/stock.dart';
import 'stocks_providers.dart';

/// Realised gains — `GET /stocks/sales`, newest first.
///
/// Each sale carries its own long/short-term split, because one FIFO sale can
/// straddle the twelve-month line: part of it long-term, the rest short. The
/// same list backs the screen's "Sold" tab and this sheet, which the Realised
/// P&L tile opens.
class StockSalesSheet extends StatelessWidget {
  const StockSalesSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const StockSalesSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

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
                  const Expanded(
                    child: Text(
                      'Realised gains',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
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
            Divider(height: 1, color: c.border),
            const Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: StockSalesList(showTermSummary: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sold book, in whatever container the caller supplies.
class StockSalesList extends ConsumerStatefulWidget {
  const StockSalesList({super.key, this.showTermSummary = false});

  /// Renders the short/long-term totals above the rows. The screen's summary
  /// already carries them, so the tab leaves it off.
  final bool showTermSummary;

  @override
  ConsumerState<StockSalesList> createState() => _StockSalesListState();
}

class _StockSalesListState extends ConsumerState<StockSalesList> {
  /// Sales with a delete in flight.
  final Set<String> _busyIds = {};

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(stockSalesProvider);

    return switch (sales) {
      AsyncData(:final value) when value.isEmpty => const _EmptySales(),
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTermSummary) ...[
            _TermSummary(sales: value),
            const SizedBox(height: 14),
          ],
          for (final sale in value)
            _SaleRow(
              sale: sale,
              busy: _busyIds.contains(sale.id),
              onDelete: () => _delete(sale),
            ),
        ],
      ),
      AsyncError(:final error) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ErrorRetry(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(stockSalesProvider),
        ),
      ),
      _ => const Column(
        children: [
          LoadingCard(lines: 2),
          SizedBox(height: 12),
          LoadingCard(lines: 2),
        ],
      ),
    };
  }

  /// `DELETE /stocks/sales/:id` reverses the sale: the lots it consumed come
  /// back and the realized gain is unbooked.
  Future<void> _delete(StockSale sale) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete this sale?',
      message:
          'The shares go back into ${sale.displayTicker} and the realised gain '
          'is unbooked.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyIds.add(sale.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Deliberately synchronous (6.4): the row's disappearance is
      // predictable, but removing a sale re-derives the whole position's
      // realised short/long-term P&L server-side. Row-only optimism would
      // leave every number around the gap wrong, which is worse than a
      // spinner. See lib/core/state/optimistic.dart.
      await ref.read(stocksRepositoryProvider).deleteSale(sale.id);
      invalidateStocks(ref);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Sale deleted')));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ApiException.from(error).message)),
        );
    } finally {
      if (mounted) setState(() => _busyIds.remove(sale.id));
    }
  }
}

/// Long- and short-term totals across every sale on record.
class _TermSummary extends StatelessWidget {
  const _TermSummary({required this.sales});

  final List<StockSale> sales;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    var long = 0.0;
    var short = 0.0;
    for (final sale in sales) {
      long += sale.realizedLongTerm;
      short += sale.realizedShortTerm;
      // A sale tagged wholesale by `term` carries no split of its own.
      if (sale.realizedLongTerm == 0 && sale.realizedShortTerm == 0) {
        if (sale.isLongTerm) {
          long += sale.realized;
        } else {
          short += sale.realized;
        }
      }
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _TermStat(
              label: 'Long-term',
              amount: long,
              icon: LucideIcons.clock,
            ),
          ),
          Container(width: 1, height: 34, color: c.border),
          Expanded(
            child: _TermStat(
              label: 'Short-term',
              amount: short,
              icon: LucideIcons.history,
            ),
          ),
        ],
      ),
    );
  }
}

class _TermStat extends StatelessWidget {
  const _TermStat({
    required this.label,
    required this.amount,
    required this.icon,
  });

  final String label;
  final num amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: c.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
                ),
                MoneyText(
                  amount,
                  tone: MoneyTone.auto,
                  signed: true,
                  compactAbove: Money.crore,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({
    required this.sale,
    required this.busy,
    required this.onDelete,
  });

  final StockSale sale;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sellDate = sale.sellDate;
    final qty = sale.qty % 1 == 0
        ? sale.qty.toInt().toString()
        : sale.qty.toString();

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.displayTicker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$qty at ${Money.format(sale.sellPrice)}'
                  '${sellDate == null ? '' : ' on ${DateX.shortDay(sellDate)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: MoneyText(
                    sale.realized,
                    tone: MoneyTone.auto,
                    signed: true,
                    compactAbove: Money.crore,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                _TermCaption(sale: sale),
              ],
            ),
          ),
          IconButton(
            onPressed: busy ? null : onDelete,
            tooltip: tr(context, 'Delete this sale'),
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

/// `₹1,240 long-term · ₹310 short-term`, showing only the halves that exist.
class _TermCaption extends StatelessWidget {
  const _TermCaption({required this.sale});

  final StockSale sale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontSize: 11, color: c.mutedForeground);
    final parts = <String>[
      // Compact on purpose: this caption sits under the headline figure in a
      // right-hand column, where a full nine-digit pair would push the row off
      // a 360dp screen.
      if (sale.realizedLongTerm != 0)
        '${Money.compact(sale.realizedLongTerm)} long-term',
      if (sale.realizedShortTerm != 0)
        '${Money.compact(sale.realizedShortTerm)} short-term',
    ];

    if (parts.isEmpty) {
      // No split on the payload — fall back to the sale's own term tag.
      return Text(
        sale.isLongTerm
            ? 'Long-term'
            : (sale.isShortTerm ? 'Short-term' : 'Realised'),
        style: style,
      );
    }

    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: style,
    );
  }
}

class _EmptySales extends StatelessWidget {
  const _EmptySales();

  @override
  Widget build(BuildContext context) {
    return const DashedBox(
      child: EmptyState(
        icon: LucideIcons.chartNoAxesCombined,
        title: 'Nothing sold yet',
        message:
            'Once you sell, the profit or loss shows up here and in your '
            'reports.',
        compact: true,
      ),
    );
  }
}
