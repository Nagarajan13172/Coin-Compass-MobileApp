import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/state/optimistic.dart';
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
  bool _merging = false;
  String? _formError;
  ApiException? _apiError;
  String? _nameError;

  bool get _isEdit => _existing != null;
  // 6.4: a delete pops the sheet on the spot and reports from the list, so
  // there is no deleting state left to spin on.
  bool get _busy => _saving || _merging;

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
      deleting: false,
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
          const SizedBox(height: 12),
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

    final body = _buildBody(name);
    final existing = _existing;

    // 6.4 — a rename or a relation change is the whole write surface, so the
    // client knows the outcome exactly and the row repaints now. A **create**
    // stays synchronous: the server assigns `_id`, a provisional row could not
    // be tapped, and a failed create is the one failure that destroys typed
    // input, which only an open form can carry.
    final predicted = existing?.predict(name: name, relation: _relation);
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
      final repository = ref.read(peopleRepositoryProvider);
      await repository.create(body);
      container.invalidate(peopleFetchProvider);
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

    // 6.4 — the row's disappearance is exactly predictable, so it goes now.
    // No Undo: `/people/:id` has no restore counterpart, and re-POSTing would
    // create a *different* person. The ConfirmSheet above is the guard.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(peopleRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(peopleWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(person.id),
            send: () => repository.delete(person.id),
            settle: () => settlePeople(container),
            messenger: messenger,
            noun: person.name,
            successMessage: 'Deleted ${person.name}',
          ),
    );
  }

  /// Closes the sheet on the predicted row and hands the write to the one
  /// mechanism. Captured before the pop, because `ref` and `context` die here.
  void _runOptimistic(
    Person existing,
    Person predicted,
    Map<String, dynamic> body,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(peopleRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(peopleWritesProvider.notifier)
          .run<Person>(
            paint: PendingWrite.upsert(predicted),
            send: () => repository.update(existing.id, body),
            confirm: (saved) => saved,
            settle: () => settlePeople(container),
            messenger: messenger,
            noun: predicted.name,
            onFix: () {
              if (!messenger.mounted) return;
              PersonFormSheet.show(messenger.context, person: predicted);
            },
          ),
    );
  }

  /// Folds this person into another and closes the sheet — the duplicate is
  /// gone, so there is nothing left to edit here.
  ///
  /// **Deliberately synchronous (6.4).** `POST /people/:id/merge` moves credits
  /// and splits across three collections and deletes the duplicate; the rows
  /// that come back are unknowable client-side, so there is nothing honest to
  /// paint. It keeps its spinner and its full refetch. Do not "fix" this by
  /// routing it through `OptimisticCollection`.
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
        ..invalidate(peopleFetchProvider)
        ..invalidate(creditsFetchProvider)
        ..invalidate(splitsFetchProvider);
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
