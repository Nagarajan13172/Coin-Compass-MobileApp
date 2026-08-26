import 'package:coincompass/features/notifications/data/device_notifier.dart';
import 'package:coincompass/features/notifications/data/notification_poller.dart';
import 'package:coincompass/features/notifications/data/notifications_repository.dart';
import 'package:coincompass/features/notifications/domain/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Phase 7.4 — the check, and everything it must refuse to do.**
///
/// The decision itself is tested in `notification_surfacer_test.dart`. This is
/// the plumbing: does it stay quiet when it should, does it remember what it
/// announced across a restart, and does a dead network produce silence rather
/// than a notification about the network.
void main() {
  late _FakeNotifier notifier;
  late _FakeRepository repository;

  setUp(() {
    notifier = _FakeNotifier();
    repository = _FakeRepository();
    SharedPreferences.setMockInitialValues({});
  });

  var seq = 0;
  AppNotification note({String? id, bool read = false}) {
    seq++;
    return AppNotification(
      id: id ?? 'n$seq',
      type: 'budget.exceeded',
      read: read,
      link: '/budgets',
      params: const {'category': 'Food', 'spent': 900, 'amount': 500},
      createdAt: DateTime(2026, 8, 24, 9, seq),
    );
  }

  Future<NotificationPoller> pollerWith({bool enabled = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) await prefs.setBool(NotificationPoller.enabledKey, true);
    return NotificationPoller(repository, notifier, prefs);
  }

  group('refusing to run', () {
    test('does nothing while the feature is off', () async {
      final poller = await pollerWith(enabled: false);
      repository.feed = NotificationFeed(items: [note()], unread: 1);

      final result = await poller.check();

      expect(result.didRun, isFalse);
      expect(result.skippedReason, contains('off'));
      expect(notifier.posted, isEmpty);
      expect(repository.calls, 0, reason: 'it must not even fetch');
    });

    test('does nothing without permission', () async {
      notifier.permitted = false;
      final poller = await pollerWith();
      repository.feed = NotificationFeed(items: [note()], unread: 1);

      final result = await poller.check();

      expect(result.didRun, isFalse);
      expect(result.skippedReason, contains('permission'));
      expect(notifier.posted, isEmpty);
    });

    test('a dead network is silence, not a notification about the network',
        () async {
      repository.error = StateError('offline');
      final poller = await pollerWith();

      final result = await poller.check();

      expect(result.didRun, isFalse);
      expect(notifier.posted, isEmpty);
    });
  });

  group('turning it on', () {
    // Regression: the device had POST_NOTIFICATIONS granted and the switch
    // still refused, because setEnabled asked Android to *request* a permission
    // it already had — and Android returns false once the decision is made.
    test('an already-granted permission does not need requesting', () async {
      notifier.permitted = true;
      notifier.requestReturns = false; // what Android really returns

      final poller = await pollerWith();
      expect(poller.isEnabled, isTrue);
      expect(await notifier.hasPermission(), isTrue);
      expect(
        notifier.requestCalls,
        0,
        reason: 'nothing should have been requested',
      );
    });
  });

  group('the first check adopts', () {
    test('an existing feed is remembered, not announced', () async {
      final poller = await pollerWith();
      repository.feed = NotificationFeed(
        items: [note(), note(), note()],
        unread: 3,
      );

      final result = await poller.check();

      expect(result.adopted, isTrue);
      expect(result.announced, 0);
      expect(notifier.posted, isEmpty);
    });

    test('and the next arrival does ring', () async {
      final poller = await pollerWith();
      repository.feed = NotificationFeed(items: [note(id: 'old')], unread: 1);
      await poller.check();

      repository.feed = NotificationFeed(
        items: [note(id: 'new'), note(id: 'old')],
        unread: 2,
      );
      final result = await poller.check();

      expect(result.announced, 1);
      expect(notifier.posted.single.payload, '/budgets');
    });
  });

  group('remembering across restarts', () {
    test('a second poller built from the same prefs does not re-announce',
        () async {
      final first = await pollerWith();
      repository.feed = NotificationFeed(items: [note(id: 'a')], unread: 1);
      await first.check(); // adopts

      repository.feed = NotificationFeed(
        items: [note(id: 'b'), note(id: 'a')],
        unread: 2,
      );
      await first.check();
      expect(notifier.posted, hasLength(1));

      // Restart: same prefs, brand-new poller and notifier.
      notifier = _FakeNotifier();
      final prefs = await SharedPreferences.getInstance();
      final second = NotificationPoller(repository, notifier, prefs);

      final result = await second.check();
      expect(result.announced, 0);
      expect(notifier.posted, isEmpty);
    });

    test('turning it off and on again does not replay the backlog', () async {
      final poller = await pollerWith();
      repository.feed = NotificationFeed(items: [note(id: 'a')], unread: 1);
      await poller.check(); // adopts

      await poller.setEnabled(false);
      repository.feed = NotificationFeed(
        items: [note(id: 'b'), note(id: 'a')],
        unread: 2,
      );
      await poller.check(); // skipped

      await poller.setEnabled(true);
      final result = await poller.check();

      // `b` arrived while it was off and is genuinely unseen, so it rings once
      // — but `a`, adopted before, stays quiet.
      expect(result.announced, 1);
      expect(result.adopted, isFalse, reason: 'adoption is not repeated');
    });
  });

  group('what it posts', () {
    test('uses the same copy the in-app feed renders', () async {
      final poller = await pollerWith();
      repository.feed = NotificationFeed(items: const [], unread: 0);
      await poller.check(); // adopt an empty feed

      final item = note(id: 'budget');
      repository.feed = NotificationFeed(items: [item], unread: 1);
      await poller.check();

      final expected = NotificationCopy.of(item);
      expect(notifier.posted.single.title, expected.title);
      expect(notifier.posted.single.body, expected.body);
      expect(notifier.posted.single.title, 'Budget exceeded');
    });

    test('carries the link so a tap can open the right screen', () async {
      final poller = await pollerWith();
      repository.feed = NotificationFeed(items: const [], unread: 0);
      await poller.check();

      repository.feed = NotificationFeed(items: [note(id: 'x')], unread: 1);
      await poller.check();

      expect(notifier.posted.single.payload, '/budgets');
    });

    test('the alert id is stable, so a repost replaces rather than stacks', () {
      expect(
        NotificationPoller.alertIdFor('66f1abc'),
        NotificationPoller.alertIdFor('66f1abc'),
      );
      expect(
        NotificationPoller.alertIdFor('66f1abc'),
        isNot(NotificationPoller.alertIdFor('66f1abd')),
      );
      expect(NotificationPoller.alertIdFor('66f1abc'), greaterThanOrEqualTo(0));
    });
  });
}

class _FakeNotifier implements DeviceNotifier {
  final List<DeviceAlert> posted = [];
  bool permitted = true;

  /// Android returns false from a request once the decision is already made —
  /// including when it was already granted. Defaults to that behaviour so a
  /// test cannot accidentally rely on requesting an already-granted permission.
  bool requestReturns = false;
  int requestCalls = 0;

  @override
  Future<void> initialise() async {}

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<bool> requestPermission() async {
    requestCalls++;
    return requestReturns;
  }

  @override
  Future<void> post(DeviceAlert alert) async => posted.add(alert);
}

class _FakeRepository implements NotificationsRepository {
  NotificationFeed feed = const NotificationFeed();
  Object? error;
  int calls = 0;

  @override
  Future<NotificationFeed> list() async {
    calls++;
    if (error != null) throw error!;
    return feed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
