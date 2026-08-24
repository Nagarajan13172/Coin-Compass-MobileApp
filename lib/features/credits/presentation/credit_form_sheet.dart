import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/enums.dart';
import '../../../core/api/write_body.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../../people/data/people_repository.dart';
import '../../people/presentation/widgets/person_picker.dart';
import '../../transactions/presentation/widgets/account_picker.dart'
    show AccountPickerField, PickerField;
import '../../transactions/presentation/widgets/amount_field.dart';
import '../../transactions/presentation/widgets/category_picker.dart';
import '../data/credits_repository.dart';
import '../domain/credit.dart';

/// Create / edit a credit — money given to or taken from someone.
/// Pops `true` when the list changed.
class CreditFormSheet extends ConsumerStatefulWidget {
  const CreditFormSheet({super.key, this.credit});

  /// Null creates a credit; non-null edits that one.
  final Credit? credit;

  static Future<bool?> show(BuildContext context, {Credit? credit}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CreditFormSheet(credit: credit),
    );
  }

  @override
  ConsumerState<CreditFormSheet> createState() => _CreditFormSheetState();
}

class _CreditFormSheetState extends ConsumerState<CreditFormSheet> {
  late final Credit? _existing = widget.credit;

  late final TextEditingController _amount = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.amount),
  );
  late final TextEditingController _note = TextEditingController(
    text: _existing?.note ?? '',
  );

  late CreditDirection _direction =
      _existing?.direction ?? CreditDirection.given;
  late DateTime _date = _existing?.date ?? DateTime.now();
  late String? _accountId = _existing?.accountId;
  late String? _categoryId = _existing?.categoryId;
  late PersonRef? _person = _existing == null
      ? null
      : PersonRef(id: _existing.personId, name: _existing.displayName);

  bool _saving = false;
  bool _deleting = false;
  String? _formError;
  ApiException? _apiError;
  String? _amountError;
  String? _personError;

  bool get _isEdit => _existing != null;
  bool get _busy => _saving || _deleting;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // References are stored as ids and resolved against the lists the pickers
    // already load, so an edit shows the right row as soon as they land.
    final account = _findAccount(
      ref.watch(accountsProvider).valueOrNull,
      _accountId,
    );
    final category = _findCategory(
      ref.watch(categoriesProvider).valueOrNull,
      _categoryId,
    );

    return FormSheetScaffold(
      title: _isEdit ? 'Edit credit' : 'Add credit',
      submitLabel: _isEdit ? 'Save changes' : 'Add credit',
      submitting: _saving,
      deleting: _deleting,
      onSubmit: _submit,
      deleteLabel: _isEdit ? 'Delete credit' : null,
      onDelete: _isEdit ? _delete : null,
      formError: _formError,
      children: [
        PersonPickerField(
          value: _person,
          errorText: _personError ?? _apiError?.fieldError('person'),
          onChanged: (person) => setState(() {
            _person = person;
            _personError = null;
          }),
        ),
        const SizedBox(height: 14),
        AppSelect<CreditDirection>(
          label: 'Direction',
          value: _direction,
          enabled: !_busy,
          errorText: _apiError?.fieldError('direction'),
          items: [
            for (final direction in CreditDirection.values)
              SelectItem(direction, _directionLabel(direction)),
          ],
          onChanged: (value) {
            if (value == null) return;
            _setDirection(value);
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Amount',
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
        PickerField(
          label: 'Date',
          hint: 'Pick a date',
          value: DateX.shortDay(_date),
          errorText: _apiError?.fieldError('date'),
          onTap: _busy ? null : _pickDate,
          leading: Icon(
            LucideIcons.calendar,
            size: 18,
            color: c.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        AccountPickerField(
          value: account,
          hint: 'Optional',
          errorText: _apiError?.fieldError('account'),
          onChanged: (picked) => setState(() => _accountId = picked.id),
        ),
        const SizedBox(height: 14),
        CategoryPickerField(
          type: _categoryType,
          value: category,
          errorText: _apiError?.fieldError('category'),
          onChanged: (picked) => setState(() => _categoryId = picked?.id),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Note',
          controller: _note,
          hint: 'What it was for (optional)',
          enabled: !_busy,
          maxLines: 2,
          errorText: _apiError?.fieldError('note'),
        ),
      ],
    );
  }

  /// The API's four directions read as jargon on their own, so each one says
  /// which way the money actually went.
  static String _directionLabel(CreditDirection direction) =>
      switch (direction) {
        CreditDirection.given => 'Given — you lent it out',
        CreditDirection.received => 'Received — it came back to you',
        CreditDirection.borrowed => 'Borrowed — you took it',
        CreditDirection.repaid => 'Repaid — you paid it back',
      };

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  /// Money leaving your hands (given, repaid) is categorised as an expense,
  /// money arriving (received, borrowed) as income — so a direction change can
  /// invalidate the chosen category.
  static CategoryType _categoryTypeFor(CreditDirection direction) =>
      direction.isOutgoing ? CategoryType.expense : CategoryType.income;

  CategoryType get _categoryType => _categoryTypeFor(_direction);

  void _setDirection(CreditDirection value) {
    final category = _findCategory(
      ref.read(categoriesProvider).valueOrNull,
      _categoryId,
    );
    setState(() {
      _direction = value;
      if (category != null && category.type != _categoryTypeFor(value)) {
        _categoryId = null;
      }
    });
  }

  static Account? _findAccount(List<Account>? accounts, String? id) {
    if (accounts == null || id == null) return null;
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  static Category? _findCategory(List<Category>? categories, String? id) {
    if (categories == null || id == null) return null;
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Future<void> _submit() async {
    final amount = parseAmount(_amount.text);
    final person = _person;

    if (amount == null || amount <= 0 || person == null) {
      setState(() {
        _amountError = (amount == null || amount <= 0)
            ? 'Enter an amount'
            : null;
        _personError = person == null ? 'Choose a person' : null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _apiError = null;
    });

    try {
      final repository = ref.read(creditsRepositoryProvider);
      final body = _buildBody(amount, person);
      if (_isEdit) {
        await repository.update(_existing!.id, body);
      } else {
        await repository.create(body);
      }
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
    final credit = _existing;
    if (credit == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete this credit?',
      message:
          'The entry is removed from your ledger with ${credit.displayName}.',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _deleting = true;
      _formError = null;
      _apiError = null;
    });

    try {
      await ref.read(creditsRepositoryProvider).delete(credit.id);
      _invalidate();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      final api = ApiException.from(error);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _apiError = api;
        _formError = api.message;
      });
    }
  }

  /// A credit can name someone new, which the backend adds to the address book
  /// — so the people list is dropped along with the credits.
  void _invalidate() {
    ref
      ..invalidate(creditsProvider)
      ..invalidate(peopleProvider);
  }

  Map<String, dynamic> _buildBody(num amount, PersonRef person) {
    final body = <String, dynamic>{
      'person': person.wireValue,
      'direction': _direction.api,
      'amount': amount,
      'date': DateX.toApi(_date),
    };
    WriteBody.putNullable(body, 'account', _accountId, _existing?.accountId);
    WriteBody.putNullable(body, 'category', _categoryId, _existing?.categoryId);
    WriteBody.putText(body, 'note', _note.text, _existing?.note);
    return body;
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}
