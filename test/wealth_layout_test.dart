import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/features/accounts/data/accounts_repository.dart';
import 'package:coincompass/features/loans/data/loans_repository.dart';
import 'package:coincompass/features/loans/domain/loan.dart';
import 'package:coincompass/features/loans/presentation/loan_form_sheet.dart';
import 'package:coincompass/features/loans/presentation/loan_pay_sheet.dart';
import 'package:coincompass/features/loans/presentation/loan_preclose_sheet.dart';
import 'package:coincompass/features/loans/presentation/loans_screen.dart';
import 'package:coincompass/features/loans/presentation/prepayment_planner_sheet.dart';
import 'package:coincompass/features/loans/presentation/widgets/loan_card.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:coincompass/features/stocks/data/stocks_repository.dart';
import 'package:coincompass/features/stocks/presentation/stock_buy_sheet.dart';
import 'package:coincompass/features/stocks/presentation/stocks_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loans and Stocks at 360 × 800dp — the two phase-4 screens the net-worth
/// suite does not cover.
///
/// The point of the hostile payloads is one specific failure: a `Row` holding a
/// label and a nine-figure `MoneyText`. ₹2,00,00,000 is the *real* balance on
/// this account, and a ten-digit stress figure is only one order of magnitude
/// further out, so every one of these rows is laid out at the width a phone
/// actually gives it and the frame is asserted to be exception-free.
///
/// Nothing here posts. The pay, preclose and buy sheets are opened and laid
/// out; their submit buttons are never tapped, because those endpoints act
/// immediately against live data.
void main() {
  const Size phone = Size(360, 800);
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_wealth');
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

  Future<ProviderContainer> pump(
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
      api.dio.httpClientAdapter = _Adapter(payloads);
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      for (final p in <ProviderListenable<Object?>>[
        settingsProvider,
        accountsProvider,
        loansProvider,
        stockPortfolioProvider,
        stockSalesProvider,
        stockSplitsProvider,
      ]) {
        container.listen<Object?>(p, (a, b) {});
      }
      // Swallowed deliberately: several of these tests point an endpoint at a
      // 500 on purpose, and the screen's own error state is what is under
      // test. `catchError` cannot be used — its handler has to return the
      // future's own type, and null is not a Settings.
      Future<Object?> settled(Future<Object?> f) async {
        try {
          return await f;
        } catch (_) {
          return null;
        }
      }

      await Future.wait(<Future<Object?>>[
        for (final f in <Future<Object?>>[
          container.read(settingsProvider.future),
          container.read(accountsProvider.future),
          container.read(loansProvider.future),
          container.read(stockPortfolioProvider.future),
          container.read(stockSalesProvider.future),
          container.read(stockSplitsProvider.future),
        ])
          settled(f),
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
    return container;
  }

  /// The screen's own list — the segmented selectors sit in horizontal
  /// scrollables that would otherwise win a `.first`.
  ScrollableState verticalList(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere((state) => state.position.axis == Axis.vertical);

  /// Slivers below the fold are only laid out once scrolled into view, which is
  /// exactly where an overflow hides. A jump rather than a drag: fl_chart and
  /// the progress bars claim pan gestures in the middle of the viewport.
  Future<void> scrollThrough(WidgetTester tester) async {
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 400) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump();
      if (offset >= position.maxScrollExtent) break;
    }
    position.jumpTo(0);
    await tester.pump();
  }

  /// Brings [text] into the viewport and taps it.
  Future<void> revealAndTap(WidgetTester tester, String text) async {
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 120) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump();
      final finder = find.text(text);
      if (finder.evaluate().isNotEmpty) {
        final rect = tester.getRect(finder.first);
        if (rect.top > 40 && rect.bottom < 720) {
          await tester.tap(finder.first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          return;
        }
      }
      if (offset >= position.maxScrollExtent) fail('could not reach "$text"');
    }
  }

  // ── Loans ────────────────────────────────────────────────────────────────

  testWidgets('loans — the recorded ₹2Cr loan', (tester) async {
    await pump(tester, const LoansScreen());
    expect(find.text('Loans'), findsWidgets);
    // The real balance, in full — not compacted to "₹2Cr". Both the summary
    // headline and the card state it, exactly as the web app does.
    expect(find.text('₹2,00,00,000'), findsNWidgets(2));
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loans — empty', (tester) async {
    await pump(tester, const LoansScreen(), payloads: {'/loans': '[]'});
    expect(find.text('No loans yet'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loans — error offers a retry', (tester) async {
    await pump(tester, const LoansScreen(), payloads: {'/loans': _boom});
    expect(find.text('Retry'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loans — hostile, both tabs', (tester) async {
    await pump(tester, const LoansScreen(), payloads: {'/loans': _stressLoans});
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);

    for (final tab in const ['Closed', 'Active']) {
      await revealAndTap(tester, tab);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('loans — the card\'s own actions reach their sheets', (
    tester,
  ) async {
    // The real user path, hit-tested at 360dp rather than called directly:
    // the three actions sit in a Wrap on the card, below the fold.
    await pump(tester, const LoansScreen(), payloads: {'/loans': _stressLoans});
    expect(find.byType(LoanCard), findsWidgets);

    await revealAndTap(tester, 'Part payment');
    expect(find.text('Part payment'), findsWidgets);
    expect(tester.takeException(), isNull);
    // Dismiss without submitting — /loans/:id/pay acts the moment it is sent.
    Navigator.of(tester.element(find.byType(LoansScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await revealAndTap(tester, 'Planner');
    expect(tester.takeException(), isNull);
  });

  // The four sheets. Opened only — `pay` and `preclose` execute the moment
  // they are submitted, so no test may ever press their buttons.

  Widget sheetHost(Future<void> Function(BuildContext) open) => Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    ),
  );

  final biggestLoan = Loan(
    id: 'l1',
    name: 'Kotak Mahindra home loan — Anna Nagar West, Chennai',
    outstanding: 999999999,
    lender: 'Kotak Mahindra Bank Ltd',
    type: LoanType.home,
    principal: 1200000000,
    roi: 7.25,
    emi: 8500000,
    foreclosureChargePct: 2.5,
    startDate: DateTime(2026, 7, 3),
    status: LoanStatus.active,
  );

  for (final entry in <String, Future<void> Function(BuildContext, Loan)>{
    'add loan': (context, _) => LoanFormSheet.show(context).then((_) {}),
    'edit loan': (context, loan) =>
        LoanFormSheet.show(context, loan: loan).then((_) {}),
    'part payment': (context, loan) =>
        LoanPaySheet.show(context, loan: loan).then((_) {}),
    'preclose': (context, loan) =>
        LoanPrecloseSheet.show(context, loan: loan).then((_) {}),
    'prepayment planner': (context, loan) =>
        PrepaymentPlannerSheet.show(context, loan: loan),
  }.entries) {
    testWidgets('loan sheet lays out at 360dp — ${entry.key}', (tester) async {
      await pump(
        tester,
        sheetHost((context) => entry.value(context, biggestLoan)),
        payloads: {'/loans': _stressLoans},
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // Drag the sheet's own list right through: the fields below the fold are
      // where a long label and a wide amount share a Row.
      for (var i = 0; i < 8; i++) {
        await tester.dragFrom(const Offset(180, 640), const Offset(0, -220));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  }

  // ── Stocks ───────────────────────────────────────────────────────────────

  testWidgets('stocks — the recorded empty book, with no demat account', (
    tester,
  ) async {
    await pump(tester, const StocksScreen());
    expect(find.text('Stocks'), findsWidgets);
    expect(find.text("You don't have a demat account yet"), findsWidgets);
    expect(find.text('No stocks yet'), findsWidgets);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stocks — error offers a retry', (tester) async {
    await pump(
      tester,
      const StocksScreen(),
      payloads: {'/stocks/portfolio': _boom},
    );
    expect(find.text('Retry'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stocks — hostile book, both tabs', (tester) async {
    await pump(
      tester,
      const StocksScreen(),
      payloads: {
        '/accounts': _dematAccount,
        '/stocks/portfolio': _stressPortfolio,
        '/stocks/sales': _stressSales,
        '/stocks/splits': _pendingSplit,
      },
    );
    // A demat account exists now, so the nudge is gone and the book renders.
    expect(find.text("You don't have a demat account yet"), findsNothing);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);

    for (final tab in const ['Sold', 'Holdings']) {
      await revealAndTap(tester, tab);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('stocks — a position expands to its lots', (tester) async {
    await pump(
      tester,
      const StocksScreen(),
      payloads: {
        '/accounts': _dematAccount,
        '/stocks/portfolio': _stressPortfolio,
      },
    );
    await revealAndTap(tester, 'RELIANCE');
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buy sheet lays out at 360dp', (tester) async {
    await pump(
      tester,
      sheetHost((context) => StockBuySheet.show(context).then((_) {})),
      payloads: {'/accounts': _dematAccount},
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);

    for (var i = 0; i < 8; i++) {
      await tester.dragFrom(const Offset(180, 640), const Offset(0, -220));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this._overrides);
  final Map<String, String> _overrides;

  static const Map<String, String> _fixtures = {
    '/settings': 'settings',
    '/auth/me': 'auth_me',
    '/accounts': 'accounts',
    '/loans': 'loans',
    '/holdings': 'holdings',
    '/stocks/portfolio': 'stocks_portfolio',
  };

  /// Endpoints with no recorded capture. An empty list is what the live
  /// account actually answers with, so it is the honest default.
  static const Map<String, String> _empty = {
    '/stocks/sales': '[]',
    '/stocks/splits': '[]',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    final override = _overrides[path];
    if (override == _boom) {
      return ResponseBody.fromString(
        '{"error":"Server error"}',
        500,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    final fixture = _fixtures[path];
    final body =
        override ??
        _empty[path] ??
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

/// Sentinel: the adapter answers 500 so the screen shows its error state.
const String _boom = '__500__';

/// One demat account, so buying is offered rather than blocked.
const String _dematAccount =
    '[{"_id":"acc1","name":"Zerodha","type":"demat","balance":125000,'
    '"currency":"INR","includeInTotal":true}]';

/// Ten-figure balances, a name that cannot fit, a loan whose EMI cannot
/// service its interest (no payoff date at all), a zero-rate loan, and a closed
/// one so the second tab has something to lay out.
const String _stressLoans = '''
[{"_id":"l1","name":"Kotak Mahindra home loan — Anna Nagar West, Chennai",
  "lender":"Kotak Mahindra Bank Ltd","type":"home","principal":1200000000,
  "outstanding":999999999,"roi":7.25,"emi":8500000,"foreclosureChargePct":2.5,
  "interestPaid":145000000,"chargesPaid":3200000,
  "startDate":"2026-07-03T00:00:00.000Z","status":"active","currency":"INR"},
 {"_id":"l2","name":"Underwater","lender":"NBFC","type":"business",
  "principal":50000000,"outstanding":50000000,"roi":18,"emi":1000,
  "foreclosureChargePct":0,"startDate":"2024-01-01T00:00:00.000Z",
  "status":"active","currency":"INR"},
 {"_id":"l3","name":"Interest-free family loan","type":"personal",
  "principal":250000,"outstanding":125000,"roi":0,"emi":5000,
  "startDate":"2025-06-01T00:00:00.000Z","status":"active","currency":"INR"},
 {"_id":"l4","name":"Car loan, settled","lender":"HDFC","type":"car",
  "principal":900000,"outstanding":0,"roi":9.1,"emi":19000,
  "interestPaid":121000,"chargesPaid":4500,
  "startDate":"2021-02-01T00:00:00.000Z","endDate":"2026-02-01T00:00:00.000Z",
  "status":"closed","currency":"INR"}]''';

/// A book worth ₹99Cr, one position stale, one deep in the red, and lots
/// behind each so the expanded row is laid out too.
const String _stressPortfolio = '''
{"configured":true,"pricedAt":"2026-08-24T09:15:00.000Z","anyStale":true,
 "totals":{"marketValue":998877665,"investedCost":1234567890,
   "unrealized":-235690225,"unrealizedPct":-19.09,"dayChange":-12345678,
   "realizedPL":87654321,"realizedShortTerm":12345678,
   "realizedLongTerm":75308643},
 "positions":[
  {"symbol":"RELIANCE.NS","ticker":"RELIANCE","name":"Reliance Industries Ltd",
   "exchange":"NSE","demat":"acc1","qty":123456,"avgCost":2450.75,
   "price":3120.4,"marketValue":385274822,"investedCost":302589492,
   "unrealized":82685330,"unrealizedPct":27.33,"dayChange":-4567890,
   "dayChangePct":-1.17,"allocationPct":38.57,"currency":"INR",
   "pricedAt":"2026-08-24T09:15:00.000Z","stale":false,
   "lots":[{"_id":"lot1","symbol":"RELIANCE.NS","qtyRemaining":100000,
     "buyPrice":2400,"fees":12500,"buyDate":"2019-04-01T00:00:00.000Z",
     "demat":"acc1","longTerm":true},
    {"_id":"lot2","symbol":"RELIANCE.NS","qtyRemaining":23456,
     "buyPrice":2666.5,"fees":900,"buyDate":"2026-06-20T00:00:00.000Z",
     "demat":"acc1","longTerm":false,"daysToLongTerm":300}]},
  {"symbol":"YESBANK.NS","ticker":"YESBANK",
   "name":"Yes Bank Limited — restructured equity",
   "exchange":"NSE","demat":"acc1","qty":9999999,"avgCost":93.15,
   "price":12.05,"marketValue":120499988,"investedCost":931499907,
   "unrealized":-810999919,"unrealizedPct":-87.06,"allocationPct":12.06,
   "currency":"INR","pricedAt":"2026-07-01T09:15:00.000Z","stale":true,
   "lots":[{"_id":"lot3","symbol":"YESBANK.NS","qtyRemaining":9999999,
     "buyPrice":93.15,"buyDate":"2018-08-14T00:00:00.000Z","demat":"acc1"}]},
  {"symbol":"NOPRICE.BO","ticker":"NOPRICE","exchange":"BSE","demat":"acc1",
   "qty":10,"avgCost":100,"marketValue":0,"investedCost":1000,
   "unrealized":-1000,"unrealizedPct":-100,"currency":"INR","stale":true,
   "lots":[]}]}''';

const String _stressSales = '''
[{"_id":"s1","symbol":"INFY.NS","ticker":"INFY","qty":50000,"sellPrice":1899.9,
  "buyPrice":455.2,"realizedPL":72235000,"realizedLongTerm":72235000,
  "realizedShortTerm":0,"term":"long","buyDate":"2017-03-01T00:00:00.000Z",
  "sellDate":"2026-08-01T00:00:00.000Z"},
 {"_id":"s2","symbol":"PAYTM.NS","ticker":"PAYTM","qty":12000,"sellPrice":410,
  "buyPrice":1955,"realizedPL":-18540000,"realizedShortTerm":-18540000,
  "realizedLongTerm":0,"term":"short","buyDate":"2026-01-10T00:00:00.000Z",
  "sellDate":"2026-08-20T00:00:00.000Z"},
 {"_id":"s3","symbol":"STRADDLE.NS","ticker":"STRADDLE","qty":900,
  "sellPrice":1200,"buyPrice":800,"realizedPL":360000,
  "realizedLongTerm":200000,"realizedShortTerm":160000,
  "sellDate":"2026-08-22T00:00:00.000Z"}]''';

const String _pendingSplit =
    '[{"symbol":"RELIANCE.NS","ticker":"RELIANCE","label":"1:5",'
    '"date":"2026-08-14","qtyBefore":123456,"qtyAfter":617280}]';
