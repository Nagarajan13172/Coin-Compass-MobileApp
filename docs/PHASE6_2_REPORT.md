# Phase 6.2 — Net Worth lock, verified on the device

Walked end to end on the owner's phone (CPH2569, Android 15, 1080×2412 @ 480dpi →
360×804dp) against the **live** backend, on the owner's real account.

The account was returned to exactly the state it was found in: **all three locks
`Off`**, confirmed after a cold start so the flag is off server-side and not just
in local state.

## Why this needed a device

The locked half of 6.2 was covered by 1,346 lines of widget tests against a fake
server. What no fake could answer is what the **real** server does when the flag
is on — and one of those answers turned out to be the thing the whole feature
hangs on.

## The state machine, confirmed against the real server

| state | pill | actions offered | verified |
|---|---|---|---|
| no passcode | `Off` | Set a passcode | ✅ |
| passcode exists, session elevated | `On` | Change passcode · Lock now · Turn off | ✅ |
| locked | `Locked` | **Unlock, and nothing else** | ✅ |

**Setting a passcode leaves the current session elevated.** `POST
/settings/wealth-passcode` sets the account flag *and* the session comes back
`mode: superadmin`, so Net Worth stays visible in this app until "Lock now". This
was previously inferred from the deployed bundle only — and it is the fact I had
stated backwards earlier in the project. It is now confirmed live, and the row's
copy says it correctly: *"Unlocked for this sign-in."*

**"Turn off" is absent while locked.** Confirmed on the device: the locked row
offers `Unlock` alone. Anyone holding the unlocked phone therefore cannot fire
`DELETE /settings/wealth-passcode` and discard a passcode they do not know.

## What the lock actually hides

With the lock engaged:

- **Dashboard** — the Net worth card is *removed*, not blanked. Income, Expense
  and Net stay, which is what the settings copy promises.
- **More menu** — Net Worth and Stocks disappear from the list, and a
  highlighted **"Unlock Net Worth"** row is added. Nothing vanishes without an
  affordance.
- **Reports** — spending, categories and the income-vs-expense chart all render;
  no net worth figure anywhere.
- **Settings** — row reads `Locked`.

## The two results worth keeping

**The lock survives a cold start, and the cache did not leak.** Force-stopped the
app while locked and relaunched. The dashboard came back with no Net worth card —
even though `−₹2,00,00,000` had been cached on disk minutes earlier, before the
lock. That is 6.3's three wealth-scope barriers holding under the exact condition
they were built for.

**The unlock does not flicker back.** Entered the passcode, the card returned, and
it was still there 8 seconds later. That is the `_userGeneration` guard: a
`GET /auth/me` that started before the unlock cannot land after it and restore the
old flag. Now also pinned by `auth_flow_test.dart`.

A wrong passcode is rejected **by the server** — *"That passcode didn't match."* —
with the sheet and field intact.

## One bug found, fixed, and pinned

**The rejection message did not clear when the owner typed again.** After a failed
attempt, the red *"That passcode didn't match."* stayed on screen for the whole
time they were entering the replacement — an error about a passcode that was no
longer in the field.

`WealthLockController.clearError()` had existed since 6.2 was written and had
**zero callers**. It is now wired to the field's `onChanged`, guarded so an
untouched field does not rebuild the sheet on every keystroke.

Pinned by *"the rejection clears as soon as the owner types again"*, and the fix
was mutation-verified: unwiring `clearError()` fails the test.

Suite 733 → **734**, analyzer clean.

## Two things left as findings, not fixed

**No orientation lock.** There is no `android:screenOrientation` in the manifest
and no `SystemChrome.setPreferredOrientations` anywhere in `lib/`. The phone
rotated mid-pass twice, and in landscape with the keyboard up a form sheet
collapses to an unusable sliver. Portrait-only is one line; it is a product call,
not a bug fix, so it is flagged rather than applied.

**Form sheets are cramped with the keyboard up.** At 360×804dp with the keyboard
open, `FormSheetScaffold`'s body viewport is roughly 96dp — about one field. The
two-field passcode sheet needs a scroll to reach "Confirm passcode".

I initially read this as the submit button *overlapping* the confirm field and
was wrong: the field scrolls into reach and the sheet is functional. Worth saying
plainly, because "cramped" and "broken" deserve different responses.

## Safety

The passcode used was `test1234`, stated before it was sent. It was removed at the
end of the pass via the app's own "Turn off", and the removal was verified on a
cold start. `POST /auth/lock-wealth` was only ever reached through the Settings
row's own guarded call site, with a passcode known to exist.
