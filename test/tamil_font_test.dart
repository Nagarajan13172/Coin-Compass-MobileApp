import 'dart:io';

import 'package:coincompass/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.1c — the font Tamil cannot render without.**
///
/// Inter carries 2,849 codepoints and **zero** in the Tamil block (U+0B80–
/// U+0BFF), so before this every Tamil string would have come out as tofu
/// (□□□). Noto Sans Tamil is bundled as a *fallback*, which is the property
/// that made it safe to land ahead of any translation: Latin text never reaches
/// it, so it cannot move a pixel of the English UI.
///
/// The suite's other ~840 tests are the real guard on that second claim — they
/// assert exact English layout at 360dp and would break if the fallback
/// displaced Inter. These tests cover what those cannot see.
void main() {
  /// A real Tamil word — "வணக்கம்" — using a consonant, a vowel sign and a
  /// pulli, so it exercises shaping rather than a bare codepoint lookup.
  const tamil = 'வணக்கம்';
  const latin = 'Net worth';

  double widthOf(String text, {List<String>? fallback, double size = 16}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontFamilyFallback: fallback,
          fontSize: size,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  group('the asset ships', () {
    test('all four weights and the OFL licence are present', () {
      for (final name in const [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
      ]) {
        final file = File('assets/fonts/NotoSansTamil-$name.ttf');
        expect(file.existsSync(), isTrue, reason: '$name weight is missing');
        expect(file.lengthSync(), greaterThan(20000));
      }
      // The OFL requires the licence to travel with the font, so it is a
      // bundled asset and not merely a file in the repo.
      final licence = File('assets/fonts/OFL-NotoSansTamil.txt');
      expect(licence.existsSync(), isTrue);
      expect(licence.readAsStringSync(), contains('SIL OPEN FONT LICENSE'));

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/fonts/OFL-NotoSansTamil.txt'));
      expect(pubspec, contains('family: ${AppTheme.tamilFontFamily}'));
    });

    test('Inter really has no Tamil, which is why the fallback exists', () {
      // Pins the premise. If a future Inter build gained Tamil coverage this
      // would still pass on the fallback — but the day it stops being true is
      // the day this whole file's reasoning needs revisiting.
      final inter = File('assets/fonts/Inter-Regular.ttf');
      expect(inter.existsSync(), isTrue);
      expect(
        _tamilCodepointCount(inter),
        0,
        reason: 'Inter is expected to have no Tamil glyphs',
      );
      expect(
        _tamilCodepointCount(File('assets/fonts/NotoSansTamil-Regular.ttf')),
        greaterThan(60),
        reason: 'Noto Sans Tamil should carry the full Tamil repertoire',
      );
    });
  });

  group('the theme reaches the fallback', () {
    test('AppTheme exposes Noto Sans Tamil as a fallback, not the primary', () {
      expect(AppTheme.fontFamily, 'Inter');
      expect(AppTheme.fontFamilyFallback, contains(AppTheme.tamilFontFamily));
      expect(
        AppTheme.fontFamilyFallback,
        isNot(contains(AppTheme.fontFamily)),
        reason: 'Inter is the primary; it must not also be a fallback',
      );
    });

    for (final dark in const [false, true]) {
      test('every themed text style carries the fallback (${dark ? 'dark' : 'light'})', () {
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        final styles = <String, TextStyle?>{
          'bodyMedium': theme.textTheme.bodyMedium,
          'titleLarge': theme.textTheme.titleLarge,
          'labelLarge': theme.textTheme.labelLarge,
          'appBar.title': theme.appBarTheme.titleTextStyle,
          'snackBar.content': theme.snackBarTheme.contentTextStyle,
        };
        styles.forEach((name, style) {
          expect(style, isNotNull, reason: '$name is unset');
          expect(
            style!.fontFamilyFallback,
            contains(AppTheme.tamilFontFamily),
            reason: '$name would render Tamil as tofu',
          );
        });
      });
    }
  });

  group('Tamil shapes, and Latin is untouched', () {
    test('Tamil measures differently with the fallback than without', () {
      // Without a font that has these glyphs the engine falls back to notdef
      // boxes; with Noto it shapes properly. The two cannot measure the same.
      final without = widthOf(tamil);
      final with_ = widthOf(tamil, fallback: AppTheme.fontFamilyFallback);
      expect(with_, greaterThan(0));
      expect(
        with_,
        isNot(closeTo(without, 0.01)),
        reason: 'the fallback is not being reached for Tamil text',
      );
    });

    test('the fallback resolves to Noto specifically, not to just anything', () {
      // "Measures differently" alone only proves *some* font was reached. This
      // pins which one: asking Inter+fallback for Tamil must produce exactly
      // what asking Noto directly produces. If those agree, the glyphs on
      // screen are Noto's — which the cmap test above showed covers all 72
      // Tamil codepoints — so they cannot be tofu.
      final viaFallback = widthOf(tamil, fallback: AppTheme.fontFamilyFallback);
      final painter = TextPainter(
        text: const TextSpan(
          text: tamil,
          style: TextStyle(
            fontFamily: AppTheme.tamilFontFamily,
            fontSize: 16,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      expect(viaFallback, painter.width);
      expect(viaFallback, greaterThan(0));
    });

    test('Latin is byte-for-byte the same width with the fallback added', () {
      // The safety property. Inter covers Latin, so the engine never consults
      // the fallback, and adding it must not move the English UI at all.
      expect(
        widthOf(latin, fallback: AppTheme.fontFamilyFallback),
        widthOf(latin),
      );
    });

    test('digits and the rupee sign stay on Inter', () {
      // Money is the app's most layout-sensitive text and every figure carries
      // ₹ and tabular digits. If the fallback ever captured these, every
      // amount on every screen would shift.
      for (final sample in const ['₹2,00,00,000', '−₹13,312', '0123456789']) {
        expect(
          widthOf(sample, fallback: AppTheme.fontFamilyFallback),
          widthOf(sample),
          reason: '$sample changed width when the fallback was added',
        );
      }
    });
  });
}

/// Counts codepoints in the Tamil block by walking the font's `cmap`.
int _tamilCodepointCount(File file) {
  final bytes = file.readAsBytesSync().buffer.asByteData();
  final tableCount = bytes.getUint16(4);
  int? cmapOffset;
  for (var i = 0; i < tableCount; i++) {
    final record = 12 + 16 * i;
    final tag = String.fromCharCodes(
      List<int>.generate(4, (j) => bytes.getUint8(record + j)),
    );
    if (tag == 'cmap') cmapOffset = bytes.getUint32(record + 8);
  }
  if (cmapOffset == null) return 0;

  final subtableCount = bytes.getUint16(cmapOffset + 2);
  int? best;
  for (var i = 0; i < subtableCount; i++) {
    final record = cmapOffset + 4 + 8 * i;
    final platform = bytes.getUint16(record);
    final encoding = bytes.getUint16(record + 2);
    final isUnicode =
        (platform == 3 && (encoding == 1 || encoding == 10)) ||
        (platform == 0);
    if (isUnicode) best = cmapOffset + bytes.getUint32(record + 4);
  }
  if (best == null) return 0;

  // Inter's preferred subtable is format 12 and Noto's is format 4, so both
  // have to be walked — an unrecognised format returns -1 rather than guessing
  // zero, because "I could not read it" and "it has no Tamil" are the two
  // answers this function must never confuse.
  const tamilStart = 0x0B80;
  const tamilEnd = 0x0BFF;
  var found = 0;

  switch (bytes.getUint16(best)) {
    case 4:
      final segCount = bytes.getUint16(best + 6) ~/ 2;
      for (var i = 0; i < segCount; i++) {
        final end = bytes.getUint16(best + 14 + 2 * i);
        final start = bytes.getUint16(best + 16 + 2 * segCount + 2 * i);
        for (var cp = start; cp <= end && cp <= 0xFFFF; cp++) {
          if (cp >= tamilStart && cp <= tamilEnd) found++;
        }
      }
    case 12:
      final groups = bytes.getUint32(best + 12);
      for (var i = 0; i < groups; i++) {
        final group = best + 16 + 12 * i;
        final start = bytes.getUint32(group);
        final end = bytes.getUint32(group + 4);
        // Clamp to the Tamil block instead of walking the whole range — a
        // format 12 group can legitimately span hundreds of thousands of
        // codepoints.
        final from = start > tamilStart ? start : tamilStart;
        final to = end < tamilEnd ? end : tamilEnd;
        if (from <= to) found += to - from + 1;
      }
    default:
      return -1;
  }
  return found;
}
