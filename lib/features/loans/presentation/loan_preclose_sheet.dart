import 'dart:math' as math;

import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../../core/widgets/money_text.dart';
import '../../transactions/presentation/widgets/amount_field.dart';
import '../data/loans_repository.dart';
import '../domain/loan.dart';
import 'loans_providers.dart';

/// Settle the whole balance and close the loan —
/// `POST /loans/:id/preclose {chargePct}`.
///
/// **This is irreversible and immediate.** The server zeroes `outstanding` and
/// flips `status` to `closed`; there is no dry run and no undo. During Phase 0
/// recon an empty-body probe of this endpoint closed the owner's live
/// ₹2,00,00,000 home loan, which is why the flow here is deliberately hard to
/// trigger by accident:
///
///   1. the sheet is only reachable from an explicit "Preclose" action;
///   2. it renders the full settlement — balance + foreclosure charge — before
///      anything is sent;
///   3. the submit button opens a destructive [ConfirmSheet] naming the loan
///      and the exact amount. Only that second tap calls the API.
class LoanPrecloseSheet extends ConsumerStatefulWidget {
  const LoanPrecloseSheet({super.key, required this.loan});

  final Loan loan;

  static Future<bool?> show(BuildContext context, {required Loan loan}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LoanPrecloseSheet(loan: loan),
    );
  }

  @override
  ConsumerState<LoanPrecloseSheet> createState() => _LoanPrecloseSheetState();
}

class _LoanPrecloseSheetState extends ConsumerState<LoanPrecloseSheet> {
  late final TextEditingController _charge = TextEditingController(
    text: widget.loan.foreclosureChargePct > 0
        ? _plainNumber(widget.loan.foreclosureChargePct)
        : '',
  );

  bool _saving = false;
  String? _formError;

  @override
  void dispose() {
    _charge.dispose();
    super.dispose();
  }

  Loan get _loan => widget.loan;

  num get _chargePct => math.max(0, parseAmount(_charge.text) ?? 0);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final outstanding = _loan.outstanding;
    final charge = prepaymentCharge(outstanding, _chargePct);
    final payable = outstanding + charge;

    // What closing early actually avoids, on the same amortisation the card
    // and the planner use.
    final schedule = scheduleFor(_loan);
    final interestAvoided = schedule.feasible ? schedule.totalInterest : null;

    return FormSheetScaffold(
      title: 'Preclose · ${_loan.name}',
      submitLabel: 'Preclose loan',
      submitting: _saving,
      onSubmit: _confirmThenPreclose,
      formError: _formError,
      footnote:
          'Closing is immediate and cannot be undone from the app. You will be '
          'asked to confirm.',
      children: [
        Text(
          'Pay off the full balance now and close the loan. Banks usually '
          'charge a foreclosure fee.',
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Preclosure charge (%)',
          controller: _charge,
          hint: '0',
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter(decimals: 3)],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          "Defaults to this loan's recorded charge. Lenders may add GST on top.",
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        _Settlement(
          outstanding: outstanding,
          chargePct: _chargePct,
          charge: charge,
          payable: payable,
        ),
        if (interestAvoided != null && interestAvoided > 0) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 15, color: c.mutedForeground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Closing now avoids about ${Money.format(interestAvoided)} '
                  'of future interest'
                  '${schedule.months > 0 ? ' over ${formatMonths(schedule.months)}' : ''}.',
                  style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The second gate. Nothing reaches the API until this returns true.
  /// **Deliberately synchronous (6.4), and permanently so.** The foreclosure
  /// charge is computed server-side from the charge percentage against the
  /// server's own outstanding, and this is the endpoint that once closed the
  /// owner's real loan. It keeps its confirmation, its spinner and its full
  /// refetch, and predicts nothing. See lib/core/state/optimistic.dart.
  Future<void> _confirmThenPreclose() async {
    final outstanding = _loan.outstanding;
    final charge = prepaymentCharge(outstanding, _chargePct);
    final payable = outstanding + charge;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Preclose "${_loan.name}"?',
      message:
          'This settles ${Money.format(payable)} '
          '(${Money.format(outstanding)} balance'
          '${charge > 0 ? ' + ${Money.format(charge)} charge' : ''}) '
          'and marks the loan closed immediately. It cannot be undone.',
      confirmLabel: 'Preclose loan',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      await ref
          .read(loansRepositoryProvider)
          .preclose(id: _loan.id, chargePct: _chargePct);
      ref.invalidate(loansFetchProvider);
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

/// Balance + charge = what settles the loan today, in destructive tone so it
/// never reads like a routine instalment.
class _Settlement extends StatelessWidget {
  const _Settlement({
    required this.outstanding,
    required this.chargePct,
    required this.charge,
    required this.payable,
  });

  final num outstanding;
  final num chargePct;
  final num charge;
  final num payable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.destructive.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.destructive.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          _Line(label: 'Outstanding', amount: outstanding),
          const SizedBox(height: 6),
          _Line(
            label:
                'Charge (${Money.percent(chargePct, alreadyScaled: true, decimals: 2)})',
            amount: charge,
          ),
          Divider(height: 18, color: c.destructive.withValues(alpha: 0.25)),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total payable',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              MoneyText(
                payable,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.destructive,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.amount});

  final String label;
  final num amount;

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
        MoneyText(amount, style: const TextStyle(fontSize: 13.5)),
      ],
    );
  }
}
