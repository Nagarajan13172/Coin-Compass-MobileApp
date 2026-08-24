/// Phase 6.3 — **one** definition of "reload what is on screen".
///
/// Every screen's pull-to-refresh and the automatic recovery after a connection
/// comes back both route through here, so the two cannot drift. Seventeen
/// screens each keeping their own private `_refresh` is exactly the drift the
/// Phase 4 integrator had to reconcile.
///
/// ## Only the visible route
///
/// Recovery refreshes the route the owner is looking at and nothing else.
/// Re-invalidating all seventeen screens' providers on every reconnect is the
/// hammering the brief warns about.
///
/// ## It cannot fire a gated read
///
/// The three wealth-gated routes consult [wealthReadAllowed] first, exactly as
/// [refreshDashboard] does for `/networth/history`. Recovery must never be the
/// thing that issues a gated GET while the Net Worth lock is on.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/enums.dart';
import '../../features/accounts/data/accounts_repository.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/budgets/data/budgets_repository.dart';
import '../../features/budgets/presentation/budgets_providers.dart';
import '../../features/calendar/presentation/calendar_providers.dart';
import '../../features/categories/data/categories_repository.dart';
import '../../features/credits/data/credits_repository.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/goals/data/goals_repository.dart';
import '../../features/gold/data/metals_repository.dart';
import '../../features/holdings/data/holdings_repository.dart';
import '../../features/insights/presentation/insights_providers.dart';
import '../../features/loans/data/loans_repository.dart';
import '../../features/networth/data/networth_repository.dart';
import '../../features/networth/presentation/networth_providers.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/people/data/people_repository.dart';
import '../../features/recurring/data/recurring_repository.dart';
import '../../features/reports/presentation/reports_providers.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/splits/data/splits_repository.dart';
import '../../features/stocks/data/stocks_repository.dart';
import '../../features/transactions/presentation/transactions_providers.dart';
import '../../features/wealth_lock/domain/wealth_lock.dart';
import '../../features/wealth_lock/presentation/wealth_lock_providers.dart';


/// How long a bump of `onlineRevisionProvider` is ignored after a refresh, so a
/// flapping connection cannot become a refresh loop.
const Duration kRecoveryCooldown = Duration(seconds: 10);

/// Reloads the reads behind [location]. Never throws: each card renders its own
/// [ErrorRetry], so the spinner should stop either way.
Future<void> refreshCurrentRoute(WidgetRef ref, String location) {
  final path = _normalise(location);
  return switch (path) {
    '/' => refreshDashboard(ref),
    '/transactions' => _refreshTransactions(ref),
    '/reports' => refreshReports(ref),
    '/insights' => refreshInsights(ref),
    '/calendar' => _refreshCalendar(ref),
    '/budgets' => _refreshBudgets(ref),
    '/goals' => _reload(
      () => ref.invalidate(goalsProvider),
      () => ref.read(goalsProvider.future),
    ),
    '/accounts' => _refreshAccounts(ref),
    '/credits' => _refreshCredits(ref),
    '/credits/people' => _refreshPeople(ref),
    '/credits/splits' => _reload(
      () => ref.invalidate(splitsProvider),
      () => ref.read(splitsProvider.future),
    ),
    '/recurring' => _reload(
      () => ref.invalidate(recurringRulesProvider),
      () => ref.read(recurringRulesProvider.future),
    ),
    '/categories' => _reload(
      () => ref.invalidate(categoriesProvider),
      () => ref.read(categoriesProvider.future),
    ),
    '/net-worth' => _refreshNetWorth(ref),
    '/net-worth/holdings' => _refreshHoldings(ref),
    '/stocks' => _refreshStocks(ref),
    '/loans' => _reload(
      () => ref.invalidate(loansProvider),
      () => ref.read(loansProvider.future),
    ),
    '/gold' => _refreshGold(ref),
    '/notifications' => _reload(
      () => ref.invalidate(notificationFeedProvider),
      () => ref.read(notificationFeedProvider.future),
    ),
    '/settings' => _refreshSettings(ref),
    // An unmapped route reloads nothing rather than guessing. A new screen
    // added in Phase 7 simply does not auto-recover until it is listed here,
    // which is the same fail-quiet the cache's allow-list uses.
    _ => Future<void>.value(),
  };
}

String _normalise(String location) {
  var path = location.trim();
  final cut = path.indexOf(RegExp(r'[?#]'));
  if (cut >= 0) path = path.substring(0, cut);
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path.isEmpty ? '/' : path;
}

// ─────────────────────────────────────────────────────────────────────────────
// The dashboard
// ─────────────────────────────────────────────────────────────────────────────

/// Drop every cached read behind the dashboard, then wait for them all to
/// settle. Failures are swallowed here because each card renders its own
/// [ErrorRetry] — the spinner should stop either way.
///
/// `/networth/history` is the one conditional read. It used to be invalidated
/// and re-read unconditionally, which would have fired a gated GET on every
/// pull while the lock was on — and, if the server redacts that payload, would
/// have handed `NetWorthCard` a zero to render as the owner's net worth.
Future<void> refreshDashboard(WidgetRef ref) async {
  final netWorthAllowed = wealthReadAllowed(ref.read(wealthVisibilityProvider));

  ref
    ..invalidate(dashboardSummaryProvider)
    ..invalidate(dashboardTrendProvider)
    ..invalidate(dashboardCategoryProvider)
    ..invalidate(accountsProvider)
    ..invalidate(metalsLatestProvider)
    ..invalidate(netWorthHistoryProvider)
    ..invalidate(transactionBalanceProvider)
    ..invalidate(transactionsPageProvider);

  await Future.wait(<Future<void>>[
    settle(ref.read(dashboardSummaryProvider.future)),
    settle(ref.read(dashboardTrendProvider.future)),
    settle(ref.read(dashboardCategoryProvider.future)),
    settle(ref.read(accountsProvider.future)),
    settle(ref.read(metalsLatestProvider.future)),
    if (netWorthAllowed) settle(ref.read(netWorthHistoryProvider.future)),
    settle(ref.read(transactionsPageProvider(recentTransactionsQuery).future)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-route sets. Each one is verbatim what its screen's private `_refresh`
// used to do; the screens now delegate here.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _refreshTransactions(WidgetRef ref) async {
  ref
    ..invalidate(transactionBalanceProvider)
    ..invalidate(transactionBalanceAsOfProvider)
    ..invalidate(transactionTagsProvider);
  try {
    await ref.read(transactionsListProvider.notifier).refresh();
  } on Object {
    // Rendered by the list's own error surface.
  }
}

Future<void> _refreshCalendar(WidgetRef ref) {
  final month = ref.read(calendarMonthAnchorProvider);
  ref.invalidate(calendarMonthProvider(month));
  return settle(ref.read(calendarMonthProvider(month).future));
}

Future<void> _refreshBudgets(WidgetRef ref) {
  ref.invalidate(budgetsProvider);
  for (final period in BudgetPeriod.values) {
    ref.invalidate(budgetSpendProvider(period));
  }
  return settle(ref.read(budgetsProvider.future));
}

Future<void> _refreshAccounts(WidgetRef ref) {
  ref
    ..invalidate(accountsProvider)
    ..invalidate(transactionBalanceProvider);
  return settle(ref.read(accountsProvider.future));
}

Future<void> _refreshCredits(WidgetRef ref) {
  ref
    ..invalidate(creditsProvider)
    ..invalidate(splitsProvider);
  return settle(ref.read(creditsProvider.future));
}

Future<void> _refreshPeople(WidgetRef ref) {
  ref
    ..invalidate(peopleProvider)
    ..invalidate(personGroupsProvider);
  return settle(ref.read(peopleProvider.future));
}

Future<void> _refreshGold(WidgetRef ref) {
  ref
    ..invalidate(metalsLatestProvider)
    ..invalidate(metalsHistoryProvider);
  return settle(ref.read(metalsLatestProvider.future));
}

Future<void> _refreshSettings(WidgetRef ref) {
  ref
    ..invalidate(settingsProvider)
    ..invalidate(twoFactorStatusProvider)
    ..invalidate(accountsProvider)
    ..invalidate(categoriesProvider)
    ..invalidate(goalsProvider)
    ..invalidate(loansProvider);
  return settle(ref.read(settingsProvider.future));
}

// ── the three gated routes ──────────────────────────────────────────────────

Future<void> _refreshNetWorth(WidgetRef ref) {
  if (!_wealthAllowed(ref)) return Future<void>.value();
  ref
    ..invalidate(netWorthHistoryProvider)
    ..invalidate(netWorthHistoryRangeProvider)
    ..invalidate(holdingsProvider)
    ..invalidate(loansProvider);
  return settle(ref.read(netWorthSeriesProvider.future));
}

Future<void> _refreshHoldings(WidgetRef ref) {
  if (!_wealthAllowed(ref)) return Future<void>.value();
  ref.invalidate(holdingsProvider);
  return settle(ref.read(holdingsProvider.future));
}

Future<void> _refreshStocks(WidgetRef ref) {
  if (!_wealthAllowed(ref)) return Future<void>.value();
  ref
    ..invalidate(stockPortfolioProvider)
    ..invalidate(stockSalesProvider)
    ..invalidate(stockSplitsProvider);
  return settle(ref.read(stockPortfolioProvider.future));
}

bool _wealthAllowed(WidgetRef ref) =>
    wealthReadAllowed(ref.read(wealthVisibilityProvider));

// ─────────────────────────────────────────────────────────────────────────────

/// Invalidate, then wait for the re-read to settle. Two closures rather than a
/// generic over `ProviderBase`, because `.future` is only reachable from the
/// concrete provider type.
Future<void> _reload(
  void Function() invalidate,
  Future<Object?> Function() read,
) {
  invalidate();
  return settle(read());
}

/// Swallows a failure so a `RefreshIndicator` spinner always stops — the error
/// itself is already carried into the provider and rendered by the screen.
Future<void> settle(Future<Object?> future) async {
  try {
    await future;
  } on Object {
    // Handled by the card that owns the read.
  }
}
