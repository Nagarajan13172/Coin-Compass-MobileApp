// Flutter's animation library exports a `Split` curve class, which would
// collide with the domain model of the same name.
import 'package:flutter/material.dart' hide Split;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../people/data/people_repository.dart';
import '../data/splits_repository.dart';
import '../domain/split.dart';
import 'split_form_sheet.dart';
import '../../../core/router/route_refresh.dart';

/// `/credits/splits` — shared expenses: what a bill came to, what your share
/// was, and what the others still owe.
class SplitsScreen extends ConsumerStatefulWidget {
  const SplitsScreen({super.key});

  @override
  ConsumerState<SplitsScreen> createState() => _SplitsScreenState();
}

class _SplitsScreenState extends ConsumerState<SplitsScreen> {
  /// Splits with a delete in flight.
  final Set<String> _busyIds = {};

  @override
  Widget build(BuildContext context) {
    final splits = ref.watch(splitsProvider);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'Splits',
            subtitle: 'Bills you shared with other people',
            onBack: () => context.go('/credits'),
            actions: [
              ScreenHeaderAction(
                label: 'Split a bill',
                icon: LucideIcons.plus,
                onPressed: () => SplitFormSheet.show(context),
              ),
            ],
          ),
          switch (splits) {
            AsyncData(:final value) when value.isEmpty => _EmptySplits(
              onAdd: () => SplitFormSheet.show(context),
            ),
            AsyncData(:final value) => _SplitList(
              splits: value,
              busyIds: _busyIds,
              onDelete: _delete,
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(splitsProvider),
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
        ],
      ),
    );
  }

  Future<void> _refresh() => refreshCurrentRoute(ref, '/credits/splits');

  Future<void> _delete(Split split) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete ${split.description}?',
      message: 'The shared expense is removed.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyIds.add(split.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(splitsRepositoryProvider).delete(split.id);
      ref.invalidate(splitsProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Deleted ${split.description}')));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ApiException.from(error).message)),
        );
    } finally {
      if (mounted) setState(() => _busyIds.remove(split.id));
    }
  }
}

class _EmptySplits extends StatelessWidget {
  const _EmptySplits({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DashedBox(
        child: EmptyState(
          icon: LucideIcons.receipt,
          title: 'No splits yet',
          message:
              'Log a bill you shared and keep track of what the others owe you.',
          actionLabel: 'Split a bill',
          onAction: onAdd,
        ),
      ),
    );
  }
}

class _SplitList extends ConsumerWidget {
  const _SplitList({
    required this.splits,
    required this.busyIds,
    required this.onDelete,
  });

  final List<Split> splits;
  final Set<String> busyIds;
  final ValueChanged<Split> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];
    final names = {for (final person in people) person.id: person.name};

    // The API has no settled flag on a split, so every row counts towards
    // what the others owe and there is no closed section to split off.
    final owed = splits.fold<num>(0, (sum, split) => sum + split.othersShare);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: _OwedCard(owed: owed, count: splits.length),
        ),
        for (final split in splits)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SplitTile(
              split: split,
              participantNames: split.participantIds
                  .map((id) => names[id] ?? 'Someone')
                  .toList(),
              busy: busyIds.contains(split.id),
              onEdit: () => SplitFormSheet.show(context, split: split),
              onDelete: () => onDelete(split),
            ),
          ),
      ],
    );
  }
}

class _OwedCard extends StatelessWidget {
  const _OwedCard({required this.owed, required this.count});

  final num owed;

  /// How many splits the total covers.
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Others owe you',
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
          const SizedBox(height: 4),
          MoneyText(
            owed,
            tone: owed > 0 ? MoneyTone.income : MoneyTone.neutral,
            compactAbove: Money.crore,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            count == 0
                ? 'Nothing shared yet'
                : 'Across $count ${count == 1 ? 'split' : 'splits'}',
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _SplitTile extends StatelessWidget {
  const _SplitTile({
    required this.split,
    required this.participantNames,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final Split split;
  final List<String> participantNames;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      onTap: onEdit,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.receipt, size: 19, color: c.primary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      split.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    split.totalAmount,
                    compactAbove: Money.crore,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'You ${Money.compact(split.yourShare)}',
                    style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
                  ),
                ],
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                )
              else
                PopupMenuButton<int>(
                  tooltip: 'Split actions',
                  color: c.popover,
                  icon: Icon(
                    LucideIcons.ellipsisVertical,
                    size: 18,
                    color: c.mutedForeground,
                  ),
                  onSelected: (value) => switch (value) {
                    1 => onEdit(),
                    _ => onDelete(),
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 1, child: Text('Edit')),
                    PopupMenuItem(
                      value: 2,
                      child: Text(
                        'Delete',
                        style: TextStyle(color: c.destructive),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (split.othersShare > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Others owe ${Money.format(split.othersShare)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.income,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      if (split.date != null) DateX.shortDay(split.date!),
      if (participantNames.isNotEmpty)
        participantNames.length <= 2
            ? participantNames.join(' & ')
            : '${participantNames.take(2).join(', ')} +${participantNames.length - 2}',
    ];
    return parts.isEmpty ? 'Shared expense' : parts.join(' · ');
  }
}
