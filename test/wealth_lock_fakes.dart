import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/features/auth/data/auth_repository.dart';
import 'package:coincompass/features/auth/domain/app_user.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:coincompass/core/api/api_exception.dart';
import 'package:coincompass/core/router/app_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coincompass/l10n/app_localizations.dart';

/// Shared fakes for the two Phase 6.2 test files.
///
/// Not named `*_test.dart` on purpose — `flutter test` would try to run it.
///
/// **Nothing here can reach the owner's account.** Two independent guarantees:
///
///  1. [WealthFixtureAdapter] replaces Dio's transport entirely, so no socket
///     is ever opened, and it *fails the test* on any request to an endpoint on
///     the never-call list — `/auth/lock-wealth` included.
///  2. [FakeAuthRepository] is a repository-level fake whose `lockWealth()`
///     throws by default, so a widget that reaches for it fails loudly rather
///     than quietly locking something.

/// The owner's real user object, with the two flags under test parameterised.
String userJson({bool wealthLockEnabled = false, String mode = 'user'}) =>
    jsonEncode({
      'user': {
        'id': '6a4669f861d974fd74ab427a',
        'email': 'haridiablo72@gmail.com',
        'name': 'Hari',
        'avatarUrl': '',
        'emailVerified': true,
        'createdAt': '2026-07-02T13:39:04.074Z',
        'hasPassword': true,
        'twoFactorEnabled': false,
        'mode': mode,
        'wealthLockEnabled': wealthLockEnabled,
      },
    });

/// `GET /settings`, with `wealthLockEnabled` parameterised — the flag the
/// Settings row reads to decide whether a passcode exists at all.
String settingsJson({bool wealthLockEnabled = false}) {
  final raw =
      jsonDecode(File('test/fixtures/settings.json').readAsStringSync())
          as Map<String, dynamic>;
  raw['wealthLockEnabled'] = wealthLockEnabled;
  return jsonEncode(raw);
}

/// The three reads that must never be issued while the lock is on.
const List<String> kGatedReadPaths = [
  '/networth/history',
  '/holdings',
  '/stocks/portfolio',
];

/// Endpoints no test may ever reach, in any form. The first two would change
/// what the owner can see on their own account; the rest are the never-call
/// list from the project brief.
const List<String> kForbiddenPaths = [
  '/auth/lock-wealth',
  '/auth/logout',
  '/settings/wealth-passcode',
  '/settings/pin',
  '/settings/pin/verify',
];

/// A fixture-backed transport that records every path it is asked for.
///
/// [redactWhileLocked] switches between the two halves of the server
/// assumption in `wealth_lock.dart`: `false` serves the owner's real captured
/// payloads even while the lock is on ("the lock is only a curtain"), `true`
/// serves zeroed and empty ones ("the server withholds the data"). The app must
/// be correct under both — in particular it must never render a redacted zero
/// as a net worth.
class WealthFixtureAdapter implements HttpClientAdapter {
  WealthFixtureAdapter({
    this.wealthLockEnabled = false,
    this.mode = 'user',
    this.settingsWealthLockEnabled = false,
    this.redactWhileLocked = false,
    this.overrides = const {},
  });

  bool wealthLockEnabled;
  String mode;
  bool settingsWealthLockEnabled;
  bool redactWhileLocked;
  final Map<String, String> overrides;

  /// Every `METHOD path` this adapter has been asked for, in order.
  final List<String> calls = <String>[];

  /// Paths seen, ignoring the verb — the convenient form for assertions.
  List<String> get paths =>
      calls.map((c) => c.split(' ').last).toList(growable: false);

  int countOf(String path) => paths.where((p) => p == path).length;

  static const Map<String, String> _fixtures = {
    '/transactions': 'transactions',
    '/transactions/balance': 'transactions_balance',
    '/transactions/summary': 'transactions_summary',
    '/transactions/tags': 'transactions_tags',
    '/accounts': 'accounts',
    '/categories': 'categories',
    '/templates': 'templates',
    '/metals/latest': 'metals_latest',
    '/metals/history': 'metals_history',
    '/networth/history': 'networth_history',
    '/reports/summary': 'reports_summary',
    '/reports/by-category': 'reports_by-category',
    '/reports/trend': 'reports_trend',
    '/reports/insights': 'reports_insights',
    '/notifications': 'notifications',
    '/auth/2fa/status': 'auth_2fa_status',
    '/budgets': 'budgets',
    '/goals': 'goals',
    '/recurring': 'recurring',
    '/credits': 'credits',
    '/credits/summary': 'credits_summary',
    '/people': 'people',
    '/people/groups': 'people_groups',
    '/splits': 'splits',
    '/loans': 'loans',
    '/holdings': 'holdings',
    '/stocks/portfolio': 'stocks_portfolio',
  };

  /// What a redacting server might plausibly answer with while locked: empty
  /// series, empty lists, and a summary whose `netWorth` is a zero that is not
  /// the truth. The owner's real net worth is −₹2,00,00,000.
  ///
  /// Income, expense and net are left **real**, because the web's own settings
  /// copy promises "Income, expenses and cash flow are always visible" — so a
  /// redaction that zeroed those would be the server contradicting its own UI.
  /// That makes the assertion sharper: the only zero in play is the one that
  /// would be a false statement about the owner's net worth.
  static Map<String, String> get _redacted => {
    '/networth/history': '[]',
    '/holdings': '[]',
    '/stocks/portfolio':
        '{"configured":false,"positions":[],"totals":{"marketValue":0,'
        '"investedCost":0,"unrealized":0,"unrealizedPct":0,"dayChange":0,'
        '"realizedPL":0,"realizedShortTerm":0,"realizedLongTerm":0}}',
    '/reports/summary': _summaryWithZeroNetWorth(),
  };

  static String _summaryWithZeroNetWorth() {
    final raw =
        jsonDecode(
              File('test/fixtures/reports_summary.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    raw['netWorth'] = 0;
    return jsonEncode(raw);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    calls.add('${options.method} $path');

    if (kForbiddenPaths.contains(path)) {
      fail(
        'A test reached $path. That endpoint is on the never-call list: it '
        'changes what the owner can see on their own live account.',
      );
    }

    if (path == '/auth/me') {
      return _json(userJson(wealthLockEnabled: wealthLockEnabled, mode: mode));
    }
    if (path == '/settings') {
      return _json(settingsJson(wealthLockEnabled: settingsWealthLockEnabled));
    }

    final override = overrides[path];
    if (override != null) return _json(override);

    if (wealthLockEnabled && redactWhileLocked && _redacted.containsKey(path)) {
      return _json(_redacted[path]!);
    }

    final fixture = _fixtures[path];
    if (fixture != null) {
      return _json(File('test/fixtures/$fixture.json').readAsStringSync());
    }
    // The owner has no accounts, so this endpoint really does answer empty.
    if (path == '/reports/by-account') return _json('[]');

    return ResponseBody.fromString(
      '{"error":"not mapped"}',
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  static ResponseBody _json(String body) => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// A repository-level fake. Implements [AuthRepository] via `noSuchMethod` so
/// only the three methods this feature touches have to exist.
///
/// `lockWealth()` **throws unless [allowLock] is set**, which is how the
/// stranding trap is asserted: a test drives the whole Settings card with a
/// passcode-less account and this never fires.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.user,
    this.meError,
    this.unlockError,
    this.allowLock = false,
  });

  /// What `GET /auth/me` answers with. Null means 401/403 — signed out.
  AppUser? user;

  /// When set, `me()` throws it instead of answering.
  Object? meError;

  /// When set, `unlockWealth()` throws it instead of succeeding.
  Object? unlockError;

  /// Guards [lockWealth]. Left false everywhere except the one test that
  /// deliberately exercises a successful re-lock.
  bool allowLock;

  int meCalls = 0;
  final List<String> unlockAttempts = <String>[];
  int lockCalls = 0;

  @override
  Future<AppUser?> me() async {
    meCalls++;
    final error = meError;
    if (error != null) throw error;
    return user;
  }

  @override
  Future<AppUser> unlockWealth(String passcode) async {
    unlockAttempts.add(passcode);
    final error = unlockError;
    if (error != null) throw error;
    final next = AppUser(
      id: user?.id ?? 'u1',
      email: user?.email ?? 'owner@example.com',
      mode: user?.mode ?? 'user',
    );
    user = next;
    return next;
  }

  @override
  Future<AppUser> lockWealth() async {
    lockCalls++;
    if (!allowLock) {
      fail(
        'POST /auth/lock-wealth was called. It takes no body, so it would '
        'succeed against an account with no wealth passcode and hide Net '
        'Worth on both clients with nothing that could reopen it.',
      );
    }
    final next = AppUser(
      id: user?.id ?? 'u1',
      email: user?.email ?? 'owner@example.com',
      mode: user?.mode ?? 'user',
      wealthLockEnabled: true,
    );
    user = next;
    return next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not part of the wealth lock and must not be '
    'called from a test.',
  );
}

/// A signed-in [AppUser] with the two flags under test.
AppUser fakeUser({bool wealthLockEnabled = false, String mode = 'user'}) =>
    AppUser(
      id: '6a4669f861d974fd74ab427a',
      email: 'haridiablo72@gmail.com',
      name: 'Hari',
      mode: mode,
      wealthLockEnabled: wealthLockEnabled,
    );

/// An offline failure, exactly as `ApiClient` surfaces one.
ApiException get offlineFailure => ApiException(
  message: 'No connection. Check your internet and try again.',
  code: 'NO_CONNECTION',
);

/// A wrong-passcode failure from `/auth/unlock-wealth`.
ApiException get wrongPasscodeFailure =>
    ApiException(message: 'Invalid passcode', statusCode: 401);

/// Boots the whole app — router, redirects, shell, gate — against [adapter],
/// with the session already restored the way `main()` restores it.
///
/// Returns the container so a test can read providers directly.
Future<ProviderContainer> bootWealthApp(
  WidgetTester tester, {
  required WealthFixtureAdapter adapter,
  bool dark = false,
  Size size = const Size(360, 800),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late ProviderContainer container;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final api = await ApiClient.create();
    api.dio.httpClientAdapter = adapter;

    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    await container.read(authControllerProvider.notifier).restore();
  });
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: container.read(routerProvider),
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: L.localizationsDelegates,
      ),
    ),
  );
  await settleWealth(tester);
  return container;
}

/// Advances both clocks: the tester's fake one for animations, and the real
/// event loop so in-flight repository calls can land. Bounded on purpose —
/// this codebase does not allow an unbounded pump.
Future<void> settleWealth(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
  }
  await tester.pump();
}
