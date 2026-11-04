# Privacy Policy

Effective November 3, 2026. Applies to Screen Setter 2.0 and later, and to its
GitHub repository and website.

## Summary

Screen Setter doesn't collect, send, or sell any personal data. It has no
accounts, analytics, advertising, crash reporting, or tracking. Its only network
request is an optional check for updates, described below. Everything it stores
stays on your Mac.

## What the app stores on your Mac

Screen Setter saves what it needs to remember your layouts, only on your Mac:

- `~/Library/Application Support/Screen Setter/library.json`, readable only by
  your user account. It contains your layout names, keyboard shortcuts, and for
  each display the arrangement, resolution, and the identifiers macOS reports
  (name, vendor, model, and serial number) so a layout can find the same
  displays again. A copy of the previous version is kept beside it, and a file
  that couldn't be read is set aside as a backup.
- The Settings window's size and position, and whether and when it last
  checked for updates, in
  `~/Library/Preferences/io.github.andrea-lonardo.screen-setter.plist`.
- A login item, only if you turn on **Open at Login**.

If you used the app when it was called Display Layouts, it reads your old
layouts from `~/Library/Application Support/Display Layouts/` and never changes
that folder.

None of this leaves your Mac unless you copy it yourself, for example in a Time
Machine or iCloud backup, which Apple's own terms cover. The app writes to the
clipboard only when you click **Copy**, and never reads it.

## Permissions

Screen Setter asks for no special permissions. Keyboard shortcuts use a macOS
mechanism that doesn't need Accessibility access, and the app can't see your
screen contents, files, or other apps.

## Links and URLs

Links such as `screensetter://apply/…` are handled on your Mac and only switch
between your saved layouts. The links in Settings, such as the source code link,
open in your web browser, where that website's own privacy policy applies.

## Downloads, issues, and the website (GitHub)

Screen Setter is downloaded from, discussed on, and documented on GitHub,
operated by GitHub, Inc. When you visit the repository, download a release,
open an issue, or view the website on GitHub Pages, GitHub processes data such
as your IP address under the
[GitHub General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
GitHub logs the IP address of every visitor to a GitHub Pages site for security
purposes. The developer doesn't receive these logs and doesn't add analytics,
cookies, or tracking scripts to the website.

Anything you post in a public issue is visible to everyone. Report security
problems privately as described in [SECURITY.md](SECURITY.md).

## Checking for updates

Screen Setter uses [Sparkle](https://sparkle-project.org), an open-source
updater, to find new versions. The second time you open the app, it asks
whether to check automatically. You can change your answer anytime in Settings
› About, or check by hand with **Check for Updates…** in the menu.

A check downloads a small file (`appcast.xml`) from this project's website on
GitHub Pages, at most once a day when automatic checks are on. The request
includes your IP address, as every web request does, and the app's name and
version. Sparkle's optional system profile, which would add details such as your
Mac model and macOS version, is turned off. If you install an update, it is
downloaded from GitHub Releases. GitHub handles these requests as described
below. Updates are verified with a signature before they are installed.

If a future version connects to the internet in any other way, this policy will
be updated before that version is released, saying what is sent, where, and how
to turn it off.

## Your choices

You can delete your data at any time. Quit the app, then delete the files
listed above, or follow the uninstall steps on the
[website](https://andrea-lonardo.github.io/screen-setter/#faq).
Because the developer holds no data about you, there is nothing to request,
correct, or delete on the developer's side.

## Children

Screen Setter collects no data from anyone, including children.

## Changes and contact

Screen Setter is made by Andrea Lonardo, an individual developer, who is
responsible for this policy. Changes to this policy are published in this file,
with the history visible in the repository. Questions are welcome in
[GitHub Issues](https://github.com/andrea-lonardo/screen-setter/issues).
