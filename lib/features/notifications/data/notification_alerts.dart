/// Phase 7.4 — wiring the check to the two things that trigger it.
///
/// The poller itself owns no Riverpod state, because one of its two callers is
/// a **background isolate** with no provider container. This file holds the
/// container-side plumbing; [backgroundCallbackDispatcher] is the other side.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/api/api_client.dart';
import 'device_notifier.dart';
import 'notification_poller.dart';
import 'notifications_repository.dart';

/// Registered with WorkManager. Android's minimum period is 15 minutes and it
/// is a *floor*, not a promise — Doze and app-standby stretch it, and that is
/// the honest limit of a feature built without server push.
const String periodicCheckTask = 'coincompass.notifications.check';
const Duration checkInterval = Duration(minutes: 15);

/// Built per call rather than held, because `SharedPreferences` must be re-read
/// after the background isolate has written to it.
final notificationPollerProvider = FutureProvider<NotificationPoller>((
  ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  return NotificationPoller(
    ref.watch(notificationsRepositoryProvider),
    ref.watch(deviceNotifierProvider),
    prefs,
  );
});

/// Turns the feature on or off, including scheduling the background task.
///
/// Kept together because the two must not drift: a scheduled task with the
/// preference off would wake the phone every 15 minutes to do nothing.
class DeviceAlertsController {
  const DeviceAlertsController(this._ref);

  final Ref _ref;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(NotificationPoller.enabledKey) ?? false;
  }

  /// Returns whether it is now on. Turning it on can fail — the user can refuse
  /// the Android permission prompt — and the preference must not claim
  /// otherwise, or Settings would show a toggle that does nothing.
  Future<bool> setEnabled(bool value) async {
    final poller = await _ref.read(notificationPollerProvider.future);

    if (!value) {
      await poller.setEnabled(false);
      await Workmanager().cancelByUniqueName(periodicCheckTask);
      return false;
    }

    // Ask only when there is something to ask for. Android's
    // `requestNotificationsPermission()` returns false once the decision has
    // already been made — including when it was already **granted** — so
    // requesting unconditionally made the switch refuse to turn on for a user
    // who had allowed notifications. Found on the device: `dumpsys` said
    // `granted=true` while the toggle insisted Android had refused.
    final notifier = _ref.read(deviceNotifierProvider);
    final granted =
        await notifier.hasPermission() || await notifier.requestPermission();
    if (!granted) return false;

    await poller.setEnabled(true);
    await Workmanager().registerPeriodicTask(
      periodicCheckTask,
      periodicCheckTask,
      frequency: checkInterval,
      // Replace, so toggling off and on does not leave two tasks running.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    );
    return true;
  }

  /// The resume-time check. Failures are swallowed: this runs on every
  /// foreground and must never surface an error over whatever the user opened
  /// the app to do.
  Future<PollResult?> checkNow() async {
    try {
      final poller = await _ref.read(notificationPollerProvider.future);
      return await poller.check();
    } catch (_) {
      return null;
    }
  }
}

final deviceAlertsProvider = Provider<DeviceAlertsController>(
  DeviceAlertsController.new,
);

/// The background isolate's entry point.
///
/// It has no provider container, no widget tree and no live session in memory —
/// only what is on disk. That is enough: the session is an httpOnly cookie in a
/// `PersistCookieJar` under the app documents directory, so `ApiClient.create()`
/// picks it up here exactly as it does in the app.
///
/// `vm:entry-point` is required or the Dart compiler strips it.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != periodicCheckTask) return true;
    try {
      final api = await ApiClient.create();
      final prefs = await SharedPreferences.getInstance();
      final poller = NotificationPoller(
        NotificationsRepository(api),
        LocalDeviceNotifier(),
        prefs,
      );
      await poller.check();
    } catch (_) {
      // Returning false asks WorkManager to retry with backoff, which for a
      // 15-minute poll just means the next run happens sooner and does the same
      // thing. Nothing here is worth retrying — the next scheduled check is.
    }
    return true;
  });
}
