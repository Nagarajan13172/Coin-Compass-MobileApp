import 'package:coincompass/core/api/api_exception.dart';
import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/accounts/data/accounts_repository.dart';
import 'package:coincompass/features/accounts/domain/account.dart';
import 'package:coincompass/features/categories/data/categories_repository.dart';
import 'package:coincompass/features/categories/domain/category.dart';
import 'package:coincompass/features/import/data/import_runner.dart';
import 'package:coincompass/features/import/domain/import_parser.dart';
import 'package:coincompass/features/import/domain/import_plan.dart';
import 'package:coincompass/features/transactions/data/transactions_repository.dart';
import 'package:coincompass/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.3c — the only part of the importer that writes, and its brakes.**
///
/// Nothing above this file can damage anything. This one POSTs to a live
/// financial backend, so what it must never do matters more than what it does:
/// never retry a write whose outcome it does not know, never keep hammering a
/// backend that is refusing everything, and never leave the user unable to say
/// what was written.
void main() {
  // Fakes forward everything they do not override, so these stay short as the
  // real repositories grow.
  late List<TransactionDraft> posted;
  late List<Map<String, dynamic>> createdAccounts;
  late List<Map<String, dynamic>> createdCategories;

  setUp(() {
    posted = [];
    createdAccounts = [];
    createdCategories = [];
  });

  Account account(String id, String name) =>
      Account(id: id, name: name, type: AccountType.bank);

  ImportRunner runnerWith({
    Object? Function(int index)? failTransaction,
    bool failAccountCreate = false,
  }) => ImportRunner(
    _FakeTransactions(
      onCreate: (draft) {
        final failure = failTransaction?.call(posted.length);
        posted.add(draft);
        if (failure != null) throw failure;
      },
    ),
    _FakeAccounts(
      onCreate: (body) {
        if (failAccountCreate) {
          throw ApiException(message: 'Account already exists');
        }
        createdAccounts.add(body);
        return Account(
          id: 'new-a${createdAccounts.length}',
          name: body['name'] as String,
          type: AccountType.bank,
        );
      },
    ),
    _FakeCategories(
      onCreate: (body) {
        createdCategories.add(body);
        return Category(
          id: 'new-c${createdCategories.length}',
          name: body['name'] as String,
          type: CategoryType.fromApi(body['type'] as String?),
        );
      },
    ),
  );

  const header =
      'Date,Type,Amount,Currency,Account,To Account,Category,Payee,Note,Tags';

  ImportPlan planFor(String csv, {List<Account> accounts = const []}) =>
      ImportPlan.from(
        parse: ImportParser.parse(csv),
        accounts: accounts,
        categories: const [],
      );

  String rows(int count) => List.generate(
    count,
    (i) => '2026-08-${(i % 28) + 1},expense,${100 + i},INR,HDFC,,,Row $i,,',
  ).join('\n');

  group('the happy path', () {
    test('writes every ready row, in file order', () async {
      final plan = planFor(
        '$header\n${rows(3)}',
        accounts: [account('a1', 'HDFC')],
      );
      final outcome = await runnerWith().run(plan);

      expect(outcome.written, 3);
      expect(outcome.isClean, isTrue);
      expect(posted.map((d) => d.payee), ['Row 0', 'Row 1', 'Row 2']);
      expect(posted.every((d) => d.accountId == 'a1'), isTrue);
    });

    test('creates what the user asked for, before any transaction', () async {
      final plan = planFor('$header\n${rows(2)}');
      final key = plan.refs.single.key;
      final outcome = await runnerWith().run(plan.decide(key, const CreateNew()));

      expect(createdAccounts.single['name'], 'HDFC');
      expect(outcome.createdAccounts, ['HDFC']);
      expect(outcome.written, 2);
      expect(posted.every((d) => d.accountId == 'new-a1'), isTrue,
          reason: 'the rows must use the id that was just created');
    });

    test('creates nothing the user did not ask for', () async {
      final plan = planFor(
        '$header\n${rows(2)}',
        accounts: [account('a1', 'HDFC')],
      );
      await runnerWith().run(plan);
      expect(createdAccounts, isEmpty);
      expect(createdCategories, isEmpty);
    });

    test('reports progress as it goes', () async {
      final seen = <ImportProgress>[];
      final plan = planFor(
        '$header\n${rows(3)}',
        accounts: [account('a1', 'HDFC')],
      );
      await runnerWith().run(plan, onProgress: seen.add);

      expect(seen.where((p) => p.stage == ImportStage.writing), hasLength(3));
      expect(seen.last.stage, ImportStage.refreshing);
      expect(seen.last.written, 3);
    });
  });

  group('failures', () {
    test('one bad row does not stop the rest', () async {
      final plan = planFor(
        '$header\n${rows(4)}',
        accounts: [account('a1', 'HDFC')],
      );
      final outcome = await runnerWith(
        failTransaction: (i) =>
            i == 1 ? ApiException(message: 'Validation failed') : null,
      ).run(plan);

      expect(outcome.written, 3);
      expect(outcome.failures.single.message, 'Validation failed');
      expect(outcome.stopped, isFalse);
    });

    test('a failed row is never retried', () async {
      // A timeout says nothing about what the server did. Retrying is how one
      // flaky row becomes two identical transactions.
      final plan = planFor(
        '$header\n${rows(3)}',
        accounts: [account('a1', 'HDFC')],
      );
      await runnerWith(
        failTransaction: (i) => i == 0 ? ApiException(message: 'boom') : null,
      ).run(plan);

      expect(posted, hasLength(3), reason: 'three attempts for three rows');
    });

    test('a failure names the line and the row, not just an index', () async {
      final plan = planFor(
        '$header\n${rows(2)}',
        accounts: [account('a1', 'HDFC')],
      );
      final outcome = await runnerWith(
        failTransaction: (i) => i == 0 ? ApiException(message: 'nope') : null,
      ).run(plan);

      expect(outcome.failures.single.line, 2, reason: 'spreadsheet gutter line');
      expect(outcome.failures.single.payee, 'Row 0');
    });

    test('five failures in a row stop the import', () async {
      // An expired session makes every remaining row fail. Without this the app
      // spends minutes hammering a backend that is already refusing, and hands
      // back 200 identical errors instead of one explanation.
      final plan = planFor(
        '$header\n${rows(200)}',
        accounts: [account('a1', 'HDFC')],
      );
      final outcome = await runnerWith(
        failTransaction: (_) => ApiException(message: 'Unauthorised'),
      ).run(plan);

      expect(outcome.failures, hasLength(5));
      expect(posted, hasLength(5), reason: 'it must stop attempting, not just counting');
      expect(outcome.stopped, isTrue);
      expect(outcome.stopReason, contains('in a row failed'));
    });

    test('the run of failures resets after a success', () async {
      final plan = planFor(
        '$header\n${rows(12)}',
        accounts: [account('a1', 'HDFC')],
      );
      // Fail 4, succeed, fail 4 — scattered bad rows, not a broken backend.
      final outcome = await runnerWith(
        failTransaction: (i) =>
            (i < 4 || (i > 4 && i < 9)) ? ApiException(message: 'bad row') : null,
      ).run(plan);

      expect(outcome.stopped, isFalse);
      expect(outcome.failures, hasLength(8));
      expect(outcome.written, 4);
    });

    test('a raw error is turned into something the report can print', () async {
      final plan = planFor(
        '$header\n${rows(1)}',
        accounts: [account('a1', 'HDFC')],
      );
      final outcome =
          await runnerWith(failTransaction: (_) => StateError('internal')).run(plan);
      expect(outcome.failures.single.message, isNotEmpty);
      expect(outcome.failures.single.message, isNot(contains('StateError')));
    });
  });

  group('a failed creation aborts before anything is written', () {
    test('no transaction is posted', () async {
      final plan = planFor('$header\n${rows(5)}');
      final outcome = await runnerWith(failAccountCreate: true)
          .run(plan.decide(plan.refs.single.key, const CreateNew()));

      expect(posted, isEmpty, reason: 'the rows had nowhere to go');
      expect(outcome.written, 0);
      expect(outcome.stopped, isTrue);
      expect(outcome.stopReason, contains('Nothing was imported'));
    });
  });

  group('cancelling', () {
    test('stops at a row boundary and keeps what was written', () async {
      final plan = planFor(
        '$header\n${rows(10)}',
        accounts: [account('a1', 'HDFC')],
      );
      final outcome = await runnerWith().run(
        plan,
        isCancelled: () => posted.length >= 3,
      );

      expect(outcome.written, 3);
      expect(outcome.stopped, isTrue);
      expect(outcome.stopReason, contains('3 of 10'));
      expect(outcome.stopReason, contains('kept'),
          reason: 'the user must be told the writes were not rolled back');
    });

    test('cancelling during creation imports nothing', () async {
      final plan = planFor('$header\n${rows(3)}');
      final outcome = await runnerWith()
          .run(plan.decide(plan.refs.single.key, const CreateNew()),
              isCancelled: () => true);

      expect(outcome.written, 0);
      expect(posted, isEmpty);
      expect(createdAccounts, isEmpty);
    });
  });

  group('what never reaches the network', () {
    test('blocked rows are not attempted', () async {
      final plan = planFor(
        '$header\n'
        '2026-08-24,expense,500,INR,HDFC,,,Good,,\n'
        '2026-08-25,nonsense,600,INR,HDFC,,,Bad,,\n'
        '2026-08-26,expense,700,INR,HDFC,,,Good too,,',
        accounts: [account('a1', 'HDFC')],
      );
      final outcome = await runnerWith().run(plan);

      expect(outcome.written, 2);
      expect(posted.map((d) => d.payee), ['Good', 'Good too']);
    });

    test('skipped rows are not attempted', () async {
      final plan = planFor(
        '$header\n'
        '2026-08-24,expense,500,INR,HDFC,,,Keep,,\n'
        '2026-08-25,expense,600,INR,Petty Cash,,,Drop,,',
        accounts: [account('a1', 'HDFC')],
      );
      final decided = plan.decide(
        plan.refs.firstWhere((r) => r.name == 'Petty Cash').key,
        const SkipRef(),
      );
      await runnerWith().run(decided);
      expect(posted.map((d) => d.payee), ['Keep']);
    });
  });
}

class _FakeTransactions implements TransactionsRepository {
  _FakeTransactions({required this.onCreate});
  final void Function(TransactionDraft) onCreate;

  @override
  Future<Transaction> create(TransactionDraft draft) async {
    onCreate(draft);
    return Transaction(
      id: 't1',
      type: draft.type,
      amount: draft.amount,
      date: draft.date,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by the runner');
}

class _FakeAccounts implements AccountsRepository {
  _FakeAccounts({required this.onCreate});
  final Account Function(Map<String, dynamic>) onCreate;

  @override
  Future<Account> create(Map<String, dynamic> body) async => onCreate(body);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by the runner');
}

class _FakeCategories implements CategoriesRepository {
  _FakeCategories({required this.onCreate});
  final Category Function(Map<String, dynamic>) onCreate;

  @override
  Future<Category> create(Map<String, dynamic> body) async => onCreate(body);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by the runner');
}
