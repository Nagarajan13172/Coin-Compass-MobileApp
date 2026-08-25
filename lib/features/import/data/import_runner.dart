/// Phase 7.3c — the only part of the importer that writes anything.
///
/// Everything up to here is offline and reversible. This file is not, so the
/// rules it follows are about damage control rather than convenience:
///
///  * **Sequential, never parallel.** `/auth` is rate-limited and the rest of
///    the deployment is one small Node process. Firing 800 concurrent POSTs at
///    it is how an import turns into an outage, and the failures it produced
///    would be indistinguishable from real rejections.
///  * **No retries.** A failed POST may still have created the row — a timeout
///    says nothing about what the server did. Retrying is how one flaky row
///    becomes two identical transactions, so a failure is reported and left
///    alone.
///  * **Creations first, and a failed creation aborts before any transaction
///    is written.** At that point nothing but the accounts and categories the
///    user asked for exists, so the user can fix the problem and re-run: the
///    records created on the first attempt now match by name, and the second
///    run creates only what is left.
///  * **A run of consecutive failures stops the import.** An expired session or
///    a 500 makes *every* remaining row fail; without this the app would spend
///    four minutes hammering a backend that is already unhappy, and hand back
///    800 identical errors instead of one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/enums.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../categories/data/categories_repository.dart';
import '../../transactions/data/transactions_repository.dart';
import '../domain/import_plan.dart';

/// Progress, pushed as each row lands so the sheet can count up.
class ImportProgress {
  const ImportProgress({
    required this.stage,
    required this.done,
    required this.total,
    this.written = 0,
    this.failed = 0,
  });

  final ImportStage stage;

  /// How many units of [stage] have been attempted.
  final int done;
  final int total;

  final int written;
  final int failed;

  double get fraction => total == 0 ? 0 : done / total;
}

enum ImportStage { creating, writing, refreshing }

/// One row that did not make it, named by the line the user can find.
class ImportFailure {
  const ImportFailure({
    required this.line,
    required this.message,
    this.payee = '',
  });

  final int line;
  final String message;

  /// Whatever the row called itself, so the report reads like the user's data
  /// rather than a list of line numbers.
  final String payee;
}

/// What a run came to. Always returned, including when the run stopped early —
/// the caller has to be able to say exactly what was written.
class ImportOutcome {
  const ImportOutcome({
    required this.written,
    required this.failures,
    required this.createdAccounts,
    required this.createdCategories,
    required this.stopped,
    this.stopReason,
  });

  final int written;
  final List<ImportFailure> failures;

  /// Names, in creation order — the report tells the user exactly what was
  /// added to their account, because they will want to check it.
  final List<String> createdAccounts;
  final List<String> createdCategories;

  /// True when the run ended before it reached the last row: cancelled, or
  /// stopped by the consecutive-failure guard, or aborted by a failed
  /// creation. Whatever was already written stays written.
  final bool stopped;
  final String? stopReason;

  bool get isClean => failures.isEmpty && !stopped;
}

/// Stops after this many failures in a row. Five is enough to distinguish a
/// patch of bad rows from a backend that is refusing everything.
const int _consecutiveFailureLimit = 5;

class ImportRunner {
  /// Positional, matching every other repository in this app
  /// (`ExportRepository(this._api)`). The three types are distinct, so a
  /// mis-ordered call is a compile error rather than a runtime surprise.
  const ImportRunner(this._transactions, this._accounts, this._categories);

  final TransactionsRepository _transactions;
  final AccountsRepository _accounts;
  final CategoriesRepository _categories;

  /// Runs [plan] against the live backend.
  ///
  /// [isCancelled] is polled between rows — cancelling stops the run cleanly at
  /// a row boundary. It cannot un-write what is already written, and the
  /// outcome says so.
  Future<ImportOutcome> run(
    ImportPlan plan, {
    void Function(ImportProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final createdAccounts = <String>[];
    final createdCategories = <String>[];
    var current = plan;

    // ── 1. creations ───────────────────────────────────────────────────────
    final pending = plan.pendingCreations;
    for (var i = 0; i < pending.length; i++) {
      final ref = pending[i];
      onProgress?.call(ImportProgress(
        stage: ImportStage.creating,
        done: i,
        total: pending.length,
      ));

      if (isCancelled?.call() ?? false) {
        return ImportOutcome(
          written: 0,
          failures: const [],
          createdAccounts: createdAccounts,
          createdCategories: createdCategories,
          stopped: true,
          stopReason: 'Cancelled before any transaction was imported.',
        );
      }

      try {
        if (ref.kind == RefKind.account) {
          final account = await _accounts.create({
            'name': ref.name,
            'type': AccountType.bank.api,
          });
          current = current.withCreatedIds({ref.key: account.id});
          createdAccounts.add(account.name);
        } else {
          final category = await _categories.create({
            'name': ref.name,
            'type': ref.categoryType!.api,
          });
          current = current.withCreatedIds({ref.key: category.id});
          createdCategories.add(category.name);
        }
      } catch (error) {
        // Nothing but these records exists yet, so stopping here leaves the
        // account in a state the user can simply re-run from.
        return ImportOutcome(
          written: 0,
          failures: const [],
          createdAccounts: createdAccounts,
          createdCategories: createdCategories,
          stopped: true,
          stopReason:
              'Could not create ${ref.kind == RefKind.account ? 'the account' : 'the category'} '
              '"${ref.name}": ${_messageFor(error)}. Nothing was imported.',
        );
      }
    }

    // ── 2. the rows ────────────────────────────────────────────────────────
    final rows = current.ready;
    final failures = <ImportFailure>[];
    var written = 0;
    var consecutiveFailures = 0;
    String? stopReason;

    for (var i = 0; i < rows.length; i++) {
      if (isCancelled?.call() ?? false) {
        stopReason = 'Cancelled after $written of ${rows.length} rows. '
            'What was already imported has been kept.';
        break;
      }

      final planned = rows[i];
      onProgress?.call(ImportProgress(
        stage: ImportStage.writing,
        done: i,
        total: rows.length,
        written: written,
        failed: failures.length,
      ));

      // Every ready row has a draft once the creation pass above has filled in
      // the ids. A null here would mean a reference the plan believed settled
      // never got one — report it as a failed row rather than crashing the
      // import half way through and leaving the user with no report at all.
      final draft = planned.draft;
      if (draft == null) {
        failures.add(ImportFailure(
          line: planned.line,
          message: 'An account or category this row needs was never created.',
          payee: planned.row.payee,
        ));
        continue;
      }

      try {
        await _transactions.create(draft);
        written++;
        consecutiveFailures = 0;
      } catch (error) {
        failures.add(ImportFailure(
          line: planned.line,
          message: _messageFor(error),
          payee: planned.row.payee,
        ));
        consecutiveFailures++;
        if (consecutiveFailures >= _consecutiveFailureLimit) {
          stopReason =
              'Stopped after $_consecutiveFailureLimit rows in a row failed — '
              'something is wrong with the connection or the session rather '
              'than with the file. $written of ${rows.length} rows were '
              'imported before that.';
          break;
        }
      }
    }

    onProgress?.call(ImportProgress(
      stage: ImportStage.refreshing,
      done: rows.length,
      total: rows.length,
      written: written,
      failed: failures.length,
    ));

    return ImportOutcome(
      written: written,
      failures: failures,
      createdAccounts: createdAccounts,
      createdCategories: createdCategories,
      stopped: stopReason != null,
      stopReason: stopReason,
    );
  }

  /// The app renders `error.message` everywhere; a raw `DioException` reaching
  /// the report would print a stack trace at the owner.
  static String _messageFor(Object error) => error is ApiException
      ? error.message
      : ApiException.from(error).message;
}

final importRunnerProvider = Provider<ImportRunner>(
  (ref) => ImportRunner(
    ref.watch(transactionsRepositoryProvider),
    ref.watch(accountsRepositoryProvider),
    ref.watch(categoriesRepositoryProvider),
  ),
);
