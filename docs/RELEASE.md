# Releasing CoinCompass Mobile

## Signing material

| What | Where |
|---|---|
| Upload keystore | `~/.android-keystores/coincompass-upload.jks` — **outside the repo**, `chmod 600` |
| Alias | `coincompass-upload` |
| Passwords | `android/key.properties` only — gitignored, `chmod 600` |

The keystore lives outside the working tree on purpose. A gitignored file inside
the repo is still deleted by `git clean -xfd`, and losing this file means no
further update can ever be published against the same Play listing.

**The password exists in exactly one place.** It was generated at creation time
and never printed anywhere else — read it out of `android/key.properties` and put
it in a password manager. Nothing can recover it.

Certificate, for cross-checking an upload:

```
CN=CoinCompass, OU=Mobile, O=CoinCompass, C=IN
SHA-1   4C:3A:26:56:6D:AC:AD:81:8F:43:93:C6:C9:ED:00:D8:AF:60:1D:BA
SHA-256 ed7cd49d0779613af37bd0b7b171ead5ce93000fb6535ba4bc1331934e27fa20
PKCS12 · RSA 4096 · SHA384withRSA · valid to 9 Jan 2054
```

## Building

```bash
flutter build appbundle --release      # what Play wants
flutter build apk --release            # one fat APK, every ABI — sideloading
flutter build apk --release --split-per-abi
```

`android/app/build.gradle.kts` reads `android/key.properties` if it is there and
signs with the upload key; if it is absent it falls back to the debug key so a
fresh clone still builds. **A build made without `key.properties` is debug-signed
and must not be published** — check before uploading:

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
~/Library/Android/sdk/build-tools/37.0.0/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

The DN must read `CN=CoinCompass`, never `CN=Android Debug`.

Only the v2 signature scheme is present, and that is correct: `minSdk` is 24, and
v1 (JAR) signing is only needed below 24.

## Sizes, as built on 24 Aug 2026

| Artifact | Size |
|---|---|
| `app-release.aab` | 59.2 MiB |
| `app-release.apk` (fat, 3 ABIs) | 61.6 MiB |
| `app-arm64-v8a-release.apk` | 22.7 MiB |
| `app-armeabi-v7a-release.apk` | 20.6 MiB |
| `app-x86_64-release.apk` | 24.1 MiB |

The AAB number is not what anyone downloads — Play slices it per device, so a
real arm64 install is close to the 22.7 MiB APK and smaller after density and
language splits. Nearly all of it is the engine: `libflutter.so` and `libapp.so`
are ~18–21 MiB of every ABI. `classes.dex` is 0.9 MiB.

Two things worth knowing before optimising:

- **2.62 MiB of the 4.05 MiB asset payload is unused font.** `lucide_icons_flutter`
  declares six `LucideVariable-w*.ttf` files (100–600 weight, ~440 KiB each) as
  package assets. The app never references them — it uses `LucideIcons.*`, which
  resolves to `lucide.ttf`, itself tree-shaken from 858 KiB to 43 KiB. Icon
  tree-shaking does not apply to plain asset fonts, and Flutter bundles every
  asset a package declares, so all six ship. Removing them means vendoring the
  package via `dependency_overrides`; worth ~11% of a per-ABI APK.
- **x86_64 is 24.1 MiB of the fat APK** and serves emulators and a handful of
  Chromebooks. Irrelevant to Play (per-device delivery), but
  `--target-platform android-arm,android-arm64` shrinks a sideloaded fat APK a
  lot.

## Before each Play upload

- Bump `version:` in `pubspec.yaml`. It is `1.0.0+1` today; the `+N` is the
  `versionCode` and Play rejects a repeat.
- Re-run the `apksigner verify` check above.
- The manifest already declares `USE_BIOMETRIC` and `USE_FINGERPRINT`, pulled in
  by the `local_auth` dependency even though phase 6.1 has not wired it up yet.
  Either land 6.1 or drop the dependency before shipping, so the listing does not
  ask for a permission the app never uses.
