/// Phase 7.3b — turning the *names* in a file into ids in this user's account.
///
/// A CSV says `HDFC Bank` and `Food`. `POST /transactions` wants
/// `account: "66f1…"` and `category: "66f2…"`. Nothing in the file can bridge
/// that, so every distinct name has to be matched against what the user already
/// has, and whatever fails to match has to become a decision the user makes
/// **before** anything is written.
///
/// ### Why nothing is auto-created
///
/// Auto-creating an unmatched name is one line of code and the wrong trade: a
/// typo'd `HDFC Bnak` in row 400 of a file the user did not write silently adds
/// a permanent account to their real finances, and they find out weeks later
/// when a balance does not reconcile. Every creation here is something the user
/// asked for by name in the preview.
///
/// ### Why matching stops at case and spacing
///
/// `HDFC` and `HDFC Bank` are different accounts to the user and similar
/// strings to an algorithm. Fuzzy matching would file transactions against the
/// wrong account without ever asking — the same failure as auto-creating, in
/// the opposite direction. So the ladder is short and total: exact, then
/// case-and-spacing-insensitive, then *ask*.
///
/// This layer is still offline and still pure. It takes the accounts and
/// categories as plain lists, so the whole of it is testable without a session.
library;

import '../../../core/api/enums.dart';
import '../../accounts/domain/account.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/transaction.dart';
import 'import_parser.dart';

enum RefKind { account, category }

enum _RefStateKind { resolved, pending, skipped, undecided }

/// Where one reference stands right now. See `ImportPlan._stateOf`.
class _RefState {
  const _RefState.resolved(this.id) : kind = _RefStateKind.resolved;
  const _RefState.pending() : kind = _RefStateKind.pending, id = null;
  const _RefState.skipped() : kind = _RefStateKind.skipped, id = null;
  const _RefState.undecided() : kind = _RefStateKind.undecided, id = null;

  final _RefStateKind kind;
  final String? id;
}

/// How confidently a name in the file was tied to an existing record.
enum MatchStrength {
  /// The name is character-for-character what the user has.
  exact,

  /// Matched after folding case and collapsing whitespace — `hdfc bank`
  /// against `HDFC Bank`. Reported so the preview can show what it did.
  normalised,

  /// Nothing matched. Needs a decision.
  none,
}

/// What the user decided about one unmatched name.
sealed class RefDecision {
  const RefDecision();
}

/// Point every row using this name at a record the user already has.
class UseExisting extends RefDecision {
  const UseExisting(this.id);
  final String id;
}

/// Create the record, then use it. Nothing is created until the import runs.
class CreateNew extends RefDecision {
  const CreateNew();
}

/// Leave the name unresolved on purpose.
///
/// For a **category** this imports the rows without one, which is a legitimate
/// transaction — the app renders an uncategorised row fine. For an **account**
/// it excludes the rows, because the API has no such thing as a transaction
/// without an account.
class SkipRef extends RefDecision {
  const SkipRef();
}

/// One distinct name the file refers to.
class NameRef {
  const NameRef({
    required this.kind,
    required this.name,
    required this.lines,
    required this.strength,
    this.categoryType,
    this.matchedId,
    this.matchedName,
  });

  final RefKind kind;

  /// As first written in the file — what the preview shows, so the user
  /// recognises their own data.
  final String name;

  /// Categories are typed on this backend, so `Food` as an expense and `Food`
  /// as an income category are two different records. Null for accounts.
  final CategoryType? categoryType;

  /// Spreadsheet lines using this name, in file order. Drives the preview's
  /// "used by 34 rows" and lets the user jump to one.
  final List<int> lines;

  final MatchStrength strength;
  final String? matchedId;

  /// The existing record's name, which differs from [name] whenever
  /// [strength] is [MatchStrength.normalised].
  final String? matchedName;

  bool get isMatched => matchedId != null;
  int get rowCount => lines.length;

  /// Stable identity for the decision map. Categories key on type as well as
  /// name, so deciding about expense-`Food` does not silently decide about
  /// income-`Food` too.
  String get key => kind == RefKind.category
      ? 'category:${categoryType!.api}:${ImportPlan.fold(name)}'
      : 'account:${ImportPlan.fold(name)}';

  NameRef copyWith({MatchStrength? strength, String? matchedId, String? matchedName}) =>
      NameRef(
        kind: kind,
        name: name,
        categoryType: categoryType,
        lines: lines,
        strength: strength ?? this.strength,
        matchedId: matchedId ?? this.matchedId,
        matchedName: matchedName ?? this.matchedName,
      );
}

enum RowStatus {
  /// Everything resolves; this row will be written.
  ready,

  /// Something is still wrong or undecided. Reported, never written.
  blocked,

  /// Deliberately left out, by a [SkipRef] on its account.
  skipped,
}

/// One row, as the plan currently sees it.
class PlannedRow {
  const PlannedRow({
    required this.row,
    required this.status,
    required this.reasons,
    this.draft,
  });

  final ParsedRow row;
  final RowStatus status;

  /// Why it is not [RowStatus.ready], phrased for the preview. Empty when it is.
  final List<String> reasons;

  /// The body that would be POSTed.
  ///
  /// Null while [status] is ready but some account or category it needs is
  /// still only *promised* — the user chose "create it" and the record does not
  /// exist yet. `ImportRunner` creates those first and re-reads the plan, so by
  /// the time it writes, every ready row has a draft.
  final TransactionDraft? draft;

  int get line => row.line;
}

/// A parsed file plus every decision made about it so far.
///
/// Immutable: each choice returns a new plan, so a Riverpod notifier can hold
/// one and the preview can rebuild from it without a mutable object escaping.
class ImportPlan {
  const ImportPlan({
    required this.parse,
    required this.refs,
    required this.decisions,
    required this.createdIds,
    this.fallbackAccountId,
  });

  final ImportParseResult parse;

  /// Every distinct name in the file, accounts first, then categories, each
  /// group in first-appearance order — the order they appear in the file, which
  /// is the order the user will scan for them.
  final List<NameRef> refs;

  /// [NameRef.key] → what the user chose. A key absent here has not been
  /// decided; an auto-matched ref never needs an entry.
  final Map<String, RefDecision> decisions;

  /// [NameRef.key] → the id a [CreateNew] actually got, filled in by the commit
  /// step once the record exists. Empty until then.
  final Map<String, String> createdIds;

  /// Used for rows whose Account cell is blank. Null means those rows stay
  /// blocked — which is the honest default, since guessing an account is
  /// guessing whose money moved.
  final String? fallbackAccountId;

  /// Builds the initial plan: match every name, decide nothing.
  factory ImportPlan.from({
    required ImportParseResult parse,
    required List<Account> accounts,
    required List<Category> categories,
  }) {
    return ImportPlan(
      parse: parse,
      refs: _collectRefs(parse.rows, accounts, categories),
      decisions: const {},
      createdIds: const {},
    );
  }

  // ── the user's choices ────────────────────────────────────────────────────

  ImportPlan decide(String refKey, RefDecision decision) => _copy(
    decisions: {...decisions, refKey: decision},
  );

  ImportPlan withFallbackAccount(String? id) =>
      _copy(fallbackAccountId: id, clearFallback: id == null);

  /// Records the ids the commit step created, which turns every [CreateNew]
  /// into a resolvable reference.
  ImportPlan withCreatedIds(Map<String, String> ids) =>
      _copy(createdIds: {...createdIds, ...ids});

  ImportPlan _copy({
    List<NameRef>? refs,
    Map<String, RefDecision>? decisions,
    Map<String, String>? createdIds,
    String? fallbackAccountId,
    bool clearFallback = false,
  }) => ImportPlan(
    parse: parse,
    refs: refs ?? this.refs,
    decisions: decisions ?? this.decisions,
    createdIds: createdIds ?? this.createdIds,
    fallbackAccountId:
        clearFallback ? null : (fallbackAccountId ?? this.fallbackAccountId),
  );

  // ── what still needs answering ────────────────────────────────────────────

  /// Names that matched nothing and have no decision yet. The preview cannot
  /// let the import run while this is non-empty.
  List<NameRef> get undecided => refs
      .where((r) => !r.isMatched && !decisions.containsKey(r.key))
      .toList(growable: false);

  /// Rows whose Account cell was blank, which [fallbackAccountId] answers.
  int get rowsNeedingFallbackAccount => parse.rows
      .where((r) => r.accountName.isEmpty && !_hasNonAccountBlocker(r))
      .length;

  bool get needsFallbackAccount =>
      fallbackAccountId == null && rowsNeedingFallbackAccount > 0;

  /// Everything the commit step has to create before it can write a single
  /// transaction, in the order the preview listed it.
  List<NameRef> get pendingCreations => refs
      .where((r) => decisions[r.key] is CreateNew && !createdIds.containsKey(r.key))
      .toList(growable: false);

  bool get isReadyToImport => undecided.isEmpty && ready.isNotEmpty;

  // ── the rows ──────────────────────────────────────────────────────────────

  List<PlannedRow> get plannedRows =>
      parse.rows.map(_plan).toList(growable: false);

  List<PlannedRow> get ready =>
      plannedRows.where((r) => r.status == RowStatus.ready).toList(growable: false);

  List<PlannedRow> get blocked =>
      plannedRows.where((r) => r.status == RowStatus.blocked).toList(growable: false);

  List<PlannedRow> get skipped =>
      plannedRows.where((r) => r.status == RowStatus.skipped).toList(growable: false);

  PlannedRow _plan(ParsedRow row) {
    final reasons = <String>[];

    // Syntactic refusals stand, with one exception: a blank Account cell is
    // answered by the fallback the user picked, so it is not counted here.
    for (final issue in row.blockingIssues) {
      if (issue.code == IssueCode.accountMissing && fallbackAccountId != null) {
        continue;
      }
      reasons.add(issue.message);
    }

    // True when some reference is settled but has no id yet, because the user
    // asked for it to be created. The row is importable; its draft simply
    // cannot be built until the run creates the record.
    var awaitingCreation = false;

    String? accountId;
    if (row.accountName.isEmpty) {
      // Blank Account cell. Either the fallback answers it, or the parser's own
      // `account.missing` issue is already in `reasons` above.
      accountId = fallbackAccountId;
    } else {
      final state = _stateOf(_refFor(RefKind.account, row.accountName, null));
      switch (state.kind) {
        case _RefStateKind.skipped:
          return PlannedRow(
            row: row,
            status: RowStatus.skipped,
            reasons: ['Skipped: the account "${row.accountName}" is not being imported.'],
          );
        case _RefStateKind.resolved:
          accountId = state.id;
        case _RefStateKind.pending:
          awaitingCreation = true;
        case _RefStateKind.undecided:
          reasons.add('The account "${row.accountName}" has not been matched yet.');
      }
    }

    String? toAccountId;
    if (row.toAccountName.isNotEmpty) {
      final state = _stateOf(_refFor(RefKind.account, row.toAccountName, null));
      switch (state.kind) {
        case _RefStateKind.skipped:
          return PlannedRow(
            row: row,
            status: RowStatus.skipped,
            reasons: [
              'Skipped: the destination account "${row.toAccountName}" is not being imported.',
            ],
          );
        case _RefStateKind.resolved:
          toAccountId = state.id;
        case _RefStateKind.pending:
          awaitingCreation = true;
        case _RefStateKind.undecided:
          reasons.add(
            'The destination account "${row.toAccountName}" has not been matched yet.',
          );
      }
    }

    // A category is optional on this API, so an unresolved one never blocks a
    // row — it imports uncategorised, which the app renders correctly and the
    // user can fix in bulk afterwards. Blocking here would turn one unfamiliar
    // category name into a hundred rows the user cannot import.
    String? categoryId;
    if (row.categoryName.isNotEmpty && row.type != null) {
      final state = _stateOf(
        _refFor(RefKind.category, row.categoryName, _categoryTypeFor(row.type!)),
      );
      if (state.kind == _RefStateKind.resolved) categoryId = state.id;
      if (state.kind == _RefStateKind.pending) awaitingCreation = true;
    }

    final missingAccount = accountId == null && !awaitingCreation;
    if (reasons.isNotEmpty ||
        missingAccount ||
        row.type == null ||
        row.amount == null) {
      if (reasons.isEmpty) reasons.add('This row is missing something required.');
      return PlannedRow(row: row, status: RowStatus.blocked, reasons: reasons);
    }

    // Settled, but not yet buildable: the ids arrive when the run creates the
    // records. `ImportRunner` re-reads `ready` after its creation pass, by
    // which point every draft here is non-null.
    if (awaitingCreation) {
      return PlannedRow(row: row, status: RowStatus.ready, reasons: const []);
    }

    return PlannedRow(
      row: row,
      status: RowStatus.ready,
      reasons: const [],
      draft: TransactionDraft(
        type: row.type!,
        amount: row.amount!,
        accountId: accountId!,
        toAccountId: toAccountId,
        categoryId: categoryId,
        date: row.date,
        note: row.note.isEmpty ? null : row.note,
        payee: row.payee.isEmpty ? null : row.payee,
        tags: row.tags,
        currency: row.currency,
      ),
    );
  }

  bool _hasNonAccountBlocker(ParsedRow row) =>
      row.blockingIssues.any((i) => i.code != IssueCode.accountMissing);

  /// Where a reference currently stands.
  ///
  /// The distinction that matters is between **undecided** and **pending** — a
  /// name the user has asked to create is settled as far as the preview is
  /// concerned, even though its id will not exist until the run starts. Folding
  /// the two together is what made the preview say "Nothing to import" the
  /// moment the user tapped "Create it".
  _RefState _stateOf(NameRef? ref) {
    if (ref == null) return const _RefState.undecided();
    if (ref.isMatched) return _RefState.resolved(ref.matchedId!);
    final decision = decisions[ref.key];
    if (decision is UseExisting) return _RefState.resolved(decision.id);
    if (decision is SkipRef) return const _RefState.skipped();
    if (decision is CreateNew) {
      final id = createdIds[ref.key];
      return id == null ? const _RefState.pending() : _RefState.resolved(id);
    }
    return const _RefState.undecided();
  }

  NameRef? _refFor(RefKind kind, String name, CategoryType? type) {
    final folded = fold(name);
    for (final ref in refs) {
      if (ref.kind != kind) continue;
      if (fold(ref.name) != folded) continue;
      if (kind == RefKind.category && ref.categoryType != type) continue;
      return ref;
    }
    return null;
  }

  /// A transfer has no income/expense sense, so its category — if a file even
  /// carries one — is matched as an expense, which is what the app's own
  /// transfer form offers.
  static CategoryType _categoryTypeFor(TransactionType type) =>
      type == TransactionType.income ? CategoryType.income : CategoryType.expense;

  // ── matching ──────────────────────────────────────────────────────────────

  /// `  HDFC   Bank ` → `hdfc bank`.
  ///
  /// Case and runs of whitespace only. Punctuation is deliberately kept: an
  /// account called `Amex (Gold)` and one called `Amex Gold` are two records a
  /// user might really have, and folding them together would file the wrong
  /// one's transactions without asking.
  static String fold(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static List<NameRef> _collectRefs(
    List<ParsedRow> rows,
    List<Account> accounts,
    List<Category> categories,
  ) {
    // Insertion-ordered, so the preview lists names in the order the file
    // introduces them.
    final accountLines = <String, List<int>>{};
    final accountNames = <String, String>{};
    final categoryLines = <String, List<int>>{};
    final categoryNames = <String, String>{};
    final categoryTypes = <String, CategoryType>{};

    void noteAccount(String name, int line) {
      if (name.isEmpty) return;
      final key = fold(name);
      accountNames.putIfAbsent(key, () => name.trim());
      accountLines.putIfAbsent(key, () => <int>[]).add(line);
    }

    for (final row in rows) {
      noteAccount(row.accountName, row.line);
      noteAccount(row.toAccountName, row.line);

      if (row.categoryName.isEmpty || row.type == null) continue;
      final type = _categoryTypeFor(row.type!);
      final key = '${type.api}:${fold(row.categoryName)}';
      categoryNames.putIfAbsent(key, () => row.categoryName.trim());
      categoryTypes.putIfAbsent(key, () => type);
      categoryLines.putIfAbsent(key, () => <int>[]).add(row.line);
    }

    final refs = <NameRef>[];

    for (final entry in accountLines.entries) {
      final name = accountNames[entry.key]!;
      final match = _matchAccount(name, accounts);
      refs.add(NameRef(
        kind: RefKind.account,
        name: name,
        lines: List.unmodifiable(entry.value),
        strength: match.strength,
        matchedId: match.id,
        matchedName: match.name,
      ));
    }

    for (final entry in categoryLines.entries) {
      final name = categoryNames[entry.key]!;
      final type = categoryTypes[entry.key]!;
      final match = _matchCategory(name, type, categories);
      refs.add(NameRef(
        kind: RefKind.category,
        name: name,
        categoryType: type,
        lines: List.unmodifiable(entry.value),
        strength: match.strength,
        matchedId: match.id,
        matchedName: match.name,
      ));
    }

    return List.unmodifiable(refs);
  }

  /// Exact, then folded. Archived accounts are matchable — a file of last
  /// year's transactions legitimately names an account since closed — but an
  /// active account of the same name always wins.
  static ({String? id, String? name, MatchStrength strength}) _matchAccount(
    String name,
    List<Account> accounts,
  ) {
    final live = accounts.where((a) => !a.archived).toList(growable: false);
    for (final pool in [live, accounts]) {
      for (final account in pool) {
        if (account.name == name) {
          return (id: account.id, name: account.name, strength: MatchStrength.exact);
        }
      }
      for (final account in pool) {
        if (fold(account.name) == fold(name)) {
          return (
            id: account.id,
            name: account.name,
            strength: MatchStrength.normalised,
          );
        }
      }
    }
    return (id: null, name: null, strength: MatchStrength.none);
  }

  static ({String? id, String? name, MatchStrength strength}) _matchCategory(
    String name,
    CategoryType type,
    List<Category> categories,
  ) {
    final typed = categories.where((c) => c.type == type).toList(growable: false);
    for (final category in typed) {
      if (category.name == name) {
        return (id: category.id, name: category.name, strength: MatchStrength.exact);
      }
    }
    for (final category in typed) {
      if (fold(category.name) == fold(name)) {
        return (
          id: category.id,
          name: category.name,
          strength: MatchStrength.normalised,
        );
      }
    }
    return (id: null, name: null, strength: MatchStrength.none);
  }
}
