import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/widgets.dart';

/// The 17 in-app destinations, matching the web app's sidebar exactly.
class Destination {
  const Destination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const List<Destination> appDestinations = [
  Destination('/', 'Dashboard', LucideIcons.layoutGrid),
  Destination('/transactions', 'Transactions', LucideIcons.arrowRightLeft),
  Destination('/reports', 'Reports', LucideIcons.chartPie),
  Destination('/calendar', 'Calendar', LucideIcons.calendar),
  Destination('/budgets', 'Budgets', LucideIcons.wallet),
  Destination('/goals', 'Goals', LucideIcons.goal),
  Destination('/accounts', 'Accounts', LucideIcons.landmark),
  Destination('/credits', 'Credits', LucideIcons.handCoins),
  Destination('/recurring', 'Recurring', LucideIcons.repeat),
  Destination('/categories', 'Categories', LucideIcons.tags),
  Destination('/net-worth', 'Net Worth', LucideIcons.trendingUp),
  Destination('/stocks', 'Stocks', LucideIcons.chartLine),
  Destination('/loans', 'Loans', LucideIcons.banknote),
  Destination('/gold', 'Gold & Silver', LucideIcons.coins),
  Destination('/insights', 'Insights', LucideIcons.sparkles),
  Destination('/notifications', 'Notifications', LucideIcons.bell),
  Destination('/settings', 'Settings', LucideIcons.settings),
];

/// The four tab slots either side of the centre FAB.
const List<Destination> tabDestinations = [
  Destination('/', 'Dashboard', LucideIcons.layoutGrid),
  Destination('/transactions', 'Transactions', LucideIcons.arrowRightLeft),
  Destination('/reports', 'Reports', LucideIcons.chartPie),
];

/// Everything reachable from the "More" sheet.
const List<Destination> moreDestinations = [
  Destination('/calendar', 'Calendar', LucideIcons.calendar),
  Destination('/budgets', 'Budgets', LucideIcons.wallet),
  Destination('/goals', 'Goals', LucideIcons.goal),
  Destination('/accounts', 'Accounts', LucideIcons.landmark),
  Destination('/credits', 'Credits', LucideIcons.handCoins),
  Destination('/recurring', 'Recurring', LucideIcons.repeat),
  Destination('/categories', 'Categories', LucideIcons.tags),
  Destination('/net-worth', 'Net Worth', LucideIcons.trendingUp),
  Destination('/stocks', 'Stocks', LucideIcons.chartLine),
  Destination('/loans', 'Loans', LucideIcons.banknote),
  Destination('/gold', 'Gold & Silver', LucideIcons.coins),
  Destination('/insights', 'Insights', LucideIcons.sparkles),
  Destination('/notifications', 'Notifications', LucideIcons.bell),
  Destination('/settings', 'Settings', LucideIcons.settings),
];

/// The "More" rows a user may actually see.
///
/// Web parity, and it is a **removal**, not a disable:
///
///     Wf.filter(d => !Gf.includes(d.to) && (o || !UM.includes(d.to)))
///
/// where `o` is the visibility predicate and `UM` is `["/net-worth","/stocks"]`.
/// The web takes the gated entries out of the nav entirely, and the sidebar
/// then drops any group left empty. A disabled-but-visible row would advertise
/// the lock to exactly the person the everyday login is meant to be shareable
/// with, which is the whole point of the feature.
///
/// Pure and total so it can be asserted directly; the shell's "More" highlight
/// still reads the full [moreDestinations] list, so the tab stays lit when an
/// unlocked user is sitting on `/net-worth`.
List<Destination> visibleMoreDestinations(bool wealthVisible) {
  if (wealthVisible) return moreDestinations;
  return [
    for (final d in moreDestinations)
      if (!gatedNavPaths.contains(d.path)) d,
  ];
}

/// The nav entries the Net Worth lock removes. Verbatim `UM` from the bundle.
/// `/net-worth/holdings` is not here because it has no nav row of its own.
const Set<String> gatedNavPaths = {'/net-worth', '/stocks'};
