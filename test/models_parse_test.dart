import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/api/paginated.dart';
import 'package:coincompass/features/accounts/domain/account.dart';
import 'package:coincompass/features/categories/domain/category.dart';
import 'package:coincompass/features/credits/domain/credit.dart';
import 'package:coincompass/features/gold/domain/metal_price.dart';
import 'package:coincompass/features/loans/domain/loan.dart';
import 'package:coincompass/features/networth/domain/net_worth_point.dart';
import 'package:coincompass/features/notifications/domain/app_notification.dart';
import 'package:coincompass/features/recurring/domain/recurring_rule.dart';
import 'package:coincompass/features/reports/domain/report_models.dart';
import 'package:coincompass/features/settings/domain/app_settings.dart';
import 'package:coincompass/features/stocks/domain/stock.dart';
import 'package:coincompass/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

Map<String, dynamic> asMap(Object? v) => (v as Map).cast<String, dynamic>();
List<Map<String, dynamic>> asList(Object? v) =>
    (v as List).map((e) => (e as Map).cast<String, dynamic>()).toList();

void main() {
  test('transactions envelope + populated category ref', () {
    final page = Paginated.fromJson(
      fixture('transactions'),
      Transaction.fromJson,
    );
    expect(page.total, 2);
    expect(page.hasMore, isFalse);
    expect(page.items, hasLength(2));

    final t = page.items.first;
    expect(t.type, TransactionType.expense);
    expect(t.amount, 12312);
    expect(t.signedAmount, -12312);
    // `category` arrives as a populated object, `account` as null.
    expect(t.categoryId, '6a4669f861d974fd74ab427f');
    expect(t.category?.name, 'Groceries');
    expect(t.category?.color, '#22C55E');
    expect(t.accountId, isNull);
    expect(t.account, isNull);
    expect(t.isRecurring, isTrue);
    expect(t.title, 'Groceries');
  });

  test('transactions summary + balance', () {
    final s = TransactionSummary.fromJson(
      asMap(fixture('transactions_summary')),
    );
    expect(s.expense, 13312);
    expect(s.net, -13312);
    expect(s.count, 2);

    final b = BalanceSnapshot.fromJson(asMap(fixture('transactions_balance')));
    expect(b.balance, 0);
    expect(b.byAccount, isEmpty);
  });

  test('categories — all 33 parse, enums and groups intact', () {
    final list = asList(fixture('categories')).map(Category.fromJson).toList();
    expect(list, hasLength(33));
    expect(list.every((c) => c.id.isNotEmpty), isTrue);
    expect(list.every((c) => c.name.isNotEmpty), isTrue);
    final food = list.firstWhere((c) => c.name == 'Food & Dining');
    expect(food.type, CategoryType.expense);
    expect(food.icon, 'utensils');
    expect(food.group, 'food');
    expect(food.isDefault, isTrue);
    expect(list.any((c) => c.type == CategoryType.income), isTrue);
  });

  test('loans — reducing-balance maths', () {
    final list = asList(fixture('loans')).map(Loan.fromJson).toList();
    expect(list, hasLength(1));
    final l = list.first;
    expect(l.name, 'Deena');
    expect(l.lender, 'UCO');
    expect(l.type, LoanType.home);
    expect(l.status, LoanStatus.active);
    expect(l.isActive, isTrue);
    expect(l.outstanding, 20000000);
    expect(l.roi, 7.25);
    expect(l.emi, 137000);
    // 2 crore at 7.25% => ~1.2L monthly interest; EMI of 1.37L does amortise.
    expect(l.monthlyInterest, closeTo(120833, 1));
    expect(l.monthsRemaining, isNotNull);
    expect(l.monthsRemaining! > 300, isTrue);
  });

  test('recurring — upcoming projections and cadence', () {
    final list = asList(
      fixture('recurring'),
    ).map(RecurringRule.fromJson).toList();
    expect(list, hasLength(2));
    final r = list.first;
    expect(r.frequency, Frequency.monthly);
    expect(r.interval, 1);
    expect(r.cadenceLabel, 'Monthly');
    expect(r.active, isTrue);
    expect(r.upcoming, hasLength(5));
    expect(r.upcoming.first.year, 2026);
    expect(r.category?.name, 'Groceries');
    expect(r.nextRun, isNotNull);
    expect(r.lastRun, isNotNull);
  });

  test('settings — currencies and defaults', () {
    final s = AppSettings.fromJson(asMap(fixture('settings')));
    expect(s.name, 'My Wallet');
    expect(s.baseCurrency, 'INR');
    expect(s.symbol, '₹');
    expect(s.locale, 'en-IN');
    expect(s.firstDayOfWeek, 1);
    expect(s.emailReports, isTrue);
    expect(s.pinEnabled, isFalse);
    expect(s.currencies, hasLength(4));
    expect(
      s.currencies.map((c) => c.code),
      containsAll(['INR', 'USD', 'EUR', 'GBP']),
    );
    expect(s.currencies.firstWhere((c) => c.code == 'USD').rateToBase, 83);
  });

  test('stocks portfolio — empty but configured', () {
    final p = StockPortfolio.fromJson(asMap(fixture('stocks_portfolio')));
    expect(p.configured, isTrue);
    expect(p.positions, isEmpty);
    expect(p.totals.marketValue, 0);
    expect(p.pricedAt, isNull);
    expect(p.anyStale, isFalse);
  });

  test('metals latest — gold and silver', () {
    final m = MetalsLatest.fromJson(asMap(fixture('metals_latest')));
    expect(m.configured, isTrue);
    expect(m.gold, isNotNull);
    expect(m.gold!.isGold, isTrue);
    expect(m.gold!.retail22k, 14950);
    expect(m.gold!.headlinePrice, 14950);
    expect(m.gold!.pricePerGram24k, 14167.53);
    expect(m.gold!.source, contains('GRT'));
    // silver's retail fields come back 0 -> headline falls back to per-gram
    expect(m.silver!.retail24k, 0);
    expect(m.silver!.headlinePrice, 270);
  });

  test('net worth history — tolerates rows missing stocksTotal', () {
    final list = asList(
      fixture('networth_history'),
    ).map(NetWorthPoint.fromJson).toList();
    expect(list, hasLength(2));
    expect(list.first.stocksTotal, 0); // absent on the older row
    expect(list.last.stocksTotal, 0);
    expect(list.first.netWorth, -20750633);
    expect(list.first.liabilities, 20000000);
    expect(list.first.date.year, 2026);
  });

  test('reports — summary, by-category, trend', () {
    final s = ReportSummary.fromJson(asMap(fixture('reports_summary')));
    expect(s.expense, 13312);
    expect(s.consumption, 13312);
    expect(s.rangeStart, isNotNull);
    expect(s.rangeEnd, isNotNull);

    final slices = asList(
      fixture('reports_by-category'),
    ).map(CategorySlice.fromJson).toList();
    expect(slices, hasLength(1));
    expect(slices.first.name, 'Groceries');
    expect(slices.first.percent, 100);
    expect(slices.first.color, '#22C55E');
    expect(slices.first.group, 'food');

    final trend = asList(
      fixture('reports_trend'),
    ).map(TrendPoint.fromJson).toList();
    expect(trend, hasLength(1));
    expect(trend.first.bucket, '2026-08-04');
    expect(trend.first.expense, 13312);
    expect(trend.first.date, isNotNull);
  });

  test('insights — null pct and savingsRate survive', () {
    final i = Insights.fromJson(asMap(fixture('reports_insights')));
    expect(i.period, 'month');
    expect(i.expense.current, 13312);
    expect(i.expense.previous, 0);
    expect(i.expense.pct, isNull); // previous was 0 -> API sends null
    expect(i.savingsRateCurrent, isNull);
    expect(i.pace.daysElapsed, 24);
    expect(i.pace.daysInPeriod, 31);
    expect(i.pace.avgPerDay, closeTo(554.67, 0.01));
    expect(i.pace.projected, 17195);
    expect(i.movers, hasLength(1));
    expect(i.movers.first.name, 'Groceries');
    expect(i.movers.first.pct, isNull);
  });

  test('notifications — feed envelope and params', () {
    final f = NotificationFeed.fromJson(fixture('notifications'));
    expect(f.items, isNotEmpty);
    final n = f.items.first;
    expect(n.type, 'recurring.posted');
    expect(n.link, '/recurring');
    expect(n.read, isFalse);
    expect(n.amount, 12312);
    expect(n.currency, 'INR');
    expect(n.countParam, 1);
    expect(n.title, 'Recurring');
  });

  test('two-factor status', () {
    final s = TwoFactorStatus.fromJson(asMap(fixture('auth_2fa_status')));
    expect(s.enabled, isFalse);
    expect(s.emailFallback, isTrue);
    expect(s.backupCodesRemaining, 0);
  });

  test('empty-array endpoints parse to empty lists', () {
    for (final name in [
      'accounts',
      'budgets',
      'goals',
      'credits',
      'holdings',
      'templates',
      'splits',
      'people',
    ]) {
      final raw = fixture(name);
      expect(raw, isA<List>(), reason: '$name should be a JSON array');
      expect((raw as List), isEmpty, reason: '$name is empty on this account');
    }
    expect(asList(fixture('accounts')).map(Account.fromJson).toList(), isEmpty);
    expect(asList(fixture('credits')).map(Credit.fromJson).toList(), isEmpty);
  });
}
