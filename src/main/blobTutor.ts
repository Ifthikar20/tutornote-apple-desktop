import { ipcMain, nativeTheme, type IpcMainEvent } from "electron";
import { APP_ORIGIN, originOf } from "./config";
import { overlayWindow } from "./screenTeach";
import { cursorTutorOf, DEFAULT_TUTOR, themeIsDark, themeOf, tutorKey, tutorLookOf, tutorName, type TutorLook } from "./tutorLook";

/*
  The tutor resting in the floating blob (companion.ts, static/blob.html) is the one that follows
  the cursor. Two ways to know it, both checked against the 14 tutors the blob has copies of
  (tutorLook.ts):
    - every page of the app says which one it is (window.anothernotes.tutorLook, called by the web
      app's lib/guide/avatars.ts tellDesktop as the page loads and when the student picks another
      tutor), with the app's theme setting;
    - the lesson's page, which draws the cursor's tutor, is read as it is drawn (its look, its
      colour, and whether the page is dark): as the blob shows, as the tutor lands back in it, and
      when another window changed the tutor or the theme (a page heard it as a storage event:
      companion:recheck). What it draws wins: it is what follows the cursor, whatever a page said
      (web b94ddfb's Settings tells the old voice's tutor before it saves the new one; web 05a65cc
      fixes that).
  Until any of that is heard, the blob keeps its own first copy: a new student's tutor, as the
  bundled web app works it out (scripts/static-tutors.mjs).
*/

let tutor: TutorLook = DEFAULT_TUTOR;
/** Whether any page has said, or the cursor's page been read (logged once even for the default). */
let heard = false;
/** The app's "theme" setting as a page last said it (null: none chosen, or none heard yet). */
let themePref: string | null = null;
/** Whether the lesson's page has a dark <html>, as it was when last read (null: no such page, or
 *  not read yet). It wins over the setting: it is how the cursor's own tutor is drawn. */
let pageDark: boolean | null = null;
let onChange: () => void = () => {};
let asking = false;
let recheck: NodeJS.Timeout | undefined;
let toldOdd = false;

/** A change heard in another window is read off the cursor's page this long after (ms), once its
 *  page has drawn it. */
const RECHECK_MS = 250;
/** How long a read of the cursor's page may take (ms); a page that does not answer is not waited on. */
const READ_MS = 2_000;

/** What the blob draws (blob:state): the copy's name once one is known, and whether it is dark. */
export function blobTutorState(): { tutor?: string; dark: boolean } {
  return { ...(heard ? { tutor: tutorKey(tutor) } : {}), dark: pageDark ?? themeIsDark(themePref, nativeTheme.shouldUseDarkColors) };
}

/** The tutor's own name, for the blob's menu ("Close Nib"). */
export const blobTutorName = (): string => tutorName(tutor);

/** A message from a page of the app itself: its own origin, in a window's top frame. Not the
 *  sign-in or offline screens (file://, which load the same bridge), nor anything framed. */
function fromAppPage(event: IpcMainEvent): boolean {
  const frame = event.senderFrame;
  if (!frame || frame.parent) return false;
  try {
    return originOf(frame.url) === APP_ORIGIN;
  } catch {
    return false;
  }
}

/** Take a tutor; true when the blob should be told again (another tutor, or the first heard). */
function take(next: TutorLook | null, how: string): boolean {
  if (!next) return false;
  const other = tutorKey(next) !== tutorKey(tutor);
  const first = !heard;
  if (other || first) console.log(`[companion] the tutor is ${tutorName(next)} (${next.base}), ${how}`);
  heard = true;
  if (other) tutor = next;
  return other || first;
}

// The cursor's tutor as the lesson's page draws it (components/screen/CompanionPointer.tsx) and
// whether that page is dark. Only plain values come back; tutorLook.ts checks them.
const READ_CURSOR = `(() => {
  const t = document.querySelector(".screen-companion-cursor .tut-char");
  const g = t && t.querySelector("radialGradient[id^='tut'], linearGradient[id^='tut']");
  return { dark: document.documentElement.classList.contains("dark"), look: t ? t.getAttribute("data-look") : null, gradient: g ? g.id : null };
})()`;

/** Read the lesson's page (the cursor's tutor and whether it is dark); the blob is told again
 *  when that changed. With no such page the pages' word and the theme setting decide. */
export async function refreshBlobTutor(): Promise<void> {
  if (asking) return;
  asking = true;
  try {
    const w = overlayWindow();
    let seen: { dark?: unknown; look?: unknown; gradient?: unknown } = {};
    if (w && !w.isDestroyed() && !w.webContents.isLoading()) {
      let timer: NodeJS.Timeout | undefined;
      const said: unknown = await Promise.race([
        w.webContents.executeJavaScript(READ_CURSOR).catch(() => null),
        new Promise((resolve) => (timer = setTimeout(() => resolve(null), READ_MS))),
      ]);
      clearTimeout(timer);
      if (typeof said === "object" && said !== null) seen = said as typeof seen;
    }
    const dark = typeof seen.dark === "boolean" ? seen.dark : null;
    let moved = dark !== pageDark;
    pageDark = dark;
    if (take(cursorTutorOf(seen.look, seen.gradient), "as the cursor shows it")) moved = true;
    if (moved) onChange();
  } finally {
    asking = false;
  }
}

/** Hear the pages; `changed` tells the blob again. */
export function installBlobTutor(changed: () => void): void {
  onChange = changed;
  // Every page of the app, as it loads and when the student picks another tutor (tellDesktop).
  ipcMain.on("companion:tutor-look", (event, value: unknown) => {
    if (!fromAppPage(event)) return;
    const theme = themeOf(typeof value === "object" && value !== null ? (value as { theme?: unknown }).theme : undefined);
    const next = tutorLookOf(value);
    if (!next && !toldOdd) {
      toldOdd = true;
      const v = (typeof value === "object" && value !== null ? value : {}) as { look?: unknown; base?: unknown };
      console.warn(`[companion] the app's pages name a tutor the blob has no copy of (${JSON.stringify([v.look, v.base])}): it stays ${tutorName(tutor)}`);
    }
    const themeMoved = theme !== themePref;
    themePref = theme;
    if (take(next, "as the app's pages say") || themeMoved) changed();
    if (themeMoved) void refreshBlobTutor();
  });
  // Another window changed the tutor or the theme: the cursor's page is read again once it has
  // drawn the change (several pages may say so at once: one read).
  ipcMain.on("companion:recheck", (event, value: unknown) => {
    if (!fromAppPage(event)) return;
    const theme = themeOf(typeof value === "object" && value !== null ? (value as { theme?: unknown }).theme : undefined);
    if (theme !== themePref) {
      themePref = theme;
      changed();
    }
    clearTimeout(recheck);
    recheck = setTimeout(() => void refreshBlobTutor(), RECHECK_MS);
  });
  // The system turned dark or light: a page that follows the system does too, and so does the blob.
  nativeTheme.on("updated", () => {
    changed();
    void refreshBlobTutor();
  });
}
