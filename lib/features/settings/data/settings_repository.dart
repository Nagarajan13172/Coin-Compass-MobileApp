import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../../../core/utils/money.dart';
import '../domain/app_settings.dart';

/// `/settings` — the wallet-settings document, its PIN and its Net Worth
/// passcode.
///
/// ## The verb is PUT, not PATCH
///
/// SPEC.md says `GET|PATCH /settings`; the deployed web client disagrees, and
/// it is the one that works:
///
///   function lm(){return ne({mutationFn:async e=>(await q.put("/settings",e)).data,…})}
///
/// `patch("/settings` appears **zero** times across all five bundle files.
/// Whether the backend also accepts PATCH is unknown and must not be probed
/// against a live account, so this uses the verb the working client uses.
///
/// ## One concern per request
///
/// There is no "save the whole settings object" anywhere in the web client.
/// The mutation is called from three places and issues exactly five bodies:
///
///   {name, description}   the Wallet card's Save button — always both keys
///   {baseCurrency}        the currency select
///   {language}            the language select
///   {emailReports}        the email-reports switch
///   {theme}               the top-bar theme dropdown
///
/// That is the whole write vocabulary. `locale`, `firstDayOfWeek`,
/// `monthStartDay`, `currencies`, `pinEnabled` and `wealthLockEnabled` are
/// **never sent**: the backend strips unknown keys silently, so a wrong guess
/// does not fail — it just loses the value. Each body below is built by its own
/// method so no screen can widen one, and `test/write_schema_test.dart` pins
/// every key list.
class SettingsRepository {
  const SettingsRepository(this._api);

  final ApiClient _api;

  Future<AppSettings> get() async {
    final json = await _api.getJson(Endpoints.settings);
    return AppSettings.fromJson(_unwrap(json));
  }

  // ── writes: /settings ─────────────────────────────────────────────────────

  /// The Wallet card. Both keys always travel together, as they do on the web.
  /// An empty name is rejected client-side — the web toasts "Wallet name can't
  /// be empty" and sends nothing.
  Future<AppSettings> updateWallet({
    required String name,
    required String description,
  }) {
    if (name.trim().isEmpty) {
      throw ApiException(
        message: "Wallet name can't be empty",
        code: 'VALIDATION_FAILED',
        fieldErrors: const {
          'name': ["Wallet name can't be empty"],
        },
      );
    }
    return _put(walletBody(name, description));
  }

  /// [code] is a `CurrencyOption.code` from `settings.currencies` — the table
  /// is server-seeded and read-only, so this only ever picks one of its rows.
  Future<AppSettings> updateBaseCurrency(String code) =>
      _put(baseCurrencyBody(code));

  /// [code] is `en` or `ta`; the web ignores anything else rather than sending
  /// it, and so does this.
  Future<AppSettings> updateLanguage(String code) {
    if (!supportedLanguages.contains(code)) {
      throw ApiException(
        message: 'Unsupported language: $code',
        code: 'VALIDATION_FAILED',
      );
    }
    return _put(languageBody(code));
  }

  Future<AppSettings> updateEmailReports(bool enabled) =>
      _put(emailReportsBody(enabled));

  /// PARITY NOTE: the web's /settings theme buttons are **device-local** —
  /// they call the zustand setter and send nothing ("Applies instantly, on this
  /// device only"), and only the top-bar dropdown persists `{theme}`. That
  /// dropdown is `hidden sm:flex`, so a phone-width web session cannot persist
  /// the theme at all. Persisting it from the mobile toggle is the sane
  /// behaviour and is what this method is for, but it IS a divergence.
  Future<AppSettings> updateTheme(String theme) {
    if (!supportedThemes.contains(theme)) {
      throw ApiException(
        message: 'Unsupported theme: $theme',
        code: 'VALIDATION_FAILED',
      );
    }
    return _put(themeBody(theme));
  }

  // ── writes: PIN lock ──────────────────────────────────────────────────────
  //
  // ⚠️ NEVER CALL DURING DEVELOPMENT. Setting a PIN the owner does not know
  // locks them out of their own app on next launch, and there is no recovery
  // path in the client other than disabling it from an already-unlocked
  // session.

  /// 4–8 digits, validated the way the web validates it (`/^\d{4,8}$/`) before
  /// anything leaves the device.
  Future<void> setPin(String pin) async {
    if (!_pinPattern.hasMatch(pin)) {
      throw ApiException(
        message: 'The PIN must be 4 to 8 digits.',
        code: 'VALIDATION_FAILED',
        fieldErrors: const {
          'pin': ['The PIN must be 4 to 8 digits.'],
        },
      );
    }
    await _api.postJson(Endpoints.settingsPin, body: pinBody(pin));
  }

  /// The PIN gate's only check. Returns the response's `ok` flag; a wrong PIN
  /// is a `false`, not an error.
  Future<bool> verifyPin(String pin) async {
    final json = await _api.postJson(
      Endpoints.settingsPinVerify,
      body: pinBody(pin),
    );
    return J.boolean(J.map(json)['ok']);
  }

  /// Turns the PIN lock off. No body, no confirmation server-side — the web
  /// fires this straight from the "Disable" button.
  Future<void> disablePin() => _api.deleteJson(Endpoints.settingsPin);

  // ── writes: Net Worth passcode ────────────────────────────────────────────
  //
  // ⚠️ NEVER CALL DURING DEVELOPMENT — same reasoning as the PIN.

  /// 4–32 characters, any characters (unlike the PIN, this one is not digits).
  Future<void> setWealthPasscode(String passcode) async {
    if (passcode.length < 4 || passcode.length > 32) {
      throw ApiException(
        message: 'The passcode must be 4 to 32 characters.',
        code: 'VALIDATION_FAILED',
        fieldErrors: const {
          'passcode': ['The passcode must be 4 to 32 characters.'],
        },
      );
    }
    await _api.postJson(
      Endpoints.settingsWealthPasscode,
      body: passcodeBody(passcode),
    );
  }

  Future<void> disableWealthPasscode() =>
      _api.deleteJson(Endpoints.settingsWealthPasscode);

  // ── the five write bodies, and nothing else ───────────────────────────────
  //
  // Public and static so they can be asserted directly in a unit test as well
  // as read out of this source by the write-schema guard. They build a map;
  // they never send one.

  static Map<String, dynamic> walletBody(String name, String description) => {
    'name': name.trim(),
    'description': description.trim(),
  };

  static Map<String, dynamic> baseCurrencyBody(String code) => {
    'baseCurrency': code,
  };

  static Map<String, dynamic> languageBody(String code) => {'language': code};

  static Map<String, dynamic> emailReportsBody(bool enabled) => {
    'emailReports': enabled,
  };

  static Map<String, dynamic> themeBody(String theme) => {'theme': theme};

  static Map<String, dynamic> pinBody(String pin) => {'pin': pin};

  static Map<String, dynamic> passcodeBody(String passcode) => {
    'passcode': passcode,
  };

  static const Set<String> supportedLanguages = {'en', 'ta'};
  static const Set<String> supportedThemes = {'light', 'dark', 'system'};
  static final RegExp _pinPattern = RegExp(r'^\d{4,8}$');

  Future<AppSettings> _put(Map<String, dynamic> body) async {
    final json = await _api.putJson(Endpoints.settings, body: body);
    return AppSettings.fromJson(_unwrap(json));
  }

  /// The live GET returns the document bare; the PUT response is unverified
  /// against this deployment, so tolerate a `{settings: {...}}` wrapper too.
  static Map<String, dynamic> _unwrap(Object? json) {
    final map = J.map(json);
    final nested = map['settings'];
    if (nested is Map) return nested.cast<String, dynamic>();
    return map;
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(apiClientProvider)),
);

/// Cached on purpose (no autoDispose): settings drive the theme, the currency
/// symbol and the week start, so every screen reads them and a refetch per
/// screen would be wasteful. Call `ref.invalidate(settingsProvider)` after a
/// successful write.
final settingsProvider = FutureProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).get(),
);

/// The server-seeded currency table, for the base-currency select and the
/// per-account currency select. Empty until settings load; read-only.
final currencyOptionsProvider = Provider<List<CurrencyOption>>(
  (ref) => ref.watch(settingsProvider).valueOrNull?.currencies ?? const [],
);

/// The base-currency symbol, so no screen has to re-derive it. Defaults to `₹`
/// while settings are loading (or if they fail), which matches the account this
/// app ships against.
final currencySymbolProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  if (settings == null) return Money.rupee;

  for (final currency in settings.currencies) {
    if (currency.code == settings.baseCurrency && currency.symbol.isNotEmpty) {
      return currency.symbol;
    }
  }
  return Money.symbolFor(settings.baseCurrency);
});
