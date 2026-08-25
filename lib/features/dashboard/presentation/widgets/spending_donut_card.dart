import 'package:fl_chart/fl_chart.dart';
import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/segmented_period_selector.dart';
import '../../../categories/domain/category.dart';
import '../../../reports/domain/report_models.dart';
import '../dashboard_screen.dart';

/// Spending by category: a Groups/All toggle, the earned/spent/net totals, a
/// donut and the per-row breakdown.
class SpendingDonutCard extends ConsumerStatefulWidget {
  const SpendingDonutCard({super.key});

  @override
  ConsumerState<SpendingDonutCard> createState() => _SpendingDonutCardState();
}

class _SpendingDonutCardState extends ConsumerState<SpendingDonutCard> {
  /// The web app opens on Groups, which is the readable view for 33 seeded
  /// categories.
  bool _grouped = true;

  static const int _maxRows = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final slices = ref.watch(dashboardCategoryProvider);
    final summary = ref.watch(dashboardSummaryProvider).valueOrNull;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Spending by category',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SegmentedPeriodSelector<bool>(
                    value: _grouped,
                    options: const [
                      SegmentOption(true, 'Groups'),
                      SegmentOption(false, 'All'),
                    ],
                    onChanged: (next) => setState(() => _grouped = next),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => context.go('/reports'),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        'View in Reports',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (summary != null) ...[
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _Total(
                  label: 'Total earned',
                  amount: summary.income,
                  tone: MoneyTone.income,
                ),
                _Total(
                  label: 'Total spent',
                  amount: summary.expense,
                  tone: MoneyTone.expense,
                ),
                _Total(
                  label: 'Net',
                  amount: summary.net,
                  tone: summary.net < 0 ? MoneyTone.expense : MoneyTone.income,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: c.border),
          ],
          slices.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LoadingCard(lines: 4),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ErrorRetry(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(dashboardCategoryProvider),
              ),
            ),
            data: (data) => _Breakdown(
              rows: buildSpendRows(data, grouped: _grouped),
              maxRows: _maxRows,
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.amount, required this.tone});

  final String label;
  final num amount;
  final MoneyTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: c.mutedForeground)),
        const SizedBox(width: 6),
        MoneyText(
          amount,
          tone: tone,
          compactAbove: Money.crore,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.rows, required this.maxRows});

  final List<SpendRow> rows;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyState(title: 'No spending this period', compact: true);
    }

    final c = context.colors;
    final total = rows.fold<num>(0, (sum, row) => sum + row.total);

    return Column(
      children: [
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 58,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(enabled: false),
                  sections: [
                    for (var i = 0; i < rows.length; i++)
                      PieChartSectionData(
                        value: rows[i].total.toDouble(),
                        color: spendRowColor(context, i, rows[i].colorHex),
                        radius: 42,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total spent',
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
                  const SizedBox(height: 2),
                  MoneyText(
                    total,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < rows.length && i < maxRows; i++)
          _Row(row: rows[i], index: i),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.index});

  final SpendRow row;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: () => context.go('/reports'),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(LucideIcons.chevronRight, size: 16, color: c.mutedForeground),
            const SizedBox(width: 6),
            CategoryAvatar(
              icon: row.icon,
              colorHex: row.colorHex,
              size: 34,
              fallbackColor: spendRowColor(context, index, row.colorHex),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Money.percent(row.percent, alreadyScaled: true),
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
            const SizedBox(width: 10),
            MoneyText(
              row.total,
              compactAbove: Money.crore,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One donut slice + list row, in either Groups or All mode.
class SpendRow {
  const SpendRow({
    required this.name,
    required this.total,
    required this.percent,
    this.icon,
    this.colorHex,
    this.count = 0,
  });

  final String name;
  final num total;

  /// Already scaled — `100` means 100%.
  final num percent;
  final String? icon;
  final String? colorHex;
  final int count;
}

/// Turns `/reports/by-category` slices into rows, optionally folded up by the
/// category's `group` (the Groups toggle). Biggest first, zero/negative
/// totals dropped — a donut cannot draw them.
List<SpendRow> buildSpendRows(
  List<CategorySlice> slices, {
  required bool grouped,
}) {
  final usable = slices.where((s) => s.total > 0).toList();
  if (usable.isEmpty) return const [];
  final total = usable.fold<num>(0, (sum, s) => sum + s.total);

  num pct(num value) => total <= 0 ? 0 : value / total * 100;

  if (!grouped) {
    final rows = [
      for (final slice in usable)
        SpendRow(
          name: slice.name,
          total: slice.total,
          percent: pct(slice.total),
          icon: slice.icon,
          colorHex: slice.color,
          count: slice.count,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return rows;
  }

  final buckets = <String, List<CategorySlice>>{};
  for (final slice in usable) {
    final key = (slice.group == null || slice.group!.isEmpty)
        ? 'other'
        : slice.group!;
    (buckets[key] ??= <CategorySlice>[]).add(slice);
  }

  final rows = <SpendRow>[];
  buckets.forEach((key, members) {
    // The group takes its tint from its biggest member, so the donut keeps
    // using the colours the user picked rather than an invented palette.
    members.sort((a, b) => b.total.compareTo(a.total));
    final sum = members.fold<num>(0, (acc, s) => acc + s.total);
    rows.add(
      SpendRow(
        name: categoryGroupLabels[key] ?? key,
        total: sum,
        percent: pct(sum),
        icon: categoryGroupIcons[key],
        colorHex: members.first.color,
        count: members.fold<int>(0, (acc, s) => acc + s.count),
      ),
    );
  });
  rows.sort((a, b) => b.total.compareTo(a.total));
  return rows;
}

/// A lucide glyph per `group` value, so a folded row still reads at a glance.
const Map<String, String> categoryGroupIcons = {
  'food': 'utensils',
  'transport': 'car',
  'home': 'home',
  'bills': 'receipt',
  'health': 'heart-pulse',
  'education': 'graduation-cap',
  'lifestyle': 'sparkles',
  'family_giving': 'gift',
  'savings': 'piggy-bank',
  'debt_transfers': 'arrow-right-left',
  'earnings': 'briefcase',
  'inflows': 'trending-up',
  'returns': 'rotate-ccw',
  'other': 'ellipsis',
};

/// The category's own colour when the API supplied one, otherwise a hue rotated
/// off `primary` so neighbouring slices stay distinguishable in both themes.
Color spendRowColor(BuildContext context, int index, String? hex) {
  final own = colorFromHex(hex);
  if (own != null) return own;
  final base = HSLColor.fromColor(context.colors.primary);
  return base
      .withHue((base.hue + index * 47) % 360)
      .withSaturation(0.68)
      .withLightness(0.55)
      .toColor();
}
