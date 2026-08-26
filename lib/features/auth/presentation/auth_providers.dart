import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/stale_ledger.dart';
import '../../settings/domain/app_settings.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';
import '../domain/auth_providers_config.dart';

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
    this.refreshing = false,
    this.error,
    this.twoFactorMethods = const ['totp'],
    this.unverifiedSession = false,
  });

  final AuthStatus status;
  final AppUser? user;
  final bool busy;

  /// A background `GET /auth/me` is in flight — a resume re-read, not a
  /// sign-in. While this is true the app knows the user object it holds may be
  /// one request out of date, which is what `WealthVisibility.checking` is
  /// for: a gated surface shows a placeholder rather than a figure it might be
  /// about to have to hide.
  final bool refreshing;

  final ApiException? error;

  /// Factors the server will accept for the pending 2FA challenge, straight
  /// from the sign-in response's `methods`. Only meaningful while
  /// [status] is [AuthStatus.needsTwoFactor].
  final List<String> twoFactorMethods;

  /// The pending challenge offers an emailed one-time code.
  bool get twoFactorEmailFallback => twoFactorMethods.contains('email');

  /// **Phase 6.3, and the highest-consequence flag in it.** A cold start that
  /// could not *reach* `GET /auth/me` — offline, timed out, or a 5xx — rather
  /// than one the server answered with a 401.
  ///
  /// It invents no user: [user] stays null, and all three consumers are
  /// already null-safe (`user?.initials ?? '·'`, `?.displayName ?? ''`,
  /// `?.mode == 'superadmin'` → false, so the superadmin bypass is
  /// unreachable). It grants access to nothing: the cookie still has to be
  /// accepted by the server for any live read to work. All it changes is which
  /// screen the owner is looking at while the API is unreachable — the shell,
  /// where the cache can serve them their own recent figures, instead of a
  /// login form that cannot succeed either.
  ///
  /// `wealthVisibilityProvider` already resolves signed-in-with-null-user to
  /// `locked`, so an unverified session automatically gates Net Worth,
  /// Holdings and Stocks, `wealthReadAllowed` returns false so those GETs are
  /// never issued, and the cache refuses wealth-sensitive bodies in both
  /// directions because the scope is not open. That falls out of code that
  /// already existed; no new gate was invented for it.
  ///
  /// Cleared by the first successful `me()`.
  final bool unverifiedSession;

  bool get isSignedIn =>
      status == AuthStatus.signedIn && (user != null || unverifiedSession);
  bool get isResolved =>
      status != AuthStatus.unknown && status != AuthStatus.restoring;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    bool clearUser = false,
    bool? busy,
    bool? refreshing,
    ApiException? error,
    bool clearError = false,
    List<String>? twoFactorMethods,
    bool? unverifiedSession,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      busy: busy ?? this.busy,
      refreshing: refreshing ?? this.refreshing,
      error: clearError ? null : (error ?? this.error),
      twoFactorMethods: twoFactorMethods ?? this.twoFactorMethods,
      unverifiedSession: unverifiedSession ?? this.unverifiedSession,
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
      // Null is the GENUINE 401/403 — `AuthRepository.me` swallows exactly
      // those. That is a real answer from the server and it means signed out.
      state = user == null
          ? state.copyWith(
              status: AuthStatus.signedOut,
              clearUser: true,
              unverifiedSession: false,
            )
          : state.copyWith(
              status: AuthStatus.signedIn,
              user: user,
              unverifiedSession: false,
            );
    } catch (error) {
      // ── Phase 6.3 ────────────────────────────────────────────────────────
      // This used to collapse "the server said no" and "we could not reach the
      // server" into signedOut. On the Underground a cold start therefore
      // landed on /login, the shell never mounted, and every cached byte was
      // unreachable — which made the whole cache worthless. So the two are now
      // told apart, and only a transport-shaped failure keeps the session.
      //
      // Fail-SAFE, not fail-open: no user is invented, nothing is granted, and
      // the shell says out loud that the session is unconfirmed.
      final failure = ApiException.from(error);
      if (_isUnreachable(failure)) {
        state = state.copyWith(
          status: AuthStatus.signedIn,
          clearUser: true,
          unverifiedSession: true,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.signedOut,
          clearUser: true,
          unverifiedSession: false,
        );
      }
    }
  }

  /// "We could not reach the server", as opposed to "the server refused us".
  ///
  /// Keyed on [ApiException.code] and the status class, which is the single
  /// switch in `api_exception.dart`. A 4xx is a real answer and must NOT keep
  /// the session alive: a 401 has to reach the router immediately.
  static bool _isUnreachable(ApiException error) {
    if (error.code == 'NO_CONNECTION' || error.code == 'TIMEOUT') return true;
    final status = error.statusCode;
    return status != null && status >= 500;
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
        case SignInNeedsTwoFactor(methods: final methods):
          state = state.copyWith(
            status: AuthStatus.needsTwoFactor,
            busy: false,
            twoFactorMethods: methods,
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

  /// [method] is one of `totp`, `backup` or `email` — the factor the code
  /// came from. The server picks which secret to check from it.
  Future<bool> verifyTwoFactor(String code, {String method = 'totp'}) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final user = await _repository.verifyTwoFactor(
        code: code,
        method: method,
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

  /// Replaces the signed-in user with the one the server just returned.
  ///
  /// `POST /auth/unlock-wealth` and `POST /auth/lock-wealth` both answer with
  /// the updated user object, and `user.wealthLockEnabled` on it is what
  /// re-gates the whole app — exactly what the web does with
  /// `pe.setQueryData(["me"], e)`.
  ///
  /// Guarded on [AuthStatus.signedIn]: this must never be able to *create* a
  /// session. Both callers already hold one (the request they made carried the
  /// cookie), so the guard only ever rejects a call that made no sense.
  /// Bumped by every authoritative write to [AuthState.user]. A `GET /auth/me`
  /// that started before a lock or unlock must not land after it and overwrite
  /// the newer truth — that flipped the wealth gate back, so the owner could
  /// enter the right passcode, see Net Worth, and have it vanish a second later
  /// (or the reverse: a locked account briefly showing its figures).
  int _userGeneration = 0;

  void applyUser(AppUser user) {
    if (state.status != AuthStatus.signedIn) return;
    _userGeneration++;
    state = state.copyWith(
      user: user,
      refreshing: false,
      clearError: true,
      unverifiedSession: false,
    );
  }

  /// Re-reads `GET /auth/me` so a lock applied somewhere else — the web, a
  /// second phone — is honoured here.
  ///
  /// Three outcomes, and the difference matters:
  ///   * a user comes back → adopt it, flag and all;
  ///   * null (401/403 — `AuthRepository.me` swallows exactly those) → the
  ///     session is genuinely gone, so sign out rather than keep rendering an
  ///     account we can no longer read;
  ///   * anything else throws (offline, 500, timeout) → **keep the last known
  ///     flag**. Guessing "unlocked" would expose the figures on a flaky train
  ///     connection; guessing "locked" would hide the owner's own money because
  ///     a request timed out. Neither is better than saying nothing.
  ///
  /// No-ops unless signed in, and never runs twice at once.
  Future<void> refreshUser() async {
    if (state.status != AuthStatus.signedIn || state.refreshing) return;
    final generation = _userGeneration;
    state = state.copyWith(refreshing: true);
    try {
      final user = await _repository.me();
      // A lock or unlock landed while this was in flight: that result is newer
      // than ours, so drop ours on the floor rather than reverting it.
      if (generation != _userGeneration) {
        state = state.copyWith(refreshing: false);
        return;
      }
      if (user == null) {
        state = const AuthState(status: AuthStatus.signedOut);
        return;
      }
      _userGeneration++;
      state = state.copyWith(
        user: user,
        refreshing: false,
        unverifiedSession: false,
      );
    } on Object {
      state = state.copyWith(refreshing: false);
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(ref.watch(authRepositoryProvider));
  },
);

/// Drops the shared [AuthState.error] when an auth screen is mounted.
///
/// [AuthState] is app-scoped, so a failure raised on one auth screen would
/// otherwise still be rendered by the next one the user opens (a blank sign-up
/// form showing "invalid credentials" from the login screen behind it). Screens
/// mix this in and also call [clearAuthError] on the way *out*, which covers
/// popping back to a screen that never unmounted.
mixin AuthErrorReset<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  @override
  void initState() {
    super.initState();
    // Post-frame: mutating a watched notifier during the first build throws
    // "Tried to modify a provider while the widget tree was building".
    WidgetsBinding.instance.addPostFrameCallback((_) => clearAuthError());
  }

  /// Safe to call from a navigation callback or after an await.
  void clearAuthError() {
    if (!mounted) return;
    ref.read(authControllerProvider.notifier).clearError();
  }
}

/// Re-reads `GET /auth/me` when the app comes back after being away a while.
///
/// ## Why this exists at all, and why the web does not have it
///
/// The web sets `refetchOnWindowFocus: false` globally, which is a
/// browser-tab-lifetime assumption: a tab is opened, used and closed, and the
/// user object it read at mount is good enough. A phone process lives for
/// weeks. Without this, an owner who locks Net Worth from their laptop would
/// keep seeing the figures on a phone that has been in a pocket since Tuesday,
/// and this app would be *less* honest than the browser rather than more.
///
/// Reuses the app lock's 30-second grace window
/// (`LockStore.defaultGraceSeconds`) rather than inventing a second one — a
/// glance at a notification and back is not "away".
///
/// Kept alive by a single `ref.watch(...notifier)` in `AppScaffold`, which
/// exists only while signed in, so this never runs on the login screen.
class SessionRefreshController extends StateNotifier<int> {
  SessionRefreshController(
    this._ref, {
    DateTime Function()? now,
    bool observeLifecycle = true,
  }) : _clock = now ?? DateTime.now,
       super(0) {
    if (observeLifecycle) {
      _listener = AppLifecycleListener(
        onHide: _markAway,
        onPause: _markAway,
        onResume: handleResumed,
      );
    }
  }

  final Ref _ref;
  final DateTime Function() _clock;
  AppLifecycleListener? _listener;
  int? _awayAtMs;

  /// Same window the app lock uses, so "away" means one thing in this app.
  static const Duration graceWindow = Duration(seconds: 30);

  void _markAway() => _awayAtMs = _clock().millisecondsSinceEpoch;

  /// Public so a test can drive the exact transition without a platform event.
  Future<void> handleResumed() async {
    final away = _awayAtMs;
    _awayAtMs = null;
    if (away == null) return;
    if (_clock().millisecondsSinceEpoch - away < graceWindow.inMilliseconds) {
      return;
    }
    state = state + 1;
    await _ref.read(authControllerProvider.notifier).refreshUser();
    // Phase 6.3 — a phone taken out of a pocket on the platform refreshes the
    // screen it is showing, through the mechanism that already exists rather
    // than a second one. `AppScaffold` listens to this and calls
    // `refreshCurrentRoute` for the visible route, behind its own cooldown.
    _ref.read(onlineRevisionProvider.notifier).state++;
  }

  @override
  void dispose() {
    _listener?.dispose();
    _listener = null;
    super.dispose();
  }
}

final sessionRefreshControllerProvider =
    StateNotifierProvider<SessionRefreshController, int>(
      (ref) => SessionRefreshController(ref),
    );

/// Convenience for widgets that only need the user.
final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authControllerProvider).user,
);

/// `GET /auth/2fa/status` — what the Settings screen's two-factor card reads.
/// Note it does NOT read `AppUser.twoFactorEnabled`, which is on the user
/// object but is not what the web renders. Invalidate after any 2FA write.
/// Which third-party sign-ins the server has configured.
///
/// Read by the login screen so the social block reflects the deployment rather
/// than a hardcoded list. Not `autoDispose`: the answer is deployment
/// configuration, it does not change while the app is open, and re-fetching it
/// on every return to /login would put a network call in front of a user who is
/// simply retrying a password.
final authProvidersConfigProvider = FutureProvider<AuthProvidersConfig>(
  (ref) => ref.watch(authRepositoryProvider).providers(),
);

final twoFactorStatusProvider = FutureProvider.autoDispose<TwoFactorStatus>(
  (ref) => ref.watch(authRepositoryProvider).twoFactorStatus(),
);
