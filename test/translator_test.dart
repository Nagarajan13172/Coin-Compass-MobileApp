import 'package:coincompass/core/i18n/translator.dart';
import 'package:flutter_test/flutter_test.dart';

/// **The synchronous half of runtime translation.**
///
/// `Text` cannot await, so [Translator.lookup] must answer immediately and
/// never throw. These pin the states it can be in — off, on-but-not-ready,
/// ready — because every one of them renders something to the owner, and only
/// one of them should render Tamil.
void main() {
  group('lookup is a pass-through unless translation can really happen', () {
    test('off: returns English', () {
      final t = Translator();
      expect(t.enabled, isFalse);
      expect(t.lookup('Net worth'), 'Net worth');
    });

    test('on but no model: still returns English', () {
      // The state that would otherwise recreate 7.1a's bug — a `த` label over
      // English text — except the pill reads the same pair of flags.
      final t = Translator()..setEnabled(true);
      expect(t.enabled, isTrue);
      expect(t.ready, isFalse, reason: 'no ML Kit model in a test host');
      expect(t.lookup('Net worth'), 'Net worth');
    });

    test('never returns an empty string', () {
      // A blank label collapses a layout with no visible cause, which is worse
      // than showing English.
      final t = Translator()..setEnabled(true);
      for (final s in const ['', 'Save', '₹2,00,00,000']) {
        expect(t.lookup(s), isNotNull);
      }
    });

    test('nothing is queued while it cannot translate', () {
      // Queueing without a model would grow an unbounded set of strings that
      // can never drain.
      final t = Translator()..setEnabled(true);
      t.lookup('Set a passcode');
      t.lookup('No budgets yet');
      expect(t.pendingCount, 0);
      expect(t.cachedCount, 0);
    });
  });

  group('model state', () {
    test('starts unknown and is never assumed ready', () {
      expect(Translator().modelState, ModelState.unknown);
      expect(Translator().ready, isFalse);
    });

    test('an unreachable plugin degrades to unavailable, not a crash', () async {
      // No platform channel in a test host. English is always a working answer,
      // so this must not take the app down.
      final t = Translator();
      await t.refreshModelState();
      expect(t.modelState, ModelState.unavailable);
      expect(t.ready, isFalse);
      expect(t.lookup('Net worth'), 'Net worth');
    });

    test('a failed download leaves it unusable rather than half-on', () async {
      final t = Translator();
      final ok = await t.downloadModel();
      expect(ok, isFalse);
      expect(t.ready, isFalse);
    });
  });

  test('toggling is idempotent', () {
    var notifications = 0;
    final t = Translator()..addListener(() => notifications++);
    t.setEnabled(true);
    t.setEnabled(true);
    t.setEnabled(true);
    expect(notifications, 1, reason: 'no-op changes must not repaint the app');
  });
}
