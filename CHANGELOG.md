# Changelog

Release tags combine the marketing version and build number: `v<version>.<build>`.

## 2.0 (21) — Unreleased

- Rename the app to Screen Setter, since another Mac app is already called
  DisplayLayouts. Layouts saved under the old name are copied to
  `~/Library/Application Support/Screen Setter/` on first launch, the old folder
  is left untouched, and `displaylayouts://` links keep working alongside the new
  `screensetter://` scheme.
- Turn Display Layouts into a free public app: save unlimited named layouts of the
  current arrangement instead of five fixed presets, then rename, reorder,
  duplicate, replace, or delete them.
- Group layouts automatically by the exact set of displays they use. Display sets
  can be renamed and reordered, and the menu shows only the connected set, with
  Command-1–9 for its first nine layouts.
- Add a layout editor for positions, Extend or Mirror, the main display, and each
  display's resolution, with validation before saving. Editing works while the
  displays are disconnected.
- Add global keyboard shortcuts for layouts, without Accessibility permission.
  Conflicting shortcuts are reported instead of failing silently.
- Choose one automatic layout per display set, replacing the fixed iPad, Monitor,
  and Projector groups.
- Add **Save Current Arrangement…** to the menu, with a descriptive suggested name.
- Accept layout names and identifiers in `displaylayouts://apply/<name-or-id>`,
  keep 1.x preset IDs working, and add `displaylayouts://settings`.
- Store everything in one versioned `library.json` and migrate 1.x presets on
  first launch. Unreadable or newer-version libraries are kept and reported, never
  overwritten.
- Rebuild Settings and a first-run welcome in SwiftUI with the macOS 26 design.
- Replace the flat app icon with a layered Icon Composer icon, so it supports
  the Liquid Glass light, dark, clear, and tinted icon styles on macOS 26 and 27.
- Draw display tiles in the layout editor with stronger edges and badges when
  Increase Contrast or Reduce Transparency is on.
- Release under the MIT License, shown in Settings › General › About and bundled
  in the app.
- Build a universal app that also runs on Intel Macs with macOS 26, and publish
  a SHA-256 checksum next to the zip.
- Opening the app again shows Settings, so it stays reachable when macOS hides
  the menu bar item. The welcome window says where the app lives.
- Shortcuts and URLs check the connected displays when they run, so a link that
  launches the app no longer reports the displays as disconnected.
- Explain the current Open Anyway steps for first launch, and add uninstall,
  support, and security reporting instructions.
- Add a privacy policy (the app collects no data) and terms of use, linked from
  Settings › General › About.
- Check for updates with Sparkle: the app asks on its second launch whether to
  check automatically, and offers **Check for Updates…** in the menu and a
  setting in Settings › General. Updates are EdDSA-signed.
- Add a website with a live demo, download steps, privacy, terms and support
  pages, published from `docs/` with GitHub Pages.
- Require macOS 26. Change the bundle identifier to
  `io.github.andrea-lonardo.screen-setter`, so Open at Login must be turned on
  again.

## Earlier versions

Versions before 2.0 were private builds, released as Display Layouts.
