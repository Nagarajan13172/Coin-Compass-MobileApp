import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/transactions/presentation/transaction_form_sheet.dart';
import '../../features/transactions/presentation/transactions_providers.dart';
import '../api/enums.dart';
import '../router/destinations.dart';
import '../theme/app_colors.dart';

/// The remaining 14 destinations, opened from the "More" tab.
class MoreSheet extends StatelessWidget {
  const MoreSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const MoreSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  const Text(
                    'More',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                shrinkWrap: true,
                itemCount: moreDestinations.length,
                separatorBuilder: (_, _) =>
                    Divider(color: c.border, height: 1, indent: 56),
                itemBuilder: (context, index) {
                  final d = moreDestinations[index];
                  return ListTile(
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c.secondary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(d.icon, size: 17, color: c.foreground),
                    ),
                    title: Text(
                      d.label,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Icon(
                      LucideIcons.chevronRight,
                      size: 17,
                      color: c.mutedForeground,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(d.path);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the FAB's "Add" menu.
///
/// [transactionType] marks the two rows that open the transaction form rather
/// than just landing on a screen; everything else is a plain jump.
@immutable
class AddChoice {
  const AddChoice({
    required this.label,
    required this.icon,
    required this.route,
    this.transactionType,
  });

  final String label;
  final IconData icon;
  final String route;
  final TransactionType? transactionType;
}

/// The FAB's "Add" menu.
///
/// [show] is the whole flow: it resolves the sheet to an [AddChoice], waits for
/// it to finish closing, then acts. Nothing runs inside a sheet that is on its
/// way out, so the quick-add can never race the dismissal.
class AddSheet extends StatelessWidget {
  const AddSheet({super.key});

  /// Opens the menu and carries out the choice. [location] is the route the
  /// shell is already on, so a quick-add from the ledger doesn't re-navigate.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required String location,
  }) async {
    final choice = await showModalBottomSheet<AddChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddSheet(),
    );
    if (choice == null || !context.mounted) return;

    final type = choice.transactionType;
    if (type == null) {
      context.go(choice.route);
      return;
    }

    // Land on the ledger first, so the row the user is about to log appears
    // under the form they logged it in.
    if (location != choice.route) {
      context.go(choice.route);
      // Let the new route build before a sheet is pushed over it.
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;
    }

    final container = ProviderScope.containerOf(context, listen: false);
    final saved = await showTransactionSheet(context, ref, initialType: type);
    if (saved == null) return;

    // The ledger may be filtered to a month the new row falls outside of, so
    // reload rather than splicing it in blind. The form sheet has already
    // dropped the balance, summary and account caches.
    if (container.exists(transactionsListProvider)) {
      await container.read(transactionsListProvider.notifier).refresh();
    }
  }

  static const List<AddChoice> _items = [
    AddChoice(
      label: 'Transaction',
      icon: LucideIcons.arrowRightLeft,
      route: '/transactions',
      transactionType: TransactionType.expense,
    ),
    AddChoice(
      label: 'Transfer',
      icon: LucideIcons.arrowLeftRight,
      route: '/transactions',
      transactionType: TransactionType.transfer,
    ),
    AddChoice(label: 'Account', icon: LucideIcons.landmark, route: '/accounts'),
    AddChoice(label: 'Budget', icon: LucideIcons.wallet, route: '/budgets'),
    AddChoice(label: 'Goal', icon: LucideIcons.goal, route: '/goals'),
    AddChoice(label: 'Loan', icon: LucideIcons.banknote, route: '/loans'),
    AddChoice(label: 'Credit', icon: LucideIcons.handCoins, route: '/credits'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Same shape as MoreSheet above: cap the height and let the rows scroll.
    // Unbounded, the seven tiles need 446dp and the last two ("Loan",
    // "Credit") land below the screen edge in landscape — unreachable, since
    // nothing here scrolls. The Flexible + ListView is the load-bearing part;
    // the ConstrainedBox alone would still overflow.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final item in _items)
                    ListTile(
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(item.icon, size: 17, color: c.primary),
                      ),
                      title: Text(
                        item.label,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(item),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
