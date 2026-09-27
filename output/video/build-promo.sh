#!/usr/bin/env bash
# Renders the promo videos from the three "Addon part" recordings and the
# captions in build/:
#   SMoRGsQoL-promo.mp4        1920x1080, ~12 s, promo banner as end card
#   SMoRGsQoL-promo-short.mp4  1080x1920 (Shorts/TikTok), ~10.5 s, social
#                              image as end card; center crops, no turn-in clip
# Cuts, captions, zoom and highlight boxes are in build/promo.filter and
# build/promo-vertical.filter; audio is normalized to -14 LUFS.
# The raw recordings ("Addon part 1-3.mp4") are not in git; keep them in this
# folder to rebuild. Needs ffmpeg 8+ (the -/filter_complex option).
# Run from anywhere: bash output/video/build-promo.sh
set -euo pipefail
cd "$(dirname "$0")"
FFMPEG="${FFMPEG:-ffmpeg}"
ENCODE=(-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart)

"$FFMPEG" -hide_banner -loglevel error -y \
    -i "Addon part 1.mp4" -i "Addon part 2.mp4" -i "Addon part 3.mp4" \
    -loop 1 -t 2.8 -i ../promo/smorgsqol-banner.png \
    -f lavfi -t 2.8 -i anullsrc=r=48000:cl=stereo \
    -/filter_complex build/promo.filter -map "[v]" -map "[a]" \
    "${ENCODE[@]}" SMoRGsQoL-promo.mp4
echo "wrote $(pwd)/SMoRGsQoL-promo.mp4"

"$FFMPEG" -hide_banner -loglevel error -y \
    -i "Addon part 1.mp4" -i "Addon part 2.mp4" -i "Addon part 3.mp4" \
    -loop 1 -t 2.8 -i ../promo/smorgsqol-social.png \
    -f lavfi -t 2.8 -i anullsrc=r=48000:cl=stereo \
    -/filter_complex build/promo-vertical.filter -map "[v]" -map "[a]" \
    "${ENCODE[@]}" SMoRGsQoL-promo-short.mp4
echo "wrote $(pwd)/SMoRGsQoL-promo-short.mp4"
