# What the Mac app needs to match the Windows app's latest changes

## 1. Where it stands

The Windows app is at `3ffa62d` (origin/feature/october of tutornote-windows-app): 1.0.1 code on app.tutornote.ai, the browser sign-in fix, `scripts/release.mjs`, the never-stuck work, floating Sprout, and the screen helper that measures scroll by pixels (`helpers/screen-win/Shift.cs`). This Mac branch starts from `ff6655e`, which already had Sprout, the board window, Keep Board on Top and the never-stuck code. This change ported the rest. The TypeScript side: sign-in on `tutornote://` with legacy `anothernotes://` and a sign-in log, the companion's moved-window and `shift` handling, the re-read when you come back from another app, the "private" wording, the lift press point, and `static/toolbar.html`. The release side: version 1.0.1, `scripts/release.mjs`, `scripts/build-renderer.mjs` building a named tutornote-web commit, build output outside iCloud, and `mac.yml` guards. The Swift side: about 1,180 lines in `helpers/screen/main.swift` (shift matcher, shift tracker and its wiring, selftests, an 8 s read time limit, the "private" point read, lesson-window cadence, `bad_command`, `--any-parent`). On the PC, `tsc --noEmit` passes and 182 of 182 tests pass. **The Swift has never been compiled or run.** The PC has no Swift toolchain. All of this is committed and pushed to feature/october with this file; the Mac CI builds only on a version tag or a manual run, so nothing was built. The first compile can be a manual run of mac.yml (workflow_dispatch) on GitHub's Mac runner, or `scripts/build-screen-helper.sh` on a Mac.

## 2. On a Mac, first

Get the branch and the tools:

```bash
xcode-select --install            # once, for swiftc
git clone https://github.com/Ifthikar20/tutornote-apple-desktop.git
cd tutornote-apple-desktop
git checkout feature/october      # after this change is pushed
. scripts/use-node.sh             # Node 22.12+ via nvm and .nvmrc
npm ci
```

Build both helpers and run the screen helper's selftest. It runs before the parent check, so it works from a terminal:

```bash
scripts/build-speech-helper.sh
scripts/build-screen-helper.sh    # writes build/helpers/tutornote-screen; prints compiler errors if any
build/helpers/tutornote-screen --selftest; echo "exit $?"
```

The selftest must end with exit 0. It now includes `shiftSelfTest` (matcher, tracker rules, the 40 ms match time) and `readTimeSelfTest` (a stuck read is given up).

Build the bundled web app from the commit live on the site. Deploy tutornote-web first, then use its sha:

```bash
WEB_SHA=$(git ls-remote https://github.com/Ifthikar20/tutornote-web refs/heads/feature/october | cut -c1-40)
TUTORNOTE_WEB_REF=$WEB_SHA npm run renderer      # git archive of that commit only; writes renderer/BUILD "<sha> <time>Z"
cat renderer/BUILD
```

Run the app:

```bash
npm run typecheck && npm test
scripts/run-mac.sh                # packaged .app from ~/Library/Caches/tutornote-build/release, logs in this terminal
scripts/run-mac.sh --dev          # faster: from source with Electron
```

Grant the permissions. Open System Settings > Privacy & Security and turn on Tutornote (in `--dev` runs, Electron and your terminal) under **Screen & System Audio Recording** and **Accessibility**. Then quit and start again. To test the first-run prompts again:

```bash
tccutil reset ScreenCapture app.tutornote.desktop.screen
tccutil reset Accessibility app.tutornote.desktop.screen
```

## 3. Remaining gaps

### 3.1 First compile of the Swift helper (T3-REL-08)

**Windows:** `helpers/screen-win/*.cs` is compiled on every build and checked with `--selftest`.
**Mac:** `helpers/screen/main.swift` changed in 060fe90, 5dddc03 and this change, and it has never been compiled. `scripts/build-screen-helper.sh` fails the whole build if the host architecture does not compile.

First get a compiler result without a Mac, through CI. This runs a workflow_dispatch build, which gives an artifact only and publishes nothing:

```bash
git push origin HEAD:feature/october
gh workflow run mac.yml -R Ifthikar20/tutornote-apple-desktop --ref feature/october
gh run watch -R Ifthikar20/tutornote-apple-desktop
gh run view -R Ifthikar20/tutornote-apple-desktop --log-failed | grep -n "error:"
```

Places most likely to fail:

- `final class ShiftTracker: @unchecked Sendable` and its `Task.detached` follow loop. Swift 6 strict-concurrency diagnostics around `NSLock` and calls into `throughFilter` / `onScreenWindow` / `moving()`. If one of these touches main-thread state, wrap it as below:

```swift
let frame = await MainActor.run { onScreenWindow(window)?.frame }
```

- `recognizeWithin(image, level, ms:)`: the `FirstOnly` race and the lock-boxed `RecognizeStall`.
- `read(id:which:level:)`: the new `if case .at = which { ... await MainActor.run { ... } }` block.

Fix the errors, push, and run the workflow again until both arm64 and x86_64 build. Then, on a Mac, run the commands in section 2 and check the helper's identifier. TCC grants are tied to it:

```bash
REL=$(node -p "require('./electron-builder.config.cjs').directories.output")
codesign -dv "$REL/mac-universal/Tutornote.app/Contents/Resources/tutornote-screen" 2>&1 | grep Identifier
# Identifier=app.tutornote.desktop.screen
```

### 3.2 Live test of the shift tracker, and its speed (T2-SH-1..4)

**Windows:** `helpers/screen-win/Shift.cs` follows a motion at 33 ms frames, survives torn frames (up to 4 refused) and restarts after a loss. `Watcher.cs` opens a motion on wheel, keys and looks. The helper emits `shift` (with `settled:true` before `settled`, or `lost` with `why`).
**Mac:** the same logic is written in `main.swift` (sections `How far the content really moved ("shift")` and `Following a motion ("shift")`). The TypeScript consumers are in `src/main/companion.ts` (`onShift`) and `src/main/screenTeach.ts` (`onLessonShift`). It has not been run.

Test it with the app running (`scripts/run-mac.sh`, logs in the terminal). In Safari, Chrome and Preview, scroll a long page by wheel notches, trackpad fling, arrow keys and Page Down:

- Each motion logs `shift` events with a dy close to the real move, then one `settled:true` shift, then `settled`.
- Page Down (a jump larger than the overlap) logs `lost` with a `why`, and the page is read again.
- Command-scroll zoom gives `zoom`, not `shift`.
- A window dragged by its title bar is read again where it is now (T1-TS-03).
- Coming back to the lesson window from another app reads it again before its marks show (T1-TS-04).
- Double tap, drop and tap-hold (400 ms) still explain. A private window gives "Tutornote doesn't read that window." (T2-PRIV-1 + T1-TS-05).

To repeat live measurements by hand with a development (ad-hoc) helper, start it from a terminal. `--any-parent` only works when the helper is not team-signed:

```bash
build/helpers/tutornote-screen --any-parent
```

If one 1200x530 match takes more than 40 ms (the selftest checks this), replace the body of `shiftNcc` with vDSP. Add `import Accelerate` at the top of `main.swift`:

```swift
func shiftNcc(_ a: [Double], _ b: [Double], lag: Int, minOverlap: Int) -> Double {
    let from = max(0, lag)
    let to = min(a.count, b.count + lag)
    let n = to - from
    if n < max(1, minOverlap) { return -2 }
    return a.withUnsafeBufferPointer { pa in
        b.withUnsafeBufferPointer { pb in
            let x = UnsafeBufferPointer(rebasing: pa[from..<to])
            let y = UnsafeBufferPointer(rebasing: pb[(from - lag)..<(to - lag)])
            let ma = vDSP.mean(x)
            let mb = vDSP.mean(y)
            let dx = vDSP.add(-ma, x)
            let dy = vDSP.add(-mb, y)
            let sab = vDSP.dot(dx, dy)
            let saa = vDSP.sumOfSquares(dx)
            let sbb = vDSP.sumOfSquares(dy)
            if saa <= 1e-9 || sbb <= 1e-9 { return -2 }
            return sab / (saa * sbb).squareRoot()
        }
    }
}
```

`trackPicture` takes one `SCScreenshotManager` picture per frame (`sourceRect` on a single-window filter). If the logs show fewer than about 15 frames a second during a scroll, move the tracker to one `SCStream` per followed window. Its frames feed the same `Grey` and the same `follow` steps. Check `sourceRect` on a `desktopIndependentWindow` filter at the same time: a wrong rect shows up as every frame refused `size`.

Do not add a `CGEventTap` or a key-down monitor for any of this. Either one makes macOS ask for Input Monitoring.

### 3.3 Signing and notarisation secrets (T3-REL-09, the part not done)

**Windows:** `scripts/release.mjs` reports SIGNED or UNSIGNED, and `--require-signed` refuses an unsigned build.
**Mac:** `.github/workflows/mac.yml` now fails a tag build without `CSC_LINK`/`APPLE_ID`, and verifies the signature, the helper identifier and the stapled ticket. Nobody has checked that the secrets exist. An unsigned build cannot auto-update (`src/main/updater.ts`).

```bash
gh secret list -R Ifthikar20/tutornote-apple-desktop
# must list: MAC_CERT_P12_BASE64  MAC_CERT_PASSWORD  APPLE_ID  APPLE_APP_SPECIFIC_PASSWORD  APPLE_TEAM_ID
```

Test locally on a Mac with the Developer ID in the keychain:

```bash
security find-identity -v -p codesigning     # a "Developer ID Application" line
TUTORNOTE_WEB_REF=$WEB_SHA npm run release -- --check --require-signed
```

### 3.4 WEB_REF and the web token for CI (T1-REL-RENDERER, the process part)

**Windows:** the renderer is built from a pushed tutornote-web commit (`scripts/build-renderer.mjs`).
**Mac:** `mac.yml` now refuses a WEB_REF that is not 7 to 40 hex characters or not on tutornote-web's feature/october. The variable is not set, and nobody has checked that `WEB_REPO_TOKEN` can read tutornote-web.

The order is: **deploy the web app first**, then set WEB_REF to the live web sha, then build the desktop apps.

```bash
# after the tutornote-web deploy is live
WEB_SHA=$(git ls-remote https://github.com/Ifthikar20/tutornote-web refs/heads/feature/october | cut -c1-40)
gh variable set WEB_REF -R Ifthikar20/tutornote-apple-desktop --body "$WEB_SHA"
gh variable list -R Ifthikar20/tutornote-apple-desktop
gh secret list -R Ifthikar20/tutornote-apple-desktop | grep WEB_REPO_TOKEN   # needed if tutornote-web is private
```

Test: the workflow_dispatch run from 3.1 passes the "Check WEB_REF names a commit" step and the renderer step.

### 3.5 Helper bundle versions (optional)

`helpers/screen/Info.plist` and `helpers/speech/Info.plist` still say `1.0` / `1`. If you change them, change only the version keys. **Keep `CFBundleIdentifier` as it is** (`app.tutornote.desktop.screen`, `app.tutornote.desktop.speech`), or users lose their Screen Recording grants.

```xml
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
```

Test: `scripts/build-screen-helper.sh` rebuilds (the plist is newer), and `codesign -dv` shows the same identifier.

### 3.6 Update feed publishing (T1-REL-06)

**Windows:** a generic feed at `https://tutornote.ai/downloads/windows/`, uploaded by tutornote-web's `deploy-aws.sh --windows-release-only`.
**Mac:** a GitHub Releases feed (`electron-builder.config.cjs` `publish`, repo Ifthikar20/tutornote-apple-desktop). A tag build publishes a **draft**. Keep GitHub for 1.0.1, because installed 0.1.0 apps only know that feed.

After the tag build:

```bash
gh release list -R Ifthikar20/tutornote-apple-desktop
gh release edit v1.0.1 -R Ifthikar20/tutornote-apple-desktop --draft=false
curl -fsSL https://github.com/Ifthikar20/tutornote-apple-desktop/releases/latest/download/latest-mac.yml
# must print version: 1.0.1 without signing in: a private repo blocks electron-updater
```

Moving to `https://tutornote.ai/downloads/mac/` is a later step: one last GitHub-fed release that carries the generic config, plus a `--mac-release-only` mode in deploy-aws.sh.

### 3.7 MAC_BASE in the Windows repo

**Windows:** `MAC_BASE` lists the files kept byte-identical with the Mac and the Mac commit they come from (`5dddc03`).
**Mac:** `static/toolbar.html` is now byte-identical to the Windows copy. `src/main/auth.ts` is not, because the Mac copy keeps its own `MAC-07` / "on the Mac" comments, so it stays off the list.

After this Mac change is committed, edit `MAC_BASE` in tutornote-windows-app. Replace the first line with the new Mac commit and add the file:

```text
<new mac sha> Ifthikar20/tutornote-apple-desktop feature/october (2026-11-17)
...
static/toolbar.html
```

Test (from the folder that holds both repos):

```bash
cmp tutornote-apple-desktop/static/toolbar.html tutornote-windows-app/static/toolbar.html && echo same
```

### 3.8 Commit and push this change

Nothing has been committed. Commit by path, and stage nothing else:

```bash
git commit -m "Mac parity with Windows 1.0.1: tutornote:// sign-in + log, shift consumers, release and renderer scripts, Swift shift tracker (uncompiled)" -- \
  .github/workflows/mac.yml electron-builder.config.cjs helpers/screen/main.swift package.json package-lock.json \
  scripts/build-renderer.sh scripts/build-renderer.mjs scripts/release.mjs scripts/run-mac.sh scripts/sign-in-tutor.mjs \
  src/main/auth.ts src/main/companion.ts src/main/explain.ts src/main/index.ts src/main/screen.ts src/main/screenTeach.ts \
  static/toolbar.html MAC-WINDOWS-PARITY.md
git push origin HEAD:feature/october
```

New files must be added before `git commit -- <paths>` will take them: `git add -N scripts/build-renderer.mjs scripts/release.mjs MAC-WINDOWS-PARITY.md` first.

The test suite (`Tutornote_test_suite`) also changed: `apple-desktop/release.test.ts` (new), `apple-desktop/sessionHandOff.test.ts` (title), and `CATALOG.md`. Regenerating CATALOG.md also picked up unrelated drift (42 insertions, 12 deletions). Review it before committing the suite.

## 4. Release: Mac 1.0.1 with the same web

1. Deploy tutornote-web and check that it is live. The Windows 1.0.1 build waits for this too.
2. Set `WEB_REF` to that sha (3.4).
3. Get a clean compile, a passing `--selftest` and the live test on a Mac (3.1, 3.2).
4. Confirm the secrets (3.3).
5. Do a local dry run on the Mac:

```bash
git status --short                         # must be empty
TUTORNOTE_WEB_REF=$WEB_SHA npm run release -- --check --require-signed
TUTORNOTE_WEB_REF=$WEB_SHA npm run release -- --require-signed
# builds the renderer, typechecks, tests, packages; checks Tutornote-1.0.1-universal.dmg,
# Tutornote-1.0.1-universal-mac.zip, latest-mac.yml (sha512 + size) and app-update.yml;
# runs codesign --verify --deep --strict, spctl -a -vv, xcrun stapler validate. Uploads nothing.
```

6. Tag the release. CI checks that the tag matches package.json, runs `release.mjs --ci`, builds WEB_REF, signs, notarises and publishes a draft:

```bash
git tag v1.0.1
git push origin v1.0.1
gh run watch -R Ifthikar20/tutornote-apple-desktop
```

7. Publish the draft and check the public feed (3.6).
8. Install the 0.1.0 app on a Mac, let it update to 1.0.1, and check that sign-in works through the browser (`tutornote://`) and writes `~/Library/Application Support/Tutornote/logs/sign-in.log`. That log holds no codes, state or secrets.

## 5. Checklist

- [ ] 3.1 Swift helpers compile on arm64 and x86_64 (CI workflow_dispatch), errors fixed
- [ ] 3.1 `build/helpers/tutornote-screen --selftest` exits 0 on a Mac
- [ ] 3.1 Helper identifier is still `app.tutornote.desktop.screen`
- [ ] 3.2 Live shift test: wheel, trackpad, arrows, Page Down (lost), zoom, title-bar drag, return from another app
- [ ] 3.2 Double tap, drop, tap-hold and the private-window refusal work
- [ ] 3.2 Match time under 40 ms (vDSP otherwise); tracker at 15 fps or more (SCStream otherwise)
- [ ] 3.3 Signing and notarisation secrets confirmed; `--require-signed` dry run passes
- [ ] 3.4 Web deployed first; `WEB_REF` set to the live sha; `WEB_REPO_TOKEN` can read tutornote-web
- [ ] 3.5 (Optional) Helper Info.plist versions 1.0.1, identifiers unchanged
- [ ] 3.6 Draft release published; `latest-mac.yml` publicly readable
- [ ] 3.7 Windows `MAC_BASE`: new Mac commit line, `static/toolbar.html` added
- [ ] 3.8 Mac change committed by path and pushed to feature/october; suite changes reviewed and committed
- [ ] 4 Tag v1.0.1 built, and the update from 0.1.0 to 1.0.1 tested with browser sign-in
