#!/usr/bin/env python3
"""Builds the website's Privacy, Terms and Support pages from the Markdown files
at the repo root, so each text lives in one place.

    python3 Tools/build_site_pages.py

Handles the small subset of Markdown those files use: headings, paragraphs,
bulleted lists, links, bold and inline code.
"""

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "https://github.com/andrea-lonardo/screen-setter/blob/main/"
PAGES = {"PRIVACY.md": "privacy", "TERMS.md": "terms", "SUPPORT.md": "support"}


def link_target(target: str) -> str:
    name, _, anchor = target.partition("#")
    if name in PAGES:
        return f"../{PAGES[name]}/" + (f"#{anchor}" if anchor else "")
    if re.match(r"^[A-Za-z]+://", target):
        return target
    return REPO + target


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda m: f'<a href="{html.escape(link_target(m.group(2)))}">{m.group(1)}</a>',
        text,
    )


def convert(markdown: str) -> tuple[str, str]:
    title, out, paragraph, items = "", [], [], []

    def flush():
        if paragraph:
            out.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items.clear()

    for line in markdown.splitlines():
        stripped = line.strip()
        if not stripped:
            flush()
        elif stripped.startswith("# "):
            flush()
            title = stripped[2:]
        elif stripped.startswith("## "):
            flush()
            out.append(f"<h2>{inline(stripped[3:])}</h2>")
        elif stripped.startswith("- "):
            if paragraph:
                flush()
            items.append(stripped[2:])
        elif items and line.startswith("  "):
            items[-1] += " " + stripped
        else:
            paragraph.append(stripped)
    flush()
    return title, "\n      ".join(out)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title} — Screen Setter</title>
  <meta name="theme-color" content="#07080b">
  <link rel="icon" href="../images/app-icon.png">
  <link rel="stylesheet" href="../assets/site.css">
</head>
<body>
  <a class="skip-link" href="#main">Skip to content</a>
  <header class="nav">
    <div class="wrap">
      <a class="brand" href="../"><img src="../images/app-icon.png" alt="" width="30" height="30">Screen Setter</a>
      <nav class="nav-links" aria-label="Main">
        <a href="../#how">How it works</a>
        <a href="../#features">Features</a>
        <a href="../#faq">Questions</a>
        <a href="https://github.com/andrea-lonardo/screen-setter">GitHub</a>
      </nav>
      <a class="btn btn-primary" href="../#download">Download</a>
    </div>
  </header>
  <main id="main" class="page">
    <div class="wrap">
      <h1>{title}</h1>
      {body}
    </div>
  </main>
  <footer class="footer">
    <div class="wrap">
      <nav class="footer-links" aria-label="Footer">
        <a href="../privacy/">Privacy</a>
        <a href="../terms/">Terms</a>
        <a href="../support/">Support</a>
        <a href="https://github.com/andrea-lonardo/screen-setter/blob/main/SECURITY.md">Security</a>
        <a href="https://github.com/andrea-lonardo/screen-setter">Source</a>
        <a href="https://github.com/andrea-lonardo/screen-setter/blob/main/LICENSE">MIT License</a>
      </nav>
      <p>© 2026 Andrea Lonardo. Screen Setter is free software, provided as is.</p>
      <p>Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions. Screen Setter is not affiliated with or endorsed by Apple.</p>
      <p>Generated from <a href="{source}">{name}</a>.</p>
    </div>
  </footer>
</body>
</html>
"""

for name, slug in PAGES.items():
    title, body = convert((ROOT / name).read_text(encoding="utf-8"))
    target = ROOT / "docs" / slug / "index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        TEMPLATE.format(title=html.escape(title), body=body, name=name, source=REPO + name),
        encoding="utf-8",
    )
    print(f"Wrote {target.relative_to(ROOT)}")
