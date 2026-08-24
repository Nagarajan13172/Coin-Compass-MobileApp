import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../credits/data/credits_repository.dart';
import '../../splits/data/splits_repository.dart';
import '../data/people_repository.dart';
import '../domain/person.dart';
import 'widgets/person_picker.dart';

/// Create / edit someone in the address book, and fold duplicates together.
/// Pops `true` when the list changed.
class PersonFormSheet extends ConsumerStatefulWidget {
  const PersonFormSheet({super.key, this.person});

  /// Null creates a person; non-null edits that one.
  final Person? person;

  static Future<bool?> show(BuildContext context, {Person? person}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PersonFormSheet(person: person),
    );
  }

  @override
  ConsumerState<PersonFormSheet> createState() => _PersonFormSheetState();
}

class _PersonFormSheetState extends ConsumerState<PersonFormSheet> {
  late final Person? _existing = widget.person;

  late final TextEditingController _name = TextEditingController(
    text: _existing?.name ?? '',
  );

  late PersonRelation _relation = _existing?.relation ?? PersonRelation.other;

  bool _saving = false;
  bool _deleting = false;
  bool _merging = false;
  String? _formError;
  ApiException? _apiError;
  String? _nameError;

  bool get _isEdit => _existing != null;
  bool get _busy => _saving || _deleting || _merging;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return FormSheetScaffold(
      title: _isEdit ? 'Edit person' : 'New person',
      submitLabel: _isEdit ? 'Save changes' : 'Add person',
      submitting: _saving,
      deleting: _deleting,
      onSubmit: _submit,
      deleteLabel: _isEdit ? 'Delete person' : null,
      onDelete: _isEdit ? _delete : null,
      formError: _formError,
      children: [
        AppTextField(
          label: 'Name',
          controller: _name,
          hint: 'e.g. Karthik',
          autofocus: !_isEdit,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          errorText: _nameError ?? _apiError?.fieldError('name'),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 14),
        AppSelect<PersonRelation>(
          label: 'Relation',
          value: _relation,
          enabled: !_busy,
          errorText: _apiError?.fieldError('relation'),
          items: [
            for (final relation in PersonRelation.values)
              SelectItem<PersonRelation>(relation, relation.label),
          ],
          onChanged: (value) =>
              setState(() => _relation = value ?? PersonRelation.other),
        ),
        if (_isEdit) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _merge,
              icon: const Icon(LucideIcons.merge, size: 17),
              label: Text(_merging ? 'Merging…' : 'Merge into another person'),
              style: TextButton.styleFrom(
                foregroundColor: c.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
          Text(
            'Use this when the same person was saved twice — their credits and '
            'splits move across.',
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ],
      ],
    );
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name is required');
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _apiError = null;
    });

    try {
      final repository = ref.read(peopleRepositoryProvider);
      final body = _buildBody(name);
      if (_isEdit) {
        await repository.update(_existing!.id, body);
      } else {
        await repository.create(body);
      }
      ref.invalidate(peopleProvider);
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
    final person = _existing;
    if (person == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete ${person.name}?',
      message: 'Credits and splits that name them are kept.',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _deleting = true;
      _formError = null;
      _apiError = null;
    });

    try {
      await ref.read(peopleRepositoryProvider).delete(person.id);
      ref.invalidate(peopleProvider);
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

  /// Folds this person into another and closes the sheet — the duplicate is
  /// gone, so there is nothing left to edit here.
  Future<void> _merge() async {
    final person = _existing;
    if (person == null) return;

    final target = await showPersonPicker(context);
    if (target == null || !mounted) return;

    if (target.id == null) {
      setState(() => _formError = 'Pick someone already saved to merge into.');
      return;
    }
    if (target.id == person.id) {
      setState(() => _formError = 'Pick a different person to merge into.');
      return;
    }

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Merge ${person.name} into ${target.name}?',
      message:
          'Everything recorded against ${person.name} moves to ${target.name}, '
          'and ${person.name} is removed.',
      confirmLabel: 'Merge',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _merging = true;
      _formError = null;
      _apiError = null;
    });

    try {
      await ref.read(peopleRepositoryProvider).merge(person.id, target.id!);
      ref
        ..invalidate(peopleProvider)
        ..invalidate(creditsProvider)
        ..invalidate(splitsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      final api = ApiException.from(error);
      if (!mounted) return;
      setState(() {
        _merging = false;
        _apiError = api;
        _formError = api.message;
      });
    }
  }

  /// `name` and `relation` are the whole accepted schema — anything else would
  /// be dropped by the server without an error. See docs/WRITE_SCHEMAS.md.
  Map<String, dynamic> _buildBody(String name) => {
    'name': name,
    'relation': _relation.api,
  };
}
