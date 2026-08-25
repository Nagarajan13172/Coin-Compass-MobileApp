import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.1b — what stops a migrated screen quietly growing English again.**
///
/// Extraction is only half the job. The other half is that a directory, once
/// migrated, stays migrated: without this, the next feature change adds
/// `Text('Saved')` and nothing notices until someone reads Tamil and finds an
/// English word in the middle of it.
///
/// So [migratedDirs] is a ratchet. A directory joins the list when its slice
/// lands, and from then on any new hardcoded UI string fails this test with the
/// file and line.
///
/// ## Why it lexes rather than pattern-matches
///
/// The first version of the scanner used a regex for Dart string literals and
/// silently mis-read this, from `security_card.dart`:
///
/// ```dart
/// '${value.backupCodesRemaining == 1 ? 'code' : 'codes'} left.'
/// ```
///
/// The quotes inside the interpolation closed the literal as far as the regex
/// was concerned, so it extracted the fragment `} left.` as a UI string, wrote
/// it into the ARB and broke the ICU parser. A scanner that mis-reads source is
/// worse than no scanner, because it edits code on a false reading. This walks
/// the source instead.
///
/// `tool/i18n_scan.py` is the same algorithm for use at the command line when
/// planning a slice; this is the enforcing copy.
void main() {
  /// Directories whose slice has landed. Append as each one is migrated.
  const migratedDirs = <String>[
    'lib/features/settings/presentation',
  ];

  test('migrated directories keep no hardcoded UI strings', () {
    final offenders = <String>[];

    for (final dir in migratedDirs) {
      final directory = Directory(dir);
      expect(
        directory.existsSync(),
        isTrue,
        reason: '$dir is on the migrated list but does not exist',
      );

      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final hit in _scan(entity.path)) {
          offenders.add('${hit.file}:${hit.line}  ${hit.text}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These directories are already localised, so a hardcoded string here '
          'would show up as English inside otherwise-Tamil UI. Move each into '
          'lib/l10n/app_en.arb and read it through L.of(context):\n  '
          '${offenders.join("\n  ")}',
    );
  });

  test('the scanner still reads interpolation correctly', () {
    // Guards the guard. If the lexer regresses to the naive reading, this
    // fragment is what it produces — and a broken scanner would otherwise make
    // the test above pass by finding nothing.
    final tmp = File(
      '${Directory.systemTemp.createTempSync('cc_i18n').path}/probe.dart',
    )..writeAsStringSync(r"""
      final a = 'Authenticator app is on. '
          '${value.emailFallback ? 'Email fallback is on. ' : ''}'
          '${n == 1 ? 'code' : 'codes'} left.';
      final b = 'Plain copy that must be found';
      // 'a comment string must be ignored'
      final c = 'lib/features/thing.dart';
""");

    final hits = _scan(tmp.path);
    final texts = hits.map((h) => h.text).toList();

    expect(
      texts,
      contains('Plain copy that must be found'),
      reason: 'the scanner missed an ordinary hardcoded string',
    );
    expect(
      texts.any((t) => t.trim() == '} left.'),
      isFalse,
      reason: 'the scanner split an interpolated literal — the original bug',
    );
    expect(
      texts.any((t) => t.contains('comment string')),
      isFalse,
      reason: 'comments are not UI copy',
    );
    expect(
      texts.any((t) => t.contains('lib/features/thing.dart')),
      isFalse,
      reason: 'paths are not UI copy',
    );

    tmp.parent.deleteSync(recursive: true);
  });
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
