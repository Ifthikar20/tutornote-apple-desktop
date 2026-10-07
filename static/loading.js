/*
  The loading screen's intro (loading.html): it plays the pictures in .slides on the
  computer's screen and tells the app when the intro is over, so the app opens on a
  finished welcome, never in the middle of a word or a picture.

  - Pictures: from FIRST_AT_MS (the welcome is written by then), each for PICTURE_MS,
    then the smiley again, and round again while the app is still loading. A picture
    that fails to load is skipped.
  - The intro is over once every picture has played once and the smiley is back; with
    no pictures, once the welcome and its line are in; with reduced motion (a still
    page), after about a second. A click on the computer, or Esc, Return or Space, ends
    it at once.
  - "Over" is said by setting the title to READY (src/main/windows.ts listens for it,
    with page-title-updated, and keeps the window's own title). The app opens at that
    point, or when its first page has loaded if that is later, and never later than its
    own cap (SPLASH_INTRO_MAX_MS) - so a long list of pictures cannot hold it up.
*/
(() => {
  const READY = "AnotherNote:ready";
  const FIRST_AT_MS = 3800; // the face has come (2.65 s), the welcome is written (3.3 s)
  const PICTURE_MS = 2200;
  const FACE_MS = 2200; // the smiley between rounds
  const FACE_BACK_MS = 700; // the smiley back on screen before the app opens
  const NO_PICTURES_MS = 3800; // the welcome and "Getting your notes ready…" are in (3.6 s)
  const STILL_MS = 1100;

  let over = false;
  const done = () => {
    if (over) return;
    over = true;
    document.title = READY;
  };

  // Ending it early: a click on the computer, or a key.
  document.querySelector(".computer")?.addEventListener("click", done);
  window.addEventListener("keydown", (e) => {
    if (e.key === "Escape" || e.key === "Enter" || e.key === " ") done();
  });

  const screen = document.querySelector(".screen");
  const slides = Array.from(document.querySelectorAll(".slides .slide"));
  const still = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (still) {
    setTimeout(done, STILL_MS);
    return;
  }
  if (!screen || !slides.length) {
    setTimeout(done, NO_PICTURES_MS);
    return;
  }

  for (const img of document.querySelectorAll(".slides img")) {
    const drop = () => {
      const figure = img.closest(".slide");
      const i = slides.indexOf(figure);
      if (i >= 0) slides.splice(i, 1);
      figure?.remove();
    };
    if (img.complete && img.naturalWidth === 0) drop();
    else img.addEventListener("error", drop, { once: true });
  }

  const show = (slide) => {
    for (const s of slides) s.classList.toggle("on", s === slide);
    screen.classList.toggle("showing", !!slide);
    // From now on the face blinks soon after it comes back (loading.html, .back).
    if (slide) screen.classList.add("back");
  };

  let next = 0;
  const step = () => {
    if (!slides.length) {
      // Every picture failed to load: the smiley stays, and the intro is over.
      show(null);
      done();
      return;
    }
    if (next < slides.length) {
      show(slides[next++]);
      setTimeout(step, PICTURE_MS);
    } else {
      next = 0;
      show(null);
      setTimeout(done, FACE_BACK_MS); // every picture has played once
      setTimeout(step, FACE_MS);
    }
  };
  setTimeout(step, FIRST_AT_MS);
})();
