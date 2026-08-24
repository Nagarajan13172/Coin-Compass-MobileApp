import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/api/envelope.dart';
import 'package:coincompass/core/api/write_body.dart';
import 'package:coincompass/features/budgets/domain/budget.dart';
import 'package:coincompass/features/budgets/presentation/budgets_providers.dart';
import 'package:coincompass/features/calendar/presentation/calendar_providers.dart';
import 'package:coincompass/features/credits/domain/credit.dart';
import 'package:coincompass/features/people/presentation/widgets/person_picker.dart';
import 'package:coincompass/features/recurring/domain/recurring_rule.dart';
import 'package:coincompass/features/recurring/presentation/recurring_screen.dart';
import 'package:coincompass/features/reports/presentation/period.dart';
import 'package:coincompass/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// The maths and parsing behind the phase-3 screens, tested without a widget in
/// sight: credit totals, monthly normalisation, calendar bucketing and the two
/// shapes the API answers list endpoints in.
void main() {
  group('credits summary', () {
    Credit credit(CreditDirection direction, num amount, {num? outstanding}) =>
        Credit(
          id: '$direction-$amount',
          amount: amount,
          direction: direction,
          outstanding: outstanding,
        );

    test('nets what is owed to you against what you owe', () {
      final summary = CreditsSummary.fromCredits([
        credit(CreditDirection.given, 5000),
        credit(CreditDirection.received, 2000),
        credit(CreditDirection.borrowed, 4000),
        credit(CreditDirection.repaid, 1000),
      ]);

      expect(summary.owedToYou, 3000);
      expect(summary.youOwe, 3000);
      expect(summary.net, 0);
    });

    test('every entry counts — the API has no settled flag to exclude', () {
      // A closed loan is recorded as the matching `received` entry, which nets
      // the original `given` out; nothing is filtered on the way in.
      final summary = CreditsSummary.fromCredits([
        credit(CreditDirection.given, 5000),
        credit(CreditDirection.received, 5000),
      ]);

      expect(summary.given, 5000);
      expect(summary.owedToYou, 0);
      expect(summary.net, 0);
    });

    test('a server-computed outstanding wins over the original amount', () {
      final summary = CreditsSummary.fromCredits([
        credit(CreditDirection.given, 5000, outstanding: 1200),
      ]);

      expect(summary.owedToYou, 1200);
    });
  });

  group('recurring monthly equivalent', () {
    RecurringRule rule(Frequency frequency, num amount, {int interval = 1}) =>
        RecurringRule(
          id: 'r',
          type: TransactionType.expense,
          amount: amount,
          frequency: frequency,
          interval: interval,
        );

    test('a monthly rule is already monthly', () {
      expect(monthlyEquivalent(rule(Frequency.monthly, 12312)), 12312);
    });

    test('weekly, daily and yearly rules are normalised', () {
      expect(
        monthlyEquivalent(rule(Frequency.weekly, 1200)),
        closeTo(5200, 0.5),
      );
      expect(
        monthlyEquivalent(rule(Frequency.daily, 100)),
        closeTo(3043.75, 0.01),
      );
      expect(monthlyEquivalent(rule(Frequency.yearly, 24000)), 2000);
    });

    test('an interval spreads the amount across that many periods', () {
      expect(
        monthlyEquivalent(rule(Frequency.monthly, 12000, interval: 3)),
        4000,
      );
      // A zero interval would divide by zero; the floor of 1 keeps it finite.
      expect(monthlyEquivalent(rule(Frequency.monthly, 500, interval: 0)), 500);
    });
  });

  group('calendar month', () {
    Transaction row(
      String id,
      TransactionType type,
      num amount,
      DateTime date, {
      String? recurringId,
    }) => Transaction(
      id: id,
      type: type,
      amount: amount,
      date: date,
      recurringId: recurringId,
    );

    final day = DateTime(2026, 8, 24, 9);
    final later = DateTime(2026, 8, 24, 18);
    final other = DateTime(2026, 8, 25, 9);

    final month = CalendarMonth.from(DateTime(2026, 8), [
      row('a', TransactionType.expense, 1200, day),
      row('b', TransactionType.income, 5000, later, recurringId: 'r1'),
      row('c', TransactionType.transfer, 9000, day),
      row('d', TransactionType.expense, 300, other),
    ]);

    test('buckets by calendar day and nets income against expense', () {
      final totals = month.totalsFor(day);
      expect(totals.count, 3);
      expect(totals.income, 5000);
      expect(totals.expense, 1200);
      // The transfer moves money between the user's own accounts, so the net
      // ignores it.
      expect(totals.net, 3800);
    });

    test('marks the days a rule posted on', () {
      expect(month.totalsFor(day).hasRecurring, isTrue);
      expect(month.totalsFor(other).hasRecurring, isFalse);
    });

    test('a day with nothing on it reads as empty rather than missing', () {
      final quiet = month.totalsFor(DateTime(2026, 8, 2));
      expect(quiet.isEmpty, isTrue);
      expect(quiet.net, 0);
      expect(month.itemsFor(DateTime(2026, 8, 2)), isEmpty);
    });

    test('a day\'s rows come back newest first', () {
      expect(month.itemsFor(day).first.id, 'b');
    });

    test('the month totals every day it holds', () {
      expect(month.income, 5000);
      expect(month.expense, 1500);
    });
  });

  group('budget spend', () {
    final range = PeriodRange.of(
      PeriodKind.month,
      anchor: DateTime(2026, 8, 10),
    );
    test('a category budget measures its own slice', () {
      final actual = BudgetSpend(
        range: range,
        byCategory: const {'c1': 4000, 'c2': 900},
        total: 7000,
      );
      const budget = Budget(id: 'b1', amount: 5000, categoryId: 'c1');

      expect(actual.forBudget(budget), 4000);
    });

    test('a budget with no category caps every expense in the window', () {
      final actual = BudgetSpend(
        range: range,
        byCategory: const {'c1': 4000},
        total: 7000,
      );
      const budget = Budget(id: 'b2', amount: 9000);

      expect(actual.forBudget(budget), 7000);
    });

    test('a category with no spending yet reads as zero, not null', () {
      final actual = BudgetSpend(range: range, byCategory: const {}, total: 0);
      const budget = Budget(id: 'b3', amount: 1000, categoryId: 'c9');

      expect(actual.forBudget(budget), 0);
    });

    test('days left counts down inside the window and stops at zero', () {
      final current = BudgetSpend(
        range: PeriodRange.of(PeriodKind.month),
        byCategory: const {},
        total: 0,
      );
      expect(current.daysLeft, greaterThan(0));
      expect(current.daysLeft, lessThanOrEqualTo(31));

      // A window that closed years ago has nothing left to count.
      final past = BudgetSpend(
        range: PeriodRange.of(PeriodKind.month, anchor: DateTime(2020, 1, 10)),
        byCategory: const {},
        total: 0,
      );
      expect(past.daysLeft, 0);
    });
  });

  group('envelope', () {
    test('unwraps a bare array and a wrapped one alike', () {
      expect(
        Envelope.rows([
          {'_id': '1'},
        ]),
        hasLength(1),
      );
      expect(
        Envelope.rows(
          {
            'budgets': [
              {'_id': '1'},
              {'_id': '2'},
            ],
          },
          const ['budgets'],
        ),
        hasLength(2),
      );
      expect(
        Envelope.rows({
          'items': [
            {'_id': '1'},
          ],
        }),
        hasLength(1),
      );
      expect(Envelope.rows({'error': 'nope'}), isEmpty);
    });

    test('unwraps a document from either shape', () {
      expect(Envelope.document({'_id': '1'})['_id'], '1');
      expect(
        Envelope.document(
          {
            'goal': {'_id': '2'},
          },
          const ['goal'],
        )['_id'],
        '2',
      );
    });
  });

  group('write body', () {
    test('a create omits what the user left blank', () {
      final body = <String, dynamic>{};
      WriteBody.putText(body, 'note', '   ', null);
      WriteBody.putNullable(body, 'group', null, null);

      // An explicit null would fail a Zod `optional()` field on create.
      expect(body, isEmpty);
    });

    test('an edit clears what the user emptied', () {
      final body = <String, dynamic>{};
      WriteBody.putText(body, 'note', '', 'the old note');
      WriteBody.putNullable(body, 'group', null, 'g1');

      expect(body['note'], '');
      expect(body['group'], isNull);
      expect(body.containsKey('group'), isTrue);
    });

    test('a value is sent trimmed', () {
      final body = <String, dynamic>{};
      WriteBody.putText(body, 'note', '  paid in cash  ', null);
      WriteBody.putNullable(body, 'group', 'g2', null);

      expect(body['note'], 'paid in cash');
      expect(body['group'], 'g2');
    });
  });

  test('a person reference sends an id when it has one, else the name', () {
    expect(const PersonRef(id: 'p1', name: 'Karthik').wireValue, 'p1');
    expect(const PersonRef(name: 'Karthik').wireValue, 'Karthik');
  });
}
