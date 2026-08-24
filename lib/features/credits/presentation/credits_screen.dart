import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
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
import '../../splits/data/splits_repository.dart';
import '../../splits/presentation/split_form_sheet.dart';
import '../data/credits_repository.dart';
import '../domain/credit.dart';
import 'credit_form_sheet.dart';
import 'widgets/credit_tile.dart';
import '../../../core/router/route_refresh.dart';

/// `/credits` — money lent to and borrowed from friends and family, with the
/// address book and shared bills a tap away.
class CreditsScreen extends ConsumerStatefulWidget {
  const CreditsScreen({super.key});

  @override
  ConsumerState<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends ConsumerState<CreditsScreen> {
  /// Credits with a delete in flight.
  final Set<String> _busyIds = {};

  @override
  Widget build(BuildContext context) {
    final credits = ref.watch(creditsProvider);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'Credits',
            subtitle: "Money you've given to or received from friends & family",
            actions: [
              ScreenHeaderAction(
                label: 'Add credit',
                icon: LucideIcons.plus,
                onPressed: () => CreditFormSheet.show(context),
              ),
              ScreenHeaderAction(
                label: 'Split a bill',
                icon: LucideIcons.receipt,
                primary: false,
                onPressed: () => SplitFormSheet.show(context),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _SummaryCard(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: _ShortcutRow(),
          ),
          switch (credits) {
            AsyncData(:final value) when value.isEmpty => _EmptyCredits(
              onAdd: () => CreditFormSheet.show(context),
            ),
            AsyncData(:final value) => _CreditList(
              credits: value,
              busyIds: _busyIds,
              onAction: _handleAction,
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(creditsProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 2),
                  SizedBox(height: 12),
                  LoadingCard(lines: 2),
                ],
              ),
            ),
          },
        ],
      ),
    );
  }

  Future<void> _refresh() => refreshCurrentRoute(ref, '/credits');

  Future<void> _handleAction(Credit credit, CreditAction action) async {
    switch (action) {
      case CreditAction.edit:
        await CreditFormSheet.show(context, credit: credit);
      case CreditAction.delete:
        await _delete(credit);
    }
  }

  Future<void> _delete(Credit credit) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete this credit?',
      message:
          'The entry is removed from your ledger with ${credit.displayName}.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyIds.add(credit.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(creditsRepositoryProvider).delete(credit.id);
      ref.invalidate(creditsProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Credit deleted')));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ApiException.from(error).message)),
        );
    } finally {
      if (mounted) setState(() => _busyIds.remove(credit.id));
    }
  }
}

/// Owed to you / you owe / net, from `/credits/summary` when the server sends
/// it and from the list itself when it doesn't.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(creditsSummaryProvider);
    final summary = async.valueOrNull;
    // A failed summary is not a slow one. Without this the card shimmers for
    // ever behind the list's own ErrorRetry, which reads as "still loading".
    final failed = summary == null && async.hasError;
    final net = summary?.net ?? 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Net position',
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
          const SizedBox(height: 4),
          if (failed)
            Text(
              '—',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: c.mutedForeground,
              ),
            )
          else if (summary == null)
            const LoadingShimmer(width: 140, height: 28)
          else
            MoneyText(
              net,
              tone: MoneyTone.auto,
              signed: true,
              compactAbove: Money.crore,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Split(
                  label: 'Owed to you',
                  amount: summary?.owedToYou,
                  failed: failed,
                  accent: c.income,
                  icon: LucideIcons.handCoins,
                  tone: MoneyTone.income,
                ),
              ),
              Container(width: 1, height: 34, color: c.border),
              Expanded(
                child: _Split(
                  label: 'You owe',
                  amount: summary?.youOwe,
                  failed: failed,
                  accent: c.expense,
                  icon: LucideIcons.wallet,
                  tone: MoneyTone.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            net == 0
                ? 'You are square with everyone.'
                : (net > 0
                      ? 'You are owed more than you owe.'
                      : 'You owe more than you are owed.'),
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _Split extends StatelessWidget {
  const _Split({
    required this.label,
    required this.amount,
    required this.accent,
    required this.icon,
    required this.tone,
    this.failed = false,
  });

  final String label;

  /// Null while the summary is still loading, or when it failed — [failed]
  /// tells the two apart.
  final num? amount;

  /// The summary request failed. Show the same em dash the rest of the app
  /// uses for a figure it does not know, not a skeleton.
  final bool failed;
  final Color accent;
  final IconData icon;
  final MoneyTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: accent),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
                ),
                if (failed && amount == null)
                  Text(
                    '—',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.mutedForeground,
                    ),
                  )
                else if (amount == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: LoadingShimmer(width: 60, height: 13),
                  )
                else
                  MoneyText(
                    amount!,
                    tone: tone,
                    compactAbove: 1000000,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two places credits lead to: the address book and shared bills.
class _ShortcutRow extends ConsumerWidget {
  const _ShortcutRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider).valueOrNull;
    final splits = ref.watch(splitsProvider).valueOrNull;
    final splitCount = splits?.length;

    return Row(
      children: [
        Expanded(
          child: _ShortcutCard(
            icon: LucideIcons.users,
            label: 'People & groups',
            caption: people == null
                ? 'Address book'
                : '${people.length} ${people.length == 1 ? 'person' : 'people'}',
            onTap: () => context.go('/credits/people'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ShortcutCard(
            icon: LucideIcons.receipt,
            label: 'Splits',
            caption: splitCount == null
                ? 'Shared bills'
                : '$splitCount ${splitCount == 1 ? 'bill' : 'bills'}',
            onTap: () => context.go('/credits/splits'),
          ),
        ),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: c.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCredits extends StatelessWidget {
  const _EmptyCredits({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DashedBox(
        child: EmptyState(
          icon: LucideIcons.handCoins,
          title: 'No credits yet',
          message:
              'Track money you give to or receive from friends and family.',
          actionLabel: 'Add credit',
          onAction: onAdd,
        ),
      ),
    );
  }
}

class _CreditList extends StatelessWidget {
  const _CreditList({
    required this.credits,
    required this.busyIds,
    required this.onAction,
  });

  final List<Credit> credits;
  final Set<String> busyIds;
  final void Function(Credit credit, CreditAction action) onAction;

  @override
  Widget build(BuildContext context) {
    // One list, newest first: the API has no settled flag, so there is no
    // closed section to split off.
    final rows = [...credits]..sort(_byDateDescending);

    return Column(
      children: [
        const SizedBox(height: 12),
        for (final credit in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CreditTile(
              credit: credit,
              busy: busyIds.contains(credit.id),
              onAction: (action) => onAction(credit, action),
              onTap: () => CreditFormSheet.show(context, credit: credit),
            ),
          ),
      ],
    );
  }

  /// Newest first; an entry with no date sorts last.
  static int _byDateDescending(Credit a, Credit b) {
    final left = a.date ?? a.createdAt;
    final right = b.date ?? b.createdAt;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  }
}
