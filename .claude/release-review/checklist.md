# Release review checklist

The checklist the `release-reviewer` agent works from. It targets a free,
MIT-licensed macOS menu-bar app distributed outside the Mac App Store:

- ad-hoc signed and not notarized (no paid Apple Developer Program),
- downloaded as a zip from GitHub Releases,
- updated with Sparkle (planned),
- with a website on GitHub Pages (planned).

Each item has an ID, the requirement, and the source it comes from (see
[Sources](#sources)). Items marked *(judgement)* are good practice rather than
a published rule. Research date: 2026-11-03. Re-check sources that may have
changed before relying on them.

Severity when reporting:

- **Must fix**: blocks a public release. Covers legal or IP exposure,
  security holes, data loss, a broken install or update path, and claims that
  are untrue.
- **Should fix**: a real quality, trust or accessibility problem that users
  will hit.
- **Could fix**: polish.

## A. Distribution and first launch

- **A1** The README and website explain the Gatekeeper flow on current macOS:
  try to open the app, then go to System Settings › Privacy & Security, click
  **Open Anyway**, and confirm. Control-click › Open no longer bypasses
  Gatekeeper on macOS 15 and later. Instructions must not tell users to
  disable Gatekeeper or SIP, or to use `spctl --master-disable`. [S1, S2]
- **A2** The instructions say plainly *why* the warning appears (no paid
  Apple Developer ID, no notarization) and how to verify the download, for
  example with a SHA-256 checksum. [S1, S12 *(judgement)*]
- **A3** The release archive is built with `ditto -c -k --sequesterRsrc
  --keepParent` or an equivalent, keeps symlinks, and contains only the app.
  [S6]
- **A4** `codesign --verify --deep --strict` passes on the shipped bundle. The
  ad-hoc signature covers the whole bundle, including any embedded
  frameworks such as Sparkle, signed inside out. [S5, S7]
- **A5** Each release publishes a SHA-256 checksum next to the archive.
  [S12 *(judgement)*]
- **A6** Do not plan an official `homebrew/cask` submission. Official casks
  must pass Gatekeeper checks, and failing casks are deprecated, then
  disabled and removed. A personal tap is "unsupported" but not forbidden.
  [S8]
- **A7** The app behaves sensibly when run from outside /Applications, such
  as Downloads or a translocated path. Open at Login (SMAppService) should
  either work there or tell the user to move the app first. *(judgement)*

## B. Updates (Sparkle, planned)

- **B1** If Sparkle is not integrated yet, report that the app has no update
  mechanism, and list what integration needs: `SUFeedURL` over HTTPS,
  `SUPublicEDKey`, an incrementing `CFBundleVersion`, and EdDSA-signed
  archives made with `generate_appcast` or `sign_update`. [S5, S6]
- **B2** The EdDSA private key must never be committed, and must be backed
  up (`generate_keys -x`). For non-Developer-ID apps there is no documented
  key rotation, so losing the key strands every installed copy. [S5]
- **B3** Sparkle system profiling (`SUEnableSystemProfiling`) stays off, or
  the privacy policy discloses it. [S7]
- **B4** Users can turn automatic update checks off, and the privacy policy
  mentions the periodic check (default every 24 hours) and what it sends.
  [S5, S7]
- **B5** Ad-hoc signing can interfere with loading Sparkle under Library
  Validation. Check entitlements and signing order. [S5]

## C. Build, packaging and metadata

- **C1** The repo builds from a clean clone with documented prerequisites:
  the macOS SDK version, and Xcode for `actool` and `ictool`. [*(judgement)*]
- **C2** Info.plist is complete and consistent:
  - `CFBundleIdentifier`, `CFBundleShortVersionString` and an incrementing
    `CFBundleVersion`,
  - `LSMinimumSystemVersion` matches the build target,
  - `NSHumanReadableCopyright` is set,
  - `LSUIElement` is set for an agent app,
  - the icon keys are set,
  - the URL types are declared.
  [S5]
- **C3** Version numbers agree across Info.plist, README, CHANGELOG and
  release tags. *(judgement)*
- **C4** The tests pass and cover migration and corrupt-data handling.
  *(judgement)*
- **C5** There are no compiler warnings, and no deprecated or private APIs.
  *(judgement)*

## D. Licensing and intellectual property

- **D1** A `LICENSE` file with the full MIT text sits at the repo root, with
  the year and copyright holder filled in. GitHub can't supply a default
  license file. [S10, S11]
- **D2** MIT requires the copyright and permission notice "in all copies or
  substantial portions". The binary distribution should carry it too, for
  example in the About panel or credits, or a file in the zip. [S11]
- **D3** No SF Symbols, and no glyphs "confusingly similar" to them, in the
  **app icon, logo or any trademark-like use**. Symbols inside the app UI are
  fine. Compare the app icon artwork (Resources/AppIcon.icon/Assets/*.svg)
  with SF Symbols such as `rectangle.2.swap`, and check git history for icons
  that embedded a symbol. [S3]
- **D4** The icon contains no replicas of Apple hardware, standard UI
  components or screenshots. [S4]
- **D5** "Mac" and "macOS" appear only in referential phrases ("for",
  "runs on", "compatible with"), never in the product name, and never more
  prominently than the product name. [S9]
- **D6** The documentation or site includes Apple's trademark attribution
  line, for example "Mac and macOS are trademarks of Apple Inc., registered
  in the U.S. and other countries and regions." Trademark symbols are not
  needed outside the US. [S9]
- **D7** The README and site use no Apple logos and no Apple-owned
  photography. A developer may show only actual photographs of genuine
  Apple products, never renders, and nothing implies Apple endorsement. [S9]
- **D8** The app name does not collide with an existing Mac app or a
  trademark in the same category. Do a quick web and GitHub search and
  report what you find. *(judgement)*
- **D9** Third-party code, assets and fonts are attributed according to
  their licenses. *(judgement)*

## E. Privacy and security

- **E1** List every network request the app makes, which should be none
  today, and every place it stores data (paths, UserDefaults keys, login
  items). These facts feed the privacy policy. *(judgement)*
- **E2** URL scheme (`displaylayouts://`): any website or app can open it.
  Check whether a crafted link can change the display setup without the
  user's intent, whether input is validated, and whether there are limits or
  confirmation. [*(judgement)*, OWASP-style input handling]
- **E3** Global hotkeys and event monitors capture only what they need, and
  no permission is requested beyond what the app uses. *(judgement)*
- **E4** No secrets, personal paths or personal data in the repo or its
  history: keys, tokens, real display serials or email addresses beyond what
  the author chose to publish. *(judgement)*
- **E5** A `SECURITY.md` explains how to report vulnerabilities privately.
  [S10]
- **E6** Applying a layout can't leave the user without a usable display
  (black screen, everything mirrored to a disconnected display). Undo or
  revert exists and is easy to find. *(judgement)*
- **E7** Data files are written atomically. Corrupt, newer-schema and
  migrated data are kept, not destroyed. *(judgement)*

## F. Human Interface Guidelines and UX

- **F1** Menu bar extra: clicking shows a **menu**, not a popover, and the
  icon is a template image or symbol that adapts to the menu bar. [S4b]
- **F2** Don't rely on the menu bar extra always being visible, because the
  system hides extras when space is short. Offer another way to reach the
  app (for example, opening it again shows Settings, the URL scheme, or
  hotkeys). [S4b]
- **F3** Users can quit from the menu, and Open at Login is opt-in.
  *(judgement)*
- **F4** Onboarding tells people where the app lives (the menu bar), because
  agent apps have no Dock icon. [S4b *(judgement)*]
- **F5** Liquid Glass: standard controls, no custom glass in the content
  layer, no hard-coded backgrounds fighting system materials, and correct
  appearance in light, dark and tinted modes. [S13]
- **F6** Accessibility: VoiceOver labels on custom controls (canvas, hotkey
  recorder, thumbnails), full keyboard operation, Increase Contrast, Reduce
  Transparency, Reduce Motion, and Dynamic Type where applicable. [S4, S13
  *(judgement)*]
- **F7** Error messages are specific and actionable, and destructive actions
  ask for confirmation. *(judgement)*
- **F8** Localization readiness: user-facing strings are localizable (String
  Catalog or `LocalizedStringKey`), and numbers and lists use formatters. An
  English-only first release is fine, but report hard-coded strings as
  could-fix. *(judgement)*

## G. Documentation and community

- **G1** The README is accurate for the current version: features,
  requirements, install (A1), uninstall (app plus data locations), URL
  scheme, and current screenshots, not 1.x ones. *(judgement)*
- **G2** `CHANGELOG.md` is current. *(judgement)*
- **G3** The community health files exist or are deliberately skipped:
  `CONTRIBUTING.md`, `SUPPORT.md`, `SECURITY.md`, issue templates, and
  optionally `CODE_OF_CONDUCT.md`. [S10]
- **G4** There is a support and contact route: GitHub Issues, or an email
  the author is willing to publish. *(judgement)*

## H. Legal documents (for Phase 4)

- **H1** The privacy policy is accurate to E1, B3 and B4. It discloses that
  GitHub Pages logs visitor IP addresses, and that GitHub Releases downloads
  and appcast requests reach GitHub. [S7, S14]
- **H2** Terms of use, or a EULA: MIT's "AS IS" warranty disclaimer and
  limitation of liability already cover the software. A separate short
  terms page for the website is optional. Report whether the docs say so.
  [S11]
- **H3** Neither the app nor the website claims anything untrue: "no data
  collected" must hold after Sparkle is added, and nothing implies Apple
  affiliation. [S9 *(judgement)*]

## Sources

- **S1** Apple Support, "Safely open apps on your Mac" (Open Anyway steps):
  https://support.apple.com/en-us/102445
- **S2** Michael Tsai, "Sequoia Removes Gatekeeper Contextual Menu Override":
  https://mjtsai.com/blog/2024/07/05/sequoia-removes-gatekeeper-contextual-menu-override/
- **S3** Apple HIG, SF Symbols, on the prohibition against symbols "or images
  that are confusingly similar" in app icons, logos or trademarked use:
  https://developer.apple.com/design/human-interface-guidelines/sf-symbols
- **S4** Apple HIG, App icons (Icon Composer layers, appearances, no Apple
  hardware replicas, no UI replicas):
  https://developer.apple.com/design/human-interface-guidelines/app-icons
- **S4b** Apple HIG, The menu bar, section "Menu bar extras":
  https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
- **S5** Sparkle, Basic Setup (EdDSA, SUFeedURL, SUPublicEDKey, HTTPS, key
  rotation only for Developer ID, ad-hoc and Library Validation note):
  https://sparkle-project.org/documentation/
- **S6** Sparkle, Publishing an update (ditto zip, generate_appcast,
  signatures): https://sparkle-project.org/documentation/publishing/
- **S7** Sparkle, System Profiling (opt-in, fields sent):
  https://sparkle-project.org/documentation/system-profiling/
- **S8** Homebrew, Acceptable Casks and the Security and Supply Chain docs
  (Gatekeeper requirement; third-party taps unsupported):
  https://docs.brew.sh/Acceptable-Casks
- **S9** Apple, Guidelines for Using Apple Trademarks and Copyrights:
  https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html
- **S10** GitHub Docs, community health files:
  https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file
- **S11** choosealicense.com, MIT License:
  https://choosealicense.com/licenses/mit/
- **S12** Example practice: open-source Mac releases that publish SHA-256
  checksums for ad-hoc builds (for instance
  https://github.com/openobserve/kide/releases).
- **S13** WWDC26 "Modernize your AppKit app" and "What's new in SwiftUI":
  https://developer.apple.com/videos/play/wwdc2026/289/ and
  https://developer.apple.com/videos/play/wwdc2026/269/
- **S14** GitHub Pages, on logging visitor IP addresses:
  https://docs.github.com/en/pages/getting-started-with-github-pages/about-github-pages
