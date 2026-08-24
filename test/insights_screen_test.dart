import 'dart:async';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
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
import 'package:flutter_test/flutter_test.dart';

/// `/insights` at 360 × 800dp, against the shapes the live account actually
/// returns.
///
/// The whole stack is real — repository, providers, widgets — with only the
/// Dio transport swapped for an adapter that replays a payload per `period`.
///
/// NOTE ON PUMPING: this screen shows [LoadingShimmer] (an endlessly repeating
/// controller) and a [RefreshIndicator], so `pumpAndSettle` would never
/// return. Every wait below is an explicit `pump(Duration)`.
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
    Map<String, String> byPeriod = const {},
    int status = 200,
    ThemeData? theme,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _Adapter(
        payload: payload,
        byPeriod: byPeriod,
        status: status,
      );
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      // Hold the autoDispose reads open for the life of the test.
      container.listen<Object?>(currentInsightsProvider, (a, b) {});
      await container
          .read(currentInsightsProvider.future)
          .catchError((Object _) => throw _Swallowed());
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
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

  /// Slivers build lazily, so a card below the fold is only laid out once it
  /// scrolls into view — which is exactly where an overflow hides.
  Future<void> scrollThrough(WidgetTester tester) async {
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 300) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (offset >= position.maxScrollExtent) break;
    }
    position.jumpTo(0);
    await tester.pump();
  }

  String? textOf(Widget widget) {
    final text = widget as Text;
    return text.data ?? text.textSpan?.toPlainText();
  }

  /// The failure this screen exists to avoid: a null percentage rendered
  /// literally, or a division by a zero previous period.
  void expectNoBrokenNumbers(WidgetTester tester) {
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      final data = textOf(widget);
      if (data == null) continue;
      for (final poison in const ['null', 'NaN', 'Infinity', '%%']) {
        expect(
          data.contains(poison),
          isFalse,
          reason: 'rendered "$data" — contains "$poison"',
        );
      }
    }
  }

  Iterable<String> allText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map(textOf)
      .whereType<String>();

  // ── loaded ───────────────────────────────────────────────────────────────

  testWidgets('loaded — the live payload, top to bottom', (tester) async {
    await pump(tester);

    expect(find.text('Insights'), findsOneWidget);
    expect(
      find.text('How your spending is changing, period over period.'),
      findsOneWidget,
    );
    // Week / Month / Year and the pager label.
    expect(find.text('Month'), findsOneWidget);
    expect(find.textContaining('Showing'), findsOneWidget);

    expect(find.text('Spending'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Net'), findsOneWidget);
    expect(find.text('₹13,312'), findsWidgets);
    expect(find.text('${Money.minus}₹13,312'), findsWidgets);

    await scrollThrough(tester);

    expect(find.text('Spending pace'), findsOneWidget);
    expect(find.text('What changed'), findsOneWidget);
    expect(find.text('Biggest expenses'), findsOneWidget);
    expect(find.text('Groceries'), findsWidgets);
    expectNoBrokenNumbers(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loaded — pull-to-refresh is wired', (tester) async {
    await pump(tester);
    // Not dragged: the indicator is indeterminate and its future is a real
    // network call, so a drag would spin past the end of the test.
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  // ── the degenerate path: no previous period at all ───────────────────────

  testWidgets('degenerate — every pct is null and nothing says "null"', (
    tester,
  ) async {
    await pump(tester);
    await scrollThrough(tester);

    final texts = allText(tester).toList();

    // The delta pill falls back to a compact amount, never a percentage.
    expect(texts, contains('₹13K'));
    // Spending and Net both moved with no baseline; Income did not move.
    expect(texts, contains('No change'));
    // The dead "Last month: ₹0" line is replaced by a statement of fact.
    expect(texts, contains('nothing spent last month'));
    expect(texts, contains('nothing earned last month'));
    expect(texts, contains('nothing recorded last month'));
    expect(
      texts.any((t) => t.startsWith('Last month:')),
      isFalse,
      reason: 'a zero previous period must not be reported as a comparison',
    );

    // A mover with no history reads "New", not "null%".
    expect(texts, contains('New'));

    // savingsRate {current: null} — an em dash, and a sentence saying why.
    expect(texts, contains('—'));
    expect(
      texts,
      contains('No income this month — a savings rate needs income to '
          'divide by.'),
    );

    // pace.previousToDate == 0 hides the faster/slower line entirely rather
    // than dividing by it.
    expect(texts.any((t) => t.contains('at this point')), isFalse);

    // The first period is a designed state, not a degraded one.
    expect(
      texts.any((t) => t.startsWith('This is your first month with data')),
      isTrue,
    );

    expectNoBrokenNumbers(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('degenerate — an all-zero period divides by nothing', (
    tester,
  ) async {
    await pump(tester, payload: _allZero);
    await scrollThrough(tester);

    final texts = allText(tester).toList();
    expect(texts.where((t) => t == 'No change').length, greaterThanOrEqualTo(3));
    expect(texts, contains('No category changes to show.'));
    expect(texts, contains('No expenses in this period.'));
    // daysInPeriod == 0 must not produce a progress bar or a NaN percentage.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expectNoBrokenNumbers(tester);
    expect(tester.takeException(), isNull);
  });

  // ── empty ────────────────────────────────────────────────────────────────

  testWidgets('empty — hasData:false keeps the header and pager', (
    tester,
  ) async {
    await pump(tester, payload: _empty);

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
    expect(tester.takeException(), isNull);
  });

  // ── error ────────────────────────────────────────────────────────────────

  testWidgets('error — ErrorRetry, with the chrome still usable', (
    tester,
  ) async {
    await pump(tester, payload: '{"message":"Insights are unavailable"}',
        status: 500);

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Insights are unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.textContaining('Showing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── loading ──────────────────────────────────────────────────────────────

  testWidgets('loading — skeleton, no unbounded wait', (tester) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gate = Completer<String>();
    // Release the request before the test ends so nothing is left hanging.
    addTearDown(() {
      if (!gate.isCompleted) gate.complete(_real);
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
    expect(tester.takeException(), isNull);

    // Unmount before the test ends so the shimmer's repeating controller is
    // disposed rather than left ticking.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // ── hostile ──────────────────────────────────────────────────────────────

  testWidgets('hostile — nine figures and 90-character names fit 360dp', (
    tester,
  ) async {
    await pump(tester, payload: _hostile);
    await scrollThrough(tester);

    final texts = allText(tester).toList();
    // A real baseline exists here, so the comparisons are the percentage form.
    expect(texts, contains('vs last month'));
    expect(texts.any((t) => t.startsWith('Last month:')), isTrue);
    expect(texts.any((t) => t.contains('faster than last month')), isTrue);
    // isCurrent:false switches "Projected" to "Total" and drops the progress
    // bar.
    expect(texts, contains('Total this month'));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expectNoBrokenNumbers(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hostile — dark mode', (tester) async {
    await pump(tester, payload: _hostile, theme: AppTheme.dark());
    await scrollThrough(tester);
    expect(find.text('Insights'), findsOneWidget);
    expectNoBrokenNumbers(tester);
    expect(tester.takeException(), isNull);
  });

  // ── period control ───────────────────────────────────────────────────────

  testWidgets('period — Week refetches and can land on the empty state', (
    tester,
  ) async {
    final container = await pump(
      tester,
      byPeriod: {'week': _empty, 'month': _real},
    );
    expect(find.text('Spending pace'), findsOneWidget);

    await tester.tap(find.text('Week'));
    await tester.pump();
    await tester.runAsync(() async {
      try {
        await container.read(currentInsightsProvider.future);
      } catch (_) {
        // Rendered by the screen.
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(insightsPeriodKindProvider), PeriodKind.week);
    expect(find.text('Not enough data yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('period — the pager moves the anchor by one period', (
    tester,
  ) async {
    final container = await pump(tester);
    final before = container.read(insightsAnchorProvider);

    await tester.tap(find.bySemanticsLabel('Previous period'));
    await tester.pump();
    final back = container.read(insightsAnchorProvider);
    expect(back.isBefore(before), isTrue);

    await tester.tap(find.bySemanticsLabel('Next period'));
    await tester.pump();
    expect(container.read(insightsAnchorProvider).isAfter(back), isTrue);
    expect(tester.takeException(), isNull);
  });
}

class _Swallowed implements Exception {}

class _Adapter implements HttpClientAdapter {
  _Adapter({
    required this.payload,
    this.byPeriod = const {},
    this.status = 200,
    this.gate,
  });

  final String payload;
  final Map<String, String> byPeriod;
  final int status;

  /// When set, every request waits on it — the loading-state test's handle.
  final Completer<String>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (gate != null) await gate!.future;
    final period = options.uri.queryParameters['period'] ?? 'month';
    return ResponseBody.fromString(
      byPeriod[period] ?? payload,
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
