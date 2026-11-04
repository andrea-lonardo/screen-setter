// The install steps: a player that shows one scene at a time (or, with reduced
// motion or no script, all three stacked), and the Download button's hand-off to it.
(() => {
  const player = document.getElementById("player");
  const section = document.getElementById("install");
  const status = document.getElementById("get-status");
  if (!player || !section) return;

  const frame = player.querySelector(".player-frame");
  const steps = [...player.querySelectorAll(".get-step")];
  const scenes = steps.map((step) => step.querySelector(".scene"));
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  const STEP = 8000, PAUSE = 24000;

  let on = false, visible = !("IntersectionObserver" in window), userPaused = false;
  let active = 0, timer = 0, resume = 0;

  function applyLive() {
    scenes.forEach((scene, i) => scene.classList.toggle("is-live", on ? visible && i === active : scene.dataset.seen === "1"));
  }

  // Outside the player, each scene plays while it is on screen.
  const sceneObserver = "IntersectionObserver" in window
    ? new IntersectionObserver((entries) => {
        for (const entry of entries) {
          entry.target.dataset.seen = entry.isIntersecting ? "1" : "0";
          if (!on) entry.target.classList.toggle("is-live", entry.isIntersecting);
        }
      }, { threshold: 0.3 })
    : null;
  function watchScenes() {
    if (!sceneObserver) { scenes.forEach((s) => { s.dataset.seen = "1"; s.classList.add("is-live"); }); return; }
    sceneObserver.disconnect();
    scenes.forEach((s) => sceneObserver.observe(s));
  }

  function schedule() {
    clearTimeout(timer);
    if (!on || userPaused || !visible || document.hidden) return;
    timer = setTimeout(() => select((active + 1) % steps.length), STEP);
  }

  function select(index, byUser = false) {
    active = index;
    steps.forEach((step) => step.classList.remove("is-active"));
    scenes.forEach((scene) => scene.classList.remove("is-active"));
    void player.offsetWidth; // restart the scene's animations and the progress bar
    steps[index].classList.add("is-active");
    scenes[index].classList.add("is-active");
    steps.forEach((step, i) => step.querySelector(".step-btn")?.setAttribute("aria-pressed", String(i === index)));
    clearTimeout(resume);
    if (byUser) {
      userPaused = true;
      player.classList.add("is-paused");
      resume = setTimeout(() => { userPaused = false; player.classList.remove("is-paused"); select(active); }, PAUSE);
    } else {
      userPaused = false;
      player.classList.remove("is-paused");
    }
    applyLive();
    schedule();
  }

  function enable() {
    if (on) return;
    on = true;
    player.classList.add("is-player");
    scenes.forEach((scene) => frame.appendChild(scene));
    steps.forEach((step, i) => {
      const h3 = step.querySelector("h3");
      const button = document.createElement("button");
      button.type = "button";
      button.className = "step-btn";
      button.textContent = h3.textContent;
      button.addEventListener("click", () => select(i, true));
      h3.textContent = "";
      h3.appendChild(button);
    });
    select(0);
  }

  function disable() {
    if (!on) return;
    on = false;
    clearTimeout(timer);
    clearTimeout(resume);
    player.classList.remove("is-player", "is-paused");
    steps.forEach((step, i) => {
      const h3 = step.querySelector("h3");
      h3.textContent = h3.textContent;
      step.classList.remove("is-active");
      scenes[i].classList.remove("is-active");
      step.appendChild(scenes[i]);
    });
    watchScenes();
  }

  function sync() { reduce.matches ? disable() : enable(); }

  if ("IntersectionObserver" in window) {
    new IntersectionObserver(([entry]) => {
      const was = visible;
      visible = entry.isIntersecting;
      if (visible && !was && on && !userPaused) select(active);
      else { applyLive(); schedule(); }
    }, { threshold: 0.35 }).observe(player);
  }
  document.addEventListener("visibilitychange", schedule);
  reduce.addEventListener?.("change", sync);

  watchScenes();
  sync();

  // Download button, below the steps: the .dmg downloads as usual; the page then
  // goes back up to the steps and plays them from the start.
  document.getElementById("download-button")?.addEventListener("click", () => {
    status.textContent = "Your download has started. Here's what to do next:";
    section.scrollIntoView({ behavior: reduce.matches ? "auto" : "smooth", block: "start" });
    if (on) select(0);
  });
})();
