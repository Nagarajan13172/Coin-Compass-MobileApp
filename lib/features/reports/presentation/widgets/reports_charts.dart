import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/report_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// The two `/reports/trend` charts.
//
// Both are 240dp tall, both share the axis formatting, and both have to read
// well with ONE bucket — which is this account's actual state: a whole year of
// data comes back as a single row. A lone bar and a lone dot are the normal
// case here, not a degenerate one.
//
// Y-axis ticks use one decimal (`13.3K`), matching the web's chart formatter;
// the money inside tooltips is formatted in full.
// ═══════════════════════════════════════════════════════════════════════════

const double kReportChartHeight = 240;

/// The "No data for this period" line the web renders at the chart's full
/// height, so an empty card keeps the same footprint as a full one.
class ChartPlaceholder extends StatelessWidget {
  const ChartPlaceholder({super.key, this.message = 'No data for this period'});

  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kReportChartHeight,
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, color: context.colors.mutedForeground),
      ),
    ),
  );
}

/// Income against expense, one pair of bars per bucket.
class IncomeVsExpenseChart extends StatelessWidget {
  const IncomeVsExpenseChart({super.key, required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const ChartPlaceholder();

    final c = context.colors;
    final peak = points.fold<double>(
      0,
      (best, p) =>
          math.max(best, math.max(p.income.toDouble(), p.expense.toDouble())),
    );
    final maxY = _niceCeiling(peak);
    final step = maxY / 4;
    final labelEvery = math.max(1, (points.length / 5).ceil());
    // 28 is the web's maxBarSize for the pair; a long month has to give it up
    // or 31 pairs will not fit 296dp.
    final barWidth = math.min(12.0, math.max(3.0, 260 / (points.length * 2.4)));

    return SizedBox(
      height: kReportChartHeight,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          minY: 0,
          alignment: points.length == 1
              ? BarChartAlignment.center
              : BarChartAlignment.spaceAround,
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
                reservedSize: 44,
                interval: step,
                getTitlesWidget: (value, meta) =>
                    _AxisTick(Money.compactPlain(value, decimals: 1)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (index % labelEvery != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _AxisTick(points[index].axisLabel),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => c.popover,
              tooltipBorder: BorderSide(color: c.border),
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                    '${points[group.x].axisLabel}\n',
                    TextStyle(fontSize: 11, color: c.mutedForeground),
                    children: [
                      TextSpan(
                        text:
                            '${rodIndex == 0 ? 'Income' : 'Expense'} '
                            '${Money.format(rod.toY)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: rodIndex == 0 ? c.income : c.expense,
                        ),
                      ),
                    ],
                  ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 3,
                barRods: [
                  _rod(points[i].income, c.income, barWidth),
                  _rod(points[i].expense, c.expense, barWidth),
                ],
              ),
          ],
        ),
      ),
    );
  }

  BarChartRodData _rod(num value, Color color, double width) => BarChartRodData(
    toY: value.toDouble(),
    color: color,
    width: width,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
  );
}

/// Net (income − expense) per bucket, as a filled area over a zero line.
class NetCashFlowChart extends StatelessWidget {
  const NetCashFlowChart({super.key, required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const ChartPlaceholder();

    final c = context.colors;
    final values = [for (final p in points) p.net.toDouble()];
    // Zero is always in frame: the whole point of the chart is which side of
    // it the line is on, and this account's net is negative every month.
    final low = math.min(0.0, values.reduce(math.min));
    final high = math.max(0.0, values.reduce(math.max));
    final span = high - low;
    final pad = span == 0 ? 100.0 : span * 0.15;
    final minY = low - pad;
    final maxY = high + pad;
    final step = (maxY - minY) / 4;
    final labelEvery = math.max(1, (points.length / 5).ceil());

    // A single bucket would collapse the x axis onto one pixel; give it room
    // either side so the lone dot lands in the middle of the plot.
    final single = points.length == 1;

    return SizedBox(
      height: kReportChartHeight,
      child: LineChart(
        LineChartData(
          minX: single ? -0.5 : 0,
          maxX: single ? 0.5 : (points.length - 1).toDouble(),
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
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(y: 0, color: c.border, strokeWidth: 1),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: step,
                getTitlesWidget: (value, meta) =>
                    _AxisTick(Money.compactPlain(value, decimals: 1)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if ((value - index).abs() > 0.01) {
                    return const SizedBox.shrink();
                  }
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (index % labelEvery != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _AxisTick(points[index].axisLabel),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => c.popover,
              tooltipBorder: BorderSide(color: c.border),
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  LineTooltipItem(
                    '${points[spot.x.round().clamp(0, points.length - 1)].axisLabel}\n'
                    'Net ${Money.format(spot.y, signed: true)}',
                    TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: spot.y < 0 ? c.expense : c.income,
                    ),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              color: c.primary,
              barWidth: 2,
              isCurved: true,
              curveSmoothness: 0.28,
              preventCurveOverShooting: true,
              isStrokeCapRound: true,
              // Always on: with one bucket the "line" IS the dot, and hiding
              // it would leave an empty card on this account's real data.
              dotData: FlDotData(
                show: points.length <= 14,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 3.5,
                      color: c.card,
                      strokeColor: c.primary,
                      strokeWidth: 2,
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                // Anchored on the zero line so a negative stretch fills
                // downward from it rather than from the bottom of the plot.
                applyCutOffY: true,
                cutOffY: 0,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.primary.withValues(alpha: 0.35),
                    c.primary.withValues(alpha: 0),
                  ],
                ),
              ),
              aboveBarData: BarAreaData(
                show: true,
                applyCutOffY: true,
                cutOffY: 0,
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    c.primary.withValues(alpha: 0.35),
                    c.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AxisTick extends StatelessWidget {
  const _AxisTick(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontSize: 10.5,
      color: context.colors.mutedForeground,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// Rounds an axis up to a readable ceiling — 13,312 becomes 14,000 so the four
/// gridlines land on 3.5K / 7K / 10.5K / 14K, exactly as the web does.
double _niceCeiling(double peak) {
  if (peak <= 0) return 100;
  if (peak < 10) return 10;
  final exponent = (math.log(peak) / math.ln10).floor() - 1;
  final magnitude = math.pow(10, exponent).toDouble();
  return (peak / magnitude).ceil() * magnitude;
}
