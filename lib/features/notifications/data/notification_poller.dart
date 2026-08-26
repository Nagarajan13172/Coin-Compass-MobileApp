/// Phase 7.4 — the check itself.
///
/// Fetch the feed, ask [decideSurface] what is new, post it, remember it. The
/// decision is a pure function tested on its own; this is the plumbing around
/// it, and it runs in two places:
///
///   * **on resume**, from the widget tree, so opening the app after a while
///     catches up immediately;
///   * **on a periodic background task**, which is the half that makes the
///     feature worth having — a notifier that only fires while you are already
///     looking at the app tells you nothing you did not just see.
///
/// Both call [NotificationPoller.check]. It owns no Riverpod state so the
/// background isolate — which has no provider container — can build one
/// directly from an [ApiClient] and [SharedPreferences].
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_notification.dart';
import '../domain/notification_surfacer.dart';
import 'device_notifier.dart';
import 'notifications_repository.dart';

/// What one check did. Returned rather than logged so the settings screen can
/// say something concrete after a manual "Check now".
class PollResult {
  const PollResult({
    required this.announced,
    required this.adopted,
    this.skippedReason,
  });

  const PollResult.skipped(String reason)
    : announced = 0,
      adopted = false,
      skippedReason = reason;

  final int announced;

  /// True when this was the first check and the feed was adopted silently.
  final bool adopted;

  /// Non-null when nothing was attempted — disabled, no permission, no session.
  final String? skippedReason;

  bool get didRun => skippedReason == null;
}

class NotificationPoller {
  /// Positional, matching every other collaborator-holding class in this app
  /// (`ExportRepository(this._api)`, `ImportRunner(...)`). The three types are
  /// distinct, so a mis-ordered call is a compile error.
  const NotificationPoller(this._repository, this._notifier, this._prefs);

  final NotificationsRepository _repository;
  final DeviceNotifier _notifier;
  final SharedPreferences _prefs;

  /// Whether the user has turned device notifications on. Off by default: the
  /// app must not start posting to the shade because someone installed it.
  static const String enabledKey = 'notifications.deviceAlerts';

  /// The ids already announced. A list rather than a set because
  /// `SharedPreferences` has no set type, and order is what [maxRemembered]
  /// trims by.
  static const String seenKey = 'notifications.surfaced';

  /// Separate from `seen` being empty — see [decideSurface].
  static const String adoptedKey = 'notifications.adopted';

  bool get isEnabled => _prefs.getBool(enabledKey) ?? false;

  Future<void> setEnabled(bool value) async {
    await _prefs.setBool(enabledKey, value);
    // Turning it off forgets nothing: turning it back on should not replay
    // everything that arrived while it was off. The adoption flag stays set, so
    // the next check announces only what is new from that point.
  }

  Future<PollResult> check() async {
    if (!isEnabled) return const PollResult.skipped('Device alerts are off.');

    if (!await _notifier.hasPermission()) {
      return const PollResult.skipped(
        'Android has not granted permission to post notifications.',
      );
    }

    final NotificationFeed feed;
    try {
      feed = await _repository.list();
    } catch (error) {
      // Offline, a dead session, a 500 — all the same here. A background check
      // that cannot reach the server is a no-op, never a notification saying
      // so.
      return PollResult.skipped('Could not reach the server: $error');
    }

    final seen = (_prefs.getStringList(seenKey) ?? const <String>[]).toSet();
    final isFirstCheck = !(_prefs.getBool(adoptedKey) ?? false);

    final decision = decideSurface(
      feed: feed,
      seen: seen,
      isFirstCheck: isFirstCheck,
    );

    for (final item in decision.toAnnounce) {
      final copy = NotificationCopy.of(item);
      await _notifier.post(
        DeviceAlert(
          id: alertIdFor(item.id),
          title: copy.title,
          body: copy.body,
          payload: item.link,
        ),
      );
    }

    // Persisted *after* posting, so a crash mid-post replays rather than
    // silently swallowing. A duplicate notification is a much smaller failure
    // than a missing one.
    await _prefs.setStringList(seenKey, decision.seen.toList());
    if (isFirstCheck) await _prefs.setBool(adoptedKey, true);

    return PollResult(
      announced: decision.toAnnounce.length,
      adopted: isFirstCheck,
    );
  }

  /// A stable 31-bit id from the Mongo `_id`.
  ///
  /// Stable so that re-posting the same notification replaces its own entry in
  /// the shade instead of stacking a second copy; non-negative because Android
  /// notification ids are signed ints and a negative one is legal but confusing
  /// in `adb shell dumpsys notification`.
  static int alertIdFor(String notificationId) =>
      notificationId.hashCode & 0x7fffffff;
}
