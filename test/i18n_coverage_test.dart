import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.1 — the strings runtime translation cannot see.**
///
/// The app translates at render time: `core/ui.dart` swaps Flutter's `Text` for
/// one that runs its content through ML Kit, so nearly every string in the app
/// is covered by importing one file. That is why there is no dictionary to keep
/// complete, and why a hardcoded English string in `lib/` is now the normal,
/// correct thing to write.
///
/// The exceptions are the handful of Flutter properties that take a `String`
/// and build their own paragraph. Nothing below them is a `Text`, so the
/// interception never happens and they render English for ever, silently, in
/// the middle of otherwise-Tamil UI:
///
///   * `InputDecoration.hintText` / `.errorText`
///   * `tooltip:` — 15 of them across the app
///   * `semanticLabel:` — what a screen reader announces
///
/// Each must be wrapped in `tr(context, ...)`. This test is the ratchet that
/// keeps it that way, because the failure is invisible: the app looks
/// translated, and one label quietly is not.
///
/// (This file previously enforced ARB extraction. That approach was replaced by
/// ML Kit; the lexer it was built on is kept because the bypass check needs the
/// same careful reading of Dart string literals.)
void main() {
  /// Properties that render their own text, out of reach of the app's `Text`.
  const bypassProperties = <String>[
    'hintText',
    'errorText',
    'tooltip',
    'semanticLabel',
    'helperText',
    'counterText',
  ];

  test('every string that bypasses Text is wrapped in tr()', () {
    final offenders = <String>[];

    for (final file in _dartFilesUnder('lib')) {
      if (file.contains('/l10n/') || file.endsWith('translated_text.dart')) {
        continue;
      }
      final masked = _blankComments(File(file).readAsStringSync());

      for (final property in bypassProperties) {
        final pattern = RegExp('\\b$property:\\s*');
        for (final match in pattern.allMatches(masked)) {
          final at = match.end;
          if (at >= masked.length) continue;
          // A literal here means the raw English reaches the renderer.
          if (masked[at] != "'" && masked[at] != '"') continue;
          final end = _endOfLiteral(masked, at);
          final text = masked.substring(at, end);
          final line = '\n'.allMatches(masked.substring(0, at)).length + 1;
          offenders.add('$file:$line  $property: $text');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These render their own paragraph, so the translating Text never sees '
          'them — they would stay English inside Tamil UI, with nothing to '
          'notice it. Wrap each in tr(context, ...):\n  '
          '${offenders.join("\n  ")}',
    );
  });

  test('the lexer still reads interpolation correctly', () {
    // Guards the guard. A lexer that mis-reads Dart strings would make the
    // check above pass by finding nothing — which is exactly how an earlier
    // regex version of this scanner produced a garbage ARB entry.
    final tmp = File(
      '${Directory.systemTemp.createTempSync('cc_i18n').path}/probe.dart',
    )..writeAsStringSync(r"""
      final a = 'Authenticator app is on. '
          '${n == 1 ? 'code' : 'codes'} left.';
      final b = 'Plain copy';
      // 'a comment string must be ignored'
""");

    final masked = _blankComments(tmp.readAsStringSync());
    final literals = _literals(masked);
    final texts = literals.map((l) => l.text).toList();

    expect(
      texts.any((t) => t.trim() == '} left.'),
      isFalse,
      reason: 'the lexer split an interpolated literal — the original bug',
    );
    expect(texts, contains('Plain copy'));
    expect(
      texts.any((t) => t.contains('comment string')),
      isFalse,
      reason: 'comments are not code',
    );

    tmp.parent.deleteSync(recursive: true);
  });
}

Iterable<String> _dartFilesUnder(String dir) sync* {
  for (final entity in Directory(dir).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity.path;
  }
}

class _Hit {
  const _Hit(this.file, this.line, this.text);
  final String file;
  final int line;
  final String text;
}

/// Not user-facing: paths, routes, asset keys, regexes, bare identifiers,
/// wire/JSON field names, numbers.
final RegExp _skip = RegExp(
  r'^(?:/|\.{1,2}/|assets/|package:|https?:|#|\^|\\|[a-z][a-zA-Z0-9_]*$'
  r'|[a-z_]+\.[a-zA-Z_.]+$|[A-Za-z0-9_./-]+\.(?:dart|json|png|jpg|ttf|arb|ya?ml)$'
  r'|[A-Za-z0-9_]+/[A-Za-z0-9_/]+$|\d[\d.,]*$)',
);

List<_Hit> _scan(String path) {
  final masked = _blankComments(File(path).readAsStringSync());
  final hits = <_Hit>[];

  for (final literal in _literals(masked)) {
    if (literal.interpolated) continue;
    final text = literal.text;
    if (text.length < 2) continue;
    if (!RegExp(r'[A-Za-z]').hasMatch(text)) continue;
    if (_skip.hasMatch(text)) continue;
    final line = '\n'.allMatches(masked.substring(0, literal.start)).length + 1;
    hits.add(_Hit(path, line, text));
  }
  return hits;
}

/// Replaces comments with spaces, preserving length so offsets stay true.
String _blankComments(String src) {
  final out = src.split('');
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == "'" || c == '"' || (c == 'r' && i + 1 < src.length && (src[i + 1] == "'" || src[i + 1] == '"'))) {
      i = _endOfLiteral(src, i);
      continue;
    }
    if (src.startsWith('//', i)) {
      var j = src.indexOf('\n', i);
      if (j < 0) j = src.length;
      for (var k = i; k < j; k++) {
        out[k] = ' ';
      }
      i = j;
      continue;
    }
    if (src.startsWith('/*', i)) {
      var j = src.indexOf('*/', i);
      j = j < 0 ? src.length : j + 2;
      for (var k = i; k < j; k++) {
        if (out[k] != '\n') out[k] = ' ';
      }
      i = j;
      continue;
    }
    i++;
  }
  return out.join();
}

int _endOfLiteral(String src, int start) {
  var i = start;
  if (src[i] == 'r') i++;
  final quote = src[i];
  final triple = src.startsWith(quote * 3, i);
  final delim = triple ? quote * 3 : quote;
  i += delim.length;

  while (i < src.length) {
    if (src[i] == r'\') {
      i += 2;
      continue;
    }
    if (src.startsWith(r'${', i)) {
      i += 2;
      var depth = 1;
      while (i < src.length && depth > 0) {
        if (src[i] == "'" || src[i] == '"') {
          i = _endOfLiteral(src, i);
          continue;
        }
        if (src[i] == '{') {
          depth++;
        } else if (src[i] == '}') {
          depth--;
        }
        i++;
      }
      continue;
    }
    if (src.startsWith(delim, i)) return i + delim.length;
    if (!triple && src[i] == '\n') return i;
    i++;
  }
  return src.length;
}

class _Literal {
  const _Literal(this.start, this.text, this.interpolated);
  final int start;
  final String text;
  final bool interpolated;
}

/// Every string literal, with adjacent ones joined the way Dart joins them.
List<_Literal> _literals(String src) {
  final out = <_Literal>[];
  var i = 0;

  bool startsLiteral(int at) =>
      at < src.length &&
      (src[at] == "'" ||
          src[at] == '"' ||
          (src[at] == 'r' &&
              at + 1 < src.length &&
              (src[at + 1] == "'" || src[at + 1] == '"')));

  while (i < src.length) {
    if (!startsLiteral(i)) {
      i++;
      continue;
    }
    final start = i;
    final buffer = StringBuffer();
    var interpolated = false;

    while (true) {
      final end = _endOfLiteral(src, i);
      var body = src.substring(i, end);
      if (body.startsWith('r')) body = body.substring(1);
      final quote = body[0];
      final delim = body.startsWith(quote * 3) ? quote * 3 : quote;
      body = body.length > delim.length && body.endsWith(delim)
          ? body.substring(delim.length, body.length - delim.length)
          : body.substring(delim.length);
      if (body.contains(r'$')) interpolated = true;
      buffer.write(
        body
            .replaceAll(r"\'", "'")
            .replaceAll(r'\"', '"')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\\', r'\'),
      );
      i = end;

      var j = i;
      while (j < src.length && ' \t\r\n'.contains(src[j])) {
        j++;
      }
      if (startsLiteral(j)) {
        i = j;
        continue;
      }
      break;
    }
    out.add(_Literal(start, buffer.toString(), interpolated));
  }
  return out;
}
