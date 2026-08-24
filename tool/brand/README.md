# Brand sources

Everything under `android/app/src/main/res/mipmap-*`, `res/drawable-*/splash_logo.png`
and `ios/.../AppIcon.appiconset` is generated from the two PNGs in this folder by
`../gen_brand_assets.sh`. Edit a source, re-run the script, commit the result.

## Where they came from

Fetched from the deployed web app on 24 Aug 2026 — these are the app's own
installed-icon assets, not a redraw:

| File | Source | What it is |
|---|---|---|
| `pwa-512x512.png` | `https://coincompass.sathishkumar.cloud/pwa-512x512.png` | Rounded square (radius ≈20%), mark at 78.5% of the canvas, transparent corners |
| `maskable-icon-512x512.png` | `…/maskable-icon-512x512.png` | Full-bleed `#0F172A`, mark at 64.5% — the `purpose: maskable` entry in `manifest.webmanifest` |
| `favicon.svg` | `…/favicon.svg` | Reference only. A simplified mark (no cardinal ticks) — not used by the generator |
| `apple-touch-icon.png` | `…/apple-touch-icon.png` | Reference only, 180×180 |

`play_store_icon.png` is generated (512×512, no alpha) for the phase 6.9 listing.

## The two marks

The web app uses **two different** compass marks and it is worth not confusing
them:

- The **header logo** — a white Lucide `Compass` glyph on a `#2563EB` rounded
  square. `AppScaffold` already reproduces this, and it stays as-is.
- The **installed-app icon** — a navy `#0F172A` square with a ringed compass,
  cardinal ticks and a blue/off-white needle. That is what this folder holds and
  what the launcher shows, because it is what a user already gets when they
  install CoinCompass from the browser.

Colours in the mark line up with `docs/SPEC.md`: ring `#E3E9F0` ≈ `border`,
needle `#3D82F4` ≈ dark-theme `primary`, ground `#0F172A` ≈ dark `background`.

## Known limitation

The largest source available is 512×512, so the iOS 1024 App Store icon is a 2×
Lanczos upscale. Fine for a debug build; regenerate from a vector master before
any App Store submission (phase 7.5).
