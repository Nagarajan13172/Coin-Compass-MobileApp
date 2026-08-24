import 'package:flutter/material.dart';

import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/lucide_map.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/money_text.dart';
import '../../domain/account.dart';

/// One row in the Accounts list: tinted type glyph, name, institution / last4,
/// and the account's balance on the right.
///
/// Designed to sit inside a shared AppCard with sibling rows, so it paints no
/// surface of its own — only its own ink response.
class AccountTile extends StatelessWidget {
  const AccountTile({
    super.key,
    required this.account,
    required this.balance,
    this.onTap,
  });

  final Account account;

  /// Already resolved by the caller — see `resolveAccountBalance`.
  final num balance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent =
        colorFromHex(account.color) ?? accountAccent(context, account.type);
    final subtitle = _subtitle();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  lucideIcon(account.icon ?? account.type.icon),
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
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
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    balance,
                    tone: balance < 0 ? MoneyTone.expense : MoneyTone.neutral,
                    compactAbove: Money.crore,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (account.creditLimit != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Limit ${Money.compact(account.creditLimit!)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _subtitle() {
    final parts = <String>[
      if (account.institution != null && account.institution!.trim().isNotEmpty)
        account.institution!.trim(),
      if (account.last4 != null && account.last4!.trim().isNotEmpty)
        '••${account.last4!.trim()}',
      if (account.excludeFromTotal) 'Excluded from total',
      if (account.archived) 'Archived',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Token-derived accent per account type — cash and savings read as money in,
/// cards as money owed, everything else as the app's primary.
Color accountAccent(BuildContext context, AccountType type) {
  final c = context.colors;
  return switch (type) {
    AccountType.cash || AccountType.savings => c.income,
    AccountType.card => c.expense,
    AccountType.bank ||
    AccountType.wallet ||
    AccountType.upi ||
    AccountType.demat => c.primary,
  };
}

/// The balance to show for [account]: the server's own figure when it sent one,
/// otherwise the running total from `/transactions/balance`, otherwise the
/// opening balance the user entered.
num resolveAccountBalance(Account account, Map<String, num> byAccount) =>
    account.balance ?? byAccount[account.id] ?? account.openingBalance;
