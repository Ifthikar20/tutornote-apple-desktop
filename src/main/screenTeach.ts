import {
  app,
  BaseWindow,
  BrowserWindow,
  clipboard,
  ClipboardItem,
  globalShortcut,
  ipcMain,
  Menu,
  screen,
  shell,
  WebContentsView,
  type BaseWindowConstructorOptions,
  type BrowserWindowConstructorOptions,
  type ContextMenuParams,
  type Display,
  type MenuItemConstructorOptions,
  type Rectangle,
  type WebContents,
} from "electron";
import { execFile } from "node:child_process";
import path from "node:path";
import {
  BOARD_COPY,
  boardMoveOf,
  boardPlaceFor,
  clampBoardZoom,
  coversReading,
  fullScreenFrame,
  leavesTab,
  mainCanHold,
  type BoardPlace,
  type BoardPrefs,
  type BoardWhere,
  type Reading,
} from "./boardHost";
import { boardStateOf, BOARD_MIN, opaqueColor, placeBoard, textBox } from "./boardPlace";
import { selectionKept, tapNumbers } from "./companionPlace";
import { APP_ORIGIN, originOf } from "./config";
import { appEvents } from "./events";
import { openExternal } from "./links";
import { watchLessonAudio } from "./media";
import {
  accessibilityAllowed,
  chordWatch,
  readWindow,
  ScreenReadError,
  turnWindow,
  unwatchWindow,
  watchEvents,
  watchWindow,
  type ScreenChord,
  type ScreenPress,
  type ScreenRead,
  type ScreenScroll,
  type ScreenTap,
  type ScreenTurn,
} from "./screen";
import { nativeSpeechAvailable } from "./speech";
import { loadBoardPrefs, loadScreenBoard, saveBoardPrefs, saveScreenBoard } from "./store";
import {
  boardTabActive,
  boardTabDocked,
  bringMainForward,
  dockBoardView,
  getMainWindow,
  hideBoardTab,
  mainWindowLook,
  navigateTo,
  selectBoardTab,
  setBoardTabInfo,
  showBoardTab,
  undockBoardView,
} from "./windows";

/*
  Teach mode over another app's window ("screen teach"). Once a pick has been read
  (explain.ts), the web app's own Teach mode runs over the window that was read: one
  see-through window over that display's work area (not under the Dock or the menu bar, which
  macOS draws above it, so the lesson's own dock and chip never sit under them) loads the web
  app's /dashboard/screen-teach page,
  with the preload's screenTeach bridge (src/preload/index.ts). The page lays the words
  out as a stand-in page and teaches it with the same pointer, marks, caption, voice and
  board as a PDF in the app. When it has taught what is on screen it asks here to turn
  the other app's page (or scroll it), and gets that window read again.

  The window lets every click through to the app below, except over the page's own
  controls (the board, the dock), which the page reports as the pointer moves over them.
  It is kept, hidden, between lessons, so the next pick starts at once: a new pick sends
  it a new start, and anything about an older start (its run) is ignored.

  Every rectangle the page is sent, or sends, is in its own CSS pixels: screen points less
  the window's top left (its zoom stays at 1). The shapes mirror the web app's
  src/lib/screen/types.ts.

  explain.ts hears about the lesson through appEvents: "screen-teach-started" (the lesson
  is on screen: its status panel goes), "screen-teach-closed", and "screen-teach-failed"
  (with the words to show in that panel).

  Companion mode (companion.ts, the tutor that trails the cursor over any app): the same window
  stays up for as long as the tutor is on, lesson or not, over the work area of the display the
  cursor is on (the lesson's, while one runs). It never takes the keys then (focusable false),
  except while the page asks for them (a question typed to the tutor: want-keys), so the
  student's arrow keys stay with the app being read. A lesson ending or the student going to
  another app no longer hides it: the lesson's own marks and dock step aside in the page
  (screen-teach:aside), and the tutor goes on following the cursor. companion.ts hears of every
  accurate read of the lesson's window ("screen-teach-read"), to keep its glance of that window
  current, and that the window is gone ("screen-teach-gone").
*/

type Point = { x: number; y: number };
type Rect = { x: number; y: number; w: number; h: number };

type ScreenMode = "scroll" | "page";
type ScreenCommand = "toggle-play" | "next" | "prev" | "close" | "pause" | "resume";

/** What the student picked on the companion's card: explain from there, or ask a question. */
type ScreenChoice = "explain" | "ask";

interface ScreenStart {
  run: number;
  overlay: Rect;
  read: ScreenRead;
  click: Point;
  canTurn: boolean;
  mode: ScreenMode;
  /** Companion mode: the card's pick that started this run. */
  choice?: ScreenChoice;
  /** A later run of one companion session: no greeting, no start sound. */
  quiet?: boolean;
  /** Started by the companion (the overlay stays up between lessons). */
  companion?: boolean;
  /** How bright the page read is, 0 to 1 (ScreenRead.ground): the marks' palette. */
  ground?: number;
  /** Companion mode: the words of the row the student tapped, as the page read them (the card's
   *  pick), so the page can find that row in this read when the two disagree at a boundary. */
  row?: string;
  /** The window scrolled or changed since this read was taken at the tap: the page starts from it
   *  and reads the window again once the lesson is up. */
  stale?: true;
}

/** How a lesson was asked for: by the companion's card (companion.ts), or by a pick. */
export interface ScreenTeachOptions {
  choice?: ScreenChoice;
  quiet?: boolean;
  companion?: boolean;
  row?: string;
  stale?: boolean;
}

/** What the page is told of the companion (screen-teach:companion): on or off; the overlay's own
 *  rectangle in screen points; where the tutor hops out from (the blob), or flies home to, in the
 *  overlay's points; and whether this is the first time ever (its tip). */
interface CompanionMessage {
  on: boolean;
  overlay: Rect;
  from?: Point;
  first: boolean;
  to?: Point;
}

interface ScreenTurnRequest {
  run: number;
  dir: "forward" | "back";
  scrollBy: number;
  pages: number;
  at: Point;
  how: "auto" | "manual";
  unlessMoved: boolean;
}

type ScreenTurnResult =
  | { ok: true; how: "scroll" | "key" | "manual"; mode: ScreenMode; read: ScreenRead; canTurn?: boolean }
  | { ok: false; reason: "end" | "stuck" | "no_access" | "no_permission" | "window_gone" | "failed" | "stale" };

/** A way of moving the app on: scrolling, or a key (forward; back is its opposite). */
type Way = { how: "scroll" } | { how: "key"; key: "right" | "pagedown" };

const ROUTE = "/dashboard/screen-teach";
/** Apps that turn whole pages (Kindle, Books). Any other app is taken to scroll until a turn shows otherwise. */
const PAGE_APPS = new Set(["com.amazon.Lassen", "com.apple.iBooksX"]);
const SETTINGS_URLS = {
  screen: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
  accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
};
const BACK_KEY = { right: "left", pagedown: "pageup" } as const;
/** How long a way not yet seen to work is given to change the window, and the one that has. */
const TRY_TIMEOUT_MS = 2_500;
const TURN_TIMEOUT_MS = 4_000;
/** The helper presses a key this often when it presses it more than once. */
const KEY_GAP_MS = 250;
/** The student turning the page themselves: as long as they like, within reason. */
const MANUAL_WAIT_MS = 180_000;
/** The page says it is ready within this long, or the lesson is given up. */
const READY_TIMEOUT_MS = 20_000;
/** A scroll the page gave no distance for. */
const DEFAULT_SCROLL = 600;
/** While a lesson is on screen, from any app. */
const SHORTCUTS: ReadonlyArray<[string, ScreenCommand]> = [
  ["Control+Alt+Space", "toggle-play"],
  ["Control+Alt+Right", "next"],
  ["Control+Alt+Left", "prev"],
];
/** The talk key, from any app, while a lesson is on screen and while the companion is on without
 *  one (its dock's mic starts a lesson there). The student's way in is Control and Option on their
 *  own (the talk chord, screen.ts chordWatch, watched exactly while this is registered): a tap asks
 *  one question, a 5 s hold turns talk mode on (screen-teach:chord, the page decides). ⌃⌥M stays as
 *  the way in where the chord cannot be (VoiceOver owns Control and Option, a helper that cannot
 *  see the modifier keys, a page older than the chord), and it means a TAP of the mic now, never
 *  talk mode by itself: a one question mic, an interrupt, or talk mode off, as the page's tap rule
 *  says (a page older than this round still takes it as its old toggle).
 *  Its own channel (screen-teach:talk), not a ScreenCommand: a page older than it would take an
 *  unknown command for a key. */
const TALK_SHORTCUT = "Control+Alt+M";
/** A chord "tap" this soon after ⌃⌥M is that key's Control and Option let go, not a tap of its
 *  own (the helper sees the M and spoils the chord itself; this is in case it ever cannot). */
const TALK_KEY_CHORD_MS = 400;

interface Lesson {
  run: number;
  window: number;
  pid: number;
  app: string;
  /** The read app's bundle id ("" when it had none): Back to {app} opens it. */
  bundle: string;
  mode: ScreenMode;
  /** The first way that moved the window in this run, kept for the rest of it. */
  way: Way | null;
  /**
   * One turn or read of the window at a time: two at once would post into each other.
   * Per lesson, so a new pick never waits behind the last one's turn (a student's own,
   * waited on for minutes).
   */
  queue: Promise<unknown>;
  /** The wait for the student's own turn going on, if any: given up when the lesson ends, and
   *  for the page's next request (the lesson has moved on, back to a page read already). */
  waiting: AbortController | null;
  /** The window read and its words (screen points), as of its latest read: where the board
   *  goes beside them (placeBoardFor). */
  frame: Rect;
  text: Rect | null;
  /** Its lines (screen points), as of its latest read: a tap on none of them was on no words. */
  lines: ReadonlyArray<Rect>;
  /** Its title, as of its latest read: a browser's window showing a PDF ends in ".pdf", where a
   *  double click on a word is the student's (onTap, companionPlace.ts selectionKept). */
  title: string;
  /** When its last turn ended (Date.now(), 0 before any): a read of the window begun before then
   *  shows it as it was, and the helper says no new look while a lesson's own turn goes on. */
  turnedAt: number;
}

let win: BrowserWindow | null = null;
/** The page in the window has asked for its start since it last loaded. */
let pageReady = false;
let readyTimer: NodeJS.Timeout | undefined;
let runs = 0;
let lesson: Lesson | null = null;
/** What the page is to run: sent with each pick, and given again whenever it asks (a reload). */
let pending: ScreenStart | null = null;
/** The page asked for clicks (the pointer is over one of its controls). */
let interactive = false;
/** Scrolls in flight: they must reach the app below even over the page's controls. */
let scrolling = 0;
/** What the window was last told (setIgnoreMouseEvents). */
let ignoring = true;
/** The lesson is hidden (and paused) because the student is in another app (watchEvents "front"). */
let aside = false;
/** Companion mode (companion.ts), while the tutor is on: the work area the window covers, and
 *  what the page is to be told (sent again whenever the page asks: companion-state). */
let companion: { on: boolean; work: Rectangle; message: CompanionMessage } | null = null;
/** The page has asked for the companion's state since it last loaded: it listens for it. */
let pageAsked = false;
/** The last press the helper heard (companion mode), and whether the page had the clicks then:
 *  a press on its card or its dock was its own, and so is the tap that follows a moment later,
 *  whatever the page has said since (the card closes as it is clicked). */
let lastPress: { at: number; page: boolean } | null = null;
/** A tap comes at most this long after its press. */
const PRESS_TAP_MS = 2_000;
/** When the lesson's window last took or gave up the keys (want-keys), and how long another
 *  window of Tutornote's taking them then is that, not the student going to it (onOwnFocus). */
let keysMovedAt = 0;
const KEYS_MOVED_MS = 300;
/** The talk key is wanted (registerTalkKey, whether macOS gave it or another app has it), and so
 *  the talk chord is watched; and when ⌃⌥M was last pressed (Date.now(), 0 never). */
let talkKeyOn = false;
let lastTalkKeyAt = 0;
/*
  The companion's card, in screen points, as the page last said after painting it
  (screen-teach:card-box), or null with no card up. The page asks for the clicks itself as the
  pointer comes over one of its controls (screen-teach:interactive), but it hears where the
  pointer is only from its own mouse moves or the cursor fed to it, up to a few hundred
  milliseconds late on a card that has just appeared under a still pointer: a click there would
  fall through to the app below. So while a card is up this side reads the cursor itself every
  CARD_WATCH_MS, and the window takes the clicks whenever it is over the card (grown by CARD_SLACK
  on every side), whatever the page has said yet (applyMouse).
*/
let cardBox: Rect | null = null;
/** The cursor is over the card now (cardBox), as last read. */
let overCard = false;
let cardWatch: NodeJS.Timeout | undefined;
const CARD_WATCH_MS = 16;
const CARD_SLACK = 4;
/*
  The last Accessibility answer (accessibilityAllowed(false)), and when. A companion pick within
  AX_KEEP_MS of it starts its lesson with that answer instead of waiting on the helper for a new
  one (a round trip on every pick), and asks again behind the lesson. Allow turning and the tutor
  going off forget it.
*/
let axAnswer: { allowed: boolean; at: number } | null = null;
const AX_KEEP_MS = 60_000;
/*
  The companion's careful read of a window (companion.ts carefulReadOf, given here by
  useCarefulReads, so this module imports nothing of it): with the tutor on, a tap on the lesson's
  window off the words it has read starts one at its release, in the accurate pass a restart from
  that tap (restartAt) would read the window in again. Vision reads one picture at a time, so a
  second read would wait for the first: the restart takes that one instead when it was begun
  within TAP_READ_FRESH_MS before the page asked, after the lesson's last turn ended, and the
  window has not scrolled or changed since. Without the tutor, none.
*/
let carefulRead: (window: number, since: number) => Promise<ScreenRead> | null = () => null;
const TAP_READ_FRESH_MS = 2_000;

/*
  The lesson's board in a window of its own: a real Mac window, with its own traffic lights,
  that the student can move and resize beside the app being read. The page opens it itself,
  empty and hidden, when it loads (window.open("", BOARD_FRAME)), and draws GuideBoard into it
  from its own document, so the board's state stays with the lesson. That is the one popup the
  page may open (ensureWindow). The page says what the board is to do (screen-teach:board): shown
  or not, zoomed or not, and its colour. This side owns the window itself: its chrome, its
  place, showing and hiding it with the lesson (syncBoard), and its red light, which hides it and
  tells the page (screen-teach:board-control), as the board's own close does.
  The popup's page (the guest) is not given a window of Electron's making: it is taken as it is
  made (createWindow) into a view of a window of this module's own (the host, a BaseWindow), so the
  same page, with everything on it, can be moved into another window without a reload.
  It has two homes. Its own window, as above (place "float"), or a Board tab of Tutornote's main
  window (place "tab"): windows.ts holds the tab's slot, and tells this module through appEvents
  what the student does with the tab. Where it goes is decided once per lesson run, at the run's
  first drawing (decide, boardHost.ts boardPlaceFor): the tab when the main window is there to hold
  it and lies clear of what is read, else its own window; Pop out keeps it in its own window until
  the student chooses Open in Tutornote. Before each move the board's page is marked with its place
  (data-board-place), so its head never drags the main window. The page hears where its board is
  (screen-teach:board-place) once it has asked (screen-teach:board-place-now): a page that never
  asks is older than the tab, and its board only ever floats.
  A Mac app older than this has no such bridge, and a page that cannot open the window draws
  the board in the lesson's window, as before.
*/
const BOARD_FRAME = "tutornote-board";
/** The board: the page the lesson opened (its contents, in its view), the window it floats in, and
 *  where it is now. */
interface Board {
  contents: WebContents;
  view: WebContentsView;
  host: BaseWindow;
  place: BoardWhere;
}
let board: Board | null = null;
/** The student's choices for the board (screen-board.json): read at install, saved as they change. */
let prefs: BoardPrefs = { place: "tab", zoom: 0 };
/** The run whose first drawing chose the board's place. */
let decidedRun = -1;
/** The Board tab is in the bar for this lesson (the board in it, or away in its own window). */
let inBar = false;
/** The board was up at the last syncBoard. */
let boardUp = false;
/** Something new went up on the board (a new `drawn`) since the last syncBoard. */
let freshDrawing = false;
let lastDrawn: { run: number; drawn: number } | null = null;
/** The page loaded now has asked screen-teach:board-place-now: it knows tabs (an older one never asks). */
let pageKnowsPlace = false;
/** The lesson is aside because Tutornote, on the Board tab, covers what is read. */
let covering = false;
/** The main window was last put in front (showInactive, or its focus), and no other app since. */
let mainOnTop = false;
/** What the page was last told of the board's place, and what the Window menu last showed. */
let lastPlaceSent = "";
let lastMenuPlace: BoardWhere | null = null;
/** The board page's title, for its tab and its window. */
let boardTitleNow = "Board";
/** The host is unmaximized as the board moves into its tab: that tells the page nothing. */
let quietZoom = false;
/** The move into the tab in flight (its number), or 0: the board's page is being marked first. */
let docking = 0;
let dockings = 0;
let mainFocusTimer: NodeJS.Timeout | undefined;
let mainBlurTimer: NodeJS.Timeout | undefined;
/** A focus change of the main window is judged this long after it (a tab bar click selects a tab
 *  just after the window takes the keys), its blur this long after; a page is marked for a move
 *  within this long, or moved anyway. */
const MAIN_FOCUS_SETTLE_MS = 120;
const MAIN_BLUR_SETTLE_MS = 150;
const MARK_TIMEOUT_MS = 300;
/** The page's last word on the board: something is on it (shown), and it is zoomed (full). */
let boardWanted = false;
let boardFull = false;
/** The run that said so: an older lesson's board never shows over this one. */
let boardRun = -1;
/** The run the board was last placed for: it is placed once per lesson, then left where it is. */
let placedRun = -1;
/** The board's own colour (the page's card colour), behind it while it loads and resizes. */
let boardColor = "#ffffff";
/** ⌘Q: the board's close goes ahead then, as every window's does (windows.ts does the same). */
let quitting = false;
app.on("before-quit", () => {
  quitting = true;
});
/** When a scroll over the board was last left out (logged once in a while, not per wheel tick). */
let scrollDropLogged = 0;
/** What the board's window was last told (setIgnoreMouseEvents): its own, as it takes every click
 *  of its own but while a scroll is posted (applyMouse). */
let boardIgnoring = false;
/*
  Where the board's window was a moment ago. The helper sends a tap only once the button is up and
  it has taken a picture of the window read (helpers/screen/main.swift, installWatch): by then the
  click may have hidden the board (its red light) or changed its size (Make smaller, the green
  light), and the point pressed is no longer on it. A tap where the board showed within
  BOARD_LEFT_MS is the board's all the same (onTap), never a move of the lesson.
*/
const BOARD_LEFT_MS = 1_000;
let boardWas: Array<{ bounds: Rectangle; until: number }> = [];
/** The board's bounds as last seen: what a move or resize of it has just left. */
let boardAt: Rectangle | null = null;
/*
  The student closed the board (closeBoardHere) a moment ago, and the page has not said since that
  it is down. A page whose board was zoomed answers the close with its own change of size, sent at
  once with the board still up (its sender keeps a hide back for BOARD_HIDE_GRACE_MS, 700 ms, in the
  web app's boardWindow.ts), and that would bring the empty board straight back. So for
  CLOSE_HOLD_MS, or until the page says show: false, a show for that run is kept (boardWanted) but
  not acted on (syncBoard); when the hold is over, the board comes up if something is on it by then.
*/
const CLOSE_HOLD_MS = 1_200;
let closeHold: { run: number; timer: NodeJS.Timeout } | null = null;

const live = (): BrowserWindow | null => (win && !win.isDestroyed() ? win : null);
const liveBoard = (): Board | null => (board && !board.contents.isDestroyed() && !board.host.isDestroyed() ? board : null);

const fromLesson = (event: { sender: WebContents }): boolean => {
  const w = live();
  return Boolean(w && event.sender === w.webContents);
};

/** Clicks reach the page only where it asked for them (or over the companion's card: cardBox), and
 *  never while a scroll is posted below it. Nor the board's window while one is: the lesson's own
 *  turn posts its wheel at a point (or the pointer's) that the board can lie over, beside the words,
 *  over their right edge or zoomed over them all, and the wheel must reach the app being read, not
 *  scroll the board. */
function applyMouse(): void {
  const b = liveBoard();
  const boardIgnore = scrolling > 0;
  // (only its own window: never the main window, with the board in a tab of it)
  if (b && b.place === "float" && boardIgnore !== boardIgnoring) {
    boardIgnoring = boardIgnore;
    b.host.setIgnoreMouseEvents(boardIgnore);
  }
  const w = live();
  const ignore = !((interactive || overCard) && scrolling === 0);
  if (!w || ignore === ignoring) return;
  ignoring = ignore;
  w.setIgnoreMouseEvents(ignore, { forward: true });
}

/** The companion's card is up at `box` (screen points), or no longer (null): the cursor is read
 *  every CARD_WATCH_MS while it is, and the window takes the clicks over it (applyMouse). */
function setCardBox(box: Rect | null): void {
  cardBox = box;
  clearInterval(cardWatch);
  cardWatch = undefined;
  if (box) {
    cardWatch = setInterval(watchCard, CARD_WATCH_MS);
    watchCard();
  } else if (overCard) {
    overCard = false;
    applyMouse();
  }
}

function watchCard(): void {
  const box = cardBox;
  if (!box) return;
  const p = screen.getCursorScreenPoint();
  const over =
    p.x >= box.x - CARD_SLACK && p.x <= box.x + box.w + CARD_SLACK && p.y >= box.y - CARD_SLACK && p.y <= box.y + box.h + CARD_SLACK;
  if (over === overCard) return;
  overCard = over;
  applyMouse();
}

/** Whether Accessibility lets the helper turn pages now, asked of it; the answer is kept for the
 *  next companion pick (axAnswer). */
async function turningAllowed(): Promise<boolean> {
  const allowed = await accessibilityAllowed(false);
  axAnswer = { allowed, at: Date.now() };
  return allowed;
}

/** A read in the window's own coordinates: every box less its top left. */
function toLocal(read: ScreenRead, origin: Point): ScreenRead {
  const shift = <T extends Point>(box: T): T => ({ ...box, x: box.x - origin.x, y: box.y - origin.y });
  return {
    app: read.app,
    bundle: read.bundle,
    title: read.title,
    window: read.window,
    pid: read.pid,
    frame: shift(read.frame),
    lines: read.lines.map((line) => (line.words ? { ...shift(line), words: line.words.map(shift) } : shift(line))),
    captureMs: read.captureMs,
    ocrMs: read.ocrMs,
    ...(typeof read.ground === "number" && Number.isFinite(read.ground) ? { ground: read.ground } : {}),
    ...(read.level ? { level: read.level } : {}),
  };
}

/** A fresh read of the lesson's window: where the board goes from now on. */
function noteRead(current: Lesson, read: ScreenRead): void {
  current.frame = read.frame;
  current.text = textBox(read.lines);
  current.lines = read.lines;
  current.title = read.title;
  // (whether Tutornote's window covers them may have changed: a board in its tab there, with the
  // student in the app being read, moves out beside them)
  const b = liveBoard();
  if (b && lesson === current && boardTabDocked() && leaveCoveredTab(b, current)) syncBoard();
  else sendPlace();
}

/*
  The board's window. Hidden until syncBoard shows it, and never shown with show() or focused
  from here: showInactive leaves the app being read in front (its menu bar stays), so nothing
  pauses because the board came up. Its first click counts (acceptFirstMouse), so a button on it
  works at once.
  It floats at the "floating" level, under the lesson's window (+1): the pointer, the caption and
  the lesson's dock still draw over it. Full screen would take it to a Space of its own, away from
  the app being read: the green light zooms it to the work area instead (fullscreenable: false).
  Minimizing it to the Dock would leave the lesson drawing on a board nobody sees, so the yellow
  light is off. Its x, y, width and height from window.open are ignored by Electron anyway:
  placeBoardFor places it.
  The page in it (the guest) has the lesson window's web preferences, which an about:blank popup
  takes as they are (context isolation, the sandbox, the preload): every call of the lesson's
  bridge checks it comes from the lesson's own window (fromLesson), so the board's copy of the
  bridge can do nothing.
*/
function hostOptions(): BaseWindowConstructorOptions {
  return {
    show: false,
    title: "Board",
    width: 620,
    height: 640,
    minWidth: BOARD_MIN.width,
    minHeight: BOARD_MIN.height,
    // The real traffic lights in the board's own 38 px head (its .guide-board-head).
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 14, y: 12 },
    resizable: true,
    movable: true,
    minimizable: false,
    maximizable: true,
    fullscreenable: false,
    acceptFirstMouse: true,
    hasShadow: true,
    backgroundColor: boardColor,
  };
}

/** The view fills its window's content (after every move into it: a view keeps the bounds it had). */
function fitHost(b: Board): void {
  const [width, height] = b.host.getContentSize();
  b.view.setBounds({ x: 0, y: 0, width, height });
}

/** The page the lesson's page just opened (createWindow): Electron wants that same page back. Only
 *  the board, from the lesson's own window, and one at a time: anything else is closed at once. */
function adoptBoard(opener: BrowserWindow, options: BrowserWindowConstructorOptions): WebContents {
  const contents = (options as { webContents: WebContents }).webContents;
  if (win !== opener || liveBoard()) {
    console.warn("[screen-teach] board window refused");
    setImmediate(() => {
      if (!contents.isDestroyed()) contents.close();
    });
    return contents;
  }
  const view = new WebContentsView({ webContents: contents });
  view.setBackgroundColor(boardColor);
  const host = new BaseWindow(hostOptions());
  host.contentView.addChildView(view);
  const b: Board = { contents, view, host, place: "float" };
  board = b;
  boardTitleNow = "Board";
  fitHost(b);
  host.on("resize", () => {
    if (board === b && b.place === "float") fitHost(b);
  });
  boardAt = host.getBounds();
  // A new window takes clicks; one made while a scroll is posted lets them through at once.
  boardIgnoring = false;
  applyMouse();
  host.setAlwaysOnTop(true, "floating", 0);
  // Over a full-screen app's Space too, as the lesson's window (ensureWindow says what that costs:
  // once per window, and the board is kept for the lesson window's life).
  host.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  contents.setZoomMode("isolated");
  // (the student's text size for the board, View > Zoom In: menu.ts)
  contents.setZoomLevel(prefs.zoom);
  // The lesson draws on it while the app being read is in front: a popup's page does not take
  // its opener's backgroundThrottling.
  contents.setBackgroundThrottling(false);
  contents.on("will-navigate", (event) => event.preventDefault());
  // A source link on the board opens in the browser, as links do from the app's tabs; nothing
  // from the web opens inside the app.
  contents.setWindowOpenHandler(({ url }) => {
    openExternal(url);
    return { action: "deny" };
  });
  watchLessonAudio(contents);
  // The page names the board (its document's title): the window's title, for the Window menu and
  // Mission Control, and its tab's.
  contents.on("page-title-updated", (_event, title) => {
    boardTitleNow = title.slice(0, 120) || "Board";
    host.setTitle(boardTitleNow);
    setBoardTabInfo({ title: boardTitleNow });
  });
  contents.on("context-menu", (_event, params) => showBoardMenu(contents, params));
  // The board's own reset follows its page: a closed host leaves the page alive, and the page goes
  // with the lesson's window.
  contents.once("destroyed", () => {
    if (board === b) dropBoardState(b);
  });

  // Where the student leaves it, and its size, are kept for the next lesson: only after a move or
  // resize of their own (will-move and will-resize are only for those; placeBoardFor's are not),
  // and not its zoomed size.
  let studentPlaced = false;
  let saveTimer: NodeJS.Timeout | undefined;
  const placedByStudent = (): void => {
    studentPlaced = true;
  };
  const settled = (): void => {
    if (!studentPlaced) return;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      if (host.isDestroyed() || !studentPlaced) return;
      studentPlaced = false;
      if (host.isMaximized()) return;
      // Dragged out of its zoom: it is no longer zoomed, whatever the page last said.
      if (boardFull) {
        tellBoard("unzoom");
        return;
      }
      saveScreenBoard(host.getBounds());
    }, 400);
  };
  host.on("will-move", placedByStudent);
  host.on("will-resize", placedByStudent);
  host.on("moved", settled);
  host.on("resized", settled);
  // Where it was, at each move or change of size while it shows (boardWas): a tap that comes in
  // after the change, made where it was, is still the board's.
  const changed = (): void => {
    if (board !== b || host.isDestroyed()) return;
    const now = host.getBounds();
    if (boardAt && host.isVisible() && !sameBounds(boardAt, now)) boardLeft(boardAt);
    boardAt = now;
  };
  host.on("move", changed);
  host.on("resize", changed);
  // The green light (or Window > Zoom). The page hears of a zoom only when it is not the one it
  // asked for itself (applyBoardFull), so its own "make smaller" never comes back as the student's.
  // (not the quiet unzoom as the board moves into its tab: toTab)
  host.on("maximize", () => {
    if (quietZoom) return;
    changed();
    if (!boardFull) tellBoard("zoom");
  });
  host.on("unmaximize", () => {
    if (quietZoom) {
      quietZoom = false;
      return;
    }
    changed();
    if (boardFull) tellBoard("unzoom");
  });
  // The red light (or ⌘W, menu.ts) hides it and closes what is on it, as the board's own close
  // does; the board stays on, and the next thing the lesson puts up brings it back. A close the
  // page made itself (window.close()) would bypass this, so the page never closes it.
  host.on("close", (event) => {
    if (quitting || board !== b || !live()) return;
    event.preventDefault();
    closeBoardHere();
  });
  host.on("closed", () => {
    clearTimeout(saveTimer);
    // Closed for real while its page lives on (a quit then called off leaves the close allowed):
    // the page goes too, so the lesson's page opens a new board instead of drawing on one with no
    // window (its destroyed handler drops the rest).
    if (board === b && !contents.isDestroyed()) contents.close();
  });
  sendPlace();
  console.log("[screen-teach] board ready");
  return contents;
}

/** Out of the main window and its tab, and the host destroyed. */
function teardownBoard(b: Board): void {
  docking = 0;
  if (boardTabDocked()) undockBoardView();
  hideBoardTab();
  if (!b.host.isDestroyed()) b.host.destroy();
}

/** The board's page is gone (with the lesson's window, or a reload): its tab and its window go with it. */
function dropBoardState(b: Board): void {
  teardownBoard(b);
  board = null;
  placedRun = -1;
  boardAt = null;
  decidedRun = -1;
  inBar = false;
  boardUp = false;
  covering = false;
  lastPlaceSent = "";
  noteMenuPlace();
}

/** Tell the page what the student did with the board's window. */
function tellBoard(control: "close" | "zoom" | "unzoom"): void {
  live()?.webContents.send("screen-teach:board-control", control);
}

/** The student closed the board (its red light, ⌘W, its tab's ×): it hides, or its tab folds away,
 *  and the page closes what is on it. Where it was is kept: the next drawing brings it back there. */
function closeBoardHere(): void {
  boardWanted = false;
  holdAfterClose();
  noteBoardPlace();
  const b = liveBoard();
  if (b) {
    docking = 0;
    if (boardTabDocked()) undockBoardView();
    hideBoardTab();
    inBar = false;
    homeView(b);
    if (b.host.isVisible()) b.host.hide();
  }
  tellBoard("close");
  boardUp = false;
  sendPlace();
  console.log("[screen-teach] board closed by the student");
}

/** Keep the page's shows for this run back for a moment, the student having closed the board
 *  (closeHold). */
function holdAfterClose(): void {
  releaseHold();
  if (!lesson) return;
  const timer = setTimeout(() => {
    if (closeHold?.timer !== timer) return;
    closeHold = null;
    syncBoard();
  }, CLOSE_HOLD_MS);
  closeHold = { run: lesson.run, timer };
}

function releaseHold(): void {
  if (closeHold) clearTimeout(closeHold.timer);
  closeHold = null;
}

const sameBounds = (a: Rectangle, b: Rectangle): boolean => a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;

/** `bounds` is where the board's window was until now: still the board's for a tap a moment more. */
function boardLeft(bounds: Rectangle): void {
  const now = Date.now();
  boardWas = boardWas.filter((was) => was.until > now);
  const last = boardWas[boardWas.length - 1];
  if (last && sameBounds(last.bounds, bounds)) last.until = now + BOARD_LEFT_MS;
  else boardWas.push({ bounds, until: now + BOARD_LEFT_MS });
}

/** The board's window, if it shows, is about to hide or change size: where it is now goes on
 *  counting for a moment. */
function noteBoardPlace(): void {
  const host = liveBoard()?.host;
  if (host?.isVisible()) boardLeft(host.getBounds());
}

/** Close the board, when it is up (⌘W with the board's window in front, or on its tab: menu.ts). */
export function closeScreenBoard(): void {
  const b = liveBoard();
  if (b && (boardTabDocked() || b.host.isVisible())) closeBoardHere();
}

/** The board's window is zoomed as the page last said. Only while it shows: macOS shows a hidden
 *  window it zooms, so a zoom asked for meanwhile waits for syncBoard to show it. Only its own
 *  window: in a tab the board already fills Tutornote's. */
function applyZoom(): void {
  const b = liveBoard();
  if (!b || b.place !== "float") return;
  const host = b.host;
  if (boardFull && host.isVisible() && !host.isMaximized()) {
    noteBoardPlace();
    host.maximize();
  } else if (!boardFull && host.isMaximized()) {
    // (Make smaller on a zoomed board: the button pressed is no longer on it once it is smaller)
    noteBoardPlace();
    host.unmaximize();
  }
}

function applyBoardFull(full: boolean): void {
  boardFull = full;
  applyZoom();
}

/** The display that holds most of a window read. */
const displayFor = (f: Rect): Display =>
  screen.getDisplayMatching({
    x: Math.round(f.x),
    y: Math.round(f.y),
    width: Math.max(1, Math.round(f.w)),
    height: Math.max(1, Math.round(f.h)),
  });

/** The board beside the words read, on the display that holds their window (as the lesson's own
 *  window is: openScreenTeach), or where the student left it last. */
function placeBoardFor(b: BaseWindow, current: Lesson): void {
  const f = current.frame;
  const display = displayFor(f);
  b.setBounds(placeBoard({ work: display.workArea, text: current.text, frame: f, saved: loadScreenBoard() }));
}

/** What the lesson reads, as boardHost.ts weighs it against the main window. */
function reading(current: Lesson): Reading {
  const display = displayFor(current.frame);
  return { words: current.text, frame: current.frame, displayId: display.id, full: fullScreenFrame(current.frame, display.bounds) };
}

/**
 * The one place the board is shown, hidden or moved. It is up exactly while the page has
 * something on it for this lesson, the page is running, and the lesson itself is on screen (not
 * aside while the student is in another app), but not the moment after the student closed it
 * (closeHold). Run at each change of any of those, so a show the
 * page sent early (before it was ready, or while aside) is kept, and happens when it can.
 * Where it goes is decided the first time it is up in a run (decide). Its own window shows and
 * hides as above; in its tab it stays through every one of those (the page shows a quiet line on
 * it while there is nothing on it). The tab folds away with the lesson.
 */
function syncBoard(): void {
  const b = liveBoard();
  if (!b) return;
  const w = live();
  if (!lesson || !w || !pageReady) return foldBoard(b, !lesson ? "the lesson ended" : "the lesson's page is not ready");
  const why = !w.isVisible()
    ? "the lesson is not on screen"
    : aside
      ? "the student is in another app"
      : boardRun !== lesson.run || !boardWanted
        ? "nothing on it"
        : closeHold?.run === lesson.run
          ? "the student has just closed it"
          : "";
  const up = !why;
  // Something new on it: a new drawing, or the board coming up.
  const fresh = freshDrawing || (up && !boardUp);
  freshDrawing = false;
  if (up && decidedRun !== lesson.run) decide(b, lesson);
  // (an older page's board only ever floats: no tab for it, not even an away one)
  if (up && pageKnowsPlace) inBar = true;
  if (b.place === "tab") {
    if (up && !boardTabDocked() && !docking) {
      if (!toTab(b, "quiet")) toFloat(b);
    } else if (fresh && boardTabDocked()) {
      // (the student still in the app being read, with Tutornote's window now over its words: the
      // tab can't be seen, and the board moves out beside them, as when they leave the window)
      if (!(up && leaveCoveredTab(b, lesson))) onFreshInTab(up);
    }
  }
  const host = b.host;
  if (b.place === "float") {
    if (up && !host.isVisible()) {
      if (placedRun !== lesson.run) {
        placeBoardFor(host, lesson);
        placedRun = lesson.run;
      }
      host.showInactive();
      boardAt = host.getBounds();
      applyZoom();
      // (a window made by this module raises no browser-window-created: companion.ts hears it here)
      appEvents.emit("screen-board-shown");
      console.log(`[screen-teach] board shown (run ${lesson.run})`);
    } else if (!up && host.isVisible()) {
      noteBoardPlace();
      host.hide();
      console.log(`[screen-teach] board hidden: ${why}`);
    }
  }
  // (in its own window, its tab stays in the bar as an away tab that brings it back)
  if (inBar && !boardTabDocked() && b.place === "float") showBoardTab({ title: boardTitleNow, surface: boardColor, away: true });
  boardUp = up;
  sendPlace();
}

/** The board leaves the bar (the lesson ended, or its page is not running): its tab folds away and
 *  its window hides. Where it was is kept for the next run's decision. */
function foldBoard(b: Board, why: string): void {
  const was = inBar || boardTabDocked() || b.host.isVisible();
  docking = 0;
  if (boardTabDocked()) undockBoardView();
  hideBoardTab();
  inBar = false;
  covering = false;
  homeView(b);
  if (b.host.isVisible()) {
    noteBoardPlace();
    b.host.hide();
  }
  boardUp = false;
  sendPlace();
  if (was) console.log(`[screen-teach] board folded: ${why}`);
}

/** Where this run's board goes, at its first drawing (boardHost.ts boardPlaceFor). A board in its tab
 *  stays there when the rule still says so. */
function decide(b: Board, current: Lesson): void {
  decidedRun = current.run;
  const d = boardPlaceFor({ pref: prefs.place, pageKnowsPlace, main: mainWindowLook(), reading: reading(current) });
  console.log(`[screen-teach] board in ${d.where === "tab" ? "its tab" : "its own window"} (run ${current.run}): ${d.why}`);
  if (d.where === "float" && b.place === "tab") toFloat(b);
  else if (d.where === "tab") b.place = "tab";
}

/** The board's view back in its own window (shown or not), filling it, and seen there: it may come
 *  back hidden (the main window hides it while another tab shows, and a view keeps that). */
function homeView(b: Board): void {
  if (!b.host.contentView.children.includes(b.view)) b.host.contentView.addChildView(b.view);
  fitHost(b);
  b.view.setVisible(true);
}

/** Mark the board's page with where it is going (data-board-place: its CSS keys the drag region on
 *  it), before it goes: a press on its head in the first frame in a tab must never drag the main
 *  window. Within MARK_TIMEOUT_MS, or the move goes ahead anyway. */
function markPlace(b: Board, where: BoardWhere): Promise<void> {
  if (b.contents.isDestroyed()) return Promise.resolve();
  const mark = b.contents
    .executeJavaScript(`document.documentElement.setAttribute("data-board-place", ${JSON.stringify(where)}); 0`, false)
    .then(() => undefined);
  const cap = new Promise<void>((resolve) => setTimeout(resolve, MARK_TIMEOUT_MS));
  return Promise.race([mark, cap]).catch(() => undefined);
}

/** The board into its own window, at once, with everything on it (hidden: syncBoard shows it beside
 *  the words when it is up). Its tab stays in the bar as an away tab. */
function toFloat(b: Board): void {
  docking = 0;
  b.place = "float";
  covering = false;
  if (boardTabDocked()) undockBoardView();
  void markPlace(b, "float");
  homeView(b);
  // (placed beside the words at its next show)
  placedRun = -1;
  boardIgnoring = scrolling > 0;
  b.host.setIgnoreMouseEvents(boardIgnoring);
  if (inBar) showBoardTab({ title: boardTitleNow, surface: boardColor, away: true });
  sendPlace();
  console.log("[screen-teach] board in its own window");
}

/**
 * The board into its tab of the main window: its window hides at once (unzoomed quietly: the page
 * keeps its own idea of full), its page is marked, then the view moves. "quiet": as the lesson puts
 * something up, never taking the keys; "focus": the student's Open in Tutornote, which brings the
 * window forward with the board's keys. False when it cannot go (an older page, no lesson, or for
 * "quiet" no window there to hold it).
 */
function toTab(b: Board, how: "quiet" | "focus"): boolean {
  if (!pageKnowsPlace || !lesson) return false;
  if (how === "quiet" && !mainCanHold(mainWindowLook())) return false;
  if (boardTabDocked() || docking) return true;
  b.place = "tab";
  noteBoardPlace();
  if (b.host.isMaximized()) {
    quietZoom = true;
    b.host.unmaximize();
    // (the unmaximize event may come once the zoom has run: it clears this, or this does)
    setTimeout(() => (quietZoom = false), 1_000).unref();
  }
  if (b.host.isVisible()) b.host.hide();
  const gen = ++dockings;
  docking = gen;
  void markPlace(b, "tab").then(() => {
    if (docking !== gen || board !== b || b.place !== "tab" || !lesson || !liveBoard()) return;
    docking = 0;
    const main = how === "focus" ? bringMainForward() : mainCanHold(mainWindowLook()) ? getMainWindow() : null;
    b.host.contentView.removeChildView(b.view);
    if (!main || !dockBoardView(b.view)) {
      toFloat(b);
      syncBoard();
      return;
    }
    inBar = true;
    showBoardTab({ title: boardTitleNow, surface: boardColor, away: false });
    if (how === "focus") {
      selectBoardTab({ focus: true });
      b.contents.focus();
    } else onFreshInTab(true);
    sendPlace();
    console.log(`[screen-teach] board in its tab${how === "focus" ? ", for the student" : ""}`);
  });
  return true;
}

/**
 * Something new went up on the board in its tab. With the student in Tutornote: a dot on the tab,
 * when another tab shows. With the student in the app being read (`raise`): the Board tab is
 * selected and the window ordered in front without the keys (that app keeps its menu bar and its
 * keys), where it lies clear of the words, as it did when the board was put there.
 */
function onFreshInTab(raise: boolean): void {
  const main = getMainWindow();
  if (!main || !boardTabDocked()) return;
  if (main.isFocused()) {
    if (!boardTabActive()) setBoardTabInfo({ dot: true });
    return;
  }
  if (!raise || !lesson || coversReading(mainWindowLook(), reading(lesson))) return;
  if (!boardTabActive()) selectBoardTab({ focus: false });
  if (main.isVisible() && !main.isMinimized()) {
    // (in front without the keys, as explain.ts gives the window back)
    main.showInactive();
    mainOnTop = true;
  }
}

/** Where the board is, for the page (screen-teach:board-place), or null with no board. */
function placeNow(): BoardPlace | null {
  const b = liveBoard();
  if (!b) return null;
  const app = lesson?.bundle && lesson.app ? lesson.app.slice(0, 60) : "";
  return { where: b.place, canMove: b.place === "tab" || !mainWindowLook().signIn, covering, ...(app ? { app } : {}) };
}

/** Tell the page where the board is, when that changed (and the Window menu). */
function sendPlace(): void {
  noteMenuPlace();
  const p = placeNow();
  const key = JSON.stringify(p);
  if (key === lastPlaceSent) return;
  lastPlaceSent = key;
  if (p) live()?.webContents.send("screen-teach:board-place", p);
}

/** The Window menu's board item follows boardPlaceNow (menu.ts rebuilds it). */
function noteMenuPlace(): void {
  const now = boardPlaceNow();
  if (now === lastMenuPlace) return;
  lastMenuPlace = now;
  appEvents.emit("board-place-changed");
}

/**
 * The main window has had the keys a moment (MAIN_FOCUS_SETTLE_MS): the student went to it. On a
 * page there, they are somewhere other than the lesson, which steps aside; on the Board tab they
 * are at the lesson's board, which goes on, unless the window lies over what is read: then it
 * steps aside too (covering, with a line on the board), until they go back to the app being read.
 */
function judgeMain(): void {
  const m = getMainWindow();
  if (!lesson || !m || !m.isFocused()) return;
  mainOnTop = true;
  if (!boardTabActive()) {
    covering = false;
    stepAside(true);
    sendPlace();
    return;
  }
  covering = coversReading(mainWindowLook(), reading(lesson));
  stepAside(covering);
  sendPlace();
}

/** The main window gave up the keys a moment ago (MAIN_BLUR_SETTLE_MS) with the board in its tab:
 *  if the student can no longer see the tab there, the board moves to its own window. */
function onMainLeft(): void {
  const b = liveBoard();
  if (!b || !lesson || b.place !== "tab" || Date.now() - keysMovedAt < KEYS_MOVED_MS) return;
  if (leaveCoveredTab(b, lesson)) syncBoard();
  else sendPlace();
}

/** The board in its tab, with the student out of the main window: when that window can't show it
 *  to them (it covers what is read, or can no longer hold it: boardHost.ts leavesTab), it moves to
 *  its own window, for the caller's syncBoard to show beside the words. True when it moved. */
function leaveCoveredTab(b: Board, current: Lesson): boolean {
  if (b.place !== "tab") return false;
  const f = BaseWindow.getFocusedWindow();
  const otherOwnFocused = Boolean(f && f !== getMainWindow());
  if (!leavesTab({ main: mainWindowLook(), reading: reading(current), otherOwnFocused })) return false;
  toFloat(b);
  return true;
}

/** Pop out: the board into its own window beside the words, with the keys; later lessons too. */
function popOut(): void {
  prefs.place = "window";
  saveBoardPrefs({ place: "window" });
  const b = liveBoard();
  if (!b) return;
  if (b.place === "tab") {
    toFloat(b);
    // (the student's own move to the board: the lesson is theirs again, wherever they pressed it)
    if (aside) stepAside(false);
  }
  syncBoard();
  // (the board's page too: its own window gives the keys to no page by itself, and the page was
  // the main window's to focus a moment ago)
  if (b.host.isVisible()) {
    b.host.focus();
    b.contents.focus();
  }
  console.log("[screen-teach] board popped out by the student");
}

/** Open in Tutornote: the board into its tab, the window forward with the board's keys; Pop out is forgotten. */
function openInTutornote(): void {
  const b = liveBoard();
  if (!b || !pageKnowsPlace || !lesson || mainWindowLook().signIn) return;
  prefs.place = "tab";
  saveBoardPrefs({ place: "tab" });
  decidedRun = lesson.run;
  inBar = true;
  toTab(b, "focus");
}

/** ⌥⌘B and the menus' Pop Out Board / Show Board in Tutornote. */
export function toggleBoardPlace(): void {
  const b = liveBoard();
  if (!b || !lesson) return;
  if (boardTabDocked() || b.place === "tab") popOut();
  else openInTutornote();
}

/** Where the lesson's board is, while it has a tab in the bar (the Window menu's item), or null. */
export const boardPlaceNow = (): BoardWhere | null => (inBar ? (liveBoard()?.place ?? null) : null);

/** Back to {app}: the app being read in front again (the student's click in Tutornote, which can
 *  hand the front on). */
function backToApp(): void {
  const bundle = lesson?.bundle;
  if (!bundle || !/^[\w.-]{1,255}$/.test(bundle)) return;
  execFile("/usr/bin/open", ["-b", bundle], (error) => {
    if (error) console.warn(`[screen-teach] could not bring ${bundle} back: ${error.message}`);
  });
}

/** The board's page while the board has the keys (menu.ts: its zoom, its developer tools). */
export const screenBoardContents = (): WebContents | undefined => (boardHasKeys() ? liveBoard()?.contents : undefined);

/** The board's text size, as menu.ts just set it: kept for later lessons. */
export function rememberBoardZoom(level: number): void {
  const zoom = clampBoardZoom(level);
  if (zoom === prefs.zoom) return;
  prefs.zoom = zoom;
  saveBoardPrefs({ zoom });
}

/** The board's right-click menu (in its tab or its own window): each item only where it applies. */
function showBoardMenu(contents: WebContents, params: ContextMenuParams): void {
  const b = liveBoard();
  if (!b || b.contents !== contents) return;
  const groups: MenuItemConstructorOptions[][] = [];
  const selected = params.selectionText.trim();
  const words: MenuItemConstructorOptions[] = [];
  if (selected && selected.length <= 60 && !/[\r\n]/.test(params.selectionText)) {
    words.push({ label: BOARD_COPY.lookUp(selected), click: () => contents.showDefinitionForSelection() });
  }
  // (explicit calls, not roles: the board's page need not be the key window's first responder)
  if (params.isEditable) {
    words.push(
      { label: "Cut", enabled: params.editFlags.canCut, click: () => contents.cut() },
      { label: "Copy", enabled: params.editFlags.canCopy, click: () => contents.copy() },
      { label: "Paste", enabled: params.editFlags.canPaste, click: () => contents.paste() },
      { label: "Select All", click: () => contents.selectAll() },
    );
  } else if (selected) {
    words.push({ label: "Copy", click: () => contents.copy() });
  }
  groups.push(words);
  if (params.mediaType === "image" && params.hasImageContents) {
    groups.push([{ label: "Copy Image", click: () => contents.copyImageAt(params.x, params.y) }]);
  }
  if (/^https?:/i.test(params.linkURL)) {
    const url = params.linkURL;
    groups.push([
      { label: "Open Link in Browser", click: () => openExternal(url) },
      { label: "Copy Link", click: () => void clipboard.writeText(url).catch(() => undefined) },
    ]);
  }
  const copyPicture = async (): Promise<void> => {
    const image = await contents.capturePage();
    if (image.isEmpty()) return;
    await clipboard.write([new ClipboardItem({ "image/png": new Blob([new Uint8Array(image.toPNG())], { type: "image/png" }) })]);
  };
  groups.push([{ label: BOARD_COPY.copyPicture, click: () => void copyPicture().catch(() => undefined) }]);
  const place = placeNow();
  const moves: MenuItemConstructorOptions[] = [];
  if (b.place === "tab" || (pageKnowsPlace && place?.canMove)) {
    moves.push({ label: b.place === "tab" ? BOARD_COPY.popOut : BOARD_COPY.showIn, click: () => toggleBoardPlace() });
  }
  moves.push({ label: BOARD_COPY.close, click: () => closeScreenBoard() });
  groups.push(moves);
  const items = groups
    .filter((g) => g.length > 0)
    .flatMap((g, i) => (i === 0 ? g : [{ type: "separator" } as MenuItemConstructorOptions, ...g]));
  const owner = boardTabDocked() ? getMainWindow() : b.host;
  if (!owner) return;
  Menu.buildFromTemplate(items).popup({ window: owner, frame: params.frame ?? undefined });
}

/** Whether `p` (screen points) is on the board's window while it shows, or, `recently`, where it
 *  showed a moment ago (boardWas: a tap comes in late). */
function overBoard(p: Point, recently = false): boolean {
  const on = (r: Rectangle): boolean => p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height;
  const host = liveBoard()?.host;
  if (host && host.isVisible() && on(host.getBounds())) return true;
  if (!recently) return false;
  const now = Date.now();
  return boardWas.some((was) => was.until > now && on(was.bounds));
}

/** Whether `p` (screen points) is on the main window while it is in front: it has the keys (the
 *  student's own click, which the lesson steps aside for only MAIN_FOCUS_SETTLE_MS later, board
 *  or not), or the board in its tab put it there (its raise). A click there was Tutornote's, as
 *  one on the board's own window is (the helper sees past Tutornote's windows). */
function overMain(p: Point): boolean {
  const m = getMainWindow();
  if (!m || !m.isVisible() || m.isMinimized() || !(m.isFocused() || (mainOnTop && boardTabDocked()))) return false;
  const r = m.getBounds();
  return p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height;
}

/** Give up the board's window with the page that drew it (its reload, its window gone): the next
 *  page opens a fresh one, and says itself what is on it. */
function destroyBoard(): void {
  const b = board;
  board = null;
  placedRun = -1;
  boardWanted = false;
  boardFull = false;
  boardAt = null;
  decidedRun = -1;
  inBar = false;
  boardUp = false;
  covering = false;
  releaseHold();
  if (!b) return;
  // (its tab and its window first: a page closed in a window that stays would leave it blank)
  teardownBoard(b);
  if (!b.contents.isDestroyed()) b.contents.close();
  noteMenuPlace();
}

function ensureWindow(bounds: Rectangle): BrowserWindow {
  const kept = live();
  if (kept) {
    const b = kept.getBounds();
    if (b.x !== bounds.x || b.y !== bounds.y || b.width !== bounds.width || b.height !== bounds.height) kept.setBounds(bounds);
    return kept;
  }
  const created = new BrowserWindow({
    ...bounds,
    show: false,
    // A panel (a non-activating window, as Spotlight's is): a click on its dock, a chip or the
    // companion's card never makes Tutornote the app in front, and when it takes the keys (focus)
    // the app being read stays in front, so they go back there once it gives them up
    // (screen-teach:want-keys). A plain window with focusable false still brings Tutornote
    // forward on a click (Electron 44 only keeps it from taking the keys).
    type: "panel",
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    hasShadow: false,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    // It takes keys when the student clicks into it (a question typed to the tutor), and
    // its first click counts, so the board's buttons work in one.
    focusable: true,
    acceptFirstMouse: true,
    enableLargerThanScreen: true,
    webPreferences: {
      preload: path.join(__dirname, "..", "preload", "index.js"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      // It speaks while another app is in front, and starts speaking without a click.
      backgroundThrottling: false,
      autoplayPolicy: "no-user-gesture-required",
      spellcheck: false,
      zoomFactor: 1,
      additionalArguments: [
        `--anothernotes-version=${app.getVersion()}`,
        "--anothernotes-screen-teach=1",
        ...(nativeSpeechAvailable() ? ["--anothernotes-speech=1"] : []),
      ],
    },
  });
  const contents = created.webContents;
  // Zoom is shared by every page of one origin: a tab zoomed from the View menu would scale
  // this one too, and every box it draws would be off.
  contents.setZoomMode("isolated");
  // The page's own console in the app's log, as windows.ts has the tabs' ([voice], [tapcard]).
  contents.on("console-message", (details) => console.log(`[web:${details.level}:screen] ${details.message}`));
  created.setAlwaysOnTop(true, "floating", 1);
  // Over a full-screen app's Space too: Kindle is often read in full-screen Chrome. To float there
  // Electron briefly turns the app into a background one, which hides its Dock icon for a moment
  // each time this is called (electron.d.ts, skipTransformProcessType); the window is kept and
  // reused, so that is once per window. Skipping the transform would keep the icon steady but the
  // lesson would never show over a full-screen app.
  created.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  created.setIgnoreMouseEvents(true, { forward: true });
  ignoring = true;
  interactive = false;
  pageReady = false;
  contents.on("will-navigate", (event) => event.preventDefault());
  // No popups, but one: the board's own window, which the page opens empty, under its name, to
  // draw the board into. Its page is taken into a window of this module's (adoptBoard), and goes
  // with this window (outlivesOpener: false).
  contents.setWindowOpenHandler(({ url, frameName }) => {
    if (url === "about:blank" && frameName === BOARD_FRAME && !liveBoard()) {
      return {
        action: "allow",
        outlivesOpener: false,
        overrideBrowserWindowOptions: { show: false },
        createWindow: (options) => adoptBoard(created, options),
      };
    }
    if (frameName === BOARD_FRAME) console.warn("[screen-teach] board window refused");
    return { action: "deny" };
  });
  // A reload (only this side ever loads the page: every navigation of the page's own is refused
  // above, though it starts first, so those have an initiator and are left alone). The board goes
  // as the reload starts, not once it has loaded: by then the new page has already asked for the
  // board by its name, and been handed the old one as it closes, and opens none of its own.
  contents.on("did-start-navigation", (details) => {
    if (win === created && details.isMainFrame && !details.isSameDocument && !details.initiator) destroyBoard();
  });
  contents.on("did-navigate", () => {
    if (win !== created) return;
    // (what the page before said about its board is void: the new one says it afresh)
    boardWanted = false;
    boardFull = false;
    pageReady = false;
    pageAsked = false;
    // (the new page says itself whether it knows the board's tab)
    pageKnowsPlace = false;
    lastPlaceSent = "";
    // A page loaded afresh (a reload) has its controls under no pointer yet: clicks go through
    // until it says otherwise. (Nor a card: the new page has none.)
    interactive = false;
    setCardBox(null);
    applyMouse();
  });
  contents.on("did-fail-load", (_event, code, description, _url, isMainFrame) => {
    // -3 is a load stopped by another (a reload): not a failure.
    if (!isMainFrame || code === -3 || win !== created) return;
    console.warn(`[screen-teach] the lesson page did not load: ${code} ${description}`);
    failLesson("The lesson couldn't open. Please try again.");
    dropWindow();
  });
  contents.on("render-process-gone", (_event, details) => {
    if (win !== created) return;
    console.warn(`[screen-teach] the lesson page stopped: ${details.reason}`);
    failLesson("The lesson stopped. Press ⌃⌥E to start again.");
    dropWindow();
  });
  created.on("closed", () => {
    if (win !== created) return;
    win = null;
    pageReady = false;
    setCardBox(null);
    destroyBoard();
    closeScreenTeach();
    // (the companion, if on, has lost its window: companion.ts turns it off)
    companion = null;
    appEvents.emit("screen-teach-gone");
  });
  watchLessonAudio(contents);
  void created.loadURL(`${APP_ORIGIN}${ROUTE}`);
  win = created;
  return created;
}

/** Give up on the window, its page having failed: the next pick makes a new one. */
function dropWindow(): void {
  const w = live();
  win = null;
  pageReady = false;
  setCardBox(null);
  // (the board shares its page's process and its life)
  destroyBoard();
  w?.destroy();
  // (the companion, if on, has lost its window too)
  companion = null;
  appEvents.emit("screen-teach-gone");
}

function registerShortcuts(): void {
  for (const [accelerator, command] of SHORTCUTS) {
    if (globalShortcut.isRegistered(accelerator)) continue;
    if (!globalShortcut.register(accelerator, () => live()?.webContents.send("screen-teach:command", command))) {
      console.warn(`[screen-teach] ${accelerator} is taken by another app`);
    }
  }
  registerTalkKey();
}

function unregisterShortcuts(): void {
  for (const [accelerator] of SHORTCUTS) {
    if (globalShortcut.isRegistered(accelerator)) globalShortcut.unregister(accelerator);
  }
  // (the companion's dock has a mic of its own while the tutor is on)
  if (!companion?.on) unregisterTalkKey();
}

/** The talk key and the talk chord, on together and off together (TALK_SHORTCUT): the chord is
 *  watched even when another app has taken ⌃⌥M, since it is then the only way in. */
function registerTalkKey(): void {
  if (!talkKeyOn) {
    talkKeyOn = true;
    chordWatch(true);
  }
  if (globalShortcut.isRegistered(TALK_SHORTCUT)) return;
  const pressed = (): void => {
    // A tap of the mic, as a chord "tap" is (the page's tap rule); its own Control and Option let
    // go just after are no chord tap (onChord).
    lastTalkKeyAt = Date.now();
    console.log(`[screen-teach] talk key ${TALK_SHORTCUT}: a tap`);
    live()?.webContents.send("screen-teach:talk");
  };
  if (!globalShortcut.register(TALK_SHORTCUT, pressed)) {
    console.warn(`[screen-teach] ${TALK_SHORTCUT} is taken by another app`);
  }
}

function unregisterTalkKey(): void {
  if (talkKeyOn) {
    talkKeyOn = false;
    chordWatch(false);
  }
  if (globalShortcut.isRegistered(TALK_SHORTCUT)) globalShortcut.unregister(TALK_SHORTCUT);
}

/**
 * The talk chord (screen.ts ScreenChord), while the talk key is on: to the lesson's page as it
 * comes ("screen-teach:chord", {kind, ms}), which decides what it is (a tap: one question, or an
 * interrupt, or talk mode off; a hold: talk mode on; down, up, cancel: the hold's ring) and drops
 * it while the student is not with the lesson. Never dropped here for Tutornote's main window
 * having the keys: the chord is the student's, wherever they are. A "tap" just after ⌃⌥M is that
 * key's (TALK_KEY_CHORD_MS). Only its kind and time go to the page; why and which keys, to the log.
 */
function onChord(chord: ScreenChord): void {
  const w = live();
  if (!talkKeyOn || !w || !pageReady) return;
  const about = [chord.why, chord.keys].filter(Boolean).join(", ");
  const said = `[screen-teach] chord ${chord.kind} ${chord.ms} ms${about ? ` (${about})` : ""}`;
  if (chord.kind === "tap" && Date.now() - lastTalkKeyAt < TALK_KEY_CHORD_MS) {
    console.log(`${said}: dropped, ${TALK_SHORTCUT} was just pressed`);
    return;
  }
  console.log(said);
  w.webContents.send("screen-teach:chord", { kind: chord.kind, ms: chord.ms });
}

/**
 * Teach the window just read, from where the student clicked (both in screen points).
 * A lesson already on screen starts again from this one.
 */
export async function openScreenTeach(read: ScreenRead, click: Point, opts?: ScreenTeachOptions): Promise<void> {
  const run = ++runs;
  // The display that holds most of the window being read.
  const display = screen.getDisplayMatching({
    x: Math.round(read.frame.x),
    y: Math.round(read.frame.y),
    width: Math.max(1, Math.round(read.frame.w)),
    height: Math.max(1, Math.round(read.frame.h)),
  });
  // (a companion pick: the answer from under a minute ago, and a new one asked behind the lesson)
  const kept = companion?.on && axAnswer && Date.now() - axAnswer.at < AX_KEEP_MS ? axAnswer.allowed : null;
  const canTurn = kept ?? (await turningAllowed());
  if (kept !== null) void turningAllowed();
  if (run !== runs) return; // a newer pick
  const w = ensureWindow(display.workArea);
  // The companion's window, moved with it (a pick made on another display while the tutor is on).
  const movedCompanion = Boolean(companion?.on && !sameBounds(companion.work, display.workArea));
  // Where macOS really put it: the boxes are made local to this.
  const b = w.getBounds();
  const mode: ScreenMode = PAGE_APPS.has(read.bundle) ? "page" : "scroll";
  // (the last lesson's wait for the student, if any, is over)
  lesson?.waiting?.abort();
  lesson = {
    run,
    window: read.window,
    pid: read.pid,
    app: read.app,
    bundle: read.bundle,
    mode,
    way: null,
    queue: Promise.resolve(),
    waiting: null,
    frame: read.frame,
    text: textBox(read.lines),
    lines: read.lines,
    title: read.title,
    turnedAt: 0,
  };
  // The page and companion.ts hear where the companion's window is now, as for a move of its own
  // (once this lesson is the one on: companion.ts keeps the window on the lesson's display then).
  if (movedCompanion && companion) {
    companion.work = display.workArea;
    companion.message = { ...companion.message, overlay: overlayRect(w) };
    sendCompanion();
    appEvents.emit("screen-teach-moved");
  }
  pending = {
    run,
    overlay: { x: b.x, y: b.y, w: b.width, h: b.height },
    read: toLocal(read, b),
    click: { x: click.x - b.x, y: click.y - b.y },
    canTurn,
    mode,
    // Companion mode: the card's pick, a quiet start after the first, and the page's ground.
    // While the tutor is on, every lesson is the companion's (a pick made meanwhile too).
    ...(opts?.choice ? { choice: opts.choice } : {}),
    ...(opts?.quiet ? { quiet: true } : {}),
    ...(opts?.companion || companion?.on ? { companion: true } : {}),
    ...(typeof read.ground === "number" && Number.isFinite(read.ground) ? { ground: read.ground } : {}),
    // (the tapped row's words, and whether the read is older than the window's look now)
    ...(opts?.row ? { row: opts.row } : {}),
    ...(opts?.stale ? { stale: true } : {}),
  };
  console.log(
    `[screen-teach] run ${run}: ${read.app} (${read.bundle || "no bundle id"}), ${mode}, turning ${canTurn ? "allowed" : "not allowed"}` +
      (pending.companion ? `, companion${pending.choice ? ` ${pending.choice}` : ""}${pending.quiet ? ", quiet" : ""}${pending.stale ? ", stale" : ""}` : ""),
  );
  // (companion.ts keeps its glance of this window as read here)
  appEvents.emit("screen-teach-read", read);
  // The student's taps on that window, and the app in front (installScreenTeach's listeners).
  aside = false;
  // (a pick is the student with the lesson: a page last told they were away hears they are back)
  if (pageReady) w.webContents.send("screen-teach:present", true);
  // The last lesson's board goes with it; this one's comes up when its page has put something on it.
  boardWanted = false;
  releaseHold();
  watchWindow(read.window);
  registerShortcuts();
  w.webContents.setAudioMuted(false);
  liveBoard()?.contents.setAudioMuted(false);
  // (its app may not be the last lesson's: Back to {app})
  sendPlace();
  clearTimeout(readyTimer);
  if (pageReady) {
    w.webContents.send("screen-teach:start", pending);
    w.showInactive();
    syncBoard();
    return;
  }
  syncBoard();
  // Shown when the page asks for its start (screen-teach:ready); a page that never does
  // (it did not load, or the app's copy of the web app has no such page) ends the lesson.
  readyTimer = setTimeout(() => {
    if (lesson?.run === run && !pageReady) {
      console.warn("[screen-teach] the lesson page never said it was ready");
      failLesson("The lesson couldn't open. Please try again.");
      dropWindow();
    }
  }, READY_TIMEOUT_MS);
}

/** End the lesson, if one is on: the page stops, the window hides (and is kept). True when one was on. */
function endLesson(): boolean {
  clearTimeout(readyTimer);
  if (!lesson) return false;
  lesson.waiting?.abort();
  lesson = null;
  pending = null;
  aside = false;
  unwatchWindow();
  unregisterShortcuts();
  interactive = false;
  scrolling = 0;
  boardWanted = false;
  covering = false;
  const w = live();
  if (w) {
    w.webContents.send("screen-teach:command", "close");
    // Hidden, it must not go on talking whatever the page does with "close".
    w.webContents.setAudioMuted(true);
    // (nor a clip playing on the board)
    liveBoard()?.contents.setAudioMuted(true);
    applyMouse();
    // With the companion on, the window stays: the tutor goes on following the cursor.
    if (!companion?.on) w.hide();
  }
  syncBoard();
  return true;
}

/** Close the lesson on screen (its own Close, or "Explain on screen" closing). */
export function closeScreenTeach(): void {
  // A lesson still opening (openScreenTeach waiting on the helper) is dropped too.
  runs++;
  if (endLesson()) appEvents.emit("screen-teach-closed");
}

function failLesson(text: string): void {
  if (endLesson()) appEvents.emit("screen-teach-failed", text);
}

export const screenTeachOpen = (): boolean => lesson !== null;

/** The board has the keys: its own window is the key window, or the main window is, on its tab. */
function boardHasKeys(): boolean {
  const b = liveBoard();
  if (!b) return false;
  return b.place === "float" ? b.host.isFocused() : boardTabDocked() && boardTabActive() && Boolean(getMainWindow()?.isFocused());
}

/** The lesson's window, or its board's, has the keys (the student clicked into it): the app's
 *  menus are not for the main window's tab then (menu.ts). */
export const screenTeachFocused = (): boolean => Boolean(lesson && (live()?.isFocused() || boardHasKeys()));

/** The board's window has the keys: ⌘W closes the board, not the lesson (menu.ts). */
export const screenBoardFocused = (): boolean => Boolean(lesson && boardHasKeys());

/** The ways to try, in order, until one moves the window. Kindle Cloud Reader is a page app inside a browser. */
const waysFor = (mode: ScreenMode): Way[] =>
  mode === "page"
    ? [
        { how: "key", key: "right" },
        { how: "key", key: "pagedown" },
      ]
    : [{ how: "scroll" }, { how: "key", key: "pagedown" }, { how: "key", key: "right" }];

/** `unlessMoved`: post nothing when the window has moved since its last read (the student's own move). */
async function move(way: Way, req: ScreenTurnRequest, base: Pick<ScreenTurn, "window" | "pid" | "at">, timeoutMs: number, unlessMoved: boolean) {
  const forward = req.dir === "forward";
  if (way.how === "key") {
    const key = forward ? way.key : BACK_KEY[way.key];
    return turnWindow({ ...base, how: "key", key, count: req.pages, timeoutMs: timeoutMs + KEY_GAP_MS * (req.pages - 1), unlessMoved });
  }
  const by = req.scrollBy > 0 ? req.scrollBy : DEFAULT_SCROLL;
  scrolling++;
  applyMouse();
  try {
    return await turnWindow({ ...base, how: "scroll", dy: forward ? by : -by, timeoutMs, unlessMoved });
  } finally {
    scrolling = Math.max(0, scrolling - 1);
    applyMouse();
  }
}

function reasonOf(e: unknown): "no_access" | "no_permission" | "window_gone" | "failed" {
  const code = e instanceof ScreenReadError ? e.code : "";
  if (code === "no_access" || code === "no_permission" || code === "window_gone") return code;
  return code === "no_window" ? "window_gone" : "failed";
}

const sameWay = (a: Way, b: Way): boolean => a.how === b.how && (a.how !== "key" || (b.how === "key" && a.key === b.key));

/** `waiting`: a manual turn's, to give its wait up with (Lesson.waiting). */
async function turn(req: ScreenTurnRequest, waiting: AbortController | null): Promise<ScreenTurnResult> {
  const current = lesson;
  const shown = live();
  const stale = (): boolean => !current || lesson !== current || current.run !== req.run || !live();
  if (!current || !shown || stale()) return { ok: false, reason: "stale" };
  const origin = shown.getBounds();
  const base = { window: current.window, pid: current.pid, at: { x: origin.x + req.at.x, y: origin.y + req.at.y } };
  try {
    let how: "scroll" | "key" | "manual";
    let canTurn: boolean | undefined;
    if (req.how === "manual") {
      // Post nothing: wait for the student to turn the page, or scroll, themselves (one made
      // already since the last read counts: unlessMoved).
      const moved = await turnWindow({ ...base, how: "manual", timeoutMs: MANUAL_WAIT_MS, unlessMoved: req.unlessMoved }, waiting?.signal);
      if (stale()) return { ok: false, reason: "stale" };
      // Not turned in time: the lesson stops there, and its next play waits for them again.
      // Not "failed", which the page shows as a page it could not read.
      if (!moved.changed) return { ok: false, reason: "end" };
      how = "manual";
      // (Accessibility switched on meanwhile: the next turn can be the app's own)
      canTurn = await turningAllowed();
    } else {
      if (!(await turningAllowed())) return stale() ? { ok: false, reason: "stale" } : { ok: false, reason: "no_access" };
      // The way that worked before first, then the others: a key that has stopped working (the
      // focus moved in the app) is not yet the end of the book.
      const kept = current.way;
      const ways = kept ? [kept, ...waysFor(current.mode).filter((w) => !sameWay(w, kept))] : waysFor(current.mode);
      let won: Way | null = null;
      let theirs = false;
      // Some key was pressed while the app was not in front: it may never have reached it.
      let unsure = false;
      for (const [i, way] of ways.entries()) {
        if (stale()) return { ok: false, reason: "stale" };
        const moved = await move(way, req, base, way === kept ? TURN_TIMEOUT_MS : TRY_TIMEOUT_MS, i === 0 && req.unlessMoved);
        if (moved.moved) {
          theirs = true;
          break;
        }
        if (moved.changed) {
          won = way;
          break;
        }
        if (moved.front === false) unsure = true;
      }
      if (stale()) return { ok: false, reason: "stale" };
      if (theirs) {
        // The student had turned or scrolled it themselves: that is this turn.
        how = "manual";
      } else if (!won) {
        // Nothing moved the window. The end of the book or the document, in an app that has
        // been turned before and was in front for the keys; else it can't be told from keys
        // that never arrived, and the student turns this page.
        return { ok: false, reason: unsure || !kept ? "stuck" : "end" };
      } else {
        if (!kept || !sameWay(won, kept)) console.log(`[screen-teach] ${current.app} turns by ${won.how === "key" ? `the ${won.key} key` : "scrolling"}`);
        current.way = won;
        // A key that turns it makes it a page app, whatever it was taken for.
        if (won.how === "key") current.mode = "page";
        how = won.how;
      }
    }
    const read = await readWindow(current.window);
    noteRead(current, read);
    const w = live();
    if (stale() || !w) return { ok: false, reason: "stale" };
    appEvents.emit("screen-teach-read", read);
    return { ok: true, how, mode: current.mode, read: toLocal(read, w.getBounds()), ...(canTurn === undefined ? {} : { canTurn }) };
  } catch (e) {
    // (a wait for the student given up for the page's next request: nothing to answer)
    if (stale() || (e instanceof ScreenReadError && e.code === "cancelled")) return { ok: false, reason: "stale" };
    console.warn(`[screen-teach] turn failed: ${e instanceof ScreenReadError ? e.code : (e as Error).message}`);
    return { ok: false, reason: reasonOf(e) };
  }
}

const finite = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value);

/** A turn request from the page, checked field by field, or null. */
function turnRequestOf(value: unknown): ScreenTurnRequest | null {
  const r = (value ?? {}) as Record<string, unknown>;
  const at = (r.at ?? {}) as Record<string, unknown>;
  if (!finite(r.run) || (r.dir !== "forward" && r.dir !== "back") || !finite(at.x) || !finite(at.y)) return null;
  return {
    run: r.run,
    dir: r.dir,
    scrollBy: finite(r.scrollBy) ? Math.min(Math.abs(r.scrollBy), 20_000) : 0,
    pages: finite(r.pages) ? Math.max(1, Math.min(Math.round(r.pages), 50)) : 1,
    at: { x: at.x, y: at.y },
    how: r.how === "manual" ? "manual" : "auto",
    unlessMoved: r.unlessMoved === true,
  };
}

/** After the lesson's turns and reads so far. */
function queued<T>(current: Lesson, job: () => Promise<T>): Promise<T> {
  const result = current.queue.then(job);
  current.queue = result.catch(() => undefined);
  return result;
}

/**
 * A tap on the page being read. The window let it through to that app, which got it; the helper
 * heard it (screen.ts watchEvents). Over the lesson's own controls it was the lesson's click, not
 * a tap on the page. If the window has moved since it was last read (the student scrolled it),
 * what the lesson holds is no longer where it was: the window is read again and the lesson starts
 * afresh from the tap, as a new pick does. Otherwise the page goes on from the paragraph there.
 */
/** The page decides what a tap is (ScreenTeachPage): a paragraph it has read, followed to
 *  wherever the student scrolled it, or words it has not read yet (`moved`: the window changed
 *  since its last read), which start the lesson again from there (screen-teach:pick-at). With the
 *  companion on it heard the release first (companion.ts onRelease), and may have opened its card
 *  then: `id` ties this verdict to it. */
function onTap(tap: ScreenTap): void {
  const current = lesson;
  const w = live();
  if (!current || !w || tap.window !== current.window || aside || !w.isVisible()) return;
  // (companion mode: a click on the page's own card or dock, whatever it has said since. A verdict
  // for a release (`id`) goes by its press alone, as the release did (companion.ts onRelease): by
  // now the cursor may be over a card the page painted at that release, and the tap was still
  // on the page being read)
  if (pressWasThePage() || (interactive && tap.id === undefined)) return;
  // The helper sees past Tutornote's own windows: a click on the board where it lies over the
  // page being read was the board's, not a tap on the words under it. Where it was a moment ago
  // too: the tap comes in after the click, which may have hidden the board or made it smaller.
  if (overBoard(tap, true) || overMain(tap)) {
    console.log("[screen-teach] tap on the board left out");
    return;
  }
  // A plain click that did something in the app (a link, a button, a page turned by its margin)
  // was the app's: the lesson notices the new look by itself (screen-teach:changed). An Option
  // click is always the tutor's. A double click selects words: the app's too, but in a reader or
  // a browser's PDF (selectionKept), where selecting a word is how the student points at it: a
  // lesson tap there, which the page takes as one that did nothing in the app. A card the page
  // opened at the release goes at once (companion-withdraw).
  const kept = selectionKept({ words: tap.words, bundle: current.bundle, title: current.title });
  if (!kept && ((tap.acted && !tap.alt) || tap.words === "select")) {
    console.log(`[screen-teach] tap acted in ${current.app}: left to the app${tapNumbers(tap)}`);
    if (companion?.on && tap.id !== undefined) {
      w.webContents.send("screen-teach:companion-withdraw", { id: tap.id, why: tap.words ?? "acted", window: tap.window });
    }
    return;
  }
  if (kept) console.log(`[screen-teach] tap in ${current.app}: a lesson tap${tapNumbers(tap)} (selection in a reader: kept)`);
  const b = w.getBounds();
  w.webContents.send("screen-teach:tap", {
    run: current.run,
    x: tap.x - b.x,
    y: tap.y - b.y,
    moved: tap.moved,
    acted: kept ? false : tap.acted,
    alt: tap.alt,
    ...(tap.id !== undefined ? { id: tap.id } : {}),
  });
}

/** Read the window again (or take the companion's careful read from the tap: carefulRead) and
 *  start the lesson afresh from `at` (screen points), as a new pick does. The page asks only for
 *  a tap its own targeting placed on words (tapTarget: a margin beside a line counts, a picture
 *  does not), so any read with lines will do; one with none (a window still drawing) changes
 *  nothing. */
function restartAt(current: Lesson, at: Point, why: string): void {
  console.log(`[screen-teach] ${why}: reading it again from there`);
  const asked = Date.now();
  // (after the lesson's turns so far: the careful read taken at the tap, if it still stands for
  // the window as it is now, else a read now; one that failed is read again)
  void queued(current, () => {
    const taken = carefulRead(current.window, Math.max(current.turnedAt, asked - TAP_READ_FRESH_MS));
    if (taken) console.log("[screen-teach] starting from the companion's read taken at the tap");
    return taken ? taken.catch(() => readWindow(current.window)) : readWindow(current.window);
  }).then(
    (read) => {
      if (lesson !== current) return;
      // (with the companion on, quietly: no new greeting or start sound in the middle of its session)
      if (read.lines.length) void openScreenTeach(read, at, companion?.on ? { companion: true, quiet: true } : undefined);
      else console.log("[screen-teach] no words in the window: the lesson goes on");
    },
    (e: unknown) => console.warn(`[screen-teach] read after a tap failed: ${e instanceof ScreenReadError ? e.code : (e as Error).message}`),
  );
}

/**
 * The student scrolling the page being read: the lesson's marks move with its words at once, as
 * over a PDF in the app (the page corrects the distance by reading the window again once the
 * scroll stops). Not while a turn of the lesson's own is posted: that move is the turn's.
 */
function onScroll(scroll: ScreenScroll): void {
  const current = lesson;
  const w = live();
  if (!current || !w || scroll.window !== current.window || aside || scrolling > 0 || !w.isVisible()) return;
  // (a sideways swipe moves no line up or down: a page it turns is seen as a new look instead)
  if (scroll.dy === 0) return;
  // Scrolling the board, over the page being read, moves the board, not the page's words (a
  // scroll comes with no point: the pointer is where it was made).
  const cursor = screen.getCursorScreenPoint();
  if (overBoard(cursor) || overMain(cursor)) {
    const now = Date.now();
    if (now - scrollDropLogged > 2_000) console.log("[screen-teach] scroll on the board left out");
    scrollDropLogged = now;
    return;
  }
  w.webContents.send("screen-teach:scroll", { run: current.run, dy: scroll.dy });
}

/**
 * Another app came to the front (`pid`). The lesson belongs over the window it reads: while the
 * student is in another app it steps aside, hidden and paused, and comes back (playing again if
 * it was playing) when they return to that app.
 *
 * Tutornote itself coming to the front says nothing by itself: its main window stays open now
 * (it no longer hides for a lesson), and the student going to their notes there is going
 * elsewhere, while their click on the lesson's own window or its board is not. So which of its
 * windows takes the keys decides (onOwnFocus).
 */
function onFront(pid: number): void {
  if (pid !== process.pid) mainOnTop = false;
  if (pid === process.pid) return;
  stepAside(pid !== lesson?.pid);
}

/** A window of Tutornote's took the keys (app "browser-window-focus"): the main window, or the
 *  pick's panel, is somewhere other than the lesson; the lesson's own window (a question typed
 *  to the tutor) or its board changes nothing. Nor does the main window taking them as the
 *  lesson's window takes or gives them up (want-keys): macOS may hand them on that way. */
function onOwnFocus(focused: BrowserWindow): void {
  // (the board's own window is no BrowserWindow, and raises no browser-window-focus)
  if (focused === live()) return;
  if (Date.now() - keysMovedAt < KEYS_MOVED_MS) return;
  // The main window: judged a moment later, by the tab it shows then (a click on the Board tab
  // selects it just after the window takes the keys).
  if (focused === getMainWindow()) {
    clearTimeout(mainFocusTimer);
    mainFocusTimer = setTimeout(judgeMain, MAIN_FOCUS_SETTLE_MS);
    return;
  }
  stepAside(true);
}

/** The student went somewhere other than the lesson's app (`away`), or came back to it. */
function stepAside(away: boolean): void {
  const current = lesson;
  const w = live();
  if (!current || !w || !pageReady) return;
  const ours = !away;
  // With the companion on, the window stays up (the tutor keeps following the cursor over the
  // other app, and its card may want clicks there): the page hides the lesson's marks and dock
  // itself (screen-teach:aside), and on the way back it reads the window again before it plays
  // on, so no "resume". Either way the page hears whether the student is with the lesson
  // (screen-teach:present): its mics follow that, not the window's focus.
  if (!ours && !aside) {
    aside = true;
    w.webContents.send("screen-teach:command", "pause");
    w.webContents.send("screen-teach:present", false);
    if (companion?.on) {
      w.webContents.send("screen-teach:aside", true);
    } else {
      interactive = false;
      applyMouse();
      w.hide();
    }
    // (the board steps aside with it, and comes back with it)
    syncBoard();
  } else if (ours && aside) {
    aside = false;
    covering = false;
    sendPlace();
    w.webContents.send("screen-teach:present", true);
    if (companion?.on) {
      syncBoard();
      w.webContents.send("screen-teach:aside", false);
      return;
    }
    w.showInactive();
    syncBoard();
    w.webContents.send("screen-teach:command", "resume");
  }
}

/*
  Companion mode (companion.ts drives it; the window and the lesson stay this module's).
*/

/** The companion's rectangle message for the window as it is now. */
const overlayRect = (w: BrowserWindow): Rect => {
  const b = w.getBounds();
  return { x: b.x, y: b.y, w: b.width, h: b.height };
};

/** Tell the page the companion's state, when it listens: once it has asked for it (companion-state)
 *  it has its listener, and the first-time tip and the hop from the blob are spent. */
function sendCompanion(): void {
  const w = live();
  if (!w || !companion || !(pageReady || pageAsked)) return;
  w.webContents.send("screen-teach:companion", companion.message);
  if (pageAsked) companion.message = { on: companion.message.on, overlay: companion.message.overlay, first: false };
}

/**
 * The companion is on: the window over `work` (the work area of the cursor's display), up for as
 * long as the tutor is, never taking the keys. `from`: the blob's centre in screen points, where
 * the tutor hops out from. `first`: the first time ever (the page shows its tip).
 */
export function showCompanionOverlay(work: Rectangle, from: Point, first: boolean): void {
  const w = ensureWindow(work);
  w.setFocusable(false);
  const overlay = overlayRect(w);
  companion = { on: true, work, message: { on: true, overlay, from: { x: from.x - overlay.x, y: from.y - overlay.y }, first } };
  sendCompanion();
  // (a page still loading is shown as it says it is ready)
  if (pageReady && !w.isVisible()) w.showInactive();
  // A lesson from a pick that had stepped aside (the window hidden, the student in another app)
  // shows again with the tutor: its marks and dock stay aside in the page until they come back.
  if (pageReady && lesson && aside) {
    w.webContents.send("screen-teach:aside", true);
    w.webContents.send("screen-teach:present", false);
  }
  // The talk chord and ⌃⌥M: the companion dock's mic, with no lesson on too.
  registerTalkKey();
}

/** The cursor went to another display (no lesson on): the window follows it. Every point the page
 *  holds from before is off by the move; companion.ts sends its glances again. */
export function moveCompanionOverlay(work: Rectangle): void {
  if (!companion?.on) return;
  const w = ensureWindow(work);
  companion.work = work;
  companion.message = { on: true, overlay: overlayRect(w), first: false };
  sendCompanion();
}

/** The companion is off (its tutor has flown home): the window hides, unless a lesson is on, and
 *  takes keys again for a lesson started without it. */
export function hideCompanionOverlay(): void {
  companion = null;
  setCardBox(null);
  // (a lesson on screen keeps ⌃⌥M and the chord; they go with the lesson then)
  if (!lesson) unregisterTalkKey();
  const w = live();
  if (!w) return;
  w.setFocusable(true);
  if (lesson) return;
  interactive = false;
  applyMouse();
  w.hide();
  syncBoard();
}

/** The work area the window covers while the tutor is on (the cursor's display, or the lesson's),
 *  or null with the tutor off. */
export const companionArea = (): Rectangle | null => (companion?.on ? companion.work : null);

/** The lesson's board window, if there is one and the board is in it (the companion counts it as
 *  Tutornote's own). */
export const boardWindow = (): BaseWindow | null => {
  const b = liveBoard();
  return b && b.place === "float" ? b.host : null;
};

/** The lesson's see-through window, if there is one (never counted as Tutornote's own: it covers
 *  the whole display, and every click goes through it). */
export const overlayWindow = (): BrowserWindow | null => live();

/** A point in screen points as the page's own (its window's top left off), or null without one. */
export function localPoint(p: Point): Point | null {
  const w = live();
  if (!w) return null;
  const b = w.getBounds();
  return { x: p.x - b.x, y: p.y - b.y };
}

/** A point of the page's own in screen points, or null without the window. */
export function screenPoint(p: Point): Point | null {
  const w = live();
  if (!w) return null;
  const b = w.getBounds();
  return { x: p.x + b.x, y: p.y + b.y };
}

/** A read in the page's own points, or null without the window. */
export function localRead(read: ScreenRead): ScreenRead | null {
  const w = live();
  return w ? toLocal(read, w.getBounds()) : null;
}

/** Send the page something (companion.ts): only once it has loaded, else it is dropped (the page
 *  asks for what it needs as it starts: companion-state). */
export function sendToPage(channel: string, payload: unknown): void {
  const w = live();
  if (w && pageReady) w.webContents.send(channel, payload);
}

/** The lesson on screen: its run, the window it reads and that window's app, or null. */
export function screenTeachLesson(): { run: number; window: number; app: string } | null {
  return lesson ? { run: lesson.run, window: lesson.window, app: lesson.app } : null;
}

/** The call came from the lesson's own page. */
export const fromScreenTeachPage = (event: { sender: WebContents }): boolean => fromLesson(event);

/** The page has the clicks now (the pointer is over its card, its dock, its board, as it says, or
 *  over the card as this side reads the cursor: cardBox): a press then is the page's, not one on
 *  the app below. */
export const overlayInteractive = (): boolean => interactive || overCard;

/** Where a restart from a tap on the lesson's window finds the companion's careful read of it
 *  (companion.ts, at install): `source(window, since)`, a read begun at `since` or later that still
 *  shows the window as it is, or null. */
export function useCarefulReads(source: (window: number, since: number) => Promise<ScreenRead> | null): void {
  carefulRead = source;
}

/** The tutor went off (companion.ts turnOff): its card's box and the kept Accessibility answer go. */
export function companionWentOff(): void {
  setCardBox(null);
  axAnswer = null;
}

/** The last press (a moment ago) was on the page's own controls: so is the tap it makes. */
export const pressWasThePage = (): boolean => Boolean(companion?.on && lastPress?.page && Date.now() - lastPress.at < PRESS_TAP_MS);

function onPress(_press: ScreenPress): void {
  lastPress = { at: Date.now(), page: overlayInteractive() };
}

export function installScreenTeach(): void {
  prefs = loadBoardPrefs();
  watchEvents.on("tap", onTap);
  watchEvents.on("scroll", onScroll);
  watchEvents.on("front", onFront);
  // The talk chord, while the talk key is on (registerTalkKey).
  watchEvents.on("chord", onChord);
  app.on("browser-window-focus", (_event, focused) => onOwnFocus(focused));
  // (before companion.ts's own listener: it asks pressWasThePage of the same press's tap)
  watchEvents.on("press", onPress);

  /*
    The Board tab (windows.ts tells of it through appEvents; it imports nothing from here).
  */
  // The student left the main window: judged a moment later (onMainLeft).
  app.on("browser-window-blur", (_event, blurred) => {
    if (blurred !== getMainWindow()) return;
    clearTimeout(mainBlurTimer);
    mainBlurTimer = setTimeout(onMainLeft, MAIN_BLUR_SETTLE_MS);
  });
  // Its ×, its middle click, ⌘W on it.
  appEvents.on("board-tab-close", () => {
    if (liveBoard()) closeBoardHere();
  });
  // The away tab chosen (the board is in its own window): Open in Tutornote.
  appEvents.on("board-tab-open", () => openInTutornote());
  // The Board tab shown, or another tab instead, by the student: where they are now is judged as
  // for a focus of the window. A tab that left because the board was closed, popped out or folded
  // is not the student going elsewhere (the lesson goes on), so that is not judged.
  appEvents.on("board-tab-selection", (e: { active: boolean; undocked: boolean }) => {
    if (e.undocked || !lesson || !getMainWindow()?.isFocused()) return sendPlace();
    clearTimeout(mainFocusTimer);
    mainFocusTimer = setTimeout(judgeMain, MAIN_FOCUS_SETTLE_MS);
  });
  // The main window minimized, hidden or closing (not for ⌘Q): the board moves to its own window.
  appEvents.on("board-host-leaving", () => {
    const b = liveBoard();
    if (b?.place === "tab" && !quitting) {
      toFloat(b);
      syncBoard();
    }
  });
  // The main window made again (closed, then the Dock): its bar starts empty, and a board floating
  // for this lesson has its away tab there again.
  appEvents.on("main-window-created", () => {
    const b = liveBoard();
    if (inBar && b?.place === "float") showBoardTab({ title: boardTitleNow, surface: boardColor, away: true });
  });
  // The main window moved or resized: over what is read now, or not.
  appEvents.on("main-window-bounds", () => {
    if (getMainWindow()?.isFocused() && boardTabActive()) judgeMain();
    else sendPlace();
  });
  // Signing out: the lesson ends, the tutor turns off, and the lesson's page goes with its board.
  appEvents.on("main-signed-out", () => {
    if (!live()) return;
    closeScreenTeach();
    dropWindow();
  });
  // Where the board is, now: asking it is how the page says it knows the board's tab.
  ipcMain.handle("screen-teach:board-place-now", (event): BoardPlace | null => {
    if (!fromLesson(event)) throw new Error("not allowed");
    pageKnowsPlace = true;
    lastPlaceSent = "";
    return placeNow();
  });
  // The board's own Pop out or Open in Tutornote (the student's click on it).
  ipcMain.on("screen-teach:board-move", (event, value: unknown) => {
    const to = boardMoveOf(value);
    if (!fromLesson(event) || !to || !lesson || !liveBoard()) return;
    if (to === "tab") openInTutornote();
    else popOut();
  });
  ipcMain.on("screen-teach:back-to-app", (event) => {
    if (fromLesson(event)) backToApp();
  });

  // A tap the page found no paragraph under (words it has not read: the student scrolled to
  // them): the lesson starts afresh from there.
  ipcMain.on("screen-teach:pick-at", (event, value: unknown) => {
    const current = lesson;
    const w = live();
    const p = (value ?? {}) as Record<string, unknown>;
    if (!fromLesson(event) || !current || !w || p.run !== current.run || !finite(p.x) || !finite(p.y)) return;
    const b = w.getBounds();
    restartAt(current, { x: b.x + p.x, y: b.y + p.y }, "tap on words not read yet");
  });

  ipcMain.handle("screen-teach:ready", (event) => {
    if (!fromLesson(event)) throw new Error("not allowed");
    pageReady = true;
    clearTimeout(readyTimer);
    const w = live();
    // (a page loaded afresh while the student is in another app: away, not with the lesson)
    if (lesson && aside) w?.webContents.send("screen-teach:present", false);
    if ((pending || companion?.on) && w && !w.isVisible()) w.showInactive();
    syncBoard();
    // (and the companion's state again, for a page that listens before it asks)
    sendCompanion();
    // A page that never asks for the companion's state is older than the companion: the tutor
    // shows nothing over other apps then, and only a rebuilt renderer will.
    if (companion?.on) {
      const page = w;
      setTimeout(() => {
        if (companion?.on && !pageAsked && live() === page && pageReady) {
          console.warn("[companion] the lesson page does not know the companion: rebuild the renderer (scripts/build-renderer.sh)");
        }
      }, 4_000).unref();
    }
    return pending;
  });

  // Companion mode: what the page is to show of the companion, as it starts (a reload included),
  // or null when the companion is off. Asked for next to ready (a page older than the companion
  // never asks).
  ipcMain.handle("screen-teach:companion-state", (event): CompanionMessage | null => {
    if (!fromLesson(event)) throw new Error("not allowed");
    pageAsked = true;
    const message = companion?.message ?? null;
    if (companion) companion.message = { on: companion.message.on, overlay: companion.message.overlay, first: false };
    // (companion.ts tells this page again what the cursor is over)
    appEvents.emit("screen-teach-companion-asked");
    return message;
  });

  // Companion mode: the page has a text field in use (a question typed to the tutor), and the window
  // takes the keys until it says otherwise; the rest of the time it never does, so the student's
  // arrow keys reach the app being read. A panel takes them without bringing Tutornote to the front
  // (Electron's focus skips that for one), so the app being read stays the one in front. Giving them
  // back takes more than setFocusable(false), which only keeps the window from taking them again
  // (Electron 44 knows no way to give them up): blur does, by ordering the window out and back in
  // behind the others at its level (the floating level, where it is alone but for explain.ts's
  // panel), and the keys go back to the app in front.
  ipcMain.on("screen-teach:want-keys", (event, on: unknown) => {
    const w = live();
    if (!fromLesson(event) || !w || typeof on !== "boolean" || !companion?.on) return;
    keysMovedAt = Date.now();
    w.setFocusable(on);
    if (on) w.focus();
    else if (w.isFocused()) w.blur();
  });

  // What the page's board is doing (boardStateOf): up or not, zoomed or not, for which run, and
  // its colour. The board's window follows it (syncBoard), for the lesson on screen only.
  ipcMain.on("screen-teach:board", (event, value: unknown) => {
    const s = boardStateOf(value);
    if (!fromLesson(event) || !lesson || !s || s.run !== lesson.run) return;
    boardRun = s.run;
    boardWanted = s.show;
    // (the page has had its board down since the student closed it: its next show is a new one)
    if (!s.show && closeHold?.run === s.run) releaseHold();
    if (s.background && s.background !== boardColor && opaqueColor(s.background)) {
      boardColor = s.background;
      const b = liveBoard();
      b?.host.setBackgroundColor(boardColor);
      b?.view.setBackgroundColor(boardColor);
      // (the Board tab's fill, which runs into the board's head)
      setBoardTabInfo({ surface: boardColor });
    }
    // Something new went up on it (a page older than the count sends none).
    if (s.show && s.drawn !== undefined && (lastDrawn?.run !== s.run || lastDrawn.drawn !== s.drawn)) {
      lastDrawn = { run: s.run, drawn: s.drawn };
      freshDrawing = true;
    }
    // (in a tab, a zoom has no effect on any window: applyZoom)
    applyBoardFull(s.full);
    syncBoard();
  });

  ipcMain.handle("screen-teach:turn", (event, value: unknown): Promise<ScreenTurnResult> => {
    if (!fromLesson(event)) throw new Error("not allowed");
    const req = turnRequestOf(value);
    if (!req) return Promise.resolve({ ok: false, reason: "failed" });
    const current = lesson;
    if (!current || current.run !== req.run) return Promise.resolve({ ok: false, reason: "stale" });
    // The page asks for one move at a time, but never waits in line for the student: a wait for
    // their turn still going (or still to start) is for a move the lesson no longer wants.
    current.waiting?.abort();
    const waiting = req.how === "manual" ? new AbortController() : null;
    current.waiting = waiting;
    return queued(current, () =>
      turn(req, waiting).finally(() => {
        current.turnedAt = Date.now();
      }),
    ).finally(() => {
      if (current.waiting === waiting) current.waiting = null;
    });
  });

  // `opts.fast`: a quick check of where the words are now (after a scroll), not words to teach:
  // the board's place and the companion's glance keep the last accurate read.
  ipcMain.handle("screen-teach:reread", (event, run: unknown, opts: unknown): Promise<ScreenRead | null> => {
    if (!fromLesson(event)) throw new Error("not allowed");
    const current = lesson;
    if (!current || current.run !== run) return Promise.resolve(null);
    const fast = (typeof opts === "object" && opts !== null ? (opts as { fast?: unknown }).fast : false) === true;
    return queued(current, async () => {
      try {
        const read = await readWindow(current.window, fast ? { fast: true } : undefined);
        if (!fast) noteRead(current, read);
        const w = live();
        if (lesson === current && w && !fast) appEvents.emit("screen-teach-read", read);
        return lesson === current && w ? toLocal(read, w.getBounds()) : null;
      } catch (e) {
        console.warn(`[screen-teach] read again failed: ${e instanceof ScreenReadError ? e.code : (e as Error).message}`);
        return null;
      }
    });
  });

  ipcMain.handle("screen-teach:allow-turning", async (event): Promise<boolean> => {
    if (!fromLesson(event)) throw new Error("not allowed");
    // (switched on in System Settings, or not: the next pick asks afresh)
    axAnswer = null;
    const allowed = await accessibilityAllowed(true);
    if (allowed && pending) pending.canTurn = true;
    return allowed;
  });

  ipcMain.on("screen-teach:started", (event) => {
    if (fromLesson(event) && lesson) appEvents.emit("screen-teach-started");
  });

  ipcMain.on("screen-teach:interactive", (event, on: unknown) => {
    if (!fromLesson(event) || typeof on !== "boolean" || on === interactive) return;
    interactive = on;
    applyMouse();
  });

  // The companion's card after each paint ({x, y, w, h}, the page's own points), or null once it
  // has gone: the window takes the clicks over it from now on (cardBox).
  ipcMain.on("screen-teach:card-box", (event, value: unknown) => {
    const w = live();
    if (!fromLesson(event) || !w) return;
    if (value === null) return setCardBox(null);
    const box = (value ?? {}) as Record<string, unknown>;
    if (!finite(box.x) || !finite(box.y) || !finite(box.w) || !finite(box.h) || box.w < 0 || box.h < 0) return;
    const b = w.getBounds();
    setCardBox({ x: box.x + b.x, y: box.y + b.y, w: box.w, h: box.h });
  });

  ipcMain.on("screen-teach:open-settings", (event, which: unknown) => {
    if (!fromLesson(event) || (which !== "screen" && which !== "accessibility")) return;
    void shell.openExternal(SETTINGS_URLS[which]);
  });

  // A link in the lesson (a sticky wall's) opens in the main window, as any route of the app.
  ipcMain.on("screen-teach:open-in-main", (event, where: unknown) => {
    if (!fromLesson(event) || typeof where !== "string" || where.length > 2048 || !where.startsWith("/")) return;
    let url: URL;
    try {
      url = new URL(where, APP_ORIGIN);
      if (originOf(url.href) !== APP_ORIGIN) return;
    } catch {
      return;
    }
    getMainWindow()?.show();
    navigateTo(`${url.pathname}${url.search}${url.hash}`);
  });

  // Only the lesson on screen: a close sent as the page heard "close" must not drop the
  // next pick's lesson while it opens.
  ipcMain.on("screen-teach:close", (event) => {
    if (fromLesson(event) && lesson) closeScreenTeach();
  });
}
