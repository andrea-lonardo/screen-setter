#!/bin/zsh
# Renders Tools/dmg/background.html into Resources/dmg-background.tiff (1x + 2x) with headless Chrome.
# Run only when the background design changes; the TIFF is committed.

set -euo pipefail

readonly here="${0:A:h}"
readonly project_dir="${here:h:h}"
readonly chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
readonly work="$(mktemp -d /private/tmp/screen-setter-dmg-bg.XXXXXX)"
trap 'rm -rf "${work}"' EXIT

for scale in 1 2; do
  "${chrome}" --headless=new --disable-gpu --hide-scrollbars \
    --user-data-dir="${work}/profile-${scale}" \
    --force-device-scale-factor="${scale}" --window-size=600,380 \
    --screenshot="${work}/bg-${scale}x.png" "file://${here}/background.html" 2>/dev/null
done

sips -s dpiWidth 144 -s dpiHeight 144 "${work}/bg-2x.png" >/dev/null
tiffutil -cathidpicheck "${work}/bg-1x.png" "${work}/bg-2x.png" -out "${project_dir}/Resources/dmg-background.tiff"
print -- "Wrote ${project_dir}/Resources/dmg-background.tiff"
