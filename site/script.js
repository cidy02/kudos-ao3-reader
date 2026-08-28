/**
 * Scroll reveals via IntersectionObserver.
 * Progressive enhancement: only runs when motion is allowed; content is
 * visible without JS (see styles.css — effects gated on html.js).
 */
(function () {
  "use strict";

  document.documentElement.classList.add("js");

  var prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)"
  ).matches;

  if (prefersReducedMotion) {
    return;
  }

  var nodes = document.querySelectorAll(".reveal");
  if (!nodes.length || !("IntersectionObserver" in window)) {
    nodes.forEach(function (el) {
      el.classList.add("is-visible");
    });
    return;
  }

  var observer = new IntersectionObserver(
    function (entries, obs) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          obs.unobserve(entry.target);
        }
      });
    },
    {
      root: null,
      rootMargin: "0px 0px -8% 0px",
      threshold: 0.12,
    }
  );

  nodes.forEach(function (el) {
    observer.observe(el);
  });
})();
