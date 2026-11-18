#!/usr/bin/env node
/*
  The tutor hanging from the logo on the sign-in screen (static/signin.html), drawn from the web
  app's own (its components/auth/LogoHang.tsx, the founder, 2026-11-17: "show an animation of
  this emoji character hanging from the Tutornote logo. make it precise", "hanging with one
  hand"), so the app's first screen and the website's sign-in page show the same tutor, the same
  hold on the "e" and the same swing.

  The screen allows only inline styles and scripts (its Content-Security-Policy), so this writes
  everything into the page, between markers, each time it runs:
    - the markup LogoHang draws (renderToStaticMarkup: Pip in 3D, its gradients, the boxes the
      swing turns), round the logo, between the HTML comments sign-in-tutor:start and
      sign-in-tutor:end, with a few lines of script for the push (LogoHang's onPointerEnter /
      onPointerDown);
    - the two stylesheets it needs (components/guide/tutorCharacters.css and
      components/auth/logoHang.css), between the CSS comments of the same names.
  scripts/build-renderer.mjs runs it after each bundle, from the same web commit.

    node scripts/sign-in-tutor.mjs [web checkout]   (default: $ANOTHERNOTES_WEB_DIR, ../tutornote-web)

  A web checkout without LogoHang (an older branch) leaves the page as it is. Exit 1: the page has
  lost its markers.
*/
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WEB = path.resolve(process.argv[2] || process.env.ANOTHERNOTES_WEB_DIR || path.join(ROOT, "..", "tutornote-web"));
const PAGE = path.join(ROOT, "static", "signin.html");
const ENTRY = path.join(WEB, "src", "components", "auth", "LogoHang.tsx");
const SHEETS = ["src/components/guide/tutorCharacters.css", "src/components/auth/logoHang.css"];

if (!existsSync(ENTRY)) {
  console.log(`sign-in tutor: ${path.relative(ROOT, ENTRY)} not in that checkout; signin.html left as it is`);
  process.exit(0);
}

// The web checkout's own esbuild (Vite brings it) and React, so the markup is the one it draws.
const req = createRequire(path.join(WEB, "package.json"));
const { buildSync } = req("esbuild");
const { createElement } = req("react");
const { renderToStaticMarkup } = req("react-dom/server");

const built = buildSync({
  entryPoints: [ENTRY],
  tsconfig: path.join(WEB, "tsconfig.app.json"),
  bundle: true,
  write: false,
  format: "cjs",
  platform: "node",
  jsx: "automatic",
  loader: { ".css": "empty" },
  external: ["react", "react/*", "react-dom", "react-dom/*"],
  logLevel: "silent",
});
const mod = { exports: {} };
new Function("module", "exports", "require", built.outputFiles[0].text)(mod, mod.exports, req);
const markup = renderToStaticMarkup(createElement(mod.exports.LogoHang));

const css = SHEETS.map((file) => `/* ${file} (web) */\n${readFileSync(path.join(WEB, file), "utf8").trim()}`).join("\n\n");

// LogoHang's push, as plain script: once the swing in has come to rest (0.3 s + 2.6 s), and once
// per push (2.3 s), away from the side the pointer came from, the free wing flapping.
const push = `(function () {
  var swing = document.querySelector(".logo-hang-swing");
  var figure = document.querySelector(".logo-hang-figure");
  if (!swing || !figure) return;
  var readyAt = performance.now() + 2900;
  function push(e) {
    var now = performance.now();
    if (now < readyAt) return;
    readyAt = now + 2300;
    var box = figure.getBoundingClientRect();
    swing.style.setProperty("--hang-push", e.clientX < box.left + box.width / 2 ? "-1" : "1");
    [[swing, "is-pushed"], [figure, "is-flapping"]].forEach(function (p) {
      p[0].classList.remove(p[1]);
      void p[0].offsetWidth;
      p[0].classList.add(p[1]);
    });
  }
  figure.addEventListener("pointerenter", push);
  figure.addEventListener("pointerdown", push);
})();`;

const html = readFileSync(PAGE, "utf8");
const between = (text, start, end, inner) => {
  const a = text.indexOf(start);
  const b = text.indexOf(end, a + start.length);
  if (a < 0 || b < 0) {
    console.error(`sign-in tutor: ${path.relative(ROOT, PAGE)} has lost its marker ${a < 0 ? start : end}`);
    process.exit(1);
  }
  return text.slice(0, a + start.length) + inner + text.slice(b);
};
let out = between(html, "/* sign-in-tutor:start */", "/* sign-in-tutor:end */", `\n${css}\n      `);
out = between(
  out,
  "<!-- sign-in-tutor:start -->",
  "<!-- sign-in-tutor:end -->",
  `\n          <span class="logo-hang-wrap logo-wrap"><img class="logo" src="tutornote-wordmark.png" alt="Tutornote" />${markup}</span>\n          <script>\n${push}\n          </script>\n          `,
);
if (out !== html) writeFileSync(PAGE, out);
console.log(`sign-in tutor: ${out === html ? "already" : "now"} drawn from ${path.relative(ROOT, ENTRY)} (${markup.length} characters of markup)`);
