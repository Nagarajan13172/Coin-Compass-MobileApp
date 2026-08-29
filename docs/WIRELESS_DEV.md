# Running CoinCompass on a phone over Wi-Fi

Everything here is terminal-only. The goal is a phone on your desk with no cable
in it, running a debug build with hot reload.

Two independent networks are involved and it helps to keep them apart in your
head:

- **The debug link** — Mac ⇄ phone. This is what must be wireless, and it is the
  only part that requires both devices on the *same* Wi-Fi.
- **The API link** — phone ⇄ backend. `ApiClient.baseUrl` points at
  `https://coincompass.sathishkumar.cloud/api`
  ([api_client.dart:36](../lib/core/api/api_client.dart#L36)), a public HTTPS host.
  So the phone just needs internet. There is no local server to reach, nothing
  to reverse-tunnel, and none of the `10.0.2.2` emulator business.

## 0. Toolchain check

The Flutter SDK is already installed and on `PATH`:

```bash
flutter --version      # Flutter 3.44.0 • stable • Dart 3.12.0
```

`adb`, however, **is not on `PATH` on this machine** — it ships with the Android
SDK but nothing exports it. Fix that once:

```bash
echo 'export ANDROID_HOME="$HOME/Library/Android/sdk"' >> ~/.zshrc
echo 'export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"' >> ~/.zshrc
source ~/.zshrc

adb version            # Android Debug Bridge 1.0.41 • 37.0.0
```

Wireless pairing needs platform-tools ≥ 30; 37.0.0 is well past that.

Then confirm the whole chain — this is the command that tells you which half is
broken when something later fails:

```bash
flutter doctor -v
```

Fetch packages once per clone (and after any `pubspec.yaml` change):

```bash
flutter pub get
```

`flutter run` regenerates the localisations (`L`) on its own, because
`pubspec.yaml` sets `flutter: generate: true`. You do not need a separate
`flutter gen-l10n` step.

---

## 1. Android over Wi-Fi

### Requirements

| | |
|---|---|
| Phone OS | **Android 11 (API 30) or newer** for `adb pair`. Older phones take the [USB-bootstrap route](#android-10-and-older) |
| App floor | `minSdk 24` (Android 7) — the app runs lower than pairing does |
| Network | Phone and Mac on the same Wi-Fi, with client isolation **off** on the router |

### Enable the phone side

On the phone, all in Settings:

1. **About phone** → tap **Build number** seven times → Developer options unlock.
2. **Developer options** → turn on **Wireless debugging**.
3. Inside Wireless debugging → **Pair device with pairing code**.

That last screen shows an IP, a **pairing port**, and a six-digit code. Leave it
open — it dies the moment you back out, and the port is single-use.

### Pair, then connect

These are two different ports. The pairing port is ephemeral and only used once;
the connect port is the one on the main Wireless debugging screen.

```bash
# One time per phone. Use the IP:PORT from the *pairing* dialog.
adb pair 192.168.1.42:37129
# Enter pairing code: 314159
# → Successfully paired to 192.168.1.42:37129

# Every session. Use the IP:PORT from the main Wireless debugging screen.
adb connect 192.168.1.42:5555
# → connected to 192.168.1.42:5555

adb devices -l
# 192.168.1.42:5555   device product:… model:… 
```

The pairing survives reboots; the connection does not. Day to day you only run
`adb connect`, and only when the device has dropped off.

### Run it

```bash
flutter devices
# CoinCompass phone (mobile) • 192.168.1.42:5555 • android-arm64 • Android 15 (API 35)

flutter run -d 192.168.1.42:5555
```

With exactly one device attached, plain `flutter run` picks it and you can skip
the `-d`.

Once it's up, the keys in that terminal are the point of the whole exercise:

| Key | Effect |
|---|---|
| `r` | Hot reload — new code, state kept |
| `R` | Hot restart — new code, state discarded |
| `o` | Toggle platform (Android ⇄ iOS look) |
| `p` | Layout-bounds overlay |
| `v` | Open DevTools in a browser |
| `q` | Quit and stop the app |

Other build modes:

```bash
flutter run -d 192.168.1.42:5555 --profile   # perf work; no hot reload
flutter run -d 192.168.1.42:5555 --release   # ship-shaped build; no hot reload
```

`--release` on Android falls back to the debug signing key unless
`android/key.properties` exists — fine for testing on your own phone, never
publishable. See [RELEASE.md](RELEASE.md).

### Reattach without rebuilding

If you kill the terminal but the app is still running on the phone:

```bash
flutter attach -d 192.168.1.42:5555
```

### Android 10 and older

No `adb pair` on these. Bootstrap over a cable once, then pull the cable — the
TCP listener survives until the phone reboots:

```bash
adb devices                 # confirm the USB device is listed
adb tcpip 5555              # restart adbd on TCP; USB link drops
# unplug the cable now
adb connect 192.168.1.42:5555
```

Find the IP under Settings → About phone → Status, or over USB with
`adb shell ip route`.

---

## 2. iPhone over Wi-Fi

The iOS project is configured: bundle id `cloud.sathishkumar.coincompass`, team
`A9L6RR9C29`, deployment target **iOS 13.0**.

Apple has no `adb pair` equivalent — the one-time trust handshake has to happen
over a cable, in Xcode:

1. Plug the iPhone in, unlock it, tap **Trust**.
2. Xcode → **Window ▸ Devices and Simulators** → select the phone → tick
   **Connect via network**.
3. Wait for the globe icon next to its name, then unplug.

From there it is terminal-only again:

```bash
flutter devices
flutter run -d "Nagarajan's iPhone"
```

First run on a fresh checkout also needs CocoaPods:

```bash
cd ios && pod install && cd ..
```

Two things that bite on iOS and not on Android:

- The phone must be **unlocked** for a wireless run to start.
- On a free (non-paid) Apple ID, the provisioning profile expires after **7
  days** and the app refuses to launch until you re-run it.

---

## 3. Project-specific notes

- **First launch needs a login.** The session is a cookie held by
  `PersistCookieJar`, so it survives restarts of the app but not a reinstall.
- **Biometric app lock** (`local_auth`) needs real hardware with an enrolled
  fingerprint/face — a wireless phone is exactly the right target, a simulator
  is not.
- **Tamil translation** (`google_mlkit_translation`) downloads its model on
  first toggle in Settings. That download goes over the phone's own internet
  connection and is a few tens of MB; it runs on-device afterwards.
- **CSV import** (`file_picker`) opens the system picker — another thing that
  only behaves honestly on a device.
- Tests and static analysis need no device at all:

  ```bash
  flutter test
  flutter analyze
  ```

---

## 4. When it breaks

| Symptom | Cause and fix |
|---|---|
| `adb: command not found` | `PATH` not exported — redo step 0 |
| `failed to connect to 192.168.1.42:5555` | Phone changed IP (DHCP lease), or Wireless debugging got toggled off. Re-read the IP:PORT off the phone and `adb connect` again |
| Pairing fails / `protocol fault` | The pairing dialog was closed or timed out. Reopen **Pair device with pairing code** for a fresh port and code |
| Paired fine, `adb devices` still empty | Router has AP/client isolation on, or Mac and phone are on different bands or a guest SSID. Put both on the same SSID |
| Device shows `offline` | `adb disconnect && adb kill-server && adb start-server`, then `adb connect …` |
| Device shows `unauthorized` | Accept the RSA-key prompt on the phone; if it never appeared, revoke under Developer options → **Revoke USB debugging authorisations** and pair again |
| `flutter devices` empty but `adb devices` fine | Stale tool state — `flutter doctor -v`, and check the phone isn't asleep |
| Connection drops every few minutes | Wi-Fi power saving. On the phone: Developer options → **Stay awake**, and set the Wi-Fi network to not sleep |
| Hot reload noticeably slower than USB | Expected. Wi-Fi round-trips cost more; `R` (hot restart) is sometimes faster than a slow `r` on a big change |
| Gradle/build failure after a `pubspec.yaml` edit | `flutter clean && flutter pub get`, then run again |

---

## Cheat sheet

```bash
# once per machine
echo 'export ANDROID_HOME="$HOME/Library/Android/sdk"' >> ~/.zshrc
echo 'export PATH="$PATH:$ANDROID_HOME/platform-tools"' >> ~/.zshrc && source ~/.zshrc

# once per phone
adb pair <ip>:<pairing-port>

# each session
adb connect <ip>:<port>
flutter devices
flutter run -d <ip>:<port>          # r = reload · R = restart · q = quit

# teardown
adb disconnect <ip>:<port>
```
