import '../../../core/ui.dart';
import '../../../core/utils/money.dart';
import '../../upi/data/upi_service.dart';
import '../../upi/domain/upi_qr.dart';
import '../../upi/domain/upi_request.dart';
import '../../upi/presentation/upi_scan_sheet.dart';
import '../../upi/domain/upi_result.dart';
import '../../upi/presentation/upi_pay_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../../settings/data/settings_repository.dart';
import '../data/transactions_repository.dart';
import '../domain/transaction.dart';
import 'transactions_providers.dart';
import 'widgets/account_picker.dart';
import 'widgets/amount_field.dart';
import 'widgets/category_picker.dart';
import 'widgets/type_selector.dart';

/// Opens the create/edit transaction sheet and resolves to the saved
/// [Transaction] so the caller can insert or replace it optimistically.
/// Resolves to null when the sheet is dismissed or the row was deleted.
///
/// [initialType] preselects the Income / Expense / Transfer segment on a new
/// row — the FAB's "Transfer" shortcut is the only caller that needs it. It is
/// ignored when [existing] is given, because that row already has a type.
///
/// [initialDate] dates a new row, for callers that already have a day in hand —
/// the Calendar's "Add on this day". Also ignored when [existing] is given.
Future<Transaction?> showTransactionSheet(
  BuildContext context,
  WidgetRef ref, {
  Transaction? existing,
  TransactionType? initialType,
  DateTime? initialDate,
}) {
  // Warm the picker caches so the account/category sheets open with data.
  ref.read(accountsProvider);
  ref.read(categoriesProvider);

  return showModalBottomSheet<Transaction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TransactionFormSheet(
      existing: existing,
      initialType: initialType,
      initialDate: initialDate,
    ),
  );
}

/// The body of [showTransactionSheet]. Renders its own sheet chrome (handle,
/// header, pinned footer) — it is never routed, so it has no Scaffold.
class TransactionFormSheet extends ConsumerStatefulWidget {
  const TransactionFormSheet({
    super.key,
    this.existing,
    this.initialType,
    this.initialDate,
  });

  /// Null creates a transaction (POST); otherwise the sheet prefills and
  /// PATCHes that row.
  final Transaction? existing;

  /// Which segment a *new* row opens on. Defaults to Expense.
  final TransactionType? initialType;

  /// Which day a *new* row is dated. Defaults to today.
  final DateTime? initialDate;

  @override
  ConsumerState<TransactionFormSheet> createState() =>
      _TransactionFormSheetState();
}

class _TransactionFormSheetState extends ConsumerState<TransactionFormSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _payee;
  late final TextEditingController _note;
  final TextEditingController _tagInput = TextEditingController();

  late TransactionType _type;
  late DateTime _date;
  late List<String> _tags;
  late bool _oneoff;

  Account? _account;
  Account? _toAccount;
  Category? _category;

  /// Once the user touches the category, the prefill must not resurrect it.
  bool _categoryTouched = false;

  /// True only while [initState] runs, so hydration assigns without setState.
  bool _hydrating = true;

  bool _busy = false;

  /// 7.7 — the VPA from a scanned QR, carried to the pay sheet so the payment
  /// app opens with the payee and amount already filled in.
  Vpa? _scannedVpa;

  String? _amountError;
  String? _accountError;
  String? _toAccountError;
  String? _categoryError;
  String? _dateError;
  String? _payeeError;
  String? _noteError;
  String? _tagsError;
  String? _formError;

  bool get _isEdit => widget.existing != null;
  bool get _isTransfer => _type == TransactionType.transfer;

  CategoryType get _categoryType => _type == TransactionType.income
      ? CategoryType.income
      : CategoryType.expense;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _type = existing?.type ?? widget.initialType ?? TransactionType.expense;
    _amount = TextEditingController(
      text: existing == null ? '' : _formatAmount(existing.amount),
    );
    _payee = TextEditingController(text: existing?.payee ?? '');
    _note = TextEditingController(text: existing?.note ?? '');
    _tags = [...?existing?.tags];
    _oneoff = existing?.oneoff ?? false;
    _date =
        _calendarDay(existing?.date) ??
        _calendarDay(widget.initialDate) ??
        DateTime.now();
    _account = existing?.account;
    _toAccount = existing?.toAccount;
    _category = existing?.category;

    if (existing != null) {
      // References arrive as bare ids when the API did not populate them, so
      // resolve against the cached lists — now, and again when they land.
      _hydrateAccounts(ref.read(accountsProvider).valueOrNull);
      _hydrateCategory(ref.read(categoriesProvider).valueOrNull);
      ref.listenManual<AsyncValue<List<Account>>>(
        accountsProvider,
        (_, next) => _hydrateAccounts(next.valueOrNull),
      );
      ref.listenManual<AsyncValue<List<Category>>>(
        categoriesProvider,
        (_, next) => _hydrateCategory(next.valueOrNull),
      );
    }

    _hydrating = false;
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  // ── prefill ──────────────────────────────────────────────────────────────

  static String _formatAmount(num amount) =>
      amount % 1 == 0 ? amount.toInt().toString() : '$amount';

  /// The API stores day-precision dates at UTC midnight; read the calendar
  /// fields straight off so a timezone can never shift the day.
  static DateTime? _calendarDay(DateTime? value) =>
      value == null ? null : DateTime(value.year, value.month, value.day);

  static Account? _findAccount(List<Account> accounts, String? id) {
    if (id == null) return null;
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  void _hydrateAccounts(List<Account>? accounts) {
    final existing = widget.existing;
    if (accounts == null || existing == null) return;

    final account = _account ?? _findAccount(accounts, existing.accountId);
    final toAccount =
        _toAccount ?? _findAccount(accounts, existing.toAccountId);
    if (account == _account && toAccount == _toAccount) return;

    void assign() {
      _account = account;
      _toAccount = toAccount;
    }

    if (_hydrating || !mounted) {
      assign();
    } else {
      setState(assign);
    }
  }

  void _hydrateCategory(List<Category>? categories) {
    final existing = widget.existing;
    if (categories == null || existing == null) return;
    if (_categoryTouched || _category != null) return;

    Category? match;
    for (final category in categories) {
      if (category.id == existing.categoryId) {
        match = category;
        break;
      }
    }
    if (match == null) return;

    if (_hydrating || !mounted) {
      _category = match;
    } else {
      setState(() => _category = match);
    }
  }

  // ── editing ──────────────────────────────────────────────────────────────

  void _setType(TransactionType type) {
    setState(() {
      _type = type;
      _accountError = null;
      _toAccountError = null;
      _categoryError = null;
      _formError = null;
      // An expense category is meaningless on an income row, and transfers
      // take no category at all.
      if (_category != null && _category!.type != _categoryType) {
        _category = null;
        _categoryTouched = true;
      }
    });
  }

  void _swapAccounts() {
    setState(() {
      final from = _account;
      _account = _toAccount;
      _toAccount = from;
      _accountError = null;
      _toAccountError = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
      _dateError = null;
    });
  }

  bool _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty || _tags.contains(tag)) return false;
    _tags.add(tag);
    return true;
  }

  /// Commits everything before a comma and leaves the tail being typed.
  void _onTagInputChanged(String value) {
    if (!value.contains(',')) return;
    final parts = value.split(',');
    final tail = parts.removeLast();
    var added = false;
    for (final part in parts) {
      added = _addTag(part) || added;
    }
    _tagInput.value = TextEditingValue(
      text: tail.trimLeft(),
      selection: TextSelection.collapsed(offset: tail.trimLeft().length),
    );
    if (added) setState(() => _tagsError = null);
  }

  void _commitTag() {
    if (!_addTag(_tagInput.text)) return;
    _tagInput.clear();
    setState(() => _tagsError = null);
  }

  // ── save ─────────────────────────────────────────────────────────────────

  /// 7.7 — a scanned QR fills the form.
  ///
  /// The amount is only written when the code fixes one; a shop-counter QR sets
  /// no amount and overwriting what the user already typed would be worse than
  /// leaving it. The note is appended rather than replaced for the same reason.
  void _onScanned(UpiQrPayload payload) {
    setState(() {
      _scannedVpa = payload.payeeVpa;
      _payee.text = payload.payeeName;

      if (payload.hasAmount) {
        _amount.text = payload.amount!.toStringAsFixed(
          payload.amount! % 1 == 0 ? 0 : 2,
        );
        _amountError = null;
      }

      final note = payload.note;
      if (note != null && note.isNotEmpty && _note.text.trim().isEmpty) {
        _note.text = note;
      }
      _payeeError = null;
    });
  }

  /// 7.6 — the payment app came back saying something happened.
  ///
  /// The note gets the UPI reference so the row can be tied to the payment
  /// afterwards; nothing is saved here, because the user still has to press the
  /// form's own Save. The deep-link response is not proof of payment, and this
  /// app does not record money on the strength of it.
  void _onUpiPaid(UpiResult result) {
    final reference = result.transactionId;
    if (reference == null) return;
    final existing = _note.text.trim();
    setState(() {
      _note.text = existing.isEmpty
          ? 'UPI $reference'
          : '$existing · UPI $reference';
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final amount = parseAmount(_amount.text);
    final account = _account;
    final toAccount = _toAccount;

    String? amountError;
    String? accountError;
    String? toAccountError;

    if (amount == null || amount <= 0) {
      amountError = 'Enter an amount greater than zero';
    }
    if (account == null) {
      accountError = _isTransfer
          ? 'Choose the account money leaves'
          : 'Choose an account';
    }
    if (_isTransfer) {
      if (toAccount == null) {
        toAccountError = 'Choose the account money arrives in';
      } else if (account != null && toAccount.id == account.id) {
        toAccountError = 'Pick a different account to transfer into';
      }
    }

    if (amountError != null || accountError != null || toAccountError != null) {
      setState(() {
        _amountError = amountError;
        _accountError = accountError;
        _toAccountError = toAccountError;
        _formError = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _amountError = null;
      _accountError = null;
      _toAccountError = null;
      _categoryError = null;
      _dateError = null;
      _payeeError = null;
      _noteError = null;
      _tagsError = null;
      _formError = null;
    });

    final existing = widget.existing;
    final repository = ref.read(transactionsRepositoryProvider);
    // Taken while the sheet is still mounted: the write has to drop the caches
    // it moved even when the sheet was dismissed mid-flight, and a container
    // outlives the widget that read it.
    final container = ProviderScope.containerOf(context, listen: false);
    // Day precision, at UTC midnight — matching every row the backend seeds.
    final date = DateTime.utc(_date.year, _date.month, _date.day);
    final currency =
        existing?.currency ??
        ref.read(settingsProvider).valueOrNull?.baseCurrency ??
        'INR';
    final categoryId = _isTransfer ? null : _category?.id;
    final toAccountId = _isTransfer ? toAccount!.id : null;

    try {
      final Transaction saved;
      if (existing == null) {
        saved = await repository.create(
          TransactionDraft(
            type: _type,
            amount: amount!,
            accountId: account!.id,
            toAccountId: toAccountId,
            categoryId: categoryId,
            date: date,
            note: _note.text.trim(),
            payee: _payee.text.trim(),
            tags: _tags,
            oneoff: _oneoff,
            currency: currency,
          ),
        );
      } else {
        final patch = <String, dynamic>{
          'type': _type.api,
          'amount': amount,
          'account': account!.id,
          'date': DateX.toApi(date),
          'note': _note.text.trim(),
          'payee': _payee.text.trim(),
          'tags': _tags,
          'oneoff': _oneoff,
          'currency': currency,
        };
        // Only send an explicit null when a reference genuinely has to be
        // cleared — e.g. a transfer that became an expense.
        if (toAccountId != null) {
          patch['toAccount'] = toAccountId;
        } else if (existing.toAccountId != null) {
          patch['toAccount'] = null;
        }
        if (categoryId != null) {
          patch['category'] = categoryId;
        } else if (existing.categoryId != null) {
          patch['category'] = null;
        }
        saved = await repository.update(existing.id, patch);
      }

      invalidateTransactionDerived(container, tags: _tags.isNotEmpty);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      _applyServerErrors(ApiException.from(error));
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete this transaction?',
      message: 'It is removed from your ledger, and can be restored later.',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _formError = null;
    });

    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(transactionsRepositoryProvider).delete(existing.id);
      // Keep the shared list in step: the sheet returns null on delete, so the
      // caller has nothing to reconcile.
      if (container.exists(transactionsListProvider)) {
        container
            .read(transactionsListProvider.notifier)
            .deleteLocal(existing.id);
      }
      invalidateTransactionDerived(container, tags: existing.tags.isNotEmpty);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _applyServerErrors(ApiException.from(error));
    }
  }

  void _applyServerErrors(ApiException error) {
    final amountError = error.fieldError('amount');
    final accountError = error.fieldError('account');
    final toAccountError = error.fieldError('toAccount');
    final categoryError = error.fieldError('category');
    final dateError = error.fieldError('date');
    final payeeError = error.fieldError('payee');
    final noteError = error.fieldError('note');
    final tagsError = error.fieldError('tags');

    final onAField = [
      amountError,
      accountError,
      toAccountError,
      categoryError,
      dateError,
      payeeError,
      noteError,
      tagsError,
    ].any((message) => message != null);

    setState(() {
      _busy = false;
      _amountError = amountError;
      _accountError = accountError;
      _toAccountError = toAccountError;
      _categoryError = categoryError;
      _dateError = dateError;
      _payeeError = payeeError;
      _noteError = noteError;
      _tagsError = tagsError;
      _formError = error.formErrors.isNotEmpty
          ? error.formErrors.first
          : (onAField ? null : error.message);
    });
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = typeTint(c, _type);
    final symbol = ref.watch(currencySymbolProvider);

    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final available = MediaQuery.sizeOf(context).height * 0.94 - insets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: available < 320 ? 320 : available,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(c),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TransactionTypeSelector(value: _type, onChanged: _setType),
                    const SizedBox(height: 18),
                    AmountField(
                      controller: _amount,
                      symbol: symbol,
                      tint: tint,
                      errorText: _amountError,
                      autofocus: !_isEdit,
                      onChanged: (_) {
                        if (_amountError != null) {
                          setState(() => _amountError = null);
                        }
                      },
                    ),
                    // 7.6 — pay the amount you just typed, from here. Expense
                    // only: UPI sends money out, so offering it on an income
                    // row would be a control that cannot do what it says.
                    // Android only — there is no UPI intent contract on iOS.
                    if (_type == TransactionType.expense &&
                        ref.watch(upiServiceProvider).isSupported) ...[
                      const SizedBox(height: 12),
                      // Rebuilt from the controller rather than from form
                      // state: `AmountField.onChanged` only calls setState to
                      // clear an error, so a button reading the amount at build
                      // time would never notice it being typed and would sit
                      // disabled forever. Listening here also keeps every
                      // keystroke from rebuilding the whole sheet.
                      _ScanQrButton(onScanned: _onScanned),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _amount,
                        builder: (context, value, _) => _PayWithUpiButton(
                          amount: parseAmount(value.text),
                          payeeName: _payee.text,
                          note: _note.text,
                          scannedVpa: _scannedVpa,
                          onPaid: _onUpiPaid,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    ..._accountFields(),
                    if (!_isTransfer) ...[
                      const SizedBox(height: 14),
                      CategoryPickerField(
                        type: _categoryType,
                        value: _category,
                        errorText: _categoryError,
                        onChanged: (category) => setState(() {
                          _category = category;
                          _categoryTouched = true;
                          _categoryError = null;
                        }),
                      ),
                    ],
                    const SizedBox(height: 14),
                    PickerField(
                      label: 'Date',
                      hint: 'Pick a date',
                      value: _dateLabel,
                      errorText: _dateError,
                      onTap: _pickDate,
                      leading: Icon(
                        LucideIcons.calendar,
                        size: 18,
                        color: c.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: 'Payee',
                      controller: _payee,
                      hint: _payeeHint,
                      errorText: _payeeError,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: 'Note',
                      controller: _note,
                      hint: 'What was this for?',
                      errorText: _noteError,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    _tagsField(c),
                    const SizedBox(height: 14),
                    _oneoffRow(c),
                    if (_formError != null) ...[
                      const SizedBox(height: 16),
                      _errorBanner(c, _formError!),
                    ],
                    if (_isEdit) ...[
                      const SizedBox(height: 8),
                      Align(
                        child: TextButton.icon(
                          onPressed: _busy ? null : _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: c.destructive,
                          ),
                          icon: const Icon(LucideIcons.trash2, size: 17),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _footer(c),
          ],
        ),
      ),
    );
  }

  Widget _header(AppColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _isEdit ? 'Edit transaction' : 'Add transaction',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          icon: Icon(LucideIcons.x, size: 20, color: c.mutedForeground),
        ),
      ],
    ),
  );

  List<Widget> _accountFields() {
    if (!_isTransfer) {
      return [
        AccountPickerField(
          value: _account,
          errorText: _accountError,
          onChanged: (account) => setState(() {
            _account = account;
            _accountError = null;
          }),
        ),
      ];
    }

    return [
      AccountPickerField(
        label: 'From account',
        hint: 'Money leaves',
        value: _account,
        excludeId: _toAccount?.id,
        errorText: _accountError,
        onChanged: (account) => setState(() {
          _account = account;
          _accountError = null;
        }),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _swapAccounts,
          icon: const Icon(LucideIcons.arrowUpDown, size: 15),
          label: const Text('Swap'),
        ),
      ),
      AccountPickerField(
        label: 'To account',
        hint: 'Money arrives',
        value: _toAccount,
        excludeId: _account?.id,
        errorText: _toAccountError,
        onChanged: (account) => setState(() {
          _toAccount = account;
          _toAccountError = null;
        }),
      ),
    ];
  }

  Widget _tagsField(AppColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppTextField(
        label: 'Tags',
        controller: _tagInput,
        hint: 'Type a tag, then press enter',
        errorText: _tagsError,
        textInputAction: TextInputAction.done,
        onChanged: _onTagInputChanged,
        onSubmitted: (_) => _commitTag(),
        suffix: IconButton(
          onPressed: _commitTag,
          icon: Icon(LucideIcons.plus, size: 18, color: c.mutedForeground),
        ),
      ),
      if (_tags.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _tags)
                Chip(
                  label: Text(tag, style: const TextStyle(fontSize: 13)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  deleteIcon: const Icon(LucideIcons.x, size: 14),
                  onDeleted: () => setState(() => _tags.remove(tag)),
                ),
            ],
          ),
        ),
    ],
  );

  Widget _oneoffRow(AppColors c) => Container(
    padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
    decoration: BoxDecoration(
      color: c.secondary,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      border: Border.all(color: c.border),
    ),
    child: Row(
      children: [
        Icon(LucideIcons.sparkles, size: 18, color: c.mutedForeground),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'One-off',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              Text(
                'Keep it out of spending averages',
                style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
              ),
            ],
          ),
        ),
        Switch(
          value: _oneoff,
          onChanged: (value) => setState(() => _oneoff = value),
        ),
      ],
    ),
  );

  Widget _errorBanner(AppColors c, String message) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: c.destructive.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      border: Border.all(color: c.destructive.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.circleAlert, size: 17, color: c.destructive),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 13.5, color: c.destructive),
          ),
        ),
      ],
    ),
  );

  Widget _footer(AppColors c) => Container(
    // The sheet's own SafeArea is `bottom: false`, so keep the CTA clear of the
    // gesture bar. `paddingOf` is already zero while the keyboard is up.
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    decoration: BoxDecoration(
      color: c.card,
      border: Border(top: BorderSide(color: c.border)),
    ),
    child: AppButton(
      label: _isEdit ? 'Save changes' : 'Add transaction',
      busy: _busy,
      onPressed: _submit,
    ),
  );

  String get _dateLabel {
    final today = DateTime.now();
    final isToday =
        _date.year == today.year &&
        _date.month == today.month &&
        _date.day == today.day;
    return isToday ? 'Today · ${DateX.dayLabel(_date)}' : DateX.dayLabel(_date);
  }

  String get _payeeHint => switch (_type) {
    TransactionType.expense => 'Who did you pay?',
    TransactionType.income => 'Who paid you?',
    TransactionType.transfer => 'Reference (optional)',
  };
}

/// `expense` / `income` / `primary` — the token that colours the whole sheet
/// for the selected type.

/// The entry point into [UpiPaySheet].
///
/// Disabled rather than hidden when the amount is not yet usable: hiding it
/// would make the button appear and disappear as digits are typed, and a
/// control that moves under the thumb is worse than one that is visibly not
/// ready yet.
class _PayWithUpiButton extends StatelessWidget {
  const _PayWithUpiButton({
    required this.amount,
    required this.payeeName,
    required this.note,
    required this.scannedVpa,
    required this.onPaid,
  });

  final num? amount;
  final String payeeName;
  final String note;
  final Vpa? scannedVpa;
  final ValueChanged<UpiResult> onPaid;

  @override
  Widget build(BuildContext context) {
    final ready = amount != null && amount! > 0;
    return AppButton(
      label: ready ? 'Pay ${Money.format(amount!)} with UPI' : 'Pay with UPI',
      icon: LucideIcons.smartphone,
      variant: AppButtonVariant.outlined,
      onPressed: ready
          ? () async {
              final result = await UpiPaySheet.show(
                context,
                amount: amount!,
                payeeName: payeeName,
                note: note.trim().isEmpty ? null : note.trim(),
                initialVpa: scannedVpa,
              );
              if (result != null) onPaid(result);
            }
          : null,
    );
  }
}

/// Opens the QR scanner and hands what it read back to the form.
///
/// Always enabled, unlike the pay button: scanning is how the amount gets
/// filled in for a merchant code, so requiring an amount first would put the
/// steps in the wrong order.
class _ScanQrButton extends StatelessWidget {
  const _ScanQrButton({required this.onScanned});

  final ValueChanged<UpiQrPayload> onScanned;

  @override
  Widget build(BuildContext context) => AppButton(
    label: 'Scan a UPI QR',
    icon: LucideIcons.scanLine,
    variant: AppButtonVariant.outlined,
    onPressed: () async {
      final payload = await UpiScanSheet.show(context);
      if (payload != null) onScanned(payload);
    },
  );
}
