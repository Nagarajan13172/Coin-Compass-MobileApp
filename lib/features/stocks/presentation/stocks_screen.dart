import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../../accounts/data/accounts_repository.dart';
import '../data/stocks_repository.dart';
import '../domain/stock.dart';
import 'stock_buy_sheet.dart';
import 'stock_sales_sheet.dart';
import 'stock_splits_sheet.dart';
import 'stocks_providers.dart';
import 'widgets/position_tile.dart';

/// `/stocks` — the equity book: what it is worth now, what it cost, what it
/// has already made, and every lot behind those numbers.
///
/// Two things about this screen are not cosmetic:
///  * buying and selling need a **demat account** (`demat` is an account id of
///    type `demat`), so an empty wallet is led to `/accounts` before it is
///    offered a buy form it could not submit;
///  * pull-to-refresh only re-reads `/stocks/portfolio`. Re-pricing is
///    `POST /stocks/refresh`, which hits a live quote provider, so it stays on
///    an explicit button.
class StocksScreen extends ConsumerStatefulWidget {
  const StocksScreen({super.key});

  @override
  ConsumerState<StocksScreen> createState() => _StocksScreenState();
}

class _StocksScreenState extends ConsumerState<StocksScreen> {
  bool _repricing = false;

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(stockPortfolioProvider);
    final tab = ref.watch(stocksTabProvider);
    // Only claim there is no demat account once the accounts list has landed.
    final accountsLoaded = ref.watch(accountsProvider).hasValue;
    final hasDemat = ref.watch(hasDematAccountProvider);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'Stocks',
            subtitle:
                'Your demat holdings, priced from the market and counted in '
                'your net worth.',
            actions: [
              ScreenHeaderAction(
                label: 'Add stock',
                icon: LucideIcons.plus,
                onPressed: () => StockBuySheet.show(context),
              ),
              ScreenHeaderAction(
                label: _repricing ? 'Refreshing…' : 'Refresh',
                icon: LucideIcons.refreshCw,
                primary: false,
                onPressed: _repricing ? null : _reprice,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const StockSplitsBanner(),
                if (accountsLoaded && !hasDemat) const _NoDematCard(),
              ],
            ),
          ),
          switch (portfolio) {
            AsyncData(:final value) => _Book(
              portfolio: value,
              tab: tab,
              hasDemat: hasDemat,
              onReprice: _repricing ? null : _reprice,
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(stockPortfolioProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 3),
                  SizedBox(height: 12),
                  LoadingCard(lines: 2),
                ],
              ),
            ),
          },
        ],
      ),
    );
  }

  /// Re-reads the book. Deliberately **not** a re-price: `/stocks/refresh` is a
  /// mutating action against a live quote feed and belongs on a button.
  Future<void> _refresh() async {
    ref
      ..invalidate(stockPortfolioProvider)
      ..invalidate(stockSalesProvider)
      ..invalidate(stockSplitsProvider);
    try {
      await ref.read(stockPortfolioProvider.future);
    } catch (_) {
      // The error state is rendered from the provider; the spinner just stops.
    }
  }

  /// `POST /stocks/refresh` — re-quotes every position from the market feed.
  Future<void> _reprice() async {
    setState(() => _repricing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(stocksRepositoryProvider).refresh();
      ref.invalidate(stockPortfolioProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Prices updated')));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ApiException.from(error).message)),
        );
    } finally {
      if (mounted) setState(() => _repricing = false);
    }
  }
}

/// Everything below the header once the portfolio has arrived.
class _Book extends StatelessWidget {
  const _Book({
    required this.portfolio,
    required this.tab,
    required this.hasDemat,
    required this.onReprice,
  });

  final StockPortfolio portfolio;
  final StocksTab tab;
  final bool hasDemat;
  final VoidCallback? onReprice;

  @override
  Widget build(BuildContext context) {
    final positions = portfolio.positions;
    final totals = portfolio.totals;
    // Zeros across the board say nothing; the empty state carries the screen
    // until there is a book to summarise.
    final hasBook = positions.isNotEmpty || totals.realizedPL != 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasBook)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _SummaryCard(totals: totals),
          ),
        if (hasBook && portfolio.anyStale)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: _StaleNote(pricedAt: portfolio.pricedAt, onReprice: onReprice),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _TabBar(tab: tab),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: switch (tab) {
            StocksTab.holdings => _Holdings(
              positions: positions,
              portfolioValue: totals.marketValue,
              hasDemat: hasDemat,
            ),
            StocksTab.sold => const StockSalesList(),
          },
        ),
      ],
    );
  }
}

class _TabBar extends ConsumerWidget {
  const _TabBar({required this.tab});

  final StocksTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedPeriodSelector<StocksTab>(
      value: tab,
      options: const [
        SegmentOption(StocksTab.holdings, 'Holdings'),
        SegmentOption(StocksTab.sold, 'Sold'),
      ],
      onChanged: (value) =>
          ref.read(stocksTabProvider.notifier).state = value,
    );
  }
}

class _Holdings extends StatelessWidget {
  const _Holdings({
    required this.positions,
    required this.portfolioValue,
    required this.hasDemat,
  });

  final List<StockPosition> positions;
  final num portfolioValue;
  final bool hasDemat;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      return DashedBox(
        child: EmptyState(
          icon: LucideIcons.chartNoAxesCombined,
          title: 'No stocks yet',
          message: hasDemat
              ? 'Add a purchase and its live price will feed straight into '
                    'your net worth.'
              : 'Purchases are filed against a demat account. Create one '
                    'first, then add a purchase and its live price feeds '
                    'straight into your net worth.',
          actionLabel: hasDemat ? 'Add stock' : 'Go to Accounts',
          onAction: hasDemat
              ? () => StockBuySheet.show(context)
              : () => context.go('/accounts'),
        ),
      );
    }

    final rows = [...positions]
      ..sort((a, b) => b.marketValue.compareTo(a.marketValue));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final position in rows)
          PositionTile(position: position, portfolioValue: portfolioValue),
      ],
    );
  }
}

/// Market value, cost, unrealized and realized — the four numbers the web app
/// leads with, folded into one card that fits a 360dp phone.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals});

  final StockTotals totals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final up = totals.unrealized >= 0;
    final accent = up ? c.income : c.expense;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Portfolio value',
                  style: TextStyle(fontSize: 13, color: c.mutedForeground),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                  size: 15,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // The exact figure, the way the web app states it. FittedBox is what
          // keeps a ten-figure balance on one line; compacting this to "₹2Cr"
          // would hide the very number the card exists to show. Dense rows,
          // where a label has to share the width, keep compactAbove.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              totals.marketValue,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Invested',
                  amount: totals.investedCost,
                ),
              ),
              Container(width: 1, height: 34, color: c.border),
              Expanded(
                child: _MiniStat(
                  label: 'Today',
                  amount: totals.dayChange,
                  tone: MoneyTone.auto,
                  signed: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Unrealised P&L',
                  amount: totals.unrealized,
                  tone: MoneyTone.auto,
                  signed: true,
                  caption: Money.percent(
                    totals.unrealizedPct,
                    alreadyScaled: true,
                  ),
                ),
              ),
              Container(width: 1, height: 34, color: c.border),
              Expanded(
                child: _MiniStat(
                  label: 'Realised P&L',
                  amount: totals.realizedPL,
                  tone: MoneyTone.auto,
                  signed: true,
                  caption:
                      '${Money.compact(totals.realizedLongTerm)} long · '
                      '${Money.compact(totals.realizedShortTerm)} short',
                  onTap: () => StockSalesSheet.show(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.amount,
    this.tone = MoneyTone.neutral,
    this.signed = false,
    this.caption,
    this.onTap,
  });

  final String label;
  final num amount;
  final MoneyTone tone;
  final bool signed;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 3),
                Icon(
                  LucideIcons.chevronRight,
                  size: 13,
                  color: c.mutedForeground,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          MoneyText(
            amount,
            tone: tone,
            signed: signed,
            compactAbove: Money.crore,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c.mutedForeground),
            ),
        ],
      ),
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: body,
      ),
    );
  }
}

/// Says how old the prices are, and offers the one action that fixes it.
class _StaleNote extends StatelessWidget {
  const _StaleNote({required this.pricedAt, required this.onReprice});

  final DateTime? pricedAt;
  final VoidCallback? onReprice;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final when = pricedAt == null
        ? 'some time ago'
        : DateX.relative(pricedAt!);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 15, color: c.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Prices as of $when. The market may have moved since.',
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
          ),
          TextButton(
            onPressed: onReprice,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Refresh', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

/// The first thing an untouched wallet sees: buying needs a demat account, and
/// there is exactly one place to make one.
class _NoDematCard extends StatelessWidget {
  const _NoDematCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DashedBox(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "You don't have a demat account yet",
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'A purchase is filed against a demat account — it is what '
                'holds the cash sitting with your broker. Add one under '
                'Accounts to start recording trades.',
                style: TextStyle(fontSize: 13, color: c.mutedForeground),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/accounts'),
                icon: const Icon(LucideIcons.arrowRight, size: 17),
                label: const Text('Go to Accounts'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
