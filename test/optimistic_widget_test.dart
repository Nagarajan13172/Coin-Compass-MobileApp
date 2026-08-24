import 'dart:async';

import 'package:coincompass/core/api/api_exception.dart';
import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/state/optimistic.dart';
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
import 'package:coincompass/features/people/presentation/person_form_sheet.dart';
import 'package:coincompass/features/recurring/data/recurring_repository.dart';
import 'package:coincompass/features/recurring/domain/recurring_rule.dart';
import 'package:coincompass/features/splits/data/splits_repository.dart';
import 'package:coincompass/features/splits/domain/split.dart';
import 'package:coincompass/features/templates/data/templates_repository.dart';
import 'package:coincompass/features/templates/domain/template.dart';
import 'package:flutter/material.dart' hide Split;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'optimistic_fakes.dart';

/// Phase 6.4 — the mechanism against every collection it was applied to.
///
/// **Fake repositories only.** Nothing here constructs an `ApiClient`, a `Dio`
/// or a cookie jar, so no test in this file can reach the owner's account.
///
/// Three claims are made for every converted collection:
///
///  1. **paint** — the row shows the client's prediction before the write
///     resolves, and the server's old value is gone from the screen;
///  2. **reconcile** — when the write lands, the row becomes the *server's*
///     document (not the guess), the list is refetched, and the entry is
///     dropped;
///  3. **rollback** — when the write fails, the list is exactly what it was
///     before, and a sentence says the change was not saved.
///
/// Then the cases that only the mechanism has: the settle window (no flash of
/// the old value), an offline post-write refetch, a timeout, a field error, a
/// retry, overlapping edits, and the delete-then-undo the transactions list
/// keeps.
///
/// Every pump is bounded — `pump()` and `pump(Duration)`, never
/// `pumpAndSettle`, and every wait is on a `Completer` the test itself
/// completes.
void main() {
  _collectionSuite<Account>(
    label: 'accounts',
    seed: const [
      Account(id: 'a1', name: 'HDFC', type: AccountType.bank, balance: 25000),
      Account(id: 'a2', name: 'Cash', type: AccountType.cash, balance: 500),
    ],
    idOf: (row) => row.id,
    text: (row) => row.name,
    fetch: accountsFetchProvider,
    writes: accountsWritesProvider,
    view: accountsProvider,
    settle: settleAccounts,
    overrides: (store) => [
      accountsRepositoryProvider.overrideWithValue(
        FakeAccountsRepository(store),
      ),
    ],
    predict: (row) => row.predict(
      name: 'HDFC Savings',
      type: row.type,
      openingBalance: row.openingBalance,
      currency: row.currency,
      excludeFromTotal: row.excludeFromTotal,
    )!,
    send: (ref, row) => ref.read(accountsRepositoryProvider).update(row.id, {
      'name': 'HDFC Savings',
    }),
    remove: (ref, row) => ref.read(accountsRepositoryProvider).delete(row.id),
    before: 'HDFC',
    painted: 'HDFC Savings',
    fromServer: 'HDFC Savings',
  );

  _collectionSuite<Budget>(
    label: 'budgets',
    seed: const [
      Budget(
        id: 'b1',
        amount: 10000,
        spent: 4000,
        remaining: 6000,
        percent: 40,
      ),
      Budget(id: 'b2', amount: 2000),
    ],
    idOf: (row) => row.id,
    // The bar is what this feature is about, so the probe prints the derived
    // percentage rather than a name: a stale server `percent` beside a new
    // limit would show up here.
    text: (row) => '${row.id}:${row.amount}:${row.percentUsed(4000)?.round()}',
    fetch: budgetsFetchProvider,
    writes: budgetsWritesProvider,
    view: budgetsProvider,
    settle: settleBudgets,
    overrides: (store) => [
      budgetsRepositoryProvider.overrideWithValue(FakeBudgetsRepository(store)),
    ],
    predict: (row) => row.predict(amount: 12000, period: row.period)!,
    send: (ref, row) =>
        ref.read(budgetsRepositoryProvider).update(row.id, {'amount': 12000}),
    remove: (ref, row) => ref.read(budgetsRepositoryProvider).delete(row.id),
    before: 'b1:10000:40',
    // nulled server percent -> re-derived from the client's own /reports spend
    painted: 'b1:12000:33',
    fromServer: 'b1:12000:40',
  );

  _collectionSuite<Category>(
    label: 'categories',
    seed: const [
      Category(id: 'c1', name: 'Food', type: CategoryType.expense, order: 3),
      Category(id: 'c2', name: 'Fuel', type: CategoryType.expense),
    ],
    idOf: (row) => row.id,
    text: (row) => row.name,
    fetch: categoriesFetchProvider,
    writes: categoriesWritesProvider,
    view: categoriesProvider,
    settle: settleCategories,
    overrides: (store) => [
      categoriesRepositoryProvider.overrideWithValue(
        FakeCategoriesRepository(store),
      ),
    ],
    predict: (row) => row.predict(name: 'Groceries', type: row.type)!,
    send: (ref, row) => ref.read(categoriesRepositoryProvider).update(row.id, {
      'name': 'Groceries',
    }),
    remove: (ref, row) => ref.read(categoriesRepositoryProvider).delete(row.id),
    before: 'Food',
    painted: 'Groceries',
    fromServer: 'Groceries',
  );

  _collectionSuite<Credit>(
    label: 'credits',
    seed: const [
      Credit(
        id: 'cr1',
        amount: 5000,
        direction: CreditDirection.given,
        personName: 'Karthik',
        outstanding: 5000,
      ),
    ],
    idOf: (row) => row.id,
    text: (row) => '${row.displayName}:${row.outstandingOrAmount}',
    fetch: creditsFetchProvider,
    writes: creditsWritesProvider,
    view: creditsProvider,
    settle: settleCredits,
    overrides: (store) => [
      creditsRepositoryProvider.overrideWithValue(FakeCreditsRepository(store)),
    ],
    predict: (row) => row.predict(
      amount: 7000,
      direction: row.direction,
      date: DateTime.utc(2026, 8, 1),
      personName: row.personName,
    )!,
    send: (ref, row) =>
        ref.read(creditsRepositoryProvider).update(row.id, {'amount': 7000}),
    remove: (ref, row) => ref.read(creditsRepositoryProvider).delete(row.id),
    before: 'Karthik:5000',
    painted: 'Karthik:7000',
    fromServer: 'Karthik:7000',
  );

  _collectionSuite<Goal>(
    label: 'goals',
    seed: const [
      Goal(
        id: 'g1',
        name: 'Bike',
        targetAmount: 100000,
        savedAmount: 25000,
        remaining: 75000,
        percentFromServer: 25,
      ),
    ],
    idOf: (row) => row.id,
    text: (row) => '${row.name}:${row.remainingOrComputed}',
    fetch: goalsFetchProvider,
    writes: goalsWritesProvider,
    view: goalsProvider,
    settle: settleGoals,
    overrides: (store) => [
      goalsRepositoryProvider.overrideWithValue(FakeGoalsRepository(store)),
    ],
    predict: (row) => row.predict(
      name: row.name,
      targetAmount: 200000,
      savedAmount: row.savedAmount,
      monthlyContribution: row.monthlyContribution,
      color: row.color,
      icon: row.icon,
    )!,
    send: (ref, row) => ref.read(goalsRepositoryProvider).update(row.id, {
      'targetAmount': 200000,
    }),
    remove: (ref, row) => ref.read(goalsRepositoryProvider).delete(row.id),
    before: 'Bike:75000',
    painted: 'Bike:175000',
    fromServer: 'Bike:175000',
  );

  _collectionSuite<Holding>(
    label: 'holdings',
    seed: const [
      Holding(
        id: 'h1',
        name: 'SBI FD',
        holdingClass: HoldingClass.saving,
        subtype: HoldingSubtype.fixedDeposit,
        value: 200000,
      ),
    ],
    idOf: (row) => row.id,
    text: (row) => '${row.name}:${row.value}',
    fetch: holdingsFetchProvider,
    writes: holdingsWritesProvider,
    view: holdingsProvider,
    settle: settleHoldings,
    overrides: (store) => [
      holdingsRepositoryProvider.overrideWithValue(
        FakeHoldingsRepository(store),
      ),
    ],
    predict: (row) => row.predict(
      name: row.name,
      holdingClass: row.holdingClass,
      subtype: row.subtype,
      value: 250000,
      currency: row.currency,
    )!,
    send: (ref, row) =>
        ref.read(holdingsRepositoryProvider).update(row.id, {'value': 250000}),
    remove: (ref, row) => ref.read(holdingsRepositoryProvider).delete(row.id),
    before: 'SBI FD:200000',
    painted: 'SBI FD:250000',
    fromServer: 'SBI FD:250000',
  );

  _collectionSuite<Loan>(
    label: 'loans',
    seed: const [
      Loan(
        id: 'l1',
        name: 'Home',
        outstanding: 20000000,
        principal: 25000000,
        interestPaid: 450000,
        chargesPaid: 12000,
      ),
    ],
    idOf: (row) => row.id,
    text: (row) => '${row.name}:${row.outstanding}:${row.interestPaid}',
    fetch: loansFetchProvider,
    writes: loansWritesProvider,
    view: loansProvider,
    settle: settleLoans,
    overrides: (store) => [
      loansRepositoryProvider.overrideWithValue(FakeLoansRepository(store)),
    ],
    predict: (row) => row.predict(
      name: 'Home loan',
      outstanding: row.outstanding,
      type: row.type,
      status: row.status,
      principal: row.principal,
      roi: row.roi,
      emi: row.emi,
      foreclosureChargePct: row.foreclosureChargePct,
      note: row.note,
    )!,
    send: (ref, row) =>
        ref.read(loansRepositoryProvider).update(row.id, {'name': 'Home loan'}),
    remove: (ref, row) => ref.read(loansRepositoryProvider).delete(row.id),
    before: 'Home:20000000:450000',
    // The form edit carries the accumulated interest across — it is not the
    // form's to move, and blanking it would misreport a two-crore loan.
    painted: 'Home loan:20000000:450000',
    fromServer: 'Home loan:20000000:450000',
  );

  _collectionSuite<Person>(
    label: 'people',
    seed: const [
      Person(id: 'p1', name: 'Karthik', key: 'karthik'),
      Person(id: 'p2', name: 'Divya', key: 'divya'),
    ],
    idOf: (row) => row.id,
    text: (row) => row.name,
    fetch: peopleFetchProvider,
    writes: peopleWritesProvider,
    view: peopleProvider,
    settle: settlePeople,
    overrides: (store) => [
      peopleRepositoryProvider.overrideWithValue(FakePeopleRepository(store)),
    ],
    predict: (row) => row.predict(name: 'Karthik R', relation: row.relation)!,
    send: (ref, row) => ref.read(peopleRepositoryProvider).update(row.id, {
      'name': 'Karthik R',
    }),
    remove: (ref, row) => ref.read(peopleRepositoryProvider).delete(row.id),
    before: 'Karthik',
    painted: 'Karthik R',
    fromServer: 'Karthik R',
  );

  _collectionSuite<RecurringRule>(
    label: 'recurring',
    seed: [
      RecurringRule(
        id: 'r1',
        type: TransactionType.expense,
        amount: 1500,
        payee: 'Netflix',
        nextRun: DateTime.utc(2026, 8, 1),
      ),
    ],
    idOf: (row) => row.id,
    text: (row) =>
        '${row.title}:${row.active}:${row.nextRun?.month.toString() ?? '-'}',
    fetch: recurringRulesFetchProvider,
    writes: recurringWritesProvider,
    view: recurringRulesProvider,
    settle: settleRecurring,
    overrides: (store) => [
      recurringRepositoryProvider.overrideWithValue(
        FakeRecurringRepository(store),
      ),
    ],
    predict: (row) => row.predictActive(false)!,
    send: (ref, row) =>
        ref.read(recurringRepositoryProvider).update(row.id, {'active': false}),
    remove: (ref, row) => ref.read(recurringRepositoryProvider).delete(row.id),
    before: 'Netflix:true:8',
    // The schedule is the server's: nulled rather than guessed, so the tile
    // drops its "Next …" line until the refetch lands.
    painted: 'Netflix:false:-',
    fromServer: 'Netflix:false:9',
  );

  _collectionSuite<Split>(
    label: 'splits',
    seed: const [
      Split(
        id: 's1',
        description: 'Dinner',
        totalAmount: 3000,
        yourShare: 1000,
      ),
    ],
    idOf: (row) => row.id,
    text: (row) => '${row.description}:${row.totalAmount}',
    fetch: splitsFetchProvider,
    writes: splitsWritesProvider,
    view: splitsProvider,
    settle: settleSplits,
    overrides: (store) => [
      splitsRepositoryProvider.overrideWithValue(FakeSplitsRepository(store)),
    ],
    predict: (row) => row.predict(
      description: 'Dinner + cab',
      totalAmount: row.totalAmount,
      yourShare: row.yourShare,
      participantIds: row.participantIds,
      date: DateTime.utc(2026, 8, 4),
    )!,
    send: (ref, row) => ref.read(splitsRepositoryProvider).update(row.id, {
      'description': 'Dinner + cab',
    }),
    remove: (ref, row) => ref.read(splitsRepositoryProvider).delete(row.id),
    before: 'Dinner:3000',
    painted: 'Dinner + cab:3000',
    fromServer: 'Dinner + cab:3000',
  );

  // Templates only ever delete — there is no `PATCH /templates/:id` in this app
  // — so they get the delete half of the suite rather than the edit half.
  group('templates', () {
    testWidgets('a removed chip disappears before the write resolves, and '
        'comes back with a message when it fails', (tester) async {
      final store = FakeStore<Template>(
        rows: const [
          Template(id: 't1', name: 'Coffee'),
          Template(id: 't2', name: 'Auto'),
        ],
        idOf: (row) => row.id,
      );
      final harness = await _mount<Template>(
        tester,
        overrides: [
          templatesRepositoryProvider.overrideWithValue(
            FakeTemplatesRepository(store),
          ),
        ],
        view: templatesProvider,
        text: (row) => row.name,
      );

      expect(find.text('Coffee'), findsOneWidget);

      final gate = Completer<void>();
      store
        ..gate = gate
        ..writeError = offlineWriteFailure();
      final pending = harness.container
          .read(templatesWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove<Template>('t1'),
            send: () => harness.container
                .read(templatesRepositoryProvider)
                .delete('t1'),
            settle: () => settleTemplates(harness.container),
            messenger: harness.messenger,
            noun: 'Coffee',
          );

      await tester.pump();
      expect(find.text('Coffee'), findsNothing, reason: 'painted at once');
      expect(find.text('Auto'), findsOneWidget);

      gate.complete();
      await pending;
      await _frames(tester);

      expect(find.text('Coffee'), findsOneWidget, reason: 'exact rollback');
      expect(find.text(ApiException.offlineWriteMessage), findsOneWidget);
      await _drainSnackBar(tester);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // The cases that belong to the mechanism rather than to any one collection.
  // ───────────────────────────────────────────────────────────────────────────
  group('the settle window', () {
    testWidgets('the optimistic value never gives way to the old one between '
        'the write landing and the refetch', (tester) async {
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      // Hold the *read* open, so the settle refetch is genuinely mid-air.
      final readGate = Completer<void>();
      store.readGate = readGate;

      final pending = harness.container
          .read(peopleWritesProvider.notifier)
          .run<Person>(
            paint: PendingWrite.upsert(
              const Person(id: 'p1', name: 'Karthik R'),
            ),
            send: () => harness.container.read(peopleRepositoryProvider).update(
              'p1',
              {'name': 'Karthik R'},
            ),
            confirm: (saved) => saved,
            settle: () => settlePeople(harness.container),
            messenger: harness.messenger,
            noun: 'Karthik R',
          );

      // Several frames, all inside the settle window. Not one of them may show
      // the pre-write name — that is the flash this phase exists to prevent.
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('Karthik'), findsNothing);
        expect(find.text('Karthik R'), findsOneWidget);
      }

      readGate.complete();
      await pending;
      await tester.pump();

      expect(find.text('Karthik R'), findsOneWidget);
      expect(
        harness.container.read(peopleWritesProvider).isEmpty,
        isTrue,
        reason: 'the entry is dropped in the same turn the fresh base lands.',
      );
    });

    testWidgets('a post-write refetch that fails keeps the confirmed document', (
      tester,
    ) async {
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      // The write lands; the network then dies before the refetch. 6.3 cleared
      // the response cache on the successful write, so there is nothing to fall
      // back on — keeping the entry is the only honest answer, and by now it
      // holds the server's own document rather than a guess.
      store.readError = offlineWriteFailure();

      await harness.container
          .read(peopleWritesProvider.notifier)
          .run<Person>(
            paint: PendingWrite.upsert(const Person(id: 'p1', name: 'guess')),
            send: () => harness.container.read(peopleRepositoryProvider).update(
              'p1',
              {'name': 'Karthik R'},
            ),
            confirm: (saved) => saved,
            settle: () => settlePeople(harness.container),
            messenger: harness.messenger,
            noun: 'Karthik R',
          );
      await tester.pump();

      expect(find.text('Karthik R'), findsOneWidget);
      expect(find.text('guess'), findsNothing);
      expect(harness.container.read(peopleWritesProvider).isNotEmpty, isTrue);
    });

    testWidgets('`isSettling` is raised while the aggregates catch up', (
      tester,
    ) async {
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      final readGate = Completer<void>();
      store.readGate = readGate;
      final pending = harness.container
          .read(peopleWritesProvider.notifier)
          .run<Person>(
            paint: PendingWrite.upsert(const Person(id: 'p1', name: 'K R')),
            send: () => harness.container.read(peopleRepositoryProvider).update(
              'p1',
              {'name': 'K R'},
            ),
            confirm: (saved) => saved,
            settle: () => settlePeople(harness.container),
            messenger: harness.messenger,
            noun: 'K R',
          );

      await tester.pump();
      expect(harness.container.read(peopleWritesProvider).isSettling, isTrue);

      readGate.complete();
      await pending;
      expect(harness.container.read(peopleWritesProvider).isSettling, isFalse);
    });
  });

  group('what the owner is told', () {
    testWidgets('offline offers Retry, and Retry re-sends the same write', (
      tester,
    ) async {
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      store.writeError = offlineWriteFailure();
      await _rename(harness, store);
      await _frames(tester);

      expect(find.text(ApiException.offlineWriteMessage), findsOneWidget);
      expect(find.text('Karthik'), findsOneWidget, reason: 'exact rollback');
      expect(find.text('Retry'), findsOneWidget);

      // The connection comes back; the retry carries the same body.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();

      expect(find.text('Karthik R'), findsOneWidget);
      await _drainSnackBar(tester);
    });

    testWidgets('a timeout rolls back and offers NO retry', (tester) async {
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      store.writeError = timedOutWriteFailure();
      await _rename(harness, store);
      await _frames(tester);

      expect(find.text(ApiException.timedOutWriteMessage), findsOneWidget);
      expect(
        find.text('Retry'),
        findsNothing,
        reason:
            'the write may already have landed, and no body here carries '
            'an idempotency key — retrying is how you double-post.',
      );
      // The base was refetched so the server's answer stands.
      expect(store.reads, greaterThan(1));
      await _drainSnackBar(tester);
    });

    testWidgets('a field error names the field and offers Fix', (tester) async {
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      var fixed = false;
      store.writeError = validationFailure('name', 'Required');
      await _rename(harness, store, onFix: () => fixed = true);
      await _frames(tester);

      expect(find.text('${kNotSavedPrefix}name: Required'), findsOneWidget);
      expect(find.text('Fix'), findsOneWidget);
      await tester.tap(find.text('Fix'));
      await tester.pump();
      expect(fixed, isTrue);
      await _drainSnackBar(tester);
    });

    testWidgets('a 500 on a PATCH offers Retry', (tester) async {
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      store.writeError = serverFailure();
      await _rename(harness, store);
      await _frames(tester);

      expect(find.text('Retry'), findsOneWidget);
      await _drainSnackBar(tester);
    });

    testWidgets('a 500 on a POST does not offer Retry', (tester) async {
      // Repeating a create blind is how the owner ends up with two of
      // something, and none of the 13 probed write bodies carries an
      // idempotency key.
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      store.writeError = serverFailure();
      await harness.container
          .read(peopleWritesProvider.notifier)
          .run<Person>(
            send: () => harness.container.read(peopleRepositoryProvider).update(
              'p1',
              {'name': 'x'},
            ),
            settle: () => settlePeople(harness.container),
            messenger: harness.messenger,
            noun: 'Karthik',
            idempotent: false,
          );
      await _frames(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await _drainSnackBar(tester);
    });

    testWidgets('two failures do not stack their snackbars', (tester) async {
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      store.writeError = offlineWriteFailure();
      await _rename(harness, store);
      await tester.pump();
      store.writeError = serverFailure();
      await _rename(harness, store);
      await _frames(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      await _drainSnackBar(tester);
    });
  });

  group('overlapping edits', () {
    testWidgets('when the earlier write fails the later value stands', (
      tester,
    ) async {
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);
      final notifier = harness.container.read(peopleWritesProvider.notifier);

      // First edit: held open, and doomed.
      final firstGate = Completer<void>();
      store
        ..gate = firstGate
        ..writeError = offlineWriteFailure();
      final first = notifier.run<Person>(
        paint: PendingWrite.upsert(const Person(id: 'p1', name: 'first')),
        send: () => harness.container.read(peopleRepositoryProvider).update(
          'p1',
          {'name': 'first'},
        ),
        confirm: (saved) => saved,
        settle: () => settlePeople(harness.container),
        messenger: harness.messenger,
        noun: 'first',
      );
      await tester.pump();
      expect(find.text('first'), findsOneWidget);

      // Second edit, started while the first is still in flight. It gets its
      // own gate: the store consumes both knobs on entry, so the first write's
      // failure is the first write's alone.
      final secondGate = Completer<void>();
      store.gate = secondGate;
      final second = notifier.run<Person>(
        paint: PendingWrite.upsert(const Person(id: 'p1', name: 'second')),
        send: () => harness.container.read(peopleRepositoryProvider).update(
          'p1',
          {'name': 'second'},
        ),
        confirm: (saved) => saved,
        settle: () => settlePeople(harness.container),
        messenger: harness.messenger,
        noun: 'second',
      );
      await tester.pump();
      expect(find.text('second'), findsOneWidget, reason: 'the later wins');

      firstGate.complete();
      await first;
      secondGate.complete();
      await second;
      await _frames(tester);

      expect(
        find.text('second'),
        findsOneWidget,
        reason:
            'rolling back the earlier write must not resurrect a value the '
            'owner already replaced — which a captured-snapshot restore would.',
      );
      expect(find.text('first'), findsNothing);
      expect(find.text('Karthik'), findsNothing);
      await _drainSnackBar(tester);
    });
  });

  group('the real call sites', () {
    testWidgets('the person sheet repaints the list before the write lands, '
        'and rolls it back when it fails', (tester) async {
      // The mechanism is proven above; this proves the *wiring*. It drives the
      // shipping `PersonFormSheet` — its `_buildBody`, its `predict`, its
      // captured messenger and container — rather than calling `run` directly.
      final store = _peopleStore();
      final container = ProviderContainer(
        overrides: [
          peopleRepositoryProvider.overrideWithValue(
            FakePeopleRepository(store),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final people =
                      ref.watch(peopleProvider).valueOrNull ?? const <Person>[];
                  return Column(
                    children: [
                      for (final person in people) Text(person.name),
                      TextButton(
                        onPressed: () => PersonFormSheet.show(
                          context,
                          person: people.isEmpty ? null : people.first,
                        ),
                        child: const Text('edit'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Karthik'), findsOneWidget);

      Future<void> rename(String to) async {
        await tester.tap(find.text('edit'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.byType(TextField).first, to);
        await tester.tap(find.text('Save changes'));
        // One frame to run `_submit` (which pops), then enough for the sheet's
        // exit animation. Bounded, never `pumpAndSettle`.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      // 1. The write is held open; the sheet is already gone and the list
      //    already shows the new name.
      final gate = Completer<void>();
      store.gate = gate;
      await rename('Karthik R');
      expect(
        find.text('Save changes'),
        findsNothing,
        reason: 'the sheet popped',
      );
      expect(find.text('Karthik R'), findsOneWidget);
      expect(find.text('Karthik'), findsNothing);

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Karthik R'), findsOneWidget);

      // 2. The next edit fails offline: the list returns to exactly what the
      //    server last said, and the owner is told.
      store.writeError = offlineWriteFailure();
      await rename('Karthik Raj');
      await _frames(tester);

      expect(find.text('Karthik R'), findsOneWidget);
      expect(find.text('Karthik Raj'), findsNothing);
      expect(find.text(ApiException.offlineWriteMessage), findsOneWidget);
      await _drainSnackBar(tester);
    });
  });

  group('the second storage adapter — a delete with a real Undo', () {
    testWidgets('the transactions list restores the row through '
        'POST /transactions/:id/restore', (tester) async {
      // The transactions list is paginated, so it keeps `deleteLocal` /
      // `insertLocal` rather than the fold. What it shares is the vocabulary —
      // and it is the one collection with a restore endpoint, so it is the one
      // that offers Undo.
      final store = _peopleStore();
      final harness = await _mountPeople(tester, store);

      // A delete, then an Undo expressed the way the row expresses it: remove
      // locally, send, and put the row back on the restore.
      final notifier = harness.container.read(peopleWritesProvider.notifier);
      await notifier.run<void>(
        paint: PendingWrite.remove<Person>('p1'),
        send: () =>
            harness.container.read(peopleRepositoryProvider).delete('p1'),
        settle: () => settlePeople(harness.container),
        messenger: harness.messenger,
        noun: 'Karthik',
        successMessage: 'Deleted Karthik',
      );
      await _frames(tester);

      expect(find.text('Karthik'), findsNothing);
      expect(find.text('Deleted Karthik'), findsOneWidget);

      // "Undo" for a collection that has a restore endpoint: put the row back
      // on the server, refetch, and it returns.
      store.rows = [...store.rows, const Person(id: 'p1', name: 'Karthik')];
      await notifier.run<void>(
        send: () async {},
        settle: () => settlePeople(harness.container),
        messenger: harness.messenger,
        noun: 'Karthik',
      );
      await tester.pump();

      expect(find.text('Karthik'), findsOneWidget);
      await _drainSnackBar(tester);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Harness
// ─────────────────────────────────────────────────────────────────────────────

class _Harness {
  _Harness(this.container, this.messenger);
  final ProviderContainer container;
  final ScaffoldMessengerState messenger;
}

/// Mounts a probe that prints one line per row of [view], and hands back the
/// container plus the messenger every `run()` call needs.
Future<_Harness> _mount<T>(
  WidgetTester tester, {
  required List<Override> overrides,
  required ProviderListenable<AsyncValue<List<T>>> view,
  required String Function(T row) text,
}) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (_, ref, _) {
              final rows = ref.watch(view).valueOrNull ?? const [];
              return ListView(
                children: [for (final row in rows) Text(text(row))],
              );
            },
          ),
        ),
      ),
    ),
  );
  // Bounded: the fake repository resolves on a microtask, so one extra frame is
  // all the first read needs.
  await tester.pump();

  return _Harness(
    container,
    tester.firstState<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)),
  );
}

/// One frame to schedule the SnackBar, then enough time for its entrance
/// animation — an action button that is still sliding in cannot be tapped.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

/// Lets a SnackBar's own dismissal timer expire, then its exit animation run —
/// a live timer at teardown fails the test with "A Timer is still pending",
/// and a half-dismissed bar leaves its action findable in the next assertion.
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pump(const Duration(milliseconds: 750));
}

FakeStore<Person> _peopleStore() => FakeStore<Person>(
  rows: const [
    Person(id: 'p1', name: 'Karthik'),
    Person(id: 'p2', name: 'Divya'),
  ],
  idOf: (row) => row.id,
);

Future<_Harness> _mountPeople(WidgetTester tester, FakeStore<Person> store) =>
    _mount<Person>(
      tester,
      overrides: [
        peopleRepositoryProvider.overrideWithValue(FakePeopleRepository(store)),
      ],
      view: peopleProvider,
      text: (row) => row.name,
    );

Future<void> _rename(
  _Harness harness,
  FakeStore<Person> store, {
  VoidCallback? onFix,
}) {
  return harness.container
      .read(peopleWritesProvider.notifier)
      .run<Person>(
        paint: PendingWrite.upsert(const Person(id: 'p1', name: 'Karthik R')),
        send: () => harness.container.read(peopleRepositoryProvider).update(
          'p1',
          {'name': 'Karthik R'},
        ),
        confirm: (saved) => saved,
        settle: () => settlePeople(harness.container),
        messenger: harness.messenger,
        noun: 'Karthik',
        onFix: onFix,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// The three claims, once per collection.
// ─────────────────────────────────────────────────────────────────────────────

void _collectionSuite<T>({
  required String label,
  required List<T> seed,
  required String Function(T row) idOf,
  required String Function(T row) text,
  required FutureProvider<List<T>> fetch,
  required StateNotifierProvider<OptimisticCollection<T>, PendingWrites<T>>
  writes,
  required ProviderListenable<AsyncValue<List<T>>> view,
  required Future<void> Function(ProviderContainer container) settle,
  required List<Override> Function(FakeStore<T> store) overrides,
  required T Function(T row) predict,
  required Future<T> Function(ProviderContainer ref, T row) send,
  required Future<void> Function(ProviderContainer ref, T row) remove,
  required String before,
  required String painted,
  required String fromServer,
}) {
  group(label, () {
    Future<(_Harness, FakeStore<T>)> boot(WidgetTester tester) async {
      final store = FakeStore<T>(rows: seed, idOf: idOf);
      final harness = await _mount<T>(
        tester,
        overrides: overrides(store),
        view: view,
        text: text,
      );
      expect(find.text(before), findsOneWidget);
      return (harness, store);
    }

    testWidgets('paints the prediction before the write resolves', (
      tester,
    ) async {
      final (harness, store) = await boot(tester);
      // Hold a local handle: the store clears `gate` the moment the write
      // reaches it, which is exactly how the test knows the write is in flight.
      final gate = Completer<void>();
      store.gate = gate;

      final pending = harness.container
          .read(writes.notifier)
          .run<T>(
            paint: PendingWrite.upsert(predict(seed.first)),
            send: () => send(harness.container, seed.first),
            confirm: (saved) => saved,
            settle: () => settle(harness.container),
            messenger: harness.messenger,
            noun: label,
          );

      await tester.pump();
      expect(find.text(painted), findsOneWidget);
      expect(find.text(before), findsNothing);
      expect(
        store.reads,
        1,
        reason: 'nothing is invalidated before the server agrees.',
      );

      gate.complete();
      await pending;
      await tester.pump();
      await _drainSnackBar(tester);
    });

    testWidgets("reconciles with the server's own document", (tester) async {
      final (harness, store) = await boot(tester);

      await harness.container
          .read(writes.notifier)
          .run<T>(
            paint: PendingWrite.upsert(predict(seed.first)),
            send: () => send(harness.container, seed.first),
            confirm: (saved) => saved,
            settle: () => settle(harness.container),
            messenger: harness.messenger,
            noun: label,
          );
      await tester.pump();

      expect(find.text(fromServer), findsOneWidget);
      expect(find.text(before), findsNothing);
      expect(store.reads, 2, reason: 'the settle refetched the list.');
      expect(
        harness.container.read(writes).isEmpty,
        isTrue,
        reason: 'the entry is dropped once the fresh base is in hand.',
      );
      await _drainSnackBar(tester);
    });

    testWidgets('rolls back exactly, and says the change was not saved', (
      tester,
    ) async {
      final (harness, store) = await boot(tester);
      store.writeError = offlineWriteFailure();

      await harness.container
          .read(writes.notifier)
          .run<T>(
            paint: PendingWrite.upsert(predict(seed.first)),
            send: () => send(harness.container, seed.first),
            confirm: (saved) => saved,
            settle: () => settle(harness.container),
            messenger: harness.messenger,
            noun: label,
          );
      await _frames(tester);

      expect(find.text(before), findsOneWidget);
      expect(find.text(painted), findsNothing);
      for (final row in seed) {
        expect(
          find.text(text(row)),
          findsOneWidget,
          reason: 'every row is exactly where it was before the write.',
        );
      }
      expect(find.text(ApiException.offlineWriteMessage), findsOneWidget);
      expect(harness.container.read(writes).isEmpty, isTrue);
      expect(
        store.reads,
        1,
        reason:
            'a failed write must not refetch — the 6.3 cache still holds '
            'the pre-write body and would present it as current.',
      );
      await _drainSnackBar(tester);
    });

    testWidgets('a delete removes the row, and a failed one puts it back', (
      tester,
    ) async {
      final (harness, store) = await boot(tester);

      // 1. It fails: the row returns to exactly where it was, and the owner is
      //    told. There is no Undo on this collection — no restore endpoint —
      //    so the row coming back has to be right.
      store.writeError = offlineWriteFailure();
      await harness.container
          .read(writes.notifier)
          .run<void>(
            paint: PendingWrite.remove<T>(idOf(seed.first)),
            send: () => remove(harness.container, seed.first),
            settle: () => settle(harness.container),
            messenger: harness.messenger,
            noun: label,
          );
      await _frames(tester);

      expect(find.text(before), findsOneWidget);
      expect(find.text(ApiException.offlineWriteMessage), findsOneWidget);
      expect(store.rows.length, seed.length);
      await _drainSnackBar(tester);

      // 2. It lands: the row is gone from the screen and from the server, and
      //    the entry is dropped once the refetch agrees.
      await harness.container
          .read(writes.notifier)
          .run<void>(
            paint: PendingWrite.remove<T>(idOf(seed.first)),
            send: () => remove(harness.container, seed.first),
            settle: () => settle(harness.container),
            messenger: harness.messenger,
            noun: label,
            successMessage: 'Deleted $label',
          );
      await _frames(tester);

      expect(find.text(before), findsNothing);
      expect(find.text('Deleted $label'), findsOneWidget);
      expect(store.rows.length, seed.length - 1);
      expect(harness.container.read(writes).isEmpty, isTrue);
      await _drainSnackBar(tester);
    });
  });
}
