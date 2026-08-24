#!/usr/bin/env bash
#
# Regenerates every launcher-icon and splash asset from the two brand sources in
# tool/brand/. Run it from the repo root after changing a source:
#
#   ./tool/gen_brand_assets.sh
#
# Requires ImageMagick 7 (`brew install imagemagick`). Nothing else — no Flutter
# packages, no pubspec entry. The generated files are committed, so a fresh
# clone builds without running this.
#
# Provenance of the sources: see tool/brand/README.md.

set -euo pipefail

cd "$(dirname "$0")/.."

command -v magick >/dev/null || { echo "need ImageMagick 7 (brew install imagemagick)"; exit 1; }

SRC_ROUNDED=tool/brand/pwa-512x512.png            # rounded square, mark at 78.5%
SRC_MASKABLE=tool/brand/maskable-icon-512x512.png # full bleed navy, mark at 64.5%
NAVY='#0F172A'                                    # background / theme_color

RES=android/app/src/main/res
IOS=ios/Runner/Assets.xcassets/AppIcon.appiconset

# density buckets: name:scale — scale is the multiplier on the dp size
BUCKETS=(mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4)

px() { python3 -c "print(round($1*$2))"; }

# ---------------------------------------------------------------------------
# 1. Legacy launcher icon (API < 26) — the rounded square, straight off the web.
# ---------------------------------------------------------------------------
for b in "${BUCKETS[@]}"; do
  d=${b%%:*}; s=${b##*:}; n=$(px 48 "$s")
  mkdir -p "$RES/mipmap-$d"
  magick "$SRC_ROUNDED" -filter Lanczos -resize "${n}x${n}" -strip "$RES/mipmap-$d/ic_launcher.png"
done

# ---------------------------------------------------------------------------
# 2. Round launcher icon, for API 21-25 launchers that ask for one (API 26+ gets
#    the adaptive icon instead). The maskable's mark sits at 64.5%, which reads
#    thin inside a circle, so it is scaled up to ~70% and centre-cropped — only
#    flat navy is lost.
# ---------------------------------------------------------------------------
for b in "${BUCKETS[@]}"; do
  d=${b%%:*}; s=${b##*:}; n=$(px 48 "$s"); r=$((n / 2)); up=$(px "$n" 1.085)
  magick "$SRC_MASKABLE" -filter Lanczos -resize "${up}x${up}" \
    -gravity center -extent "${n}x${n}" \
    \( -size "${n}x${n}" xc:none -fill white -draw "circle $r,$r $r,0" -alpha copy \) \
    -compose CopyOpacity -composite -strip "$RES/mipmap-$d/ic_launcher_round.png"
done

# ---------------------------------------------------------------------------
# 3. Adaptive icon layers (API 26+). The canvas is 108dp; only the middle 72dp
#    is ever visible and the mask can be any shape inside it, so the mark is
#    scaled to 66dp — the safe circle — and centred.
#
#    The maskable source carries the mark at 64.5% of its own canvas, so
#    shrinking the whole 512 image to 94.81% puts the mark at exactly 61.1%
#    of 108dp = 66dp. The navy is then dropped to alpha; it is redrawn by the
#    background layer underneath, which keeps the foreground a real transparent
#    layer for launchers that parallax it.
# ---------------------------------------------------------------------------
for b in "${BUCKETS[@]}"; do
  d=${b%%:*}; s=${b##*:}; n=$(px 108 "$s"); inner=$(px "$n" 0.9481)
  magick "$SRC_MASKABLE" -filter Lanczos -resize "${inner}x${inner}" \
    -fuzz 4% -transparent "$NAVY" \
    -background none -gravity center -extent "${n}x${n}" \
    -strip "$RES/mipmap-$d/ic_launcher_foreground.png"

  # Android 13+ themed icon. Only the alpha channel is read — the system tints
  # it — so this is flat white with an alpha taken from how far each pixel sits
  # from the navy, which keeps the anti-aliased edges and punches the pivot dot
  # back out as a hole.
  magick "$SRC_MASKABLE" -filter Lanczos -resize "${inner}x${inner}" \
    \( +clone -fill "$NAVY" -colorize 100 \) -compose difference -composite \
    -colorspace Gray -level 4%,22% \
    -colorspace sRGB -alpha copy -fill white -colorize 100 \
    -background none -gravity center -extent "${n}x${n}" \
    -strip "$RES/mipmap-$d/ic_launcher_monochrome.png"
done

# ---------------------------------------------------------------------------
# 4. Splash logo for API < 31 (the Android 12+ splash uses @mipmap/ic_launcher
#    directly). 120dp, centred by launch_background.xml.
# ---------------------------------------------------------------------------
for b in "${BUCKETS[@]}"; do
  d=${b%%:*}; s=${b##*:}; n=$(px 120 "$s")
  mkdir -p "$RES/drawable-$d"
  magick "$SRC_ROUNDED" -filter Lanczos -resize "${n}x${n}" -strip "$RES/drawable-$d/splash_logo.png"
done

# ---------------------------------------------------------------------------
# 5. Play Store listing icon — 512x512, 32-bit, no alpha (Play draws its own
#    corners, so it wants the full-bleed square). Used in phase 6.9.
# ---------------------------------------------------------------------------
magick "$SRC_MASKABLE" -background "$NAVY" -alpha remove -alpha off -strip \
  tool/brand/play_store_icon.png

# ---------------------------------------------------------------------------
# 6. iOS app icon set. iOS rejects alpha and applies its own squircle, so the
#    rounded source is flattened onto the navy. Phase 7.5 territory — generated
#    here only so the default Flutter icon is not what ships if iOS is picked up.
#    NOTE: 1024 is a 2x upscale of a 512 source; regenerate from a vector master
#    before any App Store submission.
# ---------------------------------------------------------------------------
if [ -d "$IOS" ]; then
  flat=$(mktemp -t cc_icon).png
  magick "$SRC_ROUNDED" -background "$NAVY" -alpha remove -alpha off "$flat"
  for spec in 20x20@1x:20 20x20@2x:40 20x20@3x:60 \
              29x29@1x:29 29x29@2x:58 29x29@3x:87 \
              40x40@1x:40 40x40@2x:80 40x40@3x:120 \
              60x60@2x:120 60x60@3x:180 \
              76x76@1x:76 76x76@2x:152 \
              83.5x83.5@2x:167 1024x1024@1x:1024; do
    name=${spec%%:*}; n=${spec##*:}
    magick "$flat" -filter Lanczos -resize "${n}x${n}" -strip "$IOS/Icon-App-$name.png"
  done
  rm -f "$flat"
fi

# ---------------------------------------------------------------------------
# 7. Contact sheet — the shipped assets composited the way each launcher draws
#    them, so the icon can be reviewed without a device. Not used by the build.
# ---------------------------------------------------------------------------
FG=$RES/mipmap-xxxhdpi/ic_launcher_foreground.png
MONO=$RES/mipmap-xxxhdpi/ic_launcher_monochrome.png
FONT=assets/fonts/Inter-Medium.ttf
tmp=$(mktemp -d -t cc_preview)

CIRCLE=( \( -size 288x288 xc:none -fill white -draw "circle 144,144 144,0" -alpha copy \) -compose CopyOpacity -composite )

# adaptive icon: background colour + foreground, cropped to the visible 72/108dp
magick -size 432x432 xc:"$NAVY" "$FG" -composite -gravity center -crop 288x288+0+0 +repage "$tmp/ad.png"
magick "$tmp/ad.png" "${CIRCLE[@]}" "$tmp/1.png"
magick "$tmp/ad.png" \( -size 288x288 xc:none -fill white -draw "roundrectangle 0,0,287,287,64,64" -alpha copy \) \
  -compose CopyOpacity -composite "$tmp/2.png"
# Android 13 themed icon, both tint directions
magick -size 432x432 xc:'#C7D7F7' \( "$MONO" -fill '#16233D' -colorize 100 \) -composite \
  -gravity center -crop 288x288+0+0 +repage "${CIRCLE[@]}" "$tmp/3.png"
magick -size 432x432 xc:'#243554' \( "$MONO" -fill '#DDE7FB' -colorize 100 \) -composite \
  -gravity center -crop 288x288+0+0 +repage "${CIRCLE[@]}" "$tmp/4.png"
# legacy + round, at their real xxxhdpi pixel size
magick "$RES/mipmap-xxxhdpi/ic_launcher.png" -filter point -resize 288x288 "$tmp/5.png"
magick "$RES/mipmap-xxxhdpi/ic_launcher_round.png" -filter point -resize 288x288 "$tmp/6.png"
# pre-31 splash, both themes — the centre of a 1080x2400 launch window
magick -size 1080x1080 xc:'#F8FAFC' "$RES/drawable-xxxhdpi/splash_logo.png" -gravity center -composite \
  -resize 288x288 "$tmp/7.png"
magick -size 1080x1080 xc:"$NAVY" "$RES/drawable-xxxhdpi/splash_logo.png" -gravity center -composite \
  -resize 288x288 "$tmp/8.png"

# caption each tile under itself, then lay them out two rows of four
i=1
for label in "adaptive · circle" "adaptive · squircle" "themed · light" "themed · dark" \
             "legacy (API<26)" "round (API 21-25)" "splash · light" "splash · dark"; do
  magick "$tmp/$i.png" -background '#9AA3B2' -alpha remove -alpha off \
    -gravity south -splice 0x38 -fill '#0F172A' -pointsize 22 -font "$FONT" \
    -annotate +0+9 "$label" -bordercolor '#9AA3B2' -border 12 "$tmp/t$i.png"
  i=$((i + 1))
done
magick \( "$tmp/t1.png" "$tmp/t2.png" "$tmp/t3.png" "$tmp/t4.png" +append \) \
       \( "$tmp/t5.png" "$tmp/t6.png" "$tmp/t7.png" "$tmp/t8.png" +append \) \
       -append -bordercolor '#9AA3B2' -border 12 tool/brand/preview.png
rm -rf "$tmp"

echo "brand assets regenerated"
