/// Phase 7.6 — the channel to the payment apps, behind an interface.
///
/// Same reason as `csvSharerProvider` and `deviceNotifierProvider`: this talks
/// to a method channel that does not exist under `flutter test`, so the sheet
/// would blow up inside the platform code rather than being exercised. Tests
/// override the provider; production gets the real thing.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/upi_request.dart';
import '../domain/upi_result.dart';

/// One UPI app installed on this phone.
class UpiApp {
  const UpiApp({required this.packageName, required this.label, this.icon});

  final String packageName;
  final String label;

  /// Launcher icon as PNG bytes. Null when it could not be read — the sheet
  /// falls back to a placeholder rather than dropping the app, because an app
  /// you cannot see is an app you cannot pay with.
  final Uint8List? icon;

  factory UpiApp.fromChannel(Map<Object?, Object?> map) {
    final encoded = map['icon'] as String?;
    Uint8List? icon;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        icon = base64Decode(encoded);
      } catch (_) {
        icon = null;
      }
    }
    return UpiApp(
      packageName: (map['packageName'] as String?) ?? '',
      label: (map['label'] as String?) ?? '',
      icon: icon,
    );
  }
}

/// How much of the payment is handed to the payment app.
///
/// Three rungs, tried in this order, each one giving away less. The app always
/// starts at the top: [prefilled] is the feature — scan the shop's code and
/// approve it with a PIN, nothing retyped. The rungs below exist because a PSP
/// can refuse a link this app has no way to make it accept, and being dropped
/// one rung is better than being told to start again somewhere else.
enum UpiHandover {
  /// Payee **and amount**. The payment app opens on a filled-in payment ready
  /// to approve.
  prefilled,

  /// Payee only — the amount is typed in the payment app. The retry when a
  /// pre-filled link comes back refused.
  payeeOnly,

  /// The payment app's own home screen, nothing attached. The last resort, and
  /// the only option when there is no VPA to pay to at all.
  appOnly,
}

abstract class UpiService {
  /// Empty when nothing can pay — no UPI app, or a platform that has no UPI.
  Future<List<UpiApp>> installedApps();

  /// Launches [request] in [app] and waits for the app to come back.
  ///
  /// [handover] chooses how much of the payment goes with it. Every rung goes
  /// out as a `upi://pay` intent through `startActivityForResult`, so all of
  /// them can come back with a result — [UpiHandover.payeeOnly] included, since
  /// the payment app still knows it was launched for a payment even when the
  /// amount was typed inside it.
  Future<UpiResult> pay({
    required UpiApp app,
    required UpiRequest request,
    UpiHandover handover = UpiHandover.prefilled,
  });

  /// Opens [app] at its own home screen with no payment attached, for when the
  /// payee is chosen inside that app — a QR scan, a saved contact, a number.
  ///
  /// Returns when the user comes back. It cannot say whether they paid: the
  /// launcher intent carries no result, so the caller has to ask.
  Future<void> openApp(UpiApp app);

  /// UPI is an Indian mobile-payments scheme with an Android intent contract
  /// and no iOS equivalent, so this is false everywhere else — the entry point
  /// hides rather than offering something that cannot work.
  bool get isSupported;
}

class MethodChannelUpiService implements UpiService {
  const MethodChannelUpiService();

  static const MethodChannel _channel = MethodChannel(
    'cloud.sathishkumar.coincompass/upi',
  );

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<List<UpiApp>> installedApps() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('listApps');
      return [
        for (final entry in raw ?? const <Object?>[])
          if (entry is Map<Object?, Object?>) UpiApp.fromChannel(entry),
      ].where((app) => app.packageName.isNotEmpty).toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> openApp(UpiApp app) async {
    try {
      await _channel.invokeMethod<String>('openApp', {
        'packageName': app.packageName,
      });
    } on PlatformException {
      // Opening failed, so there is nothing to have paid. The sheet stays put.
    }
  }

  @override
  Future<UpiResult> pay({
    required UpiApp app,
    required UpiRequest request,
    UpiHandover handover = UpiHandover.prefilled,
  }) async {
    try {
      final uri = switch (handover) {
        UpiHandover.prefilled => request.toUri(),
        UpiHandover.payeeOnly => request.payeeOnlyUri(),
        // Nothing here can launch a home screen; that is `openApp`. Treated as
        // payee-only rather than thrown on, because refusing to pay at the last
        // rung would strand the caller.
        UpiHandover.appOnly => request.payeeOnlyUri(),
      }.toString();

      // Diagnostic. Three fixes for "the bank declined" were reasoned from what
      // a QR *probably* contains rather than what this app *actually* sends;
      // this prints the exact string so the next one is not a fourth guess.
      // Visible with: adb logcat -s flutter | grep UPI
      debugPrint('UPI-OUT (${handover.name}) -> $uri');

      final response = await _channel.invokeMethod<String>('pay', {
        'packageName': app.packageName,
        'uri': uri,
      });
      debugPrint('UPI-IN  <- ${response ?? '(nothing)'}');
      return UpiResult.parse(response);
    } on PlatformException catch (error) {
      // A launch that never happened is not a failed payment, and must not be
      // reported as one — nothing left the account.
      return UpiResult(
        status: UpiStatus.cancelled,
        raw: '${error.code}: ${error.message}',
      );
    }
  }
}

final upiServiceProvider = Provider<UpiService>(
  (ref) => const MethodChannelUpiService(),
);

/// The apps, fetched once per sheet. Not cached across sheets: an app can be
/// installed or removed between payments, and the list is cheap.
final upiAppsProvider = FutureProvider.autoDispose<List<UpiApp>>(
  (ref) => ref.watch(upiServiceProvider).installedApps(),
);
