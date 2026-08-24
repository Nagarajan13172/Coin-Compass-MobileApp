import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/state/optimistic.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../transactions/presentation/widgets/account_picker.dart'
    show PickerField;
import '../data/people_repository.dart';
import '../domain/person.dart';
import 'widgets/participants_picker.dart';

/// Create / edit a group of people — a household, a trip, a team.
/// Pops `true` when the list changed.
class GroupFormSheet extends ConsumerStatefulWidget {
  const GroupFormSheet({super.key, this.group});

  /// Null creates a group; non-null edits that one.
  final PersonGroup? group;

  static Future<bool?> show(BuildContext context, {PersonGroup? group}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => GroupFormSheet(group: group),
    );
  }

  @override
  ConsumerState<GroupFormSheet> createState() => _GroupFormSheetState();
}

class _GroupFormSheetState extends ConsumerState<GroupFormSheet> {
  late final PersonGroup? _existing = widget.group;

  late final TextEditingController _name = TextEditingController(
    text: _existing?.name ?? '',
  );

  late List<String> _memberIds = [...?_existing?.memberIds];

  bool _saving = false;
  String? _formError;
  ApiException? _apiError;
  String? _nameError;

  bool get _isEdit => _existing != null;
  // 6.4: a delete pops the sheet on the spot, so there is no deleting state.
  bool get _busy => _saving;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final people = ref.watch(peopleProvider).valueOrNull ?? const <Person>[];
    final names = {for (final person in people) person.id: person.name};

    return FormSheetScaffold(
      title: _isEdit ? 'Edit group' : 'New group',
      submitLabel: _isEdit ? 'Save changes' : 'Create group',
      submitting: _saving,
      deleting: false,
      onSubmit: _submit,
      deleteLabel: _isEdit ? 'Delete group' : null,
      onDelete: _isEdit ? _delete : null,
      formError: _formError,
      children: [
        AppTextField(
          label: 'Name',
          controller: _name,
          hint: 'e.g. Goa trip',
          autofocus: !_isEdit,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          errorText: _nameError ?? _apiError?.fieldError('name'),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Members',
          hint: 'Choose people',
          value: _memberIds.isEmpty
              ? null
              : _memberIds.map((id) => names[id] ?? 'Someone').join(', '),
          errorText: _apiError?.fieldError('members'),
          onTap: _busy ? null : _pickMembers,
          leading: Icon(LucideIcons.users, size: 18, color: c.mutedForeground),
        ),
      ],
    );
  }

  Future<void> _pickMembers() async {
    final picked = await showParticipantsPicker(
      context,
      selectedIds: _memberIds,
    );
    if (picked == null || !mounted) return;
    setState(() => _memberIds = picked);
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name is required');
      return;
    }

    // `name` and `members` are the whole accepted schema — a colour or a note
    // would be stripped by the server. See docs/WRITE_SCHEMAS.md.
    final body = <String, dynamic>{'name': name, 'members': _memberIds};
    final existing = _existing;

    // 6.4 — name and membership are the entire write surface, so an edit's
    // outcome is exactly known and the row repaints now. A create keeps the
    // spinner: the server assigns the id.
    final predicted = existing?.predict(name: name, memberIds: _memberIds);
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
      await repository.createGroup(body);
      container
        ..invalidate(personGroupsFetchProvider)
        ..invalidate(peopleFetchProvider);
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
    final group = _existing;
    if (group == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete ${group.name}?',
      message: 'The people in it are kept.',
    );
    if (!confirmed || !mounted) return;

    // 6.4 — predictable, so the row goes now. No Undo: there is no restore
    // endpoint for a group, and re-POSTing would make a different one.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(peopleRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(personGroupsWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(group.id),
            send: () => repository.deleteGroup(group.id),
            settle: () => settlePersonGroups(container),
            messenger: messenger,
            noun: group.name,
            successMessage: 'Deleted ${group.name}',
          ),
    );
  }

  /// Closes the sheet on the predicted row and hands the write over.
  void _runOptimistic(
    PersonGroup existing,
    PersonGroup predicted,
    Map<String, dynamic> body,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(peopleRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(personGroupsWritesProvider.notifier)
          .run<PersonGroup>(
            paint: PendingWrite.upsert(predicted),
            send: () => repository.updateGroup(existing.id, body),
            confirm: (saved) => saved,
            // Membership lives on both sides, so the people list is dropped too.
            settle: () => settlePersonGroups(container),
            messenger: messenger,
            noun: predicted.name,
            onFix: () {
              if (!messenger.mounted) return;
              GroupFormSheet.show(messenger.context, group: predicted);
            },
          ),
    );
  }
}
