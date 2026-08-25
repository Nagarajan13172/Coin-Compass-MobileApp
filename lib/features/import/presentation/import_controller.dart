/// Phase 7.3c — the state machine behind the import screen.
///
/// The whole point of the flow is that **nothing is written until the user has
/// seen what will be written**, so the states are deliberately linear and the
/// only edge into [ImportRunning] is an explicit tap on a button that names the
/// row count.
///
///     idle ──pick──▶ preview ──run──▶ running ──▶ done
///       ▲               │                          │
///       └───────────────┴─────── reset ────────────┘
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/data/accounts_repository.dart';
import '../../categories/data/categories_repository.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../data/csv_file_source.dart';
import '../data/import_runner.dart';
import '../domain/import_parser.dart';
import '../domain/import_plan.dart';

sealed class ImportState {
  const ImportState();
}

class ImportIdle extends ImportState {
  const ImportIdle();
}

/// Reading or parsing. Short, but a 20,000-row file is not instant and the
/// screen must not look frozen.
class ImportBusy extends ImportState {
  const ImportBusy(this.label);
  final String label;
}

/// The file is parsed and the user is deciding. Everything reversible.
class ImportPreview extends ImportState {
  const ImportPreview({required this.file, required this.plan});
  final PickedCsv file;
  final ImportPlan plan;
}

class ImportRunning extends ImportState {
  const ImportRunning({required this.progress, required this.cancelling});
  final ImportProgress progress;
  final bool cancelling;
}

class ImportDone extends ImportState {
  const ImportDone({required this.outcome, required this.fileName});
  final ImportOutcome outcome;
  final String fileName;
}

/// The file could not be used at all — as opposed to a file whose rows have
/// problems, which is [ImportPreview] with a list of them.
class ImportFailed extends ImportState {
  const ImportFailed(this.message);
  final String message;
}

class ImportController extends StateNotifier<ImportState> {
  ImportController(this._ref) : super(const ImportIdle());

  final Ref _ref;

  /// Kept so [setDateOrder] can re-parse without asking for the file again.
  PickedCsv? _file;
  bool _cancelRequested = false;

  /// Opens the picker, parses what comes back, and matches its names.
  Future<void> pick() async {
    state = const ImportBusy('Reading the file…');
    try {
      final picked = await _ref.read(csvPickerProvider)();
      if (picked == null) {
        // The user backed out. Returning to idle rather than to an error keeps
        // the screen where it was.
        state = const ImportIdle();
        return;
      }
      _file = picked;
      _buildPreview(picked, null);
    } on CsvPickException catch (error) {
      state = ImportFailed(error.message);
    } on ImportFormatException catch (error) {
      state = ImportFailed(error.message);
    } catch (error) {
      state = ImportFailed('That file could not be read: $error');
    }
  }

  /// Re-reads the file with the dates the other way round.
  ///
  /// A full re-parse rather than a patch: the order changes what every date
  /// cell *means*, and half of them can flip between valid and impossible
  /// (`31/05` is a date one way round and nothing at all the other).
  void setDateOrder(DateOrder order) {
    final file = _file;
    if (file == null) return;
    final previous = state;
    try {
      _buildPreview(file, order);
      // Decisions survive the re-parse: they are keyed by name, and changing
      // how dates are read cannot change which accounts the file mentions.
      if (previous is ImportPreview && state is ImportPreview) {
        var plan = (state as ImportPreview).plan;
        for (final entry in previous.plan.decisions.entries) {
          plan = plan.decide(entry.key, entry.value);
        }
        if (previous.plan.fallbackAccountId != null) {
          plan = plan.withFallbackAccount(previous.plan.fallbackAccountId);
        }
        state = ImportPreview(file: file, plan: plan);
      }
    } on ImportFormatException catch (error) {
      state = ImportFailed(error.message);
    }
  }

  void _buildPreview(PickedCsv file, DateOrder? order) {
    final parsed = ImportParser.parse(file.text, dateOrder: order);
    state = ImportPreview(
      file: file,
      plan: ImportPlan.from(
        parse: parsed,
        accounts: _ref.read(accountsProvider).valueOrNull ?? const [],
        categories: _ref.read(categoriesProvider).valueOrNull ?? const [],
      ),
    );
  }

  void decide(String refKey, RefDecision decision) {
    final current = state;
    if (current is! ImportPreview) return;
    state = ImportPreview(
      file: current.file,
      plan: current.plan.decide(refKey, decision),
    );
  }

  void setFallbackAccount(String? accountId) {
    final current = state;
    if (current is! ImportPreview) return;
    state = ImportPreview(
      file: current.file,
      plan: current.plan.withFallbackAccount(accountId),
    );
  }

  /// The one method that writes. Everything before it is reversible.
  ///
  /// [container] comes from the screen, captured *before* it awaits this.
  /// `invalidateTransactionDerived` takes a container rather than a `Ref` for
  /// exactly this reason: a long import that the user navigates away from must
  /// still refresh the dashboard and the balances it changed.
  Future<void> run(ProviderContainer container) async {
    final current = state;
    if (current is! ImportPreview) return;
    if (!current.plan.isReadyToImport) return;

    _cancelRequested = false;
    state = ImportRunning(
      progress: ImportProgress(
        stage: ImportStage.creating,
        done: 0,
        total: current.plan.pendingCreations.length,
      ),
      cancelling: false,
    );

    final outcome = await _ref.read(importRunnerProvider).run(
      current.plan,
      onProgress: (progress) {
        if (!mounted) return;
        state = ImportRunning(progress: progress, cancelling: _cancelRequested);
      },
      isCancelled: () => _cancelRequested,
    );

    // Whatever happened, rows may have been written — a cancelled run and a
    // failed one both leave real transactions behind, so the refresh is
    // unconditional.
    if (outcome.written > 0 ||
        outcome.createdAccounts.isNotEmpty ||
        outcome.createdCategories.isNotEmpty) {
      // Every write path in this app goes through this helper, so an import
      // cannot drift out of sync with what a single manual add refreshes.
      invalidateTransactionDerived(container, tags: true);
      container.invalidate(categoriesFetchProvider);
    }

    if (!mounted) return;
    state = ImportDone(outcome: outcome, fileName: current.file.name);
  }

  /// Asks the run to stop at the next row boundary. It cannot un-write what is
  /// already written, and the outcome says so.
  void cancel() {
    _cancelRequested = true;
    final current = state;
    if (current is ImportRunning) {
      state = ImportRunning(progress: current.progress, cancelling: true);
    }
  }

  void reset() {
    _file = null;
    _cancelRequested = false;
    state = const ImportIdle();
  }
}

final importControllerProvider =
    StateNotifierProvider.autoDispose<ImportController, ImportState>(
      (ref) => ImportController(ref),
    );
