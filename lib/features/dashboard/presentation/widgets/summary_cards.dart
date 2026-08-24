import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../reports/domain/report_models.dart';
import '../dashboard_screen.dart';

/// The Income / Expense / Net trio, stacked. Values come from
/// `/reports/summary` for the selected window.
class SummaryCards extends ConsumerWidget {
  const SummaryCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);

    return summary.when(
      loading: () => const Column(
        children: [
          LoadingCard(lines: 2),
          SizedBox(height: 12),
          LoadingCard(lines: 2),
          SizedBox(height: 12),
          LoadingCard(lines: 2),
        ],
      ),
      error: (error, _) => ErrorRetry(
        error: error,
        compact: true,
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
      ),
      data: (data) => _Cards(summary: data),
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final net = summary.net;

    // Zero net is neither a win nor a loss — leave it uncoloured.
    final netTone = net < 0
        ? MoneyTone.expense
        : (net > 0 ? MoneyTone.income : MoneyTone.neutral);

    return Column(
      children: [
        StatCard(
          label: 'Income',
          icon: LucideIcons.arrowDownLeft,
          accent: c.income,
          amount: summary.income,
          tone: MoneyTone.income,
        ),
        const SizedBox(height: 12),
        StatCard(
          label: 'Expense',
          icon: LucideIcons.arrowUpRight,
          accent: c.expense,
          amount: summary.expense,
          tone: MoneyTone.expense,
        ),
        const SizedBox(height: 12),
        StatCard(
          label: 'Net',
          icon: LucideIcons.piggyBank,
          accent: net < 0 ? c.expense : c.primary,
          amount: net,
          tone: netTone,
          subtitle: summary.income == 0 ? 'No income this period' : null,
        ),
      ],
    );
  }
}
