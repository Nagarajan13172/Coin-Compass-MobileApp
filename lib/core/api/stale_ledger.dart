/// Phase 6.3 — what is on screen right now that did **not** come from the
/// server on this attempt.
///
/// ## Why a ledger and not a wrapper
///
/// Threading a `fetchedAt` through 21 repositories and 25 model types — or
/// widening `AsyncValue` — is exactly the churn 6.3 must not cause. Instead the
/// cache reports what it served, and one small notifier holds the set.
///
/// An entry **enters** when a cached body is served, and **leaves** when a live
/// read for the same key succeeds. So the banner is a truthful function of what
/// is currently painted, not a sticky "you were offline once" flag.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'response_cache.dart';


class StaleSnapshot {
  const StaleSnapshot({
    this.count = 0,
    this.oldestFetchedAt,
    this.byTag = const <StaleTag, DateTime>{},
  });

  /// How many distinct reads on screen came from disk.
  final int count;

  /// The OLDEST stamp in the ledger — never the newest. Understating freshness
  /// is safe; overstating it is the lie.
  final DateTime? oldestFetchedAt;

  /// Oldest stamp per coarse area, for [StaleStamp].
  final Map<StaleTag, DateTime> byTag;

  bool get anyStale => count > 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StaleSnapshot &&
        other.count == count &&
        other.oldestFetchedAt == oldestFetchedAt &&
        mapEquals(other.byTag, byTag);
  }

  @override
  int get hashCode => Object.hash(count, oldestFetchedAt, byTag.length);
}

class _Served {
  const _Served(this.tag, this.fetchedAt);
  final StaleTag? tag;
  final DateTime fetchedAt;
}

class StaleLedger extends StateNotifier<StaleSnapshot> {
  StaleLedger() : super(const StaleSnapshot());

  final Map<String, _Served> _entries = <String, _Served>{};

  /// A cached body was just painted.
  void recordServed(String key, StaleTag? tag, DateTime fetchedAt) {
    _entries[key] = _Served(tag, fetchedAt);
    _recompute();
  }

  /// A live read succeeded. Returns whether anything was stale **before** this
  /// success — the recovery signal.
  bool recordLive(String key) {
    final wasStale = _entries.isNotEmpty;
    if (_entries.remove(key) != null) _recompute();
    return wasStale;
  }

  /// Drops exactly these keys — the wealth-lock namespace on a lock or an
  /// unlock. Never a blanket clear: a stale transactions list must keep
  /// reporting itself.
  void dropKeys(Iterable<String> keys) {
    var changed = false;
    for (final key in keys) {
      if (_entries.remove(key) != null) changed = true;
    }
    if (changed) _recompute();
  }

  /// Scope rotation and sign-out.
  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    _recompute();
  }

  void _recompute() {
    DateTime? oldest;
    final byTag = <StaleTag, DateTime>{};
    for (final served in _entries.values) {
      if (oldest == null || served.fetchedAt.isBefore(oldest)) {
        oldest = served.fetchedAt;
      }
      final tag = served.tag;
      if (tag == null) continue;
      final current = byTag[tag];
      if (current == null || served.fetchedAt.isBefore(current)) {
        byTag[tag] = served.fetchedAt;
      }
    }
    state = StaleSnapshot(
      count: _entries.length,
      oldestFetchedAt: oldest,
      byTag: byTag,
    );
  }
}

final staleLedgerProvider =
    StateNotifierProvider<StaleLedger, StaleSnapshot>((ref) => StaleLedger());

/// What [StaleBanner] watches.
final staleSnapshotProvider = Provider<StaleSnapshot>(
  (ref) => ref.watch(staleLedgerProvider),
);

/// When one coarse area was last fetched, or null when it is live.
final staleTagProvider = Provider.family<DateTime?, StaleTag>(
  (ref, tag) => ref.watch(staleLedgerProvider).byTag[tag],
);

/// Bumped when a live read succeeds while something stale is on screen.
///
/// The recovery signal. Nothing polls and there is no connectivity plugin: a
/// successful request to the API is the only reliable evidence the API is
/// reachable, because a captive portal, a dead backend and DNS poisoning all
/// report "connected".
final onlineRevisionProvider = StateProvider<int>((ref) => 0);

/// Wires [ResponseCache]'s events into the ledger and the recovery counter.
///
/// Kept alive from the app root so `cache.onEvent` is never left null while
/// signed in. If this provider is somehow never read the only consequence is a
/// missing banner — the cache's own refusals do not depend on it.
final cacheEventBridgeProvider = Provider<void>((ref) {
  final cache = ref.watch(apiClientProvider).cache;
  final ledger = ref.read(staleLedgerProvider.notifier);

  cache.onEvent = (event) {
    switch (event) {
      case CacheServedEvent(:final key, :final tag, :final fetchedAt):
        ledger.recordServed(key, tag, fetchedAt);
      case CacheLiveEvent(:final key):
        if (ledger.recordLive(key)) {
          // A live read got through while stale figures were on screen: the
          // connection is back. AppScaffold listens and refreshes the visible
          // route, behind a cooldown so a flapping connection cannot loop.
          ref.read(onlineRevisionProvider.notifier).state++;
        }
      case CacheClearedEvent():
        ledger.clear();
      case CacheDroppedEvent(:final keys):
        ledger.dropKeys(keys);
    }
  };

  ref.onDispose(() => cache.onEvent = null);
});
