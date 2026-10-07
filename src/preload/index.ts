/// <reference lib="dom" />
import { contextBridge, ipcRenderer, webFrame } from "electron";

/*
  The bridge between the web app and the desktop shell. Deliberately tiny: the web app
  can tell it is running on the desktop (window.anothernotes is undefined in a browser)
  and which version, and it can sign in: with an email and password or a child's PIN
  (signin.ts in the main process, which checks every argument), or through the browser
  (auth.ts). Nothing else is exposed, and every call is a fixed channel. This file runs
  sandboxed, with context isolation, so the page never sees Node.
*/

const VERSION_FLAG = "--anothernotes-version=";
const versionArg = process.argv.find((arg) => arg.startsWith(VERSION_FLAG));
/* The main process has the Mac's speech helper (src/main/speech.ts): this page gets a
   SpeechRecognition of its own over it (below), and tells the web app so (speech.native). */
const nativeSpeech = process.argv.includes("--anothernotes-speech=1");

/*
  The speech bridge. A recogniser of the page (the shim below) starts a session here
  and gets its events back: start, audiostart, speechstart, interim (the words in
  flight), phrase (continuous: one finished), error (a Web Speech API code), end (and,
  for one utterance, its text). Sessions are numbered per page; the main process maps
  them to the helper's.
*/
interface SpeechEvent {
  ev: string;
  text?: string;
  code?: string;
}
const speechListeners = new Map<number, (event: SpeechEvent) => void>();
let speechRef = 0;
if (nativeSpeech) {
  ipcRenderer.on("speech:event", (_event, message: { ref?: unknown; ev?: unknown; text?: unknown; code?: unknown }) => {
    if (typeof message?.ref !== "number" || typeof message.ev !== "string") return;
    const listener = speechListeners.get(message.ref);
    if (!listener) return;
    if (message.ev === "end") speechListeners.delete(message.ref);
    listener({
      ev: message.ev,
      text: typeof message.text === "string" ? message.text : undefined,
      code: typeof message.code === "string" ? message.code : undefined,
    });
  });
}
const speechBridge = Object.freeze({
  /** The words appear as they are said, on this Mac: the web app may treat it as a browser's recogniser. */
  native: true,
  start: (lang: unknown, continuous: unknown, onEvent: (event: SpeechEvent) => void): number => {
    const ref = ++speechRef;
    speechListeners.set(ref, onEvent);
    ipcRenderer.send("speech:start", ref, typeof lang === "string" ? lang : "", continuous === true);
    return ref;
  },
  stop: (ref: unknown): void => {
    if (typeof ref === "number") ipcRenderer.send("speech:stop", ref);
  },
  abort: (ref: unknown): void => {
    if (typeof ref !== "number") return;
    speechListeners.delete(ref);
    ipcRenderer.send("speech:abort", ref);
  },
});

contextBridge.exposeInMainWorld(
  "anothernotes",
  Object.freeze({
    platform: process.platform,
    version: versionArg ? versionArg.slice(VERSION_FLAG.length) : "",
    ...(nativeSpeech ? { speech: speechBridge } : {}),
    auth: Object.freeze({
      /** Sign in with an email and password; on success the window moves to the dashboard. */
      signIn: (form: { email: string; password: string }): Promise<unknown> =>
        ipcRenderer.invoke("auth:sign-in", { email: form?.email, password: form?.password }),
      /** Sign in to a child's profile with its username and PIN. */
      signInWithPin: (form: { username: string; pin: string }): Promise<unknown> =>
        ipcRenderer.invoke("auth:sign-in-with-pin", { username: form?.username, pin: form?.pin }),
      /** Sign in through the system browser; the app comes back signed in on its own. */
      signInWithBrowser: (): Promise<void> => ipcRenderer.invoke("auth:sign-in-with-browser"),
      /** Show the app's sign-in screen in this window. */
      signInHere: (): Promise<void> => ipcRenderer.invoke("auth:sign-in-here"),
      /** Forget a browser sign-in that was started and not finished. */
      cancelBrowserSignIn: (): Promise<void> => ipcRenderer.invoke("auth:cancel-browser-sign-in"),
    }),
  }),
);

/*
  The window's tab bar sits over the content column, starting where the web app's
  sidebar ends (windows.ts). The page is the only one that knows where that is, so this
  reports it, and the sidebar's colour, whenever either changes: the sidebar resized or
  folded away, the theme or a note's sheet colour switched, another page shown. -1 means
  the page has no sidebar.
  It also reports a dialog's backdrop while one is open (a full-window layer the web app
  dims itself with), so the tab bar, which sits above the page, can be dimmed with it.
*/
function reportChrome(): void {
  let last = "";
  let timer: ReturnType<typeof setTimeout> | undefined;
  const report = (): void => {
    timer = undefined;
    const sidebar = document.querySelector('[data-sidebar="sidebar"]');
    const shell = document.querySelector(".peer ~ main");
    let right = -1;
    if (shell) {
      const box = sidebar?.getBoundingClientRect();
      right = box && box.width > 0 && box.right > 0 ? Math.round(box.right) : 0;
    }
    const painted = sidebar ?? document.body;
    const background = painted ? getComputedStyle(painted).backgroundColor : "";
    let scrim = "";
    for (const el of Array.from(document.querySelectorAll('[data-state="open"]'))) {
      const style = getComputedStyle(el);
      if (style.position !== "fixed" || /rgba\(0, 0, 0, 0\)|transparent/.test(style.backgroundColor)) continue;
      const box = el.getBoundingClientRect();
      if (box.left <= 0 && box.top <= 0 && box.right >= innerWidth - 1 && box.bottom >= innerHeight - 1) {
        scrim = style.backgroundColor;
        break;
      }
    }
    const state = { right, background, scrim, dark: document.documentElement.classList.contains("dark") };
    const key = JSON.stringify(state);
    if (key === last) return;
    last = key;
    ipcRenderer.send("chrome:layout", state);
  };
  const soon = (): void => {
    if (timer === undefined) timer = setTimeout(report, 60);
  };
  new MutationObserver(soon).observe(document.documentElement, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ["class", "style", "data-state", "data-collapsible", "data-scroll-locked", "data-an-sheet"],
  });
  window.addEventListener("resize", soon);
  document.addEventListener("transitionend", soon, true);
  report();
}

/*
  window.SpeechRecognition, over the Mac's own speech recognition. The web app's dictation
  and Teach mode drive a browser's recogniser (lib/guide/speech.ts createNativeRecognizer
  in the web repo): lang, continuous, interimResults, start/stop/abort, and the events
  start, audiostart, speechstart, result (results[i].isFinal, results[i][0].transcript,
  resultIndex), error (error: a code) and end. This is that surface, in the page's own
  world before any of its scripts run, backed by the bridge above; Chromium's own
  recogniser, which has no speech service behind it in the app, is put aside.

  Continuous: every finished phrase is one final result, kept in order, and the words in
  flight the one interim result after them. One utterance: a single result at index 0,
  interim until the utterance is done, then final, then end.
*/
if (nativeSpeech) {
  contextBridge.executeInMainWorld({
    func: () => {
      type Bridge = {
        start: (lang: string, continuous: boolean, onEvent: (event: { ev: string; text?: string; code?: string }) => void) => number;
        stop: (ref: number) => void;
        abort: (ref: number) => void;
      };
      const found = (window as unknown as { anothernotes?: { speech?: Bridge } }).anothernotes?.speech;
      if (!found) return;
      const bridge: Bridge = found;
      const result = (transcript: string, isFinal: boolean) => {
        const alternative = { transcript, confidence: isFinal ? 1 : 0.5 };
        return { 0: alternative, length: 1, isFinal, item: () => alternative };
      };
      class Recognition extends EventTarget {
        lang = "";
        continuous = false;
        interimResults = false;
        maxAlternatives = 1;
        onstart: ((e: Event) => void) | null = null;
        onaudiostart: ((e: Event) => void) | null = null;
        onsoundstart: ((e: Event) => void) | null = null;
        onspeechstart: ((e: Event) => void) | null = null;
        onspeechend: ((e: Event) => void) | null = null;
        onsoundend: ((e: Event) => void) | null = null;
        onaudioend: ((e: Event) => void) | null = null;
        onresult: ((e: Event) => void) | null = null;
        onnomatch: ((e: Event) => void) | null = null;
        onerror: ((e: Event) => void) | null = null;
        onend: ((e: Event) => void) | null = null;
        private ref: number | null = null;
        private finals: string[] = [];

        private fire(name: string, props: Record<string, unknown> = {}): void {
          const event = Object.assign(new Event(name), props);
          this.dispatchEvent(event);
          const handler = (this as unknown as Record<string, unknown>)[`on${name}`];
          if (typeof handler === "function") (handler as (e: Event) => void).call(this, event);
        }

        private results(interim: string | null) {
          const list = this.finals.map((text) => result(text, true));
          if (interim !== null) list.push(result(interim, false));
          return Object.assign(list, { item: (i: number) => list[i] });
        }

        start(): void {
          if (this.ref !== null) throw new DOMException("recognition has already started", "InvalidStateError");
          this.finals = [];
          const ref = bridge.start(this.lang || navigator.language || "en-US", !!this.continuous, (event) => this.on(ref, event));
          this.ref = ref;
        }

        private on(ref: number, event: { ev: string; text?: string; code?: string }): void {
          if (this.ref !== ref) return;
          switch (event.ev) {
            case "start":
            case "audiostart":
            case "speechstart":
              this.fire(event.ev);
              return;
            case "interim":
              if (this.interimResults) this.fire("result", { results: this.results(event.text ?? ""), resultIndex: this.finals.length });
              return;
            case "phrase":
              if (!event.text) return;
              this.finals.push(event.text);
              this.fire("result", { results: this.results(null), resultIndex: this.finals.length - 1 });
              return;
            case "error":
              this.ref = null;
              this.fire("error", { error: event.code || "network", message: "" });
              this.fire("end");
              return;
            case "end":
              this.ref = null;
              if (event.text) {
                this.finals.push(event.text);
                this.fire("result", { results: this.results(null), resultIndex: this.finals.length - 1 });
              }
              this.fire("end");
              return;
            default:
              return;
          }
        }

        stop(): void {
          if (this.ref !== null) bridge.stop(this.ref);
        }

        abort(): void {
          const ref = this.ref;
          if (ref === null) return;
          this.ref = null;
          bridge.abort(ref);
          queueMicrotask(() => {
            this.fire("error", { error: "aborted", message: "" });
            this.fire("end");
          });
        }
      }
      const w = window as unknown as Record<string, unknown>;
      w.SpeechRecognition = Recognition;
      w.webkitSpeechRecognition = Recognition;
    },
  });
}

/*
  document.cookie on the bundled web app. Chromium keeps cookies only for http(s), so on
  the app's own scheme (app://anothernotes) every cookie the web app sets is dropped, and
  the preferences it keeps there (the sidebar docked or not) reset at each launch. This
  gives the page a small cookie store in its localStorage instead, installed in the
  page's own world before any of its scripts run. The server's cookies are unaffected:
  they never reach the page (server.ts keeps them in the main process).
*/
if (location.protocol === "app:") {
  contextBridge.executeInMainWorld({
    func: () => {
      const KEY = "__anothernotes_cookies";
      type Jar = Record<string, { value: string; expires: number | null }>;
      const load = (): Jar => {
        try {
          return JSON.parse(localStorage.getItem(KEY) || "{}") as Jar;
        } catch {
          return {};
        }
      };
      const save = (jar: Jar): void => {
        try {
          localStorage.setItem(KEY, JSON.stringify(jar));
        } catch {
          /* storage full or blocked: the cookie lasts as long as the page */
        }
      };
      const live = (jar: Jar): Jar => {
        const now = Date.now();
        for (const name of Object.keys(jar)) {
          const expires = jar[name].expires;
          if (expires !== null && expires <= now) delete jar[name];
        }
        return jar;
      };
      Object.defineProperty(Document.prototype, "cookie", {
        configurable: true,
        get(): string {
          const jar = live(load());
          return Object.keys(jar)
            .map((name) => `${name}=${jar[name].value}`)
            .join("; ");
        },
        set(line: string) {
          const [pair, ...attributes] = String(line).split(";");
          const eq = pair.indexOf("=");
          if (eq <= 0) return;
          const name = pair.slice(0, eq).trim();
          const value = pair.slice(eq + 1).trim();
          let expires: number | null = null;
          for (const attribute of attributes) {
            const [key, ...rest] = attribute.split("=");
            const k = key.trim().toLowerCase();
            const v = rest.join("=").trim();
            if (k === "max-age") expires = Date.now() + Number(v) * 1000;
            else if (k === "expires" && expires === null) expires = Date.parse(v);
          }
          const jar = live(load());
          if (expires !== null && (Number.isNaN(expires) || expires <= Date.now())) delete jar[name];
          else jar[name] = { value, expires };
          save(jar);
        },
      });
    },
  });
}

/*
  Room in the web app's layout for the window's chrome, in place before the web app
  draws anything (a style added after its first paint would make the page jump). The
  selectors are the sidebar component's: its header, above whose brand block the window
  buttons sit and whose strip moves the window; its edge strip, which folds and resizes
  the sidebar and must never drag the window instead; and the content column, which
  starts below the tab bar (44px, TOOLBAR_HEIGHT in windows.ts). The column is the
  window's height less the bar: flush with the sidebar, as the web app lays it out now
  (variant "sidebar"), or less its card's bottom margin should it go back to the inset
  card it used to be.
*/
const SHELL_CSS = `
  @media (min-width: 768px) {
    .peer ~ main { margin-top: 44px !important; height: calc(100svh - 44px) !important; min-height: 0 !important; }
    .peer[data-variant="inset"] ~ main { height: calc(100svh - 44px - 0.5rem) !important; }
    [data-sidebar="header"] { padding-top: ${process.platform === "darwin" ? 40 : 8}px !important; -webkit-app-region: drag; }
    [data-sidebar="header"] :is(a, button, input, select, textarea, [role="button"], [role="combobox"], [tabindex]) {
      -webkit-app-region: no-drag;
    }
    [data-sidebar="rail"] { -webkit-app-region: no-drag; }
    /* The PDF full-page reader (web index.css .pdf-reader) fills the window; here the tab bar
       covers its top 44px, and the window buttons and the sidebar header's drag strip sit
       there too. So it starts below the bar, and it is never part of the drag strip. Its
       pages fit its own box (PdfDocument measureFit). Only in the sidebar layout, where the
       page starts at the window's top. */
    .peer ~ main .pdf-doc.pdf-reader { top: 44px !important; -webkit-app-region: no-drag; }
    .peer ~ main .pdf-reader-top { top: 44px !important; }
    .peer ~ main .pdf-reader-arrow { top: calc(50% + 22px) !important; }
    .pdf-reader-bar, .pdf-reader-arrow { -webkit-app-region: no-drag; }
  }
`;

/*
  Links routed before the page follows them. Notes and learning sessions open in tabs
  and everything else in the home page (windows.ts), so a link that leads across that
  line is handed to the app instead: a note clicked in the home page's sidebar opens in
  its tab while the home page stays as it was, and "Dashboard" clicked in a note's tab
  shows the home page while the tab keeps its note. Links within the page's own side of
  the line, and anything the page handles itself, go on as usual. The app says which
  role this page has (home, note, or a page out of sight, which routes nothing).
*/
let role = "";
ipcRenderer.on("tabs:role", (_event, value: unknown) => {
  role = typeof value === "string" ? value : "";
});

/** The note or session a path shows (the same rule as noteKey in windows.ts), or null. */
function noteOf(pathname: string): string | null {
  const where = pathname.replace(/\/+$/, "");
  const note = where.match(/^\/dashboard\/note\/([^/]+)$/);
  if (note) return note[1];
  const study = where.match(/^\/dashboard\/([^/]+)\/full-study$/);
  if (study) return study[1];
  return where === "/dashboard/full-study" ? "full-study" : null;
}

function routeLinks(): void {
  window.addEventListener(
    "click",
    (event) => {
      if (role !== "home" && role !== "note") return;
      if (event.defaultPrevented || event.button !== 0 || event.altKey || event.shiftKey) return;
      const link = (event.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!link || (link.target && link.target !== "_self") || link.hasAttribute("download")) return;
      const to = new URL(link.href, location.href);
      if (to.protocol !== location.protocol || to.host !== location.host) return;
      const there = noteOf(to.pathname);
      const here = noteOf(location.pathname);
      const elsewhere = role === "home" ? there !== null : there === null || there !== here;
      if (!elsewhere) return;
      // A link in the home page's own content (a dashboard card; the exam plan's link carries
      // router state, { plan: true }) goes through the web app's router, which keeps that
      // state, and the page then becomes the note's tab (route -> becomeTab in windows.ts),
      // as a button's navigate() does. The sidebar, its rail menus (portaled outside it) and
      // the narrow-window sheet are not in <main>, so their links are still routed here.
      if (role === "home" && link.closest("main")) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      ipcRenderer.send("nav:open", `${to.pathname}${to.search}${to.hash}`);
    },
    true,
  );
}

if (location.protocol === "app:" || location.protocol === "http:" || location.protocol === "https:") {
  webFrame.insertCSS(SHELL_CSS);
  routeLinks();
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", reportChrome);
  else reportChrome();
}

/*
  One sidebar for the window. Each tab is its own copy of the web app, which reads
  whether its sidebar is docked, and how wide it was dragged, once, as it starts; so
  when it is docked, folded or resized in one tab, the others follow. The dock lives in
  the pages' shared cookie store (the localStorage one above) and the width in their
  localStorage ("sidebar:width", ui/sidebar.tsx in the web repo): a change to either
  reaches every other page as a storage event, and a page also checks as it comes on
  screen (it may have started while the setting was changing). A page whose sidebar is
  the other way docks or folds it with the web app's own ⌘B; one whose sidebar is
  another width sets the width where the web app's own edge strip sets it, the
  --sidebar-width of its layout's wrapper. A fold follows at once; an open only as a page
  comes on screen and not while the sidebar is pinned somewhere (see followSidebar: a page
  opened out of sight folds itself again and would unpin the one in use).
*/
function followSidebar(jar: string | null, onScreen: boolean): void {
  let docked: string | undefined;
  try {
    docked = (JSON.parse(jar || "{}") as Record<string, { value?: string }>)["sidebar:docked"]?.value;
  } catch {
    return;
  }
  if (docked !== "true" && docked !== "false") return;
  const peer = document.querySelector(".peer[data-state]");
  const state = peer?.getAttribute("data-state");
  if (!state || (state === "expanded") === (docked === "true")) return;
  // This page's own edge strip is being dragged: the drag owns the sidebar until it ends.
  if (document.querySelector('[class~="group/sidebar-wrapper"]')?.hasAttribute("data-resizing")) return;
  // Pinned here (dragged to a width to stay: data-pinned, ui/sidebar.tsx): never folded from outside.
  if (docked === "false" && peer?.getAttribute("data-pinned") === "true") return;
  if (docked === "true") {
    // A sidebar opened by ⌘B is not pinned, and folds itself 3 s later (AUTO_FOLD_MS) when the
    // pointer is not in it; that fold saves docked=false and clears the pin for every page,
    // which folds the sidebar the student is using. So a page opens only as it comes on
    // screen (only the page in use writes docked=true, and a page never hears its own
    // writes), and not while another page is pinned: it keeps its rail, and a page loaded
    // later starts pinned. (Not document.visibilityState: pages playing a lesson, or about
    // to come on screen, run unthrottled and report "visible" while out of sight.)
    if (!onScreen) return;
    try {
      if (localStorage.getItem(SIDEBAR_PINNED_KEY) === "1") return;
    } catch {
      return;
    }
  }
  window.dispatchEvent(new KeyboardEvent("keydown", { key: "b", code: "KeyB", metaKey: true, bubbles: true, cancelable: true }));
}

/** The sidebar dragged to a width to stay, in any page (SIDEBAR_PINNED_KEY in ui/sidebar.tsx). */
const SIDEBAR_PINNED_KEY = "sidebar:pinned";

/** The widths the web app's edge strip allows (SIDEBAR_MIN_PX and SIDEBAR_MAX_PX in ui/sidebar.tsx). */
const SIDEBAR_WIDTH_KEY = "sidebar:width";
const SIDEBAR_WIDTH_MIN = 180;
const SIDEBAR_WIDTH_MAX = 480;

function followSidebarWidth(value: string | null): void {
  const px = Number(value);
  if (!value || !(px >= SIDEBAR_WIDTH_MIN && px <= SIDEBAR_WIDTH_MAX)) return;
  const wrapper = document.querySelector<HTMLElement>('[class~="group/sidebar-wrapper"]');
  // Not while this page's own strip is being dragged: the drag owns the width until it ends.
  if (!wrapper || wrapper.hasAttribute("data-resizing")) return;
  const width = `${Math.round(px)}px`;
  if (wrapper.style.getPropertyValue("--sidebar-width") !== width) wrapper.style.setProperty("--sidebar-width", width);
}

if (location.protocol === "app:") {
  window.addEventListener("storage", (event) => {
    if (event.key === "__anothernotes_cookies") followSidebar(event.newValue, false);
    else if (event.key === SIDEBAR_WIDTH_KEY) followSidebarWidth(event.newValue);
  });
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible") return;
    try {
      followSidebar(localStorage.getItem("__anothernotes_cookies"), true);
      followSidebarWidth(localStorage.getItem(SIDEBAR_WIDTH_KEY));
    } catch {
      /* storage blocked: the page keeps the sidebar it has */
    }
  });
}
