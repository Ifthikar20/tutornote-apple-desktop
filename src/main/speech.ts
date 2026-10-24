import { app, ipcMain, type IpcMainEvent, type WebContents } from "electron";
import { spawn, type ChildProcessByStdio } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import readline from "node:readline";
import type { Readable, Writable } from "node:stream";
import { APP_ORIGIN } from "./config";

/*
  Speech recognition on the Mac itself. Electron's Chromium has the Web Speech API but
  not Google's service behind it, so in the app the web app used to record clips and
  send them to the server's whisper: the first words took many seconds to show, and a
  busy server a minute. Now a page's SpeechRecognition (the preload's shim, src/preload/
  index.ts) comes here, and here it is Apple's Speech framework, in a helper process of
  ours (helpers/speech/main.swift, built by scripts/build-speech-helper.sh): on-device
  where the language's model is installed, so the words appear as they are said.

  One helper serves every page, started when the first recogniser starts and kept for
  the app's life (it closes the microphone itself a few seconds after the last session).
  Each recogniser is a session: the page's own number (`ref`, per page) maps to the
  helper's id. The helper's events go back to the page that owns the session; the
  helper dying hands every open session a "network" error, which the web app treats as
  a hiccup (a new recogniser, or the recorder).

  No helper (not macOS, not built, not in the bundle): nothing is installed, the preload
  gets no --anothernotes-speech flag, and the web app records for the server as before.
*/

const HELPER = "tutornote-speech";

export function speechHelperPath(): string | null {
  if (process.platform !== "darwin") return null;
  const candidates = app.isPackaged
    ? [path.join(process.resourcesPath, HELPER)]
    : [path.join(app.getAppPath(), "build", "helpers", HELPER)];
  return candidates.find((file) => existsSync(file)) ?? null;
}

export const nativeSpeechAvailable = (): boolean => speechHelperPath() !== null;

type Helper = ChildProcessByStdio<Writable, Readable, Readable>;

interface Session {
  id: number;
  ref: number;
  sender: WebContents;
}

interface HelperEvent {
  id?: unknown;
  ev?: unknown;
  text?: unknown;
  code?: unknown;
  onDevice?: unknown;
  lang?: unknown;
}

let helper: Helper | null = null;
let nextId = 1;
const sessions = new Map<number, Session>();

function tell(session: Session, ev: string, extra: { text?: string; code?: string } = {}): void {
  if (!session.sender.isDestroyed()) session.sender.send("speech:event", { ref: session.ref, ev, ...extra });
}

/** The session is over, whatever ended it. */
function drop(session: Session): void {
  sessions.delete(session.id);
}

function command(message: Record<string, unknown>): void {
  helper?.stdin.write(`${JSON.stringify(message)}\n`);
}

function onLine(line: string): void {
  let msg: HelperEvent;
  try {
    msg = JSON.parse(line) as HelperEvent;
  } catch {
    console.warn(`[speech] ${line}`);
    return;
  }
  const ev = typeof msg.ev === "string" ? msg.ev : "";
  if (ev === "ready") {
    console.log(`[speech] ${msg.onDevice ? "on this Mac" : "Apple's server"} (${String(msg.lang ?? "")})`);
    return;
  }
  const session = typeof msg.id === "number" ? sessions.get(msg.id) : undefined;
  if (!session) return;
  const text = typeof msg.text === "string" ? msg.text : undefined;
  const code = typeof msg.code === "string" ? msg.code : undefined;
  if (ev === "end") drop(session);
  tell(session, ev, { text, code });
}

function helperGone(why: string): void {
  console.warn(`[speech] helper ${why}`);
  for (const session of [...sessions.values()]) {
    drop(session);
    tell(session, "error", { code: "network" });
    tell(session, "end", { text: "" });
  }
}

function ensureHelper(): Helper | null {
  if (helper) return helper;
  const file = speechHelperPath();
  if (!file) return null;
  let child: Helper;
  try {
    child = spawn(file, [], { stdio: ["pipe", "pipe", "pipe"] });
  } catch (e) {
    console.warn(`[speech] could not start the helper: ${(e as Error).message}`);
    return null;
  }
  helper = child;
  readline.createInterface({ input: child.stdout }).on("line", onLine);
  readline.createInterface({ input: child.stderr }).on("line", (line) => console.warn(line));
  child.stdin.on("error", () => undefined);
  child.on("error", (e) => {
    if (helper === child) helper = null;
    helperGone(`failed: ${e.message}`);
  });
  child.on("exit", (code, signal) => {
    if (helper === child) helper = null;
    helperGone(`exited (${signal ?? code})`);
  });
  console.log(`[speech] helper ${file}`);
  return child;
}

function trusted(event: IpcMainEvent): boolean {
  const url = event.senderFrame?.url ?? "";
  return url === APP_ORIGIN || url.startsWith(`${APP_ORIGIN}/`);
}

function sessionOf(sender: WebContents, ref: number): Session | undefined {
  for (const session of sessions.values()) {
    if (session.sender === sender && session.ref === ref) return session;
  }
  return undefined;
}

/** The pages' recognisers (speech:start / stop / abort), when this Mac has the helper. */
export function installSpeech(): void {
  if (!nativeSpeechAvailable()) return;
  const watched = new WeakSet<WebContents>();

  ipcMain.on("speech:start", (event, ref: unknown, lang: unknown, continuous: unknown) => {
    if (!trusted(event) || typeof ref !== "number") return;
    const sender = event.sender;
    const fail = (code: string): void => {
      sender.send("speech:event", { ref, ev: "error", code });
      sender.send("speech:event", { ref, ev: "end", text: "" });
    };
    const child = ensureHelper();
    if (!child) return fail("network");
    // A page restarting a recogniser reuses no ref; an old one with this ref is gone.
    const old = sessionOf(sender, ref);
    if (old) {
      drop(old);
      command({ cmd: "abort", id: old.id });
    }
    const session: Session = { id: nextId++, ref, sender };
    sessions.set(session.id, session);
    if (!watched.has(sender)) {
      watched.add(sender);
      // The page going (a tab closed, a reload, another page loaded in its place) must
      // not leave the microphone open: its recognisers go with it.
      const abandon = (): void => {
        for (const s of [...sessions.values()]) {
          if (s.sender !== sender) continue;
          drop(s);
          command({ cmd: "abort", id: s.id });
        }
      };
      sender.once("destroyed", abandon);
      sender.on("did-start-navigation", (details) => {
        if (details.isMainFrame && !details.isSameDocument) abandon();
      });
    }
    command({
      cmd: "start",
      id: session.id,
      lang: typeof lang === "string" ? lang.slice(0, 32) : "",
      continuous: continuous === true,
    });
  });

  ipcMain.on("speech:stop", (event, ref: unknown) => {
    if (!trusted(event) || typeof ref !== "number") return;
    const session = sessionOf(event.sender, ref);
    if (session) command({ cmd: "stop", id: session.id });
  });

  ipcMain.on("speech:abort", (event, ref: unknown) => {
    if (!trusted(event) || typeof ref !== "number") return;
    const session = sessionOf(event.sender, ref);
    if (!session) return;
    drop(session);
    command({ cmd: "abort", id: session.id });
  });

  app.on("will-quit", () => {
    const child = helper;
    helper = null;
    if (child) {
      child.stdin.end();
      setTimeout(() => child.kill(), 500).unref();
    }
  });
}
