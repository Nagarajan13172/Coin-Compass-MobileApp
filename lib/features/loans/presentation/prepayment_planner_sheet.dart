import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../../core/widgets/money_text.dart';
import '../../transactions/presentation/widgets/amount_field.dart';
import '../domain/loan.dart';
import 'loans_providers.dart';

/// Early-payoff planner. Read-only: it sends nothing, it only does arithmetic.
///
/// Two levers — an extra amount on every EMI, and a one-time lump sum — are
/// compared against leaving the loan alone. The comparison is two runs of the
/// same reducing-balance amortisation ([planPrepayment]), so the payoff dates
/// and the interest figures can never contradict each other.
///
/// The number that decides it is **net benefit**: interest saved less the
/// lender's prepayment charge on the lump sum. It can be negative — a 4% fee on
/// a large prepayment can cost more than the interest it avoids — and the sheet
/// says so in words rather than leaving a minus sign to be noticed.
class PrepaymentPlannerSheet extends StatefulWidget {
  const PrepaymentPlannerSheet({super.key, required this.loan});

  final Loan loan;

  static Future<void> show(BuildContext context, {required Loan loan}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PrepaymentPlannerSheet(loan: loan),
    );
  }

  @override
  State<PrepaymentPlannerSheet> createState() => _PrepaymentPlannerSheetState();
}

class _PrepaymentPlannerSheetState extends State<PrepaymentPlannerSheet> {
  final TextEditingController _extra = TextEditingController();
  final TextEditingController _lump = TextEditingController();
  late final TextEditingController _charge = TextEditingController(
    text: widget.loan.foreclosureChargePct > 0
        ? _plainNumber(widget.loan.foreclosureChargePct)
        : '',
  );

  @override
  void dispose() {
    _extra.dispose();
    _lump.dispose();
    _charge.dispose();
    super.dispose();
  }

  Loan get _loan => widget.loan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final plan = planPrepayment(
      outstanding: _loan.outstanding,
      annualRatePct: _loan.roi,
      emi: _loan.emi,
      extraPerMonth: math.max(0, parseAmount(_extra.text) ?? 0),
      lumpSum: math.max(0, parseAmount(_lump.text) ?? 0),
      chargePct: math.max(0, parseAmount(_charge.text) ?? 0),
    );

    return FormSheetScaffold(
      title: 'Early payoff · ${_loan.name}',
      submitLabel: 'Done',
      // Nothing is sent — the primary action just closes the sheet.
      onSubmit: () => Navigator.of(context).pop(),
      footnote:
          'Reducing-balance estimate. The charge applies to the lump sum only '
          '(lenders may add 18% GST); actual figures depend on your lender.',
      children: [
        Text(
          'Outstanding ${Money.format(_loan.outstanding)} · '
          '${Money.percent(_loan.roi, alreadyScaled: true, decimals: 2)} p.a. · '
          'EMI ${_loan.emi > 0 ? '${Money.format(_loan.emi)}/mo' : 'not set'}',
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        if (!plan.base.feasible) ...[
          _Warning(
            tone: c.expense,
            icon: LucideIcons.triangleAlert,
            text: _loan.emi > 0
                ? "The EMI doesn't cover the monthly interest, so the balance "
                      'never reduces. Increase the EMI (or check the rate) to '
                      'see a payoff estimate.'
                : 'Add a monthly EMI to this loan to see a payoff estimate.',
          ),
          const SizedBox(height: 16),
        ],
        AppTextField(
          label: 'Extra per month',
          controller: _extra,
          hint: '₹0',
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'One-time lump sum',
          controller: _lump,
          hint: '₹0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Prepayment charge (%)',
          controller: _charge,
          hint: '0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter(decimals: 3)],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          "Charged on the lump sum only. Defaults to this loan's rate — "
          'floating-rate home, personal and education loans are usually 0% '
          '(RBI); car, business and fixed-rate loans are typically 2–5%.',
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        ),
        if (plan.base.feasible) ...[
          const SizedBox(height: 18),
          // IntrinsicHeight so the two panels match height inside a ListView,
          // where `stretch` alone would ask for infinite height.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Outcome(
                    title: 'Current',
                    schedule: plan.base,
                    highlight: false,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Outcome(
                    title: plan.hasPlan ? 'With plan' : 'With early payoff',
                    schedule: plan.withPlan,
                    highlight: plan.hasPlan && plan.withPlan.feasible,
                  ),
                ),
              ],
            ),
          ),
          // Match the web's gate exactly. `hasPlan` alone is not enough: the
          // web shows this block only when the plan actually achieves
          // something, so typing an extra ₹5 against a ₹2Cr balance shows
          // nothing there, where mobile used to print a "does not shorten the
          // term" verdict with four zeroes under it.
          if (plan.hasPlan &&
              (plan.monthsSaved > 0 || plan.interestSaved > 0)) ...[
            const SizedBox(height: 12),
            _Verdict(plan: plan),
          ],
        ],
      ],
    );
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

/// One side of the before/after comparison.
class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.title,
    required this.schedule,
    required this.highlight,
  });

  final String title;
  final LoanSchedule schedule;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final eta = payoffEtaLabel(schedule);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? c.income.withValues(alpha: 0.06) : c.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? c.income.withValues(alpha: 0.35) : c.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11.5, color: c.mutedForeground)),
          const SizedBox(height: 4),
          Text(
            schedule.feasible ? formatMonths(schedule.months) : 'Never',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (eta != null) ...[
            const SizedBox(height: 2),
            Text(
              eta,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            schedule.feasible
                ? '~${Money.compact(schedule.totalInterest)} interest'
                : 'Balance never clears',
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// Interest saved, the charge paid to save it, and the net of the two.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.plan});

  final PrepaymentPlan plan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bad = plan.chargeOutweighsSaving;
    final accent = bad ? c.expense : c.income;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _headline,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          _Line(
            label: 'Interest saved',
            amount: plan.interestSaved,
            tone: MoneyTone.income,
            signed: true,
          ),
          if (plan.charge > 0) ...[
            const SizedBox(height: 6),
            _Line(
              label:
                  'Prepayment charge (${Money.percent(plan.chargePct, alreadyScaled: true, decimals: 2)})',
              amount: -plan.charge,
              tone: MoneyTone.expense,
              signed: true,
            ),
          ],
          Divider(height: 18, color: accent.withValues(alpha: 0.25)),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Net benefit',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              MoneyText(
                plan.netBenefit,
                tone: plan.netBenefit < 0 ? MoneyTone.expense : MoneyTone.income,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (bad) ...[
            const SizedBox(height: 8),
            Text(
              'The charge outweighs the interest saved — prepaying this lump '
              'sum costs about ${Money.format(plan.netBenefit.abs())} more '
              'than it saves.',
              style: TextStyle(fontSize: 12.5, color: c.expense),
            ),
          ],
        ],
      ),
    );
  }

  /// "Paying ₹5L now and ₹10,000 more each month clears it 6 yr 2 mo sooner."
  String get _headline {
    final parts = <String>[
      if (plan.lumpSum > 0) '${Money.compact(plan.lumpSum)} now',
      if (plan.extraPerMonth > 0)
        '${Money.compact(plan.extraPerMonth)} more each month',
    ];
    final what = parts.join(' and ');
    if (plan.monthsSaved <= 0) {
      return 'Paying $what does not shorten the term at this rate.';
    }
    return 'Paying $what clears it ${formatMonths(plan.monthsSaved)} sooner.';
  }
}

class _Line extends StatelessWidget {
  const _Line({
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
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
        ),
        MoneyText(
          amount,
          tone: tone,
          signed: signed,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.tone, required this.icon, required this.text});

  final Color tone;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: tone),
            ),
          ),
        ],
      ),
    );
  }
}
