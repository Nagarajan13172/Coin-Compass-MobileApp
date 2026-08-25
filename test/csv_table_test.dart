import 'package:coincompass/features/import/domain/csv_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.3a — the lexer, pinned against the rows that break `split(',')`.**
///
/// Every case here is a shape the app's own export can produce, or one a
/// spreadsheet produces on the way back in. A parser that mis-reads its input
/// is worse than none: it does not fail, it writes the wrong transaction.
void main() {
  List<List<String>> cellsOf(String src) =>
      CsvTable.parse(src).rows.map((r) => r.cells).toList();

  group('records and cells', () {
    test('reads a plain table', () {
      expect(cellsOf('Date,Type\n2026-08-24,expense'), [
        ['Date', 'Type'],
        ['2026-08-24', 'expense'],
      ]);
    });

    test('keeps a trailing empty column', () {
      // `a,b,` is three cells. Dropping the last one shifts nothing here, but
      // on a 10-column export it means Tags silently becomes Note's value.
      expect(cellsOf('a,b,'), [
        ['a', 'b', ''],
      ]);
    });

    test('keeps interior empty columns', () {
      expect(cellsOf('a,,c'), [
        ['a', '', 'c'],
      ]);
    });

    test('drops blank lines rather than reporting phantom rows', () {
      expect(cellsOf('a,b\n\n\nc,d\n'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('does not invent a row for the trailing newline', () {
      expect(cellsOf('a,b\n').length, 1);
    });
  });

  group('quoting', () {
    test('a quoted field keeps its delimiter', () {
      expect(cellsOf('Note,Amount\n"Lunch, then fuel",500'), [
        ['Note', 'Amount'],
        ['Lunch, then fuel', '500'],
      ]);
    });

    test('"" is one literal quote', () {
      expect(cellsOf('a\n"He said ""hi"""'), [
        ['a'],
        ['He said "hi"'],
      ]);
    });

    test('a quoted field keeps an embedded newline', () {
      final rows = CsvTable.parse('Note,Amount\n"line one\nline two",500').rows;
      expect(rows.length, 2);
      expect(rows[1].cells[0], 'line one\nline two');
    });

    test('an embedded CRLF is normalised to itself, not split', () {
      final rows = CsvTable.parse('a\n"x\r\ny"').rows;
      expect(rows.length, 2);
      expect(rows[1].cells[0], 'x\r\ny');
    });

    test('an unterminated quote is reported, not thrown', () {
      final table = CsvTable.parse('a,b\n"never closed,500');
      expect(table.unterminatedQuote, isTrue);
      expect(table.rows.first.cells, ['a', 'b']);
    });

    test('a well-formed file reports no quote damage', () {
      expect(CsvTable.parse('a,b\n"x",y').unterminatedQuote, isFalse);
    });
  });

  group('line endings and the BOM', () {
    test('CRLF, LF and a bare CR all end a record', () {
      expect(cellsOf('a,b\r\nc,d\ne,f\rg,h'), [
        ['a', 'b'],
        ['c', 'd'],
        ['e', 'f'],
        ['g', 'h'],
      ]);
    });

    test('a leading BOM is stripped so the first header still matches', () {
      // Excel's "CSV UTF-8" save. Left in, the header reads "﻿Date" and
      // the whole file parses as headerless.
      expect(CsvTable.parse('﻿Date,Type').rows.first.cells.first, 'Date');
    });

    test('a FEFF that is not leading is content', () {
      expect(CsvTable.parse('a,﻿b').rows.first.cells[1], '﻿b');
    });
  });

  group('line numbers', () {
    test('report the spreadsheet gutter, not the record index', () {
      // The quoted note spans lines 2-3, so the next record is on line 4 even
      // though it is only the third record.
      final rows = CsvTable.parse('Date,Note\n2026-01-01,"a\nb"\n2026-01-02,c').rows;
      expect(rows.map((r) => r.line), [1, 2, 4]);
    });

    test('survive blank lines', () {
      final rows = CsvTable.parse('a\n\n\nd').rows;
      expect(rows.map((r) => r.line), [1, 4]);
    });
  });

  group('delimiter sniffing', () {
    test('defaults to comma', () {
      expect(CsvTable.sniffDelimiter('Date,Type,Amount'), ',');
    });

    test('detects a semicolon export', () {
      expect(CsvTable.sniffDelimiter('Date;Type;Amount'), ';');
      expect(cellsOf('Date;Type\n2026-08-24;expense'), [
        ['Date', 'Type'],
        ['2026-08-24', 'expense'],
      ]);
    });

    test('detects a tab export', () {
      expect(CsvTable.sniffDelimiter('Date\tType\tAmount'), '\t');
    });

    test('ignores delimiters inside quotes when sniffing', () {
      // Three real commas, one quoted semicolon. Counting inside quotes would
      // flip the entire file to `;` and collapse every row to one cell.
      expect(CsvTable.sniffDelimiter('Date,Type,"Amount; net",Tags'), ',');
    });

    test('an explicit delimiter overrides the sniff', () {
      expect(CsvTable.parse('a;b', delimiter: ',').rows.first.cells, ['a;b']);
    });

    test('a single-column file is comma-separated', () {
      expect(CsvTable.sniffDelimiter('Date'), ',');
    });
  });

  group('degenerate input', () {
    test('an empty file has no rows', () {
      expect(CsvTable.parse('').isEmpty, isTrue);
      expect(CsvTable.parse('\n\n\n').isEmpty, isTrue);
    });

    test('a short row reads blank past its end rather than throwing', () {
      final row = CsvTable.parse('a,b,c\nx').rows[1];
      expect(row[0], 'x');
      expect(row[5], '');
      expect(row[-1], '');
    });
  });
}
