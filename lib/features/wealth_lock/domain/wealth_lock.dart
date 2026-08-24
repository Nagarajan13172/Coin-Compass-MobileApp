/// The Net Worth lock's rules, as pure Dart.
///
/// No Flutter and no Riverpod imports on purpose — the same precedent
/// `features/lock/domain/lock_state.dart` set for the app lock. What lives here
/// is the part worth unit-testing without a widget binding: which routes are
/// gated, what the three visibility states mean, and the one assumption about
/// the server that the whole feature hangs from.
///
/// ## This lock is the OPPOSITE of the app lock — read this before copying 6.1
///
/// `features/lock/` is device-local by design: its PIN never leaves the phone,
/// it is checked on the device, and it works in aeroplane mode. This one is
/// server-mirrored by necessity. The truth is `user.wealthLockEnabled` on
/// `GET /auth/me`, the passcode only ever exists server-side, and the only
/// unlock is `POST /auth/unlock-wealth {passcode}`. There is deliberately no
/// local verifier, no cached passcode, no biometric path and no offline mode:
/// inventing one would let the phone and the browser disagree about whether the
/// owner's net worth is visible, which is the single failure this lock exists
/// to prevent.
library;

/// What the app currently knows about the Net Worth lock.
enum WealthVisibility {
  /// The figures may be shown, and the gated reads may be issued.
  visible,

  /// We are re-reading `GET /auth/me` and do not know yet. Gated surfaces show
  /// a placeholder — never a value, never a zero.
  checking,

  /// `user.wealthLockEnabled` is true (and the user is not a superadmin).
  locked,
}

/// The routes the web hides while the lock is on.
///
/// `["/net-worth", "/stocks"]` is verbatim from the deployed bundle (`UM`).
/// `/net-worth/holdings` is ours: the web has no such route because it renders
/// holdings *inside* `/net-worth`, but it drops the `holdings` query key on
/// every lock and unlock and its own settings copy names what is hidden as
/// "Net Worth (holdings & net-worth totals)". Leaving it open would be a hole
/// straight through the gate.
const Set<String> kWealthGatedPaths = {
  '/net-worth',
  '/stocks',
  '/net-worth/holdings',
};

/// True when [location] is one of the gated routes.
///
/// Compares the path only: a query string or a trailing slash must not be a way
/// round the gate. Sub-paths count too, so a future `/stocks/anything` is gated
/// by construction rather than by remembering to add it here.
bool isWealthGatedPath(String location) {
  var path = location.trim();
  if (path.isEmpty) return false;

  final queryAt = path.indexOf(RegExp(r'[?#]'));
  if (queryAt >= 0) path = path.substring(0, queryAt);
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  for (final gated in kWealthGatedPaths) {
    if (path == gated || path.startsWith('$gated/')) return true;
  }
  return false;
}

/// **The one assumption in Phase 6.2, in one place, so it can be flipped in one
/// edit when the truth is known.**
///
/// ASSUMED, NOT TESTED. Flipping `wealthLockEnabled` on the owner's live
/// account is on the never-call list — `POST /auth/lock-wealth` takes no body,
/// would therefore succeed, and with no passcode set could strand the owner out
/// of Net Worth and Stocks on both clients — so nobody has ever seen what the
/// API returns while the lock is on.
///
/// The guess: while the lock is on the server may return **zeroed or empty**
/// payloads for exactly the four reads the web drops on a lock or unlock
/// (`dashboard`, `reports`, `holdings`, `networth` — bundle `HM()` @715585,
/// verified verbatim), and unchanged payloads for everything else. Two facts
/// point that way: a purely client-side curtain would need no refetch at all,
/// so those four invalidations are evidence the bytes change; and the web's own
/// settings string says "Income, expenses and cash flow are always visible",
/// so `/reports/summary`'s income/expense/net are almost certainly real even
/// while locked and only a net-worth total is a redaction candidate.
///
/// While this is true the app treats every figure from those reads as
/// **unknown** rather than as zero, and simply does not issue them. That kills
/// a live false-statement bug: `NetWorthCard` falls back to `value = 0` when
/// the history is empty and there is no error, so a redacted locked response
/// would render "₹0" as the owner's net worth when the truth is −₹2,00,00,000.
///
/// Set this to `false` once someone has seen a locked response carry real
/// figures. Nothing else in the app has to change: gated reads would then be
/// allowed to run while locked, and the surfaces would stay hidden anyway
/// because the web hides them. `test/wealth_lock_test.dart` pins the invariant
/// either way.
const bool kWealthLockedResponsesAreUntrusted = true;

/// Whether a read that the web drops on a lock/unlock may be issued right now.
///
/// The single consumer of [kWealthLockedResponsesAreUntrusted]. Every gated
/// read in the app goes through this — the three gated screens, the dashboard's
/// pull-to-refresh, and the unlock/lock success path.
bool wealthReadAllowed(WealthVisibility visibility) =>
    visibility == WealthVisibility.visible ||
    !kWealthLockedResponsesAreUntrusted;

/// Whether a figure may be painted right now. Stricter than [wealthReadAllowed]
/// on purpose: even if we were allowed to *fetch* while locked, we would still
/// never *show* it, because the web does not.
bool wealthFiguresVisible(WealthVisibility visibility) =>
    visibility == WealthVisibility.visible;

/// The visibility predicate, copied from the deployed bundle:
///
///     function no(){ const {data:e} = Jn();
///       return e ? e.mode === "superadmin" || !e.wealthLockEnabled : false }
///
/// [mode] and [lockEnabled] come from the user object on `GET /auth/me`, never
/// from `/settings` — see the note on the two flags in
/// `wealth_lock_providers.dart`. A superadmin bypasses the lock entirely; the
/// owner's mode is `user`.
WealthVisibility wealthVisibilityFor({
  required String mode,
  required bool lockEnabled,
  required bool refreshing,
}) {
  if (mode == 'superadmin') return WealthVisibility.visible;
  if (lockEnabled) return WealthVisibility.locked;
  return refreshing ? WealthVisibility.checking : WealthVisibility.visible;
}
