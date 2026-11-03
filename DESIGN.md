# Screen Setter website design

The design system for the website in `docs/`. It's dark and cinematic, in the
spirit of bold product sites, with its own identity:

- **Big condensed headlines.**
- **One electric-blue accent.**
- **The live demo is the hero.** It shows a small desktop with Screen Setter's
  real menu open, and choosing a layout moves the display tiles. Spend the
  boldness there and keep everything else quiet.

Tokens are CSS variables in `docs/assets/site.css`. Pages use the names, never
raw values.

## Color (dark only)

| Token | Value | Role |
|---|---|---|
| `--bg` | #07080B | Page background |
| `--surface` | #101218 | Demo window, code blocks, settings mock |
| `--surface-2` | #171A22 | Canvas floor, hover fills, keycaps |
| `--border` | #262A35 | Dividers and outlines |
| `--text` | #F3F4F7 | Headings and body |
| `--text-2` | #A7ADBA | Secondary text (8.9:1) |
| `--text-3` | #7E8596 | Captions and fine print (5.4:1) |
| `--accent` | #3D9BFF | Buttons, links, display tiles, step numbers, focus ring (7:1) |
| `--on-accent` | #04060A | Text on the accent (7.1:1) |
| `--success` | #3DD68C | Reserved for verified states |

The icon's blue-to-indigo gradient stays in the icon. No gradient washes or
glows behind sections.

## Typography

- **Anton**, self-hosted in `docs/fonts` under the OFL. Used for `h1` and `h2`
  only, in uppercase, set tight.
- **System UI stack** for everything else.
- **System monospace** only for code, paths and the checksum command. Never for
  labels.
- **Scale:**
  - display: clamp(56px, 8.4vw, 112px) at 0.9
  - h2: clamp(40px, 6vw, 84px) at 0.95
  - feature h3: 22–28px, weight 650
  - lead: 18–21px
  - body: 17px at 1.6
  - fine print: 14px
- **Line length:** text blocks stay under about 60 characters.

## Avoided on purpose

These read as generated pages:

- small uppercase labels above headings
- facts joined with dots
- one highlighted word in a headline
- numbered pills
- grids of identical boxed cards
- the "big number, small label" stat
- arrows appended to buttons

Numbers appear only where the content is a real sequence: How it works and
the install steps.

## Spacing, shape, depth

- **Spacing:** a 4px-based scale (`--s-1` 4px … `--s-10` 128px).
- **Sections:** 128px of vertical padding on desktop, 80px on phones.
- **Content width:** 1200px with 24px gutters.
- **Radius:** 6px keys, 12px tiles and code, 20px cards, 28px for the demo
  window, pill buttons.
- **Shadows:** `--shadow-window` for the demo and the screenshot, and
  `--shadow-tile` for tiles and the menu.
- **Glass:** only on the demo's menu, as in the app.

## Components

- **Buttons:**
  - Primary: an accent pill.
  - Secondary: an outlined pill.
  - Both are 48px tall, with a 2px accent focus ring offset by 3px.
- **Demo:**
  - A menu bar strip with the status icon.
  - A canvas of tiles; the main display shows a white menu-bar strip.
  - Screen Setter's menu, with checkmark rows and ⌘1–⌘3.
  - Keys 1–3 also switch layouts, and changes animate only in response to the
    visitor.
- **Feature rows:** text beside the thing it describes (keycaps, the
  automatic-layout setting, the Settings screenshot, the URL, the data path),
  separated by hairlines rather than boxed.
- **Footer:** Privacy, Terms, Support, Security, Source and License links, plus
  the Apple trademark line.

## Imagery

- **App icon:** `images/app-icon.png`.
- **Screenshots:** offscreen renders of the app's own windows, made with
  `--render-settings --dark` from sample data.
- **Icons:** drawn for this site. No SF Symbols, Apple logos, Apple hardware
  or emoji.

## Motion

- Tiles glide in 520ms on `cubic-bezier(.2, .8, .2, 1)`, only when the visitor
  picks a layout.
- With `prefers-reduced-motion`, changes are instant.
