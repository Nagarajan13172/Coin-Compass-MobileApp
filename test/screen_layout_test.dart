import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/accounts/data/accounts_repository.dart';
import 'package:coincompass/features/accounts/presentation/accounts_screen.dart';
import 'package:coincompass/features/budgets/data/budgets_repository.dart';
import 'package:coincompass/features/budgets/presentation/budgets_providers.dart';
import 'package:coincompass/features/budgets/presentation/budgets_screen.dart';
import 'package:coincompass/features/calendar/presentation/calendar_providers.dart';
import 'package:coincompass/features/calendar/presentation/calendar_screen.dart';
import 'package:coincompass/features/categories/data/categories_repository.dart';
import 'package:coincompass/features/categories/presentation/categories_screen.dart';
import 'package:coincompass/features/credits/data/credits_repository.dart';
import 'package:coincompass/features/credits/presentation/credits_screen.dart';
import 'package:coincompass/features/dashboard/presentation/dashboard_screen.dart';
import 'package:coincompass/features/goals/data/goals_repository.dart';
import 'package:coincompass/features/goals/presentation/goals_screen.dart';
import 'package:coincompass/features/people/data/people_repository.dart';
import 'package:coincompass/features/people/presentation/people_screen.dart';
import 'package:coincompass/features/recurring/data/recurring_repository.dart';
import 'package:coincompass/features/recurring/presentation/recurring_screen.dart';
import 'package:coincompass/features/splits/data/splits_repository.dart';
import 'package:coincompass/features/splits/presentation/splits_screen.dart';
import 'package:coincompass/features/gold/data/metals_repository.dart';
import 'package:coincompass/features/networth/data/networth_repository.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:coincompass/features/templates/data/templates_repository.dart';
import 'package:coincompass/core/utils/date_x.dart';
import 'package:coincompass/features/transactions/presentation/transactions_providers.dart';
import 'package:coincompass/features/transactions/presentation/transactions_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coincompass/l10n/app_localizations.dart';

/// Renders the phase-2 screens on the narrowest device we ship to
/// (360 × 800dp) and fails on any RenderFlex overflow — the class of bug that
/// shipped in phase 1.
///
/// The whole stack is real: real repositories, real providers, real widgets.
/// Only the transport is swapped for a Dio adapter, which replays either the
/// recorded `test/fixtures/*.json` or a deliberately hostile payload — long
/// names, nine-figure amounts, every optional badge switched on.
void main() {
  const Size phone = Size(360, 800);

  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('coincompass_layout');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Warms every read the four screens make, then mounts [screen] against the
  /// already-resolved container. Warming happens outside the widget tester's
  /// fake clock, which is the only way a real Future resolves inside a
  /// `testWidgets` body.
  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Map<String, String> payloads = const {},
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _FixtureAdapter(payloads);
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );

      // Hold the autoDispose reads open for the life of the test, so the
      // screen finds them already resolved rather than refetching.
      for (final provider in <ProviderListenable<Object?>>[
        settingsProvider,
        accountsProvider,
        categoriesProvider,
        templatesProvider,
        transactionBalanceProvider,
        transactionTagsProvider,
        metalsLatestProvider,
        netWorthHistoryProvider,
        dashboardSummaryProvider,
        dashboardTrendProvider,
        dashboardCategoryProvider,
        transactionsPageProvider(recentTransactionsQuery),
        transactionsListProvider,
        budgetsProvider,
        budgetSpendProvider(BudgetPeriod.monthly),
        budgetSpendProvider(BudgetPeriod.weekly),
        goalsProvider,
        recurringRulesProvider,
        creditsProvider,
        creditsSummaryProvider,
        peopleProvider,
        personGroupsProvider,
        splitsProvider,
        calendarMonthProvider(DateTime.now().startOfMonth),
      ]) {
        container.listen<Object?>(provider, (Object? a, Object? b) {});
      }

      await Future.wait(<Future<Object?>>[
        for (final future in <Future<Object?>>[
          container.read(settingsProvider.future),
          container.read(accountsFetchProvider.future),
          container.read(categoriesFetchProvider.future),
          container.read(templatesFetchProvider.future),
          container.read(transactionBalanceProvider.future),
          container.read(transactionTagsProvider.future),
          container.read(metalsLatestProvider.future),
          container.read(netWorthHistoryProvider.future),
          container.read(dashboardSummaryProvider.future),
          container.read(dashboardTrendProvider.future),
          container.read(dashboardCategoryProvider.future),
          container.read(
            transactionsPageProvider(recentTransactionsQuery).future,
          ),
          container.read(budgetsFetchProvider.future),
          container.read(budgetSpendProvider(BudgetPeriod.monthly).future),
          container.read(budgetSpendProvider(BudgetPeriod.weekly).future),
          container.read(goalsFetchProvider.future),
          container.read(recurringRulesFetchProvider.future),
          container.read(creditsFetchProvider.future),
          container.read(creditsSummaryProvider.future),
          container.read(peopleFetchProvider.future),
          container.read(personGroupsFetchProvider.future),
          container.read(splitsFetchProvider.future),
          container.read(
            calendarMonthProvider(DateTime.now().startOfMonth).future,
          ),
        ])
          future.catchError((Object _) => null),
      ]);
      await container.read(transactionsListProvider.notifier).refresh();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: AppTheme.light(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Slivers build lazily, so everything below the fold is only laid out once
  /// it is scrolled into view — which is exactly where an overflow hides.
  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(scrollable, const Offset(0, -420));
      await tester.pump();
    }
  }

  /// Every screen is checked twice: once against what the account really
  /// returns, once against the hostile payload.
  void screenTest(String name, Widget Function() build, Finder proof) {
    testWidgets('$name — recorded payloads', (tester) async {
      await pump(tester, build());
      expect(proof, findsWidgets);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name — long names and nine-figure amounts', (tester) async {
      await pump(tester, build(), payloads: _stressPayloads);
      expect(proof, findsWidgets);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });
  }

  /// The add/edit sheets carry the densest rows in the app (type selector,
  /// amount keypad, two account pickers), so they get the same treatment.
  void sheetTest(
    String name,
    Widget Function() screen,
    String openLabel,
    String field,
  ) {
    testWidgets('$name sheet lays out at 360dp', (tester) async {
      await pump(tester, screen(), payloads: _stressPayloads);
      await tester.tap(find.text(openLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // Proof the sheet actually opened — otherwise this test proves nothing.
      expect(find.text(field), findsWidgets);
      expect(tester.takeException(), isNull);

      // Drag from inside the sheet, which covers the lower half of the screen,
      // so every field below the fold gets laid out.
      for (var i = 0; i < 8; i++) {
        await tester.dragFrom(const Offset(180, 620), const Offset(0, -240));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  }

  screenTest('dashboard', DashboardScreen.new, find.byType(DashboardScreen));
  screenTest('transactions', TransactionsScreen.new, find.text('Transactions'));
  screenTest('accounts', AccountsScreen.new, find.text('Accounts'));
  screenTest('categories', CategoriesScreen.new, find.text('Categories'));

  screenTest('budgets', BudgetsScreen.new, find.text('Budgets'));
  screenTest('goals', GoalsScreen.new, find.text('Goals'));
  screenTest('recurring', RecurringScreen.new, find.text('Recurring'));
  screenTest('calendar', CalendarScreen.new, find.text('Calendar'));
  screenTest('credits', CreditsScreen.new, find.text('Credits'));
  screenTest('people', PeopleScreen.new, find.text('People & groups'));
  screenTest('splits', SplitsScreen.new, find.text('Splits'));

  sheetTest('transaction', TransactionsScreen.new, 'Add', 'Payee');
  sheetTest('account', AccountsScreen.new, 'New account', 'Opening balance');
  sheetTest('category', CategoriesScreen.new, 'New category', 'Name');
  sheetTest('budget', BudgetsScreen.new, 'New budget', 'Period');
  sheetTest('goal', GoalsScreen.new, 'New goal', 'Target amount');
  sheetTest('recurring rule', RecurringScreen.new, 'New rule', 'Repeats');
  sheetTest('credit', CreditsScreen.new, 'Add credit', 'Direction');
  sheetTest('split', SplitsScreen.new, 'Split a bill', 'Your share');
}

/// Replays a JSON body per path. An override wins over the recorded fixture,
/// so one test can make a single endpoint hostile.
///
/// An unmapped path answers 404, so a screen that starts calling something new
/// shows up as an error state rather than silently passing.
class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this._overrides);

  final Map<String, String> _overrides;

  static const Map<String, String> _fixtures = {
    '/transactions': 'transactions',
    '/transactions/balance': 'transactions_balance',
    '/transactions/summary': 'transactions_summary',
    '/transactions/tags': 'transactions_tags',
    '/accounts': 'accounts',
    '/categories': 'categories',
    '/templates': 'templates',
    '/settings': 'settings',
    '/metals/latest': 'metals_latest',
    '/networth/history': 'networth_history',
    '/reports/summary': 'reports_summary',
    '/reports/by-category': 'reports_by-category',
    '/reports/trend': 'reports_trend',
    '/auth/me': 'auth_me',
    '/budgets': 'budgets',
    '/goals': 'goals',
    '/recurring': 'recurring',
    '/credits': 'credits',
    '/credits/summary': 'credits_summary',
    '/people': 'people',
    '/people/groups': 'people_groups',
    '/splits': 'splits',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    final fixture = _fixtures[path];
    final body =
        _overrides[path] ??
        (fixture == null
            ? null
            : File('test/fixtures/$fixture.json').readAsStringSync());

    return ResponseBody.fromString(
      body ?? '{"error":"no fixture for $path"}',
      body == null ? 404 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ─── the hostile payload ────────────────────────────────────────────────────
//
// The recorded account is nearly empty, so those fixtures exercise empty
// states rather than crowded rows. These bodies push every row to its limit.

const String _longName =
    'Kotak Mahindra Bank Salary Account — Anna Nagar West Branch';

const String _stressAccounts =
    '''
[
  {"_id":"a1","name":"$_longName","type":"bank","initialBalance":0,
   "balance":123456789,"currency":"INR","institution":"Kotak Mahindra Bank",
   "last4":"9012","icon":"landmark","color":"#3B82F6",
   "includeInTotal":true,"archived":false},
  {"_id":"a2","name":"HDFC Infinia Metal Credit Card","type":"card",
   "initialBalance":0,"balance":-98765432,"currency":"INR",
   "institution":"HDFC Bank","last4":"4417","creditLimit":150000000,
   "includeInTotal":true,"archived":false},
  {"_id":"a3","name":"Cash","type":"cash","initialBalance":250,"balance":250,
   "currency":"INR","includeInTotal":false,"archived":true}
]''';

const String _stressBalance = '''
{"balance":123456789,"byAccount":{"a1":123456789,"a2":-98765432,"a3":250}}''';

const String _stressTransactions =
    '''
{"items":[
  {"_id":"t1","type":"expense","amount":123456789,
   "account":{"_id":"a1","name":"$_longName","type":"bank"},
   "toAccount":null,
   "category":{"_id":"c1","name":"Household Maintenance & Repairs",
     "type":"expense","icon":"wrench","color":"#F97316"},
   "date":"2026-08-24T00:00:00.000Z",
   "note":"Full bathroom retiling plus the plumber's call-out charge",
   "payee":"Sri Venkateswara Hardware & Sanitary Wholesalers",
   "tags":["home","annual"],"oneoff":true,"currency":"INR",
   "recurring":"r1","createdAt":"2026-08-24T09:00:00.000Z"},
  {"_id":"t2","type":"transfer","amount":50000000,
   "account":{"_id":"a1","name":"$_longName","type":"bank"},
   "toAccount":{"_id":"a2","name":"HDFC Infinia Metal Credit Card",
     "type":"card"},
   "category":null,"date":"2026-08-24T00:00:00.000Z",
   "note":"","payee":"","tags":[],"oneoff":false,"currency":"INR",
   "createdAt":"2026-08-24T08:00:00.000Z"},
  {"_id":"t3","type":"income","amount":9876543,
   "account":{"_id":"a1","name":"$_longName","type":"bank"},
   "toAccount":null,
   "category":{"_id":"c2","name":"Salary","type":"income","icon":"wallet",
     "color":"#22C55E"},
   "date":"2026-08-01T00:00:00.000Z","note":"","payee":"Employer",
   "tags":[],"oneoff":false,"currency":"INR",
   "createdAt":"2026-08-01T08:00:00.000Z"}
],"page":1,"limit":50,"total":3,"pages":1,"hasMore":false}''';

const String _stressTemplates = '''
[
  {"_id":"tp1","name":"Weekday lunch at the office canteen","type":"expense",
   "amount":180,"account":"a1","category":"c1","icon":"utensils",
   "color":"#F97316","tags":["food"],"currency":"INR"},
  {"_id":"tp2","name":"Auto fare","type":"expense","amount":90,
   "account":"a1","currency":"INR"}
]''';

const String _stressSummary = '''
{"income":98765432,"expense":123456789,"net":-24691357,"incomeCount":12,
 "expenseCount":340,"consumption":100000000,"nonConsumption":23456789,
 "netWorth":-207506330,"byCurrency":{},
 "range":{"start":"2026-08-01T00:00:00.000Z","end":"2026-09-01T00:00:00.000Z"}}''';

const String _stressByCategory = '''
[
  {"total":123456789,"count":210,"categoryId":"c1",
   "name":"Household Maintenance & Repairs","color":"#F97316",
   "icon":"wrench","group":"home","percent":72.4},
  {"total":23456789,"count":90,"categoryId":"c3",
   "name":"Groceries & Everyday Provisions","color":"#22C55E",
   "icon":"shopping-cart","group":"food","percent":21.1},
  {"total":3456789,"count":40,"categoryId":"c4","name":"Transport",
   "color":"#3B82F6","icon":"car","group":"transport","percent":6.5}
]''';

const String _stressTags = '["home","annual","reimbursable","office-canteen"]';

const String _stressBudgets = """
[
  {"_id":"b1","amount":150000000,"period":"monthly","rollover":true,
   "currency":"INR",
   "category":{"_id":"c1","name":"Household Maintenance & Repairs",
     "type":"expense","icon":"wrench","color":"#F97316"}},
  {"_id":"b2","amount":9000,"period":"monthly","rollover":false,
   "currency":"INR","category":"c3","spent":123456789},
  {"_id":"b3","name":"Everything, capped for the whole household","amount":250000,
   "period":"weekly","rollover":false,"currency":"INR","category":null}
]""";

const String _stressGoals = """
[
  {"_id":"g1","name":"Down payment on the Anna Nagar apartment",
   "targetAmount":123456789,"savedAmount":23456789,"monthlyContribution":150000,
   "color":"#6366F1","icon":"goal","currency":"INR",
   "targetDate":"2029-04-01T00:00:00.000Z","remaining":100000000,
   "percent":19,"complete":false,"monthsLeft":34},
  {"_id":"g2","name":"Emergency fund","targetAmount":600000,"savedAmount":600000,
   "monthlyContribution":0,"color":"#22C55E","icon":"piggy-bank",
   "currency":"INR","remaining":0,"percent":100,"complete":true,
   "achievedAt":"2026-07-30T00:00:00.000Z"}
]""";

const String _stressRecurring =
    """
[
  {"_id":"r1","type":"expense","amount":123456789,
   "account":{"_id":"a1","name":"$_longName","type":"bank"},
   "category":{"_id":"c1","name":"Household Maintenance & Repairs",
     "type":"expense","icon":"wrench","color":"#F97316"},
   "payee":"Sri Venkateswara Hardware & Sanitary Wholesalers",
   "note":"","tags":[],"currency":"INR","frequency":"monthly","interval":1,
   "startDate":"2026-01-04T00:00:00.000Z","nextRun":"2026-08-04T00:00:00.000Z",
   "lastRun":"2026-07-04T00:00:00.000Z","active":true,
   "upcoming":["2026-09-04T00:00:00.000Z"]},
  {"_id":"r2","type":"income","amount":9876543,"account":"a1","category":null,
   "payee":"Employer","note":"","tags":[],"currency":"INR","frequency":"daily",
   "interval":3,"startDate":"2026-08-01T00:00:00.000Z",
   "nextRun":"2026-08-27T00:00:00.000Z","active":true,"upcoming":[]},
  {"_id":"r3","type":"expense","amount":499,"account":"a1","category":null,
   "payee":"Streaming subscription that nobody remembers signing up for",
   "note":"","tags":[],"currency":"INR","frequency":"yearly","interval":1,
   "startDate":"2025-08-01T00:00:00.000Z","nextRun":null,"active":false,
   "upcoming":[]}
]""";

const String _stressCredits = """
[
  {"_id":"cr1","person":{"_id":"p1",
     "name":"Venkataraman Subramanian Iyer"},
   "direction":"given","amount":123456789,"currency":"INR",
   "date":"2026-06-01T00:00:00.000Z","dueDate":"2026-07-01T00:00:00.000Z",
   "settled":false,"note":"For the plot registration in Thiruvallur"},
  {"_id":"cr2","person":"Anitha","direction":"borrowed","amount":50000,
   "currency":"INR","date":"2026-08-01T00:00:00.000Z","settled":false},
  {"_id":"cr3","person":{"_id":"p2","name":"Karthik"},"direction":"repaid",
   "amount":25000,"currency":"INR","date":"2026-05-01T00:00:00.000Z",
   "settled":true,"settledAt":"2026-05-02T00:00:00.000Z"}
]""";

const String _stressCreditsSummary = """
{"given":123456789,"received":0,"borrowed":50000,"repaid":25000,
 "net":123406789}""";

const String _stressPeople = """
[
  {"_id":"p1","name":"Venkataraman Subramanian Iyer",
   "phone":"+91 98400 12345","email":"venkataraman.subramanian@example.com",
   "color":"#8B5CF6","group":"pg1"},
  {"_id":"p2","name":"Karthik","phone":"+91 90000 00000"},
  {"_id":"p3","name":"Anitha"}
]""";

const String _stressGroups = """
[{"_id":"pg1","name":"Thiruvallur plot syndicate","color":"#14B8A6",
  "members":["p1","p2","p3"]}]""";

const String _stressSplits = """
[
  {"_id":"s1","description":"Farewell dinner at the Anjappar on OMR",
   "totalAmount":123456789,"yourShare":23456789,"participants":["p1","p2"],
   "group":"pg1","date":"2026-08-20T00:00:00.000Z","settled":false,
   "currency":"INR"},
  {"_id":"s2","description":"Cab","totalAmount":1200,"yourShare":600,
   "participants":["p3"],"date":"2026-08-18T00:00:00.000Z","settled":true,
   "currency":"INR"}
]""";

const Map<String, String> _stressPayloads = {
  '/accounts': _stressAccounts,
  '/transactions': _stressTransactions,
  '/transactions/balance': _stressBalance,
  '/transactions/tags': _stressTags,
  '/templates': _stressTemplates,
  '/reports/summary': _stressSummary,
  '/reports/by-category': _stressByCategory,
  '/budgets': _stressBudgets,
  '/goals': _stressGoals,
  '/recurring': _stressRecurring,
  '/credits': _stressCredits,
  '/credits/summary': _stressCreditsSummary,
  '/people': _stressPeople,
  '/people/groups': _stressGroups,
  '/splits': _stressSplits,
};
