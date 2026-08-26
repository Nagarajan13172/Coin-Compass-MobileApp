# Phase 7.5 — iOS build

The roadmap said *"already configured for iOS; needs signing + an on-device
test"*. Signing was already configured too. What actually blocked it was a
deployment target that **7.1 had quietly invalidated**.

## What was wrong

`pod install` failed the whole build:

    Error: The plugin "google_mlkit_commons" requires a higher minimum iOS
    deployment version than your application is targeting.
    To build, increase your application's deployment target to at least 15.5

7.1's runtime translation added `google_mlkit_translation`, which needs **iOS
15.5**. The Xcode project still said **13.0**, and `ios/Podfile` had its
`platform` line commented out — so CocoaPods inferred 13.0 from the project and
failed with a resolver stack trace rather than a useful message.

Nobody would have seen this: the Android build is unaffected, and iOS had not
been built since 7.1 landed.

## What changed

- `IPHONEOS_DEPLOYMENT_TARGET` **13.0 → 15.5** across all three targets in
  `project.pbxproj`.
- `ios/Podfile` — `platform :ios, '15.5'` **uncommented and pinned**, so the
  next plugin bump fails with a version message instead of a resolver trace.

**This is not a free choice.** It drops iOS 13 and 14 devices. ML Kit had
already made those unsupportable; this only makes it visible.

## What builds

Both, on Xcode 26.5:

    flutter build ios --no-codesign --debug   ✓ Built build/ios/iphoneos/Runner.app
    flutter build ios --debug                 ✓ Built build/ios/iphoneos/Runner.app

The signed build picks up the team already in the project:

    Automatically signing iOS for device deployment using specified
    development team in Xcode project: A9L6RR9C29

So signing is not outstanding either. Bundle id `cloud.sathishkumar.coincompass`,
matching Android.

## The simulator cannot be used

    The following target(s) do not support arm64 architecture, which is a
    requirement for Apple Silicon iOS 26+ simulators:
      - GoogleMLKit, MLImage, MLKitCommon, MLKitTranslate, MLKitVision

ML Kit ships no arm64 simulator slices, so on an Apple Silicon Mac the app runs
on a **real device only**. That is a permanent consequence of 7.1 for as long as
ML Kit is a dependency, and it makes the on-device test below the *only* way to
exercise iOS at all.

## Still open

- **The on-device test.** No iPhone or iPad was attached — `flutter devices`
  found only "Bhadrinathan's iPad Pro" over the network, unreachable. Needs a
  cable, an unlocked device, and the device registered to team `A9L6RR9C29`.
- **`flutter build ipa`** for TestFlight/App Store was not attempted: it needs a
  distribution profile rather than the automatic development signing above.
- **Two plugins do not support Swift Package Manager**
  (`google_mlkit_translation`, `google_mlkit_commons`), which a future Flutter
  will reject. A warning today.
- Worth checking on the first real run, because neither has been exercised on
  iOS: the app lock's `local_auth` (Face ID needs an `NSFaceIDUsageDescription`
  in `Info.plist`) and 7.4's notification permission prompt.
