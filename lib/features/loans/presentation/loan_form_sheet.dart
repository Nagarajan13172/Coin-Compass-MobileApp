import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/state/optimistic.dart';
import '../../../core/api/enums.dart';
import '../../../core/api/write_body.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../transactions/presentation/widgets/account_picker.dart'
    show PickerField;
import '../../transactions/presentation/widgets/amount_field.dart';
import '../data/loans_repository.dart';
import '../domain/loan.dart';
import 'loans_providers.dart';

/// Create / edit a borrowing. Pops `true` when the list changed.
///
/// Every control maps to a key `POST /loans` declares — name, outstanding,
/// lender, type, principal, roi, emi, foreclosureChargePct, startDate,
/// endDate, status, note, currency (docs/WRITE_SCHEMAS.md).
///
/// Two fields deliberately do **not** exist here:
///   * `interestPaid` / `chargesPaid` — the server accumulates both from part
///     payments and preclosure and strips them on write. They are shown on the
///     card as read-only figures instead.
///   * `tenure` — not a column. The web app types a tenure in months, derives
///     an end date from it for display, then sends `tenureMonths`, which the
///     server discards; nothing persists. Here the end date *is* the field,
///     because `endDate` is a key the schema actually declares.
class LoanFormSheet extends ConsumerStatefulWidget {
  const LoanFormSheet({super.key, this.loan});

  /// Null creates a loan; non-null edits that one.
  final Loan? loan;

  static Future<bool?> show(BuildContext context, {Loan? loan}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LoanFormSheet(loan: loan),
    );
  }

  @override
  ConsumerState<LoanFormSheet> createState() => _LoanFormSheetState();
}

class _LoanFormSheetState extends ConsumerState<LoanFormSheet> {
  late final Loan? _existing = widget.loan;

  late final TextEditingController _name = TextEditingController(
    text: _existing?.name ?? '',
  );
  late final TextEditingController _lender = TextEditingController(
    text: _existing?.lender ?? '',
  );

  /// Unlike the optional figures, a zero outstanding is meaningful — a closed
  /// loan owes nothing — so it is shown rather than blanked.
  late final TextEditingController _outstanding = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.outstanding),
  );
  late final TextEditingController _principal = _amountController(
    _existing?.principal,
  );
  late final TextEditingController _roi = _amountController(_existing?.roi);
  late final TextEditingController _emi = _amountController(_existing?.emi);
  late final TextEditingController _charge = _amountController(
    _existing?.foreclosureChargePct,
    // A new loan starts at its type's typical fee; an existing one keeps
    // whatever was recorded, including a deliberate 0.
    fallback: _existing == null ? typicalChargePct[LoanType.personal] : null,
  );
  late final TextEditingController _note = TextEditingController(
    text: _existing?.note ?? '',
  );

  late LoanType _type = _existing?.type ?? LoanType.personal;
  late LoanStatus _status = _existing?.status ?? LoanStatus.active;
  late DateTime? _startDate = _existing?.startDate;
  late DateTime? _endDate = _existing?.endDate;

  /// Once the user edits the fee it stops following the type picker.
  bool _chargeTouched = false;

  bool _saving = false;
  String? _formError;
  ApiException? _apiError;
  String? _nameError;
  String? _outstandingError;

  bool get _isEdit => _existing != null;
  // 6.4: a delete pops the sheet on the spot, so there is no deleting state.
  bool get _busy => _saving;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _lender,
      _outstanding,
      _principal,
      _roi,
      _emi,
      _charge,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return FormSheetScaffold(
      title: _isEdit ? 'Edit loan' : 'Add loan',
      submitLabel: _isEdit ? 'Save changes' : 'Add loan',
      submitting: _saving,
      deleting: false,
      onSubmit: _submit,
      deleteLabel: _isEdit ? 'Delete loan' : null,
      onDelete: _isEdit ? _delete : null,
      formError: _formError,
      children: [
        AppTextField(
          label: 'Name',
          controller: _name,
          hint: 'Home loan',
          autofocus: !_isEdit,
          enabled: !_busy,
          errorText: _nameError ?? _apiError?.fieldError('name'),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Lender',
          controller: _lender,
          hint: 'Optional — e.g. HDFC',
          enabled: !_busy,
          errorText: _apiError?.fieldError('lender'),
        ),
        const SizedBox(height: 14),
        AppSelect<LoanType>(
          label: 'Type',
          value: _type,
          enabled: !_busy,
          errorText: _apiError?.fieldError('type'),
          items: [
            for (final type in LoanType.values) SelectItem(type, type.label),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _type = value;
              // Prefill the typical fee while the user has not set their own.
              if (!_isEdit && !_chargeTouched) {
                _charge.text = _plainNumber(typicalChargePct[value] ?? 0);
              }
            });
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Outstanding',
          controller: _outstanding,
          hint: '₹0',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _outstandingError ?? _apiError?.fieldError('outstanding'),
          onChanged: (_) {
            setState(() => _outstandingError = null);
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Original amount',
          controller: _principal,
          hint: 'Optional — what was borrowed',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _apiError?.fieldError('principal'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Interest rate (% p.a.)',
          controller: _roi,
          hint: '8.5',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter(decimals: 3)],
          errorText: _apiError?.fieldError('roi'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Monthly EMI',
          controller: _emi,
          hint: '₹0',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _apiError?.fieldError('emi'),
          onChanged: (_) => setState(() {}),
        ),
        if (_payoffNote != null) ...[
          const SizedBox(height: 8),
          Text(
            _payoffNote!,
            style: TextStyle(
              fontSize: 12.5,
              color: _payoffFeasible ? c.mutedForeground : c.expense,
            ),
          ),
        ],
        const SizedBox(height: 14),
        AppTextField(
          label: 'Prepay / close fee (%)',
          controller: _charge,
          hint: '2',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter(decimals: 3)],
          errorText: _apiError?.fieldError('foreclosureChargePct'),
          onChanged: (_) => _chargeTouched = true,
        ),
        const SizedBox(height: 6),
        Text(
          'Typical for ${_type.label.toLowerCase()}: '
          '${Money.percent(typicalChargePct[_type] ?? 0, alreadyScaled: true, decimals: 0)}. '
          'Used as the default on part payment and preclosure.',
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Started on',
          hint: 'Optional',
          value: _startDate == null ? null : DateX.shortDay(_startDate!),
          errorText: _apiError?.fieldError('startDate'),
          onTap: _busy ? null : () => _pickDate(isStart: true),
          leading: Icon(
            LucideIcons.calendar,
            size: 18,
            color: c.mutedForeground,
          ),
          trailing: _clearButton(
            visible: _startDate != null,
            onClear: () => setState(() => _startDate = null),
          ),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Ends on',
          hint: 'Optional — the scheduled last EMI',
          value: _endDate == null ? null : DateX.shortDay(_endDate!),
          errorText: _apiError?.fieldError('endDate'),
          onTap: _busy ? null : () => _pickDate(isStart: false),
          leading: Icon(
            LucideIcons.calendarCheck,
            size: 18,
            color: c.mutedForeground,
          ),
          trailing: _clearButton(
            visible: _endDate != null,
            onClear: () => setState(() => _endDate = null),
          ),
        ),
        const SizedBox(height: 14),
        AppSelect<LoanStatus>(
          label: 'Status',
          value: _status,
          enabled: !_busy,
          errorText: _apiError?.fieldError('status'),
          items: [
            for (final status in LoanStatus.values)
              SelectItem(status, status.label),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _status = value);
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Note',
          controller: _note,
          hint: 'Optional',
          maxLines: 3,
          enabled: !_busy,
          errorText: _apiError?.fieldError('note'),
        ),
      ],
    );
  }

  Widget? _clearButton({required bool visible, required VoidCallback onClear}) {
    if (!visible) return null;
    final c = context.colors;
    return IconButton(
      onPressed: _busy ? null : onClear,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      tooltip: 'Clear date',
      icon: Icon(LucideIcons.x, size: 17, color: c.mutedForeground),
    );
  }

  /// The live payoff read-out under the EMI field, so a mistyped EMI or rate is
  /// obvious before the loan is saved.
  LoanSchedule? get _preview {
    final outstanding = parseAmount(_outstanding.text) ?? 0;
    final emi = parseAmount(_emi.text) ?? 0;
    if (outstanding <= 0 || emi <= 0) return null;
    return amortiseReducingBalance(
      outstanding: outstanding,
      annualRatePct: parseAmount(_roi.text) ?? 0,
      emi: emi,
    );
  }

  bool get _payoffFeasible => _preview?.feasible ?? true;

  String? get _payoffNote {
    final schedule = _preview;
    if (schedule == null) return null;
    final emi = parseAmount(_emi.text) ?? 0;
    if (!schedule.feasible) {
      return "At ${Money.format(emi)}/mo the EMI doesn't cover the monthly "
          "interest — the balance won't reduce.";
    }
    return 'At ${Money.format(emi)}/mo the balance clears in '
        '${formatMonths(schedule.months)}.';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final current = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 50, 12, 31),
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (isStart) {
        _startDate = day;
      } else {
        _endDate = day;
      }
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final outstanding = parseAmount(_outstanding.text);
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a loan name');
      return;
    }
    if (outstanding == null || outstanding < 0) {
      setState(() => _outstandingError = 'Enter the outstanding amount');
      return;
    }

    final body = _buildBody(name, outstanding);
    final existing = _existing;

    // 6.4 — this is the **form** edit: every field here is one the owner typed,
    // including the outstanding. `interestPaid` and `chargesPaid` are carried
    // across untouched because a form edit cannot move them (the server
    // accumulates them from part-payments and strips them on write).
    //
    // `POST /loans/:id/pay` and `POST /loans/:id/preclose` are a different
    // matter and are deliberately NOT optimistic — see `LoanPaySheet` and
    // `LoanPrecloseSheet`. A create keeps the spinner.
    final predicted = existing?.predict(
      name: name,
      outstanding: outstanding,
      type: _type,
      status: _status,
      principal: parseAmount(_principal.text) ?? 0,
      roi: parseAmount(_roi.text) ?? 0,
      emi: parseAmount(_emi.text) ?? 0,
      foreclosureChargePct: parseAmount(_charge.text) ?? 0,
      note: _note.text.trim(),
      lender: _lender.text.trim().isEmpty ? null : _lender.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
    );
    if (existing != null && predicted != null) {
      _runOptimistic(existing, predicted, body);
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _apiError = null;
      _nameError = null;
      _outstandingError = null;
    });

    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final repository = ref.read(loansRepositoryProvider);
      await repository.create(body);
      container.invalidate(loansFetchProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      final api = ApiException.from(error);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _apiError = api;
        _formError = api.message;
      });
    }
  }

  Future<void> _delete() async {
    final loan = _existing;
    if (loan == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete "${loan.name}"?',
      message:
          'The loan and its payment history are removed. This cannot be undone.',
    );
    if (!confirmed || !mounted) return;

    // 6.4 — predictable, so the row goes now. No Undo: there is no restore
    // endpoint for a loan, and the ConfirmSheet above already says the payment
    // history goes with it.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(loansRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(loansWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(loan.id),
            send: () => repository.delete(loan.id),
            settle: () => settleLoans(container),
            messenger: messenger,
            noun: loan.name,
            successMessage: 'Deleted ${loan.name}',
          ),
    );
  }

  /// Closes the sheet on the predicted row and hands the write over.
  void _runOptimistic(
    Loan existing,
    Loan predicted,
    Map<String, dynamic> body,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(loansRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(loansWritesProvider.notifier)
          .run<Loan>(
            paint: PendingWrite.upsert(predicted),
            send: () => repository.update(existing.id, body),
            confirm: (saved) => saved,
            settle: () => settleLoans(container),
            messenger: messenger,
            noun: predicted.name,
            onFix: () {
              if (!messenger.mounted) return;
              LoanFormSheet.show(messenger.context, loan: predicted);
            },
          ),
    );
  }

  /// Only keys `POST /loans` declares. Guarded by test/write_schema_test.dart,
  /// which reads this method's source.
  Map<String, dynamic> _buildBody(String name, num outstanding) {
    final body = <String, dynamic>{
      'name': name,
      'outstanding': outstanding,
      'type': _type.api,
      'status': _status.api,
      'principal': parseAmount(_principal.text) ?? 0,
      'roi': parseAmount(_roi.text) ?? 0,
      'emi': parseAmount(_emi.text) ?? 0,
      'foreclosureChargePct': parseAmount(_charge.text) ?? 0,
      'currency': _existing?.currency ?? 'INR',
    };
    WriteBody.putText(body, 'lender', _lender.text, _existing?.lender);
    WriteBody.putText(body, 'note', _note.text, _existing?.note);
    WriteBody.putNullable(
      body,
      'startDate',
      _startDate == null ? null : _apiDay(_startDate!),
      _existing?.startDate,
    );
    WriteBody.putNullable(
      body,
      'endDate',
      _endDate == null ? null : _apiDay(_endDate!),
      _existing?.endDate,
    );
    return body;
  }

  /// A calendar day as the API stores it: UTC midnight of that day. A local
  /// midnight run through `toUtc()` in IST would go out as the previous day.
  static String _apiDay(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).toIso8601String();

  static TextEditingController _amountController(num? value, {num? fallback}) {
    final resolved = (value == null || value == 0) ? fallback : value;
    return TextEditingController(
      text: resolved == null ? '' : _plainNumber(resolved),
    );
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}
