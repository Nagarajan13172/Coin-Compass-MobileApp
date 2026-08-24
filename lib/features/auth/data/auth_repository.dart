import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/app_user.dart';

/// Outcome of a sign-in attempt. The backend may demand a second factor, in
/// which case no session cookie is issued yet.
sealed class SignInResult {
  const SignInResult();
}

class SignInSuccess extends SignInResult {
  const SignInSuccess(this.user);
  final AppUser user;
}

class SignInNeedsTwoFactor extends SignInResult {
  const SignInNeedsTwoFactor({this.methods = const ['totp']});

  /// The factors the server will accept for this challenge, e.g.
  /// `['totp', 'email', 'backup']`. Never empty — defaults to `['totp']`.
  final List<String> methods;

  /// The server offers an emailed one-time code for this challenge.
  bool get emailFallback => methods.contains('email');
}

class AuthRepository {
  const AuthRepository(this._api);

  final ApiClient _api;

  /// Returns the signed-in user, or null when there is no valid session.
  /// Never throws on 401 — an expired cookie is a normal cold-start state.
  Future<AppUser?> me() async {
    try {
      final json = await _api.getJson(Endpoints.me);
      final map = J.map(json);
      if (map.isEmpty) return null;
      return AppUser.fromJson(map);
    } on ApiException catch (error) {
      if (error.isUnauthorized || error.isForbidden) return null;
      rethrow;
    }
  }

  Future<SignInResult> signIn({
    required String email,
    required String password,
  }) async {
    final json = await _api.postJson(
      Endpoints.signin,
      body: {'email': email, 'password': password},
    );
    final map = J.map(json);

    // 2FA challenge shape, read out of the deployed web bundle
    // (assets/index-BCZVpAqp.js, the /auth/signin mutation):
    //
    //   const n = (await q.post("/auth/signin", e)).data;
    //   return n.requires2fa
    //     ? {requires2fa: !0, methods: n.methods ?? ["totp"]}
    //     : {requires2fa: !1, user: n.user};
    //
    // So: HTTP 200 either way; the flag is `requires2fa` and the offered
    // factors arrive as `methods`. `emailFallback` is not part of this
    // response — the web gates its "Email me a code" button on
    // `methods.includes("email")` instead.
    //
    // Not exercisable end-to-end here (the test account has 2FA disabled), so
    // the flag name and the `methods` array are verified from the web client
    // only, not from a live challenge response. The legacy names below are
    // kept as a cheap fallback, but `requires2fa` is authoritative.
    if (_requiresTwoFactor(map)) {
      final methods = J.stringList(map['methods']);
      return SignInNeedsTwoFactor(
        methods: methods.isEmpty ? const ['totp'] : methods,
      );
    }
    // Never fabricate a user from a body that has none: an empty AppUser would
    // still satisfy AuthState.isSignedIn and strand the app on a cookie-less
    // dashboard where every request 401s.
    if (!_hasUser(map)) {
      throw ApiException(
        message: 'Unexpected sign-in response from the server.',
        code: 'UNEXPECTED_RESPONSE',
      );
    }
    return SignInSuccess(AppUser.fromJson(map));
  }

  static bool _requiresTwoFactor(Map<String, dynamic> map) {
    if (J.boolean(map['requires2fa'])) return true;
    if (_hasUser(map)) return false;
    for (final key in const [
      'twoFactorRequired',
      'requiresTwoFactor',
      'twoFactorPending',
      'pending',
      'mfaRequired',
    ]) {
      if (J.boolean(map[key])) return true;
    }
    final code = J.str(map['code']).toLowerCase();
    return code.contains('2fa') || code.contains('two_factor');
  }

  /// True when the body carries a user — either wrapped (`{user: {...}}`, what
  /// the web reads) or bare, which [AppUser.fromJson] also accepts.
  static bool _hasUser(Map<String, dynamic> map) {
    final source = map['user'] is Map ? J.map(map['user']) : map;
    return source['id'] != null ||
        source['_id'] != null ||
        source['email'] != null;
  }

  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final json = await _api.postJson(
      Endpoints.signup,
      body: {'name': name, 'email': email, 'password': password},
    );
    return AppUser.fromJson(J.map(json));
  }

  Future<void> signOut() async {
    try {
      await _api.postJson(Endpoints.logout);
    } on ApiException {
      // Even if the server call fails we still drop the local cookie below.
    } finally {
      await _api.clearSession();
    }
  }

  Future<void> forgotPassword(String email) =>
      _api.postJson(Endpoints.forgotPassword, body: {'email': email});

  Future<void> resetPassword({
    required String token,
    required String password,
  }) => _api.postJson(
    Endpoints.resetPassword,
    body: {'token': token, 'password': password},
  );

  Future<void> resendVerification() =>
      _api.postJson(Endpoints.resendVerification);

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _api.postJson(
    Endpoints.changePassword,
    body: {'currentPassword': currentPassword, 'newPassword': newPassword},
  );

  Future<TwoFactorStatus> twoFactorStatus() async {
    final json = await _api.getJson(Endpoints.twoFactorStatus);
    return TwoFactorStatus.fromJson(J.map(json));
  }

  /// Completes a 2FA challenge. [method] is one of `totp`, `backup` or
  /// `email` — the server uses it to pick which factor to check.
  ///
  /// Body and response shape read out of the deployed web bundle
  /// (assets/index-BCZVpAqp.js): the verify mutation is
  /// `(await q.post("/auth/2fa/verify", e)).data.user`, and its only call site
  /// is `o.mutateAsync({method: c, code: E.trim()})` where `c` is the selected
  /// factor (`"totp"` | `"backup"` | `"email"`). There is no `backupCode`
  /// field. Verified from the bundle only — the test account has 2FA off, so
  /// no live 200/401 from this endpoint was observed.
  Future<AppUser> verifyTwoFactor({
    required String code,
    String method = 'totp',
  }) async {
    final json = await _api.postJson(
      Endpoints.twoFactorVerify,
      body: {'method': method, 'code': code},
    );
    return AppUser.fromJson(J.map(json));
  }

  Future<void> sendTwoFactorEmail() => _api.postJson(Endpoints.twoFactorEmail);
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
