import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/people_repository.dart';
import '../domain/person.dart';
import 'group_form_sheet.dart';
import 'person_form_sheet.dart';
import 'widgets/person_avatar.dart';
import '../../../core/router/route_refresh.dart';

/// `/credits/people` — the address book behind credits and splits: everyone you
/// share money with, and the groups they belong to.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);
    final groups = ref.watch(personGroupsProvider);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'People & groups',
            subtitle: 'Everyone you lend to, borrow from or split bills with',
            onBack: () => context.go('/credits'),
            actions: [
              ScreenHeaderAction(
                label: 'New person',
                icon: LucideIcons.userPlus,
                onPressed: () => PersonFormSheet.show(context),
              ),
              ScreenHeaderAction(
                label: 'New group',
                icon: LucideIcons.users,
                primary: false,
                onPressed: () => GroupFormSheet.show(context),
              ),
            ],
          ),
          switch (people) {
            AsyncData(:final value) when value.isEmpty => _EmptyPeople(
              onAdd: () => PersonFormSheet.show(context),
            ),
            AsyncData(:final value) => _PeopleList(people: value),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(peopleFetchProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 3),
                  SizedBox(height: 12),
                  LoadingCard(lines: 3),
                ],
              ),
            ),
          },
          switch (groups) {
            AsyncData(:final value) when value.isNotEmpty => _GroupList(
              groups: value,
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: ErrorRetry(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(personGroupsFetchProvider),
              ),
            ),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) =>
      refreshCurrentRoute(ref, '/credits/people');
}

class _EmptyPeople extends StatelessWidget {
  const _EmptyPeople({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DashedBox(
        child: EmptyState(
          icon: LucideIcons.users,
          title: 'No people yet',
          message:
              'Add someone here, or just type their name when you log a credit.',
          actionLabel: 'New person',
          onAction: onAdd,
        ),
      ),
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({required this.people});

  final List<Person> people;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sorted = [...people]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < sorted.length; i++) ...[
              if (i > 0) Divider(color: c.border, height: 1, indent: 66),
              _PersonRow(person: sorted[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // `relation` is the only detail the server keeps besides the name, and
    // `other` is its default — showing it would just be noise on every row.
    final subtitle = person.relation == PersonRelation.other
        ? ''
        : person.relation.label;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => PersonFormSheet.show(context, person: person),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              PersonAvatar(name: person.name, seed: person.id),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: c.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.groups});

  final List<PersonGroup> groups;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          child: Text(
            'GROUPS',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: c.mutedForeground,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < groups.length; i++) ...[
                  if (i > 0) Divider(color: c.border, height: 1, indent: 66),
                  _GroupRow(group: groups[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final PersonGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = personTint(
      context,
      group.id.isEmpty ? group.name : group.id,
    );
    final count = group.memberCount ?? group.memberIds.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => GroupFormSheet.show(context, group: group),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.users, size: 19, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count ${count == 1 ? 'member' : 'members'}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: c.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
