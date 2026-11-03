#!/bin/zsh

# Exports docs/images/app-icon.png from Resources/AppIcon.icon with Icon
# Composer's ictool (bundled with Xcode). Pass a rendition such as Dark,
# ClearLight or TintedDark to preview other appearances; the default is Default.

set -euo pipefail

readonly project_dir="${0:A:h:h}"
readonly ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
readonly rendition="${1:-Default}"
readonly output="${2:-${project_dir}/docs/images/app-icon.png}"

"${ictool}" "${project_dir}/Resources/AppIcon.icon" \
  --export-image \
  --output-file "${output}" \
  --platform macOS \
  --rendition "${rendition}" \
  --width 512 --height 512 --scale 1 \
  --design-generation 27 >/dev/null

print -- "Exported ${rendition} icon to ${output}"
