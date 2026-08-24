/// Phase 6.3 — the app's **only** response cache.
///
/// ## Why one place and not twenty-five
///
/// All 35 `getJson` call sites across the 21 repositories funnel through
/// `ApiClient.getJson`, so a single insertion point there covers every screen.
/// More importantly the DENY decision has to be *exhaustive*: one place makes
/// it a single predicate a test can assert against the whole `Endpoints`
/// inventory. Twenty-one places make it a thing someone forgets in the
/// twenty-second repository added in Phase 7 — and the forgotten one is the one
/// that renders ₹0 as the owner's net worth.
///
/// ## Failure-fallback, not read-through
///
/// This cache is consulted **only after the live request has failed** and the
/// retry budget is spent. Online behaviour is byte-for-byte what it was before
/// 6.3. That makes the honesty property provable rather than argued: a cached
/// body can only ever be painted when the live read for that exact key failed
/// on this attempt, so there is no window in which stale beats fresh.
///
/// ## Allow-list, never deny-list
///
/// [ruleFor] returns [CacheRule.deny] for any path it does not recognise. An
/// endpoint added in Phase 7 is uncacheable until someone classifies it, so the
/// failure mode of forgetting is "no offline data for that screen", never "the
/// wrong number on screen".
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Tunables. Every one of these is a single named constant on purpose — see the
// honesty note on [CacheStats].
// ─────────────────────────────────────────────────────────────────────────────

/// Total bytes of cached bodies allowed on disk.
///
/// **A GUESS.** Nobody has measured this account's real payloads on a device.
/// Exposed on [ResponseCache.stats] so it can be replaced with a measurement
/// rather than re-argued.
const int kCacheMaxBytes = 8 * 1024 * 1024;

/// How much decoded body this process keeps in memory.
///
/// Small on purpose: the disk cache is the feature, this is only a
/// same-session shortcut that also removes the read-overtakes-write race the
/// async disk write would otherwise allow.
const int kMemoryMaxBytes = 2 * 1024 * 1024;

/// Maximum number of entries.
///
/// The Transactions screen can mint one entry per filter permutation, and
/// `netWorthHistoryRangeProvider` one per range; this stops the index itself
/// becoming the problem.
const int kCacheMaxEntries = 300;

/// Entries older than this are purged on load and are never served.
///
/// **A GUESS**, and a load-bearing one: a three-month-old balance is not
/// "recent figures", it is a wrong number with a date on it.
const Duration kCacheMaxAge = Duration(days: 14);

/// SharedPreferences key holding the current cache scope id.
const String kCacheScopePrefsKey = 'cache.scope';

/// Directory name under the application support directory.
///
/// Support-dir, **not** documents-dir: `PersistCookieJar` lives at
/// `<documents>/.cookies/`, and path_provider's own answer for regenerable app
/// data is the support directory.
const String kCacheDirName = 'api-cache';

// ─────────────────────────────────────────────────────────────────────────────
// Staleness tags
// ─────────────────────────────────────────────────────────────────────────────

/// A coarse area of the app, so a card can mark one figure as stale without
/// knowing anything about cache keys.
///
/// Derived from the same path table the allow-list is, so there is exactly one
/// place mapping paths to tags and the same exhaustiveness test covers both.
enum StaleTag {
  transactions,
  accounts,
  categories,
  budgets,
  goals,
  loans,
  credits,
  people,
  splits,
  recurring,
  notifications,
  metals,
  reports,
  netWorth,
  holdings,
  stocks,
}

// ─────────────────────────────────────────────────────────────────────────────
// Wealth scope
// ─────────────────────────────────────────────────────────────────────────────

/// What the cache knows about the Net Worth lock.
///
/// A core-local enum on purpose: `core/` must not import `features/`. A small
/// provider in `features/wealth_lock/presentation` pushes the mapped value of
/// `wealthVisibilityProvider` in.
///
/// **The default is [unknown], which refuses both writes and reads of
/// wealth-sensitive bodies.** If that wiring is ever forgotten, disposed or
/// broken, the failure mode is "no cache", never "wrong money".
enum CacheWealthScope {
  /// `WealthVisibility.visible` — figures may be written and served.
  open,

  /// `WealthVisibility.locked` — the server may be returning zeroed or
  /// redacted payloads (see `kWealthLockedResponsesAreUntrusted`). Refuse.
  closed,

  /// We do not know, so the provenance of a body is unknown. Refuse.
  unknown,
}

// ─────────────────────────────────────────────────────────────────────────────
// The rule table
// ─────────────────────────────────────────────────────────────────────────────

/// What the cache may do with one path.
class CacheRule {
  const CacheRule._({
    required this.cacheable,
    required this.tag,
    required this.wealthSensitive,
    required this.reason,
  });

  /// This path may be cached.
  const CacheRule.allow(StaleTag tag, {bool wealthSensitive = false})
    : this._(
        cacheable: true,
        tag: tag,
        wealthSensitive: wealthSensitive,
        reason: null,
      );

  /// This path must never be cached. [reason] is documentation, and the test
  /// asserts it is never empty — a silent deny is a deny nobody can review.
  const CacheRule.deny(String reason)
    : this._(
        cacheable: false,
        tag: null,
        wealthSensitive: false,
        reason: reason,
      );

  final bool cacheable;
  final StaleTag? tag;

  /// A body whose bytes may differ between locked and unlocked. Written **only
  /// when** the scope is [CacheWealthScope.open], and served **only when** the
  /// scope is [CacheWealthScope.open].
  final bool wealthSensitive;

  final String? reason;
}

class _PathRule {
  const _PathRule(this.pattern, this.rule, {this.exact = false});

  final String pattern;
  final CacheRule rule;
  final bool exact;

  bool matches(String path) {
    if (exact) return path == pattern;
    return path == pattern || path.startsWith('$pattern/');
  }
}

/// Ordered — **first match wins**, so every specific deny precedes the
/// namespace allow it sits inside.
const List<_PathRule> _kRules = <_PathRule>[
  // ── the never-cached namespaces ────────────────────────────────────────
  _PathRule(
    '/auth',
    CacheRule.deny(
      'Session-shaped. A cached "signed in" would let the app present a '
      'signed-out session as live. No /auth/me body ever touches disk.',
    ),
  ),
  _PathRule(
    '/settings',
    CacheRule.deny(
      'Carries pinEnabled and wealthLockEnabled. Replaying it offline would '
      'let the Settings security card describe a posture the server has since '
      'changed. The only cost is the currency symbol, which already has a '
      'documented fallback in currencySymbolProvider.',
    ),
  ),
  _PathRule(
    '/export',
    CacheRule.deny(
      'Binary CSV. Unreachable by construction anyway — ExportRepository goes '
      'through _api.dio.get<List<int>> directly and never through getJson. '
      'Stated so nobody "fixes" that later.',
    ),
  ),

  // ── POST-only endpoints that would otherwise fall under an allow prefix ──
  //
  // The cache is only consulted on the GET path, so none of these is
  // reachable. They are listed anyway so the table reads honestly and the
  // exhaustiveness test has something to assert.
  _PathRule(
    '/notifications/read-all',
    CacheRule.deny('POST only.'),
    exact: true,
  ),
  _PathRule('/reports/email-now', CacheRule.deny('POST only.'), exact: true),
  _PathRule('/metals/refresh', CacheRule.deny('POST only.'), exact: true),
  _PathRule('/stocks/buy', CacheRule.deny('POST only.'), exact: true),
  _PathRule('/stocks/sell', CacheRule.deny('POST only.'), exact: true),
  _PathRule('/stocks/refresh', CacheRule.deny('POST only.'), exact: true),
  _PathRule('/stocks/splits/apply', CacheRule.deny('POST only.'), exact: true),

  // ── a live lookup, deliberately not cached ──────────────────────────────
  _PathRule(
    '/stocks/search',
    CacheRule.deny(
      'A live symbol lookup. Useless offline, and it would mint one entry per '
      'query typed — pure eviction pressure on entries that matter.',
    ),
    exact: true,
  ),

  // ── the wealth-sensitive set ────────────────────────────────────────────
  //
  // Exactly the paths behind `invalidateWealthReads`. `/reports` is taken as a
  // whole namespace rather than the five named reads: a superset is safe, and
  // it makes a future /reports/anything sensitive by default.
  _PathRule(
    '/networth',
    CacheRule.allow(StaleTag.netWorth, wealthSensitive: true),
  ),
  _PathRule(
    '/holdings',
    CacheRule.allow(StaleTag.holdings, wealthSensitive: true),
  ),
  _PathRule('/stocks', CacheRule.allow(StaleTag.stocks, wealthSensitive: true)),
  _PathRule('/reports', CacheRule.allow(StaleTag.reports, wealthSensitive: true)),
  _PathRule(
    '/accounts',
    CacheRule.allow(StaleTag.accounts, wealthSensitive: true),
  ),

  // ── the ordinary reads ──────────────────────────────────────────────────
  _PathRule('/transactions', CacheRule.allow(StaleTag.transactions)),
  // The quick-add chips on the Transactions screen; tagged with the screen
  // they belong to rather than growing the enum for one endpoint.
  _PathRule('/templates', CacheRule.allow(StaleTag.transactions)),
  _PathRule('/categories', CacheRule.allow(StaleTag.categories)),
  _PathRule('/budgets', CacheRule.allow(StaleTag.budgets)),
  _PathRule('/goals', CacheRule.allow(StaleTag.goals)),
  _PathRule('/loans', CacheRule.allow(StaleTag.loans)),
  _PathRule('/credits', CacheRule.allow(StaleTag.credits)),
  _PathRule('/people', CacheRule.allow(StaleTag.people)),
  _PathRule('/splits', CacheRule.allow(StaleTag.splits)),
  _PathRule('/recurring', CacheRule.allow(StaleTag.recurring)),
  _PathRule('/notifications', CacheRule.allow(StaleTag.notifications)),
  _PathRule('/metals', CacheRule.allow(StaleTag.metals)),
];

/// The catch-all. An unrecognised path is **not cacheable**.
const CacheRule kUnknownPathRule = CacheRule.deny(
  'Not on the allow-list. New endpoints are uncacheable until someone '
  'classifies them here, so forgetting means "no offline data", never "the '
  'wrong number".',
);

// ─────────────────────────────────────────────────────────────────────────────
// Events — how the cache tells the stale ledger what it just did
// ─────────────────────────────────────────────────────────────────────────────

sealed class CacheEvent {
  const CacheEvent();
}

/// A cached body was served because the live read failed.
class CacheServedEvent extends CacheEvent {
  const CacheServedEvent({
    required this.key,
    required this.tag,
    required this.fetchedAt,
  });

  final String key;
  final StaleTag? tag;
  final DateTime fetchedAt;
}

/// A live GET succeeded. The recovery signal, and what clears one ledger entry.
class CacheLiveEvent extends CacheEvent {
  const CacheLiveEvent(this.key);

  final String key;
}

/// The whole cache went away — a scope rotation on sign-in or sign-out, or an
/// explicit clear. Nothing on screen can still be claimed as "saved at …".
class CacheClearedEvent extends CacheEvent {
  const CacheClearedEvent();
}

/// A named set of entries was deleted — today only the wealth-sensitive
/// namespace, on a lock or an unlock. Precise rather than a blanket clear: the
/// banner must not stop reporting a stale *transactions* list just because the
/// net-worth entries were dropped. Understating staleness is the unsafe
/// direction.
class CacheDroppedEvent extends CacheEvent {
  const CacheDroppedEvent(this.keys);

  final List<String> keys;
}

/// What [ResponseCache.read] hands back on a hit.
class CacheHit {
  const CacheHit({
    required this.body,
    required this.fetchedAt,
    required this.tag,
    required this.key,
  });

  final Object? body;
  final DateTime fetchedAt;
  final StaleTag? tag;
  final String key;
}

/// Debug totals, so the two guessed constants can be replaced with
/// measurements instead of re-argued.
class CacheStats {
  const CacheStats({
    required this.entries,
    required this.bytes,
    required this.maxEntries,
    required this.maxBytes,
    required this.maxAge,
    required this.loaded,
  });

  final int entries;
  final int bytes;
  final int maxEntries;
  final int maxBytes;
  final Duration maxAge;

  /// False until the first cache consultation — the index is read lazily, so a
  /// healthy online session never touches it.
  final bool loaded;

  @override
  String toString() =>
      'CacheStats(entries: $entries/$maxEntries, bytes: $bytes/$maxBytes, '
      'maxAge: ${maxAge.inDays}d, loaded: $loaded)';
}

class _Entry {
  _Entry({
    required this.hash,
    required this.key,
    required this.fetchedAtMs,
    required this.bytes,
    required this.scopeId,
    required this.tag,
    required this.wealthSensitive,
  });

  final String hash;

  /// The FULL key string, re-compared on every read. A hash-only match would
  /// let a hashing bug serve one endpoint's body for another; the re-compare
  /// turns that into a miss instead of a wrong number.
  final String key;

  final int fetchedAtMs;
  final int bytes;
  final String scopeId;
  final StaleTag? tag;
  final bool wealthSensitive;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'h': hash,
    'k': key,
    'f': fetchedAtMs,
    'b': bytes,
    's': scopeId,
    't': tag?.name,
    'w': wealthSensitive,
  };

  static _Entry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final hash = raw['h'];
    final key = raw['k'];
    final fetched = raw['f'];
    final bytes = raw['b'];
    final scope = raw['s'];
    if (hash is! String || key is! String) return null;
    if (fetched is! int || bytes is! int || scope is! String) return null;
    final tagName = raw['t'];
    StaleTag? tag;
    if (tagName is String) {
      for (final candidate in StaleTag.values) {
        if (candidate.name == tagName) {
          tag = candidate;
          break;
        }
      }
    }
    return _Entry(
      hash: hash,
      key: key,
      fetchedAtMs: fetched,
      bytes: bytes,
      scopeId: scope,
      tag: tag,
      wealthSensitive: raw['w'] == true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The cache
// ─────────────────────────────────────────────────────────────────────────────

class ResponseCache {
  ResponseCache({
    Future<Directory> Function()? directory,
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
    Random? random,
    this.maxBytes = kCacheMaxBytes,
    this.maxEntries = kCacheMaxEntries,
    this.maxAge = kCacheMaxAge,
  }) : _directory = directory ?? _defaultDirectory,
       _preferences = preferences ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final Future<Directory> Function() _directory;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  final Random _random;

  final int maxBytes;
  final int maxEntries;
  final Duration maxAge;

  /// Pushed in from `features/wealth_lock`. Defaults to the refusing value.
  CacheWealthScope wealthScope = CacheWealthScope.unknown;

  /// Where hits and live successes are reported. Set by the stale-ledger
  /// bridge provider; null in a plain unit test.
  void Function(CacheEvent event)? onEvent;

  final Map<String, _Entry> _index = <String, _Entry>{};
  bool _loaded = false;

  /// The in-flight load, memoised.
  ///
  /// `_ensureLoaded` used to set `_loaded = true` before its first await, so
  /// every concurrent caller returned immediately with `_scopeId` still null
  /// and `_index` still empty. A cold start fires roughly seven reads at once —
  /// none of them saw the cache, which is the entire feature silently doing
  /// nothing on exactly the launch it exists for. Sharing one future makes the
  /// first caller do the work and the rest await it.
  Future<void>? _loading;

  /// Bodies held for this process, keyed by hash.
  ///
  /// The file on disk exists for the COLD start. Within a session the body is
  /// already in hand, so serving from memory skips disk entirely on the path
  /// that matters — and it removes the race the async file write introduced:
  /// a read can no longer overtake a write that has not landed yet.
  ///
  /// Bounded by [kMemoryMaxBytes], oldest-inserted evicted first. Deliberately
  /// much smaller than the disk budget: this is a session convenience, not the
  /// cache itself.
  final Map<String, String> _memory = <String, String>{};
  int _memoryBytes = 0;
  String? _scopeId;
  Directory? _dir;

  /// Serialises every mutation so two concurrent writes cannot interleave a
  /// read-modify-write of the index.
  Future<void> _queue = Future<void>.value();

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/$kCacheDirName');
  }

  CacheStats get stats => CacheStats(
    entries: _index.length,
    bytes: _index.values.fold<int>(0, (sum, e) => sum + e.bytes),
    maxEntries: maxEntries,
    maxBytes: maxBytes,
    maxAge: maxAge,
    loaded: _loaded,
  );

  // ── classification ──────────────────────────────────────────────────────

  /// The single predicate. Everything else in 6.3 defers to this.
  static CacheRule ruleFor(String path) {
    final normalised = normalisePath(path);
    for (final rule in _kRules) {
      if (rule.matches(normalised)) return rule.rule;
    }
    return kUnknownPathRule;
  }

  /// True when [path] may be cached at all, ignoring the wealth scope.
  static bool isCacheable(String path) => ruleFor(path).cacheable;

  /// Strips a query/fragment and any trailing slash, and guarantees a leading
  /// slash, so `/stocks/` and `/stocks?tab=x` cannot slip past a rule.
  static String normalisePath(String path) {
    var out = path.trim();
    final cut = out.indexOf(RegExp(r'[?#]'));
    if (cut >= 0) out = out.substring(0, cut);
    if (!out.startsWith('/')) out = '/$out';
    while (out.length > 1 && out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  // ── keys ────────────────────────────────────────────────────────────────

  /// The canonical form of an already-cleaned query map.
  ///
  /// Sorted, because `{page:1,limit:50}` and `{limit:50,page:1}` are one
  /// request and must be one entry. Percent-encoded, because without it
  /// `{search: 'a&b'}` and `{search: 'a', b: ''}` join to the same string —
  /// a genuine collision between two different reads of the owner's
  /// transaction list.
  static String canonicalQuery(Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return '';
    final keys = query.keys.toList()..sort();
    return keys
        .map(
          (k) =>
              '${Uri.encodeQueryComponent(k)}='
              '${Uri.encodeQueryComponent('${query[k]}')}',
        )
        .join('&');
  }

  /// scope · method · RESOLVED path · canonical query.
  ///
  /// The method is in the key even though only GET is cacheable today, so a
  /// future cacheable verb cannot collide with the GET of the same path. The
  /// path is the resolved one (`/recurring/68a1…/transactions`), never a
  /// template, so path-parameterised endpoints never share a slot.
  static String buildKey({
    required String scopeId,
    required String method,
    required String path,
    Map<String, dynamic>? query,
  }) =>
      '$scopeId|${method.toUpperCase()}|${normalisePath(path)}|'
      '${canonicalQuery(query)}';

  // ── lifecycle ───────────────────────────────────────────────────────────

  /// Reads the index on the FIRST consultation, never in `main()`. A
  /// consultation only happens after a failed request, so a healthy online
  /// session never reads it and 6.3 costs the cold start nothing.
  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      _scopeId = await _readScopeId();
      final dir = await _resolveDir();
      final file = File('${dir.path}/index.json');
      if (!file.existsSync()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['entries'] is! List) {
        await _wipe();
        return;
      }
      for (final item in raw['entries'] as List) {
        final entry = _Entry.fromJson(item);
        if (entry == null) continue;
        _index[entry.hash] = entry;
      }
      await _purge();
    } on Object {
      // A corrupt index must fail OPEN the same way the app lock does: treat
      // it as an empty cache and wipe, never throw from the read path into a
      // screen.
      _index.clear();
      await _wipe();
    } finally {
      _loaded = true;
    }
  }

  Future<Directory> _resolveDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final dir = await _directory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<String> _readScopeId() async {
    try {
      final prefs = await _preferences();
      final existing = prefs.getString(kCacheScopePrefsKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final fresh = _newScopeId();
      await prefs.setString(kCacheScopePrefsKey, fresh);
      return fresh;
    } on Object {
      // No prefs (a unit test without a mock, a platform hiccup): a per-process
      // scope still keys correctly for this run, it just will not match
      // anything already on disk. Fail-safe: a miss, never a wrong hit.
      return _newScopeId();
    }
  }

  String _newScopeId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Rotates the scope so nothing already on disk can be addressed.
  ///
  /// Rotation rather than "delete then use" makes correctness immediate while
  /// the directory wipe stays async and best-effort. Called on sign-in and on
  /// sign-out: 6.1 already shipped a bug where sign-out left the previous
  /// account's PIN verifier behind, and account-B-reads-account-A's-
  /// transactions is the same bug with the owner's money in it.
  Future<void> rotateScope() {
    // The in-memory half is SYNCHRONOUS, so the new scope is in force the
    // instant this is called even if the caller never awaits it. Nothing
    // already on disk can be addressed by the new scope, which is what makes
    // the wipe below merely housekeeping.
    final fresh = _newScopeId();
    _scopeId = fresh;
    _index.clear();
    _forgetMemory();
    _loaded = true;
    // Satisfy the memoised loader too: without this a later consultation would
    // read the old scope's index back off disk. Harmless for correctness (a
    // rotated scope cannot address those entries) but it would repopulate
    // memory with dead rows and skew eviction against live ones.
    _loading = Future<void>.value();
    onEvent?.call(const CacheClearedEvent());

    return _enqueue(() async {
      try {
        final prefs = await _preferences();
        await prefs.setString(kCacheScopePrefsKey, fresh);
      } on Object {
        // Best effort; the in-memory rotation above is what makes it correct.
      }
      await _wipe();
    });
  }

  /// Deletes every wealth-sensitive entry. The third barrier: called as the
  /// first statement of `invalidateWealthReads`, ahead of the provider
  /// invalidations, so a provider re-read cannot race a still-present entry.
  Future<void> dropWealthSensitive() {
    // The in-memory half is SYNCHRONOUS, so an invalidated provider re-reading
    // in the same turn cannot race a still-present entry. The file deletion
    // below is housekeeping.
    final doomed = _index.values.where((e) => e.wealthSensitive).toList();
    for (final entry in doomed) {
      _index.remove(entry.hash);
    }
    if (doomed.isNotEmpty) {
      onEvent?.call(
        CacheDroppedEvent(doomed.map((e) => e.key).toList(growable: false)),
      );
    }

    return _enqueue(() async {
      // Covers the case where the index had never been read: the entries this
      // must delete are only discoverable after a load.
      await _ensureLoaded();
      final rest = _index.values.where((e) => e.wealthSensitive).toList();
      for (final entry in rest) {
        _index.remove(entry.hash);
      }
      if (rest.isNotEmpty) {
        onEvent?.call(
          CacheDroppedEvent(rest.map((e) => e.key).toList(growable: false)),
        );
      }
      for (final entry in [...doomed, ...rest]) {
        await _deleteBody(entry);
      }
      if (doomed.isNotEmpty || rest.isNotEmpty) await _persist();
    });
  }

  /// Drops everything, keeping the scope id.
  Future<void> clear() {
    _index.clear();
    _forgetMemory();
    _loaded = true;
    _loading = Future<void>.value();
    onEvent?.call(const CacheClearedEvent());
    return _enqueue(_wipe);
  }

  // ── the read path ───────────────────────────────────────────────────────

  /// The failure fallback. Returns null on any doubt whatsoever.
  Future<CacheHit?> read({
    required String path,
    Map<String, dynamic>? query,
    String method = 'GET',
  }) async {
    // Structurally impossible to reach with a write today — ApiClient only
    // calls this from getJson — but asserted here too so a future caller
    // cannot open the door.
    if (method.toUpperCase() != 'GET') return null;

    final rule = ruleFor(path);
    if (!rule.cacheable) return null;
    if (rule.wealthSensitive && wealthScope != CacheWealthScope.open) {
      // Barrier two: a wealth-sensitive body is SERVED only while visible.
      return null;
    }

    try {
      await _ensureLoaded();
      // No queue drain here: [_memory] already holds anything this process
      // wrote, so a read cannot overtake its own write. Awaiting `_queue`
      // instead would make every read wait on unrelated disk writes.
      final scope = _scopeId;
      if (scope == null) return null;

      final key = buildKey(
        scopeId: scope,
        method: method,
        path: path,
        query: query,
      );
      final hash = _hash(key);
      final entry = _index[hash];
      if (entry == null) return null;
      // The re-compare. A hash-only match would serve one endpoint's body for
      // another if the hashing were ever wrong.
      if (entry.key != key) return null;
      if (entry.scopeId != scope) return null;
      if (entry.wealthSensitive && wealthScope != CacheWealthScope.open) {
        return null;
      }

      final fetchedAt = DateTime.fromMillisecondsSinceEpoch(entry.fetchedAtMs);
      if (_now().difference(fetchedAt) > maxAge) return null;

      final held = _memory[entry.hash];
      final Object? body;
      if (held != null) {
        body = jsonDecode(held);
      } else {
        final dir = await _resolveDir();
        final file = File('${dir.path}/${entry.hash}.json');
        if (!file.existsSync()) return null;
        body = jsonDecode(await file.readAsString());
      }

      final hit = CacheHit(
        body: body,
        fetchedAt: fetchedAt,
        tag: entry.tag,
        key: key,
      );
      onEvent?.call(
        CacheServedEvent(key: key, tag: entry.tag, fetchedAt: fetchedAt),
      );
      return hit;
    } on Object {
      // Never throw from the read path into a screen.
      return null;
    }
  }

  // ── the write path ──────────────────────────────────────────────────────

  /// Called after every successful live GET.
  ///
  /// Two jobs: report the success so the stale ledger can drop this key (and
  /// the recovery bump can fire), and store the body when the path allows it.
  /// Never throws — it runs unawaited, so a slow flash write can never make a
  /// successful API call feel slower, and a failure must never surface.
  Future<void> recordSuccess({
    required String path,
    Map<String, dynamic>? query,
    required Object? body,
    String method = 'GET',
  }) async {
    try {
      final scope = _scopeId ?? await _readScopeIdOnce();
      final key = buildKey(
        scopeId: scope,
        method: method,
        path: path,
        query: query,
      );
      onEvent?.call(CacheLiveEvent(key));

      if (method.toUpperCase() != 'GET') return;
      final rule = ruleFor(path);
      if (!rule.cacheable) return;
      if (rule.wealthSensitive && wealthScope != CacheWealthScope.open) {
        // Barrier one: a locked (or unknown-provenance) body is never WRITTEN,
        // so it can never be replayed while unlocked.
        return;
      }

      final encoded = jsonEncode(body);
      // Index and body land together, synchronously. `read()` looks the entry
      // up in `_index` BEFORE it ever consults memory or disk, so indexing
      // inside the enqueued disk write left a window where the body was in
      // hand but unreachable — the cache silently missed on exactly the reads
      // it had just warmed.
      _rememberEntry(key: key, rule: rule, encoded: encoded, scope: scope);
      await _enqueue(() => _store(key: key, rule: rule, encoded: encoded));
    } on Object {
      // Caching is a convenience. It must never break a request that worked.
    }
  }

  /// The synchronous half of a write: index entry + in-memory body.
  ///
  /// Everything a same-session read needs. The disk write that follows is
  /// purely so a COLD start has something to serve.
  void _rememberEntry({
    required String key,
    required CacheRule rule,
    required String encoded,
    required String scope,
  }) {
    final hash = _hash(key);
    _index[hash] = _Entry(
      hash: hash,
      key: key,
      fetchedAtMs: _now().millisecondsSinceEpoch,
      bytes: encoded.length,
      scopeId: scope,
      tag: rule.tag,
      wealthSensitive: rule.wealthSensitive,
    );
    _remember(hash, encoded);
  }

  /// Holds [encoded] for this session, evicting oldest-first past the bound.
  void _remember(String hash, String encoded) {
    final existing = _memory.remove(hash);
    if (existing != null) _memoryBytes -= existing.length;
    _memory[hash] = encoded;
    _memoryBytes += encoded.length;
    while (_memoryBytes > kMemoryMaxBytes && _memory.isNotEmpty) {
      final oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.length;
    }
  }

  void _forgetMemory() {
    _memory.clear();
    _memoryBytes = 0;
  }

  Future<String> _readScopeIdOnce() async {
    final scope = await _readScopeId();
    _scopeId ??= scope;
    return _scopeId!;
  }

  Future<void> _store({
    required String key,
    required CacheRule rule,
    required String encoded,
  }) async {
    await _ensureLoaded();
    final scope = _scopeId;
    if (scope == null) return;
    // The scope may have rotated between the request starting and landing.
    if (!key.startsWith('$scope|')) return;

    final dir = await _resolveDir();
    final hash = _hash(key);
    final file = File('${dir.path}/$hash.json');
    // Async and unflushed, deliberately. This ran `writeAsStringSync(flush: true)`
    // on the root isolate for EVERY successful cacheable GET — an fsync per
    // read, on the thread that paints. The cache is regenerable, so a torn
    // write costs a miss rather than a wrong number: `read()` re-compares the
    // full key string and a short file simply fails to decode.
    await file.writeAsString(encoded);

    // The index entry was written synchronously by `_rememberEntry`; this task
    // only owes the disk.
    await _purge();
    await _persist();
  }

  // ── eviction ────────────────────────────────────────────────────────────

  /// Three bounds, enforced after every write and on load.
  ///
  /// LRU is by WRITE time; there is deliberately no read-time bump. The value
  /// of an entry here is its recency as *data*, not its popularity — bumping on
  /// read would keep a stale dashboard alive forever because it is the screen
  /// the owner opens most.
  Future<void> _purge() async {
    final scope = _scopeId;
    final cutoff = _now().subtract(maxAge).millisecondsSinceEpoch;

    final doomed = <_Entry>[];
    for (final entry in _index.values) {
      if (entry.fetchedAtMs < cutoff) {
        doomed.add(entry);
      } else if (scope != null && entry.scopeId != scope) {
        doomed.add(entry);
      }
    }
    for (final entry in doomed) {
      _index.remove(entry.hash);
      await _deleteBody(entry);
    }

    // Oldest first.
    List<_Entry> ordered() =>
        _index.values.toList()
          ..sort((a, b) => a.fetchedAtMs.compareTo(b.fetchedAtMs));

    if (_index.length > maxEntries) {
      final over = ordered();
      var i = 0;
      while (_index.length > maxEntries && i < over.length) {
        final entry = over[i++];
        _index.remove(entry.hash);
        await _deleteBody(entry);
      }
    }

    var total = _index.values.fold<int>(0, (sum, e) => sum + e.bytes);
    if (total > maxBytes) {
      final over = ordered();
      var i = 0;
      while (total > maxBytes && i < over.length) {
        final entry = over[i++];
        if (_index.remove(entry.hash) == null) continue;
        total -= entry.bytes;
        await _deleteBody(entry);
      }
    }
  }

  // ── disk ────────────────────────────────────────────────────────────────

  /// Rewritten atomically: write `.tmp`, then rename. A crash mid-rename loses
  /// at most the last write, never the cache.
  Future<void> _persist() async {
    try {
      final dir = await _resolveDir();
      final tmp = File('${dir.path}/index.json.tmp');
      // The rename stays atomic; only the fsync and the sync write go. At the
      // 300-entry cap this encodes ~87 KB, and it ran on the root isolate after
      // every cacheable GET — the cost was paid on every successful read, on
      // the thread that paints, for a file only ever consulted after a failure.
      await tmp.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'scope': _scopeId,
          'entries': _index.values.map((e) => e.toJson()).toList(),
        }),
      );
      await tmp.rename('${dir.path}/index.json');
    } on Object {
      // Best effort.
    }
  }

  Future<void> _deleteBody(_Entry entry) async {
    try {
      final dir = await _resolveDir();
      final file = File('${dir.path}/${entry.hash}.json');
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // Best effort.
    }
  }

  Future<void> _wipe() async {
    try {
      final dir = await _resolveDir();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      _dir = null;
      await _resolveDir();
    } on Object {
      _dir = null;
    }
  }

  Future<void> _enqueue(Future<void> Function() work) {
    final next = _queue.then((_) async {
      try {
        await work();
      } on Object {
        // Never let one failed write poison the queue.
      }
    });
    _queue = next;
    return next;
  }

  static String _hash(String key) =>
      sha256.convert(utf8.encode(key)).toString();
}
