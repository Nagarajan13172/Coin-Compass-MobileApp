import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/router/app_router.dart';
import 'package:coincompass/main.dart';
import 'package:coincompass/core/router/destinations.dart';
import 'package:coincompass/core/widgets/more_sheet.dart';
import 'package:coincompass/features/_placeholder/placeholder_screen.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/features/accounts/presentation/accounts_screen.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:coincompass/features/budgets/presentation/budgets_screen.dart';
import 'package:coincompass/features/calendar/presentation/calendar_screen.dart';
import 'package:coincompass/features/categories/presentation/categories_screen.dart';
import 'package:coincompass/features/credits/presentation/credits_screen.dart';
import 'package:coincompass/features/dashboard/presentation/dashboard_screen.dart';
import 'package:coincompass/features/goals/presentation/goals_screen.dart';
import 'package:coincompass/features/gold/presentation/gold_screen.dart';
import 'package:coincompass/features/holdings/presentation/holdings_screen.dart';
import 'package:coincompass/features/insights/presentation/insights_screen.dart';
import 'package:coincompass/features/loans/presentation/loans_screen.dart';
import 'package:coincompass/features/networth/presentation/net_worth_screen.dart';
import 'package:coincompass/features/notifications/presentation/notifications_screen.dart';
import 'package:coincompass/features/people/presentation/people_screen.dart';
import 'package:coincompass/features/recurring/presentation/recurring_screen.dart';
import 'package:coincompass/features/reports/presentation/reports_screen.dart';
import 'package:coincompass/features/settings/presentation/settings_screen.dart';
import 'package:coincompass/features/splits/presentation/splits_screen.dart';
import 'package:coincompass/features/stocks/presentation/stocks_screen.dart';
import 'package:coincompass/features/transactions/presentation/transaction_form_sheet.dart';
import 'package:coincompass/features/transactions/presentation/transactions_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the real app shell — router, redirects, bottom nav, centre FAB — with
/// a restored session, and walks the shipped routes the way a user does:
/// phase 2's four, phase 3's five, phase 4's four, and the three screens that
/// hang off another one (People and Splits under Credits, Holdings under Net
/// Worth).
void main() {
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('coincompass_nav');
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

  /// Advances both clocks: the tester's fake one for animations, and the real
  /// event loop so in-flight repository calls can land.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pump();
  }

  Future<ProviderContainer> boot(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _FixtureAdapter();

      container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      // The real session-restore path: GET /auth/me, exactly as main() does.
      await container.read(authControllerProvider.notifier).restore();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: container.read(routerProvider),
          theme: AppTheme.light(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await settle(tester);
    return container;
  }

  testWidgets('a restored session lands on the real dashboard', (tester) async {
    await boot(tester);
    expect(find.byType(DashboardScreen), findsOneWidget);
    // Phase 1's stand-in must be gone from the phase-2 routes.
    expect(find.text('Coming in phase 2'), findsNothing);
  });

  testWidgets('bottom nav reaches the real Transactions screen', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(find.text('Transactions').first);
    await settle(tester);
    expect(find.byType(TransactionsScreen), findsOneWidget);
  });

  testWidgets('the More sheet reaches Accounts and Categories', (tester) async {
    await boot(tester);

    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Accounts'));
    await settle(tester);
    expect(find.byType(AccountsScreen), findsOneWidget);

    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Categories'));
    await settle(tester);
    expect(find.byType(CategoriesScreen), findsOneWidget);
  });

  testWidgets('the More sheet reaches every phase-3 screen', (tester) async {
    await boot(tester);

    Future<void> open(String label) async {
      await tester.tap(find.text('More'));
      await settle(tester);
      await tester.tap(find.text(label));
      await settle(tester);
    }

    await open('Budgets');
    expect(find.byType(BudgetsScreen), findsOneWidget);

    await open('Goals');
    expect(find.byType(GoalsScreen), findsOneWidget);

    await open('Recurring');
    expect(find.byType(RecurringScreen), findsOneWidget);

    await open('Calendar');
    expect(find.byType(CalendarScreen), findsOneWidget);

    await open('Credits');
    expect(find.byType(CreditsScreen), findsOneWidget);

    // Phase 1's stand-in must be gone from all five.
    expect(find.text('Coming in phase 3'), findsNothing);
  });

  testWidgets('the More sheet reaches every phase-4 screen', (tester) async {
    await boot(tester);

    // Scoped to the sheet: "Stocks" and "Loans" also appear on the Net Worth
    // breakdown, so a bare find.text would be ambiguous once that screen is up.
    // The sheet's list is 14 rows tall and caps at 78% of an 800dp phone, so
    // the last few — Gold & Silver among them — have to be scrolled to.
    Future<void> open(String label) async {
      await tester.tap(find.text('More'));
      await settle(tester);
      final row = find.descendant(
        of: find.byType(MoreSheet),
        matching: find.text(label),
      );
      if (row.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          row,
          120,
          scrollable: find
              .descendant(
                of: find.byType(MoreSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle(tester);
      }
      await tester.tap(row);
      await settle(tester);
    }

    await open('Net Worth');
    expect(find.byType(NetWorthScreen), findsOneWidget);

    await open('Stocks');
    expect(find.byType(StocksScreen), findsOneWidget);

    await open('Loans');
    expect(find.byType(LoansScreen), findsOneWidget);

    await open('Gold & Silver');
    expect(find.byType(GoldScreen), findsOneWidget);

    // Phase 1's stand-in must be gone from all four.
    expect(find.text('Coming in phase 4'), findsNothing);
  });

  testWidgets('every one of the 17 destinations is a real screen', (
    tester,
  ) async {
    // The end of the placeholder era: `_screenFor` still has a
    // `PlaceholderScreen` default arm as a defensive fallback, and this walks
    // all 17 sidebar destinations through the real router to prove none of
    // them reaches it.
    final container = await boot(tester);
    final router = container.read(routerProvider);

    for (final destination in appDestinations) {
      router.go(destination.path);
      await settle(tester);
      expect(
        find.byType(PlaceholderScreen),
        findsNothing,
        reason:
            '${destination.path} (${destination.label}) is still a '
            'PlaceholderScreen.',
      );
    }
  });

  testWidgets('the bottom nav reaches the real Reports screen', (tester) async {
    await boot(tester);
    // Reports is a tab, not a More row — it is one of the four slots either
    // side of the centre FAB.
    await tester.tap(find.text('Reports').first);
    await settle(tester);
    expect(find.byType(ReportsScreen), findsOneWidget);
    expect(find.text('Analyse your income and spending'), findsOneWidget);
  });

  testWidgets('the More sheet reaches every phase-5 screen', (tester) async {
    await boot(tester);

    Future<void> open(String label) async {
      await tester.tap(find.text('More'));
      await settle(tester);
      final row = find.descendant(
        of: find.byType(MoreSheet),
        matching: find.text(label),
      );
      if (row.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          row,
          120,
          scrollable: find
              .descendant(
                of: find.byType(MoreSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle(tester);
      }
      await tester.tap(row);
      await settle(tester);
    }

    await open('Insights');
    expect(find.byType(InsightsScreen), findsOneWidget);

    await open('Notifications');
    expect(find.byType(NotificationsScreen), findsOneWidget);

    await open('Settings');
    expect(find.byType(SettingsScreen), findsOneWidget);

    // Phase 1's stand-in is gone from the last four routes — with these there
    // are no PlaceholderScreens left anywhere in the app.
    expect(find.text('Coming in phase 5'), findsNothing);
  });

  testWidgets('the app bar bell carries the unread count and opens the feed', (
    tester,
  ) async {
    await boot(tester);
    // notifications.json is the owner's real feed: six unread.
    expect(find.text('6'), findsWidgets);

    await tester.tap(find.byIcon(LucideIcons.bell).first);
    await settle(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('Net Worth leads to Holdings, and back again', (tester) async {
    // Holdings has no nav slot — the sidebar has exactly 17 destinations, so
    // it hangs off Net Worth at /net-worth/holdings the way People hangs off
    // Credits. That mounting is the only way to reach it.
    await boot(tester);

    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Net Worth'));
    await settle(tester);
    expect(find.byType(NetWorthScreen), findsOneWidget);

    await tester.tap(find.text('Manage holdings').first);
    await settle(tester);
    expect(find.byType(HoldingsScreen), findsOneWidget);

    await tester.tap(find.text('Back'));
    await settle(tester);
    expect(find.byType(NetWorthScreen), findsOneWidget);
  });

  testWidgets('Credits leads to People and Splits, and back again', (
    tester,
  ) async {
    await boot(tester);

    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Credits'));
    await settle(tester);

    await tester.tap(find.text('People & groups'));
    await settle(tester);
    expect(find.byType(PeopleScreen), findsOneWidget);

    await tester.tap(find.text('Back'));
    await settle(tester);
    expect(find.byType(CreditsScreen), findsOneWidget);

    await tester.tap(find.text('Splits'));
    await settle(tester);
    expect(find.byType(SplitsScreen), findsOneWidget);
  });

  testWidgets('the centre FAB quick-adds a transaction', (tester) async {
    await boot(tester);

    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await settle(tester);
    expect(find.text('Add'), findsWidgets);

    await tester.tap(find.text('Transaction'));
    await settle(tester);

    // It lands on the ledger and opens the form there, defaulting to Expense.
    expect(find.byType(TransactionsScreen), findsOneWidget);
    final sheet = tester.widget<TransactionFormSheet>(
      find.byType(TransactionFormSheet),
    );
    expect(sheet.existing, isNull);
    expect(sheet.initialType, TransactionType.expense);
  });

  // ── the server's theme reaches the app ────────────────────────────────────

  /// Boots the real [CoinCompassApp] — the widget `main()` builds, so
  /// `MaterialApp.themeMode` is the app's own, not the test's — with
  /// [seedPrefs] already on disk and `/settings` answering [settingsBody].
  Future<ProviderContainer> bootApp(
    WidgetTester tester, {
    required String settingsBody,
    Map<String, Object> seedPrefs = const {},
  }) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(seedPrefs);
      final prefs = await SharedPreferences.getInstance();
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _FixtureAdapter(
        overrides: {'/settings': settingsBody},
      );
      container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      await container.read(authControllerProvider.notifier).restore();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CoinCompassApp(),
      ),
    );
    await settle(tester);
    return container;
  }

  String settingsWithTheme(String theme) => File('test/fixtures/settings.json')
      .readAsStringSync()
      .replaceFirst('"theme":"system"', '"theme":"$theme"')
      .replaceFirst('"theme": "system"', '"theme": "$theme"');

  testWidgets("the account's own theme is adopted on a fresh device", (
    tester,
  ) async {
    // No local choice has ever been made here, so the account decides. Without
    // this wiring the screen's Light/Dark/System row would show "System" while
    // the server holds "dark" — the two would silently disagree.
    final container = await bootApp(
      tester,
      settingsBody: settingsWithTheme('dark'),
    );

    expect(container.read(themeControllerProvider), ThemeMode.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('a local theme choice is never overwritten by the server', (
    tester,
  ) async {
    // The device says light, the account says dark: the tap the user made on
    // this phone wins, and keeps winning across restarts.
    final container = await bootApp(
      tester,
      settingsBody: settingsWithTheme('dark'),
      seedPrefs: const {'themeMode': 'light'},
    );

    expect(container.read(themeControllerProvider), ThemeMode.light);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
  });

  testWidgets('the FAB "Transfer" row opens the form on Transfer', (
    tester,
  ) async {
    await boot(tester);

    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await settle(tester);
    await tester.tap(find.text('Transfer'));
    await settle(tester);

    expect(find.byType(TransactionsScreen), findsOneWidget);
    final sheet = tester.widget<TransactionFormSheet>(
      find.byType(TransactionFormSheet),
    );
    expect(sheet.initialType, TransactionType.transfer);
    // Transfers have two account fields and no category.
    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);
  });
}

/// Serves `test/fixtures/*.json` over Dio; anything unmapped answers 404 so a
/// screen degrades to its error state rather than hanging. [overrides] swaps
/// the body for one path without editing the shared fixture.
class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter({this.overrides = const {}});

  final Map<String, String> overrides;

  static const Map<String, String> _fixtures = {
    '/auth/me': 'auth_me',
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
    '/reports/insights': 'reports_insights',
    '/notifications': 'notifications',
    '/auth/2fa/status': 'auth_2fa_status',
    '/budgets': 'budgets',
    '/goals': 'goals',
    '/recurring': 'recurring',
    '/credits': 'credits',
    '/credits/summary': 'credits_summary',
    '/people': 'people',
    '/people/groups': 'people_groups',
    '/splits': 'splits',
    '/loans': 'loans',
    '/holdings': 'holdings',
    '/stocks/portfolio': 'stocks_portfolio',
    '/metals/history': 'metals_history',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    final override = overrides[path];
    if (override != null) {
      return ResponseBody.fromString(
        override,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final fixture = _fixtures[path];
    final body = fixture != null
        ? File('test/fixtures/$fixture.json').readAsStringSync()
        // The owner has no accounts, so this endpoint really does answer an
        // empty list — there is no capture to keep as a fixture.
        : (path == '/reports/by-account' ? '[]' : null);

    return ResponseBody.fromString(
      body ?? '{"error":"not mapped"}',
      body == null ? 404 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
