/// Phase 7.4 — putting a notification in the phone's shade.
///
/// Behind an interface for the same reason `csvSharerProvider` is: this talks to
/// a method channel that does not exist under `flutter test`, so a test of the
/// polling logic would blow up inside the plugin instead of exercising the
/// decision. Tests override the provider with a recorder; production gets the
/// real thing.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One notification to post.
class DeviceAlert {
  const DeviceAlert({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });

  /// Stable per notification, so the same server notification re-posted
  /// replaces its own entry in the shade rather than stacking a duplicate.
  final int id;
  final String title;
  final String body;

  /// The in-app path to open on tap — `AppNotification.link`.
  final String? payload;
}

abstract class DeviceNotifier {
  /// Creates the channel and wires the tap handler. Safe to call more than once.
  Future<void> initialise();

  /// Android 13+ requires the user to grant POST_NOTIFICATIONS. Returns whether
  /// the app may post. On older Android it is granted at install time.
  Future<bool> requestPermission();

  Future<bool> hasPermission();

  Future<void> post(DeviceAlert alert);
}

/// Android channel id. Changing this string orphans the user's existing channel
/// settings (importance, sound), so it is fixed for the life of the app.
const String alertsChannelId = 'coincompass_alerts';

class LocalDeviceNotifier implements DeviceNotifier {
  LocalDeviceNotifier({FlutterLocalNotificationsPlugin? plugin, this.onOpen})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Called with the tapped notification's payload — the in-app path.
  ///
  /// Settable rather than final: the provider builds this before a router
  /// exists, and `main.dart` attaches the handler once the tree is up. The
  /// background isolate constructs its own instance and leaves this null — it
  /// posts notifications but is never the one alive to handle a tap.
  void Function(String path)? onOpen;

  bool _ready = false;

  @override
  Future<void> initialise() async {
    if (_ready) return;
    try {
      await _initialise();
      _ready = true;
    } catch (_) {
      // The plugin's platform interface is absent under `flutter test`, and on
      // a platform with no notification support it throws too. Neither is worth
      // taking the app down for at startup — `_ready` stays false so a later
      // call tries again, and `post` surfaces the failure to whoever asked for
      // a notification rather than to whoever opened the app.
    }
  }

  Future<void> _initialise() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        // `drawable`, NOT `mipmap`. The plugin resolves this name with
        // `getIdentifier(name, "drawable", pkg)`, so a mipmap-only asset
        // resolves to 0 and `setSmallIcon` dies with a NullPointerException
        // *inside the plugin* — the check runs, decides correctly, and then
        // throws on the way to the shade. Found on the device: nothing
        // appeared and nothing was persisted.
        //
        // The art is 6.7's Material You monochrome layer, copied into
        // `drawable-*`: Android draws a status-bar icon from its alpha channel
        // alone, so a silhouette is exactly right and the full-colour launcher
        // icon would come out a white blob.
        android: AndroidInitializationSettings('ic_stat_coincompass'),
        iOS: DarwinInitializationSettings(
          // Asked for explicitly in [requestPermission] instead, so the prompt
          // appears when the user turns the feature on rather than at launch.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onOpen?.call(payload);
      },
    );

    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        alertsChannelId,
        'Account alerts',
        description:
            'Recurring transactions, budget limits and low balances — the same '
            'notifications the app shows in its bell.',
        importance: Importance.defaultImportance,
      ),
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async {
    await initialise();
    if (!_ready) return false;
    final android = _android;
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin
    >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<bool> hasPermission() async {
    await initialise();
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      // No plugin, no permission. The poller reads this as "skip", which is the
      // right answer when nothing can be posted anyway.
      return false;
    }
  }

  @override
  Future<void> post(DeviceAlert alert) async {
    await initialise();
    await _plugin.show(
      id: alert.id,
      title: alert.title,
      body: alert.body,
      payload: alert.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          alertsChannelId,
          'Account alerts',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          // The body is a full sentence and routinely longer than one line, so
          // the expanded form gets the same text rather than an empty string —
          // `BigTextStyleInformation('')` renders an expanded notification with
          // nothing in it.
          styleInformation: BigTextStyleInformation(alert.body),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}

/// Overridden in tests. `onOpen` is wired in `main.dart`, which is the only
/// place that can reach the router.
final deviceNotifierProvider = Provider<DeviceNotifier>(
  (ref) => LocalDeviceNotifier(),
);
