/*
  The tutor the floating blob draws (static/blob.html), kept to the one that follows the cursor.

  The tutor on the cursor is the student's main tutor, in its look and colour (the web app's
  components/screen/CompanionPointer.tsx: useMainAvatar(), lib/guide/avatars.ts). Every page of the
  app tells the desktop which one that is as it loads and whenever the student picks another
  (avatars.ts tellDesktop, through window.anothernotes.tutorLook({look, base})), and the blob shows
  the same tutor from its own copies: every look in both of its colours, drawn from the web app at
  the bundled commit (scripts/static-tutors.mjs). So a look and a colour are taken from a page only
  when they are one of those 14, and the blob is only ever told one of its own copies' names (the
  founder, 2026-11-17: "fix the part where this is a different icon from what follows your cursor").

  No Electron here, so the rules are tested on their own (Tutornote_test_suite apple-desktop/
  tutorLook.test.ts); blobTutor.ts hears the pages and keeps the answer.
*/

/**
 * The web app's tutors (lib/guide/avatars.ts AVATARS at the bundled commit): each look's name and
 * its two colours, its own and the one it wears when the student's other tutor has the same look.
 * The colour is all the drawing takes from a palette (TutorCharacter uses only palette.base).
 */
export const TUTOR_LOOKS: Readonly<Record<string, { readonly name: string; readonly bases: readonly [string, string] }>> = Object.freeze({
  folio: { name: "Folio", bases: ["#1f9d6b", "#e5533f"] },
  nib: { name: "Nib", bases: ["#e2671f", "#0f9b8e"] },
  sprout: { name: "Sprout", bases: ["#e5533f", "#3f84ee"] },
  pip: { name: "Pip", bases: ["#3f84ee", "#de5a96"] },
  bramble: { name: "Bramble", bases: ["#8b5cf6", "#478f2e"] },
  comet: { name: "Comet", bases: ["#c2459f", "#0f9b8e"] },
  mochi: { name: "Mochi", bases: ["#5b63d6", "#e2671f"] },
});

export type TutorLook = { look: string; base: string };

/** Before any page has said: the web app's own default (its default pair's first tutor, Marnie,
 *  who wears Nib in Nib's own colour), which is also what a student who never chose one sees. */
export const DEFAULT_TUTOR: TutorLook = Object.freeze({ look: "nib", base: "#e2671f" });

const known = (look: string): boolean => Object.prototype.hasOwnProperty.call(TUTOR_LOOKS, look);

/** A page's {look, base} when it is one of the 14 the blob can draw (the colour in any case);
 *  anything else is null. */
export function tutorLookOf(value: unknown): TutorLook | null {
  if (typeof value !== "object" || value === null) return null;
  const { look, base } = value as { look?: unknown; base?: unknown };
  if (typeof look !== "string" || typeof base !== "string" || look.length > 16 || base.length !== 7) return null;
  if (!known(look)) return null;
  const colour = base.toLowerCase();
  return TUTOR_LOOKS[look].bases.includes(colour) ? { look, base: colour } : null;
}

/** The tutor the cursor's own drawing shows (the lesson page's .screen-companion-cursor .tut-char):
 *  its data-look, and its colour as the web app names that drawing's gradients ("tut", the colour's
 *  six digits, then the drawing's own id: components/guide/TutorCharacter.tsx). Null unless one of
 *  the 14. */
export function cursorTutorOf(look: unknown, gradient: unknown): TutorLook | null {
  if (typeof gradient !== "string") return null;
  const digits = /^tut([0-9a-f]{6})/i.exec(gradient);
  return digits ? tutorLookOf({ look, base: `#${digits[1]}` }) : null;
}

/** The name the blob knows a copy by (its template's data-tutor): "nib:#e2671f". */
export const tutorKey = (t: TutorLook): string => `${t.look}:${t.base}`;

/** The tutor's own name, for the blob's menu ("Close Nib"). */
export const tutorName = (t: TutorLook): string => (known(t.look) ? TUTOR_LOOKS[t.look].name : "the tutor");

/** The web app's "theme" setting when it is one the app knows (public/theme-boot.js), else null
 *  (none chosen: the light page). */
export function themeOf(value: unknown): string | null {
  return value === "light" || value === "dark" || value === "dark-grey" || value === "system" ? value : null;
}

/** Whether the app's pages are dark with that setting, as the web app works it out (public/
 *  theme-boot.js, lib/screen/theme.ts darkFromPref): dark, dark grey, or the system's when it
 *  follows the system. A dark page gives the tutor a light rim and a darker shadow under it. */
export const themeIsDark = (pref: string | null, systemDark: boolean): boolean =>
  pref === "dark" || pref === "dark-grey" || (pref === "system" && systemDark);
