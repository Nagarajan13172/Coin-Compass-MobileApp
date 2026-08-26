# Phase 7.4 — Notifications on the phone

The roadmap said this needed *"FCM + a backend change"*. It does, for real push.
It does **not** for the thing the owner actually wants — the phone telling them
when something happens — and that is what shipped.

## There is no push, and there cannot be

Verified before building anything:

- **No device-token endpoint.** `GET|POST /notifications`, `/read-all`,
  `/:id/read` and the two deletes are the entire surface. Nothing registers a
  token, and nothing sends one.
- **No backend source on this machine** (`SPEC.md` §1), so the endpoint cannot
  be added.

Adding `firebase_messaging` would therefore produce a token with nowhere to go
and nothing to deliver — a permission prompt, a dependency, and no user-visible
behaviour. So the app **polls the feed it already has** and raises the
notification itself.

The honest limitation, stated in Settings rather than buried here: alerts arrive
when the check runs, not the instant the server records them.

## What runs, and when

    on resume  ─┐
                ├─▶ NotificationPoller.check() ─▶ decideSurface() ─▶ post
    every 15m  ─┘

- **On resume** — `didChangeAppLifecycleState`, every return to the foreground,
  not just cold start.
- **Every ~15 minutes** — WorkManager, which is Android's floor and a *floor*,
  not a promise: Doze and app-standby stretch it.

The background half is what makes the feature worth having. A notifier that only
fires while you are already looking at the app tells you nothing you did not
just see, so it was in scope from the start.

`NotificationPoller` deliberately owns no Riverpod state, because one of its two
callers is a **background isolate with no provider container**. That works
because the session is an httpOnly cookie in a `PersistCookieJar` under the app
documents directory — `ApiClient.create()` picks it up in the isolate exactly as
it does in the app.

## The rule that matters most: silence on the first run

A feed that has been accumulating for weeks is not news. The owner's account had
**six unread notifications** in it before this feature existed. Announcing all
six on the first check would be six buzzes about things they already knew, and
the feature would be switched off before it ever showed anything useful.

So the first check **adopts** the feed: everything present is recorded as seen
and nothing rings. Only what arrives after that is new.

`isFirstCheck` is a separate flag rather than `seen.isEmpty`, because an empty
set is also what a brand-new account has — and *that* user's first real
notification must still ring. A test pins exactly that distinction.

## Everything else it refuses to do

| | |
|---|---|
| Feature off | Does not even fetch |
| No OS permission | Skips; never posts |
| Offline / dead session / 500 | Silence, never a notification about the network |
| Already read (including read on the web) | Not announced — `read` is server state |
| Already announced | Never announced again, across restarts |
| A burst of 40 | At most **5** ring, newest five; the rest are marked seen so the burst does not arrive one buzz at a time |
| Toggled off and back on | The backlog is not replayed |

The remembered set is capped at 200 ids and **never evicts an id still in the
feed** — evicting a live id is exactly how a notification rings twice.

State is persisted *after* posting, so a crash mid-post replays rather than
silently swallowing: a duplicate notification is a much smaller failure than a
missing one.

## Content and tapping

Nothing new was written. `NotificationCopy.of()` already composes the title and
body for all six notification kinds for the in-app bell, so the device
notification says exactly what the feed says. The alert id is a stable hash of
the Mongo `_id`, so a re-post replaces its own entry in the shade instead of
stacking a second copy.

A tap carries the server's own `link` (`/budgets`, `/recurring`) and routes with
`go`, not `push` — a notification is a jump to a destination, not a step deeper
into wherever the user happened to be.

## The switch

Off by default, in Settings under Language, next to the other **device-scoped**
settings rather than the account-scoped ones above: this is a per-phone choice,
not something stored on the server, so a second device is unaffected.

It reflects what is **actually** true rather than what was tapped. The user can
refuse the Android prompt, and a toggle that stayed on after that would be
claiming something the app cannot do — the same failure 7.1a had with the
language pill. Device-verified: with permission denied, the switch stayed off
and said why.

## Verified on hardware

CPH2569, Android 15, in Tamil.

- The card renders in Settings, correctly **off by default**, no overflow.
- **The permission-denied path is correct** — tapping the switch with
  POST_NOTIFICATIONS denied left it off and explained what to do.

**Not verified: the happy path.** Android refuses synthetic taps on permission
toggles by design (`adb shell pm grant` is rejected on this ROM, and `input tap`
does not reach the system permission switch), so the grant has to be a real
human tap. Once notifications are allowed for CoinCompass in system settings,
the remaining path to check is: toggle on → first check adopts silently → a new
server notification arrives → it rings → tapping it opens the right screen.

The logic underneath is covered by 22 tests that do not need a phone.

## Platform notes

- `POST_NOTIFICATIONS` (Android 13+) and `RECEIVE_BOOT_COMPLETED` added, the
  latter so the periodic check survives a reboot.
- **Core library desugaring enabled.** `flutter_local_notifications` refuses to
  build without it — the AAR metadata check fails the build outright.
- The status-bar icon reuses `ic_launcher_monochrome`, which 6.7 already ships
  for Material You themed icons: Android renders a small icon as a silhouette,
  so the full-colour launcher icon would come out a white blob.
- `workmanager_android` still applies the Kotlin Gradle Plugin, which a future
  Flutter will reject. A warning today, not an error.
