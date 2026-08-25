import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../reports/domain/report_models.dart';
import '../dashboard_screen.dart';

/// Two lines over `/reports/trend` buckets — income against expense — with a
/// legend and the period's net underneath.
class IncomeExpenseChart extends ConsumerWidget {
  const IncomeExpenseChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(dashboardTrendProvider);
    final summary = ref.watch(dashboardSummaryProvider).valueOrNull;

    return trend.when(
      loading: () => const LoadingCard(lines: 5),
      error: (error, _) => ErrorRetry(
        error: error,
        compact: true,
        onRetry: () => ref.invalidate(dashboardTrendProvider),
      ),
      data: (points) => _Chart(
        points: points,
        net: summary?.net ?? points.fold<num>(0, (sum, p) => sum + p.net),
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.points, required this.net});

  final List<TrendPoint> points;
  final num net;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Income vs expense',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (points.isEmpty)
            const EmptyState(
              icon: LucideIcons.chartLine,
              title: 'No activity this period',
              compact: true,
            )
          else ...[
            SizedBox(height: 190, child: LineChart(_data(context))),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: c.income, label: 'Income'),
                const SizedBox(width: 18),
                _LegendDot(color: c.expense, label: 'Expense'),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Net this period: ',
                      style: TextStyle(color: c.mutedForeground),
                    ),
                    TextSpan(
                      text: Money.format(net),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: net < 0 ? c.expense : c.income,
                      ),
                    ),
                    TextSpan(
                      text: '  (income − expense)',
                      style: TextStyle(color: c.mutedForeground),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  LineChartData _data(BuildContext context) {
    final c = context.colors;
    final count = points.length;

    var peak = 0.0;
    for (final p in points) {
      peak = math.max(
        peak,
        math.max(p.income.toDouble(), p.expense.toDouble()),
      );
    }
    final maxY = niceMaxY(peak);
    final step = maxY / 4;

    // A single bucket would collapse the x axis; give it room either side so
    // the lone dot lands in the middle of the plot.
    final minX = count == 1 ? -0.5 : 0.0;
    final maxX = count == 1 ? 0.5 : (count - 1).toDouble();

    // Every bucket gets a dot while the series is short enough to read.
    final showDots = count <= 12;
    final labelEvery = math.max(1, (count / 5).ceil());

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: 0,
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
              if (index % labelEvery != 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  bucketLabel(points[index]),
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
                  fontWeight: FontWeight.w600,
                  color: spot.barIndex == 0 ? c.income : c.expense,
                ),
              ),
          ],
        ),
      ),
      lineBarsData: [
        _series(
          context,
          color: c.income,
          showDots: showDots,
          value: (p) => p.income,
        ),
        _series(
          context,
          color: c.expense,
          showDots: showDots,
          value: (p) => p.expense,
        ),
      ],
    );
  }

  LineChartBarData _series(
    BuildContext context, {
    required Color color,
    required bool showDots,
    required num Function(TrendPoint) value,
  }) {
    final card = context.colors.card;
    return LineChartBarData(
      spots: [
        for (var i = 0; i < points.length; i++)
          FlSpot(i.toDouble(), value(points[i]).toDouble()),
      ],
      color: color,
      barWidth: 2.4,
      isCurved: true,
      curveSmoothness: 0.28,
      preventCurveOverShooting: true,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: showDots,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 3.5,
          color: card,
          strokeColor: color,
          strokeWidth: 2,
        ),
      ),
      belowBarData: BarAreaData(show: false),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12.5)),
      ],
    );
  }
}

/// Rounds the axis up to a readable ceiling — 13,312 becomes 14,000 so the
/// four gridlines land on 3.5K / 7K / 10.5K / 14K, exactly as the web app does.
double niceMaxY(num peak) {
  final value = peak.toDouble();
  if (value <= 0) return 100;
  if (value < 10) return 10;
  final exponent = (math.log(value) / math.ln10).floor() - 1;
  final magnitude = math.pow(10, exponent).toDouble();
  return (value / magnitude).ceil() * magnitude;
}

/// `2026-08-04` -> `04 Aug`, `2026-08` -> `Aug`, anything else -> the raw
/// bucket. The rule lives on the model so Reports and the dashboard label the
/// same axis the same way.
String bucketLabel(TrendPoint point) => point.axisLabel;
