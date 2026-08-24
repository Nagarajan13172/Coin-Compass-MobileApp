import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../gold/data/metals_repository.dart';
import '../../../gold/domain/metal_price.dart';

/// Gold and silver are product identities rather than theme tokens — the
/// palette has no slot for them. Built from HSL so they read the same in light
/// and dark without pinning a hex literal.
final Color metalGold = const HSLColor.fromAHSL(1, 43, 0.90, 0.47).toColor();
final Color metalSilver = const HSLColor.fromAHSL(1, 210, 0.10, 0.62).toColor();

/// Today's retail gold (22K) and silver (999) prices from `/metals/latest`.
///
/// The whole card disappears when the deployment has no metals provider wired
/// up (`configured: false`) — an empty gold card would be noise.
class MetalsCard extends ConsumerWidget {
  const MetalsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metals = ref.watch(metalsLatestProvider);

    return metals.when(
      loading: () => const _Slot(child: LoadingCard(lines: 4)),
      error: (error, _) => _Slot(
        child: ErrorRetry(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(metalsLatestProvider),
        ),
      ),
      data: (data) {
        if (!data.configured || (data.gold == null && data.silver == null)) {
          return const SizedBox.shrink();
        }
        return _Slot(child: _Card(metals: data));
      },
    );
  }
}

/// The card owns its bottom gap so that hiding it leaves no hole in the page.
class _Slot extends StatelessWidget {
  const _Slot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: child);
}

class _Card extends StatelessWidget {
  const _Card({required this.metals});

  final MetalsLatest metals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gold = metals.gold;
    final silver = metals.silver;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            leading: Icon(LucideIcons.coins, size: 18, color: metalGold),
            title: 'Gold & Silver',
            actionLabel: 'View',
            onAction: () => context.go('/gold'),
          ),
          if (gold != null) ...[
            const SizedBox(height: 14),
            Text(
              'Gold · 22K / gram · Chennai',
              style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: MoneyText(
                    gold.headlinePrice,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _ChangeChip(pct: gold.changePct),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    gold.retailSource ?? gold.source ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
                ),
                Text(
                  _asOf(gold),
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(height: 40, child: LineChart(_sparkline(gold, metalGold))),
          ],
          if (gold != null && silver != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: c.border),
            const SizedBox(height: 12),
          ],
          if (silver != null)
            Row(
              children: [
                Icon(LucideIcons.circle, size: 10, color: metalSilver),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Silver · 999 / gram',
                    style: TextStyle(fontSize: 13, color: c.mutedForeground),
                  ),
                ),
                MoneyText(
                  silver.headlinePrice,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                _ChangeChip(pct: silver.changePct, fontSize: 12.5),
              ],
            ),
        ],
      ),
    );
  }

  /// `date` is a plain `yyyy-MM-dd`; fall back to the fetch stamp.
  String _asOf(MetalPrice price) {
    final day = DateX.parse(price.date) ?? price.fetchedAt;
    return day == null ? '' : 'as of ${DateX.shortDay(day)}';
  }

  /// There is no history endpoint on the frozen contract, so the trace runs
  /// from the previous close to today's price — flat on a quiet day, exactly
  /// what the web card shows.
  LineChartData _sparkline(MetalPrice price, Color color) {
    final now = price.headlinePrice.toDouble();
    final previous = price.prevClose > 0 ? price.prevClose.toDouble() : now;
    final low = previous < now ? previous : now;
    final high = previous > now ? previous : now;
    final pad = (high - low).abs() < 1
        ? (high.abs() * 0.02) + 1
        : (high - low) * 0.4;

    return LineChartData(
      minX: 0,
      maxX: 1,
      minY: low - pad,
      maxY: high + pad,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: [FlSpot(0, previous), FlSpot(1, now)],
          color: color,
          barWidth: 2,
          isCurved: true,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.22),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `↗ +0.00%` — green when flat or up, red when down, matching the web app.
class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.pct, this.fontSize = 13});

  final num pct;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final down = pct < 0;
    return Text(
      '${down ? '↘' : '↗'} ${down ? '−' : '+'}${pct.abs().toStringAsFixed(2)}%',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: down ? c.expense : c.income,
      ),
    );
  }
}
