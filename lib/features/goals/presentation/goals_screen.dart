import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/goals_repository.dart';
import '../domain/goal.dart';
import 'goal_contribute_sheet.dart';
import 'goal_form_sheet.dart';
import 'widgets/goal_card.dart';
import 'widgets/goal_ring.dart';
import '../../../core/router/route_refresh.dart';

/// `/goals` — savings goals with their progress rings and a contribute
/// shortcut. Body only; [AppScaffold] supplies the chrome.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'Goals',
            subtitle: 'Save towards what matters',
            actions: [
              ScreenHeaderAction(
                label: 'New goal',
                icon: LucideIcons.plus,
                onPressed: () => GoalFormSheet.show(context),
              ),
            ],
          ),
          switch (goals) {
            AsyncData(:final value) when value.isEmpty => _EmptyGoals(
              onAdd: () => GoalFormSheet.show(context),
            ),
            AsyncData(:final value) => _GoalList(goals: value),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(goalsFetchProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 3),
                  SizedBox(height: 12),
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

  Future<void> _refresh(WidgetRef ref) => refreshCurrentRoute(ref, '/goals');
}

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DashedBox(
        child: EmptyState(
          icon: LucideIcons.goal,
          title: 'No goals yet',
          message:
              'Set a savings goal like a trip or a new gadget and track your progress.',
          actionLabel: 'New goal',
          onAction: onAdd,
        ),
      ),
    );
  }
}

class _GoalList extends StatelessWidget {
  const _GoalList({required this.goals});

  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final active = goals.where((goal) => !goal.isComplete).toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    final complete = goals.where((goal) => goal.isComplete).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: _TotalsCard(goals: goals),
        ),
        for (final goal in active)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GoalCard(
              goal: goal,
              onTap: () => GoalFormSheet.show(context, goal: goal),
              onContribute: () => GoalContributeSheet.show(context, goal: goal),
            ),
          ),
        if (complete.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 6, 24, 8),
            child: _SectionLabel('Reached'),
          ),
          for (final goal in complete)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GoalCard(
                goal: goal,
                onTap: () => GoalFormSheet.show(context, goal: goal),
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: c.mutedForeground,
        ),
      ),
    );
  }
}

/// Saved against target across every goal, with the same ring the cards use.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.goals});

  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final target = goals.fold<num>(0, (sum, goal) => sum + goal.targetAmount);
    final saved = goals.fold<num>(0, (sum, goal) => sum + goal.savedAmount);
    final progress = target <= 0
        ? 0.0
        : (saved / target).clamp(0, 1).toDouble();
    final reached = goals.where((goal) => goal.isComplete).length;

    return AppCard(
      child: Row(
        children: [
          GoalRing(progress: progress, color: c.primary, size: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved towards goals',
                  style: TextStyle(fontSize: 13, color: c.mutedForeground),
                ),
                const SizedBox(height: 2),
                MoneyText(
                  saved,
                  compactAbove: Money.crore,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'of ${Money.compact(target)} across ${goals.length} '
                  '${goals.length == 1 ? 'goal' : 'goals'}'
                  '${reached == 0 ? '' : ' · $reached reached'}',
                  style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
