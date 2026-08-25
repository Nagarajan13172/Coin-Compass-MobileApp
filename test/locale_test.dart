import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/i18n/locale_controller.dart';
import 'package:coincompass/l10n/app_localizations.dart';
import 'package:coincompass/l10n/app_localizations_en.dart';
import 'package:coincompass/l10n/app_localizations_ta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wealth_lock_fakes.dart';

/// **Phase 7.1 — the language toggle, and what now decides it.**
///
/// Before 7.1a, tapping the app bar's pill relabelled it `த`, **persisted a
/// Tamil locale**, and then carried on painting English. A "Tamil is coming
/// soon" snackbar was honest about the intent; the state was not — the app went
/// on claiming to be in a language it was not in, across restarts.
///
/// Runtime translation can reach that state a second way: the locale is Tamil
/// but ML Kit's language pack is absent or still downloading, so every lookup
/// passes English through. So availability is no longer a constant about
/// dictionary coverage — it is device state, and the pill both renders and
/// labels itself from what is actually on screen.
///
/// The locale itself is back to being a plain stored preference. See
/// `translator_test.dart` for the half that decides whether Tamil renders.
void main() {
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_locale_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('the locale is a plain preference', () {
    test('both locales are advertised to MaterialApp', () {
      // `L.supportedLocales` is what MaterialApp resolves against, and it is
      // driven by which ARB files exist — deliberately NOT by whether ML Kit's
      // pack is downloaded, so a `ta` device locale still resolves rather than
      // throwing. Whether Tamil is *usable* is device state; see
      // tamilAvailableProvider and translator_test.dart.
      expect(L.supportedLocales.map((l) => l.languageCode), containsAll(['en', 'ta']));
      expect(SupportedLocales.available, contains(SupportedLocales.english));
      expect(SupportedLocales.available, contains(SupportedLocales.tamil));
    });

    test('a stored locale round-trips', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'locale': 'ta'});
      final controller = LocaleController(await SharedPreferences.getInstance());
      expect(controller.state.languageCode, 'ta');
    });

    test('toggle flips and persists', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(prefs);
      expect(controller.state.languageCode, 'en');

      await controller.toggle();

      expect(controller.state.languageCode, 'ta');
      expect(prefs.getString('locale'), 'ta');
    });
  });

  group('gen-l10n falls back per key, for free', () {
    // The property `Strings` used to implement by hand. gen-l10n bakes it into
    // the generated subclass, so it cannot be forgotten — every untranslated
    // key is emitted carrying the English string rather than a blank or a key.
    test('an untranslated key returns the English string, never blank', () {
      final en = LEn();
      final ta = LTa();
      final report = _untranslated('ta');
      if (report.isEmpty) return; // nothing to assert once Tamil is done

      expect(ta.navDashboard, isNotEmpty);
      if (report.contains('navDashboard')) {
        expect(
          ta.navDashboard,
          en.navDashboard,
          reason: 'an untranslated key must fall back to English',
        );
      }
    });

    test('no generated string is empty in either locale', () {
      // A blank would collapse a layout silently — worse than showing English.
      for (final l in <L>[LEn(), LTa()]) {
        expect(l.navDashboard, isNotEmpty);
        expect(l.appName, isNotEmpty);
        expect(l.navSettings, isNotEmpty);
      }
    });
  });

  group('the app bar', () {
    testWidgets('shows no language pill while the model is absent', (
      tester,
    ) async {
      await bootWealthApp(tester, adapter: WealthFixtureAdapter());

      // No ML Kit model in a test host, so Tamil is not available and the
      // pill must not render — the same guarantee as before, now resting on
      // device state rather than dictionary coverage.
      expect(
        find.text(SupportedLocales.shortLabel(const Locale('ta'))),
        findsNothing,
        reason: 'the pill must not offer a language that cannot render',
      );
      // The old copy went with it — nothing in the bar promises Tamil now.
      expect(find.text('Tamil is coming soon.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Keys `gen-l10n` reports as still untranslated for [locale].
List<String> _untranslated(String locale) {
  final file = File('lib/l10n/untranslated.json');
  if (!file.existsSync()) return const [];
  final report = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (report[locale] as List?)?.cast<String>() ?? const [];
}
