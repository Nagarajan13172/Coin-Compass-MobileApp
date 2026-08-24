import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../data/accounts_repository.dart';
import '../domain/account.dart';
import 'account_form_sheet.dart';
import 'widgets/account_tile.dart';

/// Height of the bottom nav bar in [AppScaffold]; a scrollable body has to
/// clear it because the shell renders with `extendBody: true`.
const double _navBarHeight = 62;

/// Overhang of the raised centre FAB plus a little breathing room.
const double _fabClearance = 28;

/// Space a scrollable must reserve at its tail to clear the shell's nav bar,
/// the system inset below it and the raised FAB.
///
/// `viewPaddingOf`, not `paddingOf`: inside a body with `extendBody: true`
/// Flutter already folds the nav bar into `MediaQuery.padding.bottom`, so
/// `paddingOf` would count it twice.
double _shellBottomInset(BuildContext context) =>
    _navBarHeight + MediaQuery.viewPaddingOf(context).bottom + _fabClearance;

/// `/accounts` — every cash, bank, card and wallet account with its balance,
/// grouped by type under a totals card. Body only — AppScaffold owns the chrome.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final balances =
        ref.watch(transactionBalanceProvider).valueOrNull?.byAccount ??
        const <String, num>{};

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Accounts',
              subtitle: 'Cash, bank, cards & wallets',
              actions: [
                ScreenHeaderAction(
                  label: 'New account',
                  icon: LucideIcons.plus,
                  onPressed: () => _openForm(context, ref),
                ),
              ],
            ),
          ),
          switch (accounts) {
            AsyncData(:final value) when value.isEmpty => SliverToBoxAdapter(
              child: _EmptyAccounts(onAdd: () => _openForm(context, ref)),
            ),
            AsyncData(:final value) => _AccountSlivers(
              accounts: value,
              balances: balances,
              onEdit: (account) => _openForm(context, ref, account: account),
            ),
            AsyncError(:final error) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: ErrorRetry(
                  error: error,
                  onRetry: () => ref.invalidate(accountsProvider),
                ),
              ),
            ),
            _ => const SliverToBoxAdapter(child: _AccountsLoading()),
          },
          // Not a constant: AppScaffold renders with `extendBody: true`, so a
          // fixed tail leaves the last tile under the FAB once the system
          // inset grows (3-button navigation is 48dp).
          SliverToBoxAdapter(
            child: SizedBox(height: _shellBottomInset(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(accountsProvider);
    ref.invalidate(transactionBalanceProvider);
    try {
      await ref.read(accountsProvider.future);
    } catch (_) {
      // The error state is rendered from the provider; the spinner just stops.
    }
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Account? account,
  }) async {
    final changed = await AccountFormSheet.show(context, account: account);
    // The sheet already invalidated the account list; the per-account running
    // balances come from a different endpoint, so refresh those too.
    if (changed == true) ref.invalidate(transactionBalanceProvider);
  }
}

class _AccountsLoading extends StatelessWidget {
  const _AccountsLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          LoadingCard(lines: 3),
          SizedBox(height: 12),
          LoadingCard(lines: 4),
          SizedBox(height: 12),
          LoadingCard(lines: 4),
        ],
      ),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DashedBox(
        child: EmptyState(
          icon: LucideIcons.wallet,
          title: 'No accounts yet',
          message: 'Create an account to start tracking your money.',
          actionLabel: 'New account',
          onAction: onAdd,
        ),
      ),
    );
  }
}

class _AccountSlivers extends StatelessWidget {
  const _AccountSlivers({
    required this.accounts,
    required this.balances,
    required this.onEdit,
  });

  final List<Account> accounts;
  final Map<String, num> balances;
  final ValueChanged<Account> onEdit;

  @override
  Widget build(BuildContext context) {
    final totals = AccountTotals.of(accounts, balances);

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: _TotalsCard(totals: totals),
      ),
    ];

    for (final type in AccountType.values) {
      final group = accounts.where((a) => a.type == type).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (group.isEmpty) continue;

      // Null when every account in the group is excluded — a `₹0` header there
      // would read as "these are empty" rather than "these don't count".
      final counting = group.where((a) => !a.excludeFromTotal);
      final groupTotal = counting.isEmpty
          ? null
          : counting.fold<num>(
              0,
              (sum, a) => sum + resolveAccountBalance(a, balances),
            );

      children
        ..add(
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: _GroupHeader(type: type, total: groupTotal),
          ),
        )
        ..add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _GroupCard(group: group, balances: balances, onEdit: onEdit),
          ),
        );
    }

    return SliverList(delegate: SliverChildListDelegate(children));
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.type, required this.total});

  final AccountType type;

  /// Null hides the subtotal — see the call site.
  final num? total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            type.label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: c.mutedForeground,
            ),
          ),
        ),
        if (total != null)
          MoneyText(
            total!,
            tone: MoneyTone.muted,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.balances,
    required this.onEdit,
  });

  final List<Account> group;
  final Map<String, num> balances;
  final ValueChanged<Account> onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < group.length; i++) ...[
            if (i > 0) Divider(color: c.border, height: 1, indent: 69),
            AccountTile(
              account: group[i],
              balance: resolveAccountBalance(group[i], balances),
              onTap: () => onEdit(group[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final AccountTotals totals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total balance',
            style: TextStyle(fontSize: 13, color: c.mutedForeground),
          ),
          const SizedBox(height: 4),
          MoneyText(
            totals.total,
            tone: totals.total < 0 ? MoneyTone.expense : MoneyTone.neutral,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Split(
                  label: 'Assets',
                  amount: totals.assets,
                  tone: MoneyTone.income,
                  icon: LucideIcons.trendingUp,
                  accent: c.income,
                ),
              ),
              Container(width: 1, height: 34, color: c.border),
              Expanded(
                child: _Split(
                  label: 'Liabilities',
                  amount: totals.liabilities,
                  tone: MoneyTone.expense,
                  icon: LucideIcons.creditCard,
                  accent: c.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            totals.caption,
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
    required this.tone,
    required this.icon,
    required this.accent,
  });

  final String label;
  final num amount;
  final MoneyTone tone;
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
                  tone: tone,
                  compact: amount.abs() >= 1000000,
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

/// Balance split across the accounts that count towards the user's money.
///
/// Card accounts are liabilities: money owed shows on them as a negative
/// balance, so `total == assets - liabilities` always holds.
@immutable
class AccountTotals {
  const AccountTotals({
    required this.assets,
    required this.liabilities,
    required this.counted,
    required this.excluded,
  });

  final num assets;
  final num liabilities;

  /// How many accounts fed the total.
  final int counted;

  /// How many were left out because of `excludeFromTotal`.
  final int excluded;

  num get total => assets - liabilities;

  String get caption {
    final base = 'In $counted ${counted == 1 ? 'account' : 'accounts'}';
    return excluded == 0 ? base : '$base · $excluded excluded';
  }

  static AccountTotals of(List<Account> accounts, Map<String, num> balances) {
    num assets = 0;
    num liabilities = 0;
    var counted = 0;
    var excluded = 0;

    for (final account in accounts) {
      if (account.excludeFromTotal) {
        excluded++;
        continue;
      }
      counted++;
      final balance = resolveAccountBalance(account, balances);
      if (account.isLiability) {
        liabilities += -balance;
      } else {
        assets += balance;
      }
    }

    return AccountTotals(
      assets: assets,
      liabilities: liabilities,
      counted: counted,
      excluded: excluded,
    );
  }
}
