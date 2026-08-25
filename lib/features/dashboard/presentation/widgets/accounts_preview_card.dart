import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/lucide_map.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../accounts/data/accounts_repository.dart';
import '../../../accounts/domain/account.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/presentation/transactions_providers.dart';

/// Up to four accounts with their balances, plus a "View all" jump.
class AccountsPreviewCard extends ConsumerWidget {
  const AccountsPreviewCard({super.key});

  static const int maxRows = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    // Best-effort: `/accounts` sometimes omits the running balance, and this
    // read fills it in. A failure here must never break the card.
    final balances = ref.watch(transactionBalanceProvider).valueOrNull;

    return accounts.when(
      loading: () => const LoadingCard(lines: 4),
      error: (error, _) => ErrorRetry(
        error: error,
        compact: true,
        onRetry: () => ref.invalidate(accountsFetchProvider),
      ),
      data: (items) => _Card(accounts: items, balances: balances),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.accounts, this.balances});

  final List<Account> accounts;
  final BalanceSnapshot? balances;

  @override
  Widget build(BuildContext context) {
    final visible = accounts
        .where((a) => !a.archived)
        .take(AccountsPreviewCard.maxRows)
        .toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Accounts',
            actionLabel: 'View all',
            onAction: () => context.go('/accounts'),
          ),
          if (visible.isEmpty)
            const EmptyState(title: 'No accounts yet', compact: true)
          else
            for (final account in visible) ...[
              const SizedBox(height: 14),
              _AccountRow(account: account, balance: _balanceOf(account)),
            ],
        ],
      ),
    );
  }

  num _balanceOf(Account account) =>
      account.balance ??
      balances?.byAccount[account.id] ??
      account.openingBalance;
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.balance});

  final Account account;
  final num balance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            lucideIcon(account.icon ?? account.type.icon),
            size: 17,
            color: c.mutedForeground,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                account.type.label,
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        MoneyText(
          balance,
          tone: balance < 0 ? MoneyTone.expense : MoneyTone.neutral,
          compactAbove: Money.crore,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
