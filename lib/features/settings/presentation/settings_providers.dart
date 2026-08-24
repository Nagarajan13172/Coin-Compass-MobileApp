import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/theme_controller.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../lock/presentation/lock_controller.dart';
import '../../wealth_lock/presentation/wealth_lock_providers.dart';
import '../data/settings_repository.dart';

/// Which write the Settings screen currently has in flight.
///
/// One at a time on purpose: every one of these ends in
/// `ref.invalidate(settingsProvider)`, and two overlapping writes would race
/// each other's refetch and leave the screen showing whichever landed second.
enum SettingsWrite {
  wallet,
  baseCurrency,
  emailReports,
  theme,
  pin,
  disablePin,
  wealthPasscode,
  disableWealthPasscode,
  signOut,
}

/// Every mutation the Settings screen can make, funnelled through one place so
/// the request bodies stay exactly the five keys the deployed web client sends.
///
/// The controller never builds a body itself — [SettingsRepository] owns the
/// five builders (`walletBody`, `baseCurrencyBody`, `emailReportsBody`,
/// `themeBody`, plus `pinBody` / `passcodeBody` for the two locks), and
/// `test/write_schema_test.dart` pins their key lists. The backend strips
/// unknown keys **silently**, so a stray key here would not fail — it would
/// quietly drop the user's change.
///
/// State is the pending write (or null when idle) so a row can show its own
/// spinner without every other row disabling itself for the wrong reason.
class SettingsWriteController extends StateNotifier<SettingsWrite?> {
  SettingsWriteController(this._ref) : super(null);

  final Ref _ref;

  SettingsRepository get _repo => _ref.read(settingsRepositoryProvider);

  /// `PUT /settings {name, description}` — always both keys, as on the web.
  Future<String?> saveWallet({
    required String name,
    required String description,
  }) => _run(
    SettingsWrite.wallet,
    () => _repo.updateWallet(name: name, description: description),
  );

  /// `PUT /settings {baseCurrency}` — [code] is a row of the server-seeded
  /// currency table, which is read-only everywhere else.
  Future<String?> setBaseCurrency(String code) =>
      _run(SettingsWrite.baseCurrency, () => _repo.updateBaseCurrency(code));

  /// `PUT /settings {emailReports}`
  Future<String?> setEmailReports(bool enabled) =>
      _run(SettingsWrite.emailReports, () => _repo.updateEmailReports(enabled));

  /// Applies the theme locally **first** so the tap feels instant, then
  /// persists it.
  ///
  /// PARITY NOTE: the web's /settings theme buttons are device-local and send
  /// nothing ("Applies instantly, on this device only"); only its top-bar
  /// dropdown persists `{theme}`, and that dropdown is `hidden sm:flex`, so a
  /// phone-width web session cannot persist the theme at all. Persisting it
  /// from the mobile toggle is the sane behaviour and is a deliberate
  /// divergence. A failed PUT leaves the local choice in place — losing the
  /// theme the user just picked because the network blinked would be worse
  /// than a settings row that is briefly out of sync.
  Future<String?> setTheme(ThemeMode mode) async {
    await _ref.read(themeControllerProvider.notifier).set(mode);
    return _run(
      SettingsWrite.theme,
      () => _repo.updateTheme(ThemeController.toApi(mode)),
    );
  }

  /// `POST /settings/pin {pin}` — 4–8 digits, validated inside the repository
  /// before anything leaves the device.
  ///
  /// ⚠️ Setting a PIN the owner does not know locks them out of their own app
  /// on the next cold start, and the only recovery is disabling it from an
  /// already-unlocked session. Never fire this from a test or a probe.
  Future<String?> setPin(String pin) =>
      _run(SettingsWrite.pin, () => _repo.setPin(pin));

  /// `DELETE /settings/pin` — no body.
  Future<String?> disablePin() =>
      _run(SettingsWrite.disablePin, _repo.disablePin);

  /// `POST /settings/wealth-passcode {passcode}` — 4–32 characters.
  ///
  /// Followed by [_afterWealthWrite]: this changes what the server will show,
  /// so the settings document is not the only thing that has gone stale.
  Future<String?> setWealthPasscode(String passcode) =>
      _run(SettingsWrite.wealthPasscode, () async {
        await _repo.setWealthPasscode(passcode);
        await _afterWealthWrite();
      });

  /// `DELETE /settings/wealth-passcode` — no body.
  Future<String?> disableWealthPasscode() =>
      _run(SettingsWrite.disableWealthPasscode, () async {
        await _repo.disableWealthPasscode();
        await _afterWealthWrite();
      });

  /// Re-reads the user and drops the gated caches after either wealth-passcode
  /// write.
  ///
  /// Both of them change the account's lock state, and the **gate** is derived
  /// from `user.wealthLockEnabled` on `GET /auth/me` — not from the settings
  /// document. Invalidating only `settingsProvider`, as these used to, would
  /// leave the app rendering Net Worth from a stale `AppUser` after the owner
  /// had just set a passcode.
  ///
  /// Clearing the passcode also clears this process's "we unlocked here" bit:
  /// with no passcode on the account there is nothing left that a "Lock now"
  /// button could be re-opened with.
  Future<void> _afterWealthWrite() async {
    await _ref.read(authControllerProvider.notifier).refreshUser();
    _ref.read(wealthUnlockedHereProvider.notifier).state = false;
    invalidateWealthReads(_ref);
  }

  /// `POST /auth/logout` (no body) **and** a cookie-jar wipe.
  ///
  /// [AuthRepository.signOut] posts the endpoint and clears the jar in a
  /// `finally`, so the cookie goes even when the request fails; the extra
  /// [ApiClient.clearSession] here is belt-and-braces, and idempotent. The
  /// router's redirect does the navigating — it re-runs the moment auth state
  /// flips to signedOut.
  ///
  /// ⚠️ This kills the session the whole project depends on. Never fire it
  /// during development.
  Future<String?> signOut() => _run(SettingsWrite.signOut, () async {
    await _ref.read(authControllerProvider.notifier).signOut();
    await _ref.read(apiClientProvider).clearSession();
    // Wipe the app lock too. `LockStore.clear()` documents itself as being
    // called on sign-out, but only the lock screen's own sign-out did it — so
    // signing out from Settings left the previous account's PIN verifier and
    // enabled flag on the phone, and the next person to sign in on that device
    // met a lock screen wanting a PIN that was never theirs.
    await _ref.read(lockStoreProvider).clear();
    _ref.invalidate(appLockControllerProvider);
  }, refreshSettings: false);

  /// Runs [action] with [key] pending, refetches settings on success, and
  /// returns the failure message (or null when it worked) for the caller to
  /// put in a SnackBar.
  Future<String?> _run(
    SettingsWrite key,
    Future<void> Function() action, {
    bool refreshSettings = true,
  }) async {
    // Drop the second tap rather than queueing it: the first write is still
    // deciding what the server holds.
    if (state != null) return null;
    state = key;
    try {
      await action();
      if (refreshSettings) _ref.invalidate(settingsProvider);
      return null;
    } catch (error) {
      return ApiException.from(error).message;
    } finally {
      // `mounted` here is StateNotifier's own flag, not `ref.mounted` (which
      // this codebase bans and Riverpod 2.6.1 does not have on Ref anyway).
      if (mounted) state = null;
    }
  }
}

final settingsWriteControllerProvider =
    StateNotifierProvider<SettingsWriteController, SettingsWrite?>(
      (ref) => SettingsWriteController(ref),
    );
