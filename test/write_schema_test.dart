import 'dart:io';

import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/budgets/domain/budget.dart';
import 'package:coincompass/features/credits/domain/credit.dart';
import 'package:coincompass/features/goals/domain/goal.dart';
import 'package:coincompass/features/people/domain/person.dart';
import 'package:coincompass/features/splits/domain/split.dart';
import 'package:flutter_test/flutter_test.dart';

/// The write-schema guard.
///
/// `docs/WRITE_SCHEMAS.md` records what each endpoint's Zod schema actually
/// declares, probed against the live backend. A key outside that list is
/// **silently stripped** — no error, no field error, the value just never
/// persists. That has already shipped twice (a budget `name` and `rollover`, a
/// goal `note`, a credit `dueDate`, a person's `phone`/`email`), which is why
/// this file exists.
///
/// Two layers, both offline:
///
///  1. every model's `toWriteJson()` is built from a fully-populated instance —
///     the maximal body it can ever produce — and every key it emits is checked
///     against the ACCEPTED set below;
///  2. the form sheets build their own bodies in a private `_buildBody`, which
///     is where a re-added control would actually leak. Those are read straight
///     off disk and their body keys extracted, so a new `'dueDate': ...` line
///     fails here rather than in production.
///
/// When the backend schema genuinely changes: re-probe, update
/// `docs/WRITE_SCHEMAS.md`, then update the constants below to match. Never the
/// other way round.
void main() {
  // ---------------------------------------------------------------------------
  // The ACCEPTED column of docs/WRITE_SCHEMAS.md, transcribed. Keep in sync.
  // ---------------------------------------------------------------------------

  const acceptedPeople = {'name', 'relation'};
  const acceptedPeopleGroups = {'name', 'members'};
  const acceptedCredits = {
    'person',
    'direction',
    'amount',
    'note',
    'date',
    'account',
    'category',
  };
  const acceptedSplits = {
    'description',
    'totalAmount',
    'yourShare',
    'participants',
    'date',
    'note',
    'category',
    'account',
  };
  const acceptedBudgets = {
    'amount',
    'category',
    'period',
    'currency',
    'startDate',
  };
  const acceptedGoals = {
    'name',
    'targetAmount',
    'savedAmount',
    'targetDate',
    'monthlyContribution',
    'color',
    'icon',
    'currency',
  };

  /// The keys the server drops on the floor. Named so a failure says *which*
  /// mistake was made, not just "unexpected key".
  const stripped = {
    'POST /people': {'phone', 'email', 'note', 'color', 'group', 'key',
        'nickname', 'avatar', 'tags'},
    'POST /people/groups': {'color', 'note', 'description', 'icon'},
    'POST /budgets': {'name', 'rollover', 'note', 'alertAt', 'threshold',
        'account'},
    'POST /goals': {'note', 'priority', 'status'},
    'POST /credits': {'dueDate', 'currency', 'settled', 'settledAt', 'status'},
    'POST /splits': {'group', 'currency', 'settled'},
  };

  /// One assertion, phrased so the failure names the offending key and says
  /// what will happen to it.
  void expectWithin(
    String endpoint,
    Set<String> accepted,
    Map<String, dynamic> body,
  ) {
    final leaked = body.keys.toSet().difference(accepted);
    expect(
      leaked,
      isEmpty,
      reason:
          '$endpoint would send $leaked, which its schema does not declare — '
          'the server strips those silently. Accepted: ${accepted.toList()..sort()}.',
    );
  }

  group('models emit only accepted keys', () {
    test('POST /people', () {
      // Fully populated, including the server-computed slug, so nothing that
      // exists on the model can hide from the check.
      final person = Person(
        id: 'p1',
        name: 'Karthik',
        key: 'karthik',
        relation: PersonRelation.friend,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 2, 1),
      );

      final body = person.toWriteJson();
      expectWithin('POST /people', acceptedPeople, body);
      // `name` is required and `relation` defaults server-side to `other`.
      expect(body['name'], 'Karthik');
      expect(body['relation'], 'friend');
      // `key` is a slug the server computes; sending it is meaningless.
      expect(body.containsKey('key'), isFalse);
    });

    test('POST /people/groups', () {
      final group = PersonGroup(
        id: 'g1',
        name: 'Chennai trip',
        memberIds: const ['p1', 'p2'],
        memberCount: 2,
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final body = group.toWriteJson();
      expectWithin('POST /people/groups', acceptedPeopleGroups, body);
      expect(body['name'], 'Chennai trip');
      expect(body['members'], ['p1', 'p2']);
    });

    test('POST /credits', () {
      final credit = Credit(
        id: 'c1',
        amount: 5000,
        direction: CreditDirection.given,
        personId: 'p1',
        note: 'For the plot registration',
        date: DateTime.utc(2026, 6, 1),
        accountId: 'a1',
        categoryId: 'cat1',
        outstanding: 4000,
        createdAt: DateTime.utc(2026, 6, 1),
      );

      final body = credit.toWriteJson();
      expectWithin('POST /credits', acceptedCredits, body);
      expect(body['person'], 'p1');
      expect(body['direction'], 'given');
      expect(body['amount'], 5000);
      // `outstanding` is server-computed and was never a write key.
      expect(body.containsKey('outstanding'), isFalse);
    });

    test('POST /credits — a free-text person still fits the schema', () {
      final credit = Credit(
        id: 'c2',
        amount: 250,
        direction: CreditDirection.borrowed,
        personName: 'Somebody new',
      );

      final body = credit.toWriteJson();
      expectWithin('POST /credits', acceptedCredits, body);
      expect(body['person'], 'Somebody new');
    });

    test('POST /splits', () {
      final split = Split(
        id: 's1',
        description: 'Dinner at Dakshin',
        totalAmount: 4800,
        yourShare: 1600,
        participantIds: const ['p1', 'p2'],
        date: DateTime.utc(2026, 8, 20),
        note: 'Three ways',
        categoryId: 'cat1',
        accountId: 'a1',
        createdAt: DateTime.utc(2026, 8, 20),
      );

      final body = split.toWriteJson();
      expectWithin('POST /splits', acceptedSplits, body);
      expect(body['description'], 'Dinner at Dakshin');
      expect(body['totalAmount'], 4800);
      expect(body['yourShare'], 1600);
    });

    test('POST /budgets', () {
      // Every server-computed field is populated too — `spent`, `percent` and
      // friends are read-only and must not find their way back out.
      final budget = Budget(
        id: 'b1',
        amount: 25000,
        categoryId: 'cat1',
        period: BudgetPeriod.weekly,
        spent: 9000,
        remaining: 16000,
        percent: 36,
        over: false,
        periodRange: BudgetPeriodRange(
          start: DateTime.utc(2026, 8, 1),
          end: DateTime.utc(2026, 9, 1),
        ),
        currency: 'INR',
        startDate: DateTime.utc(2026, 8, 5),
      );

      final body = budget.toWriteJson();
      expectWithin('POST /budgets', acceptedBudgets, body);
      expect(body['amount'], 25000);
      expect(body['period'], 'weekly');
      // The two that shipped broken: a budget has neither server-side.
      expect(body.containsKey('name'), isFalse);
      expect(body.containsKey('rollover'), isFalse);
      expect(body.containsKey('spent'), isFalse);
    });

    test('POST /goals', () {
      final goal = Goal(
        id: 'g1',
        name: 'Emergency fund',
        targetAmount: 600000,
        savedAmount: 125000,
        targetDate: DateTime.utc(2029, 4, 1),
        monthlyContribution: 15000,
        color: '#22C55E',
        icon: 'piggy-bank',
        currency: 'INR',
        remaining: 475000,
        percentFromServer: 20,
        completeFromServer: false,
        monthsLeft: 32,
      );

      final body = goal.toWriteJson();
      expectWithin('POST /goals', acceptedGoals, body);
      expect(body['name'], 'Emergency fund');
      expect(body['targetAmount'], 600000);
      // The one that shipped broken.
      expect(body.containsKey('note'), isFalse);
      expect(body.containsKey('remaining'), isFalse);
    });

    test('a bare instance still carries every required key', () {
      expect(
        Person(id: 'p', name: 'A').toWriteJson().keys,
        containsAll(<String>['name']),
      );
      expect(
        Credit(id: 'c', amount: 1, direction: CreditDirection.given)
            .toWriteJson()
            .keys,
        containsAll(<String>['person', 'direction', 'amount']),
      );
      expect(
        Split(id: 's', description: 'd', totalAmount: 2, yourShare: 1)
            .toWriteJson()
            .keys,
        containsAll(<String>['description', 'totalAmount', 'yourShare']),
      );
      expect(Budget(id: 'b', amount: 1).toWriteJson().keys, contains('amount'));
      expect(
        Goal(id: 'g', name: 'n', targetAmount: 1).toWriteJson().keys,
        containsAll(<String>['name', 'targetAmount']),
      );
    });
  });

  group('form sheets build only accepted keys', () {
    // The sheets do not go through `toWriteJson()` — each one assembles its own
    // map in `_buildBody`, which is exactly where a re-added TextField leaks.
    // The method is private, so the guard reads the source: it pulls out the
    // map-literal keys (`'amount': ...`) and the WriteBody helper keys
    // (`WriteBody.putText(body, 'note', ...)`) from the body-building region.
    final mapLiteralKey = RegExp(r"'([A-Za-z][A-Za-z0-9]*)'\s*:");
    final writeBodyKey = RegExp(
      r"WriteBody\.put\w+\(\s*body,\s*'([A-Za-z][A-Za-z0-9]*)'",
    );

    /// The source of `_buildBody` (or, for the group sheet, the inline literal),
    /// isolated by brace counting from [marker].
    String region(String path, String marker) {
      final source = File(path).readAsStringSync();
      final start = source.indexOf(marker);
      expect(
        start,
        isNonNegative,
        reason:
            '$path no longer contains "$marker" — this guard has gone blind, '
            'point it at the new body builder.',
      );

      var depth = 0;
      var seenOpen = false;
      for (var i = start; i < source.length; i++) {
        final char = source[i];
        if (char == '{') {
          depth++;
          seenOpen = true;
        } else if (char == '}') {
          depth--;
          if (seenOpen && depth == 0) return source.substring(start, i + 1);
        }
      }
      fail('$path: could not find the end of "$marker".');
    }

    void checkSheet(
      String endpoint,
      String path,
      String marker,
      Set<String> accepted,
    ) {
      test('$endpoint — ${path.split('/').last}', () {
        final source = region(path, marker);
        final keys = {
          for (final match in mapLiteralKey.allMatches(source))
            match.group(1)!,
          for (final match in writeBodyKey.allMatches(source)) match.group(1)!,
        };

        expect(
          keys,
          isNotEmpty,
          reason: '$path: extracted no keys at all — the guard is not reading '
              'the body builder any more.',
        );
        expectWithin(endpoint, accepted, {for (final key in keys) key: null});

        // Say it twice, so a regression names the exact historical mistake.
        for (final key in stripped[endpoint]!) {
          expect(
            keys,
            isNot(contains(key)),
            reason:
                '$path sends "$key" to $endpoint. The server declares no such '
                'key and discards it without an error — the control must go, '
                'not the value. See docs/WRITE_SCHEMAS.md.',
          );
        }
      });
    }

    checkSheet(
      'POST /people',
      'lib/features/people/presentation/person_form_sheet.dart',
      'Map<String, dynamic> _buildBody',
      acceptedPeople,
    );
    checkSheet(
      'POST /people/groups',
      'lib/features/people/presentation/group_form_sheet.dart',
      "final body = <String, dynamic>",
      acceptedPeopleGroups,
    );
    checkSheet(
      'POST /credits',
      'lib/features/credits/presentation/credit_form_sheet.dart',
      'Map<String, dynamic> _buildBody',
      acceptedCredits,
    );
    checkSheet(
      'POST /splits',
      'lib/features/splits/presentation/split_form_sheet.dart',
      'Map<String, dynamic> _buildBody',
      acceptedSplits,
    );
    checkSheet(
      'POST /budgets',
      'lib/features/budgets/presentation/budget_form_sheet.dart',
      'Map<String, dynamic> _buildBody',
      acceptedBudgets,
    );
    checkSheet(
      'POST /goals',
      'lib/features/goals/presentation/goal_form_sheet.dart',
      'Map<String, dynamic> _buildBody',
      acceptedGoals,
    );
  });
}
