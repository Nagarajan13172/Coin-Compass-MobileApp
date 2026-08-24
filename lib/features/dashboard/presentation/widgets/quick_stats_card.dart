import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../reports/domain/report_models.dart';
import '../../../reports/presentation/period.dart';
import '../dashboard_screen.dart';

/// Avg spend / day · Biggest category · Transactions.
class QuickStatsCard extends ConsumerWidget {
  const QuickStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);
    final range = ref.watch(periodRangeProvider);
    final slices = ref.watch(dashboardCategoryProvider).valueOrNull;

    return summary.when(
      loading: () => const LoadingCard(lines: 4),
      error: (error, _) => ErrorRetry(
        error: error,
        compact: true,
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
      ),
      data: (data) => _Stats(summary: data, range: range, slices: slices),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.summary, required this.range, this.slices});

  final ReportSummary summary;
  final PeriodRange range;
  final List<CategorySlice>? slices;

  @override
  Widget build(BuildContext context) {
    final biggest = biggestSlice(slices);
    final perDay = (summary.expense / elapsedDays(range)).round();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Stat(
                  label: 'Avg spend / day',
                  value: Money.format(perDay),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  label: 'Biggest category',
                  value: biggest?.name ?? '—',
                  detail: biggest == null ? null : Money.format(biggest.total),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Stat(label: 'Transactions', value: '${summary.count}'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: c.mutedForeground)),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(
            detail!,
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ],
      ],
    );
  }
}

/// Days the window has actually run for: a current period stops at today, a
/// past one counts every day. Never zero — this is a divisor.
int elapsedDays(PeriodRange range) {
  final total = range.end.difference(range.start).inDays;
  if (total <= 0) return 1;
  if (!range.contains(DateTime.now())) return total;
  final elapsed = DateTime.now().difference(range.start).inDays + 1;
  return elapsed.clamp(1, total);
}

/// Largest expense slice, or null when nothing was spent.
CategorySlice? biggestSlice(List<CategorySlice>? slices) {
  if (slices == null || slices.isEmpty) return null;
  var best = slices.first;
  for (final slice in slices) {
    if (slice.total > best.total) best = slice;
  }
  return best.total <= 0 ? null : best;
}
