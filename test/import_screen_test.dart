import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/i18n/translated_text.dart' as cc;
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/features/accounts/data/accounts_repository.dart';
import 'package:coincompass/features/accounts/domain/account.dart';
import 'package:coincompass/features/categories/data/categories_repository.dart';
import 'package:coincompass/features/categories/domain/category.dart';
import 'package:coincompass/features/import/data/csv_file_source.dart';
import 'package:coincompass/features/import/data/import_runner.dart';
import 'package:coincompass/features/import/domain/import_plan.dart';
import 'package:coincompass/features/import/presentation/import_screen.dart';
import 'package:coincompass/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.3 — the screen, and the one promise it makes.**
///
/// Nothing is written until the user taps a button that names the row count.
/// Every test that touches the run path asserts on what actually reached the
/// runner, because "the button was disabled" and "no transaction was created"
/// are different claims and only the second one matters.
void main() {
  const Size phone = Size(360, 800);

  const header =
      'Date,Type,Amount,Currency,Account,To Account,Category,Payee,Note,Tags';

  late List<ImportPlan> ran;

  setUp(() => ran = []);

  Account account(String id, String name) =>
      Account(id: id, name: name, type: AccountType.bank);

  /// Records what it was asked to import instead of writing anything.
  ImportRunner recordingRunner() => _RecordingRunner(ran);

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required String? csv,
    List<Account> accounts = const [],
    List<Category> categories = const [],
    ImportRunner? runner,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        csvPickerProvider.overrideWithValue(
          () async => csv == null
              ? null
              : PickedCsv(name: 'statement.csv', text: csv, byteCount: csv.length),
        ),
        accountsFetchProvider.overrideWith((ref) async => accounts),
        categoriesFetchProvider.overrideWith((ref) async => categories),
        importRunnerProvider.overrideWithValue(runner ?? recordingRunner()),
      ],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      container.listen<Object?>(accountsProvider, (_, _) {});
      container.listen<Object?>(categoriesProvider, (_, _) {});
      await container.read(accountsFetchProvider.future);
      await container.read(categoriesFetchProvider.future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: AppTheme.light(),
          home: const Scaffold(body: ImportScreen()),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.text('Choose a file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('picking a file', () {
    testWidgets('opens on an explanation of the format', (tester) async {
      await pump(tester, csv: null);
      expect(find.text('Import transactions'), findsOneWidget);
      expect(find.textContaining('Date,Type,Amount'), findsOneWidget);
    });

    testWidgets('backing out of the picker returns to the start', (tester) async {
      await pump(tester, csv: null);
      await choose(tester);
      expect(find.text('Import transactions'), findsOneWidget);
    });

    testWidgets('a file with no usable header is refused with a reason',
        (tester) async {
      await pump(tester, csv: '24/08/2026,500,HDFC\n25/08/2026,600,HDFC');
      await choose(tester);
      expect(find.text('That file cannot be imported'), findsOneWidget);
      expect(find.text('Choose another file'), findsOneWidget);
    });

    testWidgets('a good file lands on the preview with a tally', (tester) async {
      await pump(
        tester,
        csv: '$header\n'
            '2026-08-24,expense,500,INR,HDFC,,,Chai,,\n'
            '2026-08-25,expense,600,INR,HDFC,,,Fuel,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);

      expect(find.text('statement.csv'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('ready'), findsOneWidget);
      expect(find.text('Import 2 transactions'), findsOneWidget);
    });
  });

  group('nothing is written until it is confirmed', () {
    testWidgets('reaching the preview writes nothing', (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,HDFC,,,Chai,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);
      expect(ran, isEmpty);
    });

    testWidgets('an unmatched name disables the button and names the count',
        (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,Jupiter,,,Chai,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);

      expect(find.text('1 name needs a decision'), findsOneWidget);
      expect(find.text('Names not in your account'), findsOneWidget);
      expect(find.text('Jupiter'), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '1 name needs a decision'),
      );
      expect(button.onPressed, isNull, reason: 'the run path must be closed');
    });

    testWidgets('deciding to create opens the run path and says what it will create',
        (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,Jupiter,,,Chai,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);

      await tester.tap(find.text('Create it'));
      await tester.pump();

      expect(find.text('Import 1 transaction'), findsOneWidget);
      expect(
        find.textContaining('will also create 1 new record'),
        findsOneWidget,
      );
    });

    testWidgets('the run button is what hands the plan to the runner',
        (tester) async {
      await pump(
        tester,
        csv: '$header\n'
            '2026-08-24,expense,500,INR,HDFC,,,Chai,,\n'
            '2026-08-25,income,900,INR,HDFC,,,Refund,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);
      expect(ran, isEmpty);

      await tester.tap(find.text('Import 2 transactions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(ran, hasLength(1));
      expect(ran.single.ready, hasLength(2));
    });
  });

  group('the questions the file cannot answer', () {
    testWidgets('an ambiguous date order is asked about, not assumed',
        (tester) async {
      await pump(
        tester,
        csv: '$header\n'
            '03/04/2026,expense,500,INR,HDFC,,,Chai,,\n'
            '05/06/2026,expense,600,INR,HDFC,,,Fuel,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);
      expect(find.text('How should the dates be read?'), findsOneWidget);
    });

    testWidgets('an unambiguous file is not asked about', (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,HDFC,,,Chai,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);
      expect(find.text('How should the dates be read?'), findsNothing);
    });

    testWidgets('a blank account column asks which account', (tester) async {
      await pump(
        tester,
        csv: 'Date,Type,Amount,Account\n2026-08-24,expense,500,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);
      expect(find.text('Which account?'), findsOneWidget);
      expect(find.text('Nothing to import'), findsOneWidget);
    });
  });

  group('rows that will not import', () {
    testWidgets('are listed with their line number, and the rest still import',
        (tester) async {
      await pump(
        tester,
        csv: '$header\n'
            '2026-08-24,expense,500,INR,HDFC,,,Good,,\n'
            '2026-08-25,expense,oops,INR,HDFC,,,Bad,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);

      expect(find.text('Rows that will not be imported'), findsOneWidget);
      expect(find.text('L3'), findsOneWidget);
      expect(find.text('Import 1 transaction'), findsOneWidget);
    });
  });

  group('user data is never machine-translated', () {
    // The device walk in Tamil showed the chosen file as `சரிபார்க்கவும் 73.csv`
    // and `ZZTest Alpha` as `Zztest ஆல்பா`, while `ZZTest Gamma` came back only
    // lower-cased — the same column rendered three ways. The stored data was
    // always right; the *preview* was not, which is the one screen whose whole
    // job is showing what will be written.
    //
    // `Text.rich` is the documented bypass in TranslatedText, so these assert
    // the user-data sites took the span path and the app-copy sites did not.
    bool isVerbatim(WidgetTester tester, String text) {
      final widgets = tester
          .widgetList<cc.Text>(find.byType(cc.Text))
          .where((w) => w.textSpan?.toPlainText() == text || w.data == text);
      expect(widgets, isNotEmpty, reason: '"$text" is not on screen at all');
      return widgets.every((w) => w.data == null && w.textSpan != null);
    }

    testWidgets('the filename bypasses the translator', (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,HDFC,,,Chai,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);
      expect(isVerbatim(tester, 'statement.csv'), isTrue);
    });

    testWidgets('an unmatched account name bypasses the translator',
        (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,Import Test,,,Chai,,',
      );
      await choose(tester);
      expect(isVerbatim(tester, 'Import Test'), isTrue);
    });

    testWidgets('a payee in the preview bypasses the translator',
        (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,HDFC,,,ZZTest Alpha,,',
        accounts: [account('a1', 'HDFC')],
      );
      await choose(tester);
      expect(isVerbatim(tester, 'ZZTest Alpha'), isTrue);
    });

    testWidgets('a created account name in the report bypasses the translator',
        (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,HDFC,,,Chai,,',
        accounts: [account('a1', 'HDFC')],
        runner: _FixedOutcomeRunner(
          const ImportOutcome(
            written: 1,
            failures: [],
            createdAccounts: ['Import Test'],
            createdCategories: [],
            stopped: false,
          ),
        ),
      );
      await choose(tester);
      await tester.tap(find.text('Import 1 transaction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(isVerbatim(tester, 'Import Test'), isTrue);
      // The label beside it is app copy and must stay translatable.
      expect(isVerbatim(tester, 'New accounts: '), isFalse);
    });

    testWidgets('app copy still goes through the translator', (tester) async {
      await pump(tester, csv: null);
      expect(isVerbatim(tester, 'Import transactions'), isFalse);
    });
  });

  group('the report', () {
    testWidgets('says what was written and what was created', (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,HDFC,,,Chai,,',
        accounts: [account('a1', 'HDFC')],
        runner: _FixedOutcomeRunner(
          const ImportOutcome(
            written: 1,
            failures: [],
            createdAccounts: ['Jupiter'],
            createdCategories: [],
            stopped: false,
          ),
        ),
      );
      await choose(tester);
      await tester.tap(find.text('Import 1 transaction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Imported'), findsOneWidget);
      expect(find.textContaining('1 transaction added'), findsOneWidget);
      expect(find.textContaining('Jupiter'), findsOneWidget);
    });

    testWidgets('a partial import says so and lists what the server rejected',
        (tester) async {
      await pump(
        tester,
        csv: '$header\n2026-08-24,expense,500,INR,HDFC,,,Chai,,',
        accounts: [account('a1', 'HDFC')],
        runner: _FixedOutcomeRunner(
          const ImportOutcome(
            written: 4,
            failures: [ImportFailure(line: 7, message: 'Validation failed', payee: 'Chai')],
            createdAccounts: [],
            createdCategories: [],
            stopped: true,
            stopReason: 'Stopped after 5 rows in a row failed.',
          ),
        ),
      );
      await choose(tester);
      await tester.tap(find.text('Import 1 transaction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Imported, with some left out'), findsOneWidget);
      expect(find.text('Rows the server rejected'), findsOneWidget);
      expect(find.textContaining('Chai — Validation failed'), findsOneWidget);
      expect(find.textContaining('Stopped after 5 rows'), findsOneWidget);
    });
  });
}

class _RecordingRunner implements ImportRunner {
  _RecordingRunner(this.ran);
  final List<ImportPlan> ran;

  @override
  Future<ImportOutcome> run(
    ImportPlan plan, {
    void Function(ImportProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    ran.add(plan);
    return ImportOutcome(
      written: plan.ready.length,
      failures: const [],
      createdAccounts: const [],
      createdCategories: const [],
      stopped: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FixedOutcomeRunner implements ImportRunner {
  _FixedOutcomeRunner(this.outcome);
  final ImportOutcome outcome;

  @override
  Future<ImportOutcome> run(
    ImportPlan plan, {
    void Function(ImportProgress)? onProgress,
    bool Function()? isCancelled,
  }) async => outcome;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
