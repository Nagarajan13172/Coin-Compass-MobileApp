import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/api/api_exception.dart';
import 'package:coincompass/core/api/response_cache.dart';
import 'package:coincompass/core/api/retry_policy.dart';
import 'package:coincompass/features/auth/data/auth_repository.dart';
import 'package:coincompass/features/auth/domain/app_user.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 6.8 — the auth flow.**
///
/// The other 6.8 work (Money, DateX, model round-trips) tests values. This
/// file tests the one piece of the app that decides *whose data is on screen*,
/// and it does so through the real stack: `AuthController` → `AuthRepository`
/// → `ApiClient` → Dio, with only the socket replaced. That depth is the
/// point — the interesting failures in this feature are not in the controller's
/// arithmetic, they are in the seams:
///
///   * the session cookie has to survive one request and die on sign-out;
///   * a 200 whose body carries no user must not become a signed-in session;
///   * "the server refused us" and "we could not reach the server" must not
///     collapse into the same state;
///   * a `GET /auth/me` that lands *after* a lock or unlock must not overwrite
///     the newer answer.
///
/// ## Nothing here can reach the owner's account
///
/// [_Adapter] replaces Dio's `HttpClientAdapter` outright, so no socket is
/// opened, and it **fails the test** on any path in [_forbidden] — the
/// never-call list. `/auth/logout` is served locally (sign-out is under test)
/// but can only ever reach the fake.
void main() {
  late Directory root;
  var seq = 0;

  /// The documents directory the next [ApiClient.create] will see.
  ///
  /// It has to move per client, not per file: `ApiClient.create` builds its
  /// `PersistCookieJar` at `<documents>/.cookies/`, so a single shared
  /// directory would let one test's session cookie be replayed by the next —
  /// which is exactly what the cookie assertions below are trying to detect.
  late Directory documents;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = Directory.systemTemp.createTempSync('cc_auth_flow_test');
    documents = root;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => documents.path,
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

  /// A client wired to [adapter], with retries off and its own cache
  /// directory.
  ///
  /// Retries are disabled so an offline case costs one attempt instead of
  /// three plus backoff — this file is asserting which *state* a failure
  /// produces, and `retry_policy_test.dart` already owns the backoff itself.
  Future<ApiClient> clientFor(_Adapter adapter) async {
    final dir = Directory('${root.path}/case${seq++}')
      ..createSync(recursive: true);
    documents = dir;
    final api = await ApiClient.create(
      cache: ResponseCache(directory: () async => dir),
      retry: RetryPolicy(attempts: 0),
    );
    api.dio.httpClientAdapter = adapter;
    return api;
  }

  Future<AuthController> controllerFor(_Adapter adapter) async =>
      AuthController(AuthRepository(await clientFor(adapter)));

  // ── sign in ───────────────────────────────────────────────────────────────

  group('sign in', () {
    test('a wrapped user body signs in', () async {
      final auth = await controllerFor(_Adapter(signin: _wrapped()));

      expect(await auth.signIn(email: 'a@b.c', password: 'pw'), isTrue);
      expect(auth.state.status, AuthStatus.signedIn);
      expect(auth.state.user?.email, 'haridiablo72@gmail.com');
      expect(auth.state.user?.name, 'Hari');
      expect(auth.state.busy, isFalse);
      expect(auth.state.error, isNull);
    });

    test('a bare user body signs in too', () async {
      // `AppUser.fromJson` accepts the envelope or the inner object, and the
      // repository's `_hasUser` has to agree with it or a valid sign-in gets
      // rejected as "unexpected".
      final auth = await controllerFor(
        _Adapter(
          signin: jsonEncode({
            'id': 'u1',
            'email': 'bare@example.com',
            'name': 'Bare',
          }),
        ),
      );

      expect(await auth.signIn(email: 'a@b.c', password: 'pw'), isTrue);
      expect(auth.state.status, AuthStatus.signedIn);
      expect(auth.state.user?.email, 'bare@example.com');
    });

    test('requires2fa parks the session and carries the offered methods', () async {
      final auth = await controllerFor(
        _Adapter(
          signin: jsonEncode({
            'requires2fa': true,
            'methods': ['totp', 'email'],
          }),
        ),
      );

      expect(await auth.signIn(email: 'a@b.c', password: 'pw'), isFalse);
      expect(auth.state.status, AuthStatus.needsTwoFactor);
      expect(auth.state.twoFactorMethods, ['totp', 'email']);
      expect(auth.state.twoFactorEmailFallback, isTrue);
      // No cookie was issued, so nothing may look signed in.
      expect(auth.state.user, isNull);
      expect(auth.state.isSignedIn, isFalse);
    });

    test('a challenge with no methods defaults to totp only', () async {
      final auth = await controllerFor(
        _Adapter(signin: jsonEncode({'requires2fa': true})),
      );

      await auth.signIn(email: 'a@b.c', password: 'pw');
      expect(auth.state.twoFactorMethods, ['totp']);
      expect(auth.state.twoFactorEmailFallback, isFalse);
    });

    test('a legacy twoFactorRequired flag still parks the session', () async {
      // `requires2fa` is authoritative — read out of the deployed bundle — but
      // the older names are kept as a fallback. If that fallback ever breaks,
      // a 2FA account signs in to a cookie-less session instead of being
      // challenged, so it is worth a test.
      final auth = await controllerFor(
        _Adapter(signin: jsonEncode({'twoFactorRequired': true})),
      );

      expect(await auth.signIn(email: 'a@b.c', password: 'pw'), isFalse);
      expect(auth.state.status, AuthStatus.needsTwoFactor);
    });

    test('a 200 carrying neither a user nor a challenge is refused', () async {
      // The trap this guards: fabricating an empty AppUser would still satisfy
      // `AuthState.isSignedIn`, and the app would land on a dashboard where
      // every single request 401s, with no way back to the login screen.
      final auth = await controllerFor(_Adapter(signin: jsonEncode({'ok': true})));

      expect(await auth.signIn(email: 'a@b.c', password: 'pw'), isFalse);
      expect(auth.state.user, isNull);
      expect(auth.state.isSignedIn, isFalse);
      expect(auth.state.status, isNot(AuthStatus.signedIn));
      expect(auth.state.error?.code, 'UNEXPECTED_RESPONSE');
      expect(auth.state.busy, isFalse);
    });

    test('bad credentials leave no session and clear busy', () async {
      final auth = await controllerFor(
        _Adapter(
          signin: jsonEncode({'message': 'Invalid email or password'}),
          signinStatus: 401,
        ),
      );

      expect(await auth.signIn(email: 'a@b.c', password: 'nope'), isFalse);
      expect(auth.state.status, isNot(AuthStatus.signedIn));
      expect(auth.state.user, isNull);
      expect(auth.state.busy, isFalse);
      expect(auth.state.error?.statusCode, 401);
      expect(auth.state.error?.message, 'Invalid email or password');
    });

    test('signing in offline does NOT use the failed-write wording', () async {
      // Phase 6.3 re-worded failed writes to "Not saved — you're offline.
      // Nothing was sent." That sentence is right for a transaction and wrong
      // for a sign-in, where nothing was being saved in the first place. The
      // `/auth/` prefix is excluded from that rewrite; this pins it.
      final auth = await controllerFor(_Adapter(offline: true));

      expect(await auth.signIn(email: 'a@b.c', password: 'pw'), isFalse);
      expect(auth.state.error?.code, 'NO_CONNECTION');
      expect(auth.state.error?.message, isNot(ApiException.offlineWriteMessage));
      expect(auth.state.error?.message, contains('No connection'));
    });
  });

  // ── the session cookie ────────────────────────────────────────────────────

  group('session cookie', () {
    test('is stored on sign-in and replayed on the next request', () async {
      final adapter = _Adapter(signin: _wrapped(), me: _wrapped());
      final api = await clientFor(adapter);
      final repository = AuthRepository(api);

      // Nothing to send yet.
      await repository.me();
      expect(adapter.cookieFor('GET /auth/me'), isNull);

      await repository.signIn(email: 'a@b.c', password: 'pw');
      await repository.me();

      // The cookie the fake server set on sign-in came back on the next GET.
      expect(adapter.cookieFor('GET /auth/me'), contains('mt_session=abc123'));
    });

    test('sign-out drops it, so the next request carries none', () async {
      final adapter = _Adapter(signin: _wrapped(), me: _wrapped());
      final api = await clientFor(adapter);
      final repository = AuthRepository(api);

      await repository.signIn(email: 'a@b.c', password: 'pw');
      await repository.signOut();
      await repository.me();

      expect(adapter.paths, contains('/auth/logout'));
      expect(adapter.cookieFor('GET /auth/me'), isNull);
    });

    test('the cookie is never sent as an Authorization header', () async {
      // The whole auth scheme is httpOnly cookies. A stray bearer header would
      // be a second, unmanaged credential path.
      final adapter = _Adapter(signin: _wrapped(), me: _wrapped());
      final repository = AuthRepository(await clientFor(adapter));

      await repository.signIn(email: 'a@b.c', password: 'pw');
      await repository.me();

      expect(adapter.headerFor('GET /auth/me', 'authorization'), isNull);
    });
  });

  // ── cold start ────────────────────────────────────────────────────────────

  group('restore', () {
    test('a live cookie restores the session', () async {
      final auth = await controllerFor(_Adapter(me: _wrapped()));

      await auth.restore();
      expect(auth.state.status, AuthStatus.signedIn);
      expect(auth.state.user?.email, 'haridiablo72@gmail.com');
      expect(auth.state.unverifiedSession, isFalse);
      expect(auth.state.isResolved, isTrue);
    });

    test('a 401 is a real answer: signed out, no user', () async {
      final auth = await controllerFor(_Adapter(meStatus: 401));

      await auth.restore();
      expect(auth.state.status, AuthStatus.signedOut);
      expect(auth.state.user, isNull);
      expect(auth.state.unverifiedSession, isFalse);
    });

    test('a 403 is also a real answer: signed out', () async {
      final auth = await controllerFor(_Adapter(meStatus: 403));

      await auth.restore();
      expect(auth.state.status, AuthStatus.signedOut);
      expect(auth.state.user, isNull);
    });

    for (final probe in <({String name, _Adapter Function() build})>[
      (name: 'offline', build: () => _Adapter(offline: true)),
      (name: 'a 500', build: () => _Adapter(meStatus: 500)),
    ]) {
      test('${probe.name} keeps the shell up as an unverified session', () async {
        // Phase 6.3. Landing on /login when the API is merely unreachable made
        // every cached byte unreachable too, because the shell never mounted.
        // Fail-safe, not fail-open: no user is invented.
        final auth = await controllerFor(probe.build());

        await auth.restore();
        expect(auth.state.status, AuthStatus.signedIn);
        expect(auth.state.unverifiedSession, isTrue);
        expect(auth.state.user, isNull, reason: 'no user may be invented');
        // The pair the wealth gate reads: signed in with a null user resolves
        // to `locked`, so Net Worth stays hidden through this state.
        expect(auth.state.isSignedIn, isTrue);
      });
    }

    test('only the first call hits the network', () async {
      final adapter = _Adapter(me: _wrapped());
      final auth = await controllerFor(adapter);

      await auth.restore();
      await auth.restore();
      await auth.restore();

      expect(adapter.countOf('/auth/me'), 1);
    });
  });

  // ── the session going away underneath the app ─────────────────────────────

  group('401 mid-session', () {
    test('a refresh that 401s tears the session all the way down', () async {
      final adapter = _Adapter(me: _wrapped());
      final auth = await controllerFor(adapter);
      await auth.restore();
      expect(auth.state.status, AuthStatus.signedIn);

      // The cookie expires server-side between the two reads.
      adapter.meStatus = 401;
      await auth.refreshUser();

      expect(auth.state.status, AuthStatus.signedOut);
      expect(auth.state.user, isNull);
      expect(auth.state.refreshing, isFalse);
      expect(auth.state.unverifiedSession, isFalse);
      expect(auth.state.isSignedIn, isFalse);
    });

    test('a refresh that cannot reach the server keeps the last known flag', () async {
      // Guessing "unlocked" would expose the figures on a flaky connection;
      // guessing "locked" would hide the owner's own money because a request
      // timed out. Neither is better than saying nothing.
      final adapter = _Adapter(me: _wrapped(wealthLockEnabled: true));
      final auth = await controllerFor(adapter);
      await auth.restore();
      expect(auth.state.user?.wealthLockEnabled, isTrue);

      adapter.offline = true;
      await auth.refreshUser();

      expect(auth.state.status, AuthStatus.signedIn);
      expect(auth.state.user?.wealthLockEnabled, isTrue);
      expect(auth.state.refreshing, isFalse);
    });
  });

  // ── the stale-response race ───────────────────────────────────────────────

  group('applyUser', () {
    test('an in-flight refresh cannot overwrite a newer lock result', () async {
      // The bug this pins, in the owner's terms: enter the right passcode, see
      // Net Worth for a second, and watch it vanish — because a `GET /auth/me`
      // that started *before* the unlock landed *after* it and put the old
      // flag back. `_userGeneration` is what makes the older answer lose.
      final adapter = _Adapter(me: _wrapped(wealthLockEnabled: true));
      final auth = await controllerFor(adapter);
      await auth.restore();

      // Hold /auth/me open, then start the refresh so it is genuinely mid-air.
      adapter.hold();
      final refresh = auth.refreshUser();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(auth.state.refreshing, isTrue);

      // POST /auth/unlock-wealth answers with the newer user.
      auth.applyUser(_user(wealthLockEnabled: false));
      expect(auth.state.user?.wealthLockEnabled, isFalse);

      // Now the stale read lands, still carrying the pre-unlock flag.
      adapter.release();
      await refresh;

      expect(
        auth.state.user?.wealthLockEnabled,
        isFalse,
        reason: 'the older /auth/me answer must lose to the newer unlock',
      );
      expect(auth.state.refreshing, isFalse);
    });

    test('cannot create a session out of nothing', () async {
      final auth = await controllerFor(_Adapter(meStatus: 401));
      await auth.restore();
      expect(auth.state.status, AuthStatus.signedOut);

      auth.applyUser(_user());

      expect(auth.state.status, AuthStatus.signedOut);
      expect(auth.state.user, isNull);
    });
  });

  // ── sign out ──────────────────────────────────────────────────────────────

  group('sign out', () {
    test('resets to a clean signed-out state', () async {
      final auth = await controllerFor(_Adapter(me: _wrapped()));
      await auth.restore();

      await auth.signOut();

      expect(auth.state.status, AuthStatus.signedOut);
      expect(auth.state.user, isNull);
      expect(auth.state.busy, isFalse);
      expect(auth.state.error, isNull);
      expect(auth.state.unverifiedSession, isFalse);
    });

    test('still signs out locally when the server call fails', () async {
      // The local cookie must go regardless — otherwise "sign out" on a train
      // leaves the session on the phone.
      final adapter = _Adapter(me: _wrapped(), logoutStatus: 500);
      final auth = await controllerFor(adapter);
      await auth.restore();

      await auth.signOut();

      expect(auth.state.status, AuthStatus.signedOut);
      expect(auth.state.user, isNull);
    });
  });
}

// ── fixtures ────────────────────────────────────────────────────────────────

AppUser _user({bool wealthLockEnabled = false, String mode = 'user'}) =>
    AppUser.fromJson(
      jsonDecode(_wrapped(wealthLockEnabled: wealthLockEnabled, mode: mode))
          as Map<String, dynamic>,
    );

/// The owner's real user object, wrapped the way `/auth/me` wraps it.
String _wrapped({bool wealthLockEnabled = false, String mode = 'user'}) =>
    jsonEncode({
      'user': {
        'id': '6a4669f861d974fd74ab427a',
        'email': 'haridiablo72@gmail.com',
        'name': 'Hari',
        'emailVerified': true,
        'hasPassword': true,
        'twoFactorEnabled': false,
        'mode': mode,
        'wealthLockEnabled': wealthLockEnabled,
      },
    });

/// Endpoints no test in this file may reach, in any form.
const List<String> _forbidden = [
  '/auth/lock-wealth',
  '/auth/unlock-wealth',
  '/settings/wealth-passcode',
  '/settings/pin',
];

/// A transport that answers `/auth/*` from strings and records what it was
/// asked, including the headers — the cookie assertions need those.
class _Adapter implements HttpClientAdapter {
  _Adapter({
    this.signin,
    this.me,
    this.signinStatus = 200,
    this.meStatus = 200,
    this.logoutStatus = 200,
    this.offline = false,
  });

  String? signin;
  String? me;
  int signinStatus;
  int meStatus;
  int logoutStatus;
  bool offline;

  final List<String> calls = <String>[];
  final Map<String, Map<String, String>> _headers = {};

  /// Set by [hold], consumed by the next `/auth/me`, completed by [release].
  ///
  /// Two fields, not one: the request clears [_pendingGate] when it takes the
  /// gate, so [release] has to hold its own reference or it completes nothing
  /// and the test hangs until the 30s timeout.
  Completer<void>? _pendingGate;
  Completer<void>? _heldGate;

  /// Hold the next `/auth/me` open until [release], so a refresh can be caught
  /// genuinely mid-flight rather than by hoping a delay is long enough.
  void hold() => _pendingGate = _heldGate = Completer<void>();

  void release() {
    final gate = _heldGate;
    _heldGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  List<String> get paths =>
      calls.map((c) => c.split(' ').last).toList(growable: false);

  int countOf(String path) => paths.where((p) => p == path).length;

  String? headerFor(String call, String header) =>
      _headers[call]?[header.toLowerCase()];

  String? cookieFor(String call) => headerFor(call, 'cookie');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');
    final call = '${options.method} $path';
    calls.add(call);
    _headers[call] = {
      // A null value is Dio's "header absent" — stringifying it would turn the
      // absence of a cookie into the literal string 'null' and quietly pass a
      // test that is asserting the cookie is gone.
      for (final entry in options.headers.entries)
        if (entry.value != null) entry.key.toLowerCase(): '${entry.value}',
    };

    if (_forbidden.contains(path)) {
      fail(
        'A test reached $path. That endpoint is on the never-call list: it '
        'changes what the owner can see on their own live account.',
      );
    }

    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const SocketException('offline'),
      );
    }

    switch (path) {
      case '/auth/signin':
        // The fake server issues the session cookie here, exactly as the real
        // one does — that is what makes the replay assertion meaningful.
        return _json(
          signin ?? '{}',
          signinStatus,
          setCookie: signinStatus == 200 ? 'mt_session=abc123; Path=/' : null,
        );
      case '/auth/me':
        final gate = _pendingGate;
        if (gate != null) {
          _pendingGate = null;
          await gate.future;
        }
        return _json(me ?? '{}', meStatus);
      case '/auth/logout':
        return _json('{}', logoutStatus);
    }

    return _json('{"error":"not mapped"}', 404);
  }

  static ResponseBody _json(String body, int status, {String? setCookie}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          if (setCookie != null) 'set-cookie': [setCookie],
        },
      );

  @override
  void close({bool force = false}) {}
}
