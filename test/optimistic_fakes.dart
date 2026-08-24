import 'dart:async';

import 'package:coincompass/core/api/api_exception.dart';
import 'package:coincompass/features/accounts/data/accounts_repository.dart';
import 'package:coincompass/features/accounts/domain/account.dart';
import 'package:coincompass/features/budgets/data/budgets_repository.dart';
import 'package:coincompass/features/budgets/domain/budget.dart';
import 'package:coincompass/features/categories/data/categories_repository.dart';
import 'package:coincompass/features/categories/domain/category.dart';
import 'package:coincompass/features/credits/data/credits_repository.dart';
import 'package:coincompass/features/credits/domain/credit.dart';
import 'package:coincompass/features/goals/data/goals_repository.dart';
import 'package:coincompass/features/goals/domain/goal.dart';
import 'package:coincompass/features/holdings/data/holdings_repository.dart';
import 'package:coincompass/features/holdings/domain/holding.dart';
import 'package:coincompass/features/loans/data/loans_repository.dart';
import 'package:coincompass/features/loans/domain/loan.dart';
import 'package:coincompass/features/people/data/people_repository.dart';
import 'package:coincompass/features/people/domain/person.dart';
import 'package:coincompass/features/recurring/data/recurring_repository.dart';
import 'package:coincompass/features/recurring/domain/recurring_rule.dart';
import 'package:coincompass/features/splits/data/splits_repository.dart';
import 'package:coincompass/features/splits/domain/split.dart';
import 'package:coincompass/features/templates/data/templates_repository.dart';
import 'package:coincompass/features/templates/domain/template.dart';
import 'package:coincompass/features/transactions/domain/transaction.dart';

/// Fake repositories for the 6.4 optimistic-write suite.
///
/// **No network, ever.** Every one of these `implements` the real repository
/// rather than extending it, so it never holds an `ApiClient` and could not
/// reach the owner's account even by mistake. Dart does not require an
/// implementer in another library to provide another library's private members,
/// which is what makes `implements` (and therefore the total absence of a Dio
/// instance) possible here.
///
/// The shared behaviour lives in [FakeStore]: a mutable row list that stands in
/// for the server's collection, plus the three knobs the tests need — hold a
/// write open, fail it with a chosen [ApiException], and count the reads.
class FakeStore<T> {
  FakeStore({required this.rows, required this.idOf});

  /// The server's rows. A successful write mutates these, so the settle refetch
  /// sees what a real refetch would.
  List<T> rows;
  final String Function(T row) idOf;

  /// How many times `list()` has been called — the settle refetch is one.
  int reads = 0;

  /// Set to make `list()` throw, which is how a post-write refetch failure (or
  /// a cold read failure) is simulated.
  Object? readError;

  /// Set to make the next write throw.
  Object? writeError;

  /// When set, the next write blocks on this until the test completes it. Use
  /// it to assert what the screen shows *while* a write is in flight.
  Completer<void>? gate;

  /// Same, for the read — which is how the *settle* window is held open so a
  /// test can prove the optimistic value is still on screen while the refetch
  /// is in flight.
  Completer<void>? readGate;

  Future<List<T>> list() async {
    reads++;
    final open = readGate;
    if (open != null) {
      readGate = null;
      await open.future;
    }
    final error = readError;
    if (error != null) throw error;
    return List<T>.of(rows);
  }

  /// Both knobs are consumed the moment a write *enters*, not when it leaves —
  /// so a second write started while the first is parked on its gate is not
  /// also caught by the first write's error. That is what makes the
  /// overlapping-edit test express the case it means.
  Future<void> _await() async {
    final open = gate;
    final error = writeError;
    gate = null;
    writeError = null;
    if (open != null) await open.future;
    if (error != null) throw error;
  }

  /// A write that replaces one row and answers with the server's version.
  Future<T> put(String id, T row) async {
    await _await();
    rows = [
      for (final existing in rows)
        if (idOf(existing) == id) row else existing,
    ];
    return row;
  }

  Future<void> remove(String id) async {
    await _await();
    rows = [
      for (final existing in rows)
        if (idOf(existing) != id) existing,
    ];
  }

  Future<T> add(T row) async {
    await _await();
    rows = [...rows, row];
    return row;
  }
}

/// The failure every rollback test starts from: a write that never left the
/// phone. `ApiClient._sendWrite` is what re-words this in production; the fakes
/// hand back the already-worded exception so the assertion is about what the
/// screen says, not about Dio.
ApiException offlineWriteFailure() => ApiException(
  message: ApiException.offlineWriteMessage,
  code: 'NO_CONNECTION',
);

ApiException timedOutWriteFailure() =>
    ApiException(message: ApiException.timedOutWriteMessage, code: 'TIMEOUT');

ApiException validationFailure(String field, String message) => ApiException(
  message: 'Validation failed',
  statusCode: 400,
  code: 'VALIDATION_FAILED',
  fieldErrors: {
    field: [message],
  },
);

ApiException serverFailure() => ApiException(
  message: 'The server had a problem. Please try again.',
  statusCode: 500,
);

// ─── one fake per converted collection ──────────────────────────────────────

class FakeAccountsRepository implements AccountsRepository {
  FakeAccountsRepository(this.store);
  final FakeStore<Account> store;

  @override
  Future<List<Account>> list() => store.list();
  @override
  Future<Account> create(Map<String, dynamic> body) =>
      store.add(store.rows.first);
  @override
  Future<Account> update(String id, Map<String, dynamic> body) =>
      store.put(id, _apply(id, body));
  @override
  Future<void> delete(String id) => store.remove(id);

  Account _apply(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((a) => a.id == id);
    return Account(
      id: current.id,
      name: (body['name'] as String?) ?? current.name,
      type: current.type,
      openingBalance: current.openingBalance,
      balance: current.balance,
      currency: current.currency,
      color: (body['color'] as String?) ?? current.color,
      icon: current.icon,
      excludeFromTotal: body.containsKey('includeInTotal')
          ? !(body['includeInTotal'] as bool)
          : current.excludeFromTotal,
    );
  }
}

class FakeBudgetsRepository implements BudgetsRepository {
  FakeBudgetsRepository(this.store);
  final FakeStore<Budget> store;

  @override
  Future<List<Budget>> list() => store.list();
  @override
  Future<Budget> create(Map<String, dynamic> body) =>
      store.add(store.rows.first);
  @override
  Future<Budget> update(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((b) => b.id == id);
    // The server answers with its own recomputed figures, which is exactly what
    // the optimistic row must be replaced by.
    return store.put(
      id,
      Budget(
        id: id,
        amount: (body['amount'] as num?) ?? current.amount,
        period: current.period,
        spent: 4000,
        remaining: ((body['amount'] as num?) ?? current.amount) - 4000,
        percent: 40,
        over: false,
      ),
    );
  }

  @override
  Future<void> delete(String id) => store.remove(id);
}

class FakeCategoriesRepository implements CategoriesRepository {
  FakeCategoriesRepository(this.store);
  final FakeStore<Category> store;

  @override
  Future<List<Category>> list() => store.list();
  @override
  Future<Category> create(Map<String, dynamic> body) =>
      store.add(store.rows.first);
  @override
  Future<Category> update(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((c) => c.id == id);
    return store.put(
      id,
      Category(
        id: id,
        name: (body['name'] as String?) ?? current.name,
        type: current.type,
        icon: current.icon,
        color: (body['color'] as String?) ?? current.color,
        group: current.group,
      ),
    );
  }

  @override
  Future<void> delete(String id) => store.remove(id);
}

class FakeCreditsRepository implements CreditsRepository {
  FakeCreditsRepository(this.store);
  final FakeStore<Credit> store;

  @override
  Future<List<Credit>> list() => store.list();
  @override
  Future<CreditsSummary?> summary() async => null;
  @override
  Future<Credit> create(Map<String, dynamic> body) =>
      store.add(store.rows.first);
  @override
  Future<Credit> update(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((c) => c.id == id);
    final amount = (body['amount'] as num?) ?? current.amount;
    return store.put(
      id,
      Credit(
        id: id,
        amount: amount,
        direction: current.direction,
        personName: current.personName,
        personId: current.personId,
        outstanding: amount,
      ),
    );
  }

  @override
  Future<void> delete(String id) => store.remove(id);
}

class FakeGoalsRepository implements GoalsRepository {
  FakeGoalsRepository(this.store);
  final FakeStore<Goal> store;

  @override
  Future<List<Goal>> list() => store.list();
  @override
  Future<Goal> create(Map<String, dynamic> body) => store.add(store.rows.first);
  @override
  Future<Goal> update(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((g) => g.id == id);
    final target = (body['targetAmount'] as num?) ?? current.targetAmount;
    return store.put(
      id,
      Goal(
        id: id,
        name: (body['name'] as String?) ?? current.name,
        targetAmount: target,
        savedAmount: current.savedAmount,
        remaining: target - current.savedAmount,
        percentFromServer: 25,
        completeFromServer: false,
        monthsLeft: 9,
      ),
    );
  }

  @override
  Future<void> delete(String id) => store.remove(id);
  @override
  Future<Goal> contribute(String id, num amount) =>
      throw UnimplementedError('contribute is deliberately not optimistic');
}

class FakeHoldingsRepository implements HoldingsRepository {
  FakeHoldingsRepository(this.store);
  final FakeStore<Holding> store;

  @override
  Future<List<Holding>> list() => store.list();
  @override
  Future<Holding> create(Map<String, dynamic> body) =>
      store.add(store.rows.first);
  @override
  Future<Holding> update(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((h) => h.id == id);
    return store.put(
      id,
      Holding(
        id: id,
        name: (body['name'] as String?) ?? current.name,
        holdingClass: current.holdingClass,
        subtype: current.subtype,
        value: (body['value'] as num?) ?? current.value,
      ),
    );
  }

  @override
  Future<void> delete(String id) => store.remove(id);
}

class FakeLoansRepository implements LoansRepository {
  FakeLoansRepository(this.store);
  final FakeStore<Loan> store;

  @override
  Future<List<Loan>> list() => store.list();
  @override
  Future<Loan> create(Map<String, dynamic> body) => store.add(store.rows.first);
  @override
  Future<Loan> update(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((l) => l.id == id);
    return store.put(
      id,
      Loan(
        id: id,
        name: (body['name'] as String?) ?? current.name,
        outstanding: (body['outstanding'] as num?) ?? current.outstanding,
        principal: current.principal,
        interestPaid: current.interestPaid,
        chargesPaid: current.chargesPaid,
      ),
    );
  }

  @override
  Future<void> delete(String id) => store.remove(id);
  @override
  Future<Loan> pay({
    required String id,
    required num amount,
    num chargePct = 0,
  }) => throw UnimplementedError('pay is deliberately not optimistic');
  @override
  Future<Loan> preclose({required String id, num chargePct = 0}) =>
      throw UnimplementedError('preclose is deliberately not optimistic');
}

class FakePeopleRepository implements PeopleRepository {
  FakePeopleRepository(this.store, {FakeStore<PersonGroup>? groups})
    : groupStore =
          groups ?? FakeStore<PersonGroup>(rows: const [], idOf: (g) => g.id);

  final FakeStore<Person> store;
  final FakeStore<PersonGroup> groupStore;

  @override
  Future<List<Person>> list() => store.list();
  @override
  Future<Person> create(Map<String, dynamic> body) =>
      store.add(store.rows.first);
  @override
  Future<Person> update(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((p) => p.id == id);
    return store.put(
      id,
      Person(
        id: id,
        name: (body['name'] as String?) ?? current.name,
        // The server recomputes the slug from the name.
        key: ((body['name'] as String?) ?? current.name).toLowerCase(),
        relation: current.relation,
      ),
    );
  }

  @override
  Future<void> delete(String id) => store.remove(id);
  @override
  Future<void> merge(String id, String intoId) =>
      throw UnimplementedError('merge is deliberately not optimistic');
  @override
  Future<List<PersonGroup>> groups() => groupStore.list();
  @override
  Future<PersonGroup> createGroup(Map<String, dynamic> body) =>
      groupStore.add(groupStore.rows.first);
  @override
  Future<PersonGroup> updateGroup(String id, Map<String, dynamic> body) {
    final current = groupStore.rows.firstWhere((g) => g.id == id);
    return groupStore.put(
      id,
      PersonGroup(
        id: id,
        name: (body['name'] as String?) ?? current.name,
        memberIds: current.memberIds,
        memberCount: current.memberIds.length,
      ),
    );
  }

  @override
  Future<void> deleteGroup(String id) => groupStore.remove(id);
}

class FakeRecurringRepository implements RecurringRepository {
  FakeRecurringRepository(this.store);
  final FakeStore<RecurringRule> store;

  @override
  Future<List<RecurringRule>> list() => store.list();
  @override
  Future<RecurringRule> create(Map<String, dynamic> body) =>
      store.add(store.rows.first);
  @override
  Future<RecurringRule> update(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((r) => r.id == id);
    return store.put(
      id,
      RecurringRule(
        id: id,
        type: current.type,
        amount: (body['amount'] as num?) ?? current.amount,
        payee: current.payee,
        active: (body['active'] as bool?) ?? current.active,
        // The server owns the schedule and always sends one back.
        nextRun: DateTime.utc(2026, 9, 1),
        upcoming: [DateTime.utc(2026, 9, 1), DateTime.utc(2026, 10, 1)],
      ),
    );
  }

  @override
  Future<void> delete(String id) => store.remove(id);
  @override
  Future<RecurringRunResult> run(String id) =>
      throw UnimplementedError('run is deliberately not optimistic');
  @override
  Future<RecurringRunResult> skip(String id) =>
      throw UnimplementedError('skip is deliberately not optimistic');
  @override
  Future<RecurringRunResult> postOne(String id) =>
      throw UnimplementedError('post-one is deliberately not optimistic');
  @override
  Future<List<Transaction>> history(String id) async => const [];
}

class FakeSplitsRepository implements SplitsRepository {
  FakeSplitsRepository(this.store);
  final FakeStore<Split> store;

  @override
  Future<List<Split>> list() => store.list();
  @override
  Future<Split> create(Map<String, dynamic> body) =>
      store.add(store.rows.first);
  @override
  Future<Split> update(String id, Map<String, dynamic> body) {
    final current = store.rows.firstWhere((s) => s.id == id);
    return store.put(
      id,
      Split(
        id: id,
        description: (body['description'] as String?) ?? current.description,
        totalAmount: (body['totalAmount'] as num?) ?? current.totalAmount,
        yourShare: (body['yourShare'] as num?) ?? current.yourShare,
      ),
    );
  }

  @override
  Future<void> delete(String id) => store.remove(id);
}

class FakeTemplatesRepository implements TemplatesRepository {
  FakeTemplatesRepository(this.store);
  final FakeStore<Template> store;

  @override
  Future<List<Template>> list() => store.list();
  @override
  Future<Template> create(Map<String, dynamic> body) =>
      store.add(store.rows.first);
  @override
  Future<void> delete(String id) => store.remove(id);
}
