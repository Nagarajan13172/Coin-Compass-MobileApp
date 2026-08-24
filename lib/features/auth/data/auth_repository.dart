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
  const SignInNeedsTwoFactor({this.emailFallback = false});
  final bool emailFallback;
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

    // The 2FA-required shape is unverified against this deployment (the test
    // account has 2FA off). We detect it defensively: any response that carries
    // a pending/2FA flag instead of a user is treated as "needs second factor".
    if (_looksLikeTwoFactorChallenge(map)) {
      return SignInNeedsTwoFactor(
        emailFallback: J.boolean(map['emailFallback']),
      );
    }
    return SignInSuccess(AppUser.fromJson(map));
  }

  static bool _looksLikeTwoFactorChallenge(Map<String, dynamic> map) {
    if (map['user'] is Map) return false;
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

  /// Completes a 2FA challenge. [backupCode] switches to a recovery code.
  Future<AppUser> verifyTwoFactor({
    required String code,
    bool backupCode = false,
  }) async {
    final json = await _api.postJson(
      Endpoints.twoFactorVerify,
      body: {'code': code, if (backupCode) 'backupCode': true},
    );
    return AppUser.fromJson(J.map(json));
  }

  Future<void> sendTwoFactorEmail() => _api.postJson(Endpoints.twoFactorEmail);
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
