# Phase 5 — Reports, Insights, Notifications, Settings

**Status: complete.** `flutter analyze` clean · **486 tests passing** (up from 397
at integration, 221 before the phase) · debug APK built.

**All 17 screens are now real.** The only `PlaceholderScreen` left in the router
is the `_ =>` catch-all for an unmapped route.

## Shipped

| Screen | Route | Notes |
|---|---|---|
| Reports | `/reports` | Period bar (W/M/Y + prev/next), 6 stat tiles, by-category donut, income-vs-expense bars, by-account, net cash-flow area chart, CSV export |
| Insights | `/insights` | This-vs-previous compare cards, savings rate, spending pace, category movers |
| Notifications | `/notifications` | Grouped by day, per-type sentences, read/unread, mark-all, delete |
| Settings | `/settings` | Profile, theme, wallet, currencies, email reports, security, sign out |

25 files across the four features.

## Review findings fixed

23 agents, 0 errors. Four adversarial lenses raised claims; **7 survived
refutation**. All fixed:

| Sev | What | Where |
|---|---|---|
| major | `FittedBox` gives its child unbounded width, so the biggest-expense tile's `maxLines: 1` **never ellipsised** — a long category name scaled to ~3.7sp instead of truncating | `reports_screen.dart` |
| major | **The security settings made false promises.** The PIN sheet said "you will be asked for it every time the app starts" and the Net Worth lock said those screens "stay hidden" — this app has neither gate. The flags arm the *web* client | `security_sheets.dart`, `security_card.dart` |
| minor | Insights judged "was there a previous period?" from one metric's `previous != 0`, so a month that earned and spent ₹50,000 (net exactly 0) made the Net card claim nothing was recorded | `insights_screen.dart` |
| minor | Spending-pace values didn't line up: a `Flexible` shrink-wraps, so `centerRight` had nothing to align within | `insights_screen.dart` |
| minor | Mark-read invalidated the feed **after** navigating away, on a disposed ref — the bell kept a stale unread count all session | `notifications_screen.dart` |

The layout lens wrote failing widget tests to prove its findings; those tests are
now green rather than deleted.

A **fourth false security claim** turned up during the device walk that no lens
had caught — a footnote under the 2FA row still read *"These locks only gate the
app on your devices."* Fixed the same way as the other three.

## Parity fixes landed with this phase

Deferred from `docs/WEB_PARITY.md` while Phase 5 held `lib/core/`:

- **Pasting a figure copied from the web app was silently dropped.** The
  formatter tested the raw text, so the first comma in `₹50,00,000` failed the
  shape check and the whole paste was rejected with no feedback. It now
  sanitises separators, spaces and the rupee sign, and holds the caret.
- **Percent fields truncated the third decimal.** They reused the money
  formatter's 2-dp cap, so typing `2.125` left `2.12` and swallowed the
  keystroke. All five rate/charge fields now take 3 decimals.
- **`Money.compact` picked its magnitude bucket before rounding**, so ₹99,99,999
  rendered `₹100L` — a unit the scale does not use — where the web renders
  `₹1Cr`. The bucket is now chosen from the value as it will print, at whatever
  precision the caller asked for.

## Known and deliberate

**The PIN and wealth-lock settings write server-side flags this app does not yet
enforce.** The copy now says so plainly rather than implying the phone is locked.
The actual lock screen is Phase 6 work (`local_auth` is already a dependency);
the wording changes when the gate ships.

**Widget tests measure in `flutter test`'s fallback font, not Inter**, where every
glyph is exactly `fontSize` wide — roughly 75% wider than Inter for digits. No
test loads a `FontLoader`. This makes every layout assertion *conservative*: the
suite over-reports overflow risk rather than under-reporting it, so it fails safe.
Worth fixing before any layout test is used to justify tightening a width.

## Device gate — passed

Installed on the owner's CPH2569 (Android 15) over wireless ADB and walked end to
end: Reports (period pager, stat tiles, "Where it went", insight banner, category
donut), Insights (first-period copy, spending pace, movers, biggest expenses),
Notifications (grouped by day, per-type sentences, deep links), Settings (profile,
appearance, security, sign out, app info).

Confirmed on device:
- The biggest-expense tile renders "Groceries" at full size — the FittedBox fix.
- "Spending vs last month" shows an em-dash, not "null%" or "Infinity".
- The three spending-pace values end flush with the progress bar's right edge.
- The unread bell badge shows 6 and matches "6 unread of 6 notifications".

`logcat` clean across 11,097 lines: no `RenderFlex`, no `E/flutter`, no `FATAL`.
