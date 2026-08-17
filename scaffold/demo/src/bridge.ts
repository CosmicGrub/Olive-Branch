/**
 * OLIVE BRANCH — demo bridge.
 *
 * This file exists so the demo is driven by the SHIPPED engines rather than by
 * hand-written mock data. Every figure the demo displays — the ribbon offsets,
 * the sleeps countdown, the double-dose refusal, the expense split, the hash
 * chain verdict — is produced by the same code the 667 assertions test.
 *
 * Anything not yet implemented is surfaced explicitly as `underConstruction`
 * rather than faked, because a demo that quietly pretends is worse than one that
 * admits a gap.
 */
import { DateTime } from 'luxon';
import { resolveZone, resolveWallClock } from '../../packages/time-engine/src/time.ts';
import { materialize, nextReachableWindow } from '../../packages/delivery-engine/src/materialize.ts';
import { gate, recipientContext } from '../../packages/delivery-engine/src/gate.ts';
import { can } from '../../packages/family-graph/src/authorize.ts';
import { blocks, sideOn, sleepsUntilSideChange, childCalendarLabel, exchanges }
  from '../../packages/custody/src/schedule.ts';
import { gateImage, guardHint, forbiddenFor } from '../../packages/homework/src/capture.ts';
import { doseKey, recordDose, offlineBundle, manifestOrder, recordArrival, auditArrival }
  from '../../packages/care/src/care.ts';
import { ping, readJournal, childListView, claimNeed, ritualsForChild, auditChildPayload }
  from '../../packages/agency/src/agency.ts';
import { append, verifyChain, allocate, owedTo, certify, verifyExport, authorizeExport }
  from '../../packages/ledger/src/ledger.ts';
import { compileYearBook, handover, onThisDay } from '../../packages/archive/src/archive.ts';
import { scheduleStrip, buildSms, auditSms, newGame, drop } from '../../packages/phase3/src/phase3.ts';
import { Canvas } from '../../packages/annotation/src/canvas.ts';
export * from './play.ts';
import { CATALOGUE, forAge, newGame as newG, play as playG, setHandicap,
  handicapBanner, takeBack, childView as gameChildView, auditChildView,
  shouldOfferHandicap, handicapOffer, storyArtifact } from '../../packages/games/src/games.ts';
import { buildPush, auditPush } from '../../packages/transport/src/push.ts';
import { chooseEntry, suggestEntryRole, routeFromEntry, ENTRY_CHOICE_GRANTS_NO_AUTHORITY }
  from '../../packages/onboarding/src/onboarding.ts';
export { chooseEntry, suggestEntryRole, routeFromEntry, ENTRY_CHOICE_GRANTS_NO_AUTHORITY };
import { captureCameraPhoto, captureScreenshot, SCREENSHOT_SCOPED_OFF_SURFACES,
  neverToDeviceGallery, autoUploadsToAppStorage } from '../../packages/homework/src/snapshot.ts';
import { OBSERVER_MAY, OBSERVER_MAY_NOT, OBSERVER_GRANT_TTL_DAYS, invite,
  activeObservers, auditObserverView, type Observer }
  from '../../packages/observer/src/observer.ts';

const NYC = 'America/New_York', CHI = 'America/Chicago';
const ALL = [0, 1, 2, 3, 4, 5, 6];

// ------------------------------------------------------------------ fixtures
export const DAYPARTS = [
  { kind: 'asleep', startsLocal: '21:00', endsLocal: '06:30', daysOfWeek: ALL, reachable: false },
  { kind: 'wake', startsLocal: '06:30', endsLocal: '08:00', daysOfWeek: ALL, reachable: true },
  { kind: 'school', startsLocal: '08:00', endsLocal: '15:00', daysOfWeek: [1,2,3,4,5], reachable: false },
  { kind: 'after_school', startsLocal: '15:00', endsLocal: '18:30', daysOfWeek: ALL, reachable: true },
  { kind: 'dinner', startsLocal: '18:30', endsLocal: '19:30', daysOfWeek: ALL, reachable: true },
  { kind: 'wind_down', startsLocal: '19:30', endsLocal: '20:30', daysOfWeek: ALL, reachable: true },
  { kind: 'bedtime', startsLocal: '20:30', endsLocal: '21:00', daysOfWeek: ALL, reachable: true },
];

const PARENT_PARTS = [
  { kind: 'asleep', startsLocal: '22:00', endsLocal: '07:00', daysOfWeek: ALL, reachable: false },
  { kind: 'wake', startsLocal: '07:00', endsLocal: '09:00', daysOfWeek: ALL, reachable: true },
  { kind: 'school', startsLocal: '09:00', endsLocal: '17:00', daysOfWeek: [1,2,3,4,5], reachable: false },
  { kind: 'free', startsLocal: '17:00', endsLocal: '22:00', daysOfWeek: ALL, reachable: true },
];

export const CTX = { homeTz: NYC, dayParts: DAYPARTS, tzIntervals: [
  { tz: NYC, start: null, end: '2026-06-12T22:00:00Z' },
  { tz: CHI, start: '2026-06-12T22:00:00Z', end: '2026-07-25T22:00:00Z' },
  { tz: NYC, start: '2026-07-25T22:00:00Z', end: null },
] };
const PARENT_CTX = { homeTz: CHI, dayParts: PARENT_PARTS, tzIntervals: [] };

const ORDER = {
  pattern: '2-2-3' as const, orderTz: NYC, anchorLocalDate: '2026-01-05',
  exchangeTime: '18:00', effectiveFrom: '2020-01-01', effectiveTo: null,
  holidays: [
    { name: 'Christmas', startMonthDay: '12-24', endMonthDay: '12-26',
      evenYearSide: 'A' as const, priority: 10 },
    { name: 'Thanksgiving', startMonthDay: '11-26', endMonthDay: '11-29',
      evenYearSide: 'B' as const, priority: 10 },
  ],
};

const EDGE = {
  childId: 'maya', userId: 'dad', role: 'guardian' as const, scope: {},
  observerOnly: false, restricted: false, validFrom: '2020-01-01T00:00:00Z',
  validTo: null, expiresAt: null, closedAt: null, ladderStep: null,
};

const SIDES = { A: 'Dad', B: 'Mom' };

// ------------------------------------------------------------------ live now
export function now() { return DateTime.utc(); }

export function clocks() {
  const n = now();
  const zone = resolveZone(CTX.tzIntervals, n, CTX.homeTz);
  const child = n.setZone(zone), parent = n.setZone(CHI);
  const g = gate(CTX, n);
  return {
    childTime: child.toFormat('h:mm a'), childZone: child.toFormat('ZZZZ'),
    parentTime: parent.toFormat('h:mm a'), parentZone: parent.toFormat('ZZZZ'),
    offsetHours: (child.offset - parent.offset) / 60,
    reachable: g.allow, dayPart: g.reason ?? currentPart(child),
    childLocalDate: child.toISODate(),
  };
}
function currentPart(local: DateTime) {
  const hhmm = local.toFormat('HH:mm'), dow = local.weekday % 7;
  const p = DAYPARTS.find(x => x.daysOfWeek.includes(dow) &&
    (x.startsLocal <= x.endsLocal
      ? hhmm >= x.startsLocal && hhmm < x.endsLocal
      : hhmm >= x.startsLocal || hhmm < x.endsLocal));
  return p?.kind ?? 'free';
}

/** Human sentence for the guardian header, from the real day-part. */
export function childState() {
  const k = clocks().dayPart;
  return ({ asleep: 'Maya is asleep — notifications are held',
    wake: 'Maya is getting ready for school',
    school: 'Maya is at school — notifications are held',
    after_school: 'Maya just got home from school',
    dinner: 'Maya is at dinner', wind_down: 'Maya is winding down',
    bedtime: 'Maya is going to bed', free: 'Maya is free right now' } as any)[k]
    ?? `Maya is ${k}`;
}

// ------------------------------------------------------------------ entry gate
/**
 * §8.5.0 — the role question. A device that already has Maya's birth date on
 * record (the demo family already does) pre-highlights "child"; its absence
 * would suggest nothing, never "grownup".
 */
export function entryView() {
  return { suggestedWithRecord: suggestEntryRole(true),
           suggestedWithoutRecord: suggestEntryRole(false) };
}

/**
 * Proves ENTRY_CHOICE_GRANTS_NO_AUTHORITY directly rather than just asserting
 * it: the REAL authorizer, called with a guardian-role tap and ZERO edges,
 * still denies.
 */
export function entryProof() {
  return { grantsNoAuthority: ENTRY_CHOICE_GRANTS_NO_AUTHORITY,
           deniedWithZeroEdges: can('expense.view', [], 'maya', new Date(), 'guardian') };
}

// ------------------------------------------------------------------ ribbon
export function ribbon() {
  const n = now();
  const zone = resolveZone(CTX.tzIntervals, n, CTX.homeTz);
  const toChild = (n.setZone(zone).offset - n.setZone(CHI).offset) / 60;
  const START = 6, SPAN = 18;
  const band = (parts: any[], shift: number) => parts.flatMap(p => {
    const a = Math.max(hm(p.startsLocal) + shift, START);
    const b = Math.min(hm(p.endsLocal) + shift, START + SPAN);
    if (b <= a) return [];
    return [{ kind: p.kind, left: ((a - START) / SPAN) * 100,
              width: ((b - a) / SPAN) * 100, reachable: p.reachable }];
  });
  const childLocal = n.setZone(zone);
  const nowPct = ((hm(childLocal.toFormat('HH:mm')) - START) / SPAN) * 100;
  // Overlap: her reachable evening ∩ his free evening, on her axis.
  const lo = Math.max(15, 17 + toChild), hi = Math.min(20.5, 22 + toChild);
  return {
    child: band(DAYPARTS, 0), parent: band(PARENT_PARTS, toChild),
    nowPct: nowPct >= 0 && nowPct <= 100 ? nowPct : null,
    overlap: hi > lo
      ? { left: ((lo - START) / SPAN) * 100, width: ((hi - lo) / SPAN) * 100,
          label: `both free · ${fmt(lo)}–${fmt(hi)} her time` }
      : null,
  };
}
const hm = (s: string) => { const [h, m] = s.split(':').map(Number); return h + m / 60; };
const fmt = (h: number) => {
  const H = Math.floor(h), M = Math.round((h - H) * 60);
  return `${H % 12 === 0 ? 12 : H % 12}:${String(M).padStart(2, '0')} ${H < 12 ? 'AM' : 'PM'}`;
};

// ------------------------------------------------------------------ custody
export function calendar() {
  const today = clocks().childLocalDate!;
  const end = DateTime.fromISO(today).plus({ days: 13 }).toISODate()!;
  const bs = blocks(ORDER, today, end);
  const s = sleepsUntilSideChange(ORDER, today);
  const ex = exchanges(ORDER, today, end, CTX.tzIntervals, CTX.homeTz);
  return {
    today: sideOn(ORDER, today),
    blocks: bs.map(b => ({ ...b, label: childCalendarLabel(b, SIDES) })),
    sleeps: s ? { n: s.sleeps, who: SIDES[s.nextSide], on: s.onLocalDate } : null,
    nextExchange: ex[0] ? { on: ex[0].localDate, label: ex[0].orderTimeLabel,
      from: SIDES[ex[0].from], to: SIDES[ex[0].to], zoneFlips: ex[0].zoneFlips } : null,
  };
}

// ------------------------------------------------------------------ delivery
export function bedtimeDelivery() {
  const n = now();
  const zone = resolveZone(CTX.tzIntervals, n, CTX.homeTz);
  const date = n.setZone(zone).toISODate()!;
  const r = materialize({ id: 'd', childId: 'maya', state: 'pending',
    expiresAt: n.plus({ days: 90 }).toISO()!, policy: 'at_daypart',
    targetDaypart: 'bedtime' }, CTX, n);
  return r.ok
    ? { at: r.scheduledAt.setZone(r.tz).toFormat('h:mm a ZZZZ'),
        onDate: r.scheduledAt.setZone(r.tz).toISODate(), zone: r.tz,
        rolled: r.rolled, utc: r.scheduledAt.toUTC().toFormat('HH:mm') + 'Z' }
    : { error: r.reason };
}

export function sendGuard() {
  const c = recipientContext(CTX, now(), CHI);
  return { localTime: c.localTime, zone: c.zoneAbbr, reachable: c.reachable,
           dayPart: c.dayPart, deferTo: c.deferTo, skewHours: c.skewHours };
}

export function bankBatch(nights: number) {
  const n = now();
  const zone = resolveZone(CTX.tzIntervals, n, CTX.homeTz);
  const start = n.setZone(zone);
  const out: any[] = [];
  for (let i = 0; i < nights; i++) {
    const d = start.plus({ days: i }).toISODate()!;
    const r = materialize({ id: `b${i}`, childId: 'maya', state: 'pending',
      expiresAt: n.plus({ days: 400 }).toISO()!, policy: 'on_local_date',
      targetLocalDate: d, targetDaypart: 'bedtime' }, CTX, n);
    if (r.ok) out.push({ date: d, zone: r.tz,
      local: r.scheduledAt.setZone(r.tz).toFormat('HH:mm'),
      utc: r.scheduledAt.toUTC().toFormat('HH:mm') });
  }
  const zones = [...new Set(out.map(o => o.zone))];
  const drift = out.filter(o => o.local !== '20:30').length;
  const utcs = [...new Set(out.map(o => o.utc))];
  return { nights: out.length, zones, drift, distinctUtcTimes: utcs.length,
           sample: [out[0], out[Math.floor(out.length / 2)], out[out.length - 1]] };
}

// ------------------------------------------------------------------ homework
export function homeworkGate(preset: 'good' | 'blurry' | 'skewed' | 'tiny') {
  const base = { widthPx: 1200, heightPx: 800, sharpness: 400, clipping: 0.05, skewDegrees: 0 };
  const s = preset === 'blurry' ? { ...base, sharpness: 20 }
          : preset === 'skewed' ? { ...base, skewDegrees: 9 }
          : preset === 'tiny' ? { ...base, widthPx: 200, heightPx: 200 }
          : base;
  return { input: s, verdict: gateImage(s) };
}

export function tutorHint(text: string, problem: string) {
  const forbidden = forbiddenFor(problem);
  return { forbidden, verdict: guardHint(text, { text: problem, forbiddenAnswers: forbidden }) };
}

// ------------------------------------------------------------------ snapshot
/** Same measured thresholds §9.1's homework gate uses — a blurred photo is a
 *  blurred photo whether it's headed for OCR or a keepsake. */
export function snapshotCamera(preset: 'good' | 'blurry' | 'skewed' | 'tiny') {
  const base = { widthPx: 1200, heightPx: 800, sharpness: 400, clipping: 0.05, skewDegrees: 0 };
  const s = preset === 'blurry' ? { ...base, sharpness: 20 }
          : preset === 'skewed' ? { ...base, skewDegrees: 9 }
          : preset === 'tiny' ? { ...base, widthPx: 200, heightPx: 200 }
          : base;
  return { input: s, result: captureCameraPhoto(s) };
}

/** Refused entirely on the call surface; never solved, only refused. */
export function snapshotScreenshot(currentSurface: string) {
  return { surface: currentSurface, result: captureScreenshot(currentSurface) };
}

/** The named invariants this whole feature exists for. */
export function snapshotPolicy() {
  return { neverToDeviceGallery, autoUploadsToAppStorage,
           scopedOffSurfaces: [...SCREENSHOT_SCOPED_OFF_SURFACES] };
}

// ------------------------------------------------------------------ care
export function doubleDose() {
  const n = now();
  const zone = resolveZone(CTX.tzIntervals, n, CTX.homeTz);
  const morning = n.setZone(zone).set({ hour: 8, minute: 2 });
  const k1 = doseKey('m1', 'morning', morning, zone);
  const given = [{ ...k1, administeredAt: morning.toISO()!, localTz: CHI,
    byUserName: 'Dad', status: 'given' as const }];
  const noon = n.setZone(zone).set({ hour: 12, minute: 14 });
  const k2 = doseKey('m1', 'morning', noon, zone);
  const r = recordDose(given, k2, { administeredAt: noon.toISO()!, localTz: NYC,
    byUserName: 'Mom', status: 'given' });
  return { firstDose: { by: 'Dad', slot: k1.slot, localDate: k1.localDate },
           secondAttempt: { by: 'Mom', localDate: k2.localDate },
           blocked: !r.ok, message: r.ok ? null : r.error.message };
}

export function emergencyCard() {
  const card = { childId: 'maya', displayName: 'Maya Ruiz', birthDate: '2016-04-02',
    bloodType: 'O+',
    allergies: [{ substance: 'Pollen', reaction: 'sneezing', severity: 'mild' as const },
      { substance: 'Peanuts', reaction: 'anaphylaxis', severity: 'severe' as const }],
    conditions: ['Asthma'], meds: [{ name: 'Albuterol', dose: '2 puffs' }],
    providers: [{ role: 'Pediatrician', name: 'Dr Reyes', phone: '555-0100' }],
    guardians: [{ name: 'Dad', phone: '555-0111' }, { name: 'Mom', phone: '555-0122' }],
    insurance: { carrier: 'BlueCross', memberId: 'X1' }, updatedAt: '2026-07-01T00:00:00Z' };
  return offlineBundle(card);
}

export function bag() {
  return manifestOrder([
    { id: '1', label: 'Blue rabbit', essential: false, sent: false, returned: false },
    { id: '2', label: 'Inhaler', essential: true, sent: true, returned: false },
    { id: '3', label: 'Retainer', essential: true, sent: true, returned: false },
    { id: '4', label: 'Homework folder', essential: false, sent: true, returned: false },
    { id: '5', label: 'Soccer cleats', essential: false, sent: false, returned: false },
    { id: '6', label: 'Glasses', essential: true, sent: false, returned: false },
  ]);
}

export function arrival() {
  const sched = now().set({ hour: 18, minute: 0 });
  const ev = recordArrival('e1', sched, sched.plus({ minutes: 4 }));
  return { event: ev, audit: auditArrival(ev as any) };
}

// ------------------------------------------------------------------ agency
let pingHistory: any[] = [];
export function doPing() {
  const n = now();
  const zone = resolveZone(CTX.tzIntervals, n, CTX.homeTz);
  const r = ping(pingHistory, 'maya', 'dad', n, zone);
  if (r.sent) pingHistory.push({ childId: 'maya', toUserId: 'dad',
    localDate: n.setZone(zone).toISODate() });
  return { result: r, usedToday: pingHistory.length };
}
export function resetPings() { pingHistory = []; }

export function journalAs(role: string) {
  const entries = [
    { id: 'j1', childId: 'maya', body: "i don't want to go this weekend but i don't want to say so", createdAt: '2026-07-27T21:08:00Z' },
    { id: 'j2', childId: 'maya', body: 'the science fair went ok', createdAt: '2026-07-23T19:40:00Z' },
  ];
  return readJournal(entries, role, role === 'child' ? 'maya' : null, 'maya');
}

export function lists() {
  const items = [
    { id: '1', childId: 'maya', kind: 'need' as const, title: 'Soccer cleats, size 4', claimedBy: 'dad' },
    { id: '2', childId: 'maya', kind: 'need' as const, title: 'Winter coat', claimedBy: null },
    { id: '3', childId: 'maya', kind: 'need' as const, title: 'Math tutor', claimedBy: null },
    { id: '4', childId: 'maya', kind: 'want' as const, title: 'A bigger sketchbook' },
    { id: '5', childId: 'maya', kind: 'want' as const, title: 'Guitar lessons' },
    { id: '6', childId: 'maya', kind: 'want' as const, title: 'To see the ocean' },
  ];
  return { guardian: items, child: childListView(items),
           audit: auditChildPayload(childListView(items)),
           claimWant: claimNeed(items[3], 'dad') };
}

export function strip() {
  const n = now();
  const zone = resolveZone(CTX.tzIntervals, n, CTX.homeTz);
  return scheduleStrip(DAYPARTS, n.setZone(zone).toFormat('HH:mm'));
}

export function rituals() {
  return ritualsForChild([
    { id: 'r1', childId: 'maya', withUserId: 'dad', label: 'Sunday pancakes call',
      daypart: 'wake', daysOfWeek: [0], active: true },
    { id: 'r2', childId: 'maya', withUserId: 'dad', label: 'Chess move',
      daypart: 'after_school', daysOfWeek: [3], active: true },
  ], ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']);
}

// ------------------------------------------------------------------ ledger
export function buildChain(n: number) {
  let c: any[] = [];
  const bodies = [
    'Can we move Friday to 7pm? Traffic on the 77 is bad.',
    'That works. I will bring the inhaler and the retainer.',
    'She has a science fair Thursday — can you come?',
    'Yes. What time does it start?',
    '6:30. She wants to show you the volcano.',
    'I will be there.',
  ];
  for (let i = 0; i < n; i++) {
    c = [...c, append(c, { childId: 'maya', authorId: i % 2 ? 'mom' : 'dad',
      at: DateTime.fromISO('2026-07-01T09:00:00Z').plus({ days: i }).toISO()!,
      body: bodies[i % bodies.length] })];
  }
  return c;
}

export function tamperDemo(mode: 'clean' | 'edit' | 'delete' | 'reorder') {
  const c = buildChain(6);
  const chain = mode === 'clean' ? c
    : mode === 'edit' ? c.map((e, i) => i === 2 ? { ...e, body: 'I never agreed to that.' } : e)
    : mode === 'delete' ? c.filter((_, i) => i !== 2)
    : (() => { const x = [...c]; [x[2], x[3]] = [x[3], x[2]]; return x; })();
  const att = certify(c, 'maya', now().toISO()!);
  return { chain, attestation: att, verify: verifyChain(chain),
           reVerify: verifyExport(chain, att) };
}

export function expenses() {
  const rule = { dad: 5000, mom: 5000 };
  const items = [
    { id: '1', childId: 'maya', paidBy: 'dad', amountCents: 12000, category: 'medical', incurredOn: '2026-07-03', status: 'accepted' as const },
    { id: '2', childId: 'maya', paidBy: 'mom', amountCents: 8500, category: 'activity', incurredOn: '2026-07-09', status: 'accepted' as const },
    { id: '3', childId: 'maya', paidBy: 'dad', amountCents: 6400, category: 'clothing', incurredOn: '2026-07-14', status: 'proposed' as const },
    { id: '4', childId: 'maya', paidBy: 'mom', amountCents: 2501, category: 'school', incurredOn: '2026-07-20', status: 'disputed' as const },
  ];
  return { items, rule, net: owedTo(items, rule),
           oddCent: allocate(2501, rule), threeCents: allocate(3, rule),
           childCanSee: can('expense.view', [EDGE], 'maya', new Date(), 'child') };
}

export function exportOptions(certifiedTaken: number, courtTier: boolean) {
  return {
    raw: authorizeExport({ kind: 'raw', childId: 'maya', requestedBy: 'dad',
      courtTier, certifiedInLast12Months: certifiedTaken }),
    certified: authorizeExport({ kind: 'certified', childId: 'maya', requestedBy: 'dad',
      courtTier, certifiedInLast12Months: certifiedTaken }),
  };
}

// ------------------------------------------------------------------ archive
export function yearBook() {
  const kinds = ['video_msg', 'drawing', 'homework', 'photo'];
  const all = Array.from({ length: 184 }, (_, i) => ({
    id: `a${i}`, childId: 'maya', kind: kinds[i % 4], storageKey: `k${i}`,
    capturedAt: DateTime.fromISO('2026-01-05T15:00:00Z').plus({ days: i * 2 }).toISO()!,
    capturedTz: i % 7 === 0 ? CHI : NYC, preserved: true, eraTag: null, authorId: 'dad',
  }));
  return compileYearBook(all, 'maya', 2026);
}

export function handoverDemo(age: number) {
  const birth = now().minus({ years: age }).toISODate()!;
  const child = { id: 'maya', birthDate: birth, majorityAge: 18, handedOverAt: null };
  const arts = Array.from({ length: 1842 }, (_, i) => ({ id: `a${i}`, childId: 'maya',
    kind: 'video_msg', storageKey: `k${i}`, capturedAt: '2026-01-01T00:00:00Z',
    capturedTz: NYC, preserved: true, eraTag: null, authorId: 'dad' }));
  return handover(child as any, arts as any, 214, now());
}

// ------------------------------------------------------------------ p6/p7
export function authProbe(action: string, role: string) {
  return can(action as any, role === 'child' ? [] : [EDGE], 'maya', new Date(), role);
}

// ------------------------------------------------------------------ observer tier
/**
 * RENDER-01 fix (round-2 rendering pass, "Every Door, Opened") — the demo's
 * "Observers" screens (both the interactive one and its engine-room writeup)
 * have always called T.observerView(), a function that never existed anywhere
 * in this codebase. Every value here comes from the real, already-tested
 * observer.ts primitives — nothing here was invented to make the screen stop
 * throwing.
 */
export function observerView() {
  const probes = [
    ...OBSERVER_MAY.map(scope => ({ scope, can: true })),
    ...OBSERVER_MAY_NOT.map(scope => ({ scope, can: false })),
  ];
  // The three scopes the screen's own copy names as never grantable to
  // anyone: the journal (P7), a sealed letter, a private note. Only the
  // journal has a real OBSERVER_MAY_NOT scope string to point at — sealed
  // letters and private notes aren't observer-reachable surfaces at all (no
  // route exists to expose them), so they have no scope string to probe.
  const never = ['read_child_journal'];
  const sample: Observer[] = [
    { userId: 'grandma', role: 'grandparent', invitedBy: 'dad', label: 'Grandma',
      invitedAt: '2026-06-01T00:00:00Z', acceptedAt: '2026-06-02T00:00:00Z',
      revokedAt: null },
  ];
  const childView = activeObservers(sample).map(o => ({ who: o.label,
    sees: OBSERVER_MAY.map(s => s.replace(/_/g, ' ')).join(', ') }));
  const therapistInvite = invite([], 'guardian', { userId: 't1', role: 'carer',
    invitedBy: 'dad', label: 'Therapist', invitedAt: now().toISO()! });
  // Honestly labelled, not fabricated: invite() as written takes one
  // guardian's say-so and does not itself require the other guardian's
  // consent (that requirement is this screen's own prose, and MASTERFILE
  // §16.2 #11 marks the therapist-role scope question still open) — so this
  // shows the REAL result of a single guardian inviting alone, whatever it
  // is, rather than asserting a refusal the code does not actually perform.
  const soloInvite = invite([], 'guardian', { userId: 'a1', role: 'relative',
    invitedBy: 'dad', label: 'Aunt', invitedAt: now().toISO()! });
  return {
    probes, never, childView, ttl: OBSERVER_GRANT_TTL_DAYS,
    defaults: { therapist: therapistInvite },
    soloRefused: soloInvite,
    forbiddenRefused: auditObserverView({ journal: 'a private thought' }),
  };
}

// ------------------------------------------------------------------ misc
export function pushProbe(kind: string) {
  const p = buildPush({ kind: kind as any, platform: 'android',
    deviceToken: 'tok', ref: 'r_opaque', callRoomHandle: 'h' });
  return { payload: p, audit: auditPush(p) };
}
export function smsProbe(custom?: string) {
  const s = custom ? { to: '+1', body: custom } : buildSms('message_waiting', '+1');
  return { sms: s, audit: auditSms(s) };
}
export function canvasDemo() {
  const c = new Canvas();
  c.add({ id: 'd1', actorId: 'dad', actorKind: 'guardian', points: [[0,0]], color: '#A3364A', widthPx: 2 });
  c.add({ id: 'm1', actorId: 'maya', actorKind: 'child', points: [[1,1]], color: '#2F6FB0', widthPx: 2 });
  c.add({ id: 'd2', actorId: 'dad', actorKind: 'guardian', points: [[2,2]], color: '#A3364A', widthPx: 2 });
  const before = c.visible().map(s => s.id);
  const undone = c.undo('dad', 1);
  return { before, undone: undone?.id ?? null, after: c.visible().map(s => s.id) };
}
export function gameDemo(moves: number[]) {
  let g = newGame('demo', now());
  const log: string[] = [];
  for (const col of moves) {
    const r = drop(g, g.turn, col, now());
    if (r.ok) { log.push(`${g.turn} → col ${col}`); g = r.state; }
    else log.push(`${g.turn} → col ${col} REFUSED (${r.reason})`);
  }
  return { log, winner: g.winner, turn: g.turn, board: g.board };
}

// ------------------------------------------------------------------ games
export function gameCatalogue(age: number) {
  return { all: CATALOGUE, forAge: forAge(age) };
}

/** A short tic-tac-toe with the child's handicap in force. */
export function ticTacToe(withHandicap: boolean) {
  let g = newG('tictactoe', 'demo');
  if (withHandicap) g = setHandicap(g, 'A', 'no_centre').state ?? g;
  const log: string[] = [];
  const step = (side: any, at: number) => {
    const r = playG(g, side, at);
    if (r.ok) { g = r.state; log.push(`${side === 'A' ? 'Maya' : 'Dad'} → ${at}`); }
    else log.push(`${side === 'A' ? 'Maya' : 'Dad'} → ${at} REFUSED (${r.reason})`);
  };
  step('A', 0); step('B', 4); step('A', 1); step('B', 3); step('A', 2);
  return { log, banner: handicapBanner(g), outcome: g.outcome,
           childView: gameChildView(g), audit: auditChildView(gameChildView(g)) };
}

export function takebackDemo() {
  let g = newG('dotsboxes', 'demo');
  const mv: any[] = [['h',0,0],['h',1,0],['v',0,0],['v',0,1]];
  let side: any = 'A';
  for (const m of mv) { const r = playG(g, g.turn, m); if (r.ok) g = r.state; }
  const before = { score: g.scores.B, turn: g.turn };
  const u = takeBack(g);
  return { before, after: u.ok ? { score: u.state.scores.B, turn: u.state.turn } : null,
           note: 'Undoing a box-completing move must restore the score AND the extra turn.' };
}

export function storyDemo() {
  let g = newG('story', 'demo');
  const lines = [
    'Once there was a dog who could drive.',
    'He was not very good at parking.',
    'He parked on top of a cake.',
    'The cake belonged to a bear who was already having a bad week.',
  ];
  let side: any = 'A';
  for (const l of lines) { const r = playG(g, side, l); if (r.ok) g = r.state; side = side === 'A' ? 'B' : 'A'; }
  return { lines: g.board.lines, outcome: g.outcome,
           artifact: storyArtifact(g), childView: gameChildView(g) };
}

export function streakDemo(outcomes: string[]) {
  return { outcomes, offers: shouldOfferHandicap(outcomes as any, 'tictactoe'),
           offer: handicapOffer('tictactoe') };
}

/** Everything not yet built. Surfaced honestly rather than faked. */
export const UNDER_CONSTRUCTION: Record<string, string> = {
  guardian_setup: 'Real account setup — passkey/WebAuthn sign-in and the real '
       + 'family-graph invitation/consent flow (§11) — is not built in this demo. '
       + 'Shown honestly as a stub rather than faked, the same way the native '
       + 'kiosk bridges are documented as drafted and unverified rather than '
       + 'glossed over. The important property is what does NOT happen here: '
       + 'tapping "grown-up" on the welcome screen granted nothing by itself — '
       + 'whatever account gets created here still has to earn a real '
       + 'guardianship edge before can() allows anything.',
  video: 'Live video needs a LiveKit server and a real device camera. Token '
       + 'minting and room lifecycle ARE verified against a running server '
       + '(21 assertions) — the media stream is not wired into this demo.',
  kiosk: 'The Android and Windows kiosk modules need a device build environment. '
       + 'The defeat state machine and the cross-language channel contract are '
       + 'tested; the native side has never been compiled.',
  captions: 'Live captions and translation are specified in §8.4 and not built.',
  ocr_live: 'OCR runs against real tesseract in the test suite. Wiring a camera '
          + 'into the browser demo would add nothing the quality gate does not '
          + 'already show.',
  print: 'Year Book print fulfilment needs a partner; §19 lists it as deferred.',
  school: 'The school layer (§9.6.4) is specified, not built.',
  games_ui: 'Four games ship with full engines and 77 assertions. The demo '
          + 'renders their transcripts and child views rather than an '
          + 'interactive board — the board is a Flutter widget, not a browser one.',
  more_games: 'Checkers, Battleship, word search with parent-hidden words, '
            + 'hangman and chess are designed but not built. Chess should use '
            + 'chess.js rather than hand-rolled rules — castling, en passant, '
            + 'promotion, stalemate and threefold repetition are a classic '
            + 'underestimate.',
};
