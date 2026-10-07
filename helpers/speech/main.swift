/*
  AnotherNote's speech helper: the Mac's own speech recognition (Apple's Speech
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
    in   {"cmd":"start","id":1,"lang":"en-US","continuous":true}
         {"cmd":"stop","id":1}      hand over what is in flight, then end
         {"cmd":"abort","id":1}     end at once; nothing more is handed over
    out  {"id":1,"ev":"start"}                 the recogniser is set up
         {"id":1,"ev":"audiostart"}            the microphone is running: talk now
         {"id":1,"ev":"speechstart"}           the first words of a phrase are being heard
         {"id":1,"ev":"interim","text":"…"}    the words in flight (the whole phrase so far)
         {"id":1,"ev":"phrase","text":"…"}     continuous: one finished phrase
         {"id":1,"ev":"end","text":"…"}        over; for one utterance, its text
         {"id":1,"ev":"error","code":"…"}      Web Speech API codes: not-allowed, no-speech,
                                               network, aborted, audio-capture,
                                               language-not-supported
         {"ev":"ready","onDevice":true}        once per start, what this Mac can do

  One recogniser runs at a time (as in Chrome): a second start aborts the first. Apple's
  recogniser gives the WHOLE transcription of a request as it grows, so a phrase is cut
  here: once the words stop changing for QUIET_MS the request's audio is ended and a new
  request takes the open microphone in the same moment (nothing said meanwhile is lost);
  the old one's final text is the phrase, handed over in order. A request is also ended at
  a hard cap (Apple's server allows about a minute; on-device far longer).

  Environment: ANOTHERNOTES_SPEECH_ONDEVICE=0 forces Apple's server recogniser even when
  the language can be done here; ANOTHERNOTES_SPEECH_QUIET_MS sets the pause that ends a
  phrase (default 800).
*/
import AVFoundation
import Darwin
import Foundation
import Speech

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

func emit(_ fields: [String: Any]) {
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

/// The pause that ends a phrase (continuous), and a spoken question (one utterance).
let QUIET_MS = envMs("ANOTHERNOTES_SPEECH_QUIET_MS", 800)
let QUESTION_QUIET_MS = max(QUIET_MS, 900)
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

// MARK: - The microphone

final class Microphone {
    static let shared = Microphone()
    private let engine = AVAudioEngine()
    private var tapped = false
    private let lock = NSLock()
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var stopper: DispatchWorkItem?

    func setSink(_ sink: ((AVAudioPCMBuffer) -> Void)?) {
        lock.lock()
        self.sink = sink
        lock.unlock()
    }

    /// Open (or keep open) the microphone. Throws when there is no input device.
    func start() throws {
        stopper?.cancel()
        stopper = nil
        let input = engine.inputNode
        if !tapped {
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                throw NSError(domain: "anothernote.speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "no audio input"])
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.lock.lock()
                let sink = self.sink
                self.lock.unlock()
                sink?(buffer)
            }
            tapped = true
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    /// Close the microphone soon, unless a session starts meanwhile.
    func releaseSoon() {
        stopper?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        stopper = work
        DispatchQueue.main.asyncAfter(deadline: .now() + MIC_LINGER_MS / 1000, execute: work)
    }

    func stop() {
        stopper = nil
        if engine.isRunning { engine.stop() }
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
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
}

final class Session {
    let id: Int
    let continuous: Bool
    let recognizer: SFSpeechRecognizer
    let onDevice: Bool

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
    private var quietTimer: DispatchWorkItem?
    private var capTimer: DispatchWorkItem?

    init(id: Int, continuous: Bool, recognizer: SFSpeechRecognizer, onDevice: Bool) {
        self.id = id
        self.continuous = continuous
        self.recognizer = recognizer
        self.onDevice = onDevice
    }

    func begin() {
        do {
            try Microphone.shared.start()
        } catch {
            log("[speech] microphone: \(error.localizedDescription)")
            fail("audio-capture")
            return
        }
        emit(id, "audiostart")
        beginRequest()
    }

    private func beginRequest() {
        let r = Request()
        r.req.shouldReportPartialResults = true
        r.req.taskHint = .dictation
        if onDevice { r.req.requiresOnDeviceRecognition = true }
        if #available(macOS 13.0, *) { r.req.addsPunctuation = true }
        current = r
        heard = false
        quietTimer?.cancel()
        let req = r.req
        Microphone.shared.setSink { buffer in req.append(buffer) }
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
            if self.continuous || self.heard { self.closeCurrent() } else { self.fail("no-speech") }
        }
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
                // Apple ended it by itself: take it as a finished phrase.
                r.text = words.isEmpty ? r.text : words
                closeCurrent()
                return
            }
            if words != r.text {
                r.text = words
                if !heard && !words.isEmpty {
                    heard = true
                    emit(id, "speechstart")
                    if !continuous {
                        schedule(&capTimer, after: onDevice ? ONDEVICE_CAP_MS : SERVER_CAP_MS) { [weak self] in self?.closeCurrent() }
                    }
                }
                emit(id, "interim", text: inFlight())
                if !words.isEmpty {
                    schedule(&quietTimer, after: continuous ? QUIET_MS : QUESTION_QUIET_MS) { [weak self] in self?.closeCurrent() }
                }
            }
        }
        if let error = error {
            let ns = error as NSError
            if ns.code == 1110 { // no speech detected
                if continuous { r.text = ""; closeCurrent(); return }
                return fail("no-speech")
            }
            log("[speech] recogniser: \(ns.domain) \(ns.code) \(ns.localizedDescription)")
            if continuous && !r.text.isEmpty {
                closeCurrent() // keep the words in flight; a new request carries on
                return
            }
            fail("network")
        }
    }

    /// End the current request's audio and, still listening, start the next one at once.
    private func closeCurrent() {
        guard !ended, let r = current else { return }
        quietTimer?.cancel()
        capTimer?.cancel()
        current = nil
        r.req.endAudio()
        closing.append(r)
        let wait = stopping ? STOP_FINAL_WAIT_MS : FINAL_WAIT_MS
        let timer = DispatchWorkItem { [weak self, weak r] in
            guard let self = self, let r = r else { return }
            self.settle(r, r.text)
        }
        r.finalTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + wait / 1000, execute: timer)
        if continuous && !stopping { beginRequest() } else { Microphone.shared.setSink(nil) }
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
                if !final.isEmpty { emit(id, "phrase", text: final) }
            } else {
                utterance = [utterance, final].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        if !closing.isEmpty || current != nil { return }
        if !continuous || stopping { end(text: utterance) }
    }

    func stop() {
        guard !ended else { return }
        stopping = true
        if let r = current {
            if heard || !r.text.isEmpty { closeCurrent() } else { current = nil; r.task?.cancel(); Microphone.shared.setSink(nil); flush() }
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
        quietTimer?.cancel()
        capTimer?.cancel()
        Microphone.shared.setSink(nil)
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

// MARK: - Commands

enum Sessions {
    static var current: Session?
    /// Sessions aborted (or stopped) while their permission dialog was still up.
    static var cancelled = Set<Int>()

    static func start(id: Int, lang: String, continuous: Bool) {
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
            let locale = Locale(identifier: lang.isEmpty ? Locale.current.identifier : lang)
            guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
                emit(id, "error", code: "language-not-supported")
                emit(id, "end", text: "")
                return
            }
            guard recognizer.isAvailable else {
                emit(id, "error", code: "network")
                emit(id, "end", text: "")
                return
            }
            let wantsOnDevice = ProcessInfo.processInfo.environment["ANOTHERNOTES_SPEECH_ONDEVICE"] != "0"
            let onDevice = wantsOnDevice && recognizer.supportsOnDeviceRecognition
            emit(["ev": "ready", "id": id, "onDevice": onDevice, "lang": recognizer.locale.identifier])
            let session = Session(id: id, continuous: continuous, recognizer: recognizer, onDevice: onDevice)
            current = session
            emit(id, "start")
            session.begin()
        }
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
            start(id: id, lang: message["lang"] as? String ?? "", continuous: message["continuous"] as? Bool ?? false)
        case "stop":
            if let s = current, s.id == id { s.stop() } else { cancelled.insert(id) }
        case "abort":
            if let s = current, s.id == id { s.abort() } else { cancelled.insert(id) }
        default:
            log("[speech] unknown command: \(cmd)")
        }
    }
}

runDisclaimedIfNeeded()

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
