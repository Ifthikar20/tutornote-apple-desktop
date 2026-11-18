#!/usr/bin/env node
/*
  Build the web app (tutornote-web) and copy its production bundle into renderer/, which the
  desktop app serves from its own origin and packages (src/main/renderer.ts). As the Windows app's
  scripts/build-renderer.mjs; scripts/build-renderer.sh runs this.

    npm run renderer                                         the web checkout beside this repo, feature/october
    TUTORNOTE_WEB_REF=94ae3b7 npm run renderer               another branch, tag or commit
    TUTORNOTE_WEB_DIR=~/code/tutornote-web npm run renderer  a checkout somewhere else

  With no checkout beside this repo (and no TUTORNOTE_WEB_DIR), tutornote-web is cloned into .web/
  (TUTORNOTE_WEB_REPO), fetched again on each later run, and a branch is taken as GitHub has it;
  its .env.off is the commit's .env.off.example.

  Only committed work is built: the ref is exported with `git archive` into a build folder outside
  iCloud (~/Library/Caches/tutornote-build/web, or TUTORNOTE_WEB_BUILD_DIR), so the checkout's own
  working tree, its dist/ and its node_modules are never touched, and nobody's unfinished changes
  end up in the app. The checkout's .env.off (the build profile's settings: API at the relative
  /api, Turnstile off; VITE_* values, which end up in the public bundle anyway) is copied in, as
  `npm run build:off` needs it. Before renderer/ is replaced, the tutors on the app's own screens
  are drawn from the same export (scripts/static-tutors.mjs): every tutor the floating blob can rest
  as (static/blob.html), and the sign-in screen's hanging one. renderer/BUILD records the commit and
  the time.
*/
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const besideUs = path.join(root, "..", "tutornote-web");
const cloned = path.join(root, ".web");
const webDir = path.resolve(
  process.env.TUTORNOTE_WEB_DIR || (fs.existsSync(path.join(besideUs, "package.json")) ? besideUs : cloned),
);
const webRepo = process.env.TUTORNOTE_WEB_REPO || "https://github.com/Ifthikar20/tutornote-web";
const ref = process.env.TUTORNOTE_WEB_REF || "feature/october";
const buildDir = path.resolve(
  process.env.TUTORNOTE_WEB_BUILD_DIR ||
    (process.platform === "darwin"
      ? path.join(os.homedir(), "Library", "Caches", "tutornote-build", "web")
      : path.join(os.homedir(), ".cache", "tutornote-build", "web")),
);
const out = path.join(root, "renderer");

const say = (line) => console.log(`==> ${line}`);
function run(cmd, args, opts = {}) {
  // npm is npm.cmd on Windows (a build tried there), which only runs through a shell; its
  // arguments here are this script's own constants, so they go as one command line.
  const viaShell = process.platform === "win32" && cmd === "npm";
  const r = viaShell
    ? spawnSync([cmd, ...args].join(" "), { stdio: "inherit", shell: true, ...opts })
    : spawnSync(cmd, args, { stdio: "inherit", ...opts });
  if (r.status !== 0) {
    console.error(`${cmd} ${args.join(" ")} failed (exit ${r.status ?? r.signal})`);
    process.exit(1);
  }
  return r;
}
function git(...args) {
  const r = spawnSync("git", ["-C", webDir, ...args], { encoding: "utf8" });
  if (r.status !== 0) {
    console.error(`git ${args.join(" ")}: ${r.stderr.trim()}`);
    process.exit(1);
  }
  return r.stdout.trim();
}
const hashOf = (file) => (fs.existsSync(file) ? createHash("sha256").update(fs.readFileSync(file)).digest("hex") : "");

// The .web/ clone: made once, fetched each time, and a branch named is taken as GitHub has it.
let wanted = ref;
const cloning = !process.env.TUTORNOTE_WEB_DIR && webDir === cloned;
if (cloning) {
  if (!fs.existsSync(path.join(cloned, ".git"))) {
    say(`cloning ${webRepo} into .web/`);
    run("git", ["clone", "--quiet", "--no-checkout", webRepo, cloned]);
  } else {
    say("fetching .web/");
    run("git", ["-C", cloned, "fetch", "--quiet", "origin"]);
  }
  const remote = spawnSync("git", ["-C", cloned, "rev-parse", "--verify", "-q", `origin/${ref}^{commit}`], { encoding: "utf8" });
  if (remote.status === 0) wanted = `origin/${ref}`;
} else if (!fs.existsSync(path.join(webDir, "package.json"))) {
  console.error(`No web app at ${webDir} (TUTORNOTE_WEB_DIR).`);
  process.exit(1);
}
const envFile = path.join(webDir, ".env.off");
// (the clone's: the committed .env.off.example, as CI builds it; a checkout of your own keeps its own)
if (cloning && !fs.existsSync(envFile)) {
  const example = spawnSync("git", ["-C", webDir, "show", `${wanted}:.env.off.example`], { encoding: "utf8" });
  if (example.status === 0) fs.writeFileSync(envFile, example.stdout);
}
if (!fs.existsSync(envFile)) {
  console.error(`${envFile} is missing: copy .env.off.example to .env.off in the web checkout first.`);
  process.exit(1);
}

const sha = git("rev-parse", "--short", `${wanted}^{commit}`);
say(`exporting tutornote-web ${ref} (${sha}) into ${buildDir}`);
fs.mkdirSync(buildDir, { recursive: true });
// Everything but node_modules goes, so a file deleted in the web app does not linger here.
for (const name of fs.readdirSync(buildDir)) {
  if (name !== "node_modules") fs.rmSync(path.join(buildDir, name), { recursive: true, force: true });
}
const tarName = `web-${sha}.tar`;
const tarFile = path.join(path.dirname(buildDir), tarName);
git("archive", "--format=tar", "-o", tarFile, sha);
// (a relative path, as on Windows, where Git Bash's GNU tar reads "C:\..." as a remote host)
run("tar", ["-xf", `../${tarName}`], { cwd: buildDir });
fs.rmSync(tarFile, { force: true });
fs.copyFileSync(envFile, path.join(buildDir, ".env.off"));

// Install only when the lock file changed since the last install here.
const lockHash = hashOf(path.join(buildDir, "package-lock.json"));
const stamp = path.join(buildDir, "node_modules", ".tutornote-lock");
if (!fs.existsSync(stamp) || fs.readFileSync(stamp, "utf8") !== lockHash) {
  say("installing the web app's dependencies");
  run("npm", ["ci", "--prefer-offline", "--no-audit", "--no-fund"], { cwd: buildDir });
  fs.writeFileSync(stamp, lockHash);
}

say("building the web app (build:off)");
run("npm", ["run", "build:off"], { cwd: buildDir });

// The tutors on the app's own screens, drawn from the same export (scripts/static-tutors.mjs): every
// tutor the floating blob can rest as (static/blob.html), and the sign-in screen's hanging one.
// Before renderer/ is replaced, so a failure leaves the bundle and the pages as they were.
run(process.execPath, [path.join(root, "scripts", "static-tutors.mjs"), buildDir]);

say("copying the bundle into renderer/");
fs.rmSync(out, { recursive: true, force: true });
fs.cpSync(path.join(buildDir, "dist"), out, { recursive: true });
fs.writeFileSync(path.join(out, "BUILD"), `${sha} ${new Date().toISOString().slice(0, 16)}Z\n`);
say(`renderer/ is ${fs.readFileSync(path.join(out, "BUILD"), "utf8").trim()}`);
