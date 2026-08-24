import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../data/loans_repository.dart';
import '../domain/loan.dart';
import 'loan_form_sheet.dart';
import 'loan_pay_sheet.dart';
import 'loan_preclose_sheet.dart';
import 'loans_providers.dart';
import 'prepayment_planner_sheet.dart';
import 'widgets/loan_card.dart';
import '../../../core/router/route_refresh.dart';

/// `/loans` — what is still owed, what it costs every month, and the tools to
/// pay it off early. Body only; [AppScaffold] supplies the chrome.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'Loans',
            subtitle: 'Track balances and plan an early payoff',
            actions: [
              ScreenHeaderAction(
                label: 'Add loan',
                icon: LucideIcons.plus,
                onPressed: () => LoanFormSheet.show(context),
              ),
            ],
          ),
          switch (loans) {
            AsyncData(:final value) when value.isEmpty => _EmptyLoans(
              onAdd: () => LoanFormSheet.show(context),
            ),
            AsyncData() => const _LoansBody(),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(loansFetchProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 4),
                  SizedBox(height: 12),
                  LoadingCard(lines: 5),
                  SizedBox(height: 12),
                  LoadingCard(lines: 5),
                ],
              ),
            ),
          },
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) => refreshCurrentRoute(ref, '/loans');
}

class _EmptyLoans extends StatelessWidget {
  const _EmptyLoans({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DashedBox(
        child: EmptyState(
          icon: LucideIcons.landmark,
          title: 'No loans yet',
          message:
              'Add your loans to track outstanding balances and plan an early '
              'payoff.',
          actionLabel: 'Add loan',
          onAction: onAdd,
        ),
      ),
    );
  }
}

/// Summary, the share-of-total breakdown, then the Active / Closed lists.
class _LoansBody extends ConsumerWidget {
  const _LoansBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeLoansProvider);
    final closed = ref.watch(closedLoansProvider);
    final summary = ref.watch(loansSummaryProvider);
    final tab = ref.watch(loansTabProvider);
    final shown = tab == LoanStatus.active ? active : closed;

    return Column(
      children: [
        if (active.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _SummaryCard(summary: summary),
          ),
          if (active.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _OutstandingByLoan(
                loans: active,
                total: summary.totalOutstanding,
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(
            children: [
              // The counts sit beside the pills rather than inside them: two
              // labels with numbers baked in overflow 360dp.
              SegmentedPeriodSelector<LoanStatus>(
                value: tab,
                options: const [
                  SegmentOption(LoanStatus.active, 'Active'),
                  SegmentOption(LoanStatus.closed, 'Closed'),
                ],
                onChanged: (value) =>
                    ref.read(loansTabProvider.notifier).state = value,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${shown.length} ${shown.length == 1 ? 'loan' : 'loans'}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.colors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: DashedBox(
              child: EmptyState(
                compact: true,
                icon: tab == LoanStatus.active
                    ? LucideIcons.partyPopper
                    : LucideIcons.archive,
                title: tab == LoanStatus.active
                    ? 'No active loans'
                    : 'No closed loans',
                message: tab == LoanStatus.active
                    ? 'Every loan is marked closed — nothing outstanding.'
                    : 'Loans you preclose or mark closed are kept here.',
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (final loan in shown)
                  LoanCard(
                    loan: loan,
                    onEdit: () => LoanFormSheet.show(context, loan: loan),
                    onPlan: () =>
                        PrepaymentPlannerSheet.show(context, loan: loan),
                    onPay: () => LoanPaySheet.show(context, loan: loan),
                    onPreclose: () =>
                        LoanPrecloseSheet.show(context, loan: loan),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Total outstanding as the headline, with the three figures that decide what
/// to do about it: what it costs each month, what it will still cost in
/// interest, and the blended rate being paid.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final LoansSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final repaidPct = summary.repaidPct;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total outstanding',
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
          const SizedBox(height: 4),
          // The exact figure, the way the web app states it. FittedBox is what
          // keeps a ten-figure balance on one line; compacting this to "₹2Cr"
          // would hide the very number the card exists to show. Dense rows,
          // where a label has to share the width, keep compactAbove.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              summary.totalOutstanding,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: c.expense,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            repaidPct != null
                ? '$repaidPct% repaid of ${Money.compact(summary.totalPrincipal)} borrowed'
                : '${summary.count} active ${summary.count == 1 ? 'loan' : 'loans'}',
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Stat(
                  label: 'EMI / month',
                  value: summary.totalEmi > 0
                      ? Money.compact(summary.totalEmi)
                      : '—',
                  caption:
                      'Across ${summary.count} ${summary.count == 1 ? 'loan' : 'loans'}',
                ),
              ),
              Container(width: 1, height: 46, color: c.border),
              Expanded(
                child: _Stat(
                  label: 'Interest left',
                  value: '~${Money.compact(summary.interestRemaining)}',
                  tone: c.expense,
                  caption: 'At current EMIs & rates',
                ),
              ),
              Container(width: 1, height: 46, color: c.border),
              Expanded(
                child: _Stat(
                  label: 'Avg rate',
                  value: summary.weightedRoi == null
                      ? '—'
                      : Money.percent(
                          summary.weightedRoi,
                          alreadyScaled: true,
                          decimals: 2,
                        ),
                  caption: 'Weighted by balance',
                ),
              ),
            ],
          ),
          if (summary.anyInfeasible) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.triangleAlert, size: 15, color: c.expense),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'One or more EMIs do not cover their monthly interest, so '
                    'the interest left is understated.',
                    style: TextStyle(fontSize: 12, color: c.expense),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.caption,
    this.tone,
  });

  final String label;
  final String value;
  final String caption;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tone,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            caption,
            maxLines: 2,
            style: TextStyle(fontSize: 10.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// Each loan's share of the total owed — which balance to attack first.
class _OutstandingByLoan extends StatelessWidget {
  const _OutstandingByLoan({required this.loans, required this.total});

  final List<Loan> loans;
  final num total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Outstanding by loan',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            "Each loan's share of the ${Money.compact(total)} total outstanding.",
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 14),
          for (final loan in loans) ...[
            _ShareRow(
              loan: loan,
              share: total > 0 ? (loan.outstanding / total).toDouble() : 0,
            ),
            if (loan != loans.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.loan, required this.share});

  final Loan loan;
  final double share;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                loan.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(share * 100).round()}%',
              style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
            ),
            const SizedBox(width: 10),
            MoneyText(
              loan.outstanding,
              compactAbove: Money.crore,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: share.clamp(0, 1),
            minHeight: 7,
            backgroundColor: c.secondary,
            valueColor: AlwaysStoppedAnimation<Color>(c.expense),
          ),
        ),
      ],
    );
  }
}
