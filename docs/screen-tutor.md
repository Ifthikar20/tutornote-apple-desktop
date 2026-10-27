# Screen tutor and voice: how it is built
Tutornote's Mac app can teach a page that is open in another app: a book in Kindle or Books, a PDF in a browser or in Preview, a slide deck. The student taps the words, and the tutor reads that window on this Mac, explains it aloud with marks over the page, turns the pages and draws on a board beside it.
The student can talk to it: one tap of the mic asks one question, and a five second hold turns on talk mode, a spoken back and forth.
When the student moves to another document, the tutor stops and starts again on the new one, and the server paces each lesson by what is on screen (slides, code, a table, a book).
The lesson itself is the bundled web app's Teach mode, and its words come from the backend. The Mac app adds two native helpers, the windows that float over other apps, and the bridge between the page and macOS. This document describes the code as it is in the working files. What has not been tried on real hardware is listed at the end.

## Map of the code
Mac app (this repo):

| File | What it holds |
|---|---|
| `helpers/screen/main.swift`, `helpers/screen/Info.plist` | The screen helper: window pictures and their text, the window list, taps and scrolls in other apps, page turns, which document is showing, new looks, the talk chord. |
| `helpers/speech/main.swift`, `helpers/speech/Info.plist` | The speech helper: Apple's speech recognition on the microphone, phrase cutting, the input choice, speakers or headphones. |
| `scripts/build-screen-helper.sh`, `scripts/build-speech-helper.sh`, `scripts/build-renderer.sh` | Build each helper as one universal binary in `build/helpers/`; build the web app into `renderer/`, with `renderer/BUILD`. |
| `scripts/use-node.sh`, `scripts/run-mac.sh`, `electron-builder.config.cjs`, `build/entitlements.mac.plist` | A Node that can build the app; build and run in one step; packaging, with the helpers as extra resources under the hardened runtime. |
| `src/main/index.ts`, `src/main/windows.ts`, `src/main/launchReveal.ts` | Start up order and one running copy; the main window, tab bar, pages, loader and the board's tab slot; the launch rule as a pure step function. |
| `src/main/screen.ts` | Runs the screen helper: requests, standing asks and events. |
| `src/main/screenTeach.ts` | The lesson: its window, runs, turns, rereads, taps, the board window, the talk key and chord, the switch to another document. |
| `src/main/docIdentity.ts` | Pure rules: is this still the same document, which rows are browser bars, where a switched run starts. |
| `src/main/explain.ts`, `src/main/screenText.ts` | "Explain on screen": the pick layers and the status panel; the helper's lines put back together as paragraphs (`mergeRows`, `blocksOf`). |
| `src/main/companion.ts` | The companion: the blob, glances, cards, taps, the ident listener. |
| `src/main/companionPlace.ts` | Pure companion rules: the blob's place, tap routes, private, reader, browser and editor apps, `selectionKept`. |
| `src/main/boardHost.ts`, `src/main/boardPlace.ts` | Pure board rules: in a tab or its own window, and where a floating board goes. |
| `src/main/speech.ts`, `src/main/speechLog.ts` | Runs the speech helper and its `speech:*` channels; checks start options; writes the `[speech]` lines. |
| `src/main/renderer.ts`, `src/main/server.ts`, `src/main/apiTiming.ts` | Serves the bundled web app on `app://anothernotes`, proxies the API, logs its timing. |
| `src/main/menu.ts`, `src/main/store.ts`, `src/main/events.ts` | Menus; small JSON files in the app's data folder; `appEvents`, the main process's own events. |
| `src/main/config.ts`, `auth.ts`, `signin.ts`, `links.ts`, `media.ts`, `updater.ts` | The app's origin and the proxied paths (`APP_ORIGIN`, `APP_SCHEME`, `PROXIED_PATHS`); sign in through the browser and in the app; links out (web and mail only, `openExternal`); the display kept awake while a page, the lesson window or the board plays sound, and for a minute after (`watchLessonAudio`); updates. |
| `src/preload/index.ts` | The bridge in every web page: `window.anothernotes` with `speech`, `screenTeach` and the `SpeechRecognition` shim. |
| `src/preload/toolbar.ts`, `blob.ts`, `board.ts`, `overlay.ts` | The bridges of the tab bar, the blob, the status panel and the pick layers. |
| `static/loading.html`, `toolbar.html`, `blob.html`, `board.html`, `overlay.html`, `signin.html`, `offline.html` | The app's own small pages. |
| `scripts/tests/*.test.ts` | Unit tests of the pure rules (`npm test`). |

Web app (bundled as `renderer/`, gitignored here; `renderer/BUILD` names the web build):
- `src/pages/ScreenTeachPage.tsx`: the screen tutor page.
- `src/components/guide/TeachMode.tsx`, `src/components/guide/GuideDock.tsx`, `src/components/screen/CompanionDock.tsx`: the lesson, its dock, the companion's dock.
- `src/lib/screen/`: `docIdentity.ts`, `screenBlocks.ts`, `screenFlow.ts`, `contentKind.ts`, `screenKind.ts`, `types.ts`.
- `src/lib/guide/`: `talkMode.ts`, `micShare.ts`, `outputRoute.ts`, `voiceTiming.ts`, `speech.ts`, `askCapture.ts`, `blocks.ts`.
- `src/lib/talkHold.ts`, `src/lib/useTalkKey.ts`, `src/services/guide.ts`, `src/index.css`.

Backend: `app/api/guide.py` (the `screen` field and the pacing per kind).

## What rounds 3 and 4 changed (27 October 2026)
Round 3, voice and launch:
- **One tap asks one question.** A click on the mic, the talk key, ⌃⌥M or a short Control+Option opens the mic once. The question sends itself when the student stops, and the mic closes quietly after 8 s of nothing. Web: `talkMode.ts`, `TeachMode.tsx` (`askOnce`).
- **A five second hold turns talk mode on**, with a ring that fills. It is the only way in. Web: `talkHold.ts`, `useTalkKey.ts`, the docks.
- **Control+Option alone is the screen tutor's talk key.** ⌃⌥M stays as the fallback and is always a tap. Screen helper `chord`; `screen.ts` `chordWatch`; `screenTeach.ts` `registerTalkKey`, `onChord`, `onChordState`; preload `onChord`, `onChordState`.
- **On speakers the tutor stops hearing itself** (half duplex). Speech helper `OutputWatch`; `speech.ts` `speech:output`; preload `speech.output`, `speech.onOutput`; web `outputRoute.ts`, `talkMode.ts`.
- **Launch with no intro.** The window shows as soon as its page loads; a loader comes up only after 1 s. New `launchReveal.ts`; `windows.ts`, `index.ts` and `static/loading.html` changed; `static/loading.js` and `static/loading/` removed.
- **A double click in a reader keeps the card.** `companionPlace.ts` `selectionKept`, used by `companion.ts` and `screenTeach.ts`.

Round 4, follow the screen:
- **Another document is noticed right away**: another tab, another window of the same app, or another reading app the student stays in. Screen helper `ident` and the `still` wait; `screen.ts` `identOf`; new `docIdentity.ts`; the switch flow in `screenTeach.ts`. The companion withdraws cards on a window that shows another document.
- **The old lesson and board stop, and a new run starts on the new document**, quietly, at its first words. It plays at once only if the old one was playing, the tutor is not paused, and the new page's kind is sure and one of slides, book, article, code or table; otherwise it stands on its first words until Play. Mac: `beginSwitch`, `switchRead`, the `screen-teach:hears-switching` handshake. Web: `ScreenTeachPage.tsx`.
- **Browser bars are not page text.** Mac: `docIdentity.ts` `browserBars`. Web: `screenBlocks.ts` `markBars`, `markSidebar`.
- **Content kind and wording per kind.** Web: `contentKind.ts`, `screenKind.ts`.
- **The screen kind goes to the server** in an optional `screen` field on `/guide/script` and `/guide/ask`. Web: `services/guide.ts`, `TeachMode.tsx`. The Mac app's proxy passes the body through untouched.
- The lesson's own `screen-teach:changed` now comes from `screenTeach.ts` for every lesson, not from `companion.ts`. `npm test` gained `docIdentity.test.ts`.

Backend: **lessons are paced per kind** in `app/api/guide.py`, committed on `feature/screen-pacing` and merged into `feature/october`: one slide at a time with a recap only on the deck's last slide, code and tables taught as a whole, forms with no quick checks. Without the field the prompt is byte for byte as before. See "The page and the server".

## Native helpers
The Mac app ships two small Swift programs next to Electron. The main process starts each one as a child process and talks to it in JSON lines: one object per line on the helper's stdin (a command, `"cmd"`), one per line on its stdout (an event, `"ev"`). A helper's stderr is its log, and the app copies every stderr line into its own log. Both helpers are optional: without them the app still runs. `build/helpers/` is gitignored.

| | Screen helper | Speech helper |
|---|---|---|
| Source | `helpers/screen/main.swift` | `helpers/speech/main.swift` |
| Embedded Info.plist | `helpers/screen/Info.plist` | `helpers/speech/Info.plist` |
| Build script | `scripts/build-screen-helper.sh` | `scripts/build-speech-helper.sh` |
| Binary | `build/helpers/tutornote-screen` | `build/helpers/tutornote-speech` |
| Minimum macOS (`MIN_MACOS`) | 14.0 | 12.0 |
| Driven by | `src/main/screen.ts` | `src/main/speech.ts` |
| Signing identifier | `app.tutornote.desktop.screen` | `app.tutornote.desktop.speech` |
| Permissions it holds | Screen Recording; Accessibility (page turns only) | Microphone; Speech Recognition |

### Why helpers at all
- **Screen helper.** ScreenCaptureKit takes one picture of one window (`SCScreenshotManager` with `SCContentFilter(desktopIndependentWindow:)`, cursor hidden). Vision reads its text (`VNRecognizeTextRequest`). The window server list (`CGWindowListCopyWindowInfo`) says which window is where and its title. `NSEvent.addGlobalMonitorForEvents` hears presses, releases, scrolls and cursor moves in other apps. Accessibility brings a reader's app to the front for a page turn by key, and `CGEvent` posts that turn. `CGEventSource.flagsState` polls the modifier keys for the talk chord: Electron's global shortcuts need a key that is not a modifier, so Control+Option on their own cannot be registered there.
- **Speech helper.** Electron's Chromium has the Web Speech API but not Google's service behind it. The helper runs Apple's `SFSpeechRecognizer` on an `AVAudioEngine` microphone tap, on this Mac whenever the language's on device model is installed, and reads input and output devices through Core Audio. The preload's `window.SpeechRecognition` shim makes it look like the browser's recogniser to the web app.
- **A permission identity of its own.** Each helper becomes its own "responsible" process (below), so macOS asks for, and records, Screen Recording, the microphone and speech recognition for the helper itself, not for whichever app or terminal started Tutornote. Each helper also refuses to run for any parent but Tutornote, so nothing else can borrow those permissions.

### Building: one universal binary each
`npm run build` runs `tsc`, then `scripts/build-speech-helper.sh`, then `scripts/build-screen-helper.sh`. Each script:
1. Exits 0 with a message when not on macOS, or when `xcrun -f swiftc` finds no Swift compiler. The app then has no "Explain on screen" button (screen), or dictates through the server's whisper as before (speech).
2. Skips the build when the binary is newer than its `main.swift`, its `Info.plist` and the script itself.
3. Compiles `swiftc -O` once per architecture, `arm64` and `x86_64`, with `-target <arch>-apple-macos<MIN_MACOS>`. The screen helper links ScreenCaptureKit, Vision, AppKit and Security; the speech helper links Speech, AVFoundation and Security.
4. Embeds the helper's `Info.plist` with `-Xlinker -sectcreate __TEXT __info_plist`. macOS reads the helper's names and usage reasons from there.
5. Requires the host's own architecture; the other is optional. With both, `lipo -create` joins them; with one, it is copied as is.
6. Signs the result ad hoc: `codesign --force --sign - --identifier app.tutornote.desktop.screen` (or `.speech`), so it runs from the working tree (`npm start`).

Packaging: `electron-builder.config.cjs` adds each built helper to `extraResources`, so it lands in `Tutornote.app/Contents/Resources/`. electron-builder signs it with the app under the hardened runtime, with `build/entitlements.mac.plist` (JIT, unsigned executable memory, `com.apple.security.device.audio-input`). Notarising happens only when Apple credentials are in the environment.

### Signing check, disclaiming and permission identity
Both `main.swift` files run the same start sequence, in this order:
1. `--selftest` and `--chordtest` (screen only) are handled first and exit. They need no app.
2. `refuseUnlessLaunchedByTutornote()`. The helper reads its own Team ID (`SecCodeCopySigningInformation`). With a team, the launching app must satisfy `identifier "app.tutornote.desktop" and anchor apple generic and certificate leaf[subject.OU] = "<that team>"`. Signed ad hoc (no team), the identifier `app.tutornote.desktop` or `com.github.Electron` (`npm start`) is enough. The launching app is the parent, or the grandparent inside the disclaimed copy. Any other parent gets one log line and exit code 1.
3. `runDisclaimedIfNeeded()`. The helper looks up `responsibility_spawnattrs_setdisclaim` at run time with `dlsym` and starts itself again with that attribute set, marked by `ANOTHERNOTES_SCREEN_DISCLAIMED` or `ANOTHERNOTES_SPEECH_DISCLAIMED` in the environment. The new copy shares the same stdin, stdout and stderr. The first copy waits for it, passes on SIGTERM, SIGINT and SIGHUP, and exits with its exit code. When the call is missing, the helper carries on as it is.

The disclaimed copy is its own responsible process, so the permissions belong to its embedded Info.plist identity, whoever started the app:

| Helper | CFBundleIdentifier | CFBundleName | CFBundleDisplayName | Usage reasons |
|---|---|---|---|---|
| Screen | `app.tutornote.desktop.screen` | Tutornote Screen Reader | Tutornote | none (Screen Recording and Accessibility take no Info.plist reason) |
| Speech | `app.tutornote.desktop.speech` | Tutornote Speech | Tutornote | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` |

The screen helper needs Screen Recording for any picture and to read window titles (`kCGWindowName`), and Accessibility only to post a page turn. Mouse monitors, the window list's geometry, `IsSecureEventInputEnabled` and the chord's flag polling ask for no permission. Whether the modifier flags reach a process without Input Monitoring is not documented by Apple; the helper reports it if they look hidden (see "The talk chord"). The speech helper needs the microphone and speech recognition, and asks for both only when a session starts.

### How the app runs them
**Screen (`src/main/screen.ts`).**
- `helperPath()` returns nothing off macOS, below Darwin 23 (macOS 14) or when the file is missing; `screenReadingAvailable()` is then false and the feature says so. The path is `process.resourcesPath/tutornote-screen` when packaged, else `build/helpers/tutornote-screen` under the app path.
- One helper runs for the app's life, started on first use by `ensureHelper()` with `spawn(file, [], { stdio: ["pipe", "pipe", "pipe"] })`. Stdout lines go through `readline` to `onLine`; stderr lines go to `console.warn`.
- `read` and `turn` are requests. Each gets a fresh `id`, waits for the one answer whose `ev` matches (`"read"` or `"turned"`), and fails with `ScreenReadError(code)` on any other `ev`. A read gives up after `READ_TIMEOUT_MS` (30 s); a turn after its own `timeoutMs` plus `TURN_GRACE_MS` (5 s). An `AbortSignal` sends `{"cmd":"cancel","id":…}`.
- `status`, `request` and `ax` carry no id and are answered in order, through queues. An `ax` check with no answer within `AX_TIMEOUT_MS` (3 s) counts as not allowed.
- Unasked events (`tap`, `release`, `press`, `scroll`, `front`, `over`, `changed`, `ident`, `chord`) are checked field by field and re-emitted on `watchEvents`. A chord `"state"` becomes a separate `chordState` event.
- Standing asks (`watch`, `companion`, `observe`, `chord`) are kept and sent again to a new helper as it starts. While the companion is on or the chord is watched, a helper that stops is started again after `RESPAWN_MS` (1 s), at most `RESPAWNS_PER_MINUTE` (5) times a minute.
- `restartScreenHelper()` stops the helper, because Screen Recording granted in System Settings counts only for a process started after it. On `will-quit` the app closes stdin and kills the helper 500 ms later.

**Speech (`src/main/speech.ts`).**
- `speechHelperPath()` has the same packaged and development paths, with no macOS version check. Without a helper, `installSpeech()` installs nothing, and the web app records for the server as before.
- One helper serves every page for the app's life. `speech:start` may always start it. `speech:warm`, `speech:prepare` and `speech:output` start none within `HELPER_RETRY_MS` (30 s) of a helper going down by itself.
- IPC is taken only from pages on the app's own origin (`trusted()`). The channels are in the bridge tables under "Windows, companion, board and the bridge". `speech:warm` is clamped to 0 to 20000 ms and the language is cut to 32 characters. `speechStartOptions` (`src/main/speechLog.ts`) checks the pre roll (dropped when in the future or older than `PREROLL_STALE_MS`, 5 s; brought to at most `PREROLL_MAX_MS`, 1.5 s, back) and the hints (strings, trimmed, at most `HINTS_MAX` 50 of at most `HINT_CHARS` 40 characters).
- Each page recogniser (`ref`) maps to a helper session `id`. Events go back to the owning page on `speech:event`. A page that is destroyed or navigates has its sessions aborted, so the microphone never stays open for it.
- A helper that exits hands every open session an `error` with code `network`, then `end`.

**On the helper side.** Stdin is read on its own thread and each line runs on the main queue. Stdin closing ends the helper; the speech helper first aborts its session and stops the microphone. The screen helper runs an `NSApplication` with the `.accessory` policy (no Dock icon, no menu bar) so its event monitors are delivered. The speech helper runs `RunLoop.main`.

### Screen helper: commands and events
All boxes and points are screen points from the top left of the main display, Electron's own space. **Permissions.** `{"cmd":"status"}` answers `{"ev":"status","screen":bool}` from `CGPreflightScreenCaptureAccess()`. `{"cmd":"request"}` calls `CGRequestScreenCaptureAccess()`; macOS shows its own prompt the first time. `{"cmd":"ax","prompt":bool}` answers `{"ev":"ax","trusted":bool}` from `AXIsProcessTrustedWithOptions`; with `prompt`, macOS shows its own dialog.
#### Reading a window: `read`
- `{"cmd":"read","id":1,"x":…,"y":…,"exclude":[pid,…]}` reads the top window at that point. `windowAt` takes layer 0 windows only, front to back, and skips the excluded processes, any copy of Tutornote (bundle ids starting `app.tutornote.`, `app.anothernote.` or `app.anothernotes.`), windows 40 points or less on a side, and windows with alpha under 0.05.
- `{"cmd":"read","id":1,"window":12345}` reads a window read before, by its id. When it is still listed but off screen (a Space sliding), the helper waits up to `SPACE_WAIT_MS` (1200 ms) before saying `window_gone`.
- `"level":"fast"` is a glance: Vision's fast pass with no language correction. When that finds no words on a window that is not blank (`isBlank`: grey range under 12), it reads once more accurately. The default `accurate` pass uses language correction and automatic language detection.
- The picture is taken at the display's scale, capped at `MAX_PIXELS_WIDE` (3600 px). A small grey thumbnail taken with it is remembered as the window's last read look (`remember`); its mean brightness becomes `"ground"`, 0 to 1.
- The answer, `{"id":1,"ev":"read",…}`, carries `app`, `bundle`, `title`, `window`, `pid`, `frame`, `lines` (each with `t`, `c`, a box and optional `words` with boxes), `captureMs`, `ocrMs`, `level`, `ground`, and `heldMs` when it waited. A line keeps no `words` when Vision cannot place every word, or gives one word the whole line's box.
- Vision reads one picture at a time per process. While a companion tap is being judged, a whole window read takes its picture at once but waits up to `TAP_HOLD_MS` (400 ms) before reading it (`tapsJudged`).
#### Turning a page: `turn`, `cancel`
`{"cmd":"turn","id":2,"window":…,"pid":…,"how":"scroll"|"key"|"manual",…}`. The command is checked first: `dy` is clamped to ±20000, `count` to 1 to 50, `timeoutMs` to 100 to 600000 (default 4000). Screen Recording is required, and Accessibility too unless `how` is `manual`. The window must still be on screen and owned by `pid`.
- `scroll`: wheel events over `at` (kept inside the window, else its centre), in steps of at most 100 points, 12 ms apart, each tagged `POSTED_BY_US` so the helper never reports its own scroll as the student's.
- `key`: one of `right`, `left`, `pagedown`, `pageup`, `down`, `up` (`KEY_CODES`), pressed `count` times, 250 ms apart. `bringForward` first raises the window and brings its app to the front through Accessibility. If the app does not come to the front, the key goes to that process directly (`postToPid`), never to whatever the student was typing into. Every posted event names its own modifier flags, so a held Control+Option cannot turn Right into Control+Right.
- `manual`: nothing is posted; the helper waits for the student.
- `unlessMoved: true`: when the window already differs from its last read look by more than `CHANGED_ABOVE`, that move counts as the turn. Nothing is posted and the answer says `"moved":true`.
- Settling: after the turn, a 256 px wide (`THUMB_WIDE`) grey thumbnail every `POLL_MS` (100 ms). The window has changed when its mean difference from the look before is above `CHANGED_ABOVE` (1.5 of 255), and has settled when two thumbnails in a row differ by less than `SETTLED_BELOW` (0.4). The answer is `{"id":2,"ev":"turned","changed":bool,"settleMs":…,"moved":bool,"front":bool}` (`front` for keys only). At the timeout, `changed` describes the last thumbnail.
- `"still":true` (with `manual` only) is no turn. It answers as soon as two thumbnails in a row agree, changed or not: `"still":true` in time, `"still":false` at the timeout, and `"changed"` says whether the window differs from its last read. `screenTeach.ts` sends it when a lesson switches documents (see `switchRead`).
- `{"cmd":"cancel","id":2}` gives a turn up; it answers `error` `cancelled`.

While a real turn runs, and for `TURN_QUIET_S` (2 s) after, the watch for new looks (`observe`) leaves that window alone. A `still` wait does not quiet it.
#### Watching the lesson's window: `watch`, `unwatch`
`{"cmd":"watch","window":12345}` until `{"cmd":"unwatch"}`:
- `{"ev":"front","pid":…,"bundle":…}`: the app in front, said as the watch starts and on every app activation.
- `{"ev":"tap","x":…,"y":…,"window":…,"moved":bool,"alt":bool}`, with the companion off. A tap is a press and a release within 5 points and 0.7 s, on the watched window where it is on top. `moved`: the window's middle rows, as pictured at the press, differ from its last read look. `alt`: Option was held.
- `{"ev":"scroll","dy":…,"dx":…,"momentum":bool,"window":…}`: the student scrolled the watched window (with the companion on, the window under the cursor). Content moved up by `dy` points; a wheel's lines count 40 points each.
- `ident` (next).
#### Which document: `ident`
A browser tab switch keeps the window id, so only the title says another document is showing. While a window is watched, `identTick` looks every `IDENT_MS` (150 ms, leeway `IDENT_LEEWAY_MS` 30 ms), and at once when an app comes to the front. It says `ident` as the watch starts, then only when something changed:

```
{"ev":"ident","window":…,"title":"…","onScreen":bool,
 "top":id|null,"topTitle":"…","topFrame":{…},
 "other":{"window":…,"pid":…,"app":"…","bundle":"…","title":"…","frame":{…}},
 "secure":bool}
```

- `title`, `onScreen`: the watched window's own entry in the window list.
- `top`: while the lesson's app is in front, that app's front ordinary window (`frontWindow`: layer 0, at least `IDENT_MIN_SIDE` 40 points each way, alpha 0.05 or more, on screen). Null while that app is behind.
- `other`: while another app is in front, that app's front ordinary window. Never said for Tutornote, and never while secure input is on.
- `secure`: secure input is on.
- A title that changed starts a burst of the new look watch, so the new page is said as soon as it is still.

`screen.ts` validates every field (`identOf`) into a `ScreenIdent` and passes it to `screenTeach.ts` and `companion.ts`. Titles go to the app only, never to either log.
#### The companion: `companion`, `over`, `press`, `release`, `tap`
`{"cmd":"companion","on":bool,"stop":[ids],"private":[bundle ids],"readers":[bundle ids]}`. `companion.ts` passes `PRIVATE_APPS` and `READER_APPS` from `companionPlace.ts`; `stop` lists Tutornote's own windows by id (`stopIds`: the blob, the board's own window, the main window and the Explain on screen panel), sent again whenever one of them comes on screen.
- `companionTarget` decides what the cursor is over. A window in `stop`, or a layer 0 Tutornote window, is `own`. Tutornote's other floating windows are looked through. Any other window above layer 0 (Dock, menu bar, a menu, Spotlight, a notification) means nothing, except another app's overlay that covers at least 95% of the display and is not from `com.apple.`, which is looked through.
- `{"ev":"over",…}`: the window under the cursor changed (`window` null over nothing or over Tutornote's own; `own`; `secure`). The helper looks again at once when the cursor leaves the last frame, else at most every `OVER_EVERY_S` (0.05 s), and on app activation and Space changes.
- `{"ev":"press","x","y","window"}`: the button went down on an ordinary window, said at once. Then, unless the app is private, secure input is on, or this is a double click's second press, the helper takes a thumbnail, a full scale picture of the column `COLUMN_REACH` (300 points) either side of the press, the title, and the watch's latest look of the window if it is at most `PRESS_LOOK_S` (1.5 s) old.
- `{"ev":"release","id":…,"x","y","window","alt","clicks","hand","private"}`: said at once at the release, before anything is judged. `id` counts on from the millisecond clock at the helper's start, so it is never reused. `clicks` is 2 or more for a double click. `hand` is true when the system cursor at the press matched `NSCursor.pointingHand` (hot spot, size and image). `private` is true when nothing of that window is pictured.
- `{"ev":"tap","id":…,"acted":bool,"words":"…",…}`: the verdict, judged on pictures taken `TAP_AFTER_MS` (150 ms) after the release.

| `words` | `acted` | Meaning |
|---|---|---|
| (none) | false | Private app, or secure input: said at once, no picture. |
| `select` | true | A double click (selects words). No pictures. A single tap on the same window still being judged gets `select` too. |
| `covered` | true | The window closed, or another window is on top at the tap now (a menu, a popover, a sheet). |
| `title` | true | The window's title changed since the press. |
| `skipped` | false | The tapped line's own patch did not change, so no words were read. |
| `kept` | false | The tapped words are still there, moved at most `TEXT_SHIFT` (120) points. |
| `gone` | true | The tapped words went. |
| `content` | true | The tapped label stayed, but the content away from it changed (a tab, a sidebar item). |
| `caret` | true | All that changed is a stroke at most `CARET_WIDE` (3) points wide and about a line tall. |
| `none` | pixels decide | No words at the tap or near it. |
| `pixels` | pixels decide | The words were not read within `TEXT_BUDGET_MS` (120 ms), or a picture failed. |

The pixel step (`judgeTap`) compares the tapped line's patch, `LINE_REACH` (14) points above and below the tap and `SIDE_REACH` (160) points either side, against the press picture and the watch's earlier look. In a reader (`readers`), the earlier look counts only when the window away from the tap, outside `TAP_REACH` (60) points, looked the same in both: a reader's bars fading in between the two must not count as the tap's doing. When the patch changed, the words decide (`judgeText`, `judgeMargin`): the column before and after is read with Vision's fast pass. The verdict also carries `moved`, `wide`, `line`, `away`, `look`, and for word verdicts `kept`, `shift` and `textMs`.
#### New looks: `observe`, `changed`
`{"cmd":"observe","windows":[…]}` watches at most two windows; `[]` stops. With the companion on, the app asks for the lesson's window and the one under the cursor (the lesson's alone while the companion is paused); otherwise `screenTeach.ts` asks for the lesson's window, plus the other window while a switch waits for words there (`observeSwitch`).
- A thumbnail of each every `OBSERVE_IDLE_MS` (500 ms), and every `POLL_MS` (100 ms) for `BURST_S` (1.5 s) after a press, a tap, a scroll, the cursor arriving, or a title change.
- `{"ev":"changed","window":…,"settleMs":…}`: the window's middle rows differ from its last read look (or its first look, if never read) by more than `CHANGED_ABOVE`, and two thumbnails in a row agree. The top and bottom `EDGE_SHARE` (12%) are left out, so a reader's bars or a dimming title bar are no new look. Said once per new look.
- Not said when a wheel scroll began within `SCROLL_EXPLAINS_S` (0.6 s) before the change began: the app follows scrolls from `scroll` itself. Keys and a dragged scroll bar send no wheel, so their changes are said.
- A window that keeps changing (a video, typing) is looked at quickly for at most `CHANGING_BURST_S` (3 s), then every 500 ms until it is still.
#### The talk chord: `chord`
`{"cmd":"chord","on":bool}`. `screenTeach.ts` turns it on exactly while its talk key is registered (see Voice).
- **How it watches.** Every `CHORD_POLL_MS` (33 ms, leeway `CHORD_LEEWAY_MS` 8 ms) it reads which modifiers are held (`CGEventSource.flagsState(.combinedSessionState)`). While a chord could be under way, it also reads how long ago the last modifier change, key down or up, mouse button and wheel event were (`secondsSinceLastEventType`, the later of the session and HID states): when, never which key. No event is taken; every key goes where it was going. While watched, the helper holds a `.userInitiatedAllowingIdleSystemSleep` activity and a strict timer to stay out of App Nap. The log says once if two polls come more than `CHORD_GAP_S` (0.15 s) apart.
- **Start.** Both Control and Option down with no Shift, Command or Fn (`CHORD_OTHERS`). The start time is the last modifier change, at most `CHORD_START_BACK_S` (0.1 s) before the poll that saw it. Keys already held when the watch starts, or still held after a release, cannot start a chord until all are up.
- **Spoiled.** Another modifier joining (`modifier`), a key down or up (`key`), a mouse button (`mouse`), or the wheel (`wheel`) between the start and the poll that saw the release. A wheel still gliding when the chord began (within `CHORD_GLIDE_S`, 0.15 s) never spoils it. VoiceOver or secure input coming on also spoils it. A chord spoiled after its `down` says `cancel` with that `why`; one spoiled before its `down` says nothing to the app, and the log says why at most once per `CHORD_SPOILED_EVERY_S` (1 s).
- **Events** `{"ev":"chord","kind":…,"ms":…,"why"?,"keys"?}`:
  - `down` at `CHORD_DOWN_S` (300 ms) held. The page shows the hold's ring.
  - `hold` once at `CHORD_HOLD_S` (5 s). The page turns on talk mode.
  - At the release: `up` after a hold; `tap` when held `CHORD_TAP_S` (700 ms) or less, with or without a `down` before it; else `cancel` with `why` `long`.
  - `cancel` with `why` `off` when the watch stops during a chord that said `down`.
  - `keys` (which sides, such as `lctrl+lopt` or `rctrl+ropt`, from the flags' device bits; `ctrl` or `opt` where they name no side) is for the log only. `screen.ts` forwards only the five known kinds, with `ms` rounded, `why` cut to 24 characters and `keys` to 32.
- **State** `{"ev":"chord","kind":"state","on":bool,"why"?}`: whether the chord can be used at all, said as the watch goes on and on every change. Off with `why` `voiceover` (Control and Option are VoiceOver's keys), `secure` (secure input, found as the keys are pressed, on again as soon as it ends), or `hidden` (three modifier changes in a row with no modifier ever seen held).
#### Secure input and errors
`secureInputOn()` is `IsSecureEventInputEnabled()`, except when the process holding it (`kCGSSessionSecureInputPID`) is `com.apple.loginwindow`: macOS holds it there while the screen is locked and can leave it held after unlocking. While it is on, the companion takes no picture of any window (`keptPrivate`), `over` and `ident` say `"secure":true`, `ident` says no `other`, and the chord is off. Errors are `{"id":…,"ev":"error","code":…}` with `no_permission`, `no_window`, `window_gone`, `no_access`, `capture_failed`, `bad_command` or `cancelled`. `screen.ts` adds `timeout` and `no_helper`.

### Speech helper: commands and events
| Command | What it does |
|---|---|
| `{"cmd":"start","id":1,"lang":"en-US","continuous":bool,"preroll":unixMs,"hints":[…]}` | Starts a session. A second start aborts the first: one recogniser at a time. |
| `{"cmd":"stop","id":1}` | Hands over what is in flight, then ends. |
| `{"cmd":"abort","id":1}` | Ends at once: `error` `aborted`, then `end`. |
| `{"cmd":"warm","id":0,"ms":3000}` | Keeps the microphone running up to `WARM_MAX_MS` (20 s). Only once the microphone is already allowed; it never asks. |
| `{"cmd":"prepare","id":0,"lang":"…"}` | Makes the language's recogniser now, when both permissions are already given. Never asks, opens no microphone. |
| `{"cmd":"output","id":0}` | Says the current output now (below). |

How a session runs:
- `start` asks for the microphone, then speech recognition, if not yet decided. Refused, it says `not-allowed`.
- Recognisers are made once per language and kept (`Recognizers`). `{"ev":"ready","onDevice","lang","cached","setupMs"}` says what this Mac can do. Recognition is on device when `supportsOnDeviceRecognition` is true and `ANOTHERNOTES_SPEECH_ONDEVICE` is not `0`; otherwise it is Apple's server recogniser.
- Each request reports partial results, uses the dictation task hint, adds punctuation on macOS 13 and later, and passes the hints as `contextualStrings`.
- Events: `start` (microphone open), `audiostart` (`warm`, and `preroll` in ms of earlier audio fed), `speechstart`, `interim` (all the words in flight), `phrase` (continuous: `text`, `cut`, `voiceEnd`, `cutAt`, `words` count), `end` (with the text for one utterance), `error` with a Web Speech code (`not-allowed`, `no-speech`, `network`, `aborted`, `audio-capture`, `language-not-supported`), `prepared`, `mic` (`on`, `why` `warm` or `session`), and `route`. Every event carries `"t"`, the unix ms it was sent.
- **Cutting phrases.** Apple's recogniser returns the whole growing transcription, so the helper cuts phrases itself (`cutNow`, checked every `CUT_CHECK_MS` 50 ms):
  - `quiet`: the energy gate is trusted and heard voice in this request, there is at least `END_QUIET_MS` (450 ms) of quiet, and the words have been unchanged for `STABLE_MS` (300 ms).
  - `text`: the words have been unchanged for `QUIET_MS` (800 ms default, `ANOTHERNOTES_SPEECH_QUIET_MS`; `QUESTION_QUIET_MS`, at least 900, for one utterance), with the gate untrusted or hearing at least `TEXT_QUIET_MS` (200 ms) of quiet; or unchanged for `NOISY_MS` (2 s) whatever the gate hears.
  - Words are compared lower case, letters and digits only, so a comma or a capital Apple adds later is no change.
- At a cut, a new request takes the open microphone in the same moment and the old one's final text becomes the phrase. Phrases go out strictly in order. Other cuts: `cap` (`SERVER_CAP_MS` 50 s, `ONDEVICE_CAP_MS` 240 s), `apple`, `error`, `stop`, `route`. A final result is waited for up to `FINAL_WAIT_MS` (1.5 s), or `STOP_FINAL_WAIT_MS` (0.5 s) after a stop. One utterance with nothing heard ends `no-speech` after `NO_SPEECH_MS` (10 s).
- **The energy gate** (`EnergyGate`) calls a buffer voice when channel 0's RMS is above three times the room's noise floor (at least 0.006). The floor is learnt only while quiet: it falls over about `FLOOR_FALL_MS` (500 ms) and rises over about `FLOOR_RISE_MS` (10 s). The gate is trusted after `GATE_TRUST_MS` (500 ms) of room sound. Exact zeros are digital silence, never voice.

The microphone:
- Whenever it runs, it keeps its last `RING_MS` (2 s) of audio in memory. A start's `preroll` feeds the first request from that ring, at most `PREROLL_MAX_MS` (1.5 s) back, so words said between the student's press and the start are kept.
- After the last session it stays open `MIC_LINGER_MS` (4 s), or until a warm's time is up.
- `audiostart` waits for the first buffer that is not digital silence, up to `SOUND_WAIT_MS` (1.5 s); after that it goes anyway and logs "input silent".
- `chooseInput`: the Mac's default input, except that a Bluetooth default gives way to a built in microphone when there is one, so AirPods keep their full quality profile. `ANOTHERNOTES_SPEECH_INPUT=default` keeps the default. If the built in pick gives only digital silence for 1.5 s (a MacBook with its lid shut), the helper goes back to the default (`checkSound`).
- An input change (`AVAudioEngineConfigurationChange`) restarts the microphone and cuts the request in flight with `route`. `{"ev":"route","input","transport","using","usingTransport","changed"}` names the default input and the one used. Transports are `builtin`, `bluetooth`, `usb`, `hdmi`, `displayport`, `airplay`, `thunderbolt`, `virtual`, `aggregate` or `other`.
#### OutputWatch: speakers or headphones
On speakers the microphone hears the tutor's voice. The page uses this verdict to listen only between the tutor's parts on speakers, and to allow listening while the tutor talks on headphones (see Voice).
- `OutputWatch.shared.start()` runs right after the disclaim step, before any command is read. It needs no permission, reads no audio and opens no microphone.
- It adds Core Audio's plain C listener (`AudioObjectAddPropertyListener`) on the system object for the default output device and the device list. On the current default device it listens for the name, `kAudioDevicePropertyDeviceIsAlive` and, when the device has one, the output data source. The device listeners move to each new default. A C function is used because a Swift block listener could never be removed.
- A burst of changes is looked at once, `OUTPUT_SETTLE_MS` (200 ms) after the last. The event is said at start, on any real change, and on the `output` command: `{"ev":"output","name":"…","transport":"…","source":"ispk"|"hdpn"|"","speakers":bool,"changed":bool}`.
- `outputIsSpeakers(name, transport, source)`:
  - `builtin`: headphones when the data source is `hdpn` or the name contains "headphone" (Apple silicon lists its jack as its own device); else speakers.
  - `bluetooth` or `usb`: headphones when the name contains one of `WORN_NAMES` (airpods, beats, headphone, earphone, earbud, buds, headset, wh-1000, wf-1000, quietcomfort) and none of `LOUD_NAMES` (pill, speaker, soundbar, homepod, boom, flip, charge); else speakers.
  - Anything else (HDMI, DisplayPort, AirPlay, Thunderbolt, virtual, aggregate, other): speakers.
  - Anything not known to be headphones counts as speakers, the safe side: a tutor that waits for its own voice to fade, never one that answers itself. A Bluetooth device's class would be surer, but reading it needs Bluetooth permission.
- `speech.ts` keeps the latest route (`lastOutput`). `ipcMain.handle("speech:output")` returns it (or null while none is known), subscribes the asking page, and has the helper say it again. Every route the helper says (at its start, on a change, in answer to an ask) is pushed to the subscribed pages on `speech:output`, only while they show the app's origin. Only the name, transport, data source and verdict reach the page. The log gets a line only when the route is news.

### Self tests: `--selftest` and `--chordtest`
Both run before the parent check, so they work from Terminal without the app. Each `--selftest` prints `ok` or `FAIL` per check and exits 0 or 1; `--chordtest` prints one line per poll and exits 0.
- `tutornote-speech --selftest` covers the pure parts on made up audio and devices: `normalizedWords` and `wordCount`, `cutNow`, `voiceHeard`, the `EnergyGate` (room noise, voice, soft voice in a noisy room, digital silence), the `AudioRing`, `chooseInput`, `clampHints`, `outputIsSpeakers`, `transportName` and `fourCharCode`. It uses no microphone, no Speech framework, no audio device and no permission.
- `tutornote-screen --selftest` covers the thumbnail arithmetic (`bandRows`, `patchCols`, the difference functions, `middleDifference`, `ground`, `isBlank`, `SettleWatch`, `StillWatch`); `judgeTap` on drawn reader pages with bars fading; `scrollExplains` and `keepsBursting`; `isPointingHand`; the words rule on columns of made up words drawn with CoreText and read by Vision (`textSelfTest`); the read's wait for a tap verdict (`holdSelfTest`); `frontWindow`, `identLook` and `identFields` on made up window lists (`identSelfTest`); and the chord's `chordStep` on made up presses at every phase of the polls (`chordSelfTest`). It needs no screen and no permission.
- `tutornote-screen --chordtest` is for a person at the keyboard, in Terminal. For `CHORD_TEST_S` (20 s), every `CHORD_TEST_EVERY_MS` (50 ms), it prints the modifier flags, how long since the last modifier, key, mouse and wheel event, VoiceOver and secure input state, the chord's phase and what the watch would say. It shows no window and asks for nothing. It runs as Terminal does and in a plain loop, so it cannot show App Nap or the app's own permission state.

## The lesson (main process)
The lesson lives in `src/main/screenTeach.ts`. The rule for "is this still the same document?" is in `src/main/docIdentity.ts`, which has no Electron and no other module at run time, so it is tested on its own (`scripts/tests/docIdentity.test.ts`). `src/main/explain.ts` uses `screenText.ts` to count paragraphs before a picked lesson starts; the lesson page lays the page out itself. The content kind, its wording and the screen kind sent to the server are not decided here; they live in the web app and the backend.

### Runs and the Lesson
`runs` counts every start. Each call of `openScreenTeach` takes the next number (`run`), and `closeScreenTeach` bumps it too, so a start still waiting on the helper is dropped. The page gets its run in `ScreenStart` and sends it back with every turn, reread, board state and tap pick. Anything that carries an older run is ignored. One lesson at a time lives in `lesson` (the `Lesson` interface):
- What it reads: `window` (the CGWindowID), `pid`, `app`, `bundle`.
- How it turns: `mode` ("page" or "scroll") and `way` (the first way that moved the window in this run, kept for the rest of it).
- Its latest read: `frame`, `text` (the words' box, for the board), `lines`, `title`, `doc` (`docKeyOf`), and `look` (the latest look, a quick read after a scroll included, with the app's bundle).
- Bookkeeping: `queue` (one turn or read at a time), `waiting` (the AbortController of a wait for the student's own turn), `titles` (other titles this document has shown, the latest `OWN_TITLES` = 8), `top` (the app's front window as the helper last said it: the baseline), `checking`, `switching`, `switchedAt`, `turnedAt`, `moving`.

`doc` is kept up to date on each accurate read and in `checkTitle`, but no decision in the main process reads it today. The lesson window (`ensureWindow`) loads `/dashboard/screen-teach` (`ROUTE`) from the app's origin; how it floats and lets clicks through is under "The windows" below.

### How a lesson starts
Every start ends in `openScreenTeach(read, click, opts)`:
1. It takes a new run and finds the display that holds most of the window read.
2. It gets the Accessibility answer (`canTurn`). With the companion on and an answer under `AX_KEEP_MS` (60 s) old, it uses that one and asks again behind the lesson. Otherwise it waits on `accessibilityAllowed(false)`, which `screen.ts` caps at 3 s.
3. If a newer run began meanwhile, or `opts.still()` now says no, it stops there.
4. It builds the new `Lesson`, aborts the last lesson's wait, clears the app follow timer, and builds `pending` (a `ScreenStart`): `run`, `overlay`, the read in the window's own points (`toLocal`), `click`, `canTurn`, `mode`, and the optional `choice`, `quiet`, `companion`, `ground`, `row`, `stale` and `switched`.
5. It watches the window (`watchWindow`), observes it for new looks when the companion is off (`observeWindows([window])`), registers the lesson's shortcuts and unmutes the page and the board. If the page is ready it sends `screen-teach:start` at once; otherwise the page gets `pending` when it asks (`screen-teach:ready`). A page that never asks within `READY_TIMEOUT_MS` (20 s) fails the lesson.

`mode` is "page" for `PAGE_APPS` (Kindle `com.amazon.Lassen`, Books `com.apple.iBooksX`), and "scroll" for any other app until a turn shows otherwise. The ways in:
- **Pick** (`explain.ts`). The student clicks on a see through layer over every display. `onPick` reads the window under the click (`readWindowAt`, skipping Tutornote's own process) and `blocksOf` counts its paragraphs. With none, the panel says "No text there. Click right on a paragraph." With some, `openScreenTeach(read, at)`. The status panel stays up until `screen-teach-started`.
- **Card** (`companion.ts`). With the companion on, a tap opens a card (Explain, Ask a question). The pick calls `openScreenTeach` with `choice`, `companion: true`, `quiet` after the first lesson of the session, the tapped `row`, and `stale` when the window moved since the tap.
- **Tap on words not read yet.** The page sends `screen-teach:pick-at`. `restartAt` reads the window again in the lesson's queue and starts afresh from that point, quietly with the companion on. It takes the companion's careful read from the tap instead when that read began after the lesson's last turn and no earlier than `TAP_READ_FRESH_MS` (2 s) before the page asked, and the window has not changed since. A read with no lines changes nothing.
- **Shortcuts.** `Control+Alt+E` belongs to `companion.ts` and turns the tutor on or off. While a lesson is on screen, `SHORTCUTS` send `screen-teach:command`: `Control+Alt+Space` (toggle-play), `Control+Alt+Right` (next), `Control+Alt+Left` (prev). `Control+Alt+M` (`TALK_SHORTCUT`) and the talk chord go to the page on channels of their own (see Voice).
- **Another document.** `switchRead` starts a run on the new document with `switched: true` and `quiet: true`, at `firstBodyPoint(read)`.

### How a lesson ends
`endLesson` aborts the wait for the student, clears `lesson` and `pending`, stops the app follow timer, unwatches the window, stops observing it (companion off), unregisters the shortcuts, sends `screen-teach:command` "close", mutes the page and the board, hides the window (unless the companion is on) and folds the board away.
- `closeScreenTeach` (emits `screen-teach-closed`): the page's `screen-teach:close`; `explain.ts` `closeAll`; the companion turning off (`companion.ts` `turnOff`); `CmdOrCtrl+W` while the lesson window has the keys (`menu.ts`); the lesson window closed; signing out (`main-signed-out`, which also drops the window). And three switch cases: no words at all in the other document; the lesson's window closed while a switch waited for it to come back; the lesson's own window unreadable for a reason other than leaving the screen.
- `failLesson` (emits `screen-teach-failed` with the words for the panel): the page never said it was ready within `READY_TIMEOUT_MS`, the page did not load, or its renderer stopped.

### Turns
The page asks with `screen-teach:turn` `{run, dir, scrollBy, pages, at, how, unlessMoved}`. `turnRequestOf` checks every field (a scroll of 20,000 points at most, 1 to 50 pages). A turn for another run answers "stale". Each new request aborts a wait for the student that is still going, then runs in the lesson's queue (`queued`), so turns and rereads never overlap.
- **auto** needs Accessibility (else "no_access"). It tries ways in order until one changes the window: the kept `way` first, with `TURN_TIMEOUT_MS` (4 s), then the others with `TRY_TIMEOUT_MS` (2.5 s). Page mode tries the right arrow key, then Page Down. Scroll mode tries a scroll (`scrollBy`, or `DEFAULT_SCROLL`, 600 points), then Page Down, then the right arrow key. A turn of several pages adds `KEY_GAP_MS` (250 ms) to the timeout for each press after the first. A key that works switches the lesson to page mode.
- **manual** posts nothing and waits up to `MANUAL_WAIT_MS` (180 s) for the student to turn or scroll. No change in time answers "end".
- `unlessMoved`, on the first way only: if the window moved since its last read, nothing is posted and that move is the turn ("manual").
- Nothing moved: "stuck" when a key was pressed while the app was not in front, or when no way had worked yet in this run; otherwise "end".
- While a scroll is posted (`scrolling`), the lesson window and the board window let every click through (`applyMouse`), so the wheel reaches the app being read.
- After a move: an accurate `readWindow`, `noteRead`, the `screen-teach-read` event for `companion.ts`, and the read sent back in the page's own points.
- An auto turn sets `Lesson.moving` while it runs (`checkTitle` waits for it). Every turn sets `turnedAt` when it ends.

### Stale answers and rereads
Another document makes old answers unsafe. `turn` runs a `stale()` test after every await: the lesson changed, the run is not the request's, the lesson's own window is gone, a switch is on (`switching`), or a switch began after the turn started (`switchedAt >= started`). Any of these answers `{ok: false, reason: "stale"}`, and the read it took is never kept as the lesson's (it may hold the other document's title). `switchedAt` is not cleared when a switch is cancelled, so a read that began before even a flick stays stale. `screen-teach:reread` `(run, {fast})` reads the window again in the queue. It returns null while a switch is on, or if one began during the read.
- Accurate: `noteRead` (frame, words box, lines, look, title, doc; the board may move) and the `screen-teach-read` event.
- Fast (the page's check after a scroll): it updates only `Lesson.look`, and only when the title is unchanged or says nothing (`titleChange` "none" or "weak"). A quick look taken just as another title came up would otherwise pass the other document off as the lesson's own.

`restartAt` drops its read the same way, and logs "the read after a tap left out: another document came up meanwhile".

### Taps, scrolls and new looks
- `onTap` (the helper's `tap` on the lesson's window). Ignored while aside or hidden, on the page's own controls (`pressWasThePage`, `interactive`), on the board or where the board was within the last `BOARD_LEFT_MS` (1 s), and on the main window. A plain click that did something in the app (`acted` without Option), or a double click (`words` "select"), is left to the app, except where `selectionKept` says the student is pointing at a word (see "The companion"): that goes to the page as a lesson tap with `acted: false`. A tap whose words say the title changed starts a "tap" switch, but only when the helper says nothing of the window's document (`lastIdent` is for another window).
- `onScroll` sends `screen-teach:scroll {run, dy}`, except during the lesson's own turn, while aside, for a sideways swipe, and over the board or the main window. It also wakes a switch that waits for words in the scrolled window.
- `onLessonChanged` (the helper's `changed`) sends `screen-teach:changed {run, window}` for every lesson, with the companion on or off. During a switch it sends nothing (that new look is the next run's); it only wakes a switch that waits for words in that window.

### Aside and back
The helper says which app is in front (`front`). `onFront(pid)`:
- Tutornote itself in front says nothing by itself; which of its windows takes the keys decides (`onOwnFocus`). The lesson window or the board change nothing. The main window is judged `MAIN_FOCUS_SETTLE_MS` (120 ms) later by `judgeMain`: on any other tab the lesson steps aside; on its Board tab the lesson goes on, unless the window covers what is read. Any other Tutornote window steps aside.
- Any other app: `stepAside(pid !== lesson.pid)`.

`stepAside(true)` sets `aside` and sends `screen-teach:command` "pause" and `screen-teach:present` false. With the companion on, the window stays and the page hides its marks (`screen-teach:aside` true); without it, the window hides. Back in the lesson's app: `screen-teach:present` true, then either `screen-teach:aside` false (companion on: the page reads the window again before it plays on) or `showInactive` and "resume". The board follows both ways through `syncBoard`.

### The board follows the lesson
`syncBoard` is the one place the board is shown, hidden or moved. The board is up only while every condition holds, and the first that fails is logged as "board hidden: <why>" or "board folded: <why>". In order: "the lesson ended" and "the lesson's page is not ready" (the board folds away, its tab and its window); "the lesson is not on screen"; "another document is on screen" (`Lesson.switching` is set); "the student is in another app" (`aside`); "nothing on it" (the page's last `screen-teach:board` for this run said no, or was for another run); "the student has just closed it" (`closeHold`, `CLOSE_HOLD_MS`, 1.2 s). Where it goes is decided once per run at the run's first drawing (`decide`, `boardHost.ts` `boardPlaceFor`; see "The board"). Every new run, a switched one included, sets `boardWanted` to false, so the new document's board comes up only once its page draws something.

### Another document
A lesson knows the window it reads, not the document in it. A Chrome tab switch keeps the window id and changes only its title. An app coming back to the front does not say which of its windows the student came back to. So the helper reports which document the watched window shows (`ident`, under "Native helpers"), and `docIdentity.ts` decides by the title. Why the title and not the words: the comments in `docIdentity.ts` give the measured shares of rows found again. The same look read twice: 0.73 to 1.0. Another document: 0.0. A far part of the same document: 0.02. The next slide: 0.04 to 0.10. The words cannot tell another document from a far part of the same one; they only confirm a title that changed by itself. The four reasons for a switch (`SwitchWhy`):
- "title": another title in the lesson's window (a browser tab).
- "window": another window of the lesson's app in front (Preview opens each document in a window of its own; native tabs).
- "app": the student stayed `APP_FOLLOW_MS` in another app, on a reading window there.
- "tap": a tap whose verdict saw the title change, for a helper that sends no ident.
#### onIdent
1. Keeps the ident as `lastIdent`, and ignores it unless it is for the lesson's window.
2. Before the page is ready, it only notes `identLate`. When the page says `screen-teach:started`, the last ident is judged then, since the helper says nothing again until something changes.
3. Moves the baseline `Lesson.top` when the front window is the lesson's own or another document's (`anotherWindow`). A popup or a sheet moves nothing.
4. Asks `identVerdict` (with the `top` from before this ident) and acts: "cancel" calls `cancelSwitch` with "back", "switch" calls `beginSwitch`, "check" calls `checkTitle`, "reread" calls `readAgain`, "retarget" calls `retargetSwitch`.
5. Wakes a switch waiting for "secure" when `secure` is false, and one waiting for "screen" when the window is on screen again. For a switch waiting for "screen", a window off the screen with no title was closed: the lesson ends.
6. Calls `maybeFollowApp`.
#### docIdentity.ts, piece by piece
- **`titleSignature(title, app)`** is a title as the rule compares it. `plainTitle`: NFKC, lower case, runs of spaces made one; a leading counter in brackets taken off (up to four digits, with an optional plus); at the end, repeated until nothing changes, the app's name after a dash, a bar or a middle dot, and an "edited" mark after one of those or after a space; "page N of M", "slide N" and "slide N of M" taken off wherever they are, with the empty brackets and stray separators they leave; "" when nothing is left or the title is only the app's name. Then every run of digits becomes "#".
- **`titleChange(was, now, app)`** returns "weak" (either title says nothing; this never starts a switch), "none" (the same title once counters, the app's name and the rest are off), "digits" (only numbers changed: a numbered lecture file to the next one, or a page that numbers itself) or "letters" (another title).
- **`bodyRows(read)`** gives the page's own rows. A line counts when its centre lies between `BODY_TOP` (0.15) of the window's height from the top and `BODY_FOOT` (0.08) from the foot; it is not one of a browser's own bars (`browserBars`); its key (`keyOf`: lower case, letters and digits, single spaces) has at least `BODY_LETTERS` (4) letters; and that key appears only once in the read (a key seen twice counts for neither).
- **`browserBars(read)`** finds a browser's own bars by what they hold, not by their size. The band alone fails in a short window: the bookmarks and a PDF viewer's toolbar fall inside it. It works only for a browser's bundle (`BROWSER_BUNDLES`, plus Chrome and Edge in any channel by `BROWSER_BUNDLE_PREFIXES`; a test keeps this list equal to `companionPlace.ts`'s). It looks in the top `BAR_BAND` (0.3) of the window:
  - The address row: the first line from the top that holds a web address or a local path (`addressPiece`: three words at most; a scheme or "www", a known domain ending, a local path, or a run of at least `ADDRESS_RUN` (24) characters with a dot or a slash).
  - A viewer's toolbar: a page counter (`counterPiece`) on a row of at least `BAR_PIECES` (3) separate pieces, each `BAR_WORDS` (12) words at most, spread over at least `BAR_SPREAD` (0.5) of the window's width, below the address row.
  - The bars end at the foot of the lowest toolbar. With an address row alone, they go on down through the rows of controls under it (the bookmarks), each within `BAR_STEP` (2.5) of the last one's heights, and stop at a row that is columned like a table.
  - They never run past a heading of the page: a line with three letters or more that is `BAR_TALL` (1.8) times as tall.
  - Every line whose middle is above that end is a bar.
  - Arc keeps its tabs and its address down a sidebar: the strip in the left `SIDEBAR` (0.3) of the window, its address starting within `SIDEBAR_LEFT` (0.05), reaching `SIDEBAR_STEP` (2) address heights past the address's end. That strip is all bars; over the page beside it, only a viewer's toolbar is.
- **`sameLook(before, after)`** is the share of `after`'s body rows whose keys are in `before`; 0 when `after` has none.
- **`sameDocument(befores, after)`** takes the best `sameLook` over the lesson's looks (its last accurate read and its latest look). Both must hold: the share is at least `SAME_LOOK_SHARE` (0.6), and the rows found (share times rows, rounded) are at least `SAME_LOOK_FOUND` (2). One row alone, such as a bookmarks row caught in a short window's band over a page with nothing of its own yet, cannot tell. It also returns `share` and `rows`, for the log.
- **`docKeyOf(read)`** is `bundle|window|titleSignature`: one document's key.
- **`firstBodyPoint(read)`** is where a switched run begins: the centre of the first body row (on a slide, normally its title); else the topmost line below `BODY_TOP` that is not a browser bar; else the window's centre. Never a tab or the address row, where a click would land on the browser.
- **`documentSized(topFrame, lessonFrame)`**: at least `SWITCH_MIN_W` by `SWITCH_MIN_H` (320 by 240 points), and at least `SWITCH_MIN_SHARE` (0.25) of the lesson window's area. No frame said counts as document sized.
- **`sheetOf(topFrame, lessonFrame)`**: the front window hangs from the lesson's window as a sheet does (Print, Save): inside its frame (1 point of slack), smaller each way by more than 2 points, its middle within `SHEET_CENTRE` (2 points) of the window's middle side to side, its top within `SHEET_TOP` (100 points) below the window's top.
- **`anotherWindow(lesson, ident)`** is true when there is a front window, it is not the lesson's, its title says something, it is document sized, and it is no sheet.
#### identVerdict
`identVerdict(lesson, ident)` returns one act, or null. With no switch going on:
- "switch" (why "window"): another document's window is in front, a baseline `top` was already said in this run, and the front window is not that baseline. So the window that was in front as the lesson began is no switch.
- Nothing while the app is behind, the window is off the screen, or the title is one of `Lesson.titles`. A title that changes out of sight is judged when the student comes back.
- "switch" (why "title") for "letters"; "check" for "digits".

With a switch going on:
- "cancel": a "title" or "tap" switch whose window shows the lesson's own title again (or a known one), with no other document's window in front; or a "window" switch with the lesson's window in front again, on screen, with its own title. Digits alone are no way back: a different number is another file.
- "retarget": only for a switch left waiting, with the lesson's app in front, and not an "app" switch. Another document's window in front that it is not reading gives why "window". The lesson's own window in front, on screen, showing another title while the switch waited on another window gives why "title".
- "reread": a switch left waiting, with the lesson's app in front, whose window's title changed (letters or digits) since it began to wait. For a "window" switch that is the front window's title; for a tab, the lesson window's title. "app" switches are not judged here.
#### beginSwitch
`beginSwitch(current, why, to)` runs once per switch. It does nothing if a switch is already on, the lesson has changed, or the page is not ready. If the page has not said it hears switches, it logs that and returns, and the lesson goes on as before. Otherwise it:
- sets `Lesson.switching` (`at`, `why`, `target`, `pid`, `app`) and `switchedAt`;
- aborts any wait for the student's turn, and the app follow timer;
- sends `screen-teach:switching {run, on: true, why}` (the page stops; see "The page and the server");
- runs `syncBoard` (the board goes: "another document is on screen");
- calls `readSwitch`, which runs `switchRead` and cancels the switch ("failed") if it throws.
#### switchRead
It reads the other document outside the lesson's queue, and at every step stops as soon as the switch is no longer this one (`ours()`).
1. **Still wait.** `turnWindow` with `how: "manual"`, `still: true`, `timeoutMs: SWITCH_SETTLE_MS` (1.5 s), `unlessMoved: true` (for a helper too old to know `still`). It posts nothing. Errors are ignored here; the read reports them.
2. **Read** (`readOnce`). With secure input on (from `lastIdent`), nothing is read: wait "secure". Otherwise an accurate `readWindow`. On an error: another window that could not be read, or the lesson's own window gone with a helper that sends no ident, cancels ("failed"); the lesson's own window off the screen (`window_gone`, `no_window`) waits "screen"; the lesson's own window unreadable for another reason ends the lesson.
3. **Retries.** While the read has fewer than `SWITCH_MIN_ROWS` (3) body rows, up to `SWITCH_RETRIES` (2) more reads, `SWITCH_RETRY_MS` (300 ms) apart.
4. **Empty page.** While it has no body rows at all, it reads again every `SWITCH_EMPTY_RETRY_MS` (1 s), until `SWITCH_EMPTY_GIVE_UP_MS` (8 s) after `since` (the switch's start, or the last `readAgain`).
5. **Log** the read: the time since the switch was seen, lines, rows, words, tries, the still wait, the text time, and, for the lesson's own window, the share of rows found again.
6. **Gone on** (`goneOnTo`): if the helper's last word says the student has moved on to another document of the lesson's app, the switch goes there and reads again.
7. **No lines at all:** the lesson ends.
8. **Same look** (the lesson's own window only, `sameDocument` against its last read and its latest look): the title changed by itself. The lesson takes the read (`noteRead`), keeps its old title as its own (`keepTitle`), and cancels with "same".
9. **Words threshold.** In a browser (`isBrowserApp`) it waits for "words" when the page has no body rows, or fewer than `SWITCH_MIN_WORDS` (25) words in them and it is not a document page. A document page is a reading window (a reader app, or a browser whose title ends in ".pdf"), or a title that matches `DOCUMENT_TITLE`: the extension pdf, ppt, pptx, key, doc, docx, xls, xlsx, odp, ods, odt or epub, or the names Google Slides, Google Docs, Google Sheets, PowerPoint, Keynote, Word, Excel, Canva or Prezi. A deck's title slide may say five words. The title is matched, never logged. Other apps have no words threshold.
10. **Student away** (an app other than the one read is in front, or Tutornote's own windows while the lesson is aside): wait "student".
11. **New run.** It notes `switchedRun`, then calls `openScreenTeach(read, firstBodyPoint(read), {companion, quiet: true, switched: true, still})`. `still` is asked just before the run starts, after the Accessibility wait: the switch must still be this one, and the student must not be away. If they left just then, wait "student".
#### Waiting, and what wakes a switch
`waitSwitch(current, mine, what, title, said)` leaves the lesson stopped with nothing started. It keeps the other window's title at that moment (`waiting`, which `identVerdict` compares against) and the reason (`waitingFor`), logs `said`, sends `screen-teach:switching {on: true, why: "wait <what>"}`, updates the observed windows (`observeSwitch`), and judges the helper's last ident again (or calls `maybeFollowApp`).

| Reason | Set when | Woken by |
|---|---|---|
| `words` | a browser page with nothing, or too little, of its own | the waited window's title changing (ident "reread"); a new look of that window (`onLessonChanged`; with the companion off, `observeSwitch` adds that window to the observed ones); a scroll of it, `SWITCH_SCROLL_MS` (400 ms) after the scroll stops |
| `student` | the student went on to another app during the read | the student back in the app of the window being read (`onFront`) |
| `secure` | secure input is on | an ident with `secure` false |
| `screen` | the lesson's own window is off the screen | an ident with that window on screen; off screen with no title means closed, and the lesson ends |

Any waiting switch also moves when the student goes on: to another document of the lesson's app (`retargetSwitch`), or to another app's reading window after `APP_FOLLOW_MS` (`maybeFollowApp`). A flick back to the lesson's own document still cancels it.
- `readAgain(current, said)` works only on a waiting switch: it clears `waiting` and `waitingFor`, logs, sends `{on: true, why: "reading"}`, and calls `readSwitch` with a fresh `since`, so the 8 s empty page limit starts again.
- `retargetSwitch(current, why, target)` points the waiting switch at the new window (`why` "title" or "window", with the lesson's app and pid) and calls `readAgain`.
- `switchBack(current, from)` handles the student coming back to the lesson's app from an "app" switch that had begun in that app (`Switching.from`). It replaces the switch with a new one on `from`'s window (so a read of the other app's window still going is dropped), sends "reading", and reads that window again.
#### cancelSwitch
`cancelSwitch(current, code, said)` ends a switch with no new run: `switching` goes back to null, the page hears `screen-teach:switching {on: false, why: code}`, the observed windows go back to the lesson's own, and `syncBoard` brings the board back. `switchedAt` stays, so reads that began before the switch are still stale.
- "back": `identVerdict` said "cancel" (a flick), or the student came back to the lesson's app during an "app" switch that had no `from`.
- "same": `switchRead` found the same look in the lesson's own window.
- "failed": the read threw, or the other window (or the lesson's own, with a helper that sends no ident) could not be read.
#### checkTitle: only the numbers changed
A "digits" change stops nothing. `checkTitle(current, title)` runs once per title; never while secure input is on (a later ident with it off asks again); never for a page that does not hear switches. It waits for the lesson's own auto turn if one is going (`Lesson.moving`), since a title that numbers the pages changes with the turn. It takes a fast read outside the queue, with the board left up and the page told nothing, and drops the result if the lesson changed, a switch began, or the title is back to "none". Then `sameDocument` against the last accurate read and the latest look: the same look logs that, takes the new title (and `doc`) if nothing else has updated it, and keeps the old one with `keepTitle`; another look calls `beginSwitch` with "title". `keepTitle` adds the old title to `Lesson.titles` (the latest 8). A title on that list counts as the lesson's own, so a page whose title flashes a notice and goes back is not two documents.
#### Following another reading app
`onFront` calls `followApp(pid)`. For an app other than the lesson's and Tutornote, it starts a timer of `APP_FOLLOW_MS` (1.5 s). `maybeFollowApp` runs when the timer fires and after every ident, so it also catches a reading window the student opens later in the same stay. It follows when:
- no switch is being read (a waiting one may be taken over), the page is ready, and that app has been in front for the full 1.5 s;
- `lastIdent.other` belongs to that app, is not a private app's (`isPrivateApp`), and is a reading window: a reader (Kindle, Books, Preview) or a browser window whose title ends in ".pdf";
- it has a title, and is at least 320 by 240 points.

Then it calls `beginSwitch` with "app". If a switch is waiting, it is taken there instead: its old target is kept as `from` (unless it was already an "app" switch), and it reads again. Any other window in another app is a plain step aside, as before.
#### The handshake: `screen-teach:hears-switching`
A page older than round 4 would neither stop for a switch nor hold a switched run until Play. So the preload's `onSwitching` sends `screen-teach:hears-switching` as it starts to listen. `screenTeach.ts` sets `pageHearsSwitching` when that comes from the lesson's own page, and clears it on every navigation of the page (`did-navigate`). Without it, `beginSwitch` logs "but the lesson page does not hear of one: rebuild the renderer" and does nothing, `checkTitle` does nothing, and no `switched` start is ever sent. What the page hears on `screen-teach:switching` (`{run, on, why}`):
- `on: true` with `why` "title", "window", "app" or "tap": another document seen and being read.
- `on: true` with "wait words", "wait student", "wait secure" or "wait screen": waiting, nothing started; "reading": being read again.
- `on: false` with "back", "same" or "failed": no new run; the lesson goes on.
- A new run comes as `screen-teach:start` with `switched: true` and `quiet: true`.
#### Log lines
They all start with `[screen-teach]` and carry the run, the app's name, the why, counts, times and percentages. None carries a window title or the page's words.
- `run N: <app> (<bundle>), <mode>, turning allowed, ..., switched`: a new run.
- `run N: another document in <app> (<why>), reading it`, or `..., but the lesson page does not hear of one: rebuild the renderer`.
- `run N: the other document read <ms> ms after it was seen: <L> lines (<R> rows, <W> words of the page's own), read <K> times, still after <ms> ms (not still in time), text <ms> ms, <P>% of its rows the same as before` (each part only when it applies).
- `run N: <reason>: the lesson waits`, `run N: <reason>: reading the other document again`, `run N: <reason>: the lesson goes on` and `run N: <reason>: the lesson ends`, where the reason is a fixed phrase such as "secure input is on", "a new look", "the same document after all" or "no words in the other document", some with the app's name or counts added (for example "little to read in the other document (<R> rows, <W> words)").
- `run N: the title's numbers changed, <P>% of its <R> rows the same: the same document` (or ": another document").
- `run N ready <ms> ms after the switch was seen`: the whole switch, from the moment it was seen to the new lesson being up.
- Two warnings carry an error's code or message: "reading the other document failed: <message>" and "a look at the window's new title failed: <code>".
#### Timeline: a Chrome tab switch
The student clicks another tab in the Chrome window being taught. The window keeps its id and changes its title. The times come from the constants; they were not measured.

| Step | When | What happens |
|---|---|---|
| 1 | 0 | The tab changes, and Chrome retitles the window. |
| 2 | within `IDENT_MS`, 150 ms (plus up to 30 ms leeway) | The helper's ident tick sees the new title and sends `ident`. |
| 3 | at once | `onIdent`: the app is in front and the window on screen; `titleChange` says "letters", so `identVerdict` says "switch" with why "title". (If only digits changed, `checkTitle` takes a fast read first, and only a different look switches.) |
| 4 | at once | `beginSwitch`: the page hears `{on: true, why: "title"}` and stops; the board hides; the log says "another document in <app> (title), reading it". |
| 5 | at least 100 ms, at most `SWITCH_SETTLE_MS` (1,500 ms) | The still wait: a thumbnail every `POLL_MS` (100 ms) until two in a row agree. |
| 6 | next | An accurate read of the window (its OCR time is logged as "text N ms"). |
| 7 | up to 2 more reads, 300 ms apart | While it has fewer than 3 body rows. |
| 8 | every 1,000 ms, until 8,000 ms after step 4 | While it has no body rows (a page still loading). Lines but no rows by then: decided as it is. No lines at all: the lesson ends. |
| 9 | next | Under 25 words of its own and not a document page (a new tab, a search page): the switch waits for "words" until a new title, a new look or a scroll. |
| 10 | next | `openScreenTeach(..., switched)` at `firstBodyPoint`. The Accessibility answer is kept if the companion is on and the last one is under 60 s old; otherwise it is asked (3 s at most). |
| 11 | next | The page gets `screen-teach:start` with `switched: true`, starts quietly at the first words, plays if the last run was playing, and says `screen-teach:started`. The log says "run N ready X ms after the switch was seen". |

A flick (another tab and straight back) before step 11 cancels with "back": the window shows the lesson's own title again, `identVerdict` says "cancel", and the lesson plays on.

## Windows, companion, board and the bridge
This part is the shell around the screen tutor: the windows, how a launch shows the main window, the companion (the tutor that follows the cursor over other apps), where the lesson's board lives, the API proxy, and the preload bridge the web page talks through.

### The windows
| Window | Made in | What it is | Keys and clicks | Level |
|---|---|---|---|---|
| Main window | `windows.ts` `createMainWindow` | A `BrowserWindow` with no title bar (`titleBarStyle: "hiddenInset"`, traffic lights at x 16, y 12 in the tab bar's row). At least 900 by 600. Made hidden and shown by the launch reveal. Size and place kept in `window-state.json` (`store.ts`). | An ordinary window: it activates Tutornote and takes the keys. | normal |
| Tab bar | `windows.ts`, a `WebContentsView` in the main window | `static/toolbar.html` with `src/preload/toolbar.ts` (`window.tabbar`). `TOOLBAR_HEIGHT` 38. Added again after every page so it stays on top. | After a click on it the keys go back to the page (`focusActive`, 30 ms later). | in the main window |
| Pages | `windows.ts` `newPage` | `WebContentsView`s of the web app, each in a role: `home`, `note`, `spare` or `closing`. Preload `src/preload/index.ts`. | | in the main window |
| Loader | `windows.ts` `createSplash` | A 420 by 440 frameless `BrowserWindow` showing `static/loading.html`. Only on a slow start. | | normal |
| Lesson window | `screenTeach.ts` `ensureWindow` | `type: "panel"`, frameless, transparent, no shadow, `skipTaskbar`, over the work area of one display. Loads `/dashboard/screen-teach` with `--anothernotes-screen-teach=1`. Kept hidden between lessons, so the next start is quick. Its zoom is isolated from the tabs. | Click through by default (`setIgnoreMouseEvents(true, { forward: true })`). For a picked lesson it is focusable, so a click into it gives it the keys; with the companion on, only when the page asks. | `floating`, 1 |
| Board window | `screenTeach.ts` `adoptBoard` | A `BaseWindow` holding, in a `WebContentsView`, the page the lesson page opened with `window.open`. Real traffic lights in the board's 38 pt head. Resizable and zoomable; no minimize, no full screen. | Shown with `showInactive`, so the app being read stays in front. First click counts (`acceptFirstMouse`). Takes its own clicks, except while a scroll is posted. | `floating`, 0 |
| Blob | `companion.ts` `ensureBlob` | `type: "panel"`, frameless, transparent, 64 points (`BLOB_SIZE`). `static/blob.html` with `src/preload/blob.ts` (`window.screenBlob`). | `focusable: false`: never takes the keys, and a click never brings Tutornote forward. Moved by the main process, not by a drag region. | `floating`, 2 |
| Explain on screen panel | `explain.ts` `ensurePanel` | `static/board.html` with `src/preload/board.ts` (`window.screenTutor`): a small status panel shown before a picked lesson is up. | `skipTaskbar`, shown with `showInactive`. | `floating`, 1 |
| Pick layers | `explain.ts` `overlayFor` | One transparent, `focusable: false` window per display, `static/overlay.html` with `src/preload/overlay.ts` (`window.screenOverlay`). | Click through, except while the student picks. | `floating` |

Note the names: `static/board.html` is the Explain on screen status panel. The lesson's board is the web page's own popup inside the board window. Common to all of them:
- Every window runs with `contextIsolation`, `sandbox` and no `nodeIntegration`.
- The lesson window, the board, the blob, the panel and the pick layers refuse navigation. The lesson window allows one popup, the board, under its frame name (`adoptBoard`), and refuses a second. A link on the board opens in the browser; the others open nothing.
- Every window but the main window and the loader floats over every Space, a full screen app's too (`setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })`).
- Order within the `floating` level: the blob (2) over the lesson window (1) over the board (0).
- **Non activating.** The blob and the lesson window are `type: "panel"`. The code comments say why: on Electron 44, `focusable: false` alone only keeps a window from taking the keys, and a click on it still brings Tutornote to the front. A panel does not, so the student's keys stay with the app being read.

Clicks in the lesson window (`screenTeach.ts` `applyMouse`) reach the page only where it says it is interactive (`screen-teach:interactive`) or over the companion's card. The card's box comes from the page (`screen-teach:card-box`); the main process checks the cursor against it every `CARD_WATCH_MS` (16 ms), with `CARD_SLACK` 4 points, so the card takes clicks before the page says so itself. No clicks at all while a scroll is being posted. Keys in the lesson window: with the companion on it is made not focusable (`showCompanionOverlay`). When the page has a text field in use it sends `screen-teach:want-keys` true; the window becomes focusable and takes focus without bringing Tutornote forward. On false it blurs, and the keys go back to the app in front.

### Launch
`index.ts`:
- One running copy (`requestSingleInstanceLock`).
- A `launched` flag is set once, right after the first `createMainWindow`, and never reset. Before it, a second launch only queues its links and the Dock's `activate` does nothing, so a slow start never makes a second window. After it, `activate` calls `windows.ts` `showMainWindow`.
- Start order in `whenReady`: the bundled renderer, permissions (for the app's own origin only: the microphone but never video, clipboard writes, full screen and notifications), the client header, the auth handlers, `installSignIn`, `installSpeech`, `installExplain`, `installScreenTeach`, `installCompanion`, `installMenu`, then `createMainWindow("app")` or `createMainWindow("signin")` by whether a session cookie exists, then `installUpdater` and the queued links.

Before round 3 the loader played an intro and the window waited for it. That is gone. `launchReveal.ts` holds the rule as a pure step function (`launchStep`), tested on its own:
- State: `revealed`, and the loader as `none`, `making`, `up` or `gone`. Events: `delay`, `splash-ready`, `loaded`, `asked`, `max`, `shown`. Actions: `make-splash`, `show-splash`, `close-splash`, `show-window`.
- `SPLASH_DELAY_MS` 1000: the loader is made only if the window is still not up 1 s after it was made.
- `SPLASH_MAX_MS` 15000: the window shows by then, whatever its page is doing.
- `show-window` always comes before `close-splash`, so there is no moment with neither on screen. Once the window is shown, no loader is made.

How `windows.ts` drives it:
- Events: `loaded` is the home page's first `did-finish-load` (the web app, the sign-in screen or the offline page); `asked` is the Dock (`showMainWindow`) or the student's Open in Tutornote (`bringMainForward`), through `revealMain`; `shown` is the window's `show` event, however it was shown (a link, a lesson). At `SPLASH_DELAY_MS` it sends `shown` if the window is already visible, else `delay`.
- `show-window` maximizes the window if it was saved maximized, then shows and focuses it. It is not maximized earlier, because `maximize()` shows a window at once.
- The loader fades in (`fadeInSplash`): `setOpacity` with an ease out over `SPLASH_FADE_MS` (150 ms), on a 16 ms timer.
- The window's size and place are not saved before the reveal (`scheduleSave` and the `close` handler check `launch.revealed`), so quitting during a slow start does not lose a saved maximized state.
- `static/loading.html` has no script (its CSP sets `script-src 'none'`), fetches nothing, and holds still under reduced motion.

### The companion
`companion.ts` runs it; the rules that need no Electron are in `companionPlace.ts`. On and off:
- The tab bar's button (`tabs:command` `explain`, which becomes appEvents `companion-blob`) and `Control+Alt+E` (`SHORTCUT`, a global shortcut) turn the tutor on or off, showing the blob first when it is hidden.
- Its place is kept per display in `companion-blob.json` (`store.ts`). The first place is the bottom right of the work area (`defaultBlobPlace`, 24 points in). `clampBlobPlace` keeps it whole on the work area, also after a display goes or changes (`reclampBlob`).
- Drag: the page reports press and release; the main process moves the window after the cursor every `FRAME_MS` (16 ms). A release that moved less than `CLICK_TRAVEL` (4 points) is a click and toggles the tutor. On hover the window widens by `LABEL_WIDTH` (228) for its label. A right click offers Hide the tutor, and Turn off while the tutor is on.
- `turnOn` first checks Screen Recording (`ensureScreenReading("companion")`); without it the blob shows its blocked look. Then the lesson window comes up as the companion's overlay on the cursor's display (or the lesson's), the first time tip shows once (`companionTipped`), and the helper is told the companion is on (`companionWatch`) with Tutornote's own window ids (`stopIds`), `PRIVATE_APPS` and `READER_APPS`.
- While the page has a dock of its own (`screen-teach:companion-dock`), the blob fades out over `BLOB_FADE_MS` (120 ms) and hides (`blobUp`). The first check is `BLOB_HANDOFF_MS` (180 ms) after the tutor hops out. A page without a dock keeps the blob up as the way to turn it off.
- `turnOff`: the tutor flies home to the blob (`screen-teach:companion` with `on: false` and `to`), any lesson closes, and the overlay hides after `HOME_MS` (320 ms).
- The dock's pause (`screen-teach:companion-hold`) holds everything: no glances, no careful reads, and the helper hears the companion is off. The lesson's own window is still observed.

Glances (fast reads, on this Mac):
- The helper's `over` says which window the cursor is over (only when that changes). `DWELL_MS` (120 ms) after the cursor comes over a window without a fresh glance, if it is still over it, the window is read fast (`glance`), one read per window at a time.
- A read with no lines never replaces one with lines. It is tried again `GLANCE_AGAIN_MS` (300 ms) later; if that finds none too, it is sent with `empty` so the page lets it replace the old one.
- After a scroll, a new glance `AFTER_SCROLL_MS` (250 ms) later. After a new look (`changed`), at most one every `CHANGED_GLANCE_MS` (2000 ms).
- The lesson's own accurate reads become its window's glance (appEvents `screen-teach-read`).
- The page gets them as `screen-teach:glance` and `screen-teach:over`. Nothing read leaves the Mac until the student picks on the card.

Cards:
- On the helper's `release` (a tap ended, not yet judged), `tapRoute` decides: `lesson`, `page`, `private`, `acted`, `editor` or `card`. Unless it is the page's own control or a plain click in an editor (`EDITOR_APPS`, `EDITOR_PREFIXES`; an Option click is always the tutor's), the page hears `screen-teach:companion-release` with the release's `id`, and may paint the card in that frame.
- A careful read of that window starts at once (`startCarefulRead`), except for a private window, a double click, or a tap on lesson words already read. Up to `CAREFUL_KEPT` (4) are kept by release id.
- On the helper's verdict (`tap`): a click its app used (`acted`) or a double click that selected words (`select`) withdraws the card (`screen-teach:companion-withdraw` with `why` set to the verdict's words or `acted`) and drops its careful read. Otherwise, where a card is wanted, the page hears `screen-teach:companion-tap` (a card that waited for the verdict, on a margin or under a pointing hand, opens now).
- A new look within `TAP_SETTLE_MS` (1500 ms) of the card's tap is that tap's own doing: the page is not told of it, and the card stays.
- The pick (`screen-teach:explain-at`, `explainAt`) starts the lesson from the tap's careful read, else the window's latest one, else a read now. It is marked `stale` if the window moved since the tap. The lesson window moves to the read window's display, and later lessons of one session start quietly.

**The reader double click rule.** `selectionKept({ words, bundle, title })` is true when the verdict's words are `select` and either the app is a reader (`READER_APPS`: both Kindle bundle ids, Books, Preview), or it is a browser (`BROWSER_APPS`, or Chrome and Edge in any channel by `BROWSER_PREFIXES`) and the window's title ends in `.pdf` (any case, trimmed). In `onTap` such a tap counts as not acted: the card stays (or opens there) and its careful read is kept. The log says the selection was kept, with no words. The title used is the window's glance title, else the title from the cursor's last `over`. `screenTeach.ts` uses the same rule for a tap on the lesson's own window. Anywhere else (an editor, a web page, any other app) a double click still withdraws the card.

**The ident listener.** The helper sends `ident` only while a lesson watches a window, and `companion.ts` acts on it only while the companion is on. `onIdent` takes the titles it carries for the lesson's window, its app's front window (`top`, `topTitle`) and another app's front window (`other`), and calls `retitled` for each:
- For a window known here (a glance of it, or its app from `over`), the new title is stored. If `titleChange` says `letters`, the window shows another document: its glance and the careful reads taken for taps there go stale (`markReadStale`).
- For a window that is not the lesson's, every release heard on it gets `screen-teach:companion-withdraw` with `why: "another document"`, and the window is glanced at again if the cursor is over it. Per the code comment, the page may keep a card that is asking; that is the web app's decision.
- The lesson's own window only goes stale here. What the lesson does about another document there is `screenTeach.ts` (`beginSwitch`).
- A title that changed only in its digits (`digits`) or says too little (`weak`) is not another document here.
- Titles are never logged; the log line names only the window number.

New looks: `onChanged` returns early for the lesson's window (`screenTeach.ts` sends that one). For any other window the companion sends `screen-teach:changed` with `run: 0`. Tap recordings: with `TUTORNOTE_TAP_LOG=1` in the environment, each verdict on a window that is not private is written to the app's data folder under `taps/` (the newest `TAPS_KEPT`, 200, are kept). Off by default, because the files hold the words read.

### The board
The board is one page, the popup the lesson page opened, that moves between two homes: the floating board window, or a tab of the main window (`BOARD_TAB_ID` -1, the second tab, right after Home). Where it goes (`boardHost.ts`, pure):
- `boardPlaceFor` decides once per run, at its first drawing. It floats when the student chose its own window (Pop out), when the page is too old to know tabs, when the main window cannot hold it (`mainCanHold`: open, shown, not minimized, not closing, not signing in), or when the main window covers what is read (`coversReading`). Otherwise it goes in the tab.
- `coversReading`: on the same display, and the main window or the read window is in full screen, or the main window lies over more than `WORDS_COVER_MAX` (0.1) of the words' box. On another display it never covers.
- `leavesTab`: when the student goes to another app and the tab can no longer be seen there, the board moves to its own window. Not while another Tutornote window (the lesson's) has the keys.

`windows.ts` holds only the tab's slot: `showBoardTab`, `hideBoardTab`, `dockBoardView`, `undockBoardView`, `selectBoardTab`, `setBoardTabInfo` and `mainWindowLook`. It tells `screenTeach.ts` what the student did through appEvents: `board-tab-open`, `board-tab-close`, `board-tab-selection`, and `board-host-leaving` when the main window minimizes, hides or closes (not on quit). While the board floats, its tab stays in the bar as an away tab that brings it back. Where a floating board is placed (`boardPlace.ts` `placeBoard`, pure):
- Beside the words, on the side with more room, `GAP` (24) away and narrowed to that room. When neither side has room for `BOARD_MIN`'s width (360 points; the smallest board is 360 by 260), it goes at the right of the work area, `MARGIN` (16) in, over the words' right edge.
- Level with the middle of the window read, `MARGIN` (16) from the top and clear of the bottom `DOCK_CLEAR` (140) left to the lesson's dock. Default size 620 by 640.
- A place the student chose is reused while at least `MIN_ON_WORK` (half) of it and of its 38 pt head are on the work area, and it covers no more than `MAX_OVER_TEXT` (0.25) of its own area with words.
- It is placed once per run (`placedRun`) and then left where it is.

Kept between lessons in `screen-board.json` (`store.ts`): `x`, `y`, `width`, `height`, `place` (`tab` or `window`) and `zoom`, each checked as it is read (`boardPrefsOf`, `boardFileWith`). The text size is `BOARD_ZOOM` -3 to 3 in steps of 0.5. Menus (`menu.ts`): the Window menu has Pop Out Board or Show Board in Tutornote (`Alt+CmdOrCtrl+B`), rebuilt on appEvents `board-place-changed`. `CmdOrCtrl+W` closes the board when it has the keys, else the lesson when it has them, else the tab. View's zoom items act on the board while it has the keys, clamped and saved. The page hears the place on `screen-teach:board-place` and asks for it with `boardPlace()`; asking marks the page as one that knows tabs. Its board messages are checked by `boardStateOf`, and a see through colour never reaches the window (`opaqueColor`).

### The API proxy and its timing log
`renderer.ts` serves the bundled web app on the app's own origin, `app://anothernotes` (`APP_SCHEME` `app`), registered as a privileged scheme before the app is ready. That is `config.ts` `BUNDLED`: `renderer/index.html` exists and `ANOTHERNOTES_SITE` is not `1`; otherwise the window loads the site itself and nothing here is proxied. A route of the single page app gets `renderer/_html/app.html` (`index.html` for an older bundle). Files come from `renderer/` only, with the path checked to stay inside it. HTML gets the app's CSP and `Cache-Control: no-store`. `rendererBuild` reads `renderer/BUILD` for the start up log line. `PROXIED_PATHS` (`/api`, `/img`, `/files`, `/health`) are forwarded by `forward()` through `server.ts` `serverRequest`. The app's cookies stay in the main process; the page never sees them, and `server.ts` stores the server's cookies itself (Secure is dropped only for a plain http server). A request made by another site's page (an `Origin` that is not the app's, or `Sec-Fetch-Site: cross-site`) is refused with 403. No answer at all becomes `Response.error()`: a fetch by the page then fails as it would offline, and a page load fails with `ERR_FAILED`, which `windows.ts` `REASONS` words for the offline page. Redirects back to the site are rewritten to the app's origin, keeping the sign-in callback path (`signInCallbackOf`); a picture's redirect (`/img/<sha256>.jpg`) is followed here (`followPicture`: raster types only, sent with `nosniff`). Token renewals (`/api/auth/refresh`) are joined so only one is in flight, and a good answer is reused for `REUSE_REFRESH_MS` (5000 ms). Changes to the lists (`changesLists`, and an upload whose state turns `done`: `watchUpload`) raise appEvents `lists-changed`, which refreshes pages out of sight. Request priority is `highest` for the tutor's paths and `low` for `/img` and `/files`. Round 4's `screen` field passes through untouched: the proxy forwards the body bytes as they are, and nothing in the Mac app reads or changes them.

The timing log (`apiTiming.ts`, pure): every proxied answer logs `[api] <local time> <method> <path> -> <status> <ms> ms`, the ms from when the request reached `forward()`. The tutor's streamed answers, the paths matching `TIMED` (`/\/guide\/(ask|script|tts|explain)$/`), get a second line as the body ends (`timeBody`): first byte, first words (the first SSE `event: text`; not for `tts`, which is audio), end, and size in bytes. Chunks pass on as they come; the body's words are never logged. Known gaps, by design: a body the page stops reading gets no `done` line, and an `event: text` split across two chunks is missed.

### The preload bridge
`src/preload/index.ts` runs in every page of the web app (the tabs and the lesson window), sandboxed with context isolation. It exposes `window.anothernotes` with `platform`, `version`, `auth`, and two optional parts:
- `speech`: only when the main process passes `--anothernotes-speech=1` (`nativeSpeechAvailable`). It also installs `window.SpeechRecognition` and `webkitSpeechRecognition` over it, in the page's own world before its scripts run.
- `screenTeach`: only in the lesson window (`--anothernotes-screen-teach=1`). The board popup gets the same preload, but every handler in the main process checks the sender is the lesson window itself (`fromLesson`, `fromScreenTeachPage`), so the board's copy can do nothing.

The tabs alone also get the tab bar's room (`SHELL_CSS`), link routing (`nav:open`, `tabs:role`), the layout reports (`chrome:layout`) and the sidebar kept in step across tabs. Every page on `app:`, the lesson window included, gets a small cookie store kept in its localStorage, since Chromium keeps no cookies for the app's scheme. In the tables, "page to Mac" is a one way message, "page asks Mac" waits for an answer, and "Mac to page" is an event. Every `on...` call returns a function that stops listening. Points are the lesson window's own (screen points less its top left).

`window.anothernotes.screenTeach`: the lesson

| Bridge call | Channel | Direction | Payload | Round |
|---|---|---|---|---|
| `ready()` | `screen-teach:ready` | page asks Mac | returns the pending start, or null | |
| `onStart(cb)` | `screen-teach:start` | Mac to page | `{ run, overlay, read, click, canTurn, mode, choice?, quiet?, companion?, ground?, row?, stale?, switched? }` | 4 adds `switched` |
| `started()` | `screen-teach:started` | page to Mac | none | |
| `interactive(on)` | `screen-teach:interactive` | page to Mac | boolean | |
| `turn(request)` | `screen-teach:turn` | page asks Mac | `{ run, dir, scrollBy, pages, at, how, unlessMoved }`; returns `{ ok: true, how, mode, read, canTurn? }` or `{ ok: false, reason }` | |
| `reread(run, opts)` | `screen-teach:reread` | page asks Mac | `run`, `{ fast }`; returns a read in the window's points, or null | |
| `allowTurning()` | `screen-teach:allow-turning` | page asks Mac | returns boolean | |
| `openSettings(which)` | `screen-teach:open-settings` | page to Mac | `"screen"` or `"accessibility"` | |
| `openInMain(path)` | `screen-teach:open-in-main` | page to Mac | a path starting with `/` | |
| `onCommand(cb)` | `screen-teach:command` | Mac to page | `"toggle-play"`, `"next"`, `"prev"`, `"close"`, `"pause"` or `"resume"` | |
| `onTap(cb)` | `screen-teach:tap` | Mac to page | `{ run, x, y, moved, acted, alt, id? }` | 3: `acted` false for a reader selection |
| `onScroll(cb)` | `screen-teach:scroll` | Mac to page | `{ run, dy }` | |
| `pickAt(point)` | `screen-teach:pick-at` | page to Mac | `{ run, x, y }` | |
| `close()` | `screen-teach:close` | page to Mac | none | |
| `board(state)` | `screen-teach:board` | page to Mac | `{ run, show, full, background?, drawn? }` | |
| `onBoardControl(cb)` | `screen-teach:board-control` | Mac to page | `"close"`, `"zoom"` or `"unzoom"` | |
| `onBoardPlace(cb)` | `screen-teach:board-place` | Mac to page | `{ where, canMove, covering, app? }` | |
| `boardPlace()` | `screen-teach:board-place-now` | page asks Mac | returns the same, or null | |
| `moveBoard(to)` | `screen-teach:board-move` | page to Mac | `"tab"` or `"float"` | |
| `backToApp()` | `screen-teach:back-to-app` | page to Mac | none | |
| `onAside(cb)` | `screen-teach:aside` | Mac to page | boolean | |
| `onPresent(cb)` | `screen-teach:present` | Mac to page | boolean (anything else is false) | |
| `onTalk(cb)` | `screen-teach:talk` | Mac to page | none (`Control+Alt+M`) | 3: now one tap of the mic |
| `onChord(cb)` | `screen-teach:chord` | Mac to page | `{ kind, ms }`, kind `down`, `tap`, `hold`, `up` or `cancel`; ms finite | 3 (new) |
| `onChordState(cb)` | `screen-teach:chord-state` | Mac to page | `{ on }`, a boolean | 3 (new) |
| `onSwitching(cb)` | `screen-teach:switching` | Mac to page | `{ run, on, why? }`; `why` cut to 24 characters | 4 (new) |
| (sent by `onSwitching`) | `screen-teach:hears-switching` | page to Mac | none | 4 (new) |
| `onTapDropped(cb)` | `screen-teach:tap-dropped` | Mac to page | `{ window, app, x, y }`; no longer sent, kept for older pages | |

`window.anothernotes.screenTeach`: the companion

| Bridge call | Channel | Direction | Payload | Round |
|---|---|---|---|---|
| `onCompanion(cb)` | `screen-teach:companion` | Mac to page | `{ on, overlay, from?, first, to? }` | |
| `companionState()` | `screen-teach:companion-state` | page asks Mac | returns the same, or null when off | |
| `onGlance(cb)` | `screen-teach:glance` | Mac to page | `{ window, read, ground, fast, keepCard?, tap?, empty? }` | |
| `onOver(cb)` | `screen-teach:over` | Mac to page | `{ window }` (a number or null), with `own?`, `private?` or `reading?` | |
| `onPress(cb)` | `screen-teach:press` | Mac to page | `{ window, x, y }` | |
| `onCompanionRelease(cb)` | `screen-teach:companion-release` | Mac to page | `{ id, window, x, y, alt, hand, clicks, lesson, run?, private? }` | |
| `onCompanionTap(cb)` | `screen-teach:companion-tap` | Mac to page | `{ window, x, y, id? }` | |
| `onCompanionWithdraw(cb)` | `screen-teach:companion-withdraw` | Mac to page | `{ id, why, window }`; `why` is the verdict's words, `acted`, or `another document` | 3: not for a reader selection; 4 adds `another document` |
| `onWindowScroll(cb)` | `screen-teach:window-scroll` | Mac to page | `{ window, dy, dx }` | |
| `onChanged(cb)` | `screen-teach:changed` | Mac to page | `{ run, window }`; run 0 for a window that is not the lesson's | 4: the lesson's now from `screenTeach.ts`, companion on or off |
| `onCursor(cb)` | `screen-teach:cursor` | Mac to page | `{ x, y }` | |
| `explainAt(request)` | `screen-teach:explain-at` | page asks Mac | `{ window, x, y, choice, tap?, row? }`; returns `{ ok: true }` or `{ ok: false, reason }`, reason `off`, `private`, `failed`, `bad` or `no_permission` | |
| `cardClosed()` | `screen-teach:card-closed` | page to Mac | none | |
| `cardBox(box)` | `screen-teach:card-box` | page to Mac | `{ x, y, w, h }`, or null (anything but four finite numbers is sent as null) | |
| `wantKeys(on)` | `screen-teach:want-keys` | page to Mac | boolean | |
| `cursorFeed(from)` | `screen-teach:cursor-feed` | page to Mac | `"main"` or `"page"` | |
| `companionOff()` | `screen-teach:companion-off` | page to Mac | none | |
| `companionHold(held)` | `screen-teach:companion-hold` | page to Mac | boolean | |
| `companionDock(on)` | `screen-teach:companion-dock` | page to Mac | boolean | |

`window.anothernotes.speech`

| Bridge call | Channel | Direction | Payload | Round |
|---|---|---|---|---|
| `native` | none | constant | `true` | |
| `start(lang, continuous, onEvent, opts?)` | `speech:start` | page to Mac | `ref`, `lang`, `continuous`, `{ preroll?, hints? }`; returns `ref` | |
| (the `onEvent` given to `start`) | `speech:event` | Mac to page | `{ ref, ev, text?, code? }`, ev `start`, `audiostart`, `speechstart`, `interim`, `phrase`, `error` or `end` | |
| `warm(ms)` | `speech:warm` | page to Mac | a finite number | |
| `prepare(lang)` | `speech:prepare` | page to Mac | a string | |
| `stop(ref)` | `speech:stop` | page to Mac | a number | |
| `abort(ref)` | `speech:abort` | page to Mac | a number | |
| `output()` | `speech:output` | page asks Mac | returns `{ name, transport, source, speakers }` or null | 3 (new) |
| `onOutput(cb)` | `speech:output` | Mac to page | `{ name, transport, source, speakers }`, sent after `output()` was asked | 3 (new) |

The blob's bridge (`window.screenBlob`, `static/blob.html` only): `onState(draw)` hears `blob:state` `{ look, label, side, pop? }` (look `resting`, `on`, `reading`, `blocked` or `hidden`) and sends `blob:ready` as it starts to listen; `dragStart()`, `dragEnd()`, `toggle()`, `menu()` and `hover(on)` send `blob:drag-start`, `blob:drag-end`, `blob:toggle`, `blob:menu` and `blob:hover` (a boolean).

Old and new together:
- Every new call is optional; the web page feature detects each one, so a new page runs on an older Mac app.
- New messages get channels of their own (`screen-teach:talk`, `chord`, `chord-state`, `switching`, `board-control`), never new values on `screen-teach:command`, which an older page would take for a key.
- A switch to another document is begun only for a page that listens (`screen-teach:hears-switching`).
- Where the page could get odd values, the preload checks them before the page sees them (`onChord`, `onChordState`, `onSwitching`, `onPresent`, `onOutput`, `cardBox`). The main process checks every argument again.

## Voice
How the student talks to the tutor: a tap asks one question, a long hold turns on talk mode, the screen tutor has a Control+Option chord, and the mic must not take the tutor's own voice for the student's. Most of the logic is in the web app. The Mac app adds Apple's speech recognition (the speech helper and `speech.ts`), the chord (the screen helper, `screen.ts` `chordWatch`, `screenTeach.ts`) and the output route (`OutputWatch`). In the web app, `src/lib/guide/talkMode.ts` holds the tap rule, talk mode's constants, the duplex and tail rules, the echo check, and all of talk mode's copy (`TALK_COPY`); `src/lib/talkHold.ts` the five second hold and its ring; `src/lib/useTalkKey.ts` the main window's talk key; `src/lib/guide/micShare.ts` one microphone per page, plus `micHints` and `screenMicHints`; `src/lib/guide/outputRoute.ts` speakers or headphones; `src/lib/guide/voiceTiming.ts` the `[voice]` timing lines; `src/lib/guide/speech.ts` `createNativeRecognizer`, `pageMic`, `voiceAskOptions`, `voiceQuietMs` and `voiceWarm`. `src/components/guide/TeachMode.tsx` has `mic`, `askOnce`, `startListening`, `openTalk`, `talkHeld` and `talkTick`; `src/pages/ScreenTeachPage.tsx` has the chord and ⌃⌥M wiring.

### A tap asks one question
A tap is a click on the dock's mic; the talk key in the main window (plain M by default), which acts as the key goes down; or, in the screen tutor, the chord's "tap" or ⌃⌥M. The screen tutor turns its taps into the window event `TALK_TAP_EVENT` (`"an:talk-tap"`), which `TeachMode` handles as `mic("key")`. With talk mode off and no mic open, `mic` calls `askOnce`, which calls `startListening({ press: true, preroll: voiceTimer.pressWall() })`. The tutor's voice stops and the mic opens for one question. The question sends itself when the student stops talking:
- `askOnceSettle` treats a question's "wait" verdict as "brief", the same way a talk turn does (`talkSettle`).
- `turnEndMs` sets how long "brief" waits: `TALK_END_MS` (450 ms) after the words last changed if the question sounds finished; `ASK_COMMAND_IDLE_MS` (1500 ms, from `askCapture.ts`) if the last word trails off (the `DANGLING` list, such as "the", "of", "what" or "um") or words are still in flight.
- The wait counts from the last change in the words, not from when the recogniser hands over a finished phrase.
- Replies and commands keep their own rules: they go at once, or after `ASK_REPLY_IDLE_MS` (3000 ms) when it is not yet clear what the student meant.

**Idle close.** The tap's listener gets `idleMs: ASK_ONCE_IDLE_MS` (8000 ms) instead of the long `ASK_IDLE_MS` (20 s). If no word comes within that time after the mic goes live, it closes quietly (`askOnceQuiet`) and shows `TALK_COPY.heardNothing`. A lesson that the tap stopped then goes on by itself. A second tap while the mic is listening sends the words heard; with nothing heard it just stops listening; if the mic was lost partway through a question, it listens again; and if the lesson had opened the mic by itself for an answer, the tap makes it the student's own question, with the same quick end.

**Pre roll.** In the Mac app the mic hears from the moment of the press. `voiceTimer.pressWall()` gives the press time if the press was less than `VOICE_PRESS_MS` (2000 ms) ago, and the shim sends it as `tutornotePreroll`. `speechStartOptions` and the helper's ring (`RING_MS`, `PREROLL_MAX_MS`; see "Native helpers") do the rest. So that the ring has audio in it, the page wakes the Mac mic early with `voiceWarm(6000)` when the pointer goes down on the dock's mic and on the chord's "down".

### A five second hold turns talk mode on
`TALK_HOLD_MS` is 5000 ms (`talkMode.ts`). `createTalkHold` in `src/lib/talkHold.ts` times it. Only one hold runs at a time on a page, from one of three sources:
- **`"key"` (main window).** `useTalkKey` calls `pressTalkHold("key", code)` before the tap acts, so the tap opens the mic at once. If the hold counts, it takes over that open mic: `talkHeld` calls `talkStart("hold")` while the mic is listening. Releasing the key, pressing another key, the window losing focus or the page being hidden ends the hold.
- **`"pointer"` (the dock's mic in `GuideDock.tsx`, the companion's in `CompanionDock.tsx`).** The tap acts on the click. When a press turns into a hold, `talkHoldClick` swallows its click. Pointer up, pointer cancel, losing pointer capture or leaving the button ends the hold. If talk mode is already on, `GuideDock` starts no hold, so no ring fills.
- **`"chord"` (screen tutor).** The screen helper times the chord, not the page. "down" calls `pressTalkHold("chord")`, "hold" calls `completeTalkHold("chord", ms)`, and "tap", "up" and "cancel" call `releaseTalkHold`. If nothing more comes after a "down", the hold ends after `CHORD_LOST_MS` (`TALK_HOLD_MS + 2500`, 7500 ms).

The ring: `useTalkHolding` turns true once a hold has lasted `TALK_HOLD_SHOW_MS` (350 ms), so a tap never flashes the ring. A chord shows it at once, because its "down" already means 300 ms held. The ring then fills over `TALK_HOLD_RING_MS` (`TALK_HOLD_MS` less `TALK_HOLD_SHOW_MS`, 4650 ms), set inline as the animation length on the SVG circle (`guide-mic-hold` in `src/index.css`). A hold is the only way the student turns talk mode on, and a hold while talk mode is on does nothing. In the screen tutor a new run picks up talk mode that a hold turned on in the run before (`talkCarry`). A tap that turns talk mode off releases the hold its own press started, so a long press meant to stop talk mode cannot turn it back on five seconds later.

### A tap while talk mode is on
`mic` decides from what the lesson is doing now. The same states, named by `talkMicStateOf`, give the dock's mic its title, and `talkTapAction` names the choice in the `[voice] press` line:
- **The tutor is talking** (`"talkSpeaking"`): `talkInterrupt` stops the voice and opens the student's turn at once, treated as a press. If the student says nothing for `TALK_WAIT_MS` (8000 ms), the lesson picks up again. On speakers this is the only way to cut in.
- **Words heard in the open turn** (`"talkWords"`): they are sent now (`talkTap`).
- **Anything else** (`"empty"`): `talkSendThenOff` turns talk mode off, sending any words already heard first.

Talk mode also turns off with the Talk chip, Esc, `TALK_SLEEP_MS` (60000 ms) of waiting with nothing said, `TALK_AWAY_MS` (600000 ms) with no word from the student, or `TALK_FAILS` (2) turns in a row that never got to listen. While it is on, `talkTick` runs every `TALK_TICK_MS` (250 ms). A turn waits `TALK_WAIT_MS` for a first word, and no turn runs longer than `TALK_CAP_MS` (90000 ms).

### Control+Option and the ⌃⌥M fallback
The chord is Control and Option pressed on their own, read by the screen helper's polling (see "The talk chord" under "Native helpers"): "down" at 300 ms, "tap" at a release within 700 ms, "hold" at 5 s, "up" at the release after a hold. A release between 0.7 s and 5 s does nothing ("cancel", why "long"). The polling needs no permission and shows no prompt. In the main process:
- `registerTalkKey` turns on `chordWatch(true)` and registers `TALK_SHORTCUT` (`"Control+Alt+M"`) together. This happens while a lesson is on screen (`registerShortcuts`) and while the companion is on (`showCompanionOverlay`). The chord is watched even if another app has taken ⌃⌥M.
- `onChord` drops the chord unless the talk key is on, the window exists and its page is ready. It also drops a "tap" within `TALK_KEY_CHORD_MS` (400 ms) of ⌃⌥M or of one of the lesson's `SHORTCUTS`: that tap is just the shortcut's own Control and Option being released. Otherwise it sends `{ kind, ms }` on `screen-teach:chord`. The cancel reason and which side's keys were used go only to the log.
- ⌃⌥M sends `screen-teach:talk`. It is always a tap, and the page's tap rule decides what it does: one question, an interrupt, a send, or talk mode off. It never turns talk mode on.
- `onChordState` stores whether the chord is usable in `chordUsable`, logs it, and sends `screen-teach:chord-state` with `{ on }`. It sends the state again on `screen-teach:ready` for a page that loads later.

In `ScreenTeachPage.tsx`:
- "down" wakes the Mac mic (`voiceWarm(6000)`) and starts the hold; "hold" counts it; every other kind releases it, and a "tap" also goes to `talkKeyTap`.
- With a lesson up and the student in another app (`presentNow()` false), chord events do nothing; a "hold" then only releases the ring.
- With no lesson up, a tap goes to the companion dock's mic, but only while the companion is on and `cardMicSupport()` is `"native"`.
- The page keeps the chord's state in its own `chordUsable`. `screenTalkKey` labels the key `⌃⌥` while the chord works, and `⌃⌥M` while it does not, or when the Mac app has no `onChord` at all.

### Half duplex on speakers
The speech helper's verdict (`OutputWatch`, under "Native helpers") reaches the page as `{ name, transport, source, speakers }`. On the page, `routeOf` in `outputRoute.ts` returns headphones only when `speakers` is exactly `false`. Everything else counts as speakers, including a browser and an older Mac app. Until the Mac app answers, the route is `OUTPUT_UNKNOWN`. `talkDuplex` returns `"full"` only for headphones and `"half"` for everything else. On speakers (half duplex), nothing listens while the tutor plays:
- **No ear.** `talkEarWanted` and `talkEarKeep` return false. If a recogniser from the last turn is still running, `pageMic().dropKept()` in `talkTick` drops it once the voice is audible.
- **When a turn opens.** Only after the lesson has waited `TALK_AFTER_MS` (300 ms) and the voice has been quiet for the route's tail (`talkTurnDue`, `talkTurnWaitMs`).
- **The tail per route** (`talkTailMs`, by transport): `TALK_TAIL_MS` 700 ms for any other transport (built in, USB, unknown); `TALK_TAIL_LONG_MS` 1000 ms for Bluetooth, HDMI or DisplayPort; `TALK_TAIL_AIRPLAY_MS` 2500 ms for AirPlay.
- **A press that stops the voice** (a tap's question, an interrupt). The mic hears from the later of the press and `PRESS_TAIL_MS` (300 ms) after the voice went quiet, and the start waits until then (`talkPressFrom`). This happens only where the recogniser can replay audio from before its start, which is the Mac app's (`voicePrerollWorks`). A browser's recogniser starts at once.
- **A new recogniser each time.** Every talk turn and every tap's question gets a new one (`fresh` in `micShare.ts`), never one that ran while the tutor talked.
- **A floor after each step.** In talk mode, each lesson step said to its end is followed by `TALK_FLOOR_MS` (2500 ms) for the student to speak into.
- **What "quiet" means.** `voiceQuietMs` and `voiceQuietWall` in `speech.ts` follow the shared audio element: audible from its `playing` event, quiet from `pause`, `ended`, `emptied` or `error`.

In headphones (full duplex), the ear listens while the tutor teaches or answers, so the student can cut in by voice. The student's turn takes over the ear's running recogniser through `micShare`, so words in flight are not lost; a recogniser released with `keep` keeps running for `MIC_KEEP_MS` (1500 ms) so the turn can take it over.

### The echo check
The recogniser does not cancel echo. Instead, heard words are compared with what the tutor just said.
- **Heard:** only the last `TALK_ECHO_WINDOW_WORDS` (8) words. **Said:** the tutor's runs of speech whose sound ended no more than `TALK_ECHO_WINDOW_MS` (8000 ms) ago, plus the line being said now (`talkEchoRef`).
- **Normalising** (`talkWordsOf`): written signs become their spoken words, text is lower cased, accents are removed, a British "tre" ending becomes "ter", and every number becomes one token.
- **A heard word counts as the tutor's** (`talkCover`) when it stands next to the same neighbour as in the tutor's words, or two heard words join to make one of the tutor's. Near misses count too (`talkSameWord`): one letter off for words of at least `TALK_NEAR_CHARS` (5), two letters off once either word is at least `TALK_NEAR_LONG_CHARS` (8); shorter words must match exactly.

The ear's verdict in headphones (`talkBargeWeigh`):
- If at least `TALK_ECHO_SHARE` (0.5) of the window is the tutor's, it is the tutor heard back and does not cut in, unless the student's own words run on at the end: `TALK_BARGE_RUN` (4) of them while the voice sounds, or `TALK_BARGE_RUN_QUIET` (3) just after.
- Otherwise the student cuts in with `TALK_BARGE_LIVE` (3) of their own words while the voice sounds, or `TALK_BARGE_WORDS` (2) just after. Nods on their own never cut in.
- A single stop or control word ("wait", "next") does cut in, once the recogniser has finished it as a phrase and the tutor did not just say it. While the tutor speaks a language the ear does not know, only these words cut in.
- An ear that keeps ending early hands over to the floors: `TALK_EAR_FAILS` (5) ends shorter than `TALK_EAR_SHORT_MS` (1500 ms) within `TALK_EAR_WINDOW_MS` (30000 ms). If the ear's microphone is taken or refused (`talkEarGivesUp`), the ear stops for the rest of the session.

In every talk turn, on both routes, `talkEchoOff` removes a run of two or more of the tutor's words from the start, only for words that begin within `TALK_ECHO_LIVE_MS` (1500 ms) of the voice, while the tutor can still be heard (`talkEchoLive`). Everything from the student's first word of their own onward is kept. A tap's one question does not go through the echo filter; on speakers it relies on the press tail and a new recogniser instead.

### Mic hints from the page's words
New recognisers lean towards the lesson's own words through Apple's `contextualStrings`. Only the Mac app's recogniser gets hints; a browser's never does.
- **Main window** (`micHints`): first the titles of the sections near the one being taught, nearest first, each cut between words to at most `MIC_HINT_CHARS` (40); then words from the caption that are six letters or longer, or short all capitals words (`HINT_WORD`).
- **Screen tutor** (`screenMicHints`, through `micHintsNow` in `TeachMode`): screen lesson sections are titled only by page number, so titles are not used. First the caption's words, then the page's own words, longest first, read from the text blocks (`[data-pdf-kind]`) and skipping blocks of kind `"furniture"`.
- At most `MIC_HINTS_MAX` (50) hints, each kept once regardless of case. Hints go only to a recogniser made new for a lease; one taken over keeps the hints it was made with. The page sets them as `tutornoteHints`, the preload passes on strings only, `speechStartOptions` trims and clamps them, and the helper checks them again (`clampHints`).

### What voice logs
No word the student says is written to a log. The lines carry times, counts and causes.
- **Page `[voice]` lines** (`voiceTiming.ts`, `console.log`; the Mac app copies page console lines into its own log as `[web:info:<role>]`, or `[web:info:screen]` for the screen tutor): `press <surface> (<action>)`; `<surface> mic live +N ms after the press (<how>)` (or `after the turn opened`); `<surface> first words +N ms after live`; `<surface> question sent +N ms after the last words (rule <rule>, N words)`; `ask request`, `first answer words` and `first audio`, each `+N ms after sent`; `talk on|off (<how>)`; `hold <source> N ms`; `turn open (<how>) <owner>`; `turn waits N ms for the speakers`, `mic waits N ms for the speakers`; `output <kind> (<transport>)`; `cut in (N own words of M heard, echo share S) <surface>`.
- **Main process `[speech]` lines** (`speechLine` in `speechLog.ts`): helper started, prepared, mic on or off, input route, output; and for each session `#id`: start (with how far back a pre roll was asked), ready, live, first words, each phrase (word count, what cut it, and how long after the voice ended), and end. The input and output lines name the audio device the way macOS reports it.
- **`[screen-teach]` lines:** each chord (kind, ms, cancel reason, which side's keys), a dropped tap, the chord becoming usable or unusable, and `talk key Control+Alt+M: a tap`.

## The page and the server
The Mac app draws the lesson, but the lesson is the bundled web app's Teach mode and its words come from the backend. This part covers what the page does for the screen tutor, and the server code the Mac app depends on. The files are listed in "Map of the code". When this was written, the web side of rounds 3 and 4 (and the screen tutor's own web files, such as `ScreenTeachPage.tsx` and `src/lib/screen/`) was in the web app's working tree and not yet committed to a web branch; `renderer/BUILD` marks the bundle as a local build.

### Switching on: the lesson stops
The page listens through `bridge.onSwitching`, which also tells the Mac app it listens (`screen-teach:hears-switching`). On `on: true` the page calls `leaveDocument`:
- It stops the lesson with TeachMode's own stop (the `onStop` prop), not the play and pause key, since a toggle sent while the page wrongly thought the lesson was idle would start it playing.
- It records whether the lesson was playing (`Switching.play`): talking, paused only because the student stepped into another app, or paused for a new part it was about to go through. A run that had not mounted yet counts as playing unless it came from a card's Ask. A held tutor, or a lesson the student paused, is not playing. The next run plays at once only if this one was playing.
- It hides the marks and the pointer, and closes the lesson's mics (`presentNow` is false while switching). An open mic or talk turn is dropped with nothing sent, since those words were about the old document.
- It closes a tap card on that window, unless the student is asking a question in it.
- It shows the chip "Another document. Reading it now." and logs `[screen] another document: run N stopped (playing|paused|held)`. It never logs a title.

While the switch lasts:
- `onChanged` events for that run are ignored: the new look belongs to the next run.
- If the student presses play on the old lesson, it stops again at once, and the press counts as "was playing" (`notePlace`).
- Another `on: true` for the same run only changes the chip: "wait words" shows "Another document. Nothing to read there yet."; "wait student", "wait secure" or "wait screen" show "Another document. Waiting to read it."; "reading" goes back to "Another document. Reading it now." The waiting chips have a Close button, which ends the lesson.

### Switching off: the same document after all
`on: false` means the switch ended with no new run: a flick (a tab and straight back), a title that changed by itself, or another document that could not be read. `backToDocument` clears the switch and puts back the chip that was up before, unless that chip stood for a wait the switch gave up (`waitChip`). If the lesson was playing, it plays on where it was; if the student is in another app now, it plays on when they come back; if it had paused for a new part, that part is gone through after the dwell below. It logs `[screen] the same document: run N goes on` (or `stays stopped`), with the Mac app's `why` only when that is at most 24 lowercase letters and spaces. The page keeps the lesson stopped when `why` is "gone". The current Mac app sends "back", "same" or "failed" when a switch ends, so in practice a lesson that was playing always plays on, after a "failed" too. A page turn the lesson asked for before the switch is answered "stale" by the Mac app. After a flick the page asks for that turn again (`switchSeen`), and a move the student made meanwhile is taken as the turn, so nothing is posted twice.

### The run on the new document
The Mac app then starts a new run with `ScreenStart.switched`. The page's start effect:
- Starts it quietly: no start sound, no greeting, no research on the board. The student did not ask about these words.
- Aborts research still running for the old document (`researchStore.abortAll`), clears the kind memory (`kinds.current.clear()`) and empties the board's strip (`boardDoc`). Two numbered files of one course can share a `docKeyOf`, so a switched run always starts fresh. The old TeachMode unmounts, which aborts its `/guide/script` stream (`lessonAbort`).
- Mounts the lesson at the first block of page 1 that is not furniture (on a slide, usually its title), and gives page 1's section `opens`, so its script request carries `section_start: true`.

Then it plays or stands:
- It plays at once only when the old lesson was playing, the tutor is not held, page 1's kind is sure, and that kind is in `PLAYS_ON_SWITCH` (slides, book, article, code, table).
- Otherwise it stands (`TeachStart.hold`). TeachMode puts the lesson on that block, paused and silent, with the pointer there, and asks the server nothing until Play. The chip says "New document. Press play to go through it."; its Close only hides the chip. A chat, a form or a page it cannot identify may be private (mail, a bank's page), so nothing of it is sent to be explained unless the student asks.
- If the student had paused the whole tutor, the tutor's own Play plays the new run.
- It logs `[screen] new document: run N plays` (or `stands`).

### Older Mac apps: the page checks for itself
When `bridge.onSwitching` is missing, the page runs `switchAway` on reads of the lesson's window it takes anyway: after the student's own move (`ctl.ownMove`), on return from another app (`ctl.comeBack`), when the student scrolls to words no page has (the scroll settle `realign`), and for a stale start (`ctl.realign`, which is `comeBack`). It compares the run's title and lines with the new read using `otherDocument` (web `docIdentity.ts`):
- Another document if the window differs, or the title changed in its words ("letters") or only in its digits ("digits").
- Still the same document if the look stayed: at least `SAME_LOOK_FOUND` (2) body rows found again, and at least `SAME_LOOK_SHARE` (0.6) of them. The title only ticked, and the page keeps the new title as the run's.
- A title that says nothing ("weak": empty, or just the app's name, as a reader app's often is) is the same document.

For another document the page calls `leaveDocument` and then `bridge.pickAt` at `firstBodyPoint` of the new read. The run that comes for that window is treated as switched. If none comes within `EXPLAIN_WAIT_MS` (12000 ms), the chip goes and the lesson stays stopped.

### A new part of the same document
`afterOwn` handles the student's own move. If they moved to words no page has ("new") while the lesson was playing, the lesson goes through that part (`goThrough`) once the window has kept its look for `NEW_PART_DWELL_MS` (600 ms), no read of a change is still running, and the page is not following a scroll. Flipping quickly through slides restarts nothing until the student stops. If the student is in another app, it waits for them. If the student had paused the lesson, they get the chip "New page. Shall we go through it?" A flick back to the lesson's page before the dwell ends lets the lesson play on where it was. Log: `[screen] new part: run N goes through page P`. `screenFlow.ts` matches only lines inside paragraphs, never furniture. "The words are where they were" counts only when most lines in the window's body match (`band` and `lineShare` against `SAME_LOOK_SHARE`). Browser bars and a slide's logo stay in place through a tab switch or the next slide, and used to make both read as "known, nothing moved".

### Browser bars are furniture
`markFurniture` calls `markBars` for a browser window (`isBrowser`: Safari, Firefox, Arc, Brave, Opera, Vivaldi, Orion, Chromium, and Chrome and Edge in any channel); for Arc, `markBars` first marks its sidebar (`markSidebar`). `src/lib/screen/screenBlocks.ts` applies the same rule as the Mac app's `browserBars` (see "docIdentity.ts, piece by piece"), with the same constants, and marks those rows as furniture. The web `bodyRows` uses the same `BODY_TOP`, `BODY_FOOT` and `BODY_LETTERS`. A row repeated in place on stacked slides or pages (a logo, in a browser or Preview, at least 0.3 of the window height apart) is furniture too, and so is a short row in the same place on a slide that replaced the last one (`inPlaceFurniture` in `screenFlow.ts`). These rows used to reach the model as page text, tab titles and a local file path among them.

### Content kind, and when it is sure
`contentKind(read, blocks)` returns a kind (slides, book, article, code, table, form, chat, other), whether it is `sure`, a slide counter when one was read, and a `why` for the log made of the code's own words and numbers only, never screen text. App and title come first, and are always sure:
- Keynote and PowerPoint are slides; Excel and Numbers are a table; editors and terminals (VS Code, Xcode, Terminal, iTerm and others in `CODE_APPS`, and JetBrains IDEs by `CODE_PREFIXES`) are code; Kindle and Books are a book; the Claude and ChatGPT apps are a chat.
- By the title's signature: a title ending "google slides", .ppt, .pptx, .key or .odp is slides; "google sheets", .xls, .xlsx, .xlsm, .csv, .tsv, .numbers or .ods is a table; a code file extension is code; in a browser, a title ending in the Claude or ChatGPT name is a chat.

Otherwise the layout decides, on the text under the window's bars:
- Code: 6 rows or more, and at least 0.4 of them dense with code marks or at least 0.3 opening with a keyword. Sure only with marks at 0.6 or more and keywords at 0.3 or more.
- Table: 4 or more rows of 3 or more aligned cells, or numbers making up 0.4 or more of 20 or more words. Sure only with the aligned rows and numbers at 0.3 or more.
- Form: 4 or more short labels ending in ":" or "*". Sure with 6.
- Slides: a counter total of 120 or less (or no counter), 2 or more blocks of text (1 with a counter), under 0.5 of the rows in dense paragraphs, 220 words or fewer, text at least 1.25 times the height of the bar rows (when bars were read), and either h2 blocks at 0.35 or more or a row repeated 0.3 window heights apart. Sure with a counter, a repeated row, or (outside a browser, or on a PDF in one) a measured text size and 3 or more blocks.
- Book: 200 words or more, 0.45 or more of the rows in dense paragraphs, h2 at 0.25 or less. On a PDF (Preview, or a title ending .pdf) this is a sure book, and anything else there is "other", not sure. Any other browser page is an article, sure only when it reads as prose. Everything else is "other", not sure.

The code, table and form numbers were set by hand with no real reads to measure, so they are kept strict. The slides and book numbers were measured on real reads during development. `kindMemo` keeps a document's kind by `docKeyOf`: the kind most of its sure pages had. A page that is not sure takes the document's kind, as sure, once any page of it was sure. A slide's numbers are always the page's own. The memo is cleared for a switched run. Each page logs one line, `[screen] page N: <kind> (slide n of m)`, with "(unsure)" when it is. The kind also changes, in the web app:
- The hidden question of a tap's Explain (`kindAsk`): a slide's point briefly, as a lecturer would; what code does before any line of it; a table's pattern, not its cells. Other kinds keep the old wording.
- `scriptCaps`: code, table and form pages ask for no worked exercise and no graph (`solve: 0`, `graph: 0`).
- `blockHints`: on a page that is surely code, blocks of 2 or more rows go to the server as kind "code" (`data-guide-kind`, read by `kindOf` in `src/lib/guide/blocks.ts`). Headings stay headings.

### What the page sends
- Only `/guide/script` and `/guide/ask` carry the `screen` field. Research questions and note writes do not.
- The field is `{kind}`, or for slides with a valid counter `{kind: "slides", slide, slides}`.
- `screenOf` builds it from sure kinds only. `screenField` (in `screenKind.ts`, called by `services/guide.ts` on both requests) checks it again: exactly one of the eight kinds; `slide` and `slides` only for slides, whole numbers from 1 to `MOST_SLIDES` (10000), the first no more than the second. Anything else on the object is dropped, so a title, a file name or the screen's text can never be sent in it.
- TeachMode adds it only when `source` is "pdf" and `voiceSurface` is "screen" (`screenOfSec`). In app notes and the app's own PDF reader never send it.
- With no sure kind, `screenField` returns undefined and the key is left out of the JSON, so the request body is exactly what it was before.

### What the server does with it
In `app/api/guide.py`:
- `ScreenIn` accepts `kind` only from `SCREEN_KINDS`. `slide` and `slides` are strict whole numbers from 1 to `SCREEN_SLIDES_MAX` (10000). For any kind but slides the counter is dropped unread (`_counter_for_slides`). A slide past the deck's last is invalid.
- An invalid `screen` never fails the request: `_screen_of` logs one line and treats it as unsent.
- The field is read only when the topic is a PDF page (`_PdfPage`). Screen lessons are pages of the stand in "Reading on screen" PDF session, page n being topic -n. On a notes section it is ignored.

For a script with a screen:
- The prompt names the page by `_screen_label` ("slide 3 of 9 of the slide deck on their screen", "the code on their screen"; a book, a chat or other is "the page on their screen") and says the student is looking at it on their screen.
- Slides (`_screen_rule`): one short pass. The title gets the first step, one clause on the slide's idea, never read out. Then one step per bullet, expanded as a lecturer would. A recap only on the deck's last slide (slide equals slides); every earlier slide, or one whose place is unknown, ends with no recap (`_mid_deck`). A lesson that starts past slide 1 does not treat its first page as a document's title page.
- Code: what it does first, with its inputs and outputs, then one step per function, method or class on its first line, quoting its signature. Never line by line unless asked.
- Table: what is compared, then the overall pattern, then one or two rows worth noticing. Never every cell. A chart only when the numbers call for one.
- Form: what it is for, its sections and fields and the usual mistakes. Never the data typed into it, and never filling it in. Quick checks are switched off on form pages.
- Article: paragraph by paragraph, with the website around it (menus, adverts, cookie boxes, comments) left out. Book, chat and other get no extra rule.
- Slides, code, table and form get no KEY IDEAS (`_SCREEN_PACED`). Code, table and form are taught as a whole (`_SCREEN_WHOLE`): no block is owed its own step, and there is no COVER THE WHOLE PAGE rule.
- The script cache key gets `|screen=<tag>` as its last part, from `_screen_tag`: `sc1:<kind>`, or `sc1:slides.<slide>/<slides>` for slides. `SCREEN_STYLE` ("sc1") is to be raised whenever `_screen_rule` changes, so old cached lessons are not reused.
- Log: `[Guide] topic <id>: on their screen (<tag>)`.

For an ask with a screen, the page is named the same way, and `_screen_ask_line` adds one line for slides, code, table or form (for example, a table's pattern first, but a question about one row answered first). Without the field the prompt is the same byte for byte, with the same cache key, the same cache and the same stream. All screen wording comes after the shared part of the prompt, so its cached prefix never changes. The request models do not forbid extra fields, so a server without this change simply ignores `screen`.

## Privacy rules the code keeps
- **No titles, screen words or student words in the logs.** The screen helper's log lines carry codes, process ids, counts and timings; titles and page text go to the app only, and `screen.ts` does not log them either. `[screen-teach]` lines carry runs, app names, whys, counts, times and percentages; a document title is matched (`DOCUMENT_TITLE`), never logged. `companion.ts` logs a retitled window by its number only. The speech helper, `speechLine` and the page's `[voice]` lines carry counts, causes and times, never the words heard; phrase text goes to the page only. `apiTiming.ts` never logs a body. The page logs no title when a document changes.
- **What the logs do carry.** Audio device names (input and output), the way macOS reports them; app names and bundle ids; error messages; at start up, the server addresses the build uses and the path of the app's data folder (and, with tap recordings on, the folder they go to). Two places could echo more: a command line a helper cannot parse is written to its log as it came, and `screen.ts` and `speech.ts` echo a stdout line that is not JSON. The app's own commands carry no page text, so in practice nothing leaks there. One warning ("reading the other document failed: <message>") prints an exception's message, which by design never holds a title, though nothing enforces that.
- **Tap recordings are opt in.** Only with `TUTORNOTE_TAP_LOG=1` are verdicts written under `taps/` in the app's data folder (the newest 200), because those files hold the words read.
- **Browser bars are not page text.** Rows the browser draws (the address, tabs, bookmarks, a PDF viewer's toolbar, Arc's sidebar) are left out of what the document is judged by on the Mac (`browserBars`) and marked as furniture on the page (`markBars`, `markSidebar`), so tab titles and file paths are not sent to the model as page text.
- **Reads stay on the Mac until a lesson needs them.** Glances stay on the Mac until the student picks on the card. After a document switch, the new run plays on (and so sends the new page to the server) only when the old lesson was playing and the new page's kind is sure and in `PLAYS_ON_SWITCH`; a chat, a form or a page it cannot identify stands paused and asks the server nothing until Play. The `screen` field carries only a kind and a slide counter; `screenField` and `ScreenIn` drop anything else.
- **Secure input.** While it is on (the login window's hold excepted), the companion pictures no window, `ident` reports no other app's window, the chord is off, and a switch waits instead of reading.
- **Private apps.** `PRIVATE_APPS` (password managers, Keychain Access, System Settings) are never pictured by the companion, never get a careful read, and are never followed to as another reading app (`isPrivateApp`).
- **Tutornote's own windows** are never pictured: `read` skips them and the companion treats them as `own`.
- **The tutor never moves the cursor or clicks for the student.** No call in the screen helper moves the pointer, clicks or types. The only input it posts is a lesson's own page turn: wheel steps (`postScroll`) or one of six navigation keys (`pressKey`), and only with Accessibility allowed; its scroll events carry `POSTED_BY_US`. Before a key it raises the read window and brings its app to the front through Accessibility (`bringForward`). It never takes or blocks an event: global monitors only see what other apps get, and the chord is polled, with no event tap.
- **No pictures or audio on disk.** A read's picture is dropped once read; small grey thumbnails stay in memory for comparison only (the last read look of up to `SEEN_KEPT`, 64, windows). The speech helper keeps no audio but the 2 s ring in memory, cleared when the microphone stops.
- **Permissions.** The speech helper asks for the microphone and speech recognition only at `start`; `warm`, `prepare` and `output` never ask. Both helpers refuse to run for any parent but Tutornote. The page's IPC is taken only from the app's own origin, and the `screenTeach` handlers only from the lesson window.
- **Tests use synthetic text.** The Mac app's unit tests, the helpers' self tests and the web test files named under "Building, testing and installing" run on made up reads, made up words drawn with CoreText, made up window lists, made up audio and made up presses. (One other file in the web checkout's ignored `scripts/tests/` loads the boxes of a recorded read with every letter masked; it is in neither repo.)

## Building, testing and installing
Node 22.12 or later is needed (`scripts/use-node.sh` finds one through nvm when the shell has an older one).

**1. Build the web app into `renderer/`.**
```sh
ANOTHERNOTES_WEB_DIR=<web checkout> scripts/build-renderer.sh
```

It runs `npm ci` in the web checkout when its dependencies are missing or stale, builds it with `npm run build:off`, copies its `dist` into `renderer/` and writes `renderer/BUILD`. Without `ANOTHERNOTES_WEB_DIR` it clones or updates a checkout in `.web/` (`ANOTHERNOTES_WEB_REF` picks a branch or tag there).

**2. Build the app and the helpers.**
```sh
npm run build
```

This is `tsc -p tsconfig.json`, then `scripts/build-speech-helper.sh` and `scripts/build-screen-helper.sh` (see "Native helpers").

**3. Package an unpacked app**, with the Electron already in `node_modules` instead of a download:
```sh
scripts/use-node.sh npx electron-builder --dir --config electron-builder.config.cjs --config.electronDist=node_modules/electron/dist
```

This gives `release/mac-arm64/Tutornote.app` on Apple silicon (`release/mac/` on Intel, electron-builder's folder for its default architecture). `npm run pack` runs step 2 and the same packaging in one go, without the `electronDist` setting, and `npm run dist:mac` builds the universal `.dmg` and `.zip`. `scripts/run-mac.sh` points `release/` at a folder outside iCloud Drive when the project is in a synced folder, because codesign refuses files with iCloud metadata.

**4. Install.** Quit Tutornote first (it allows one running copy). `ditto` copies over an existing app and leaves its old files, so remove the old copy first:
```sh
rm -rf /Applications/Tutornote.app
ditto release/mac-arm64/Tutornote.app /Applications/Tutornote.app
codesign --verify --deep --strict --verbose=2 /Applications/Tutornote.app
codesign -dv /Applications/Tutornote.app/Contents/Resources/tutornote-screen
codesign -dv /Applications/Tutornote.app/Contents/Resources/tutornote-speech
```

The last two show each helper's signing identifier (`app.tutornote.desktop.screen`, `app.tutornote.desktop.speech`).

**5. Check the Mac app.**
```sh
npx tsc -p tsconfig.json --noEmit
npm test
build/helpers/tutornote-screen --selftest
build/helpers/tutornote-speech --selftest
```

`npm run typecheck` is the same `tsc` check. `npm test` runs `node --experimental-strip-types --test` over the seven files in `scripts/tests/`: `boardHost`, `boardPlace`, `companionPlace`, `speechLog`, `apiTiming`, `launchReveal` and `docIdentity`. The packaged helpers take `--selftest` too, under `Tutornote.app/Contents/Resources/`. `build/helpers/tutornote-screen --chordtest` is for a person at the keyboard (20 s).

**6. Check the web app**, in the web checkout:
```sh
npx tsc --noEmit -p tsconfig.app.json
for f in contentKind screenDocIdentity screenOwnMove screenBlocks screenHold \
         voiceHold voiceTalk voiceMicShare voiceTiming voiceAsk; do
  node --experimental-strip-types --test "scripts/tests/$f.test.ts"
done
```

The web app's own `npm test` imports `scripts/tests/register-alias.mjs`, which is not in the checkout, so each file is run on its own. The web repo ignores `scripts/tests/`, so these files live in the checkout only.

Results when this was written, on one Apple silicon Mac with Node 22.23.2: the Mac app's `tsc` clean and `npm test` 91 of 91 passing (`docIdentity` 22, `companionPlace` 19, `boardHost` 15, `boardPlace` 14, `launchReveal` 8, `speechLog` 8, `apiTiming` 5); both helpers' `--selftest` passing; the web app's `tsc` clean; the six voice and hold files 90 passing and the four screen files 59 passing. The backend has no automated tests for `ScreenIn` or the per kind rules.

## Not verified on real hardware yet
These checks cover the pure rules and the helpers' made up inputs. The items below depend on real Macs, apps and devices, and have not been tried for this write up.

Following the screen (round 4):
- The switch flow in `screenTeach.ts` (ident handling, the still wait, retries, waits, following another app, the handshake, the new run) has no unit tests and has not been run on a real Mac. The tab switch timeline above is worked out from the constants; the `[screen-teach]` log lines are where real timings will show.
- It needs a screen helper that sends `ident` and knows `still`. With an older helper only a "tap" switch can happen, and only with the companion on; an older helper also waits for a change instead of stillness, up to the 1.5 s timeout.
- It needs a renderer built from a web app whose lesson page listens on `screen-teach:switching`. Without it, no switch starts.
- Switching tabs in a real browser, Arc's sidebar, a card withdrawn when the document in its window changes, and how the 600 ms new part dwell feels.
- The code, table and form thresholds, which were set by hand.
- Whether the server the app talks to runs the merged backend change.

Voice (round 3):
- How the chord feels with 33 ms polling on different keyboards, and whether the 0.7 s tap limit is right.
- Whether a process without Input Monitoring sees the modifier flags. Apple does not document it; the helper detects the case and reports `"why":"hidden"`.
- Poll timing under load and App Nap. The helper logs `polls N ms apart` once if it happens.
- Whether ⌃⌥M still fires while secure input is on, and whether holding it makes macOS repeat it. The code treats every ⌃⌥M as a tap. The "press and hold {key}" lines in `TALK_COPY` name ⌃⌥M as the key in the screen tutor when the chord is off, but holding ⌃⌥M does not turn talk mode on there; holding the dock's mic is the only hold that works then.
- The speakers or headphones verdict on real devices, especially Bluetooth and USB devices whose names are in neither `WORN_NAMES` nor `LOUD_NAMES`. They fall to speakers.
- Whether the tails are long enough in real rooms. `TALK_TAIL_MS` was sized from one MacBook's log; no measurement in the code backs the longer tails.
- How well the echo check holds up against sound leaking out of headphones.
- `voiceQuietMs` follows only the shared audio element, not the browser's own speech synthesis voice.

Windows and the companion:
- The loader coming up only after 1 s, and its fade.
- The panels never bringing Tutornote forward.
- The blob dragged across displays.
- The double click rule in real readers and browser PDF tabs.
- The board moving between its tab and its own window.

The helpers on macOS:
- Disclaiming on every macOS version the helpers support.
- Which name System Settings shows for each helper (`CFBundleName` or `CFBundleDisplayName`) on a Developer ID signed, notarised build. On a locally packaged build signed with a development certificate, the packaged helpers keep their identifiers (`codesign -dv`); a Developer ID build has not been checked.
