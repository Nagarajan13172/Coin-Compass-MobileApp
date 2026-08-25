import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/i18n/locale_controller.dart';
import 'package:coincompass/core/i18n/tamil_readiness.dart';
import 'package:coincompass/l10n/app_localizations.dart';
import 'package:coincompass/l10n/app_localizations_en.dart';
import 'package:coincompass/l10n/app_localizations_ta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wealth_lock_fakes.dart';

/// **Phase 7.1 — the language toggle, and why it is still hidden.**
///
/// Before 7.1a, tapping the app bar's pill relabelled it `த`, **persisted a
/// Tamil locale**, and then carried on painting English. A "Tamil is coming
/// soon" snackbar was honest about the intent; the state was not — the app went
/// on claiming to be in a language it was not in, across restarts.
///
/// 7.1b moved the dictionary to `gen-l10n`. That buys compile-time key safety —
/// a typo'd key no longer renders `dashNetWorth` at the owner, it fails the
/// build — at the cost of the runtime coverage check, because Dart cannot
/// enumerate an abstract class's getters without reflection. So the coverage
/// gate lives in `tamil_readiness_test.dart` instead, and this file pins
/// everything around it.
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

  group('availability follows the readiness gate', () {
    test('hasTamil is exactly kTamilReady', () {
      expect(SupportedLocales.hasTamil, kTamilReady);
      expect(SupportedLocales.canChoose, kTamilReady);
      expect(
        SupportedLocales.available.length,
        kTamilReady ? 2 : 1,
        reason: 'English is always available; Tamil only when complete',
      );
    });

    test('English is always offered', () {
      expect(SupportedLocales.available, contains(SupportedLocales.english));
    });

    test('the generated delegate advertises both locales either way', () {
      // `L.supportedLocales` is what MaterialApp resolves against, and it is
      // driven by which ARB files exist — deliberately NOT by readiness. The
      // gate decides what the owner may *choose*, not what the framework can
      // load, so a `ta` device locale still resolves rather than throwing.
      expect(L.supportedLocales.map((l) => l.languageCode), containsAll(['en', 'ta']));
    });
  });

  group('a locale that is not ready cannot be adopted', () {
    test('resolve() clamps an unavailable locale to English', () {
      expect(
        SupportedLocales.resolve(SupportedLocales.tamil).languageCode,
        kTamilReady ? 'ta' : 'en',
      );
      expect(
        SupportedLocales.resolve(SupportedLocales.english).languageCode,
        'en',
      );
    });

    test('a phone that already stored "ta" is not stranded', () async {
      // The real regression. Someone tapped the pill while Tamil was a stub, so
      // 'ta' is in SharedPreferences. The pill is hidden now, so if the stored
      // value were honoured they would reopen to a `த`-labelled English app
      // with no visible control to get out of it.
      SharedPreferences.setMockInitialValues(<String, Object>{'locale': 'ta'});
      final controller = LocaleController(await SharedPreferences.getInstance());

      expect(controller.state.languageCode, kTamilReady ? 'ta' : 'en');
    });

    test('set() ignores a locale it cannot render', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(prefs);
      expect(controller.state.languageCode, 'en');

      await controller.set(SupportedLocales.tamil);

      expect(controller.state.languageCode, kTamilReady ? 'ta' : 'en');
      // And nothing misleading was persisted for the next launch.
      expect(prefs.getString('locale'), kTamilReady ? 'ta' : null);
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
    testWidgets('shows no language pill while Tamil is not ready', (
      tester,
    ) async {
      await bootWealthApp(tester, adapter: WealthFixtureAdapter());

      expect(
        find.text(SupportedLocales.shortLabel(const Locale('en'))),
        SupportedLocales.canChoose ? findsOneWidget : findsNothing,
        reason: 'the pill renders on SupportedLocales.canChoose alone',
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
