/**
 * MASTERFILE §8.10 — the two-to-four shell.
 *
 * A two-year-old cannot read, cannot reliably tap a 64 dp target, does not
 * understand that the person in the rectangle is elsewhere, and will end a call
 * by walking away from the tablet.
 *
 * Everything the product has built so far assumes a child who can read a little,
 * choose from a list, and understand a screen as a place. Below about five, none
 * of that holds — so this is a different shell, not a smaller one.
 */

export const TODDLER_MAX_AGE = 4;
export const isToddler = (age: number) => age <= TODDLER_MAX_AGE;

/**
 * One control. Not a menu with one item — one control, filling most of the
 * screen, that starts a call to whoever is reachable.
 */
export const TAP_TARGET_PX = 180;
export const MAX_CONTROLS_ON_SCREEN = 2;

export type ToddlerControl = 'call' | 'watch_again' | 'nothing';

export interface ToddlerScreen {
  /** No text is required to use it. Any words present are for a nearby adult. */
  controls: ToddlerControl[];
  /** His face, large, live if reachable and a still photograph if not. */
  faceState: 'live' | 'photo' | 'sleeping';
  /** Read aloud by the device, because she cannot read it. */
  spoken: string;
  tapTargetPx: number;
}

export function toddlerScreen(
  reachable: boolean, hasRecording: boolean, childLocalHour: number,
): ToddlerScreen {
  // Between 19:00 and 06:00 his face sleeps rather than showing as unavailable.
  // "Unavailable" is an adult concept; a sleeping picture is one she has met.
  const night = childLocalHour >= 19 || childLocalHour < 6;
  const controls: ToddlerControl[] = [];
  if (reachable && !night) controls.push('call');
  if (hasRecording) controls.push('watch_again');
  return {
    controls: controls.length ? controls : ['nothing'],
    faceState: night ? 'sleeping' : reachable ? 'live' : 'photo',
    spoken: night ? 'Daddy is asleep. You can see him in the morning.'
      : reachable ? 'Tap Daddy to talk to him.'
      : hasRecording ? 'Daddy left you something.'
      : 'Daddy is busy. He will be back.',
    tapTargetPx: TAP_TARGET_PX,
  };
}

/**
 * §8.10.1 — she ends calls by walking away.
 *
 * A toddler does not press "end". She loses interest and goes, and the call runs
 * on with a parent talking to an empty room, which is a small and specific
 * humiliation.
 *
 * So the shell watches for absence — no face, no sound, no touch — and offers
 * the ADULT the ending. It never ends the call itself: sometimes she is fetching
 * something to show him, and hanging up on that would be much worse.
 */
export const ABSENCE_SECONDS_BEFORE_PROMPT = 45;

export function absencePrompt(secondsAbsent: number): {
  offer: boolean; line: string | null;
} {
  return secondsAbsent < ABSENCE_SECONDS_BEFORE_PROMPT
    ? { offer: false, line: null }
    : { offer: true,
        line: 'She seems to have wandered off. Wait a little, or say goodnight '
            + 'and we will tell her you did.' };
}

/**
 * When he ends a call she has walked away from, she gets told he said goodbye —
 * because otherwise, from her point of view, he simply vanished.
 */
export function goodbyeOnHerBehalf(): { spoken: string; artifact: true } {
  return { spoken: 'Daddy said goodnight. He will see you soon.', artifact: true };
}

/** §8.10.2 — what the toddler shell deliberately does NOT have. */
export const NOT_IN_TODDLER_SHELL = [
  'games', 'homework', 'calendar', 'wants_and_needs', 'journal', 'storyteller',
  'colouring', 'settings', 'text_input', 'lists', 'menus', 'scrolling',
] as const;

export function availableToToddler(feature: string): boolean {
  return !(NOT_IN_TODDLER_SHELL as readonly string[]).includes(feature);
}

/**
 * The one exception, and it is the important one: **being read to**. A
 * two-year-old cannot play chess and does not want to, but she will sit through a
 * story, and shared reading (§9.13.2) is the single most valuable thing at this
 * age. It runs with her page-turn button and nothing else on screen.
 */
export const TODDLER_KEEPS = ['call', 'shared_reading', 'watch_again'] as const;

/** She graduates by age, not by achievement. There is nothing to unlock. */
export function graduatesAt(): number { return TODDLER_MAX_AGE + 1; }
