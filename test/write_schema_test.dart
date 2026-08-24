import 'dart:io';

import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/budgets/domain/budget.dart';
import 'package:coincompass/features/credits/domain/credit.dart';
import 'package:coincompass/features/goals/domain/goal.dart';
import 'package:coincompass/features/holdings/domain/holding.dart';
import 'package:coincompass/features/loans/domain/loan.dart';
import 'package:coincompass/features/people/domain/person.dart';
import 'package:coincompass/features/splits/domain/split.dart';
import 'package:coincompass/features/stocks/domain/stock.dart';
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

  const acceptedAccounts = {
    'name',
    'type',
    'initialBalance',
    'includeInTotal',
    'color',
    'icon',
    'currency',
  };
  const acceptedTransactions = {
    'type',
    'amount',
    'account',
    'toAccount',
    'category',
    'date',
    'note',
    'payee',
    'tags',
    'oneoff',
    'currency',
  };
  const acceptedRecurring = {
    'type',
    'amount',
    'account',
    'toAccount',
    'category',
    'payee',
    'note',
    'currency',
    'frequency',
    'interval',
    'startDate',
    'endDate',
    'active',
  };
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
  const acceptedLoans = {
    'name',
    'outstanding',
    'lender',
    'type',
    'principal',
    'roi',
    'emi',
    'foreclosureChargePct',
    'startDate',
    'endDate',
    'status',
    'note',
    'currency',
  };
  const acceptedHoldings = {
    'name',
    'class',
    'subtype',
    'value',
    'maturityDate',
    'startDate',
    'note',
    'currency',
  };
  const acceptedStocksBuy = {
    'symbol',
    'demat',
    'qty',
    'buyPrice',
    'buyDate',
    'note',
  };
  const acceptedStocksSell = {
    'symbol',
    'demat',
    'qty',
    'sellPrice',
    'sellDate',
    'note',
  };

  // The two loan actions are not Zod-probeable — an empty preclose body is
  // *valid* and executes, which is how a live 2Cr loan got closed during
  // Phase 0 recon. Their contracts come from the deployed web bundle, and the
  // bodies are built inside LoansRepository so no screen can widen them.
  const acceptedLoanPay = {'amount', 'chargePct'};
  const acceptedLoanPreclose = {'chargePct'};
  const acceptedSplitApply = {'symbol', 'date'};

  /// The keys the server drops on the floor. Named so a failure says *which*
  /// mistake was made, not just "unexpected key".
  const stripped = {
    // The Phase-2 blocker: the app shipped the web app's own field names,
    // which the API declares none of. Every balance a user typed was dropped.
    'POST /accounts': {'openingBalance', 'excludeFromTotal', 'institution',
        'last4', 'note', 'creditLimit', 'balance'},
    'POST /recurring': {'nextRun', 'lastRun', 'dayOfMonth', 'occurrences'},
    'POST /people': {'phone', 'email', 'note', 'color', 'group', 'key',
        'nickname', 'avatar', 'tags'},
    'POST /people/groups': {'color', 'note', 'description', 'icon'},
    'POST /budgets': {'name', 'rollover', 'note', 'alertAt', 'threshold',
        'account'},
    'POST /goals': {'note', 'priority', 'status'},
    'POST /credits': {'dueDate', 'currency', 'settled', 'settledAt', 'status'},
    'POST /splits': {'group', 'currency', 'settled'},
    'POST /loans': {'interestPaid', 'chargesPaid', 'tenure', 'account'},
    'POST /holdings': {'invested', 'institution', 'roi', 'account'},
    'POST /stocks/buy': {'date', 'exchange', 'name', 'charges', 'brokerage',
        'fees'},
    'POST /stocks/sell': {'date', 'lot', 'charges', 'brokerage', 'fees'},
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

    test('POST /loans', () {
      // Every server-computed figure populated too: a loan carries
      // `interestPaid` and `chargesPaid` on read, and the server recomputes
      // both from part-payments — sending them back is a no-op it will not
      // report.
      final loan = Loan(
        id: 'l1',
        name: 'Deena',
        outstanding: 20000000,
        lender: 'UCO',
        type: LoanType.home,
        principal: 20000000,
        roi: 7.25,
        emi: 137000,
        foreclosureChargePct: 2,
        interestPaid: 145000,
        chargesPaid: 3200,
        startDate: DateTime(2026, 7, 3),
        endDate: DateTime(2046, 7, 3),
        status: LoanStatus.active,
        note: 'Sanctioned July 2026',
        currency: 'INR',
        createdAt: DateTime.utc(2026, 7, 3),
        updatedAt: DateTime.utc(2026, 7, 3),
      );

      final body = loan.toWriteJson();
      expectWithin('POST /loans', acceptedLoans, body);
      expect(body['name'], 'Deena');
      expect(body['outstanding'], 20000000);
      expect(body.containsKey('interestPaid'), isFalse);
      expect(body.containsKey('chargesPaid'), isFalse);
      expect(body.containsKey('tenure'), isFalse);
      // A calendar day must survive as that day: a local midnight run through
      // `toUtc()` in IST would go out as 2026-07-02.
      expect(body['startDate'], '2026-07-03T00:00:00.000Z');
    });

    test('POST /holdings', () {
      final holding = Holding(
        id: 'h1',
        name: 'HDFC FD',
        holdingClass: HoldingClass.saving,
        subtype: HoldingSubtype.fixedDeposit,
        value: 450000,
        maturityDate: DateTime(2027, 3, 31),
        startDate: DateTime(2026, 3, 31),
        note: 'Auto-renew off',
        currency: 'INR',
        createdAt: DateTime.utc(2026, 3, 31),
        updatedAt: DateTime.utc(2026, 3, 31),
      );

      final body = holding.toWriteJson();
      expectWithin('POST /holdings', acceptedHoldings, body);
      expect(body['class'], 'saving');
      expect(body['subtype'], 'fixed_deposit');
      expect(body['value'], 450000);
      expect(body['maturityDate'], '2027-03-31T00:00:00.000Z');
      // The three the server strips. They are not just absent from the body —
      // Phase 4 deleted them from the model, so a form has nothing to bind to.
      for (final key in const ['invested', 'institution', 'roi']) {
        expect(body.containsKey(key), isFalse);
      }
    });

    test('POST /stocks/splits/apply', () {
      final split = StockSplit(
        symbol: 'RELIANCE.NS',
        date: '2026-08-14',
        ticker: 'RELIANCE',
        label: '1:2',
        qtyBefore: 10,
        qtyAfter: 20,
      );

      final body = split.toApplyJson();
      expectWithin('POST /stocks/splits/apply', acceptedSplitApply, body);
      // The date goes back exactly as it arrived — the pair identifies the
      // split, so reformatting it would fail to match.
      expect(body['date'], '2026-08-14');
      expect(body['symbol'], 'RELIANCE.NS');
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
      expect(
        Loan(id: 'l', name: 'n', outstanding: 1).toWriteJson().keys,
        containsAll(<String>['name', 'outstanding']),
      );
      expect(
        Holding(
          id: 'h',
          name: 'n',
          holdingClass: HoldingClass.investment,
          subtype: HoldingSubtype.bonds,
          value: 1,
        ).toWriteJson().keys,
        containsAll(<String>['name', 'class', 'subtype', 'value']),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Source-level guard. Some bodies never pass through a model: a form sheet
  // assembles its own map in `_buildBody`, and the stock/loan action bodies are
  // assembled inside their repository. Neither is reachable from a unit test —
  // both are private — so the guard reads the source, isolates the body region
  // by brace counting, and extracts the keys it would emit.
  // ---------------------------------------------------------------------------

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

  /// [optional] marks a file that a later phase still has to land. It is only
  /// ever true while the screen is being built in parallel with this guard —
  /// a missing file skips, a present one is checked like any other. Never set
  /// it to silence a real failure.
  void checkSheet(
    String endpoint,
    String path,
    String marker,
    Set<String> accepted, {
    bool optional = false,
  }) {
    test('$endpoint — ${path.split('/').last}', () {
      if (optional && !File(path).existsSync()) {
        markTestSkipped('$path does not exist yet — nothing to guard.');
        return;
      }
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
      for (final key in stripped[endpoint] ?? const <String>{}) {
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


  group('form sheets build only accepted keys', () {
    // The sheets do not go through `toWriteJson()` — each one assembles its own
    // map in `_buildBody`, which is exactly where a re-added TextField leaks.
    // The method is private, so the guard reads the source: it pulls out the
    // map-literal keys (`'amount': ...`) and the WriteBody helper keys
    // (`WriteBody.putText(body, 'note', ...)`) from the body-building region.
    checkSheet(
      'POST /accounts',
      'lib/features/accounts/presentation/account_form_sheet.dart',
      'Map<String, dynamic> _buildBody',
      acceptedAccounts,
    );
    // Creating a transaction goes through the typed `TransactionDraft`, so the
    // compiler guards it. Editing does not — the patch is assembled by hand.
    checkSheet(
      'POST /transactions',
      'lib/features/transactions/presentation/transaction_form_sheet.dart',
      'final patch = <String, dynamic>',
      acceptedTransactions,
    );
    checkSheet(
      'POST /recurring',
      'lib/features/recurring/presentation/recurring_form_sheet.dart',
      'final body = <String, dynamic>',
      acceptedRecurring,
    );
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

    // Phase 4. Both sheets have landed, so `optional` is gone: a missing file
    // is now a failure, not a skip. A guard that quietly skips is a guard that
    // is not running.
    checkSheet(
      'POST /loans',
      'lib/features/loans/presentation/loan_form_sheet.dart',
      'Map<String, dynamic> _buildBody',
      acceptedLoans,
    );
    checkSheet(
      'POST /holdings',
      'lib/features/holdings/presentation/holding_form_sheet.dart',
      'Map<String, dynamic> _buildBody',
      acceptedHoldings,
    );
  });

  group('repositories build only accepted action bodies', () {
    // Buy, sell, pay and preclose take typed arguments, not a caller-supplied
    // map — the body is assembled inside the repository precisely so a screen
    // cannot widen it. That makes the repository source the single place a
    // stray key could appear, so the guard reads it directly.
    checkSheet(
      'POST /stocks/buy',
      'lib/features/stocks/data/stocks_repository.dart',
      'Endpoints.stocksBuy,',
      acceptedStocksBuy,
    );
    checkSheet(
      'POST /stocks/sell',
      'lib/features/stocks/data/stocks_repository.dart',
      'Endpoints.stocksSell,',
      acceptedStocksSell,
    );
    checkSheet(
      'POST /loans/:id/pay',
      'lib/features/loans/data/loans_repository.dart',
      'Endpoints.loanPay(id),',
      acceptedLoanPay,
    );
    checkSheet(
      'POST /loans/:id/preclose',
      'lib/features/loans/data/loans_repository.dart',
      'Endpoints.loanPreclose(id),',
      acceptedLoanPreclose,
    );
  });

  group('action sheets cannot assemble a body of their own', () {
    // Buy, sell, part-payment and preclose have no `_buildBody`: the body is
    // built inside the repository from typed arguments, which is the only
    // reason the four repository checks above are sufficient. That guarantee
    // holds only while the sheets keep delegating — the moment one calls the
    // API directly it can send whatever it likes, and the repository guard
    // goes blind. So the delegation itself is what is asserted here.
    const delegating = {
      'lib/features/stocks/presentation/stock_buy_sheet.dart': '.buy(',
      'lib/features/stocks/presentation/stock_sell_sheet.dart': '.sell(',
      'lib/features/loans/presentation/loan_pay_sheet.dart': '.pay(',
      'lib/features/loans/presentation/loan_preclose_sheet.dart': '.preclose(',
    };

    for (final entry in delegating.entries) {
      test('${entry.key.split('/').last} goes through its repository', () {
        final source = File(entry.key).readAsStringSync();

        expect(
          source.contains(entry.value),
          isTrue,
          reason:
              '${entry.key} no longer calls ${entry.value} — if the write moved '
              'somewhere else, point this guard at it.',
        );

        // The typed call is the whole protection. A raw request from a sheet
        // would carry a map the repository guard never sees.
        for (final direct in const [
          'postJson(',
          'patchJson(',
          '_api.',
          'apiClientProvider',
        ]) {
          expect(
            source.contains(direct),
            isFalse,
            reason:
                '${entry.key} reaches the API directly via "$direct". Every '
                'write on this path must go through the repository, whose '
                'body is checked against docs/WRITE_SCHEMAS.md.',
          );
        }
      });
    }
  });

  group('endpoints that do not exist stay uncalled', () {
    test('nothing POSTs to /stocks/splits', () {
      // `GET /stocks/splits` lists pending splits; the matching POST 404s.
      // Applying one goes to /stocks/splits/apply.
      final source = File(
        'lib/features/stocks/data/stocks_repository.dart',
      ).readAsStringSync();
      // The trailing delimiter matters: `stocksSplitsApply` starts with
      // `stocksSplits`, and a plain `contains` would flag the correct call.
      expect(
        RegExp(r'postJson\(Endpoints\.stocksSplits[,)]').hasMatch(source),
        isFalse,
        reason:
            'POST /stocks/splits does not exist — it 404s. Apply a split with '
            'Endpoints.stocksSplitsApply. See docs/WRITE_SCHEMAS.md.',
      );
      expect(source.contains('Endpoints.stocksSplitsApply'), isTrue);
    });

    test('a loan has no tenure field to bind to', () {
      // `tenure` reads like a column and is not one — the server strips it and
      // derives the remaining term from outstanding, roi and emi instead.
      // `Loan.monthsRemaining` is that derivation; a stored field would be a
      // second, divergent answer.
      final source = File(
        'lib/features/loans/domain/loan.dart',
      ).readAsStringSync();
      for (final field in const ['tenure', 'account']) {
        expect(
          source.contains('this.$field'),
          isFalse,
          reason:
              'Loan.$field is back. POST /loans strips it — see '
              'docs/WRITE_SCHEMAS.md.',
        );
      }
    });

    test('a holding class and subtype are never independent', () {
      // The API validates the two keys separately, so an illegal pair is
      // written without complaint and the holding lands on the wrong side of
      // the saving/investment split. The pairing lives in the enum; this keeps
      // it total and self-consistent.
      for (final subtype in HoldingSubtype.values) {
        expect(
          HoldingSubtype.forClass(subtype.holdingClass),
          contains(subtype),
          reason:
              '${subtype.api} claims ${subtype.holdingClass.api} but is not '
              'offered under it — the Type select would drop it.',
        );
      }
      expect(
        HoldingSubtype.forClass(HoldingClass.saving).length +
            HoldingSubtype.forClass(HoldingClass.investment).length,
        HoldingSubtype.values.length,
        reason: 'every subtype must be reachable from exactly one class.',
      );
    });

    test('a holding has no cost basis to bind to', () {
      // `invested`, `institution` and `roi` were guessed in Phase 1 and are
      // stripped by the server. Phase 4 removed the fields outright so no
      // screen can offer an input for a value that cannot persist.
      final source = File(
        'lib/features/holdings/domain/holding.dart',
      ).readAsStringSync();
      for (final field in const ['invested', 'institution', 'roi']) {
        // The constructor parameter is the unambiguous marker that the field
        // exists — unlike the bare name, which appears in the doc comment
        // explaining why it must not.
        expect(
          source.contains('this.$field'),
          isFalse,
          reason:
              'Holding.$field is back. The server strips it on write and never '
              'returns it — see docs/WRITE_SCHEMAS.md.',
        );
      }
    });
  });
}
