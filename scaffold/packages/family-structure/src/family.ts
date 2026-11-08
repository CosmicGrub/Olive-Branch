/**
 * FAMILY STRUCTURE AND AGE BANDS (suites J and K). Design:
 * docs/superpowers/specs/2026-11-07-age-bands-and-family-structure-design.md.
 * Mockups: docs/superpowers/mockups/overhaul2 (r2AgeBands ... r2Birthday).
 *
 * Pure logic only (same posture as co-view and parent-learn): no I/O, no clock, no
 * storage. Every function that needs "today" takes it as an argument, as a
 * child-local ISO date string.
 *
 * ONE FUNCTION, deriveChildView(structure, ageBand, suites, rungs): what the child
 * sees = f(the family structure a guardian built, her age band, the suites a
 * guardian switched on, the ladder rungs she has been given). A guardian writes the
 * first three; the product writes the fourth, and only by permanent steps.
 *
 * Owner decisions 2026-11-07, each held by a test:
 *
 *  F1  The guardian ALONE edits the structure. Never the child, a step-parent, a
 *      sitter, a trusted adult, a helper, a court principal or the system.
 *  F2  The child's options follow the structure. She reads only what has been
 *      RELEASED to her; a held change is invisible until a guardian releases it,
 *      and a dated one until her local date reaches it.
 *  F3  "Hold until I've told her" is a real timing choice, and the default for a
 *      big change. Settings changes (birthday line, band hold) cannot be held.
 *  F4  Ladder rungs (MASTERFILE section 21) are permanent: derived from the rungs
 *      held, never from a band, a hold, an override or a suite switch. Every other
 *      age default here is a PROPOSAL a guardian may hold or change.
 *  F5  She only ever sees labels a guardian chose. No role word, no "step", "half",
 *      "caseworker" is ever emitted to her; a person with no label is not shown.
 *      Sitters, therapists and caseworkers are never in her people list.
 *  F6  A court order wins: a rhythm set by an order is locked and not editable.
 *  F7  A story that travels with a change is guardian-authored text only. This
 *      module generates no story and no content about a partner (it needs clinical
 *      review); it only bounds what a guardian wrote.
 *
 * Child-facing keys avoid every word in packages/globalaudit's
 * GLOBAL_CHILD_FORBIDDEN (no age, count, countdown, pending, total, ...), because
 * api.ts sweeps every child response; a test runs the sweep over derived views.
 */

// ================================================================ constants ==
export type AgeBand = 't34' | 't57' | 't812' | 't13';
export const AGE_BANDS: readonly AgeBand[] = ['t34', 't57', 't812', 't13'];

export type Area = 'reading' | 'games' | 'chat' | 'calendar' | 'people';
export const AREAS: readonly Area[] = ['reading', 'games', 'chat', 'calendar', 'people'];

export type Role = 'guardian' | 'parent' | 'step_parent' | 'relative' | 'trusted_adult'
  | 'sitter' | 'foster_parent' | 'caseworker' | 'therapist';
export const ROLES: readonly Role[] = ['guardian', 'parent', 'step_parent', 'relative',
  'trusted_adult', 'sitter', 'foster_parent', 'caseworker', 'therapist'];
/** Roles that work in the background: never in her people. */
export const BACKGROUND_ROLES: readonly Role[] = ['sitter', 'therapist', 'caseworker'];

export type ContactMode = 'live_call' | 'message' | 'postcard' | 'voice_line' | 'supervised_visit';
export const CONTACT_MODES: readonly ContactMode[] = ['live_call', 'message', 'postcard',
  'voice_line', 'supervised_visit'];

export type Pattern = 'none' | '2-2-3' | '2-2-5-5' | 'alternating_weeks' | 'week_on_week_off' | 'custom';
export const PATTERNS: readonly Pattern[] = ['none', '2-2-3', '2-2-5-5', 'alternating_weeks',
  'week_on_week_off', 'custom'];

export const MAX_HOMES = 4;
export const MAX_PEOPLE = 24;
export const MAX_LABEL = 30;
export const MAX_HOME_NAME = 40;
export const MAX_STORY_PAGES = 6;
export const MAX_STORY_PAGE_CHARS = 240;
/** How far ahead a dated change may be set (days). */
export const MAX_DATE_AHEAD_DAYS = 730;
/** How many days a released story stays on her My people screen. */
export const STORY_SHOWN_DAYS = 14;
/** The one place name for people who are far away or have no home. */
export const FAR_PLACE_NAME = 'Near and far';

// ================================================================== shapes ===
export interface Home { id: string; name: string; childSleeps: boolean }
export interface Away { until: string | null }
export interface Person {
  id: string;
  /** The name SHE uses, chosen by a guardian. Empty = not shown to her. */
  label: string;
  role: Role;
  homeId: string | null;
  contact: ContactMode[];
  away: Away | null;
}
export interface Rhythm {
  pattern: Pattern;
  exchangeDay: number | null;      // 0 = Sunday
  exchangeTime: string | null;     // 'HH:mm'
  source: 'guardian' | 'court_order';
}
export interface FamilyStructure {
  homes: Home[];
  people: Person[];
  rhythm: Rhythm;
  /** Per-area band override (a child can be ahead in reading, behind in social things). */
  areaBands: Partial<Record<Area, AgeBand>>;
  birthdayVisible: boolean;
  /** Hold a band move until a guardian releases it. Default true. */
  holdBandChange: boolean;
  /** The band a guardian last released her to; null until the first baseline. */
  releasedBand: AgeBand | null;
}

export const EMPTY_RHYTHM: Rhythm = Object.freeze({ pattern: 'none', exchangeDay: null,
  exchangeTime: null, source: 'guardian' }) as Rhythm;

export function emptyStructure(): FamilyStructure {
  return { homes: [], people: [], rhythm: { ...EMPTY_RHYTHM }, areaBands: {},
    birthdayVisible: true, holdBandChange: true, releasedBand: null };
}

// ============================================================ band table ====
export type HomeKind = 'icons3' | 'pictures' | 'words';
export type TileKey = 'call' | 'stories' | 'colour' | 'myDay' | 'play' | 'messages' | 'showTell'
  | 'homework' | 'myList' | 'myPeople' | 'more';
export const TILE_KEYS: readonly TileKey[] = ['call', 'stories', 'colour', 'myDay', 'play',
  'messages', 'showTell', 'homework', 'myList', 'myPeople', 'more'];

export interface BandDef {
  id: AgeBand;
  minYears: number;
  maxYears: number | null;
  /** Names a family would use, never clinical. */
  label: string;
  name: string;
  home: HomeKind;
  tiles: TileKey[];
  /** What each area looks like in this band. */
  areaModes: Record<Area, string>;
  /** Plain lines for the guardian's "At this band" card. */
  summary: string[];
}

/** The band table, as data. A proposal: a guardian may hold or override any of it. */
export const BAND_TABLE: readonly BandDef[] = [
  { id: 't34', minYears: 0, maxYears: 4, label: '3 to 4', name: 'Three big pictures', home: 'icons3',
    tiles: ['call', 'stories', 'colour'],
    areaModes: { reading: 'pictures', games: 'none', chat: 'none', calendar: 'none', people: 'call_only' },
    summary: ['Three big pictures, no words to read', 'Every picture speaks its own name',
      'The call is the biggest thing, with the face of the person she calls',
      'Nothing moves and nothing is a setting'] },
  { id: 't57', minYears: 5, maxYears: 7, label: '5 to 7', name: 'Pictures lead', home: 'pictures',
    tiles: ['myDay', 'play', 'messages', 'stories', 'showTell', 'homework', 'myList', 'myPeople', 'more'],
    areaModes: { reading: 'pictures_spoken', games: 'pairs', chat: 'pictures', calendar: 'my_day', people: 'my_people' },
    summary: ['Pictures lead and every word can be heard', 'Her colour of the day and favourite things',
      'Games for two, played in turns', 'No settings of her own yet'] },
  { id: 't812', minYears: 8, maxYears: 12, label: '8 to 12', name: 'Words and her own list', home: 'words',
    tiles: ['myDay', 'play', 'messages', 'stories', 'showTell', 'homework', 'myList', 'myPeople', 'more'],
    areaModes: { reading: 'words_beside', games: 'more', chat: 'short', calendar: 'weeks', people: 'my_people' },
    summary: ['Words sit beside the pictures', 'A calendar of her weeks', 'More games, in a quiet grid',
      'Her own list arrives at 10, and stays hers'] },
  { id: 't13', minYears: 13, maxYears: null, label: '13 and up', name: 'Mostly hers', home: 'words',
    tiles: ['myDay', 'play', 'messages', 'stories', 'showTell', 'homework', 'myList', 'myPeople', 'more'],
    areaModes: { reading: 'words', games: 'more', chat: 'full', calendar: 'own', people: 'my_people' },
    summary: ['Quiet: calendar, availability, a private journal', 'Her choices come first',
      'Each step up is hers, and permanent'] },
];

export function bandDef(b: AgeBand): BandDef {
  return BAND_TABLE.find((d) => d.id === b) as BandDef;
}

/** Whole years to her natural band. Fails closed to the YOUNGEST band on junk. */
export function bandForYears(years: unknown): AgeBand {
  if (typeof years !== 'number' || !Number.isFinite(years) || years < 0) return 't34';
  const y = Math.floor(years);
  if (y <= 4) return 't34';
  if (y <= 7) return 't57';
  if (y <= 12) return 't812';
  return 't13';
}

export function isAgeBand(x: unknown): x is AgeBand {
  return typeof x === 'string' && (AGE_BANDS as readonly string[]).includes(x);
}
export function isArea(x: unknown): x is Area {
  return typeof x === 'string' && (AREAS as readonly string[]).includes(x);
}

/**
 * Hold until I've told her. With the hold on, a move to a new band is invisible
 * until a guardian releases it: she stays at the band last released. A band a
 * guardian has not baselined yet follows her natural band.
 */
export function effectiveBand(natural: AgeBand, hold: boolean, released: AgeBand | null): AgeBand {
  if (!hold || released === null || !isAgeBand(released)) return natural;
  // A hold only ever delays a move UP: a held band never exceeds her natural one.
  return AGE_BANDS.indexOf(released) > AGE_BANDS.indexOf(natural) ? natural : released;
}

/** The band an area follows: the guardian's per-area override, else her band. */
export function areaBand(structure: Pick<FamilyStructure, 'areaBands'>, area: Area, band: AgeBand): AgeBand {
  const o = structure.areaBands?.[area];
  return isAgeBand(o) ? o : band;
}

/** What changes between two bands, area by area and tile by tile (for previews). */
export function diffBands(from: AgeBand, to: AgeBand): { area: Area; from: string; to: string }[] {
  const a = bandDef(from), b = bandDef(to);
  return AREAS.filter((r) => a.areaModes[r] !== b.areaModes[r])
    .map((r) => ({ area: r, from: a.areaModes[r], to: b.areaModes[r] }));
}

// ================================================================== rungs ===
export type Grant = 'own_list' | 'journal_absolute' | 'own_calendar' | 'publish_availability'
  | 'curate_archive' | 'own_export' | 'everything';
/** The section 21 ladder, ages in whole years. Mirrors packages/maturation LADDER. */
export const RUNG_AGES: readonly { age: number; grant: Grant }[] = [
  { age: 10, grant: 'own_list' }, { age: 13, grant: 'journal_absolute' },
  { age: 14, grant: 'own_calendar' }, { age: 15, grant: 'publish_availability' },
  { age: 16, grant: 'curate_archive' }, { age: 17, grant: 'own_export' },
  { age: 18, grant: 'everything' },
];

/** The rungs she has reached at a whole-year age. Only ever grows as years grow. */
export function rungsAt(years: unknown): Grant[] {
  if (typeof years !== 'number' || !Number.isFinite(years)) return [];
  return RUNG_AGES.filter((r) => years >= r.age).map((r) => r.grant);
}

// ================================================================= suites ====
export type SuiteKey = 'calls' | 'messages' | 'stories' | 'games' | 'showTell' | 'homework'
  | 'myList' | 'myPeople' | 'myDay' | 'birthday' | 'twoSkies' | 'postcards' | 'weeks';
export const SUITE_KEYS: readonly SuiteKey[] = ['calls', 'messages', 'stories', 'games', 'showTell',
  'homework', 'myList', 'myPeople', 'myDay', 'birthday', 'twoSkies', 'postcards', 'weeks'];
/** A suite is ON unless a guardian switched it off. */
export type Suites = Partial<Record<SuiteKey, boolean>>;
const suiteOn = (s: Suites | null | undefined, k: SuiteKey): boolean => !s || s[k] !== false;

// ============================================================ derive view ====
export type ChildButton = 'call' | 'chat' | 'postcard' | 'voice' | 'visit';
export interface ChildPerson { id: string; name: string; buttons: ChildButton[]; apart: boolean }
export interface ChildPlace { id: string; name: string; kind: 'home' | 'far'; people: ChildPerson[] }
export interface ChildView {
  band: AgeBand;
  home: {
    variant: HomeKind;
    tiles: TileKey[];
    heroPersonId: string | null;
    wordsBesidePictures: boolean;
    speakEveryWord: boolean;
    plainGreeting: boolean;
  };
  places: ChildPlace[];
  features: {
    twoSkies: boolean; pathHome: boolean; postcards: boolean; weeks: boolean;
    packingBuddy: boolean; myHelpers: boolean; voiceLine: boolean; scheduledVisits: boolean;
  };
  areas: Record<Area, { band: AgeBand; mode: string }>;
  ladder: {
    ownList: boolean; privateJournal: boolean; ownCalendar: boolean; publishAvailability: boolean;
    curateArchive: boolean; ownExport: boolean; everything: boolean;
  };
  birthday: { visible: boolean };
}

export interface DeriveOpts { today?: string }

const hasGrant = (rungs: readonly string[] | null | undefined, g: Grant) =>
  Array.isArray(rungs) && rungs.includes(g);

function isAway(p: Person, today?: string): boolean {
  if (!p.away) return false;
  if (p.away.until && today && p.away.until < today) return false;
  return true;
}

export function childButtons(p: Person): ChildButton[] {
  const c = new Set(p.contact);
  const out: ChildButton[] = [];
  if (c.has('supervised_visit')) out.push('visit');
  else if (c.has('live_call')) out.push('call');
  if (c.has('message')) out.push('chat');
  if (c.has('postcard')) out.push('postcard');
  if (c.has('voice_line')) out.push('voice');
  return out;
}

/** May she see this person at all? (F5) */
export function shownToChild(p: Person): boolean {
  return p.label.trim().length > 0 && !(BACKGROUND_ROLES as readonly string[]).includes(p.role);
}

export function deriveChildView(
  structure: FamilyStructure, ageBand: AgeBand, suites: Suites | null | undefined,
  rungs: readonly string[] | null | undefined, opts: DeriveOpts = {},
): ChildView {
  const band: AgeBand = isAgeBand(ageBand) ? ageBand : 't34';
  const def = bandDef(band);
  const s = structure ?? emptyStructure();
  const areas = {} as Record<Area, { band: AgeBand; mode: string }>;
  for (const a of AREAS) {
    const b = areaBand(s, a, band);
    areas[a] = { band: b, mode: bandDef(b).areaModes[a] };
  }

  const visible = (s.people ?? []).filter(shownToChild);
  const mk = (p: Person): ChildPerson => ({ id: p.id, name: p.label.trim(), buttons: childButtons(p), apart: isAway(p, opts.today) });
  const homesById = new Map((s.homes ?? []).map((h) => [h.id, h]));
  const places: ChildPlace[] = [];
  for (const h of s.homes ?? []) {
    const ppl = visible.filter((p) => p.homeId === h.id && !isAway(p, opts.today)).map(mk);
    if (ppl.length) places.push({ id: h.id, name: h.name.trim(), kind: 'home', people: ppl });
  }
  const far = visible.filter((p) => isAway(p, opts.today) || p.homeId === null || !homesById.has(p.homeId as string)).map(mk);
  if (far.length) places.push({ id: 'far', name: FAR_PLACE_NAME, kind: 'far', people: far });

  const callable = visible.map(mk).find((p) => p.buttons.includes('call') || p.buttons.includes('visit'));
  const heroPersonId = suiteOn(suites, 'calls') && callable ? callable.id : null;

  // ---- tiles -----------------------------------------------------------------
  const peopleMode = areas.people.mode;
  const tileOk = (t: TileKey): boolean => {
    switch (t) {
      case 'call': return heroPersonId !== null;
      case 'stories': return suiteOn(suites, 'stories');
      case 'colour': return true;
      case 'myDay': return areas.calendar.mode !== 'none' && suiteOn(suites, 'myDay');
      case 'play': return areas.games.mode !== 'none' && suiteOn(suites, 'games');
      case 'messages': return areas.chat.mode !== 'none' && suiteOn(suites, 'messages');
      case 'showTell': return suiteOn(suites, 'showTell');
      case 'homework': return suiteOn(suites, 'homework');
      // F4: her own list is a permanent rung. No suite switch can take it away.
      case 'myList': return hasGrant(rungs, 'own_list') || suiteOn(suites, 'myList');
      case 'myPeople': return peopleMode === 'my_people' && places.length > 0 && suiteOn(suites, 'myPeople');
      case 'more': return true;
    }
  };
  const tiles = def.tiles.filter(tileOk);
  if (hasGrant(rungs, 'own_list') && band !== 't34' && !tiles.includes('myList')) {
    tiles.splice(Math.min(tiles.indexOf('homework') + 1, tiles.length), 0, 'myList');
  }

  const young = band === 't34';
  const sleepingHomes = (s.homes ?? []).filter((h) => h.childSleeps).length;
  const anyApart = visible.some((p) => isAway(p, opts.today));
  const anyContact = (m: ContactMode) => visible.some((p) => p.contact.includes(m));
  const helpers = (s.people ?? []).some((p) => p.role === 'foster_parent' || p.role === 'caseworker');
  const readingBand = areas.reading.band;
  const features = {
    twoSkies: !young && anyApart && suiteOn(suites, 'twoSkies'),
    pathHome: !young && anyApart && suiteOn(suites, 'twoSkies'),
    postcards: !young && (anyApart || anyContact('postcard')) && suiteOn(suites, 'postcards'),
    weeks: !young && sleepingHomes > 1 && suiteOn(suites, 'weeks'),
    packingBuddy: !young && sleepingHomes > 1 && suiteOn(suites, 'weeks'),
    myHelpers: !young && helpers,
    voiceLine: !young && anyContact('voice_line'),
    scheduledVisits: !young && (s.people ?? []).some((p) => shownToChild(p) && p.contact.includes('supervised_visit')),
  };

  return {
    band,
    home: {
      variant: def.home,
      tiles,
      heroPersonId: young ? heroPersonId : null,
      wordsBesidePictures: readingBand === 't812' || readingBand === 't13',
      speakEveryWord: readingBand === 't34' || readingBand === 't57',
      plainGreeting: band === 't812' || band === 't13',
    },
    places: young ? [] : places,
    features,
    areas,
    ladder: {
      ownList: hasGrant(rungs, 'own_list'),
      privateJournal: hasGrant(rungs, 'journal_absolute'),
      ownCalendar: hasGrant(rungs, 'own_calendar'),
      publishAvailability: hasGrant(rungs, 'publish_availability'),
      curateArchive: hasGrant(rungs, 'curate_archive'),
      ownExport: hasGrant(rungs, 'own_export'),
      everything: hasGrant(rungs, 'everything'),
    },
    birthday: { visible: s.birthdayVisible !== false && suiteOn(suites, 'birthday') },
  };
}

// ================================================================= who =======
export interface Principal { roleName?: unknown; userId?: unknown; childId?: unknown }

/** F1. Only a guardian session with a user id edits the structure. */
export function canEditStructure(p: Principal | null | undefined): boolean {
  return !!p && typeof p === 'object' && p.roleName === 'guardian'
    && typeof p.userId === 'string' && p.userId.length > 0;
}
/** F2. Only the child herself reads the released structure, and only her own. */
export function canReadReleased(p: Principal | null | undefined, childId: unknown): boolean {
  return !!p && typeof p === 'object' && p.roleName === 'child'
    && typeof p.childId === 'string' && p.childId.length > 0 && p.childId === childId;
}

// ============================================================== validation ===
const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
// eslint-disable-next-line no-control-regex
const CTRL_RE = /[\u0000-\u001f\u007f\u2028\u2029]/;
export const isIsoDate = (x: unknown): x is string => {
  if (typeof x !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(x)) return false;
  const [y, m, d] = x.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
};
const dayNum = (iso: string): number => {
  const [y, m, d] = iso.split('-').map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / 86400000);
};
export const daysBetween = (a: string, b: string): number => dayNum(b) - dayNum(a);

export type Reason = string;
export type Verdict = { ok: true } | { ok: false; reason: Reason };
const ok: Verdict = { ok: true };
const no = (reason: Reason): Verdict => ({ ok: false, reason });

const isObj = (x: unknown): x is Record<string, unknown> => !!x && typeof x === 'object' && !Array.isArray(x);

export function validatePerson(p: unknown, homes: readonly Home[]): Verdict {
  if (!isObj(p)) return no('bad_person');
  if (typeof p.id !== 'string' || !ID_RE.test(p.id)) return no('bad_id');
  if (typeof p.label !== 'string' || p.label.length > MAX_LABEL || CTRL_RE.test(p.label)) return no('bad_label');
  if (typeof p.role !== 'string' || !(ROLES as readonly string[]).includes(p.role)) return no('bad_role');
  if (!Array.isArray(p.contact) || p.contact.length > CONTACT_MODES.length
    || p.contact.some((c) => typeof c !== 'string' || !(CONTACT_MODES as readonly string[]).includes(c))
    || new Set(p.contact).size !== p.contact.length) return no('bad_contact');
  if (p.homeId !== null && (typeof p.homeId !== 'string' || !homes.some((h) => h.id === p.homeId))) return no('unknown_home');
  if (p.away !== null) {
    if (!isObj(p.away) || Object.keys(p.away).some((k) => k !== 'until')) return no('bad_away');
    if (p.away.until !== null && !isIsoDate(p.away.until)) return no('bad_away');
  }
  const extra = Object.keys(p).filter((k) => !['id', 'label', 'role', 'homeId', 'contact', 'away'].includes(k));
  if (extra.length) return no('bad_person');
  return ok;
}

export function validateHome(h: unknown): Verdict {
  if (!isObj(h)) return no('bad_home');
  if (typeof h.id !== 'string' || !ID_RE.test(h.id)) return no('bad_id');
  if (typeof h.name !== 'string' || h.name.trim().length < 1 || h.name.length > MAX_HOME_NAME || CTRL_RE.test(h.name)) return no('bad_home');
  if (typeof h.childSleeps !== 'boolean') return no('bad_home');
  if (Object.keys(h).some((k) => !['id', 'name', 'childSleeps'].includes(k))) return no('bad_home');
  return ok;
}

export function validateRhythm(r: unknown): Verdict {
  if (!isObj(r)) return no('bad_rhythm');
  if (typeof r.pattern !== 'string' || !(PATTERNS as readonly string[]).includes(r.pattern)) return no('bad_rhythm');
  if (r.exchangeDay !== null && !(Number.isInteger(r.exchangeDay) && (r.exchangeDay as number) >= 0 && (r.exchangeDay as number) <= 6)) return no('bad_rhythm');
  if (r.exchangeTime !== null && !(typeof r.exchangeTime === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(r.exchangeTime))) return no('bad_rhythm');
  // F6: an order is the court's to set, never a guardian's to claim here.
  if (r.source !== 'guardian') return no('bad_rhythm');
  if (Object.keys(r).some((k) => !['pattern', 'exchangeDay', 'exchangeTime', 'source'].includes(k))) return no('bad_rhythm');
  return ok;
}

// ================================================================= changes ===
export type FamilyOp =
  | { op: 'put_person'; person: Person; before: Person | null }
  | { op: 'remove_person'; personId: string; before: Person | null }
  | { op: 'put_home'; home: Home; before: Home | null }
  | { op: 'remove_home'; homeId: string; before: Home | null }
  | { op: 'set_rhythm'; rhythm: Rhythm; before: Rhythm | null }
  | { op: 'set_area_band'; area: Area; band: AgeBand | null; before: AgeBand | null }
  | { op: 'set_birthday_visible'; visible: boolean; before: boolean | null }
  | { op: 'set_band_hold'; hold: boolean; before: boolean | null }
  | { op: 'release_band'; band: AgeBand; before: AgeBand | null };
export const OP_KINDS = ['put_person', 'remove_person', 'put_home', 'remove_home', 'set_rhythm',
  'set_area_band', 'set_birthday_visible', 'set_band_hold', 'release_band'] as const;
const OP_FIELDS: Record<string, string[]> = {
  put_person: ['person'], remove_person: ['personId'], put_home: ['home'], remove_home: ['homeId'],
  set_rhythm: ['rhythm'], set_area_band: ['area', 'band'], set_birthday_visible: ['visible'],
  set_band_hold: ['hold'], release_band: ['band'],
};
/** Settings ops are about HER settings, not what a guardian is telling her: always now. */
export const NOW_ONLY_OPS: readonly string[] = ['set_birthday_visible', 'set_band_hold', 'release_band'];

export type Timing = { kind: 'now' } | { kind: 'hold' } | { kind: 'date'; on: string };

/** A guardian's raw timing choice -> a checked Timing. */
export function parseTiming(raw: unknown, today: string): { ok: true; timing: Timing } | { ok: false; reason: Reason } {
  if (!isObj(raw)) return { ok: false, reason: 'bad_timing' };
  if (raw.kind === 'now' || raw.kind === 'hold') {
    if (Object.keys(raw).length !== 1) return { ok: false, reason: 'bad_timing' };
    return { ok: true, timing: { kind: raw.kind } };
  }
  if (raw.kind === 'date') {
    if (Object.keys(raw).some((k) => k !== 'kind' && k !== 'on')) return { ok: false, reason: 'bad_timing' };
    if (!isIsoDate(raw.on) || !isIsoDate(today)) return { ok: false, reason: 'bad_date' };
    const ahead = daysBetween(today, raw.on);
    // A date is a promise to the calendar: tomorrow at the earliest ("now" is for today).
    if (ahead < 1) return { ok: false, reason: 'date_not_future' };
    if (ahead > MAX_DATE_AHEAD_DAYS) return { ok: false, reason: 'date_too_far' };
    return { ok: true, timing: { kind: 'date', on: raw.on } };
  }
  return { ok: false, reason: 'bad_timing' };
}

/** Big changes default to "hold until I've told her" (F3). */
export function isBigChange(op: FamilyOp): boolean {
  switch (op.op) {
    case 'set_rhythm': case 'remove_person': case 'remove_home': return true;
    case 'put_home': return op.before === null || op.before.childSleeps !== op.home.childSleeps;
    case 'put_person':
      return op.before === null
        || JSON.stringify(op.before.away) !== JSON.stringify(op.person.away)
        || op.before.homeId !== op.person.homeId;
    default: return false;
  }
}
export function defaultTiming(op: FamilyOp): Timing {
  if (NOW_ONLY_OPS.includes(op.op)) return { kind: 'now' };
  return isBigChange(op) ? { kind: 'hold' } : { kind: 'now' };
}

/** Fill `before` from the structure the op applies to (the server, never the client, decides it). */
export function withBefore(structure: FamilyStructure, op: FamilyOp): FamilyOp {
  const s = structure;
  switch (op.op) {
    case 'put_person': return { ...op, before: s.people.find((p) => p.id === op.person.id) ?? null };
    case 'remove_person': return { ...op, before: s.people.find((p) => p.id === op.personId) ?? null };
    case 'put_home': return { ...op, before: s.homes.find((h) => h.id === op.home.id) ?? null };
    case 'remove_home': return { ...op, before: s.homes.find((h) => h.id === op.homeId) ?? null };
    case 'set_rhythm': return { ...op, before: s.rhythm };
    case 'set_area_band': return { ...op, before: s.areaBands[op.area] ?? null };
    case 'set_birthday_visible': return { ...op, before: s.birthdayVisible };
    case 'set_band_hold': return { ...op, before: s.holdBandChange };
    case 'release_band': return { ...op, before: s.releasedBand };
  }
}

/** Check a client-supplied op (no `before` expected) against the structure it will apply to. */
export function validateOp(structure: FamilyStructure, op: unknown): Verdict {
  if (!isObj(op) || typeof op.op !== 'string' || !(OP_KINDS as readonly string[]).includes(op.op)) return no('bad_op');
  // Untrusted: nothing but the fields this kind of op has ('before' is ignored, the server fills it).
  const allowed = OP_FIELDS[op.op] ?? [];
  if (Object.keys(op).some((k) => k !== 'op' && k !== 'before' && !allowed.includes(k))) return no('bad_op');
  const s = structure;
  switch (op.op) {
    case 'put_person': {
      const v = validatePerson(op.person, s.homes);
      if (!v.ok) return v;
      const id = (op.person as Person).id;
      if (!s.people.some((p) => p.id === id) && s.people.length >= MAX_PEOPLE) return no('too_many_people');
      return ok;
    }
    case 'remove_person':
      return typeof op.personId === 'string' && s.people.some((p) => p.id === op.personId) ? ok : no('unknown_person');
    case 'put_home': {
      const v = validateHome(op.home);
      if (!v.ok) return v;
      const id = (op.home as Home).id;
      if (!s.homes.some((h) => h.id === id) && s.homes.length >= MAX_HOMES) return no('too_many_homes');
      return ok;
    }
    case 'remove_home':
      return typeof op.homeId === 'string' && s.homes.some((h) => h.id === op.homeId) ? ok : no('unknown_home');
    case 'set_rhythm': {
      // F6: a court order wins and is not editable here.
      if (s.rhythm.source === 'court_order') return no('locked_by_order');
      return validateRhythm(op.rhythm);
    }
    case 'set_area_band':
      if (!isArea(op.area)) return no('bad_area');
      return op.band === null || isAgeBand(op.band) ? ok : no('bad_band');
    case 'set_birthday_visible':
      return typeof op.visible === 'boolean' ? ok : no('bad_op');
    case 'set_band_hold':
      return typeof op.hold === 'boolean' ? ok : no('bad_op');
    case 'release_band':
      return isAgeBand(op.band) ? ok : no('bad_band');
  }
  return no('bad_op');
}

/** Validate op + timing together (settings ops cannot be held or dated). */
export function validateChange(structure: FamilyStructure, op: unknown, timing: unknown, today: string):
  { ok: true; timing: Timing } | { ok: false; reason: Reason } {
  const v = validateOp(structure, op);
  if (!v.ok) return v;
  const t = parseTiming(timing, today);
  if (!t.ok) return t;
  if (NOW_ONLY_OPS.includes((op as { op: string }).op) && t.timing.kind !== 'now') return { ok: false, reason: 'settings_now_only' };
  return t;
}

/** Apply one op to a structure (pure; unknown targets are ignored, never thrown on). */
export function applyOp(structure: FamilyStructure, op: FamilyOp): FamilyStructure {
  const s: FamilyStructure = {
    homes: structure.homes.map((h) => ({ ...h })),
    people: structure.people.map((p) => ({ ...p, contact: [...p.contact], away: p.away ? { ...p.away } : null })),
    rhythm: { ...structure.rhythm },
    areaBands: { ...structure.areaBands },
    birthdayVisible: structure.birthdayVisible,
    holdBandChange: structure.holdBandChange,
    releasedBand: structure.releasedBand,
  };
  switch (op.op) {
    case 'put_person': {
      const p = { ...op.person, contact: [...op.person.contact], away: op.person.away ? { ...op.person.away } : null };
      const i = s.people.findIndex((x) => x.id === p.id);
      if (i >= 0) s.people[i] = p; else s.people.push(p);
      break;
    }
    case 'remove_person': s.people = s.people.filter((p) => p.id !== op.personId); break;
    case 'put_home': {
      const h = { ...op.home };
      const i = s.homes.findIndex((x) => x.id === h.id);
      if (i >= 0) s.homes[i] = h; else s.homes.push(h);
      break;
    }
    case 'remove_home':
      s.homes = s.homes.filter((h) => h.id !== op.homeId);
      s.people = s.people.map((p) => (p.homeId === op.homeId ? { ...p, homeId: null } : p));
      break;
    case 'set_rhythm':
      if (s.rhythm.source !== 'court_order') s.rhythm = { ...op.rhythm };
      break;
    case 'set_area_band':
      if (op.band === null) delete s.areaBands[op.area]; else s.areaBands[op.area] = op.band;
      break;
    case 'set_birthday_visible': s.birthdayVisible = op.visible; break;
    case 'set_band_hold': s.holdBandChange = op.hold; break;
    case 'release_band': s.releasedBand = op.band; break;
  }
  return s;
}

/** An undo is a NEW change that puts things back; the original stays in the history. */
export function invertOp(op: FamilyOp, current: FamilyStructure): FamilyOp {
  let inv: FamilyOp;
  switch (op.op) {
    case 'put_person':
      inv = op.before ? { op: 'put_person', person: op.before, before: null }
        : { op: 'remove_person', personId: op.person.id, before: null };
      break;
    case 'remove_person':
      inv = op.before ? { op: 'put_person', person: op.before, before: null }
        : { op: 'remove_person', personId: op.personId, before: null };
      break;
    case 'put_home':
      inv = op.before ? { op: 'put_home', home: op.before, before: null }
        : { op: 'remove_home', homeId: op.home.id, before: null };
      break;
    case 'remove_home':
      inv = op.before ? { op: 'put_home', home: op.before, before: null }
        : { op: 'remove_home', homeId: op.homeId, before: null };
      break;
    case 'set_rhythm':
      inv = { op: 'set_rhythm', rhythm: op.before ?? { ...EMPTY_RHYTHM }, before: null };
      break;
    case 'set_area_band': inv = { op: 'set_area_band', area: op.area, band: op.before, before: null }; break;
    case 'set_birthday_visible': inv = { op: 'set_birthday_visible', visible: op.before ?? true, before: null }; break;
    case 'set_band_hold': inv = { op: 'set_band_hold', hold: op.before ?? true, before: null }; break;
    case 'release_band': inv = { op: 'release_band', band: op.before ?? op.band, before: null }; break;
  }
  return withBefore(current, inv);
}

// ============================================================= the history ===
export interface ChangeEntry {
  entry: 'change';
  id: string;
  seq: number;
  op: FamilyOp;
  timing: Timing;
}
export interface ReleaseEntry { entry: 'release'; id: string; seq: number; ref: string }
export type HistoryEntry = ChangeEntry | ReleaseEntry;

/** The ids that have reached HER by `today` (child-local date). Hold needs a release entry. */
export function releasedIds(entries: readonly HistoryEntry[], today: string): Set<string> {
  const released = new Set(entries.filter((e): e is ReleaseEntry => e.entry === 'release').map((e) => e.ref));
  const out = new Set<string>();
  for (const e of entries) {
    if (e.entry !== 'change') continue;
    const t = e.timing;
    if (t.kind === 'now') out.add(e.id);
    else if (t.kind === 'date') { if (isIsoDate(t.on) && isIsoDate(today) && t.on <= today) out.add(e.id); }
    else if (released.has(e.id)) out.add(e.id);
  }
  return out;
}

/** What a guardian has intended so far (every change, in order) . */
export function foldIntended(base: FamilyStructure, entries: readonly HistoryEntry[]): FamilyStructure {
  return [...entries].sort((a, b) => a.seq - b.seq)
    .reduce((s, e) => (e.entry === 'change' ? applyOp(s, e.op) : s), base);
}
/** What she sees: ONLY changes released to her by `today` (F2). */
export function foldReleased(base: FamilyStructure, entries: readonly HistoryEntry[], today: string): FamilyStructure {
  const ids = releasedIds(entries, today);
  return [...entries].sort((a, b) => a.seq - b.seq)
    .reduce((s, e) => (e.entry === 'change' && ids.has(e.id) ? applyOp(s, e.op) : s), base);
}
/** Changes still waiting: held (no release yet) or dated in the future. */
export function pendingChanges(entries: readonly HistoryEntry[], today: string): ChangeEntry[] {
  const ids = releasedIds(entries, today);
  return entries.filter((e): e is ChangeEntry => e.entry === 'change' && !ids.has(e.id));
}

/** A change a guardian previews: her screens before and after (F2/F3). */
export function previewChange(
  released: FamilyStructure, op: FamilyOp, timing: Timing, band: AgeBand, suites: Suites | null,
  rungs: readonly string[], today: string,
): { before: ChildView; after: ChildView; differs: boolean; big: boolean; recommended: Timing; reaches: 'now' | 'when_told' | 'on_date' } {
  const before = deriveChildView(released, band, suites, rungs, { today });
  const full = withBefore(released, op);
  const after = deriveChildView(applyOp(released, full), band, suites, rungs, { today });
  return {
    before, after,
    differs: JSON.stringify(before) !== JSON.stringify(after),
    big: isBigChange(full),
    recommended: defaultTiming(full),
    reaches: timing.kind === 'now' ? 'now' : timing.kind === 'hold' ? 'when_told' : 'on_date',
  };
}

// ================================================================= stories ===
/** F7: a story is guardian-authored text, bounded. Nothing here writes one. */
export function validateStory(story: unknown): Verdict {
  if (!isObj(story) || Object.keys(story).some((k) => k !== 'pages')) return no('bad_story');
  const pages = story.pages;
  if (!Array.isArray(pages) || pages.length < 1 || pages.length > MAX_STORY_PAGES) return no('bad_story');
  for (const p of pages) {
    if (typeof p !== 'string' || p.trim().length < 1 || p.length > MAX_STORY_PAGE_CHARS || CTRL_RE.test(p.replace(/\n/g, ' '))) return no('bad_story');
  }
  return ok;
}

// ================================================================ birthday ===
export interface BirthdayInfo {
  yearsOld: number;
  nextOn: string;
  sleepsUntil: number;
  turnsYears: number;
  bandNow: AgeBand;
  bandAtBirthday: AgeBand;
  bandChanges: boolean;
}

/** A Feb 29 birthday is held on Mar 1 in a non-leap year. */
function birthdayIn(year: number, month: number, day: number): string {
  const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
  const m = month === 2 && day === 29 && !leap ? 3 : month;
  const d = month === 2 && day === 29 && !leap ? 1 : day;
  return `${String(year).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

/** Everything about the next birthday, from a birth date and her local today. Null on bad input. */
export function birthdayInfo(birthDate: unknown, today: unknown): BirthdayInfo | null {
  if (!isIsoDate(birthDate) || !isIsoDate(today) || birthDate > today) return null;
  const [by, bm, bd] = birthDate.split('-').map(Number);
  const ty = Number(today.slice(0, 4));
  let next = birthdayIn(ty, bm, bd);
  if (next < today) next = birthdayIn(ty + 1, bm, bd);
  const nextYear = Number(next.slice(0, 4));
  const sleepsUntil = daysBetween(today, next);
  const turnsYears = nextYear - by;
  const yearsOld = sleepsUntil === 0 ? turnsYears : turnsYears - 1;
  const bandNow = bandForYears(yearsOld);
  const bandAtBirthday = bandForYears(turnsYears);
  return { yearsOld, nextOn: next, sleepsUntil, turnsYears, bandNow, bandAtBirthday,
    bandChanges: bandNow !== bandAtBirthday && sleepsUntil > 0 };
}

/** The one quiet line: only in her last week, and only if a guardian has not hidden it. */
export function birthdayLineShown(sleepsUntil: number, visible: boolean): boolean {
  return visible && Number.isInteger(sleepsUntil) && sleepsUntil >= 0 && sleepsUntil <= 7;
}

/** The guardian's preview of the next birthday: what moves, what the hold does. */
export function birthdayPreview(info: BirthdayInfo, hold: boolean, released: AgeBand | null) {
  const stays = effectiveBand(info.bandAtBirthday, hold, released ?? info.bandNow);
  return {
    sleepsUntil: info.sleepsUntil,
    turnsYears: info.turnsYears,
    bandChanges: info.bandChanges,
    herBandAfter: info.bandAtBirthday,
    herHomeAfter: stays,
    heldAtBirthday: info.bandChanges && stays !== info.bandAtBirthday,
    changes: info.bandChanges ? diffBands(info.bandNow, info.bandAtBirthday) : [],
  };
}
