# Screen Setter website design

The design system for the website in `docs/`. The direction comes from the
product itself, not from reference sites (UXKIN was not connected): a precise,
calm Mac utility, where **the arrangement canvas is the hero**. Displays are
drawn as tiles that move between layouts, just as they do in the app.

Tokens live as CSS variables in `docs/assets/site.css`. Pages use the variable
names, never raw values.

## Color

There is one primary, a neutral scale, and a status green. The icon's
blue-to-indigo gradient appears **only in the icon**. Text, buttons and
backgrounds never use it.

| Token | Light | Dark | Role |
|---|---|---|---|
| `--bg` | #FAFAFB | #0B0C10 | Page background |
| `--surface` | #FFFFFF | #14161C | Cards, window frames, code blocks |
| `--surface-2` | #F1F2F5 | #1C1F27 | Canvas floor, quiet fills, hover |
| `--border` | #E1E3E8 | #2A2E38 | Dividers, card and input borders |
| `--text` | #15171C | #F2F3F6 | Headings and body (17:1) |
| `--text-2` | #545A66 | #A9AFBC | Secondary text (6.6:1 / 8.9:1) |
| `--text-3` | #6B7180 | #8B92A0 | Captions, meta (4.7:1 / 6.3:1) |
| `--primary` | #2563EB | #6EA8FF | Buttons, links, display tiles, focus ring |
| `--on-primary` | #FFFFFF | #0B0C10 | Text on primary (5.2:1 / 8.1:1) |
| `--success` | #1A7F4B | #3DD68C | "Connected" and verified states |

Dark mode follows `prefers-color-scheme`.

## Typography

- **Family:** the system UI stack (`ui-sans-serif, system-ui, …`) and the
  system monospace stack (`ui-monospace, …`) for URLs, shortcuts and
  checksums. No web fonts, so there are no third-party font requests, which
  keeps the privacy policy true.
- **Weights:** 400, 500, 600 and 700.
- **Scale:**

| Name | Size | Line height | Weight | Use |
|---|---|---|---|---|
| display | clamp(44px, 7vw, 84px) | 1.02 | 700, tracking −0.035em | Hero headline |
| h2 | clamp(30px, 4vw, 44px) | 1.1 | 700, tracking −0.02em | Section titles |
| h3 | 20px | 1.3 | 600 | Feature titles |
| lead | 20px | 1.5 | 400 | Hero and section intro |
| body | 17px | 1.6 | 400 | Paragraphs |
| small | 14px | 1.5 | 500 | Meta, captions, nav |
| mono | 14px | 1.5 | 500 | Code and shortcuts |

- **Line length:** 68 characters at most (`--measure: 68ch`).

## Spacing

The scale is 4px-based: 4, 8, 12, 16, 24, 32, 48, 64, 96 and 128
(`--s-1` … `--s-10`).

- **Sections:** 128px of vertical padding on desktop, 80px on phones.
- **Content width:** 1120px, with 24px gutters (16px on phones).

## Shape and depth

- **Radius:** `--r-sm` 6px (badges, keys), `--r-md` 10px (buttons, inputs,
  tiles), `--r-lg` 16px (cards), `--r-xl` 22px (window frames).
- **Shadows:** `--shadow-window` for screenshots and the canvas window, and
  `--shadow-tile` for display tiles. No other shadows.
- **Glass:** glass only where the app uses it, in the canvas window's toolbar.
  No blurred cards anywhere else.

## Components

- **Buttons:**
  - Primary: filled `--primary`, 44px tall.
  - Secondary: `--surface` with a `--border` outline.
  - Quiet: a text link with an arrow.
  - Hover darkens or lightens by 8%. Focus shows a 2px `--primary` ring with
    a 3px offset. Disabled is 45% opacity.
- **Links:** `--primary`, underlined on hover and focus.
- **Keycaps:** `kbd` in mono, `--surface` with `--border` and a 1px bottom
  border, `--r-sm`.
- **Code and checksum blocks:** `--surface`, `--border`, mono, and a Copy
  button.
- **Cards:** used only for the step-by-step install. Features are a split
  layout with text beside a live demo, not a grid of identical cards.
- **Navigation:**
  - A slim sticky bar: icon and name on the left, links on the right, and a
    Download button.
  - On phones the links collapse to a single Download button.
- **Footer:** links to Privacy, Terms, Security, Source and License, plus the
  Apple trademark line.

## Imagery and icons

- **App icon:** `images/app-icon.png`, exported from `Resources/AppIcon.icon`.
- **Screenshots:** offscreen renders of the app's own windows, made with
  `--render-settings` and `--render-onboarding` from sample data, in both
  light and dark.
- **Display tiles:** drawn in HTML/CSS. Never Apple hardware, photos or
  renders.
- **Icons:** small inline SVGs drawn for this site, 1.75px stroke, in
  `currentColor`. No SF Symbols (Apple licenses them for apps on its
  platforms only), no emoji, and no Apple logos.

## Motion

- Tiles glide between layouts in 450ms on `cubic-bezier(.2, .8, .2, 1)`.
- With `prefers-reduced-motion`, the tiles change instantly and nothing loops.
