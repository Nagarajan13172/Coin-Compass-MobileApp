import 'package:coincompass/core/api/api_exception.dart';
import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/state/optimistic.dart';
import 'package:coincompass/features/accounts/domain/account.dart';
import 'package:coincompass/features/budgets/domain/budget.dart';
import 'package:coincompass/features/categories/domain/category.dart';
import 'package:coincompass/features/credits/domain/credit.dart';
import 'package:coincompass/features/goals/domain/goal.dart';
import 'package:coincompass/features/holdings/domain/holding.dart';
import 'package:coincompass/features/loans/domain/loan.dart';
import 'package:coincompass/features/people/domain/person.dart';
import 'package:coincompass/features/recurring/domain/recurring_rule.dart';
import 'package:coincompass/features/splits/domain/split.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 6.4 — the mechanism, tested as the pure function it is.
///
/// Everything here runs without a widget, a container or a socket: a
/// [PendingWrites] is `(server list, ordered entries) -> list`, and rollback is
/// "remove one token and re-run the fold". If those two claims hold, the
/// exactness argument in the design holds with them.
void main() {
  // A minimal row type, so the fold is tested on its own terms rather than
  // through one feature's model.
  PendingWrites<_Row> empty({RowOrder<_Row>? order}) =>
      PendingWrites<_Row>(idOf: (row) => row.id, order: order);

  const a = _Row('a', 'Alpha');
  const b = _Row('b', 'Bravo');
  const c = _Row('c', 'Charlie');
  const base = [a, b, c];

  group('the fold', () {
    test('an upsert replaces in place and leaves the server order alone', () {
      final writes = empty().add(
        PendingWrite.upsert(const _Row('b', 'Bravo 2')),
      );
      expect(
        writes.fold(base).map((row) => row.name),
        ['Alpha', 'Bravo 2', 'Charlie'],
        reason:
            'the list arrives in an order the server chose; an edit must move '
            'nothing but the row it edits.',
      );
    });

    test('an upsert of a row not on screen appends rather than vanishing', () {
      final writes = empty().add(PendingWrite.upsert(const _Row('d', 'Delta')));
      expect(writes.fold(base).map((row) => row.id), ['a', 'b', 'c', 'd']);
    });

    test('a remove drops exactly one row', () {
      final writes = empty().add(PendingWrite.remove<_Row>('b'));
      expect(writes.fold(base).map((row) => row.id), ['a', 'c']);
    });

    test('a remove for an id that is not on screen is a no-op', () {
      // A delete that lands after a refresh has already dropped the row must
      // not corrupt the list.
      final writes = empty().add(PendingWrite.remove<_Row>('zzz'));
      expect(identical(writes.fold(base), base), isTrue);
    });

    test('an `order` comparator re-places only the edited row', () {
      final writes = empty(
        order: (x, y) => x.name.compareTo(y.name),
      ).add(PendingWrite.upsert(const _Row('c', 'Aardvark')));
      expect(
        writes.fold(base).map((row) => row.id),
        ['c', 'a', 'b'],
        reason:
            'the row moves to where the comparator puts it; a and b keep '
            'their relative order.',
      );
    });
  });

  group('rollback is removing one token', () {
    test('removing a token leaves every other entry in place', () {
      final first = PendingWrite.upsert(const _Row('a', 'Alpha 2'));
      final second = PendingWrite.upsert(const _Row('c', 'Charlie 2'));
      final writes = empty().add(first).add(second);

      expect(writes.fold(base).map((row) => row.name), [
        'Alpha 2',
        'Bravo',
        'Charlie 2',
      ]);

      final rolledBack = writes.removeToken(first.token);
      expect(rolledBack.fold(base).map((row) => row.name), [
        'Alpha',
        'Bravo',
        'Charlie 2',
      ]);
    });

    test('rolling everything back returns the server list untouched', () {
      final first = PendingWrite.upsert(const _Row('a', 'Alpha 2'));
      final second = PendingWrite.remove<_Row>('b');
      final writes = empty().add(first).add(second);

      final clean = writes.removeToken(first.token).removeToken(second.token);
      expect(clean.isEmpty, isTrue);
      expect(identical(clean.fold(base), base), isTrue);
    });

    test('two edits on one row: the later one wins on screen', () {
      final earlier = PendingWrite.upsert(const _Row('b', 'first edit'));
      final later = PendingWrite.upsert(const _Row('b', 'second edit'));
      final writes = empty().add(earlier).add(later);

      expect(writes.fold(base)[1].name, 'second edit');
    });

    test('two edits on one row, the EARLIER fails: the later value stands', () {
      // A captured-snapshot restore would put the stale value back here,
      // undoing an edit the owner never asked to undo.
      final earlier = PendingWrite.upsert(const _Row('b', 'first edit'));
      final later = PendingWrite.upsert(const _Row('b', 'second edit'));
      final writes = empty().add(earlier).add(later);

      final after = writes.removeToken(earlier.token);
      expect(after.fold(base)[1].name, 'second edit');
    });

    test('two edits on one row, the LATER fails: the earlier value stands', () {
      final earlier = PendingWrite.upsert(const _Row('b', 'first edit'));
      final later = PendingWrite.upsert(const _Row('b', 'second edit'));
      final writes = empty().add(earlier).add(later);

      final after = writes.removeToken(later.token);
      expect(after.fold(base)[1].name, 'first edit');
    });

    test('a delete and an edit of the same row compose by order', () {
      final edit = PendingWrite.upsert(const _Row('b', 'edited'));
      final drop = PendingWrite.remove<_Row>('b');
      expect(empty().add(edit).add(drop).fold(base).length, 2);
      // Rolling the delete back brings the edit's value back, not the server's.
      expect(
        empty().add(edit).add(drop).removeToken(drop.token).fold(base)[1].name,
        'edited',
      );
    });

    test('a fresh server list mid-flight keeps the pending entry applied', () {
      // Pull-to-refresh replaces the base; entries are keyed by token, not by
      // base generation, so a pending edit survives it.
      final writes = empty().add(PendingWrite.upsert(const _Row('b', 'mine')));
      const refreshed = [a, _Row('b', 'theirs'), c];
      expect(writes.fold(refreshed)[1].name, 'mine');
    });

    test('confirming swaps the row without moving the entry in the order', () {
      final first = PendingWrite.upsert(const _Row('a', 'guess'));
      final second = PendingWrite.upsert(const _Row('c', 'later'));
      final writes = empty().add(first).add(second);

      final confirmed = writes.replaceToken(
        first.token,
        UpsertWrite<_Row>.withToken(first.token, const _Row('a', 'server')),
      );
      expect(confirmed.entries.first.token, first.token);
      expect(confirmed.entries.last.token, second.token);
      expect(confirmed.fold(base).first.name, 'server');
    });
  });

  group('applyTo preserves the async state exactly', () {
    const data = AsyncData<List<_Row>>(base);

    test('with no entries it returns the SAME object', () {
      // This is what guarantees a screen with no write in flight behaves
      // exactly as it did before 6.4 — including state_audit_test's four-state
      // sweep and 6.3's stale banner.
      final none = empty();
      const loading = AsyncLoading<List<_Row>>();
      final failed = AsyncError<List<_Row>>('boom', StackTrace.empty);

      expect(identical(none.applyTo(data), data), isTrue);
      expect(identical(none.applyTo(loading), loading), isTrue);
      expect(identical(none.applyTo(failed), failed), isTrue);
    });

    test('an error with no value stays an error, not a skeleton', () {
      final writes = empty().add(PendingWrite.upsert(const _Row('b', 'x')));
      final failed = AsyncError<List<_Row>>('boom', StackTrace.empty);
      final out = writes.applyTo(failed);
      expect(out.hasError, isTrue);
      expect(out.hasValue, isFalse);
    });

    test('a refreshing AsyncData stays refreshing, with the folded value', () {
      final writes = empty().add(PendingWrite.upsert(const _Row('b', 'x')));
      final refreshing = const AsyncLoading<List<_Row>>().copyWithPrevious(
        data,
      );
      expect(refreshing.isRefreshing, isTrue);

      final out = writes.applyTo(refreshing);
      expect(out.isRefreshing, isTrue);
      expect(out.valueOrNull![1].name, 'x');
    });

    test('a reloading AsyncLoading keeps its previous value, folded', () {
      final writes = empty().add(PendingWrite.upsert(const _Row('b', 'x')));
      final reloading = const AsyncLoading<List<_Row>>().copyWithPrevious(
        data,
        isRefresh: false,
      );
      expect(reloading.isReloading, isTrue);

      final out = writes.applyTo(reloading);
      expect(out.isReloading, isTrue);
      expect(out.valueOrNull![1].name, 'x');
    });

    test('an error that carries a previous value keeps both', () {
      final writes = empty().add(PendingWrite.remove<_Row>('b'));
      final failed = AsyncError<List<_Row>>(
        'boom',
        StackTrace.empty,
      ).copyWithPrevious(data);

      final out = writes.applyTo(failed);
      expect(out.hasError, isTrue);
      expect(out.valueOrNull!.length, 2);
    });
  });

  group('the failure vocabulary', () {
    test('offline says nothing was sent', () {
      expect(
        rollbackMessage(
          ApiException(message: 'x', code: 'NO_CONNECTION'),
          noun: 'HDFC',
        ),
        ApiException.offlineWriteMessage,
      );
    });

    test('a timeout claims nothing about whether it landed', () {
      expect(
        rollbackMessage(ApiException(message: 'x', code: 'TIMEOUT')),
        ApiException.timedOutWriteMessage,
      );
    });

    test('a field error names the field', () {
      final message = rollbackMessage(
        ApiException(
          message: 'Validation failed',
          statusCode: 400,
          fieldErrors: const {
            'amount': ['Required'],
          },
        ),
      );
      expect(message, '${kNotSavedPrefix}amount: Required');
    });

    test('anything else is prefixed once, never twice', () {
      final message = rollbackMessage(
        ApiException(message: '${kNotSavedPrefix}already prefixed'),
        noun: 'Rent',
      );
      expect(message, '${kNotSavedPrefix}Rent: already prefixed');
      expect(kNotSavedPrefix.allMatches(message).length, 1);
    });

    test('every branch speaks the 6.3 vocabulary', () {
      for (final error in [
        ApiException(message: 'x', code: 'NO_CONNECTION'),
        ApiException(message: 'x', code: 'TIMEOUT'),
        ApiException(message: 'nope', statusCode: 500),
        ApiException(
          message: 'v',
          fieldErrors: const {
            'name': ['Required'],
          },
        ),
      ]) {
        final message = rollbackMessage(error, noun: 'Row');
        expect(
          message == ApiException.offlineWriteMessage ||
              message == ApiException.timedOutWriteMessage ||
              message.startsWith(kNotSavedPrefix),
          isTrue,
          reason: 'unexpected wording: $message',
        );
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // predict(): the doctrine rule, one test per model.
  //
  // Each one feeds `predict` the row's *own* values and asserts the result is
  // the row back again, except for the fields the design says must be nulled
  // because the server recomputes them. A field added to a model later and
  // forgotten in `predict` fails here rather than silently vanishing from the
  // optimistic row for the length of a round trip.
  // ───────────────────────────────────────────────────────────────────────────
  group(
    'predict copies what the client sent and nulls what the server owns',
    () {
      test('Person nulls the server slug and keeps everything else', () {
        const person = Person(
          id: 'p1',
          name: 'Karthik',
          key: 'karthik',
          relation: PersonRelation.friend,
        );
        final out = person.predict(
          name: person.name,
          relation: person.relation,
        )!;
        expect(out.id, person.id);
        expect(out.name, person.name);
        expect(out.relation, person.relation);
        expect(out.key, isNull, reason: 'a rename moves the slug');
      });

      test('PersonGroup derives its own member count', () {
        const group = PersonGroup(
          id: 'g1',
          name: 'Trip',
          memberIds: ['p1', 'p2'],
          memberCount: 2,
        );
        final out = group.predict(name: 'Goa', memberIds: const ['p1'])!;
        expect(out.name, 'Goa');
        expect(out.memberIds, ['p1']);
        expect(out.memberCount, 1);
      });

      test('Account keeps its balance for an edit that cannot move it', () {
        const account = Account(
          id: 'a1',
          name: 'HDFC',
          type: AccountType.bank,
          openingBalance: 1000,
          balance: 25000,
          color: '#2563EB',
          icon: 'landmark',
        );
        final out = account.predict(
          name: 'HDFC Savings',
          type: account.type,
          openingBalance: account.openingBalance,
          currency: account.currency,
          excludeFromTotal: account.excludeFromTotal,
          color: account.color,
          icon: account.icon,
        )!;
        expect(out.name, 'HDFC Savings');
        expect(
          out.balance,
          25000,
          reason:
              'a rename does not move the running balance, so blanking it '
              'would be a worse lie than keeping it.',
        );
      });

      test('Account refuses to predict an opening-balance change', () {
        const account = Account(
          id: 'a1',
          name: 'HDFC',
          type: AccountType.bank,
          openingBalance: 1000,
          balance: 25000,
        );
        expect(
          account.predict(
            name: account.name,
            type: account.type,
            openingBalance: 2000,
            currency: account.currency,
            excludeFromTotal: false,
          ),
          isNull,
          reason:
              'the escape hatch: the server balance shifts by an amount only '
              'the whole ledger could re-derive, so this submission takes the '
              'spinner.',
        );
      });

      test('Budget nulls every server-computed figure the limit can move', () {
        final budget = Budget(
          id: 'b1',
          amount: 10000,
          categoryId: 'c1',
          period: BudgetPeriod.monthly,
          spent: 4000,
          remaining: 6000,
          percent: 40,
          over: false,
          periodRange: BudgetPeriodRange(
            start: DateTime.utc(2026, 8),
            end: DateTime.utc(2026, 9),
          ),
        );
        final out = budget.predict(
          amount: 12000,
          period: budget.period,
          categoryId: budget.categoryId,
        )!;
        expect(out.amount, 12000);
        expect(out.spent, isNull);
        expect(out.remaining, isNull);
        expect(out.percent, isNull);
        expect(out.over, isNull);
        expect(out.periodRange, isNull);
        // …and the model's own fallback then produces a correct bar from the
        // spend the app already holds.
        expect(out.percentUsed(4000), closeTo(33.33, 0.01));
        expect(out.isOver(4000), isFalse);
      });

      test('Category keeps order, isDefault and usageCount', () {
        const category = Category(
          id: 'c1',
          name: 'Food',
          type: CategoryType.expense,
          icon: 'utensils',
          color: '#EF4444',
          group: 'food',
          order: 3,
          isDefault: true,
          usageCount: 42,
        );
        final out = category.predict(
          name: 'Groceries',
          type: category.type,
          icon: category.icon,
          color: category.color,
          group: category.group,
        )!;
        expect(out.name, 'Groceries');
        expect(out.order, 3);
        expect(out.isDefault, isTrue);
        expect(out.usageCount, 42);
      });

      test('Credit nulls outstanding and falls back to the typed amount', () {
        const credit = Credit(
          id: 'cr1',
          amount: 5000,
          direction: CreditDirection.given,
          personName: 'Karthik',
          outstanding: 5000,
        );
        final out = credit.predict(
          amount: 7000,
          direction: credit.direction,
          date: DateTime.utc(2026, 8, 1),
          personName: 'Karthik',
        )!;
        expect(out.outstanding, isNull);
        expect(out.outstandingOrAmount, 7000);
        expect(out.displayName, 'Karthik');
      });

      test('Goal nulls all four derived figures and re-derives three', () {
        const goal = Goal(
          id: 'g1',
          name: 'Bike',
          targetAmount: 100000,
          savedAmount: 25000,
          remaining: 75000,
          percentFromServer: 25,
          completeFromServer: false,
          monthsLeft: 15,
        );
        final out = goal.predict(
          name: goal.name,
          targetAmount: 200000,
          savedAmount: goal.savedAmount,
          monthlyContribution: goal.monthlyContribution,
          color: goal.color,
          icon: goal.icon,
        )!;
        expect(out.remaining, isNull);
        expect(out.percentFromServer, isNull);
        expect(out.completeFromServer, isNull);
        expect(
          out.monthsLeft,
          isNull,
          reason:
              'no client-side counterpart — the '
              'tile omits the phrase rather than showing a stale figure.',
        );
        expect(out.remainingOrComputed, 175000);
        expect(out.percent, closeTo(12.5, 0.001));
        expect(out.isComplete, isFalse);
      });

      test('Holding is a straight copy — it has nothing derived', () {
        final holding = Holding(
          id: 'h1',
          name: 'SBI FD',
          holdingClass: HoldingClass.saving,
          subtype: HoldingSubtype.fixedDeposit,
          value: 200000,
          maturityDate: DateTime.utc(2027),
          startDate: DateTime.utc(2026),
          note: 'auto renew',
        );
        final out = holding.predict(
          name: holding.name,
          holdingClass: holding.holdingClass,
          subtype: holding.subtype,
          value: 250000,
          currency: holding.currency,
          maturityDate: holding.maturityDate,
          startDate: holding.startDate,
          note: holding.note,
        )!;
        expect(out.value, 250000);
        expect(out.subtype, HoldingSubtype.fixedDeposit);
        expect(out.maturityDate, holding.maturityDate);
        expect(out.note, 'auto renew');
      });

      test('Loan carries interestPaid and chargesPaid across a form edit', () {
        const loan = Loan(
          id: 'l1',
          name: 'Home',
          outstanding: 20000000,
          principal: 25000000,
          roi: 8.5,
          emi: 200000,
          interestPaid: 450000,
          chargesPaid: 12000,
        );
        final out = loan.predict(
          name: 'Home loan',
          outstanding: loan.outstanding,
          type: loan.type,
          status: loan.status,
          principal: loan.principal,
          roi: loan.roi,
          emi: loan.emi,
          foreclosureChargePct: loan.foreclosureChargePct,
          note: loan.note,
        )!;
        expect(out.name, 'Home loan');
        expect(
          out.interestPaid,
          450000,
          reason: 'a form edit cannot move what part-payments accumulated.',
        );
        expect(out.chargesPaid, 12000);
        expect(out.outstanding, 20000000);
      });

      test('RecurringRule nulls the schedule the server projects', () {
        final rule = RecurringRule(
          id: 'r1',
          type: TransactionType.expense,
          amount: 1500,
          payee: 'Netflix',
          frequency: Frequency.monthly,
          interval: 1,
          nextRun: DateTime.utc(2026, 9),
          lastRun: DateTime.utc(2026, 8),
          upcoming: [DateTime.utc(2026, 9), DateTime.utc(2026, 10)],
        );
        final out = rule.predictActive(false)!;
        expect(out.active, isFalse);
        expect(out.nextRun, isNull);
        expect(out.upcoming, isEmpty);
        expect(out.lastRun, rule.lastRun, reason: 'history, not projection');
        expect(out.amount, 1500);
        expect(out.payee, 'Netflix');
      });

      test('Split is a straight copy', () {
        final split = Split(
          id: 's1',
          description: 'Dinner',
          totalAmount: 3000,
          yourShare: 1000,
          participantIds: const ['p1', 'p2'],
          date: DateTime.utc(2026, 8, 4),
        );
        final out = split.predict(
          description: split.description,
          totalAmount: 4000,
          yourShare: 1500,
          participantIds: split.participantIds,
          date: split.date!,
        )!;
        expect(out.totalAmount, 4000);
        expect(out.othersShare, 2500);
        expect(out.participantIds, ['p1', 'p2']);
      });
    },
  );
}

class _Row {
  const _Row(this.id, this.name);
  final String id;
  final String name;
}
