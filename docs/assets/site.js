// The hero demo: choosing a layout in the menu moves the display tiles, as the
// app does. Rects are in canvas units (160 × 100, the canvas's 16:10 aspect).
// On wide screens the menu covers the right of the canvas, so the arrangement
// sits on the left; on phones the menu moves below and the tiles are centred.

(() => {
  const W = 160, H = 100;
  const studio = { w: 46, h: 25.9 }, builtin = { w: 31, h: 20.2 };

  const layouts = {
    above: {
      label: "Studio Display above the Built-in Display",
      rects: { studio: { x: 21, y: 26, ...studio }, builtin: { x: 28.5, y: 53.4, ...builtin } },
    },
    side: {
      label: "Studio Display to the left of the Built-in Display",
      rects: { studio: { x: 1, y: 40, ...studio }, builtin: { x: 48.5, y: 45.7, ...builtin } },
    },
    mirror: {
      label: "Built-in Display mirroring the Studio Display",
      ghost: "builtin",
      rects: { studio: { x: 21, y: 38, ...studio }, builtin: { x: 24.5, y: 34.5, ...studio } },
    },
  };
  const order = Object.keys(layouts);

  const canvas = document.getElementById("canvas");
  if (!canvas) return;
  const tiles = [...canvas.querySelectorAll(".tile")];
  const rows = [...document.querySelectorAll(".menu-row[data-layout]")];
  const narrow = window.matchMedia("(max-width: 620px)");
  const demo = document.getElementById("demo");
  const status = document.getElementById("demo-status");
  let current = "above";

  function show(name, announce = true) {
    const layout = layouts[name];
    const dx = narrow.matches ? 36 : 0;
    for (const tile of tiles) {
      const id = tile.dataset.id;
      const rect = layout.rects[id];
      tile.classList.toggle("is-main", id === "studio");
      tile.classList.toggle("is-ghost", id === layout.ghost);
      tile.style.zIndex = id === layout.ghost ? 0 : 1;
      tile.style.left = ((rect.x + dx) / W) * 100 + "%";
      tile.style.top = (rect.y / H) * 100 + "%";
      tile.style.width = (rect.w / W) * 100 + "%";
      tile.style.height = (rect.h / H) * 100 + "%";
    }
    for (const row of rows) row.setAttribute("aria-pressed", String(row.dataset.layout === name));
    canvas.setAttribute("aria-label", layout.label);
    if (announce && status) status.textContent = `${rows.find((r) => r.dataset.layout === name).firstChild.textContent} applied: ${layout.label}.`;
    current = name;
  }

  rows.forEach((row) => row.addEventListener("click", () => show(row.dataset.layout)));

  // Keys 1–3 pick layouts, like ⌘1–⌘3 in the app's menu, while the demo has focus.
  demo.addEventListener("keydown", (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    const index = Number(event.key) - 1;
    if (index >= 0 && index < order.length) show(order[index]);
  });

  narrow.addEventListener?.("change", () => show(current, false));
  show(current, false);
})();

// Copy buttons for the URL and checksum examples.
document.querySelectorAll(".copy[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.textContent = "Copied";
    } catch {
      button.textContent = "Select and copy";
    }
    setTimeout(() => (button.textContent = "Copy"), 1600);
  });
});
