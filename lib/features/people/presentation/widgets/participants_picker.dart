import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../data/people_repository.dart';
import '../../domain/person.dart';
import 'person_avatar.dart';

/// Multi-select over the address book. Resolves to the chosen ids, or null when
/// dismissed without applying.
Future<List<String>?> showParticipantsPicker(
  BuildContext context, {
  required List<String> selectedIds,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ParticipantsSheet(selectedIds: selectedIds),
  );
}

class _ParticipantsSheet extends ConsumerStatefulWidget {
  const _ParticipantsSheet({required this.selectedIds});

  final List<String> selectedIds;

  @override
  ConsumerState<_ParticipantsSheet> createState() => _ParticipantsSheetState();
}

class _ParticipantsSheetState extends ConsumerState<_ParticipantsSheet> {
  late final Set<String> _selected = {...widget.selectedIds};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final people = ref.watch(peopleProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
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
                      'Who is splitting?',
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
            Flexible(
              child: switch (people) {
                AsyncData(:final value) when value.isEmpty => Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Text(
                    'No people saved yet. Add them from People & groups first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
                  ),
                ),
                AsyncData(:final value) => ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  children: [for (final person in value) _row(person)],
                ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: AppButton(
                label: _selected.isEmpty
                    ? 'Done'
                    : 'Add ${_selected.length} ${_selected.length == 1 ? 'person' : 'people'}',
                onPressed: () => Navigator.of(context).pop(_selected.toList()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Person person) {
    final selected = _selected.contains(person.id);
    return CheckboxListTile(
      value: selected,
      onChanged: (value) => setState(() {
        if (value ?? false) {
          _selected.add(person.id);
        } else {
          _selected.remove(person.id);
        }
      }),
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: PersonAvatar(name: person.name, seed: person.id, size: 34),
      title: Text(
        person.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
    );
  }
}
