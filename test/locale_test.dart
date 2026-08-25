import 'dart:io';

import 'package:coincompass/core/i18n/en.dart';
import 'package:coincompass/core/i18n/locale_controller.dart';
import 'package:coincompass/core/i18n/strings.dart';
import 'package:coincompass/core/i18n/ta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wealth_lock_fakes.dart';

/// **Phase 7.1 — the language toggle, and why it is currently hidden.**
///
/// Before this, `ta` resolved to the English map. Tapping the app bar's pill
/// relabelled it `த`, **persisted a Tamil locale**, showed a "Tamil is coming
/// soon" snackbar, and then carried on painting English. The snackbar was
/// honest about the intent; the state was not — the app went on claiming to be
/// in a language it was not in, across restarts.
///
/// The fix is to derive availability from the dictionary rather than from a
/// flag someone has to remember to flip. These tests pin both directions of
/// that coupling, and the escape hatch for a phone that already stored `ta`.
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

  group('availability is read off the dictionary', () {
    test('hasTamil is exactly "Tamil covers every English key"', () {
      // The whole point: no separate flag, and the bar is COVERAGE rather than
      // "is it non-empty". Offering Tamil on a partial dictionary would put a
      // `த` label over mostly-English text — the same lie, with a few Tamil
      // words sprinkled in. Written to keep passing in both states, so it does
      // not rot the day the dictionary is finished.
      final covered = enStrings.isNotEmpty && SupportedLocales.tamilGaps.isEmpty;
      expect(SupportedLocales.hasTamil, covered);
      expect(SupportedLocales.canChoose, covered);
      expect(
        SupportedLocales.available.length,
        covered ? 2 : 1,
        reason: 'English is always available; Tamil only at full coverage',
      );
    });

    test('a partial dictionary does not count as coverage', () {
      // The state 7.1 lives in for its whole duration. Every English key that
      // has no Tamil string is a gap, and one gap is enough to keep the toggle
      // hidden.
      expect(
        SupportedLocales.tamilGaps.length,
        enStrings.keys.where((k) => (taStrings[k] ?? '').isEmpty).length,
      );
      if (SupportedLocales.tamilGaps.isNotEmpty) {
        expect(SupportedLocales.hasTamil, isFalse);
      }
    });

    test('English is always offered', () {
      expect(SupportedLocales.available, contains(SupportedLocales.english));
    });
  });

  group('a locale with no dictionary cannot be adopted', () {
    test('resolve() clamps an unavailable locale to English', () {
      final resolved = SupportedLocales.resolve(SupportedLocales.tamil);
      expect(
        resolved.languageCode,
        SupportedLocales.hasTamil ? 'ta' : 'en',
        reason: 'Tamil may only be resolved once it has strings',
      );
      expect(SupportedLocales.resolve(SupportedLocales.english).languageCode, 'en');
    });

    test('a phone that already stored "ta" is not stranded', () async {
      // The real regression. Someone tapped the pill while Tamil was a stub, so
      // 'ta' is in SharedPreferences. The pill is hidden now, so if the stored
      // value were honoured they would reopen to a `த`-labelled English app
      // with no visible control to get out of it.
      SharedPreferences.setMockInitialValues(<String, Object>{'locale': 'ta'});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(prefs);

      expect(
        controller.state.languageCode,
        SupportedLocales.hasTamil ? 'ta' : 'en',
      );
    });

    test('set() ignores a locale it cannot render', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(prefs);
      expect(controller.state.languageCode, 'en');

      await controller.set(SupportedLocales.tamil);

      expect(
        controller.state.languageCode,
        SupportedLocales.hasTamil ? 'ta' : 'en',
        reason: 'switching to a dictionary-less locale must not half-apply',
      );
      // And nothing misleading was persisted for the next launch.
      expect(prefs.getString('locale'), SupportedLocales.hasTamil ? 'ta' : null);
    });
  });

  group('Strings falls back per key, never per dictionary', () {
    // Constructed directly so the half-translated case is testable while the
    // real Tamil map is still empty — this is the state 7.1 lives in for its
    // whole duration, so it is the state most worth pinning.
    const half = <String, String>{'nav.dashboard': 'முகப்பு', 'nav.blank': ''};

    test('a translated key uses the translation', () {
      const s = Strings(Locale('ta'), half);
      expect(s.t('nav.dashboard'), 'முகப்பு');
    });

    test('an untranslated key falls back to English, not to the key', () {
      const s = Strings(Locale('ta'), half);
      final key = enStrings.keys.firstWhere((k) => !half.containsKey(k));
      expect(s.t(key), enStrings[key]);
      expect(s.t(key), isNot(key));
    });

    test('a blank translation falls back too', () {
      // An empty string is a hole, not a translation — it would collapse a
      // layout silently.
      const s = Strings(Locale('ta'), half);
      expect(s.t('nav.blank'), isNot(''));
    });

    test('a key in no dictionary renders as itself, never blank', () {
      const s = Strings(Locale('ta'), half);
      expect(s.t('totally.unknown.key'), 'totally.unknown.key');
    });

    test('interpolation still works through the fallback', () {
      const s = Strings(Locale('ta'), <String, String>{});
      const withVar = <String, String>{'x': 'Sum of {{count}} things'};
      expect(
        const Strings(Locale('ta'), <String, String>{}, fallback: withVar)
            .t('x', {'count': 3}),
        'Sum of 3 things',
      );
      expect(s.t('unused', const {'count': 1}), 'unused');
    });
  });

  group('the app bar', () {
    testWidgets('shows no language pill while there is nothing to switch to', (
      tester,
    ) async {
      await bootWealthApp(tester, adapter: WealthFixtureAdapter());

      final pill = find.text(SupportedLocales.shortLabel(const Locale('en')));
      expect(
        pill,
        SupportedLocales.canChoose ? findsOneWidget : findsNothing,
        reason: 'the pill renders on SupportedLocales.canChoose alone',
      );
      // The old copy went with it — nothing promises Tamil in the bar now.
      expect(find.text('Tamil is coming soon.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
