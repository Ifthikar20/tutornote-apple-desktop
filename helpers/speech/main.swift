/*
  Tutornote's speech helper: the Mac's own speech recognition (Apple's Speech
  framework, on this machine whenever the language's model is installed) as a small
  line-based tool the app's main process runs (src/main/speech.ts). Commands come in on
  stdin, one JSON object per line; events go out on stdout the same way. The web app sees
  it as window.SpeechRecognition (src/preload/index.ts), so dictation and Teach mode run
  exactly as they do in Chrome: the words appear as they are said, and a phrase is
  finished at the first pause.

  Why: Electron's Chromium has the Web Speech API but not Google's key behind it, so in
  the app the web app used to record clips and send them to the server's whisper - the
  first words took many seconds to land, and a busy server a minute. This keeps every
  word on the Mac.

  Protocol (src/main/speech.ts has the TypeScript side):
    in   {"cmd":"start","id":1,"lang":"en-US","continuous":true,"preroll":1761512640104,"hints":["osmosis"]}
                                    `preroll` (optional, unix ms): the first request is fed the
                                    microphone's audio from then on (the ring: at most
                                    PREROLL_MAX_MS back), so words said between the student's
                                    press and the start are not lost; `hints` (optional, at most
                                    50, each at most 40 characters): the lesson's words, for
                                    Apple's recogniser to expect (contextualStrings)
         {"cmd":"stop","id":1}      hand over what is in flight, then end
         {"cmd":"abort","id":1}     end at once; nothing more is handed over
         {"cmd":"warm","id":0,"ms":3000}
                                    keep the microphone running this long (at most WARM_MAX_MS)
                                    for a session about to start; 0: let it go now unless a
                                    session runs. Only once the microphone is allowed: it never
                                    asks
         {"cmd":"prepare","id":0,"lang":"en-US"}
                                    make the language's recogniser now (Recognizers), when both
                                    permissions are already given; never asks, opens no microphone
         {"cmd":"output","id":0}    say the output the tutor's voice plays on now ("output"),
                                    changed or not; never asks, opens no microphone
    out  every event carries "t": when it was sent (unix ms)
         {"id":1,"ev":"start"}                 the microphone is open and the recogniser set up
         {"id":1,"ev":"audiostart","warm":true,"preroll":126}
                                               sound is arriving: talk now. Sent at the first
                                               buffer that is not digital silence (or after
                                               SOUND_WAIT_MS, "input silent" in the log).
                                               `warm`: the microphone was already running;
                                               `preroll`: ms of audio from before the start
                                               fed to the first request
         {"id":1,"ev":"speechstart"}           the first words of a phrase are being heard
         {"id":1,"ev":"interim","text":"…"}    the words in flight (the whole phrase so far)
         {"id":1,"ev":"phrase","text":"…","cut":"quiet","voiceEnd":…,"cutAt":…,"words":9}
                                               continuous: one finished phrase. `cut`: what
                                               ended it (quiet, text, cap, apple, error, stop,
                                               route); `voiceEnd`: the end of the last voiced
                                               audio (unix ms, when there was any); `cutAt`: when
                                               it was cut (unix ms); `words`: how many
         {"id":1,"ev":"end","text":"…"}        over; for one utterance, its text
         {"id":1,"ev":"error","code":"…"}      Web Speech API codes: not-allowed, no-speech,
                                               network, aborted, audio-capture,
                                               language-not-supported
         {"ev":"ready","id":1,"onDevice":true,"lang":"en-US","cached":true,"setupMs":0}
                                               once per start, what this Mac can do, and whether
                                               the recogniser was made before (and in how long)
         {"ev":"prepared","lang":"en-US","onDevice":true,"ms":112}
                                               a prepare made (or found) the recogniser
         {"ev":"mic","on":true,"why":"warm"}   the microphone really started ("warm" or
                                               "session": what started it) or stopped
         {"ev":"route","input":"AirPods Pro","transport":"bluetooth","using":"MacBook Pro
          Microphone","usingTransport":"builtin","changed":false}
                                               the input the microphone runs on, once per start
                                               of it, and again on a change (`changed`): the
                                               Mac's default input and its transport, and the
                                               one used (chooseInput). Transports: builtin,
                                               bluetooth, usb, hdmi, displayport, airplay,
                                               thunderbolt, virtual, aggregate, other
         {"ev":"output","name":"MacBook Pro Speakers","transport":"builtin","source":"ispk",
          "speakers":true,"changed":false}
                                               the Mac's default output (where the tutor's voice
                                               plays), from the start and on every change, the
                                               microphone on or not (OutputWatch): its name, its
                                               transport, its data source ("ispk" the Mac's own
                                               speakers, "hdpn" its headphone jack, "" none),
                                               whether it is loud in the room (outputIsSpeakers:
                                               anything not known to be headphones is), and
                                               whether it is a change from the last said. Also
                                               said when asked ("output"), with `changed` false
                                               unless it differs from the last said

  One recogniser runs at a time (as in Chrome): a second start aborts the first. Apple's
  recogniser gives the WHOLE transcription of a request as it grows, so a phrase is cut
  here: once the microphone has heard real quiet and the words have stopped changing
  (cutNow: the energy gate's quiet, the words' stillness, and the words alone where the
  gate cannot tell, or heard no voice with them: voiceHeard) the request's audio is ended
  and a new request takes the open microphone in the same moment (nothing said meanwhile
  is lost); the old one's final text is the phrase, handed over in order. A request is also ended at a hard cap (Apple's
  server allows about a minute; on-device far longer).

  The microphone keeps its last RING_MS of audio (the ring), whenever it runs: for a
  session (lingering MIC_LINGER_MS after the last) or warmed ahead of one (warm). A start's
  pre roll is fed from it, so the words between the student's press and the microphone
  being theirs are kept. It runs on the Mac's default input, but for a Bluetooth headset's
  microphone when the Mac has one of its own (chooseInput): AirPods would drop to their
  call quality profile for as long as their microphone is open. A Mac's own microphone that
  gives only digital silence (a MacBook's with its lid shut) gives way to the default
  (checkSound). A change of the input (a headset plugged in) restarts it and cuts the request
  in flight ("route").

  It also keeps an eye on the Mac's default output, where the tutor's voice plays (the web app
  never picks one), and says what it is ("output"): on speakers the microphone hears the tutor
  too, so the page listens only between the tutor's parts; with headphones it may listen while
  the tutor talks. Reading the output needs no permission and opens no microphone, so it runs
  from the helper's start, whether anything listens or not (OutputWatch).

  Environment: ANOTHERNOTES_SPEECH_ONDEVICE=0 forces Apple's server recogniser even when
  the language can be done here; ANOTHERNOTES_SPEECH_QUIET_MS sets how long unchanged words
  end a phrase where the microphone cannot tell (default 800);
  ANOTHERNOTES_SPEECH_INPUT=default keeps a Bluetooth headset's microphone when it is the
  default input.

  `tutornote-speech --selftest` checks the pure parts (the words compared, the cut rule, the
  energy gate and whether it heard a request's voice, the ring, the choice of input, the
  hints, whether an output is speakers) on made-up audio and devices, with no microphone, no
  Speech framework, no audio device read or listened to and no permission, and exits 0 or 1.
*/
import AudioToolbox
import AVFoundation
import CoreAudio
import Darwin
import Foundation
import Security
import Speech

// MARK: - Only for Tutornote

/*
  The helper is its own responsible process (below), so once someone has allowed the
  microphone and speech recognition, the permission is the helper's: any program that ran
  it could listen through it and read what is said. So it runs only for the Tutornote app:
  its parent (the disclaimed copy's grandparent) must be signed as app.tutornote.desktop by
  the same team as the helper itself. A development build signed ad hoc has no team; then
  the identifier alone, or Electron's own (npm start), will do.
*/
let TUTORNOTE_ID = "app.tutornote.desktop"

func parentPid(of pid: pid_t) -> pid_t {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
    return info.kp_eproc.e_ppid
}

/// The Team ID this helper is signed with, or nil (signed ad hoc, or not at all).
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
    if app > 1 && requirements.contains(where: { signed(app, as: $0) }) { return }
    log("[speech] not started by the Tutornote app (process \(app)): refusing to listen")
    exit(1)
}

// MARK: - Its own responsible process

/*
  macOS asks for the microphone and for speech recognition on behalf of the "responsible"
  process: the app the helper runs under - or, when the app was started from a terminal
  (npm run mac from VS Code, say), that terminal. A terminal has no reason for speech
  recognition in its Info.plist, so macOS kills the helper at the first request ("attempted
  to access privacy-sensitive data without a usage description") and dictation falls back
  to recording for the server. So the helper starts itself again, once, disclaimed: the new
  copy is responsible for itself, and its reasons are its own embedded Info.plist
  (helpers/speech/Info.plist). stdin, stdout and stderr are the same pipes; this copy waits
  for it and passes on its exit and a SIGTERM. No disclaim API (older macOS): carry on as is.
*/
let DISCLAIMED_ENV = "ANOTHERNOTES_SPEECH_DISCLAIMED"
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
        log("[speech] could not start a disclaimed copy (\(rc)); carrying on")
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

/// Now, in unix ms: what every event carries ("t"), and the clock the ring and the gate keep
/// (the main process logs against the same wall clock).
func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

func emit(_ fields: [String: Any]) {
    var fields = fields
    fields["t"] = Int64(nowMs().rounded())
    guard JSONSerialization.isValidJSONObject(fields),
          let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    else { return }
    outputLock.lock()
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    outputLock.unlock()
}

func emit(_ id: Int, _ ev: String, text: String? = nil, code: String? = nil) {
    var fields: [String: Any] = ["id": id, "ev": ev]
    if let text = text { fields["text"] = text }
    if let code = code { fields["code"] = code }
    emit(fields)
}

func log(_ message: String) {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
}

func envMs(_ name: String, _ fallback: Double) -> Double {
    guard let raw = ProcessInfo.processInfo.environment[name], let value = Double(raw), value > 0 else { return fallback }
    return value
}

/// How long unchanged words end a phrase (continuous) and a spoken question (one utterance)
/// where the microphone cannot tell quiet from voice (cutNow's "text").
let QUIET_MS = envMs("ANOTHERNOTES_SPEECH_QUIET_MS", 800)
let QUESTION_QUIET_MS = max(QUIET_MS, 900)
/// The cut rule (cutNow): this much real quiet with the words unchanged for STABLE_MS ends a
/// phrase ("quiet"); with less than TEXT_QUIET_MS of quiet the student is still voicing, and
/// unchanged words alone do not end it, unless they stay so for NOISY_MS (a room too loud
/// for the gate to read). Checked every CUT_CHECK_MS while a request has words.
let END_QUIET_MS = 450.0
let STABLE_MS = 300.0
let TEXT_QUIET_MS = 200.0
let NOISY_MS = 2_000.0
let CUT_CHECK_MS = 50.0
/// The energy gate trusts its quiet once it has heard this much of the room (not digital silence).
let GATE_TRUST_MS = 500.0
/// The gate's noise floor falls to a quieter room within about FLOOR_FALL_MS, and rises to a
/// louder one only over about FLOOR_RISE_MS: a student speaking too softly for the gate to call
/// voice must not teach it that the room is that loud (it would then hear no voice at all).
let FLOOR_FALL_MS = 500.0
let FLOOR_RISE_MS = 10_000.0
/// The gate's quiet may end a phrase only when it heard voice in the request, and no longer
/// than this before the words last changed (Apple's words come a little after the audio): words
/// still coming with no voice heard mean the gate is deaf to this student (voiceHeard).
let GATE_LAG_MS = 1_500.0
/// "stop" with no words yet: when the gate heard voice this recently, the request is ended and
/// its final text waited for (a last word Apple has not shown yet), not thrown away.
let STOP_VOICE_MS = 1_000.0
/// The microphone's ring keeps this much audio; a start's pre roll reaches back at most
/// PREROLL_MAX_MS of it.
let RING_MS = 2_000.0
let PREROLL_MAX_MS = 1_500.0
/// "audiostart" waits this long for a buffer that is not digital silence, then goes anyway.
let SOUND_WAIT_MS = 1_500.0
/// A warm keeps the microphone at most this long.
let WARM_MAX_MS = 20_000.0
/// A start's hints: at most this many, each cut to this many characters.
let HINTS_MAX = 50
let HINT_CHARS = 40
/// One utterance with nothing heard this long: "no-speech", as Chrome says after a while.
let NO_SPEECH_MS = 10_000.0
/// A request's hard cap: Apple's server allows about a minute; on-device much more, but a
/// request kept short keeps its transcription small and its final result quick.
let SERVER_CAP_MS = 50_000.0
let ONDEVICE_CAP_MS = 240_000.0
/// After a request's audio is ended, how long its final result gets before the words in
/// flight are taken as it: while talking (the microphone has moved on, nothing is lost by
/// waiting), and after Stop (the take is being written: every millisecond shows).
let FINAL_WAIT_MS = 1_500.0
let STOP_FINAL_WAIT_MS = 500.0
/// The microphone stays open this long after the last session, for the next one (the
/// web app starts a new recogniser as soon as one ends).
let MIC_LINGER_MS = 4_000.0

// MARK: - The pure parts (--selftest checks them: no microphone, no Speech, no permission)

/// The words of a transcription as the cut rule compares them: lower case, letters and digits
/// only, one space between. Apple re-punctuates and re-capitalises a request as it grows
/// ("what is osmosis" becomes "What is osmosis?"): no new word, so no reason to wait longer.
func normalizedWords(_ text: String) -> String {
    var out = ""
    var gap = false
    for scalar in text.lowercased().unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            if gap && !out.isEmpty { out.append(" ") }
            gap = false
            out.unicodeScalars.append(scalar)
        } else {
            gap = true
        }
    }
    return out
}

/// How many words a phrase has, as normalizedWords counts them (for the log: never the words).
func wordCount(_ text: String) -> Int { normalizedWords(text).split(separator: " ").count }

/// Whether the request with words in it is to be cut now, and why: "quiet" once the gate has
/// heard real quiet and the words have settled; "text" on the words alone, once they have not
/// changed for `textMs` and the gate does not hear the student still voicing (or cannot be
/// trusted yet), or for NOISY_MS whatever it hears; nil while the student may still be talking,
/// so a request is never ended mid word.
func cutNow(stableMs: Double, quietMs: Double, trusted: Bool, textMs: Double = QUIET_MS) -> String? {
    if trusted && quietMs >= END_QUIET_MS && stableMs >= STABLE_MS { return "quiet" }
    if stableMs >= textMs && (!trusted || quietMs >= TEXT_QUIET_MS) { return "text" }
    if stableMs >= max(NOISY_MS, textMs) { return "text" }
    return nil
}

/// Whether the gate may speak for a request (cutNow's `trusted`, with the gate's own trust): it
/// heard voice since the request's audio began (`audioFrom`, unix ms), and not more than
/// GATE_LAG_MS before the words last changed (`wordsAt`). A soft voice in a noisy room is quiet
/// to the gate; then its quiet would end the phrase while the student talks on, so the words
/// alone do (textMs, as before the gate).
func voiceHeard(lastVoicedAt: Double, audioFrom: Double, wordsAt: Double) -> Bool {
    lastVoicedAt > 0 && lastVoicedAt >= audioFrom && lastVoicedAt >= wordsAt - GATE_LAG_MS
}

/*
  The energy gate: voice or quiet, from each buffer's loudness (RMS, channel 0) against the
  room's own, a running noise floor learnt only while quiet: it falls quickly to a quieter room
  and rises only slowly (FLOOR_FALL_MS, FLOOR_RISE_MS), so speech too soft to be called voice
  does not lift it to the speaker's own level. It is trusted once it has heard GATE_TRUST_MS of
  the room; before that, in a room too loud for it, and in a request it heard no voice in
  (voiceHeard), the cut goes by the words. A device still switching (a Bluetooth headset going
  to its call profile) delivers exact zeros: digital silence, never voice, never learnt as the
  room.
*/
struct EnergyGate {
    var floor: Float = 0.003
    private(set) var voiced = false
    /// Audio heard since the last voiced buffer (ms of audio, not of the clock).
    private(set) var quietMs: Double = 0
    /// The end of the last voiced buffer (unix ms), 0 before any.
    private(set) var lastVoicedAt: Double = 0
    /// The last buffer was all zeros.
    private(set) var digitalSilence = false
    private(set) var heardMs: Double = 0
    var trusted: Bool { heardMs >= GATE_TRUST_MS }

    /// Feed one buffer of `ms` that began at `start` (unix ms).
    mutating func step(_ samples: UnsafeBufferPointer<Float>, start: Double, ms: Double) {
        guard !samples.isEmpty else { return }
        var sum: Float = 0
        var zeros = true
        for s in samples {
            sum += s * s
            if s != 0 { zeros = false }
        }
        digitalSilence = zeros
        if zeros {
            voiced = false
            quietMs += ms
            return
        }
        heardMs += ms
        let rms = (sum / Float(samples.count)).squareRoot()
        voiced = rms > max(floor * 3, 0.006)
        if voiced {
            quietMs = 0
            lastVoicedAt = start + ms
        } else {
            quietMs += ms
            // (by the buffer's length, whatever the tap's buffers are: quick down, slow up)
            let k = Float(1 - exp(-ms / (rms < floor ? FLOOR_FALL_MS : FLOOR_RISE_MS)))
            floor += (rms - floor) * k
        }
    }
}

/// The last `maxMs` of the microphone: the tap's buffers with when each began (unix ms), so a
/// request started after the words did can be fed them from before it existed (pre roll).
struct AudioRing<Item> {
    struct Entry {
        let item: Item
        let start: Double
        let ms: Double
    }
    let maxMs: Double
    private(set) var entries: [Entry] = []

    init(maxMs: Double) { self.maxMs = maxMs }

    mutating func append(_ item: Item, start: Double, ms: Double) {
        entries.append(Entry(item: item, start: start, ms: ms))
        let keepFrom = start + ms - maxMs
        if let first = entries.firstIndex(where: { $0.start >= keepFrom }), first > 0 { entries.removeFirst(first) }
    }

    /// The buffers that began at `from` or later, and no earlier than `maxMs` before `now`,
    /// oldest first.
    func since(_ from: Double, maxMs: Double, now: Double) -> [Entry] {
        let first = max(from, now - maxMs)
        return entries.filter { $0.start >= first }
    }

    mutating func removeAll() { entries.removeAll() }
}

/// A start's hints as Apple's contextualStrings take them: strings only, trimmed, no empty
/// ones, each cut to HINT_CHARS characters, at most HINTS_MAX.
func clampHints(_ raw: Any?) -> [String] {
    guard let list = raw as? [Any] else { return [] }
    var out: [String] = []
    for item in list {
        guard let text = item as? String else { continue }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        out.append(String(trimmed.prefix(HINT_CHARS)))
        if out.count == HINTS_MAX { break }
    }
    return out
}

/// An audio device as chooseInput weighs it. `transport`: transportName's word for it.
struct AudioInput {
    let id: UInt32
    let name: String
    let transport: String
    let hasInput: Bool
}

/// The input the microphone runs on: the Mac's default, but for a Bluetooth headset's when the
/// Mac has a microphone of its own (AirPods keep their full quality profile, and never switch
/// to the call one as a session starts). `setting` "default" (ANOTHERNOTES_SPEECH_INPUT): always
/// the default.
func chooseInput(defaultID: UInt32, devices: [AudioInput], setting: String?) -> UInt32 {
    if setting == "default" { return defaultID }
    guard devices.first(where: { $0.id == defaultID })?.transport == "bluetooth" else { return defaultID }
    return devices.first(where: { $0.transport == "builtin" && $0.hasInput })?.id ?? defaultID
}

func transportName(_ code: UInt32) -> String {
    switch code {
    case kAudioDeviceTransportTypeBuiltIn: return "builtin"
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "bluetooth"
    case kAudioDeviceTransportTypeUSB: return "usb"
    case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return "aggregate"
    case kAudioDeviceTransportTypeVirtual: return "virtual"
    case kAudioDeviceTransportTypeAirPlay: return "airplay"
    case kAudioDeviceTransportTypeThunderbolt: return "thunderbolt"
    // (apart: a display's speakers lag differently over each, and the page waits out the lag)
    case kAudioDeviceTransportTypeHDMI: return "hdmi"
    case kAudioDeviceTransportTypeDisplayPort: return "displayport"
    default: return "other"
    }
}

/// A Core Audio four character code (a data source: 'ispk') as its four letters; its eight hex
/// digits when they are not all printable.
func fourCharCode(_ code: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xff) }
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }), let text = String(bytes: bytes, encoding: .ascii) else {
        return String(format: "%08x", code)
    }
    return text
}

/*
  Whether the Mac's default output is loud in the room (speakers) or in the student's ears
  (headphones), from what Core Audio says of it: its name, transportName's word for its
  transport, and its data source on the output scope ("ispk" the Mac's own speakers, "hdpn" the
  headphone jack of the same device, as Intel Macs have it; "" when it has none). On speakers the
  microphone hears the tutor's voice, and the page must never take it for the student. Anything
  not known to be headphones is speakers: the safe side (a tutor that waits for its own voice to
  fade, never one that answers itself).
  - builtin: headphones when the source is "hdpn", or when the device is named for them (Apple
    silicon lists its jack as a device of its own, "External Headphones"); else the Mac's speakers.
  - bluetooth (Low Energy too) or usb: headphones when the name says so (AirPods, Beats, a
    headset, earbuds, Sony's WH-1000 and WF-1000, Bose QuietComfort) and nothing in it says
    speaker (Beats Pill, JBL Flip and Charge, UE Boom, a soundbar, a HomePod). A Bluetooth
    device's own class would say it surely, but reading it asks for Bluetooth permission.
  - anything else (a display's speakers over HDMI or DisplayPort, AirPlay, Thunderbolt, virtual
    and aggregate devices): speakers.
*/
let WORN_NAMES = ["airpods", "beats", "headphone", "earphone", "earbud", "buds", "headset", "wh-1000", "wf-1000", "quietcomfort"]
let LOUD_NAMES = ["pill", "speaker", "soundbar", "homepod", "boom", "flip", "charge"]

func outputIsSpeakers(name: String, transport: String, source: String) -> Bool {
    let lower = name.lowercased()
    switch transport {
    case "builtin":
        return !(source == "hdpn" || lower.contains("headphone"))
    case "bluetooth", "usb":
        let worn = WORN_NAMES.contains { lower.contains($0) } && !LOUD_NAMES.contains { lower.contains($0) }
        return !worn
    default:
        return true
    }
}

// MARK: - Input devices (Core Audio; read only but for the engine's own input unit)

enum InputDevices {
    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// The Mac's default input device, or nil (none).
    static func defaultInput() -> AudioDeviceID? {
        var prop = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    /// Every audio device, with its name, transport and whether it has an input.
    static func all() -> [AudioInput] {
        var prop = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &prop, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &prop, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { AudioInput(id: $0, name: name(of: $0), transport: transport(of: $0), hasInput: hasInput($0)) }
    }

    static func name(of id: AudioDeviceID) -> String {
        var prop = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &name) == noErr, let name else { return "device \(id)" }
        return name.takeRetainedValue() as String
    }

    static func transport(of id: AudioDeviceID) -> String {
        var prop = address(kAudioDevicePropertyTransportType)
        var code: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &code) == noErr else { return "other" }
        return transportName(code)
    }

    static func hasInput(_ id: AudioDeviceID) -> Bool {
        var prop = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &prop, 0, nil, &size) == noErr && size > 0
    }

    /// The device an engine's input unit runs on.
    static func current(of unit: AudioUnit) -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let rc = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size)
        return rc == noErr && id != 0 ? id : nil
    }

    /// Run an engine's input unit on `id` (the engine stopped). False when the unit refuses it.
    static func use(_ id: AudioDeviceID, on unit: AudioUnit) -> Bool {
        var device = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, size) == noErr
    }
}

// MARK: - The output (Core Audio; read only)

enum OutputDevice {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// The Mac's default output device, where the tutor's voice plays, or nil (none).
    static func defaultOutput() -> AudioDeviceID? {
        var prop = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    /// Whether the device says which of its outputs plays (its data source: an Intel Mac's
    /// speakers or headphone jack).
    static func hasDataSource(_ id: AudioDeviceID) -> Bool {
        var prop = address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput)
        return AudioObjectHasProperty(id, &prop)
    }

    /// The device's data source on the output scope as four letters ("ispk", "hdpn"), or "".
    static func dataSource(of id: AudioDeviceID) -> String {
        guard hasDataSource(id) else { return "" }
        var prop = address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput)
        var code: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &code) == noErr else { return "" }
        return fourCharCode(code)
    }
}

/// The default output as "output" says it.
struct OutputRoute: Equatable {
    let name: String
    let transport: String
    let source: String
    var speakers: Bool { outputIsSpeakers(name: name, transport: transport, source: source) }
}

/// The default output is looked at again this long after the last change heard: plugging in
/// AirPods changes the default, the device list and the device's own properties in a burst.
let OUTPUT_SETTLE_MS = 200.0

/*
  The watch on the default output, its state all on the main queue. Core Audio calls one listener
  for the system object (the default output, the device list) and for the device that is the
  default now (its data source, when it has one: an Intel Mac's headphones plugged in; its name;
  whether it is still alive), and the watch follows the default to each new device. A burst of
  changes is looked at once, OUTPUT_SETTLE_MS after the last, and "output" is said only when the
  route differs from the last said.

  The listener is Core Audio's plain C one (a function and its client data), not a listener block:
  a listener is removed only by what it was added with, and Swift makes a new block at every call
  that passes one (a block kept in a property included), so a block could never be removed and
  would fire on for every device the default had been. A C function is the same pointer each
  time: it is added and removed with the same object, address, function and client data (none),
  and it hops to the main queue. Never started by --selftest; it needs no permission, and reads
  no audio.
*/
final class OutputWatch {
    static let shared = OutputWatch()
    /// What Core Audio calls, on a thread of its own, for any property watched.
    private static let listener: AudioObjectPropertyListenerProc = { _, _, _, _ in
        DispatchQueue.main.async { OutputWatch.shared.heard() }
        return noErr
    }
    private var started = false
    /// The device whose own listeners are on, and the addresses they are on.
    private var device: AudioDeviceID?
    private var deviceAddresses: [AudioObjectPropertyAddress] = []
    private var told: OutputRoute?
    private var settle: DispatchWorkItem?

    private init() {}

    /// Listen, and say the output now. Once.
    func start() {
        guard !started else { return }
        started = true
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var prop = OutputDevice.address(selector)
            let rc = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &prop, OutputWatch.listener, nil)
            if rc != noErr { log("[speech] output: cannot follow changes (\(rc)); said at start and when asked only") }
        }
        report(force: true)
    }

    /// A change heard: looked at once the burst is over.
    private func heard() {
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.settle = nil
            self?.report(force: false)
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + OUTPUT_SETTLE_MS / 1000, execute: work)
    }

    /// The default output now, followed (its device's listeners moved to it), and said when it
    /// differs from the last said, or whatever it is (`force`: the start, the "output" command).
    /// Nothing is said while the Mac names no default output (between two, a moment).
    func report(force: Bool) {
        let id = OutputDevice.defaultOutput()
        follow(id)
        guard let id else { return }
        let route = OutputRoute(name: InputDevices.name(of: id), transport: InputDevices.transport(of: id), source: OutputDevice.dataSource(of: id))
        let was = told
        if !force && was == route { return }
        told = route
        emit(["ev": "output", "name": route.name, "transport": route.transport, "source": route.source,
              "speakers": route.speakers, "changed": was != nil && was != route])
    }

    /// The device's own listeners off the last default and on `id` (once started: before, there
    /// are none to move).
    private func follow(_ id: AudioDeviceID?) {
        guard started, id != device else { return }
        if let old = device {
            for address in deviceAddresses {
                var prop = address
                AudioObjectRemovePropertyListener(old, &prop, OutputWatch.listener, nil)
            }
        }
        device = id
        deviceAddresses = []
        guard let id else { return }
        var wanted = [OutputDevice.address(kAudioObjectPropertyName), OutputDevice.address(kAudioDevicePropertyDeviceIsAlive)]
        if OutputDevice.hasDataSource(id) { wanted.append(OutputDevice.address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput)) }
        for address in wanted {
            var prop = address
            if AudioObjectAddPropertyListener(id, &prop, OutputWatch.listener, nil) == noErr { deviceAddresses.append(address) }
        }
    }
}

// MARK: - The microphone

/// A copy of a tap's buffer, for the ring (the engine may reuse its own).
func copied(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
    copy.frameLength = buffer.frameLength
    let from = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
    let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for (source, target) in zip(from, to) {
        guard let src = source.mData, let dst = target.mData else { continue }
        memcpy(dst, src, Int(min(source.mDataByteSize, target.mDataByteSize)))
    }
    return copy
}

final class Microphone {
    static let shared = Microphone()
    private let engine = AVAudioEngine()
    private var tapped = false
    /// Guards what the tap's thread shares with the main queue: the sink, the ring, the gate and
    /// the wait for the first sound. The tap puts each buffer in the ring and hands it to the
    /// sink in one hold of it, so a request's pre roll (setSink) gets every buffer once: from the
    /// ring, or from the sink, never both and never neither; and once setSink has returned, the
    /// sink it replaced (a request whose audio is about to end) gets no buffer more.
    private let lock = NSLock()
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var ring = AudioRing<AVAudioPCMBuffer>(maxMs: RING_MS)
    private var gate = EnergyGate()
    private var onSound: (() -> Void)?
    private var lastBufferAt = 0.0
    /// The last buffer that was not digital silence came then (unix ms): checkSound.
    private var lastSoundAt = 0.0
    // (the rest: the main queue only)
    private var stopper: DispatchWorkItem?
    /// What started the engine ("warm" or "session"), nil while it is off.
    private var runningFor: String?
    /// A warm wants the microphone until then (unix ms): a session that ends sooner lingers on to it.
    private var warmUntil = 0.0
    /// When the stopper is due (unix ms).
    private var stopAt = 0.0
    /// The engine is being (re)started here (run): a configuration change heard meanwhile is not
    /// acted on in the middle of it. The observer runs on the main queue, so a change that comes
    /// after run() has returned finds this false, and only a stopped engine is restarted for it.
    private var starting = false
    /// pickInput moved the engine's input unit off the Mac's default (to chooseInput's pick): the
    /// unit stays there until it is moved back, so a later pick of the default must move it too.
    private var pinned = false
    /// The input picked over the default gave only digital silence (checkSound): the default is
    /// kept while this is still the Mac's default input.
    private var keepDefaultFor: AudioDeviceID?
    /// The check that the input picked over the default really gives sound.
    private var soundCheck: DispatchWorkItem?

    private init() {
        // The input changed under the engine (a headset plugged in, another default input): the
        // engine has stopped itself (configurationChanged).
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.configurationChanged()
        }
    }

    /// Where the microphone's buffers go now (a request's append, or nowhere). `preroll` (unix
    /// ms): the ring's buffers from then (at most PREROLL_MAX_MS back) go to it first. Returns
    /// the ms of audio fed from the ring.
    @discardableResult
    func setSink(_ sink: ((AVAudioPCMBuffer) -> Void)?, preroll from: Double? = nil) -> Double {
        lock.lock()
        defer { lock.unlock() }
        var fed = 0.0
        if let from, let sink {
            for entry in ring.since(from, maxMs: PREROLL_MAX_MS, now: nowMs()) {
                sink(entry.item)
                fed += entry.ms
            }
        }
        self.sink = sink
        return fed
    }

    /// The gate as it stands (a copy).
    func gateNow() -> EnergyGate {
        lock.lock()
        defer { lock.unlock() }
        return gate
    }

    /// Sound is arriving now: a buffer came in the last moment, and it was not digital silence.
    func soundNow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lastBufferAt > 0 && nowMs() - lastBufferAt < 300 && !gate.digitalSilence
    }

    /// `then` runs (on the main queue, once) at the next buffer that is not digital silence; nil
    /// forgets it.
    func awaitSound(_ then: (() -> Void)?) {
        lock.lock()
        onSound = then
        lock.unlock()
    }

    /// A buffer from the tap (its own thread): into the gate and the ring, then to the sink.
    private func heard(_ buffer: AVAudioPCMBuffer, _ when: AVAudioTime) {
        let now = nowMs()
        let ms = buffer.format.sampleRate > 0 ? Double(buffer.frameLength) / buffer.format.sampleRate * 1000 : 0
        // When its first sample came: its host time, else as if it had just ended.
        var start = now - ms
        if when.isHostTimeValid {
            let age = AVAudioTime.seconds(forHostTime: mach_absolute_time()) - AVAudioTime.seconds(forHostTime: when.hostTime)
            if age >= 0 && age < 5 { start = now - age * 1000 }
        }
        let copy = copied(buffer)
        lock.lock()
        if let channels = buffer.floatChannelData, buffer.frameLength > 0 {
            gate.step(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)), start: start, ms: ms)
        }
        if let copy { ring.append(copy, start: start, ms: ms) }
        lastBufferAt = now
        if !gate.digitalSilence { lastSoundAt = now }
        var sound: (() -> Void)?
        if !gate.digitalSilence, let waiting = onSound {
            onSound = nil
            sound = waiting
        }
        // (still holding the lock: a request's append is quick, and no buffer reaches a request
        // after the microphone has moved on from it)
        sink?(buffer)
        lock.unlock()
        if let sound { DispatchQueue.main.async(execute: sound) }
    }

    /// Open (or keep open) the microphone, for `why` ("session" or "warm"). True when it was
    /// already running (its ring has audio from before). Throws when there is no input device.
    @discardableResult
    func start(why: String) throws -> Bool {
        stopper?.cancel()
        stopper = nil
        if engine.isRunning && tapped { return true }
        let was = runningFor
        try run(changed: false, announce: was == nil ? why : nil)
        if was == nil { runningFor = why }
        return false
    }

    /// The tap installed afresh (the input's format may be new) on the input chooseInput picks,
    /// and the engine started; then "mic" (`announce`: what started it, when it was off) and the
    /// route are told. The ring starts empty: what it held was in the old tap's format.
    private func run(changed: Bool, announce: String? = nil) throws {
        starting = true
        defer { starting = false }
        soundCheck?.cancel()
        soundCheck = nil
        if engine.isRunning { engine.stop() }
        let input = engine.inputNode
        if tapped {
            input.removeTap(onBus: 0)
            tapped = false
        }
        lock.lock()
        ring.removeAll()
        lock.unlock()
        var route = pickInput(input)
        try installTap(input)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // The input pickInput moved the unit to would not start: back to the one it was on
            // (the default, or the engine's own choice). A unit pickInput left alone has nothing
            // to go back to.
            guard let unit = input.audioUnit, let back = route?.before, route?.usingID != back,
                  InputDevices.use(back, on: unit)
            else {
                input.removeTap(onBus: 0)
                tapped = false
                throw error
            }
            log("[speech] the input picked would not start (\(error.localizedDescription)): back to the one before")
            input.removeTap(onBus: 0)
            tapped = false
            try installTap(input)
            engine.prepare()
            try engine.start()
            pinned = back != route?.defaultID
            route = route.map { RouteNow(defaultID: $0.defaultID, input: $0.input, transport: $0.transport, usingID: back,
                                         using: InputDevices.name(of: back), usingTransport: InputDevices.transport(of: back), before: nil) }
        }
        if let why = announce { emit(["ev": "mic", "on": true, "why": why]) }
        if let route {
            emit(["ev": "route", "input": route.input, "transport": route.transport, "using": route.using,
                  "usingTransport": route.usingTransport, "changed": changed])
            // An input picked over the default must give sound (checkSound); one the default was
            // already kept against (and still would not start) is not tried again and again.
            if route.usingID != route.defaultID && keepDefaultFor != route.defaultID {
                let started = nowMs()
                let check = DispatchWorkItem { [weak self] in
                    self?.checkSound(since: started, defaultID: route.defaultID, using: route.using)
                }
                soundCheck = check
                DispatchQueue.main.asyncAfter(deadline: .now() + SOUND_WAIT_MS / 1000, execute: check)
            }
        }
    }

    private func installTap(_ input: AVAudioInputNode) throws {
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw NSError(domain: "tutornote.speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "no audio input"])
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            self?.heard(buffer, when)
        }
        tapped = true
    }

    private struct RouteNow {
        let defaultID: AudioDeviceID
        let input: String
        let transport: String
        let usingID: AudioDeviceID
        let using: String
        let usingTransport: String
        /// The device the unit ran on before pickInput moved it (nil: not moved), for run() to go
        /// back to when the one moved to will not start.
        let before: AudioDeviceID?
    }

    /// Put the engine's input on the device chooseInput picks (the engine stopped), and say
    /// which it is. Nil when the Mac names no default input (the engine's own choice stands).
    /// The unit is moved only for a pick other than the default, or back from one (pinned):
    /// otherwise it stays on the device the engine chose for itself, which need not be the
    /// default's own id (with a default input and output that differ it may be an aggregate).
    private func pickInput(_ input: AVAudioInputNode) -> RouteNow? {
        guard let defaultID = InputDevices.defaultInput() else { return nil }
        // (a new default input: an input picked over it is worth trying again)
        if let kept = keepDefaultFor, kept != defaultID { keepDefaultFor = nil }
        let devices = InputDevices.all()
        let setting = keepDefaultFor == defaultID ? "default" : ProcessInfo.processInfo.environment["ANOTHERNOTES_SPEECH_INPUT"]
        var chosen = chooseInput(defaultID: defaultID, devices: devices, setting: setting)
        var before: AudioDeviceID?
        if let unit = input.audioUnit, chosen != defaultID || pinned {
            let now = InputDevices.current(of: unit)
            if now == chosen {
                pinned = chosen != defaultID
            } else if InputDevices.use(chosen, on: unit) {
                before = now ?? defaultID
                pinned = chosen != defaultID
            } else {
                log("[speech] could not move the microphone to input \(chosen)")
                chosen = now ?? defaultID
            }
        }
        let byDefault = devices.first { $0.id == defaultID }
        let used = devices.first { $0.id == chosen }
        return RouteNow(defaultID: defaultID, input: byDefault?.name ?? "", transport: byDefault?.transport ?? "other",
                        usingID: chosen, using: used?.name ?? "", usingTransport: used?.transport ?? "other", before: before)
    }

    /*
      The input changed under the engine: it has stopped itself, and its tap's format may be
      gone. A request fed in the old format can take no more, so the microphone restarts
      (restart) on the input chooseInput picks now, if anything still wants it. One that finds
      the engine running (a change it got over, or one set off by this side's own move of the
      input while the engine was stopped) is let be.
    */
    private func configurationChanged() {
        if starting || engine.isRunning { return }
        guard runningFor != nil else {
            lock.lock()
            gate = EnergyGate()
            lock.unlock()
            if tapped {
                engine.inputNode.removeTap(onBus: 0)
                tapped = false
            }
            return
        }
        restart()
    }

    /*
      The input picked over the default (a Mac's own microphone, for a Bluetooth headset's)
      gave nothing but digital silence for SOUND_WAIT_MS after it started: a MacBook's own
      microphone with its lid shut is still listed, and gives zeros. The default is kept from
      then on (keepDefaultFor, until the Mac's default input changes) and the microphone
      restarts on it, as for a change of input.
    */
    private func checkSound(since started: Double, defaultID: AudioDeviceID, using: String) {
        soundCheck = nil
        guard engine.isRunning, runningFor != nil else { return }
        lock.lock()
        let sound = lastSoundAt >= started
        lock.unlock()
        if sound { return }
        log("[speech] no sound from \(using) in \(Int(SOUND_WAIT_MS)) ms: back to the default input")
        keepDefaultFor = defaultID
        restart()
    }

    /// The microphone restarted on the input chooseInput picks now: the session's request in
    /// flight is cut first ("route": its words are a phrase, a new request takes over; the gate
    /// still says where its voice ended), then the ring and the gate start again (the old
    /// audio, the old room). It not starting ends the session ("audio-capture").
    private func restart() {
        guard let why = runningFor else { return }
        Sessions.current?.routeChanged()
        lock.lock()
        gate = EnergyGate()
        lock.unlock()
        do {
            try run(changed: true)
        } catch {
            log("[speech] microphone after a route change: \(error.localizedDescription)")
            runningFor = nil
            emit(["ev": "mic", "on": false, "why": why])
            Sessions.current?.micLost()
        }
    }

    /// Keep the microphone running for `ms` (a session about to start); 0 lets it go now unless a
    /// session runs. Never asks for the microphone: only once it is allowed (Sessions.warm).
    func warm(_ ms: Double, sessionOn: Bool) {
        if ms <= 0 {
            warmUntil = 0
            if !sessionOn && runningFor != nil { stop() }
            return
        }
        warmUntil = max(warmUntil, nowMs() + ms)
        // (a session runs: its end lingers on to the warm's, releaseSoon)
        if sessionOn { return }
        // (the linger after the last session, if longer, stands)
        let lingering = stopper != nil ? stopAt : 0
        do {
            try start(why: "warm")
        } catch {
            log("[speech] microphone (warm): \(error.localizedDescription)")
            return
        }
        stopAfter(max(warmUntil, lingering) - nowMs())
    }

    /// Close the microphone soon, unless a session starts meanwhile (or a warm wants it longer).
    func releaseSoon() {
        stopAfter(max(MIC_LINGER_MS, warmUntil - nowMs()))
    }

    private func stopAfter(_ ms: Double) {
        stopper?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        stopper = work
        stopAt = nowMs() + max(0, ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, ms) / 1000, execute: work)
    }

    func stop() {
        stopper?.cancel()
        stopper = nil
        soundCheck?.cancel()
        soundCheck = nil
        if engine.isRunning { engine.stop() }
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        lock.lock()
        ring.removeAll()
        gate = EnergyGate()
        lastBufferAt = 0
        lastSoundAt = 0
        lock.unlock()
        warmUntil = 0
        if let was = runningFor {
            runningFor = nil
            emit(["ev": "mic", "on": false, "why": was])
        }
    }
}

// MARK: - Permission

enum Permission {
    static var speech: SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }
    static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    /// Ask for both when not yet asked; the answer comes on the main queue.
    static func request(_ done: @escaping (Bool) -> Void) {
        let finish = { (ok: Bool) in DispatchQueue.main.async { done(ok) } }
        let afterMic = { (micOK: Bool) in
            guard micOK else { return finish(false) }
            switch speech {
            case .authorized: finish(true)
            case .notDetermined: SFSpeechRecognizer.requestAuthorization { finish($0 == .authorized) }
            default: finish(false)
            }
        }
        switch microphone {
        case .authorized: afterMic(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { afterMic($0) }
        default: afterMic(false)
        }
    }
}

// MARK: - A session (one recogniser, as the web app sees it)

/// One recognition request: Apple's recogniser transcribes it as a whole, growing.
final class Request {
    let req = SFSpeechAudioBufferRecognitionRequest()
    var task: SFSpeechRecognitionTask?
    /// Its transcription so far.
    var text = ""
    /// Its final text, once known (closing requests only).
    var final: String?
    var finalTimer: DispatchWorkItem?
    /// Its words as the cut rule compares them (normalizedWords), and when they last changed
    /// (unix ms): a comma or a capital Apple adds later is no change.
    var wordsKey = ""
    var wordsAt = 0.0
    /// When its audio began (unix ms): the pre roll's start for a session's first request, else
    /// when the microphone moved on to it. Voice the gate heard before then was another's.
    var audioFrom = 0.0
    /// What ended it (cutNow's verdict, or "cap", "apple", "error", "stop", "route"), when, and
    /// where the gate last heard voice then (unix ms; 0: none): for its phrase event.
    var cut: String?
    var cutAt = 0.0
    var voiceEnd = 0.0
}

final class Session {
    let id: Int
    let continuous: Bool
    let recognizer: SFSpeechRecognizer
    let onDevice: Bool
    /// The start's pre roll (unix ms; the first request is fed the ring from then), and the
    /// lesson's words for every request (contextualStrings).
    let preroll: Double?
    let hints: [String]

    /// The request the microphone feeds now.
    private var current: Request?
    /// Requests whose audio has ended, oldest first, waiting for their final text: their
    /// phrases go out strictly in this order. The microphone has already moved on to a new
    /// request, so nothing said while one of these finishes is lost.
    private var closing: [Request] = []
    /// "speechstart" sent for the current request.
    private var heard = false
    /// "stop" came: end once every phrase is out.
    private var stopping = false
    private(set) var ended = false
    /// The cut rule's check (every CUT_CHECK_MS while the current request has words).
    private var cutTimer: DispatchWorkItem?
    private var capTimer: DispatchWorkItem?
    /// "audiostart" sent; the wait for sound before it goes anyway.
    private var live = false
    private var soundTimer: DispatchWorkItem?
    /// The first request is the one the pre roll feeds; how much it fed (ms).
    private var firstRequest = true
    private var prerollFed = 0.0

    init(id: Int, continuous: Bool, recognizer: SFSpeechRecognizer, onDevice: Bool, preroll: Double?, hints: [String]) {
        self.id = id
        self.continuous = continuous
        self.recognizer = recognizer
        self.onDevice = onDevice
        self.preroll = preroll
        self.hints = hints
    }

    /*
      The microphone first, then "start" (the page may take it as the moment to talk), then
      the first request (fed the pre roll), then "audiostart" once sound is really arriving:
      at once from a microphone that was already running with sound in it, else at the first
      buffer that is not digital silence (a Bluetooth input switching profile sends zeros
      first), or after SOUND_WAIT_MS whatever comes.
    */
    func begin() {
        let warm: Bool
        do {
            warm = try Microphone.shared.start(why: "session")
        } catch {
            log("[speech] microphone: \(error.localizedDescription)")
            fail("audio-capture")
            return
        }
        emit(id, "start")
        beginRequest()
        if warm && Microphone.shared.soundNow() {
            goLive(warm: true)
            return
        }
        Microphone.shared.awaitSound { [weak self] in self?.goLive(warm: warm) }
        schedule(&soundTimer, after: SOUND_WAIT_MS) { [weak self] in
            guard let self = self, !self.live else { return }
            log("[speech] input silent: no sound from the microphone in \(Int(SOUND_WAIT_MS)) ms")
            self.goLive(warm: warm)
        }
    }

    /// This session is the one the microphone serves: only that one changes where its buffers
    /// go, or what waits for its sound (a session left behind must never take it from the live one).
    private var ownsMic: Bool { Sessions.current === self }

    private func goLive(warm: Bool) {
        guard !ended, !live else { return }
        live = true
        soundTimer?.cancel()
        if ownsMic { Microphone.shared.awaitSound(nil) }
        emit(["id": id, "ev": "audiostart", "warm": warm, "preroll": Int(prerollFed.rounded())])
    }

    private func beginRequest() {
        let r = Request()
        r.req.shouldReportPartialResults = true
        r.req.taskHint = .dictation
        if onDevice { r.req.requiresOnDeviceRecognition = true }
        if #available(macOS 13.0, *) { r.req.addsPunctuation = true }
        if !hints.isEmpty { r.req.contextualStrings = hints }
        current = r
        heard = false
        cutTimer?.cancel()
        let req = r.req
        // (the first request of a session with a pre roll gets the ring's audio from then first)
        let from = firstRequest ? preroll : nil
        firstRequest = false
        r.audioFrom = from.map { max($0, nowMs() - PREROLL_MAX_MS) } ?? nowMs()
        let fed = ownsMic ? Microphone.shared.setSink({ buffer in req.append(buffer) }, preroll: from) : 0
        if from != nil { prerollFed = fed }
        r.task = recognizer.recognitionTask(with: req) { [weak self, weak r] result, error in
            DispatchQueue.main.async {
                guard let self = self, let r = r else { return }
                self.handle(r, result, error)
            }
        }
        // The cap, and for one utterance the silence that means nobody is talking.
        let cap = onDevice ? ONDEVICE_CAP_MS : SERVER_CAP_MS
        schedule(&capTimer, after: continuous ? cap : min(cap, NO_SPEECH_MS)) { [weak self] in
            guard let self = self else { return }
            if self.continuous || self.heard { self.closeCurrent(cut: "cap") } else { self.fail("no-speech") }
        }
    }

    /// The cut rule, now (the words just changed) and every CUT_CHECK_MS while the current
    /// request has words, until it says to cut.
    private func checkCut() {
        guard !ended, let r = current, !r.wordsKey.isEmpty else {
            cutTimer?.cancel()
            return
        }
        let gate = Microphone.shared.gateNow()
        let textMs = continuous ? QUIET_MS : QUESTION_QUIET_MS
        // (a gate that heard no voice with these words is deaf to this student: the words decide)
        let heardVoice = voiceHeard(lastVoicedAt: gate.lastVoicedAt, audioFrom: r.audioFrom, wordsAt: r.wordsAt)
        if let cut = cutNow(stableMs: nowMs() - r.wordsAt, quietMs: gate.quietMs, trusted: gate.trusted && heardVoice, textMs: textMs) {
            closeCurrent(cut: cut)
            return
        }
        schedule(&cutTimer, after: CUT_CHECK_MS) { [weak self] in self?.checkCut() }
    }

    /// The words in flight: what closing requests have not finalised yet, then the current one.
    private func inFlight() -> String {
        (closing.map { $0.final ?? $0.text } + [current?.text ?? ""])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func handle(_ r: Request, _ result: SFSpeechRecognitionResult?, _ error: Error?) {
        guard !ended else { return }
        let words = result?.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        if r !== current {
            // A closing request: its final text (or, on an error, what it had).
            guard closing.contains(where: { $0 === r }), r.final == nil else { return }
            if let words = words, !words.isEmpty { r.text = words }
            if result?.isFinal == true || error != nil { settle(r, r.text) }
            return
        }
        if let words = words {
            if result?.isFinal == true {
                // Apple ended it by itself: take it as a finished phrase, at once (its task is
                // over: no other final is coming for closeCurrent to wait for).
                r.text = words.isEmpty ? r.text : words
                closeCurrent(cut: "apple")
                settle(r, r.text)
                return
            }
            if words != r.text {
                r.text = words
                // (a comma or a capital is no new word: the words' stillness runs on)
                let key = normalizedWords(words)
                if key != r.wordsKey {
                    r.wordsKey = key
                    r.wordsAt = nowMs()
                }
                if !heard && !words.isEmpty {
                    heard = true
                    emit(id, "speechstart")
                    if !continuous {
                        schedule(&capTimer, after: onDevice ? ONDEVICE_CAP_MS : SERVER_CAP_MS) { [weak self] in self?.closeCurrent(cut: "cap") }
                    }
                }
                emit(id, "interim", text: inFlight())
                if !key.isEmpty { checkCut() }
            }
        }
        if let error = error {
            let ns = error as NSError
            // (an error ends the request's task: what it has is settled at once, not waited on)
            if ns.code == 1110 { // no speech detected
                if continuous { r.text = ""; closeCurrent(cut: "error"); settle(r, r.text); return }
                return fail("no-speech")
            }
            log("[speech] recogniser: \(ns.domain) \(ns.code) \(ns.localizedDescription)")
            if continuous && !r.text.isEmpty {
                closeCurrent(cut: "error") // keep the words in flight; a new request carries on
                settle(r, r.text)
                return
            }
            fail("network")
        }
    }

    /// The input changed (Microphone.configurationChanged): the request in flight was fed the old
    /// format and can take no more. Its words are a phrase; a new request takes the new input.
    /// One with nothing in it yet (no words, no voice heard: an input that gave only silence) is
    /// simply replaced, so the session runs on as it was, one utterance too.
    func routeChanged() {
        guard !ended, let r = current else { return }
        let gate = Microphone.shared.gateNow()
        if r.text.isEmpty && !(gate.lastVoicedAt > 0 && gate.lastVoicedAt >= r.audioFrom) {
            current = nil
            r.task?.cancel()
            beginRequest()
            return
        }
        closeCurrent(cut: "route")
    }

    /// The microphone could not be had again after a change of input.
    func micLost() { fail("audio-capture") }

    /// End the current request's audio and, still listening, start the next one at once. `cut`:
    /// what ended it, for its phrase event.
    private func closeCurrent(cut: String) {
        guard !ended, let r = current else { return }
        cutTimer?.cancel()
        capTimer?.cancel()
        r.cut = cut
        r.cutAt = nowMs()
        // (voice from before the request began was another request's: none heard in this one)
        let voiced = Microphone.shared.gateNow().lastVoicedAt
        r.voiceEnd = voiced >= r.audioFrom ? voiced : 0
        current = nil
        closing.append(r)
        // The microphone moves on first, then the old request's audio ends: once setSink has
        // returned no buffer can reach it, so every buffer goes to exactly one request.
        if continuous && !stopping { beginRequest() } else if ownsMic { Microphone.shared.setSink(nil) }
        r.req.endAudio()
        let wait = stopping ? STOP_FINAL_WAIT_MS : FINAL_WAIT_MS
        let timer = DispatchWorkItem { [weak self, weak r] in
            guard let self = self, let r = r else { return }
            self.settle(r, r.text)
        }
        r.finalTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + wait / 1000, execute: timer)
        flush()
    }

    private func settle(_ r: Request, _ text: String) {
        guard r.final == nil else { return }
        r.final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        r.finalTimer?.cancel()
        flush()
    }

    /// Hand over the finished phrases, in order, and end when nothing is left.
    private func flush() {
        guard !ended else { return }
        var utterance = ""
        while let first = closing.first, let final = first.final {
            closing.removeFirst()
            first.task?.cancel()
            if continuous {
                if !final.isEmpty { emitPhrase(first, final) }
            } else {
                utterance = [utterance, final].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        if !closing.isEmpty || current != nil { return }
        if !continuous || stopping { end(text: utterance) }
    }

    /// One finished phrase, with what cut it, when the voice ended, and how many words it has.
    private func emitPhrase(_ r: Request, _ text: String) {
        var fields: [String: Any] = ["id": id, "ev": "phrase", "text": text, "cut": r.cut ?? "text", "words": wordCount(text)]
        if r.voiceEnd > 0 { fields["voiceEnd"] = Int64(r.voiceEnd.rounded()) }
        if r.cutAt > 0 { fields["cutAt"] = Int64(r.cutAt.rounded()) }
        emit(fields)
    }

    func stop() {
        guard !ended else { return }
        stopping = true
        if let r = current {
            // No words yet, but voice a moment ago: its last word may still be on Apple's way.
            let gate = Microphone.shared.gateNow()
            let voiceJustNow = gate.lastVoicedAt > 0 && nowMs() - gate.lastVoicedAt <= STOP_VOICE_MS
            if heard || !r.text.isEmpty || voiceJustNow {
                closeCurrent(cut: "stop")
            } else {
                current = nil; r.task?.cancel(); if ownsMic { Microphone.shared.setSink(nil) }; flush()
            }
        } else {
            flush()
        }
    }

    func abort() {
        guard !ended else { return }
        tearDown()
        emit(id, "error", code: "aborted")
        emit(id, "end", text: "")
    }

    private func fail(_ code: String) {
        guard !ended else { return }
        tearDown()
        emit(id, "error", code: code)
        emit(id, "end", text: "")
    }

    private func end(text: String) {
        guard !ended else { return }
        tearDown()
        emit(id, "end", text: text)
    }

    private func tearDown() {
        ended = true
        cutTimer?.cancel()
        capTimer?.cancel()
        soundTimer?.cancel()
        if ownsMic {
            Microphone.shared.awaitSound(nil)
            Microphone.shared.setSink(nil)
        }
        for r in closing + [current].compactMap({ $0 }) {
            r.finalTimer?.cancel()
            r.task?.cancel()
        }
        closing = []
        current = nil
        Sessions.ended(self)
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after ms: Double, _ work: @escaping () -> Void) {
        slot?.cancel()
        let item = DispatchWorkItem(block: work)
        slot = item
        DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000, execute: item)
    }
}

// MARK: - Recognisers, made once per language

/*
  Making Apple's recogniser for a language takes 85 to 124 ms, on every session as it was. It
  is made once per language and kept (the main queue only), and made afresh when the kept one
  says it is not available (its model went, or the server cannot be reached). A page about to
  listen has it made ahead (prepare), so its first session finds it ready.
*/
enum Recognizers {
    private static var kept: [String: SFSpeechRecognizer] = [:]

    static func get(_ lang: String) -> SFSpeechRecognizer? { lookup(lang)?.recognizer }

    /// The language's recogniser, whether it was kept from before, and how long it took to have.
    static func lookup(_ lang: String) -> (recognizer: SFSpeechRecognizer, cached: Bool, ms: Double)? {
        let key = lang.isEmpty ? Locale.current.identifier : lang
        let began = DispatchTime.now().uptimeNanoseconds
        let took = { Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000 }
        if let recognizer = kept[key], recognizer.isAvailable { return (recognizer, true, took()) }
        guard let made = SFSpeechRecognizer(locale: Locale(identifier: key)) ?? SFSpeechRecognizer() else {
            kept[key] = nil
            return nil
        }
        kept[key] = made
        return (made, false, took())
    }
}

/// Recognition on this Mac, unless ANOTHERNOTES_SPEECH_ONDEVICE=0 or the language's model is not here.
func onDeviceFor(_ recognizer: SFSpeechRecognizer) -> Bool {
    ProcessInfo.processInfo.environment["ANOTHERNOTES_SPEECH_ONDEVICE"] != "0" && recognizer.supportsOnDeviceRecognition
}

// MARK: - Commands

enum Sessions {
    static var current: Session?
    /// Sessions aborted (or stopped) while their permission dialog was still up.
    static var cancelled = Set<Int>()

    static func start(id: Int, lang: String, continuous: Bool, preroll: Double?, hints: [String]) {
        if let active = current, !active.ended { active.abort() }
        cancelled.remove(id)
        Permission.request { ok in
            if cancelled.remove(id) != nil {
                emit(id, "end", text: "")
                return
            }
            guard ok else {
                emit(id, "error", code: "not-allowed")
                emit(id, "end", text: "")
                return
            }
            guard let found = Recognizers.lookup(lang) else {
                emit(id, "error", code: "language-not-supported")
                emit(id, "end", text: "")
                return
            }
            let recognizer = found.recognizer
            guard recognizer.isAvailable else {
                emit(id, "error", code: "network")
                emit(id, "end", text: "")
                return
            }
            let onDevice = onDeviceFor(recognizer)
            emit(["ev": "ready", "id": id, "onDevice": onDevice, "lang": recognizer.locale.identifier,
                  "cached": found.cached, "setupMs": Int(found.ms.rounded())])
            let session = Session(id: id, continuous: continuous, recognizer: recognizer, onDevice: onDevice, preroll: preroll, hints: hints)
            // (another start's session may have come up while this one's permission answer was on
            // its way: one recogniser at a time, and none left running unowned)
            if let active = current, !active.ended { active.abort() }
            current = session
            session.begin()
        }
    }

    /// The microphone running for a session about to start (or let go: 0). Only once the
    /// microphone is allowed: a warm never asks, and the engine is not touched before then.
    static func warm(ms: Double) {
        guard Permission.microphone == .authorized else { return }
        Microphone.shared.warm(min(max(ms, 0), WARM_MAX_MS), sessionOn: current.map { !$0.ended } ?? false)
    }

    /// The language's recogniser made now, when both permissions are already given (never asks,
    /// opens no microphone); "prepared" says so.
    static func prepare(lang: String) {
        guard Permission.speech == .authorized, Permission.microphone == .authorized else { return }
        guard let found = Recognizers.lookup(lang) else { return }
        emit(["ev": "prepared", "lang": found.recognizer.locale.identifier, "onDevice": onDeviceFor(found.recognizer),
              "ms": Int(found.ms.rounded())])
    }

    static func ended(_ session: Session) {
        if current === session {
            current = nil
            Microphone.shared.releaseSoon()
        }
    }

    static func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cmd = message["cmd"] as? String,
              let id = message["id"] as? Int
        else {
            log("[speech] bad command: \(line)")
            return
        }
        switch cmd {
        case "start":
            let preroll = (message["preroll"] as? NSNumber)?.doubleValue
            start(id: id, lang: message["lang"] as? String ?? "", continuous: message["continuous"] as? Bool ?? false,
                  preroll: preroll.flatMap { $0.isFinite ? $0 : nil }, hints: clampHints(message["hints"]))
        case "stop":
            if let s = current, s.id == id { s.stop() } else { cancelled.insert(id) }
        case "abort":
            if let s = current, s.id == id { s.abort() } else { cancelled.insert(id) }
        case "warm":
            let ms = (message["ms"] as? NSNumber)?.doubleValue ?? 0
            warm(ms: ms.isFinite ? ms : 0)
        case "prepare":
            prepare(lang: message["lang"] as? String ?? "")
        case "output":
            // (a page asking where the tutor's voice plays: said again, changed or not)
            OutputWatch.shared.report(force: true)
        default:
            log("[speech] unknown command: \(cmd)")
        }
    }
}

// MARK: - Self test

/// `--selftest`: the rules the cut and the microphone rest on, on made-up audio and devices (no
/// microphone, no Speech framework, no permission asked). True when all of it holds.
func selfTest() -> Bool {
    var ok = true
    func check(_ what: String, _ holds: Bool) {
        print("\(holds ? "ok  " : "FAIL") \(what)")
        if !holds { ok = false }
    }

    // The words as the cut compares them.
    check("normalizedWords: \"What is osmosis?\" is \"what is  osmosis\"",
          normalizedWords("What is osmosis?") == normalizedWords("what is  osmosis") && normalizedWords("what is  osmosis") == "what is osmosis")
    check("normalizedWords of punctuation alone is empty", normalizedWords(" ?, . ").isEmpty)
    check("wordCount counts words, not punctuation", wordCount("What is osmosis?") == 3 && wordCount("") == 0)

    // The cut rule (the words' stillness, the gate's quiet, whether the gate is trusted).
    check("cutNow(310, 460, trusted) is quiet", cutNow(stableMs: 310, quietMs: 460, trusted: true, textMs: 800) == "quiet")
    check("cutNow(290, 900, trusted) waits: the words changed a moment ago", cutNow(stableMs: 290, quietMs: 900, trusted: true, textMs: 800) == nil)
    check("cutNow(820, 100, trusted) waits: the student is still voicing", cutNow(stableMs: 820, quietMs: 100, trusted: true, textMs: 800) == nil)
    check("cutNow(820, 250, trusted) is text", cutNow(stableMs: 820, quietMs: 250, trusted: true, textMs: 800) == "text")
    check("cutNow(2001, 0, trusted) is text: a room too loud for the gate", cutNow(stableMs: 2001, quietMs: 0, trusted: true, textMs: 800) == "text")
    check("cutNow(820, 0, not trusted) is text", cutNow(stableMs: 820, quietMs: 0, trusted: false, textMs: 800) == "text")
    check("cutNow(500, 1000, not trusted) waits: an untrusted gate never cuts on quiet", cutNow(stableMs: 500, quietMs: 1000, trusted: false, textMs: 800) == nil)
    check("voiceHeard: voice in the request, 300 ms before its words changed", voiceHeard(lastVoicedAt: 10_700, audioFrom: 10_000, wordsAt: 11_000))
    check("voiceHeard: voice only from before the request began is another's", !voiceHeard(lastVoicedAt: 9_900, audioFrom: 10_000, wordsAt: 10_200))
    check("voiceHeard: words still changing 2 s after the last voice: the gate is deaf to them",
          !voiceHeard(lastVoicedAt: 10_700, audioFrom: 10_000, wordsAt: 12_700))
    check("voiceHeard: no voice at all", !voiceHeard(lastVoicedAt: 0, audioFrom: 0, wordsAt: 500))

    // The gate: 1 s of room noise, 300 ms of voice, 500 ms of room noise, in 100 ms buffers.
    let rate = 16_000.0
    let block = Int(rate / 10)
    var gate = EnergyGate()
    var clock = 1_000_000.0
    var seed: UInt32 = 12_345
    func noise(rms: Float) -> [Float] {
        // Uniform in ±a has an RMS of a/√3.
        let a = rms * Float(3).squareRoot()
        return (0..<block).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return (Float(seed >> 8) / Float(1 << 24) * 2 - 1) * a
        }
    }
    func tone(rms: Float) -> [Float] {
        let a = rms * Float(2).squareRoot()
        return (0..<block).map { i in a * Float(sin(2 * Double.pi * 220 * Double(i) / rate)) }
    }
    /// Feed `ms` of `make`'s buffers; whether each was voiced.
    func feed(_ ms: Int, _ make: () -> [Float]) -> [Bool] {
        var voiced: [Bool] = []
        for _ in 0..<(ms / 100) {
            let samples = make()
            samples.withUnsafeBufferPointer { gate.step($0, start: clock, ms: 100) }
            clock += 100
            voiced.append(gate.voiced)
        }
        return voiced
    }
    let room = feed(400, { noise(rms: 0.002) })
    check("the gate is not trusted after 400 ms of the room", !gate.trusted)
    let roomRest = feed(600, { noise(rms: 0.002) })
    check("the gate is trusted after 500 ms of the room", gate.trusted)
    let voice = feed(300, { tone(rms: 0.2) })
    let voiceEnded = clock
    let after = feed(500, { noise(rms: 0.002) })
    check("room noise at RMS 0.002 is quiet", !(room + roomRest + after).contains(true))
    check("a tone at RMS 0.2 is voiced, all through", voice.allSatisfy { $0 })
    check("the last voice is where the tone ended", gate.lastVoicedAt == voiceEnded)
    check("quietMs is 500 ± 100 after 500 ms of the room", abs(gate.quietMs - 500) <= 100)
    var zeros = EnergyGate()
    [Float](repeating: 0, count: block).withUnsafeBufferPointer { zeros.step($0, start: 0, ms: 100) }
    check("zeros are digital silence, never voice", zeros.digitalSilence && !zeros.voiced && !zeros.trusted)
    check("the room is not digital silence", !gate.digitalSilence)

    // A soft voice in a noisy room: 1 s of the room at RMS 0.004, then 3 s of speech at 0.008,
    // too soft for the gate to call voice. It must not teach the gate that the room is that
    // loud, and the gate's quiet must not end the phrase while it goes on: the words alone do.
    gate = EnergyGate()
    _ = feed(1_000, { noise(rms: 0.004) })
    let softFrom = clock
    let soft = feed(3_000, { noise(rms: 0.008) })
    check("a voice at RMS 0.008 in a room at 0.004 is too soft for the gate", !soft.contains(true))
    check("3 s of it keep the floor below 0.006", gate.floor < 0.006)
    let softHeard = voiceHeard(lastVoicedAt: gate.lastVoicedAt, audioFrom: softFrom, wordsAt: clock - 300)
    check("words that came with no voice heard: the gate cannot speak for them", !softHeard && gate.trusted)
    check("so its 4 s of quiet do not cut at 300 ms of unchanged words",
          gate.quietMs >= 3_900 && cutNow(stableMs: 300, quietMs: gate.quietMs, trusted: gate.trusted && softHeard, textMs: 800) == nil)
    check("the words alone cut them at 800 ms", cutNow(stableMs: 800, quietMs: gate.quietMs, trusted: gate.trusted && softHeard, textMs: 800) == "text")
    gate = EnergyGate()
    _ = feed(1_000, { noise(rms: 0.004) })
    _ = feed(3_000, { noise(rms: 0.010) })
    check("1 s of the room at 0.004, then 3 s at 0.010: the floor stays below 0.006", gate.floor < 0.006)
    check("and then a voice at RMS 0.020 is voice", feed(500, { tone(rms: 0.020) }).allSatisfy { $0 })

    // The ring: 30 buffers of 100 ms from t0; 2 s are kept.
    let t0 = 5_000_000.0
    var ring = AudioRing<Int>(maxMs: RING_MS)
    for i in 0..<30 { ring.append(i, start: t0 + Double(i) * 100, ms: 100) }
    let now = t0 + 3_000
    check("the ring drops what is older than 2000 ms", ring.entries.count == 20 && ring.entries.first?.item == 10)
    let back = ring.since(t0 + 1_234, maxMs: 1_500, now: now)
    check("since(t0 + 1234, max 1500) is the last 1500 ms, from buffer 15",
          back.map(\.item) == Array(15..<30) && back.allSatisfy { $0.start >= t0 + 1_234 } && back.reduce(0) { $0 + $1.ms } <= 1_500)
    let near = ring.since(t0 + 2_234, maxMs: 1_500, now: now)
    check("since(t0 + 2234) is the buffers that began at it or later", near.map(\.item) == Array(23..<30))
    check("since(after the newest buffer began) is empty", ring.since(t0 + 2_950, maxMs: 1_500, now: now).isEmpty)

    // The input the microphone runs on.
    let builtIn = AudioInput(id: 1, name: "MacBook Pro Microphone", transport: "builtin", hasInput: true)
    let speakers = AudioInput(id: 2, name: "MacBook Pro Speakers", transport: "builtin", hasInput: false)
    let airPods = AudioInput(id: 3, name: "AirPods Pro", transport: "bluetooth", hasInput: true)
    let usb = AudioInput(id: 4, name: "External Microphone", transport: "usb", hasInput: true)
    let all = [speakers, airPods, builtIn, usb]
    check("a Bluetooth default with a built in microphone: the built in one", chooseInput(defaultID: 3, devices: all, setting: nil) == 1)
    check("a USB default: the USB one", chooseInput(defaultID: 4, devices: all, setting: nil) == 4)
    check("Bluetooth only: the Bluetooth one", chooseInput(defaultID: 3, devices: [speakers, airPods], setting: nil) == 3)
    check("ANOTHERNOTES_SPEECH_INPUT=default: the default", chooseInput(defaultID: 3, devices: all, setting: "default") == 3)

    // A start's hints.
    let sixty: [Any] = (0..<60).map { "word \($0)" }
    check("hints: 60 come to 50, in order", clampHints(sixty).count == 50 && clampHints(sixty).first == "word 0" && clampHints(sixty).last == "word 49")
    check("hints: a long one is cut to 40 characters", clampHints([String(repeating: "a", count: 90)] as [Any]) == [String(repeating: "a", count: 40)])
    check("hints: empty ones and others than strings are dropped", clampHints(["", "  ", "osmosis", 7] as [Any]) == ["osmosis"])
    check("hints: none but a list", clampHints("osmosis").isEmpty && clampHints(nil).isEmpty)

    // Whether the output is loud in the room (made up devices: none is read).
    check("the Mac's own speakers (builtin, ispk) are speakers", outputIsSpeakers(name: "MacBook Pro Speakers", transport: "builtin", source: "ispk"))
    check("an Intel Mac's headphone jack (builtin, hdpn) is headphones", !outputIsSpeakers(name: "Built-in Output", transport: "builtin", source: "hdpn"))
    check("Apple silicon's jack, \"External Headphones\", is headphones", !outputIsSpeakers(name: "External Headphones", transport: "builtin", source: ""))
    check("\"AirPods Pro\" over Bluetooth are headphones", !outputIsSpeakers(name: "AirPods Pro", transport: "bluetooth", source: ""))
    check("\"Beats Pill+\" is a speaker, though Beats", outputIsSpeakers(name: "Beats Pill+", transport: "bluetooth", source: ""))
    check("\"JBL Flip 5\" is a speaker", outputIsSpeakers(name: "JBL Flip 5", transport: "bluetooth", source: ""))
    check("\"Jabra Evolve2 Headset\" over USB is headphones", !outputIsSpeakers(name: "Jabra Evolve2 Headset", transport: "usb", source: ""))
    check("a display, \"LG HDR 4K\" over DisplayPort, is speakers", outputIsSpeakers(name: "LG HDR 4K", transport: "displayport", source: ""))
    check("a virtual device, \"BlackHole 2ch\", is speakers", outputIsSpeakers(name: "BlackHole 2ch", transport: "virtual", source: ""))
    check("AirPlay is speakers, whatever its name", outputIsSpeakers(name: "Living Room", transport: "airplay", source: "")
            && outputIsSpeakers(name: "AirPods Pro", transport: "airplay", source: ""))
    check("transportName tells HDMI from DisplayPort",
          transportName(kAudioDeviceTransportTypeHDMI) == "hdmi" && transportName(kAudioDeviceTransportTypeDisplayPort) == "displayport")
    check("fourCharCode reads 'ispk', and an unprintable code as hex", fourCharCode(0x6973_706B) == "ispk" && fourCharCode(1) == "00000001")
    return ok
}

// Checked on its own, before anything else: it reads nothing and needs no app.
if CommandLine.arguments.contains("--selftest") {
    exit(selfTest() ? 0 : 1)
}
refuseUnlessLaunchedByTutornote()
runDisclaimedIfNeeded()

// The output the tutor's voice plays on, said now and on every change, before any command is
// read: in the disclaimed copy (the first one never returns from runDisclaimedIfNeeded, unless
// this macOS cannot disclaim, and then it is the only one).
OutputWatch.shared.start()

// Stdin on its own thread; everything else on the main queue. The pipe closing (the app
// has gone) ends the helper.
let reader = Thread {
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        DispatchQueue.main.async { Sessions.handle(trimmed) }
    }
    DispatchQueue.main.async {
        Sessions.current?.abort()
        Microphone.shared.stop()
        exit(0)
    }
}
reader.start()
signal(SIGPIPE, SIG_IGN)
RunLoop.main.run()
