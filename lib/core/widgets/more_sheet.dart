import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

/// The FAB's "Add" menu.
class AddSheet extends StatelessWidget {
  const AddSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const AddSheet(),
  );

  static const List<({String label, IconData icon, String route})> _items = [
    (
      label: 'Transaction',
      icon: LucideIcons.arrowRightLeft,
      route: '/transactions',
    ),
    (
      label: 'Transfer',
      icon: LucideIcons.arrowLeftRight,
      route: '/transactions',
    ),
    (label: 'Account', icon: LucideIcons.landmark, route: '/accounts'),
    (label: 'Budget', icon: LucideIcons.wallet, route: '/budgets'),
    (label: 'Goal', icon: LucideIcons.goal, route: '/goals'),
    (label: 'Loan', icon: LucideIcons.banknote, route: '/loans'),
    (label: 'Credit', icon: LucideIcons.handCoins, route: '/credits'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
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
              onTap: () {
                Navigator.of(context).pop();
                context.go(item.route);
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
