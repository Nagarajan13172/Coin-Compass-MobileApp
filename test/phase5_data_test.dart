import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/utils/date_x.dart';
import 'package:coincompass/core/utils/money.dart';
import 'package:coincompass/features/insights/domain/insights.dart';
import 'package:coincompass/features/insights/presentation/insights_providers.dart';
import 'package:coincompass/features/notifications/domain/app_notification.dart';
import 'package:coincompass/features/reports/data/export_repository.dart';
import 'package:coincompass/features/reports/domain/report_metrics.dart';
import 'package:coincompass/features/reports/domain/report_models.dart';
import 'package:coincompass/features/reports/presentation/period.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:coincompass/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 5 data layer, pinned against the live captures in `test/fixtures/`
/// (byte-identical copies of what the owner's account actually returns).
///
/// The account is sparse on purpose — 2 transactions, 1 category, 0 accounts,
/// 0 income, no previous period — so the null and empty branches below are the
/// *normal* path, not edge cases. Every one of them is what the screens will
/// render on first open.
Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

Map<String, dynamic> asMap(Object? v) => (v as Map).cast<String, dynamic>();
List<Map<String, dynamic>> asList(Object? v) =>
    (v as List).map((e) => (e as Map).cast<String, dynamic>()).toList();

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('reports — /reports/summary', () {
    test('the live capture, including the consumption split', () {
      final s = ReportSummary.fromJson(asMap(fixture('reports_summary')));
      expect(s.income, 0);
      expect(s.expense, 13312);
      expect(s.net, -13312);
      expect(s.expenseCount, 2);
      expect(s.count, 2);
      // Savings rate divides by `consumption`, so it has to survive parsing
      // even though it happens to equal `expense` on this account.
      expect(s.consumption, 13312);
      expect(s.nonConsumption, 0);
      expect(s.byCurrency, isEmpty);
      expect(s.rangeStart, isNotNull);
      expect(s.rangeEnd, isNotNull);
    });
  });

  group('reports — /reports/by-category', () {
    test('the one category this account has', () {
      final slices = asList(
        fixture('reports_by-category'),
      ).map(CategorySlice.fromJson).toList();

      expect(slices, hasLength(1));
      final groceries = slices.single;
      expect(groceries.name, 'Groceries');
      expect(groceries.categoryId, '6a4669f861d974fd74ab427f');
      expect(groceries.total, 13312);
      expect(groceries.color, '#22C55E');
      expect(groceries.icon, 'shopping-cart');
      // The group key drives the donut's "Groups" mode.
      expect(groceries.group, 'food');
      expect(groceries.percent, 100);
    });
  });

  group('reports — /reports/by-account', () {
    // The live response is `[]` (the owner has no accounts), so the field
    // names come from the deployed bundle: {_id, name, color, income, expense,
    // transferIn, transferOut}. There is no `net`, `total` or `count` — the
    // model derives all three, which is the correction this phase made.
    const rows = [
      {
        '_id': 'a1',
        'name': 'HDFC',
        'color': '#3B82F6',
        'income': 50000,
        'expense': 12000,
        'transferIn': 2000,
        'transferOut': 8000,
      },
      {
        '_id': 'a2',
        'name': 'Cash',
        'color': '#64748B',
        'income': 0,
        'expense': 750,
        'transferIn': 0,
        'transferOut': 0,
      },
    ];

    test('money in / out / net are derived, not read', () {
      final slices = rows
          .map((e) => AccountSlice.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final hdfc = slices.first;
      expect(hdfc.accountId, 'a1');
      expect(hdfc.name, 'HDFC');
      expect(hdfc.color, '#3B82F6');
      expect(hdfc.moneyIn, 52000); // income + transferIn
      expect(hdfc.moneyOut, 20000); // expense + transferOut
      expect(hdfc.net, 32000);

      final cash = slices.last;
      expect(cash.moneyIn, 0);
      expect(cash.moneyOut, 750);
      expect(cash.net, -750);
    });

    test('an account-less wallet parses to an empty list', () {
      expect(
        <Map<String, dynamic>>[].map(AccountSlice.fromJson).toList(),
        isEmpty,
      );
    });
  });

  group('reports — /reports/trend buckets', () {
    test('the live day bucket', () {
      final points = asList(
        fixture('reports_trend'),
      ).map(TrendPoint.fromJson).toList();

      expect(points, hasLength(1)); // sparse: one bucket for the whole month
      final day = points.single;
      expect(day.bucket, '2026-08-04');
      expect(day.expense, 13312);
      expect(day.granularity, TrendGranularity.day);
      expect(day.date, DateTime(2026, 8, 4));
      expect(day.axisLabel, '04 Aug');
      expect(day.window?.from, DateTime(2026, 8, 4));
      expect(day.window?.to, DateTime(2026, 8, 5));
    });

    test('a month bucket — which DateTime.parse alone cannot read', () {
      // `?granularity=month` returns `2026-08`. Dart's parser requires a day,
      // so the naive `DateTime.tryParse(bucket)` used before returned null and
      // the year view fell back to printing the raw bucket on its axis.
      const point = TrendPoint(bucket: '2026-08', expense: 13312);
      expect(point.granularity, TrendGranularity.month);
      expect(point.date, DateTime(2026, 8));
      expect(point.axisLabel, 'Aug');
      expect(point.window?.from, DateTime(2026, 8));
      expect(point.window?.to, DateTime(2026, 9));
    });

    test('an ISO week bucket stays unparsed, and the tap stays a no-op', () {
      // `?granularity=week` is supported server-side but nothing sends it —
      // `2026-W32` is not a date any formatter here or on the web can read.
      const point = TrendPoint(bucket: '2026-W32');
      expect(point.granularity, TrendGranularity.week);
      expect(point.date, isNull);
      expect(point.window, isNull);
      expect(point.axisLabel, '2026-W32'); // raw, never a guess
    });

    test('the query vocabulary is exactly what the server accepts', () {
      expect(TrendGranularity.day.api, 'day');
      expect(TrendGranularity.month.api, 'month');
      expect(TrendGranularity.week.api, 'week');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('reports — derived stat-card figures', () {
    final august = PeriodRange(
      PeriodKind.month,
      DateTime(2026, 8),
      DateTime(2026, 9),
    );

    test('days elapsed counts calendar days so far, not the whole month', () {
      // 1 Aug through 24 Aug inclusive.
      expect(
        ReportMetrics.daysElapsed(
          august.start,
          august.end,
          now: DateTime(2026, 8, 24, 16, 50),
        ),
        24,
      );
    });

    test('a closed period counts its own length, not one day more', () {
      // The exclusive end is 1 Sep 00:00; using it directly would say 32.
      expect(
        ReportMetrics.daysElapsed(
          august.start,
          august.end,
          now: DateTime(2026, 12, 1),
        ),
        31,
      );
    });

    test('a period that has not started yet still divides by a day', () {
      expect(
        ReportMetrics.daysElapsed(
          august.start,
          august.end,
          now: DateTime(2026, 1, 1),
        ),
        1,
      );
    });

    test('avg daily spend keeps its decimals', () {
      final summary = ReportSummary.fromJson(asMap(fixture('reports_summary')));
      final avg = ReportMetrics.avgDailySpend(
        summary,
        august.start,
        august.end,
        now: DateTime(2026, 8, 24, 16, 50),
      );
      // 13312 / 24 — the web renders ₹554.67 here and rounds only on Insights.
      expect(avg, closeTo(554.6666, 0.001));
      expect(Money.format(avg), '₹554.67');
    });

    test('savings rate divides by consumption and is null without income', () {
      final live = ReportSummary.fromJson(asMap(fixture('reports_summary')));
      // income 0 -> null, which the card renders as an em dash. Not 0%.
      expect(ReportMetrics.savingsRate(live), isNull);

      // The distinction that matters: 90k spent of 100k earned, but 50k of it
      // went into a deposit, so only 40k was consumed -> 60%, not 10%.
      const saver = ReportSummary(
        income: 100000,
        expense: 90000,
        consumption: 40000,
        nonConsumption: 50000,
      );
      expect(ReportMetrics.savingsRate(saver), 60);
    });

    test('the period-over-period change is null without a baseline', () {
      expect(ReportMetrics.changeVsPrevious(13312, 0), isNull);
      expect(ReportMetrics.changeVsPrevious(4000, 3000), 33);
      expect(ReportMetrics.changeVsPrevious(1500, 3000), -50);
    });

    test('the biggest slice, and nothing to pick from', () {
      const slices = [
        CategorySlice(name: 'Groceries', total: 13312),
        CategorySlice(name: 'Fuel', total: 22000),
        CategorySlice(name: 'Coffee', total: 400),
      ];
      expect(ReportMetrics.biggest(slices)?.name, 'Fuel');
      expect(ReportMetrics.biggest(const []), isNull);
    });
  });

  group('reports — the period pager label', () {
    test('the web never says "This month"', () {
      final august = PeriodRange(
        PeriodKind.month,
        DateTime(2026, 8),
        DateTime(2026, 9),
      );
      expect(august.periodLabel, 'August 2026');

      final year = PeriodRange(
        PeriodKind.year,
        DateTime(2026),
        DateTime(2027),
      );
      expect(year.periodLabel, '2026');
    });

    test('a week names its last day, not the exclusive end', () {
      final week = PeriodRange(
        PeriodKind.week,
        DateTime(2026, 8, 4),
        DateTime(2026, 8, 11),
      );
      // EN DASH, and 10 Aug — the day inside the window.
      expect(week.periodLabel, '04 Aug – 10 Aug');
    });

    test('the caption vocabulary', () {
      expect(PeriodKind.month.viewName, 'Month view');
      expect(PeriodKind.week.noun, 'week');
      expect(PeriodKind.year.apiValue, 'year');
    });

    test('shiftAnchor moves whole periods', () {
      expect(
        shiftAnchor(PeriodKind.month, DateTime(2026, 8, 24), -1),
        DateTime(2026, 7, 24),
      );
      expect(
        shiftAnchor(PeriodKind.week, DateTime(2026, 8, 24), 1),
        DateTime(2026, 8, 31),
      );
      expect(
        shiftAnchor(PeriodKind.year, DateTime(2026, 8, 24), -1),
        DateTime(2025, 8, 24),
      );
      // January minus one month must not stay in the same year.
      expect(
        shiftAnchor(PeriodKind.month, DateTime(2026, 1, 15), -1),
        DateTime(2025, 12, 15),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('insights — the live capture', () {
    late Insights insights;

    setUp(() {
      insights = Insights.fromJson(asMap(fixture('reports_insights')));
    });

    test('ranges, hasData and the two lists', () {
      expect(insights.period, 'month');
      expect(insights.hasData, isTrue);
      expect(insights.currentStart, isNotNull);
      expect(insights.currentEnd, isNotNull);
      expect(insights.previousStart, isNotNull);
      expect(insights.previousEnd, isNotNull);
      expect(insights.movers, hasLength(1));
      expect(insights.topExpenses, hasLength(2));
    });

    test('every pct is null because the previous period was empty', () {
      expect(insights.expense.current, 13312);
      expect(insights.expense.previous, 0);
      expect(insights.expense.delta, 13312);
      expect(insights.expense.pct, isNull);
      expect(insights.expense.hasNoBaseline, isTrue);

      expect(insights.income.delta, 0);
      expect(insights.income.isFlat, isTrue);
      expect(insights.income.pct, isNull);

      expect(insights.net.current, -13312);
      expect(insights.net.pct, isNull);

      // Not rendered anywhere, but it must not crash the parse.
      expect(insights.savingsRateCurrent, isNull);
      expect(insights.savingsRatePrevious, isNull);
    });

    test('pace — unrounded average, and no baseline to compare against', () {
      final pace = insights.pace;
      expect(pace.isCurrent, isTrue);
      expect(pace.daysElapsed, 24);
      expect(pace.daysInPeriod, 31);
      expect(pace.avgPerDay, closeTo(554.6666, 0.001));
      expect(pace.projected, 17195);
      expect(pace.percentElapsed, 77);
      expect(pace.progress, closeTo(0.774, 0.001));
      // 0 hides the faster/slower line entirely.
      expect(pace.previousToDate, 0);
    });

    test('the mover is new, so its percentage column has no number', () {
      final mover = insights.movers.single;
      expect(mover.name, 'Groceries');
      expect(mover.categoryId, '6a4669f861d974fd74ab427f');
      expect(mover.color, '#22C55E');
      expect(mover.icon, 'shopping-cart');
      expect(mover.delta, 13312);
      expect(mover.pct, isNull);
      expect(mover.isNew, isTrue);
      expect(insights.topRiser, same(mover));
    });

    test('top expenses fall back through payee -> note -> category', () {
      final biggest = insights.topExpenses.first;
      expect(biggest.id, '6a712b806ecc7fc372fedcd6');
      expect(biggest.amount, 12312);
      // Both blank on this account, so the category name is the title.
      expect(biggest.payee, isEmpty);
      expect(biggest.note, isEmpty);
      expect(biggest.title, 'Groceries');
      expect(biggest.category?.color, '#22C55E');
      expect(biggest.category?.icon, 'shopping-cart');
      // `account` is null on the wire and must stay null, not become an empty
      // stub that renders a blank chip.
      expect(biggest.account, isNull);
      expect(biggest.date, isNotNull);
    });
  });

  group('insights — the branches the live account does not exercise', () {
    test('hasData false empties the whole screen', () {
      // Verified live: ?period=week returns this shape for the owner today.
      final insights = Insights.fromJson({
        'period': 'week',
        'hasData': false,
        'movers': const [],
        'topExpenses': const [],
      });
      expect(insights.hasData, isFalse);
      expect(insights.movers, isEmpty);
      expect(insights.topExpenses, isEmpty);
      expect(insights.topRiser, isNull);
      // Missing blocks must still parse to zeroed values, never to null.
      expect(insights.expense.current, 0);
      expect(insights.pace.isCurrent, isFalse);
    });

    test('movers absent entirely is the same as movers empty', () {
      final insights = Insights.fromJson(const {'period': 'month'});
      expect(insights.movers, isEmpty);
      expect(insights.topExpenses, isEmpty);
      expect(insights.hasData, isFalse);
    });

    test('a period with a real baseline carries percentages', () {
      final insights = Insights.fromJson({
        'period': 'month',
        'hasData': true,
        'expense': const {
          'current': 4000,
          'previous': 3000,
          'delta': 1000,
          'pct': 33,
        },
        'savingsRate': const {'current': 22, 'previous': 15},
        'pace': const {
          'isCurrent': false,
          'daysElapsed': 31,
          'daysInPeriod': 31,
          'avgPerDay': 129.03,
          'projected': 4000,
          'previousToDate': 3000,
        },
        'movers': const [
          {
            'categoryId': null,
            'name': 'Uncategorised',
            'current': 500,
            'previous': 200,
            'delta': 300,
            'pct': 150,
          },
        ],
        'topExpenses': const [
          {
            '_id': 't1',
            'amount': 900,
            'payee': 'Amma Mess',
            'note': 'lunch',
            'category': null,
            'account': null,
          },
        ],
      });

      expect(insights.expense.pct, 33);
      expect(insights.expense.hasNoBaseline, isFalse);
      expect(insights.expense.isUp, isTrue);
      expect(insights.savingsRateCurrent, 22);
      expect(insights.savingsRatePrevious, 15);

      // A closed period: the progress bar is hidden, the comparison line shown.
      expect(insights.pace.isCurrent, isFalse);
      expect(insights.pace.percentElapsed, 100);
      expect(insights.pace.previousToDate, 3000);

      final mover = insights.movers.single;
      expect(mover.categoryId, isNull); // uncategorised still navigates
      expect(mover.pct, 150);
      expect(mover.isNew, isFalse);

      // payee wins over note.
      expect(insights.topExpenses.single.title, 'Amma Mess');
    });

    test('an expense with nothing to name it says "Expense"', () {
      final row = TopExpense.fromJson(const {'_id': 'x', 'amount': 10});
      expect(row.title, 'Expense');
      expect(row.category, isNull);
    });

    test('the query key is stable and pages whole periods', () {
      final august = InsightsQuery(at: DateTime(2026, 8, 24));
      expect(august, InsightsQuery(at: DateTime(2026, 8, 24)));
      expect(
        august.hashCode,
        InsightsQuery(at: DateTime(2026, 8, 24)).hashCode,
      );
      expect(august.shifted(-1).at, DateTime(2026, 7, 24));
      expect(august.shifted(-1).kind, PeriodKind.month);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('notifications — the live feed', () {
    test('the envelope is {items, unread}, and unread is the server count', () {
      final feed = NotificationFeed.fromJson(fixture('notifications'));
      expect(feed.items, hasLength(6));
      expect(feed.unread, 6);
      expect(feed.isEmpty, isFalse);

      final first = feed.items.first;
      expect(first.id, '6a712b80cf44dc86406a55f7');
      expect(first.type, 'recurring.posted');
      expect(first.kind, NotificationKind.recurringPosted);
      expect(first.link, '/recurring');
      expect(first.read, isFalse);
      expect(first.readAt, isNull);
      expect(first.dedupeKey, isNotNull);
      expect(first.amount, 12312);
      expect(first.currency, 'INR');
      expect(first.countParam, 1);
    });

    test('every type in the capture maps to a known kind', () {
      final feed = NotificationFeed.fromJson(fixture('notifications'));
      for (final item in feed.items) {
        expect(
          item.kind,
          isNot(NotificationKind.unknown),
          reason: '${item.type} is not in the six the bundle declares.',
        );
      }
      expect(
        feed.items.map((e) => e.kind).toSet(),
        containsAll(<NotificationKind>[
          NotificationKind.recurringPosted,
          NotificationKind.recurringDueSoon,
          NotificationKind.balanceLow,
        ]),
      );
    });

    test('the live rows compose the sentences the web shows', () {
      final feed = NotificationFeed.fromJson(fixture('notifications'));

      final posted = NotificationCopy.of(feed.items.first);
      // The title is the type's heading; `ruleTitle` belongs in the body.
      expect(posted.title, 'Recurring posted');
      expect(posted.body, 'Recurring posted 1 transaction (₹12,312).');

      final low = NotificationCopy.of(
        feed.items.firstWhere((e) => e.kind == NotificationKind.balanceLow),
      );
      expect(low.title, 'Low balance');
      // U+2212 MINUS SIGN, not a hyphen — same as everywhere else in the app.
      expect(low.body, 'Cash is overdrawn (−₹7,50,633).');
    });
  });

  group('notifications — copy for every type', () {
    AppNotification of(String type, Map<String, dynamic> params) =>
        AppNotification.fromJson({
          '_id': 'n1',
          'type': type,
          'params': params,
          'read': false,
        });

    test('recurring.posted pluralises on count', () {
      expect(
        NotificationCopy.of(
          of('recurring.posted', const {
            'ruleTitle': 'Rent',
            'count': 1,
            'amount': 12312,
            'currency': 'INR',
          }),
        ).body,
        'Rent posted 1 transaction (₹12,312).',
      );
      expect(
        NotificationCopy.of(
          of('recurring.posted', const {
            'ruleTitle': 'Rent',
            'count': 3,
            'amount': 36936,
            'currency': 'INR',
          }),
        ).body,
        'Rent posted 3 transactions (₹36,936).',
      );
    });

    test('recurring.ended', () {
      final copy = NotificationCopy.of(
        of('recurring.ended', const {'ruleTitle': 'Gym'}),
      );
      expect(copy.title, 'Recurring ended');
      expect(copy.body, 'Gym reached its end date and has stopped.');
    });

    test('recurring.due_soon formats the date as dd MMM yyyy', () {
      final copy = NotificationCopy.of(
        of('recurring.due_soon', const {
          'ruleTitle': 'Recurring',
          'amount': 12312,
          'currency': 'INR',
          'date': '2026-08-04',
        }),
      );
      expect(copy.title, 'Coming up');
      expect(copy.body, 'Recurring is scheduled for 04 Aug 2026 (₹12,312).');
    });

    test('recurring.overdue', () {
      final copy = NotificationCopy.of(
        of('recurring.overdue', const {
          'ruleTitle': 'EMI',
          'amount': 137000,
          'currency': 'INR',
          'date': '2026-08-04',
        }),
      );
      expect(copy.title, 'Overdue');
      expect(
        copy.body,
        "EMI was due 04 Aug 2026 (₹1,37,000) and hasn't posted yet.",
      );
    });

    test('budget.exceeded reads two money params', () {
      final copy = NotificationCopy.of(
        of('budget.exceeded', const {
          'category': 'Groceries',
          'spent': 15000,
          'amount': 12000,
          'currency': 'INR',
        }),
      );
      expect(copy.title, 'Budget exceeded');
      expect(copy.body, 'Groceries — spent ₹15,000 of ₹12,000.');
    });

    test('a non-rupee notification formats in its own currency', () {
      final copy = NotificationCopy.of(
        of('balance.low', const {
          'account': 'Wise',
          'balance': -42.5,
          'currency': 'USD',
        }),
      );
      expect(copy.body, 'Wise is overdrawn (−\$42.50).');
    });

    test('a missing value interpolates as empty, exactly as the web does', () {
      // Not a fallback we invented: the web's composer replaces a missing
      // numeric or date param with "", so a malformed payload renders with a
      // gap rather than the word "null" or a fabricated zero.
      final copy = NotificationCopy.of(
        of('recurring.due_soon', const {'ruleTitle': 'Recurring'}),
      );
      expect(copy.body, 'Recurring is scheduled for  ().');
    });

    test('an unknown type is humanised, not printed as an i18n key', () {
      final copy = NotificationCopy.of(of('goal.milestone_reached', const {}));
      expect(copy.title, 'Milestone reached');
      expect(copy.body, isEmpty);
    });

    test('timestamps read the way date-fns writes them', () {
      final feed = NotificationFeed.fromJson(fixture('notifications'));
      // Anchored on the row's own instant rather than on a wall-clock literal,
      // so the assertion means the same thing in every timezone.
      final created = feed.items.first.createdAt!;
      final now = created.add(const Duration(days: 20));
      expect(feed.items.first.timeAgo(now: now), '20 days ago');

      expect(DateX.timeAgo(now.subtract(const Duration(seconds: 10)), now: now),
          'less than a minute ago');
      expect(DateX.timeAgo(now.subtract(const Duration(minutes: 5)), now: now),
          '5 minutes ago');
      expect(DateX.timeAgo(now.subtract(const Duration(hours: 5)), now: now),
          'about 5 hours ago');
      expect(DateX.timeAgo(now.subtract(const Duration(days: 1)), now: now),
          '1 day ago');
      expect(DateX.timeAgo(now.subtract(const Duration(days: 55)), now: now),
          'about 2 months ago');
      expect(DateX.timeAgo(now.subtract(const Duration(days: 400)), now: now),
          'about 1 year ago');
      expect(DateX.timeAgo(null), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('settings — the document round-trips', () {
    test('every key the live GET returns is read back', () {
      final s = AppSettings.fromJson(asMap(fixture('settings')));
      expect(s.id, '6a4669f861d974fd74ab427c');
      expect(s.userId, '6a4669f861d974fd74ab427a');
      expect(s.name, 'My Wallet');
      expect(s.description, isEmpty);
      expect(s.baseCurrency, 'INR');
      expect(s.theme, 'system');
      expect(s.locale, 'en-IN');
      expect(s.language, 'en');
      expect(s.firstDayOfWeek, 1);
      expect(s.monthStartDay, 1);
      expect(s.pinEnabled, isFalse);
      expect(s.emailReports, isTrue);
      expect(s.wealthLockEnabled, isFalse);
      expect(s.currencies, hasLength(4));
      expect(s.symbol, '₹');
      expect(s.createdAt, isNotNull);
      expect(s.updatedAt, isNotNull);
    });

    test('toJson covers the read shape and survives a second parse', () {
      final original = AppSettings.fromJson(asMap(fixture('settings')));
      final again = AppSettings.fromJson(original.toJson());

      expect(again.id, original.id);
      expect(again.userId, original.userId);
      expect(again.name, original.name);
      expect(again.description, original.description);
      expect(again.baseCurrency, original.baseCurrency);
      expect(again.theme, original.theme);
      expect(again.locale, original.locale);
      expect(again.language, original.language);
      expect(again.firstDayOfWeek, original.firstDayOfWeek);
      expect(again.monthStartDay, original.monthStartDay);
      expect(again.pinEnabled, original.pinEnabled);
      expect(again.emailReports, original.emailReports);
      expect(again.wealthLockEnabled, original.wealthLockEnabled);
      expect(again.createdAt, original.createdAt);
      expect(again.updatedAt, original.updatedAt);
      expect(again.currencies.map((c) => c.code), ['INR', 'USD', 'EUR', 'GBP']);
      expect(again.currencies.first.rateToBase, 1);
      expect(again.currencies[1].rateToBase, 83);

      // Nothing from the capture is dropped except Mongo's own `__v`.
      final captured = asMap(fixture('settings')).keys.toSet()
        ..remove('__v');
      expect(again.toJson().keys.toSet(), containsAll(captured));
    });

    test('the currency table is read-only, and labels itself', () {
      final s = AppSettings.fromJson(asMap(fixture('settings')));
      final usd = s.currencies.firstWhere((c) => c.code == 'USD');
      expect(usd.selectLabel, 'USD – US Dollar (\$)');
      expect(usd.shortLabel, 'USD (\$)');
    });

    test('copyWith cannot touch a read-only field', () {
      final s = AppSettings.fromJson(asMap(fixture('settings')));
      final dark = s.copyWith(theme: 'dark');
      expect(dark.theme, 'dark');
      // The five writable concerns are the only parameters copyWith takes;
      // everything else rides through untouched.
      expect(dark.locale, s.locale);
      expect(dark.firstDayOfWeek, s.firstDayOfWeek);
      expect(dark.currencies, s.currencies);
      expect(dark.id, s.id);
    });

    test('two-factor status and enrolment', () {
      final status = TwoFactorStatus.fromJson(
        asMap(fixture('auth_2fa_status')),
      );
      expect(status.enabled, isFalse);
      expect(status.emailFallback, isTrue);
      expect(status.backupCodesRemaining, 0);

      final enrolment = TwoFactorEnrolment.fromJson(const {
        'qrDataUrl': 'data:image/png;base64,AAA',
        'secret': 'JBSWY3DPEHPK3PXP',
      });
      expect(enrolment.secret, 'JBSWY3DPEHPK3PXP');
      expect(enrolment.qrDataUrl, startsWith('data:image/png'));
    });

    test('the write vocabulary is five bodies and nothing else', () {
      // Pinned again in test/write_schema_test.dart against the accepted sets;
      // repeated here so a change to the builders fails the data tests too.
      expect(SettingsRepository.walletBody('W', 'label').keys, [
        'name',
        'description',
      ]);
      expect(SettingsRepository.baseCurrencyBody('USD'), {
        'baseCurrency': 'USD',
      });
      expect(SettingsRepository.languageBody('ta'), {'language': 'ta'});
      expect(SettingsRepository.emailReportsBody(true), {
        'emailReports': true,
      });
      expect(SettingsRepository.themeBody('dark'), {'theme': 'dark'});
      expect(SettingsRepository.pinBody('4321'), {'pin': '4321'});
      expect(SettingsRepository.passcodeBody('hunter2'), {
        'passcode': 'hunter2',
      });
      expect(SettingsRepository.supportedLanguages, {'en', 'ta'});
      expect(SettingsRepository.supportedThemes, {'light', 'dark', 'system'});
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('export — the CSV filename', () {
    test('the header the server actually sends', () {
      expect(
        ExportRepository.fileNameFrom(
          'attachment; filename="coincompass-transactions-2026-08-24-INR.csv"',
          baseCurrency: 'INR',
        ),
        'coincompass-transactions-2026-08-24-INR.csv',
      );
    });

    test('unquoted, and the RFC 5987 form', () {
      expect(
        ExportRepository.fileNameFrom(
          'attachment; filename=export.csv',
          baseCurrency: 'INR',
        ),
        'export.csv',
      );
      expect(
        ExportRepository.fileNameFrom(
          "attachment; filename*=UTF-8''my%20export.csv",
          baseCurrency: 'INR',
        ),
        'my export.csv',
      );
    });

    test('a path in the header cannot escape the export directory', () {
      expect(
        ExportRepository.fileNameFrom(
          'attachment; filename="../../etc/passwd"',
          baseCurrency: 'INR',
        ),
        'passwd',
      );
    });

    test('no header falls back to the pattern the server itself uses', () {
      expect(
        ExportRepository.fileNameFrom(
          null,
          baseCurrency: 'INR',
          today: DateTime(2026, 8, 24),
        ),
        'coincompass-transactions-2026-08-24-INR.csv',
      );
      expect(
        ExportRepository.fileNameFrom(
          'attachment',
          baseCurrency: 'USD',
          today: DateTime(2026, 1, 5),
        ),
        'coincompass-transactions-2026-01-05-USD.csv',
      );
    });
  });

  group('money — the two compact roundings one screen needs', () {
    test('the delta pill compacts to whole units', () {
      expect(Money.compact(13312, decimals: 0), '₹13K');
      expect(Money.compact(-13312, decimals: 0), '−₹13K');
    });

    test('a chart axis keeps one decimal', () {
      expect(Money.compactPlain(13312, decimals: 1), '13.3K');
      expect(Money.compactPlain(10500, decimals: 1), '10.5K');
      expect(Money.compactPlain(0, decimals: 1), '0');
    });

    test('the default trim is unchanged', () {
      expect(Money.compact(150000), '₹1.5L');
      expect(Money.compact(12500000), '₹1.25Cr');
    });

    test('a notification formats in its own currency symbol', () {
      expect(Money.symbolFor('INR'), '₹');
      expect(Money.symbolFor('usd'), r'$');
      expect(Money.symbolFor(null), '₹');
      expect(Money.symbolFor('XYZ'), '₹');
    });
  });
}
