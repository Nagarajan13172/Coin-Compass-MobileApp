import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/router/app_router.dart';
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
import 'package:coincompass/features/people/presentation/people_screen.dart';
import 'package:coincompass/features/recurring/presentation/recurring_screen.dart';
import 'package:coincompass/features/splits/presentation/splits_screen.dart';
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
/// phase 2's four, phase 3's five, and the two screens that hang off Credits.
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
/// screen degrades to its error state rather than hanging.
class _FixtureAdapter implements HttpClientAdapter {
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
    final fixture = _fixtures[options.uri.path.replaceFirst('/api', '')];
    final body = fixture == null
        ? null
        : File('test/fixtures/$fixture.json').readAsStringSync();

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
