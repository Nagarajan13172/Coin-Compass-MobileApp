import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 6.4's source guard.
///
/// A separate file from `write_schema_test.dart` on purpose: that guard exists
/// because two rounds of the owner's data were silently discarded, and nothing
/// in this phase should be able to blunt it. This one covers the failure modes
/// 6.4 introduces, all of which are **silent** — they compile, they run, and
/// they are wrong.
void main() {
  /// Every list a screen watches. Each of these names now belongs to a
  /// `Provider<AsyncValue<List<T>>>` that folds in-flight optimistic writes
  /// over its `<x>FetchProvider`.
  const viewProviders = [
    'accountsProvider',
    'budgetsProvider',
    'categoriesProvider',
    'creditsProvider',
    'goalsProvider',
    'holdingsProvider',
    'loansProvider',
    'peopleProvider',
    'personGroupsProvider',
    'recurringRulesProvider',
    'splitsProvider',
    'templatesProvider',
  ];

  List<File> dartFiles(String root) => Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  group('nothing invalidates a composed view', () {
    // THE failure mode of the re-homing. `ref.invalidate(accountsProvider)`
    // still compiles: it just recomputes the fold instead of issuing a request,
    // so pull-to-refresh silently stops refetching on that screen with no error
    // anywhere. `.future` is compiler-caught; this is not.
    test('every invalidate names a Fetch provider, not a view', () {
      final offenders = <String>[];
      for (final root in const ['lib', 'test']) {
        for (final file in dartFiles(root)) {
          if (file.path.endsWith('optimistic_guard_test.dart')) continue;
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            for (final name in viewProviders) {
              if (lines[i].contains('invalidate($name)')) {
                offenders.add('${file.path}:${i + 1} -> $name');
              }
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'invalidating the composed view compiles and does nothing useful. '
            'Name the <x>FetchProvider instead:\n${offenders.join('\n')}',
      );
    });

    test('route_refresh reloads the server read on every route', () {
      // Pull-to-refresh and 6.3's reconnect recovery both come through here.
      final source = File(
        'lib/core/router/route_refresh.dart',
      ).readAsStringSync();
      for (final name in const [
        'accountsFetchProvider',
        'budgetsFetchProvider',
        'categoriesFetchProvider',
        'creditsFetchProvider',
        'goalsFetchProvider',
        'holdingsFetchProvider',
        'loansFetchProvider',
        'peopleFetchProvider',
        'personGroupsFetchProvider',
        'recurringRulesFetchProvider',
        'splitsFetchProvider',
      ]) {
        expect(
          source.contains(name),
          isTrue,
          reason: '$name is no longer refreshed by route_refresh.dart.',
        );
      }
    });
  });

  group('the mechanism knows nothing about HTTP', () {
    final source = File('lib/core/state/optimistic.dart').readAsStringSync();

    test('it imports neither the client nor the endpoint map', () {
      // The moment this file can reach `ApiClient` it can start building
      // requests, and every write body in the app stops being where
      // `write_schema_test.dart` reads it.
      for (final forbidden in const [
        'api_client.dart',
        'endpoints.dart',
        'package:dio',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason:
              'lib/core/state/optimistic.dart imports "$forbidden". It takes '
              'closures; the repositories keep owning the requests.',
        );
      }
    });

    test('it contains no wire keys', () {
      // A `'amount':` here would be a body being assembled outside the builders
      // the write-schema guard inspects — the exact blindness this phase was
      // told not to introduce.
      final offenders = _wireKeysIn(source);
      expect(
        offenders,
        isEmpty,
        reason:
            'optimistic.dart is building a map with wire-looking keys: '
            '$offenders',
      );
    });

    test('every rollback sentence speaks 6.3\'s vocabulary', () {
      // `rollbackMessage` has exactly four returns; three name a 6.3 constant
      // and the fourth is prefixed. A fifth wording added later fails here.
      final body = source.substring(source.indexOf('String rollbackMessage('));
      final returns = RegExp(
        r'return ([^;]+);',
      ).allMatches(body).map((m) => m.group(1)!.trim()).toList();

      expect(returns, isNotEmpty, reason: 'the guard lost the function body.');
      for (final value in returns) {
        expect(
          value.contains('ApiException.offlineWriteMessage') ||
              value.contains('ApiException.timedOutWriteMessage') ||
              value.contains(r'$kNotSavedPrefix'),
          isTrue,
          reason:
              'a rollback message that is neither 6.3 constant nor '
              'kNotSavedPrefix-prefixed: "$value"',
        );
      }
    });

    test('kNotSavedPrefix is the parent of 6.3\'s offline wording', () {
      // Not a sibling: `offlineWriteMessage` already starts with it, and that
      // is what keeps the two phases speaking one language.
      final exception = File(
        'lib/core/api/api_exception.dart',
      ).readAsStringSync();
      expect(
        exception.contains('"Not saved — you\'re offline. Nothing was sent."'),
        isTrue,
      );
      expect(source.contains("kNotSavedPrefix = 'Not saved — '"), isTrue);
    });
  });

  group('the allow-list stops where prediction stops', () {
    test('no lock, auth or settings surface is optimistic', () {
      // A lock shown as ON (or OFF) before the server agrees is a lie about
      // whether the owner's data is protected. 6.1 and 6.2 own those flows.
      final offenders = <String>[];
      for (final tree in const [
        'lib/features/auth',
        'lib/features/settings',
        'lib/features/wealth_lock',
        'lib/features/lock',
        'lib/features/notifications',
      ]) {
        for (final file in dartFiles(tree)) {
          final source = file.readAsStringSync();
          for (final marker in const [
            'OptimisticCollection',
            'PendingWrite',
            'WritesProvider',
          ]) {
            // A comment naming the mechanism is how a file says why it is NOT
            // using it; only code counts.
            if (_codeOf(source).contains(marker)) {
              offenders.add('${file.path}: $marker');
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'the optimistic mechanism has reached a surface it must not: '
            '$offenders',
      );
    });

    test('every excluded mutation still says why it is synchronous', () {
      // Without the note, a later phase reads "await then invalidate" as an
      // oversight and "fixes" it. These are the mutations whose result the
      // client cannot predict.
      const sites = {
        'lib/features/loans/presentation/loan_pay_sheet.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/loans/presentation/loan_preclose_sheet.dart':
            'Deliberately synchronous (6.4), and permanently so',
        'lib/features/goals/presentation/goal_contribute_sheet.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/stocks/presentation/stock_buy_sheet.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/stocks/presentation/stock_sell_sheet.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/stocks/presentation/stock_sales_sheet.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/stocks/presentation/stock_splits_sheet.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/stocks/presentation/widgets/position_tile.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/stocks/presentation/stocks_screen.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/gold/presentation/gold_screen.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/people/presentation/person_form_sheet.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/recurring/presentation/recurring_screen.dart':
            'Deliberately synchronous (6.4)',
        'lib/features/notifications/data/notifications_repository.dart':
            'Deliberately not optimistic (6.4)',
      };

      for (final entry in sites.entries) {
        final source = File(entry.key).readAsStringSync();
        expect(
          source.contains(entry.value),
          isTrue,
          reason:
              '${entry.key} lost its exclusion note ("${entry.value}"). Either '
              'put it back, or say out loud why this mutation became '
              'predictable.',
        );
      }
    });

    test('the two loan actions predict nothing', () {
      // These are the endpoints the server recomputes with its own
      // amortisation — and preclose is the one that once closed a live
      // two-crore loan.
      for (final path in const [
        'lib/features/loans/presentation/loan_pay_sheet.dart',
        'lib/features/loans/presentation/loan_preclose_sheet.dart',
      ]) {
        final source = File(path).readAsStringSync();
        for (final marker in const [
          'loansWritesProvider',
          'PendingWrite.',
          '.predict(',
        ]) {
          expect(
            source.contains(marker),
            isFalse,
            reason: '$path is predicting a figure only the server can compute.',
          );
        }
      }
    });
  });

  group('an aggregate that lags says so', () {
    test('the credits summary card dims while it is catching up', () {
      // `/credits/summary` is a separate server read, so it trails an
      // optimistic row by one round trip. The row is the owner's own change and
      // is shown plainly; the *total* is what must not sit confidently on a
      // superseded figure.
      final source = File(
        'lib/features/credits/presentation/credits_screen.dart',
      ).readAsStringSync();
      expect(
        source.contains('ref.watch(creditsWritesProvider).isSettling'),
        isTrue,
        reason:
            'the summary card no longer dims while the aggregate catches up.',
      );
    });
  });

  group('the write-schema guard still points at real builders', () {
    // 6.4 moved *when* a body is sent, never *where* it is built. If a
    // `_buildBody` ever moves, write_schema_test.dart must be repointed
    // deliberately — this is the tripwire that says it has not been.
    test('every body builder the guard anchors on is still in place', () {
      const anchors = {
        'lib/features/accounts/presentation/account_form_sheet.dart':
            'Map<String, dynamic> _buildBody',
        'lib/features/transactions/presentation/transaction_form_sheet.dart':
            'final patch = <String, dynamic>',
        'lib/features/recurring/presentation/recurring_form_sheet.dart':
            'final body = <String, dynamic>',
        'lib/features/people/presentation/person_form_sheet.dart':
            'Map<String, dynamic> _buildBody',
        'lib/features/people/presentation/group_form_sheet.dart':
            'final body = <String, dynamic>',
        'lib/features/credits/presentation/credit_form_sheet.dart':
            'Map<String, dynamic> _buildBody',
        'lib/features/splits/presentation/split_form_sheet.dart':
            'Map<String, dynamic> _buildBody',
        'lib/features/budgets/presentation/budget_form_sheet.dart':
            'Map<String, dynamic> _buildBody',
        'lib/features/goals/presentation/goal_form_sheet.dart':
            'Map<String, dynamic> _buildBody',
        'lib/features/loans/presentation/loan_form_sheet.dart':
            'Map<String, dynamic> _buildBody',
        'lib/features/holdings/presentation/holding_form_sheet.dart':
            'Map<String, dynamic> _buildBody',
      };
      for (final entry in anchors.entries) {
        expect(
          File(entry.key).readAsStringSync().contains(entry.value),
          isTrue,
          reason:
              '${entry.key} no longer contains "${entry.value}" — '
              'write_schema_test.dart is reading a body builder that moved.',
        );
      }
    });

    test('predict() never assembles a request body', () {
      // `predict` is a projection of the *model*, not a second body builder.
      // A wire key in one would be a body the schema guard cannot see.
      const models = [
        'lib/features/accounts/domain/account.dart',
        'lib/features/budgets/domain/budget.dart',
        'lib/features/categories/domain/category.dart',
        'lib/features/credits/domain/credit.dart',
        'lib/features/goals/domain/goal.dart',
        'lib/features/holdings/domain/holding.dart',
        'lib/features/loans/domain/loan.dart',
        'lib/features/people/domain/person.dart',
        'lib/features/recurring/domain/recurring_rule.dart',
        'lib/features/splits/domain/split.dart',
      ];
      for (final path in models) {
        final source = File(path).readAsStringSync();
        final start = source.indexOf(' predict(');
        expect(start, isNonNegative, reason: '$path has no predict().');
        final offenders = _wireKeysIn(_bodyFrom(source, start));
        expect(
          offenders,
          isEmpty,
          reason: '$path: predict() is emitting wire keys $offenders.',
        );
      }
    });
  });
}

/// Source with comment lines stripped, so a comment that *names* the mechanism
/// in order to explain why a surface does not use it is not read as usage.
String _codeOf(String source) => [
  for (final line in source.split('\n'))
    if (!line.trimLeft().startsWith('//')) line,
].join('\n');

/// Map-literal keys in [source], ignoring comments and `case` patterns (which
/// look identical to a wire key and are not one).
List<String> _wireKeysIn(String source) {
  final mapKey = RegExp(r"'[a-zA-Z][a-zA-Z0-9]*'\s*:");
  final found = <String>[];
  for (final line in source.split('\n')) {
    final code = line.trimLeft();
    if (code.startsWith('//') || code.startsWith('case ')) continue;
    for (final match in mapKey.allMatches(code)) {
      found.add(match.group(0)!);
    }
  }
  return found;
}

/// One method's source, brace-counted from [start] — the same isolation
/// `write_schema_test.dart` uses, so `predict()` is read and its neighbours are
/// not.
String _bodyFrom(String source, int start) {
  var depth = 0;
  var opened = false;
  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (char == '{' || char == '(') {
      depth++;
      opened = true;
    } else if (char == '}' || char == ')') {
      depth--;
      if (opened && depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start);
}
