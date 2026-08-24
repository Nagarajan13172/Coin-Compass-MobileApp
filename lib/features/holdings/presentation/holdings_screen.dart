import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/holdings_repository.dart';
import '../domain/holding.dart';
import 'holding_form_sheet.dart';
import 'widgets/holding_tile.dart';
import '../../../core/router/route_refresh.dart';

/// Savings and investments — the asset half of net worth, grouped by the two
/// classes the backend declares (`saving` / `investment`) with each row
/// labelled by its subtype.
///
/// Body only; [AppScaffold] supplies the app bar and bottom nav. Reached from
/// the Net Worth screen's "Manage holdings" action as well as its own route.
class HoldingsScreen extends ConsumerWidget {
  const HoldingsScreen({super.key});

  /// Where the router mounts this screen. Net Worth links here by constant so
  /// the two cannot drift apart.
  static const String routePath = '/net-worth/holdings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(holdingsProvider);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'Holdings',
            subtitle: 'Savings and investments that add up to your assets',
            onBack: () => context.go('/net-worth'),
            actions: [
              ScreenHeaderAction(
                label: 'New holding',
                icon: LucideIcons.plus,
                onPressed: () => HoldingFormSheet.show(context),
              ),
            ],
          ),
          switch (holdings) {
            AsyncData(:final value) when value.isEmpty => _EmptyHoldings(
              onAdd: () => HoldingFormSheet.show(context),
            ),
            AsyncData(:final value) => _HoldingsList(holdings: value),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(holdingsFetchProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 3),
                  SizedBox(height: 12),
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

  Future<void> _refresh(WidgetRef ref) =>
      refreshCurrentRoute(ref, HoldingsScreen.routePath);
}

class _EmptyHoldings extends StatelessWidget {
  const _EmptyHoldings({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DashedBox(
        child: EmptyState(
          icon: LucideIcons.piggyBank,
          title: 'No holdings yet',
          message:
              'Add a deposit, fund, property or anything else you own '
              'and it counts toward your net worth.',
          actionLabel: 'New holding',
          onAction: onAdd,
        ),
      ),
    );
  }
}

class _HoldingsList extends StatelessWidget {
  const _HoldingsList({required this.holdings});

  final List<Holding> holdings;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: _TotalsCard(holdings: holdings),
      ),
    ];

    for (final holdingClass in HoldingClass.values) {
      final group =
          holdings
              .where((holding) => holding.holdingClass == holdingClass)
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      if (group.isEmpty) continue;

      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: _GroupHeader(
            label: holdingClass.label,
            count: group.length,
            total: group.fold<num>(0, (sum, holding) => sum + holding.value),
          ),
        ),
      );
      children.addAll([
        for (final holding in group)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: HoldingTile(
              holding: holding,
              onTap: () => HoldingFormSheet.show(context, holding: holding),
            ),
          ),
      ]);
    }

    return Column(children: children);
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.count,
    required this.total,
  });

  final String label;
  final int count;
  final num total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: c.mutedForeground,
            ),
          ),
        ),
        Text(
          '$count · ',
          style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
        ),
        MoneyText(
          total,
          compactAbove: Money.crore,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: c.mutedForeground,
          ),
        ),
      ],
    );
  }
}

/// Total value with the saving / investment split — the same two figures the
/// net-worth snapshot rolls into `holdingsTotal`.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.holdings});

  final List<Holding> holdings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = holdings.fold<num>(0, (sum, h) => sum + h.value);
    final saving = holdings
        .where((h) => h.isSaving)
        .fold<num>(0, (sum, h) => sum + h.value);
    final investment = total - saving;
    final maturing = holdings
        .where((h) => h.maturityDate != null && !h.isMatured)
        .length;
    final matured = holdings.where((h) => h.isMatured).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total value',
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
          const SizedBox(height: 4),
          // The exact figure, the way the web app states it. FittedBox is what
          // keeps a ten-figure balance on one line; compacting this to "₹2Cr"
          // would hide the very number the card exists to show. Dense rows,
          // where a label has to share the width, keep compactAbove.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              total,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Split(
                  label: 'Saving',
                  amount: saving,
                  icon: LucideIcons.piggyBank,
                  accent: c.income,
                ),
              ),
              Container(width: 1, height: 34, color: c.border),
              Expanded(
                child: _Split(
                  label: 'Investment',
                  amount: investment,
                  icon: LucideIcons.trendingUp,
                  accent: c.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _footnote(holdings.length, maturing, matured),
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  static String _footnote(int count, int maturing, int matured) {
    final base = count == 1 ? 'Across 1 holding' : 'Across $count holdings';
    if (matured > 0) return '$base · $matured matured';
    if (maturing > 0) return '$base · $maturing maturing';
    return base;
  }
}

class _Split extends StatelessWidget {
  const _Split({
    required this.label,
    required this.amount,
    required this.icon,
    required this.accent,
  });

  final String label;
  final num amount;
  final IconData icon;
  final Color accent;

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
                MoneyText(
                  amount,
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
