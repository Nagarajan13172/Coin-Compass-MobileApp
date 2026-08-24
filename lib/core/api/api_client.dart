import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api_exception.dart';
import 'response_cache.dart';
import 'retry_policy.dart';

/// Talks to the deployed CoinCompass Node.js backend.
///
/// The session is an **HttpOnly `mt_session` cookie** (JWT, 180-day Max-Age) —
/// the signin response body carries no bearer token. So auth depends entirely on
/// a cookie jar persisted to disk, which is what keeps the user signed in across
/// app restarts. Never add an Authorization header; this API does not read one.
///
/// ## Phase 6.3 — where offline lives, and where it structurally cannot
///
/// [getJson] is the **only** method that touches the retry policy or the
/// response cache. [postJson], [patchJson], [putJson] and [deleteJson] call the
/// unchanged `_send` and are therefore incapable of reaching either. That is
/// not a convention — it is the mechanism that guarantees no write is ever
/// retried or replayed.
///
/// **There is no write queue, and there will not be one here.** Replaying
/// `POST /transactions` on reconnect without conflict resolution double-posts
/// the owner's money, and none of the 13 probed write bodies in
/// docs/WRITE_SCHEMAS.md carries an idempotency key, so a client-side queue has
/// no way to be safe. Writes fail immediately and say so.
class ApiClient {
  ApiClient._(this._dio, this._jar, this._cache, this._retry);

  static const String baseUrl = 'https://coincompass.sathishkumar.cloud/api';

  final Dio _dio;
  final PersistCookieJar _jar;
  final ResponseCache _cache;
  final RetryPolicy _retry;

  Dio get dio => _dio;

  /// The single response cache. Exposed so `features/wealth_lock` can push the
  /// visibility scope in and drop the wealth-sensitive namespace.
  ResponseCache get cache => _cache;

  static Future<ApiClient> create({
    ResponseCache? cache,
    RetryPolicy? retry,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final jar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        // 6.3: was 20s. Three attempts against a dead network at 20s each is a
        // sixty-second spinner; a mobile TCP connect that has not completed in
        // 8s will not produce a useful response. receiveTimeout stays 30s — a
        // large transactions page on a weak connection is real.
        connectTimeout: kConnectTimeout,
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 20),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        headers: const {'Accept': 'application/json'},
        // Let every response through so the interceptor can build a rich
        // ApiException from the body instead of Dio's opaque error.
        validateStatus: (status) => status != null && status > 0,
      ),
    );

    dio.interceptors.add(CookieManager(jar));
    dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          final status = response.statusCode ?? 0;
          if (status >= 200 && status < 300) {
            return handler.next(response);
          }
          return handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: ApiException.fromResponse(status, response.data),
            ),
            true,
          );
        },
      ),
    );

    return ApiClient._(
      dio,
      jar,
      cache ?? ResponseCache(),
      retry ?? RetryPolicy(),
    );
  }

  /// The one cacheable, retryable verb.
  ///
  /// Order is **send → retry → cache → throw**, never cache-first. A cached
  /// body can therefore only be painted when the live read for this exact key
  /// failed on this attempt, so there is no window in which stale beats fresh
  /// and no "was this figure live?" ambiguity.
  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    final cleaned = _clean(query);
    try {
      final data = await _retry.run(
        () => _send(() => _dio.get(path, queryParameters: cleaned)),
      );
      // Reports the success (which clears the stale ledger and is the recovery
      // signal) and stores the body when the allow-list permits it. Unawaited:
      // a slow flash write must never make a successful call feel slower.
      unawaited(_cache.recordSuccess(path: path, query: cleaned, body: data));
      return data;
    } on ApiException catch (error) {
      if (!isCacheFallbackEligible(error)) rethrow;
      final hit = await _cache.read(path: path, query: cleaned);
      if (hit == null) rethrow;
      return hit.body;
    }
  }

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) => _sendWrite(
    path,
    () => _dio.post(path, data: body, queryParameters: _clean(query)),
  );

  Future<dynamic> patchJson(String path, {Object? body}) =>
      _sendWrite(path, () => _dio.patch(path, data: body));

  Future<dynamic> putJson(String path, {Object? body}) =>
      _sendWrite(path, () => _dio.put(path, data: body));

  Future<dynamic> deleteJson(String path, {Object? body}) =>
      _sendWrite(path, () => _dio.delete(path, data: body));

  Future<dynamic> _send(Future<Response<dynamic>> Function() run) async {
    try {
      final response = await run();
      return response.data;
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Every non-GET. No retry, no cache — and the failure is re-worded so the
  /// form can tell the owner whether their change was saved.
  ///
  /// [path] decides two things a bare runner could not:
  ///
  ///  * **Invalidation.** A write the server accepted makes every cached body
  ///    a potential lie: the next failed GET would replay a list the owner's
  ///    own edit has already superseded — a deleted transaction reappearing,
  ///    a new one missing, the pre-write balance painted as current. Cached
  ///    reads are dropped on success.
  ///  * **Wording.** `/auth/*` posts are sign-in, sign-up and 2FA — not saves.
  ///    They render `error.message` verbatim on the login screen, where
  ///    "Not saved — you're offline. Nothing was sent." is nonsense.
  Future<dynamic> _sendWrite(
    String path,
    Future<Response<dynamic>> Function() run,
  ) async {
    final isAuth = path.startsWith('/auth/');
    try {
      final result = await _send(run);
      if (!isAuth) unawaited(_cache.clear());
      return result;
    } on ApiException catch (error) {
      if (isAuth) rethrow;
      throw ApiException.forFailedWrite(error);
    }
  }

  /// Drops query entries that are null or empty so we never send `?type=`.
  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      out[key] = value is DateTime ? value.toUtc().toIso8601String() : value;
    });
    return out.isEmpty ? null : out;
  }

  /// Wipes the session cookie — used on sign-out and on a hard 401.
  ///
  /// Also **rotates the cache scope**, so the next account cannot address this
  /// one's cached bodies. 6.1 already shipped a bug where sign-out left the
  /// previous account's PIN verifier behind; the same bug with the owner's
  /// transaction list in it is not one to ship twice.
  Future<void> clearSession() async {
    unawaited(_cache.rotateScope());
    await _jar.deleteAll();
  }
}

/// Overridden in `main()` with the instance built by [ApiClient.create].
final apiClientProvider = Provider<ApiClient>(
  (ref) => throw StateError('apiClientProvider was not overridden in main()'),
);
