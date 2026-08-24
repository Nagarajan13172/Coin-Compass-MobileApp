import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/state/optimistic.dart';
import '../../../core/api/enums.dart';
import '../../../core/api/write_body.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../../settings/data/settings_repository.dart';
import '../../transactions/presentation/widgets/account_picker.dart';
import '../../transactions/presentation/widgets/amount_field.dart';
import '../../transactions/presentation/widgets/category_picker.dart';
import '../../transactions/presentation/widgets/type_selector.dart';
import '../data/recurring_repository.dart';
import '../domain/recurring_rule.dart';

/// Create / edit a recurring rule: the transaction it posts, plus the cadence
/// it posts on. Pops `true` when the rule list changed.
class RecurringFormSheet extends ConsumerStatefulWidget {
  const RecurringFormSheet({super.key, this.rule});

  /// Null creates a rule; non-null edits that one.
  final RecurringRule? rule;

  static Future<bool?> show(BuildContext context, {RecurringRule? rule}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RecurringFormSheet(rule: rule),
    );
  }

  @override
  ConsumerState<RecurringFormSheet> createState() => _RecurringFormSheetState();
}

class _RecurringFormSheetState extends ConsumerState<RecurringFormSheet> {
  late final RecurringRule? _existing = widget.rule;

  late final TextEditingController _amount = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.amount),
  );
  late final TextEditingController _interval = TextEditingController(
    text: '${_existing?.interval ?? 1}',
  );
  late final TextEditingController _payee = TextEditingController(
    text: _existing?.payee ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: _existing?.note ?? '',
  );

  late TransactionType _type = _existing?.type ?? TransactionType.expense;
  late Frequency _frequency = _existing?.frequency ?? Frequency.monthly;
  late DateTime _startDate =
      _existing?.startDate ?? _existing?.nextRun ?? DateTime.now();
  late DateTime? _endDate = _existing?.endDate;
  late bool _active = _existing?.active ?? true;

  Account? _account;
  Account? _toAccount;
  Category? _category;

  /// Set once the cached lists have hydrated the pickers from the rule's ids.
  bool _hydrated = false;

  /// Once the user touches the category the hydration must not resurrect it.
  bool _categoryTouched = false;

  bool _saving = false;
  String? _formError;
  ApiException? _apiError;
  String? _amountError;
  String? _accountError;
  String? _toAccountError;

  bool get _isEdit => _existing != null;
  // 6.4: a delete pops the sheet on the spot, so there is no deleting state.
  bool get _busy => _saving;
  bool get _isTransfer => _type == TransactionType.transfer;

  CategoryType get _categoryType => _type == TransactionType.income
      ? CategoryType.income
      : CategoryType.expense;

  @override
  void dispose() {
    _amount.dispose();
    _interval.dispose();
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The rule's account and category arrive populated most of the time, but as
  /// bare ids when they don't — so both are looked up once the caches land.
  void _hydratePickers() {
    final existing = _existing;
    if (_hydrated || existing == null) return;

    final accounts = ref.watch(accountsProvider).valueOrNull;
    final categories = ref.watch(categoriesProvider).valueOrNull;
    if (accounts == null || categories == null) return;

    Account? account(String? id) =>
        id == null ? null : accounts.where((a) => a.id == id).firstOrNull;

    _account = existing.account ?? account(existing.accountId);
    _toAccount = account(existing.toAccountId);
    _category =
        existing.category ??
        (existing.categoryId == null
            ? null
            : categories.where((c) => c.id == existing.categoryId).firstOrNull);
    _hydrated = true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    _hydratePickers();
    final symbol = ref.watch(currencySymbolProvider);
    final tint = typeTint(c, _type);

    return FormSheetScaffold(
      title: _isEdit ? 'Edit rule' : 'New recurring rule',
      submitLabel: _isEdit ? 'Save changes' : 'Create rule',
      submitting: _saving,
      deleting: false,
      onSubmit: _submit,
      deleteLabel: _isEdit ? 'Delete rule' : null,
      onDelete: _isEdit ? _delete : null,
      formError: _formError,
      children: [
        TransactionTypeSelector(
          value: _type,
          onChanged: (value) => setState(() {
            _type = value;
            if (_isTransfer) _category = null;
          }),
        ),
        const SizedBox(height: 14),
        AmountField(
          controller: _amount,
          symbol: symbol,
          tint: tint,
          autofocus: !_isEdit,
          errorText: _amountError ?? _apiError?.fieldError('amount'),
          onChanged: (_) {
            if (_amountError != null) setState(() => _amountError = null);
          },
        ),
        const SizedBox(height: 14),
        AccountPickerField(
          value: _account,
          label: _isTransfer ? 'From account' : 'Account',
          errorText: _accountError ?? _apiError?.fieldError('account'),
          onChanged: (account) => setState(() {
            _account = account;
            _accountError = null;
          }),
        ),
        if (_isTransfer) ...[
          const SizedBox(height: 14),
          AccountPickerField(
            value: _toAccount,
            label: 'To account',
            excludeId: _account?.id,
            errorText: _toAccountError ?? _apiError?.fieldError('toAccount'),
            onChanged: (account) => setState(() {
              _toAccount = account;
              _toAccountError = null;
            }),
          ),
        ] else ...[
          const SizedBox(height: 14),
          CategoryPickerField(
            type: _categoryType,
            value: _category,
            errorText: _apiError?.fieldError('category'),
            onChanged: (category) => setState(() {
              _category = category;
              _categoryTouched = true;
            }),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: AppSelect<Frequency>(
                label: 'Repeats',
                value: _frequency,
                enabled: !_busy,
                errorText: _apiError?.fieldError('frequency'),
                items: [
                  for (final frequency in Frequency.values)
                    SelectItem(frequency, frequency.label),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _frequency = value);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: AppTextField(
                label: 'Every',
                controller: _interval,
                hint: '1',
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                errorText: _apiError?.fieldError('interval'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _cadenceCaption(),
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Starts',
          hint: 'Pick a date',
          value: DateX.shortDay(_startDate),
          errorText: _apiError?.fieldError('startDate'),
          onTap: _busy ? null : _pickStartDate,
          leading: Icon(
            LucideIcons.calendar,
            size: 18,
            color: c.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Ends',
          hint: 'Never',
          value: _endDate == null ? null : DateX.shortDay(_endDate!),
          errorText: _apiError?.fieldError('endDate'),
          onTap: _busy ? null : _pickEndDate,
          leading: Icon(
            LucideIcons.calendarOff,
            size: 18,
            color: c.mutedForeground,
          ),
          trailing: _endDate == null
              ? null
              : IconButton(
                  onPressed: () => setState(() => _endDate = null),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  tooltip: 'Clear end date',
                  icon: Icon(LucideIcons.x, size: 17, color: c.mutedForeground),
                ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Payee',
          controller: _payee,
          hint: 'Who it goes to (optional)',
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          errorText: _apiError?.fieldError('payee'),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Note',
          controller: _note,
          hint: 'Optional',
          enabled: !_busy,
          maxLines: 2,
          errorText: _apiError?.fieldError('note'),
        ),
        const SizedBox(height: 16),
        _ActiveSwitch(
          value: _active,
          enabled: !_busy,
          onChanged: (value) => setState(() => _active = value),
        ),
      ],
    );
  }

  /// `Posts every 2 months, starting 04 Sep 2026`
  String _cadenceCaption() {
    final interval = int.tryParse(_interval.text.trim()) ?? 1;
    final unit = switch (_frequency) {
      Frequency.daily => interval == 1 ? 'day' : 'days',
      Frequency.weekly => interval == 1 ? 'week' : 'weeks',
      Frequency.monthly => interval == 1 ? 'month' : 'months',
      Frequency.yearly => interval == 1 ? 'year' : 'years',
    };
    final every = interval <= 1 ? 'every $unit' : 'every $interval $unit';
    return 'Posts $every from ${DateX.shortDay(_startDate)}.';
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _startDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime(now.year + 30, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _endDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _submit() async {
    final amount = parseAmount(_amount.text);
    final account = _account;

    if (amount == null || amount <= 0 || account == null) {
      setState(() {
        _amountError = (amount == null || amount <= 0)
            ? 'Enter an amount'
            : null;
        _accountError = account == null ? 'Pick an account' : null;
      });
      return;
    }
    if (_isTransfer && _toAccount == null) {
      setState(() => _toAccountError = 'Pick a destination');
      return;
    }

    final body = _buildBody(amount, account);
    final existing = _existing;

    // 6.4 — every field on this form is one the client sent. `nextRun` and
    // `upcoming` are the server's schedule projection and *every* field here
    // moves them, so `RecurringRule.predict` nulls both; the tile already omits
    // its "Next …" line when `nextRun` is null, so no schedule the server owns
    // is ever painted from a guess. A create keeps the spinner.
    //
    // `/recurring/:id/run`, `/skip` and `/post-one` are deliberately NOT
    // optimistic — see `RecurringScreen._perform`.
    final interval = int.tryParse(_interval.text.trim()) ?? 1;
    final predicted = existing?.predict(
      type: _type,
      amount: amount,
      frequency: _frequency,
      interval: interval < 1 ? 1 : interval,
      active: _active,
      note: _note.text.trim(),
      payee: _payee.text.trim(),
      accountId: account.id,
      account: account,
      toAccountId: _isTransfer ? _toAccount?.id : null,
      categoryId: _isTransfer ? null : _category?.id,
      category: _isTransfer ? null : _category,
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
    });

    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final repository = ref.read(recurringRepositoryProvider);
      await repository.create(body);
      container.invalidate(recurringRulesFetchProvider);
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
    final rule = _existing;
    if (rule == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete this rule?',
      message:
          'It stops posting from now on. Transactions it already posted are kept.',
    );
    if (!confirmed || !mounted) return;

    // 6.4 — predictable, so the row goes now. No Undo: there is no restore
    // endpoint for a rule. The ConfirmSheet above is the guard.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(recurringRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(recurringWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(rule.id),
            send: () => repository.delete(rule.id),
            settle: () => settleRecurring(container),
            messenger: messenger,
            noun: rule.title,
            successMessage: 'Deleted ${rule.title}',
          ),
    );
  }

  /// Closes the sheet on the predicted row and hands the write over.
  void _runOptimistic(
    RecurringRule existing,
    RecurringRule predicted,
    Map<String, dynamic> body,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(recurringRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(recurringWritesProvider.notifier)
          .run<RecurringRule>(
            paint: PendingWrite.upsert(predicted),
            send: () => repository.update(existing.id, body),
            confirm: (saved) => saved,
            settle: () => settleRecurring(container),
            messenger: messenger,
            noun: predicted.title,
            onFix: () {
              if (!messenger.mounted) return;
              RecurringFormSheet.show(messenger.context, rule: predicted);
            },
          ),
    );
  }

  Map<String, dynamic> _buildBody(num amount, Account account) {
    final interval = int.tryParse(_interval.text.trim()) ?? 1;
    // A transfer has no category; an income/expense rule may have had one
    // cleared, which goes out as null rather than ''.
    final categoryId = _isTransfer
        ? null
        : (_categoryTouched
              ? _category?.id
              : (_category?.id ?? _existing?.categoryId));

    final body = <String, dynamic>{
      'type': _type.api,
      'amount': amount,
      'account': account.id,
      'payee': _payee.text.trim(),
      'note': _note.text.trim(),
      'currency': _existing?.currency ?? 'INR',
      'frequency': _frequency.api,
      'interval': interval < 1 ? 1 : interval,
      'startDate': DateX.toApi(_startDate),
      'active': _active,
    };
    WriteBody.putNullable(
      body,
      'toAccount',
      _isTransfer ? _toAccount?.id : null,
      _existing?.toAccountId,
    );
    WriteBody.putNullable(body, 'category', categoryId, _existing?.categoryId);
    WriteBody.putNullable(
      body,
      'endDate',
      _endDate == null ? null : DateX.toApi(_endDate!),
      _existing?.endDate,
    );
    return body;
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

class _ActiveSwitch extends StatelessWidget {
  const _ActiveSwitch({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  'Paused rules keep their schedule but post nothing.',
                  style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}
