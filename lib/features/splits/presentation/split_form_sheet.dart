// Flutter's animation library exports a `Split` curve class, which would
// collide with the domain model of the same name.
import 'package:flutter/material.dart' hide Split;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/enums.dart';
import '../../../core/api/write_body.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../../people/data/people_repository.dart';
import '../../people/domain/person.dart';
import '../../people/presentation/widgets/participants_picker.dart';
import '../../transactions/presentation/widgets/account_picker.dart'
    show AccountPickerField, PickerField;
import '../../transactions/presentation/widgets/amount_field.dart';
import '../../transactions/presentation/widgets/category_picker.dart';
import '../data/splits_repository.dart';
import '../domain/split.dart';

/// Create / edit a shared expense. Pops `true` when the list changed.
class SplitFormSheet extends ConsumerStatefulWidget {
  const SplitFormSheet({super.key, this.split});

  /// Null creates a split; non-null edits that one.
  final Split? split;

  static Future<bool?> show(BuildContext context, {Split? split}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SplitFormSheet(split: split),
    );
  }

  @override
  ConsumerState<SplitFormSheet> createState() => _SplitFormSheetState();
}

class _SplitFormSheetState extends ConsumerState<SplitFormSheet> {
  late final Split? _existing = widget.split;

  late final TextEditingController _description = TextEditingController(
    text: _existing?.description ?? '',
  );
  late final TextEditingController _total = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.totalAmount),
  );
  late final TextEditingController _yourShare = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.yourShare),
  );
  late final TextEditingController _note = TextEditingController(
    text: _existing?.note ?? '',
  );

  late DateTime _date = _existing?.date ?? DateTime.now();
  late String? _categoryId = _existing?.categoryId;
  late String? _accountId = _existing?.accountId;
  late List<String> _participantIds = [...?_existing?.participantIds];

  bool _saving = false;
  bool _deleting = false;
  String? _formError;
  ApiException? _apiError;
  String? _descriptionError;
  String? _totalError;
  String? _shareError;

  bool get _isEdit => _existing != null;
  bool get _busy => _saving || _deleting;

  @override
  void dispose() {
    _description.dispose();
    _total.dispose();
    _yourShare.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final people = ref.watch(peopleProvider).valueOrNull ?? const <Person>[];
    final names = {for (final person in people) person.id: person.name};
    // References are stored as ids and resolved against the lists the pickers
    // already load, so an edit shows the right row as soon as they land.
    final category = _findCategory(
      ref.watch(categoriesProvider).valueOrNull,
      _categoryId,
    );
    final account = _findAccount(
      ref.watch(accountsProvider).valueOrNull,
      _accountId,
    );

    return FormSheetScaffold(
      title: _isEdit ? 'Edit split' : 'Split a bill',
      submitLabel: _isEdit ? 'Save changes' : 'Create split',
      submitting: _saving,
      deleting: _deleting,
      onSubmit: _submit,
      deleteLabel: _isEdit ? 'Delete split' : null,
      onDelete: _isEdit ? _delete : null,
      formError: _formError,
      children: [
        AppTextField(
          label: 'What was it?',
          controller: _description,
          hint: 'e.g. Dinner at Anjappar',
          autofocus: !_isEdit,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          errorText: _descriptionError ?? _apiError?.fieldError('description'),
          onChanged: (_) {
            if (_descriptionError != null) {
              setState(() => _descriptionError = null);
            }
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Total amount',
          controller: _total,
          hint: '₹0',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _totalError ?? _apiError?.fieldError('totalAmount'),
          onChanged: (_) {
            if (_totalError != null) setState(() => _totalError = null);
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Your share',
          controller: _yourShare,
          hint: '₹0',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _shareError ?? _apiError?.fieldError('yourShare'),
          onChanged: (_) {
            if (_shareError != null) setState(() => _shareError = null);
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _splitEvenly,
            icon: const Icon(LucideIcons.equal, size: 16),
            label: Text(
              'Split evenly (${_participantIds.length + 1} ways)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
            ),
          ),
        ),
        const SizedBox(height: 6),
        PickerField(
          label: 'Split with',
          hint: 'Choose people',
          value: _participantIds.isEmpty
              ? null
              : _participantIds.map((id) => names[id] ?? 'Someone').join(', '),
          errorText: _apiError?.fieldError('participants'),
          onTap: _busy ? null : _pickParticipants,
          leading: Icon(LucideIcons.users, size: 18, color: c.mutedForeground),
        ),
        const SizedBox(height: 14),
        CategoryPickerField(
          type: CategoryType.expense,
          value: category,
          errorText: _apiError?.fieldError('category'),
          onChanged: (picked) => setState(() => _categoryId = picked?.id),
        ),
        const SizedBox(height: 14),
        AccountPickerField(
          value: account,
          hint: 'Optional',
          errorText: _apiError?.fieldError('account'),
          onChanged: (picked) => setState(() => _accountId = picked.id),
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
        AppTextField(
          label: 'Note',
          controller: _note,
          hint: 'Optional',
          enabled: !_busy,
          maxLines: 2,
          errorText: _apiError?.fieldError('note'),
        ),
        const SizedBox(height: 10),
        Text(
          _shareCaption(),
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        ),
      ],
    );
  }

  /// `Others owe ₹1,200 of ₹1,600.`
  String _shareCaption() {
    final total = parseAmount(_total.text) ?? 0;
    final yours = parseAmount(_yourShare.text) ?? 0;
    final others = total - yours;
    if (total <= 0) return 'Enter the bill total and what you owe of it.';
    if (others < 0) return 'Your share is more than the total.';
    return 'Others owe ${Money.format(others)} of ${Money.format(total)}.';
  }

  void _splitEvenly() {
    final total = parseAmount(_total.text);
    if (total == null || total <= 0) {
      setState(() => _totalError = 'Enter the total first');
      return;
    }
    final ways = _participantIds.length + 1;
    final share = total / ways;
    setState(() {
      _yourShare.text = share % 1 == 0
          ? share.toInt().toString()
          : share.toStringAsFixed(2);
      _shareError = null;
    });
  }

  Future<void> _pickParticipants() async {
    final picked = await showParticipantsPicker(
      context,
      selectedIds: _participantIds,
    );
    if (picked == null || !mounted) return;
    setState(() => _participantIds = picked);
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
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _submit() async {
    final description = _description.text.trim();
    final total = parseAmount(_total.text);
    final share = parseAmount(_yourShare.text);

    if (description.isEmpty || total == null || total <= 0 || share == null) {
      setState(() {
        _descriptionError = description.isEmpty ? 'Say what it was' : null;
        _totalError = (total == null || total <= 0) ? 'Enter the total' : null;
        _shareError = share == null ? 'Enter your share' : null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _apiError = null;
    });

    try {
      final repository = ref.read(splitsRepositoryProvider);
      final body = _buildBody(description, total, share);
      if (_isEdit) {
        await repository.update(_existing!.id, body);
      } else {
        await repository.create(body);
      }
      ref.invalidate(splitsProvider);
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
    final split = _existing;
    if (split == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete ${split.description}?',
      message: 'The shared expense is removed.',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _deleting = true;
      _formError = null;
      _apiError = null;
    });

    try {
      await ref.read(splitsRepositoryProvider).delete(split.id);
      ref.invalidate(splitsProvider);
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

  Map<String, dynamic> _buildBody(String description, num total, num share) {
    final body = <String, dynamic>{
      'description': description,
      'totalAmount': total,
      'yourShare': share,
      'participants': _participantIds,
      'date': DateX.toApi(_date),
    };
    WriteBody.putNullable(body, 'category', _categoryId, _existing?.categoryId);
    WriteBody.putNullable(body, 'account', _accountId, _existing?.accountId);
    WriteBody.putText(body, 'note', _note.text, _existing?.note);
    return body;
  }

  static Category? _findCategory(List<Category>? categories, String? id) {
    if (categories == null || id == null) return null;
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  static Account? _findAccount(List<Account>? accounts, String? id) {
    if (accounts == null || id == null) return null;
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}
