import '../../../core/api/json.dart';
import '../../../core/utils/date_x.dart';

/// `GET /settings` — the one wallet-settings document.
///
/// Every key the live GET returns is modelled, including the two the web never
/// exposes ([firstDayOfWeek], [monthStartDay]) and the ones it only reads
/// ([pinEnabled], [wealthLockEnabled], [currencies]). [toJson] reproduces the
/// read shape so a round-trip can be pinned in a test.
///
/// There is deliberately **no** write-body builder on this class, and
/// `test/write_schema_test.dart` fails if one comes back (it greps for the two
/// names such a method would have, so do not name one in a comment either).
/// Writes go one concern at a time through `SettingsRepository`, whose bodies
/// are the five the web sends and nothing else. A whole-object write is the
/// single most dangerous call this app could make against a live account: an
/// incomplete body could overwrite the server-seeded currency table.
class AppSettings {
  const AppSettings({
    this.id = '',
    this.userId = '',
    this.name = 'My Wallet',
    this.description = '',
    this.baseCurrency = 'INR',
    this.theme = 'system',
    this.locale = 'en-IN',
    this.language = 'en',
    this.firstDayOfWeek = 1,
    this.monthStartDay = 1,
    this.pinEnabled = false,
    this.emailReports = true,
    this.wealthLockEnabled = false,
    this.currencies = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// The owning user's id. Read-only; never sent back.
  final String userId;

  /// The wallet's name — editable, and NOT the user's name. The Settings
  /// screen's "Wallet name" field writes this.
  final String name;

  /// The wallet's optional label/tag. Editable alongside [name].
  final String description;
  final String baseCurrency;

  /// 'light' | 'dark' | 'system'
  final String theme;

  /// Number formatting locale, e.g. `en-IN`. Read-only: the web has no control
  /// for it and never sends it.
  final String locale;

  /// UI language, `en` or `ta`.
  final String language;

  /// 1 = Monday … 7 = Sunday, matching DateTime.weekday.
  ///
  /// Read-only as far as the web is concerned: the string `firstDayOfWeek`
  /// appears **zero** times in the deployed bundle, so no control writes it and
  /// its Zod status on PUT is unknown. This app reads it to size week windows;
  /// a mobile control for it would be writing an unverified key.
  final int firstDayOfWeek;

  /// Same story as [firstDayOfWeek] — read-only, absent from the web bundle.
  final int monthStartDay;

  /// Whether a PIN gate is set. Toggled by POST/DELETE /settings/pin, never by
  /// a PUT of this flag.
  final bool pinEnabled;
  final bool emailReports;

  /// Whether the Net Worth passcode is set. Toggled by POST/DELETE
  /// /settings/wealth-passcode.
  final bool wealthLockEnabled;

  /// The server-seeded currency table (INR/USD/EUR/GBP). Read-only everywhere:
  /// `rateToBase` appears zero times in the web bundle and there is no add,
  /// edit or remove control anywhere in the deployed client.
  final List<CurrencyOption> currencies;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CurrencyOption get base => currencies.firstWhere(
    (c) => c.code == baseCurrency,
    orElse: () => const CurrencyOption(
      code: 'INR',
      symbol: '₹',
      name: 'Indian Rupee',
      rateToBase: 1,
    ),
  );

  String get symbol => base.symbol;

  AppSettings copyWith({
    String? name,
    String? description,
    String? baseCurrency,
    String? theme,
    String? language,
    bool? emailReports,
    bool? pinEnabled,
    bool? wealthLockEnabled,
  }) => AppSettings(
    id: id,
    userId: userId,
    name: name ?? this.name,
    description: description ?? this.description,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    theme: theme ?? this.theme,
    locale: locale,
    language: language ?? this.language,
    firstDayOfWeek: firstDayOfWeek,
    monthStartDay: monthStartDay,
    pinEnabled: pinEnabled ?? this.pinEnabled,
    emailReports: emailReports ?? this.emailReports,
    wealthLockEnabled: wealthLockEnabled ?? this.wealthLockEnabled,
    currencies: currencies,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    id: J.id(json['_id']),
    userId: J.refId(json['user']) ?? '',
    name: J.str(json['name'], 'My Wallet'),
    description: J.str(json['description']),
    baseCurrency: J.str(json['baseCurrency'], 'INR'),
    theme: J.str(json['theme'], 'system'),
    locale: J.str(json['locale'], 'en-IN'),
    language: J.str(json['language'], 'en'),
    firstDayOfWeek: J.integer(json['firstDayOfWeek'], 1),
    monthStartDay: J.integer(json['monthStartDay'], 1),
    pinEnabled: J.boolean(json['pinEnabled']),
    emailReports: J.boolean(json['emailReports'], true),
    wealthLockEnabled: J.boolean(json['wealthLockEnabled']),
    currencies: J.list(json['currencies'], CurrencyOption.fromJson),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  /// The **read** shape, not a write body. Used to pin the round-trip in tests
  /// and to persist a settings snapshot locally if that is ever wanted. Sending
  /// this to the API would be exactly the whole-object write the class note
  /// warns about.
  Map<String, dynamic> toJson() => {
    '_id': id,
    'user': userId,
    'name': name,
    'description': description,
    'baseCurrency': baseCurrency,
    'theme': theme,
    'locale': locale,
    'language': language,
    'firstDayOfWeek': firstDayOfWeek,
    'monthStartDay': monthStartDay,
    'pinEnabled': pinEnabled,
    'emailReports': emailReports,
    'wealthLockEnabled': wealthLockEnabled,
    'currencies': [for (final c in currencies) c.toJson()],
    if (createdAt != null) 'createdAt': DateX.toApi(createdAt!),
    if (updatedAt != null) 'updatedAt': DateX.toApi(updatedAt!),
  };
}

class CurrencyOption {
  const CurrencyOption({
    required this.code,
    required this.symbol,
    required this.name,
    this.rateToBase = 1,
  });

  final String code;
  final String symbol;
  final String name;

  /// Seeded server-side (USD 83, EUR 90, GBP 105) and never editable — the web
  /// has no rate input, and multi-currency conversion is not enabled.
  final num rateToBase;

  /// `INR – Indian Rupee (₹)` — the base-currency select's option label.
  String get selectLabel => '$code – $name ($symbol)';

  /// `INR (₹)` — the shorter form the account form uses.
  String get shortLabel => '$code ($symbol)';

  factory CurrencyOption.fromJson(Map<String, dynamic> json) => CurrencyOption(
    code: J.str(json['code']),
    symbol: J.str(json['symbol']),
    name: J.str(json['name']),
    rateToBase: J.number(json['rateToBase'], 1),
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'symbol': symbol,
    'name': name,
    'rateToBase': rateToBase,
  };
}

/// `GET /auth/2fa/status`
class TwoFactorStatus {
  const TwoFactorStatus({
    this.enabled = false,
    this.emailFallback = true,
    this.backupCodesRemaining = 0,
  });

  final bool enabled;
  final bool emailFallback;
  final int backupCodesRemaining;

  factory TwoFactorStatus.fromJson(Map<String, dynamic> json) =>
      TwoFactorStatus(
        enabled: J.boolean(json['enabled']),
        emailFallback: J.boolean(json['emailFallback'], true),
        backupCodesRemaining: J.integer(json['backupCodesRemaining']),
      );
}

/// `POST /auth/2fa/setup` — the enrolment payload. The QR is a data URI the
/// client renders directly; [secret] is the same key in manual-entry form.
class TwoFactorEnrolment {
  const TwoFactorEnrolment({this.qrDataUrl = '', this.secret = ''});

  final String qrDataUrl;
  final String secret;

  factory TwoFactorEnrolment.fromJson(Map<String, dynamic> json) =>
      TwoFactorEnrolment(
        qrDataUrl: J.str(json['qrDataUrl']),
        secret: J.str(json['secret']),
      );
}
