import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/widgets/app_card.dart';
import 'package:coincompass/features/insights/presentation/insights_providers.dart';
import 'package:coincompass/features/insights/presentation/insights_screen.dart';
import 'package:coincompass/features/reports/presentation/reports_providers.dart';
import 'package:coincompass/features/reports/presentation/reports_screen.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 5 layout lens — two defects that the rest of the suite cannot see.
///
/// ## Why this file loads Inter itself
///
/// `flutter test` does NOT bundle `pubspec.yaml`'s font assets. Every other
/// widget test in this repo therefore measures text in the harness fallback
/// font, whose glyphs are all exactly `fontSize` wide — "₹99,99,999" at 13.5sp
/// measures **137.5dp** there and **78.6dp** in Inter. That makes the existing
/// tests conservative about *overflow* (they see text ~75% wider than a phone
/// does, so a green suite really is green) but blind to *shrinkage*: a
/// `FittedBox` never throws, it just scales, and nothing in the suite looks at
/// the scale factor. Both defects below are shrink/alignment defects, so they
/// are asserted against the real font at the real width.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader(AppTheme.fontFamily);
    for (final f in const [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
      'assets/fonts/Inter-Bold.ttf',
    ]) {
      loader.addFont(
        Future.value(File(f).readAsBytesSync().buffer.asByteData()),
      );
    }
    await loader.load();

    tempDir = Directory.systemTemp.createTempSync('cc_layout_lens');
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

  ScrollableState listOf(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere((s) => s.position.axis == Axis.vertical);

  Future<Finder> reveal(WidgetTester tester, String text) async {
    final position = listOf(tester).position;
    for (var offset = 0.0; ; offset += 120) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump(const Duration(milliseconds: 16));
      if (find.text(text).evaluate().isNotEmpty) {
        final rect = tester.getRect(find.text(text).first);
        if (rect.top > 30 && rect.bottom < 760) return find.text(text).first;
      }
      if (offset >= position.maxScrollExtent) fail('could not reveal "$text"');
    }
  }

  /// Painted-to-laid-out height ratio: 1.0 unscaled, 0.25 means the glyphs are
  /// painted at a quarter of their nominal size by an ancestor [FittedBox].
  double paintedScale(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    final painted =
        box.localToGlobal(Offset(0, box.size.height)) -
        box.localToGlobal(Offset.zero);
    return painted.dy / box.size.height;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. reports_screen.dart:380-387 + 517-521
  //
  // `_MetricTile` wraps its value in `FittedBox(fit: scaleDown)`, which lays the
  // child out against UNBOUNDED width. The "Biggest expense" tile passes a
  // `Text(maxLines: 1, overflow: ellipsis)` as that value, so the ellipsis can
  // never fire — the text lays out at full intrinsic width and the FittedBox
  // shrinks the whole line instead. A 154dp tile against a 544dp name is a
  // 0.24x scale: 16sp painted at under 4sp.
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets(
    'reports: the biggest-expense category name ellipsises, it does not shrink',
    (tester) async {
      await _pumpReports(
        tester,
        phone: const Size(360, 800),
        payloads: {'/reports/by-category': _longNameCategory},
      );

      await reveal(tester, 'Biggest expense');
      final name = find.text(_longName);
      expect(name, findsWidgets, reason: 'the tile should name the category');

      final scale = paintedScale(tester, name.first);
      expect(
        scale,
        greaterThan(0.85),
        reason:
            'the category name is painted at ${(16 * scale).toStringAsFixed(1)}sp '
            'instead of 16sp (${scale.toStringAsFixed(3)}x). '
            'maxLines/ellipsis on the Text is dead code inside the FittedBox.',
      );
    },
  );

  testWidgets(
    'reports: the longest SEEDED category name still renders at full size',
    (tester) async {
      // "Parents Maintenance" is the longest of the 33 categories the backend
      // seeds — no hostile payload needed to trip this.
      await _pumpReports(
        tester,
        phone: const Size(360, 800),
        payloads: {'/reports/by-category': _seededLongCategory},
      );

      await reveal(tester, 'Biggest expense');
      final scale = paintedScale(tester, find.text('Parents Maintenance').first);
      expect(
        scale,
        greaterThan(0.85),
        reason:
            '"Parents Maintenance" is painted at '
            '${(16 * scale).toStringAsFixed(1)}sp beside a 20sp sibling tile',
      );
    },
  );

  // ───────────────────────────────────────────────────────────────────────────
  // 2. insights_screen.dart:766-794
  //
  // `_PaceStat` is documented as a "label-left / value-right row" and asks for
  // `alignment: Alignment.centerRight`. It never gets one: label and value are
  // both flex-1, so the Expanded label is forced to exactly half the row while
  // the loose Flexible value takes only its intrinsic width — and the slack
  // lands *after* the value, not before it. The values float mid-card with a
  // 70-100dp gutter to their right, out of line with every other value column
  // in the app and with the progress bar directly beneath them.
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('insights: spending-pace values line up on the card edge', (
    tester,
  ) async {
    await _pumpInsights(tester, phone: const Size(360, 800));

    await reveal(tester, 'Spent so far');
    // The day-progress bar under the three rows spans the card's content
    // width, so its right edge is exactly where a right-aligned value must end.
    final paceCard = find.ancestor(
      of: find.text('Spending pace'),
      matching: find.byType(AppCard),
    );
    final bar = find.descendant(
      of: paceCard,
      matching: find.byType(LinearProgressIndicator),
    );
    expect(bar, findsOneWidget, reason: 'the day-progress bar should render');
    final barRight = tester.getRect(bar).right;

    for (final value in const ['₹13,312', '₹555', '₹17,195']) {
      final finder = find.descendant(
        of: paceCard,
        matching: find.text(value),
      );
      expect(finder, findsWidgets, reason: 'pace row "$value" should render');
      final right = tester.getRect(finder.first).right;
      expect(
        right,
        closeTo(barRight, 1.0),
        reason:
            '"$value" ends at ${right.toStringAsFixed(1)}dp, '
            '${(barRight - right).toStringAsFixed(1)}dp short of the card edge '
            'at ${barRight.toStringAsFixed(1)}dp — the values are left-aligned '
            'in a ragged column, not flush right.',
      );
    }
  });
}

// ── harnesses ───────────────────────────────────────────────────────────────

Future<void> _pumpReports(
  WidgetTester tester, {
  required Size phone,
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
    container.read(reportsAnchorProvider.notifier).state = DateTime(
      2026,
      8,
      24,
      11,
      20,
    );
    container.listen<Object?>(settingsProvider, (_, _) {});
    await _settle(container.read(settingsProvider.future));

    final range = container.read(reportsRangeProvider);
    final previous = container.read(reportsPreviousRangeProvider);
    final reads = <ProviderListenable<AsyncValue<Object?>>>[
      reportsSummaryProvider(range),
      reportsSummaryProvider(previous),
      reportsByCategoryProvider(CategoryBreakdownQuery(range)),
      reportsByAccountProvider(range),
      reportsTrendProvider(range),
    ];
    for (final read in reads) {
      container.listen<Object?>(read, (_, _) {});
    }
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
        theme: AppTheme.light(),
        home: const Scaffold(body: ReportsScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpInsights(WidgetTester tester, {required Size phone}) async {
  tester.view
    ..physicalSize = phone
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late ProviderContainer container;
  await tester.runAsync(() async {
    final api = await ApiClient.create();
    api.dio.httpClientAdapter = _Adapter({'/reports/insights': _insights});
    container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    container.listen<Object?>(currentInsightsProvider, (a, b) {});
    await _settle(container.read(currentInsightsProvider.future));
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
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settle(Future<Object?> future) async {
  try {
    await future;
  } catch (_) {
    // Rendered by the card that owns the read.
  }
}

// ── payloads ────────────────────────────────────────────────────────────────

const String _longName =
    'Kotak Mahindra Bank Cumulative Fixed Deposit — Anna Nagar West';

final String _longNameCategory =
    '[{"total":13312,"count":2,"categoryId":"cat0","name":"$_longName",'
    '"color":"#22C55E","icon":"shopping-cart","group":"food","percent":100}]';

const String _seededLongCategory =
    '[{"total":13312,"count":2,"categoryId":"cat0",'
    '"name":"Parents Maintenance","color":"#22C55E","icon":"shopping-cart",'
    '"group":"family_giving","percent":100}]';

/// The owner's real August payload.
const String _insights =
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
    '"movers":[{"categoryId":"c1","name":"Groceries","color":"#22C55E",'
    '"icon":"shopping-cart","current":13312,"previous":0,"delta":13312,'
    '"pct":null}],'
    '"topExpenses":[],"hasData":true}';

class _Adapter implements HttpClientAdapter {
  _Adapter(this._overrides);

  final Map<String, String> _overrides;

  static const Map<String, String> _fixtures = {
    '/settings': 'settings',
    '/auth/me': 'auth_me',
    '/reports/summary': 'reports_summary',
    '/reports/by-category': 'reports_by-category',
    '/reports/trend': 'reports_trend',
    '/reports/insights': 'reports_insights',
  };

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
        _overrides[path] ??
        _defaults[path] ??
        (fixture == null
            ? null
            : File('test/fixtures/$fixture.json').readAsStringSync());

    if (body == null) {
      return ResponseBody.fromString(
        '{"error":"boom"}',
        500,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
