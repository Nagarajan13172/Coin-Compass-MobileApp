/// Phase 6.4 — **one** mechanism for optimistic writes.
///
/// Phase 4 had to reconcile four screens that had each invented their own money
/// formatting. This file exists so the same thing does not happen with mutation
/// handling: there is one apply/rollback/report path, and every collection that
/// wants optimism wires itself to it in three lines.
///
/// ## The shape, and why it fits Riverpod 2.6.1 without codegen
///
/// `@riverpod`, `Notifier` and `AsyncNotifier` are all banned here, which leaves
/// `Provider` and `StateNotifierProvider` as the only state primitives — and
/// `StateNotifierProvider` is exactly what `transactionsListProvider` already
/// is. So the mechanism is a `StateNotifier` that is **generic over the row
/// type** and takes two injected functions ([IdOf], [RowOrder]) instead of a
/// generated class per entity. No build_runner, no new idiom, one file.
///
/// Three parts:
///
///  1. [PendingWrite] — a pure `List<T> -> List<T>` plus a unique [token].
///     Two variants: [UpsertWrite] and [RemoveWrite].
///  2. [PendingWrites] — the immutable, ordered set of entries for one
///     collection. [PendingWrites.applyTo] folds them over the server list.
///     **With no entries it returns the base `AsyncValue` object itself**, so a
///     screen with no write in flight is byte-for-byte what it was before this
///     phase — loading, error, `isRefreshing` and 6.3's stale banner included.
///  3. [OptimisticCollection] — the notifier, with exactly one public entry
///     point, [OptimisticCollection.run].
///
/// ## Rollback is exact by construction
///
/// The base list is never mutated. What a screen sees is
/// `entries.fold(base, apply)` — a pure function of (server list, ordered
/// entries). Rolling back is removing **one token** and letting the fold re-run,
/// so there is no partially-reverted state to leave behind, no captured
/// snapshot to go stale, and no refetch papering over the failure. A failed
/// write does not clear 6.3's response cache (`_sendWrite` clears only on
/// success), so a "rollback by refetch" would fall back to a cached body and
/// present the owner's superseded rows as current. Local removal is exact,
/// instant, and costs no request.
///
/// The one exception is `TIMEOUT`: the client cannot know whether the write
/// landed, so the entry is dropped **and** the base is refetched, and the
/// server's answer stands.
///
/// ## This file knows nothing about HTTP
///
/// No `ApiClient`, no `Endpoints`, no request body. [OptimisticCollection.run]
/// takes closures: the `send` closure is whatever repository call the sheet was
/// already making, so every write body keeps being built where
/// `test/write_schema_test.dart` reads it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';

/// Every sentence this phase says after a rollback begins with this, and
/// `ApiException.offlineWriteMessage` — which 6.3 wrote — already does. 6.3's
/// wording is the parent of 6.4's, not a sibling.
const String kNotSavedPrefix = 'Not saved — ';

/// How long a rollback message stays up. Long enough to read and to reach the
/// action; a silent rollback is the failure mode this phase exists to prevent.
const Duration kRollbackSnackDuration = Duration(seconds: 6);

/// Pulls the stable identity out of a row. Every collection has one; none of
/// them spell it the same way, so it is injected.
typedef IdOf<T> = String Function(T row);

/// Where an upserted row belongs relative to its neighbours. Null means "leave
/// the server's order alone and replace in place", which is what every
/// collection here uses — see the note on [UpsertWrite.applyTo].
typedef RowOrder<T> = int Function(T a, T b);

// ─────────────────────────────────────────────────────────────────────────────
// 1. One pending write
// ─────────────────────────────────────────────────────────────────────────────

/// One in-flight change, expressed as a pure list transform.
///
/// [token] is unique for the life of the isolate, so removing "this write" can
/// never remove a different one that happens to touch the same row.
@immutable
abstract class PendingWrite<T> {
  PendingWrite() : token = _nextToken++;

  const PendingWrite.withToken(this.token);

  /// Identifies this entry among the live ones. Minted, never derived from the
  /// row — two edits to the same row must be two distinguishable entries.
  final int token;

  static int _nextToken = 1;

  /// The row this write is claiming, when it has one. Used to prefill the form
  /// again on **Fix**, so nothing typed is lost.
  T? get row => null;

  List<T> applyTo(List<T> rows, IdOf<T> idOf, RowOrder<T>? order);

  /// The client's guess, replaced by the server's own document — same token, so
  /// the swap is one assignment and there is no frame without the entry.
  static PendingWrite<T> upsert<T>(T row) => UpsertWrite<T>(row);

  /// The row disappears. The client knows this outcome exactly.
  static PendingWrite<T> remove<T>(String id) => RemoveWrite<T>(id);
}

/// Replaces (or, for a row not on screen, appends) one row.
class UpsertWrite<T> extends PendingWrite<T> {
  UpsertWrite(this.row);

  const UpsertWrite.withToken(super.token, this.row) : super.withToken();

  @override
  final T row;

  /// Replaces **in place** when [order] is null.
  ///
  /// That is deliberate: these lists arrive in an order the server chose, and
  /// re-sorting the whole list with a client comparator would move rows this
  /// edit never touched — precisely the "leaves the list sorted differently"
  /// failure the phase forbids. When a collection genuinely needs the row
  /// re-placed, [order] moves *only that row* and leaves its neighbours where
  /// the server put them.
  @override
  List<T> applyTo(List<T> rows, IdOf<T> idOf, RowOrder<T>? order) {
    final id = idOf(row);

    if (order == null) {
      final out = List<T>.of(rows);
      for (var i = 0; i < out.length; i++) {
        if (idOf(out[i]) == id) {
          out[i] = row;
          return out;
        }
      }
      return out..add(row);
    }

    final out = [
      for (final existing in rows)
        if (idOf(existing) != id) existing,
    ];
    var at = out.length;
    for (var i = 0; i < out.length; i++) {
      if (order(row, out[i]) < 0) {
        at = i;
        break;
      }
    }
    return out..insert(at, row);
  }
}

/// Drops one row by id. A no-op when the id is not on screen, so a delete that
/// arrives after a refresh cannot corrupt the list.
class RemoveWrite<T> extends PendingWrite<T> {
  RemoveWrite(this.id);

  const RemoveWrite.withToken(super.token, this.id) : super.withToken();

  final String id;

  @override
  List<T> applyTo(List<T> rows, IdOf<T> idOf, RowOrder<T>? order) {
    var found = false;
    final out = <T>[];
    for (final existing in rows) {
      if (!found && idOf(existing) == id) {
        found = true;
        continue;
      }
      out.add(existing);
    }
    return found ? out : rows;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. The ordered set for one collection
// ─────────────────────────────────────────────────────────────────────────────

/// Every in-flight write on one collection, in application order.
@immutable
class PendingWrites<T> {
  const PendingWrites({
    required this.idOf,
    this.order,
    this.entries = const [],
    this.settling = 0,
  });

  final IdOf<T> idOf;
  final RowOrder<T>? order;

  /// Ordered by application. Later entries win on screen, which is what makes
  /// an *earlier* failure leave the later edit standing rather than reverting
  /// to a value the owner already replaced.
  final List<PendingWrite<T>> entries;

  /// How many successful writes are waiting for their refetch. A card fed by a
  /// separate server aggregate (`/credits/summary`, the budget totals) can dim
  /// while it catches up rather than sitting on a superseded number.
  final int settling;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// True while a confirmed write is waiting for the server aggregates to
  /// catch up with the row that already repainted.
  bool get isSettling => settling > 0;

  /// The rows a screen should show.
  List<T> fold(List<T> base) {
    if (entries.isEmpty) return base;
    var rows = base;
    for (final entry in entries) {
      rows = entry.applyTo(rows, idOf, order);
    }
    return rows;
  }

  /// Folds the entries over [base], **preserving its async state exactly**.
  ///
  /// With no entries this returns the very same object it was given, so:
  ///
  ///  * a screen with no write in flight behaves identically to before 6.4;
  ///  * `isRefreshing` / `isReloading` — which 6.3's stale banner and
  ///    `state_audit_test`'s four-state sweep both read — are untouched;
  ///  * an `AsyncError` stays an `AsyncError`, so an errored screen keeps
  ///    rendering its error rather than reverting to a skeleton.
  ///
  /// With entries, the value is transformed and the state is rebuilt to match:
  /// a refreshing `AsyncData` stays refreshing, a reloading `AsyncLoading`
  /// keeps its previous value, an `AsyncError` keeps its error *and* its
  /// previous value. This is what stops a flash of the pre-write value in the
  /// window between the optimistic paint and the settle refetch.
  AsyncValue<List<T>> applyTo(AsyncValue<List<T>> base) {
    if (entries.isEmpty) return base;

    return base.map<AsyncValue<List<T>>>(
      data: (data) {
        final folded = AsyncData<List<T>>(fold(data.value));
        // `isLoading` on an AsyncData is a pull-to-refresh in flight.
        return data.isLoading
            ? AsyncLoading<List<T>>().copyWithPrevious(folded)
            : folded;
      },
      loading: (loading) {
        final previous = loading.valueOrNull;
        if (previous == null) return loading;
        return AsyncLoading<List<T>>().copyWithPrevious(
          AsyncData<List<T>>(fold(previous)),
          isRefresh: false,
        );
      },
      error: (failed) {
        final previous = failed.valueOrNull;
        if (previous == null) return failed;
        final rebuilt = AsyncError<List<T>>(
          failed.error,
          failed.stackTrace,
        ).copyWithPrevious(AsyncData<List<T>>(fold(previous)));
        return failed.isLoading
            ? AsyncLoading<List<T>>().copyWithPrevious(rebuilt)
            : rebuilt;
      },
    );
  }

  PendingWrites<T> _copy({List<PendingWrite<T>>? entries, int? settling}) =>
      PendingWrites<T>(
        idOf: idOf,
        order: order,
        entries: entries ?? this.entries,
        settling: settling ?? this.settling,
      );

  PendingWrites<T> add(PendingWrite<T> entry) =>
      _copy(entries: [...entries, entry]);

  /// Rollback. Exactly one token leaves; every other entry keeps its place.
  PendingWrites<T> removeToken(int token) => _copy(
    entries: [
      for (final entry in entries)
        if (entry.token != token) entry,
    ],
  );

  /// Swaps the guess for the server's document without moving it in the order.
  PendingWrites<T> replaceToken(int token, PendingWrite<T> entry) => _copy(
    entries: [
      for (final existing in entries)
        if (existing.token == token) entry else existing,
    ],
  );

  PendingWrites<T> settlingDelta(int delta) =>
      _copy(settling: (settling + delta).clamp(0, 1 << 30));
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. The notifier
// ─────────────────────────────────────────────────────────────────────────────

/// The optimistic overlay for one collection. One public method.
class OptimisticCollection<T> extends StateNotifier<PendingWrites<T>> {
  OptimisticCollection({required IdOf<T> idOf, RowOrder<T>? order})
    : super(PendingWrites<T>(idOf: idOf, order: order));

  /// Paint → send → confirm → settle → drop, with an exact rollback and a
  /// visible message on every failure path.
  ///
  /// * [paint] is the prediction. **Null means there is no prediction**, which
  ///   is how an unpredictable mutation opts out and keeps its spinner.
  /// * [send] is the repository call the sheet was already making. It never
  ///   builds a body — it closes over one.
  /// * [confirm] extracts the server's own document from the response, which
  ///   replaces the guess in the same synchronous assignment.
  /// * [settle] drops the cached read and **waits for the fresh one**. It must
  ///   not swallow: a failed refetch is why the confirmed entry is kept.
  /// * [idempotent] is true for PATCH/DELETE with a fixed body and false for
  ///   every POST — it decides whether a **Retry** action is offered.
  /// * [onFix] reopens the form on the attempted row when the server returned
  ///   field errors.
  ///
  /// Returns true when the server accepted the write.
  Future<bool> run<R>({
    PendingWrite<T>? paint,
    required Future<R> Function() send,
    required Future<void> Function() settle,
    required ScaffoldMessengerState messenger,
    required String noun,
    T? Function(R response)? confirm,
    bool idempotent = true,
    VoidCallback? onFix,
    String? successMessage,
  }) async {
    final entry = paint;
    if (entry != null && mounted) state = state.add(entry);

    final R response;
    try {
      response = await send();
    } on Object catch (error) {
      // Exact rollback: one token out, the fold re-runs, nothing else moves.
      if (entry != null && mounted) state = state.removeToken(entry.token);
      final api = ApiException.from(error);

      _report(
        messenger,
        api,
        noun: noun,
        idempotent: idempotent,
        onFix: onFix,
        retry: () => run<R>(
          paint: paint,
          send: send,
          settle: settle,
          messenger: messenger,
          noun: noun,
          confirm: confirm,
          idempotent: idempotent,
          onFix: onFix,
          successMessage: successMessage,
        ),
      );

      // A timeout may have landed. Refetching is the only honest answer, and
      // it is the one failure path that is allowed to issue a GET.
      if (api.code == 'TIMEOUT') {
        try {
          await settle();
        } on Object {
          // The row falls back to its last known server value; the message
          // above already says we cannot tell.
        }
      }
      return false;
    }

    // 2xx. Swap the guess for the server's document *before* anything is
    // invalidated, so no frame can be painted without the entry.
    if (entry != null && confirm != null && mounted) {
      final confirmed = confirm(response);
      if (confirmed != null) {
        state = state.replaceToken(
          entry.token,
          UpsertWrite<T>.withToken(entry.token, confirmed),
        );
      }
    }

    if (successMessage != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    }

    if (mounted) state = state.settlingDelta(1);
    var settled = false;
    try {
      await settle();
      settled = true;
    } on Object {
      // The cache was cleared by the successful write, so a refetch that fails
      // has no cached body to fall back on. Keeping the entry is the honest
      // outcome: by now it holds the server's own document, so the screen
      // shows a true value while 6.3's stale banner says the rest is old.
      settled = false;
    }
    if (mounted) {
      var next = state.settlingDelta(-1);
      // Dropped in the same synchronous turn the fresh base landed — that is
      // the whole answer to the flash.
      if (entry != null && settled) next = next.removeToken(entry.token);
      state = next;
    }
    return true;
  }

  void _report(
    ScaffoldMessengerState messenger,
    ApiException error, {
    required String noun,
    required bool idempotent,
    required VoidCallback? onFix,
    required Future<bool> Function() retry,
  }) {
    final SnackBarAction? action;
    if (error.code == 'TIMEOUT') {
      // Retrying a write that may already have landed is how you double-post,
      // and none of the 13 probed write bodies carries an idempotency key.
      action = null;
    } else if (error.fieldErrors.isNotEmpty && onFix != null) {
      action = SnackBarAction(label: 'Fix', onPressed: onFix);
    } else if (error.code == 'NO_CONNECTION' || idempotent) {
      action = SnackBarAction(
        label: 'Retry',
        onPressed: () => unawaited(retry()),
      );
    } else {
      action = null;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(rollbackMessage(error, noun: noun)),
          duration: kRollbackSnackDuration,
          action: action,
        ),
      );
  }
}

/// What the owner is told when a change was rolled back.
///
/// Every branch is either `ApiException.offlineWriteMessage`,
/// `ApiException.timedOutWriteMessage`, or [kNotSavedPrefix]-prefixed — the
/// vocabulary 6.3 established, pinned by `test/optimistic_guard_test.dart`.
/// [noun] names the row, so an owner with two edits in flight can tell which
/// one failed.
String rollbackMessage(ApiException error, {String noun = ''}) {
  switch (error.code) {
    case 'NO_CONNECTION':
      return ApiException.offlineWriteMessage;
    case 'TIMEOUT':
      return ApiException.timedOutWriteMessage;
  }

  for (final entry in error.fieldErrors.entries) {
    if (entry.value.isEmpty) continue;
    return '$kNotSavedPrefix${entry.key}: ${entry.value.first}';
  }

  final detail = error.message.startsWith(kNotSavedPrefix)
      ? error.message.substring(kNotSavedPrefix.length)
      : error.message;
  final subject = noun.trim().isEmpty ? '' : '$noun: ';
  return '$kNotSavedPrefix$subject$detail';
}

/// The settle step for a collection whose list lives in one [FutureProvider].
///
/// Drops [provider] (and anything in [also]) and **waits for the fresh read**.
/// Waiting is load-bearing: the optimistic entry is released only once the
/// value that replaces it is already in hand, which is what closes the window
/// where a screen could flash the pre-write list.
///
/// It deliberately does not swallow — `run` needs to know when the post-write
/// refetch failed so it can keep the confirmed entry.
Future<void> settleFetch<X>(
  ProviderContainer container,
  FutureProvider<X> provider, {
  List<ProviderOrFamily> also = const [],
}) async {
  for (final other in also) {
    container.invalidate(other);
  }
  container.invalidate(provider);
  await container.read(provider.future);
}
