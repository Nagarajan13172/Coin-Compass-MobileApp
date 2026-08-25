/// Phase 7.3a — deciding what each column in someone's CSV *is*.
///
/// The guaranteed case is a round-trip of this app's own export, whose header
/// is fixed (`ExportRepository`):
///
///     Date,Type,Amount,Currency,Account,To Account,Category,Payee,Note,Tags
///
/// Everything past that is a convenience for files from a bank or another
/// tracker, so the matching is deliberately shallow: normalise the header text
/// and look it up. There is no fuzzy matching and no positional guessing —
/// a header this table does not recognise is reported as unmapped and the user
/// is told, rather than being silently assigned to whichever column happened to
/// sit at that index. Guessing wrong here does not fail, it files the amount
/// under Currency.
library;

/// Every column the importer can consume.
enum ImportField {
  date,
  type,
  amount,
  currency,
  account,
  toAccount,
  category,
  payee,
  note,
  tags,

  /// Bank statements overwhelmingly ship two signed-by-position columns
  /// instead of a `Type`. They are read only when [type] is absent — see
  /// `ImportParser`.
  debit,
  credit;

  /// What the preview calls this column.
  String get label => switch (this) {
    ImportField.date => 'Date',
    ImportField.type => 'Type',
    ImportField.amount => 'Amount',
    ImportField.currency => 'Currency',
    ImportField.account => 'Account',
    ImportField.toAccount => 'To Account',
    ImportField.category => 'Category',
    ImportField.payee => 'Payee',
    ImportField.note => 'Note',
    ImportField.tags => 'Tags',
    ImportField.debit => 'Debit',
    ImportField.credit => 'Credit',
  };
}

/// Header text → field.
///
/// Two judgement calls worth stating, because both are arguable:
///
///  * **`description` and `narration` map to Payee, not Note.** They are the
///    "what was this" column of an Indian bank statement, and `Transaction.title`
///    renders payee first. Sending them to Note would leave every imported row
///    titled by its category, which is what the list already groups by — the
///    user would scroll a screen of identical titles.
///  * **Only explicitly note-ish words map to Note** (`note`, `memo`, `remark`,
///    `comment`), so a file carrying both a description and a memo keeps them
///    in separate fields instead of one overwriting the other.
const Map<String, ImportField> _aliases = {
  'date': ImportField.date,
  'transactiondate': ImportField.date,
  'txndate': ImportField.date,
  'valuedate': ImportField.date,
  'postingdate': ImportField.date,
  'posted': ImportField.date,
  'when': ImportField.date,

  'type': ImportField.type,
  'transactiontype': ImportField.type,
  'txntype': ImportField.type,
  'kind': ImportField.type,
  'direction': ImportField.type,

  'amount': ImportField.amount,
  'value': ImportField.amount,
  'sum': ImportField.amount,
  'total': ImportField.amount,

  'currency': ImportField.currency,
  'ccy': ImportField.currency,
  'currencycode': ImportField.currency,

  'account': ImportField.account,
  'fromaccount': ImportField.account,
  'sourceaccount': ImportField.account,
  'from': ImportField.account,
  'source': ImportField.account,
  'wallet': ImportField.account,

  'toaccount': ImportField.toAccount,
  'destinationaccount': ImportField.toAccount,
  'destination': ImportField.toAccount,
  'to': ImportField.toAccount,
  'transferto': ImportField.toAccount,

  'category': ImportField.category,
  'categories': ImportField.category,
  'subcategory': ImportField.category,

  'payee': ImportField.payee,
  'merchant': ImportField.payee,
  'description': ImportField.payee,
  'narration': ImportField.payee,
  'particulars': ImportField.payee,
  'details': ImportField.payee,
  'counterparty': ImportField.payee,

  'note': ImportField.note,
  'notes': ImportField.note,
  'memo': ImportField.note,
  'remark': ImportField.note,
  'remarks': ImportField.note,
  'comment': ImportField.note,
  'comments': ImportField.note,

  'tags': ImportField.tags,
  'tag': ImportField.tags,
  'labels': ImportField.tags,

  'debit': ImportField.debit,
  'withdrawal': ImportField.debit,
  'withdrawals': ImportField.debit,
  'moneyout': ImportField.debit,
  'paidout': ImportField.debit,
  'dr': ImportField.debit,

  'credit': ImportField.credit,
  'deposit': ImportField.credit,
  'deposits': ImportField.credit,
  'moneyin': ImportField.credit,
  'paidin': ImportField.credit,
  'cr': ImportField.credit,
};

/// The result of reading the header row.
class ImportHeader {
  const ImportHeader({
    required this.columns,
    required this.names,
    required this.unmapped,
    required this.duplicates,
  });

  /// field → column index. A field absent from this map is absent from the file.
  final Map<ImportField, int> columns;

  /// The header row exactly as written, for showing the user what was read.
  final List<String> names;

  /// Column indices whose header matched nothing. Not an error — a bank export
  /// carries a running balance and a reference number this app has nowhere to
  /// put — but the preview names them so "why is my Balance column missing?"
  /// has a visible answer.
  final List<int> unmapped;

  /// Fields named by more than one column, e.g. both `Note` and `Memo`. The
  /// **first** wins; the rest land here so the preview can say which column was
  /// ignored instead of the user wondering why half their data vanished.
  final Map<ImportField, List<int>> duplicates;

  bool has(ImportField field) => columns.containsKey(field);
  int? indexOf(ImportField field) => columns[field];

  /// Reads [names] as a header row.
  factory ImportHeader.read(List<String> names) {
    final columns = <ImportField, int>{};
    final unmapped = <int>[];
    final duplicates = <ImportField, List<int>>{};

    for (var i = 0; i < names.length; i++) {
      final field = _aliases[normalise(names[i])];
      if (field == null) {
        // A wholly empty header cell is a spreadsheet artefact, not a column
        // the user meant to include; reporting it as unmapped is noise.
        if (names[i].trim().isNotEmpty) unmapped.add(i);
        continue;
      }
      if (columns.containsKey(field)) {
        duplicates.putIfAbsent(field, () => <int>[]).add(i);
        continue;
      }
      columns[field] = i;
    }

    return ImportHeader(
      columns: columns,
      names: List.unmodifiable(names),
      unmapped: List.unmodifiable(unmapped),
      duplicates: Map.unmodifiable(duplicates),
    );
  }

  /// Would this row plausibly be a header rather than data?
  ///
  /// Used to tell "the file has no header row" from "the file has a header this
  /// table does not know". Importing a headerless file by position is not
  /// offered: two of the ten columns are free text, so a positional read of the
  /// wrong file writes notes into the amount column silently.
  static bool looksLikeHeader(List<String> cells) {
    var matched = 0;
    for (final cell in cells) {
      if (_aliases.containsKey(normalise(cell))) matched++;
    }
    // Two is enough: the narrowest file worth importing is Date + Amount.
    return matched >= 2;
  }

  /// `"  To Account "` → `toaccount`; `"Amount (INR)"` → `amount`.
  ///
  /// Two steps, and the order matters:
  ///
  ///  1. **Drop parenthesised trailers.** Headers carry their unit in
  ///     brackets far too often — `Amount (INR)`, `Debit (₹)`, `Date (DD/MM)` —
  ///     and folding the unit into the key would need one alias per currency.
  ///     The bracket content is never the column's identity.
  ///  2. **Strip every remaining non-alphanumeric**, which is what lets one
  ///     alias cover `To Account`, `to_account` and `TO-ACCOUNT`.
  ///
  /// A header still unrecognised after both is reported unmapped rather than
  /// mis-assigned: no entry, no match, no guess.
  static String normalise(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}
