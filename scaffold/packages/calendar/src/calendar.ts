/**
 * MASTERFILE §8.7, §9.4 — the calendar primitive, and her birthday.
 *
 * `monthGrid()` is the ONE month renderer in the product. The child's calendar
 * (§9.4), the guardian's, and the birthday picker below all read it. A separate
 * throwaway picker would have been quicker and would have drifted from the real
 * calendar within two increments.
 *
 * THE PROBLEM THE PICKER SOLVES: a six-year-old finding a date six years in the
 * past is genuinely hard. Scrolling back 72 months is 72 taps, and she may not
 * know the year at all. But she almost certainly knows the MONTH and the NUMBER.
 * So the year is derived rather than asked for, and she only ever makes choices
 * she can actually make.
 */

// ================================================== the shared month grid ===
export interface MonthMeta { index: number; name: string; short: string; days: number }

/** Names, not numbers. A child reads "March", not "03". */
export const MONTHS: MonthMeta[] = [
  { index: 1,  name: 'January',   short: 'Jan', days: 31 },
  { index: 2,  name: 'February',  short: 'Feb', days: 28 },
  { index: 3,  name: 'March',     short: 'Mar', days: 31 },
  { index: 4,  name: 'April',     short: 'Apr', days: 30 },
  { index: 5,  name: 'May',       short: 'May', days: 31 },
  { index: 6,  name: 'June',      short: 'Jun', days: 30 },
  { index: 7,  name: 'July',      short: 'Jul', days: 31 },
  { index: 8,  name: 'August',    short: 'Aug', days: 31 },
  { index: 9,  name: 'September', short: 'Sep', days: 30 },
  { index: 10, name: 'October',   short: 'Oct', days: 31 },
  { index: 11, name: 'November',  short: 'Nov', days: 30 },
  { index: 12, name: 'December',  short: 'Dec', days: 31 },
];

/** US market scope (§1), so weeks begin on Sunday. */
export const WEEK_STARTS_ON = 0;
export const DOW_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export const isLeap = (y: number) =>
  (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;

export function daysInMonth(year: number, month: number): number {
  if (month === 2) return isLeap(year) ? 29 : 28;
  return MONTHS[month - 1].days;
}

export interface Cell {
  /** null for the leading and trailing blanks. */
  day: number | null;
  iso: string | null;
  dow: number;
  isToday: boolean;
  /** Set when a marker falls on this day. */
  markers: string[];
}

/**
 * One month, aligned to the week. Blanks are real cells rather than absent, so
 * every consumer gets a stable 7-column grid and nobody has to compute offsets.
 */
export function monthGrid(
  year: number, month: number, opts?: { today?: Date; markers?: Record<string, string[]> },
): { year: number; month: number; name: string; cells: Cell[]; weeks: number } {
  const total = daysInMonth(year, month);
  const firstDow = new Date(Date.UTC(year, month - 1, 1)).getUTCDay();
  const lead = (firstDow - WEEK_STARTS_ON + 7) % 7;
  const todayIso = opts?.today ? opts.today.toISOString().slice(0, 10) : null;

  const cells: Cell[] = [];
  for (let i = 0; i < lead; i++) {
    cells.push({ day: null, iso: null, dow: (WEEK_STARTS_ON + i) % 7,
      isToday: false, markers: [] });
  }
  for (let d = 1; d <= total; d++) {
    const iso = `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
    cells.push({ day: d, iso, dow: new Date(Date.UTC(year, month - 1, d)).getUTCDay(),
      isToday: iso === todayIso, markers: opts?.markers?.[iso] ?? [] });
  }
  while (cells.length % 7 !== 0) {
    cells.push({ day: null, iso: null, dow: cells.length % 7, isToday: false, markers: [] });
  }
  return { year, month, name: MONTHS[month - 1].name, cells, weeks: cells.length / 7 };
}

// ============================================== deriving the birth year =====
/**
 * She just told us how old she is (§8.5.2). That plus one yes/no question
 * resolves the year, so she is never asked to reason about a number she has no
 * way to know.
 *
 * "Have you had your birthday this year?" is a question a five-year-old can
 * answer with certainty, and it is the only ambiguity that exists.
 */
export function deriveBirthYear(
  age: number, hadBirthdayThisYear: boolean, now: Date,
): number {
  return now.getUTCFullYear() - age - (hadBirthdayThisYear ? 0 : 1);
}

/**
 * When a guardian has already entered a birth date it is AUTHORITATIVE (§8.5.2),
 * and the picker's job changes: she is not entering data, she is placing her own
 * birthday on a calendar. Highlighting the right month makes the hunt short and
 * successful without doing it for her — scaffolding, in the §21.5 sense, and it
 * should fade with age.
 */
export function hintMonth(birthDate: string | null): number | null {
  if (!birthDate) return null;
  const m = Number(birthDate.slice(5, 7));
  return m >= 1 && m <= 12 ? m : null;
}

export const HINT_FADES_AT_AGE = 9;

export function shouldHint(birthDate: string | null, age: number | null): boolean {
  return Boolean(birthDate) && (age === null || age < HINT_FADES_AT_AGE);
}

// ================================================== the birthday picker =====
export type PickerStep = 'month' | 'day' | 'year_check' | 'done';

export interface BirthdayPicker {
  step: PickerStep;
  month: number | null;
  day: number | null;
  year: number | null;
  /** Guardian-entered, if any. Authoritative for the record. */
  authoritative: string | null;
  /** Her age, used to derive the year. */
  age: number | null;
}

export function beginPicker(authoritative: string | null, age: number | null): BirthdayPicker {
  return { step: 'month', month: null, day: null, year: null, authoritative, age };
}

export type PickerError = 'no_such_day' | 'in_the_future' | 'no_age';

export function pickMonth(p: BirthdayPicker, month: number): BirthdayPicker {
  if (month < 1 || month > 12) return p;
  return { ...p, month, day: null, step: 'day' };
}

export function pickDay(
  p: BirthdayPicker, day: number, now: Date,
): { ok: true; picker: BirthdayPicker } | { ok: false; reason: PickerError } {
  if (p.month === null) return { ok: false, reason: 'no_such_day' };
  // Use a leap year as the ceiling so 29 February is selectable before the year
  // is known. The year check that follows resolves whether it exists.
  if (day < 1 || day > daysInMonth(2024, p.month)) {
    return { ok: false, reason: 'no_such_day' };
  }
  // If the year is already known from the guardian's date, skip the question.
  if (p.authoritative) {
    const y = Number(p.authoritative.slice(0, 4));
    return { ok: true, picker: { ...p, day, year: y, step: 'done' } };
  }
  if (p.age === null) return { ok: false, reason: 'no_age' };
  return { ok: true, picker: { ...p, day, step: 'year_check' } };
}

export function answerYearCheck(
  p: BirthdayPicker, hadBirthdayThisYear: boolean, now: Date,
): { ok: true; picker: BirthdayPicker } | { ok: false; reason: PickerError } {
  if (p.age === null) return { ok: false, reason: 'no_age' };
  const year = deriveBirthYear(p.age, hadBirthdayThisYear, now);
  const iso = `${year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
  if (Date.parse(iso) > now.getTime()) return { ok: false, reason: 'in_the_future' };
  return { ok: true, picker: { ...p, year, step: 'done' } };
}

export function pickedDate(p: BirthdayPicker): string | null {
  if (p.month === null || p.day === null || p.year === null) return null;
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

/**
 * §8.5.2 again: the guardian's date wins for the record, hers is kept, and the
 * disagreement is RECORDED rather than corrected on screen.
 *
 * She is not told she got her own birthday wrong. If she puts it a day out, the
 * calendar shows the real one and nobody mentions it — being corrected about
 * your own birthday, by software, in front of nobody, is a small humiliation
 * with no upside.
 */
export function resolveBirthday(p: BirthdayPicker): {
  ofRecord: string | null; asShePlacedIt: string | null; disagrees: boolean;
} {
  const hers = pickedDate(p);
  const ofRecord = p.authoritative ?? hers;
  return { ofRecord, asShePlacedIt: hers,
    disagrees: Boolean(p.authoritative && hers && p.authoritative !== hers) };
}

// ================================================ the permanent marker ======
export interface BirthdayEvent {
  kind: 'birthday';
  childId: string;
  /** Month and day. The year lives on the child record, not the event. */
  month: number;
  day: number;
  /** §8.6 — her colour, on an allowed placement. */
  colourId: string | null;
  /** Annual, forever. */
  recurrence: 'yearly';
  /** A birthday is a fact, so a guardian cannot delete it. */
  deletableByGuardian: false;
  /** She placed it herself. Recorded because it matters to her. */
  placedByChild: boolean;
  markedAt: string;
}

/**
 * 29 February needs an explicit rule or the event silently vanishes in three
 * years out of four.
 *
 * The product celebrates on 28 February in a common year. That is the choice
 * more families make, and — more to the point — it keeps the birthday inside the
 * correct month, which is what a child cares about.
 */
export const LEAP_DAY_OBSERVED_ON: { month: number; day: number } =
  { month: 2, day: 28 };

export function markBirthday(
  childId: string, p: BirthdayPicker, colourId: string | null, at: string,
): { ok: true; event: BirthdayEvent } | { ok: false; reason: 'incomplete' } {
  const r = resolveBirthday(p);
  if (!r.ofRecord) return { ok: false, reason: 'incomplete' };
  return { ok: true, event: {
    kind: 'birthday', childId,
    month: Number(r.ofRecord.slice(5, 7)),
    day: Number(r.ofRecord.slice(8, 10)),
    colourId, recurrence: 'yearly',
    deletableByGuardian: false,
    placedByChild: Boolean(r.asShePlacedIt),
    markedAt: at,
  }};
}

/** The ISO date this birthday falls on in a given year. */
export function occurrenceIn(e: BirthdayEvent, year: number): string {
  if (e.month === 2 && e.day === 29 && !isLeap(year)) {
    return `${year}-${String(LEAP_DAY_OBSERVED_ON.month).padStart(2, '0')}-`
      + `${String(LEAP_DAY_OBSERVED_ON.day).padStart(2, '0')}`;
  }
  return `${year}-${String(e.month).padStart(2, '0')}-${String(e.day).padStart(2, '0')}`;
}

export function sleepsUntilBirthday(e: BirthdayEvent, todayIso: string): number {
  const y = Number(todayIso.slice(0, 4));
  let next = occurrenceIn(e, y);
  if (next < todayIso) next = occurrenceIn(e, y + 1);
  return Math.round((Date.parse(next) - Date.parse(todayIso)) / 86_400_000);
}

/**
 * §9.4 — her calendar begins with her own birthday, not a custody exchange.
 *
 * That ordering is deliberate and it is the reason this step sits in onboarding
 * at all. The first entry a child ever sees in a co-parenting product should be
 * a thing she is looking forward to.
 */
export function firstCalendarEntry(e: BirthdayEvent): {
  label: string; markers: string[];
} {
  return { label: 'My birthday', markers: ['birthday'] };
}
