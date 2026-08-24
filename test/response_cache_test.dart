import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/api/api_exception.dart';
import 'package:coincompass/core/api/endpoints.dart';
import 'package:coincompass/core/api/response_cache.dart';
import 'package:coincompass/core/api/retry_policy.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 6.3 — the response cache's invariants.
///
/// Every one of these is a statement about the owner's money. Nothing here
/// opens a socket: the ApiClient tests below drive a fake `HttpClientAdapter`,
/// and the rest is the cache on a temp directory.
void main() {
  late Directory root;
  var seq = 0;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = Directory.systemTemp.createTempSync('cc_cache_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => root.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Directory freshDir() {
    final dir = Directory('${root.path}/case${seq++}');
    dir.createSync(recursive: true);
    return dir;
  }

  ResponseCache buildCache({
    Directory? directory,
    DateTime Function()? now,
    int maxBytes = kCacheMaxBytes,
    int maxEntries = kCacheMaxEntries,
    Duration maxAge = kCacheMaxAge,
  }) {
    final dir = directory ?? freshDir();
    return ResponseCache(
      directory: () async => dir,
      now: now,
      maxBytes: maxBytes,
      maxEntries: maxEntries,
      maxAge: maxAge,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. EXHAUSTIVENESS — every endpoint is explicitly classified
  // ───────────────────────────────────────────────────────────────────────────
  //
  // The whole point of putting the decision in ONE place is that a test can
  // walk the entire `Endpoints` inventory. This parses the source file rather
  // than a hand-copied list, so an endpoint added in Phase 7 fails HERE rather
  // than silently landing in either bucket.

  group('the allow-list is exhaustive over Endpoints', () {
    /// name -> (path, expected rule). `null` means "must be denied".
    const expected = <String, StaleTag?>{
      // ── auth: never, in its entirety ─────────────────────────────────────
      'signin': null,
      'signup': null,
      'logout': null,
      'me': null,
      'authProviders': null,
      'forgotPassword': null,
      'resetPassword': null,
      'verifyEmail': null,
      'resendVerification': null,
      'changePassword': null,
      'lockWealth': null,
      'unlockWealth': null,
      'twoFactorStatus': null,
      'twoFactorSetup': null,
      'twoFactorEnable': null,
      'twoFactorDisable': null,
      'twoFactorVerify': null,
      'twoFactorPending': null,
      'twoFactorEmail': null,
      'twoFactorEmailFallback': null,
      'twoFactorBackupCodes': null,
      // ── settings: never ──────────────────────────────────────────────────
      'settings': null,
      'settingsPin': null,
      'settingsPinVerify': null,
      'settingsWealthPasscode': null,
      // ── export: never ────────────────────────────────────────────────────
      'exportCsv': null,
      // ── POST-only, denied explicitly so the table reads honestly ─────────
      'notificationsReadAll': null,
      'reportsEmailNow': null,
      'metalsRefresh': null,
      'stocksBuy': null,
      'stocksSell': null,
      'stocksRefresh': null,
      'stocksSplitsApply': null,
      // ── a live lookup, deliberately uncached ─────────────────────────────
      'stocksSearch': null,
      // ── transactions ─────────────────────────────────────────────────────
      'transactions': StaleTag.transactions,
      'transactionsBalance': StaleTag.transactions,
      'transactionsSummary': StaleTag.transactions,
      'transactionsTags': StaleTag.transactions,
      'transactionsDeleted': StaleTag.transactions,
      'transaction': StaleTag.transactions,
      'transactionRestore': StaleTag.transactions,
      'templates': StaleTag.transactions,
      'template': StaleTag.transactions,
      // ── the wealth-sensitive set ─────────────────────────────────────────
      'accounts': StaleTag.accounts,
      'account': StaleTag.accounts,
      'holdings': StaleTag.holdings,
      'holding': StaleTag.holdings,
      'netWorthHistory': StaleTag.netWorth,
      'stocksPortfolio': StaleTag.stocks,
      'stocksSales': StaleTag.stocks,
      'stocksSplits': StaleTag.stocks,
      'stocksSale': StaleTag.stocks,
      'stocksLot': StaleTag.stocks,
      'reports': StaleTag.reports,
      'reportsSummary': StaleTag.reports,
      'reportsByCategory': StaleTag.reports,
      'reportsByAccount': StaleTag.reports,
      'reportsTrend': StaleTag.reports,
      'reportsInsights': StaleTag.reports,
      // ── ordinary reads ───────────────────────────────────────────────────
      'categories': StaleTag.categories,
      'category': StaleTag.categories,
      'budgets': StaleTag.budgets,
      'budget': StaleTag.budgets,
      'goals': StaleTag.goals,
      'goal': StaleTag.goals,
      'goalContribute': StaleTag.goals,
      'loans': StaleTag.loans,
      'loan': StaleTag.loans,
      'loanPay': StaleTag.loans,
      'loanPreclose': StaleTag.loans,
      'credits': StaleTag.credits,
      'creditsSummary': StaleTag.credits,
      'credit': StaleTag.credits,
      'people': StaleTag.people,
      'peopleGroups': StaleTag.people,
      'person': StaleTag.people,
      'personMerge': StaleTag.people,
      'personGroup': StaleTag.people,
      'splits': StaleTag.splits,
      'split': StaleTag.splits,
      'recurring': StaleTag.recurring,
      'recurringRule': StaleTag.recurring,
      'recurringRun': StaleTag.recurring,
      'recurringSkip': StaleTag.recurring,
      'recurringPostOne': StaleTag.recurring,
      'recurringTransactions': StaleTag.recurring,
      'notifications': StaleTag.notifications,
      'notificationsClearAll': StaleTag.notifications,
      'notification': StaleTag.notifications,
      'notificationRead': StaleTag.notifications,
      'metalsLatest': StaleTag.metals,
      'metalsHistory': StaleTag.metals,
    };

    /// Paths the design names as wealth-sensitive: exactly the set behind
    /// `invalidateWealthReads`, plus the whole `/reports` namespace as a
    /// deliberate superset.
    const wealthSensitive = <String>{
      'accounts',
      'account',
      'holdings',
      'holding',
      'netWorthHistory',
      'stocksPortfolio',
      'stocksSales',
      'stocksSplits',
      'stocksSale',
      'stocksLot',
      'reports',
      'reportsSummary',
      'reportsByCategory',
      'reportsByAccount',
      'reportsTrend',
      'reportsInsights',
    };

    Map<String, String> parseEndpoints() {
      final source = File(
        'lib/core/api/endpoints.dart',
      ).readAsStringSync();
      final out = <String, String>{};
      for (final match in RegExp(
        r"static const String (\w+) = '([^']*)';",
      ).allMatches(source)) {
        out[match.group(1)!] = match.group(2)!;
      }
      for (final match in RegExp(
        r"static String (\w+)\([^)]*\) =>\s*'([^']*)';",
      ).allMatches(source)) {
        // Resolve the template so the rule table sees a real path, exactly as
        // it does at runtime — the key is the RESOLVED path, never a template.
        out[match.group(1)!] = match.group(2)!.replaceAll(r'$id', '65f0abc');
      }
      return out;
    }

    test('the parser actually found the inventory', () {
      final found = parseEndpoints();
      // A sanity floor: if the regex silently stops matching, every other
      // assertion in this group becomes vacuous.
      expect(found.length, greaterThan(70));
      expect(found['me'], Endpoints.me);
      expect(found['transactions'], Endpoints.transactions);
      expect(found['recurringTransactions'], '/recurring/65f0abc/transactions');
    });

    test('every endpoint is explicitly allowed or explicitly denied', () {
      final found = parseEndpoints();
      final unclassified = found.keys
          .where((name) => !expected.containsKey(name))
          .toList();
      expect(
        unclassified,
        isEmpty,
        reason:
            'New endpoints must be classified in ResponseCache._kRules AND in '
            'this test. Until then they are uncacheable, which is the safe '
            'failure — but the decision has to be written down: $unclassified',
      );

      final stale = expected.keys
          .where((name) => !found.containsKey(name))
          .toList();
      expect(stale, isEmpty, reason: 'no longer in Endpoints: $stale');
    });

    test('each one classifies exactly as declared', () {
      final found = parseEndpoints();
      found.forEach((name, path) {
        final rule = ResponseCache.ruleFor(path);
        final wanted = expected[name];
        if (wanted == null) {
          expect(
            rule.cacheable,
            isFalse,
            reason: '$name ($path) must never be cached',
          );
          expect(
            rule.reason,
            isNotNull,
            reason: '$name: a deny with no stated reason is unreviewable',
          );
        } else {
          expect(
            rule.cacheable,
            isTrue,
            reason: '$name ($path) should be cacheable',
          );
          expect(rule.tag, wanted, reason: '$name ($path) tag');
          expect(
            rule.wealthSensitive,
            wealthSensitive.contains(name),
            reason: '$name ($path) wealth sensitivity',
          );
        }
      });
    });

    test('an unrecognised path is refused, not guessed', () {
      // The allow-list's whole point: forgetting means "no offline data",
      // never "the wrong number".
      expect(ResponseCache.isCacheable('/something/new'), isFalse);
      expect(ResponseCache.isCacheable('/'), isFalse);
      expect(ResponseCache.ruleFor('/whatever').reason, isNotNull);
    });

    test('a trailing slash or a query is not a way round a deny', () {
      expect(ResponseCache.isCacheable('/auth/me/'), isFalse);
      expect(ResponseCache.isCacheable('/auth/me?x=1'), isFalse);
      expect(ResponseCache.isCacheable('/settings/'), isFalse);
      expect(ResponseCache.isCacheable('/settings/pin/verify'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. KEYS
  // ───────────────────────────────────────────────────────────────────────────

  group('cache keys', () {
    String key(String path, [Map<String, dynamic>? query]) =>
        ResponseCache.buildKey(
          scopeId: 'scope',
          method: 'GET',
          path: path,
          query: query,
        );

    test('query order does not change the key', () {
      expect(
        key('/transactions', {'page': 1, 'limit': 50}),
        key('/transactions', {'limit': 50, 'page': 1}),
      );
    });

    test('genuinely different queries never collide', () {
      // Without percent-encoding these two join to the same string, which is a
      // real collision between two different reads of the owner's transactions.
      expect(
        key('/transactions', {'search': 'a&b'}),
        isNot(key('/transactions', {'search': 'a', 'b': ''})),
      );
      expect(
        key('/transactions', {'page': 1}),
        isNot(key('/transactions', {'page': 2})),
      );
    });

    test('the resolved path is in the key, not a template', () {
      expect(
        key('/recurring/aaa/transactions'),
        isNot(key('/recurring/bbb/transactions')),
      );
    });

    test('the verb is in the key', () {
      expect(
        ResponseCache.buildKey(scopeId: 's', method: 'GET', path: '/goals'),
        isNot(
          ResponseCache.buildKey(scopeId: 's', method: 'POST', path: '/goals'),
        ),
      );
    });

    test('the scope is in the key', () {
      expect(
        ResponseCache.buildKey(scopeId: 'a', method: 'GET', path: '/goals'),
        isNot(
          ResponseCache.buildKey(scopeId: 'b', method: 'GET', path: '/goals'),
        ),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. HIT AND MISS
  // ───────────────────────────────────────────────────────────────────────────

  group('hit and miss', () {
    test('a stored body comes back, with the stamp and the tag', () async {
      final cache = buildCache();
      await cache.recordSuccess(
        path: Endpoints.goals,
        body: [
          {'name': 'Bike'},
        ],
      );

      final hit = await cache.read(path: Endpoints.goals);
      expect(hit, isNotNull);
      expect(hit!.body, [
        {'name': 'Bike'},
      ]);
      expect(hit.tag, StaleTag.goals);
      expect(
        DateTime.now().difference(hit.fetchedAt).inSeconds,
        lessThan(5),
      );
    });

    test('a path that was never stored misses', () async {
      final cache = buildCache();
      expect(await cache.read(path: Endpoints.goals), isNull);
    });

    test('a different query misses rather than serving the wrong page',
        () async {
      final cache = buildCache();
      await cache.recordSuccess(
        path: Endpoints.transactions,
        query: {'page': 1},
        body: {'items': []},
      );
      expect(
        await cache.read(path: Endpoints.transactions, query: {'page': 2}),
        isNull,
      );
      expect(
        await cache.read(path: Endpoints.transactions, query: {'page': 1}),
        isNotNull,
      );
    });

    test('the index survives a new cache over the same directory', () async {
      final dir = freshDir();
      final first = buildCache(directory: dir);
      await first.recordSuccess(path: Endpoints.loans, body: [
        {'name': 'Home'},
      ]);
      // Force the queued write to land.
      await first.read(path: Endpoints.loans);

      final second = buildCache(directory: dir);
      final hit = await second.read(path: Endpoints.loans);
      expect(hit, isNotNull, reason: 'the index is on disk, not just in memory');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. THE NEVER-CACHED RULES
  // ───────────────────────────────────────────────────────────────────────────

  group('never cached', () {
    test('GET /auth/me is never stored and never served', () async {
      final cache = buildCache();
      await cache.recordSuccess(
        path: Endpoints.me,
        body: {
          'user': {'id': 'u1'},
        },
      );
      expect(
        await cache.read(path: Endpoints.me),
        isNull,
        reason:
            'a cached "signed in" would let the app present a signed-out '
            'session as live',
      );
      expect(cache.stats.entries, 0);
    });

    test('no /auth path is stored', () async {
      final cache = buildCache();
      for (final path in const [
        '/auth/me',
        '/auth/2fa/status',
        '/auth/2fa/pending',
        '/auth/providers',
      ]) {
        await cache.recordSuccess(path: path, body: {'x': 1});
        expect(await cache.read(path: path), isNull, reason: path);
      }
      expect(cache.stats.entries, 0);
    });

    test('/settings is never stored', () async {
      final cache = buildCache();
      await cache.recordSuccess(
        path: Endpoints.settings,
        body: {'pinEnabled': false, 'wealthLockEnabled': false},
      );
      expect(await cache.read(path: Endpoints.settings), isNull);
      expect(cache.stats.entries, 0);
    });

    test('no non-GET verb can ever reach the cache', () async {
      final cache = buildCache();
      await cache.recordSuccess(
        path: Endpoints.goals,
        body: {'ok': true},
        method: 'POST',
      );
      expect(
        cache.stats.entries,
        0,
        reason: 'a write body must never be stored — no write queue',
      );

      await cache.recordSuccess(path: Endpoints.goals, body: {'ok': true});
      expect(
        await cache.read(path: Endpoints.goals, method: 'POST'),
        isNull,
        reason: 'and a write must never be answered from one',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. THE WEALTH-SENSITIVE SET — three barriers
  // ───────────────────────────────────────────────────────────────────────────

  group('wealth-sensitive bodies', () {
    const zeroedNetWorth = <Map<String, Object>>[];
    final realNetWorth = [
      {'date': '2026-08-01', 'netWorth': -20000000},
    ];

    test('the default scope is `unknown` and refuses both directions',
        () async {
      final cache = buildCache();
      expect(cache.wealthScope, CacheWealthScope.unknown);

      await cache.recordSuccess(
        path: Endpoints.netWorthHistory,
        body: realNetWorth,
      );
      expect(cache.stats.entries, 0, reason: 'barrier one: never written');
      expect(await cache.read(path: Endpoints.netWorthHistory), isNull);
    });

    test('a locked body is never written, so it can never be replayed',
        () async {
      final cache = buildCache()..wealthScope = CacheWealthScope.closed;
      await cache.recordSuccess(
        path: Endpoints.netWorthHistory,
        body: zeroedNetWorth,
      );
      expect(cache.stats.entries, 0);

      // Now unlock. There is nothing to replay, which is the whole point: the
      // owner's real net worth is −₹2,00,00,000 and a replayed ₹0 would be a
      // false statement about it.
      cache.wealthScope = CacheWealthScope.open;
      expect(await cache.read(path: Endpoints.netWorthHistory), isNull);
    });

    test('a body written while visible is not served while locked', () async {
      final cache = buildCache()..wealthScope = CacheWealthScope.open;
      await cache.recordSuccess(
        path: Endpoints.netWorthHistory,
        body: realNetWorth,
      );
      expect(await cache.read(path: Endpoints.netWorthHistory), isNotNull);

      cache.wealthScope = CacheWealthScope.closed;
      expect(
        await cache.read(path: Endpoints.netWorthHistory),
        isNull,
        reason: 'barrier two: never served unless visible',
      );

      cache.wealthScope = CacheWealthScope.unknown;
      expect(await cache.read(path: Endpoints.netWorthHistory), isNull);
    });

    test('the whole gated set behaves the same way', () async {
      final cache = buildCache()..wealthScope = CacheWealthScope.open;
      const paths = [
        '/networth/history',
        '/holdings',
        '/stocks/portfolio',
        '/reports/summary',
        '/reports/trend',
        '/reports/by-category',
        '/reports/by-account',
        '/reports/insights',
        '/accounts',
      ];
      for (final path in paths) {
        await cache.recordSuccess(path: path, body: {'p': path});
      }
      cache.wealthScope = CacheWealthScope.closed;
      for (final path in paths) {
        expect(await cache.read(path: path), isNull, reason: path);
      }
    });

    test('dropWealthSensitive empties that namespace and nothing else',
        () async {
      final cache = buildCache()..wealthScope = CacheWealthScope.open;
      await cache.recordSuccess(
        path: Endpoints.netWorthHistory,
        body: realNetWorth,
      );
      await cache.recordSuccess(path: Endpoints.holdings, body: []);
      await cache.recordSuccess(path: Endpoints.transactions, body: {
        'items': [],
      });
      // Let the queued writes land.
      await cache.read(path: Endpoints.transactions);
      expect(cache.stats.entries, 3);

      await cache.dropWealthSensitive();

      expect(await cache.read(path: Endpoints.netWorthHistory), isNull);
      expect(await cache.read(path: Endpoints.holdings), isNull);
      expect(
        await cache.read(path: Endpoints.transactions),
        isNotNull,
        reason: 'a stale transactions list must keep reporting itself',
      );
      expect(cache.stats.entries, 1);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 6. EVICTION
  // ───────────────────────────────────────────────────────────────────────────

  group('eviction', () {
    test('honours kCacheMaxEntries, oldest first', () async {
      var clock = DateTime(2026, 8, 24, 9);
      final cache = buildCache(maxEntries: 3, now: () => clock);

      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(minutes: 1));
        await cache.recordSuccess(
          path: Endpoints.transactions,
          query: {'page': i},
          body: {'page': i},
        );
      }
      // Drain the queue.
      await cache.read(path: Endpoints.transactions, query: {'page': 4});

      expect(cache.stats.entries, 3);
      expect(
        await cache.read(path: Endpoints.transactions, query: {'page': 0}),
        isNull,
      );
      expect(
        await cache.read(path: Endpoints.transactions, query: {'page': 4}),
        isNotNull,
      );
    });

    test('honours kCacheMaxBytes', () async {
      var clock = DateTime(2026, 8, 24, 9);
      // Each body below encodes to well over 200 bytes, so only one fits.
      final cache = buildCache(maxBytes: 400, now: () => clock);
      final fat = {'blob': 'x' * 300};

      for (var i = 0; i < 3; i++) {
        clock = clock.add(const Duration(minutes: 1));
        await cache.recordSuccess(
          path: Endpoints.transactions,
          query: {'page': i},
          body: fat,
        );
      }
      await cache.read(path: Endpoints.transactions, query: {'page': 2});

      expect(cache.stats.bytes, lessThanOrEqualTo(400));
      expect(cache.stats.entries, 1);
      expect(
        await cache.read(path: Endpoints.transactions, query: {'page': 2}),
        isNotNull,
        reason: 'the newest survives',
      );
    });

    test('an entry past kCacheMaxAge is never served', () async {
      var clock = DateTime(2026, 8, 1, 9);
      final cache = buildCache(
        now: () => clock,
        maxAge: const Duration(days: 14),
      );
      await cache.recordSuccess(path: Endpoints.loans, body: [
        {'outstanding': 20000000},
      ]);
      expect(await cache.read(path: Endpoints.loans), isNotNull);

      clock = clock.add(const Duration(days: 15));
      expect(
        await cache.read(path: Endpoints.loans),
        isNull,
        reason:
            'a three-month-old balance is not "recent figures", it is a wrong '
            'number with a date on it',
      );
    });

    test('there is no read-time LRU bump', () async {
      var clock = DateTime(2026, 8, 24, 9);
      final cache = buildCache(maxEntries: 2, now: () => clock);

      await cache.recordSuccess(path: Endpoints.loans, body: [1]);
      clock = clock.add(const Duration(minutes: 1));
      await cache.recordSuccess(path: Endpoints.goals, body: [2]);
      clock = clock.add(const Duration(minutes: 1));

      // Read the oldest a lot. Popularity must not keep it alive: the value of
      // an entry here is its recency as data.
      for (var i = 0; i < 5; i++) {
        await cache.read(path: Endpoints.loans);
      }

      await cache.recordSuccess(path: Endpoints.budgets, body: [3]);
      await cache.read(path: Endpoints.budgets);

      expect(await cache.read(path: Endpoints.loans), isNull);
      expect(await cache.read(path: Endpoints.budgets), isNotNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 7. SCOPE + RESILIENCE
  // ───────────────────────────────────────────────────────────────────────────

  group('scope and resilience', () {
    test('rotating the scope makes everything unreachable at once', () async {
      final cache = buildCache();
      await cache.recordSuccess(path: Endpoints.credits, body: [
        {'amount': 500},
      ]);
      expect(await cache.read(path: Endpoints.credits), isNotNull);

      await cache.rotateScope();

      expect(
        await cache.read(path: Endpoints.credits),
        isNull,
        reason: "account B must never read account A's ledger",
      );
      expect(cache.stats.entries, 0);
    });

    test('a corrupt index fails OPEN — empty cache, never a throw', () async {
      final dir = freshDir();
      final first = buildCache(directory: dir);
      await first.recordSuccess(path: Endpoints.people, body: [1]);
      await first.read(path: Endpoints.people);

      File('${dir.path}/index.json').writeAsStringSync('{ not json at all');

      final second = buildCache(directory: dir);
      expect(await second.read(path: Endpoints.people), isNull);
      expect(second.stats.entries, 0);
    });

    test('a missing body file is a miss, not a crash', () async {
      // Deliberately a COLD start. Within one session the body is held in
      // memory (kMemoryMaxBytes), so deleting the file underneath is correctly
      // survivable rather than a miss — the resilience that matters is the
      // next launch, where memory is empty and only the index remembers an
      // entry whose body is gone.
      final dir = freshDir();
      final warm = buildCache(directory: dir);
      await warm.recordSuccess(path: Endpoints.splits, body: [1]);
      await warm.read(path: Endpoints.splits);

      for (final file in dir.listSync()) {
        if (file is File && !file.path.endsWith('index.json')) {
          file.deleteSync();
        }
      }

      // The same session still serves it: the body never left memory.
      expect(await warm.read(path: Endpoints.splits), isNotNull);

      // A fresh process over the same directory must miss, not throw.
      final cold = buildCache(directory: dir);
      expect(await cold.read(path: Endpoints.splits), isNull);
    });

    test('a body that cannot be encoded is simply not cached', () async {
      final cache = buildCache();
      await cache.recordSuccess(
        path: Endpoints.goals,
        body: Object(), // not JSON-encodable
      );
      expect(cache.stats.entries, 0);
    });

    test('the index is not read until the first consultation', () async {
      final cache = buildCache();
      expect(cache.stats.loaded, isFalse);
      await cache.read(path: Endpoints.goals);
      expect(cache.stats.loaded, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 8. THROUGH THE REAL ApiClient
  // ───────────────────────────────────────────────────────────────────────────

  group('ApiClient', () {
    Future<ApiClient> client(_FakeAdapter adapter, {ResponseCache? cache}) async {
      final api = await ApiClient.create(
        cache: cache ?? buildCache(),
        // No jitter and no sleeping: the schedule itself is covered by
        // retry_policy_test.dart.
        retry: RetryPolicy(attempts: 0),
      );
      api.dio.httpClientAdapter = adapter;
      return api;
    }

    test('a GET falls back to cache only after the live read fails', () async {
      final adapter = _FakeAdapter();
      final api = await client(adapter);

      adapter.bodies['/transactions'] = '{"items":[{"amount":1200}],"total":1}';
      final live = await api.getJson(Endpoints.transactions);
      expect((live as Map)['total'], 1);

      // Let the unawaited cache write land.
      await Future<void>.delayed(Duration.zero);

      adapter.failWith = DioExceptionType.connectionError;
      final cached = await api.getJson(Endpoints.transactions);
      expect(
        (cached as Map)['total'],
        1,
        reason: 'the owner sees their real recent figures, not a retry button',
      );
    });

    test('GET /auth/me is NEVER served from cache', () async {
      final adapter = _FakeAdapter();
      final api = await client(adapter);

      adapter.bodies['/auth/me'] = '{"user":{"id":"u1","email":"o@x.com"}}';
      final live = await api.getJson(Endpoints.me);
      expect(((live as Map)['user'] as Map)['id'], 'u1');
      await Future<void>.delayed(Duration.zero);

      adapter.failWith = DioExceptionType.connectionError;
      await expectLater(
        api.getJson(Endpoints.me),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'NO_CONNECTION'),
        ),
      );
    });

    test('a 401 is never answered from cache', () async {
      final adapter = _FakeAdapter();
      final api = await client(adapter);

      adapter.bodies['/goals'] = '[{"name":"Bike"}]';
      await api.getJson(Endpoints.goals);
      await Future<void>.delayed(Duration.zero);

      adapter.status = 401;
      adapter.bodies['/goals'] = '{"error":"Unauthorized"}';
      await expectLater(
        api.getJson(Endpoints.goals),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', 401),
        ),
        reason:
            'a real answer from the server must not be replaced by 14-minute '
            'old figures',
      );
    });

    test('an offline write fails, and says nothing was sent', () async {
      final adapter = _FakeAdapter()..failWith = DioExceptionType.connectionError;
      final api = await client(adapter);

      await expectLater(
        api.postJson(Endpoints.transactions, body: {'amount': 100}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            ApiException.offlineWriteMessage,
          ),
        ),
      );
    });

    test('an offline write stores nothing — there is no queue', () async {
      final cache = buildCache();
      final adapter = _FakeAdapter()..failWith = DioExceptionType.connectionError;
      final api = await client(adapter, cache: cache);

      await expectLater(
        api.postJson(Endpoints.transactions, body: {'amount': 100}),
        throwsA(isA<ApiException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cache.stats.entries, 0);
      expect(adapter.calls.where((c) => c.startsWith('POST')).length, 1,
          reason: 'and it is sent exactly once — writes are never retried');
    });

    test('a timed-out write claims nothing about whether it landed', () async {
      final adapter = _FakeAdapter()..failWith = DioExceptionType.receiveTimeout;
      final api = await client(adapter);

      await expectLater(
        api.patchJson('/transactions/abc', body: {'amount': 100}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            ApiException.timedOutWriteMessage,
          ),
        ),
      );
    });
  });

  group('the load race, and the write that must drop it', () {
    test('concurrent cold reads all see the warmed data', () async {
      // `_ensureLoaded` used to set `_loaded = true` BEFORE its first await, so
      // every concurrent caller returned instantly with an empty index. A cold
      // start fires roughly seven reads at once — none saw the cache, which is
      // the whole feature silently doing nothing on the launch it exists for.
      final dir = freshDir();
      final warm = buildCache(directory: dir);
      for (final path in const [
        Endpoints.people,
        Endpoints.splits,
        Endpoints.goals,
        Endpoints.budgets,
      ]) {
        await warm.recordSuccess(path: path, body: [1]);
      }

      final cold = buildCache(directory: dir);
      final hits = await Future.wait([
        cold.read(path: Endpoints.people),
        cold.read(path: Endpoints.splits),
        cold.read(path: Endpoints.goals),
        cold.read(path: Endpoints.budgets),
      ]);

      expect(
        hits.where((h) => h != null).length,
        4,
        reason: 'every concurrent reader must await the same load, not skip it',
      );
    });

    test('a body is readable the instant it is recorded', () async {
      // The body went into memory synchronously while the index entry was
      // written inside the enqueued disk task, so a read in between found no
      // entry and bailed before it ever consulted memory.
      final cache = buildCache();
      await cache.recordSuccess(path: Endpoints.people, body: [1]);
      expect(await cache.read(path: Endpoints.people), isNotNull);
    });
  });

}

/// A transport that answers from a map and can be told to fail. No socket is
/// ever opened.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, String> bodies = <String, String>{};
  final List<String> calls = <String>[];

  DioExceptionType? failWith;
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    calls.add('${options.method} $path');

    final failure = failWith;
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure);
    }

    return ResponseBody.fromString(
      bodies[path] ?? jsonEncode({'error': 'not mapped'}),
      bodies.containsKey(path) ? status : 404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
