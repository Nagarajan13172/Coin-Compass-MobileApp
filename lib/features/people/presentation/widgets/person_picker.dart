import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../transactions/presentation/widgets/account_picker.dart'
    show PickerField;
import '../../data/people_repository.dart';
import '../../domain/person.dart';
import 'person_avatar.dart';

/// Who a credit or split involves. `/credits` accepts either a saved person's
/// id or a plain name, so the picker can answer with either — a name typed for
/// someone who isn't in the address book yet is a first-class choice, not an
/// error.
@immutable
class PersonRef {
  const PersonRef({this.id, required this.name});

  factory PersonRef.of(Person person) =>
      PersonRef(id: person.id, name: person.name);

  final String? id;
  final String name;

  /// What goes on the wire as `person`.
  Object get wireValue => id ?? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonRef && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Opens the searchable people sheet. Resolves to the chosen person, a plain
/// name, or null when dismissed.
Future<PersonRef?> showPersonPicker(
  BuildContext context, {
  PersonRef? selected,
}) {
  return showModalBottomSheet<PersonRef>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PersonPickerSheet(selected: selected),
  );
}

/// A [PickerField] wired to [showPersonPicker].
class PersonPickerField extends StatelessWidget {
  const PersonPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Person',
    this.hint = 'Who is this with?',
    this.errorText,
  });

  final PersonRef? value;
  final ValueChanged<PersonRef> onChanged;
  final String label;
  final String hint;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final person = value;
    return PickerField(
      label: label,
      hint: hint,
      value: person?.name,
      errorText: errorText,
      onTap: () async {
        final picked = await showPersonPicker(context, selected: person);
        if (picked != null) onChanged(picked);
      },
      leading: person == null
          ? null
          : PersonAvatar(name: person.name, size: 30),
    );
  }
}

class _PersonPickerSheet extends ConsumerStatefulWidget {
  const _PersonPickerSheet({this.selected});

  final PersonRef? selected;

  @override
  ConsumerState<_PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends ConsumerState<_PersonPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final people = ref.watch(peopleProvider);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final typed = _query.trim();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85 - insets,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choose a person',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: AppTextField(
                  controller: _search,
                  hint: 'Search or type a new name',
                  autofocus: true,
                  onChanged: (value) => setState(() => _query = value),
                  prefix: Icon(
                    LucideIcons.search,
                    size: 18,
                    color: c.mutedForeground,
                  ),
                ),
              ),
              Flexible(
                child: switch (people) {
                  AsyncData(:final value) => _results(context, value, typed),
                  AsyncError(:final error) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: ErrorRetry(
                      error: error,
                      compact: true,
                      onRetry: () => ref.invalidate(peopleFetchProvider),
                    ),
                  ),
                  _ => const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      children: [
                        LoadingShimmer(height: 40),
                        SizedBox(height: 10),
                        LoadingShimmer(height: 40),
                      ],
                    ),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context, List<Person> people, String typed) {
    final c = context.colors;
    final matches = typed.isEmpty
        ? people
        : people
              .where(
                (person) =>
                    person.name.toLowerCase().contains(typed.toLowerCase()),
              )
              .toList();

    final exact = people.any(
      (person) => person.name.toLowerCase() == typed.toLowerCase(),
    );

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        if (typed.isNotEmpty && !exact)
          ListTile(
            onTap: () => Navigator.of(context).pop(PersonRef(name: typed)),
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.userPlus, size: 17, color: c.primary),
            ),
            title: Text(
              'Use "$typed"',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Saved with this entry',
              style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
            ),
          ),
        if (matches.isEmpty && typed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            child: Text(
              'No people yet — type a name to add one as you go.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
            ),
          ),
        for (final person in matches)
          ListTile(
            onTap: () => Navigator.of(context).pop(PersonRef.of(person)),
            leading: PersonAvatar(name: person.name, seed: person.id, size: 34),
            title: Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: person.relation == PersonRelation.other
                ? null
                : Text(
                    person.relation.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                  ),
            trailing: widget.selected?.id == person.id
                ? Icon(LucideIcons.check, size: 18, color: c.primary)
                : null,
          ),
      ],
    );
  }
}
