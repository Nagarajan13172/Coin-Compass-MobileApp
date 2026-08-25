import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/i18n/tamil_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

/// **The Tamil coverage gate.**
///
/// Phase 7.1a derived availability from the dictionary itself, so nobody could
/// forget to flip a switch in either direction. Moving to `gen-l10n` took that
/// away — `L` is an abstract class of getters and Dart cannot enumerate them at
/// runtime without reflection, so the app cannot count its own coverage while
/// it runs.
///
/// This file restores the property at test time. `flutter gen-l10n` writes
/// `lib/l10n/untranslated.json` on every build, listing exactly which keys each
/// locale is still missing, and [kTamilReady] is held to it **in both
/// directions** — early and late are both failures.
///
/// The state this makes unconstructable is the same one 7.1a fixed: a `த` label
/// over mostly-English text.
void main() {
  const reportPath = 'lib/l10n/untranslated.json';
  const templatePath = 'lib/l10n/app_en.arb';
  const tamilPath = 'lib/l10n/app_ta.arb';

  List<String> untranslated(String locale) {
    final file = File(reportPath);
    if (!file.existsSync()) return const [];
    final report = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return (report[locale] as List?)?.cast<String>() ?? const [];
  }

  int keyCount(String arbPath) {
    final arb = jsonDecode(File(arbPath).readAsStringSync()) as Map<String, dynamic>;
    return arb.keys.where((k) => !k.startsWith('@')).length;
  }

  test('the generator actually reports coverage', () {
    // If this file ever stops being produced the gate below would silently
    // start passing on an empty list, so the report's existence is itself an
    // assertion rather than an assumption.
    expect(
      File(reportPath).existsSync(),
      isTrue,
      reason:
          'lib/l10n/untranslated.json is missing — run `flutter gen-l10n`. '
          'Without it the readiness gate cannot see the gaps it exists to see.',
    );
    expect(File(templatePath).existsSync(), isTrue);
    expect(File(tamilPath).existsSync(), isTrue);
    expect(keyCount(templatePath), greaterThan(0));
  });

  test('kTamilReady agrees with the untranslated report, both ways', () {
    final gaps = untranslated('ta');

    if (gaps.isEmpty) {
      expect(
        kTamilReady,
        isTrue,
        reason:
            'Tamil is fully translated — set kTamilReady = true in '
            'lib/core/i18n/tamil_readiness.dart so the language toggle appears. '
            'This is the "finished it and forgot to switch it on" half of the '
            'gate.',
      );
    } else {
      expect(
        kTamilReady,
        isFalse,
        reason:
            'kTamilReady is true but Tamil is still missing ${gaps.length} '
            'key(s), e.g. ${gaps.take(5).join(", ")}. Turning the toggle on now '
            'would put a `த` label over mostly-English text — the exact bug '
            '7.1a fixed. Finish the translation or set it back to false.',
      );
    }
  });

  test('every Tamil key exists in the English template', () {
    // A key that is only in app_ta.arb is dead weight the generator ignores —
    // and, worse, it inflates the apparent progress of the translation while
    // translating nothing the app can render.
    final en = jsonDecode(File(templatePath).readAsStringSync()) as Map<String, dynamic>;
    final ta = jsonDecode(File(tamilPath).readAsStringSync()) as Map<String, dynamic>;
    final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();
    final orphans = ta.keys
        .where((k) => !k.startsWith('@') && !enKeys.contains(k))
        .toList();

    expect(
      orphans,
      isEmpty,
      reason: 'app_ta.arb has keys the template does not: $orphans',
    );
  });

  test('no Tamil value is blank', () {
    // gen-l10n treats a present-but-empty string as translated, so a blank
    // would ship as an empty label rather than falling back to English. That is
    // a collapsed layout with no visible cause.
    final ta = jsonDecode(File(tamilPath).readAsStringSync()) as Map<String, dynamic>;
    final blanks = <String>[
      for (final entry in ta.entries)
        if (!entry.key.startsWith('@') &&
            entry.value is String &&
            (entry.value as String).trim().isEmpty)
          entry.key,
    ];

    expect(blanks, isEmpty, reason: 'blank Tamil values: $blanks');
  });
}
