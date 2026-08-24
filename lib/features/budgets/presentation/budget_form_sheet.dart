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
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../../transactions/presentation/widgets/account_picker.dart'
    show PickerField;
import '../../transactions/presentation/widgets/amount_field.dart';
import '../../transactions/presentation/widgets/category_picker.dart';
import '../data/budgets_repository.dart';
import '../domain/budget.dart';
import 'budgets_providers.dart';

/// Create / edit a spending limit. Pops `true` when the list changed.
///
/// Every control here maps to a key `POST /budgets` actually declares —
/// amount, category, period, currency, startDate. A budget has no name and no
/// rollover server-side; both were being typed and silently dropped, so they
/// are gone (docs/WRITE_SCHEMAS.md).
class BudgetFormSheet extends ConsumerStatefulWidget {
  const BudgetFormSheet({super.key, this.budget});

  /// Null creates a budget; non-null edits that one.
  final Budget? budget;

  static Future<bool?> show(BuildContext context, {Budget? budget}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BudgetFormSheet(budget: budget),
    );
  }

  @override
  ConsumerState<BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<BudgetFormSheet> {
  late final Budget? _existing = widget.budget;

  late final TextEditingController _amount = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.amount),
  );

  late BudgetPeriod _period = _existing?.period ?? BudgetPeriod.monthly;
  late DateTime? _startDate = _existing?.startDate;

  /// The user's own choice. Until they make one the field shows the budget's
  /// existing category, which arrives as a bare id whenever `/budgets` did not
  /// populate it — so it is looked up in the cached category list.
  Category? _picked;
  bool _categoryTouched = false;

  bool _saving = false;
  String? _formError;
  ApiException? _apiError;
  String? _amountError;

  bool get _isEdit => _existing != null;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final category = _categoryFor(ref.watch(categoriesProvider).valueOrNull);

    return FormSheetScaffold(
      title: _isEdit ? 'Edit budget' : 'New budget',
      submitLabel: _isEdit ? 'Save changes' : 'Create budget',
      submitting: _saving,
      deleting: false,
      onSubmit: _submit,
      deleteLabel: _isEdit ? 'Delete budget' : null,
      onDelete: _isEdit ? _delete : null,
      formError: _formError,
      children: [
        AppTextField(
          label: 'Limit',
          controller: _amount,
          hint: '₹0',
          autofocus: !_isEdit,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _amountError ?? _apiError?.fieldError('amount'),
          onChanged: (_) {
            if (_amountError != null) setState(() => _amountError = null);
          },
        ),
        const SizedBox(height: 14),
        CategoryPickerField(
          type: CategoryType.expense,
          value: category,
          label: 'Category',
          hint: 'All spending',
          errorText: _apiError?.fieldError('category'),
          onChanged: (picked) => setState(() {
            _picked = picked;
            _categoryTouched = true;
          }),
        ),
        const SizedBox(height: 6),
        Text(
          category == null
              ? 'Caps every expense in the period.'
              : 'Caps spending in ${category.name}.',
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 14),
        AppSelect<BudgetPeriod>(
          label: 'Period',
          value: _period,
          enabled: !_busy,
          errorText: _apiError?.fieldError('period'),
          items: [
            for (final period in BudgetPeriod.values)
              SelectItem(period, period.label),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _period = value);
          },
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Starts on',
          hint: 'Optional — defaults to the calendar period',
          value: _startDate == null ? null : DateX.shortDay(_startDate!),
          errorText: _apiError?.fieldError('startDate'),
          onTap: _busy ? null : _pickStartDate,
          leading: Icon(
            LucideIcons.calendar,
            size: 18,
            color: c.mutedForeground,
          ),
          trailing: _startDate == null
              ? null
              : IconButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _startDate = null),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  tooltip: 'Clear date',
                  icon: Icon(LucideIcons.x, size: 17, color: c.mutedForeground),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          _startNote,
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        ),
      ],
    );
  }

  // 6.4: a delete pops the sheet on the spot, so there is no deleting state.
  bool get _busy => _saving;

  /// The server anchors each window to `startDate`, so this is what makes the
  /// period concrete: a salary month that runs from the 5th, a week that runs
  /// Thu–Wed. Left empty the server falls back to the calendar period.
  String get _startNote {
    final start = _startDate;
    if (start == null) {
      return 'Each ${_period.label.toLowerCase()} window follows the calendar.';
    }
    return 'Windows are counted from ${DateX.shortDay(start)}.';
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _startDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  /// The category the field is showing: the user's pick once they have touched
  /// it, otherwise the budget's own — resolved through [categories] when the
  /// payload carried only an id.
  Category? _categoryFor(List<Category>? categories) {
    if (_categoryTouched) return _picked;
    final existing = _existing;
    if (existing == null) return null;
    return existing.category ??
        categories
            ?.where((category) => category.id == existing.categoryId)
            .firstOrNull;
  }

  Future<void> _submit() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter a limit');
      return;
    }

    final body = _buildBody(amount);
    final existing = _existing;
    final category = _categoryFor(ref.read(categoriesProvider).valueOrNull);

    // 6.4 — the client knows the new limit, category, period and start date
    // exactly. What it does *not* know is `spent`/`remaining`/`percent`/`over`,
    // which the server recomputes — so `Budget.predict` nulls all four and the
    // tile re-derives the bar from the spend the app already holds. A create
    // keeps the spinner (server-assigned id).
    final predicted = existing?.predict(
      amount: amount,
      period: _period,
      categoryId: category?.id,
      category: category,
      startDate: _startDate,
    );
    if (existing != null && predicted != null) {
      _runOptimistic(existing, predicted, body);
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _apiError = null;
      _amountError = null;
    });

    try {
      final repository = ref.read(budgetsRepositoryProvider);
      await repository.create(body);
      _invalidate();
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
    final budget = _existing;
    if (budget == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete this budget?',
      message: 'The limit is removed. Your transactions are untouched.',
    );
    if (!confirmed || !mounted) return;

    // 6.4 — predictable, so the row goes now. No Undo: `/budgets/:id` has no
    // restore counterpart. The ConfirmSheet above is the guard.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(budgetsRepositoryProvider);
    final settle = _settleFor(container);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(budgetsWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(budget.id),
            send: () => repository.delete(budget.id),
            settle: settle,
            messenger: messenger,
            noun: 'budget',
            successMessage: 'Deleted budget',
          ),
    );
  }

  /// Closes the sheet on the predicted row and hands the write over.
  void _runOptimistic(
    Budget existing,
    Budget predicted,
    Map<String, dynamic> body,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(budgetsRepositoryProvider);
    final settle = _settleFor(container);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(budgetsWritesProvider.notifier)
          .run<Budget>(
            paint: PendingWrite.upsert(predicted),
            send: () => repository.update(existing.id, body),
            confirm: (saved) => saved,
            settle: settle,
            messenger: messenger,
            noun: predicted.category?.name ?? 'budget',
            onFix: () {
              if (!messenger.mounted) return;
              BudgetFormSheet.show(messenger.context, budget: predicted);
            },
          ),
    );
  }

  /// The settle step: the list, plus the spend windows the limit's own tile
  /// reads — a changed limit or period moves the totals card as well as the
  /// row. Built before the pop, so it does not read `_period` off a dead State.
  Future<void> Function() _settleFor(ProviderContainer container) {
    final period = _period;
    final previous = _existing?.period;
    return () => settleFetch(
      container,
      budgetsFetchProvider,
      also: [
        budgetSpendProvider(period),
        if (previous != null && previous != period)
          budgetSpendProvider(previous),
      ],
    );
  }

  /// Drops the list and the spend windows — a new limit changes the totals card
  /// as well as the row.
  void _invalidate() {
    ref.invalidate(budgetsFetchProvider);
    ref.invalidate(budgetSpendProvider(_period));
    final previous = _existing?.period;
    if (previous != null && previous != _period) {
      ref.invalidate(budgetSpendProvider(previous));
    }
  }

  Map<String, dynamic> _buildBody(num amount) {
    final category = _categoryFor(ref.read(categoriesProvider).valueOrNull);
    final body = <String, dynamic>{
      'amount': amount,
      'period': _period.api,
      'currency': _existing?.currency ?? 'INR',
    };
    // Null clears a category that was set before; '' would fail the id check.
    WriteBody.putNullable(
      body,
      'category',
      category?.id,
      _existing?.categoryId,
    );
    WriteBody.putNullable(
      body,
      'startDate',
      _startDate == null ? null : DateX.toApi(_startDate!),
      _existing?.startDate,
    );
    return body;
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}
