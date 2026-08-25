#!/usr/bin/env python3
"""Find hardcoded UI strings that phase 7.1b still has to extract.

Used two ways:
  * by hand, to plan a slice;
  * by `test/i18n_coverage_test.dart`, which fails when a directory that has
    already been migrated grows a new hardcoded string.

## Why this lexes instead of matching a regex

The first version used a regex for Dart string literals and it silently
produced garbage on this, from security_card.dart:

    '${value.backupCodesRemaining == 1 ? 'code' : 'codes'} left.'

The quotes *inside* the interpolation closed the literal as far as the regex was
concerned, so it extracted the fragment `} left.` as though it were a UI string,
wrote it into the ARB, and broke the ICU parser. A scanner that mis-reads source
is worse than none: it edits code on a false reading.

So this walks the source instead, tracking escapes, `$name` and `${...}` with
nested quotes, and raw/triple-quoted forms.
"""
import re, sys, json

# Not user-facing: import paths, routes, asset keys, regexes, prefs keys,
# bare identifiers, wire/JSON field names.
SKIP = re.compile(
    r"^(?:/|\.{1,2}/|assets/|package:|https?:|#|\^|\\|[a-z][a-zA-Z0-9_]*$"
    r"|[a-z_]+\.[a-zA-Z_.]+$|[A-Za-z0-9_./-]+\.(?:dart|json|png|jpg|ttf|arb|ya?ml)$"
    r"|[A-Za-z0-9_]+/[A-Za-z0-9_/]+$|\d[\d.,]*$)"
)


def _strip_comments(src: str) -> str:
    """Blank comments to spaces, preserving length.

    Length matters: the extractor rewrites the ORIGINAL file using offsets this
    function's output produced, so deleting characters here would shift every
    later edit and corrupt the source.
    """
    out, i, n = list(src), 0, len(src)
    while i < n:
        c = src[i]
        if c in "'\"" or (c == 'r' and i + 1 < n and src[i + 1] in "'\""):
            i = _end_of_literal(src, i); continue
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j): out[k] = ' '
            i = j; continue
        if src.startswith('/*', i):
            j = src.find('*/', i)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != '\n': out[k] = ' '
            i = j; continue
        i += 1
    return ''.join(out)


def _end_of_literal(src: str, start: int) -> int:
    """Index just past the literal beginning at `start`."""
    i = start
    if src[i] == 'r':
        i += 1
    quote = src[i]
    triple = src.startswith(quote * 3, i)
    delim = quote * 3 if triple else quote
    i += len(delim)
    while i < len(src):
        if src[i] == '\\':
            i += 2; continue
        if src.startswith('${', i):
            i += 2
            depth = 1
            while i < len(src) and depth:
                if src[i] in "'\"":
                    i = _end_of_literal(src, i); continue
                if src[i] == '{': depth += 1
                elif src[i] == '}': depth -= 1
                i += 1
            continue
        if src.startswith(delim, i):
            return i + len(delim)
        if not triple and src[i] == '\n':
            return i
        i += 1
    return len(src)


def _literals(src: str):
    """(start, end, text, interpolated) for every literal, adjacent ones joined."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c in "'\"" or (c == 'r' and i + 1 < n and src[i + 1] in "'\""):
            start = i
            text, interp = '', False
            while True:
                end = _end_of_literal(src, i)
                raw = src[i:end]
                body = raw
                if body.startswith('r'): body = body[1:]
                q = body[0]
                d = q * 3 if body.startswith(q * 3) else q
                body = body[len(d):-len(d)] if body.endswith(d) and len(body) > len(d) else body[len(d):]
                if '$' in body: interp = True
                text += (body.replace("\\'", "'").replace('\\"', '"')
                             .replace('\\n', '\n').replace('\\\\', '\\'))
                i = end
                # join adjacent literals separated only by whitespace
                j = i
                while j < n and src[j] in ' \t\r\n': j += 1
                if j < n and (src[j] in "'\"" or (src[j] == 'r' and j + 1 < n and src[j + 1] in "'\"")):
                    i = j; continue
                break
            yield start, i, text, interp
        else:
            i += 1


def scan(path: str):
    src = _strip_comments(open(path).read())
    out = []
    for start, _end, text, interp in _literals(src):
        if len(text) < 2 or not re.search(r'[A-Za-z]', text):
            continue
        if SKIP.match(text):
            continue
        out.append({
            'file': path,
            'line': src[:start].count('\n') + 1,
            'text': text,
            'interpolated': interp,
        })
    return out


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if a != '--json']
    hits = [h for p in args for h in scan(p)]
    if '--json' in sys.argv:
        print(json.dumps(hits, ensure_ascii=False, indent=2))
    else:
        for h in hits:
            mark = ' [INTERP]' if h['interpolated'] else ''
            print(f"{h['file']}:{h['line']}{mark}: {h['text'][:100]}")
        print(f"\n{len(hits)} hardcoded string(s)")
