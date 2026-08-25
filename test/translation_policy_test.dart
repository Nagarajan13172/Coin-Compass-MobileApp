import 'package:coincompass/core/i18n/translation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// **The guard in front of machine translation.**
///
/// Runtime translation means nobody reads the Tamil before the owner does. That
/// is fine for "Save" and fatal for a figure or a finance term, so two things
/// stand in front of the model: [isTranslatable] refuses anything that is a
/// number rather than prose, and [glossary] substitutes a hand-checked term
/// instead of asking.
///
/// These are the cases that would misdescribe the owner's money.
void main() {
  group('figures never reach the translator', () {
    const figures = <String>[
      '₹2,00,00,000',
      '−₹13,312',
      '₹0',
      '₹1.37L',
      '~₹2.86Cr',
      '7.25%',
      '+0.54%',
      '₹15,030',
      '1,234',
      '5:30 AM',
      '04 Aug 2026',
      'Aug 2026',
      '1 INR = ₹1.00',
    ];

    for (final text in figures) {
      test('refuses ${text.replaceAll("\n", " ")}', () {
        expect(
          isTranslatable(text),
          isFalse,
          reason: 'a figure translated is a figure that can be mangled',
        );
      });
    }
  });

  group('prose does reach it', () {
    const prose = <String>[
      'Set a passcode',
      'No budgets yet',
      'Create a budget to keep your spending on track.',
      'Everything you own, minus what you owe',
      'Sign out?',
      'Two-factor authentication',
    ];

    for (final text in prose) {
      test('allows "${text.length > 34 ? "${text.substring(0, 34)}…" : text}"', () {
        expect(isTranslatable(text), isTrue);
      });
    }
  });

  group('codes and names are left alone', () {
    for (final text in const ['INR', 'GBP', 'CoinCompass', 'credit-card', 'mt_session']) {
      test('refuses $text', () => expect(isTranslatable(text), isFalse));
    }
  });

  group('the glossary covers what a translator gets wrong', () {
    test('Outstanding is a balance, not praise', () {
      // The headline case: general translators render this as "excellent".
      expect(glossary['Outstanding'], isNotNull);
      expect(glossary['Outstanding'], 'நிலுவைத் தொகை');
    });

    test('Net is netting-off, not a fishing net', () {
      expect(glossary['Net'], 'நிகர');
      expect(glossary['Net worth'], 'நிகர மதிப்பு');
      // வலை is the fishing net. If it ever appears here, that is the bug.
      for (final value in glossary.values) {
        expect(value, isNot('வலை'));
      }
    });

    test('every term that can misdescribe money has an entry', () {
      // Chosen because each has a plausible wrong translation in ordinary use.
      const mustCover = <String>[
        'Outstanding', 'Net', 'Net worth', 'Credit', 'Credits',
        'Principal', 'Interest', 'Balance', 'Returns',
        'Preclose', 'EMI', 'Income', 'Expense', 'Assets', 'Liabilities',
      ];
      final missing = mustCover.where((t) => !glossary.containsKey(t)).toList();
      expect(missing, isEmpty, reason: 'no checked Tamil for: $missing');
    });

    test('no glossary entry is blank or still English', () {
      glossary.forEach((english, tamil) {
        expect(tamil.trim(), isNotEmpty, reason: '$english has no translation');
        expect(
          tamil,
          isNot(english),
          reason: '$english was never actually translated',
        );
        // Must contain Tamil script, or it is not a Tamil translation.
        expect(
          RegExp(r'[஀-௿]').hasMatch(tamil),
          isTrue,
          reason: '$english -> "$tamil" contains no Tamil characters',
        );
      });
    });

    test('glossary keys are strings the app actually shows', () {
      // A whole-string match only fires on an exact label, so an entry with
      // trailing punctuation or odd casing would silently never apply.
      glossary.forEach((english, _) {
        expect(english.trim(), english, reason: '"$english" has stray padding');
        expect(english, isNot(endsWith('.')), reason: '"$english" is a sentence');
      });
    });
  });
}
