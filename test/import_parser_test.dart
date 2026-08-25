import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/import/domain/import_columns.dart';
import 'package:coincompass/features/import/domain/import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.3a — the rules that decide what a row means.**
///
/// The governing rule, and what most of this file exists to defend: the parser
/// **never guesses in a direction that changes money**. An unreadable amount,
/// an unknown type word and an undecidable direction are all refusals. A wrong
/// guess here does not surface as a broken row the user notices — it surfaces
/// as a plausible transaction with the sign inverted.
void main() {
  /// The header `ExportRepository` documents, verbatim.
  const exportHeader =
      'Date,Type,Amount,Currency,Account,To Account,Category,Payee,Note,Tags';

  group('amounts', () {
    num? amount(String raw) => ImportParser.parseAmount(raw);

    test('plain and grouped', () {
      expect(amount('500'), 500);
      expect(amount('1,234.56'), 1234.56);
      expect(amount('1,23,456.78'), 123456.78); // Indian grouping
      expect(amount('  42  '), 42);
    });

    test('strips currency symbols and codes', () {
      expect(amount('₹1,234'), 1234);
      expect(amount(r'$99.99'), 99.99);
      expect(amount('INR 500'), 500);
      expect(amount('500 INR'), 500);
    });

    test('reads every negative form a statement uses', () {
      expect(amount('-500'), -500);
      expect(amount('−500'), -500); // U+2212, what this app itself renders
      expect(amount('(500)'), -500); // accounting parentheses
      expect(amount('500-'), -500); // trailing sign
      expect(amount('(₹1,234.50)'), -1234.50);
    });

    test('a space-grouped amount is one number', () {
      expect(amount('1 234,56'), 1234.56); // NBSP grouping, comma decimal
      expect(amount('1 234.56'), 1234.56);
    });

    test('resolves the decimal separator from evidence, not a guess', () {
      // Both separators present — exactly one reading each way.
      expect(amount('1.234,56'), 1234.56); // European
      expect(amount('1,234.56'), 1234.56); // Indian/US
      // One separator — the app's own convention, which is also the likelier
      // file. Reading `1.234` as 1234 would be a 1000x error on a real amount.
      expect(amount('1.234'), 1.234);
      expect(amount('1,234'), 1234);
    });

    test('refuses text rather than reading a number out of it', () {
      expect(amount('N/A'), isNull);
      expect(amount('pending'), isNull);
      expect(amount(''), isNull);
      expect(amount('--'), isNull);
      expect(amount('1.2.3'), isNull);
      expect(amount('5-0-0'), isNull);
    });
  });

  group('dates', () {
    DateTime? parse(String raw, [DateOrder order = DateOrder.dayFirst]) =>
        ImportParser.parseDate(raw, order);

    test('ISO, which is what this app exports', () {
      expect(parse('2026-08-24'), DateTime(2026, 8, 24));
      expect(parse('2026-08-24T10:30:00'), DateTime(2026, 8, 24));
    });

    test('a bare year is not a date', () {
      // A stray "2026" in a reference column would otherwise import as
      // 1 January 2026 on every affected row.
      expect(parse('2026'), isNull);
    });

    test('textual months, either way round', () {
      expect(parse('24 Aug 2026'), DateTime(2026, 8, 24));
      expect(parse('24-Aug-2026'), DateTime(2026, 8, 24));
      expect(parse('Aug 24, 2026'), DateTime(2026, 8, 24));
      expect(parse('24 August 2026'), DateTime(2026, 8, 24));
      expect(parse('24-Aug-26'), DateTime(2026, 8, 24));
    });

    test('numeric dates follow the order they are given', () {
      expect(parse('03/04/2026', DateOrder.dayFirst), DateTime(2026, 4, 3));
      expect(parse('03/04/2026', DateOrder.monthFirst), DateTime(2026, 3, 4));
      expect(parse('03-04-2026', DateOrder.dayFirst), DateTime(2026, 4, 3));
      expect(parse('03.04.2026', DateOrder.dayFirst), DateTime(2026, 4, 3));
    });

    test('a four-digit lead is the year whatever the order says', () {
      expect(parse('2026/08/24', DateOrder.monthFirst), DateTime(2026, 8, 24));
    });

    test('two-digit years pivot at 70', () {
      expect(parse('01/01/26'), DateTime(2026, 1, 1));
      expect(parse('01/01/99'), DateTime(1999, 1, 1));
    });

    test('an impossible day is unreadable, not rolled over', () {
      // DateTime(2026, 2, 31) silently becomes 3 March in Dart. An unreadable
      // date the user is told about beats a confidently wrong one.
      expect(parse('31/02/2026'), isNull);
      expect(parse('45/13/2026'), isNull);
      expect(parse('00/01/2026'), isNull);
      expect(parse('13/01/2026', DateOrder.monthFirst), isNull); // month 13
    });

    test('refuses what is not a date', () {
      expect(parse('yesterday'), isNull);
      expect(parse(''), isNull);
      expect(parse('24/08'), isNull);
    });
  });

  group('date order detection', () {
    DateOrderReading read(String body) =>
        ImportParser.parse('Date,Amount\n$body').dateOrder;

    test('one impossible month settles the whole file', () {
      final reading = read('13/04/2026,100\n03/04/2026,200');
      expect(reading.order, DateOrder.dayFirst);
      expect(reading.certain, isTrue);
    });

    test('an impossible second component means month-first', () {
      final reading = read('04/13/2026,100');
      expect(reading.order, DateOrder.monthFirst);
      expect(reading.certain, isTrue);
    });

    test('a file with no tell is flagged ambiguous, not silently guessed', () {
      // Every row reads either way. Choosing wrong shifts up to eleven months
      // of history into the wrong months, so the preview has to ask.
      final reading = read('03/04/2026,100\n05/06/2026,200');
      expect(reading.ambiguous, isTrue);
      expect(reading.order, DateOrder.dayFirst, reason: 'en_IN default');
    });

    test('a file that needs both orders is reported as conflicting', () {
      final reading = read('13/04/2026,100\n04/13/2026,200');
      expect(reading.conflicting, isTrue);
      expect(reading.certain, isFalse);
    });

    test('ISO dates are not ambiguous and raise no flag', () {
      final reading = read('2026-04-03,100\n2026-06-05,200');
      expect(reading.ambiguous, isFalse);
      expect(reading.certain, isTrue);
    });

    test('an explicit order overrides detection', () {
      final result = ImportParser.parse(
        'Date,Amount\n03/04/2026,100',
        dateOrder: DateOrder.monthFirst,
      );
      expect(result.rows.single.date, DateTime(2026, 3, 4));
      expect(result.dateOrder.ambiguous, isFalse);
    });
  });

  group('type', () {
    test('reads the words a file actually uses', () {
      expect(ImportParser.parseType('Expense'), TransactionType.expense);
      expect(ImportParser.parseType('INCOME'), TransactionType.income);
      expect(ImportParser.parseType('transfer'), TransactionType.transfer);
      expect(ImportParser.parseType('debit'), TransactionType.expense);
      expect(ImportParser.parseType('Cr'), TransactionType.income);
    });

    test('refuses an unknown word instead of defaulting to expense', () {
      // TransactionType.fromApi maps anything unknown to expense, which is
      // right for a server response and wrong for a user's file.
      expect(TransactionType.fromApi('nonsense'), TransactionType.expense);
      expect(ImportParser.parseType('nonsense'), isNull);

      final row = ImportParser
          .parse('Date,Type,Amount,Account\n2026-08-24,nonsense,500,HDFC')
          .rows
          .single;
      expect(row.isImportable, isFalse);
      expect(row.blockingIssues.first.code, IssueCode.typeUnknown);
    });
  });

  group('direction, resolved from whatever the file offers', () {
    ParsedRow only(String csv) => ImportParser.parse(csv).rows.single;

    test('an explicit Type column wins, and the amount sign is discarded', () {
      // Same row written two ways; both must import identically.
      final unsigned =
          only('Date,Type,Amount,Account\n2026-08-24,expense,500,HDFC');
      final signed =
          only('Date,Type,Amount,Account\n2026-08-24,expense,-500,HDFC');
      expect(unsigned.type, TransactionType.expense);
      expect(unsigned.amount, 500);
      expect(signed.type, TransactionType.expense);
      expect(signed.amount, 500, reason: 'stored positive; sign lives in type');
    });

    test('Debit and Credit columns carry the sign by position', () {
      final debit =
          only('Date,Account,Debit,Credit\n2026-08-24,HDFC,500,');
      expect(debit.type, TransactionType.expense);
      expect(debit.amount, 500);

      final credit =
          only('Date,Account,Debit,Credit\n2026-08-24,HDFC,,1200');
      expect(credit.type, TransactionType.income);
      expect(credit.amount, 1200);
    });

    test('a row with both a debit and a credit is refused', () {
      final row = only('Date,Account,Debit,Credit\n2026-08-24,HDFC,500,300');
      expect(row.isImportable, isFalse);
      expect(row.blockingIssues.first.code, IssueCode.debitAndCredit);
    });

    test('Type wins over Debit/Credit when a file carries all three', () {
      // This shape used to import as "no amount on this row": direction and
      // magnitude were read from the same branch, and Type has no magnitude.
      final row = only('Date,Type,Account,Debit,Credit\n'
          '2026-08-24,transfer,HDFC,500,');
      expect(row.type, TransactionType.transfer);
      expect(row.amount, 500);
    });

    test('a lone signed amount reads its own sign', () {
      expect(only('Date,Amount,Account\n2026-08-24,-500,HDFC').type,
          TransactionType.expense);
      expect(only('Date,Amount,Account\n2026-08-24,1200,HDFC').type,
          TransactionType.income);
    });

    test('a zero amount is refused', () {
      final row = only('Date,Amount,Account\n2026-08-24,0,HDFC');
      expect(row.isImportable, isFalse);
      expect(row.blockingIssues.first.code, IssueCode.amountZero);
    });
  });

  group('the export round-trip, which is the guaranteed case', () {
    test('reads a row this app wrote', () {
      final result = ImportParser.parse(
        '$exportHeader\n'
        '2026-08-24,expense,1250.50,INR,HDFC Bank,,Food,Chai Kada,'
        '"Lunch, then fuel","food;travel"',
      );

      expect(result.fileWarnings, isEmpty);
      final row = result.rows.single;
      expect(row.isImportable, isTrue);
      expect(row.date, DateTime(2026, 8, 24));
      expect(row.type, TransactionType.expense);
      expect(row.amount, 1250.50);
      expect(row.currency, 'INR');
      expect(row.accountName, 'HDFC Bank');
      expect(row.categoryName, 'Food');
      expect(row.payee, 'Chai Kada');
      expect(row.note, 'Lunch, then fuel',
          reason: 'the quoted comma must not have split the row');
      expect(row.tags, ['food', 'travel']);
    });

    test('reads a transfer row', () {
      final row = ImportParser
          .parse('$exportHeader\n'
              '2026-08-24,transfer,5000,INR,HDFC Bank,ICICI,,,,')
          .rows
          .single;
      expect(row.type, TransactionType.transfer);
      expect(row.toAccountName, 'ICICI');
      expect(row.isImportable, isTrue);
    });

    test('a transfer with no destination is refused', () {
      final row = ImportParser
          .parse('$exportHeader\n2026-08-24,transfer,5000,INR,HDFC,,,,,')
          .rows
          .single;
      expect(row.isImportable, isFalse);
      expect(row.blockingIssues.first.code, IssueCode.transferNoDestination);
    });
  });

  group('headers', () {
    test('aliases cover a bank statement', () {
      final result = ImportParser.parse(
        'Txn Date,Narration,Withdrawal,Deposit,Account\n'
        '24/08/2026,SWIGGY BANGALORE,450,,HDFC',
      );
      final row = result.rows.single;
      expect(row.payee, 'SWIGGY BANGALORE');
      expect(row.type, TransactionType.expense);
      expect(row.amount, 450);
      expect(row.accountName, 'HDFC');
    });

    test('a parenthesised unit does not stop a column matching', () {
      final header = ImportHeader.read(['Amount (INR)', 'Date (DD/MM)']);
      expect(header.indexOf(ImportField.amount), 0);
      expect(header.indexOf(ImportField.date), 1);
    });

    test('an unknown column is reported, never assigned by position', () {
      final result =
          ImportParser.parse('Date,Amount,Running Balance\n2026-08-24,500,9000');
      expect(result.header.unmapped, [2]);
      expect(
        result.fileWarnings.join(),
        contains('"Running Balance"'),
      );
    });

    test('a duplicated field keeps the first column and says so', () {
      final result = ImportParser.parse(
        'Date,Amount,Note,Memo,Account\n2026-08-24,500,first,second,HDFC',
      );
      expect(result.rows.single.note, 'first');
      expect(result.fileWarnings.join(), contains('Memo'));
    });

    test('a file with no recognisable header is refused outright', () {
      // Importing by position is not offered: two of the ten columns are free
      // text, so a positional read of the wrong file writes notes into Amount.
      expect(
        () => ImportParser.parse('24/08/2026,500,HDFC\n25/08/2026,600,HDFC'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('a file with no amount column is refused outright', () {
      expect(
        () => ImportParser.parse('Date,Account\n2026-08-24,HDFC'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('an empty file is refused outright', () {
      expect(() => ImportParser.parse(''), throwsA(isA<ImportFormatException>()));
    });
  });

  group('row-level complaints', () {
    ParsedRow only(String csv) => ImportParser.parse(csv).rows.single;

    test('a missing account blocks the row', () {
      final row = only('Date,Amount,Account\n2026-08-24,500,');
      expect(row.isImportable, isFalse);
      expect(row.blockingIssues.map((i) => i.code),
          contains(IssueCode.accountMissing));
    });

    test('a missing date is a warning, not a refusal', () {
      final row = only('Date,Amount,Account\n,500,HDFC');
      expect(row.isImportable, isTrue);
      expect(row.warnings.map((i) => i.code), contains(IssueCode.dateMissing));
    });

    test('an unreadable date blocks the row', () {
      final row = only('Date,Amount,Account\nyesterday,500,HDFC');
      expect(row.isImportable, isFalse);
      expect(row.blockingIssues.first.code, IssueCode.dateUnreadable);
    });

    test('an odd currency falls back to INR with a warning', () {
      final row = only('Date,Amount,Currency,Account\n2026-08-24,500,Rupees,HDFC');
      expect(row.currency, 'INR');
      expect(row.isImportable, isTrue);
      expect(row.warnings.map((i) => i.code), contains(IssueCode.currencyOdd));
    });

    test('issues name the line a user can find in their spreadsheet', () {
      final result = ImportParser.parse(
        'Date,Amount,Account\n'
        '2026-08-24,500,HDFC\n'
        '2026-08-25,oops,HDFC\n',
      );
      expect(result.rejected.single.line, 3);
    });

    test('good and bad rows are separated, not all-or-nothing', () {
      final result = ImportParser.parse(
        'Date,Amount,Account\n'
        '2026-08-24,500,HDFC\n'
        '2026-08-25,oops,HDFC\n'
        '2026-08-26,700,HDFC\n',
      );
      expect(result.importable.length, 2);
      expect(result.rejected.length, 1);
    });
  });

  group('the localisation contract', () {
    // 7.1b will swap the preview's `issue.message` for a lookup on
    // `issue.code`. That is only a presentation-layer edit if every issue that
    // quotes a cell also carries that cell as structured `detail` — otherwise
    // a translator's sentence would have to parse the offending text back out
    // of an English string.
    test('an issue that quotes a cell carries it as detail', () {
      final rows = ImportParser.parse(
        'Date,Type,Amount,Currency,Account\n'
        'yesterday,nonsense,oops,Rupees,HDFC',
      ).rows.single.issues;

      String? detailFor(String code) =>
          rows.firstWhere((i) => i.code == code).detail;

      expect(detailFor(IssueCode.dateUnreadable), 'yesterday');
      expect(detailFor(IssueCode.amountUnreadable), 'oops');
      expect(detailFor(IssueCode.currencyOdd), 'RUPEES');
    });

    test('every issue names a code, and the message only echoes it', () {
      final result = ImportParser.parse(
        'Date,Amount,Account\n'
        'yesterday,500,HDFC\n'
        '2026-08-24,0,\n',
      );
      for (final issue in result.rows.expand((r) => r.issues)) {
        expect(issue.code, isNotEmpty);
        expect(issue.message, isNotEmpty);
        if (issue.detail != null) {
          expect(issue.message, contains(issue.detail!));
        }
      }
    });
  });

  group('tags', () {
    test('split on any of the three separators, trimmed and deduped', () {
      expect(ImportParser.parseTags('food;travel'), ['food', 'travel']);
      expect(ImportParser.parseTags('food, travel'), ['food', 'travel']);
      expect(ImportParser.parseTags('food|travel'), ['food', 'travel']);
      expect(ImportParser.parseTags('food; Food ;travel'), ['food', 'travel']);
      expect(ImportParser.parseTags('  '), isEmpty);
    });
  });
}
