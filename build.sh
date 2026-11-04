#!/bin/zsh

set -euo pipefail

readonly project_dir="${0:A:h}"
readonly build_dir="${project_dir}/build"
readonly cache_dir="${build_dir}/swift-cache"
readonly staging_dir="$(mktemp -d /private/tmp/screen-setter-build.XXXXXX)"
readonly app_dir="${staging_dir}/Screen Setter.app"
readonly executable="${app_dir}/Contents/MacOS/Screen Setter"
trap 'rm -rf "${staging_dir}"' EXIT

mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources" "${app_dir}/Contents/Frameworks" "${cache_dir}"
cp "${project_dir}/Resources/Info.plist" "${app_dir}/Contents/Info.plist"
cp "${project_dir}/LICENSE" "${app_dir}/Contents/Resources/LICENSE"
# Sparkle handles updates. It is embedded with its own signature intact.
ditto "${project_dir}/Vendor/Sparkle/Sparkle.framework" "${app_dir}/Contents/Frameworks/Sparkle.framework"
cp "${project_dir}/Vendor/Sparkle/LICENSE" "${app_dir}/Contents/Resources/Sparkle-LICENSE"

# The Icon Composer icon compiles to Assets.car (the layered Liquid Glass icon)
# plus AppIcon.icns. Needs Xcode for actool.
if ! xcrun actool "${project_dir}/Resources/AppIcon.icon" \
  --compile "${app_dir}/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "${staging_dir}/icon-info.plist" \
  --errors --warnings --output-format human-readable-text >"${staging_dir}/actool.log"; then
  cat "${staging_dir}/actool.log" >&2
  exit 1
fi
grep -iE "warning|error" "${staging_dir}/actool.log" >&2 || true

# Universal binary: Apple silicon and the Intel Macs that run macOS 26.
for arch in arm64 x86_64; do
  swiftc \
    -parse-as-library \
    -target "${arch}-apple-macosx26.0" \
    -module-cache-path "${cache_dir}" \
    -O \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework ColorSync \
    -framework Carbon \
    -F "${project_dir}/Vendor/Sparkle" \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "${project_dir}"/Sources/ScreenSetter/**/*.swift \
    -o "${staging_dir}/Screen Setter-${arch}"
done
lipo -create "${staging_dir}/Screen Setter-arm64" "${staging_dir}/Screen Setter-x86_64" -output "${executable}"

xattr -cr "${app_dir}"
codesign --force --sign - "${app_dir}"
codesign --verify --deep --strict "${app_dir}"
plutil -lint "${app_dir}/Contents/Info.plist"

rm -rf "${build_dir}/Screen Setter.app" "${build_dir}"/Screen-Setter.{zip,dmg}{,.sha256}
ditto "${app_dir}" "${build_dir}/Screen Setter.app"
codesign --verify --deep --strict "${build_dir}/Screen Setter.app"
# The zip is what Sparkle updates from; the disk image is what people download first.
ditto -c -k --sequesterRsrc --keepParent "${app_dir}" "${build_dir}/Screen-Setter.zip"

# The disk image opens a window with the app beside an Applications shortcut, to drag across.
# dmgbuild writes that window's layout itself, without scripting Finder.
readonly dmg_venv="${build_dir}/dmg-venv"
if [[ ! -x "${dmg_venv}/bin/dmgbuild" ]]; then
  python3 -m venv "${dmg_venv}"
  "${dmg_venv}/bin/pip" install --quiet "dmgbuild==1.6.5"
fi
"${dmg_venv}/bin/dmgbuild" -s "${project_dir}/Tools/dmg/settings.py" \
  -D app="${build_dir}/Screen Setter.app" \
  -D background="${project_dir}/Resources/dmg-background.tiff" \
  "Screen Setter" "${build_dir}/Screen-Setter.dmg" >/dev/null
codesign --force --sign - "${build_dir}/Screen-Setter.dmg"

(
  cd "${build_dir}"
  shasum -a 256 "Screen-Setter.zip" > "Screen-Setter.zip.sha256"
  shasum -a 256 "Screen-Setter.dmg" > "Screen-Setter.dmg.sha256"
)

print -- "Built: ${build_dir}/Screen Setter.app ($(lipo -archs "${build_dir}/Screen Setter.app/Contents/MacOS/Screen Setter"))"
print -- "Disk image: ${build_dir}/Screen-Setter.dmg"
print -- "  SHA-256: $(cut -d ' ' -f 1 "${build_dir}/Screen-Setter.dmg.sha256")"
print -- "Update archive: ${build_dir}/Screen-Setter.zip"
print -- "  SHA-256: $(cut -d ' ' -f 1 "${build_dir}/Screen-Setter.zip.sha256")"
