# Phase 6.10 — on-device pass, all 17 screens

Walked on the owner's phone (CPH2569, Android 15, 1080×2412 @ 480dpi → 360×804dp)
against the **live** backend with their real data, in dark mode.

## Coverage

All 17 destinations plus the four secondary screens that hang off them.

| screen | data | verdict |
|---|---|---|
| Dashboard | real | ✅ |
| Transactions | 2 txns, Aug 2026 | ✅ |
| Reports | real | ✅ |
| Calendar | real | ✅ |
| Budgets | empty | ✅ empty state |
| Goals | empty | ✅ empty state |
| Accounts | empty | ✅ empty state |
| Credits | empty + summary | ✅ |
| Recurring | 2 rules | ✅ |
| Categories | 23 expense · 10 income | ✅ |
| Net Worth | real | ⚠️ caption bug — fixed |
| Stocks | empty | ✅ + demat explainer |
| Loans | 1 active, ₹2Cr | ✅ |
| Gold & Silver | live rates | ✅ |
| Insights | real | ✅ |
| Notifications | 6 unread | ✅ |
| Settings | real | ✅ |
| Holdings | empty | ✅ |
| People & groups | empty | ✅ |
| Splits | empty | ✅ |

Highlights worth recording: Gold & Silver pulls live Chennai/GRT rates (22K
₹15,030/g, spot ₹4.43L/oz, last close 24 Aug 2026). Loans computes EMI ₹1.37L,
interest-left ~₹2.86Cr and a 7.25% balance-weighted average across one loan.
Insights writes real prose and admits *"This is your first month with data"*
rather than inventing a comparison. Categories groups by parent with per-group
counts, and the count agrees with Settings (33).

## The bug this pass existed to find

**The dashboard net-worth card captioned a figure with a false statement about it.**

On the owner's account the card printed:

```
−₹2,00,00,000
Sum of 0 accounts  ⓘ
```

The sum of zero accounts is ₹0. Every rupee of that −₹2Cr is the loan. Net worth
is `accounts + holdings + stocks − loans`, so the caption was never describing the
number above it — it was wrong with accounts too, just less visibly: one holding,
one stock or one loan and the label became a lie.

The caption now states what the figure is: **"Everything you own, minus what you
owe."** The account count belongs on the Accounts card, and the full derivation is
one tap away behind "Breakdown".

Pinned by *"the net-worth caption describes the figure it sits under"*, which runs
on the owner's own captured snapshot (`accountsTotal: 0`, `assets: 0`,
`liabilities: 20000000`, `netWorth: -20000000`) — the exact numbers that exposed
it. Mutation-verified: restoring the literal `'Sum of 0 accounts'` compiles
cleanly and fails the test with *"net worth is assets MINUS liabilities, never a
sum of accounts"*.

Removing the string also made an existing assertion vacuous —
`expect(find.textContaining('Sum of'), findsNothing)` in the locked-dashboard test
could no longer fail. That assertion now targets the new caption, so it still
tests something.

Suite 734 → **836**, analyzer clean.

## Findings not fixed

**No orientation lock** — still the largest one, and now with evidence. There is
no `android:screenOrientation` and no `SystemChrome.setPreferredOrientations`
anywhere in `lib/`. The phone rotated twice mid-pass, and the landscape capture of
**Calendar** shows the month grid clipped to its day-name header row by the bottom
nav — the screen is unusable. Form sheets in landscape collapse to a sliver.
Portrait-only is one line, but it is a product call.

**Two opposing arrows on the Net Worth card.** The corner badge is
`negative ? trendingDown : trendingUp` — it reports that net worth *is negative*.
The delta arrow beside it is `delta >= 0 ? trendingUp : trendingDown` — it reports
that net worth *improved*. On the owner's account both fire at once: a red
down-arrow badge next to a green ↗ +3.62%. Both statements are true and they are
different facts, but at a glance they read as contradicting each other.

**Minor truncation at 360dp.** The Credits screen's "People & Groups" tile
ellipsises to "People & …", and Recurring's row subtitle ellipsises mid-word
("Last poste…") even across two lines.

## Not app bugs

A notification from 24 days ago reads *"Low balance — Cash is overdrawn
(−₹7,50,633)"* while Accounts is empty. That is a historical notification about an
account since deleted, which is correct behaviour for a feed.

## Method note

Driven by `adb` with screenshots read back visually, rather than blind taps. Three
things went wrong and are worth writing down:

1. **The phone dozes within seconds over wireless adb** — `mStayOn=false` because
   it draws no power — so several captures came back black and the device
   re-locked behind a secure lock screen.
2. **A stray tap reached the lock screen and opened the camera.** No photo was
   taken (verified against `/sdcard/DCIM`). The navigation helper now refuses to
   send any tap unless `dumpsys window` says our package owns the focused window.
3. **One capture was silently the wrong screen** — a tap eaten by a wake landed
   nowhere and the Dashboard was captured under the name `budgets`. Screen
   identity is now confirmed visually per capture rather than assumed from
   coordinates; `uiautomator dump` is useless here because Flutter exposes no
   semantics tree without an accessibility service.
