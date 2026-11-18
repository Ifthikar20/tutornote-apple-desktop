#!/usr/bin/env node
/*
  The tutors on the app's own static screens, drawn from the web app's own code at the commit the
  app bundles, so they are the same tutors, in the same 3D look, as the bundled web app's:

    static/blob.html     the floating blob (src/main/companion.ts): every tutor a student can have
                         on the cursor (the web app's lib/guide/avatars.ts AVATARS: each look in its
                         own colour and in the one it wears when the student's other tutor has the
                         same look), drawn as components/screen/CompanionPointer.tsx draws the
                         cursor's (GuideAvatar: kind "neutral", mood "idle", POINTER_AVATAR_PX), one
                         <template> each, named "look:colour". The page shows the one the main
                         process names (blob:state's tutor: src/main/blobTutor.ts, from the web app's
                         tutorLook and from the cursor's own drawing), so the tutor resting in the
                         blob is the one that follows the cursor (the founder, 2026-11-17: "fix the
                         part where this is a different icon from what follows your cursor"). The
                         copy marked data-default is a new student's (useMainAvatar with nothing
                         chosen); it shows until main has heard which tutor it is.
    static/signin.html   the sign-in screen: Pip hanging by one wing from the logo (the web app's
                         components/auth/LogoHang.tsx: "show an animation of this emoji character
                         hanging from the Tutornote logo. make it precise", "hanging with one hand").

  Both pages allow only inline styles and scripts (their Content-Security-Policy), so this writes
  everything into each page, between markers, every time it runs: the markup (react-dom/server's
  renderToStaticMarkup of the web app's own components, with the web build's own esbuild and
  React) between the HTML comments <name>:start and <name>:end, and the stylesheets it needs
  between the CSS comments of the same names (blob-tutor, sign-in-tutor). Both pages are worked out
  first and written together. scripts/build-renderer.mjs runs it on the same export, before it
  replaces renderer/. Running it again changes nothing.

    node scripts/static-tutors.mjs [web build]

  [web build]: an export of tutornote-web with its node_modules installed, as build-renderer.mjs
  makes one (default: $TUTORNOTE_WEB_BUILD_DIR, else ~/Library/Caches/tutornote-build/web). Never a
  checkout's working tree: the app ships a commit, not anybody's unfinished changes. The pages do
  not say which commit they were drawn from, so another web commit with the same tutors redraws
  nothing (mac.yml and release.mjs stop only on a real change).

  An older web build: without LogoHang the sign-in screen is left as it is; from before the cursor
  wore the student's own tutor (no useMainAvatar: before web b5b00b2 it was always Sprout), the
  blob's first copy is Sprout.

  Exit 1: no web build there; a page has lost its markers; the web's tutors are not the ones the app
  takes from its pages (src/main/tutorLook.ts TUTOR_LOOKS and DEFAULT_TUTOR: make those the web's);
  the cursor wears a picture (POINTER_OVERRIDE), which the blob has no copy of; or a drawing came
  out with something the blob must never hold (a script, a handler, a link, an outside address).
*/
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WEB = path.resolve(
  process.argv[2] ||
    process.env.TUTORNOTE_WEB_BUILD_DIR ||
    (process.platform === "darwin"
      ? path.join(os.homedir(), "Library", "Caches", "tutornote-build", "web")
      : path.join(os.homedir(), ".cache", "tutornote-build", "web")),
);
const SRC = path.join(WEB, "src");
const has = (rel) => existsSync(path.join(SRC, rel));
const fail = (why) => {
  console.error(`static tutors: ${why}`);
  process.exit(1);
};

if (!has("lib/guide/avatars.ts") || !existsSync(path.join(WEB, "node_modules", "react-dom"))) {
  fail(`no web build at ${WEB} (an export with its node_modules: npm run renderer makes one)`);
}
const withLogo = has("components/auth/LogoHang.tsx");
// The cursor wears the student's own tutor (useMainAvatar, web b5b00b2 and after), and the pages say
// which.
const ownTutor = /export function useMainAvatar\b/.test(readFileSync(path.join(SRC, "lib", "guide", "avatars.ts"), "utf8"));

// The web build's own esbuild (Vite brings it) and React, so the markup is the one it draws.
const req = createRequire(path.join(WEB, "package.json"));
const { buildSync } = req("esbuild");
const { createElement } = req("react");
const { renderToStaticMarkup } = req("react-dom/server");

const entry = `
import { createElement } from "react";
import { GuideAvatar } from "@/components/guide/GuideAvatar";
import * as avatars from "@/lib/guide/avatars";
const SIZE = avatars.POINTER_AVATAR_PX ?? 48;
/** Every tutor a student can have on the cursor: each look in its own colour and in its other. */
export const TUTORS = avatars.AVATARS.flatMap((a) => [a.palette, a.alt].filter(Boolean).map((tint) => ({ look: a.id, name: a.name, tint })));
export const PICTURE = avatars.POINTER_OVERRIDE ?? null;
/** As components/screen/CompanionPointer.tsx draws the cursor's tutor (its passing feelings aside). */
export function Tutor({ look, tint }) {
  return createElement(GuideAvatar, { avatar: look, tint, image: null, kind: "neutral", size: SIZE, mood: "idle" });
}
/** A new student's tutor on the cursor, as "look:colour": useMainAvatar with nothing chosen (before
 *  it, the cursor was always useAvatar("", "neutral"): Sprout). */
export function NewStudent() {
  const a = avatars.useMainAvatar ? avatars.useMainAvatar() : avatars.useAvatar("", "neutral");
  return createElement("i", { "data-key": a.id + ":" + a.palette.base });
}
${withLogo ? 'export { LogoHang } from "@/components/auth/LogoHang";' : ""}
`;
const built = buildSync({
  stdin: { contents: entry, resolveDir: SRC, loader: "tsx", sourcefile: "static-tutors.tsx" },
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
const { TUTORS, PICTURE, Tutor, NewStudent } = mod.exports;
if (PICTURE) fail("the web app puts a picture on the cursor (POINTER_OVERRIDE), which the blob has no copy of");

/** A stylesheet of the web build, as it is, under its name. */
const sheet = (rel) => `/* src/${rel} (web) */\n${readFileSync(path.join(SRC, rel), "utf8").trim()}`;
/** Markup the blob must never hold. (An xmlns="http://www.w3.org/..." names a namespace and fetches
 *  nothing, so it is left out of the look.) */
const NEVER = /<(script|iframe|object|embed|foreignObject|image|use|a|link|style|meta|base)[\s/>]|[\s"'/]on[a-z]+\s*=|(?:xlink:)?href\s*=|javascript:|https?:\/\//i;
const unsafe = (markup) => NEVER.test(markup.replace(/\sxmlns(?::\w+)?="[^"]*"/g, ""));
const attr = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function between(text, page, start, end, inner) {
  const a = text.indexOf(start);
  const b = text.indexOf(end, a + start.length);
  if (a < 0 || b < 0) fail(`${page} has lost its marker ${a < 0 ? start : end}`);
  return text.slice(0, a + start.length) + inner + text.slice(b);
}

/** A page as it is to be: its stylesheet and markup between the markers. */
function drawn(page, name, css, html, what) {
  if (/<\/style|<script/i.test(css)) fail(`a stylesheet for ${page} could close its <style>`);
  const file = path.join(ROOT, "static", page);
  const was = readFileSync(file, "utf8");
  let out = between(was, page, `/* ${name}:start */`, `/* ${name}:end */`, `\n${css}\n      `);
  out = between(out, page, `<!-- ${name}:start -->`, `<!-- ${name}:end -->`, html);
  return { page, file, was, out, what };
}

/** The tutors the app takes from its pages (src/main/tutorLook.ts), read as written there. */
function appTutors() {
  const src = readFileSync(path.join(ROOT, "src", "main", "tutorLook.ts"), "utf8");
  const rows = [...src.matchAll(/^\s*([a-z][a-z0-9-]*): \{ name: "([^"]+)", bases: \["(#[0-9a-f]{6})", "(#[0-9a-f]{6})"\] \},?$/gm)];
  const first = /DEFAULT_TUTOR: TutorLook = Object\.freeze\(\{ look: "([a-z][a-z0-9-]*)", base: "(#[0-9a-f]{6})" \}\)/.exec(src);
  if (!rows.length || !first) fail("src/main/tutorLook.ts no longer has TUTOR_LOOKS and DEFAULT_TUTOR in the shape this reads");
  return {
    keys: rows.flatMap((r) => [`${r[1]}:${r[3]}`, `${r[1]}:${r[4]}`]),
    names: new Map(rows.map((r) => [r[1], r[2]])),
    first: `${first[1]}:${first[2]}`,
  };
}

// The blob: every tutor it can rest as, one inert <template> each (only the one shown is ever in
// the page, and each copy's gradients have ids of their own: identifierPrefix).
const KEY = /^[a-z][a-z0-9-]*:#[0-9a-f]{6}$/;
const newStudent = ((renderToStaticMarkup(createElement(NewStudent)).match(/data-key="([^"]+)"/) || [])[1] || "").toLowerCase();
const keys = [];
const names = new Map();
const copies = TUTORS.map((t, i) => {
  const key = `${t.look}:${String(t.tint?.base).toLowerCase()}`;
  const name = String(t.name ?? "").trim();
  if (!KEY.test(key) || !name || name.length > 40) fail(`a tutor unlike the others in the web app: ${key} ${name}`);
  if (keys.includes(key)) return "";
  keys.push(key);
  names.set(t.look, name);
  const markup = renderToStaticMarkup(createElement(Tutor, t), { identifierPrefix: `b${i}-` });
  if (unsafe(markup)) fail(`${key} came out with something the blob must not hold`);
  return `\n      <template data-tutor="${key}" data-name="${attr(name)}"${key === newStudent ? " data-default" : ""}>${markup}</template>`;
});
if (!keys.includes(newStudent)) fail(`no copy of a new student's tutor (${newStudent || "none said"})`);

// The app takes only these from its pages: they must be the web's, or the blob would keep another
// tutor while the cursor shows this one (a web with no tutorLook never names one).
if (ownTutor) {
  const app = appTutors();
  const missing = keys.filter((k) => !app.keys.includes(k));
  const extra = app.keys.filter((k) => !keys.includes(k));
  const renamed = [...names].filter(([look, name]) => app.names.has(look) && app.names.get(look) !== name).map(([look, name]) => `${look} is ${name}`);
  if (missing.length || extra.length || renamed.length || app.first !== newStudent) {
    fail(
      "the web app's tutors are not the ones src/main/tutorLook.ts takes from its pages; make TUTOR_LOOKS and DEFAULT_TUTOR the web's" +
        (missing.length ? `\n  the web has, the app does not: ${missing.join(", ")}` : "") +
        (extra.length ? `\n  the app has, the web does not: ${extra.join(", ")}` : "") +
        (renamed.length ? `\n  renamed in the web: ${renamed.join(", ")}` : "") +
        (app.first !== newStudent ? `\n  a new student's: the web's ${newStudent}, the app's ${app.first}` : ""),
    );
  }
}

const pages = [
  drawn(
    "blob.html",
    "blob-tutor",
    sheet("components/guide/tutorCharacters.css"),
    `${copies.join("")}\n      `,
    `${keys.length} tutors, a new student's ${newStudent}`,
  ),
];

// The sign-in screen: Pip hanging from the logo, and LogoHang's push as plain script: once the
// swing in has come to rest (0.3 s + 2.6 s), and once per push (2.3 s), away from the side the
// pointer came from, the free wing flapping.
if (withLogo) {
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
  const logo = renderToStaticMarkup(createElement(mod.exports.LogoHang));
  pages.push(
    drawn(
      "signin.html",
      "sign-in-tutor",
      `${sheet("components/guide/tutorCharacters.css")}\n\n${sheet("components/auth/logoHang.css")}`,
      `\n          <span class="logo-hang-wrap logo-wrap"><img class="logo" src="tutornote-wordmark.png" alt="Tutornote" />${logo}</span>\n          <script>\n${push}\n          </script>\n          `,
      `Pip on the logo, ${logo.length} characters of markup`,
    ),
  );
} else {
  console.log("static tutors: no components/auth/LogoHang.tsx in that web build; signin.html left as it is");
}

// Every page worked out: now written, together.
for (const p of pages) {
  if (p.out !== p.was) writeFileSync(p.file, p.out);
  console.log(`static tutors: ${p.page} ${p.out === p.was ? "already" : "now"} drawn from the web app (${p.what})`);
}
