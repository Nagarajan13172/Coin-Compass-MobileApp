import '../../../core/api/json.dart';

/// `GET /auth/providers` — which third-party sign-ins this deployment has
/// configured.
///
/// Live response (26 Aug 2026):
///
///     {"google":true,"github":false,"microsoft":false,"apple":false}
///
/// The endpoint has existed in `Endpoints` since phase 1 and was never called:
/// the login screen hardcoded a Google button. That worked only because Google
/// happens to be the one provider this deployment enables — the app was
/// advertising a fixed list and would have gone on advertising it if the server
/// turned Google off.
class AuthProvidersConfig {
  const AuthProvidersConfig({
    this.google = false,
    this.github = false,
    this.microsoft = false,
    this.apple = false,
  });

  /// Nothing configured. The value the login screen falls back to when the
  /// call fails — see [LoginScreen]: a button that cannot work is worse than
  /// no button, and email sign-in is unaffected.
  static const AuthProvidersConfig none = AuthProvidersConfig();

  final bool google;
  final bool github;
  final bool microsoft;
  final bool apple;

  bool get hasAny => google || github || microsoft || apple;

  /// Tolerant of a server that adds a provider this build predates: unknown
  /// keys are ignored rather than throwing, matching every other `fromJson`
  /// in this app.
  factory AuthProvidersConfig.fromJson(Object? json) {
    final map = J.map(json);
    return AuthProvidersConfig(
      google: J.boolean(map['google']),
      github: J.boolean(map['github']),
      microsoft: J.boolean(map['microsoft']),
      apple: J.boolean(map['apple']),
    );
  }
}
