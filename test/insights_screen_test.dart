import 'dart:async';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/utils/money.dart';
import 'package:coincompass/core/widgets/loading_shimmer.dart';
import 'package:coincompass/features/insights/presentation/insights_providers.dart';
import 'package:coincompass/features/insights/presentation/insights_screen.dart';
import 'package:coincompass/features/reports/presentation/period.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:coincompass/features/transactions/presentation/transactions_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:coincompass/l10n/app_localizations.dart';

/// `/insights` at 360 × 800dp, against the shapes the live account actually
/// returns.
///
/// The whole stack is real — repository, providers, widgets — with only the
/// Dio transport swapped for an adapter that replays a payload per `period`.
///
/// TWO PUMPING RULES, both learned the hard way:
///
/// * This screen mounts [LoadingShimmer] (an endlessly repeating controller)
///   and a [RefreshIndicator], so `pumpAndSettle` would never return. Every
///   wait below is an explicit `pump(Duration)`.
/// * A request started inside the fake-async zone only completes while the
///   test keeps pumping, so `runAsync`-ing its future deadlocks. Anything that
///   has to *resolve* is therefore set up before the widget is mounted, and
///   the interaction tests assert on state rather than on a second round trip.
void main() {
  const Size phone = Size(360, 800);
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_insights');
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

  /// Warms `/reports/insights` outside the fake clock — the only way a real
  /// Future resolves inside a `testWidgets` body — then mounts the screen
  /// against the already-resolved container.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String payload = _real,
    int status = 200,
    ThemeData? theme,
    PeriodKind? kind,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _Adapter(payload: payload, status: status);
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      if (kind != null) {
        container.read(insightsPeriodKindProvider.notifier).state = kind;
      }
      // Hold the autoDispose reads open for the life of the test.
      container.listen<Object?>(currentInsightsProvider, (a, b) {});
      try {
        await container.read(currentInsightsProvider.future);
      } catch (_) {
        // The failure is what the error test is about; the screen renders it.
      }
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: theme ?? AppTheme.light(),
          home: const Scaffold(body: InsightsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  ScrollableState verticalList(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere((state) => state.position.axis == Axis.vertical);

  String? textOf(Widget widget) {
    final text = widget as Text;
    return text.data ?? text.textSpan?.toPlainText();
  }

  Iterable<String> renderedText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map(textOf)
      .whereType<String>();

  /// The failure this screen exists to avoid: a null percentage rendered
  /// literally, or a division by a zero previous period.
  void expectNoBrokenNumbers(WidgetTester tester) {
    for (final data in renderedText(tester)) {
      for (final poison in const ['null', 'NaN', 'Infinity']) {
        expect(
          data.contains(poison),
          isFalse,
          reason: 'rendered "$data" — contains "$poison"',
        );
      }
    }
  }

  /// Walks the whole list, collecting everything that renders on the way.
  ///
  /// Slivers build lazily, so a card below the fold is only laid out once it
  /// scrolls into view — which is exactly where an overflow hides, and also
  /// why an assertion made after scrolling back to the top would miss it.
  Future<Set<String>> scrollThrough(WidgetTester tester) async {
    final seen = <String>{};
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 250) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'laying out at scroll offset $offset threw — likely a '
            'RenderFlex overflow at 360dp',
      );
      seen.addAll(renderedText(tester));
      expectNoBrokenNumbers(tester);
      if (offset >= position.maxScrollExtent) break;
    }
    position.jumpTo(0);
    await tester.pump();
    return seen;
  }

  // ── loaded ───────────────────────────────────────────────────────────────

  testWidgets('loaded — the live payload, top to bottom', (tester) async {
    await pump(tester);

    expect(find.text('Insights'), findsOneWidget);
    expect(
      find.text('How your spending is changing, period over period.'),
      findsOneWidget,
    );
    // Week / Month / Year, the pager and the caption.
    expect(find.text('Month'), findsOneWidget);
    expect(find.textContaining('Showing'), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);

    final seen = await scrollThrough(tester);

    expect(seen, containsAll(<String>['Spending', 'Income', 'Net']));
    expect(seen, contains('₹13,312'));
    expect(seen, contains('${Money.minus}₹13,312'));
    expect(seen, contains('Savings rate'));
    expect(seen, contains('Spending pace'));
    expect(seen, contains('Spent so far'));
    expect(seen, contains('Avg per day'));
    // avgPerDay 554.666… is rounded to whole rupees here, unlike Reports.
    expect(seen, contains('₹555'));
    expect(seen, contains('Projected this month'));
    expect(seen, contains('₹17,195'));
    expect(seen, contains('Day 24 of 31'));
    expect(seen, contains('77%'));
    expect(seen, contains('What changed'));
    expect(seen, contains('Biggest shifts vs last month'));
    expect(seen, contains('Groceries'));
    expect(seen, contains('+₹13,312'));
    expect(seen, contains('Biggest expenses'));
    expect(seen, contains('₹12,312'));
    expect(seen, contains('Groceries · 04 Aug'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loaded — pull-to-refresh is wired', (tester) async {
    await pump(tester);
    // Deliberately not dragged: the indicator is indeterminate and its future
    // is a real network call, so a drag would spin past the end of the test.
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  // ── the degenerate path: no previous period at all ───────────────────────

  testWidgets('degenerate — every pct is null and nothing says "null"', (
    tester,
  ) async {
    await pump(tester);
    final seen = await scrollThrough(tester);

    // The delta pill falls back to a compact amount, never a percentage.
    expect(seen, contains('₹13K'));
    // Spending and Net both moved with no baseline; Income did not move.
    expect(seen, contains('No change'));
    // The dead "Last month: ₹0" line is replaced by a statement of fact.
    expect(seen, contains('nothing spent last month'));
    expect(seen, contains('nothing earned last month'));
    expect(seen, contains('nothing recorded last month'));
    expect(
      seen.any((t) => t.startsWith('Last month:')),
      isFalse,
      reason: 'a zero previous period must not be reported as a comparison',
    );
    expect(
      seen.contains('vs last month'),
      isFalse,
      reason: 'there is nothing to be "vs" yet',
    );

    // A mover with no history reads "New", not "null%".
    expect(seen, contains('New'));

    // savingsRate {current: null} — an em dash, and a sentence saying why.
    expect(seen, contains('—'));
    expect(
      seen,
      contains(
        'No income this month — a savings rate needs income to divide by.',
      ),
    );

    // pace.previousToDate == 0 hides the faster/slower line entirely rather
    // than dividing by it.
    expect(seen.any((t) => t.contains('at this point')), isFalse);

    // The first period is a designed state, not a degraded one.
    expect(
      seen.any((t) => t.startsWith('This is your first month with data')),
      isTrue,
    );
    // …and the highlight leads with the no-baseline sentence.
    expect(seen, contains("You've spent ₹13,312 this month."));

    expect(tester.takeException(), isNull);
  });

  testWidgets('degenerate — an all-zero period divides by nothing', (
    tester,
  ) async {
    await pump(tester, payload: _allZero);
    final seen = await scrollThrough(tester);

    expect(seen.where((t) => t == 'No change').length, 1);
    expect(seen, contains('No category changes to show.'));
    expect(seen, contains('No expenses in this period.'));
    // daysInPeriod == 0 must not produce a progress row or a NaN percentage.
    expect(seen.any((t) => t.startsWith('Day ')), isFalse);
    expect(seen, contains('₹0'));
    expect(tester.takeException(), isNull);
  });

  // ── empty ────────────────────────────────────────────────────────────────

  testWidgets('empty — hasData:false keeps the header and pager', (
    tester,
  ) async {
    await pump(tester, payload: _empty, kind: PeriodKind.week);

    expect(find.text('Not enough data yet'), findsOneWidget);
    expect(
      find.text(
        'Add a few transactions and insights about your spending will show up '
        'here.',
      ),
      findsOneWidget,
    );
    // The chrome survives, so the user can page somewhere with data.
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.textContaining('Showing'), findsOneWidget);
    // …and none of the body is built.
    expect(find.text('Spending pace'), findsNothing);
    expect(find.text('Savings rate'), findsNothing);
    expectNoBrokenNumbers(tester);
    expect(tester.takeException(), isNull);
  });

  // ── error ────────────────────────────────────────────────────────────────

  testWidgets('error — ErrorRetry, with the chrome still usable', (
    tester,
  ) async {
    await pump(
      tester,
      payload: '{"error":"Insights are unavailable"}',
      status: 500,
    );

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Insights are unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.textContaining('Showing'), findsOneWidget);
    expect(find.byType(LoadingCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ── loading ──────────────────────────────────────────────────────────────

  testWidgets('loading — skeleton, no unbounded wait', (tester) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gate = Completer<void>();
    // Release the request before the test ends so nothing is left hanging.
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });

    late ProviderContainer container;
    await tester.runAsync(() async {
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _Adapter(payload: _real, gate: gate);
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      container.listen<Object?>(currentInsightsProvider, (a, b) {});
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: AppTheme.light(),
          home: const Scaffold(body: InsightsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(LoadingCard), findsWidgets);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Not enough data yet'), findsNothing);
    expect(find.text('Something went wrong'), findsNothing);
    expect(tester.takeException(), isNull);

    // Unmount before the test ends so the shimmer's repeating controller is
    // disposed rather than left ticking.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // ── hostile ──────────────────────────────────────────────────────────────

  testWidgets('hostile — nine figures and a 90-character name fit 360dp', (
    tester,
  ) async {
    await pump(tester, payload: _hostile);
    final seen = await scrollThrough(tester);

    // A real baseline exists here, so the comparisons take the percentage
    // form and the "last month" lines appear.
    expect(seen, contains('vs last month'));
    expect(seen.any((t) => t.startsWith('Last month:')), isTrue);
    expect(seen, contains('700%'));
    expect(seen.any((t) => t.contains('faster than last month')), isTrue);
    // isCurrent:false switches "Projected" to "Total" and drops the progress
    // row.
    expect(seen, contains('Total this month'));
    expect(seen.any((t) => t.startsWith('Day ')), isFalse);
    // A mover that fell reads with a real minus sign, and the one with no
    // history still reads "New".
    expect(seen.any((t) => t.startsWith(Money.minus)), isTrue);
    expect(seen, contains('New'));
    // A top expense with no category and no date still renders.
    expect(seen, contains('Uncategorized'));
    expect(seen, contains('Expense'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hostile — dark mode', (tester) async {
    await pump(tester, payload: _hostile, theme: AppTheme.dark());
    final seen = await scrollThrough(tester);
    expect(find.text('Insights'), findsOneWidget);
    expect(seen, contains('Spending pace'));
    expect(tester.takeException(), isNull);
  });

  // ── period control ───────────────────────────────────────────────────────

  testWidgets('period — the segmented control switches the period', (
    tester,
  ) async {
    final container = await pump(tester);
    expect(container.read(insightsPeriodKindProvider), PeriodKind.month);

    await tester.tap(find.text('Week'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(insightsPeriodKindProvider), PeriodKind.week);
    // Stale-while-revalidate: the previous payload stays on screen instead of
    // being replaced by a skeleton under the control the user just tapped.
    expect(find.byType(LoadingCard), findsNothing);
    expect(find.text('Insights'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── drill-through ────────────────────────────────────────────────────────

  testWidgets('mover row opens the ledger filtered by that category', (
    tester,
  ) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _Adapter(payload: _real);
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      container.listen<Object?>(currentInsightsProvider, (a, b) {});
      await container.read(currentInsightsProvider.future);
    });
    addTearDown(container.dispose);

    // A stub ledger: this test is about what the tap sets and where it goes,
    // not about the real Transactions screen.
    final router = GoRouter(
      initialLocation: '/insights',
      routes: [
        GoRoute(
          path: '/insights',
          builder: (_, _) => const Scaffold(body: InsightsScreen()),
        ),
        GoRoute(
          path: '/transactions',
          builder: (_, _) => const Scaffold(body: Text('ledger')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: L.localizationsDelegates,
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Bring the mover row fully into view before tapping it.
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 120) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump();
      // Not the category name: "Groceries" is also the fallback title of
      // both top-expense rows. The signed delta belongs to the mover row
      // alone.
      final finder = find.text('+₹13,312');
      if (finder.evaluate().isNotEmpty) {
        final rect = tester.getRect(finder.first);
        if (rect.top > 60 && rect.bottom < 700) break;
      }
      if (offset >= position.maxScrollExtent) {
        fail('the mover row never came into view');
      }
    }

    await tester.tap(find.text('+₹13,312'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('ledger'), findsOneWidget);
    final query = container.read(transactionQueryProvider);
    expect(query.categoryId, '6a4669f861d974fd74ab427f');
    expect(query.type, TransactionType.expense);
    // The window is the server's own `current`, not a client-side guess.
    expect(query.from, DateTime.parse('2026-08-01T00:00:00.000Z').toLocal());
    expect(query.to, DateTime.parse('2026-09-01T00:00:00.000Z').toLocal());
    // …and the ledger's month is stamped so it opens on that period.
    expect(container.read(transactionsMonthProvider).month, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('period — the pager moves the anchor by one period', (
    tester,
  ) async {
    final container = await pump(tester);
    final before = container.read(insightsAnchorProvider);

    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    // The duration matters: moving the anchor starts a fresh request, and Dio
    // arms a zero-duration timer to do it. A bare `pump()` never fires that
    // timer, and the test then fails on a pending one at teardown.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final back = container.read(insightsAnchorProvider);
    expect(back.isBefore(before), isTrue);
    expect(back.month, before.addMonthsForTest(-1).month);

    await tester.tap(find.byIcon(LucideIcons.chevronRight));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(insightsAnchorProvider).isAfter(back), isTrue);
    expect(find.text('Insights'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

extension on DateTime {
  DateTime addMonthsForTest(int months) =>
      DateTime(year, month + months, 1, hour, minute);
}

class _Adapter implements HttpClientAdapter {
  _Adapter({required this.payload, this.status = 200, this.gate});

  final String payload;
  final int status;

  /// When set, every request waits on it — the loading-state test's handle.
  final Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (gate != null) await gate!.future;
    return ResponseBody.fromString(
      payload,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The owner's real August payload: every `pct` null, `savingsRate` both null,
/// one mover with no history, `previousToDate` 0.
const String _real =
    '{"period":"month","current":{"start":"2026-08-01T00:00:00.000Z",'
    '"end":"2026-09-01T00:00:00.000Z"},'
    '"previous":{"start":"2026-07-01T00:00:00.000Z",'
    '"end":"2026-08-01T00:00:00.000Z"},'
    '"expense":{"current":13312,"previous":0,"delta":13312,"pct":null},'
    '"income":{"current":0,"previous":0,"delta":0,"pct":null},'
    '"net":{"current":-13312,"previous":0,"delta":-13312,"pct":null},'
    '"savingsRate":{"current":null,"previous":null},'
    '"pace":{"isCurrent":true,"daysElapsed":24,"daysInPeriod":31,'
    '"avgPerDay":554.6666666666666,"projected":17195,"previousToDate":0},'
    '"movers":[{"categoryId":"6a4669f861d974fd74ab427f","name":"Groceries",'
    '"color":"#22C55E","icon":"shopping-cart","current":13312,"previous":0,'
    '"delta":13312,"pct":null}],'
    '"topExpenses":[{"_id":"6a712b806ecc7fc372fedcd6","amount":12312,'
    '"note":"","payee":"","date":"2026-08-04T00:00:00.000Z",'
    '"category":{"name":"Groceries","color":"#22C55E","icon":"shopping-cart"},'
    '"account":null},{"_id":"6a712b806ecc7fc372fedcd2","amount":1000,'
    '"note":"","payee":"","date":"2026-08-04T00:00:00.000Z",'
    '"category":{"name":"Groceries","color":"#22C55E","icon":"shopping-cart"},'
    '"account":null}],"hasData":true}';

/// What `?period=week` returns for this account today.
const String _empty =
    '{"period":"week","current":{"start":"2026-08-24T00:00:00.000Z",'
    '"end":"2026-08-31T00:00:00.000Z"},'
    '"previous":{"start":"2026-08-17T00:00:00.000Z",'
    '"end":"2026-08-24T00:00:00.000Z"},'
    '"expense":{"current":0,"previous":0,"delta":0,"pct":null},'
    '"income":{"current":0,"previous":0,"delta":0,"pct":null},'
    '"net":{"current":0,"previous":0,"delta":0,"pct":null},'
    '"savingsRate":{"current":null,"previous":null},'
    '"pace":{"isCurrent":true,"daysElapsed":1,"daysInPeriod":7,'
    '"avgPerDay":0,"projected":0,"previousToDate":0},'
    '"movers":[],"topExpenses":[],"hasData":false}';

/// hasData is true but there is nothing in it, and `daysInPeriod` is 0 — the
/// shape that would divide by zero if anything here did its own arithmetic.
const String _allZero =
    '{"period":"month","current":{"start":"2026-08-01T00:00:00.000Z",'
    '"end":"2026-09-01T00:00:00.000Z"},'
    '"previous":{"start":"2026-07-01T00:00:00.000Z",'
    '"end":"2026-08-01T00:00:00.000Z"},'
    '"expense":{"current":0,"previous":0,"delta":0,"pct":null},'
    '"income":{"current":0,"previous":0,"delta":0,"pct":null},'
    '"net":{"current":0,"previous":0,"delta":0,"pct":null},'
    '"savingsRate":{"current":null,"previous":null},'
    '"pace":{"isCurrent":true,"daysElapsed":0,"daysInPeriod":0,'
    '"avgPerDay":0,"projected":0,"previousToDate":0},'
    '"movers":[],"topExpenses":[],"hasData":true}';

/// Nine-figure amounts, a 90-character category name, a real baseline on every
/// metric, a closed period, and a mover that fell as well as ones that rose.
const String _hostile =
    '{"period":"month","current":{"start":"2026-07-01T00:00:00.000Z",'
    '"end":"2026-08-01T00:00:00.000Z"},'
    '"previous":{"start":"2026-06-01T00:00:00.000Z",'
    '"end":"2026-07-01T00:00:00.000Z"},'
    '"expense":{"current":987654321,"previous":123456789,"delta":864197532,'
    '"pct":700},'
    '"income":{"current":1234567,"previous":98765432,"delta":-97530865,'
    '"pct":-98.75},'
    '"net":{"current":-986419754,"previous":-24691357,"delta":-961728397,'
    '"pct":-3894},'
    '"savingsRate":{"current":-7900.5,"previous":75},'
    '"pace":{"isCurrent":false,"daysElapsed":31,"daysInPeriod":31,'
    '"avgPerDay":31859816.806451612,"projected":987654321,'
    '"previousToDate":123456789},'
    '"movers":['
    '{"categoryId":"c1",'
    '"name":"Kotak Mahindra Bank Cumulative Fixed Deposit — Anna Nagar West '
    'Branch Renewal","color":"#F97316","icon":"utensils",'
    '"current":900000000,"previous":100000000,"delta":800000000,"pct":800},'
    '{"categoryId":null,"name":"Uncategorised","color":null,"icon":null,'
    '"current":0,"previous":87654321,"delta":-87654321,"pct":-100},'
    '{"categoryId":"c3","name":"Groceries","color":"#22C55E",'
    '"icon":"shopping-cart","current":12345,"previous":0,"delta":12345,'
    '"pct":null}],'
    '"topExpenses":['
    '{"_id":"t1","amount":987654321,'
    '"note":"Quarterly advance tax instalment plus the late-payment interest",'
    '"payee":"","date":"2026-07-15T00:00:00.000Z",'
    '"category":{"name":"Bills & Subscriptions","color":"#EAB308",'
    '"icon":"receipt"},"account":null},'
    '{"_id":"t2","amount":50000,"note":"","payee":"","date":null,'
    '"category":null,"account":null}],'
    '"hasData":true}';
