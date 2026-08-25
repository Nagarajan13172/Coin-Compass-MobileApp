/// Phase 7.3a — turning cells into candidate transactions.
///
/// This layer is **purely syntactic**. It knows what `24/08/2026` and
/// `(1,234.50)` mean; it does not know whether an account called "HDFC" exists
/// in the signed-in user's data. That resolution is 7.3b's job, and keeping the
/// two apart is what lets every rule below be tested without a network, a
/// session, or a widget.
///
/// The one rule the whole file serves: **never guess in a direction that
/// changes money.** An unreadable amount, an unknown type word and an ambiguous
/// sign are all refusals, not defaults. Guessing income where the file meant
/// expense does not produce a broken row the user notices — it produces a
/// plausible row that silently inverts their net worth.
library;

import '../../../core/api/enums.dart';
import 'csv_table.dart';
import 'import_columns.dart';

/// How a `03/04/2026` should be read.
enum DateOrder {
  /// `03/04/2026` is 3 April. The default: this app ships against an `en_IN`
  /// account, and its own export writes unambiguous ISO anyway.
  dayFirst,

  /// `03/04/2026` is 4 March.
  monthFirst;

  String get label =>
      this == DateOrder.dayFirst ? 'Day first (DD/MM)' : 'Month first (MM/DD)';
}

/// What [ImportParser] concluded about a file's numeric dates.
class DateOrderReading {
  const DateOrderReading({
    required this.order,
    required this.ambiguous,
    required this.conflicting,
  });

  final DateOrder order;

  /// Every numeric date in the file could be read either way — no row had a
  /// component above 12. The chosen [order] is a default, not a deduction, so
  /// the preview must offer to flip it. Silently picking one is how an import
  /// lands twelve months of transactions in the wrong months.
  final bool ambiguous;

  /// The file contains a date that can only be day-first *and* one that can
  /// only be month-first. No single order reads the file correctly; at least
  /// one row is wrong whatever is chosen.
  final bool conflicting;

  /// True when the file settled the question by itself.
  bool get certain => !ambiguous && !conflicting;
}

enum IssueSeverity { warning, blocking }

/// Something wrong with one row, phrased for the user rather than the log.
///
/// ### Why the English lives here, and how 7.1b gets it out
///
/// This is a domain object with no `BuildContext`, so it cannot reach
/// `AppLocalizations`. Rather than thread a localisations instance through a
/// pure parser — which would make every test above need a widget binding —
/// each issue carries **`code` + `field` + `detail`**, which is everything
/// needed to rebuild the sentence in any language. [message] is the English
/// rendering of exactly those three, and the only part 7.1b has to move: the
/// preview swaps `issue.message` for a lookup on `issue.code`, and nothing in
/// this file changes.
///
/// Callers must match on [code], never on [message], so that swap stays a
/// presentation-layer edit.
class RowIssue {
  const RowIssue(
    this.code,
    this.message, {
    this.severity = IssueSeverity.blocking,
    this.field,
    this.detail,
  });

  /// Stable identifier for tests, for the resolver — which clears
  /// [IssueCode.accountMissing] once a default account is chosen — and for the
  /// eventual ARB key.
  final String code;

  /// English, and a fallback. See the class doc.
  final String message;

  final IssueSeverity severity;
  final ImportField? field;

  /// The offending cell text, unquoted, when the message names one. Held apart
  /// from [message] so a translated sentence can interpolate it rather than
  /// having to parse it back out of English.
  final String? detail;

  bool get isBlocking => severity == IssueSeverity.blocking;

  @override
  String toString() => '$code: $message';
}

/// The codes [RowIssue] uses. Named so callers never match on message text.
abstract final class IssueCode {
  static const dateMissing = 'date.missing';
  static const dateUnreadable = 'date.unreadable';
  static const amountMissing = 'amount.missing';
  static const amountUnreadable = 'amount.unreadable';
  static const amountZero = 'amount.zero';
  static const typeUnknown = 'type.unknown';
  static const typeUndecidable = 'type.undecidable';
  static const debitAndCredit = 'amount.debitAndCredit';
  static const accountMissing = 'account.missing';
  static const transferNoDestination = 'transfer.noDestination';
  static const currencyOdd = 'currency.odd';
  static const rowShort = 'row.short';
}

/// One CSV record, read as far as syntax allows.
class ParsedRow {
  ParsedRow({
    required this.line,
    required this.cells,
    required this.issues,
    this.date,
    this.type,
    this.amount,
    this.currency = 'INR',
    this.accountName = '',
    this.toAccountName = '',
    this.categoryName = '',
    this.payee = '',
    this.note = '',
    this.tags = const [],
  });

  /// Spreadsheet gutter line, so an error the user can act on names a row they
  /// can find.
  final int line;

  /// The record verbatim, for showing the offending text next to the complaint.
  final List<String> cells;

  final List<RowIssue> issues;

  final DateTime? date;
  final TransactionType? type;

  /// Always positive when set — the sign lives in [type], the way
  /// `TransactionDraft` expects it.
  final num? amount;

  final String currency;
  final String accountName;
  final String toAccountName;
  final String categoryName;
  final String payee;
  final String note;
  final List<String> tags;

  /// True when nothing syntactic stands in the way of importing this row.
  /// Whether the *names* resolve is a separate question — see 7.3b.
  bool get isImportable => !issues.any((i) => i.isBlocking);

  Iterable<RowIssue> get blockingIssues => issues.where((i) => i.isBlocking);
  Iterable<RowIssue> get warnings =>
      issues.where((i) => i.severity == IssueSeverity.warning);
}

/// What a whole file came to.
class ImportParseResult {
  const ImportParseResult({
    required this.header,
    required this.rows,
    required this.dateOrder,
    required this.delimiter,
    required this.fileWarnings,
  });

  final ImportHeader header;
  final List<ParsedRow> rows;
  final DateOrderReading dateOrder;
  final String delimiter;

  /// Problems with the file as a whole rather than one row — an unterminated
  /// quote, a duplicated column, an unmapped header.
  final List<String> fileWarnings;

  List<ParsedRow> get importable =>
      rows.where((r) => r.isImportable).toList(growable: false);
  List<ParsedRow> get rejected =>
      rows.where((r) => !r.isImportable).toList(growable: false);
}

/// Raised when the file cannot be read at all — as opposed to a file whose
/// individual rows have problems, which is the normal case and is reported
/// per row.
class ImportFormatException implements Exception {
  const ImportFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImportParser {
  const ImportParser._();

  /// Parses raw CSV text.
  ///
  /// [dateOrder] overrides the detected reading — this is what the preview's
  /// "these dates could be either" control sends back after the user chooses.
  static ImportParseResult parse(String source, {DateOrder? dateOrder}) {
    final table = CsvTable.parse(source);
    if (table.isEmpty) {
      throw const ImportFormatException('That file has no rows in it.');
    }

    final headerRow = table.rows.first;
    if (!ImportHeader.looksLikeHeader(headerRow.cells)) {
      throw const ImportFormatException(
        'The first row does not name any columns this app recognises. A CSV '
        'exported from CoinCompass starts with '
        '"Date,Type,Amount,Currency,Account,To Account,Category,Payee,Note,Tags".',
      );
    }

    final header = ImportHeader.read(headerRow.cells);
    final body = table.rows.skip(1).toList(growable: false);

    if (!header.has(ImportField.amount) &&
        !header.has(ImportField.debit) &&
        !header.has(ImportField.credit)) {
      throw const ImportFormatException(
        'That file has no Amount column, so there is nothing to import.',
      );
    }

    final reading = dateOrder == null
        ? detectDateOrder(body, header.indexOf(ImportField.date))
        : DateOrderReading(
            order: dateOrder,
            ambiguous: false,
            conflicting: false,
          );

    final rows = [
      for (final row in body) _parseRow(row, header, reading),
    ];

    return ImportParseResult(
      header: header,
      rows: rows,
      dateOrder: reading,
      delimiter: table.delimiter,
      fileWarnings: _fileWarnings(table, header),
    );
  }

  static List<String> _fileWarnings(CsvTable table, ImportHeader header) {
    final warnings = <String>[];

    if (table.unterminatedQuote) {
      warnings.add(
        'The file ends inside an unclosed quote, so the last rows may be '
        'incomplete. Check the end of the file before importing.',
      );
    }
    if (table.delimiter != ',') {
      final name = switch (table.delimiter) {
        ';' => 'semicolons',
        '\t' => 'tabs',
        '|' => 'pipes',
        _ => 'the "${table.delimiter}" character',
      };
      warnings.add('Columns are separated by $name, not commas.');
    }
    for (final entry in header.duplicates.entries) {
      final ignored = entry.value
          .map((i) => '"${header.names[i]}"')
          .join(', ');
      warnings.add(
        '${entry.key.label} is named by more than one column; '
        'using "${header.names[header.indexOf(entry.key)!]}" and ignoring $ignored.',
      );
    }
    if (header.unmapped.isNotEmpty) {
      final names = header.unmapped.map((i) => '"${header.names[i]}"').join(', ');
      warnings.add('These columns have nowhere to go and will be skipped: $names.');
    }
    return warnings;
  }

  // ── the row ────────────────────────────────────────────────────────────────

  static ParsedRow _parseRow(
    CsvRow row,
    ImportHeader header,
    DateOrderReading reading,
  ) {
    final issues = <RowIssue>[];
    String cell(ImportField f) {
      final index = header.indexOf(f);
      return index == null ? '' : row[index].trim();
    }

    if (row.cells.length < header.names.length - header.unmapped.length) {
      issues.add(const RowIssue(
        IssueCode.rowShort,
        'This row has fewer columns than the header; the missing ones are '
        'treated as blank.',
        severity: IssueSeverity.warning,
      ));
    }

    // date
    DateTime? date;
    final dateText = cell(ImportField.date);
    if (!header.has(ImportField.date) || dateText.isEmpty) {
      issues.add(const RowIssue(
        IssueCode.dateMissing,
        'No date, so this row would be filed under today.',
        severity: IssueSeverity.warning,
        field: ImportField.date,
      ));
    } else {
      date = parseDate(dateText, reading.order);
      if (date == null) {
        issues.add(RowIssue(
          IssueCode.dateUnreadable,
          '"$dateText" is not a date this app can read.',
          field: ImportField.date,
          detail: dateText,
        ));
      }
    }

    // amount + type, which are decided together
    final money = _readMoney(cell, header, issues);

    // currency
    var currency = cell(ImportField.currency).toUpperCase();
    if (currency.isEmpty) {
      currency = 'INR';
    } else if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      issues.add(RowIssue(
        IssueCode.currencyOdd,
        '"$currency" is not a three-letter currency code; using INR.',
        severity: IssueSeverity.warning,
        field: ImportField.currency,
        detail: currency,
      ));
      currency = 'INR';
    }

    final accountName = cell(ImportField.account);
    if (accountName.isEmpty) {
      issues.add(const RowIssue(
        IssueCode.accountMissing,
        'No account named. Every transaction has to belong to one.',
        field: ImportField.account,
      ));
    }

    final toAccountName = cell(ImportField.toAccount);
    if (money.type == TransactionType.transfer && toAccountName.isEmpty) {
      issues.add(const RowIssue(
        IssueCode.transferNoDestination,
        'A transfer needs a destination account.',
        field: ImportField.toAccount,
      ));
    }

    return ParsedRow(
      line: row.line,
      cells: row.cells,
      issues: issues,
      date: date,
      type: money.type,
      amount: money.amount,
      currency: currency,
      accountName: accountName,
      toAccountName: toAccountName,
      categoryName: cell(ImportField.category),
      payee: cell(ImportField.payee),
      note: cell(ImportField.note),
      tags: parseTags(cell(ImportField.tags)),
    );
  }

  /// Amount and type, resolved together because neither is decidable alone.
  ///
  /// **Magnitude** comes from `Amount` if the file has one, otherwise from
  /// whichever of `Debit`/`Credit` is filled in.
  ///
  /// **Direction** is taken from the first of these the file can answer:
  ///
  ///  1. **An explicit `Type` column** — the app's own export. The amount's
  ///     sign is then redundant and is discarded, so a file that writes
  ///     expenses as `-500` and one that writes them as `500` import the same.
  ///  2. **Which of `Debit`/`Credit` is filled** — the bank-statement shape,
  ///     where position carries the sign.
  ///  3. **The sign of `Amount`** — negative is an expense, positive is income.
  ///     There is no third reading available this way, so a transfer is never
  ///     inferred from a sign.
  ///
  /// The three are separate because files mix them: `Type,Debit,Credit` has no
  /// Amount column at all, and reading direction and magnitude from the same
  /// branch used to make that file import as "no amount on any row".
  static ({num? amount, TransactionType? type}) _readMoney(
    String Function(ImportField) cell,
    ImportHeader header,
    List<RowIssue> issues,
  ) {
    final amountText = cell(ImportField.amount);
    final signed = amountText.isEmpty ? null : parseAmount(amountText);
    if (amountText.isNotEmpty && signed == null) {
      issues.add(RowIssue(
        IssueCode.amountUnreadable,
        '"$amountText" is not an amount this app can read.',
        field: ImportField.amount,
        detail: amountText,
      ));
      return (amount: null, type: null);
    }

    final debit = parseAmount(cell(ImportField.debit));
    final credit = parseAmount(cell(ImportField.credit));
    final hasDebit = debit != null && debit != 0;
    final hasCredit = credit != null && credit != 0;

    // ── magnitude ──
    final num? magnitude = signed?.abs() ??
        (hasDebit ? debit.abs() : (hasCredit ? credit.abs() : null));

    if (magnitude == 0) {
      issues.add(const RowIssue(
        IssueCode.amountZero,
        'The amount is zero.',
        field: ImportField.amount,
      ));
      return (amount: null, type: null);
    }
    if (magnitude == null) {
      // An explicit `0` in Debit or Credit is a row the user can fix; a blank
      // one may just be a stray line the blank-row filter did not catch. A zero
      // in `Amount` cannot reach here — it is a magnitude of 0, caught above.
      final sawZero = debit == 0 || credit == 0;
      issues.add(RowIssue(
        sawZero ? IssueCode.amountZero : IssueCode.amountMissing,
        sawZero ? 'The amount is zero.' : 'No amount on this row.',
        field: ImportField.amount,
      ));
      return (amount: null, type: null);
    }

    // ── direction ──
    if (header.has(ImportField.type)) {
      final typeText = cell(ImportField.type);
      final type = parseType(typeText);
      if (typeText.isEmpty) {
        issues.add(const RowIssue(
          IssueCode.typeUnknown,
          'No type. Say income, expense or transfer.',
          field: ImportField.type,
        ));
      } else if (type == null) {
        issues.add(RowIssue(
          IssueCode.typeUnknown,
          '"$typeText" is not income, expense or transfer.',
          field: ImportField.type,
          detail: typeText,
        ));
      }
      return (amount: magnitude, type: type);
    }

    if (hasDebit && hasCredit) {
      issues.add(const RowIssue(
        IssueCode.debitAndCredit,
        'This row has both a debit and a credit, so which way the money moved '
        'is not clear.',
      ));
      return (amount: magnitude, type: null);
    }
    if (hasDebit) return (amount: magnitude, type: TransactionType.expense);
    if (hasCredit) return (amount: magnitude, type: TransactionType.income);

    if (signed != null) {
      return (
        amount: magnitude,
        type: signed < 0 ? TransactionType.expense : TransactionType.income,
      );
    }

    issues.add(const RowIssue(
      IssueCode.typeUndecidable,
      'Nothing in this row says whether the money came in or went out.',
    ));
    return (amount: magnitude, type: null);
  }

  // ── values ─────────────────────────────────────────────────────────────────

  static const Map<String, TransactionType> _typeWords = {
    'income': TransactionType.income,
    'in': TransactionType.income,
    'credit': TransactionType.income,
    'cr': TransactionType.income,
    'deposit': TransactionType.income,
    'inflow': TransactionType.income,
    'received': TransactionType.income,
    'expense': TransactionType.expense,
    'out': TransactionType.expense,
    'debit': TransactionType.expense,
    'dr': TransactionType.expense,
    'withdrawal': TransactionType.expense,
    'outflow': TransactionType.expense,
    'spend': TransactionType.expense,
    'spent': TransactionType.expense,
    'paid': TransactionType.expense,
    'payment': TransactionType.expense,
    'transfer': TransactionType.transfer,
    'transferred': TransactionType.transfer,
    'move': TransactionType.transfer,
    'movement': TransactionType.transfer,
  };

  /// `Expense`, `EXPENSE`, `debit`, `Transfer` → the enum; anything else null.
  ///
  /// Deliberately **not** `TransactionType.fromApi`, which maps every
  /// unrecognised value to `expense`. That tolerance is right for a server
  /// response — a new server-side type must not crash the app — and wrong here,
  /// where the unrecognised value is the user's own file and quietly calling it
  /// an expense inverts the sign on their money.
  static TransactionType? parseType(String raw) =>
      _typeWords[raw.trim().toLowerCase()];

  /// Splits a tag cell on any of `;`, `,` and `|`.
  ///
  /// The app's export writes them into one quoted cell; which separator it uses
  /// is not worth depending on, and none of the three is legal inside a tag.
  static List<String> parseTags(String raw) {
    if (raw.trim().isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[;,|]'))) {
      final tag = part.trim();
      if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
      out.add(tag);
    }
    return List.unmodifiable(out);
  }

  static final RegExp _parenNegative = RegExp(r'^\((.*)\)$');
  static final RegExp _notNumeric = RegExp(r'[^0-9.,\-]');

  /// `₹1,23,456.78` → 123456.78; `(500)` → -500; `−500` → -500.
  ///
  /// ### Which separator is the decimal point
  ///
  /// `1.234` is one-point-two-three-four to an Indian or American writer and
  /// one thousand two hundred and thirty-four to a German one. Getting it wrong
  /// is a 1000× error on a real amount, so the ambiguity is resolved from
  /// evidence rather than a guess:
  ///
  ///  * **Both separators present** — unambiguous. `1.234,56` and `1,234.56`
  ///    each have exactly one reading: the *last* separator is the decimal
  ///    point and the other is grouping.
  ///  * **One separator, and spaces group the thousands** — `1 234,56`. The
  ///    spaces are doing the grouping, so the remaining mark can only be the
  ///    decimal point whichever character it is.
  ///  * **One separator, nothing else to go on** — `,` is grouping and `.` is
  ///    the decimal point, the convention this app's own export and its `en_IN`
  ///    locale both use. A European file is not assumed, because assuming it
  ///    would corrupt the far more likely case.
  ///
  /// A `;`-delimited file is a strong hint of a European locale, but the hint
  /// lives at the file level and this function is per-cell; the mixed case
  /// above already covers the common European amount, which writes both.
  static num? parseAmount(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    var negative = false;

    // Accounting parentheses, before anything strips the brackets.
    final parens = _parenNegative.firstMatch(text);
    if (parens != null) {
      negative = true;
      text = parens.group(1)!.trim();
    }

    // A real minus sign (U+2212) is what this app itself renders.
    text = text.replaceAll('−', '-');

    // A space between two digits is a *grouping* separator — nobody writes a
    // decimal point as a space. That is real evidence about the other marks in
    // the same number: if the thousands are already grouped by spaces, a lone
    // `,` or `.` can only be the decimal point. `1 234,56` is 1234.56, not
    // 123456. Captured before the spaces are stripped, which destroys it.
    final spaceGrouped = RegExp(r'\d[\s\u00a0\u202f]\d').hasMatch(text);
    text = text.replaceAll(RegExp(r'[\s\u00a0\u202f]'), '');

    // Currency symbols, codes, and stray marks. Whatever is left must be
    // digits, separators and a sign — anything else means this was not a
    // number and must not be read as one.
    final stripped = text.replaceAll(_notNumeric, '');
    if (stripped.isEmpty) return null;

    // A trailing sign (`500-`, the way some statements mark a debit).
    var body = stripped;
    if (body.endsWith('-')) {
      negative = !negative;
      body = body.substring(0, body.length - 1);
    }
    if (body.startsWith('-')) {
      negative = !negative;
      body = body.substring(1);
    }
    // Any sign left in the middle is not a number.
    if (body.contains('-') || body.isEmpty) return null;

    final lastDot = body.lastIndexOf('.');
    final lastComma = body.lastIndexOf(',');

    String normalised;
    if (lastDot >= 0 && lastComma >= 0) {
      final decimalAt = lastDot > lastComma ? lastDot : lastComma;
      final grouping = lastDot > lastComma ? ',' : '.';
      normalised =
          '${body.substring(0, decimalAt).replaceAll(grouping, '')}.${body.substring(decimalAt + 1)}';
    } else if (lastComma >= 0) {
      // Spaces already did the grouping, so this comma is the decimal point.
      normalised = spaceGrouped
          ? body.replaceAll(',', '.')
          : body.replaceAll(',', '');
    } else {
      normalised = body;
    }

    // More than one point left means it was never a single number.
    if ('.'.allMatches(normalised).length > 1) return null;

    final value = num.tryParse(normalised);
    if (value == null) return null;
    return negative ? -value : value;
  }

  static const List<String> _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  static final RegExp _numericDate =
      RegExp(r'^(\d{1,4})[/\-.](\d{1,2})[/\-.](\d{1,4})$');
  static final RegExp _textualDayFirst =
      RegExp(r'^(\d{1,2})[\s\-/]+([A-Za-z]{3,})[\s\-/,]+(\d{2,4})$');
  static final RegExp _textualMonthFirst =
      RegExp(r'^([A-Za-z]{3,})[\s\-/]+(\d{1,2})[\s\-/,]+(\d{2,4})$');

  /// Reads the date formats a CSV actually carries, in this order:
  ///
  ///  1. **ISO** (`2026-08-24`, `2026-08-24T10:30:00Z`) — what this app
  ///     exports, and never ambiguous.
  ///  2. **Textual month** (`24 Aug 2026`, `Aug 24, 2026`, `24-Aug-26`) — a
  ///     bank statement staple, and also never ambiguous.
  ///  3. **All-numeric** (`24/08/2026`) — ambiguous, and read according to
  ///     [order], which the caller derives from the whole file.
  ///
  /// Returns a local midnight; the time of day a statement carries is not
  /// something this app records.
  static DateTime? parseDate(String raw, DateOrder order) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // ISO first — but only when it really looks ISO. `DateTime.tryParse`
    // accepts `2026` alone as a year, which would turn a stray "2026" in a
    // reference column into 1 January.
    if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}').hasMatch(text)) {
      final iso = DateTime.tryParse(text);
      if (iso != null) {
        final local = iso.isUtc ? iso.toLocal() : iso;
        return DateTime(local.year, local.month, local.day);
      }
    }

    final dayFirstText = _textualDayFirst.firstMatch(text);
    if (dayFirstText != null) {
      return _build(
        day: int.parse(dayFirstText.group(1)!),
        month: _monthFromName(dayFirstText.group(2)!),
        year: int.parse(dayFirstText.group(3)!),
      );
    }

    final monthFirstText = _textualMonthFirst.firstMatch(text);
    if (monthFirstText != null) {
      return _build(
        day: int.parse(monthFirstText.group(2)!),
        month: _monthFromName(monthFirstText.group(1)!),
        year: int.parse(monthFirstText.group(3)!),
      );
    }

    final numeric = _numericDate.firstMatch(text);
    if (numeric == null) return null;
    final a = int.parse(numeric.group(1)!);
    final b = int.parse(numeric.group(2)!);
    final c = int.parse(numeric.group(3)!);

    // `2026/08/24` — a four-digit leading group can only be the year.
    if (numeric.group(1)!.length == 4) {
      return _build(day: c, month: b, year: a);
    }
    return order == DateOrder.dayFirst
        ? _build(day: a, month: b, year: c)
        : _build(day: b, month: a, year: c);
  }

  static int? _monthFromName(String raw) {
    final key = raw.toLowerCase();
    for (var i = 0; i < _months.length; i++) {
      if (key.startsWith(_months[i])) return i + 1;
    }
    return null;
  }

  /// Builds a date only when the parts are a real calendar day.
  ///
  /// `DateTime(2026, 13, 45)` does not throw in Dart, it rolls over into 2027 —
  /// which would turn an unreadable date into a confidently wrong one. Every
  /// component is therefore range-checked first.
  static DateTime? _build({required int day, int? month, required int year}) {
    if (month == null || month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;

    final fullYear = _expandYear(year);
    if (fullYear == null) return null;

    final date = DateTime(fullYear, month, day);
    // Catches 31 February, which would otherwise roll into March.
    if (date.month != month || date.day != day) return null;
    return date;
  }

  /// `26` → 2026, `99` → 1999.
  ///
  /// The pivot is 70, the POSIX convention. A finance app's data does not
  /// reach back to the 1970s, so the choice only ever matters for a typo, and
  /// a wrong century is far more visible than a wrong decade.
  static int? _expandYear(int year) {
    if (year >= 100) return year >= 1000 ? year : null;
    return year < 70 ? 2000 + year : 1900 + year;
  }

  // ── file-level date order ──────────────────────────────────────────────────

  /// Works out whether a file's numeric dates are day-first or month-first by
  /// looking for a component that can only be one thing.
  ///
  /// A single `13/04/2026` settles the whole file: there is no thirteenth
  /// month, so the first component is the day. Only when *no* row contains such
  /// a tell is the file genuinely ambiguous — and then the answer is a flagged
  /// default rather than a silent one, because being wrong shifts up to eleven
  /// months of the user's history into the wrong months.
  static DateOrderReading detectDateOrder(List<CsvRow> body, int? dateColumn) {
    if (dateColumn == null) {
      return const DateOrderReading(
        order: DateOrder.dayFirst,
        ambiguous: false,
        conflicting: false,
      );
    }

    var dayFirstOnly = false;
    var monthFirstOnly = false;
    var sawNumeric = false;

    for (final row in body) {
      final match = _numericDate.firstMatch(row[dateColumn].trim());
      if (match == null) continue;
      // A four-digit lead is an ISO-ish `2026/08/24`; it says nothing about the
      // order of the other two, which are then unambiguously month then day.
      if (match.group(1)!.length == 4) continue;

      sawNumeric = true;
      final a = int.parse(match.group(1)!);
      final b = int.parse(match.group(2)!);
      if (a > 12) dayFirstOnly = true;
      if (b > 12) monthFirstOnly = true;
    }

    if (dayFirstOnly && monthFirstOnly) {
      return const DateOrderReading(
        order: DateOrder.dayFirst,
        ambiguous: false,
        conflicting: true,
      );
    }
    if (dayFirstOnly) {
      return const DateOrderReading(
        order: DateOrder.dayFirst,
        ambiguous: false,
        conflicting: false,
      );
    }
    if (monthFirstOnly) {
      return const DateOrderReading(
        order: DateOrder.monthFirst,
        ambiguous: false,
        conflicting: false,
      );
    }
    // No numeric dates at all is not ambiguity — there is nothing to be
    // ambiguous about, and flagging it would put a control on the preview that
    // changes nothing.
    return DateOrderReading(
      order: DateOrder.dayFirst,
      ambiguous: sawNumeric,
      conflicting: false,
    );
  }
}
