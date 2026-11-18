#!/usr/bin/env node
/*
  Make a Mac release on a Mac: check, build, and check what was built. It touches no server and
  uploads nothing; the last lines say how the release reaches the update feed. As the Windows
  app's scripts/release.mjs.

    TUTORNOTE_WEB_REF=<web commit> npm run release              the whole release
    TUTORNOTE_WEB_REF=<web commit> npm run release -- --check   only the checks: nothing is built or written
    ... -- --require-signed    stop when the build would be unsigned (or not notarised)
    ... -- --skip-renderer     keep renderer/ as it is (it must already be that web commit's build)
    ... -- --rebuild           build the version the release folder already holds once more
                               (only while that build has never been published)
    node scripts/release.mjs --ci   the checks of the repo's own files alone (version, lock,
                               addresses, feed): what the release workflow runs on a tag

  The steps, each stopping with what to do:
    1. The checks. No uncommitted change to a tracked file, and no file git has never seen in
       src/, static/, helpers/ or build/ (they go into the app); the version is plain n.n.n, the same
       in package-lock.json, and above the one the release folder's latest-mac.yml names; the app
       talks to app.tutornote.ai and keeps a browser sign-in's session; the update feed is still
       GitHub's Ifthikar20/tutornote-apple-desktop, the one every installed app asks;
       TUTORNOTE_WEB_REF names a commit of tutornote-web that is on origin/feature/october, so only
       pushed web code goes into an app; signed or unsigned.
    2. npm run typecheck, npm test.
    3. The web app's bundle from that commit (scripts/build-renderer.mjs), into renderer/, and the
       tutors on the static pages drawn from it (scripts/static-tutors.mjs): a page that changed
       stops the release until it is committed.
    4. npm run dist:mac: the universal .dmg, the .zip the updater takes and latest-mac.yml, in the
       release folder (~/Library/Caches/tutornote-build/release, or TUTORNOTE_RELEASE_DIR; outside
       iCloud).
    5. The files agree: latest-mac.yml names this version, the .zip and the .dmg, with their own
       sizes and SHA-512s, and the app inside asks the feed above for updates. When signed: the app
       passes codesign --verify --deep --strict and Gatekeeper (spctl), and the .dmg carries its
       notarisation ticket (stapler).

  Signed when electron-builder has a Developer ID to sign with (CSC_LINK or CSC_NAME, or a
  "Developer ID Application" identity in the keychain), and notarised when APPLE_ID,
  APPLE_APP_SPECIFIC_PASSWORD and APPLE_TEAM_ID are set (electron-builder.config.cjs). An unsigned
  Mac app cannot update itself.

  TUTORNOTE_WEB_DIR names a web checkout somewhere else, as for `npm run renderer`. The tests live
  in Tutornote_test_suite: the ones scripts/tests lacks are copied from the checkout beside this
  repo (TUTORNOTE_SUITE_DIR for another place), never over a file that is there.
*/
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** The feed every installed app asks for updates: GitHub Releases of this repo (0.1.0 knows no other). */
export const FEED = { provider: "github", owner: "Ifthikar20", repo: "tutornote-apple-desktop" };
/** Web code goes into an app only once it is on this branch of the web repo's origin. */
export const PUBLISHED_BRANCH = "origin/feature/october";
/** The files a release is (electron-builder's names for a universal build). */
export const dmgName = (version) => `Tutornote-${version}-universal.dmg`;
export const zipName = (version) => `Tutornote-${version}-universal-mac.zip`;

const PLAIN_VERSION = /^\d+\.\d+\.\d+$/;
const lf = (text) => String(text ?? "").replace(/\r\n/g, "\n");
const unquote = (value) => value.trim().replace(/^(['"])(.*)\1$/, "$2");

/** Which of two plain versions is later: below zero, zero, or above zero. */
export function compareVersions(a, b) {
  const x = a.split(".").map(Number);
  const y = b.split(".").map(Number);
  for (let i = 0; i < 3; i += 1) if (x[i] !== y[i]) return x[i] - y[i];
  return 0;
}

/** latest-mac.yml as electron-builder writes it: the version, the file the updater takes (path),
 *  its SHA-512, and the files list (each with its own name, SHA-512 and size). Missing lines come
 *  back as null. */
export function readFeed(text) {
  const lines = lf(text).split("\n");
  const top = (name) => {
    for (const line of lines) {
      const m = new RegExp(`^${name}:\\s*(.+)$`).exec(line);
      if (m) return unquote(m[1]);
    }
    return null;
  };
  const files = [];
  for (const line of lines) {
    const start = /^\s+-\s+url:\s*(.+)$/.exec(line);
    if (start) {
      files.push({ url: unquote(start[1]), sha512: null, size: null });
      continue;
    }
    const field = /^\s+(sha512|size):\s*(.+)$/.exec(line);
    if (field && files.length) {
      const file = files[files.length - 1];
      if (field[1] === "size") file.size = Number(unquote(field[2]));
      else file.sha512 = unquote(field[2]);
    }
  }
  return { version: top("version"), path: top("path"), sha512: top("sha512"), files };
}

/** The feed electron-builder.config.cjs names (its publish block), or null when it names none. */
export function feedOfConfig(builderText) {
  const block = /publish:\s*\{([^}]*)\}/.exec(lf(builderText));
  if (!block) return null;
  const field = (name) => new RegExp(`${name}:\\s*"([^"]*)"`).exec(block[1])?.[1] ?? null;
  return { provider: field("provider"), owner: field("owner"), repo: field("repo") };
}

const sameFeed = (feed) => Boolean(feed) && feed.provider === FEED.provider && feed.owner === FEED.owner && feed.repo === FEED.repo;
const feedShown = (feed) => (feed ? `${feed.provider ?? "?"} ${feed.owner ?? "?"}/${feed.repo ?? "?"}` : "not named");

/**
 * What stops a release before anything is built, as plain sentences (none: go ahead).
 *   pkg, lock    package.json and package-lock.json, parsed
 *   sources      { config, server, builder }: the text of src/main/config.ts, src/main/server.ts
 *                and electron-builder.config.cjs
 *   feedText     the release folder's latest-mac.yml from the release before, or null when none
 *   rebuild      true to allow the very version the release folder already holds
 */
export function preflightProblems({ pkg, lock, sources, feedText = null, rebuild = false }) {
  const problems = [];
  const version = String(pkg?.version ?? "");
  const plain = PLAIN_VERSION.test(version);
  if (!plain) {
    problems.push(
      `package.json's version is "${version}": a release is plain n.n.n. electron-updater takes a name like ` +
        `1.0.1-beta.1 as a pre-release, which installed apps never update to.`,
    );
  }
  const lockTop = lock?.version;
  const lockRoot = lock?.packages?.[""]?.version;
  if (lockTop !== version || lockRoot !== version) {
    problems.push(
      `package-lock.json says ${lockTop ?? "nothing"} (and ${lockRoot ?? "nothing"} for the app itself) where package.json ` +
        `says ${version}: set the version with \`npm version ${plain ? version : "<n.n.n>"} --no-git-tag-version\`.`,
    );
  }
  if (feedText !== null && feedText !== undefined) {
    const before = readFeed(feedText).version;
    if (!before || !PLAIN_VERSION.test(before)) {
      problems.push(`The release folder's latest-mac.yml names no plain version (${before ?? "none"}): move that file aside and try again.`);
    } else if (plain && compareVersions(version, before) < 0) {
      problems.push(`The release folder already holds ${before}, which is later than ${version}: installed apps never go back. Raise the version.`);
    } else if (plain && compareVersions(version, before) === 0 && !rebuild) {
      problems.push(
        `The release folder already holds ${before}: raise the version in package.json first. ` +
          `(To build ${version} once more because it was never published, pass --rebuild.)`,
      );
    }
  }
  const config = lf(sources?.config);
  if (!config.includes(`const DEFAULT_SITE = "https://app.tutornote.ai";`)) {
    problems.push(`src/main/config.ts: DEFAULT_SITE is not "https://app.tutornote.ai", so this build would not talk to the application's own name.`);
  }
  if (!config.includes(`const DEFAULT_WEBSITE = "https://tutornote.ai";`)) {
    problems.push(`src/main/config.ts: DEFAULT_WEBSITE is not "https://tutornote.ai", so the terms, the privacy page and the website link would open in the wrong place.`);
  }
  if (!lf(sources?.server).includes("useSessionCookies: jarCookies")) {
    problems.push(`src/main/server.ts has no \`useSessionCookies: jarCookies\`: without it a browser sign-in ends signed out, and this release signs every Mac out once.`);
  }
  const named = feedOfConfig(sources?.builder);
  if (!sameFeed(named)) {
    problems.push(
      `electron-builder.config.cjs: the update feed is ${feedShown(named)}, not ${feedShown(FEED)}. ` +
        `It must stay that feed, or the apps already installed never find this release.`,
    );
  }
  return problems;
}

/**
 * What is wrong with a finished release folder, as plain sentences (none: it is good to publish).
 *   feedText     the new latest-mac.yml, or null when the build wrote none
 *   version      package.json's version
 *   files        { "<name>": { size, sha512 } } for each file that is there (fileFacts)
 *   updateText   mac-universal/Tutornote.app/Contents/Resources/app-update.yml: left out = not
 *                checked, null = missing
 */
export function feedProblems({ feedText, version, files, updateText }) {
  const problems = [];
  const zip = zipName(version);
  const dmg = dmgName(version);
  const have = files ?? {};
  if (feedText === null || feedText === undefined) {
    problems.push("The build wrote no latest-mac.yml: installed apps would never hear of this release.");
  } else {
    const feed = readFeed(feedText);
    if (feed.version !== version) problems.push(`latest-mac.yml says version ${feed.version ?? "nothing"}, not ${version}.`);
    if (feed.path !== zip) problems.push(`latest-mac.yml names ${feed.path ?? "no file"} for the updater, not ${zip}.`);
    for (const name of [zip, dmg]) {
      const listed = feed.files.find((file) => file.url === name);
      if (!listed) {
        problems.push(`latest-mac.yml's files list has no ${name}.`);
        continue;
      }
      const fact = have[name];
      if (!fact) continue;
      if (listed.sha512 !== fact.sha512 || (name === zip && feed.sha512 !== fact.sha512)) {
        problems.push(`latest-mac.yml's SHA-512 is not ${name}'s own: an installed app would refuse the download.`);
      }
      if (listed.size !== fact.size) problems.push(`latest-mac.yml says ${listed.size ?? "no"} bytes where ${name} has ${fact.size}.`);
    }
  }
  for (const name of [zip, dmg]) if (!have[name]) problems.push(`${name} is not in the release folder.`);
  if (updateText !== undefined) {
    const field = (name) => {
      const m = new RegExp(`^${name}:\\s*(.+)$`, "m").exec(lf(updateText));
      return m ? unquote(m[1]) : null;
    };
    const asked = updateText === null ? null : { provider: field("provider"), owner: field("owner"), repo: field("repo") };
    if (!sameFeed(asked)) {
      problems.push(
        `The app inside asks ${updateText === null ? "no feed" : feedShown(asked)} for updates ` +
          `(Tutornote.app/Contents/Resources/app-update.yml), not ${feedShown(FEED)}.`,
      );
    }
  }
  return problems;
}

/** Each named file that is in the folder, with its size and its SHA-512 the way latest-mac.yml
 *  writes it (base64). Read in pieces: the .dmg is over a hundred megabytes. */
export function fileFacts(dir, names) {
  const facts = {};
  const piece = Buffer.alloc(1024 * 1024);
  for (const name of names) {
    const file = path.join(dir, name);
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) continue;
    const hash = createHash("sha512");
    const fd = fs.openSync(file, "r");
    let size = 0;
    try {
      for (;;) {
        const n = fs.readSync(fd, piece, 0, piece.length, null);
        if (n === 0) break;
        hash.update(piece.subarray(0, n));
        size += n;
      }
    } finally {
      fs.closeSync(fd);
    }
    facts[name] = { size, sha512: hash.digest("base64") };
  }
  return facts;
}

/** Signed or not, and notarised or not, from what electron-builder will find (no secret is shown).
 *  `identities` is `security find-identity -v -p codesigning`'s output (null off a Mac). */
export function signingState(env, identities) {
  const developerId = /"Developer ID Application: ([^"]+)"/.exec(identities ?? "");
  const signed = Boolean(env.CSC_LINK || env.CSC_NAME || developerId);
  const by = env.CSC_NAME ? env.CSC_NAME : env.CSC_LINK ? "the certificate in CSC_LINK" : developerId ? `Developer ID Application: ${developerId[1]}` : null;
  const notarise = ["APPLE_ID", "APPLE_APP_SPECIFIC_PASSWORD", "APPLE_TEAM_ID"];
  const missing = notarise.filter((name) => !env[name]);
  return { signed, by, notarised: signed && missing.length === 0, missing };
}

/* ---- the run itself: everything below reads the machine, and only from `main` ---- */

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const say = (line) => console.log(`==> ${line}`);

function stop(lines) {
  for (const line of [].concat(lines)) console.error(line);
  process.exit(1);
}

function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { stdio: "inherit", cwd: root, ...opts });
  if (r.status !== 0) stop(`${cmd} ${args.join(" ")} failed (exit ${r.status ?? r.signal}). Nothing was published; fix it and run the release again.`);
}

/** A git answer, or null when git refuses. --no-optional-locks: a check never writes, not even
 *  the index's own bookkeeping. */
function git(dir, ...args) {
  const r = spawnSync("git", ["--no-optional-locks", "-C", dir, ...args], { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trimEnd() : null;
}

const readText = (file) => (fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null);

/** The folders a build takes whole: src/ is compiled, helpers/ is built into the Swift helpers,
 *  static/ and build/ are packaged as they stand. A file there goes into the app, tracked or not. */
const BUILT_FOLDERS = /^(src|static|helpers|build)\//;

/** Where electron-builder writes: electron-builder.config.cjs's own answer (its directories.output). */
const releaseDirOf = () =>
  path.resolve(root, String(createRequire(import.meta.url)(path.join(root, "electron-builder.config.cjs")).directories?.output ?? "release"));

/** The keychain's code-signing identities, on a Mac (no secret: names only). */
function identities() {
  if (process.platform !== "darwin") return null;
  const r = spawnSync("security", ["find-identity", "-v", "-p", "codesigning"], { encoding: "utf8" });
  return r.status === 0 ? r.stdout : null;
}

/** The test files `npm test` names that scripts/tests lacks, and where the suite keeps them. */
function missingTests(pkg) {
  const named = String(pkg?.scripts?.test ?? "").match(/scripts\/tests\/\S+/g) ?? [];
  const missing = named.map((rel) => path.basename(rel)).filter((name) => !fs.existsSync(path.join(root, "scripts", "tests", name)));
  const suite = path.resolve(process.env.TUTORNOTE_SUITE_DIR || path.join(root, "..", "Tutornote_test_suite", "apple-desktop"));
  return { missing, suite, inSuite: missing.every((name) => fs.existsSync(path.join(suite, name))) };
}

function usage() {
  console.log(
    [
      "TUTORNOTE_WEB_REF=<web commit> node scripts/release.mjs [--check] [--require-signed] [--skip-renderer] [--rebuild]",
      "  --check           only the checks: nothing is built, nothing is written",
      "  --require-signed  stop when the build would be unsigned or not notarised",
      "  --skip-renderer   keep renderer/ as it is (it must be that web commit's build)",
      "  --rebuild         build the version the release folder already holds once more",
      "node scripts/release.mjs --ci   only the checks of the repo's own files (the release workflow's)",
    ].join("\n"),
  );
}

function main() {
  const flags = new Set(process.argv.slice(2));
  if (flags.has("--help") || flags.has("-h")) return usage();
  const known = ["--check", "--require-signed", "--skip-renderer", "--rebuild", "--ci"];
  const unknown = [...flags].filter((flag) => !known.includes(flag));
  if (unknown.length) {
    usage();
    stop(`Unknown option: ${unknown.join(" ")}`);
  }
  const checkOnly = flags.has("--check");

  // 1. The checks. Every problem is gathered, so one run names them all.
  say("checking (nothing is built yet)");
  const pkg = JSON.parse(readText(path.join(root, "package.json")) ?? "{}");
  const lock = JSON.parse(readText(path.join(root, "package-lock.json")) ?? "{}");
  const version = String(pkg.version ?? "");
  const releaseDir = releaseDirOf();
  const sources = {
    config: readText(path.join(root, "src", "main", "config.ts")),
    server: readText(path.join(root, "src", "main", "server.ts")),
    builder: readText(path.join(root, "electron-builder.config.cjs")),
  };
  if (flags.has("--ci")) {
    // (the workflow's: a fresh checkout, no release folder; the tag is checked against the version there)
    const problems = preflightProblems({ pkg, lock, sources, feedText: null });
    if (problems.length) stop([`Not ready: ${problems.length} thing${problems.length === 1 ? "" : "s"} to put right first.`, ...problems.map((line) => `  - ${line}`)]);
    say(`Tutornote ${version}: the repo's own checks pass`);
    return;
  }
  const problems = preflightProblems({
    pkg,
    lock,
    sources,
    feedText: readText(path.join(releaseDir, "latest-mac.yml")),
    rebuild: flags.has("--rebuild"),
  });

  if (process.platform !== "darwin") problems.push("A Mac release is built on a Mac: run this on the Mac.");

  // What git holds is what is built: no change to a tracked file, and no file git has never seen
  // in a folder the build takes whole (BUILT_FOLDERS). Ignored files (node_modules, renderer/,
  // build/helpers, the tests) are not listed, and a stray file anywhere else does not matter.
  const status = git(root, "status", "--porcelain", "--untracked-files=all");
  if (status === null) problems.push(`${root} is not a git checkout: a release is built from committed work only.`);
  else {
    const lines = status ? status.split("\n") : [];
    const few = (names) => `${names.slice(0, 4).join(", ")}${names.length > 4 ? ", ..." : ""}`;
    const changed = lines.filter((line) => !line.startsWith("??")).map((line) => line.slice(3));
    const stray = lines
      .filter((line) => line.startsWith("??"))
      .map((line) => line.slice(3).replace(/^"/, ""))
      .filter((name) => BUILT_FOLDERS.test(name));
    if (changed.length) problems.push(`Uncommitted changes in this repo (${few(changed)}): commit them first, so the release is what git holds.`);
    if (stray.length) {
      problems.push(`Files git does not hold would go into the build (${few(stray)}): commit them or move them out of the repo first.`);
    }
  }
  const appCommit = git(root, "rev-parse", "--short", "HEAD") ?? "unknown";

  if (!fs.existsSync(path.join(root, "node_modules", "typescript")) || !fs.existsSync(path.join(root, "node_modules", "electron-builder"))) {
    problems.push("node_modules is missing or incomplete here: run `npm ci` in this repo first.");
  }

  const tests = missingTests(pkg);
  if (tests.missing.length && !tests.inSuite) {
    problems.push(
      `${tests.missing.length} of the tests npm test names are not in scripts/tests (first: ${tests.missing[0]}) and not in ${tests.suite}: ` +
        "run `python sync.py --to-apps` in Tutornote_test_suite, or name its apple-desktop folder in TUTORNOTE_SUITE_DIR.",
    );
  }

  // The web commit that goes inside the app: named, a commit, and pushed.
  const webDir = path.resolve(process.env.TUTORNOTE_WEB_DIR || path.join(root, "..", "tutornote-web"));
  const ref = (process.env.TUTORNOTE_WEB_REF ?? "").trim();
  let webSha = null;
  let webShort = null;
  if (!fs.existsSync(path.join(webDir, "package.json"))) {
    problems.push(`No web app at ${webDir}: name the tutornote-web checkout in TUTORNOTE_WEB_DIR.`);
  } else {
    if (!ref) {
      problems.push(
        "TUTORNOTE_WEB_REF is not set: name the web commit that goes inside this release (the one that is live), " +
          "for example TUTORNOTE_WEB_REF=1a2b3c4 npm run release.",
      );
    } else if (!/^[0-9a-f]{7,40}$/i.test(ref)) {
      problems.push(`TUTORNOTE_WEB_REF is "${ref}": name a commit by its id (7 to 40 hex characters), not a branch. A branch moves; a release must say exactly what is inside it.`);
    } else {
      webSha = git(webDir, "rev-parse", "--verify", "--quiet", `${ref}^{commit}`);
      if (!webSha) {
        problems.push(`The web checkout at ${webDir} has no commit ${ref}: run \`git fetch\` there, or check the id.`);
      } else {
        webShort = git(webDir, "rev-parse", "--short", webSha) ?? webSha.slice(0, 7);
        const branches = (git(webDir, "branch", "-r", "--contains", webSha) ?? "").split("\n").map((line) => line.trim());
        if (!branches.includes(PUBLISHED_BRANCH)) {
          problems.push(
            `Web commit ${webShort} is not on ${PUBLISHED_BRANCH} as the web checkout knows it: push it first ` +
              "(or run `git fetch` in the web checkout). Only pushed web code goes into an app.",
          );
        }
      }
    }
    if (!fs.existsSync(path.join(webDir, ".env.off"))) {
      problems.push(`${path.join(webDir, ".env.off")} is missing: copy .env.off.example to .env.off in the web checkout first (or name a checkout that has it in TUTORNOTE_WEB_DIR).`);
    }
  }

  const signing = signingState(process.env, identities());
  if (flags.has("--require-signed")) {
    if (!signing.signed) problems.push("--require-signed: no Developer ID to sign with (CSC_LINK, CSC_NAME or the keychain), so this build would be unsigned.");
    else if (!signing.notarised) problems.push(`--require-signed: ${signing.missing.join(", ")} not set, so this build would not be notarised.`);
  }

  const signedLine = signing.signed
    ? `signed by ${signing.by}${signing.notarised ? ", notarised" : `, NOT notarised (no ${signing.missing.join(", ")})`}`
    : "UNSIGNED: no Developer ID (an unsigned Mac app cannot update itself)";
  say(`Tutornote ${version} for the Mac, app commit ${appCommit}, web commit ${webShort ?? "(not named)"}`);
  say(signedLine);
  say(`release folder: ${releaseDir}`);
  if (problems.length) {
    stop([`Not ready: ${problems.length} thing${problems.length === 1 ? "" : "s"} to put right first.`, ...problems.map((line) => `  - ${line}`)]);
  }
  if (checkOnly) {
    say(`ready to build ${version}. Nothing was built. Run it again without --check to build.`);
    return;
  }

  // 2. The code is sound.
  if (tests.missing.length) {
    say(`copying ${tests.missing.length} test${tests.missing.length === 1 ? "" : "s"} from ${tests.suite}`);
    fs.mkdirSync(path.join(root, "scripts", "tests"), { recursive: true });
    for (const name of tests.missing) fs.copyFileSync(path.join(tests.suite, name), path.join(root, "scripts", "tests", name), fs.constants.COPYFILE_EXCL);
  }
  say("type check and tests");
  run("npm", ["run", "typecheck"]);
  run("npm", ["test"]);

  // 3. The web app's bundle, from the named commit.
  if (flags.has("--skip-renderer")) say("keeping renderer/ as it is (--skip-renderer)");
  else {
    say(`building the web app's bundle from ${webShort}`);
    run(process.execPath, [path.join(root, "scripts", "build-renderer.mjs")], {
      env: { ...process.env, TUTORNOTE_WEB_REF: webSha, TUTORNOTE_WEB_DIR: webDir },
    });
    // The static pages are drawn from that commit too (scripts/static-tutors.mjs: the floating
    // blob's tutors, the sign-in screen's), and CI packages static/ as git holds it: pages the
    // drawing changed are committed first, so this release and CI's ship the same screens.
    const redrawn = git(root, "status", "--porcelain", "--", "static");
    if (redrawn) stop(`the web app's bundle redrew static pages from ${webShort}; commit them, then release again:\n${redrawn}`);
  }
  // renderer/BUILD starts with the commit's short id (scripts/build-renderer.mjs). Its length is
  // git's choice on the day it was written, so it is matched as the start of the full id.
  const built = (readText(path.join(root, "renderer", "BUILD")) ?? "").trim();
  const builtSha = built.split(/\s+/)[0] ?? "";
  if (!/^[0-9a-f]{7,40}$/.test(builtSha) || !webSha.startsWith(builtSha)) {
    stop(`renderer/ is ${built || "not built"}, not web commit ${webShort}: run the release again without --skip-renderer.`);
  }
  if (!fs.existsSync(path.join(root, "renderer", "index.html"))) {
    stop("renderer/index.html is missing: without it the app would load the site in its window instead of its own bundle.");
  }

  // 4. The .dmg and the .zip.
  say("packaging (npm run dist:mac)");
  run("npm", ["run", "dist:mac"]);

  // 5. What was built is what the feed says, and signed as it says.
  say("checking the release folder");
  const names = [zipName(version), dmgName(version)];
  const facts = fileFacts(releaseDir, names);
  const appPath = path.join(releaseDir, "mac-universal", "Tutornote.app");
  const wrong = feedProblems({
    feedText: readText(path.join(releaseDir, "latest-mac.yml")),
    version,
    files: facts,
    updateText: readText(path.join(appPath, "Contents", "Resources", "app-update.yml")),
  });
  if (wrong.length) stop(["The build finished, but the release is not right. Do not publish it.", ...wrong.map((line) => `  - ${line}`)]);
  if (signing.signed) {
    run("codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
    run("spctl", ["-a", "-vv", appPath]);
    if (signing.notarised) run("xcrun", ["stapler", "validate", path.join(releaseDir, dmgName(version))]);
  }

  // 6. What to do next. Nothing here goes near a server.
  const megabytes = Math.round(facts[dmgName(version)].size / (1024 * 1024));
  console.log("");
  say(`Tutornote ${version} is built (${signedLine}).`);
  console.log(`    folder:  ${releaseDir}`);
  console.log(`    files:   ${dmgName(version)}  (${megabytes} MB, ${facts[dmgName(version)].size} bytes)`);
  console.log(`             ${zipName(version)}`);
  console.log("             latest-mac.yml");
  console.log(`    inside:  app commit ${appCommit}, web commit ${webShort}`);
  console.log("");
  console.log("Nothing was published. The release the apps update to is built by the workflow (.github/workflows/mac.yml):");
  console.log(`    set the repository variable WEB_REF to ${webSha}, then: git tag v${version} && git push origin v${version}`);
  console.log("It publishes a DRAFT release: publish it by hand, then check that");
  console.log(`    https://github.com/${FEED.owner}/${FEED.repo}/releases/latest/download/latest-mac.yml is readable without signing in.`);
}

const asScript = (() => {
  try {
    return fs.realpathSync(process.argv[1] ?? "") === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
})();
if (asScript) main();
