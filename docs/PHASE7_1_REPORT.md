# Phase 7.1 — Tamil localisation

Three jobs, and only the last is translation:

| | | state |
|---|---|---|
| **7.1a** | language toggle + per-key fallback | ✅ done |
| **7.1b** | extract ~1,240 hardcoded strings into the dictionary | not started (parked) |
| **7.1c** | Noto Sans Tamil + coverage gate | ✅ font done · translation blocked on 7.1b |

## 7.1a — the toggle claimed a language the app wasn't in

Tapping the app bar's pill switched the label to `த`, **persisted a Tamil
locale**, and then went on painting English — `Strings._mapFor` returned the
English map for both `'en'` and `'ta'`. A *"Tamil is coming soon"* snackbar
explained the intent but did not undo the state, which survived restarts.

Availability is now derived from the dictionary rather than asserted by a flag,
so there is no switch anyone can forget to flip in either direction.

Two details that matter on a real phone:

- **`resolve()` clamps an unavailable locale to English.** Without it, anyone who
  had already tapped the pill would reopen to a `த`-labelled English app with the
  escape control now hidden.
- **`Strings.t` falls back per *key*** — Tamil → English → key — so the
  half-translated state 7.1 lives in renders as a Tamil/English mix rather than
  leaking `dash.netWorth` at the owner. A blank counts as a hole, not a
  translation.

## 7.1c — the font

**Inter carries 2,849 codepoints and zero in the Tamil block** (U+0B80–U+0BFF),
verified by walking its `cmap`. Every Tamil string would have been tofu.

Noto Sans Tamil ships as a **fallback, never the primary** — Latin never reaches
it, so it cannot move a pixel of the English UI. That is what made it safe to
land ahead of any translation. Four static instances cut from the variable font
at `wdth=100` (330,736 bytes, 10KB *less* than the variable font) mirror Inter's
four weights, so weight matching is a lookup rather than a variable-axis
negotiation. The OFL licence ships as a bundled asset, which the licence
requires.

Release APK **24.7MB → 24.9MB** for the full Tamil script.

### Verified on the device

Walked on the owner's phone (CPH2569, Android 15, 360×804dp) with a temporary
probe on the Dashboard, since the UI has no Tamil strings of its own yet. The
probe was reverted and a clean build reinstalled immediately after.

Everything rendered, with **no tofu boxes anywhere**:

- `வணக்கம்` — pulli on the final ம்
- `பரிவர்த்தனைகள்` — the ர்த்த conjunct
- `கௌ கோ கீ க் ஸ்ரீ ஞ்ஞா` — split vowel, vowel signs, bare pulli, and the ஸ்ரீ
  ligature
- `நிகர மதிப்பு: −₹2,00,00,000` — **the important one**: the engine switches
  Noto → Inter mid-string for the colon, minus, ₹ and digits, seamlessly
- w400 / w500 / w600 / w700 all render and visibly differ, so all four static
  instances resolve

## What 7.1b has to plan for

Tamil is **not** uniformly longer — it ranges from much shorter to much longer,
measured at 14sp with the shipped fonts:

| English | | Tamil | | ratio |
|---|---|---|---|---|
| Outstanding | 80.4dp | நிலுவைத் தொகை | 139.2dp | **173%** |
| Settings | 53.9dp | அமைப்புகள் | 92.3dp | **171%** |
| Transactions | 84.9dp | பரிவர்த்தனைகள் | 129.0dp | 152% |
| Net worth | 65.2dp | நிகர மதிப்பு | 88.2dp | 135% |
| Categories | 72.0dp | வகைகள் | 68.9dp | 96% |
| Dashboard | 72.2dp | முகப்பு | 49.2dp | 68% |

**A label sized for English at `maxLines: 1` will ellipsise at 173%.** This app
has a lot of hard-won 360dp layouts in exactly that shape — the loan card's three
`_Fact` columns get 96dp each, and the More sheet, stat tiles and form labels are
all tight. Tamil glyphs are also taller, so line heights need re-checking, not
just widths.

`flutter_test_config.dart` now loads both families, so layout tests measure Tamil
in Tamil rather than in a stand-in.

## The coverage gate

`hasTamil` is **not** "the Tamil map is non-empty" — it is "Tamil covers every
English key" (`tamilGaps` is empty).

Offering Tamil on a partial dictionary would recreate 7.1a's bug wearing a
different hat: a `த` label over mostly-English text, now with a handful of Tamil
words scattered through it, which reads as broken rather than as pending.

It is self-correcting in the direction that matters. 7.1b will *add* hundreds of
keys to `en.dart` as it extracts hardcoded strings, and each one re-opens a gap
until Tamil catches up — so the bar rises with the work instead of being passed
once and forgotten.

## Still open

The **translation half of 7.1c is blocked on 7.1b**. There are 107 keys in
`en.dart` and essentially none are wired to a widget: `Strings.` is called twice
in the whole codebase, one of those inside `strings.dart` itself. Translating
today would produce strings nothing renders.
