import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../../core/widgets/money_text.dart';
import '../../transactions/presentation/widgets/amount_field.dart';
import '../data/loans_repository.dart';
import '../domain/loan.dart';
import 'loans_providers.dart';

/// A part payment against a loan — `POST /loans/:id/pay {amount, chargePct}`.
///
/// The body is assembled inside [LoansRepository.pay], not here, so this sheet
/// cannot widen it. What this screen adds is the **effect**: before confirming,
/// the borrower sees the new balance, the fee, what leaves their pocket today,
/// and — the part a bank statement never tells you — how much interest the
/// payment avoids and how many months it takes off the term.
class LoanPaySheet extends ConsumerStatefulWidget {
  const LoanPaySheet({super.key, required this.loan});

  final Loan loan;

  static Future<bool?> show(BuildContext context, {required Loan loan}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LoanPaySheet(loan: loan),
    );
  }

  @override
  ConsumerState<LoanPaySheet> createState() => _LoanPaySheetState();
}

class _LoanPaySheetState extends ConsumerState<LoanPaySheet> {
  final TextEditingController _amount = TextEditingController();
  late final TextEditingController _charge = TextEditingController(
    text: widget.loan.foreclosureChargePct > 0
        ? _plainNumber(widget.loan.foreclosureChargePct)
        : '',
  );

  bool _saving = false;
  String? _formError;
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    _charge.dispose();
    super.dispose();
  }

  Loan get _loan => widget.loan;

  /// What the payment actually removes from the balance — never more than is
  /// owed, so an over-typed amount does not promise an impossible saving.
  num get _applied =>
      math.min(_loan.outstanding, math.max(0, parseAmount(_amount.text) ?? 0));

  num get _chargePct => math.max(0, parseAmount(_charge.text) ?? 0);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final applied = _applied;
    final charge = prepaymentCharge(applied, _chargePct);
    final after = math.max(0, _loan.outstanding - applied);

    // Same amortisation on both sides, so "months shaved" and the payoff dates
    // elsewhere in the app can never disagree.
    final before = scheduleFor(_loan);
    final plan = planPrepayment(
      outstanding: _loan.outstanding,
      annualRatePct: _loan.roi,
      emi: _loan.emi,
      lumpSum: applied,
      chargePct: _chargePct,
    );

    return FormSheetScaffold(
      title: 'Part payment · ${_loan.name}',
      // Compact, not full: 'Pay ₹2,00,00,000' overflows the button at 360dp.
      submitLabel: applied > 0
          ? 'Pay ${Money.compact(applied + charge)}'
          : 'Pay',
      submitting: _saving,
      onSubmit: _submit,
      formError: _formError,
      footnote:
          'Reduces the balance immediately. It does not post a transaction to '
          'an account.',
      children: [
        Text(
          'Outstanding ${Money.format(_loan.outstanding)}'
          '${_loan.emi > 0 ? ' · EMI ${Money.format(_loan.emi)}/mo' : ''}',
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Amount to pay',
          controller: _amount,
          hint: '₹0',
          autofocus: true,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _amountError,
          onChanged: (_) => setState(() => _amountError = null),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amount in _suggestions)
              ActionChip(
                label: Text(Money.compact(amount)),
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _amount.text = _plainNumber(amount);
                        _amountError = null;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Prepay charge (%)',
          controller: _charge,
          hint: '0',
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          "Defaults to this loan's recorded charge. Lenders may add GST on top.",
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        ),
        if (applied > 0) ...[
          const SizedBox(height: 16),
          _Effect(
            rows: [
              _Row('Reduces balance by', applied),
              _Row(
                'Prepayment charge (${Money.percent(_chargePct, alreadyScaled: true, decimals: 2)})',
                charge,
              ),
            ],
            totalLabel: 'Total you pay',
            total: applied + charge,
            footer: after <= 0
                ? 'This clears the balance — the loan closes.'
                : 'Outstanding after: ${Money.format(after)}',
          ),
          if (before.feasible &&
              (plan.interestSaved > 0 || plan.monthsSaved > 0)) ...[
            const SizedBox(height: 10),
            _Saving(
              interestSaved: plan.interestSaved,
              monthsSaved: plan.monthsSaved,
              netBenefit: plan.netBenefit,
              charged: charge > 0,
            ),
          ],
        ],
      ],
    );
  }

  /// A month's EMI and the whole balance — the two amounts people actually pay.
  List<num> get _suggestions => <num>{
    if (_loan.emi > 0 && _loan.emi < _loan.outstanding) _loan.emi,
    if (_loan.outstanding > 0) _loan.outstanding,
  }.toList();

  Future<void> _submit() async {
    // Submit `_applied`, not the raw text. The whole sheet previews the
    // clamped amount — balance after, months shaved, interest saved — so
    // sending the raw value would post a payment the user was never shown.
    final amount = _applied;
    if (amount <= 0) {
      setState(() => _amountError = 'Enter an amount greater than 0');
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      await ref
          .read(loansRepositoryProvider)
          .pay(id: _loan.id, amount: amount, chargePct: _chargePct);
      ref.invalidate(loansProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      final api = ApiException.from(error);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = api.message;
      });
    }
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

/// A labelled amount inside the effect panel.
class _Row {
  const _Row(this.label, this.amount);
  final String label;
  final num amount;
}

/// The bordered "here is what happens" panel both action sheets share.
class _Effect extends StatelessWidget {
  const _Effect({
    required this.rows,
    required this.totalLabel,
    required this.total,
    this.footer,
  });

  final List<_Row> rows;
  final String totalLabel;
  final num total;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          for (final row in rows) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    style: TextStyle(fontSize: 13, color: c.mutedForeground),
                  ),
                ),
                MoneyText(
                  row.amount,
                  style: const TextStyle(fontSize: 13.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Divider(height: 12, color: c.border),
          Row(
            children: [
              Expanded(
                child: Text(
                  totalLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              MoneyText(
                total,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                footer!,
                style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the payment buys: interest avoided and months off the term.
class _Saving extends StatelessWidget {
  const _Saving({
    required this.interestSaved,
    required this.monthsSaved,
    required this.netBenefit,
    required this.charged,
  });

  final num interestSaved;
  final int monthsSaved;
  final num netBenefit;
  final bool charged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final worthIt = netBenefit > 0;
    final accent = worthIt ? c.income : c.expense;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Interest saved',
                  style: TextStyle(fontSize: 13, color: c.mutedForeground),
                ),
              ),
              MoneyText(
                interestSaved,
                tone: MoneyTone.income,
                signed: true,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (monthsSaved > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Clears ${formatMonths(monthsSaved)} sooner.',
              style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
            ),
          ],
          if (charged) ...[
            const SizedBox(height: 8),
            Text(
              worthIt
                  ? 'Net benefit after the charge: ${Money.format(netBenefit)}.'
                  : 'The charge outweighs the interest saved — this payment '
                        'costs ${Money.format(netBenefit.abs())} more than it saves.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: worthIt ? c.mutedForeground : c.expense,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
