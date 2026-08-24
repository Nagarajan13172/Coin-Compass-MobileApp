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
