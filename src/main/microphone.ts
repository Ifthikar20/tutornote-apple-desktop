import { app, BrowserWindow, dialog, type MessageBoxOptions, type WebContents } from "electron";
import fs from "node:fs";
import path from "node:path";
import { appEvents } from "./events";
import { createMicConsent, type MicAnswer } from "./micConsent";

/*
  The microphone question's Electron half (micConsent.ts has the rule; WHAT_TO_FIX.md WIN-07 /
  MAC-08). The answer is kept in microphone.json in the app's profile folder (userData); the
  question is a native dialog from the main process, on the window that asked when it is on
  screen. The permission handlers (index.ts) and the Mac's own dictation (speech.ts) come here
  before the microphone; the File menu's "Allow Microphone" (menu.ts) changes the answer, and
  "microphone-changed" redraws its tick. That menu is on screen on a Mac; the Windows window has
  no menu bar, so there the answer is changed only by deleting microphone.json for now.
*/

const file = (): string => path.join(app.getPath("userData"), "microphone.json");

const consent = createMicConsent(
  {
    read: () => {
      try {
        return fs.readFileSync(file(), "utf8");
      } catch {
        return null;
      }
    },
    // Written whole, then put in place: a crash halfway leaves the answer before, never half a file.
    write: (text) => {
      const target = file();
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(`${target}.tmp`, text, "utf8");
      fs.renameSync(`${target}.tmp`, target);
    },
    now: () => new Date(),
  },
  (answer) => {
    console.log(`[permissions] microphone: ${answer}`);
    appEvents.emit("microphone-changed");
  },
);

/** The answer kept, or null before the student has given one. */
export const microphoneAnswer = (): MicAnswer | null => consent.answer();

/** A new answer, from the menu. */
export const setMicrophoneAnswer = (answer: MicAnswer): void => consent.set(answer);

async function ask(contents: WebContents | null): Promise<MicAnswer | null> {
  const owner = contents && !contents.isDestroyed() ? BrowserWindow.fromWebContents(contents) : null;
  const win = owner && !owner.isDestroyed() && owner.isVisible() ? owner : null;
  const options: MessageBoxOptions = {
    type: "question",
    buttons: ["Allow", "Don't Allow"],
    defaultId: 0,
    cancelId: 1,
    noLink: true,
    message: "Allow Tutornote to use your microphone?",
    // The File menu is on screen on a Mac only: the Windows window draws no menu bar (windows.ts).
    detail:
      process.platform === "darwin"
        ? "For dictation and talking to the tutor. You can change it later in the File menu."
        : "For dictation and talking to the tutor.",
  };
  const { response } = win ? await dialog.showMessageBox(win, options) : await dialog.showMessageBox(options);
  return response === 0 ? "allow" : "deny";
}

/** Whether the page in `contents` may use the microphone now: by the answer kept, else by the
 *  student's, asked once (requests while the question is up share it). */
export const microphoneAllowed = (contents: WebContents | null): Promise<boolean> => consent.allowed(() => ask(contents));
