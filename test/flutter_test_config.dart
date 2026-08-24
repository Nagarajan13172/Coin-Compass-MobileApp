import 'dart:async';
import 'dart:io';

import 'package:coincompass/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test in this directory tree — Flutter picks this file up by
/// name, no import required.
///
/// **Why it exists: without it, every layout assertion in the suite is measured in
/// the wrong font.** `flutter test` does not bundle `pubspec.yaml` font assets, so
/// text falls back to a stand-in whose glyphs are all exactly `fontSize` wide.
/// Digits come out roughly 75% wider than Inter's — `₹99,99,999` at 13.5sp/w700
/// measures 137.5dp in the harness against 78.6dp in the real app.
///
/// That direction fails *safe*: the suite over-reports overflow risk and never
/// under-reports it, so a passing layout test was still meaningful. But it made the
/// numbers useless for the opposite question — you could not use them to justify
/// *tightening* a width, and a test asserting "this fits" was proving something
/// much stronger than the app actually needs.
///
/// One test file (`phase5_layout_lens_test.dart`) already loaded Inter by hand.
/// Doing it here instead means every test measures what the owner's phone renders.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final loader = FontLoader(AppTheme.fontFamily);
  for (final path in const [
    'assets/fonts/Inter-Regular.ttf',
    'assets/fonts/Inter-Medium.ttf',
    'assets/fonts/Inter-SemiBold.ttf',
    'assets/fonts/Inter-Bold.ttf',
  ]) {
    final file = File(path);
    // Never fail the whole suite over a missing font — a checkout without the
    // asset should still run, just back on the fallback metrics.
    if (!file.existsSync()) continue;
    loader.addFont(
      Future<ByteData>.value(file.readAsBytesSync().buffer.asByteData()),
    );
  }
  await loader.load();

  await testMain();
}
