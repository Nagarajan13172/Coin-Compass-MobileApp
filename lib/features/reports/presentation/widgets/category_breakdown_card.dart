import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/lucide_map.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/segmented_period_selector.dart';
import '../../../categories/domain/category.dart';
import '../../domain/report_models.dart';
import '../reports_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// "By category" — the donut, its totals strip and the legend.
//
// Two toggles drive it, exactly as on the web: Groups|All folds the 33 seeded
// categories up by their `group` key, and Expense|Income swaps which side of
// the ledger is being broken down (and with it the donut's centre total, which
// comes from `/reports/summary` rather than from the sum of the slices).
// ═══════════════════════════════════════════════════════════════════════════

/// A group's glyph and tint, transcribed from the web bundle's static table
/// (offset 634460). Held as [IconData] rather than lucide *names* because
/// these are this app's own constants — nothing here comes off the wire, so
/// there is no reason to round-trip them through the API icon-name map.
class _GroupMeta {
  const _GroupMeta(this.icon, this.color);
  final IconData icon;
  final Color color;
}

const Map<String, _GroupMeta> _groupMeta = {
  'food': _GroupMeta(LucideIcons.utensils, Color(0xFFF97316)),
  'transport': _GroupMeta(LucideIcons.car, Color(0xFF3B82F6)),
  'home': _GroupMeta(LucideIcons.house, Color(0xFF8B5CF6)),
  'bills': _GroupMeta(LucideIcons.receipt, Color(0xFFEAB308)),
  'health': _GroupMeta(LucideIcons.heartPulse, Color(0xFFEF4444)),
  'education': _GroupMeta(LucideIcons.graduationCap, Color(0xFF0EA5E9)),
  'lifestyle': _GroupMeta(LucideIcons.sparkles, Color(0xFFEC4899)),
  'family_giving': _GroupMeta(LucideIcons.heartHandshake, Color(0xFF22C55E)),
  'savings': _GroupMeta(LucideIcons.piggyBank, Color(0xFF14B8A6)),
  'debt_transfers': _GroupMeta(LucideIcons.creditCard, Color(0xFFA855F7)),
  'earnings': _GroupMeta(LucideIcons.banknote, Color(0xFF22C55E)),
  'returns': _GroupMeta(LucideIcons.trendingUp, Color(0xFF14B8A6)),
  'inflows': _GroupMeta(LucideIcons.coins, Color(0xFF0EA5E9)),
};

const _GroupMeta _fallbackGroup = _GroupMeta(LucideIcons.tag, Color(0xFF64748B));

/// The key the web buckets a group-less category under, and its label. Note it
/// is `ungrouped`, not the `other` that `categoryGroupLabels` carries.
const String _ungrouped = 'ungrouped';

String _groupLabel(String key) => key == _ungrouped
    ? 'Ungrouped'
    : (categoryGroupLabels[key] ?? 'Other');

/// One legend row / donut slice.
///
/// A group row carries its [children]; a flat row carries none. Both are the
/// same type so the legend can render them with one code path — the donut only
/// ever draws the top level.
@immutable
class CategoryRow {
  const CategoryRow({
    required this.key,
    required this.name,
    required this.total,
    required this.percent,
    required this.color,
    this.icon,
    this.iconName,
    this.categoryId,
    this.children = const [],
  });

  /// Stable identity for expansion state: the group key, or the category id.
  final String key;
  final String name;
  final num total;

  /// Already scaled — `100` means 100%.
  final num percent;
  final Color color;

  /// Set for a group row, whose glyph is a constant rather than an API name.
  final IconData? icon;

  /// Set for a category row, whose glyph is the lucide name the API sent.
  final String? iconName;

  /// Null for a group row and for the uncategorised bucket.
  final String? categoryId;

  final List<CategoryRow> children;

  bool get isGroup => children.isNotEmpty;
}

/// Folds `/reports/by-category` into legend rows, biggest first.
///
/// Zero and negative totals are dropped — a donut cannot draw them, and the
/// server never sends them for a real window anyway.
///
/// Percentages deliberately follow the web's asymmetry: a flat row echoes the
/// server's integer `percent`, while a group row is recomputed to one decimal
/// (`round(total / grand * 1000) / 10`).
List<CategoryRow> buildCategoryRows(
  List<CategorySlice> slices, {
  required bool grouped,
  Color? fallbackColor,
}) {
  final usable = slices.where((s) => s.total > 0).toList();
  if (usable.isEmpty) return const [];

  Color colorOf(CategorySlice s) =>
      colorFromHex(s.color) ?? fallbackColor ?? _fallbackGroup.color;

  CategoryRow flat(CategorySlice s) => CategoryRow(
    key: s.categoryId ?? s.name,
    name: s.name,
    total: s.total,
    percent: s.percent,
    color: colorOf(s),
    iconName: s.icon,
    categoryId: s.categoryId,
  );

  if (!grouped) {
    return [for (final s in usable) flat(s)]
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  final grand = usable.fold<num>(0, (sum, s) => sum + s.total);
  final buckets = <String, List<CategorySlice>>{};
  for (final slice in usable) {
    final key = (slice.group == null || slice.group!.isEmpty)
        ? _ungrouped
        : slice.group!;
    (buckets[key] ??= <CategorySlice>[]).add(slice);
  }

  final rows = <CategoryRow>[];
  buckets.forEach((key, members) {
    members.sort((a, b) => b.total.compareTo(a.total));
    final total = members.fold<num>(0, (sum, s) => sum + s.total);
    final meta = _groupMeta[key];
    rows.add(
      CategoryRow(
        key: key,
        name: _groupLabel(key),
        total: total,
        // One decimal, and never `13.0` — Money.percent trims a whole number.
        percent: grand <= 0 ? 0 : (total / grand * 1000).round() / 10,
        // An unknown group that is not `ungrouped` inherits the colour of its
        // biggest child, which is what keeps a server-added group from
        // rendering in the same slate grey as Ungrouped.
        color: meta?.color ??
            (key == _ungrouped
                ? _fallbackGroup.color
                : colorOf(members.first)),
        icon: meta?.icon ?? _fallbackGroup.icon,
        children: [for (final s in members) flat(s)],
      ),
    );
  });

  rows.sort((a, b) => b.total.compareTo(a.total));
  return rows;
}

/// The card itself: header toggles, totals strip, donut and legend.
class CategoryBreakdownCard extends ConsumerStatefulWidget {
  const CategoryBreakdownCard({
    super.key,
    required this.summary,
    required this.onOpenCategory,
  });

  /// The window's summary, for the centre total and the earned/spent/net
  /// strip. Null while `/reports/summary` is still in flight or has failed —
  /// the donut then falls back to the sum of its own slices.
  final ReportSummary? summary;

  /// Drill-through: the tapped category id (null for the uncategorised
  /// bucket), plus which side of the ledger the toggle is on.
  final void Function(String? categoryId, String type) onOpenCategory;

  @override
  ConsumerState<CategoryBreakdownCard> createState() =>
      _CategoryBreakdownCardState();
}

class _CategoryBreakdownCardState extends ConsumerState<CategoryBreakdownCard> {
  final Set<String> _expanded = <String>{};

  /// The slice the user last tapped — grown in the donut and tinted in the
  /// legend. The web drives this from hover, which a phone does not have.
  int? _active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final range = ref.watch(reportsRangeProvider);
    final type = ref.watch(reportsBreakdownTypeProvider);
    final grouping = ref.watch(categoryGroupingProvider);
    final slices = ref.watch(
      reportsByCategoryProvider(CategoryBreakdownQuery(range, type: type)),
    );
    final summary = widget.summary;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'By category',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          // Two segmented controls side by side is 300dp+ of pills; a Wrap
          // lets the second drop to its own line at 360dp instead of
          // overflowing the card.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SegmentedPeriodSelector<CategoryGrouping>(
                value: grouping,
                options: const [
                  SegmentOption(CategoryGrouping.group, 'Groups'),
                  SegmentOption(CategoryGrouping.flat, 'All'),
                ],
                onChanged: (next) {
                  setState(() {
                    _active = null;
                    _expanded.clear();
                  });
                  ref.read(categoryGroupingProvider.notifier).state = next;
                },
              ),
              SegmentedPeriodSelector<String>(
                value: type,
                options: const [
                  SegmentOption('expense', 'Expense'),
                  SegmentOption('income', 'Income'),
                ],
                onChanged: (next) {
                  setState(() {
                    _active = null;
                    _expanded.clear();
                  });
                  ref.read(reportsBreakdownTypeProvider.notifier).state = next;
                },
              ),
            ],
          ),
          if (summary != null) ...[
            const SizedBox(height: 14),
            _TotalsStrip(summary: summary),
            const SizedBox(height: 12),
            Divider(height: 1, color: c.border),
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
                onRetry: () => ref.invalidate(
                  reportsByCategoryProvider(
                    CategoryBreakdownQuery(range, type: type),
                  ),
                ),
              ),
            ),
            data: (data) => _Body(
              rows: buildCategoryRows(
                data,
                grouped: grouping == CategoryGrouping.group,
                fallbackColor: c.primary,
              ),
              type: type,
              summary: summary,
              expanded: _expanded,
              active: _active,
              onSliceTap: (index) => setState(
                () => _active = _active == index ? null : index,
              ),
              onToggleGroup: (key) => setState(() {
                if (!_expanded.remove(key)) _expanded.add(key);
              }),
              onOpenCategory: (id) => widget.onOpenCategory(id, type),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsStrip extends StatelessWidget {
  const _TotalsStrip({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final net = summary.net;
    return Wrap(
      spacing: 16,
      runSpacing: 6,
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
          amount: net,
          tone: net < 0 ? MoneyTone.expense : MoneyTone.income,
          signed: true,
        ),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.amount,
    required this.tone,
    this.signed = false,
  });

  final String label;
  final num amount;
  final MoneyTone tone;
  final bool signed;

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
          signed: signed,
          compactAbove: Money.crore,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.rows,
    required this.type,
    required this.summary,
    required this.expanded,
    required this.active,
    required this.onSliceTap,
    required this.onToggleGroup,
    required this.onOpenCategory,
  });

  final List<CategoryRow> rows;
  final String type;
  final ReportSummary? summary;
  final Set<String> expanded;
  final int? active;
  final ValueChanged<int> onSliceTap;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<String?> onOpenCategory;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      // House voice, and it names the side of the ledger being shown: with the
      // Income toggle selected, "No spending this period" would be a lie.
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: EmptyState(
          icon: LucideIcons.chartPie,
          title: type == 'income'
              ? 'No income this period'
              : 'No spending this period',
          message: 'Nothing to break down for the window you are on.',
          compact: true,
        ),
      );
    }

    final c = context.colors;
    final income = type == 'income';
    // The centre states the period's total from `/reports/summary`, not the
    // sum of the slices — an uncategorised transaction is in one and not the
    // other, and the web shows the summary figure.
    final centre = summary == null
        ? rows.fold<num>(0, (sum, row) => sum + row.total)
        : (income ? summary!.income : summary!.expense);
    final biggest = rows.first.total;

    return Column(
      children: [
        const SizedBox(height: 16),
        SizedBox(
          height: 192,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 62,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions) return;
                      final index =
                          response?.touchedSection?.touchedSectionIndex;
                      if (index == null || index < 0) return;
                      HapticFeedback.selectionClick();
                      onSliceTap(index);
                    },
                  ),
                  sections: [
                    for (var i = 0; i < rows.length; i++)
                      PieChartSectionData(
                        value: rows[i].total.toDouble(),
                        color: active == null || active == i
                            ? rows[i].color
                            : rows[i].color.withValues(alpha: 0.4),
                        radius: active == i ? 32 : 26,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              // The overlay must not swallow the slice taps behind it.
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        income ? 'Total earned' : 'Total spent',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: MoneyText(
                          centre,
                          tone: income ? MoneyTone.income : MoneyTone.expense,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < rows.length; i++) ...[
          _LegendRow(
            row: rows[i],
            share: biggest <= 0 ? 0 : rows[i].total / biggest,
            active: active == i,
            expanded: expanded.contains(rows[i].key),
            onTap: () => rows[i].isGroup
                ? onToggleGroup(rows[i].key)
                : onOpenCategory(rows[i].categoryId),
          ),
          if (rows[i].isGroup && expanded.contains(rows[i].key))
            for (final child in rows[i].children)
              _LegendRow(
                row: child,
                share: biggest <= 0 ? 0 : child.total / biggest,
                active: false,
                expanded: false,
                child: true,
                onTap: () => onOpenCategory(child.categoryId),
              ),
        ],
      ],
    );
  }
}

/// `[chevron] [avatar] name … amount` over a proportional bar.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.row,
    required this.share,
    required this.active,
    required this.expanded,
    required this.onTap,
    this.child = false,
  });

  final CategoryRow row;

  /// This row's total against the biggest row's, 0–1 — the bar's width.
  final double share;
  final bool active;
  final bool expanded;
  final bool child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      button: true,
      label: row.isGroup
          ? '${expanded ? 'Hide' : 'Show'} the categories in ${row.name}'
          : 'View ${row.name} transactions',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: active ? c.accent : null,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: EdgeInsets.fromLTRB(child ? 22 : 6, 7, 6, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (row.isGroup)
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        LucideIcons.chevronRight,
                        size: 15,
                        color: c.mutedForeground,
                      ),
                    )
                  else
                    const SizedBox(width: 15),
                  const SizedBox(width: 6),
                  _RowAvatar(row: row, size: child ? 26 : 30),
                  const SizedBox(width: 9),
                  // The name is the only elastic child: a nine-figure amount
                  // and a 40-character category name have to share 296dp, so
                  // the amount keeps its intrinsic width and the name gives.
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: child ? 13 : 14.5,
                        fontWeight: child ? FontWeight.w500 : FontWeight.w600,
                        color: child ? c.mutedForeground : c.foreground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MoneyText(
                    row.total,
                    compactAbove: Money.crore,
                    style: TextStyle(
                      fontSize: child ? 13 : 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 21),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          // A 0.02 floor keeps a rounding-error slice visible
                          // rather than collapsing it to nothing, matching the
                          // web's `max(2%, …)`.
                          value: share.isFinite ? share.clamp(0.02, 1.0) : 0.02,
                          minHeight: 6,
                          backgroundColor: c.muted,
                          valueColor: AlwaysStoppedAnimation(row.color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        Money.percent(row.percent, alreadyScaled: true),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: c.mutedForeground,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowAvatar extends StatelessWidget {
  const _RowAvatar({required this.row, required this.size});

  final CategoryRow row;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = row.icon;
    if (icon == null) {
      // A category row: the glyph is an API-supplied lucide name.
      return _Tinted(
        color: row.color,
        size: size,
        child: Icon(
          // Unknown names fall back rather than throwing — the seeded
          // categories all resolve, but the backend can add icons.
          lucideIcon(row.iconName, fallback: LucideIcons.tag),
          size: size * 0.5,
          color: row.color,
        ),
      );
    }
    return _Tinted(
      color: row.color,
      size: size,
      child: Icon(icon, size: size * 0.5, color: row.color),
    );
  }
}

class _Tinted extends StatelessWidget {
  const _Tinted({
    required this.color,
    required this.size,
    required this.child,
  });

  final Color color;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: child,
  );
}
