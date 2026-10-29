/*
  Tutornote's screen helper: reads the words in another app's window (Kindle, a PDF in
  Chrome or Preview) so the tutor can teach the page the student points at. It finds the
  window under a point on the screen, takes one picture of that window alone, and reads its
  text with Apple's Vision framework, on this Mac. Nothing is kept: the picture is dropped
  once read, and only the lines and their words go back to the app (and, with a read a lesson
  teaches from, where the page's paper, rules and other marks are: numbers, never pixels).

  During a lesson it also turns that window's page: it scrolls it or presses a key in its
  app (which needs Accessibility), or waits for the student to do it, then watches small
  grey pictures of the window until the new page has stopped moving. A window that already
  looks different from its last read was moved by the student: asked (unlessMoved), the
  helper takes that as the turn and posts nothing.

  With the desktop companion on (the tutor that trails the cursor over any app), it also
  says which window the cursor is over, hears presses, taps and scrolls on any window (never
  taking them), and keeps an eye on up to two windows (the lesson's and the one under the
  cursor) with a thumbnail twice a second, to say when one has settled into a new look (a
  page the student turned). It never moves the cursor, and it never clicks or types: the only
  input it ever posts is a lesson's own turn (postScroll, pressKey), as before.

  While the app's talk key is on, it also watches for the talk chord: Control and Option pressed
  on their own, a tap to ask the tutor one question, a 5 s hold for talk mode. It does so by
  looking at which modifier keys are held, thirty times a second; it never takes a key, and
  needs no permission for it ("The talk chord").

  Protocol (src/main/screen.ts has the TypeScript side), one JSON object per line:
    in   {"cmd":"status"}                          may this Mac's screen be read?
         {"cmd":"request"}                         ask macOS for Screen Recording (once)
         {"cmd":"ax","prompt":false}               may the helper scroll and press keys?
                                                   (true shows macOS's own prompt)
         {"cmd":"read","id":1,"x":640,"y":400,"exclude":[123]}
                                                   the window under (x, y), in screen points
                                                   from the top left of the main display, of
                                                   any process but those in `exclude`
         {"cmd":"read","id":1,"window":12345}      a window read before, by its id
         {"cmd":"read",…,"level":"fast"}           either of them, read quickly (a glance:
                                                   Vision's fast pass, no language
                                                   correction; once more accurately when it
                                                   finds no words on a window that is not
                                                   blank)
         {"cmd":"turn","id":2,"window":12345,"pid":678,"how":"scroll","dy":600,
          "at":{"x":…,"y":…},"timeoutMs":4000}     scroll by dy points (more than 0 shows
                                                   later content), the wheel over `at`
         {"cmd":"turn",…,"how":"key","key":"right","count":1}
                                                   right, left, pagedown, pageup, down, up
         {"cmd":"turn",…,"how":"manual","timeoutMs":180000}
                                                   post nothing; wait for the student's turn
         {"cmd":"turn",…,"unlessMoved":true}       any of them: if the window has moved since
                                                   its last read, that is the turn
         {"cmd":"turn",…,"how":"manual","still":true,"timeoutMs":1500}
                                                   no turn: a wait for the window to be still
                                                   (a lesson switching documents), answered as
                                                   soon as two thumbnails in a row agree, changed
                                                   or not ("changed": it differs from its last
                                                   read; "still": it was still in time); the watch
                                                   for a new look ("observe") is not kept quiet
                                                   for it, as it is for a turn
         {"cmd":"cancel","id":2}                   give a turn up (it answers "cancelled")
         {"cmd":"watch","window":12345}            tell the student's taps on that window, which
                                                   app is in front, and which document the
                                                   window shows ("ident"), until "unwatch"
         {"cmd":"unwatch"}
         {"cmd":"companion","on":true,"stop":[45,67],"private":["com.apple.keychainaccess"],
          "readers":["com.amazon.Lassen"]}         the companion on (or off): say which window
                                                   the cursor is over ("over"), and hear
                                                   presses, taps and scrolls on any ordinary
                                                   window. `stop`: Tutornote's own floating
                                                   windows (the blob, the board), which count
                                                   as its own, as its ordinary windows do.
                                                   `private`: the apps whose windows are never
                                                   pictured (a tap there is told with no
                                                   picture taken, "acted" false). `readers`:
                                                   the apps whose bars fade in and out at a
                                                   click on their page (judgeTap vets the look)
         {"cmd":"observe","windows":[12345,23456],"page":[12345]}
                                                   watch these (two at most) for a new look
                                                   ("changed"), the companion on or not (the
                                                   app asks for the lesson's window and the one
                                                   under the cursor while it is on, and for the
                                                   lesson's window alone while it is paused or
                                                   off); [] stops, as "companion" off does.
                                                   "page" (optional): those of them that turn
                                                   by the page (Kindle, Books), where no wheel
                                                   explains a new look (scrollExplains)
         {"cmd":"chord","on":true}                 watch for the talk chord (Control and Option
                                                   pressed on their own, in any app: "The talk
                                                   chord", polled, no permission), or stop (a
                                                   chord under way says "cancel", "off")
    out  {"ev":"status","screen":true}
         {"ev":"ax","trusted":true}                status and ax are answered in order
         {"id":1,"ev":"read","app":"Kindle","bundle":"com.amazon.Lassen","title":"…",
          "window":12345,"pid":678,"frame":{"x":…,"y":…,"w":…,"h":…},
          "lines":[{"t":"…","c":0.98,"x":…,"y":…,"w":…,"h":…,
                    "words":[{"t":"…","x":…,"y":…,"w":…,"h":…,"wg":true}]}],
          "captureMs":120,"ocrMs":640,"ground":0.94,"level":"accurate","wordless":0,"guessed":1,
          "paper":{…},"rules":[{…}],"ink":{"x":…,"y":…,"cell":8,"cols":63,"rows":113,"bits":"…"},
          "inkMs":7}
                                                   line and word boxes in screen points too;
                                                   a word Vision cannot place is placed by its
                                                   share of the line's characters between its
                                                   neighbours, "wg" (guessed: wordBoxes); a line
                                                   Vision places none of has no words.
                                                   "wordless", "guessed": how many lines went
                                                   without words, and how many words were guessed.
                                                   "paper", "rules", "ink" (a read at the accurate
                                                   level only, never a glance: "What else the page
                                                   draws"): where the page's paper is (none when
                                                   it cannot be told), the rules drawn on it (64 at
                                                   most), and a grid of 8 point cells over the
                                                   paper (else the window), 400 at most each way,
                                                   a cell's bit set where it is drawn on besides
                                                   the words (base64; cell r * cols + c is bit
                                                   i & 7 of byte i >> 3); "inkMs": finding them.
                                                   "ground": how bright the window is, 0 (black)
                                                   to 1 (white), from its thumbnail; "level":
                                                   the pass that read it, "fast" or "accurate";
                                                   "heldMs" (only when it waited): how long its
                                                   words waited, once pictured, for a companion
                                                   tap being judged (tapsJudged)
         {"id":2,"ev":"turned","changed":true,"settleMs":420,"moved":false,"front":true}
                                                   whether the window shows something else,
                                                   once still (or at timeoutMs); "moved": it
                                                   had moved already (unlessMoved), nothing
                                                   posted; "front" (keys only): its app came
                                                   to the front to take them
         {"ev":"tap","x":…,"y":…,"window":12345,"moved":false,"alt":false}
                                                   a tap on the watched window; "moved": it no
                                                   longer looked as it did at its last read when
                                                   it was pressed (its middle rows); "alt":
                                                   Option was held
         {"ev":"release","id":7,"x":…,"y":…,"window":12345,"alt":false,"clicks":1,
          "hand":false,"private":false}            with the companion on: a tap on any ordinary
                                                   window has just ended, said at once, before
                                                   anything is judged; "id": its verdict's too
                                                   (counted on from the clock in milliseconds at
                                                   the helper's start: never the same twice);
                                                   "clicks": 2 or more for a double click;
                                                   "hand": the cursor was a pointing hand at the
                                                   press (a link); "private": nothing of that
                                                   window is pictured (a private app, or secure
                                                   input)
         {"ev":"tap","id":7,…,"acted":false,"words":"kept","kept":0.83,"shift":-23,"textMs":21,
          "wide":false,"line":0.2,"away":3.7,"look":0.4}
                                                   then the verdict on it: "acted": the click did
                                                   something in its app (a link, a button, a page
                                                   turn, a menu); "words": what decided it
                                                   (companionTap): "covered" (another window is
                                                   on top at the tap now), "title" (the window's
                                                   title changed), "skipped" (the tapped line's
                                                   patch did not change, so no words were read),
                                                   then by the words at the tap (or, on a margin,
                                                   the rows near it): "kept", "gone", "none" (no
                                                   words there or near: the pixels decide),
                                                   "content" (the tapped label stayed, the
                                                   content away from it changed), "caret" (the
                                                   click put a caret there), "pixels" (the words
                                                   could not be read in time: the pixels decide);
                                                   "select" for a double click; "kept", "shift":
                                                   the share of the tapped row's words found
                                                   again, and how far they moved (points, up less
                                                   than 0); "textMs": reading them; "line",
                                                   "away": the tapped line's patch difference and
                                                   the window's away from it, 0 to 255; "wide":
                                                   away changed too; "look": the age in seconds
                                                   of the watch's look it was judged against as
                                                   well, or -1
         {"ev":"press","x":…,"y":…,"window":12345} with the companion on: the button went down
                                                   on an ordinary window (at once, before any
                                                   picture); with it off, on the watched window
                                                   alone
         {"ev":"over","window":12345,"pid":678,"app":"Kindle","bundle":"…","title":"…",
          "frame":{…},"own":false,"secure":false}  with the companion on: the window the cursor
                                                   is over changed. "window" null over nothing
                                                   or over Tutornote's own ("own"); "secure": a
                                                   password field somewhere has the keys
         {"ev":"changed","window":12345,"settleMs":300}
                                                   an observed window settled into a new look
                                                   (once, until it looks different again) that
                                                   no wheel scroll told already explains (one
                                                   up or down, in a window not observed as
                                                   "page"); its middle rows only (a change in
                                                   its top and bottom 12% alone, a reader's
                                                   bars, is none)
         {"ev":"keyed","window":12345}             a key went down in the watched window's app,
                                                   in front, that window observed (the first of
                                                   a run of keys, then one at most every
                                                   KEY_RUN_S while they keep coming: keyTick);
                                                   never which key, and never a lesson's own
                                                   turn's
         {"ev":"front","pid":678,"bundle":"…"}     the app in front (on watch, then on each change)
         {"ev":"ident","window":12345,"title":"…","onScreen":true,"frame":{…},"top":12345,
          "topTitle":"…","topFrame":{…},"other":{"window":23456,"pid":789,"app":"Preview",
                                  "bundle":"…","title":"…","frame":{…}},"secure":false}
                                                   the watched window's title and whether it is
                                                   on the screen; "frame": where it is (left out
                                                   once it is listed no more: closed), so a drag
                                                   of it, its app in front or not, is said on
                                                   every tick while it goes; "top" (null while its app is
                                                   not in front): its app's front ordinary
                                                   window, "topTitle" and "topFrame" its title and
                                                   frame; "other" (only while another app is in
                                                   front, not Tutornote, not under secure input):
                                                   that app's front ordinary window; "secure":
                                                   a password field somewhere has the keys. Said as the
                                                   watch starts, then whenever any of it changes
                                                   (looked at every IDENT_MS, and as an app comes
                                                   to the front)
         {"ev":"scroll","dy":12.5,"dx":0,"lines":0,"momentum":false,"window":12345}
                                                   the student scrolled the watched window (with
                                                   the companion on, the one under the cursor):
                                                   its content moved up by dy points (down if
                                                   less than 0) and left by dx; "lines": a mouse
                                                   wheel's lines in dy's sense, each taken as
                                                   WHEEL_LINE_PT points in dy (0 for a trackpad's
                                                   points: wheelStep); "momentum": the glide
                                                   after the fingers left the trackpad; never
                                                   the helper's own turns
         {"ev":"chord","kind":"tap","ms":180,"keys":"lctrl+lopt"}
                                                   the talk chord, with "chord" on: "down" (held
                                                   300 ms: the page shows the hold's ring), "hold"
                                                   (held 5 s, once), then at the release "up"
                                                   (after a hold), "tap" (held 700 ms or less, with
                                                   or without a "down" before it) or "cancel" with
                                                   "why": "long" (let go between the two), or
                                                   spoiled after its "down" by "key", "mouse",
                                                   "wheel", "modifier", "voiceover", "secure", or
                                                   "off" (the watch stopped). A chord spoiled
                                                   before its "down" says nothing here (the log
                                                   says it, a line a second at most). "ms": how
                                                   long it had been held; "keys" (for the log
                                                   only): which sides
         {"ev":"chord","kind":"state","on":false,"why":"voiceover"}
                                                   whether the chord can be used at all: said as
                                                   "chord" goes on, then on each change. Off while
                                                   VoiceOver is on ("voiceover"), while secure
                                                   input is (found as the keys are pressed:
                                                   "secure"), or once the modifier keys look
                                                   hidden from this helper ("hidden")
         {"id":1,"ev":"error","code":"…"}          no_permission, no_window, window_gone,
                                                   no_access, capture_failed, bad_command,
                                                   cancelled

  `tutornote-screen --selftest` checks the picture arithmetic, the words rule, and a page's paper,
  rules and ink on pictures it draws itself (no screen needed), a line's guessed words on made up
  boxes, a wheel's step and the keys that burst a window on made up numbers, and the talk chord's
  steps on made up presses, and exits 0 or 1. `tutornote-screen --chordtest` (in Terminal, for a person at the keyboard) prints what the
  chord's polls see for 20 s; it needs no app, shows no window and asks for nothing.

  Needs macOS 14 (ScreenCaptureKit's one-picture capture). The app shows no button when the
  helper is missing.
*/
import AppKit
import ApplicationServices
import Carbon
import CoreText
import Darwin
import Foundation
import ScreenCaptureKit
import Security
import Vision

// MARK: - Only for Tutornote

/*
  Once Screen Recording is allowed, the permission is this helper's (it is its own
  responsible process, below), so any program that ran it could read the screen through it.
  So, as the speech helper does, it runs only for the Tutornote app: its parent (the
  disclaimed copy's grandparent) must be signed as app.tutornote.desktop by the same team as
  the helper. A development build signed ad hoc has no team; then the identifier alone, or
  Electron's own (npm start), will do.
*/
let TUTORNOTE_ID = "app.tutornote.desktop"
/// The Tutornote app that started the helper (checked below): its windows are its own to the
/// companion, by their process, in a development build too (which runs as Electron).
var tutornoteAppPid: pid_t = 0

func parentPid(of pid: pid_t) -> pid_t {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
    return info.kp_eproc.e_ppid
}

func ownTeam() -> String? {
    var me: SecCode?
    guard SecCodeCopySelf([], &me) == errSecSuccess, let me else { return nil }
    var file: SecStaticCode?
    guard SecCodeCopyStaticCode(me, [], &file) == errSecSuccess, let file else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(file, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let fields = info as? [String: Any]
    else { return nil }
    return fields[kSecCodeInfoTeamIdentifier as String] as? String
}

func signed(_ pid: pid_t, as requirement: String) -> Bool {
    var code: SecCode?
    let guest = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, guest, [], &code) == errSecSuccess, let code else { return false }
    var req: SecRequirement?
    guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
    return SecCodeCheckValidity(code, [], req) == errSecSuccess
}

func refuseUnlessLaunchedByTutornote() {
    let disclaimed = ProcessInfo.processInfo.environment[DISCLAIMED_ENV] != nil
    let app = disclaimed ? parentPid(of: getppid()) : getppid()
    let requirements: [String]
    if let team = ownTeam() {
        requirements = ["identifier \"\(TUTORNOTE_ID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""]
    } else {
        requirements = ["identifier \"\(TUTORNOTE_ID)\"", "identifier \"com.github.Electron\""]
    }
    if app > 1 && requirements.contains(where: { signed(app, as: $0) }) {
        tutornoteAppPid = app
        return
    }
    log("[screen] not started by the Tutornote app (process \(app)): refusing to read the screen")
    exit(1)
}

// MARK: - Its own responsible process

/*
  macOS asks for Screen Recording on behalf of the "responsible" process: the app, or the
  terminal the app was started from (npm run mac from VS Code), which would then be the one
  listed and allowed. So, as the speech helper does, the helper starts itself again, once,
  disclaimed: the new copy is responsible for itself, and System Settings lists it by its
  own name (helpers/screen/Info.plist, embedded in the binary).
*/
let DISCLAIMED_ENV = "ANOTHERNOTES_SCREEN_DISCLAIMED"
var disclaimedChild: pid_t = 0

func runDisclaimedIfNeeded() {
    guard ProcessInfo.processInfo.environment[DISCLAIMED_ENV] == nil,
          let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim")
    else { return }
    typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    let setDisclaim = unsafeBitCast(symbol, to: SetDisclaim.self)
    var attr: posix_spawnattr_t?
    guard posix_spawnattr_init(&attr) == 0 else { return }
    defer { posix_spawnattr_destroy(&attr) }
    guard setDisclaim(&attr, 1) == 0 else { return }
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size) + 1)
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { return }
    let path = String(cString: buffer)
    var env = ProcessInfo.processInfo.environment
    env[DISCLAIMED_ENV] = "1"
    let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
    let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, path, nil, &attr, argv, envp)
    guard rc == 0 else {
        log("[screen] could not start a disclaimed copy (\(rc)); carrying on")
        return
    }
    disclaimedChild = pid
    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig) { s in
            if disclaimedChild > 0 { kill(disclaimedChild, s) }
            exit(0)
        }
    }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
    let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 1
    exit(code)
}

// MARK: - Output

let outputLock = NSLock()

func emit(_ fields: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(fields),
          let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    else { return }
    outputLock.lock()
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    outputLock.unlock()
}

func log(_ message: String) {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
}

func msSince(_ start: DispatchTime) -> Int {
    Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
}

func sleepMs(_ ms: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000)
}

// MARK: - Finding a window

/// A window of another app, as the window server lists it.
struct Target {
    let id: CGWindowID
    let pid: pid_t
    /// In screen points from the top left of the main display.
    let frame: CGRect
    let owner: String
    let title: String
}

func target(from info: [String: Any]) -> Target? {
    guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
          let number = info[kCGWindowNumber as String] as? CGWindowID,
          let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: boundsDict)
    else { return nil }
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    let title = info[kCGWindowName as String] as? String ?? ""
    return Target(id: number, pid: pid, frame: bounds, owner: owner, title: title)
}

/// A window of Tutornote itself, or of an older copy of it (AnotherNote, the name it had until
/// October): never the page a lesson reads. On 2026-10-25 an old AnotherNote window left open in
/// front of the student's PDF was picked, and the tutor taught its "Couldn't reach the server".
func isTutornote(_ pid: pid_t) -> Bool {
    guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
    return bundle.hasPrefix("app.tutornote.") || bundle.hasPrefix("app.anothernote.") || bundle.hasPrefix("app.anothernotes.")
}

/// The window that is on top at (x, y), in screen points from the top left of the main
/// display, skipping the processes in `exclude` (the app's own overlay and panels), any copy
/// of Tutornote, and anything that is not an ordinary window (menus, the Dock, the menu bar:
/// layer 0 only).
func windowAt(_ point: CGPoint, excluding exclude: Set<pid_t>) -> Target? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    // Front to back.
    for info in list {
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let found = target(from: info), !exclude.contains(found.pid), !isTutornote(found.pid),
              found.frame.contains(point), found.frame.width > 40, found.frame.height > 40
        else { continue }
        if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
        return found
    }
    return nil
}

/// A window read before, where it is now: nil once it is closed, minimised or on another
/// Space, since a picture of it would then show nothing the student can see.
func onScreenWindow(_ number: CGWindowID) -> Target? {
    guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], number) as? [[String: Any]],
          let info = list.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == number }),
          (info[kCGWindowIsOnscreen as String] as? Bool) == true
    else { return nil }
    return target(from: info)
}

/*
  A full-screen app's Space sliding in or out (the student swiping to Kindle full screen and back)
  takes its windows off the screen for a moment: the window server still lists them, but not as on
  screen. A read by id then waits, looking again every POLL_MS for up to SPACE_WAIT_MS, before it
  says window_gone; one that is not listed at all is gone at once.
*/
let SPACE_WAIT_MS = 1200

/// Whether the window server still lists `number`, on screen or not.
func windowListed(_ number: CGWindowID) -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], number) as? [[String: Any]] else { return false }
    return list.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == number }
}

/// onScreenWindow, waiting while the window is listed but not on screen (a Space switching).
func onScreenSoon(_ number: CGWindowID) async -> Target? {
    var waited = 0
    while true {
        if let found = onScreenWindow(number) { return found }
        guard waited < SPACE_WAIT_MS, windowListed(number) else { return nil }
        await sleepMs(POLL_MS)
        waited += POLL_MS
    }
}

/// ScreenCaptureKit's own handle on a window, to take pictures of it alone.
func shareableWindow(_ number: CGWindowID) async throws -> SCWindow? {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    return content.windows.first(where: { $0.windowID == number })
}

// MARK: - Reading a window

/// Pixels per point on the display that holds most of `frame`.
func scaleFor(_ frame: CGRect) -> CGFloat {
    let center = CGPoint(x: frame.midX, y: frame.midY)
    for screen in NSScreen.screens {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
        if CGDisplayBounds(CGDirectDisplayID(number.uint32Value)).contains(center) { return screen.backingScaleFactor }
    }
    return NSScreen.main?.backingScaleFactor ?? 2
}

/// The biggest picture read: wide enough for small print, small enough for a quick read.
let MAX_PIXELS_WIDE: CGFloat = 3600

/// Which window a read is for: the one under the student's click (a new pick), or one read
/// before (the next page of a lesson), which may have moved since.
enum Which {
    case at(CGPoint, exclude: Set<pid_t>)
    case window(CGWindowID)
}

/// A word of a line as a read sends it: its text, its box, and whether the box is only guessed
/// (wordBoxes: Vision could not place it).
typealias ReadWord = (text: String, box: CGRect, guessed: Bool)

/// A line's words, each a run of anything but spaces (so its punctuation comes with it), with
/// Vision's box for it: a fraction of the picture from its bottom left, like the line's own.
/// Vision cannot always place a word (no box, a box of nothing, or on a line of two words or
/// more a box of 95% of the line or more, as it gives for some scripts). Such a word is placed
/// by its share of the line's characters, as textRows places a row's words, but only across the
/// room between the words Vision did place either side of it (the line's own ends past the first
/// and the last), so it lies in order, clear of them and inside the line, which the page needs
/// to keep a line's word boxes at all (screenBlocks cleaned); and it is flagged guessed. One
/// failing word used to cost the whole line its words. Nil, as then, only when Vision places
/// none of them, or leaves one no room between its neighbours: the line goes without words and
/// the page places it as one piece, rather than with words piled on top of each other. `box`:
/// Vision's box for a word, given its range in `string`.
func wordBoxes(_ string: String, lineBox: CGRect, box: (Range<String.Index>) -> CGRect?) -> [ReadWord]? {
    var runs: [(range: Range<String.Index>, from: Int, to: Int)] = []
    var index = string.startIndex
    var at = 0
    while let start = string[index...].firstIndex(where: { !$0.isWhitespace }) {
        let end = string[start...].firstIndex(where: { $0.isWhitespace }) ?? string.endIndex
        let from = at + string.distance(from: index, to: start)
        let to = from + string.distance(from: start, to: end)
        runs.append((start..<end, from, to))
        index = end
        at = to
    }
    guard !runs.isEmpty else { return nil }
    let placed: [CGRect?] = runs.map { run in
        guard let found = box(run.range), found.width > 0, found.height > 0, found.minX.isFinite, found.maxX.isFinite,
              runs.count == 1 || found.width < lineBox.width * 0.95
        else { return nil }
        return found
    }
    let anchors = placed.compactMap { $0 }
    guard let first = anchors.first, let last = anchors.last else { return nil }
    // A line laid right to left (Vision's boxes running leftwards): its characters count from its
    // right. With one word placed there is no run of boxes to tell by, and the line's script tells
    // (a guess laid left to right on a Hebrew line would put each word on another's place).
    let leftwards = anchors.count > 1 ? first.midX > last.midX : rightToLeft(string)
    let characters = string.count
    var words: [ReadWord] = []
    for (i, run) in runs.enumerated() {
        let text = String(string[run.range])
        if let found = placed[i] {
            words.append((text, found, false))
            continue
        }
        // The room it shares with the other unplaced words beside it: from the end of the word
        // placed before it (or the line's start) to the start of the one placed after it (or the
        // line's end), as characters and as the line's x.
        let before = placed[..<i].lastIndex(where: { $0 != nil })
        let after = placed[(i + 1)...].firstIndex(where: { $0 != nil })
        let fromChar = before.map { runs[$0].to } ?? 0
        let toChar = after.map { runs[$0].from } ?? characters
        let fromX = before.map { leftwards ? placed[$0]!.minX : placed[$0]!.maxX } ?? (leftwards ? lineBox.maxX : lineBox.minX)
        let toX = after.map { leftwards ? placed[$0]!.maxX : placed[$0]!.minX } ?? (leftwards ? lineBox.minX : lineBox.maxX)
        let room = leftwards ? fromX - toX : toX - fromX
        guard room > 0, toChar > fromChar else { return nil }
        func x(_ char: Int) -> CGFloat { fromX + (leftwards ? -1 : 1) * room * CGFloat(char - fromChar) / CGFloat(toChar - fromChar) }
        let a = x(run.from)
        let b = x(run.to)
        words.append((text, CGRect(x: min(a, b), y: lineBox.minY, width: abs(b - a), height: lineBox.height), true))
    }
    return words
}

/// Whether a line is written right to left: its first letter is in a script written that way
/// (Hebrew, Arabic and their neighbours).
func rightToLeft(_ string: String) -> Bool {
    guard let letter = string.unicodeScalars.first(where: { $0.properties.isAlphabetic }) else { return false }
    switch letter.value {
    case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF: return true
    default: return false
    }
}

/// A line's words as Vision read them (wordBoxes).
func words(of text: VNRecognizedText, lineBox: CGRect) -> [ReadWord]? {
    wordBoxes(text.string, lineBox: lineBox) { range in (try? text.boundingBox(for: range))?.boundingBox }
}

/// A line as a read sends it, in screen points: its text and Vision's confidence, its box, and
/// its words (nil: it goes without them).
struct ReadLine {
    let text: String
    let confidence: Double
    let box: CGRect
    let words: [ReadWord]?
}

/// Vision's lines as a read sends them, front to back. Vision's boxes are fractions of the
/// picture from its bottom left, and the picture is the window's `frame`: this puts a line or a
/// word back in screen points from the top left.
func readLines(_ observations: [VNRecognizedTextObservation], frame: CGRect) -> [ReadLine] {
    func place(_ box: CGRect) -> CGRect {
        CGRect(x: frame.minX + box.minX * frame.width, y: frame.minY + (1 - box.maxY) * frame.height,
               width: box.width * frame.width, height: box.height * frame.height)
    }
    var lines: [ReadLine] = []
    for observation in observations {
        guard let best = observation.topCandidates(1).first else { continue }
        let text = best.string.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { continue }
        let found = words(of: best, lineBox: observation.boundingBox)?.map { (text: $0.text, box: place($0.box), guessed: $0.guessed) }
        lines.append(ReadLine(text: text, confidence: Double(best.confidence), box: place(observation.boundingBox), words: found))
    }
    return lines
}

/// A box's fields as the protocol sends them, with `fields` of its own.
func boxFields(_ box: CGRect, _ fields: [String: Any] = [:]) -> [String: Any] {
    fields.merging(["x": Double(box.minX), "y": Double(box.minY), "w": Double(box.width), "h": Double(box.height)]) { _, new in new }
}

/*
  Two passes. "accurate" (every read before the companion, and every read a lesson teaches
  from): Vision's accurate pass with language correction, 0.3 to 1 s on a full page. "fast" (a
  glance: the companion's read of the window under the cursor, for the hover band, or a
  lesson's quick check after a scroll): the fast pass without language correction, about a
  quarter of that, with boxes good enough for paragraphs and lines. A fast pass that finds no
  words on a window that is not blank (a page in a hand Vision's fast pass cannot read) is
  run again accurately, once, so a glance is never empty for want of trying.
*/
enum Level: String {
    case fast
    case accurate
}

/// The words in `image` at `level`: Vision's lines, front to back.
func recognize(_ image: CGImage, _ level: Level) throws -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level == .fast ? .fast : .accurate
    request.usesLanguageCorrection = level == .accurate
    // (only the accurate pass detects the language; the fast one reads Latin script)
    request.automaticallyDetectsLanguage = level == .accurate
    try VNImageRequestHandler(cgImage: image).perform([request])
    return request.results ?? []
}

/// The picture a read is made from, and its thumbnail (`small`) taken alongside it rather than
/// after: the same moment, which unlessMoved and observe compare later looks with, in the time of
/// the one picture.
func picture(_ filter: SCContentFilter, _ config: SCStreamConfiguration, _ small: SCStreamConfiguration) async throws -> (image: CGImage, thumb: [UInt8]?) {
    async let image = SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    async let thumb = thumbnail(filter, small)
    let taken = try await image
    return (taken, try? await thumb)
}

func read(id: Int, which: Which, level: Level = .accurate) async {
    guard CGPreflightScreenCaptureAccess() else {
        emit(["id": id, "ev": "error", "code": "no_permission"])
        return
    }
    let found: Target?
    let missing: String
    switch which {
    case let .at(point, exclude):
        found = windowAt(point, excluding: exclude)
        missing = "no_window"
    case let .window(number):
        found = await onScreenSoon(number)
        missing = "window_gone"
    }
    guard let target = found else {
        emit(["id": id, "ev": "error", "code": missing])
        return
    }
    let started = DispatchTime.now()
    let image: CGImage
    var seen: [UInt8]?
    do {
        let config = SCStreamConfiguration()
        let scale = min(scaleFor(target.frame), MAX_PIXELS_WIDE / max(target.frame.width, 1))
        config.width = Int(target.frame.width * scale)
        config.height = Int(target.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let small = thumbnailConfig(for: target.frame)
        // Every read, a lesson's careful one too, takes the window's handle from the keep
        // (throughFilter: a few milliseconds) rather than asking for every window on the screen
        // again (tens of milliseconds): the tutor over another app "should be super responsive"
        // (the founder, 2026-10-28). The window alone: nothing drawn over it (the app's own
        // pointer and panel) is in the picture.
        guard let taken = try await throughFilter(target.id, frame: target.frame, { try await picture($0, config, small) }) else {
            emit(["id": id, "ev": "error", "code": missing])
            return
        }
        image = taken.image
        // How it looks as it is read, small: a turn that goes only if the window has not moved
        // since (unlessMoved) compares with this, and so does the companion's watch for a new
        // look (observe). Its brightness is the page's ground.
        seen = taken.thumb
        if let seen { remember(target.id, seen) }
    } catch {
        log("[screen] capture failed: \(error.localizedDescription)")
        emit(["id": id, "ev": "error", "code": "capture_failed"])
        return
    }
    let captureMs = msSince(started)

    // (the picture is taken; its words wait while a companion tap is being judged: tapsJudged)
    let heldMs = await tapsJudged(upTo: TAP_HOLD_MS)
    let ocrStarted = DispatchTime.now()
    var used = level
    var observations: [VNRecognizedTextObservation]
    do {
        observations = try recognize(image, level)
        // (no thumbnail to tell by: tried again too)
        if level == .fast && observations.isEmpty && !(seen.map(isBlank) ?? false) {
            observations = try recognize(image, .accurate)
            used = .accurate
        }
    } catch {
        log("[screen] text recognition failed: \(error.localizedDescription)")
        emit(["id": id, "ev": "error", "code": "capture_failed"])
        return
    }
    let frame = target.frame
    // (placing the words asks Vision for their boxes: part of the reading, as it always was)
    let textLines = readLines(observations, frame: frame)
    let ocrMs = msSince(ocrStarted)
    var lines: [[String: Any]] = []
    // (counts only, to see how often Vision cannot place a word on real pages)
    var wordless = 0
    var guessed = 0
    for line in textLines {
        var fields = boxFields(line.box, ["t": line.text, "c": line.confidence])
        if let placed = line.words {
            fields["words"] = placed.map { boxFields($0.box, $0.guessed ? ["t": $0.text, "wg": true] : ["t": $0.text]) }
            guessed += placed.filter(\.guessed).count
        } else {
            wordless += 1
        }
        lines.append(fields)
    }
    // What else the page draws, for a read a lesson teaches from: never a glance's, even one
    // read again accurately.
    var drawn: [String: Any] = [:]
    if level == .accurate {
        let inkStarted = DispatchTime.now()
        if let geometry = pageGeometry(image, frame: frame, lines: textLines) { drawn = geometryFields(geometry) }
        drawn["inkMs"] = msSince(inkStarted)
    }
    let app = NSRunningApplication(processIdentifier: target.pid)
    var answer: [String: Any] = [
        "id": id,
        "ev": "read",
        "app": app?.localizedName ?? target.owner,
        "bundle": app?.bundleIdentifier ?? "",
        "title": target.title,
        "window": Int(target.id),
        "pid": Int(target.pid),
        "frame": ["x": Double(frame.minX), "y": Double(frame.minY), "w": Double(frame.width), "h": Double(frame.height)],
        "lines": lines,
        "captureMs": captureMs,
        "ocrMs": ocrMs,
        "level": used.rawValue,
        "wordless": wordless,
        "guessed": guessed,
    ]
    answer.merge(drawn) { _, new in new }
    if let seen { answer["ground"] = ground(seen) }
    if heldMs >= TAP_HOLD_POLL_MS { answer["heldMs"] = heldMs }
    emit(answer)
}

// MARK: - What else the page draws

/*
  A read a lesson teaches from also says where the page's paper is and what else is drawn on it
  besides the words read, so the lesson can write on a page in another app as it does on the
  web's own reader (the founder, 2026-10-28: "the part where we write on the PDF documents. That
  has to work in our Mac application"): the paper (a PDF page inside Preview's grey or Chrome's
  dark viewer), the rules drawn across it (an answer's line, a blank's drawn line), and a coarse
  grid of where else it is drawn on (a figure, a drawn box, a hand's working), the words' own
  boxes left out. All of it from the picture already taken, drawn again in grey at a pixel a
  point. Numbers go back, never a pixel; the picture is dropped with the rest once read, and
  none of it is logged here (the app logs counts and times at most).

  Every test is by the distance from the paper's own grey, the commonest one inside the lines
  read (between their letters): a dark page (a night theme) has a dark paper, and light marks
  on it count as dark ones do on a white page.
*/

/// The paper's grey is the commonest (within four shades) inside the lines read only when it
/// is at least this share of them: else the words sit on no one ground (a photograph), and
/// nothing of the page is sent.
let PAPER_PEAK = 0.3
/// A grey this near the paper's (0 to 255) is the paper, when telling it from the viewer around
/// it: a rendered page is one flat grey, and a scan's speckle mostly stays within this.
let PAPER_NEAR = 12
/// A line sits on the paper when this share of its box is the paper.
let PAPER_SITS = 0.5
/// A column (over the lines' rows) or a row (over the paper's columns) with fewer of its pixels
/// paper than this is past the paper's edge: the viewer around a page is all one other grey,
/// while a figure keeps the page's margins either side of it.
let PAPER_EDGE_SHARE = 0.08
/// A grey this far from the paper's is drawn on: a rule, a figure, a box, a stroke (a tinted
/// panel or a pale highlight is not: writing goes over those as over the paper).
let MARK_FAR = 48
/// The words' boxes, this much bigger (points), are left out of the rules and the ink.
let WORD_PAD: CGFloat = 2
/// A rule is a run of marked pixels along a row at least RULE_MIN points long (or RULE_MIN_SHARE
/// of the paper's width, if more), at most RULE_THICK rows thick together, as the web's rulesIn
/// (writePlace.ts) finds them on its own reader's page: letters break every row, a filled box or
/// a figure is thicker. RULES_KEPT at most, top to bottom.
let RULE_MIN: CGFloat = 40
let RULE_MIN_SHARE: CGFloat = 0.08
let RULE_THICK = 3
let RULES_KEPT = 64
/// The ink grid's cells are INK_CELL points square, INK_CELLS_MOST at most each way; a cell with
/// more than INK_SHARE of its pixels marked is drawn on (the web's own INK_SHARE).
let INK_CELL = 8
let INK_CELLS_MOST = 400
let INK_SHARE = 0.02

/// Where else the page is drawn on: `cols` x `rows` cells of INK_CELL points from (x, y) in
/// screen points, row by row, a bit each (cell i = r * cols + c is set when bits[i >> 3] has
/// bit i & 7).
struct InkGrid {
    let x: Double
    let y: Double
    let cols: Int
    let rows: Int
    let bits: [UInt8]

    func inked(col: Int, row: Int) -> Bool {
        guard col >= 0, col < cols, row >= 0, row < rows else { return false }
        let i = row * cols + col
        return bits[i >> 3] & UInt8(1 << (i & 7)) != 0
    }
}

/// What an accurate read sends of its page besides the words, in screen points: the paper (nil
/// when it cannot be told), the rules drawn on it, and the ink grid over the paper (over the
/// window with no paper).
struct PageGeometry {
    let paper: CGRect?
    let rules: [CGRect]
    let ink: InkGrid
}

/// Whether a text has a letter or a digit: the words the page keeps (screenBlocks cleaned).
func hasLetterOrDigit(_ text: String) -> Bool {
    text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
}

/// The runs of `true` in `flags`, each [start, end).
func trueRuns(_ flags: [Bool]) -> [Range<Int>] {
    var runs: [Range<Int>] = []
    var start: Int?
    for (i, on) in flags.enumerated() {
        if on, start == nil { start = i }
        if !on, let s = start {
            runs.append(s..<i)
            start = nil
        }
    }
    if let s = start { runs.append(s..<flags.count) }
    return runs
}

/// The page in `image`, a picture of the window's `frame` (screen points), with `lines` read from
/// it: its paper, its rules and its ink, or nil when its paper's grey cannot be told.
func pageGeometry(_ image: CGImage, frame: CGRect, lines: [ReadLine]) -> PageGeometry? {
    let width = Int(frame.width.rounded())
    let height = Int(frame.height.rounded())
    guard width > 0, height > 0, width * height <= 40_000_000 else { return nil }
    // Drawn small in its own colours, then made grey here: drawn straight into grey, the colour
    // matching alone took 20 ms of a page. (`.low` still averages a hairline's two pixels into one.)
    let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
    var colour = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = colour.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return false }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { return nil }
    var grey = [UInt8](repeating: 0, count: width * height)
    // (the pixels with little or nothing drawn: a window's rounded corners. They are made paper
    // once its grey is known, not black marks in the corners of a page that fills the window; and
    // a pixel partly drawn, its corner's edge, is its own grey, not that grey darkened by its alpha.)
    var clear: [Int] = []
    colour.withUnsafeBufferPointer { bgra in
        grey.withUnsafeMutableBufferPointer { out in
            for i in 0..<(width * height) {
                let alpha = Int(bgra[4 * i + 3])
                if alpha < 128 { clear.append(i) }
                let blue = Int(bgra[4 * i]) * 29
                let green = Int(bgra[4 * i + 1]) * 150
                let red = Int(bgra[4 * i + 2]) * 77
                let lightness = (blue + green + red) >> 8
                out[i] = UInt8(alpha >= 255 || alpha == 0 ? lightness : min(255, lightness * 255 / alpha))
            }
        }
    }
    colour = []
    // Pixels a point (1, but for a frame of a fraction of a point).
    let sx = CGFloat(width) / frame.width
    let sy = CGFloat(height) / frame.height
    /// A box in screen points as the pixels of `grey` it covers, clipped to them.
    func pixels(_ box: CGRect) -> (x: Range<Int>, y: Range<Int>) {
        let x0 = min(max(Int(((box.minX - frame.minX) * sx).rounded(.down)), 0), width)
        let x1 = min(max(Int(((box.maxX - frame.minX) * sx).rounded(.up)), x0), width)
        let y0 = min(max(Int(((box.minY - frame.minY) * sy).rounded(.down)), 0), height)
        let y1 = min(max(Int(((box.maxY - frame.minY) * sy).rounded(.up)), y0), height)
        return (x0..<x1, y0..<y1)
    }
    /// Pixels of `grey` back in screen points.
    func points(x: Range<Int>, y: Range<Int>) -> CGRect {
        CGRect(x: frame.minX + CGFloat(x.lowerBound) / sx, y: frame.minY + CGFloat(y.lowerBound) / sy,
               width: CGFloat(x.count) / sx, height: CGFloat(y.count) / sy)
    }

    // The paper's grey: the commonest inside the lines the page keeps.
    let kept = lines.filter { hasLetterOrDigit($0.text) }
    var counts = [Int](repeating: 0, count: 256)
    for line in kept {
        let box = pixels(line.box)
        for y in box.y { for x in box.x { counts[Int(grey[y * width + x])] += 1 } }
    }
    let total = counts.reduce(0, +)
    guard total > 0 else { return nil }
    var peak = 0
    var peakCount = -1
    for v in 0..<256 {
        let around = counts[max(0, v - 4)...min(255, v + 4)].reduce(0, +)
        if around > peakCount { (peak, peakCount) = (v, around) }
    }
    guard Double(peakCount) >= PAPER_PEAK * Double(total) else { return nil }
    var weighted = 0
    for v in max(0, peak - 4)...min(255, peak + 4) { weighted += v * counts[v] }
    let paperGrey = Int((Double(weighted) / Double(max(peakCount, 1))).rounded())
    func isPaper(_ v: UInt8) -> Bool { abs(Int(v) - paperGrey) <= PAPER_NEAR }
    func isMarked(_ v: UInt8) -> Bool { abs(Int(v) - paperGrey) > MARK_FAR }
    let paperByte = UInt8(paperGrey)
    for i in clear { grey[i] = paperByte }

    // The paper: the columns that are paper over the rows of the lines sitting on it, then the
    // rows that are paper over those columns, each the run with most of those lines in it (a page
    // beside or under the next, in a viewer that shows two); then the columns again over the
    // paper's own rows, and its rows over those, until it holds (three goes at most). Over the rows
    // from a viewer's bars to the page's last line, a bar as light as the paper (a browser's white
    // tab and toolbar over its dark PDF viewer) can make a column of the dark viewer beside the
    // page count as paper; over the page's own rows it does not. Told only when one of its edges
    // is inside the window: a page that fills it shows none of them.
    let sitting = kept.map { pixels($0.box) }.filter { box in
        var paper = 0
        for y in box.y { for x in box.x where isPaper(grey[y * width + x]) { paper += 1 } }
        return box.x.count * box.y.count > 0 && Double(paper) >= PAPER_SITS * Double(box.x.count * box.y.count)
    }
    func overlap(_ a: Range<Int>, _ b: Range<Int>) -> Int { max(0, min(a.upperBound, b.upperBound) - max(a.lowerBound, b.lowerBound)) }
    /// Of `runs`, the one with most of the sitting lines in it (`weight`), if any has some.
    func heaviest(_ runs: [Range<Int>], _ weight: (Range<Int>) -> Int) -> Range<Int>? {
        runs.map { ($0, weight($0)) }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }
    var paper: (x: Range<Int>, y: Range<Int>)?
    if let top = sitting.map(\.y.lowerBound).min(), let bottom = sitting.map(\.y.upperBound).max(), bottom > top {
        var band = top..<bottom
        for _ in 0..<3 {
            var colPaper = [Int](repeating: 0, count: width)
            for y in band { for x in 0..<width where isPaper(grey[y * width + x]) { colPaper[x] += 1 } }
            let paperCols = trueRuns(colPaper.map { Double($0) >= PAPER_EDGE_SHARE * Double(band.count) })
            guard let across = heaviest(paperCols, { run in sitting.reduce(0) { $0 + overlap($1.x, run) * overlap($1.y, band) } })
            else { break }
            var rowPaper = [Int](repeating: 0, count: height)
            for y in 0..<height { for x in across where isPaper(grey[y * width + x]) { rowPaper[y] += 1 } }
            let paperRows = trueRuns(rowPaper.map { Double($0) >= PAPER_EDGE_SHARE * Double(across.count) })
            guard let down = heaviest(paperRows, { run in sitting.reduce(0) { $0 + overlap($1.y, run) * overlap($1.x, across) } })
            else { break }
            let held = paper.map { $0.x == across && $0.y == down } ?? false
            paper = (across, down)
            if held || down == band { break }
            band = down
        }
        if let found = paper, found.x == 0..<width, found.y == 0..<height { paper = nil }
    }

    // The words left out (as paper), each box WORD_PAD bigger: the words of a line, or the whole
    // line when it has none or one of them is guessed. A word with no letter or digit is not one
    // the page keeps: a blank's underscores ("____") stay, and are found as a rule.
    for line in kept {
        let boxes: [CGRect]
        if let found = line.words, !found.contains(where: \.guessed) {
            boxes = found.filter { hasLetterOrDigit($0.text) }.map(\.box)
        } else {
            boxes = [line.box]
        }
        for box in boxes {
            let out = pixels(box.insetBy(dx: -WORD_PAD, dy: -WORD_PAD))
            for y in out.y { for x in out.x { grey[y * width + x] = paperByte } }
        }
    }
    let region = paper ?? (0..<width, 0..<height)

    // The rules: per row, every run of marked pixels long enough; runs in rows one under another
    // that overlap are one, kept when RULE_THICK rows thick or less.
    let minRun = max(Int((RULE_MIN * sx).rounded()), Int((RULE_MIN_SHARE * CGFloat(region.x.count)).rounded()), 1)
    var groups: [(x: Range<Int>, y: Range<Int>)] = []
    var open: [Int] = []
    for y in region.y {
        var still: [Int] = []
        var start = -1
        for x in region.x.lowerBound...region.x.upperBound {
            let on = x < region.x.upperBound && isMarked(grey[y * width + x])
            if on && start < 0 { start = x }
            guard !on, start >= 0 else { continue }
            if x - start >= minRun {
                let run = start..<x
                if let k = open.first(where: { overlap(groups[$0].x, run) > 0 }) {
                    let x0 = min(groups[k].x.lowerBound, run.lowerBound)
                    groups[k] = (x0..<max(groups[k].x.upperBound, run.upperBound), groups[k].y.lowerBound..<(y + 1))
                    if !still.contains(k) { still.append(k) }
                } else {
                    groups.append((run, y..<(y + 1)))
                    still.append(groups.count - 1)
                }
            }
            start = -1
        }
        open = still
    }
    let rules = groups.filter { CGFloat($0.y.count) <= CGFloat(RULE_THICK) * sy }.prefix(RULES_KEPT).map { points(x: $0.x, y: $0.y) }

    // The ink: a cell is drawn on when enough of its pixels are marked (the words are paper now).
    let cell = max(1, Int((CGFloat(INK_CELL) * sx).rounded()))
    let cols = min(INK_CELLS_MOST, (region.x.count + cell - 1) / cell)
    let rows = min(INK_CELLS_MOST, (region.y.count + cell - 1) / cell)
    var marked = [Int](repeating: 0, count: cols * rows)
    for y in region.y.lowerBound..<min(region.y.upperBound, region.y.lowerBound + rows * cell) {
        let r = (y - region.y.lowerBound) / cell
        for x in region.x.lowerBound..<min(region.x.upperBound, region.x.lowerBound + cols * cell) where isMarked(grey[y * width + x]) {
            marked[r * cols + (x - region.x.lowerBound) / cell] += 1
        }
    }
    var bits = [UInt8](repeating: 0, count: (cols * rows + 7) / 8)
    for r in 0..<rows {
        let tall = min(cell, region.y.count - r * cell)
        for c in 0..<cols {
            let wide = min(cell, region.x.count - c * cell)
            let i = r * cols + c
            if Double(marked[i]) > INK_SHARE * Double(tall * wide) { bits[i >> 3] |= UInt8(1 << (i & 7)) }
        }
    }
    let origin = points(x: region.x, y: region.y)
    return PageGeometry(paper: paper.map { points(x: $0.x, y: $0.y) }, rules: Array(rules),
                        ink: InkGrid(x: Double(origin.minX), y: Double(origin.minY), cols: cols, rows: rows, bits: bits))
}

/// A page's geometry as the read sends it ("paper" only when told).
func geometryFields(_ geometry: PageGeometry) -> [String: Any] {
    var fields: [String: Any] = [
        "rules": geometry.rules.map { boxFields($0) },
        "ink": [
            "x": geometry.ink.x, "y": geometry.ink.y, "cell": INK_CELL, "cols": geometry.ink.cols, "rows": geometry.ink.rows,
            "bits": Data(geometry.ink.bits).base64EncodedString(),
        ] as [String: Any],
    ]
    if let paper = geometry.paper { fields["paper"] = boxFields(paper) }
    return fields
}

// MARK: - Has it changed?

/*
  A turn is judged by pictures, not by what the app says: a small grey thumbnail of the
  window before it, then one every tenth of a second after. This part is plain arithmetic
  on those thumbnails, kept apart so it can be checked without the screen.
*/

/// A thumbnail that differs from the one before the turn by more than this (the mean
/// difference of its pixels, 0 to 255) shows something else. A blinking caret or a link
/// lighting up under the pointer stays well under it.
let CHANGED_ABOVE = 1.5
/// Two thumbnails in a row that differ by less than this: the window has stopped moving
/// (a page slide or an eased scroll has finished).
let SETTLED_BELOW = 0.4

/// The mean absolute difference of two grey thumbnails, 0 to 255. Pictures of different
/// sizes count as wholly different.
func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 255 }
    var total = 0
    for i in a.indices { total += abs(Int(a[i]) - Int(b[i])) }
    return Double(total) / Double(a.count)
}

/*
  Did a tap do something in its app? A click on a link, a button or a page's margin changes
  the window where it landed (a page turns, a row or a button lights, the link's page comes in);
  a click that only puts the tutor's attention on a paragraph changes nothing there. So the
  companion compares the window's thumbnail from just before the press with one 150 ms after
  the release over the tapped line's own patch only: the rows within LINE_REACH points above and
  below the tap, and the columns within SIDE_REACH points either side of it. A reader's bars
  fading in or out at the window's edges, a page's side controls and a clock far off fall
  outside it; a row or a button lit at the tap counts for more in it than in whole rows.

  The watch's look from just before the press (a tab strip or a list acts on the press itself,
  before the press's own picture is taken) is judged against as well. In a reader ("readers"
  with "companion": Kindle, Books, Preview) only when the window away from the tap (outside the
  TAP_REACH rows) looked the same in it as in the press's picture: its bars that faded in between
  the two make that look no picture of the window before the press. Elsewhere it counts as it
  is: a browser's tab or a Finder sidebar item switches the whole window on the press. With no
  press picture, the look alone; with neither, nothing is acted.

  The patch has the first word only: when it says acted, the words at the tap have the last
  (judgeText, "The words at a tap" below), so a page laid out again under a reader's bars, with
  the tapped words still on it, is the tutor's tap after all.
*/

/// How far above and below a tap the window away from it begins, in points (judgeTap).
let TAP_REACH: CGFloat = 60
/// The tapped line's own patch: this far above and below the tap, in points,
let LINE_REACH: CGFloat = 14
/// and this far either side of it.
let SIDE_REACH: CGFloat = 160

/// The rows of a thumbnail `height` rows tall, of a window at `frame`, that lie within `reach`
/// points above and below `y` (screen points); nil when none do (the tap was off the window).
func bandRows(y: CGFloat, frame: CGRect, height: Int, reach: CGFloat = TAP_REACH) -> ClosedRange<Int>? {
    guard height > 0, frame.height > 0 else { return nil }
    let perPoint = CGFloat(height) / frame.height
    let top = Int(((y - reach - frame.minY) * perPoint).rounded(.down))
    let bottom = Int(((y + reach - frame.minY) * perPoint).rounded(.up))
    let first = max(0, top)
    let last = min(height - 1, bottom)
    return first <= last ? first...last : nil
}

/// The columns of a thumbnail `width` columns wide, of a window at `frame`, that lie within
/// `reach` points either side of `x` (screen points); nil when none do (the tap was off the window).
func patchCols(x: CGFloat, frame: CGRect, width: Int, reach: CGFloat = SIDE_REACH) -> ClosedRange<Int>? {
    guard width > 0, frame.width > 0 else { return nil }
    let perPoint = CGFloat(width) / frame.width
    let first = max(0, Int(((x - reach - frame.minX) * perPoint).rounded(.down)))
    let last = min(width - 1, Int(((x + reach - frame.minX) * perPoint).rounded(.up)))
    return first <= last ? first...last : nil
}

/// The mean absolute difference of two grey thumbnails `width` pixels wide over `rows` only, 0 to
/// 255. Pictures of different sizes, or rows outside them, count as wholly different.
func bandDifference(_ a: [UInt8], _ b: [UInt8], width: Int, rows: ClosedRange<Int>) -> Double {
    guard a.count == b.count, width > 0, !a.isEmpty, (rows.upperBound + 1) * width <= a.count else { return 255 }
    var total = 0
    let start = rows.lowerBound * width
    let end = (rows.upperBound + 1) * width
    for i in start..<end { total += abs(Int(a[i]) - Int(b[i])) }
    return Double(total) / Double(end - start)
}

/// The same over `rows` and `cols` only (a tapped line's own patch).
func patchDifference(_ a: [UInt8], _ b: [UInt8], width: Int, rows: ClosedRange<Int>, cols: ClosedRange<Int>) -> Double {
    guard a.count == b.count, width > 0, !a.isEmpty, (rows.upperBound + 1) * width <= a.count, cols.upperBound < width else { return 255 }
    var total = 0
    for r in rows { for c in cols { total += abs(Int(a[r * width + c]) - Int(b[r * width + c])) } }
    return Double(total) / Double(rows.count * cols.count)
}

/// The same over every row outside `rows` (the window away from a tap); 0 when there are none.
func awayDifference(_ a: [UInt8], _ b: [UInt8], width: Int, rows: ClosedRange<Int>) -> Double {
    guard a.count == b.count, width > 0, !a.isEmpty, (rows.upperBound + 1) * width <= a.count else { return 255 }
    var total = 0
    for i in 0..<(rows.lowerBound * width) { total += abs(Int(a[i]) - Int(b[i])) }
    for i in ((rows.upperBound + 1) * width)..<a.count { total += abs(Int(a[i]) - Int(b[i])) }
    let count = a.count - rows.count * width
    return count > 0 ? Double(total) / Double(count) : 0
}

/*
  A window's own edges change by themselves: a reader's bars fade in and out at its top and
  bottom, a title bar dims as its app goes to the back, a status line ticks. So a new look
  (looked), whether a tapped window has moved since its last read, and whether the window away
  from a tap changed (companionTap) are judged on its middle rows only: EDGE_SHARE of its height
  off the top and off the bottom.
*/
let EDGE_SHARE = 0.12

/// The rows of a thumbnail `height` rows tall between its top and bottom EDGE_SHARE; nil if none.
func middleRows(height: Int) -> ClosedRange<Int>? {
    let first = Int((Double(height) * EDGE_SHARE).rounded(.up))
    let last = Int((Double(height) * (1 - EDGE_SHARE)).rounded(.down)) - 1
    return height > 0 && first <= last ? first...last : nil
}

/// The mean absolute difference of two grey thumbnails `width` pixels wide over their middle rows,
/// 0 to 255. Pictures of different sizes count as wholly different.
func middleDifference(_ a: [UInt8], _ b: [UInt8], width: Int) -> Double {
    guard a.count == b.count, width > 0, !a.isEmpty, a.count % width == 0, let rows = middleRows(height: a.count / width) else { return 255 }
    return bandDifference(a, b, width: width, rows: rows)
}

/// The same over the middle rows outside `rows` (the window away from a tap, less its edges); 0
/// when there are none.
func middleAwayDifference(_ a: [UInt8], _ b: [UInt8], width: Int, rows: ClosedRange<Int>) -> Double {
    guard a.count == b.count, width > 0, !a.isEmpty, a.count % width == 0, let middle = middleRows(height: a.count / width) else { return 255 }
    var total = 0
    var count = 0
    for r in middle where !rows.contains(r) {
        for c in 0..<width { total += abs(Int(a[r * width + c]) - Int(b[r * width + c])) }
        count += width
    }
    return count > 0 ? Double(total) / Double(count) : 0
}

/// How bright a window is, 0 (black) to 1 (white): the mean of its grey thumbnail. The lesson
/// draws strong marks on a white page and light ones on a dark page (a Kindle night theme).
func ground(_ thumb: [UInt8]) -> Double {
    guard !thumb.isEmpty else { return 1 }
    var total = 0
    for value in thumb { total += Int(value) }
    return Double(total) / Double(thumb.count) / 255
}

/// A thumbnail of one flat colour (a blank page, a window still drawing): no words to find.
func isBlank(_ thumb: [UInt8]) -> Bool {
    guard let low = thumb.min(), let high = thumb.max() else { return true }
    return Int(high) - Int(low) < 12
}

/// Follows the thumbnails taken after a turn, one at a time.
struct SettleWatch {
    let before: [UInt8]
    private var previous: [UInt8]?
    /// Whether the latest thumbnail shows something other than the window before the turn.
    /// Judged on the latest alone, so a window that moves and comes back (a scroll that
    /// bounces at the end of a book) has not changed.
    private(set) var changed = false

    init(before: [UInt8]) {
        self.before = before
    }

    /// Takes the next thumbnail; true once the window has changed and two thumbnails in a
    /// row agree.
    mutating func settled(with now: [UInt8]) -> Bool {
        let last = previous
        previous = now
        changed = meanDifference(before, now) > CHANGED_ABOVE
        guard changed, let last else { return false }
        return meanDifference(last, now) < SETTLED_BELOW
    }
}

/// Each window as it looked at its last read (a thumbnail), by its id; the latest read last in
/// `seenOrder`. With the companion glancing at every window the cursor rests on, the oldest go
/// past SEEN_KEPT (a thumbnail is about 40 KB).
let seenLock = NSLock()
var seenWindows: [CGWindowID: [UInt8]] = [:]
var seenOrder: [CGWindowID] = []
let SEEN_KEPT = 64

func remember(_ window: CGWindowID, _ thumb: [UInt8]) {
    seenLock.lock()
    seenWindows[window] = thumb
    seenOrder.removeAll { $0 == window }
    seenOrder.append(window)
    while seenOrder.count > SEEN_KEPT { seenWindows[seenOrder.removeFirst()] = nil }
    seenLock.unlock()
    // Read as it looks now: the companion's watch for a new look starts again from here.
    observedRead(window)
}

func lastSeen(_ window: CGWindowID) -> [UInt8]? {
    seenLock.lock()
    defer { seenLock.unlock() }
    return seenWindows[window]
}

// MARK: - Turning a window's page

/// Thumbnails are this many pixels wide: enough to see a line of text move, and cheap
/// enough to take ten a second.
let THUMB_WIDE = 256
/// How often a thumbnail is taken while waiting for the window to change and settle.
let POLL_MS = 100

func thumbnailConfig(for frame: CGRect) -> SCStreamConfiguration {
    let config = SCStreamConfiguration()
    config.width = THUMB_WIDE
    config.height = max(1, Int((CGFloat(THUMB_WIDE) * frame.height / max(frame.width, 1)).rounded()))
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    config.captureResolution = .nominal
    return config
}

/// One grey byte per pixel, the window alone (the lesson's own pointer and captions over it
/// are not in the picture, so they never count as a change). Drawn at the configured size,
/// so every thumbnail of a turn compares pixel for pixel.
func thumbnail(_ filter: SCContentFilter, _ config: SCStreamConfiguration) async throws -> [UInt8]? {
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    let width = config.width
    let height = config.height
    var pixels = [UInt8](repeating: 0, count: width * height)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return false }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? pixels : nil
}

/// Virtual key codes. These keys have the same code on every keyboard layout.
let KEY_CODES: [String: CGKeyCode] = ["right": 124, "left": 123, "pagedown": 121, "pageup": 116, "down": 125, "up": 126]

/*
  A posted event takes on the modifier keys held at the time unless it names its own, and a
  turn can start from Control+Option+Right (the lesson's "next" shortcut): a Right that
  arrived as Control+Right would switch Spaces instead. So every event below names its
  flags: none for the wheel, and for a key the ones the real key sends (the arrows count as
  keypad keys, and all six as function keys).
*/
func keyFlags(_ code: CGKeyCode) -> CGEventFlags {
    code == 121 || code == 116 ? .maskSecondaryFn : [.maskSecondaryFn, .maskNumericPad]
}

/// Scrolls whatever is under `point` by dy points, as a mouse wheel would: steps of at most
/// 100 points, 12 ms apart, so an app that eases its scrolling sees an ordinary wheel. A
/// negative wheel value shows later content, so dy above 0 does.
func postScroll(dy: Double, at point: CGPoint) async {
    let source = CGEventSource(stateID: .privateState)
    let steps = Int((abs(dy) / 100).rounded(.up))
    var posted = 0
    for step in 0..<steps {
        if step > 0 { await sleepMs(12) }
        let upTo = Int((dy * Double(step + 1) / Double(steps)).rounded())
        let amount = upTo - posted
        posted = upTo
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
                                  wheel1: Int32(-amount), wheel2: 0, wheel3: 0)
        else { continue }
        event.location = point
        event.flags = []
        // Ours, not the student's: the scroll watch (installWatch) leaves it out.
        event.setIntegerValueField(.eventSourceUserData, value: POSTED_BY_US)
        event.post(tap: .cghidEventTap)
    }
}

/// A window's frame as Accessibility gives it: screen points from the top left of the main
/// display, as the window server's.
func axFrame(_ element: AXUIElement) -> CGRect? {
    var position: CFTypeRef?
    var size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
          let position, let size,
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &extent)
    else { return nil }
    return CGRect(origin: origin, size: extent)
}

/// Brings the app `pid` to the front, with its window at `frame` above its others (a browser
/// with several windows, Kindle's library behind its book), so the keys that follow reach that
/// window. Through Accessibility, which a turn by key has: macOS 14 refuses most activation that
/// a process in the background asks for, as the helper is, and the student clicking into the
/// lesson puts Tutornote in front. True when the app is in front afterwards.
func bringForward(pid: pid_t, frame: CGRect) async -> Bool {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    let same = { (a: CGFloat, b: CGFloat) in abs(a - b) < 2 }
    if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
       let windows = value as? [AXUIElement],
       let window = windows.first(where: { element in
           guard let box = axFrame(element) else { return false }
           return same(box.minX, frame.minX) && same(box.minY, frame.minY) && same(box.width, frame.width) && same(box.height, frame.height)
       }) {
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    _ = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    // (asked for as any app asks too, which macOS may grant as well)
    await MainActor.run { _ = NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
    for _ in 0..<6 {
        await sleepMs(50)
        let front = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
        if front {
            // Its window redrawn as the active one's, before the picture the turn is judged against.
            await sleepMs(150)
            return true
        }
    }
    return false
}

/// Presses `code` `count` times, 250 ms apart: through the system, to the app in front, when
/// that is `pid`'s (bringForward); else to that app's process directly, so the keys never land
/// in whatever the student was typing into.
func pressKey(_ code: CGKeyCode, count: Int, pid: pid_t, inFront: Bool) async {
    if !inFront { log("[screen] process \(pid) did not come to the front; sending it the key directly") }
    let source = CGEventSource(stateID: .privateState)
    for press in 0..<count {
        if press > 0 { await sleepMs(250) }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = keyFlags(code)
            if inFront { event.post(tap: .cghidEventTap) } else { event.postToPid(pid) }
        }
    }
}

/// A turn as asked for (the "turn" command, checked).
struct Turn {
    let window: CGWindowID
    /// The app the lesson read the window in, when the page says.
    let pid: pid_t?
    /// "scroll", "key" or "manual".
    let how: String
    let dy: Double
    let key: CGKeyCode?
    let count: Int
    /// Where the wheel turns, in screen points; the window's centre when not given, or outside it.
    let at: CGPoint?
    let timeoutMs: Int
    /// The window moved since its last read: that is the turn, and nothing is posted.
    let unlessMoved: Bool
    /// No turn ("manual" only): a wait for the window to be still (StillWatch), changed or not.
    let still: Bool
}

/// Follows the thumbnails of a wait for the window to be still ("still"), one at a time: still once
/// two in a row agree, whatever they show.
struct StillWatch {
    private var previous: [UInt8]

    init(first: [UInt8]) {
        previous = first
    }

    mutating func still(with now: [UInt8]) -> Bool {
        defer { previous = now }
        return meanDifference(previous, now) < SETTLED_BELOW
    }
}

/// `point` when it is inside `frame`, else the frame's centre: a scroll goes to the window being
/// read, never to another one on the screen.
func inside(_ point: CGPoint?, _ frame: CGRect) -> CGPoint {
    if let point, frame.insetBy(dx: 1, dy: 1).contains(point) { return point }
    return CGPoint(x: frame.midX, y: frame.midY)
}

func turn(id: Int, _ asked: Turn) async {
    guard CGPreflightScreenCaptureAccess() else {
        emit(["id": id, "ev": "error", "code": "no_permission"])
        return
    }
    // Posting another app's input is Accessibility's; waiting for the student needs none.
    if asked.how != "manual" && !AXIsProcessTrusted() {
        emit(["id": id, "ev": "error", "code": "no_access"])
        return
    }
    // The id must still name the window the lesson read, owned by the app it read it in.
    guard let target = onScreenWindow(asked.window), asked.pid == nil || asked.pid == target.pid else {
        emit(["id": id, "ev": "error", "code": "window_gone"])
        return
    }
    // (through the handle kept, or one asked for now and kept: the careful read after the turn
    // pictures through it too, throughFilter)
    let config = thumbnailConfig(for: target.frame)
    let filter: SCContentFilter
    var before: [UInt8]
    do {
        guard let first = try await throughFilter(target.id, frame: target.frame, { ($0, try await thumbnail($0, config)) }) else {
            emit(["id": id, "ev": "error", "code": "window_gone"])
            return
        }
        guard let thumb = first.1 else {
            emit(["id": id, "ev": "error", "code": onScreenWindow(target.id) == nil ? "window_gone" : "capture_failed"])
            return
        }
        filter = first.0
        before = thumb
    } catch {
        // (the picture through a fresh handle failing: the window going, or capture refused)
        let code = onScreenWindow(target.id) == nil ? "window_gone" : "capture_failed"
        if code == "capture_failed" { log("[screen] capture failed: \(error.localizedDescription)") }
        emit(["id": id, "ev": "error", "code": code])
        return
    }

    // The time to settle and the timeout both count from here, so they include the turn itself.
    let started = DispatchTime.now()
    // A wait for the window to be still, not a turn (the lesson's window showing another document,
    // or the student in another window: screenTeach.ts switchRead, before it reads it): nothing is
    // posted, no change is waited for, and it is answered as soon as two thumbnails in a row agree
    // (a tab still drawing its page has not), or at timeoutMs. "changed": whether the window, as
    // last seen, differs from its last read.
    if asked.still {
        var still = StillWatch(first: before)
        var last = before
        let stillAnswer = { (settled: Bool) in
            let changed = lastSeen(target.id).map { meanDifference($0, last) > CHANGED_ABOVE } ?? false
            emit(["id": id, "ev": "turned", "moved": false, "changed": changed, "still": settled, "settleMs": msSince(started)])
        }
        repeat {
            await sleepMs(POLL_MS)
            if Task.isCancelled {
                emit(["id": id, "ev": "error", "code": "cancelled"])
                return
            }
            do {
                guard let now = try await thumbnail(filter, config) else { continue }
                last = now
                if still.still(with: now) {
                    stillAnswer(true)
                    return
                }
            } catch {
                if onScreenWindow(target.id) == nil {
                    emit(["id": id, "ev": "error", "code": "window_gone"])
                    return
                }
            }
        } while msSince(started) < asked.timeoutMs
        stillAnswer(false)
        return
    }
    // Moved since its last read (the student scrolled it, or turned the page themselves): when
    // the lesson asks, that move is this turn. Nothing is posted, and the window is watched from
    // how it looked at that read, until it is still.
    var how = asked.how
    var answer: [String: Any] = ["id": id, "ev": "turned", "moved": false]
    if asked.unlessMoved, let seen = lastSeen(target.id), meanDifference(seen, before) > CHANGED_ABOVE {
        before = seen
        how = "manual"
        answer["moved"] = true
    }
    switch how {
    case "scroll":
        await postScroll(dy: asked.dy, at: inside(asked.at, target.frame))
    case "key":
        guard let key = asked.key else { break }
        let inFront = await bringForward(pid: target.pid, frame: target.frame)
        answer["front"] = inFront
        // Judged from here, with the app in front: its bars drawn as the active app's are no
        // turn of the page.
        if inFront, let now = try? await thumbnail(filter, config) { before = now }
        await pressKey(key, count: asked.count, pid: target.pid, inFront: inFront)
    default:
        break // manual: the student turns the page
    }

    // A full poll's wait after every thumbnail, even a slow one: two taken back to back would
    // agree while a slow scroll was still easing to a stop. At least one look after the turn,
    // however long the keys took.
    var watch = SettleWatch(before: before)
    let answered = { (changed: Bool) in
        emit(answer.merging(["changed": changed, "settleMs": msSince(started)]) { _, new in new })
    }
    repeat {
        await sleepMs(POLL_MS)
        // Given up (a wait for the student the lesson no longer wants): no more pictures.
        if Task.isCancelled {
            emit(["id": id, "ev": "error", "code": "cancelled"])
            return
        }
        do {
            guard let now = try await thumbnail(filter, config) else { continue }
            if watch.settled(with: now) {
                answered(true)
                return
            }
        } catch {
            if onScreenWindow(target.id) == nil {
                emit(["id": id, "ev": "error", "code": "window_gone"])
                return
            }
        }
    } while msSince(started) < asked.timeoutMs
    // Out of time: say whether the window, as last seen, shows something else (it may be
    // changing still, or the student may not have turned the page).
    answered(watch.changed)
}

/// The turns going on, by id: a "cancel" ends one.
let turnsLock = NSLock()
var turnTasks: [Int: Task<Void, Never>] = [:]

func startTurn(id: Int, _ asked: Turn) {
    turnsLock.lock()
    defer { turnsLock.unlock() }
    // The companion's watch for a new look (observe) leaves the window alone meanwhile: the
    // lesson's own turn is no page the student turned. (Not for a wait for it to be still: no turn,
    // and a slide the student changes just after is to be seen at once.) Its keys are no
    // student's either (keyTick); a wait for the student's own turn posts none.
    let keys = asked.how == "key"
    if !asked.still { turning(asked.window, true, keys: keys) }
    turnTasks[id] = Task {
        await turn(id: id, asked)
        if !asked.still { turning(asked.window, false, keys: keys) }
        _ = takeTurn(id)
    }
}

func takeTurn(_ id: Int) -> Task<Void, Never>? {
    turnsLock.lock()
    defer { turnsLock.unlock() }
    return turnTasks.removeValue(forKey: id)
}

// MARK: - Watching the lesson's window

/*
  During a lesson the student taps a paragraph in its own app to have the tutor explain it
  there, as a click on a paragraph does in Teach mode, and switches to other apps. The lesson's
  window is see-through and lets every click through to the app below, so it never hears the
  tap; this does, without taking it: a global monitor sees the click the other app gets (watching
  mouse clicks needs no permission; only key presses would need Accessibility). A tap is a press
  and a release within 5 points and 0.7 s (a drag is the student selecting text), on the watched
  window where it is the one on top. Each tap says whether the window had moved since its last
  read (the student scrolled it) by the time it was pressed, judged on its middle rows: the
  paragraphs the lesson holds are then not where they were. (What the click itself does there, a
  reader's bars coming in and the page laid out again under them, is no move.)
  It also says which app comes to the front, so the lesson can step aside while the student is
  elsewhere. All of it on the main thread, where the monitors and the commands run.
*/
var watched: CGWindowID?
var pressedAt: (point: CGPoint, time: TimeInterval)?
/// The watched window's picture as it was pressed (the companion off): what its tap's "moved" is
/// judged on.
var watchPress: (window: CGWindowID, picture: Task<[UInt8]?, Never>)?
/// The cursor was a pointing hand at the last press (a link), with the companion on.
var pressHand = false
var watching = false
/** On the scroll events this helper posts itself (a lesson's own turn): the scroll watch leaves
 *  them out, so a turn is never also taken for the student's scroll. */
let POSTED_BY_US: Int64 = 0x5475_746F
/** Where the watched window was last seen on top, and when: a scroll over it comes many times
 *  a second, and the window list is not asked each time. */
var onTopAt: (frame: CGRect, time: TimeInterval)?

/// The watched window is the one on top at `point` (asked at most every 0.3 s while the point
/// stays inside where it was last seen on top).
func watchedOnTop(_ point: CGPoint, _ window: CGWindowID, now: TimeInterval) -> Bool {
    if let seen = onTopAt, now - seen.time < 0.3, seen.frame.contains(point) { return true }
    guard let top = windowAt(point, excluding: []), top.id == window else {
        onTopAt = nil
        return false
    }
    onTopAt = (top.frame, now)
    return true
}

/// The points a mouse wheel's line is taken as until the read after the scroll says better: about
/// what a browser scrolls a line by. The page learns each app's own step from the lines said.
let WHEEL_LINE_PT = 40.0

/// What one wheel event over a window says ("scroll"): its content moved up by `dy` points and left
/// by `dx`; `lines`, a mouse wheel's lines in dy's sense (0 for a trackpad, whose deltas are points
/// already); and whether it is that window's scroll for the watch (`scrolls`: scrolledAt, which
/// keeps the new look it settles into from being said). Only a move up or down is (the founder,
/// 2026-10-28: the tutor over another app should be "very accurate in the way it points at
/// things"): a pan sideways across a zoomed page, or a swipe that turns a page, would otherwise
/// leave the lesson where the words were, the app told of no new look.
struct WheelStep {
    let dy: Double
    let dx: Double
    let lines: Double
    let scrolls: Bool
}

/// The event's own deltas (`precise`: hasPreciseScrollingDeltas, a trackpad's or a Magic Mouse's)
/// as a WheelStep.
func wheelStep(deltaY: Double, deltaX: Double, precise: Bool) -> WheelStep {
    let point = precise ? 1 : WHEEL_LINE_PT
    let dy = deltaY == 0 ? 0 : -deltaY * point
    let dx = deltaX == 0 ? 0 : -deltaX * point
    let lines = precise || deltaY == 0 ? 0 : -deltaY
    return WheelStep(dy: dy, dx: dx, lines: lines, scrolls: dy != 0)
}

/// When the watch is to take `step`, heard `now`, as its window's scroll (scrolledAt: the new look
/// it settles into is told already), or nil: a pan or a swipe sideways, or an event that moved
/// nothing, whose new look is said (installWatch).
func wheelScrolledAt(_ step: WheelStep, now: TimeInterval) -> TimeInterval? {
    step.scrolls ? now : nil
}

func installWatch() {
    guard !watching else { return }
    watching = true
    NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .scrollWheel]) { event in
        // Screen points from the top left of the main display, as every box here is.
        guard let point = event.cgEvent?.location else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if event.type == .scrollWheel {
            // The student scrolling the watched window (the wheel goes to the window under the
            // pointer): how far its content moved, in points, so the lesson's marks move with it
            // as they would over a PDF in the app. Up is positive: the window went down its
            // document. A trackpad gives points; a wheel gives lines, which a browser scrolls
            // about WHEEL_LINE_PT points each, and which are said too ("lines"), so the page can
            // learn the app's own step from the read after the scroll stops, which corrects what
            // this is off by (wheelStep). Sideways too (dx, left positive): a pan across a zoomed
            // page, or a swipe that turns a page in some readers. With the companion on,
            // whichever window is under the cursor (overAt), never Tutornote's own.
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != POSTED_BY_US else { return }
            let window: CGWindowID
            if companionOn {
                guard let under = overAt(point, now: now).window else { return }
                window = under
            } else {
                guard let only = watched, watchedOnTop(point, only, now: now) else { return }
                window = only
            }
            let step = wheelStep(deltaY: Double(event.scrollingDeltaY), deltaX: Double(event.scrollingDeltaX), precise: event.hasPreciseScrollingDeltas)
            if step.dy != 0 || step.dx != 0 {
                emit(["ev": "scroll", "dy": step.dy, "dx": step.dx, "lines": step.lines, "momentum": !event.momentumPhase.isEmpty, "window": Int(window)])
            }
            // (told already: the new look it settles into is no "changed". The companion off too: the
            // lesson's window is observed for every lesson now. Only a move up or down is: a pan
            // or a swipe sideways, and an event that moved nothing (fingers set down or lifted),
            // leave the new look to be said, as a key's is; and in a window observed as turning by
            // the page, no wheel explains one: scrollExplains)
            if let at = wheelScrolledAt(step, now: now) { scrolled(window, at: at) }
            burst(window)
            return
        }
        if event.type == .leftMouseDown {
            pressedAt = (point, now)
            pressBefore = nil
            watchPress = nil
            // (the cursor as the button went down: over a link it is the pointing hand)
            pressHand = companionOn && isPointingHand(NSCursor.currentSystem)
            // The companion's press is told at once, before any picture is taken; the picture
            // of the window as it was is taken after, for the tap to compare with, with the
            // watch's latest look of it from before the press (a tab strip or a list acts on the
            // press itself, before that picture can be taken), and the column around the press
            // at full size with the window's title, for the words at the tap (judgeText). Never
            // a picture of a private window, or of any while a password field has the keys; none
            // for the second press of a double click (its tap selects words: no pictures).
            if companionOn, case let .window(top) = overAt(point, now: now, force: true) {
                emit(["ev": "press", "x": Double(point.x), "y": Double(point.y), "window": Int(top.id)])
                if !keptPrivate(top.pid) && event.clickCount < 2 {
                    let look = latestThumb(top.id, within: PRESS_LOOK_S)
                    let column = columnRect(x: point.x, frame: top.frame)
                    pressBefore = PressBefore(
                        window: top.id,
                        look: look?.thumb,
                        lookAge: look?.age,
                        picture: Task { await quickThumbnail(top.id, frame: top.frame) },
                        frame: top.frame,
                        column: column,
                        columnPicture: column.map { source in Task { await columnPicture(top.id, frame: top.frame, source: source) } },
                        title: top.title
                    )
                    burst(top.id)
                }
            } else if !companionOn, let window = watched, watchedOnTop(point, window, now: now), let frame = onTopAt?.frame {
                // (the companion off: the lesson's window alone, so a click that turns a page in
                // Kindle's or Books' margin, on its release, hides what the lesson wrote at once,
                // and the new look is said as soon as it is still. Its tap's "moved" is still
                // judged on the picture from the press)
                emit(["ev": "press", "x": Double(point.x), "y": Double(point.y), "window": Int(window)])
                watchPress = (window, Task { await quickThumbnail(window, frame: frame) })
                burst(window)
            }
            return
        }
        guard let pressed = pressedAt else { return }
        pressedAt = nil
        let before = pressBefore
        pressBefore = nil
        let hand = pressHand
        pressHand = false
        let pressPicture = watchPress
        watchPress = nil
        guard now - pressed.time < 0.7, hypot(point.x - pressed.point.x, point.y - pressed.point.y) < 5 else { return }
        let alt = event.modifierFlags.contains(.option)
        if companionOn {
            companionTap(at: point, alt: alt, clicks: event.clickCount, hand: hand, before: before)
            return
        }
        guard let window = watched, let top = windowAt(point, excluding: []), top.id == window else { return }
        let earlier = pressPicture?.window == window ? pressPicture : nil
        Task {
            var moved = false
            if let seen = lastSeen(window) {
                // The window as it was pressed; with no picture of it, as it is now.
                if let picture = await earlier?.picture.value {
                    moved = middleDifference(seen, picture, width: THUMB_WIDE) > CHANGED_ABOVE
                } else if let shared = try? await shareableWindow(window),
                          let now = try? await thumbnail(SCContentFilter(desktopIndependentWindow: shared), thumbnailConfig(for: top.frame)) {
                    moved = middleDifference(seen, now, width: THUMB_WIDE) > CHANGED_ABOVE
                }
            }
            emit(["ev": "tap", "x": Double(point.x), "y": Double(point.y), "window": Int(window), "moved": moved, "alt": alt])
        }
    }
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { note in
        // Another app in front may have brought a window over the cursor without it moving.
        if companionOn, let point = CGEvent(source: nil)?.location {
            overAt(point, now: ProcessInfo.processInfo.systemUptime, force: true)
        }
        guard watched != nil,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        emit(["ev": "front", "pid": Int(app.processIdentifier), "bundle": app.bundleIdentifier ?? ""])
        // (which window of it is in front, at once rather than at the next tick: "ident")
        identTick()
    }
    // Another Space (a swipe, ⌃→, a full-screen app) brings other windows under a cursor that has
    // not moved: what it is over is looked up again, or the band would stay on the last Space's.
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { _ in
        if companionOn, let point = CGEvent(source: nil)?.location {
            overAt(point, now: ProcessInfo.processInfo.systemUptime, force: true)
        }
    }
}

// MARK: - The lesson's window: which document

/*
  A lesson knows the window it reads by its id, and a browser's tab switch keeps the id: only the
  window's title says another document is in it now (the founder's test, 2026-10-27: a 9 slide
  deck opened in a new tab of the window a textbook was being taught in, and the lesson went on
  about the textbook). Nor does the app coming back to the front say which of its windows the
  student came back to (Preview opens each document in a window of its own). So while a window is
  watched ("watch" until "unwatch") this looks at it every IDENT_MS: its title (kCGWindowName,
  which Screen Recording lets the helper read) and whether it is on the screen; and, while its
  app is the one in front, that app's front ordinary window (its first layer 0 window front to
  back, IDENT_MIN_SIDE points or more each way, on screen): another document in a window of its
  own, a native tab in front of the lesson's, the student's pick of another of its windows. With
  another app in front (not Tutornote, and nothing while a password field has the keys), that
  app's front ordinary window instead ("other"): the lesson follows the student into a reader
  there (screenTeach.ts, APP_FOLLOW_MS). And whether secure input is on (a password field has the
  keys, in any app): the app reads nothing of another document then, nor of a sign in it is
  shown. It says "ident" as the watch starts, then only when any of that changed; an app coming
  to the front is looked at at once (installWatch), not at the next tick. A title that changed has the watch for a new look ("observe") look often for a
  moment, as a press does: the new page is said as soon as it is still.
  It says where the watched window is too ("frame", its own entry's bounds), whichever app is in
  front: a window dragged by its title bar changes no pixel of it, so no new look is ever said
  for it, and the lesson's marks would stay where its words were (the founder, 2026-10-28: the
  tutor over another app "should be very accurate in the way it points at things"). "topFrame"
  says as much only while its app is in front with that window its front one; a Cmd drag of a
  window behind, or one under another of its app's, is said by "frame" alone. A drag is said on
  every tick while it goes, as "topFrame" already was; the app (screenTeach.ts followFrame) moves
  the lesson with it.

  One window list a tick (about half a millisecond), and the watched window's own entry. While a
  lesson watches a window its talk chord is watched too, which keeps the helper out of App Nap
  ("The talk chord"), so these ticks come on time. The titles go to the app, never to the log.
  What is said is identLook, a function of the window list alone (--selftest: identSelfTest).
*/
let IDENT_MS = 150
let IDENT_LEEWAY_MS = 30
/// An app's front ordinary window is this many points each way at least, as windowAt's are.
let IDENT_MIN_SIDE: CGFloat = 40

/// A window "ident" names: its id, its app's process (and name, as the window server has it), its
/// title and its frame.
struct IdentWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let title: String
    let frame: CGRect
}

/// What "ident" says: the watched window's title, whether it is on the screen and where it is
/// (`frame`, nil once it is listed no more); its app's front ordinary window while that app is in
/// front (`top`); another app's while that one is (`other`); and whether secure input is on
/// (`secure`).
struct IdentLook: Equatable {
    let window: CGWindowID
    let title: String
    let onScreen: Bool
    let frame: CGRect?
    let top: IdentWindow?
    let other: IdentWindow?
    let secure: Bool
}

var identTimer: DispatchSourceTimer?
/// What was last said, or nil: nothing since the watch began.
var identTold: IdentLook?
/// The watched window's process, as last listed (a window closed is listed no more).
var identPid: pid_t?

/// The front ordinary window of `pid` in `list` (the windows on screen, front to back): layer 0,
/// seen (not see-through), on screen, IDENT_MIN_SIDE points each way at least.
func frontWindow(of pid: pid_t, in list: [[String: Any]]) -> IdentWindow? {
    for info in list {
        guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
              let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let found = target(from: info),
              found.frame.width >= IDENT_MIN_SIDE, found.frame.height >= IDENT_MIN_SIDE
        else { continue }
        if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
        if let shown = info[kCGWindowIsOnscreen as String] as? Bool, !shown { continue }
        return IdentWindow(id: found.id, pid: found.pid, owner: found.owner, title: found.title, frame: found.frame)
    }
    return nil
}

/// What "ident" says of `window`: `own`, its own entry in the window server's list (nil: not listed,
/// closed); `pid`, its process as last listed; `list`, the windows on screen front to back; `front`,
/// the app in front; `otherTold`, whether another app's window may be said (not Tutornote's, not
/// under secure input); `secure`, whether secure input is on.
func identLook(window: CGWindowID, own: [String: Any]?, pid: pid_t?, list: [[String: Any]], front: pid_t?, otherTold: Bool,
               secure: Bool = false) -> IdentLook {
    let title = own?[kCGWindowName as String] as? String ?? ""
    let onScreen = (own?[kCGWindowIsOnscreen as String] as? Bool) == true
    let frame = own.flatMap(target(from:))?.frame
    var top: IdentWindow?
    var other: IdentWindow?
    if let front {
        if let pid, front == pid {
            top = frontWindow(of: front, in: list)
        } else if otherTold {
            other = frontWindow(of: front, in: list)
        }
    }
    return IdentLook(window: window, title: title, onScreen: onScreen, frame: frame, top: top, other: other, secure: secure)
}

func frameFields(_ frame: CGRect) -> [String: Double] {
    ["x": Double(frame.minX), "y": Double(frame.minY), "w": Double(frame.width), "h": Double(frame.height)]
}

/// An app's name and bundle id, by its process (NSRunningApplication's; --selftest gives its own).
func runningApp(_ pid: pid_t) -> (name: String?, bundle: String?) {
    let app = NSRunningApplication(processIdentifier: pid)
    return (app?.localizedName, app?.bundleIdentifier)
}

/// The "ident" event for `look`; `appOf`: another app's name and bundle id.
func identFields(_ look: IdentLook, appOf: (pid_t) -> (name: String?, bundle: String?) = runningApp) -> [String: Any] {
    var fields: [String: Any] = [
        "ev": "ident",
        "window": Int(look.window),
        "title": look.title,
        "onScreen": look.onScreen,
        "top": look.top.map { Int($0.id) as Any } ?? NSNull(),
        "topTitle": look.top?.title ?? "",
        "secure": look.secure,
    ]
    if let frame = look.frame { fields["frame"] = frameFields(frame) }
    if let top = look.top { fields["topFrame"] = frameFields(top.frame) }
    if let other = look.other {
        let app = appOf(other.pid)
        fields["other"] = [
            "window": Int(other.id),
            "pid": Int(other.pid),
            "app": app.name ?? other.owner,
            "bundle": app.bundle ?? "",
            "title": other.title,
            "frame": frameFields(other.frame),
        ] as [String: Any]
    }
    return fields
}

/// One look at the watched window (the timer, an app come to the front, the watch starting:
/// `force`, said whatever it is). Main thread.
func identTick(force: Bool = false) {
    guard let window = watched else { return }
    let own = (CGWindowListCopyWindowInfo([.optionIncludingWindow], window) as? [[String: Any]])?
        .first { ($0[kCGWindowNumber as String] as? CGWindowID) == window }
    if let pid = own?[kCGWindowOwnerPID as String] as? pid_t { identPid = pid }
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let secure = secureInputOn()
    let otherTold = front.map { $0 != identPid && !isTutornoteKept($0) && !secure } ?? false
    let listed = front != nil && (front == identPid || otherTold)
    let list = listed ? (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []) : []
    let look = identLook(window: window, own: own, pid: identPid, list: list, front: front, otherTold: otherTold, secure: secure)
    let was = identTold
    guard force || look != was else { return }
    identTold = look
    emit(identFields(look))
    // (another title: the new page is looked at often until it is still, and said then)
    if let was, was.window == look.window, was.title != look.title { burst(window) }
}

/// The watch began (or moved to another window): said at once, then every IDENT_MS. Main thread.
func startIdent() {
    identTold = nil
    identPid = nil
    if identTimer == nil {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(IDENT_MS), repeating: .milliseconds(IDENT_MS), leeway: .milliseconds(IDENT_LEEWAY_MS))
        timer.setEventHandler { identTick() }
        timer.resume()
        identTimer = timer
    }
    identTick(force: true)
}

func stopIdent() {
    identTimer?.cancel()
    identTimer = nil
    identTold = nil
    identPid = nil
}

/// `--selftest`: which window "ident" names, and when it says anything, on made up window lists.
func identSelfTest(_ check: (String, Bool) -> Void) {
    func listed(_ id: CGWindowID, pid: pid_t, _ frame: CGRect, layer: Int = 0, title: String = "", alpha: Double = 1, shown: Bool = true) -> [String: Any] {
        [
            kCGWindowNumber as String: NSNumber(value: id),
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowOwnerName as String: "App \(pid)",
            kCGWindowBounds as String: frame.dictionaryRepresentation,
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowName as String: title,
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowIsOnscreen as String: NSNumber(value: shown),
        ]
    }
    let page = CGRect(x: 2, y: 44, width: 1800, height: 1125)
    let lesson = listed(3545, pid: 50, page, title: "Alpha.pdf")
    // Front to back: a menu bar item (layer 25), a tooltip-sized window, a see-through one, another
    // app's window, then the lesson's app's second window and the lesson's own.
    let list: [[String: Any]] = [
        listed(1, pid: 50, CGRect(x: 0, y: 0, width: 300, height: 24), layer: 25),
        listed(2, pid: 50, CGRect(x: 10, y: 10, width: 30, height: 200)),
        listed(3, pid: 50, page, alpha: 0),
        listed(4, pid: 60, page, title: "Bravo.pdf"),
        listed(3546, pid: 50, CGRect(x: 40, y: 80, width: 1600, height: 1000), title: "Charlie.pdf"),
        lesson,
    ]
    check("frontWindow takes an app's first ordinary window, front to back, past layers, slivers and see-through ones",
          frontWindow(of: 50, in: list)?.id == 3546 && frontWindow(of: 60, in: list)?.id == 4 && frontWindow(of: 70, in: list) == nil)
    check("nor one listed as off the screen", frontWindow(of: 50, in: [listed(9, pid: 50, page, shown: false), lesson])?.id == 3545)
    let inFront = identLook(window: 3545, own: lesson, pid: 50, list: list, front: 50, otherTold: false)
    check("the lesson's app in front: its front window is top, with its title, and no other",
          inFront.title == "Alpha.pdf" && inFront.onScreen && inFront.top?.id == 3546 && inFront.top?.title == "Charlie.pdf" && inFront.other == nil)
    let elsewhere = identLook(window: 3545, own: lesson, pid: 50, list: list, front: 60, otherTold: true)
    check("another app in front: no top, and its front window is other",
          elsewhere.top == nil && elsewhere.other?.id == 4 && elsewhere.other?.title == "Bravo.pdf")
    check("nothing of another app's window when it may not be said (Tutornote's, secure input)",
          identLook(window: 3545, own: lesson, pid: 50, list: list, front: 60, otherTold: false).other == nil)
    let gone = identLook(window: 3545, own: nil, pid: 50, list: Array(list.dropLast()), front: 50, otherTold: false)
    check("a watched window closed: no title, off the screen, its app's next window on top",
          gone.title == "" && !gone.onScreen && gone.top?.id == 3546)
    // Said only when it changed: the same look twice is nothing new, another title is.
    let again = identLook(window: 3545, own: lesson, pid: 50, list: list, front: 50, otherTold: false)
    let retitled = identLook(window: 3545, own: listed(3545, pid: 50, page, title: "Delta.pdf"), pid: 50, list: list, front: 50, otherTold: false)
    check("the same look again is not said; another title, or another window in front, is",
          again == inFront && retitled != inFront && elsewhere != inFront)
    // A drag moves the window and changes nothing else: said on every tick while it goes, its app
    // in front or behind (a Cmd drag), and gone with the window.
    let dragged = listed(3545, pid: 50, page.offsetBy(dx: 40, dy: 25), title: "Alpha.pdf")
    let draggedList = Array(list.dropLast()) + [dragged]
    let movedFront = identLook(window: 3545, own: dragged, pid: 50, list: draggedList, front: 50, otherTold: false)
    let movedBehind = identLook(window: 3545, own: dragged, pid: 50, list: draggedList, front: 60, otherTold: true)
    let saidInFront = inFront.frame == page && movedFront != inFront && movedFront.frame == page.offsetBy(dx: 40, dy: 25)
    let saidBehind = movedBehind != elsewhere && movedBehind.top == nil && movedBehind.frame?.minX == 42
    check("a drag of the watched window is a change, its frame where it went, its app in front or behind",
          saidInFront && saidBehind && gone.frame == nil)
    let movedFields = identFields(movedBehind) { _ in ("Bravo", "com.example.bravo") }
    let movedFrame = movedFields["frame"] as? [String: Double]
    let movedAt = movedFrame?["x"] == 42 && movedFrame?["y"] == 69 && movedFrame?["w"] == 1800
    check("ident says the watched window's frame, with no top while its app is behind",
          movedAt && movedFields["topFrame"] == nil && identFields(gone)["frame"] == nil && JSONSerialization.isValidJSONObject(movedFields))
    let fields = identFields(inFront)
    check("ident says the window, its title, on screen, top and its title and frame, and no other",
          fields["ev"] as? String == "ident" && fields["window"] as? Int == 3545 && fields["onScreen"] as? Bool == true
            && fields["top"] as? Int == 3546 && fields["topTitle"] as? String == "Charlie.pdf"
            && (fields["topFrame"] as? [String: Double])?["w"] == 1600 && fields["other"] == nil
            && (fields["frame"] as? [String: Double])?["h"] == 1125
            && fields["secure"] as? Bool == false && JSONSerialization.isValidJSONObject(fields))
    // Secure input going on or off is said too: nothing is read for another document meanwhile.
    let secured = identLook(window: 3545, own: lesson, pid: 50, list: list, front: 50, otherTold: false, secure: true)
    check("secure input on is said, and its change is a change",
          secured != inFront && identFields(secured)["secure"] as? Bool == true && secured.top == inFront.top)
    let away = identFields(identLook(window: 3545, own: nil, pid: nil, list: list, front: 60, otherTold: true)) { _ in ("Bravo", "com.example.bravo") }
    let awayOther = away["other"] as? [String: Any]
    check("its app behind: top is null; another app's window is other, with its app and frame",
          away["top"] is NSNull && away["topTitle"] as? String == "" && awayOther?["window"] as? Int == 4
            && awayOther?["app"] as? String == "Bravo" && awayOther?["bundle"] as? String == "com.example.bravo"
            && (awayOther?["frame"] as? [String: Double])?["h"] == 1125 && JSONSerialization.isValidJSONObject(away))
    // A wait for the window to be still: two thumbnails in a row that agree, changed or not.
    let width = THUMB_WIDE
    let flat = [UInt8](repeating: 250, count: width * 40)
    var moving = flat
    for i in 0..<(10 * width) { moving[i] = 20 }
    var watch = StillWatch(first: flat)
    check("a window still from the first look is still at the second", watch.still(with: flat))
    var drawing = StillWatch(first: flat)
    check("one still drawing is not, until two looks in a row agree", !drawing.still(with: moving) && drawing.still(with: moving))
}

// MARK: - The companion

/*
  The desktop companion: the tutor drawn beside the cursor over any app (the app's
  src/main/companion.ts). It needs to know which window the cursor is over, as it moves, so the
  band under the cursor can be worked out from a glance read of that window; to hear a press
  at once (the band pulses), a tap with whether it did something in its app (a tap that did
  nothing offers the tutor's help), and scrolls on any window; and to notice when a window it
  cares about settles into a new look (a page the student turned with a key or a swipe, which
  nothing else would say).

  All of it by watching, never by taking: global monitors see the events the other apps get,
  and the cursor is never moved. Watching the mouse (moves, drags, presses, the wheel) needs no
  permission; Apple's NSEvent documentation restricts only key events to apps Accessibility
  trusts. IsSecureEventInputEnabled needs none either. Pictures need Screen Recording, as reads
  do.

  Tutornote's own windows are "own": the companion neither reads them nor helps with them.
  Its ordinary windows (the main window) by their app, its floating ones (the blob, the board)
  by the ids the app passes in `stop`. The lesson's see-through window floats above everything
  at a level of its own and is looked through, as are the pick's.

  Anything else above the ordinary windows stops the search: the Dock, the menu bar and its
  menus, an app's open menu, Spotlight, a notification, a picture-in-picture video. A click there
  is no tap on the page under it, and the cursor over it is over nothing. Only a window of
  another app that covers the whole display (a screen annotation or dimming tool, which lets
  every click through) is looked through, or the tutor would find nothing anywhere; never one of
  the system's own (Launchpad, Mission Control).
*/

var companionOn = false
var stopWindows: Set<CGWindowID> = []
/// The apps never pictured ("private" with "companion": companionPlace.ts PRIVATE_APPS).
var privateBundles: Set<String> = []
/// Which processes are such an app, as asked (cleared with the list).
var privatePids: [pid_t: Bool] = [:]
/// The readers, whose tap is judged against a vetted look ("readers": companionPlace.ts
/// READER_APPS), and which processes are one, as asked (cleared with the list).
var readerBundles: Set<String> = []
var readerPids: [pid_t: Bool] = [:]
var moveMonitor: Any?
/// What the cursor is over: an ordinary window, one of Tutornote's own, or nothing.
enum Hit {
    case window(Target)
    case own(CGRect)
    case nothing

    var window: CGWindowID? {
        if case let .window(t) = self { return t.id }
        return nil
    }

    var frame: CGRect? {
        switch self {
        case let .window(t): return t.frame
        case let .own(frame): return frame
        case .nothing: return nil
        }
    }

    var own: Bool {
        if case .own = self { return true }
        return false
    }
}

/// Where the cursor was last found (overAt), when, and whether secure input was on then.
var lastOver: (hit: Hit, at: TimeInterval, secure: Bool)?
/// Asked again at most this often while the cursor stays where it was found.
let OVER_EVERY_S = 0.05
/// Which processes are Tutornote (isTutornote asks the system each time; the window list is
/// walked on every look).
var tutornotePids: [pid_t: Bool] = [:]

func isTutornoteKept(_ pid: pid_t) -> Bool {
    if let known = tutornotePids[pid] { return known }
    let found = pid == getpid() || (tutornoteAppPid > 1 && pid == tutornoteAppPid) || isTutornote(pid)
    if tutornotePids.count > 256 { tutornotePids.removeAll() }
    tutornotePids[pid] = found
    return found
}

/// Whether `pid` is one of the private apps (a password manager, Keychain Access, System Settings).
func isPrivateApp(_ pid: pid_t) -> Bool {
    if privateBundles.isEmpty { return false }
    if let known = privatePids[pid] { return known }
    let found = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier.map { privateBundles.contains($0) } ?? false
    if privatePids.count > 256 { privatePids.removeAll() }
    privatePids[pid] = found
    return found
}

/// Whether `pid` is one of the readers (Kindle, Books, Preview). Main thread.
func isReaderApp(_ pid: pid_t) -> Bool {
    if readerBundles.isEmpty { return false }
    if let known = readerPids[pid] { return known }
    let found = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier.map { readerBundles.contains($0) } ?? false
    if readerPids.count > 256 { readerPids.removeAll() }
    readerPids[pid] = found
    return found
}

/// No picture of `pid`'s window is taken now: a private app's, or any while a password field has
/// the keys. Main thread.
func keptPrivate(_ pid: pid_t) -> Bool {
    isPrivateApp(pid) || secureInputOn()
}

/// Whether `window` (another app's, above the ordinary windows, at `point`) covers the whole
/// display there and is not the system's own: an overlay drawn over everything, looked through.
func overlaysEverything(_ window: Target, at point: CGPoint) -> Bool {
    var display: CGDirectDisplayID = 0
    var count: UInt32 = 0
    guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return false }
    let screen = CGDisplayBounds(display)
    guard window.frame.width >= screen.width * 0.95, window.frame.height >= screen.height * 0.95 else { return false }
    // (the window server's own have no app)
    guard let bundle = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier else { return false }
    return !bundle.hasPrefix("com.apple.")
}

/*
  Secure input: while a password field has the keys (a browser's, a password manager's),
  macOS lets no app see the keys, and the companion reads no window. Not when only the login
  window holds it: it does while the screen is locked (nobody is pointing at anything then),
  and macOS has been known to leave it held there after unlocking, which would otherwise keep
  every window from the tutor until the next restart.
*/
var loginWindowPid: pid_t = 0

func secureInputOn() -> Bool {
    guard IsSecureEventInputEnabled() else { return false }
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
          let holder = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value
    else { return true }
    if loginWindowPid == 0 || loginWindowPid != holder {
        if NSRunningApplication(processIdentifier: holder)?.bundleIdentifier == "com.apple.loginwindow" { loginWindowPid = holder }
    }
    return holder != loginWindowPid
}

/// What is on top at `point`, front to back, as windowAt finds it, but telling Tutornote's own
/// windows apart from nothing: one listed in `stop` (floating), or an ordinary one of
/// Tutornote's, is "own"; its other floating ones (the lesson's see-through window, the pick's)
/// are looked through. Anything else above the ordinary windows (the Dock, the menu bar, a menu,
/// Spotlight, a notification) is nothing, but for another app's overlay over the whole display
/// (overlaysEverything). One window list (about half a millisecond).
func companionTarget(_ point: CGPoint) -> Hit {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return .nothing
    }
    for info in list {
        guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict), bounds.contains(point),
              let found = target(from: info)
        else { continue }
        if stopWindows.contains(found.id) { return .own(found.frame) }
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        if isTutornoteKept(found.pid) {
            if layer == 0 { return .own(found.frame) }
            continue
        }
        if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
        if layer != 0 {
            if overlaysEverything(found, at: point) { continue }
            return .nothing
        }
        guard found.frame.width > 40, found.frame.height > 40 else { continue }
        return .window(found)
    }
    return .nothing
}

/// What the cursor at `point` is over: looked up at once when it has left where it was last
/// found, else at most every OVER_EVERY_S (another window may have come up within the one it
/// is over). Says so ("over") when the window, "own" or secure input changes. Main thread.
@discardableResult
func overAt(_ point: CGPoint, now: TimeInterval, force: Bool = false) -> Hit {
    if !force, let last = lastOver, now - last.at < OVER_EVERY_S, last.hit.frame?.contains(point) ?? true {
        return last.hit
    }
    let hit = companionTarget(point)
    let secure = secureInputOn()
    let before = lastOver
    lastOver = (hit, now, secure)
    let same = before.map { $0.hit.window == hit.window && $0.hit.own == hit.own && $0.secure == secure } ?? false
    if !same {
        tellOver(hit, secure: secure)
        if let window = hit.window { burst(window) }
    }
    return hit
}

func tellOver(_ hit: Hit, secure: Bool) {
    guard case let .window(t) = hit else {
        emit(["ev": "over", "window": NSNull(), "own": hit.own, "secure": secure])
        return
    }
    let app = NSRunningApplication(processIdentifier: t.pid)
    emit([
        "ev": "over",
        "window": Int(t.id),
        "pid": Int(t.pid),
        "app": app?.localizedName ?? t.owner,
        "bundle": app?.bundleIdentifier ?? "",
        "title": t.title,
        "frame": ["x": Double(t.frame.minX), "y": Double(t.frame.minY), "w": Double(t.frame.width), "h": Double(t.frame.height)],
        "own": false,
        "secure": secure,
    ])
}

/// What the tap compares with, from its press: the watch's latest look of the window from just
/// before it (if there was one, at most PRESS_LOOK_S old) and how old it was then, and its picture
/// being taken; for the words at the tap, the window's frame then, the column around the press
/// (columnRect, in the window's own points) and its picture being taken, and the window's title.
struct PressBefore {
    let window: CGWindowID
    let look: [UInt8]?
    let lookAge: TimeInterval?
    let picture: Task<[UInt8]?, Never>
    let frame: CGRect
    let column: CGRect?
    let columnPicture: Task<CGImage?, Never>?
    let title: String
}
var pressBefore: PressBefore?
/// The watch's look from before a press counts as the window before it only this fresh.
let PRESS_LOOK_S: TimeInterval = 1.5
/// The tap's second picture is taken this long after the release: long enough for a link's
/// hover to give way to what the click did, short enough for the card to come within 0.3 s.
let TAP_AFTER_MS = 150

/// How a tap is judged: acted when the tapped line's own patch differs in `after` from the press
/// picture, or from the watch's look (in a reader, only when the window away from the tap looked
/// the same in both: nothing else faded in or out between them). `wide`: the same base differs
/// away from the tap too. `line`: the largest patch difference; `away`: the difference away from
/// the tap against the base that decided (or the first); `lookUsed`: the look was one of the bases.
struct TapJudgement { let acted: Bool; let wide: Bool; let line: Double; let away: Double; let lookUsed: Bool }

/// `line` and `cols`: the tapped line's own patch (LINE_REACH, SIDE_REACH); `band`: the rows within
/// TAP_REACH of the tap, outside which is "away"; `vetLook`: a reader's tap (isReaderApp).
func judgeTap(look: [UInt8]?, picture: [UInt8]?, after: [UInt8], line: ClosedRange<Int>, cols: ClosedRange<Int>, band: ClosedRange<Int>, vetLook: Bool) -> TapJudgement {
    let width = THUMB_WIDE
    var bases: [[UInt8]] = []
    if let picture { bases.append(picture) }
    var lookUsed = false
    if let look, !vetLook || (picture.map({ awayDifference(look, $0, width: width, rows: band) <= CHANGED_ABOVE }) ?? true) {
        bases.append(look)
        lookUsed = true
    }
    guard !bases.isEmpty else { return TapJudgement(acted: false, wide: false, line: 0, away: 0, lookUsed: false) }
    var decided = bases[0]
    var most = -1.0
    for base in bases {
        let difference = patchDifference(base, after, width: width, rows: line, cols: cols)
        if difference > most {
            most = difference
            decided = base
        }
    }
    let acted = most > CHANGED_ABOVE
    let away = awayDifference(acted ? decided : bases[0], after, width: width, rows: band)
    return TapJudgement(acted: acted, wide: acted && away > CHANGED_ABOVE, line: most, away: away, lookUsed: lookUsed)
}

/// A number for the tap's log line, to one decimal.
func tenths(_ value: Double) -> Double { (value * 10).rounded() / 10 }

/// The taps told so far: a release and its verdict share the number. Main thread. Counted on from
/// the clock (milliseconds) as the helper starts, so a helper started again (after a crash, or for
/// Screen Recording) never says a number the app and the page still hold for an earlier tap.
var tapCount = Int(Date().timeIntervalSince1970 * 1000)
/// The single tap being judged on each window, and those a double click there has made a
/// selection of meanwhile (their verdict says "select"). The judging runs off the main thread.
let judgingLock = NSLock()
var judgingTaps: [CGWindowID: Int] = [:]
var selectedTaps: Set<Int> = []

/// The tap `id` on `window` has its verdict: true when a double click there made it a selection.
func verdictGiven(_ id: Int, on window: CGWindowID) -> Bool {
    judgingLock.lock()
    defer { judgingLock.unlock() }
    if judgingTaps[window] == id { judgingTaps[window] = nil }
    return selectedTaps.remove(id) != nil
}

/*
  Vision reads one picture at a time in a process, whoever asks (measured on the founder's Kindle
  page: a fast read of a tap's column that began 80 ms after a whole window's accurate pass took
  about 220 ms instead of 50, done just after it). A tap's words must be read within
  TEXT_BUDGET_MS of its second picture, and the careful read the app starts at every release
  would be ahead of them: the verdict would fall back to the pixels ("pixels"), the very taps the
  words rule is for. So a read of a whole window takes its picture at once, as before, but reads
  its words only once no tap is being judged (judgingTaps, filled at the release, before the app
  can ask for that read), waiting TAP_HOLD_MS at most; the read says how long ("heldMs").
*/
let TAP_HOLD_MS = 400
let TAP_HOLD_POLL_MS = 10

/// Whether a tap is being judged on any window now.
func tapBeingJudged() -> Bool {
    judgingLock.lock()
    defer { judgingLock.unlock() }
    return !judgingTaps.isEmpty
}

/// Wait while a tap is being judged on any window, `ms` at most; how long it waited (ms).
func tapsJudged(upTo ms: Int) async -> Int {
    let started = DispatchTime.now()
    while msSince(started) < ms && tapBeingJudged() {
        await sleepMs(TAP_HOLD_POLL_MS)
    }
    return msSince(started)
}

/*
  A tap on any ordinary window, with the companion on. Its release is said at once ("release"),
  before any picture, so the page can paint the card in the same frame; then the verdict ("tap",
  the same id), once the window has been looked at again TAP_AFTER_MS after the release:

    covered   another window is on top at the tap now (a menu, a popover, a sheet): acted.
    title     the window's title changed since the press (a link followed, a tab chosen): acted.
    skipped   the tapped line's own patch did not change (judgeTap): not acted, and no words read,
              as fast as before.
    then the words at the tap decide (judgeText, on the column around it before and after):
    kept      the tapped words are still there, moved at most TEXT_SHIFT points, whatever else
              redrew (a reader's bars, the page laid out again under them): not acted.
    gone, content, caret: acted (the words went; the tapped label stayed but the content away from
              it changed, a tab or a sidebar item; the click put a caret there).
    none      no words at the tap or near it (a picture, a wide margin): the pixels decide. A tap on
              a margin with rows near it is told by those rows (judgeMargin): kept or gone.
    pixels    the words could not be read within TEXT_BUDGET_MS of the second picture, or a
              picture failed: the pixels decide.

  A double click (clicks 2 or more) selects words: acted, "select", with no pictures, and so is a
  single tap there whose verdict had not gone yet. "moved", as for the watched window: it no longer
  looked as at its last read when pressed (middle rows). A private window (or any while a
  password field has the keys) is not pictured: its tap is said at once, as having done nothing.
*/
func companionTap(at point: CGPoint, alt: Bool, clicks: Int, hand: Bool, before: PressBefore?) {
    guard case let .window(top) = companionTarget(point) else { return }
    tapCount += 1
    let id = tapCount
    let hidden = keptPrivate(top.pid)
    emit([
        "ev": "release", "id": id, "x": Double(point.x), "y": Double(point.y), "window": Int(top.id), "alt": alt,
        "clicks": clicks, "hand": hand, "private": hidden,
    ])
    let tap: [String: Any] = ["ev": "tap", "id": id, "x": Double(point.x), "y": Double(point.y), "window": Int(top.id), "alt": alt]
    if hidden {
        emit(tap.merging(["moved": false, "acted": false]) { _, new in new })
        return
    }
    if clicks >= 2 {
        judgingLock.lock()
        if let single = judgingTaps[top.id] { selectedTaps.insert(single) }
        judgingLock.unlock()
        emit(tap.merging(["moved": false, "acted": true, "words": "select"]) { _, new in new })
        return
    }
    judgingLock.lock()
    judgingTaps[top.id] = id
    judgingLock.unlock()
    burst(top.id)
    let earlier = before?.window == top.id ? before : nil
    let reader = isReaderApp(top.pid)
    // The column as it was pressed, in screen points, and its words, read while the click settles.
    let crop = earlier.flatMap { e in e.column.map { $0.offsetBy(dx: e.frame.minX, dy: e.frame.minY) } }
    let rowsBefore: Task<[TextRow]?, Never>? = earlier?.columnPicture.flatMap { picture in
        crop.map { crop in
            Task.detached(priority: .userInitiated) {
                guard let image = await picture.value else { return nil }
                return try? textRows(image, crop: crop, spans: true)
            }
        }
    }
    Task {
        await sleepMs(TAP_AFTER_MS)
        // In parallel: the window's thumbnail and its column again, and what is on top at the tap.
        async let afterThumb = quickThumbnail(top.id, frame: top.frame)
        async let afterColumn = columnAgain(top.id, earlier)
        let (onTop, still) = await MainActor.run { (windowOnTop(at: point), onScreenWindow(top.id)) }
        let after = await afterThumb
        let picture = await earlier?.picture.value
        var judged = TapJudgement(acted: false, wide: false, line: 0, away: 0, lookUsed: false)
        var band: ClosedRange<Int>?
        if let after,
           let line = bandRows(y: point.y, frame: top.frame, height: after.count / THUMB_WIDE, reach: LINE_REACH),
           let cols = patchCols(x: point.x, frame: top.frame, width: THUMB_WIDE),
           let rows = bandRows(y: point.y, frame: top.frame, height: after.count / THUMB_WIDE) {
            band = rows
            judged = judgeTap(look: earlier?.look, picture: picture, after: after, line: line, cols: cols, band: rows, vetLook: reader)
        }
        var moved = false
        if let seen = lastSeen(top.id), let base = picture ?? after { moved = middleDifference(seen, base, width: THUMB_WIDE) > CHANGED_ABOVE }
        var acted = judged.acted
        var fields: [String: Any] = [:]
        if still == nil || (onTop != nil && onTop != top.id) {
            acted = true
            fields["words"] = "covered"
        } else if let was = earlier?.title, let now = still?.title, now != was {
            acted = true
            fields["words"] = "title"
        } else if !judged.acted {
            fields["words"] = "skipped"
        } else if let crop, let rowsBefore, let beforeImage = earlier?.columnPicture {
            let afterImage = await afterColumn
            // (the window away from the tap, less its edges, changed against what the patch was judged on)
            let bases = [picture, judged.lookUsed ? earlier?.look : nil].compactMap { $0 }
            let awayChanged = after.flatMap { a in band.map { b in bases.contains { middleAwayDifference($0, a, width: THUMB_WIDE, rows: b) > CHANGED_ABOVE } } } ?? false
            let started = DispatchTime.now()
            let verdict = await within(TEXT_BUDGET_MS) { () -> TextVerdict? in
                guard let afterImage, let beforeImage = await beforeImage.value, let rows = await rowsBefore.value,
                      let afterRows = try? textRows(afterImage, crop: crop, spans: false)
                else { return nil }
                return judgeText(before: rows, after: afterRows, crop: crop, tap: point, window: top.frame, awayChanged: awayChanged) { rowY, height in
                    caretOnly(before: beforeImage, after: afterImage, crop: crop, tap: point, rowY: rowY, lineHeight: height)
                }
            }
            fields["textMs"] = msSince(started)
            if let verdict {
                fields["words"] = verdict.words
                fields["kept"] = (verdict.kept * 100).rounded() / 100
                fields["shift"] = tenths(verdict.shift)
                if verdict.words != "none" { acted = verdict.words != "kept" }
            } else {
                fields["words"] = "pixels"
            }
        } else {
            fields["words"] = "pixels"
        }
        if verdictGiven(id, on: top.id) {
            acted = true
            fields["words"] = "select"
        }
        let look = judged.lookUsed ? tenths(earlier?.lookAge ?? -1) : -1
        emit(tap.merging(fields.merging([
            "moved": moved, "acted": acted, "wide": judged.wide, "line": tenths(judged.line), "away": tenths(judged.away), "look": look,
        ]) { _, new in new }) { _, new in new })
    }
}

/// The column of a press (PressBefore) taken again now, as large; nil without one.
func columnAgain(_ id: CGWindowID, _ press: PressBefore?) async -> CGImage? {
    guard let press, let source = press.column, press.columnPicture != nil else { return nil }
    return await columnPicture(id, frame: press.frame, source: source)
}

// MARK: - The words at a tap

/*
  The pixels cannot tell a page laid out again from a page turned: when Kindle's bars come in at a
  tap and its page is fitted again under them, or a reply streams in above the tapped line, the
  tapped line's patch differs (judgeTap: acted) though the student's words are all still there. So
  when the patch says acted, the words decide. The column around the tap (COLUMN_REACH points
  either side, the window's full height) is pictured at full size as the button goes down and
  again with the second thumbnail, and both are read with Vision's fast pass (Latin script):

    the anchor  the tapped row (its words within LINE_REACH points of the tap and SIDE_REACH either
                side of it, less any the reach cuts) and up to two nearest rows of TEXT_MIN_WORDS
                words or more within TEXT_NEAR_ROWS points of it.
    kept        the tapped row found again (TEXT_KEEP of its words in order, in one row or a row and
                the next for a line wrapped again, moved TEXT_SHIFT points at most; a row of fewer
                than TEXT_MIN_WORDS words also needs a neighbour found moved as far, within
                TEXT_SAME_SHIFT), and at least half the anchor's rows found moved that far.
    gone        not so: the app used the click.
    a margin    no words at the tap: the nearest rows near it are the anchor, and all of them found
                again moved alike is kept (judgeMargin); "none" with no rows near it either: the
                pixels decide.
    content     kept, but the window away from the tap changed (its middle rows): then a band
                AWAY_GAP points off, AWAY_HALF either side of it, must be found again too, half its
                rows of AWAY_WORDS words or more moved alike, or the click changed the content
                beside a label that stayed (a tab, a sidebar item).
    caret       kept, and all that changed at the tap is a stroke CARET_WIDE points wide at most and
                about a line tall: a caret the click put there (a field, a document).

  Thresholds from a model of the founder's Kindle page (scratchpad tapcard model2: 56 of 56 right),
  checked again by --selftest on pictures drawn here. A page in another script reads as no words:
  the pixels decide, as before.
*/
let COLUMN_REACH: CGFloat = 300
let TEXT_KEEP = 0.6
let TEXT_SHIFT = 120.0
let TEXT_MIN_WORDS = 3
let TEXT_SAME_SHIFT = 10.0
let TEXT_NEAR_ROWS = 160.0
/// A row and the next one this close below it are tried together (a line wrapped again).
let TEXT_REWRAP = 40.0
let AWAY_GAP = 250.0
let AWAY_HALF = 160.0
let AWAY_WORDS = 5
let AWAY_KEEP = 0.7
/// A row within this of a crop's side may have lost its word there.
let CROP_EDGE = 3.0
let CARET_WIDE = 3.0
/// The words must have decided this long after the second picture, or the pixels do.
let TEXT_BUDGET_MS = 120

/// A row Vision read in a column picture: its words (wordKey), each one's left and right when
/// asked for (`spans`), and the row's middle, ends and height, in screen points.
struct TextRow {
    let words: [String]
    let spans: [ClosedRange<Double>]?
    let midY: Double
    let minX: Double
    let maxX: Double
    let height: Double
}

/// A word as rows are compared: lower case, letters and digits only; "" for one too short to tell
/// rows apart by (a single letter).
func wordKey(_ word: Substring) -> String {
    let kept = String(String.UnicodeScalarView(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    return kept.count >= 2 || (kept.count == 1 && kept.first?.isNumber == true) ? kept : ""
}

/// The rows in `image`, a picture of `crop` (screen points), with each word's left and right when
/// `spans` (by Vision's box for it, else by its place among the row's characters).
func textRows(_ image: CGImage, crop: CGRect, spans: Bool) throws -> [TextRow] {
    var rows: [TextRow] = []
    for observation in try recognize(image, .fast) {
        guard let best = observation.topCandidates(1).first else { continue }
        let box = observation.boundingBox
        let minX = Double(crop.minX + box.minX * crop.width)
        let maxX = Double(crop.minX + box.maxX * crop.width)
        let string = best.string
        let characters = Double(max(string.count, 1))
        var words: [String] = []
        var xs: [ClosedRange<Double>] = []
        var index = string.startIndex
        while let start = string[index...].firstIndex(where: { !$0.isWhitespace }) {
            let end = string[start...].firstIndex(where: { $0.isWhitespace }) ?? string.endIndex
            index = end
            let key = wordKey(string[start..<end])
            if key.isEmpty { continue }
            words.append(key)
            guard spans else { continue }
            if let found = try? best.boundingBox(for: start..<end)?.boundingBox, found.width < box.width * 0.95 || words.count == 1 {
                let left = Double(crop.minX + found.minX * crop.width)
                let right = Double(crop.minX + found.maxX * crop.width)
                xs.append(left...max(left, right))
            } else {
                let from = Double(string.distance(from: string.startIndex, to: start)) / characters
                let to = Double(string.distance(from: string.startIndex, to: end)) / characters
                xs.append((minX + from * (maxX - minX))...(minX + to * (maxX - minX)))
            }
        }
        if words.isEmpty { continue }
        rows.append(TextRow(words: words, spans: spans ? xs : nil, midY: Double(crop.minY + (1 - box.midY) * crop.height),
                            minX: minX, maxX: maxX, height: Double(box.height * crop.height)))
    }
    return rows
}

/// The length of the longest common subsequence of two lists of words.
func lcs(_ a: [String], _ b: [String]) -> Int {
    if a.isEmpty || b.isEmpty { return 0 }
    var previous = [Int](repeating: 0, count: b.count + 1)
    for x in a {
        var current = [Int](repeating: 0, count: b.count + 1)
        for (j, y) in b.enumerated() { current[j + 1] = x == y ? previous[j] + 1 : max(previous[j + 1], current[j]) }
        previous = current
    }
    return previous[b.count]
}

/// Every place in `after` (a row, or a row and the next) that holds at least TEXT_KEEP of `words`
/// in order, within TEXT_SHIFT of `y`: the share found, and how far it moved.
func textPlaces(_ words: [String], y: Double, in after: [TextRow]) -> [(kept: Double, shift: Double)] {
    guard !words.isEmpty else { return [] }
    let rows = after.sorted { $0.midY < $1.midY }
    var found: [(kept: Double, shift: Double)] = []
    for (i, row) in rows.enumerated() where abs(row.midY - y) <= TEXT_SHIFT {
        var tried = [row.words]
        if i + 1 < rows.count, rows[i + 1].midY - row.midY < TEXT_REWRAP { tried.append(row.words + rows[i + 1].words) }
        for candidate in tried {
            let kept = Double(lcs(words, candidate)) / Double(words.count)
            if kept >= TEXT_KEEP { found.append((kept, row.midY - y)) }
        }
    }
    return found
}

/// A row's words that lie wholly within `reach` (screen points, sideways).
func wordsWithin(_ row: TextRow, _ reach: ClosedRange<Double>) -> [String] {
    guard let spans = row.spans else { return [] }
    return zip(row.words, spans).filter { reach.contains($0.1.lowerBound) && reach.contains($0.1.upperBound) }.map { $0.0 }
}

/// A row's words less any the crop's side may have cut.
func edgeTrimmed(_ row: TextRow, crop: CGRect) -> [String] {
    var words = row.words
    if row.minX - Double(crop.minX) < CROP_EDGE, !words.isEmpty { words.removeFirst() }
    if Double(crop.maxX) - row.maxX < CROP_EDGE, !words.isEmpty { words.removeLast() }
    return words
}

/// What the words at a tap said: kept, gone, none, content or caret; the share of the tapped row
/// found again, and how far it had moved (points).
struct TextVerdict { let words: String; let kept: Double; let shift: Double }

/// The tapped row within `reach`: the row nearest the tap within LINE_REACH and the pieces of it
/// Vision read apart, its words, its middle and height; nil with no words there.
func tappedRow(_ before: [TextRow], tap: CGPoint, reach: ClosedRange<Double>) -> (words: [String], midY: Double, height: Double)? {
    let y = Double(tap.y)
    let near = before.filter { abs($0.midY - y) <= Double(LINE_REACH) && $0.maxX >= reach.lowerBound && $0.minX <= reach.upperBound }
    guard let nearest = near.min(by: { abs($0.midY - y) < abs($1.midY - y) }) else { return nil }
    let pieces = near.filter { abs($0.midY - nearest.midY) <= nearest.height / 2 }.sorted { $0.minX < $1.minX }
    let words = pieces.flatMap { wordsWithin($0, reach) }
    return words.isEmpty ? nil : (words, pieces.map(\.midY).reduce(0, +) / Double(pieces.count), nearest.height)
}

/// Whether the band AWAY_GAP points from the tap (below it in the window's upper half, else above)
/// is still there: half its rows of AWAY_WORDS words or more found again (AWAY_KEEP) moved alike.
/// True with no such rows (nothing to tell by).
func awayKept(before: [TextRow], after: [TextRow], crop: CGRect, tap: CGPoint, window: CGRect) -> Bool {
    let middle = Double(tap.y) < Double(window.midY) ? Double(tap.y) + AWAY_GAP : Double(tap.y) - AWAY_GAP
    var rows: [(words: [String], y: Double)] = []
    for row in before where abs(row.midY - middle) <= AWAY_HALF {
        let words = edgeTrimmed(row, crop: crop)
        if words.count >= AWAY_WORDS { rows.append((words, row.midY)) }
    }
    guard !rows.isEmpty else { return true }
    let shifts: [[Double]] = rows.map { row in
        after.filter { abs($0.midY - row.y) <= TEXT_SHIFT && Double(lcs(row.words, $0.words)) / Double(row.words.count) >= AWAY_KEEP }.map { $0.midY - row.y }
    }
    var most = 0
    for shift in shifts.joined() { most = max(most, shifts.filter { $0.contains { abs($0 - shift) <= TEXT_SAME_SHIFT } }.count) }
    return 2 * most >= rows.count
}

/// Whether all that changed at the tap between two pictures of `crop` (its row, a line above and
/// below, SIDE_REACH either side) is one stroke at most CARET_WIDE points wide and about a line
/// tall: a caret. Columns with no more change than a focus ring's two edges would make count as
/// unchanged.
func caretOnly(before: CGImage, after: CGImage, crop: CGRect, tap: CGPoint, rowY: Double, lineHeight: Double) -> Bool {
    guard before.width == after.width, before.height == after.height, crop.width > 0, lineHeight > 0 else { return false }
    let perPoint = Double(before.width) / Double(crop.width)
    let left = max(Double(crop.minX), Double(tap.x - SIDE_REACH))
    let right = min(Double(crop.maxX), Double(tap.x + SIDE_REACH))
    let top = max(Double(crop.minY), rowY - lineHeight)
    let bottom = min(Double(crop.maxY), rowY + lineHeight)
    let region = CGRect(x: ((left - Double(crop.minX)) * perPoint).rounded(.down), y: ((top - Double(crop.minY)) * perPoint).rounded(.down),
                        width: ((right - left) * perPoint).rounded(.up), height: ((bottom - top) * perPoint).rounded(.up))
    guard region.width >= 1, region.height >= 1, let a = before.cropping(to: region), let b = after.cropping(to: region),
          a.width == b.width, a.height == b.height
    else { return false }
    let width = a.width
    let height = a.height
    func grey(_ image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
    guard let greyBefore = grey(a), let greyAfter = grey(b) else { return false }
    var counts = [Int](repeating: 0, count: width)
    for r in 0..<height {
        for c in 0..<width where abs(Int(greyBefore[r * width + c]) - Int(greyAfter[r * width + c])) > 48 { counts[c] += 1 }
    }
    let quiet = Int((CARET_WIDE * perPoint).rounded())
    let changed = counts.indices.filter { counts[$0] > quiet }
    guard let first = changed.first, let last = changed.last, last - first + 1 == changed.count,
          Double(last - first + 1) <= CARET_WIDE * perPoint + 1
    else { return false }
    let tallest = Double(counts[first...last].max() ?? 0)
    let linePixels = lineHeight * perPoint
    return tallest >= 0.6 * linePixels && tallest <= 1.6 * linePixels
}

/// The rule (above), on the rows read before and after the click. `awayChanged`: the window's
/// middle rows changed away from the tap; `caret`: caretOnly for the tapped row (its middle and
/// height), asked only when it matters.
func judgeText(before: [TextRow], after: [TextRow], crop: CGRect, tap: CGPoint, window: CGRect, awayChanged: Bool,
               caret: (Double, Double) -> Bool) -> TextVerdict {
    let reach = Double(tap.x - SIDE_REACH)...Double(tap.x + SIDE_REACH)
    guard let row = tappedRow(before, tap: tap, reach: reach) else {
        return judgeMargin(before: before, after: after, crop: crop, tap: tap, window: window, awayChanged: awayChanged, reach: reach, caret: caret)
    }
    let mine = textPlaces(row.words, y: row.midY, in: after)
    var nearby: [(words: [String], y: Double)] = []
    for other in before {
        let distance = abs(other.midY - row.midY)
        guard distance > row.height / 2, distance <= TEXT_NEAR_ROWS else { continue }
        let words = wordsWithin(other, reach)
        if words.count >= TEXT_MIN_WORDS { nearby.append((words, other.midY)) }
    }
    nearby.sort { abs($0.y - row.midY) < abs($1.y - row.midY) }
    let neighbours = nearby.prefix(2)
    let short = row.words.count < TEXT_MIN_WORDS
    // (a row of a word or two, with no neighbour to tell by: one word is found anywhere)
    if short && neighbours.isEmpty {
        return mine.isEmpty ? TextVerdict(words: "gone", kept: 0, shift: 0) : TextVerdict(words: "none", kept: mine.map(\.kept).max() ?? 0, shift: 0)
    }
    let theirs = neighbours.map { textPlaces($0.words, y: $0.y, in: after) }
    let ranked = mine.sorted { $0.kept > $1.kept || ($0.kept == $1.kept && abs($0.shift) < abs($1.shift)) }
    for place in ranked {
        let found = theirs.filter { $0.contains { abs($0.shift - place.shift) <= TEXT_SAME_SHIFT } }.count
        if short && found == 0 { continue }
        guard 2 * (1 + found) >= 1 + theirs.count else { continue }
        if awayChanged && !awayKept(before: before, after: after, crop: crop, tap: tap, window: window) {
            return TextVerdict(words: "content", kept: place.kept, shift: place.shift)
        }
        if caret(row.midY, row.height) { return TextVerdict(words: "caret", kept: place.kept, shift: place.shift) }
        return TextVerdict(words: "kept", kept: place.kept, shift: place.shift)
    }
    let best = after.filter { abs($0.midY - row.midY) <= TEXT_SHIFT }.map { Double(lcs(row.words, $0.words)) / Double(row.words.count) }.max() ?? 0
    return TextVerdict(words: "gone", kept: best, shift: 0)
}

/*
  A tap on no words (a margin, the top of the page, the white between paragraphs or under the last
  line) that the pixels said was acted: Kindle's bars coming in at a click on its margin, and the
  page fitted again under them, change the patch there as much as a page turned. The anchor is then
  the up to two nearest rows of TEXT_MIN_WORDS words or more within TEXT_NEAR_ROWS points of the
  tap (their words within SIDE_REACH of it). All of them found again, moved alike (within
  TEXT_SAME_SHIFT): kept, as for a tap on words, but for content and caret (an empty field the click
  put a caret in). Not all of them: gone. No such rows near it: "none", the pixels decide.
*/
func judgeMargin(before: [TextRow], after: [TextRow], crop: CGRect, tap: CGPoint, window: CGRect, awayChanged: Bool,
                 reach: ClosedRange<Double>, caret: (Double, Double) -> Bool) -> TextVerdict {
    let y = Double(tap.y)
    var nearby: [(words: [String], y: Double, height: Double)] = []
    for row in before where abs(row.midY - y) <= TEXT_NEAR_ROWS {
        let words = wordsWithin(row, reach)
        if words.count >= TEXT_MIN_WORDS { nearby.append((words, row.midY, row.height)) }
    }
    nearby.sort { abs($0.y - y) < abs($1.y - y) }
    let anchor = nearby.prefix(2)
    guard let nearest = anchor.first else { return TextVerdict(words: "none", kept: 0, shift: 0) }
    let places = anchor.map { textPlaces($0.words, y: $0.y, in: after) }
    let ranked = places[0].sorted { $0.kept > $1.kept || ($0.kept == $1.kept && abs($0.shift) < abs($1.shift)) }
    for place in ranked {
        guard places.dropFirst().allSatisfy({ $0.contains { abs($0.shift - place.shift) <= TEXT_SAME_SHIFT } }) else { continue }
        if awayChanged && !awayKept(before: before, after: after, crop: crop, tap: tap, window: window) {
            return TextVerdict(words: "content", kept: place.kept, shift: place.shift)
        }
        // (a caret at the tap itself, about as tall as the rows near it)
        if caret(y, nearest.height) { return TextVerdict(words: "caret", kept: place.kept, shift: place.shift) }
        return TextVerdict(words: "kept", kept: place.kept, shift: place.shift)
    }
    return TextVerdict(words: "gone", kept: 0, shift: 0)
}

/// The column a tap's words are read in: COLUMN_REACH points either side of `x`, the window's full
/// height, in the window's own points (its top left 0, 0); nil off the window.
func columnRect(x: CGFloat, frame: CGRect) -> CGRect? {
    let left = max(0, x - COLUMN_REACH - frame.minX)
    let right = min(frame.width, x + COLUMN_REACH - frame.minX)
    guard right - left >= 1, frame.height >= 1 else { return nil }
    return CGRect(x: left, y: 0, width: right - left, height: frame.height)
}

/// A picture of the part `source` (its own points) of the window `id` at `frame`, at its display's
/// own scale, through its kept handle (cachedFilter); nil when it cannot be had.
func columnPicture(_ id: CGWindowID, frame: CGRect, source: CGRect) async -> CGImage? {
    let config = SCStreamConfiguration()
    let scale = scaleFor(frame)
    config.sourceRect = source
    config.width = max(1, Int((source.width * scale).rounded()))
    config.height = max(1, Int((source.height * scale).rounded()))
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    if let filter = try? await cachedFilter(id), let picture = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
        return picture
    }
    guard let filter = try? await cachedFilter(id, fresh: true) else { return nil }
    return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
}

/// The window on top at `point` now, over every layer (a menu, a popover, a sheet the click
/// opened), looking through what companionTarget looks through: Tutornote's own windows, ones all
/// but transparent, another app's overlay over the whole display, and an ordinary window 40 points
/// or smaller (a floating widget, a timer), so the window it found at the release is still the one
/// here on a screen that did not change. Nil when the window list cannot be had or nothing is
/// there. Main thread.
func windowOnTop(at point: CGPoint) -> CGWindowID? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for info in list {
        guard let found = target(from: info), found.frame.contains(point) else { continue }
        if stopWindows.contains(found.id) || isTutornoteKept(found.pid) { continue }
        if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        if layer != 0 && overlaysEverything(found, at: point) { continue }
        if layer == 0 && (found.frame.width <= 40 || found.frame.height <= 40) { continue }
        return found.id
    }
    return nil
}

/// The first of two to say so: an answer or a deadline (within).
final class FirstOnly: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}

/// `work`'s answer, or nil once `ms` have passed first (the work goes on; its answer is dropped).
func within<T>(_ ms: Int, _ work: @escaping () async -> T?) async -> T? {
    await withCheckedContinuation { (answer: CheckedContinuation<T?, Never>) in
        let first = FirstOnly()
        Task.detached(priority: .userInitiated) {
            let value = await work()
            if first.take() { answer.resume(returning: value) }
        }
        Task {
            await sleepMs(ms)
            if first.take() { answer.resume(returning: nil) }
        }
    }
}

/*
  A link under the press: another app shows the pointing hand over it. The system's cursor
  (NSCursor.currentSystem) is the hand when it has the hand's hot spot, size and picture (its TIFF
  bytes, taken once). The page then waits for the verdict before it shows a card, so none flashes
  up on a link being followed. Anything unexpected (no cursor, no picture): not the hand.
*/
enum PointingHand {
    static let print: (hotSpot: NSPoint, size: NSSize, tiff: Data)? = {
        let hand = NSCursor.pointingHand
        guard let tiff = hand.image.tiffRepresentation else { return nil }
        return (hand.hotSpot, hand.image.size, tiff)
    }()
}

func isPointingHand(_ cursor: NSCursor?) -> Bool {
    guard let cursor, let hand = PointingHand.print, cursor.hotSpot == hand.hotSpot, cursor.image.size == hand.size else { return false }
    return cursor.image.tiffRepresentation == hand.tiff
}

/*
  Pictures of a window, many times a second, without asking ScreenCaptureKit for every window
  on the screen each time (shareableWindow, tens of milliseconds): its handle is kept for
  FILTER_KEEP_S, and fetched again then, or at once when a picture through it fails (the window
  closed and came back).
*/
let FILTER_KEEP_S: TimeInterval = 10
let filterLock = NSLock()
var keptFilters: [CGWindowID: (filter: SCContentFilter, size: CGSize, at: TimeInterval)] = [:]

/// The handle kept for `id`, while it is fresh, with the window's size as it was made for it.
func keptFilter(_ id: CGWindowID, now: TimeInterval) -> (filter: SCContentFilter, size: CGSize)? {
    filterLock.lock()
    defer { filterLock.unlock() }
    guard let kept = keptFilters[id], now - kept.at < FILTER_KEEP_S else { return nil }
    return (kept.filter, kept.size)
}

/// `filter` nil forgets the handle kept for `id`, else keeps it from `now`, made for a window of `size`.
func keepFilter(_ id: CGWindowID, _ filter: SCContentFilter?, size: CGSize = .zero, now: TimeInterval) {
    filterLock.lock()
    defer { filterLock.unlock() }
    keptFilters = keptFilters.filter { now - $0.value.at < 6 * FILTER_KEEP_S }
    keptFilters[id] = filter.map { ($0, size, now) }
}

func cachedFilter(_ id: CGWindowID, fresh: Bool = false) async throws -> SCContentFilter? {
    let now = ProcessInfo.processInfo.systemUptime
    if !fresh, let kept = keptFilter(id, now: now) { return kept.filter }
    guard let window = try await shareableWindow(id) else {
        keepFilter(id, nil, now: now)
        return nil
    }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    keepFilter(id, filter, size: window.frame.size, now: now)
    return filter
}

/*
  A read and a turn take the handle kept too (throughFilter): a lesson's turn asks for its own
  afresh and keeps it, and the careful read after it, a moment later, pictures through that one.
  Kept only while the window is still the size it had when the handle was made: the size
  ScreenCaptureKit listed it at then (SCWindow's frame, in the same points as the window lists'
  frames; not the handle's contentRect, which Apple's header calls only the content's size, and
  which was never seen here to agree with a window's frame, its shadow in or out). A window resized
  since has a new one asked for, as one whose picture through the kept handle fails. A handle kept
  with no size is taken as the glances always took it.
*/
/// How far a window's size may be from its kept handle's and still be pictured through it, in points.
let FILTER_SIZE_SLACK: CGFloat = 1

/// Whether a handle made for a window of `kept` size still fits it at `frame`.
func filterFits(_ kept: CGSize, _ frame: CGRect) -> Bool {
    if kept.width <= 0 || kept.height <= 0 { return true }
    return abs(kept.width - frame.width) <= FILTER_SIZE_SLACK && abs(kept.height - frame.height) <= FILTER_SIZE_SLACK
}

/// `take` done through the window `id`'s kept handle while it fits `frame`, else (or when that
/// fails) through one asked for now, and kept. Nil when ScreenCaptureKit no longer lists the
/// window; throws when `take` fails through the fresh handle too.
func throughFilter<T>(_ id: CGWindowID, frame: CGRect, _ take: (SCContentFilter) async throws -> T) async throws -> T? {
    if let kept = keptFilter(id, now: ProcessInfo.processInfo.systemUptime), filterFits(kept.size, frame),
       let done = try? await take(kept.filter) {
        return done
    }
    guard let fresh = try await cachedFilter(id, fresh: true) else { return nil }
    return try await take(fresh)
}

/// A thumbnail of the window `id` at `frame` (its size decides the thumbnail's), or nil.
func quickThumbnail(_ id: CGWindowID, frame: CGRect) async -> [UInt8]? {
    let config = thumbnailConfig(for: frame)
    if let filter = try? await cachedFilter(id), let picture = try? await thumbnail(filter, config) { return picture }
    guard let filter = try? await cachedFilter(id, fresh: true) else { return nil }
    return try? await thumbnail(filter, config)
}

/*
  Watching for a new look ("observe"): the lesson's window and the one under the cursor, two at
  most (the companion paused, the lesson's alone, with "companion" off meanwhile; a lesson without
  the companion, its own). A thumbnail of each every OBSERVE_IDLE_MS, and every POLL_MS for BURST_S after
  something happens on it (a press, a tap, a scroll, the cursor coming over it), when a page
  turns. A window that differs in its middle rows (middleRows) from how it looked at its last
  read (or, never read, from the first look at it) and has stopped moving (two thumbnails in a
  row agree, as after a turn) is said to have changed, once: the helper stays quiet about it
  until it looks different again, or is read again. Left alone while a lesson's own turn of it
  is going on, and for TURN_QUIET_S after (the lesson reads it then itself).

  A new look that a wheel scroll of the window explains (one began within SCROLL_EXPLAINS_S of
  the student's last scroll up or down there, which the app was told: "scroll") is no "changed":
  the app follows the scroll itself, and a "changed" would hide the lesson's marks for a careful
  reread after every scroll. Keys and a dragged scroll bar send no wheel, and are said; so is a
  sideways pan or swipe (wheelStep), which moves no line up or down. In a window the app observes
  as turning by the page ("page": a lesson in Kindle or Books, or in an app a key turned) no wheel
  explains a new look: a wheel or a swipe there turns a whole page, which nothing follows from the
  scroll, and the page it turned is said as a key's is. A key pressed in the watched window's app
  bursts it at once (keyTick). A window that keeps changing (a video, typing) is looked at often
  for CHANGING_BURST_S at most, then twice a second until it is still again.
*/
let OBSERVE_IDLE_MS = 500
let BURST_S: TimeInterval = 1.5
let TURN_QUIET_S: TimeInterval = 2
let SCROLL_EXPLAINS_S: TimeInterval = 0.6
let CHANGING_BURST_S: TimeInterval = 3
/// Windows no longer watched keep their looks (a tap's baseline, what was said) this many at most.
let LOOKS_KEPT = 8
let observeLock = NSLock()
var observed: [CGWindowID] = []
var observeTask: Task<Void, Never>?
/// Per window: busy until (a burst), next look due, the latest thumbnail (and when), the one
/// before it, the first look (for a window never read), the look last said to have changed,
/// since when it has looked different, and the student's last wheel scroll of it.
var burstUntil: [CGWindowID: TimeInterval] = [:]
var lookDue: [CGWindowID: TimeInterval] = [:]
var latestLook: [CGWindowID: [UInt8]] = [:]
var latestLookAt: [CGWindowID: TimeInterval] = [:]
var previousLook: [CGWindowID: [UInt8]] = [:]
var firstLook: [CGWindowID: [UInt8]] = [:]
var toldLook: [CGWindowID: [UInt8]] = [:]
var differentSince: [CGWindowID: TimeInterval] = [:]
var scrolledAt: [CGWindowID: TimeInterval] = [:]
/// The windows observed now that turn by the page ("observe"'s "page").
var pagedObserved: Set<CGWindowID> = []
/// The windows no longer watched whose looks are kept, the latest last.
var unobserved: [CGWindowID] = []
/// A lesson's turns going on, by window, and when the last one of each ended; and the same for
/// its turns by a key alone, whose keys are no student's (keyTick).
var turnsOn: [CGWindowID: Int] = [:]
var turnEnded: [CGWindowID: TimeInterval] = [:]
var keyTurnsOn: [CGWindowID: Int] = [:]
var keyTurnEnded: [CGWindowID: TimeInterval] = [:]

/// Whether a new look that began at `since` is the wheel scroll last heard at `scrolled`'s. Never
/// in a window that turns by the page (`page`): a wheel or a swipe there turns a whole page.
func scrollExplains(since: TimeInterval, scrolled: TimeInterval?, page: Bool = false) -> Bool {
    guard !page, let scrolled else { return false }
    return scrolled >= since - SCROLL_EXPLAINS_S
}

/// Whether a window that has looked different since `since` is still looked at often at `now`.
func keepsBursting(since: TimeInterval, now: TimeInterval) -> Bool {
    now - since < CHANGING_BURST_S
}

/// A lesson's turn of `window` begins (`on`) or ends; `keys`: one that presses keys.
func turning(_ window: CGWindowID, _ on: Bool, keys: Bool = false) {
    observeLock.lock()
    defer { observeLock.unlock() }
    if on {
        turnsOn[window, default: 0] += 1
        if keys { keyTurnsOn[window, default: 0] += 1 }
    } else {
        let now = ProcessInfo.processInfo.systemUptime
        turnsOn[window] = max(0, (turnsOn[window] ?? 1) - 1)
        turnEnded[window] = now
        if keys {
            keyTurnsOn[window] = max(0, (keyTurnsOn[window] ?? 1) - 1)
            keyTurnEnded[window] = now
        }
    }
}

/// Something happened on `window`: look at it often for a moment.
func burst(_ window: CGWindowID) {
    observeLock.lock()
    burstUntil[window] = ProcessInfo.processInfo.systemUptime + BURST_S
    lookDue[window] = 0
    observeLock.unlock()
}

/// `window` was just read: whatever it looked like before no longer counts as new.
func observedRead(_ window: CGWindowID) {
    observeLock.lock()
    firstLook[window] = nil
    toldLook[window] = nil
    differentSince[window] = nil
    observeLock.unlock()
}

/// The latest thumbnail the watch took of `window` (a tap's look from before its press), and how
/// old it is in seconds; `within`: only one taken at most that long ago.
func latestThumb(_ window: CGWindowID, within: TimeInterval? = nil) -> (thumb: [UInt8], age: TimeInterval)? {
    observeLock.lock()
    defer { observeLock.unlock() }
    guard let thumb = latestLook[window], let at = latestLookAt[window] else { return nil }
    let age = ProcessInfo.processInfo.systemUptime - at
    if let within, age > within { return nil }
    return (thumb, age)
}

/// The student scrolled `window` with the wheel (or a trackpad), as told ("scroll").
func scrolled(_ window: CGWindowID, at time: TimeInterval) {
    observeLock.lock()
    scrolledAt[window] = time
    observeLock.unlock()
}

/// Watch `windows` (two at most) for a new look; `paged`: those of them that turn by the page.
func observeWindows(_ windows: [CGWindowID], paged: Set<CGWindowID> = []) {
    observeLock.lock()
    let kept = Array(windows.prefix(2))
    pagedObserved = paged.intersection(kept)
    // (what is known about a window no longer watched goes, but how it last looked, for the
    // latest few: a helper that lives as long as the app would keep every window's otherwise)
    for gone in observed where !kept.contains(gone) {
        burstUntil[gone] = nil
        lookDue[gone] = nil
        previousLook[gone] = nil
        differentSince[gone] = nil
        unobserved.removeAll { $0 == gone }
        unobserved.append(gone)
    }
    unobserved.removeAll { kept.contains($0) }
    while unobserved.count > LOOKS_KEPT {
        let old = unobserved.removeFirst()
        latestLook[old] = nil
        latestLookAt[old] = nil
        firstLook[old] = nil
        toldLook[old] = nil
        scrolledAt[old] = nil
    }
    for window in kept where !observed.contains(window) { lookDue[window] = 0 }
    observed = kept
    // (the companion on or not: paused, the app still has the lesson's window watched, which
    // "companion" off stopped, as it stops every one)
    let run = !kept.isEmpty
    let going = observeTask
    if run && going == nil { observeTask = Task { await observeLoop() } }
    if !run {
        observeTask = nil
        going?.cancel()
    }
    observeLock.unlock()
}

/// The windows watched now. None (nothing left to watch, as after the companion went off): the
/// loop ends, and the next "observe" starts another.
func observedNow() -> [CGWindowID] {
    observeLock.lock()
    defer { observeLock.unlock() }
    let windows = observed
    if windows.isEmpty { observeTask = nil }
    return windows
}

/// Whether a look at `window` is due now (and, if so, when the next one is): never while a
/// lesson's turn of it is going on, or just after.
func lookNow(_ window: CGWindowID, now: TimeInterval) -> Bool {
    observeLock.lock()
    defer { observeLock.unlock() }
    let busy = (turnsOn[window] ?? 0) > 0 || now - (turnEnded[window] ?? -.infinity) < TURN_QUIET_S
    guard !busy, now >= lookDue[window] ?? 0 else { return false }
    let quick = now < (burstUntil[window] ?? 0)
    lookDue[window] = now + Double(quick ? POLL_MS : OBSERVE_IDLE_MS) / 1000
    return true
}

func observeLoop() async {
    while !Task.isCancelled {
        let windows = observedNow()
        if windows.isEmpty { break }
        // (a key just pressed in the lesson's app: its window is looked at in this tick)
        await keyTick(windows)
        for window in windows {
            guard lookNow(window, now: ProcessInfo.processInfo.systemUptime), let target = onScreenWindow(window) else { continue }
            guard let look = await quickThumbnail(window, frame: target.frame) else { continue }
            looked(window, look)
        }
        // Woken often enough for a burst to start within a tenth of a second; a look is taken
        // only when one is due.
        await sleepMs(POLL_MS)
    }
}

/// A new thumbnail of an observed window: say "changed" when it has settled into a new look.
func looked(_ window: CGWindowID, _ look: [UInt8]) {
    let base = lastSeen(window)
    let now = ProcessInfo.processInfo.systemUptime
    observeLock.lock()
    latestLook[window] = look
    latestLookAt[window] = now
    let previous = previousLook[window]
    previousLook[window] = look
    if base == nil && firstLook[window] == nil { firstLook[window] = look }
    let from = base ?? firstLook[window] ?? look
    // (its middle rows: a reader's bars or a title bar fading are no new look)
    let different = middleDifference(from, look, width: THUMB_WIDE) > CHANGED_ABOVE
    let newSinceTold = toldLook[window].map { middleDifference($0, look, width: THUMB_WIDE) > CHANGED_ABOVE } ?? true
    var settleMs: Int?
    if different && newSinceTold {
        let since = differentSince[window] ?? now
        differentSince[window] = since
        if let previous, meanDifference(previous, look) < SETTLED_BELOW {
            toldLook[window] = look
            differentSince[window] = nil
            // (a wheel scroll's new look: the app follows it from the scroll itself; never a page
            // turned by the wheel or a swipe in a window that turns by the page)
            if !scrollExplains(since: since, scrolled: scrolledAt[window], page: pagedObserved.contains(window)) { settleMs = Int((now - since) * 1000) }
        } else if keepsBursting(since: since, now: now) {
            // Changing (a key turned the page, which nothing else hears): looked at often until
            // it is still, so the new page is said within a tenth of a second of settling. Not
            // for ever: a video or typing goes back to OBSERVE_IDLE_MS after CHANGING_BURST_S.
            burstUntil[window] = now + BURST_S
            lookDue[window] = min(lookDue[window] ?? 0, now + Double(POLL_MS) / 1000)
        }
    } else {
        differentSince[window] = nil
    }
    observeLock.unlock()
    if let settleMs { emit(["ev": "changed", "window": Int(window), "settleMs": settleMs]) }
}

/*
  A key pressed in the lesson's app (the founder, 2026-10-28: the tutor over another app should be
  "super responsive"). The watch takes no key event, and a key sends no wheel, so a page turned or
  scrolled by one (Page Down, an arrow, the space bar) was seen only at the window's next idle look,
  up to OBSERVE_IDLE_MS later, with the lesson's ink left on where the words were meanwhile. Each
  tick of the observe loop now asks when a key last went down (lastEventAt, as the talk chord does:
  when, never which key), and one that went down less than KEY_FRESH_S before, with the watched
  window's app in front and that window observed (keyBurstDue), bursts it: looked at every POLL_MS,
  its new look is said as soon as it is still. The first key of a run is also said at once
  ("keyed": the window alone), so the lesson can stop trusting its ink before the new look is in;
  and while keys keep coming (a key held down, Page Down tapped, typing), one again at most every
  KEY_RUN_S (keyRunStarts, from the last one said). The page trusts its ink again 700 ms after the
  last "keyed" it heard (the web's inkUnsure.ts KEY_QUIET_MS), and a page a held key scrolls changes all the while,
  with no "changed" until it is still: said once a run, its ink came back over words gone by.
  Never the keys of a lesson's own turn by a key, posted while it goes on (keyIsOurs).
*/
/// (more than a tick's POLL_MS plus the looks it takes, up to two thumbnails during a burst, so no
/// key falls between two ticks)
let KEY_FRESH_S: TimeInterval = 0.3
/// (a key said this long after the last one, plus a repeat's gap, plus a tick's look at it, comes
/// well inside the page's 700 ms)
let KEY_RUN_S: TimeInterval = 0.3
/// When the last key said ("keyed") went down (seconds of uptime), or nil: none yet.
var lastKeyTaken: TimeInterval?

/// Whether a key that went down `sinceKey` seconds ago, with `frontPid`'s app in front, bursts the
/// watched window, `windowPid`'s: only one just pressed, and only in that window's own app.
func keyBurstDue(sinceKey: TimeInterval, frontPid: pid_t?, windowPid: pid_t?) -> Bool {
    guard let frontPid, let windowPid, frontPid == windowPid else { return false }
    return sinceKey >= 0 && sinceKey < KEY_FRESH_S
}

/// Whether the key that went down at `keyAt` is said ("keyed"), the last one said having gone down
/// at `lastKeyAt` (nil: none yet): the first of a run, and one at most every KEY_RUN_S after it.
func keyRunStarts(keyAt: TimeInterval, lastKeyAt: TimeInterval?) -> Bool {
    guard let lastKeyAt else { return true }
    return keyAt - lastKeyAt > KEY_RUN_S
}

/// Whether a key that went down at `keyAt` is one a lesson's own turn by a key posted in the
/// window: such a turn going on (`turnsOn`), or one that ended at `turnEnded` or after it.
func keyIsOurs(keyAt: TimeInterval, turnsOn: Int, turnEnded: TimeInterval?) -> Bool {
    turnsOn > 0 || keyAt <= (turnEnded ?? -.infinity)
}

/// Whether the key that went down at `keyAt` in `window` is a lesson's own (keyIsOurs) and, when
/// it is not, whether it is said ("keyed"), then the last one said. (A step of its own, as the
/// watch's other locked ones are: an async function takes no NSLock in its body.)
func keyTaken(_ window: CGWindowID, keyAt: TimeInterval) -> (posted: Bool, starts: Bool) {
    observeLock.lock()
    defer { observeLock.unlock() }
    // (the keys a lesson's own turn posts, going on or done: none is the student's)
    let posted = keyIsOurs(keyAt: keyAt, turnsOn: keyTurnsOn[window] ?? 0, turnEnded: keyTurnEnded[window])
    let starts = !posted && keyRunStarts(keyAt: keyAt, lastKeyAt: lastKeyTaken)
    if starts { lastKeyTaken = keyAt }
    return (posted, starts)
}

/// One tick's look at the keys (observeLoop), `windows` being those observed now.
func keyTick(_ windows: [CGWindowID]) async {
    let now = ProcessInfo.processInfo.systemUptime
    let keyAt = lastEventAt(.keyDown, now: now)
    // (most ticks: no key just pressed, and nothing more is asked)
    guard now - keyAt < KEY_FRESH_S else { return }
    let (watchedNow, windowPid, frontPid) = await MainActor.run {
        (watched, identPid, NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }
    guard let window = watchedNow, windows.contains(window),
          keyBurstDue(sinceKey: now - keyAt, frontPid: frontPid, windowPid: windowPid)
    else { return }
    let (posted, starts) = keyTaken(window, keyAt: keyAt)
    guard !posted else { return }
    burst(window)
    if starts { emit(["ev": "keyed", "window": Int(window)]) }
}

/// The companion on (watching the cursor) or off. Main thread.
func setCompanion(_ on: Bool, stop: Set<CGWindowID>, privateApps: Set<String>, readerApps: Set<String>) {
    stopWindows = stop
    if privateApps != privateBundles {
        privateBundles = privateApps
        privatePids.removeAll()
    }
    if readerApps != readerBundles {
        readerBundles = readerApps
        readerPids.removeAll()
    }
    if on {
        installWatch()
        if moveMonitor == nil {
            moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
                guard companionOn, let point = event.cgEvent?.location else { return }
                overAt(point, now: ProcessInfo.processInfo.systemUptime)
            }
        }
        let was = companionOn
        observeLock.lock()
        companionOn = true
        observeLock.unlock()
        // Where the cursor is now, said at once (and again whenever the stop list changes).
        if !was { lastOver = nil }
        if let point = CGEvent(source: nil)?.location { overAt(point, now: ProcessInfo.processInfo.systemUptime, force: true) }
    } else {
        if let monitor = moveMonitor { NSEvent.removeMonitor(monitor) }
        moveMonitor = nil
        observeLock.lock()
        companionOn = false
        observeLock.unlock()
        lastOver = nil
        pressBefore = nil
        observeWindows([])
    }
}

// MARK: - Self test

/// `--selftest`: the arithmetic the companion's taps and grounds rest on, on made-up pictures, the
/// words rule on columns it draws, a line's guessed words, and a page's paper, rules and ink on
/// windows it draws (no screen, no permission). True when all of it holds.
func selfTest() -> Bool {
    var ok = true
    func check(_ what: String, _ holds: Bool) {
        print("\(holds ? "ok  " : "FAIL") \(what)")
        if !holds { ok = false }
    }
    let width = THUMB_WIDE
    let height = 160
    let page = [UInt8](repeating: 250, count: width * height)
    // A window 1000 points tall from y 100: its thumbnail has 0.16 rows a point.
    let frame = CGRect(x: 0, y: 100, width: 1600, height: 1000)
    let tapY: CGFloat = 600
    let band = bandRows(y: tapY, frame: frame, height: height)
    // (600 - 60 - 100) x 0.16 = 70.4, down to 70; (600 + 60 - 100) x 0.16 = 89.6, up to 90
    check("bandRows maps 60 points around a tap at y 600 to rows 70 to 90", band == 70...90)
    check("bandRows clips at the window's top", bandRows(y: 110, frame: frame, height: height)?.lowerBound == 0)
    check("bandRows is nil off the window", bandRows(y: 2000, frame: frame, height: height) == nil)
    guard let rows = band else { return false }
    check("bandDifference of identical pictures is 0", bandDifference(page, page, width: width, rows: rows) == 0)
    // A change far from the tap (a clock at the top of the window): not the tap's doing.
    var elsewhere = page
    for i in 0..<(10 * width) { elsewhere[i] = 0 }
    check("meanDifference sees a change elsewhere", meanDifference(page, elsewhere) > CHANGED_ABOVE)
    check("a change only outside the band is not acted", bandDifference(page, elsewhere, width: width, rows: rows) <= CHANGED_ABOVE)
    // The rows around the tap darkened (a menu opened there, a new page came in).
    var around = page
    for row in 78...88 { for col in 0..<width { around[row * width + col] = 40 } }
    check("a change inside the band is acted", bandDifference(page, around, width: width, rows: rows) > CHANGED_ABOVE)
    check("pictures of different sizes count as wholly different", bandDifference(page, [UInt8](repeating: 250, count: 10), width: width, rows: rows) == 255)
    let white = [UInt8](repeating: 255, count: width * height)
    let black = [UInt8](repeating: 0, count: width * height)
    check("a white page's ground is about 1", abs(ground(white) - 1) < 0.01)
    check("a black page's ground is about 0", ground(black) < 0.01)
    check("a grey page's ground is about 0.5", abs(ground([UInt8](repeating: 128, count: 64)) - 0.5) < 0.01)
    check("a flat picture is blank", isBlank(white))
    check("a page with text is not blank", !isBlank(around))
    // The watch for a new look: settled once two looks in a row agree.
    var watch = SettleWatch(before: page)
    check("a first new look has not settled", !watch.settled(with: around))
    check("a second matching look has settled", watch.settled(with: around))
    // A tab strip acts on the press: its own picture already shows the change, the look from
    // before the press does not (and differs from it only at the tap).
    guard let line = bandRows(y: tapY, frame: frame, height: height, reach: LINE_REACH),
          let cols = patchCols(x: 800, frame: frame, width: width) else { return false }
    check("a tap is acted when the look before the press differs", judgeTap(look: page, picture: around, after: around, line: line, cols: cols, band: rows, vetLook: false).acted)
    check("a tap is not acted when no base differs", !judgeTap(look: page, picture: page, after: page, line: line, cols: cols, band: rows, vetLook: false).acted)
    check("a tap with no base is not acted", !judgeTap(look: nil, picture: nil, after: around, line: line, cols: cols, band: rows, vetLook: false).acted)
    // A wheel scroll explains a new look that began just after it, or while it went on.
    check("a scroll explains a look that began 0.2 s later", scrollExplains(since: 10.2, scrolled: 10.0))
    check("a scroll still going explains it", scrollExplains(since: 10.0, scrolled: 10.4))
    check("a scroll 2 s before does not", !scrollExplains(since: 12.0, scrolled: 10.0))
    check("no scroll explains nothing", !scrollExplains(since: 10.0, scrolled: nil))
    check("a scroll explains nothing in a window that turns by the page", !scrollExplains(since: 10.2, scrolled: 10.0, page: true))
    check("a window changing for 1 s is still looked at often", keepsBursting(since: 10, now: 11))
    check("one changing for 5 s goes back to twice a second", !keepsBursting(since: 10, now: 15))
    // A wheel's step: what "scroll" says, and whether it is the window's scroll for the watch.
    let wheel = wheelStep(deltaY: -3, deltaX: 0, precise: false)
    check("a wheel's 3 lines on down the document are 120 points up, said as 3 lines", wheel.dy == 120 && wheel.dx == 0 && wheel.lines == 3 && wheel.scrolls)
    check("a wheel's line back up is a line the other way", wheelStep(deltaY: 1, deltaX: 0, precise: false).lines == -1)
    let pad = wheelStep(deltaY: -12.5, deltaX: 2, precise: true)
    check("a trackpad's points are its own, with no lines", pad.dy == 12.5 && pad.dx == -2 && pad.lines == 0 && pad.scrolls)
    let pan = wheelStep(deltaY: 0, deltaX: -30, precise: true)
    check("a sideways pan is said, and is no scroll up or down", pan.dx == 30 && pan.dy == 0 && !pan.scrolls)
    // (what installWatch stamps as the window's scroll, from wheelScrolledAt itself: a pan stamps
    // nothing, so the new look it settles into is said; a trackpad's scroll down stamps its time)
    check("so the new look it settles into is said", !scrollExplains(since: 10.2, scrolled: wheelScrolledAt(pan, now: 10.0)))
    check("and a scroll up or down explains the new look it settles into", scrollExplains(since: 10.2, scrolled: wheelScrolledAt(pad, now: 10.0)))
    check("a wheel event that moved nothing is no scroll", !wheelStep(deltaY: 0, deltaX: 0, precise: true).scrolls)
    check("a sideways wheel has no lines", wheelStep(deltaY: 0, deltaX: 2, precise: false).lines == 0)
    // A key just pressed in the watched window's app bursts it; the first of a run is said.
    check("a key 0.1 s ago in the window's app bursts it", keyBurstDue(sinceKey: 0.1, frontPid: 678, windowPid: 678))
    check("so does one 0.25 s ago, seen by a tick that took two looks", keyBurstDue(sinceKey: 0.25, frontPid: 678, windowPid: 678))
    check("not one pressed in another app", !keyBurstDue(sinceKey: 0.1, frontPid: 679, windowPid: 678))
    check("nor one 0.5 s ago", !keyBurstDue(sinceKey: 0.5, frontPid: 678, windowPid: 678))
    check("nor with the window's app not known", !keyBurstDue(sinceKey: 0.1, frontPid: 678, windowPid: nil))
    check("nor with no app in front", !keyBurstDue(sinceKey: 0.1, frontPid: nil, windowPid: 678))
    check("the first key is said", keyRunStarts(keyAt: 10, lastKeyAt: nil))
    // A key held down: the first press, then its repeats every 0.05 s after a 0.4 s wait. Said
    // again at most every KEY_RUN_S while it is held (counted from the last one said, as keyTick
    // keeps lastKeyTaken), so the page's 700 ms quiet never runs out while the page still moves.
    var told = 0
    var last: TimeInterval?
    for keyAt in [10.0, 10.4, 10.45, 10.5, 10.55, 10.6, 10.65, 10.7, 10.75] where keyRunStarts(keyAt: keyAt, lastKeyAt: last) {
        told += 1
        last = keyAt
    }
    check("a key held down is said again while it is held", told == 3)
    check("the same key seen on the next tick is not said again", !keyRunStarts(keyAt: 10.6, lastKeyAt: 10.6))
    check("a key a second after the last is said again", keyRunStarts(keyAt: 11.6, lastKeyAt: 10.6))
    // The keys a lesson's own turn by a key posts are never the student's (keyTick).
    check("a key while a lesson's turn by a key goes on is ours", keyIsOurs(keyAt: 10, turnsOn: 1, turnEnded: nil))
    check("so is one that went down before that turn ended", keyIsOurs(keyAt: 10, turnsOn: 0, turnEnded: 10.5))
    check("not one after it ended", !keyIsOurs(keyAt: 11, turnsOn: 0, turnEnded: 10.5))
    check("nor one with no turn by a key ever", !keyIsOurs(keyAt: 10, turnsOn: 0, turnEnded: nil))
    // And the bookkeeping keyTick reads, on a made up window (nothing is observed in a selftest).
    let turnedByUs: CGWindowID = 9_999_999
    turning(turnedByUs, true, keys: true)
    observeLock.lock()
    let keysOn = keyTurnsOn[turnedByUs] ?? 0
    observeLock.unlock()
    turning(turnedByUs, false, keys: true)
    observeLock.lock()
    let keysOff = keyTurnsOn[turnedByUs] ?? 0
    let keysEnded = keyTurnEnded[turnedByUs]
    observeLock.unlock()
    turning(turnedByUs, true)
    observeLock.lock()
    let scrollOn = keyTurnsOn[turnedByUs] ?? 0
    turnsOn[turnedByUs] = nil
    turnEnded[turnedByUs] = nil
    keyTurnsOn[turnedByUs] = nil
    keyTurnEnded[turnedByUs] = nil
    observeLock.unlock()
    check("a turn by a key counts while it goes on", keysOn == 1)
    check("and once it ends, the keys before its end are ours, none after",
          keysOff == 0 && keysEnded.map { keyIsOurs(keyAt: $0 - 0.01, turnsOn: keysOff, turnEnded: $0) && !keyIsOurs(keyAt: $0 + 0.5, turnsOn: keysOff, turnEnded: $0) } == true)
    check("a turn by a scroll counts no keys", scrollOn == 0)

    // Kindle full screen as in the founder's test: a window at (0, 36), 1512 x 946 points, its
    // thumbnail 256 x 160; a white page in columns 72 to 186 on black, a line of text every 5
    // rows; the reader's bars at rows 0 to 5 and 154 to 159, which fade in and out as the pointer
    // comes and goes (`bars`: how far in). `refit`: with the bars away the page is laid out again
    // a little higher; `shift`: another page.
    let kindleFrame = CGRect(x: 0, y: 36, width: 1512, height: 946)
    func kindle(bars: Double, refit: Bool = false, shift: Int = 0) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: width * height)
        for r in 6...153 { for c in 72...186 { p[r * width + c] = 255 } }
        let first = refit && bars < 0.5 ? 9 : 12
        for (i, row) in stride(from: first, through: 148, by: 5).enumerated() {
            for r in row...(row + 2) {
                for c in 82...176 where (c * 7 + i * 13 + shift * 5) % 9 != 0 {
                    p[r * width + c] = UInt8(165 + ((c + i + shift) % 5) * 10)
                }
            }
        }
        guard bars > 0 else { return p }
        let barRows = Array(0...5) + Array(154...159)
        for r in barRows { for c in 0..<width { p[r * width + c] = UInt8((Double(p[r * width + c]) * (1 - bars) + (r < 6 ? 43 : 30) * bars).rounded()) } }
        for c in 12...240 { p[156 * width + c] = UInt8((Double(p[156 * width + c]) * (1 - bars) + 120 * bars).rounded()) }
        return p
    }
    let hidden = kindle(bars: 0)
    let shown = kindle(bars: 1)
    // Taps on "one of the qualities of the human soul" (mid page) and on the page's header, the
    // line just under the top bar.
    let mid = CGPoint(x: 839, y: 306)
    let header = CGPoint(x: 839, y: 105)
    guard let midLine = bandRows(y: mid.y, frame: kindleFrame, height: height, reach: LINE_REACH),
          let midBand = bandRows(y: mid.y, frame: kindleFrame, height: height),
          let headLine = bandRows(y: header.y, frame: kindleFrame, height: height, reach: LINE_REACH),
          let headBand = bandRows(y: header.y, frame: kindleFrame, height: height),
          let tapCols = patchCols(x: mid.x, frame: kindleFrame, width: width) else { return false }
    func midTap(_ look: [UInt8]?, _ picture: [UInt8]?, _ after: [UInt8]) -> TapJudgement {
        judgeTap(look: look, picture: picture, after: after, line: midLine, cols: tapCols, band: midBand, vetLook: true)
    }
    // A row lit under the tap (a selection, a tab chosen, a list row), and a 70 x 18 point button.
    var lit = hidden
    for r in midLine { for c in 90...170 { lit[r * width + c] = lit[r * width + c] > 200 ? 200 : 120 } }
    var button = hidden
    for r in (midLine.lowerBound + 1)...(midLine.lowerBound + 3) { for c in 120...131 { button[r * width + c] = 215 } }

    check("a reader's bars coming in are not acted on a line mid page",
          !midTap(hidden, hidden, shown).acted && !midTap(hidden, shown, shown).acted)
    let halfGone = kindle(bars: 0.5)
    check("nor on the line just under the top bar, which the old 60 point band reached",
          !judgeTap(look: shown, picture: shown, after: halfGone, line: headLine, cols: tapCols, band: headBand, vetLook: true).acted
            && bandDifference(shown, halfGone, width: width, rows: headBand) > CHANGED_ABOVE)
    let refitted = kindle(bars: 0, refit: true)
    check("a look from before the bars came in is not the window before the press",
          !midTap(refitted, shown, shown).acted && patchDifference(refitted, shown, width: width, rows: midLine, cols: tapCols) > CHANGED_ABOVE)
    let strip = midTap(hidden, lit, lit)
    check("a tab strip that acts on the press is still acted", strip.acted && strip.lookUsed && !strip.wide)
    let row = midTap(hidden, hidden, lit)
    check("a row lit under the tap is acted and not wide", row.acted && !row.wide)
    check("a 70 x 18 point button lit at the tap is acted (the old band missed it)",
          midTap(hidden, hidden, button).acted && bandDifference(hidden, button, width: width, rows: midBand) <= CHANGED_ABOVE)
    let turned = midTap(hidden, hidden, kindle(bars: 0, shift: 4))
    check("a new page everywhere is acted and wide", turned.acted && turned.wide)
    let lookAlone = midTap(hidden, nil, lit)
    check("with no press picture, a look is used as it is", lookAlone.acted && lookAlone.lookUsed && !midTap(hidden, nil, hidden).acted)
    let noBase = midTap(nil, nil, lit)
    check("with no base at all, nothing is acted", !noBase.acted && noBase.line == 0 && noBase.away == 0)
    // A browser's tab or a Finder sidebar item switches the whole window on the press: the press's
    // own picture is the new one already, and only the look from before it shows the change.
    let switched = kindle(bars: 0, shift: 4)
    let tab = judgeTap(look: hidden, picture: switched, after: switched, line: midLine, cols: tapCols, band: midBand, vetLook: false)
    check("a tab switched on the press is acted outside a reader, where the look is not vetted",
          tab.acted && tab.lookUsed && tab.wide && !midTap(hidden, switched, switched).acted)
    check("patchCols clips at the window's edges and is nil off it",
          patchCols(x: 10, frame: kindleFrame, width: width)?.lowerBound == 0
            && patchCols(x: 1505, frame: kindleFrame, width: width)?.upperBound == width - 1
            && patchCols(x: 3000, frame: kindleFrame, width: width) == nil
            && patchCols(x: -400, frame: kindleFrame, width: width) == nil)

    // A window's own edges: its top 12% fading (a reader's bars) is no new look; its middle is.
    var topFaded = page
    for r in 0..<Int(Double(height) * EDGE_SHARE) { for c in 0..<width { topFaded[r * width + c] = 30 } }
    var middleTurned = page
    for r in 60...100 { for c in 0..<width { middleTurned[r * width + c] = 30 } }
    check("middleDifference leaves out a change in the window's top 12%",
          meanDifference(page, topFaded) > CHANGED_ABOVE && middleDifference(page, topFaded, width: width) == 0
            && middleDifference(page, middleTurned, width: width) > CHANGED_ABOVE)
    check("middleAwayDifference leaves out the rows at the tap and the window's edges",
          middleAwayDifference(page, middleTurned, width: width, rows: 60...100) == 0
            && middleAwayDifference(page, topFaded, width: width, rows: 60...100) == 0
            && middleAwayDifference(page, middleTurned, width: width, rows: 0...5) > CHANGED_ABOVE)
    check("isPointingHand(nil) is false", !isPointingHand(nil))
    check("the pointing hand is the hand, and the arrow is not", isPointingHand(NSCursor.pointingHand) && !isPointingHand(NSCursor.arrow))
    let kept = CGSize(width: 800, height: 600)
    check("a kept handle fits its window where it is, a point either way, and when it says no size",
          filterFits(kept, CGRect(x: 300, y: 90, width: 800.5, height: 599))
            && filterFits(.zero, CGRect(x: 0, y: 0, width: 1200, height: 900)))
    check("a window resized since its handle was kept has a new one",
          !filterFits(kept, CGRect(x: 0, y: 0, width: 820, height: 600)) && !filterFits(kept, CGRect(x: 0, y: 0, width: 800, height: 540)))
    textSelfTest(check)
    wordsSelfTest(check)
    geometrySelfTest(check)
    holdSelfTest(check)
    identSelfTest(check)
    chordSelfTest(check)
    return ok
}

/// What a selftest task saw (holdSelfTest): written by it, read once it has signalled.
final class SelfTestAnswer: @unchecked Sendable {
    var ms = -1
}

/*
  A whole window's words wait for a tap being judged (tapsJudged), so the tap's own words are not
  read behind them: not at all with no tap being judged, until the verdict with one, and no longer
  than TAP_HOLD_MS for one whose verdict never comes. (The read's "heldMs" and the tap's "textMs"
  say the same of real taps, in the app's log.)
*/
func holdSelfTest(_ check: (String, Bool) -> Void) {
    let window: CGWindowID = 1
    func waited(judging: Bool, verdictAfter ms: Int?) -> Int {
        if judging {
            judgingLock.lock()
            judgingTaps[window] = 1
            judgingLock.unlock()
        }
        let answer = SelfTestAnswer()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            answer.ms = await tapsJudged(upTo: TAP_HOLD_MS)
            done.signal()
        }
        if let ms {
            usleep(UInt32(ms * 1000))
            _ = verdictGiven(1, on: window)
        }
        done.wait()
        _ = verdictGiven(1, on: window)
        return answer.ms
    }
    check("a read's words do not wait with no tap being judged", waited(judging: false, verdictAfter: nil) < TAP_HOLD_POLL_MS)
    let untilVerdict = waited(judging: true, verdictAfter: 80)
    check("a read's words wait for a tap being judged until its verdict (80 ms)", untilVerdict >= 70 && untilVerdict < TAP_HOLD_MS)
    let never = waited(judging: true, verdictAfter: nil)
    check("and no longer than TAP_HOLD_MS for a verdict that never comes", never >= TAP_HOLD_MS && never < TAP_HOLD_MS + 200)
}

/*
  The words at a tap (judgeText, caretOnly), on columns drawn here with CoreText at 2 pixels a
  point, as a Retina capture is: a window 800 x 1000 points at the screen's top left, rows of
  made-up words (a fixed sequence from a short list, nothing from any book) every 28 points, a
  tap on row 12. Vision reads them as it reads a capture.
*/
func textSelfTest(_ check: (String, Bool) -> Void) {
    let list = """
    river market garden window paper candle silver morning yellow travel kitchen pencil orange thunder blanket harbour
    meadow basket lantern violin pocket marble ladder bridge castle forest island ribbon saddle tunnel valley wagon
    anchor button carpet desert engine feather gravel hammer jacket kettle lemon mirror needle onion parrot rabbit
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    var state: UInt32 = 7
    let rows: [String] = (0..<30).map { _ in
        (0..<8).map { _ -> String in
            state = state &* 1_664_525 &+ 1_013_904_223
            return list[Int(state >> 8) % list.count]
        }.joined(separator: " ")
    }
    // Another page: the same rows, 13 further on (none within reach of where it was).
    let turned = Array(rows[13...] + rows[..<13])
    let window = CGRect(x: 0, y: 0, width: 800, height: 1000)
    let font = CTFontCreateWithName("Georgia" as CFString, 18, nil)
    func baseline(_ i: Int) -> CGFloat { 120 + CGFloat(i) * 28 }
    let tap = CGPoint(x: 400, y: baseline(12) - 6)
    guard let crop = columnRect(x: tap.x, frame: window) else {
        check("columnRect gives the column around a tap", false)
        return
    }
    check("columnRect gives the column 300 points either side of a tap, the window's height",
          crop == CGRect(x: 100, y: 0, width: 600, height: 1000) && columnRect(x: 20, frame: window)?.minX == 0 && columnRect(x: 1200, frame: window) == nil)

    /// The column of a window showing `lines`: scaled about the window's centre, then moved by
    /// `shift` points, a selection `lit` behind them, and `over` drawn on top (screen points).
    func column(_ lines: [String], scale: CGFloat = 1, shift: CGFloat = 0, lit: CGRect? = nil, over: ((CGContext) -> Void)? = nil) -> CGImage? {
        let width = Int(crop.width * 2)
        let height = Int(crop.height * 2)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Screen points from the top left.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 2, y: -2)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        context.saveGState()
        context.translateBy(x: window.midX, y: window.midY + shift)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -window.midX, y: -window.midY)
        if let lit {
            context.setFillColor(CGColor(red: 0.62, green: 0.78, blue: 1, alpha: 1))
            context.fill(lit)
        }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1),
        ]
        for (i, text) in lines.enumerated() {
            context.textPosition = CGPoint(x: 110, y: baseline(i))
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
        }
        context.restoreGState()
        over?(context)
        return context.makeImage()
    }
    func judge(_ before: CGImage?, _ after: CGImage?, at point: CGPoint = tap, awayChanged: Bool) -> TextVerdict? {
        guard let before, let after, let rowsBefore = try? textRows(before, crop: crop, spans: true),
              let rowsAfter = try? textRows(after, crop: crop, spans: false)
        else { return nil }
        return judgeText(before: rowsBefore, after: rowsAfter, crop: crop, tap: point, window: window, awayChanged: awayChanged) { rowY, height in
            caretOnly(before: before, after: after, crop: crop, tap: point, rowY: rowY, lineHeight: height)
        }
    }
    let page = column(rows)
    check("the words at a tap are kept on the same page", judge(page, page, awayChanged: false)?.words == "kept")
    let up = judge(page, column(rows, shift: -23), awayChanged: true)
    check("kept when the page moved 23 points up (a banner closed above), with that shift",
          up?.words == "kept" && abs((up?.shift ?? 0) + 23) <= 3)
    check("kept when the page is laid out again at 96% (a reader's bars came in)",
          judge(page, column(rows, scale: 0.96, shift: 20), awayChanged: true)?.words == "kept")
    let selection = CGRect(x: 300, y: baseline(12) - 16, width: 220, height: 22)
    check("kept when a selection under the tap was cleared (no caret: it was wide)",
          judge(column(rows, lit: selection), page, awayChanged: false)?.words == "kept")
    check("gone when the page turned", judge(page, column(turned), awayChanged: true)?.words == "gone")
    let box = column(rows) { context in
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: tap.x - 110, y: tap.y - 25, width: 220, height: 50))
    }
    check("gone when a box came over the tapped line (a menu)", judge(page, box, awayChanged: false)?.words == "gone")
    check("gone when the page went blank (a link's page loading)", judge(page, column([]), awayChanged: true)?.words == "gone")
    // A tap on no words: told by the rows near it (judgeMargin), or by the pixels with none near.
    check("gone for a tap on the margin under the last row when the page turned",
          judge(page, column(turned), at: CGPoint(x: 400, y: 985), awayChanged: true)?.words == "gone")
    check("none for a tap on a margin with no rows near it",
          judge(column(Array(rows[0..<10])), column(turned), at: CGPoint(x: 400, y: 985), awayChanged: true)?.words == "none")
    let topMargin = CGPoint(x: 400, y: 60)
    check("kept for a tap on the top margin when the page is laid out again at 96% (a reader's bars came in)",
          judge(page, column(rows, scale: 0.96, shift: 20), at: topMargin, awayChanged: true)?.words == "kept")
    check("gone for a tap on the top margin when the page turned", judge(page, column(turned), at: topMargin, awayChanged: true)?.words == "gone")
    let fieldCaret = column(rows) { context in
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: topMargin.x + 1, y: topMargin.y - 10, width: 2, height: 19))
    }
    check("caret for a tap on a margin that put a 2 point stroke there (an empty field)",
          judge(page, fieldCaret, at: topMargin, awayChanged: false)?.words == "caret")
    // A label (a tab, a sidebar item) kept with the rows around it, the content beside it replaced.
    let switched = column(Array(rows[0...17] + turned[18...]))
    check("content when the tapped label stayed and the content away from it changed",
          judge(page, switched, awayChanged: true)?.words == "content" && judge(page, page, awayChanged: true)?.words == "kept")
    let caret = column(rows) { context in
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: tap.x + 1, y: baseline(12) - 15, width: 2, height: 19))
    }
    check("caret when the click put a 2 point stroke a line tall at the tap", judge(page, caret, awayChanged: false)?.words == "caret")
    // A row of two words (a paragraph's last line) is told by a neighbour found moved as far.
    var short = rows
    short[12] = "quiet harbour"
    let shortTap = CGPoint(x: 140, y: baseline(12) - 6)
    var shortTurned = turned
    shortTurned[12] = short[12]
    check("a short row with its neighbour moved alike is kept",
          judge(column(short), column(short, shift: -23), at: shortTap, awayChanged: true)?.words == "kept")
    check("a short row found again without its neighbours is gone",
          judge(column(short), column(shortTurned), at: shortTap, awayChanged: true)?.words == "gone")
}

/*
  A line's words when Vision cannot place one of them (wordBoxes), on a made-up line of made-up
  words: boxes laid out a character at a time across the line, as Vision's are (a little bigger
  than their letters), with one word's withheld or given the whole line, as Vision does.
*/
func wordsSelfTest(_ check: (String, Bool) -> Void) {
    let string = "river market garden window paper"
    let line = CGRect(x: 0.1, y: 0.5, width: 0.6, height: 0.02)
    let each = line.width / CGFloat(string.count)
    let pad: CGFloat = 0.002
    /// Where a word really is: its characters' place along the line (right to left when `leftwards`).
    func laid(_ range: Range<String.Index>, leftwards: Bool = false) -> CGRect {
        let from = CGFloat(string.distance(from: string.startIndex, to: range.lowerBound))
        let to = CGFloat(string.distance(from: string.startIndex, to: range.upperBound))
        let x = leftwards ? line.maxX - to * each : line.minX + from * each
        return CGRect(x: x - pad, y: line.minY + 0.001, width: (to - from) * each + 2 * pad, height: line.height - 0.002)
    }
    func boxes(withheld: Set<String> = [], whole: Set<String> = [], leftwards: Bool = false) -> [ReadWord]? {
        wordBoxes(string, lineBox: line) { range in
            let word = String(string[range])
            if withheld.contains(word) { return nil }
            return whole.contains(word) ? line : laid(range, leftwards: leftwards)
        }
    }
    /// Every word kept, in order, each box real, clear of the next and (a guessed one) inside the
    /// line; only `guessed` guessed, and the rest where Vision put them.
    func tidy(_ found: [ReadWord]?, guessed: Set<String>, leftwards: Bool = false) -> Bool {
        guard let found, found.map(\.text) == string.split(separator: " ").map(String.init) else { return false }
        var index = string.startIndex
        for (i, word) in found.enumerated() {
            guard let start = string[index...].range(of: word.text) else { return false }
            index = start.upperBound
            guard word.box.width > 0, word.box.height > 0, word.guessed == guessed.contains(word.text) else { return false }
            if word.guessed {
                guard word.box.minX >= line.minX, word.box.maxX <= line.maxX else { return false }
            } else if word.box != laid(start, leftwards: leftwards) {
                return false
            }
            if i > 0 {
                let previous = found[i - 1].box
                guard leftwards ? word.box.maxX <= previous.minX : word.box.minX >= previous.maxX else { return false }
            }
        }
        return true
    }
    let one = boxes(withheld: ["garden"])
    check("a line with one word Vision cannot place keeps all its words, that one guessed between its neighbours",
          tidy(one, guessed: ["garden"]))
    if let garden = one?.first(where: { $0.text == "garden" }), let range = string.range(of: "garden") {
        check("and guessed where its characters are", abs(garden.box.midX - laid(range).midX) < each / 2)
    }
    check("a word Vision gives the whole line's box is guessed too", tidy(boxes(whole: ["window"]), guessed: ["window"]))
    check("the first and the last word are guessed from the line's own ends",
          tidy(boxes(withheld: ["river", "paper"]), guessed: ["river", "paper"]))
    check("two words side by side are guessed in order", tidy(boxes(withheld: ["market", "garden"]), guessed: ["market", "garden"]))
    check("on a line laid right to left, a withheld word is guessed between its neighbours",
          tidy(boxes(withheld: ["garden"], leftwards: true), guessed: ["garden"], leftwards: true))
    check("a line Vision places none of goes without words", boxes(withheld: Set(string.split(separator: " ").map(String.init))) == nil)
    let crowded = wordBoxes(string, lineBox: line) { range in
        let word = String(string[range])
        if word == "garden" { return nil }
        // (market's box runs on over window's)
        return word == "market" ? laid(range).union(laid(string.range(of: "window")!)) : laid(range)
    }
    check("a line whose placed words leave a withheld one no room goes without words", crowded == nil)
    let alone = wordBoxes("river", lineBox: line) { _ in line }
    check("a one-word line keeps a box the width of the line", alone?.count == 1 && alone?.first?.guessed == false)
    // A Hebrew line of three words, only its middle one placed: no run of boxes to tell its way by.
    let hebrew = "שלום עולם יפה"
    let letter = line.width / CGFloat(hebrew.count)
    let middle = CGRect(x: line.maxX - 9 * letter, y: line.minY, width: 4 * letter, height: line.height)
    let rtl = wordBoxes(hebrew, lineBox: line) { range in String(hebrew[range]) == "עולם" ? middle : nil }
    check("on a right to left line with one word placed, its first word is guessed on its right and its last on its left",
          rtl.map { $0.count == 3 && $0[0].guessed && $0[2].guessed && $0[0].box.minX >= middle.maxX && $0[0].box.maxX <= line.maxX
              && $0[2].box.maxX <= middle.minX && $0[2].box.minX >= line.minX } ?? false)
}

/*
  The page's paper, rules and ink (pageGeometry), on windows drawn here at 2 pixels a point, as a
  Retina capture is, and read by Vision's accurate pass, as a lesson's read is: a window 800 x 1000
  points at (100, 50) on the screen; a page with two paragraphs of made-up words on it, a 200 point
  rule under the first, a filled box between them; and under it the top of the next page (no
  words), as a viewer that scrolls shows it. Then the same words on a page that fills the window,
  its corners rounded off as a window's capture has them, and on a page under a browser's white
  bars; and the first page again at 1 and at 1.25 pixels a point.
*/
func geometrySelfTest(_ check: (String, Bool) -> Void) {
    let window = CGRect(x: 100, y: 50, width: 800, height: 1000)
    let list = "river market garden window paper candle silver morning yellow travel kitchen pencil orange thunder"
        .split(separator: " ").map(String.init)
    let rows = (0..<12).map { i in (0..<6).map { list[(i * 5 + $0 * 3) % list.count] }.joined(separator: " ") }
    let baselines: [CGFloat] = (0..<12).map { i -> CGFloat in (i < 6 ? 110 : 364) + CGFloat(i) * 26 }
    let font = CTFontCreateWithName("Georgia" as CFString, 16, nil)
    // In points from the window's top left.
    let page = CGRect(x: 150, y: 40, width: 500, height: 900)
    let nextPage = CGRect(x: 150, y: 960, width: 500, height: 40)
    let rule = CGRect(x: 200, y: 262, width: 200, height: 1)
    let box = CGRect(x: 220, y: 320, width: 160, height: 120)
    func onScreen(_ r: CGRect) -> CGRect { r.offsetBy(dx: window.minX, dy: window.minY) }

    /// The window: a viewer of grey `viewer`, `pages` of grey `paper` on it, and the words, the rule
    /// and the box in grey `ink`. `bar`: a bar of the viewer's as light as the paper, with a title
    /// on it (a browser's white tab strip and toolbar); `corner`: the window's corners rounded off,
    /// nothing drawn past them, as a window's capture has them; `scale`: pixels a point (2, a
    /// Retina capture; 1, a display that is not; or what a capture over MAX_PIXELS_WIDE is cut to).
    func picture(viewer: CGFloat, paper: CGFloat, ink: CGFloat, pages: [CGRect], bar: CGRect? = nil, corner: CGFloat = 0, scale: CGFloat = 2) -> CGImage? {
        let width = Int(window.width * scale)
        let height = Int(window.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if corner > 0 {
            let whole = CGRect(x: 0, y: 0, width: width, height: height)
            context.addPath(CGPath(roundedRect: whole, cornerWidth: corner * scale, cornerHeight: corner * scale, transform: nil))
            context.clip()
        }
        context.setFillColor(CGColor(gray: viewer, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.setFillColor(CGColor(gray: paper, alpha: 1))
        for p in pages { context.fill(p) }
        if let bar { context.fill(bar) }
        context.setFillColor(CGColor(gray: ink, alpha: 1))
        context.fill(rule)
        context.fill(box)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: ink, alpha: 1),
        ]
        var texts = Array(zip(rows, baselines).map { (text: $0.0, at: CGPoint(x: 200, y: $0.1)) })
        if let bar { texts.append((text: "Reading notes", at: CGPoint(x: bar.minX + 40, y: bar.minY + 26))) }
        for (text, at) in texts {
            context.textPosition = at
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
        }
        return context.makeImage()
    }
    func geometry(_ image: CGImage?) -> (geometry: PageGeometry?, lines: [ReadLine]) {
        guard let image, let observations = try? recognize(image, .accurate) else { return (nil, []) }
        let lines = readLines(observations, frame: window)
        return (pageGeometry(image, frame: window, lines: lines), lines)
    }
    func near(_ a: CGRect?, _ b: CGRect, within: CGFloat = 2) -> Bool {
        guard let a else { return false }
        return abs(a.minX - b.minX) <= within && abs(a.maxX - b.maxX) <= within && abs(a.minY - b.minY) <= within && abs(a.maxY - b.maxY) <= within
    }
    /// The cells of a grid that are drawn on, in screen points.
    func inkedCells(_ ink: InkGrid) -> [CGRect] {
        var cells: [CGRect] = []
        for r in 0..<ink.rows {
            for c in 0..<ink.cols where ink.inked(col: c, row: r) {
                cells.append(CGRect(x: ink.x + Double(c * INK_CELL), y: ink.y + Double(r * INK_CELL), width: Double(INK_CELL), height: Double(INK_CELL)))
            }
        }
        return cells
    }
    /// The rule, the box and the words as a page shows them, checked: `what` names the page.
    func checkPage(_ what: String, _ found: (geometry: PageGeometry?, lines: [ReadLine])) {
        let textBoxes = found.lines.flatMap { $0.words?.map(\.box) ?? [$0.box] }
        check("\(what): Vision reads its 12 rows", found.lines.filter { hasLetterOrDigit($0.text) }.count == 12)
        guard let geometry = found.geometry else {
            check("\(what): its geometry is told", false)
            return
        }
        check("\(what): the page's rectangle is told within 2 points, not the next page's", near(geometry.paper, onScreen(page)))
        check("\(what): the 200 point rule under a line of words is found, and the words and the box are not",
              geometry.rules.count == 1 && near(geometry.rules.first, onScreen(rule)))
        let cells = inkedCells(geometry.ink)
        let boxOn = onScreen(box)
        let ruleOn = onScreen(rule).insetBy(dx: -1, dy: -1)
        var inside = 0
        var insideInked = 0
        for r in 0..<geometry.ink.rows {
            for c in 0..<geometry.ink.cols {
                let cell = CGRect(x: geometry.ink.x + Double(c * INK_CELL), y: geometry.ink.y + Double(r * INK_CELL), width: Double(INK_CELL), height: Double(INK_CELL))
                guard boxOn.contains(cell) else { continue }
                inside += 1
                if geometry.ink.inked(col: c, row: r) { insideInked += 1 }
            }
        }
        check("\(what): the filled box sets every cell inside it", inside > 0 && insideInked == inside)
        check("\(what): nothing else is inked, and the cells over the words stay clear",
              cells.allSatisfy { $0.intersects(boxOn) || $0.intersects(ruleOn) }
                && !cells.contains { cell in !cell.intersects(boxOn) && !cell.intersects(ruleOn) && textBoxes.contains { $0.intersects(cell) } })
        check("\(what): the grid lies over the paper told",
              geometry.paper.map {
                  geometry.ink.x == Double($0.minX) && geometry.ink.y == Double($0.minY)
                    && geometry.ink.cols == Int(($0.width / CGFloat(INK_CELL)).rounded(.up)) && geometry.ink.rows == Int(($0.height / CGFloat(INK_CELL)).rounded(.up))
              } ?? false)
    }

    let white = geometry(picture(viewer: 0.6, paper: 1, ink: 0.1, pages: [page, nextPage]))
    checkPage("a white page on a grey viewer", white)
    if let geometry = white.geometry, let ink = geometryFields(geometry)["ink"] as? [String: Any], let sent = ink["bits"] as? String,
       let bytes = Data(base64Encoded: sent).map(Array.init) {
        var same = ink["cell"] as? Int == 8 && ink["cols"] as? Int == geometry.ink.cols && ink["rows"] as? Int == geometry.ink.rows
        for i in 0..<(geometry.ink.cols * geometry.ink.rows) {
            if (bytes[i >> 3] & UInt8(1 << (i & 7)) != 0) != geometry.ink.inked(col: i % geometry.ink.cols, row: i / geometry.ink.cols) { same = false }
        }
        check("the grid goes as base64, cell r * cols + c at bit (i & 7) of byte i >> 3", same)
    } else {
        check("the grid goes as base64, cell r * cols + c at bit (i & 7) of byte i >> 3", false)
    }
    // A night theme: a dark page, light words and marks, on Chrome's dark grey.
    checkPage("a dark page", geometry(picture(viewer: 0.33, paper: 0.12, ink: 0.9, pages: [page, nextPage])))
    // The same page captured at a point a pixel (a display that is not Retina), and at 1.25 pixels
    // a point (a capture cut down under MAX_PIXELS_WIDE): pageGeometry draws either down to points.
    checkPage("a white page captured at 1x", geometry(picture(viewer: 0.6, paper: 1, ink: 0.1, pages: [page, nextPage], scale: 1)))
    checkPage("a white page captured at 1.25x", geometry(picture(viewer: 0.6, paper: 1, ink: 0.1, pages: [page, nextPage], scale: 1.25)))
    // Kindle's way: the page fills the window, its corners rounded off.
    let filling = geometry(picture(viewer: 1, paper: 1, ink: 0.1, pages: [], corner: 10))
    check("a page that fills the window has no paper told, and its grid covers the window",
          filling.geometry.map {
              $0.paper == nil && $0.ink.x == Double(window.minX) && $0.ink.y == Double(window.minY)
                && $0.ink.cols == Int(window.width) / INK_CELL && $0.ink.rows == Int(window.height) / INK_CELL
                && $0.rules.count == 1 && near($0.rules.first, onScreen(rule))
          } ?? false)
    check("and the window's rounded corners, where nothing is drawn, are not inked",
          filling.geometry.map { inkedCells($0.ink).allSatisfy { $0.intersects(onScreen(box)) || $0.intersects(onScreen(rule).insetBy(dx: -1, dy: -1)) } } ?? false)
    // A browser's white tab strip and toolbar, a title on it, over its dark PDF viewer: over the
    // rows from the title to the page's last line it is a tenth of every column, the dark viewer's
    // beside the page too, but it is no part of the page.
    let below = CGRect(x: 150, y: 92, width: 500, height: 888)
    let barred = geometry(picture(viewer: 0.33, paper: 1, ink: 0.1, pages: [below], bar: CGRect(x: 0, y: 0, width: 800, height: 80)))
    check("under a browser's white bars, the page's rectangle is told within 2 points, not the window's width",
          near(barred.geometry?.paper, onScreen(below)))
}

/*
  The talk chord's state machine (chordStep) on made up presses, polled every CHORD_POLL_MS as the
  watch polls (no keyboard, no timer: the polls' times are made up too): which events each says,
  and that it ends ready for the next chord.
*/
func chordSelfTest(_ check: (String, Bool) -> Void) {
    /// A key held from `from` to `to` (seconds of uptime): "ctrl", "opt" or "shift".
    struct Held {
        let key: String
        let from: Double
        let to: Double
    }
    /// The polls from 9.9 s (plus `offset`) to `until` as they would see `held`, the keys pressed or
    /// let go at `keys`, a mouse button pressed at `mice` and the wheel turned at `wheels`, with the
    /// chord off for `blocked`, played through chordStep from `phase`: the events said (the log's
    /// "spoiled" too), and the phase it ends in.
    func play(_ held: [Held], keys: [Double] = [], mice: [Double] = [], wheels: [Double] = [], blocked: String? = nil,
              until: Double, from phase: ChordPhase = .idle, offset: Double = 0) -> (events: [ChordEvent], phase: ChordPhase) {
        var phase = phase
        var events: [ChordEvent] = []
        let edges = held.flatMap { [$0.from, $0.to] }
        var now = 9.9 + offset
        while now < until {
            let at = now
            let down = { (key: String) in held.contains { $0.key == key && $0.from <= at && at < $0.to } }
            let last = { (times: [Double]) in times.filter { $0 <= at }.max() ?? 0 }
            let sample = ChordSample(now: at, pair: down("ctrl") && down("opt"), anyPair: down("ctrl") || down("opt"),
                                     others: down("shift"), blocked: blocked, flagsAt: last(edges), keyAt: last(keys),
                                     buttonAt: last(mice), wheelAt: last(wheels))
            let (next, event) = chordStep(phase, sample)
            phase = next
            if let event { events.append(event) }
            now += Double(CHORD_POLL_MS) / 1000
        }
        return (events, phase)
    }
    /// What the app hears ("spoiled" is the log's alone), and what the log says was spoiled.
    func said(_ events: [ChordEvent]) -> String {
        events.filter { $0.kind != "spoiled" }.map { event in event.why.map { "\(event.kind) \($0)" } ?? event.kind }.joined(separator: ", ")
    }
    func spoiled(_ events: [ChordEvent]) -> String {
        events.filter { $0.kind == "spoiled" }.compactMap(\.why).joined(separator: ", ")
    }
    /// The same presses at every phase of the polls against them (CHORD_POLL_MS of 1 ms steps).
    func everyPhase(_ test: (Double) -> Bool) -> Bool {
        (0..<CHORD_POLL_MS).allSatisfy { test(Double($0) / 1000) }
    }
    func ms(_ events: [ChordEvent], _ kind: String) -> Int { events.first { $0.kind == kind }?.ms ?? -1 }

    // Control down at 10.00 s, Option at 10.05, Option up at 10.23 and Control at 10.24.
    let tap = play([Held(key: "ctrl", from: 10.0, to: 10.24), Held(key: "opt", from: 10.05, to: 10.23)], until: 10.6)
    check("Control and Option tapped together are a tap of about 180 ms, with no down", said(tap.events) == "tap"
            && abs(ms(tap.events, "tap") - 185) <= 30 && tap.phase == .idle)
    let slowTap = play([Held(key: "ctrl", from: 10.0, to: 10.6), Held(key: "opt", from: 10.05, to: 10.6)], until: 11)
    check("held 550 ms they are a down, then a tap", said(slowTap.events) == "down, tap"
            && ms(slowTap.events, "down") >= 300 && ms(slowTap.events, "down") < 340 && slowTap.phase == .idle)
    let hold = play([Held(key: "ctrl", from: 10.0, to: 16.0), Held(key: "opt", from: 10.05, to: 16.0)], until: 16.5)
    check("held 6 s they are a down, a hold at 5 s (once), and an up", said(hold.events) == "down, hold, up"
            && ms(hold.events, "hold") >= 5000 && ms(hold.events, "hold") < 5040 && abs(ms(hold.events, "up") - 5950) <= 40
            && hold.phase == .idle)
    // ⌃⌥M (the app's own shortcut): M goes down and up within the chord.
    let shortcut = play([Held(key: "ctrl", from: 10.0, to: 10.4), Held(key: "opt", from: 10.05, to: 10.4)], keys: [10.15, 10.22], until: 10.8)
    let lateKey = play([Held(key: "ctrl", from: 10.0, to: 10.9), Held(key: "opt", from: 10.05, to: 10.9)], keys: [10.6, 10.7], until: 11.2)
    check("Control+Option+M is no chord: nothing before its down (the log says why), a cancel (key) after it",
          said(shortcut.events) == "" && spoiled(shortcut.events) == "key" && shortcut.phase == .idle
            && said(lateKey.events) == "down, cancel key" && spoiled(lateKey.events) == "" && lateKey.phase == .idle)
    // A quick ⌃⌥Space (the lesson's pause): Control at 10.00, Option at 10.02, Space down at 10.09,
    // both let go at 10.10 and Space at 10.11, after them. Its let go is the last key time a poll
    // can see, later than the release: still no tap, whichever moment the polls fall on.
    check("a quick Control+Option+Space, Space let go after them, is no tap at any phase of the polls",
          everyPhase { offset in
              let roll = play([Held(key: "ctrl", from: 10.0, to: 10.1), Held(key: "opt", from: 10.02, to: 10.1)], keys: [10.09, 10.11],
                              until: 10.6, offset: offset)
              return said(roll.events) == "" && roll.phase == .idle
          })
    let keyBefore = play([Held(key: "ctrl", from: 10.0, to: 10.24), Held(key: "opt", from: 10.05, to: 10.23)], keys: [9.95, 10.02], until: 10.6)
    check("a key let go before the chord began does not spoil it", said(keyBefore.events) == "tap")
    let shift = play([Held(key: "ctrl", from: 10.0, to: 10.3), Held(key: "opt", from: 10.05, to: 10.3), Held(key: "shift", from: 10.1, to: 10.25)], until: 10.7)
    let shiftFirst = play([Held(key: "shift", from: 9.95, to: 10.4), Held(key: "ctrl", from: 10.0, to: 10.2), Held(key: "opt", from: 10.05, to: 10.2)], until: 10.7)
    let shiftLate = play([Held(key: "ctrl", from: 10.0, to: 11.0), Held(key: "opt", from: 10.05, to: 11.0), Held(key: "shift", from: 10.5, to: 10.6)], until: 11.3)
    check("Shift with them spoils the chord: before it, during it, after its down",
          said(shift.events) == "" && said(shiftFirst.events) == "" && said(shiftLate.events) == "down, cancel modifier"
            && shift.phase == .idle && shiftFirst.phase == .idle && shiftLate.phase == .idle)
    let click = play([Held(key: "ctrl", from: 10.0, to: 10.3), Held(key: "opt", from: 10.05, to: 10.3)], mice: [10.15], until: 10.7)
    let clickBefore = play([Held(key: "ctrl", from: 9.95, to: 10.3), Held(key: "opt", from: 10.05, to: 10.3)], mice: [10.0], until: 10.7)
    check("a click within the chord spoils it; one before its second key does not",
          said(click.events) == "" && spoiled(click.events) == "mouse" && click.phase == .idle && said(clickBefore.events) == "tap")
    // A trackpad flicked a moment before: the glide's wheel turns every 16 ms until 11.0 s, all
    // through a tap of 200 ms from 10.0 s (and through a hold).
    let glide = Array(stride(from: 9.0, to: 11.0, by: 0.016))
    check("a tap during a scroll's glide is a tap, at any phase of the polls",
          everyPhase { offset in
              said(play([Held(key: "ctrl", from: 10.0, to: 10.2), Held(key: "opt", from: 10.02, to: 10.2)], wheels: glide,
                        until: 10.6, offset: offset).events) == "tap"
          }
            && said(play([Held(key: "ctrl", from: 10.0, to: 16.0), Held(key: "opt", from: 10.02, to: 16.0)], wheels: glide, until: 16.5).events)
                == "down, hold, up")
    let wheelIn = play([Held(key: "ctrl", from: 10.0, to: 10.3), Held(key: "opt", from: 10.05, to: 10.3)], wheels: [10.2, 10.216, 10.232], until: 10.7)
    let wheelLate = play([Held(key: "ctrl", from: 10.0, to: 11.0), Held(key: "opt", from: 10.05, to: 11.0)], wheels: [10.6, 10.616], until: 11.3)
    let wheelBefore = play([Held(key: "ctrl", from: 10.0, to: 10.3), Held(key: "opt", from: 10.05, to: 10.3)], wheels: [9.5, 9.516], until: 10.7)
    check("a wheel begun inside the chord (a Control scroll) spoils it; one stopped well before does not",
          said(wheelIn.events) == "" && spoiled(wheelIn.events) == "wheel" && wheelIn.phase == .idle
            && said(wheelLate.events) == "down, cancel wheel" && said(wheelBefore.events) == "tap")
    let long = play([Held(key: "ctrl", from: 10.0, to: 11.5), Held(key: "opt", from: 10.05, to: 11.5)], until: 12)
    check("let go between 700 ms and 5 s it is a down, then a cancel (long)", said(long.events) == "down, cancel long"
            && abs(ms(long.events, "cancel") - 1450) <= 40 && long.phase == .idle)
    // A tap with Control kept down, then Option pressed again (held 2 s) while Control still is.
    let again = play([Held(key: "ctrl", from: 10.0, to: 13.0), Held(key: "opt", from: 10.05, to: 10.25), Held(key: "opt", from: 10.6, to: 12.6)], until: 13.4)
    check("one key still down after a tap cannot start another chord: both up first", said(again.events) == "tap" && again.phase == .idle)
    let afterBoth = play([Held(key: "ctrl", from: 10.0, to: 10.24), Held(key: "opt", from: 10.05, to: 10.23),
                          Held(key: "ctrl", from: 10.5, to: 10.74), Held(key: "opt", from: 10.55, to: 10.73)], until: 11.1)
    check("with both up in between, two taps are two taps", said(afterBoth.events) == "tap, tap")
    let voiceOver = play([Held(key: "ctrl", from: 10.0, to: 10.24), Held(key: "opt", from: 10.05, to: 10.23)], blocked: "voiceover", until: 10.6)
    let voiceOverHold = play([Held(key: "ctrl", from: 10.0, to: 16.0), Held(key: "opt", from: 10.05, to: 16.0)], blocked: "voiceover", until: 16.5)
    check("with VoiceOver on (Control and Option are its keys) there is no chord: no tap, no hold",
          said(voiceOver.events) == "" && said(voiceOverHold.events) == "" && voiceOverHold.phase == .idle)
    let secure = play([Held(key: "ctrl", from: 10.0, to: 10.24), Held(key: "opt", from: 10.05, to: 10.23)], blocked: "secure", until: 10.6)
    check("nor with secure input on", said(secure.events) == "")
    let alreadyHeld = play([Held(key: "ctrl", from: 9.0, to: 10.3), Held(key: "opt", from: 9.0, to: 10.3)], until: 10.7, from: .waitRelease)
    check("keys already down when the watch starts are no chord", said(alreadyHeld.events) == "" && alreadyHeld.phase == .idle)
    check("chordKeyNames reads the sides from the device bits",
          chordKeyNames(CGEventFlags(rawValue: CHORD_PAIR.rawValue | 0x1 | 0x20)) == "lctrl+lopt"
            && chordKeyNames(CGEventFlags(rawValue: CHORD_PAIR.rawValue | 0x2000 | 0x40)) == "rctrl+ropt"
            && chordKeyNames(CHORD_PAIR) == "ctrl+opt")
}

// MARK: - The talk chord

/*
  The talk chord: Control and Option pressed on their own, from any app. A tap of them asks the
  tutor one question, and holding them for 5 s turns talk mode on (src/main/screenTeach.ts passes
  the events to the lesson's page, which decides what each means). Electron's global shortcuts
  need a key that is not a modifier, so the app cannot register this; a key monitor would need
  Accessibility, and an event tap Input Monitoring (with macOS's prompt), neither of which the
  student need have given this helper. So it is polled, with no permission at all: every
  CHORD_POLL_MS while the app wants it ("chord" on), which modifier keys are held now
  (CGEventSource.flagsState) and, while that could matter, how long ago the last modifier change,
  key and mouse press were (secondsSinceLastEventType: when, never which key). Nothing is taken:
  every key goes where it was going.

  A chord begins when both are down with no Shift, Command or Fn, at the moment the second went
  down (the last modifier change, but no further back than CHORD_START_BACK_S before the poll that
  saw it). Anything else within it spoils it, and it is then no chord: another modifier joining, a
  key going down or up (Control+Option+M, Space or the arrows, the app's own shortcuts; a window
  manager's), a mouse button (a Control click) or the wheel (Control scroll zooms the screen).
  "Within" runs to the poll that saw the keys let go, not to the moment they were: only the last
  key event's time is known, so a key let go just after them (Space, in a quick ⌃⌥Space) would
  hide the key that went down inside, and the shortcut would come out a tap. That costs only a tap
  followed within a poll by typing. The wheel is the exception: a trackpad's glide (or a Magic
  Mouse's resting finger) keeps saying the wheel turned for a second or more after the fingers
  left, so a chord begun while it still was (CHORD_GLIDE_S) is not spoiled by the wheel at all; one
  begun with the wheel still, then turned within it (a Control scroll), is.
  Spoiled, it says "cancel" if it had said "down", then waits for both keys to be up (spoiled
  before its "down", it says nothing to the app, and the log says why: a miss leaves a trace).
  Unspoiled it
  says "down" at CHORD_DOWN_S held (the page shows the hold's ring), "hold" once at CHORD_HOLD_S,
  and at the release "up" after a hold, "tap" when it was held CHORD_TAP_S or less, else "cancel"
  ("long": too long for a tap, let go before the hold). A key still down after a release cannot
  begin another: both must be up first. So must keys already down when the watch starts (the
  lesson's own ⌃⌥Space, still held as its talk key comes on).

  Off while VoiceOver is on (Control and Option are its own keys: every VoiceOver command would
  be a chord) and while secure input is on (a password field has the keys, and the keys pressed
  within the chord could not be told); the log says so once per change, and the app hears it
  ("state": so the page names ⌃⌥M, not a chord that does nothing). ⌃⌥M, the app's own shortcut,
  is the way in then. A key the helper posts itself (a lesson's turn) is a key like any other: one
  within a chord spoils it, which costs nothing.

  The helper is an app with no window, which macOS would put in App Nap: its timers then fire
  late and together, far apart, and a quick tap falls between two polls. So while the chord is
  watched it holds an activity that keeps it out of App Nap (user initiated, letting the Mac sleep
  when idle; not "latency critical", which is for audio and would cost more for hours on end) and
  the timer is a strict one; the log says once if two polls ever come more than CHORD_GAP_S apart.

  The steps are chordStep, a pure function of what one poll saw (--selftest plays made up presses
  through it). Whether a helper with no Input Monitoring sees the modifier keys at all is not
  documented (a menu bar app reads them the same way, and the timings were seen to be readable):
  the log says once if they look hidden (three modifier changes, none of them seen held; the app
  hears it as a "state", and again should one be seen held after all), and once when the first
  chord is seen. `--chordtest` shows the founder what the polls see.
*/

/// The keys are looked at this often while the chord is watched (the timer may fire up to
/// CHORD_LEEWAY_MS late: fewer wakeups).
let CHORD_POLL_MS = 33
let CHORD_LEEWAY_MS = 8
/// Held this long: "down"; let go within CHORD_TAP_S: a tap; held CHORD_HOLD_S: "hold" (seconds).
let CHORD_DOWN_S = 0.3
let CHORD_TAP_S = 0.7
let CHORD_HOLD_S = 5.0
/// A chord's beginning is the last modifier change, at most this long before the poll that saw it.
let CHORD_START_BACK_S = 0.1
/// The wheel turned this soon before a chord began (or since): a glide under way, which the wheel
/// does not spoil (seconds).
let CHORD_GLIDE_S = 0.15
/// Two polls further apart than this (seconds) mean the timer is held back: said once in the log.
let CHORD_GAP_S = 0.15
/// A chord spoiled before its "down" is said in the log at most this often (seconds).
let CHORD_SPOILED_EVERY_S = 1.0
let CHORD_PAIR: CGEventFlags = [.maskControl, .maskAlternate]
/// The modifiers that make it another shortcut. Caps Lock, the keypad's and Help's flags are none.
let CHORD_OTHERS: CGEventFlags = [.maskShift, .maskCommand, .maskSecondaryFn]
/// Every modifier a key holds (Caps Lock too): any of them seen set shows the flags are visible.
let CHORD_ANY_MODIFIER: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn, .maskAlphaShift]
/// How long `--chordtest` prints (seconds), and how often (ms).
let CHORD_TEST_S = 20.0
let CHORD_TEST_EVERY_MS = 50

enum ChordPhase: Equatable {
    case idle
    /// Both keys down since `start` (seconds of uptime); whether "down" and "hold" were said; and
    /// whether it began in a glide of the wheel (CHORD_GLIDE_S), which then never spoils it.
    case held(start: Double, told: Bool, holdTold: Bool, glide: Bool)
    /// Spoiled, over, or held from before: nothing until both keys and any other modifier are up.
    case waitRelease
}

/// What one poll saw. Times in seconds of uptime (ProcessInfo.systemUptime), as `now`.
struct ChordSample {
    let now: Double
    /// Control and Option both held; either of them; Shift, Command or Fn.
    let pair: Bool
    let anyPair: Bool
    let others: Bool
    /// Why the chord is off now ("voiceover", "secure"), or nil.
    let blocked: String?
    /// The last modifier change; the last key down or up; the last mouse button pressed (left,
    /// right or other); the last turn of the wheel (a glide's too).
    let flagsAt: Double
    let keyAt: Double
    let buttonAt: Double
    let wheelAt: Double
}

/// What the chord says ("chord"): its kind, how long it had been held, and why a cancel. And one
/// the app never hears: "spoiled", a chord spoiled before its "down" (why), for the log alone.
struct ChordEvent: Equatable {
    let kind: String
    let ms: Int
    let why: String?
}

/// One poll of the chord: the phase it moves to, and what it says, if anything.
func chordStep(_ phase: ChordPhase, _ s: ChordSample) -> (ChordPhase, ChordEvent?) {
    switch phase {
    case .waitRelease:
        return (s.anyPair || s.others ? .waitRelease : .idle, nil)
    case .idle:
        guard s.pair else { return (.idle, nil) }
        // (another modifier with them, or the chord off: not this time, and not until all are up)
        if s.others || s.blocked != nil { return (.waitRelease, nil) }
        let start = min(s.now, max(s.flagsAt, s.now - CHORD_START_BACK_S))
        // (the wheel turning as it began, or since: a glide still going, not the student's scroll)
        let glide = s.wheelAt > start - CHORD_GLIDE_S
        // (anything already within it, since the second key went down, is looked at at once)
        return chordStep(.held(start: start, told: false, holdTold: false, glide: glide), s)
    case let .held(start, told, holdTold, glide):
        // Held until now, or let go at the last modifier change.
        let end = s.pair ? s.now : min(s.now, max(start, s.flagsAt))
        let held = end - start
        let ms = Int((held * 1000).rounded())
        // (up to this poll, not to the release: a key let go after the keys must not hide one
        // pressed within them, as the latest key time alone would)
        let within = { (at: Double) in at > start && at <= s.now }
        let spoiled: String? = s.blocked ?? (s.others ? "modifier" : within(s.keyAt) ? "key" : within(s.buttonAt) ? "mouse"
            : !glide && within(s.wheelAt) ? "wheel" : nil)
        if let why = spoiled {
            return (.waitRelease, ChordEvent(kind: told ? "cancel" : "spoiled", ms: ms, why: why))
        }
        if !s.pair {
            let next: ChordPhase = s.anyPair ? .waitRelease : .idle
            if holdTold { return (next, ChordEvent(kind: "up", ms: ms, why: nil)) }
            if held <= CHORD_TAP_S { return (next, ChordEvent(kind: "tap", ms: ms, why: nil)) }
            return (next, told ? ChordEvent(kind: "cancel", ms: ms, why: "long") : nil)
        }
        if !told && held >= CHORD_DOWN_S {
            return (.held(start: start, told: true, holdTold: false, glide: glide), ChordEvent(kind: "down", ms: ms, why: nil))
        }
        if told && !holdTold && held >= CHORD_HOLD_S {
            return (.held(start: start, told: true, holdTold: true, glide: glide), ChordEvent(kind: "hold", ms: ms, why: nil))
        }
        return (phase, nil)
    }
}

var chordTimer: DispatchSourceTimer?
var chordPhase = ChordPhase.idle
/// Which keys made the chord, for the app's log ("lctrl+lopt"): as the last poll with both held saw them.
var chordKeys = ""
var voiceOverOn = false
var voiceOverWatch: NSKeyValueObservation?
/// Why the chord is off, as the log last said ("voiceover", "secure"); nil: on (or never off).
var chordOffTold: String?
var chordFirstSeen = false
/// The check that the modifier keys are visible to this helper at all: settled once any is seen
/// held, or once told hidden; until then, the modifier changes counted, and when the last was.
var chordFlagsVisible = false
var chordHiddenTold = false
var chordFlagChanges = 0
var chordLastFlagsAt = 0.0
/// What keeps the helper out of App Nap while the chord is watched (setChord), else nil.
var chordActivity: NSObjectProtocol?
/// When the last poll came (seconds of uptime; 0: none yet since the watch went on), and whether
/// polls too far apart (CHORD_GAP_S) were said in the log.
var chordLastTickAt = 0.0
var chordGapTold = false
/// When a chord spoiled before its "down" was last said in the log (seconds of uptime).
var chordSpoiledToldAt = -Double.infinity
/// What the app was last told ("state") of whether the chord can be used: "on", or why not; nil:
/// nothing yet since the watch went on.
var chordStateTold: String?

/// When the last event of `type` came, in seconds of uptime: the later of what the session and the
/// keyboard itself say (a key the system keeps for a shortcut, ⌃⌥M's M, still counts).
func lastEventAt(_ type: CGEventType, now: Double) -> Double {
    now - min(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type),
              CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type))
}

/// What a poll sees: the keys held (`flags`, asked once by the caller) and, when `timed`, when the
/// last modifier change, key and mouse press came, and why the chord is off. Untimed (nothing held
/// that could begin a chord, none going on) a poll asks for nothing more than the flags.
func chordSample(_ flags: CGEventFlags, now: Double, timed: Bool) -> ChordSample {
    let pair = flags.isSuperset(of: CHORD_PAIR)
    let anyPair = !flags.intersection(CHORD_PAIR).isEmpty
    let others = !flags.intersection(CHORD_OTHERS).isEmpty
    guard timed else {
        return ChordSample(now: now, pair: pair, anyPair: anyPair, others: others, blocked: nil, flagsAt: 0, keyAt: 0, buttonAt: 0, wheelAt: 0)
    }
    let keyAt = max(lastEventAt(.keyDown, now: now), lastEventAt(.keyUp, now: now))
    let buttonAt = [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].map { lastEventAt($0, now: now) }.max() ?? 0
    return ChordSample(now: now, pair: pair, anyPair: anyPair, others: others,
                       blocked: voiceOverOn ? "voiceover" : secureInputOn() ? "secure" : nil,
                       flagsAt: lastEventAt(.flagsChanged, now: now), keyAt: keyAt, buttonAt: buttonAt,
                       wheelAt: lastEventAt(.scrollWheel, now: now))
}

/// Which keys make the chord, for the app's log: "lctrl+lopt", "rctrl+ropt", from the device bits
/// of the flags (IOKit's NX_DEVICELCTLKEYMASK 0x1, NX_DEVICERCTLKEYMASK 0x2000,
/// NX_DEVICELALTKEYMASK 0x20, NX_DEVICERALTKEYMASK 0x40); "ctrl", "opt" where they say no side.
func chordKeyNames(_ flags: CGEventFlags) -> String {
    let raw = flags.rawValue
    func sides(_ left: UInt64, _ right: UInt64, _ name: String) -> [String] {
        let found = (raw & left != 0 ? ["l" + name] : []) + (raw & right != 0 ? ["r" + name] : [])
        return found.isEmpty ? [name] : found
    }
    return (sides(0x1, 0x2000, "ctrl") + sides(0x20, 0x40, "opt")).joined(separator: "+")
}

/// Why the chord is off (nil: on again), said in the log once per change. Main thread.
func noteChordOff(_ why: String?) {
    guard why != chordOffTold else { return }
    let was = chordOffTold
    chordOffTold = why
    switch why {
    case "voiceover": log("[screen] chord: off while VoiceOver is on (Control and Option are its keys)")
    case "secure": log("[screen] chord: off while secure input is on (a password field has the keys)")
    default: log("[screen] chord: on again (\(was == "voiceover" ? "VoiceOver" : "secure input") is off)")
    }
    tellChordState()
}

/// Whether the chord can be used now, as the app is told: "on", or why not ("voiceover", "secure",
/// "hidden"). Main thread.
func chordStateNow() -> String {
    if voiceOverOn { return "voiceover" }
    if chordOffTold == "secure" { return "secure" }
    if chordHiddenTold && !chordFlagsVisible { return "hidden" }
    return "on"
}

/// Tell the app ("state") whether the chord can be used, while it is watched: when that changed,
/// or always (`force`: the watch just went on, for an app that knows nothing yet). So the page
/// names ⌃⌥M, not a chord that does nothing. Main thread.
func tellChordState(force: Bool = false) {
    guard chordTimer != nil else { return }
    let state = chordStateNow()
    guard force || state != chordStateTold else { return }
    chordStateTold = state
    var fields: [String: Any] = ["ev": "chord", "kind": "state", "on": state == "on"]
    if state != "on" { fields["why"] = state }
    emit(fields)
}

/// The check that this helper sees the modifier keys at all (chordFlagsVisible), at one poll:
/// `flagsAt` when the poll asked already. Told hidden, a modifier seen held later says otherwise
/// (and the chord is usable again). Main thread.
func checkChordFlags(_ flags: CGEventFlags, flagsAt known: Double?, now: Double) {
    guard !chordFlagsVisible else { return }
    if !flags.intersection(CHORD_ANY_MODIFIER).isEmpty {
        chordFlagsVisible = true
        if chordHiddenTold {
            log("[screen] chord: modifier keys seen after all")
            tellChordState()
        }
        return
    }
    guard !chordHiddenTold else { return }
    // A modifier changed since the last poll, and none is held at this one.
    let flagsAt = known ?? lastEventAt(.flagsChanged, now: now)
    if flagsAt > chordLastFlagsAt + 0.01 {
        chordFlagChanges += 1
        if chordFlagChanges >= 3 {
            chordHiddenTold = true
            log("[screen] chord: modifier keys look hidden from this helper")
            tellChordState()
        }
    }
    chordLastFlagsAt = flagsAt
}

func tellChord(_ event: ChordEvent) {
    // (for the log alone, a line a second at most: a chord that never got as far as its "down",
    // and why, so a miss leaves a trace; never which key)
    if event.kind == "spoiled" {
        let now = ProcessInfo.processInfo.systemUptime
        if now - chordSpoiledToldAt >= CHORD_SPOILED_EVERY_S {
            chordSpoiledToldAt = now
            log("[screen] chord: spoiled before its down (\(event.why ?? "?"), \(event.ms) ms)")
        }
        return
    }
    if !chordFirstSeen && (event.kind == "down" || event.kind == "tap") {
        chordFirstSeen = true
        log("[screen] chord: first chord seen")
    }
    var fields: [String: Any] = ["ev": "chord", "kind": event.kind, "ms": event.ms]
    if let why = event.why { fields["why"] = why }
    if !chordKeys.isEmpty { fields["keys"] = chordKeys }
    emit(fields)
}

/// One poll of the watch (the timer, on the main queue).
func chordTick() {
    let now = ProcessInfo.processInfo.systemUptime
    // (held back anyway, App Nap or not: the log says so once, in numbers)
    if chordLastTickAt > 0 && now - chordLastTickAt > CHORD_GAP_S && !chordGapTold {
        chordGapTold = true
        log("[screen] chord: polls \(Int(((now - chordLastTickAt) * 1000).rounded())) ms apart")
    }
    chordLastTickAt = now
    let flags = CGEventSource.flagsState(.combinedSessionState)
    var timed = false
    switch chordPhase {
    case .held: timed = true
    case .idle: timed = flags.isSuperset(of: CHORD_PAIR)
    case .waitRelease: timed = false
    }
    let sample = chordSample(flags, now: now, timed: timed)
    checkChordFlags(flags, flagsAt: timed ? sample.flagsAt : nil, now: now)
    if timed { noteChordOff(sample.blocked) }
    // (off for secure input, found as the keys were pressed: on again as soon as it ends, not only
    // at the next press, so the page names the chord again; the cheap check alone, between presses)
    else if chordOffTold == "secure" && !IsSecureEventInputEnabled() { noteChordOff(nil) }
    if sample.pair { chordKeys = chordKeyNames(flags) }
    let (next, event) = chordStep(chordPhase, sample)
    chordPhase = next
    if let event { tellChord(event) }
}

func voiceOverChanged(_ on: Bool) {
    guard on != voiceOverOn else { return }
    voiceOverOn = on
    guard chordTimer != nil else { return }
    if on {
        noteChordOff("voiceover")
    } else if chordOffTold == "voiceover" {
        noteChordOff(nil)
    }
    tellChordState()
}

/// The chord watched (the app's talk key is on) or not. Main thread.
func setChord(_ on: Bool) {
    guard on else {
        chordTimer?.cancel()
        chordTimer = nil
        if let activity = chordActivity {
            ProcessInfo.processInfo.endActivity(activity)
            chordActivity = nil
        }
        chordStateTold = nil
        if case let .held(start, told, _, _) = chordPhase, told {
            tellChord(ChordEvent(kind: "cancel", ms: Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded()), why: "off"))
        }
        chordPhase = .idle
        return
    }
    guard chordTimer == nil else { return }
    if voiceOverWatch == nil {
        voiceOverOn = NSWorkspace.shared.isVoiceOverEnabled
        // (told on whichever thread changed it: read on the main one, as the polls are)
        voiceOverWatch = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new]) { workspace, _ in
            let on = workspace.isVoiceOverEnabled
            DispatchQueue.main.async { voiceOverChanged(on) }
        }
    }
    if voiceOverOn { noteChordOff("voiceover") }
    let now = ProcessInfo.processInfo.systemUptime
    let flags = CGEventSource.flagsState(.combinedSessionState)
    chordPhase = flags.intersection(CHORD_PAIR.union(CHORD_OTHERS)).isEmpty ? .idle : .waitRelease
    if !chordFlagsVisible && !chordHiddenTold { chordLastFlagsAt = lastEventAt(.flagsChanged, now: now) }
    // (out of App Nap while watched, and a timer kept to its leeway: polls on time, so a quick tap
    // is never missed between two)
    chordActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                          reason: "Watching the talk chord")
    chordLastTickAt = 0
    let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
    timer.schedule(deadline: .now(), repeating: .milliseconds(CHORD_POLL_MS), leeway: .milliseconds(CHORD_LEEWAY_MS))
    timer.setEventHandler { chordTick() }
    timer.resume()
    chordTimer = timer
    // (the app hears at once whether the chord can be used: a helper started again knows nothing old)
    tellChordState(force: true)
}

/*
  `--chordtest`: for a person at the keyboard, in Terminal. For CHORD_TEST_S, every
  CHORD_TEST_EVERY_MS: the modifier keys as this process sees them ("ctrl opt" while both are
  held), how long ago the last modifier change, key and mouse press were, VoiceOver and secure
  input, the chord's phase, and what the watch would say. No window, no prompt, no app: it reads
  what the polls read and nothing else. (From Terminal it runs as Terminal does: were Terminal
  allowed Input Monitoring, the flags it shows would prove less for the helper in the app. Nor does
  it run the app's timer: it is a plain loop, before the helper becomes an app, so App Nap and a
  late timer cannot show here; the app's log says "polls N ms apart" for those.)
*/
func chordTest() {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("chordtest: \(Int(CHORD_TEST_S)) s. Tap Control and Option, hold them 5 s, press Control+Option+M; \"ctrl opt\" shows while both are held.")
    let began = ProcessInfo.processInfo.systemUptime
    var phase = ChordPhase.idle
    var keys = ""
    func since(_ at: Double, _ now: Double) -> String { String(format: "%.2f", now - at) }
    while ProcessInfo.processInfo.systemUptime - began < CHORD_TEST_S {
        let now = ProcessInfo.processInfo.systemUptime
        voiceOverOn = NSWorkspace.shared.isVoiceOverEnabled
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let sample = chordSample(flags, now: now, timed: true)
        if sample.pair { keys = chordKeyNames(flags) }
        let names: [(CGEventFlags, String)] = [(.maskControl, "ctrl"), (.maskAlternate, "opt"), (.maskShift, "shift"), (.maskCommand, "cmd"),
                                               (.maskSecondaryFn, "fn"), (.maskAlphaShift, "caps")]
        let held = names.filter { flags.contains($0.0) }.map(\.1)
        let (next, event) = chordStep(phase, sample)
        let state: String
        switch phase {
        case .idle: state = "idle"
        case let .held(start, _, _, _): state = "held \(String(format: "%.2f", now - start)) s"
        case .waitRelease: state = "wait for release"
        }
        phase = next
        var line = String(format: "%6.2f", now - began)
            + "  flags 0x" + String(flags.rawValue, radix: 16) + " " + (held.isEmpty ? "-" : held.joined(separator: " "))
            + "  since: modifier \(since(sample.flagsAt, now)) s, key \(since(sample.keyAt, now)) s, mouse \(since(sample.buttonAt, now)) s"
            + ", wheel \(since(sample.wheelAt, now)) s"
            + "  voiceover \(voiceOverOn ? "on" : "off"), secure input \(secureInputOn() ? "on" : "off")"
            + "  \(state)"
        if let event {
            line += "  -> \(event.kind) \(event.ms) ms" + (event.why.map { " (\($0))" } ?? "") + (keys.isEmpty ? "" : " \(keys)")
        }
        print(line)
        usleep(useconds_t(CHORD_TEST_EVERY_MS * 1000))
    }
}

// MARK: - Commands

func handle(_ line: String) {
    guard let data = line.data(using: .utf8),
          let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let cmd = message["cmd"] as? String
    else {
        log("[screen] bad command: \(line)")
        return
    }
    switch cmd {
    case "status":
        emit(["ev": "status", "screen": CGPreflightScreenCaptureAccess()])
    case "request":
        // Shows macOS's own prompt the first time; after that it only says how things stand.
        // A permission given in System Settings counts once the helper starts again.
        let granted = CGRequestScreenCaptureAccess()
        emit(["ev": "status", "screen": granted])
    case "ax":
        // Scrolling and pressing keys in another app need Accessibility, for this helper by
        // its own name (it is its own responsible process). With "prompt", macOS shows its own
        // dialog the first time, which leads to System Settings; unlike Screen Recording, a
        // switch turned on there counts at once. The option is named by its string: the SDK's
        // constant has changed type between Xcode versions.
        let prompt = message["prompt"] as? Bool ?? false
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
        emit(["ev": "ax", "trusted": trusted])
    case "read":
        guard let id = message["id"] as? Int else {
            log("[screen] bad read: \(line)")
            return
        }
        let level: Level = (message["level"] as? String) == "fast" ? .fast : .accurate
        if let number = (message["window"] as? NSNumber)?.uint32Value {
            Task { await read(id: id, which: .window(number), level: level) }
        } else if let x = message["x"] as? Double, let y = message["y"] as? Double {
            let exclude = Set(((message["exclude"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.int32Value })
            Task { await read(id: id, which: .at(CGPoint(x: x, y: y), exclude: exclude), level: level) }
        } else {
            log("[screen] bad read: \(line)")
            emit(["id": id, "ev": "error", "code": "bad_command"])
        }
    case "turn":
        guard let id = message["id"] as? Int else {
            log("[screen] bad turn: \(line)")
            return
        }
        let how = message["how"] as? String ?? ""
        let dy = (message["dy"] as? NSNumber)?.doubleValue
        let key = (message["key"] as? String).flatMap { KEY_CODES[$0] }
        guard let number = (message["window"] as? NSNumber)?.uint32Value,
              how == "manual" || (how == "scroll" && dy != nil) || (how == "key" && key != nil)
        else {
            log("[screen] bad turn: \(line)")
            emit(["id": id, "ev": "error", "code": "bad_command"])
            return
        }
        var at: CGPoint?
        if let point = message["at"] as? [String: Any],
           let x = (point["x"] as? NSNumber)?.doubleValue,
           let y = (point["y"] as? NSNumber)?.doubleValue {
            at = CGPoint(x: x, y: y)
        }
        // Bounds that only a mistake would reach: a screenful is under 2000 points, a lesson
        // goes back at most 50 pages at once (screenTeach.ts allows no more), and it waits for
        // the student a few minutes at most.
        let asked = Turn(
            window: number,
            pid: (message["pid"] as? NSNumber)?.int32Value,
            how: how,
            dy: min(max(dy ?? 0, -20_000), 20_000),
            key: key,
            count: min(max((message["count"] as? NSNumber)?.intValue ?? 1, 1), 50),
            at: at,
            timeoutMs: min(max((message["timeoutMs"] as? NSNumber)?.intValue ?? 4000, 100), 600_000),
            unlessMoved: message["unlessMoved"] as? Bool ?? false,
            still: how == "manual" && (message["still"] as? Bool ?? false)
        )
        startTurn(id: id, asked)
    case "cancel":
        // A turn no longer wanted (the lesson's wait for the student, given up). One already
        // answered is gone from the list: nothing to do.
        if let id = message["id"] as? Int { takeTurn(id)?.cancel() }
    case "watch":
        guard let number = (message["window"] as? NSNumber)?.uint32Value else {
            log("[screen] bad watch: \(line)")
            return
        }
        installWatch()
        watched = number
        onTopAt = nil
        // How things stand now, as the lesson starts: later ones come as the student switches apps.
        if let app = NSWorkspace.shared.frontmostApplication {
            emit(["ev": "front", "pid": Int(app.processIdentifier), "bundle": app.bundleIdentifier ?? ""])
        }
        // (and which document the window shows, from now on: "ident")
        startIdent()
    case "unwatch":
        watched = nil
        pressedAt = nil
        onTopAt = nil
        stopIdent()
    case "companion":
        let stop = Set(((message["stop"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.uint32Value })
        let privateApps = Set(((message["private"] as? [Any]) ?? []).compactMap { $0 as? String })
        let readerApps = Set(((message["readers"] as? [Any]) ?? []).compactMap { $0 as? String })
        setCompanion(message["on"] as? Bool ?? false, stop: stop, privateApps: privateApps, readerApps: readerApps)
    case "observe":
        // Ordinary windows the app has heard of from "over" or a read: at most two are watched.
        // "page": those of them that turn by the page, where no wheel explains a new look (left
        // out by an app older than it: none).
        let windows = ((message["windows"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.uint32Value }
        let paged = Set(((message["page"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.uint32Value })
        observeWindows(windows, paged: paged)
    case "chord":
        // On exactly while the app's talk key is (a lesson's shortcuts, or the companion on).
        setChord(message["on"] as? Bool ?? false)
    default:
        log("[screen] unknown command: \(cmd)")
    }
}

// Checked on its own, before anything else: it reads nothing and needs no app.
if CommandLine.arguments.contains("--selftest") {
    exit(selfTest() ? 0 : 1)
}
// So is the chord's check, for a person in Terminal: it reads the keys' state and nothing else.
if CommandLine.arguments.contains("--chordtest") {
    chordTest()
    exit(0)
}
refuseUnlessLaunchedByTutornote()
runDisclaimedIfNeeded()

// Stdin on its own thread; the pipe closing (the app has gone) ends the helper.
let reader = Thread {
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        DispatchQueue.main.async { handle(trimmed) }
    }
    exit(0)
}
reader.start()
signal(SIGPIPE, SIG_IGN)
// An app's event loop rather than a bare run loop: the click monitor (installWatch) is delivered
// through it. An accessory app: no Dock icon and no menu bar of its own.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.run()
