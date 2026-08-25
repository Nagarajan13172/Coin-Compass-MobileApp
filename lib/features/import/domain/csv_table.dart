/// A field-level CSV reader for phase 7.3.
///
/// ## Why this is hand-written and not a regex or a `split(',')`
///
/// The app's own export writes `Date,Type,Amount,Currency,Account,To Account,
/// Category,Payee,Note,Tags` — and two of those columns routinely carry the
/// delimiter inside the value. A note reading `Lunch, then fuel` and a tag list
/// reading `"food,travel"` both survive a spreadsheet round-trip only because
/// the writer quoted them. `split(',')` tears exactly those rows apart and
/// shifts every later column left, so the amount lands in `Currency` and the
/// row imports as garbage rather than failing loudly.
///
/// So this walks the source one character at a time, tracking quote state, and
/// implements RFC 4180 plus the three deviations real files actually have:
///
///  * **a UTF-8 BOM** — Excel writes one on every "CSV UTF-8" save. Left in
///    place it becomes part of the first header name, so `Date` never matches
///    and the whole file reads as headerless.
///  * **mixed line endings** — `\r\n` from Windows, `\n` from the server,
///    a bare `\r` from very old Mac exports. All three end a record.
///  * **a non-comma delimiter** — a machine with a European locale exports
///    `;`-separated from the same spreadsheet. See [sniffDelimiter].
///
/// Nothing here knows what a transaction is; it turns bytes into cells and
/// records where each one came from. Meaning is [ImportParser]'s job.
library;

/// One record, plus where it started in the file.
class CsvRow {
  const CsvRow({required this.cells, required this.line});

  final List<String> cells;

  /// 1-based **physical** line the record began on — what a spreadsheet's row
  /// gutter shows, which is the only line number a user can act on. It is not
  /// the record index: a quoted note containing a newline spans several lines,
  /// after which the two diverge for the rest of the file.
  final int line;

  /// Empty-safe accessor — a short row (fewer cells than the header) reads as
  /// blank rather than throwing. Real files are ragged: trailing empty columns
  /// are frequently dropped by the writer.
  String operator [](int index) =>
      index >= 0 && index < cells.length ? cells[index] : '';

  bool get isBlank => cells.every((c) => c.trim().isEmpty);

  @override
  String toString() => 'CsvRow($line: ${cells.join('|')})';
}

class CsvTable {
  const CsvTable({
    required this.rows,
    required this.delimiter,
    required this.unterminatedQuote,
  });

  /// Every record in file order, blank lines already dropped. A blank line is
  /// not a record: writers emit one before EOF, and users leave them between
  /// blocks. Keeping them would produce a row of empty cells that fails
  /// validation and reads to the user as a phantom error on a line that looks
  /// fine in their spreadsheet.
  final List<CsvRow> rows;

  /// Which delimiter was actually used — surfaced so the preview can say
  /// "read as semicolon-separated" instead of silently mis-parsing.
  final String delimiter;

  /// True when the file ended inside an open quote. The rows parsed so far are
  /// still returned (they are usually fine; the damage is at the tail), but the
  /// caller should warn: everything after the stray `"` was swallowed into one
  /// field, so the row count is short and the last row is wrong.
  final bool unterminatedQuote;

  bool get isEmpty => rows.isEmpty;

  /// Candidates in preference order. Comma first so it wins a tie — it is what
  /// this app exports, and the format's own name.
  static const List<String> _candidates = [',', ';', '\t', '|'];

  /// Picks the delimiter by counting each candidate **outside quotes** in the
  /// first non-empty line.
  ///
  /// Counting inside quotes is what makes the naive version wrong: the header
  /// `Date,Type,"Amount; net",Tags` has one `;` and three `,`, but a scan that
  /// ignores quoting on a row like `"a;b;c;d",x` sees four semicolons and one
  /// comma and switches the whole file to `;`. Only the header is measured,
  /// because it is the one line guaranteed to be free-text-free.
  static String sniffDelimiter(String source) {
    final header = _firstNonEmptyLine(_stripBom(source));
    if (header.isEmpty) return ',';

    var best = ',';
    var bestCount = 0;
    for (final candidate in _candidates) {
      final count = _countOutsideQuotes(header, candidate);
      if (count > bestCount) {
        best = candidate;
        bestCount = count;
      }
    }
    return best;
  }

  /// Parses [source], sniffing the delimiter unless one is given.
  static CsvTable parse(String source, {String? delimiter}) {
    final text = _stripBom(source);
    final delim = delimiter ?? sniffDelimiter(text);
    final scan = _scan(text, delim);
    return CsvTable(
      rows: scan.rows.where((r) => !r.isBlank).toList(growable: false),
      delimiter: delim,
      unterminatedQuote: scan.unterminatedQuote,
    );
  }

  /// U+FEFF, written by Excel on every "CSV UTF-8" save. Only ever leads the
  /// file; a FEFF anywhere else is real content and is left alone.
  static String _stripBom(String s) =>
      s.startsWith('﻿') ? s.substring(1) : s;

  static String _firstNonEmptyLine(String s) {
    for (final line in s.split(RegExp(r'\r\n|\r|\n'))) {
      if (line.trim().isNotEmpty) return line;
    }
    return '';
  }

  static int _countOutsideQuotes(String line, String needle) {
    var count = 0;
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        quoted = !quoted;
        continue;
      }
      if (!quoted && ch == needle) count++;
    }
    return count;
  }

  static ({List<CsvRow> rows, bool unterminatedQuote}) _scan(
    String src,
    String delim,
  ) {
    final rows = <CsvRow>[];
    var cells = <String>[];
    final field = StringBuffer();
    var quoted = false;
    // Distinguishes a row that ended with an empty *field* (`a,b,`) from one
    // that never started. Without it the trailing empty column is dropped and
    // the row silently loses its last cell.
    var sawField = false;
    var line = 1;
    var rowLine = 1;
    var i = 0;

    void endField() {
      cells.add(field.toString());
      field.clear();
      sawField = false;
    }

    void endRow() {
      endField();
      rows.add(CsvRow(cells: cells, line: rowLine));
      cells = <String>[];
    }

    while (i < src.length) {
      final ch = src[i];

      if (quoted) {
        if (ch == '"') {
          // `""` inside a quoted field is one literal quote.
          if (i + 1 < src.length && src[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          quoted = false;
          i++;
          continue;
        }
        // Newlines are ordinary characters inside quotes, but still advance the
        // line counter so later rows report the right gutter number.
        if (ch == '\n') line++;
        if (ch == '\r') {
          line++;
          if (i + 1 < src.length && src[i + 1] == '\n') {
            field.write('\r\n');
            i += 2;
            continue;
          }
        }
        field.write(ch);
        i++;
        continue;
      }

      if (ch == '"') {
        quoted = true;
        sawField = true;
        i++;
        continue;
      }
      if (ch == delim) {
        endField();
        i++;
        continue;
      }
      if (ch == '\n' || ch == '\r') {
        endRow();
        if (ch == '\r' && i + 1 < src.length && src[i + 1] == '\n') {
          i += 2;
        } else {
          i++;
        }
        line++;
        rowLine = line;
        continue;
      }

      field.write(ch);
      sawField = true;
      i++;
    }

    // Final record, when the file does not end in a newline.
    if (field.isNotEmpty || cells.isNotEmpty || sawField || quoted) {
      endRow();
    }

    return (rows: rows, unterminatedQuote: quoted);
  }
}
