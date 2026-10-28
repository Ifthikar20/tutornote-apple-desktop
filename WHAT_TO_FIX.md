# What to fix — tutornote-apple-desktop

Security review, October 2026. Branch `vulnerability_october_vulnerability`, cut from `claude/beautiful-gauss-rc0er0` at `87aa789`.

This file lists every vulnerability found in this repository and what to change to fix it. It was written
**before** any fix, so it describes the code as it stands at `87aa789`. The fixes follow on this same branch;
each fix commit names the IDs it closes, and the Status column below is updated as they land.

**13 findings: 4 Medium, 9 Low.**

How to read a finding:
- **Severity:** how bad it is if exploited, given what is reachable today.
- **Confidence:** `confirmed` means it was traced or reproduced in the code; `likely` means the code path is
  there but one condition (a live setting, a browser behaviour) could not be checked from the repository.
- **Evidence** quotes the code; secret values are never reproduced, only their first characters.

## At a glance

| ID | Severity | Category | What | Status |
|---|---|---|---|---|
| MAC-01 | Medium | Native helper | Native helpers' "launched by Tutornote" check can be satisfied by another local process | Open |
| MAC-02 | Medium | Other (trust boundary / configuration) | Launch environment variables repoint the trusted origin in the packaged app | Open |
| MAC-03 | Medium (likely) | Electron hardening | Chromium debugging and network switches are honoured; fuses don't cover them | Open |
| MAC-04 | Medium | CI / supply chain | Release workflow exposes signing and notarisation secrets to third-party build code | Open |
| MAC-05 | Low | Navigation | A sign-in "round trip" lets any HTTPS host reached by redirect load in the app window with the preload | Open |
| MAC-06 | Low | Electron hardening | `grantFileProtocolExtraPrivileges` stays on; `offline.html` has no CSP and follows its `url` query parameter | Open |
| MAC-07 | Low | Deep link | Any website can cancel an in-progress browser sign-in through `anothernotes://auth/…` | Open |
| MAC-08 | Low | Electron hardening | Microphone silently re-granted to the app origin; desktop CSP still allows Cloudflare's script host | Open |
| MAC-09 | Low | Update | Update feed points at a repository name that doesn't match this repo | Open |
| MAC-10 | Low | Electron hardening | Broad hardened-runtime entitlements, inherited by every helper | Open |
| MAC-11 | Low | Info leak | One-time sign-in secrets and text read from other apps written to stdout; email kept in localStorage | Open |
| MAC-12 | Low | Hard-coded information | Internal test server address in source and README; `.gitignore` lacks key-file patterns | Open |
| MAC-13 | Low | CVE | npm audit advisories are build-toolchain only | Open |

Branch `vulnerability_october_vulnerability` (HEAD 87aa789, cut from `claude/beautiful-gauss-rc0er0`, the newest line; this repo has no `feature/october`). Reviewed: `src/main/*`, `src/preload/*`, `static/*`, `helpers/screen`, `helpers/speech`, `build/entitlements.mac.plist`, `electron-builder.config.cjs`, `.github/workflows/mac.yml`, `scripts/*`, the lockfile and git history. `npm test`: 91/91 passing.

## Summary
The Electron baseline is the same strong one as the Windows app:
- every window has `contextIsolation`, `sandbox` and no `nodeIntegration`;
- IPC handlers check who is calling, and `openExternal` only takes http(s) and mailto links;
- the browser sign-in uses `state` plus PKCE;
- the fuses turn off RunAsNode, NODE_OPTIONS and `--inspect`, and cookies are encrypted with a Keychain key;
- updates go through Squirrel.Mac, which requires a valid code signature;
- there are no secrets in git history.

No path from a website to code execution was found. The weak points are local and in the supply chain:
- the native helpers' "only Tutornote may run me" check (MAC-01);
- environment variables and Chromium switches that a packaged app still honours, which reopen the door the fuses were meant to close (MAC-02, MAC-03);
- a release workflow that runs third-party build code in the same job as the signing and notarisation secrets (MAC-04).

## Attack chains
1. **Local malware borrows Tutornote's privacy permissions (MAC-01, MAC-02, MAC-03).** A same-user process without Screen Recording or Microphone permission of its own can:
   - try to get the helpers to work for it (MAC-01);
   - relaunch Tutornote pointed at its own origin (MAC-02), which then gets the app's microphone silently (MAC-08);
   - relaunch it with a debugging switch (MAC-03).

   Any one of these turns the user's "allow Tutornote" consent into consent for the attacker.
2. **Poisoned build becomes a signed, notarised, auto-updated release (MAC-04).** One malicious dependency in the web app's unpinned checkout or in `npm ci` runs in the same job as `CSC_LINK`, `APPLE_APP_SPECIFIC_PASSWORD` and a `contents: write` token. That is enough to steal the Developer ID certificate or to ship a signed update to every installed copy.
3. **Redirect inside the app, then a fake sign-in (MAC-05).** This is the same round-trip weakness as on Windows: it needs an open redirect behind `/api/auth/` or `/api/sources/`, and none exists today.

## Findings

### MAC-01 — Native helpers' "launched by Tutornote" check can be satisfied by another local process
- Severity: Medium (local attacker; defeats the macOS privacy-permission boundary for Screen Recording, Accessibility and Microphone)
- Category: Native helper
- Location: `helpers/screen/main.swift:270-285` (`refuseUnlessLaunchedByTutornote`), `:298-330` (`runDisclaimedIfNeeded`); `helpers/speech/main.swift:170-216` (same pattern); `src/main/screen.ts:504`, `src/main/speech.ts:280` (spawn)
- Confidence: likely (code reviewed; not exercised on a Mac)
- Evidence:
  ```swift
  // helpers/screen/main.swift:271-272
  let disclaimed = ProcessInfo.processInfo.environment[DISCLAIMED_ENV] != nil
  let app = disclaimed ? parentPid(of: getppid()) : getppid()
  ```
  The helper re-launches itself as its own "responsible process", so the macOS permission belongs to the helper and not to the Tutornote app. What protects that permission is a check on *who started it*, and that check has three weaknesses:
  - it identifies the caller by PID;
  - it uses an environment variable, which the caller controls, to decide which ancestor to check;
  - the private-app list is supplied over stdin by whoever drives the helper.
- Attack scenario: a program running as the user that has no Screen Recording or Microphone permission of its own launches the helper binary from inside `Tutornote.app` in a way that passes the ancestry check. It can then read other apps' windows or the microphone under the permission the user granted to Tutornote. It can also pass an empty private-app list, so password managers and Keychain Access are not excluded.
- Fix:
  - Stop making the helpers their own responsible process in signed builds; let TCC attribute to the signed app.
  - Alternatively, turn the helpers into XPC services (or launch them only with an inherited, pre-opened pipe) and verify the peer with an audit-token-based code-signing requirement. Never use a PID, and never use an environment variable to choose which process to check.
  - Hard-code the private-app list (Keychain Access, password managers, System Settings) inside the helper, and only allow the app to *add* entries.
  - If the disclaim step must stay, have the parent pass a one-time secret on an inherited file descriptor, and refuse to run without it.

### MAC-02 — Launch environment variables repoint the trusted origin in the packaged app
- Severity: Medium (on macOS this hands the app's microphone and speech-recognition permission to an attacker origin)
- Category: Other (trust boundary / configuration)
- Location: `src/main/config.ts:12`, `:48`, `:58`, `:86`; `src/main/companion.ts:1010`; `src/main/index.ts:134-141`
- Confidence: confirmed (code)
- Evidence:
  ```ts
  const override = process.env.ANOTHERNOTES_URL;          // config.ts:12
  export const BUNDLED = process.env.ANOTHERNOTES_SITE !== "1" && ...   // :48
  const override = process.env.ANOTHERNOTES_API_URL;      // :58
  ```
  Nothing checks `app.isPackaged`, and `http:` is accepted.
- Attack scenario:
  - A same-user process sets these variables, for example with `launchctl setenv` or by relaunching the app with `open --env`.
  - Tutornote then treats `https://evil.example` as its own origin:
    - the sign-in screen posts the typed password there;
    - the page gets the microphone without a new prompt (MAC-08) and gets the auth bridge.
  - `TUTORNOTE_TAP_LOG=1` additionally writes what the companion reads from other apps to stdout.
- Fix: read `ANOTHERNOTES_URL`, `ANOTHERNOTES_API_URL`, `ANOTHERNOTES_SITE`, `ANOTHERNOTES_PREVIEW_KEY` and `TUTORNOTE_TAP_LOG` only when `!app.isPackaged`, and refuse non-https URLs other than localhost. If testers need a packaged build pointed at a test server, make that a visible in-app setting with a permanent "Connected to <host>" banner.

### MAC-03 — Chromium debugging and network switches are honoured; fuses don't cover them
- Severity: Medium (likely)
- Category: Electron hardening
- Location: `src/main/index.ts` (no `app.commandLine` check); `electron-builder.config.cjs` `electronFuses`
- Confidence: likely
- Evidence: the fuses disable `--inspect` and NODE_OPTIONS, but nothing refuses `--remote-debugging-port`, `--remote-debugging-pipe`, `--proxy-server`, `--host-resolver-rules` or `--ignore-certificate-errors`.
- Attack scenario: a same-user process relaunches Tutornote with a debugging switch. It can then run script in the app's origin, including silent microphone use, and read the decrypted refresh cookie. This defeats the Keychain-protected cookie encryption the fuses were set up for.
- Fix: as the first statements of `src/main/index.ts`, exit if `app.isPackaged` and any forbidden switch is present. The list is: remote-debugging-port/pipe/address, remote-allow-origins, inspect*, js-flags, proxy-server, proxy-pac-url, host-rules, host-resolver-rules, ignore-certificate-errors*, disable-web-security, user-data-dir, renderer-cmd-prefix, gpu-launcher, utility-cmd-prefix, browser-subprocess-path.

### MAC-04 — Release workflow exposes signing and notarisation secrets to third-party build code
- Severity: Medium
- Category: CI / supply chain
- Location: `.github/workflows/mac.yml:20-21` (`permissions: contents: write` for the whole workflow), `:27` and `:40-44` (checkouts keep credentials on disk; the web repo is unpinned), `:34`, `:47` (`npm ci` and the web app's build run in the same job), `:49-56` (signing secrets)
- Confidence: confirmed (workflow)
- Evidence:
  ```yaml
  permissions:
    contents: write
  ...
  - uses: actions/checkout@v4          # persist-credentials defaults to true
  ...
  repository: Ifthikar20/playstudy-card-dash   # no ref: whatever its default branch is now
  token: ${{ secrets.WEB_REPO_TOKEN || github.token }}
  ...
  CSC_LINK: ${{ secrets.MAC_CERT_P12_BASE64 }}
  APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
  ```
- Attack scenario:
  - Install scripts from `npm ci` (in this repo or in the web checkout) run on the same runner before the signing step.
  - They can change files that the signing step later runs, and so read the `.p12` and the Apple password.
  - They can also use the persisted, write-scoped token to push to the repo or edit releases.
  - Whatever they plant ships as a signed, notarised update.
- Fix:
  - Set `permissions: contents: read` at the workflow level, and give `contents: write` only to a separate publish job.
  - Add `persist-credentials: false` to both checkouts, and pin the web checkout to a reviewed `ref`/SHA.
  - Run `npm ci --ignore-scripts`, with explicit `npm rebuild` for the packages that need it.
  - Build the web app in its own job with no secrets and pass it on as an artifact.
  - Pin third-party actions to commit SHAs.
  - Do the signing and notarisation in a job that only downloads the built artifacts.

### MAC-05 — A sign-in "round trip" lets any HTTPS host reached by redirect load in the app window with the preload
- Severity: Low
- Category: Navigation
- Location: `src/main/windows.ts:187`, `:302`, `:1522-1523`; `src/preload/index.ts` (bridge exposed on any http(s) page)
- Confidence: confirmed (code path). Exploiting it needs an open redirect behind `/api/auth/` or `/api/sources/`, and none was found in the backend.
- Evidence: `if (roundTrip && /^https:/i.test(url) && (redirect || tripHosts.has(host))) { tripHosts.add(host); return; }`
- Fix: same as WIN-04:
  - allowlist the identity and source provider hosts in `guard`;
  - expose the preload bridge and the `nav:open`/`chrome:layout` IPC only to the app origin and to `static/` pages;
  - check `event.senderFrame.url` in those handlers.

### MAC-06 — `grantFileProtocolExtraPrivileges` stays on; `offline.html` has no CSP and follows its `url` query parameter
- Severity: Low
- Category: Electron hardening
- Location: `electron-builder.config.cjs` (`grantFileProtocolExtraPrivileges: true`); `static/offline.html:37-42` (no CSP meta, unlike every other static page); `static/signin.html:7` (`img-src file:`, `media-src http:`)
- Confidence: confirmed (configuration). No current injection path was found.
- Fix:
  - Serve `static/` from a dedicated privileged scheme (`protocol.handle`, path-checked like `renderer.ts`) and turn the fuse off.
  - Meanwhile, add a CSP to `offline.html`, and only follow `url` when it matches `^(app|https)://`.

### MAC-07 — Any website can cancel an in-progress browser sign-in through `anothernotes://auth/…`
- Severity: Low
- Category: Deep link
- Location: `src/main/auth.ts:73-76`, `:87-95`
- Confidence: confirmed
- Evidence:
  ```ts
  const current = pending;
  pending = null;                       // cleared before the state is compared
  if (!current || Date.now() - current.startedAt > PENDING_TTL_MS) return null;
  if (state !== current.state || !TOKEN.test(code)) return null;
  ```
- Attack scenario: while a sign-in is in progress, any page can fire `anothernotes://auth/callback?state=x`. That throws away the genuine sign-in and shows an "expired" dialog. A malformed link makes `new URL(raw)` in `handleDeepLink` throw. The attacker cannot sign the user in to a different account, because `state` and PKCE prevent it.
- Fix: compare `state` before clearing `pending`; parse the URL once inside a `try`; show the dialog only when a sign-in was actually pending.

### MAC-08 — Microphone silently re-granted to the app origin; desktop CSP still allows Cloudflare's script host
- Severity: Low
- Category: Electron hardening
- Location: `src/main/index.ts:134-141`; `src/main/renderer.ts:55-60`
- Confidence: confirmed
- Evidence:
  - `permission === "media"` is granted to the app origin with no in-app prompt once macOS has granted the microphone the first time.
  - `script-src 'self' 'wasm-unsafe-eval' https://challenges.cloudflare.com`, although the desktop bundle has Turnstile off.
- Fix: ask once in the app (store the answer in `userData`); require `details.isMainFrame`; drop `challenges.cloudflare.com` from the desktop bundle's CSP.

### MAC-09 — Update feed points at a repository name that doesn't match this repo
- Severity: Low
- Category: Update
- Location: `electron-builder.config.cjs` `publish: { provider: "github", owner: "Ifthikar20", repo: "Another-note-apple-desktop" }`
- Confidence: likely
- Attack scenario: if `Another-note-apple-desktop` is private, deleted, or not the repo releases go to, installed apps stop receiving security updates. If the name were ever freed and re-registered by someone else, the update feed would point at them; Squirrel.Mac's signature check limits the damage to denial of updates.
- Fix: point `publish.repo` at the real release repository (`tutornote-apple-desktop`), and check that `latest-mac.yml` is reachable without a token.

### MAC-10 — Broad hardened-runtime entitlements, inherited by every helper
- Severity: Low
- Category: Electron hardening
- Location: `build/entitlements.mac.plist`; `electron-builder.config.cjs` (`entitlementsInherit: "build/entitlements.mac.plist"`)
- Evidence: `com.apple.security.cs.allow-unsigned-executable-memory` is set alongside `allow-jit`. The same file is inherited by the speech and screen helpers, which need neither.
- Fix: drop `allow-unsigned-executable-memory`; current Electron needs only `allow-jit`. Give the helpers their own minimal entitlements file (audio-input for the speech helper only) and sign them with it.

### MAC-11 — One-time sign-in secrets and text read from other apps written to stdout; email kept in localStorage
- Severity: Low
- Category: Info leak
- Location: `src/main/windows.ts:294`, `:1589` (`forLog` strips only the `#fragment`); `src/main/index.ts:184`; `src/main/auth.ts:80-82` (code, state and `code_verifier` in the query); `src/main/companion.ts:1010-1015`; `static/signin.html:443-444`
- Confidence: confirmed
- Fix: make `forLog` keep only origin and path, and use it in `index.ts:184`; keep the tap log for development builds only; remember the email only if the user opts in.

### MAC-12 — Internal test server address in source and README; `.gitignore` lacks key-file patterns
- Severity: Low
- Category: Hard-coded information
- Location: `src/main/config.ts:7`; `README.md:85-90`, `:188` (`http://100.49…`, plain HTTP); `.gitignore` (no `.env`, `*.p12`, `*.pem`, `*.key`)
- Confidence: confirmed
- Fix: replace the IP with a placeholder (`http://<test-server>/`), serve the test server over HTTPS, and add `.env*`, `*.p12`, `*.pfx`, `*.pem`, `*.key`, `*.cer` and `*.mobileprovision` to `.gitignore`.

### MAC-13 — npm audit advisories are build-toolchain only
- Severity: Low (informational)
- Category: CVE
- Location: `package-lock.json` (undici via `@electron/get` and node-gyp; http-cache-semantics; fast-uri)
- Confidence: confirmed (`npm audit --omit=dev` finds 0; none of these ship in `app.asar`). No advisory is listed for the Electron version in use.
- Fix: `npm audit fix` (in-range updates exist); keep Electron on the latest patch release of its major.
