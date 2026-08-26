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

abstract class UpiService {
  /// Empty when nothing can pay — no UPI app, or a platform that has no UPI.
  Future<List<UpiApp>> installedApps();

  /// Launches [request] in [packageName] and waits for the app to come back.
  Future<UpiResult> pay({
    required UpiApp app,
    required UpiRequest request,
  });

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
  Future<UpiResult> pay({
    required UpiApp app,
    required UpiRequest request,
  }) async {
    try {
      final response = await _channel.invokeMethod<String>('pay', {
        'packageName': app.packageName,
        'uri': request.toUri().toString(),
      });
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
