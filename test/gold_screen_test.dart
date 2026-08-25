import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/widgets/app_card.dart';
import 'package:coincompass/features/gold/data/metals_repository.dart';
import 'package:coincompass/features/gold/domain/metal_price.dart';
import 'package:coincompass/features/gold/presentation/gold_providers.dart';
import 'package:coincompass/features/gold/presentation/gold_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coincompass/l10n/app_localizations.dart';

/// Gold & Silver: the client-side rate maths, and the screen at 360 × 800dp.
///
/// The rates the screen quotes are not all published by the API — only GRT's
/// Chennai counter rate is. Every other city is derived here, so the derivation
/// is pinned against the same numbers the web app produces.
void main() {
  const Size phone = Size(360, 800);

  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('coincompass_gold');
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

  group('rate maths', () {
    const gold = MetalPrice(
      metal: 'gold',
      date: '2026-08-24',
      retail22k: 15030,
      retail24k: 16408,
      retail18k: 12306,
      pricePerGram22k: 13046.88,
      pricePerGram24k: 14243.06,
      pricePerGram18k: 10682.29,
      pricePerOunce: 443008.68,
      change: 80,
      changePct: 0.54,
      prevClose: 14950,
      source: 'GRT · grtjewels.com',
      retailSource: 'GRT · grtjewels.com',
    );

    // Silver comes back with every retail field at 0 — the per-gram spot is
    // the only figure it publishes.
    const silver = MetalPrice(
      metal: 'silver',
      date: '2026-08-24',
      pricePerGram22k: 275,
      pricePerGram24k: 275,
      pricePerGram18k: 275,
      pricePerOunce: 8553.45,
      change: 5,
      changePct: 1.85,
      prevClose: 270,
      source: 'GRT · grtjewels.com',
    );

    test('Chennai quotes the published counter rate, not spot', () {
      final rates = MetalRates.of(gold, metalCityFor('chennai'));
      expect(rates.approx, isFalse);
      expect(rates.gram22k, 15030);
      expect(rates.gram24k, 16408);
      expect(rates.gram18k, 12306);
      expect(rates.source, 'GRT · grtjewels.com');
      expect(rates.forPurity(MetalPurity.k22), 15030);
    });

    test('another city derives from spot with its own premium', () {
      final city = metalCityFor('mumbai');
      final rates = MetalRates.of(gold, city);
      expect(city.premiumPct, 14.5);
      expect(rates.approx, isTrue);
      expect(rates.gram22k, closeTo(13046.88 * 1.145, 0.01));
      expect(rates.gram24k, closeTo(14243.06 * 1.145, 0.01));
      expect(rates.source, contains('14.5%'));
    });

    test('an unknown city key falls back to Chennai', () {
      expect(metalCityFor('atlantis').key, 'chennai');
    });

    test('silver ignores the retail board and the city premium', () {
      final rates = MetalRates.of(silver, metalCityFor('delhi'));
      expect(rates.approx, isFalse);
      expect(rates.gram24k, 275);
      expect(rates.forPurity(MetalPurity.k18), 275);
      expect(silver.headlinePrice, 275);
    });

    test('the history series is priced at the chosen purity', () {
      final rows = [
        gold,
        const MetalPrice(metal: 'gold', date: '2026-08-25', retail22k: 15100),
      ];
      final series = metalHistorySeries(
        rows,
        city: metalCityFor('chennai'),
        purity: MetalPurity.k22,
      );
      expect(series.map((point) => point.value), [15030, 15100]);
      expect(series.first.date, DateTime(2026, 8, 24));
      expect(series.every((point) => !point.approx), isTrue);
    });

    test('IST is the day boundary the board is stamped against', () {
      // 23:00 UTC is already the next day in Kolkata.
      expect(istToday(DateTime.utc(2026, 8, 23, 23)), '2026-08-24');
      expect(istToday(DateTime.utc(2026, 8, 24, 3)), '2026-08-24');
    });
  });

  Future<void> pump(
    WidgetTester tester, {
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
      const historyKey = (metal: 'gold', days: 30);
      container.listen<Object?>(metalsLatestProvider, (a, b) {});
      container.listen<Object?>(metalsHistoryProvider(historyKey), (a, b) {});
      await Future.wait(<Future<Object?>>[
        for (final future in <Future<Object?>>[
          container.read(metalsLatestProvider.future),
          container.read(metalsHistoryProvider(historyKey).future),
        ])
          future.catchError((Object _) => null),
      ]);
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: AppTheme.light(),
          home: const Scaffold(body: GoldScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 10; i++) {
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pump();
    }
  }

  testWidgets('gold — board, chart and calculator at 360dp', (tester) async {
    await pump(tester);
    expect(find.text('Gold & Silver'), findsWidgets);
    // The recorded board: 22K retail for gold, per-gram spot for silver.
    expect(find.text('₹14,950'), findsWidgets);
    expect(find.text('₹270'), findsWidgets);
    await scrollThrough(tester);
    expect(find.text('Price history'), findsWidgets);
    expect(find.text('What your gram is worth'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gold — the purity selector switches the figure', (tester) async {
    await pump(tester);
    await tester.tap(find.text('24K').first);
    await tester.pump();
    expect(find.text('₹16,321'), findsWidgets);
    await tester.tap(find.text('18K').first);
    await tester.pump();
    expect(find.text('₹12,241'), findsWidgets);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gold — picking another city marks the rate approximate', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mumbai').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Mumbai · approx'), findsWidgets);
    expect(find.textContaining('+14.5%'), findsWidgets);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gold — the calculator prices a weight at the shown purity', (
    tester,
  ) async {
    await pump(tester);
    await scrollThrough(tester);
    // 8 g of 22K Chennai gold at the recorded ₹14,950/g.
    expect(find.text('₹1,19,600'), findsWidgets);
    await tester.tap(find.text('100 g'));
    await tester.pump();
    expect(find.text('₹14.95L'), findsWidgets);
    // The calculator's own metal toggle — not the chart's, which is a
    // separate control higher up the page.
    final calculator = find.ancestor(
      of: find.text('What your gram is worth'),
      matching: find.byType(AppCard),
    );
    final silverToggle = find.descendant(
      of: calculator,
      matching: find.text('Silver'),
    );
    await tester.ensureVisible(silverToggle);
    await tester.pumpAndSettle();
    await tester.tap(silverToggle);
    await tester.pumpAndSettle();
    // 100 g of silver at the recorded ₹270 per-gram spot.
    expect(find.text('₹27,000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gold — an unconfigured deployment explains itself', (
    tester,
  ) async {
    await pump(tester, payloads: {'/metals/latest': '{"configured":false}'});
    expect(find.textContaining("isn't set up yet"), findsWidgets);
    // Nothing to re-scrape and no rate to localise.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gold — configured with no snapshot yet', (tester) async {
    await pump(tester, payloads: {'/metals/latest': '{"configured":true}'});
    expect(find.text('No rates yet'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gold — a one-row history cannot be charted', (tester) async {
    await pump(
      tester,
      payloads: {
        '/metals/history':
            '[{"metal":"gold","date":"2026-08-24","retail22k":15030,'
            '"retail24k":16408,"retail18k":12306,"pricePerGram22k":13046.88,'
            '"pricePerGram24k":14243.06,"pricePerGram18k":10682.29}]',
      },
    );
    await scrollThrough(tester);
    expect(find.textContaining('History is still building'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

/// Replays `test/fixtures/*.json`, with per-test overrides. An unmapped path
/// answers 404 so a new request shows up as an error state, never as a pass.
class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this._overrides);

  final Map<String, String> _overrides;

  static const Map<String, String> _fixtures = {
    '/metals/latest': 'metals_latest',
    '/metals/history': 'metals_history',
    '/settings': 'settings',
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
    final body =
        _overrides[path] ??
        (fixture == null
            ? null
            : File('test/fixtures/$fixture.json').readAsStringSync());

    return ResponseBody.fromString(
      body ?? '{"error":"not found"}',
      body == null ? 404 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
