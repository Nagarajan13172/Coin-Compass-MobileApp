import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api_exception.dart';

/// Talks to the deployed CoinCompass Node.js backend.
///
/// The session is an **HttpOnly `mt_session` cookie** (JWT, 180-day Max-Age) —
/// the signin response body carries no bearer token. So auth depends entirely on
/// a cookie jar persisted to disk, which is what keeps the user signed in across
/// app restarts. Never add an Authorization header; this API does not read one.
class ApiClient {
  ApiClient._(this._dio, this._jar);

  static const String baseUrl = 'https://coincompass.sathishkumar.cloud/api';

  final Dio _dio;
  final PersistCookieJar _jar;

  Dio get dio => _dio;

  static Future<ApiClient> create() async {
    final dir = await getApplicationDocumentsDirectory();
    final jar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 20),
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

    return ApiClient._(dio, jar);
  }

  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: _clean(query)));

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send(() => _dio.post(path, data: body, queryParameters: _clean(query)));

  Future<dynamic> patchJson(String path, {Object? body}) =>
      _send(() => _dio.patch(path, data: body));

  Future<dynamic> putJson(String path, {Object? body}) =>
      _send(() => _dio.put(path, data: body));

  Future<dynamic> deleteJson(String path, {Object? body}) =>
      _send(() => _dio.delete(path, data: body));

  Future<dynamic> _send(Future<Response<dynamic>> Function() run) async {
    try {
      final response = await run();
      return response.data;
    } catch (error) {
      throw ApiException.from(error);
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
  Future<void> clearSession() => _jar.deleteAll();
}

/// Overridden in `main()` with the instance built by [ApiClient.create].
final apiClientProvider = Provider<ApiClient>(
  (ref) => throw StateError('apiClientProvider was not overridden in main()'),
);
