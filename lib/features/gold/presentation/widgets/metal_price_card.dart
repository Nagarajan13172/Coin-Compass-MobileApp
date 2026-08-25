import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/segmented_period_selector.dart';
import '../../../dashboard/presentation/widgets/metals_card.dart'
    show metalGold, metalSilver;
import '../../domain/metal_price.dart';
import '../gold_providers.dart';

/// One metal's board: purity selector, headline per-gram figure, today's move
/// and where the number came from.
///
/// The purity lives in [metalPurityProvider] rather than in the widget so the
/// chart and the calculator below quote the same karat the user is looking at.
class MetalPriceCard extends ConsumerWidget {
  const MetalPriceCard({super.key, required this.price});

  final MetalPrice price;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final city = ref.watch(metalCityProvider);
    final purity = ref.watch(metalPurityProvider(price.metal));
    final rates = MetalRates.of(price, city);
    final accent = price.isGold ? metalGold : metalSilver;
    final stale = price.date != null && price.date != istToday();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.coins, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                price.isGold ? 'Gold' : 'Silver',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: price.isGold
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: _Badge(
                          label:
                              '${city.label} · ${rates.approx ? 'approx' : 'GRT'}',
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              MetalChangeChip(changePct: price.changePct),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedPeriodSelector<MetalPurity>(
            options: [
              for (final option in MetalPurity.values)
                SegmentOption(option, option.label),
            ],
            value: purity,
            onChanged: (value) =>
                ref.read(metalPurityProvider(price.metal).notifier).state =
                    value,
          ),
          const SizedBox(height: 14),
          Text(
            purity.gramLabel,
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    rates.forPurity(purity),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: _TodayMove(change: price.change),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _detail(rates, city),
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: c.border),
          const SizedBox(height: 10),
          // Both halves are flexible so a long "Last close · …" can never push
          // the row over the edge; the date gets the larger share because it is
          // the half that matters when the two compete.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Spot ${Money.compact(price.pricePerOunce)}/oz',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ),
              Flexible(
                flex: 2,
                child: Text(
                  _asOf(stale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// `GRT · grtjewels.com · spot 22K ₹13,046.88`, or for a derived city
  /// `≈ spot 22K ₹13,046.88 · +15.2% (duty, GST, margin)`.
  ///
  /// Silver has no retail board: the feed publishes the same per-gram figure
  /// under all three purities, and saying so is better than three identical
  /// numbers with no explanation.
  String _detail(MetalRates rates, MetalCity city) {
    if (!price.isGold) {
      final source = rates.source.isEmpty ? 'Spot per gram' : rates.source;
      final flat =
          price.pricePerGram24k == price.pricePerGram22k &&
          price.pricePerGram22k == price.pricePerGram18k;
      return flat
          ? '$source · 999 fineness, one rate for every purity'
          : source;
    }
    final spot = Money.format(price.pricePerGram22k);
    return rates.approx
        ? '≈ spot 22K $spot · +${city.premiumPct}% (duty, GST, margin)'
        : '${rates.source} · spot 22K $spot';
  }

  /// `As of 24 Aug 2026` while the board is today's, `Last close · …` once the
  /// day has rolled over in India and the scrape has not run yet.
  String _asOf(bool stale) {
    final day = DateX.parse(price.date) ?? price.fetchedAt;
    if (day == null) return '';
    final label = '${DateX.shortDay(day)} ${day.year}';
    return stale ? 'Last close · $label' : 'As of $label';
  }
}

/// `↗ +0.54%` in income/expense colour — flat counts as up, as on the web.
class MetalChangeChip extends StatelessWidget {
  const MetalChangeChip({super.key, required this.changePct});

  final num changePct;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final down = changePct < 0;
    final color = down ? c.expense : c.income;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          down ? LucideIcons.trendingDown : LucideIcons.trendingUp,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '${down ? Money.minus : '+'}${changePct.abs().toStringAsFixed(2)}%',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The rupee move against yesterday's close, beside the headline.
class _TodayMove extends StatelessWidget {
  const _TodayMove({required this.change});

  final num change;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (change == 0) {
      return Text(
        'unchanged',
        style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
      );
    }
    return MoneyText(
      change,
      signed: true,
      tone: MoneyTone.auto,
      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
    );
  }
}

/// `Chennai · GRT` — the secondary pill beside the metal name.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: c.secondaryForeground),
      ),
    );
  }
}
