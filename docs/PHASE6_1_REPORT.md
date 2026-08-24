# Phase 6.1 — Biometric + PIN app lock

**Status: complete and verified on device.** `flutter analyze` clean ·
**580 tests passing** · debug APK built, installed, walked · logcat clean across
12,930 lines.

## What it does

A device-local app lock, gating cold start and resume-after-30s. The gate lives in
`MaterialApp.builder` — above the Router, below Theme/MediaQuery — so on a cold
start the `Router` child is never mounted and no screen can paint before the lock.

**Nothing on the unlock path touches the network.** The PIN is 4–8 digits, stored
only as a PBKDF2-HMAC-SHA256 verifier with a per-install 16-byte `Random.secure()`
salt in SharedPreferences, derived in an isolate so the unlock does not jank.
Biometrics (`local_auth`) are an opt-in fast path on top, never the only path. It
behaves identically in aeroplane mode.

`POST /settings/pin/verify` is **never** on the unlock path. Verified after the
device walk: the owner's account still reads `pinEnabled: false`,
`wealthLockEnabled: false`.

## Threat model — stated, not implied

Defends against one thing: a person who picks up the already-unlocked phone and
opens or resumes CoinCompass to read a net worth or a loan balance. It buys
friction on an unattended running device.

It does **not** defend against root, a debugger, `adb backup`, or an extracted app
sandbox — the `mt_session` cookie already sits in `PersistCookieJar`'s files and
reads the whole account straight from the API. A 4-digit PIN behind any KDF is
~10,000 candidates. This is a privacy curtain, not a security boundary, which is
why it fails **open** on corrupt local state and always offers a keyless way out.

## Host changes

- `MainActivity` → `FlutterFragmentActivity` (`local_auth` needs a FragmentActivity;
  as `FlutterActivity` every biometric call threw `no_fragment_activity`)
- **`android.permission.INTERNET` added to the main manifest** — see below
- Recents masking via `setRecentsScreenshotEnabled(false)` on API 33+, `FLAG_SECURE`
  as the pre-33 fallback, applied only while the lock is armed

## ⚠️ Release-blocking bug found in passing

The signed release APK had **no `android.permission.INTERNET`**. Confirmed with
`aapt2 dump permissions` on the actual signed artifact — it carried only
`USE_BIOMETRIC`, `USE_FINGERPRINT` and a receiver permission.

Flutter injects `INTERNET` into the **debug** and **profile** manifests only, never
the main one. Every build tested on the device worked; the release AAB would have
installed, launched, and failed every API call. The app would have been unusable
and the failure would have looked like a server outage.

Nothing to do with 6.1 — found because a design agent verified the manifest with
`aapt2` instead of trusting the brief. Fixed.

## Review findings — 8 confirmed, all fixed

| Sev | What |
|---|---|
| **blocker** | `_markAway()` refreshed `lastActiveAtMs` **while the lock screen was showing**, so killing the app from the lock screen and reopening within 30s started **unlocked**. Fixed two ways: `_markAway` returns early when locked, and `_enterLocked` burns the stamp so being locked survives process death |
| major | **"Forgot your PIN?" was dead in production** — `showModalBottomSheet` from `MaterialApp.builder`, which has no Navigator ancestor. The test passed only because a bare `MaterialApp(home:)` harness *does* have one. Rebuilt as an inline panel needing no Navigator |
| major | Cooldown stored an absolute instant with no backwards-clock guard: a clock jump disabled the keypad for the whole skew. Remaining time now clamps to one max grant — self-healing |
| major | "Turn off the PIN lock?" said *"the app will open without asking for a PIN"* — false whenever the app lock is on. Renamed **"Turn off the web PIN?"**, and it now says the phone lock is separate |
| minor | Sign-out from Settings never cleared the lock store, so the previous account's verifier survived into the next sign-in |
| minor | A throwing PBKDF2 isolate left `verifying: true` forever, permanently disabling the keypad |
| minor | The row claimed "PIN — or your fingerprint" from `lock.enabled` alone, so a PIN-only setup advertised a fingerprint it would never offer |

Two of the eight were **honesty bugs** — the same class that shipped twice in Phase 5.

## Verified on the device

- Sign-in screen is **not** gated (the lock is inert when signed out)
- "Lock now" → lock screen with in-app keypad, both escape hatches present
- **Force-stop from the lock screen → relaunch ~10s later → still locked** (the blocker)
- "Forgot your PIN?" opens, with zero Flutter errors in logcat
- PIN unlock → dashboard
- Turning the lock **off requires the PIN**, so a grabbed phone cannot disarm it
- The off-toast names the side effect it reverts: *"Screenshots and the app-switcher
  preview work normally again."*
- Server settings unchanged: `pinEnabled: false`, `wealthLockEnabled: false`

**Left off.** The test PIN was `1234` and the owner does not know it, so the lock was
disarmed after testing rather than left armed.

## Not done here

Biometric unlock could not be exercised over adb — it needs a real fingerprint. The
capability probe, the opt-in toggle and the error-code handling are built and unit
tested; the prompt itself is unverified on hardware.

The **Net Worth lock is still 6.2** and its copy remains honest about that.
