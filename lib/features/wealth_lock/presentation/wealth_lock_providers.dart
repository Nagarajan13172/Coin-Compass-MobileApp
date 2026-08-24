import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/response_cache.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../holdings/data/holdings_repository.dart';
import '../../insights/presentation/insights_providers.dart';
import '../../networth/data/networth_repository.dart';
import '../../networth/presentation/networth_providers.dart';
import '../../reports/presentation/reports_providers.dart';
import '../../settings/data/settings_repository.dart';
import '../../stocks/data/stocks_repository.dart';
import '../domain/wealth_lock.dart';

/// What the app currently knows about the Net Worth lock, derived from the
/// **user object** and nothing else.
///
/// ## The two `wealthLockEnabled` flags, and which one gates
///
/// There are two fields with that name, read from two endpoints:
///
///   * `user.wealthLockEnabled` from `GET /auth/me` — what the web's `no()`
///     reads, and the only thing this provider looks at;
///   * `settings.wealthLockEnabled` from `GET /settings` — what the web's
///     Settings page reads to decide whether a passcode exists.
///
/// They may or may not be the same field; nobody can tell while both are false,
/// and finding out means flipping the lock on the owner's live account, which
/// is on the never-call list. So the split is deliberate: the **gate** is
/// derived only from the user object, exactly as the web derives it, and the
/// Settings row's **actions** consult both plus [wealthUnlockedHereProvider].
/// Every wealth write is followed by a `GET /auth/me`, so the two can never
/// drift more than one request apart.
///
/// ## Why "not signed in" is `visible`, not `locked`
///
/// The shell — and therefore every gated surface — exists only while signed in;
/// the router sends a signed-out user to `/login` before any of it mounts. So
/// `visible` here is not a fail-open in a reachable state, it is the inert
/// value for a state in which nothing gated is on screen. Returning `locked`
/// instead would make the gate fire during the sign-in screen's own build and
/// on every widget test that never signs in, for no gain in safety.
///
/// A signed-in state with a null user is a contradiction (`isSignedIn` requires
/// both), and it resolves to `locked`: if we are claiming a session but cannot
/// say whose, we do not paint their net worth.
final wealthVisibilityProvider = Provider<WealthVisibility>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth.status != AuthStatus.signedIn) return WealthVisibility.visible;

  final user = auth.user;
  if (user == null) return WealthVisibility.locked;

  return wealthVisibilityFor(
    mode: user.mode,
    lockEnabled: user.wealthLockEnabled,
    refreshing: auth.refreshing,
  );
});

/// Drops the gated caches on EVERY visibility transition, not only the two the
/// controller drives.
///
/// `WealthLockController` invalidates after its own unlock/lock calls, but the
/// state can also flip underneath the app: `refreshUser()` on resume discovers
/// that another sign-in locked or unlocked the account. That path used to leave
/// the caches alone, so a figure fetched in one visibility state could be
/// painted in the other — the design's "dropped on BOTH lock and unlock"
/// invariant, broken by the one transition nothing owned.
///
/// Kept alive for the app's lifetime by [wealthLockControllerProvider]'s own
/// dependency on it, so there is no widget to forget to mount.
final wealthVisibilityWatcherProvider = Provider<void>((ref) {
  var previous = ref.read(wealthVisibilityProvider);
  ref.listen<WealthVisibility>(wealthVisibilityProvider, (_, next) {
    // `checking` is transient and carries no new data — only a settled change
    // between visible and locked means the bytes on screen may be stale.
    if (next == WealthVisibility.checking) return;
    if (next == previous) return;
    previous = next;
    invalidateWealthReads(ref);
  });
});

/// Pushes [wealthVisibilityProvider] into `ResponseCache.wealthScope`.
///
/// `core/` must not import `features/`, so the cache holds a core-local enum
/// and this one small provider is the bridge. Kept alive from the app root —
/// see `main.dart` — the same way [wealthVisibilityWatcherProvider] is kept
/// alive by the controller.
///
/// **If this wiring is ever forgotten, disposed or broken the cache stays at
/// its default `unknown`, which refuses wealth-sensitive bodies in BOTH
/// directions.** The failure mode is "no cache", never "wrong money".
///
/// Stricter than a straight mapping on purpose: [wealthVisibilityProvider]
/// answers `visible` while signed *out* (its documented inert value, because
/// nothing gated is on screen then), and that must not be read as permission
/// to store figures. Only a signed-in session with a known user can open the
/// scope.
final wealthCacheScopeProvider = Provider<CacheWealthScope>((ref) {
  final cache = ref.watch(apiClientProvider).cache;
  final auth = ref.watch(authControllerProvider);
  final visibility = ref.watch(wealthVisibilityProvider);

  final scope = (auth.status != AuthStatus.signedIn || auth.user == null)
      ? CacheWealthScope.unknown
      : switch (visibility) {
          WealthVisibility.visible => CacheWealthScope.open,
          // A body received while locked has redacted-or-not provenance we
          // cannot establish; one received while `checking` has none at all.
          WealthVisibility.locked => CacheWealthScope.closed,
          WealthVisibility.checking => CacheWealthScope.unknown,
        };

  cache.wealthScope = scope;
  ref.onDispose(() => cache.wealthScope = CacheWealthScope.unknown);
  return scope;
});

/// True when **this process** has successfully unlocked with a passcode the
/// server accepted.
///
/// In memory only — never SharedPreferences, never disk. It is not a
/// credential and it is not the lock's state; it is one bit of evidence that a
/// passcode exists, which is the precondition for offering "Lock now" (see
/// [WealthLockController.lockNow]). It resets on every process start, and the
/// worst consequence of that is that the Settings row offers "Set a passcode"
/// instead of "Lock now" until the next unlock — which is exactly what the
/// web's own Settings switch does.
final wealthUnlockedHereProvider = StateProvider<bool>((ref) => false);

/// Drops every cached read whose bytes may differ between locked and unlocked.
///
/// The web drops four query keys on both lock and unlock — `dashboard`,
/// `reports`, `holdings`, `networth` (bundle `HM()` @715585) — and that refetch
/// is the strongest evidence we have that the server returns different data
/// depending on the flag. This is the same set, expanded to the providers that
/// stand behind those keys here, plus `stocks`: the web does not invalidate it,
/// but the Stocks screen is behind the same gate and a portfolio fetched while
/// unlocked must not survive into a locked session.
///
/// Called on **both** transitions, so nothing fetched in one state can ever be
/// painted in the other.
void invalidateWealthReads(Ref ref) {
  // ── Phase 6.3, and it must stay the FIRST statement ──────────────────────
  // Barrier three. The in-memory half of this runs synchronously, so a
  // provider re-read triggered by the invalidations below cannot race a
  // still-present entry. One edit covers all four call sites — the
  // controller's unlock and its lock, the settings path, and
  // `wealthVisibilityWatcherProvider`'s "flipped underneath us on resume"
  // transition — so there is no new place to forget.
  //
  // Two barriers already make the replay bug unconstructable on their own (a
  // wealth-sensitive body is never WRITTEN unless the scope is open, and never
  // SERVED unless the scope is open). This is the belt to those braces.
  try {
    unawaited(ref.read(apiClientProvider).cache.dropWealthSensitive());
  } on Object {
    // Barrier three must never be able to stop the invalidations below, which
    // are the mechanism that actually re-reads the gated figures. If the cache
    // is unreachable (a container without an ApiClient, a disposed client) the
    // other two barriers still hold: a wealth-sensitive body is never written
    // unless the scope is open, and never served unless the scope is open.
  }

  ref
    // networth
    ..invalidate(netWorthHistoryProvider)
    ..invalidate(netWorthHistoryRangeProvider)
    ..invalidate(netWorthLatestProvider)
    ..invalidate(netWorthSeriesProvider)
    // holdings
    ..invalidate(holdingsProvider)
    // stocks — ours, not the web's
    ..invalidate(stockPortfolioProvider)
    ..invalidate(stockSalesProvider)
    ..invalidate(stockSplitsProvider)
    // dashboard
    ..invalidate(dashboardSummaryProvider)
    ..invalidate(dashboardTrendProvider)
    ..invalidate(dashboardCategoryProvider)
    ..invalidate(accountsProvider)
    // reports + insights
    ..invalidate(reportsSummaryProvider)
    ..invalidate(reportsByCategoryProvider)
    ..invalidate(reportsByAccountProvider)
    ..invalidate(reportsTrendProvider)
    ..invalidate(insightsProvider);
}

/// Which panel the unlock sheet is showing.
enum WealthUnlockPhase {
  /// The opening `GET /auth/me` preflight is in flight.
  checking,

  /// Show the passcode field.
  ready,

  /// The preflight could not reach the server. There is no offline unlock, so
  /// the sheet says so instead of offering a field that cannot work.
  offline,

  /// The lock is already off — someone unlocked it elsewhere, or it was never
  /// on. Close, don't ask for a passcode we do not need.
  alreadyUnlocked,
}

class WealthLockState {
  const WealthLockState({
    this.phase = WealthUnlockPhase.checking,
    this.busy = false,
    this.error,
    this.expiredSession = false,
  });

  final WealthUnlockPhase phase;

  /// An unlock or a lock is in flight.
  final bool busy;

  /// The last failure, already turned into a sentence the sheet can print.
  final String? error;

  /// The server has stopped accepting this session, so no passcode can help.
  /// Shares the `offline` phase with a genuine connection failure but needs a
  /// different icon, title and — the part that mattered — a different action:
  /// "Try again" can only repeat the 401.
  final bool expiredSession;

  WealthLockState copyWith({
    WealthUnlockPhase? phase,
    bool? busy,
    String? error,
    bool? expiredSession,
    bool clearError = false,
  }) {
    return WealthLockState(
      phase: phase ?? this.phase,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      expiredSession: expiredSession ?? this.expiredSession,
    );
  }
}

/// The **only** place in this app that calls `POST /auth/unlock-wealth` or
/// `POST /auth/lock-wealth`.
///
/// ## The stranding trap, and how [lockNow] is structurally closed
///
/// `POST /auth/lock-wealth` takes no body. It would therefore succeed today,
/// against an account with `wealthLockEnabled: false` and **no passcode set** —
/// and if the server accepts that, the owner is locked out of Net Worth and
/// Stocks on the phone *and* in the browser with no passcode that can open
/// them. That is the pre-close incident again.
///
/// So [lockNow] refuses unless there is positive evidence a passcode exists:
/// either `settings.wealthLockEnabled` is true, or this process has already
/// unlocked with a passcode the server accepted. The Settings row applies the
/// same test before it renders the button at all, so there are two independent
/// guards, and `test/wealth_lock_test.dart` drives the whole UI with a fake
/// that throws if the endpoint is reached.
class WealthLockController extends StateNotifier<WealthLockState> {
  WealthLockController(this._ref) : super(const WealthLockState());

  final Ref _ref;

  AuthRepository get _auth => _ref.read(authRepositoryProvider);

  /// Opens the sheet's session: re-read `GET /auth/me` before showing a field.
  ///
  /// Answers three questions in one request — is there a connection, is the
  /// lock still on, and is the flag we are holding current — and each answer
  /// has a different panel.
  /// The way out of an expired session, offered from the unlock sheet.
  ///
  /// The sheet used to print "please sign in again" with no control that could
  /// do it — signing in again means signing out first, and from a modal sheet
  /// there was nothing to tap. Mirrors the sign-out the lock screen and
  /// Settings already perform: end the session, then drop the persisted cookie
  /// so the next launch reaches the login form rather than a stale 401 loop.
  Future<void> signOut() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _ref.read(authControllerProvider.notifier).signOut();
      await _ref.read(apiClientProvider).clearSession();
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  Future<void> preflight() async {
    state = const WealthLockState(phase: WealthUnlockPhase.checking);
    try {
      final user = await _auth.me();
      if (user == null) {
        // 401/403: the session is gone. Say nothing about passcodes; the
        // router is about to send them to /login anyway.
        state = state.copyWith(
          phase: WealthUnlockPhase.offline,
          expiredSession: true,
          error:
              'You have been signed out. Sign in again to reach Net Worth — '
              'none of your data is affected.',
        );
        return;
      }
      _ref.read(authControllerProvider.notifier).applyUser(user);
      final locked = user.mode != 'superadmin' && user.wealthLockEnabled;
      state = state.copyWith(
        phase: locked
            ? WealthUnlockPhase.ready
            : WealthUnlockPhase.alreadyUnlocked,
        clearError: true,
      );
    } catch (error) {
      final failure = ApiException.from(error);
      state = state.copyWith(
        phase: _isOffline(failure)
            ? WealthUnlockPhase.offline
            : WealthUnlockPhase.ready,
        error: _isOffline(failure) ? null : failure.message,
      );
    }
  }

  /// `POST /auth/unlock-wealth {passcode}` → `{user}`.
  ///
  /// Returns true when the server accepted it. On success the returned user is
  /// what re-gates the app, every gated cache is dropped, and settings is
  /// re-read so the Settings row stops offering the wrong buttons.
  Future<bool> unlock(String passcode) async {
    if (state.busy) return false;
    if (passcode.isEmpty) {
      state = state.copyWith(error: 'Enter your wealth passcode.');
      return false;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      final user = await _auth.unlockWealth(passcode);
      _ref.read(authControllerProvider.notifier).applyUser(user);
      _ref.read(wealthUnlockedHereProvider.notifier).state = true;
      invalidateWealthReads(_ref);
      _ref.invalidate(settingsProvider);
      // Stays on `ready` rather than flipping to `alreadyUnlocked`: the sheet
      // pops itself on a true return, and a phase change racing that pop is
      // how a sheet ends up dismissed twice with the wrong result.
      state = const WealthLockState(phase: WealthUnlockPhase.ready);
      return true;
    } catch (error) {
      final failure = ApiException.from(error);
      state = state.copyWith(
        busy: false,
        phase: _isOffline(failure)
            ? WealthUnlockPhase.offline
            : WealthUnlockPhase.ready,
        error: _isOffline(failure) ? null : unlockFailureMessage(failure),
      );
      return false;
    }
  }

  /// `POST /auth/lock-wealth` — **no body**. Returns null on success, or a
  /// sentence explaining why nothing was sent.
  ///
  /// Read the class doc before touching this. The guard is not a nicety.
  Future<String?> lockNow() async {
    if (state.busy) return null;
    if (!_ref.read(canRelockProvider)) return kNoPasscodeRefusal;

    state = state.copyWith(busy: true, clearError: true);
    try {
      final user = await _auth.lockWealth();
      _ref.read(authControllerProvider.notifier).applyUser(user);
      _ref.read(wealthUnlockedHereProvider.notifier).state = false;
      invalidateWealthReads(_ref);
      _ref.invalidate(settingsProvider);
      state = const WealthLockState(phase: WealthUnlockPhase.ready);
      return null;
    } catch (error) {
      final failure = ApiException.from(error);
      state = state.copyWith(busy: false, error: failure.message);
      return failure.message;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  static bool _isOffline(ApiException error) =>
      error.code == 'NO_CONNECTION' || error.code == 'TIMEOUT';
}

/// Why a lock request was refused before it was sent.
const String kNoPasscodeRefusal =
    'Set a passcode first — locking without one could hide Net Worth with '
    'nothing that can reveal it again.';

/// Positive evidence that a wealth passcode exists on the account.
///
/// The precondition for `POST /auth/lock-wealth`. `settings.wealthLockEnabled`
/// is the account's own answer; [wealthUnlockedHereProvider] covers the case
/// where this process just unlocked with a passcode the server accepted and the
/// settings document has not been re-read yet.
final wealthPasscodeExistsProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  // A settings document we actually hold is authoritative in BOTH directions.
  // This used to fall through to the in-memory bit whenever the document said
  // `false`, so a passcode cleared on another client left this phone still
  // believing one existed: "Lock now" stayed on screen, and
  // `POST /auth/lock-wealth` takes NO BODY — it would have succeeded and hidden
  // Net Worth and Stocks behind a passcode that no longer exists, with nothing
  // in the app able to unlock it.
  if (settings != null) return settings.wealthLockEnabled;
  // Only when the document is genuinely unknown does the fact that THIS process
  // unlocked with a passcode the server accepted stand in for it.
  return ref.watch(wealthUnlockedHereProvider);
});

/// Whether a "Lock now" control may exist at all: a passcode is known to
/// exist, and the figures are not already hidden.
///
/// A provider rather than a helper so the Settings row and
/// [WealthLockController.lockNow] cannot drift apart, and so a test can assert
/// the condition directly instead of inferring it from a rendered button.
final canRelockProvider = Provider<bool>((ref) {
  if (ref.watch(wealthVisibilityProvider) == WealthVisibility.locked) {
    return false;
  }
  return ref.watch(wealthPasscodeExistsProvider);
});

/// Turns an unlock failure into one honest sentence.
///
/// A wrong passcode comes back as a 400/401 from `/auth/unlock-wealth`; the
/// auth limiter (10 requests / 900s) answers 429. Neither is "something went
/// wrong", and the 429 in particular must say **who** is refusing — this app
/// has no cooldown of its own here, unlike the device lock in `features/lock/`.
String unlockFailureMessage(ApiException error) {
  if (error.isRateLimited) {
    return 'Too many attempts. Wait a while before trying again — it is the '
        'server refusing new tries, not this app.';
  }
  if (error.statusCode == 400 ||
      error.isUnauthorized ||
      error.isForbidden ||
      error.isValidation) {
    return "That passcode didn't match.";
  }
  return error.message;
}

final wealthLockControllerProvider =
    StateNotifierProvider<WealthLockController, WealthLockState>((ref) {
      // Reading the watcher here is what keeps it alive — it has no other
      // consumer, and a transition nothing is listening to would silently stop
      // dropping the gated caches.
      ref.watch(wealthVisibilityWatcherProvider);
      return WealthLockController(ref);
    });
