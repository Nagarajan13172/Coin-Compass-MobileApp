import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/features/reports/data/export_repository.dart';
import 'package:coincompass/features/reports/domain/report_models.dart';
import 'package:coincompass/features/reports/presentation/export_csv_sheet.dart';
import 'package:coincompass/features/reports/presentation/period.dart';
import 'package:coincompass/features/reports/presentation/reports_providers.dart';
import 'package:coincompass/features/reports/presentation/reports_screen.dart';
import 'package:coincompass/features/reports/presentation/widgets/category_breakdown_card.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders `/reports` at 360 × 800dp against the recorded payloads and against
/// the shapes that actually break layouts: everything empty, everything
/// failing, one trend bucket, no accounts, no previous period, and a hostile
/// payload of 40-character category names next to nine-figure amounts.
///
/// The owner's real data IS the sparse case — 2 transactions, 1 category, 0
/// accounts — so that is the first thing asserted, not an afterthought.
///
/// NEVER `pumpAndSettle` here: `LoadingShimmer` repeats forever, so a settle
/// on a loading card would spin until the test timed out. Every wait is an
/// explicit `pump(Duration)`.
void main() {
  const Size phone = Size(360, 800);

  /// Fixed so the pager label is deterministic — the screen otherwise anchors
  /// on `DateTime.now()` and the assertions would rot with the wall clock.
  final anchor = DateTime(2026, 8, 24, 11, 20);

  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_reports');
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

  /// Warms every read the screen makes, then mounts it against the resolved
  /// container. Warming happens inside `runAsync` because that is the only
  /// place a real Future resolves inside a `testWidgets` body.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Map<String, String> payloads = const {},
    _Responder? responder,
    bool dark = false,
    List<Override> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = _Adapter(payloads, responder);
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api), ...overrides],
      );
      container.read(reportsAnchorProvider.notifier).state = anchor;

      // Settings first: the window's week start is read from it, so resolving
      // it before deriving the range keeps the warmed family keys identical to
      // the ones the widget will ask for.
      container.listen<Object?>(settingsProvider, (_, _) {});
      try {
        await container.read(settingsProvider.future);
      } catch (_) {
        // Rendered by the cards that need it; the window falls back to Monday.
      }

      final range = container.read(reportsRangeProvider);
      final previous = container.read(reportsPreviousRangeProvider);
      final reads = <ProviderListenable<AsyncValue<Object?>>>[
        reportsSummaryProvider(range),
        reportsSummaryProvider(previous),
        reportsByCategoryProvider(CategoryBreakdownQuery(range)),
        reportsByAccountProvider(range),
        reportsTrendProvider(range),
      ];
      // autoDispose families need a live listener or the warm-up is discarded
      // the instant it resolves.
      for (final read in reads) {
        container.listen<Object?>(read, (_, _) {});
      }
      // `catchError` cannot be used here: the futures are typed
      // Future<ReportSummary> at runtime, so an onError returning null is an
      // ArgumentError rather than a swallowed failure — which is exactly how
      // the "every endpoint failing" case used to blow up inside the warm-up.
      await Future.wait(<Future<void>>[
        _settle(container.read(reportsSummaryProvider(range).future)),
        _settle(container.read(reportsSummaryProvider(previous).future)),
        _settle(
          container.read(
            reportsByCategoryProvider(CategoryBreakdownQuery(range)).future,
          ),
        ),
        _settle(container.read(reportsByAccountProvider(range).future)),
        _settle(container.read(reportsTrendProvider(range).future)),
      ]);
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: const Scaffold(body: ReportsScreen()),
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
  /// scrolls into view — which is exactly where an overflow hides. Bounded:
  /// it stops at `maxScrollExtent`, never loops on a growing list.
  Future<void> scrollThrough(WidgetTester tester) async {
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 320) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump(const Duration(milliseconds: 16));
      if (offset >= position.maxScrollExtent) break;
    }
    position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Brings whatever [target] matches into the viewport and returns a finder
  /// for it. Bounded by `maxScrollExtent`, so it cannot spin.
  Future<Finder> revealFinder(
    WidgetTester tester,
    Finder target, {
    String? what,
  }) async {
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 140) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump(const Duration(milliseconds: 16));
      if (target.evaluate().isNotEmpty) {
        final rect = tester.getRect(target.first);
        if (rect.top > 30 && rect.bottom < 770) return target.first;
      }
      if (offset >= position.maxScrollExtent) {
        fail('could not bring ${what ?? target.toString()} into view');
      }
    }
  }

  Future<Finder> reveal(WidgetTester tester, String text) =>
      revealFinder(tester, find.text(text), what: '"$text"');

  /// The same, but scoped to one card — "Income" appears as a stat label, a
  /// chart legend AND a donut toggle, so an unscoped `find.text` picks the
  /// wrong one.
  Future<Finder> revealIn(
    WidgetTester tester,
    Type card,
    String text,
  ) => revealFinder(
    tester,
    find.descendant(of: find.byType(card), matching: find.text(text)),
    what: '"$text" inside $card',
  );

  // ── the account's real data ───────────────────────────────────────────────

  testWidgets('reports — recorded payloads', (tester) async {
    await pump(tester);

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Analyse your income and spending'), findsOneWidget);
    // The web never says "This month" on this screen, and neither do we.
    expect(
      find.textContaining('August 2026 · Month view', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('This month'), findsNothing);
    expect(find.text('₹13,312'), findsWidgets);
    expect(find.text('2 transactions'), findsOneWidget);

    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports — the one category, and its insight sentence', (
    tester,
  ) async {
    await pump(tester);
    await reveal(tester, 'By category');
    expect(find.text('Groceries'), findsWidgets);
    expect(find.text('Total spent'), findsWidgets);
    expect(
      find.textContaining('your biggest expense is', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports — no accounts renders the empty state, not a chart', (
    tester,
  ) async {
    await pump(tester);
    await reveal(tester, 'By account');
    expect(find.text('Money in vs out per account'), findsOneWidget);
    // House voice, shared with every other empty state in the app: it says
    // what is missing and why, never a bare "No data".
    expect(find.text('No account activity yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports — a null metric is an em dash, never a zero', (
    tester,
  ) async {
    // Income 0 -> no savings rate to compute; previous expense 0 -> no
    // month-on-month percentage. Both are "there is nothing to compare",
    // which is not the same statement as 0%.
    await pump(
      tester,
      responder: (options) {
        if (!options.uri.path.endsWith('/reports/summary')) return null;
        // Parse rather than string-match: `from` goes out as a UTC instant,
        // so July's local midnight is "2026-06-30T18:30:00Z" from an IST
        // machine and a `startsWith('2026-07')` check would silently miss.
        final from = DateTime.tryParse(
          options.uri.queryParameters['from'] ?? '',
        )?.toLocal();
        final isPrevious = from != null && from.isBefore(DateTime(2026, 8));
        // The previous window (July) is genuinely empty on this account.
        return isPrevious
            ? _zeroSummary
            : File('test/fixtures/reports_summary.json').readAsStringSync();
      },
    );

    await reveal(tester, 'Savings rate');
    expect(find.text('—'), findsWidgets);
    expect(find.text('No income to divide by'), findsOneWidget);
    expect(find.text('Spending vs last month'), findsOneWidget);
    // No baseline means no "Last month: …" caption either.
    expect(find.textContaining('Last month:'), findsNothing);
    expect(find.text('0%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports — a single trend bucket still draws', (tester) async {
    await pump(tester);
    await reveal(tester, 'Income vs Expense');
    expect(find.text('One bucket with activity in this period.'), findsOneWidget);
    expect(find.text('No data for this period'), findsNothing);
    await reveal(tester, 'Net cash flow');
    expect(find.text('Income minus expense over time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports — the consumption split explains the savings rate', (
    tester,
  ) async {
    await pump(tester);
    await reveal(tester, 'Where it went');
    expect(find.text('Consumed'), findsOneWidget);
    expect(find.text('Set aside'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── empty, failing and hostile ────────────────────────────────────────────

  testWidgets('reports — nothing at all', (tester) async {
    await pump(
      tester,
      payloads: {
        '/reports/summary': _zeroSummary,
        '/reports/by-category': '[]',
        '/reports/by-account': '[]',
        '/reports/trend': '[]',
      },
    );

    expect(find.text('Reports'), findsOneWidget);
    // The donut is on `expense`, so the empty state names that side.
    await reveal(tester, 'No spending this period');
    expect(find.text('No spending this period'), findsOneWidget);
    await reveal(tester, 'No account activity yet');
    expect(find.text('No account activity yet'), findsOneWidget);
    // The chart placeholder keeps the web's own wording.
    await reveal(tester, 'No data for this period');
    // The charts render the placeholder at their full height. Only the ones
    // currently in the viewport are built, so this is `findsWidgets`.
    expect(find.text('No data for this period'), findsWidgets);
    // Nothing was spent, so neither the split card nor the insight banner
    // has anything to say.
    expect(find.text('Where it went'), findsNothing);
    expect(
      find.textContaining('your biggest expense is', findRichText: true),
      findsNothing,
    );
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports — every endpoint failing', (tester) async {
    await pump(tester, responder: (_) => _fail);

    expect(find.text('Reports'), findsOneWidget);
    // The header and the period bar survive: a failed read degrades a card,
    // never the controls that would let you retry with a different window.
    expect(
      find.textContaining('August 2026 · Month view', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Something went wrong'), findsWidgets);
    expect(find.text('Retry'), findsWidgets);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports — hostile payloads at 360dp', (tester) async {
    await pump(
      tester,
      payloads: {
        '/reports/summary': _hostileSummary,
        '/reports/by-category': _hostileCategories,
        '/reports/by-account': _hostileAccounts,
        '/reports/trend': _hostileTrend,
      },
    );
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);

    // Expand the biggest group and scroll again — the children are a second
    // row shape, with a smaller avatar and an indent.
    final chevron = find.text('Food');
    if (chevron.evaluate().isNotEmpty) {
      await tester.tap(await reveal(tester, 'Food'));
      await tester.pump(const Duration(milliseconds: 250));
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reports — dark mode', (tester) async {
    await pump(tester, dark: true, payloads: {
      '/reports/by-account': _hostileAccounts,
    });
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  // ── controls ──────────────────────────────────────────────────────────────

  testWidgets('period selector and pager move the window', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.text('Week'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(reportsPeriodKindProvider), PeriodKind.week);
    expect(
      find.textContaining('Week view', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Year'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('2026 · Year view', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Month'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The pager is NOT clamped to today — the web lets you page forward into
    // an empty period, and so does this.
    await tester.tap(find.bySemanticsLabel('Next period'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('September 2026 · Month view', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Previous period'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Previous period'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('July 2026 · Month view', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the donut toggles swap grouping and side of the ledger', (
    tester,
  ) async {
    final container = await pump(tester);

    await tester.tap(await revealIn(tester, CategoryBreakdownCard, 'All'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(categoryGroupingProvider), CategoryGrouping.flat);
    // Flat mode names the category itself rather than its group.
    expect(find.text('Groceries'), findsWidgets);

    await tester.tap(await revealIn(tester, CategoryBreakdownCard, 'Income'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(reportsBreakdownTypeProvider), 'income');
    expect(find.text('Total earned'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the avg-daily hint is reachable by tap', (tester) async {
    await pump(tester);
    await reveal(tester, 'Avg daily spend');
    await tester.tap(find.byTooltip(_avgHint));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(_avgHint), findsOneWidget);
    // Let the tooltip's own dismiss timer fire, or it outlives the test.
    await tester.pump(const Duration(seconds: 8));
    expect(tester.takeException(), isNull);
  });

  // ── export ────────────────────────────────────────────────────────────────

  testWidgets('the export sheet lays out and offers all three windows', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Export CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Download transactions'), findsOneWidget);
    expect(find.text('This period'), findsOneWidget);
    // The default range is the window's own days — 1 Aug to 31 Aug, i.e. the
    // last day INSIDE the exclusive end, never 01 Sep.
    expect(
      find.descendant(
        of: find.byType(ExportCsvSheet),
        matching: find.text('August 2026'),
      ),
      findsOneWidget,
    );
    expect(find.text('All transactions'), findsOneWidget);
    expect(find.text('Custom range'), findsOneWidget);
    expect(find.text('01 Aug'), findsOneWidget);
    expect(find.text('31 Aug'), findsOneWidget);
    expect(find.text('Export range'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exporting this period writes a file and shares it', (
    tester,
  ) async {
    final shared = <ExportedCsv>[];
    await pump(
      tester,
      payloads: {'/export/csv': _csv},
      overrides: [
        csvSharerProvider.overrideWithValue((csv) async => shared.add(csv)),
      ],
    );

    await tester.tap(find.text('Export CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('This period'));
    await tester.pump();

    await _drain(tester, until: () => shared.isNotEmpty);

    expect(shared, hasLength(1));
    expect(shared.single.fileName, 'coincompass-transactions-2026-08-24-INR.csv');
    expect(File(shared.single.path).existsSync(), isTrue);
    expect(shared.single.byteCount, greaterThan(0));

    // The sheet closes on success.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Custom range'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failing export reports it in the sheet, and stays open', (
    tester,
  ) async {
    await pump(
      tester,
      responder: (options) =>
          options.uri.path.endsWith('/export/csv') ? _fail : null,
      overrides: [
        csvSharerProvider.overrideWithValue(
          (csv) async => fail('nothing should be shared'),
        ),
      ],
    );

    await tester.tap(find.text('Export CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('All transactions'));
    await tester.pump();
    await _drain(tester, until: () => find.text('boom').evaluate().isNotEmpty);

    // The sheet stays open with the SERVER'S message on it — the CSV body is
    // bytes, so `ExportRepository` has to decode it before the usual
    // Zod-envelope parsing can find the `error` key. A generic "request
    // failed" here would mean that decode regressed.
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Custom range'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ── the pure grouping the donut and legend are built from ─────────────────

  group('buildCategoryRows', () {
    CategorySlice slice(
      String name,
      num total, {
      String? group,
      num percent = 0,
      String? id,
    }) => CategorySlice(
      name: name,
      categoryId: id ?? name,
      total: total,
      percent: percent,
      group: group,
      color: '#22C55E',
    );

    test('flat mode keeps the server percent and sorts biggest first', () {
      final rows = buildCategoryRows(
        [
          slice('Rent', 40000, percent: 40),
          slice('Groceries', 60000, percent: 60),
        ],
        grouped: false,
      );
      expect(rows.map((r) => r.name), ['Groceries', 'Rent']);
      expect(rows.first.percent, 60);
      expect(rows.first.isGroup, isFalse);
    });

    test('group mode folds by group key and recomputes to one decimal', () {
      final rows = buildCategoryRows(
        [
          slice('Groceries', 1000, group: 'food'),
          slice('Dining', 2000, group: 'food'),
          slice('Fuel', 3000, group: 'transport'),
        ],
        grouped: true,
      );
      expect(rows.map((r) => r.name), ['Food', 'Transport']);
      expect(rows.first.total, 3000);
      expect(rows.first.percent, 50);
      // Children come back biggest-first too, so the expanded list reads the
      // same way the collapsed one does.
      expect(rows.first.children.map((r) => r.name), ['Dining', 'Groceries']);
      expect(rows.first.isGroup, isTrue);
    });

    test('a category with no group lands in Ungrouped, not Other', () {
      final rows = buildCategoryRows([slice('Misc', 500)], grouped: true);
      expect(rows.single.name, 'Ungrouped');
      expect(rows.single.children.single.name, 'Misc');
    });

    test('zero and negative totals are dropped — a donut cannot draw them', () {
      expect(
        buildCategoryRows([slice('Nothing', 0), slice('Refund', -5)],
            grouped: false),
        isEmpty,
      );
      expect(buildCategoryRows(const [], grouped: true), isEmpty);
    });

    test('an unknown group inherits its biggest child colour', () {
      final rows = buildCategoryRows(
        [
          CategorySlice(
            name: 'Crypto',
            categoryId: 'c1',
            total: 900,
            group: 'invented_by_the_server',
            color: '#123456',
          ),
        ],
        grouped: true,
      );
      expect(rows.single.color, const Color(0xFF123456));
      expect(rows.single.name, 'Other');
    });
  });
}

const String _avgHint =
    'Total spent ÷ days elapsed in this period, so a partial month isn’t '
    'divided by a full 30 days.';

const String _fail = '__fail__';

const String _zeroSummary = '{"income":0,"expense":0,"net":0,"incomeCount":0,'
    '"expenseCount":0,"oneoffIncome":0,"oneoffExpense":0,"consumption":0,'
    '"nonConsumption":0,"netWorth":0,"byCurrency":{},'
    '"range":{"start":"2026-08-01T00:00:00.000Z","end":"2026-09-01T00:00:00.000Z"}}';

const String _hostileSummary =
    '{"income":123456789,"expense":987654321,"net":-864197532,"incomeCount":9,'
    '"expenseCount":874,"oneoffIncome":0,"oneoffExpense":0,'
    '"consumption":887654321,"nonConsumption":100000000,"netWorth":-20000000,'
    '"byCurrency":{},'
    '"range":{"start":"2026-08-01T00:00:00.000Z","end":"2026-09-01T00:00:00.000Z"}}';

final String _hostileCategories = _json([
  for (var i = 0; i < 24; i++)
    '{"total":${(24 - i) * 4000037},"count":${i + 1},'
        '"categoryId":"cat$i",'
        '"name":"Kotak Mahindra cumulative deposit — Anna Nagar West $i",'
        '"color":"#22C55E","icon":"shopping-cart",'
        '"group":"${_groups[i % _groups.length]}","percent":${(100 / 24)}}',
]);

const List<String> _groups = [
  'food',
  'transport',
  'home',
  'bills',
  'invented_by_the_server',
];

final String _hostileAccounts = _json([
  for (var i = 0; i < 6; i++)
    '{"_id":"acc$i","name":"Kotak Mahindra Bank savings — Anna Nagar West $i",'
        '"color":"#3B82F6","income":${123456789 - i * 1000},'
        '"expense":${98765432 + i * 7},"transferIn":${5000 * i},'
        '"transferOut":${900 * i}}',
]);

final String _hostileTrend = _json([
  for (var day = 1; day <= 31; day++)
    '{"bucket":"2026-08-${day.toString().padLeft(2, '0')}",'
        '"income":${day * 31337},"expense":${day * 51337},'
        '"net":${day * 31337 - day * 51337}}',
]);

const String _csv = 'Date,Type,Amount,Currency,Account,To Account,Category,'
    'Payee,Note,Tags\n2026-08-04,expense,1000,INR,,,Groceries,,,\n';

String _json(List<String> rows) => '[${rows.join(',')}]';

/// Lets a mixed real/fake async chain finish.
///
/// The export path is both: Dio's timeouts are fake timers that only advance
/// with `pump`, while the HTTP response and the `File.writeAsBytes` complete on
/// the REAL event loop, which a widget test's fake-async zone never reaches.
/// Neither a plain pump loop nor a plain `runAsync` finishes it — this
/// alternates the two. Bounded at 40 rounds so a stall fails rather than hangs.
Future<void> _drain(WidgetTester tester, {required bool Function() until}) async {
  for (var i = 0; i < 40 && !until(); i++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(Future<Object?> future) async {
  try {
    await future;
  } catch (_) {
    // Rendered as an ErrorRetry by the card that owns the read.
  }
}

typedef _Responder = String? Function(RequestOptions options);

class _Adapter implements HttpClientAdapter {
  _Adapter(this._overrides, this._responder);

  final Map<String, String> _overrides;
  final _Responder? _responder;

  static const Map<String, String> _fixtures = {
    '/settings': 'settings',
    '/auth/me': 'auth_me',
    '/reports/summary': 'reports_summary',
    '/reports/by-category': 'reports_by-category',
    '/reports/trend': 'reports_trend',
  };

  /// No capture exists for this one — the owner has no accounts, so the live
  /// response really is an empty array.
  static const Map<String, String> _defaults = {'/reports/by-account': '[]'};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    final fixture = _fixtures[path];
    final body =
        _responder?.call(options) ??
        _overrides[path] ??
        _defaults[path] ??
        (fixture == null
            ? null
            : File('test/fixtures/$fixture.json').readAsStringSync());

    if (body == null || body == _fail) {
      return ResponseBody.fromString(
        '{"error":"boom"}',
        500,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final csv = path == '/export/csv';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [
          csv ? 'text/csv; charset=utf-8' : Headers.jsonContentType,
        ],
        if (csv)
          'content-disposition': [
            'attachment; filename="coincompass-transactions-2026-08-24-INR.csv"',
          ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
