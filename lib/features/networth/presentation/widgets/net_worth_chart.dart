import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_x.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/net_worth_point.dart';

/// The net-worth trend line over `/networth/history`.
///
/// The series is genuinely tiny in practice — the recorded account has two
/// snapshots — and it is frequently **negative** (a ₹2Cr home loan against
/// almost no assets). Both cases are handled here rather than assumed away:
///
///  * 0 points renders an empty state, not a blank box;
///  * 1 point renders a single dot centred on its own axis, because a
///    one-element line has no x range and fl_chart would collapse it;
///  * the y bounds are derived from the data on both sides, so an all-negative
///    series is drawn in full instead of being clipped against a zero floor.
class NetWorthChart extends StatelessWidget {
  const NetWorthChart({super.key, required this.points, this.height = 200});

  /// Oldest first.
  final List<NetWorthPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.chartLine,
        title: 'No snapshots yet',
        message: 'Net worth is recorded over time — check back tomorrow.',
        compact: true,
      );
    }
    return SizedBox(height: height, child: LineChart(_data(context)));
  }

  LineChartData _data(BuildContext context) {
    final c = context.colors;
    final count = points.length;
    final values = [for (final point in points) point.netWorth.toDouble()];

    final (minY, maxY) = _bounds(
      values.reduce(math.min),
      values.reduce(math.max),
    );
    final step = (maxY - minY) / 4;

    // A lone snapshot has no x span; give it half a unit either side so the
    // dot lands in the middle of the plot rather than on its left edge.
    final minX = count == 1 ? -0.5 : 0.0;
    final maxX = count == 1 ? 0.5 : (count - 1).toDouble();

    // Below −₹0 the line is a debt curve, above it a growth curve. The tint
    // follows the newest figure so the card reads at a glance.
    final accent = points.last.netWorth < 0 ? c.expense : c.income;
    final labelEvery = math.max(1, (count / 4).ceil());
    final crossesZero = minY < 0 && maxY > 0;

    return LineChartData(
      minX: minX,
      maxX: maxX,
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
      // The zero line only earns its ink when the series actually straddles
      // it — on an all-negative chart it would sit off-canvas.
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          if (crossesZero)
            HorizontalLine(
              y: 0,
              color: c.mutedForeground.withValues(alpha: 0.55),
              strokeWidth: 1,
            ),
        ],
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            // 50 left 42dp for the text, and a negative crore label
            // ('\u22122.02Cr') needs ~44 — the 'Cr' wrapped onto its own line.
            // The width is the real fix; maxLines is the belt-and-braces so a
            // longer label ellipsises instead of wrapping again.
            reservedSize: 60,
            interval: step,
            getTitlesWidget: (value, meta) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                Money.compactPlain(value),
                textAlign: TextAlign.right,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
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
              // The ends are always named; the middle only when the series is
              // long enough for the labels not to collide.
              final isEnd = index == 0 || index == count - 1;
              if (!isEnd && (count < 5 || index % labelEvery != 0)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  DateX.shortDay(points[index].date),
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
                '${DateX.shortDay(points[spot.x.round().clamp(0, count - 1)].date)}\n'
                '${Money.format(points[spot.x.round().clamp(0, count - 1)].netWorth)}',
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.foreground,
                ),
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < count; i++) FlSpot(i.toDouble(), values[i]),
          ],
          color: accent,
          barWidth: 2.4,
          isCurved: count > 2,
          curveSmoothness: 0.28,
          preventCurveOverShooting: true,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: count <= 12,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 3.5,
              color: c.card,
              strokeColor: accent,
              strokeWidth: 2,
            ),
          ),
          // Filled toward zero, not toward the axis floor: on a debt chart the
          // band sits *above* the line, which is what makes it read as a hole
          // rather than a holding.
          belowBarData: BarAreaData(
            show: true,
            applyCutOffY: true,
            cutOffY: 0,
            color: accent.withValues(alpha: 0.12),
          ),
          aboveBarData: BarAreaData(
            show: true,
            applyCutOffY: true,
            cutOffY: 0,
            color: accent.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }

  /// Symmetric padding around the data, widened when every value is identical
  /// so a flat (or single-point) series still gets a usable axis instead of a
  /// zero-height one, which fl_chart cannot divide into gridlines.
  static (double, double) _bounds(double low, double high) {
    var lo = low;
    var hi = high;
    if ((hi - lo).abs() < 1e-9) {
      final pad = lo.abs() < 1 ? 1.0 : lo.abs() * 0.08;
      lo -= pad;
      hi += pad;
    }
    final padding = (hi - lo) * 0.12;
    return (lo - padding, hi + padding);
  }
}
