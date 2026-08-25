import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/segmented_period_selector.dart';
import '../../../dashboard/presentation/widgets/metals_card.dart'
    show metalGold, metalSilver;
import '../../data/metals_repository.dart';
import '../gold_providers.dart';

/// `GET /metals/history?metal=…&days=…` as a filled line, with the metal and
/// the window switchable. The series is priced at the same purity and city the
/// cards above are showing.
class MetalHistoryChart extends ConsumerWidget {
  const MetalHistoryChart({super.key});

  static const List<int> _windows = [7, 30, 90, 365];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final metal = ref.watch(historyMetalProvider);
    final days = ref.watch(historyDaysProvider);
    final city = ref.watch(metalCityProvider);
    final purity = ref.watch(metalPurityProvider(metal));
    final key = (metal: metal, days: days);
    final history = ref.watch(metalsHistoryProvider(key));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Price history',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              SegmentedPeriodSelector<String>(
                options: const [
                  SegmentOption('gold', 'Gold'),
                  SegmentOption('silver', 'Silver'),
                ],
                value: metal,
                onChanged: (value) =>
                    ref.read(historyMetalProvider.notifier).state = value,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedPeriodSelector<int>(
              options: [
                for (final window in _windows)
                  SegmentOption(window, _windowLabel(window)),
              ],
              value: days,
              onChanged: (value) =>
                  ref.read(historyDaysProvider.notifier).state = value,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${purity.label} / g · ${metal == 'gold' ? city.label : '999 fineness'}',
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
          const SizedBox(height: 12),
          switch (history) {
            AsyncData(:final value) => _Body(
              points: metalHistorySeries(value, city: city, purity: purity),
              color: metal == 'gold' ? metalGold : metalSilver,
            ),
            // A minimum, not a fixed height: the retry card needs ~256dp at
            // 360dp and a hard 240 clipped the button off behind a RenderFlex
            // overflow. The floor keeps the card from collapsing when the
            // message is short.
            AsyncError(:final error) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 240),
              child: ErrorRetry(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(metalsHistoryProvider(key)),
              ),
            ),
            _ => const LoadingShimmer(
              width: double.infinity,
              height: 220,
              radius: 12,
            ),
          },
        ],
      ),
    );
  }

  static String _windowLabel(int days) => days == 365 ? '1Y' : '${days}D';
}

class _Body extends StatelessWidget {
  const _Body({required this.points, required this.color});

  final List<MetalHistoryPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // One point draws no trend — the series is genuinely still filling up.
    if (points.length < 2) {
      return const EmptyState(
        icon: LucideIcons.chartLine,
        title: 'History is still building.',
        message: 'A new data point is added each day — check back tomorrow.',
        compact: true,
      );
    }

    final first = points.first.value;
    final last = points.last.value;
    final move = first == 0 ? 0 : (last - first) / first * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 220, child: LineChart(_data(context))),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${points.length} days · ',
                style: TextStyle(color: c.mutedForeground),
              ),
              TextSpan(
                text:
                    '${move < 0 ? Money.minus : '+'}${move.abs().toStringAsFixed(2)}%',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: move < 0 ? c.expense : c.income,
                ),
              ),
              TextSpan(
                text: ' over the window',
                style: TextStyle(color: c.mutedForeground),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 12.5),
        ),
        if (points.any((point) => point.approx)) ...[
          const SizedBox(height: 4),
          Text(
            'Estimated from international spot plus the local premium.',
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
        ],
      ],
    );
  }

  LineChartData _data(BuildContext context) {
    final c = context.colors;
    final count = points.length;

    var low = points.first.value.toDouble();
    var high = low;
    for (final point in points) {
      low = math.min(low, point.value.toDouble());
      high = math.max(high, point.value.toDouble());
    }
    // A flat series would collapse to a zero-height plot; give it a band.
    final span = high - low;
    final pad = span < 1 ? math.max(high.abs() * 0.01, 1) : span * 0.08;
    final axis = _axis(low - pad, high + pad);
    final minY = axis.min;
    final maxY = axis.max;
    final step = axis.step;
    final labelEvery = math.max(1, (count / 4).ceil());

    return LineChartData(
      minX: 0,
      maxX: (count - 1).toDouble(),
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: step,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: c.border, strokeWidth: 1, dashArray: const [3, 4]),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 46,
            interval: step,
            getTitlesWidget: (value, meta) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                Money.compactPlain(value),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 10.5, color: c.mutedForeground),
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if ((value - index).abs() > 0.01) return const SizedBox.shrink();
              if (index < 0 || index >= count) return const SizedBox.shrink();
              // The last day always gets a label — it is the one the reader
              // came for — and a regular tick too close to it stands down.
              final last = count - 1;
              if (index != last) {
                if (index % labelEvery != 0) return const SizedBox.shrink();
                if (last - index < labelEvery * 0.75) {
                  return const SizedBox.shrink();
                }
              }
              final date = points[index].date;
              if (date == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  DateX.shortDay(date),
                  style: TextStyle(fontSize: 10.5, color: c.mutedForeground),
                ),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => c.popover,
          tooltipBorder: BorderSide(color: c.border),
          tooltipPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          getTooltipItems: (spots) => [
            for (final spot in spots)
              LineTooltipItem(
                Money.format(spot.y),
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.foreground,
                ),
                children: [
                  TextSpan(
                    text: '\n${_tooltipDate(spot.x.round())}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < count; i++)
              FlSpot(i.toDouble(), points[i].value.toDouble()),
          ],
          color: color,
          barWidth: 2.4,
          isCurved: true,
          curveSmoothness: 0.2,
          preventCurveOverShooting: true,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: count <= 14,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 3,
              color: c.card,
              strokeColor: color,
              strokeWidth: 2,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.28),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The tightest axis whose gridlines land on round numbers: the smallest
  /// 1/2/2.5/5 × 10^n step that still covers the series in five bands or
  /// fewer. Without this the labels read 12.87K / 13.41K and collide once
  /// abbreviated; with it they read 13K / 13.5K / 14K.
  static ({double min, double max, double step}) _axis(
    double low,
    double high,
  ) {
    final range = math.max(high - low, 1e-6);
    const ladder = [1.0, 2.0, 2.5, 5.0, 10.0];
    var magnitude = math
        .pow(10, (math.log(range / 5) / math.ln10).floor())
        .toDouble();

    for (var attempt = 0; attempt < 8; attempt++, magnitude *= 10) {
      for (final factor in ladder) {
        final step = factor * magnitude;
        final min = (low / step).floor() * step;
        final max = (high / step).ceil() * step;
        if ((max - min) / step <= 5.001) {
          return (min: min, max: max, step: step);
        }
      }
    }
    return (min: low, max: high, step: range / 4);
  }

  String _tooltipDate(int index) {
    if (index < 0 || index >= points.length) return '';
    final date = points[index].date;
    return date == null ? '' : '${DateX.shortDay(date)} ${date.year}';
  }
}
