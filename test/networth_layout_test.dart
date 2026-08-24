import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/holdings/domain/holding.dart';
import 'package:coincompass/features/holdings/presentation/widgets/holding_tile.dart';
import 'package:coincompass/features/networth/domain/net_worth_point.dart';
import 'package:coincompass/features/networth/presentation/widgets/breakdown_card.dart';
import 'package:coincompass/features/networth/presentation/widgets/net_worth_chart.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/utils/money.dart';
import 'package:coincompass/features/holdings/data/holdings_repository.dart';
import 'package:coincompass/features/holdings/presentation/holdings_screen.dart';
import 'package:coincompass/features/loans/data/loans_repository.dart';
import 'package:coincompass/features/networth/data/networth_repository.dart';
import 'package:coincompass/features/networth/presentation/networth_providers.dart';
import 'package:coincompass/features/networth/presentation/net_worth_screen.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Size phone = Size(360, 800);
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_nw');
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

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Map<String, String> payloads = const {},
    NetWorthRange range = NetWorthRange.month3,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _Adapter(payloads);
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      container.read(netWorthRangeProvider.notifier).state = range;
      for (final p in <ProviderListenable<Object?>>[
        settingsProvider,
        holdingsProvider,
        loansProvider,
        netWorthHistoryProvider,
        netWorthHistoryRangeProvider(range.days),
        netWorthSeriesProvider,
      ]) {
        container.listen<Object?>(p, (a, b) {});
      }
      await Future.wait(<Future<Object?>>[
        for (final f in <Future<Object?>>[
          container.read(settingsProvider.future),
          container.read(holdingsProvider.future),
          container.read(loansProvider.future),
          container.read(netWorthHistoryProvider.future),
          container.read(netWorthSeriesProvider.future),
        ])
          f.catchError((Object _) => null),
      ]);
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The screen's own list — not the horizontal strip the segmented control
  /// sits in, which is also a Scrollable and comes first often enough to make
  /// `.first` a coin toss.
  ScrollableState verticalList(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere((state) => state.position.axis == Axis.vertical);

  /// Winds the list back deterministically. A drag would not do: the trend
  /// chart sits under the middle of the viewport and fl_chart claims the pan
  /// gesture, so the list would never move.
  Future<void> scrollBackToTop(WidgetTester tester) async {
    verticalList(tester).position.jumpTo(0);
    await tester.pump();
  }

  /// Scrolls [text] fully inside the viewport and returns a finder for it.
  /// `ensureVisible` cannot do this here — the nearest scrollable ancestor of
  /// the segmented control is the horizontal strip it lives in, which has no
  /// vertical axis to scroll.
  Future<Finder> reveal(WidgetTester tester, String text) async {
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 160) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump();
      final finder = find.text(text);
      if (finder.evaluate().isNotEmpty) {
        final rect = tester.getRect(finder.first);
        if (rect.top > 40 && rect.bottom < 760) {
          // The pills also live in a horizontal strip that overflows a narrow
          // phone, so the last one has to be scrolled sideways into reach.
          await tester.ensureVisible(finder.first);
          await tester.pump();
          return finder.first;
        }
      }
      if (offset >= position.maxScrollExtent) {
        fail('could not bring "$text" into view');
      }
    }
  }

  /// Slivers build lazily, so everything below the fold is only laid out once
  /// it is scrolled into view — which is exactly where an overflow hides.
  Future<void> scrollThrough(WidgetTester tester) async {
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 400) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump();
      if (offset >= position.maxScrollExtent) break;
    }
  }

  for (final range in NetWorthRange.values) {
    testWidgets('net worth — recorded, ${range.label}', (tester) async {
      await pump(tester, const NetWorthScreen(), range: range);
      expect(find.text('Net Worth'), findsWidgets);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the headline figures are exact, never compacted', (
    tester,
  ) async {
    // The web app states ₹2,00,00,000 in full on the hero, on Total
    // liabilities and on the trend card; "₹2Cr" would hide the balance these
    // cards exist to report. They are single-child lines inside a FittedBox,
    // so the exact figure is safe at 360dp — only the rows where a label has
    // to share the width use `compactAbove`.
    await pump(tester, const NetWorthScreen());
    expect(find.text('${Money.minus}₹2,00,00,000'), findsWidgets);
    expect(find.text('₹2,00,00,000'), findsWidgets);
    // The dense breakdown rows still compact, and should: there a label and a
    // chevron share the line, which is the shape that overflowed before.
    for (final headline in tester.widgetList<Text>(find.byType(Text)).where(
      (t) => (t.style?.fontSize ?? 0) >= 19,
    )) {
      expect(
        headline.data,
        isNot('₹2Cr'),
        reason: 'a headline figure was compacted — state the exact balance.',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('net worth — hostile', (tester) async {
    await pump(
      tester,
      const NetWorthScreen(),
      payloads: {
        '/networth/history': _stressHistory,
        '/holdings': _stressHoldings,
      },
    );
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);

    // Every breakdown view gets laid out, not just the default one. The
    // selector sits above the fold, so the list is wound back first.
    for (final label in const ['Assets', 'Liabilities', 'Overview']) {
      await scrollBackToTop(tester);
      await tester.tap(await reveal(tester, label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('net worth — single snapshot', (tester) async {
    await pump(
      tester,
      const NetWorthScreen(),
      payloads: {'/networth/history': _oneSnapshot},
    );
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('net worth — no snapshots', (tester) async {
    await pump(
      tester,
      const NetWorthScreen(),
      payloads: {'/networth/history': '[]'},
    );
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holdings — empty', (tester) async {
    await pump(tester, const HoldingsScreen());
    expect(find.text('No holdings yet'), findsWidgets);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holdings — hostile', (tester) async {
    await pump(
      tester,
      const HoldingsScreen(),
      payloads: {'/holdings': _stressHoldings},
    );
    expect(find.text('Holdings'), findsWidgets);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holding sheet lays out at 360dp', (tester) async {
    await pump(
      tester,
      const HoldingsScreen(),
      payloads: {'/holdings': _stressHoldings},
    );
    await tester.tap(find.text('New holding'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Maturity date'), findsWidgets);
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 8; i++) {
      await tester.dragFrom(const Offset(180, 620), const Offset(0, -240));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });

  // ── the chart's degenerate shapes ─────────────────────────────────────────
  //
  // The real account has exactly two snapshots and a negative net worth, so a
  // series of 0, 1 or 2 points is the normal case rather than an edge one, and
  // a zero floor would clip the whole line.

  NetWorthPoint point(String date, num netWorth) => NetWorthPoint(
    id: date,
    date: DateTime.parse(date),
    netWorth: netWorth,
  );

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SizedBox(width: 360, child: child)),
  );

  testWidgets('chart survives 0, 1 and 2 points, and crossing zero', (
    tester,
  ) async {
    for (final points in [
      <NetWorthPoint>[],
      [point('2026-08-24', -20000000)],
      [point('2026-08-01', -20750633), point('2026-08-24', -20000000)],
      [point('2026-08-01', 0), point('2026-08-24', 0)],
      [
        point('2026-08-01', -500),
        point('2026-08-10', 0),
        point('2026-08-24', 900),
      ],
    ]) {
      await tester.pumpWidget(host(NetWorthChart(points: points)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the recorded negative snapshot reads as an improvement', (
    tester,
  ) async {
    final series = NetWorthSeries.from([
      NetWorthPoint(
        id: 'a',
        date: DateTime.parse('2026-08-01'),
        netWorth: -20750633,
        assets: -750633,
        liabilities: 20000000,
        accountsTotal: -750633,
      ),
      NetWorthPoint(
        id: 'b',
        date: DateTime.parse('2026-08-24'),
        netWorth: -20000000,
        liabilities: 20000000,
      ),
    ], NetWorthRange.month3);

    // Paying ₹7.5L off a ₹2Cr debt is +3.6%, not −3.6%: the percentage is
    // measured against the magnitude of the starting figure, because dividing
    // by a negative base flips the sign of every improvement.
    expect(series.delta, 750633);
    expect(series.deltaPercent, greaterThan(3));
    expect(series.deltaPercent, lessThan(4));
    expect(series.hasOtherAssets, isFalse);

    for (final view in BreakdownView.values) {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: BreakdownCard(series: series, view: view),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('every holding subtype has a glyph and a row that fits', (
    tester,
  ) async {
    for (final subtype in HoldingSubtype.values) {
      await tester.pumpWidget(
        host(
          HoldingTile(
            holding: Holding(
              id: 'h',
              name: 'Kotak Mahindra cumulative deposit — Anna Nagar West',
              holdingClass: subtype.holdingClass,
              subtype: subtype,
              value: 123456789,
              maturityDate: DateTime(2029, 3, 31),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this._overrides);
  final Map<String, String> _overrides;

  static const Map<String, String> _fixtures = {
    '/settings': 'settings',
    '/networth/history': 'networth_history',
    '/holdings': 'holdings',
    '/loans': 'loans',
    '/auth/me': 'auth_me',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    final fixture = _fixtures[path];
    final body = _overrides[path] ??
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

const String _oneSnapshot =
    '[{"_id":"a","date":"2026-08-24","netWorth":-20000000,"assets":0,'
    '"liabilities":20000000,"accountsTotal":0,"holdingsTotal":0,'
    '"currency":"INR"}]';

const String _stressHistory = '''
[{"_id":"a","date":"2026-05-01","netWorth":-987654321,"assets":123456789,
  "liabilities":1111111110,"accountsTotal":100000000,"holdingsTotal":23456789,
  "currency":"INR"},
 {"_id":"b","date":"2026-06-01","netWorth":-500000000,"assets":611111110,
  "liabilities":1111111110,"accountsTotal":-75063300,"holdingsTotal":400000000,
  "stocksTotal":286174410,"currency":"INR"},
 {"_id":"c","date":"2026-07-01","netWorth":0,"assets":1111111110,
  "liabilities":1111111110,"accountsTotal":500000000,"holdingsTotal":400000000,
  "stocksTotal":211111110,"currency":"INR"},
 {"_id":"d","date":"2026-08-01","netWorth":888888888,"assets":1999999998,
  "liabilities":1111111110,"accountsTotal":900000000,"holdingsTotal":700000000,
  "stocksTotal":399999998,"currency":"INR"},
 {"_id":"e","date":"2026-08-24","netWorth":123456789,"assets":1234567899,
  "liabilities":1111111110,"accountsTotal":900000000,"holdingsTotal":334567899,
  "currency":"INR"}]
''';

const String _stressHoldings = '''
[{"_id":"h1","name":"Kotak Mahindra Bank Cumulative Fixed Deposit — Anna Nagar West",
  "class":"saving","subtype":"fixed_deposit","value":123456789,
  "maturityDate":"2029-03-31T00:00:00.000Z","startDate":"2024-03-31T00:00:00.000Z",
  "note":"Auto-renew off","currency":"INR"},
 {"_id":"h2","name":"Emergency","class":"saving","subtype":"emergency_fund",
  "value":0,"currency":"INR"},
 {"_id":"h3","name":"Matured RD","class":"saving","subtype":"recurring_deposit",
  "value":250000,"maturityDate":"2020-01-01T00:00:00.000Z","currency":"INR"},
 {"_id":"h4","name":"Parag Parikh Flexi Cap Direct Growth","class":"investment",
  "subtype":"mutual_funds","value":987654321,"currency":"INR"},
 {"_id":"h5","name":"Plot","class":"investment","subtype":"real_estate",
  "value":50000000,"currency":"INR"},
 {"_id":"h6","name":"Sovereign Gold Bond 2016 Series II","class":"investment",
  "subtype":"gold","value":1234567,"maturityDate":"2032-09-30T00:00:00.000Z",
  "currency":"INR"}]
''';
