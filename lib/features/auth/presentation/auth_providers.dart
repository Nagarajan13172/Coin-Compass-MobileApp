import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';

enum AuthStatus {
  /// Cold start — we haven't asked the server yet.
  unknown,
  restoring,
  signedOut,
  signedIn,

  /// Credentials accepted but a second factor is required.
  needsTwoFactor,
}

@immutable
class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.busy = false,
    this.error,
    this.twoFactorEmailFallback = false,
  });

  final AuthStatus status;
  final AppUser? user;
  final bool busy;
  final ApiException? error;
  final bool twoFactorEmailFallback;

  bool get isSignedIn => status == AuthStatus.signedIn && user != null;
  bool get isResolved =>
      status != AuthStatus.unknown && status != AuthStatus.restoring;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    bool clearUser = false,
    bool? busy,
    ApiException? error,
    bool clearError = false,
    bool? twoFactorEmailFallback,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      twoFactorEmailFallback:
          twoFactorEmailFallback ?? this.twoFactorEmailFallback,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState());

  final AuthRepository _repository;
  bool _restoreStarted = false;

  /// Reads the persisted session cookie. Safe to call more than once; only the
  /// first call hits the network. Never throws — a failure means "signed out".
  Future<void> restore() async {
    if (_restoreStarted) return;
    _restoreStarted = true;

    state = state.copyWith(status: AuthStatus.restoring, clearError: true);
    try {
      final user = await _repository.me();
      state = user == null
          ? state.copyWith(status: AuthStatus.signedOut, clearUser: true)
          : state.copyWith(status: AuthStatus.signedIn, user: user);
    } on Object {
      // Offline or server trouble: fall back to signed-out rather than hanging
      // on the splash forever. Deliberately NOT surfaced as an error — a failed
      // restore is indistinguishable from "no session", and showing a scary
      // banner on a fresh login form is wrong.
      state = state.copyWith(status: AuthStatus.signedOut, clearUser: true);
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await _repository.signIn(email: email, password: password);
      switch (result) {
        case SignInSuccess(user: final user):
          state = state.copyWith(
            status: AuthStatus.signedIn,
            user: user,
            busy: false,
          );
          return true;
        case SignInNeedsTwoFactor(emailFallback: final fallback):
          state = state.copyWith(
            status: AuthStatus.needsTwoFactor,
            busy: false,
            twoFactorEmailFallback: fallback,
          );
          return false;
      }
    } catch (error) {
      state = state.copyWith(busy: false, error: ApiException.from(error));
      return false;
    }
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final user = await _repository.signUp(
        name: name,
        email: email,
        password: password,
      );
      state = state.copyWith(
        status: AuthStatus.signedIn,
        user: user,
        busy: false,
      );
      return true;
    } catch (error) {
      state = state.copyWith(busy: false, error: ApiException.from(error));
      return false;
    }
  }

  Future<bool> verifyTwoFactor(String code, {bool backupCode = false}) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final user = await _repository.verifyTwoFactor(
        code: code,
        backupCode: backupCode,
      );
      state = state.copyWith(
        status: AuthStatus.signedIn,
        user: user,
        busy: false,
      );
      return true;
    } catch (error) {
      state = state.copyWith(busy: false, error: ApiException.from(error));
      return false;
    }
  }

  Future<bool> forgotPassword(String email) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repository.forgotPassword(email);
      state = state.copyWith(busy: false);
      return true;
    } catch (error) {
      state = state.copyWith(busy: false, error: ApiException.from(error));
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(busy: true, clearError: true);
    await _repository.signOut();
    state = const AuthState(status: AuthStatus.signedOut);
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(ref.watch(authRepositoryProvider));
  },
);

/// Convenience for widgets that only need the user.
final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authControllerProvider).user,
);
