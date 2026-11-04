// Drawn UI scenes: play only while visible, reveal on scroll, and mark the
// nav link of the section in view. Everything works without this script.

(() => {
  document.documentElement.classList.add("js");

  const scenes = [...document.querySelectorAll(".scene")];
  const reveals = [...document.querySelectorAll(".reveal")];
  const links = [...document.querySelectorAll('.nav-links a[href^="#"]')];

  if (!("IntersectionObserver" in window)) {
    scenes.forEach((s) => s.classList.add("is-playing"));
    reveals.forEach((r) => r.classList.add("is-in"));
    return;
  }

  const play = new IntersectionObserver((entries) => {
    for (const e of entries) e.target.classList.toggle("is-playing", e.isIntersecting);
  }, { threshold: 0.2 });
  scenes.forEach((s) => play.observe(s));

  const reveal = new IntersectionObserver((entries, obs) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add("is-in");
      obs.unobserve(e.target);
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
  reveals.forEach((r) => reveal.observe(r));

  const targets = links.map((a) => document.getElementById(a.hash.slice(1))).filter(Boolean);
  const live = new Set();
  const spy = new IntersectionObserver((entries) => {
    for (const e of entries) (e.isIntersecting ? live.add(e.target) : live.delete(e.target));
    const current = targets.filter((t) => live.has(t)).pop();
    for (const a of links) {
      if (current && a.hash === "#" + current.id) a.setAttribute("aria-current", "true");
      else a.removeAttribute("aria-current");
    }
  }, { rootMargin: "-45% 0px -50% 0px" });
  targets.forEach((t) => spy.observe(t));
})();
