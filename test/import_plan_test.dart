import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/accounts/domain/account.dart';
import 'package:coincompass/features/categories/domain/category.dart';
import 'package:coincompass/features/import/domain/import_plan.dart';
import 'package:coincompass/features/import/domain/import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.3b — matching names to ids, and refusing to guess.**
///
/// The two failure modes this file exists to prevent are mirror images:
/// silently *creating* a record the user did not ask for, and silently
/// *reusing* one they did not mean. Both write real transactions against the
/// wrong account and neither shows up as an error.
void main() {
  Account account(String id, String name, {bool archived = false}) => Account(
    id: id,
    name: name,
    type: AccountType.bank,
    archived: archived,
  );

  Category category(String id, String name, CategoryType type) =>
      Category(id: id, name: name, type: type);

  const header =
      'Date,Type,Amount,Currency,Account,To Account,Category,Payee,Note,Tags';

  ImportPlan planFor(
    String csv, {
    List<Account> accounts = const [],
    List<Category> categories = const [],
  }) => ImportPlan.from(
    parse: ImportParser.parse(csv),
    accounts: accounts,
    categories: categories,
  );

  NameRef refNamed(ImportPlan plan, String name) =>
      plan.refs.firstWhere((r) => r.name == name);

  group('matching', () {
    test('an exact account name resolves with no decision needed', () {
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,HDFC Bank,,,,,',
        accounts: [account('a1', 'HDFC Bank')],
      );
      final ref = refNamed(plan, 'HDFC Bank');
      expect(ref.strength, MatchStrength.exact);
      expect(ref.matchedId, 'a1');
      expect(plan.undecided, isEmpty);
      expect(plan.ready.single.draft!.accountId, 'a1');
    });

    test('case and spacing are folded, and the fold is reported', () {
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,  hdfc   bank ,,,,,',
        accounts: [account('a1', 'HDFC Bank')],
      );
      final ref = plan.refs.single;
      expect(ref.strength, MatchStrength.normalised);
      expect(ref.matchedId, 'a1');
      expect(ref.matchedName, 'HDFC Bank',
          reason: 'the preview has to show what it matched to');
    });

    test('punctuation is not folded away', () {
      // "Amex (Gold)" and "Amex Gold" are two records a user may really have.
      // Folding them together files the wrong one's money without asking.
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,Amex Gold,,,,,',
        accounts: [account('a1', 'Amex (Gold)')],
      );
      expect(plan.refs.single.isMatched, isFalse);
      expect(plan.undecided, hasLength(1));
    });

    test('nothing near-misses into a match', () {
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,HDFC,,,,,',
        accounts: [account('a1', 'HDFC Bank')],
      );
      expect(plan.refs.single.strength, MatchStrength.none);
    });

    test('an active account beats an archived one of the same name', () {
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,Savings,,,,,',
        accounts: [
          account('old', 'Savings', archived: true),
          account('new', 'Savings'),
        ],
      );
      expect(plan.refs.single.matchedId, 'new');
    });

    test('an archived account still matches when it is the only one', () {
      // A file of last year's transactions legitimately names a closed account.
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,Old Wallet,,,,,',
        accounts: [account('old', 'Old Wallet', archived: true)],
      );
      expect(plan.refs.single.matchedId, 'old');
    });
  });

  group('categories are typed', () {
    test('a category matches only within its own type', () {
      // The row is an expense, so it must not pick up the income "Bonus".
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,HDFC,,Bonus,,,',
        accounts: [account('a1', 'HDFC')],
        categories: [category('c1', 'Bonus', CategoryType.income)],
      );
      final ref = refNamed(plan, 'Bonus');
      expect(ref.categoryType, CategoryType.expense);
      expect(ref.isMatched, isFalse);
    });

    test('the same name in both directions is two separate decisions', () {
      final plan = planFor(
        '$header\n'
        '2026-08-24,expense,500,INR,HDFC,,Gift,,,\n'
        '2026-08-25,income,900,INR,HDFC,,Gift,,,',
        accounts: [account('a1', 'HDFC')],
      );
      final gifts = plan.refs.where((r) => r.name == 'Gift').toList();
      expect(gifts, hasLength(2));
      expect(gifts.map((r) => r.key).toSet(), hasLength(2));
    });

    test("a transfer's category is matched as an expense", () {
      final plan = planFor(
        '$header\n2026-08-24,transfer,500,INR,HDFC,ICICI,Moving,,,',
        accounts: [account('a1', 'HDFC'), account('a2', 'ICICI')],
        categories: [category('c1', 'Moving', CategoryType.expense)],
      );
      expect(refNamed(plan, 'Moving').matchedId, 'c1');
    });
  });

  group('nothing is created without being asked for', () {
    test('an unmatched name blocks the import until it is decided', () {
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,HDFC Bnak,,,,,',
        accounts: [account('a1', 'HDFC Bank')],
      );
      expect(plan.isReadyToImport, isFalse);
      expect(plan.undecided.single.name, 'HDFC Bnak');
      expect(plan.pendingCreations, isEmpty,
          reason: 'undecided is not the same as "create it"');
    });

    test('a typo pointed at an existing account imports against that account', () {
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,HDFC Bnak,,,,,',
        accounts: [account('a1', 'HDFC Bank')],
      );
      final decided =
          plan.decide(plan.refs.single.key, const UseExisting('a1'));
      expect(decided.isReadyToImport, isTrue);
      expect(decided.ready.single.draft!.accountId, 'a1');
      expect(decided.pendingCreations, isEmpty);
    });

    test('a row waiting on a creation is ready, but has no draft yet', () {
      // "Decided" and "buildable" are different. Folding them together made the
      // preview say "Nothing to import" the instant the user tapped "Create
      // it" — the row is settled, its id simply does not exist until the run
      // creates the record.
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,Jupiter,,,,,',
        accounts: [account('a1', 'HDFC')],
      );
      final key = plan.refs.single.key;
      final decided = plan.decide(key, const CreateNew());

      expect(decided.undecided, isEmpty);
      expect(decided.pendingCreations.single.name, 'Jupiter');
      expect(decided.isReadyToImport, isTrue,
          reason: 'the run button must open once every name is decided');
      expect(decided.ready.single.draft, isNull,
          reason: 'nothing to POST until the account exists');

      // The runner creates the record, then re-reads the plan.
      final created = decided.withCreatedIds({key: 'a9'});
      expect(created.pendingCreations, isEmpty);
      expect(created.ready.single.draft!.accountId, 'a9');
    });

    test('an undecided name still blocks its rows', () {
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,Jupiter,,,,,',
        accounts: [account('a1', 'HDFC')],
      );
      expect(plan.ready, isEmpty);
      expect(plan.blocked, hasLength(1));
      expect(plan.isReadyToImport, isFalse);
    });
  });

  group('skipping', () {
    test('skipping an account excludes its rows rather than blocking them', () {
      final plan = planFor(
        '$header\n'
        '2026-08-24,expense,500,INR,Petty Cash,,,,,\n'
        '2026-08-25,expense,600,INR,HDFC,,,,,',
        accounts: [account('a1', 'HDFC')],
      );
      final decided =
          plan.decide(refNamed(plan, 'Petty Cash').key, const SkipRef());

      expect(decided.skipped.single.line, 2);
      expect(decided.ready.single.line, 3);
      expect(decided.isReadyToImport, isTrue);
    });

    test('an unresolved category imports the row uncategorised', () {
      // Blocking here would turn one unfamiliar category name into a hundred
      // rows the user cannot import. A category is optional on this API.
      final plan = planFor(
        '$header\n2026-08-24,expense,500,INR,HDFC,,Groceries,,,',
        accounts: [account('a1', 'HDFC')],
      );
      final decided =
          plan.decide(refNamed(plan, 'Groceries').key, const SkipRef());
      expect(decided.ready.single.draft!.categoryId, isNull);
      expect(decided.ready.single.draft!.accountId, 'a1');
    });
  });

  group('the fallback account', () {
    test('rows with a blank account are blocked until one is chosen', () {
      final plan = planFor(
        'Date,Type,Amount,Account\n2026-08-24,expense,500,',
      );
      expect(plan.needsFallbackAccount, isTrue);
      expect(plan.rowsNeedingFallbackAccount, 1);
      expect(plan.ready, isEmpty);
      expect(plan.blocked.single.reasons.join(), contains('account'));
    });

    test('choosing one clears the block', () {
      final plan = planFor(
        'Date,Type,Amount,Account\n2026-08-24,expense,500,',
      ).withFallbackAccount('a1');

      expect(plan.needsFallbackAccount, isFalse);
      expect(plan.ready.single.draft!.accountId, 'a1');
    });

    test('it does not rescue a row broken for another reason', () {
      final plan = planFor(
        'Date,Type,Amount,Account\n2026-08-24,expense,oops,',
      ).withFallbackAccount('a1');
      expect(plan.ready, isEmpty);
      expect(plan.blocked, hasLength(1));
    });
  });

  group('the draft that gets POSTed', () {
    test('carries every field the row supplied', () {
      final plan = planFor(
        '$header\n'
        '2026-08-24,expense,1250.50,INR,HDFC,,Food,Chai Kada,"Lunch, then fuel","food;travel"',
        accounts: [account('a1', 'HDFC')],
        categories: [category('c1', 'Food', CategoryType.expense)],
      );
      final draft = plan.ready.single.draft!;
      final json = draft.toJson();

      expect(json['type'], 'expense');
      expect(json['amount'], 1250.50);
      expect(json['account'], 'a1');
      expect(json['category'], 'c1');
      expect(json['payee'], 'Chai Kada');
      expect(json['note'], 'Lunch, then fuel');
      expect(json['tags'], ['food', 'travel']);
      expect(json['currency'], 'INR');
      expect(json.containsKey('toAccount'), isFalse);
    });

    test('a transfer carries its destination', () {
      final plan = planFor(
        '$header\n2026-08-24,transfer,5000,INR,HDFC,ICICI,,,,',
        accounts: [account('a1', 'HDFC'), account('a2', 'ICICI')],
      );
      final json = plan.ready.single.draft!.toJson();
      expect(json['account'], 'a1');
      expect(json['toAccount'], 'a2');
    });

    test('a transfer whose destination is undecided does not get written', () {
      final plan = planFor(
        '$header\n2026-08-24,transfer,5000,INR,HDFC,Unknown Bank,,,,',
        accounts: [account('a1', 'HDFC')],
      );
      expect(plan.ready, isEmpty);
      expect(plan.blocked.single.reasons.join(), contains('Unknown Bank'));
    });

    test('a row the parser refused never reaches a draft', () {
      final plan = planFor(
        '$header\n2026-08-24,nonsense,500,INR,HDFC,,,,,',
        accounts: [account('a1', 'HDFC')],
      );
      expect(plan.ready, isEmpty);
      expect(plan.blocked, hasLength(1));
    });
  });

  group('the refs the preview lists', () {
    test('one entry per distinct name, counting the rows that use it', () {
      final plan = planFor(
        '$header\n'
        '2026-08-24,expense,500,INR,HDFC,,,,,\n'
        '2026-08-25,expense,600,INR,hdfc,,,,,\n'
        '2026-08-26,expense,700,INR,ICICI,,,,,',
        accounts: [account('a1', 'HDFC')],
      );
      expect(plan.refs, hasLength(2));
      expect(refNamed(plan, 'HDFC').rowCount, 2,
          reason: 'HDFC and hdfc are one name');
      expect(refNamed(plan, 'HDFC').lines, [2, 3]);
    });

    test('a destination account is collected too', () {
      final plan = planFor(
        '$header\n2026-08-24,transfer,500,INR,HDFC,ICICI,,,,',
      );
      expect(plan.refs.map((r) => r.name), containsAll(['HDFC', 'ICICI']));
    });

    test('deciding is per ref and leaves the others alone', () {
      final plan = planFor(
        '$header\n'
        '2026-08-24,expense,500,INR,HDFC,,,,,\n'
        '2026-08-25,expense,600,INR,ICICI,,,,,',
      );
      final decided =
          plan.decide(refNamed(plan, 'HDFC').key, const UseExisting('a1'));
      expect(decided.undecided.single.name, 'ICICI');
    });

    test('a plan is immutable — deciding returns a new one', () {
      final plan = planFor('$header\n2026-08-24,expense,500,INR,HDFC,,,,,');
      final decided =
          plan.decide(plan.refs.single.key, const UseExisting('a1'));
      expect(plan.undecided, hasLength(1));
      expect(decided.undecided, isEmpty);
    });
  });
}
