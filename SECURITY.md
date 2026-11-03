# Security

## Reporting a vulnerability

Please report security problems privately through GitHub's
[private vulnerability reporting](https://github.com/andrea-lonardo/screen-setter/security/advisories/new)
rather than in a public issue. Include the Screen Setter version (Settings ›
General › About), your macOS version, and steps to reproduce.

You can expect an acknowledgement within a week. Fixes ship in a new release,
and the report is credited unless you prefer otherwise.

## Scope

Screen Setter runs locally and needs no special permissions. Its only network
request is the optional update check through Sparkle, which verifies each
update's EdDSA signature before installing it. Areas of interest include the `screensetter://` and
`displaylayouts://` URL handlers, the global keyboard shortcuts, and how saved
layouts are read from disk.

Releases are ad-hoc signed and not notarized. Download them only from this
repository's Releases page and check the SHA-256 checksum published with each
release.
