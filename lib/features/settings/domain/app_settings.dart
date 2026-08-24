import '../../../core/api/json.dart';

/// `GET /settings`
class AppSettings {
  const AppSettings({
    this.id = '',
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
  final String name;
  final String description;
  final String baseCurrency;

  /// 'light' | 'dark' | 'system'
  final String theme;
  final String locale;
  final String language;

  /// 1 = Monday … 7 = Sunday, matching DateTime.weekday.
  final int firstDayOfWeek;
  final int monthStartDay;
  final bool pinEnabled;
  final bool emailReports;
  final bool wealthLockEnabled;
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

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    id: J.id(json['_id']),
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

  Map<String, dynamic> toPatchJson() => {
    'name': name,
    'description': description,
    'baseCurrency': baseCurrency,
    'theme': theme,
    'locale': locale,
    'language': language,
    'firstDayOfWeek': firstDayOfWeek,
    'monthStartDay': monthStartDay,
    'emailReports': emailReports,
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
  final num rateToBase;

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
