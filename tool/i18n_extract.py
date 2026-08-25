#!/usr/bin/env python3
"""Move hardcoded UI strings into the ARB and rewrite call sites (phase 7.1b).

Rewrites by byte offset, back-to-front, using the same lexer the scanner uses —
so a literal containing quotes inside `${...}` is never half-replaced.

Interpolated strings are deliberately left alone: they need declared ARB
placeholders and a human deciding what each parameter means.
"""
import re, sys, json, collections
sys.path.insert(0, 'tool')
from i18n_scan import _strip_comments, _literals, SKIP

STOP = {'the','a','an','and','or','to','of','in','on','is','are','you','your',
        'this','that','it','for','with','be','not','can','will','has','have'}


def make_key(prefix, text, taken):
    words = [w.replace("'", '') for w in re.findall(r"[A-Za-z']+", text)]
    core = [w for w in words if w.lower() not in STOP] or words
    slug = ''.join(w[:1].upper() + w[1:].lower() for w in core[:4]) or 'Text'
    key, base, n = prefix + slug, prefix + slug, 2
    while key in taken:
        key = f'{base}{n}'; n += 1
    taken.add(key)
    return key


def run(path, prefix, arb_path='lib/l10n/app_en.arb'):
    arb = json.load(open(arb_path), object_pairs_hook=collections.OrderedDict)
    taken = {k for k in arb if not k.startswith('@')}
    by_value = {v: k for k, v in arb.items() if not k.startswith('@')}

    src = open(path).read()
    masked = _strip_comments(src)

    targets = []
    for start, end, text, interp in _literals(masked):
        if interp or len(text) < 3 or not re.search(r'[A-Za-z]', text):
            continue
        if SKIP.match(text):
            continue
        targets.append((start, end, text))

    mapping = {}
    for _s, _e, text in targets:
        if text in mapping:
            continue
        key = by_value.get(text) or make_key(prefix, text, taken)
        mapping[text] = key
        if text not in by_value:
            arb[key] = text
            arb['@' + key] = {'description': f'{path.split("/")[-1]} (7.1b)'}
            by_value[text] = key

    # back-to-front so earlier offsets stay valid
    out = src
    for start, end, text in sorted(targets, key=lambda t: t[0], reverse=True):
        out = out[:start] + f'L.of(context).{mapping[text]}' + out[end:]

    if 'l10n/app_localizations.dart' not in out:
        rel = '../' * (path.count('/') - 1) + 'l10n/app_localizations.dart'
        lines = out.split('\n')
        i = max((n for n, l in enumerate(lines) if l.startswith("import '")), default=0)
        lines.insert(i + 1, f"import '{rel}';")
        out = '\n'.join(lines)

    open(path, 'w').write(out)
    json.dump(arb, open(arb_path, 'w'), ensure_ascii=False, indent=2)
    open(arb_path, 'a').write('\n')
    print(f'{path}: {len(mapping)} string(s) -> ARB')


if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2])
