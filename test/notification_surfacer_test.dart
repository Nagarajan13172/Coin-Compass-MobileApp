import 'package:coincompass/features/notifications/domain/app_notification.dart';
import 'package:coincompass/features/notifications/domain/notification_surfacer.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.4 — what the phone is allowed to announce.**
///
/// Every rule here exists to stop the feature being uninstalled. A notifier
/// that buzzes about things the user already knows, or buzzes twice about the
/// same thing, is worse than no notifier at all — so the tests are mostly about
/// *silence*.
void main() {
  var seq = 0;
  AppNotification note({
    String? id,
    bool read = false,
    DateTime? at,
    String type = 'recurring.posted',
  }) {
    seq++;
    return AppNotification(
      id: id ?? 'n$seq',
      type: type,
      read: read,
      createdAt: at ?? DateTime(2026, 8, 24, 9, seq),
    );
  }

  NotificationFeed feedOf(List<AppNotification> items) => NotificationFeed(
    items: items,
    unread: items.where((n) => !n.read).length,
  );

  setUp(() => seq = 0);

  group('the first check is silent', () {
    test('a feed of old unread notifications is adopted, not announced', () {
      // The owner's account had six unread sitting in it before this feature
      // existed. Six buzzes for old news is how a notifier gets turned off.
      final feed = feedOf([for (var i = 0; i < 6; i++) note()]);

      final decision = decideSurface(
        feed: feed,
        seen: const {},
        isFirstCheck: true,
      );

      expect(decision.isSilent, isTrue);
      expect(decision.seen, hasLength(6));
    });

    test('what was adopted never rings later', () {
      final feed = feedOf([note(id: 'a'), note(id: 'b')]);
      final first = decideSurface(feed: feed, seen: const {}, isFirstCheck: true);

      final second = decideSurface(
        feed: feed,
        seen: first.seen,
        isFirstCheck: false,
      );
      expect(second.isSilent, isTrue);
    });

    test('a genuinely empty feed still lets the next one ring', () {
      // An empty `seen` set is also what a brand-new account has. That user's
      // first real notification must not be swallowed, which is why
      // isFirstCheck is a separate flag rather than `seen.isEmpty`.
      final adopted = decideSurface(
        feed: feedOf(const []),
        seen: const {},
        isFirstCheck: true,
      );
      expect(adopted.seen, isEmpty);

      final next = decideSurface(
        feed: feedOf([note(id: 'first-ever')]),
        seen: adopted.seen,
        isFirstCheck: false,
      );
      expect(next.toAnnounce.single.id, 'first-ever');
    });
  });

  group('announcing', () {
    test('a new unread notification rings once', () {
      final decision = decideSurface(
        feed: feedOf([note(id: 'new')]),
        seen: const {'old'},
        isFirstCheck: false,
      );
      expect(decision.toAnnounce.single.id, 'new');
      expect(decision.seen, containsAll(['old', 'new']));
    });

    test('and never rings again on the next check', () {
      final feed = feedOf([note(id: 'new')]);
      final first = decideSurface(
        feed: feed,
        seen: const {},
        isFirstCheck: false,
      );
      expect(first.toAnnounce, hasLength(1));

      final second = decideSurface(
        feed: feed,
        seen: first.seen,
        isFirstCheck: false,
      );
      expect(second.isSilent, isTrue);
    });

    test('an already-read notification is not announced', () {
      // `read` is server state, so this also covers dismissing it on the web
      // moments before the phone checks.
      final decision = decideSurface(
        feed: feedOf([note(id: 'seen-on-web', read: true)]),
        seen: const {},
        isFirstCheck: false,
      );
      expect(decision.isSilent, isTrue);
    });

    test('newest is announced last so it sits on top of the shade', () {
      final older = note(id: 'older', at: DateTime(2026, 8, 24, 9));
      final newer = note(id: 'newer', at: DateTime(2026, 8, 24, 11));

      final decision = decideSurface(
        feed: feedOf([newer, older]), // feed order is newest-first
        seen: const {},
        isFirstCheck: false,
      );
      expect(decision.toAnnounce.map((n) => n.id), ['older', 'newer']);
    });

    test('an item with no id is ignored rather than announced', () {
      final decision = decideSurface(
        feed: feedOf([note(id: '')]),
        seen: const {},
        isFirstCheck: false,
      );
      expect(decision.isSilent, isTrue);
    });
  });

  group('a burst is capped', () {
    test('at most five ring, and the newest five are the ones that do', () {
      final items = [
        for (var i = 0; i < 40; i++)
          note(id: 'n$i', at: DateTime(2026, 8, 24, 0, i)),
      ];

      final decision = decideSurface(
        feed: feedOf(items),
        seen: const {},
        isFirstCheck: false,
      );

      expect(decision.toAnnounce, hasLength(maxPerCheck));
      expect(decision.toAnnounce.last.id, 'n39');
      expect(decision.toAnnounce.first.id, 'n35');
    });

    test('the ones held back do not ring on the next check either', () {
      // Otherwise the burst simply arrives one buzz at a time, which is the
      // same forty buzzes spread over ten hours.
      final items = [
        for (var i = 0; i < 40; i++)
          note(id: 'n$i', at: DateTime(2026, 8, 24, 0, i)),
      ];
      final feed = feedOf(items);

      final first = decideSurface(
        feed: feed,
        seen: const {},
        isFirstCheck: false,
      );
      final second = decideSurface(
        feed: feed,
        seen: first.seen,
        isFirstCheck: false,
      );
      expect(second.isSilent, isTrue);
    });
  });

  group('the remembered set stays bounded', () {
    test('it is trimmed to the cap', () {
      final seen = {for (var i = 0; i < maxRemembered + 50; i++) 'old$i'};
      final decision = decideSurface(
        feed: feedOf([note(id: 'new')]),
        seen: seen,
        isFirstCheck: false,
      );
      expect(decision.seen.length, lessThanOrEqualTo(maxRemembered));
    });

    test('trimming never evicts an id still in the feed', () {
      // Evicting a live id is exactly how a notification rings a second time.
      final live = [for (var i = 0; i < 10; i++) note(id: 'live$i', read: true)];
      final seen = {
        for (var i = 0; i < maxRemembered + 50; i++) 'old$i',
        ...live.map((n) => n.id),
      };

      final decision = decideSurface(
        feed: feedOf(live),
        seen: seen,
        isFirstCheck: false,
      );

      for (final item in live) {
        expect(decision.seen, contains(item.id),
            reason: '${item.id} is still in the feed and must stay remembered');
      }
      expect(decision.seen.length, lessThanOrEqualTo(maxRemembered));
    });
  });
}
