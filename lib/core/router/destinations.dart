import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// The 17 in-app destinations, matching the web app's sidebar exactly.
///
/// ## Why the label is a function
///
/// Phase 7.1b. These lists are `const` and built long before any
/// `BuildContext` exists, so a label cannot be a translated string — it has to
/// be something that resolves once a locale is known.
///
/// A const tear-off of a top-level function is the one form that keeps the
/// lists `const` **and** keeps the compiler involved: `_navDashboard` cannot
/// reference an ARB key that does not exist, and renaming a key in
/// `app_en.arb` breaks the build rather than shipping a raw key to the owner.
/// A `switch (path)` would have been shorter and would have failed at runtime
/// instead, on a destination someone forgot to add a case for.
class Destination {
  const Destination(this.path, this.label, this.icon);
  final String path;

  /// Resolved against the active locale at render time.
  final String Function(L) label;

  final IconData icon;
}

// One per destination. Trivial by design — their only job is to be a constant
// that the compiler can check against the generated `L`.
String _navDashboard(L l) => l.navDashboard;
String _navTransactions(L l) => l.navTransactions;
String _navReports(L l) => l.navReports;
String _navCalendar(L l) => l.navCalendar;
String _navBudgets(L l) => l.navBudgets;
String _navGoals(L l) => l.navGoals;
String _navAccounts(L l) => l.navAccounts;
String _navCredits(L l) => l.navCredits;
String _navRecurring(L l) => l.navRecurring;
String _navCategories(L l) => l.navCategories;
String _navNetWorth(L l) => l.navNetWorth;
String _navStocks(L l) => l.navStocks;
String _navLoans(L l) => l.navLoans;
String _navGold(L l) => l.navGold;
String _navInsights(L l) => l.navInsights;
String _navNotifications(L l) => l.navNotifications;
String _navSettings(L l) => l.navSettings;

/// The bottom bar's fifth slot, which opens the sheet rather than a route.
String navMoreLabel(L l) => l.navMore;

const List<Destination> appDestinations = [
  Destination('/', _navDashboard, LucideIcons.layoutGrid),
  Destination('/transactions', _navTransactions, LucideIcons.arrowRightLeft),
  Destination('/reports', _navReports, LucideIcons.chartPie),
  Destination('/calendar', _navCalendar, LucideIcons.calendar),
  Destination('/budgets', _navBudgets, LucideIcons.wallet),
  Destination('/goals', _navGoals, LucideIcons.goal),
  Destination('/accounts', _navAccounts, LucideIcons.landmark),
  Destination('/credits', _navCredits, LucideIcons.handCoins),
  Destination('/recurring', _navRecurring, LucideIcons.repeat),
  Destination('/categories', _navCategories, LucideIcons.tags),
  Destination('/net-worth', _navNetWorth, LucideIcons.trendingUp),
  Destination('/stocks', _navStocks, LucideIcons.chartLine),
  Destination('/loans', _navLoans, LucideIcons.banknote),
  Destination('/gold', _navGold, LucideIcons.coins),
  Destination('/insights', _navInsights, LucideIcons.sparkles),
  Destination('/notifications', _navNotifications, LucideIcons.bell),
  Destination('/settings', _navSettings, LucideIcons.settings),
];

/// The four tab slots either side of the centre FAB.
const List<Destination> tabDestinations = [
  Destination('/', _navDashboard, LucideIcons.layoutGrid),
  Destination('/transactions', _navTransactions, LucideIcons.arrowRightLeft),
  Destination('/reports', _navReports, LucideIcons.chartPie),
];

/// Everything reachable from the "More" sheet.
const List<Destination> moreDestinations = [
  Destination('/calendar', _navCalendar, LucideIcons.calendar),
  Destination('/budgets', _navBudgets, LucideIcons.wallet),
  Destination('/goals', _navGoals, LucideIcons.goal),
  Destination('/accounts', _navAccounts, LucideIcons.landmark),
  Destination('/credits', _navCredits, LucideIcons.handCoins),
  Destination('/recurring', _navRecurring, LucideIcons.repeat),
  Destination('/categories', _navCategories, LucideIcons.tags),
  Destination('/net-worth', _navNetWorth, LucideIcons.trendingUp),
  Destination('/stocks', _navStocks, LucideIcons.chartLine),
  Destination('/loans', _navLoans, LucideIcons.banknote),
  Destination('/gold', _navGold, LucideIcons.coins),
  Destination('/insights', _navInsights, LucideIcons.sparkles),
  Destination('/notifications', _navNotifications, LucideIcons.bell),
  Destination('/settings', _navSettings, LucideIcons.settings),
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
