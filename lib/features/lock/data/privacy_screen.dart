import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hides CoinCompass from the task-switcher preview while the app lock is on.
///
/// ## Why this is not unconditional FLAG_SECURE
///
/// The recents thumbnail is the single most likely place this owner's net worth
/// gets read by someone else — it is exactly the "glance at an unattended
/// phone" case the lock exists for, and a lock whose task-switcher card still
/// shows the dashboard is a lock with a window cut into it. But FLAG_SECURE
/// also permanently blocks the owner from screenshotting their own dashboard,
/// blocks screen recording, and blacks out casting. On API 33+ the framework
/// can suppress *only* the snapshot, so that is what the host does; FLAG_SECURE
/// is the pre-33 fallback, where there is no finer lever.
///
/// Scoped to the setting, never on unconditionally: lock off means screenshots
/// and mirroring behave exactly as they did before this feature existed.
class PrivacyScreen {
  const PrivacyScreen();

  static const MethodChannel channel = MethodChannel(
    'cloud.sathishkumar.coincompass/privacy',
  );

  Future<void> setEnabled(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>('setPrivacyScreen', enabled);
    } on MissingPluginException {
      // A test host, or an engine without this activity. Never worth throwing.
    } on PlatformException {
      // OEM refused the flag; the in-process shield still covers the app.
    }
  }
}
