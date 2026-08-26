import 'package:coincompass/features/auth/domain/auth_providers_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.2 — the login screen asks the server what it supports.**
///
/// `/auth/providers` existed in `Endpoints` from phase 1 and was never called;
/// the login screen hardcoded a Google button. That was right by luck. These
/// pin the parse, including the shapes that would make the screen advertise a
/// provider the deployment does not have.
void main() {
  group('the live response', () {
    test('parses exactly what the deployment returns', () {
      // Verified against https://coincompass.sathishkumar.cloud/api on
      // 26 Aug 2026.
      final config = AuthProvidersConfig.fromJson(const {
        'google': true,
        'github': false,
        'microsoft': false,
        'apple': false,
      });

      expect(config.google, isTrue);
      expect(config.github, isFalse);
      expect(config.microsoft, isFalse);
      expect(config.apple, isFalse);
      expect(config.hasAny, isTrue);
    });
  });

  group('degrading safely', () {
    test('a provider the server never mentions is off', () {
      final config = AuthProvidersConfig.fromJson(const {'google': true});
      expect(config.google, isTrue);
      expect(config.apple, isFalse);
    });

    test('an empty document offers nothing', () {
      final config = AuthProvidersConfig.fromJson(const <String, dynamic>{});
      expect(config.hasAny, isFalse);
    });

    test('junk offers nothing rather than throwing', () {
      // The login screen is the first thing a cold start paints. A parse throw
      // here would be a crash before anyone could type a password.
      expect(AuthProvidersConfig.fromJson(null).hasAny, isFalse);
      expect(AuthProvidersConfig.fromJson('nonsense').hasAny, isFalse);
      expect(AuthProvidersConfig.fromJson(const []).hasAny, isFalse);
    });

    test('a non-boolean value is not truthy', () {
      // `"google": "yes"` must not light the button up.
      final config = AuthProvidersConfig.fromJson(const {'google': 'yes'});
      expect(config.google, isFalse);
    });

    test('every provider off means the whole social block is hidden', () {
      final config = AuthProvidersConfig.fromJson(const {
        'google': false,
        'github': false,
        'microsoft': false,
        'apple': false,
      });
      expect(config.hasAny, isFalse);
    });

    test('the fallback used when the call fails offers nothing', () {
      expect(AuthProvidersConfig.none.hasAny, isFalse);
    });
  });
}
