/**
 * Delivery engine — adversarial unit suite.
 * MASTERFILE §6.3–6.5. Run: node test/delivery.test.mjs
 */
import { DateTime } from 'luxon';
import {
  materialize, nextReachableWindow, PAST_GRACE_MINUTES,
} from '../src/materialize.mjs';
import { gate, recipientContext, MAX_DEFERS } from '../src/gate.mjs';

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}

const NYC = 'America/New_York', CHI = 'America/Chicago';
const ALL = [0, 1, 2, 3, 4, 5, 6];

const DAYPARTS = [
  { kind: 'asleep',        startsLocal: '21:00', endsLocal: '06:30', daysOfWeek: ALL, reachable: false },
  { kind: 'wake',          startsLocal: '06:30', endsLocal: '08:00', daysOfWeek: ALL, reachable: true  },
  { kind: 'school',        startsLocal: '08:00', endsLocal: '15:00', daysOfWeek: [1,2,3,4,5], reachable: false },
  { kind: 'after_school',  startsLocal: '15:00', endsLocal: '18:30', daysOfWeek: ALL, reachable: true  },
  { kind: 'dinner',        startsLocal: '18:30', endsLocal: '19:30', daysOfWeek: ALL, reachable: true  },
  { kind: 'bedtime',       startsLocal: '20:30', endsLocal: '21:00', daysOfWeek: ALL, reachable: true  },
];

// Child is Eastern, then Central for the summer, then Eastern again.
const SPLIT_CTX = {
  homeTz: NYC,
  dayParts: DAYPARTS,
  tzIntervals: [
    { tz: NYC, start: null,                   end: '2026-06-12T22:00:00Z' },
    { tz: CHI, start: '2026-06-12T22:00:00Z', end: '2026-07-25T22:00:00Z' },
    { tz: NYC, start: '2026-07-25T22:00:00Z', end: null                   },
  ],
};
const NYC_CTX = { homeTz: NYC, dayParts: DAYPARTS, tzIntervals: [] };

const intent = (o) => ({
  id: 'i', childId: 'c', state: 'pending',
  expiresAt: '2030-01-01T00:00:00Z', ...o,
});

// ---------------------------------------------------------------------------
// G1 — the mid-flight batch move. THE scenario I flagged.
//      A 181-night batch materialized in Eastern. On night 60 the child moves
//      to Central. Nights before the move must stay Eastern; nights after must
//      become Central; every night must remain 8:30 PM LOCAL.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-05-01T12:00:00Z');
  const before = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-01', targetDaypart: 'bedtime' }),
    SPLIT_CTX, now);
  const after = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-07-01', targetDaypart: 'bedtime' }),
    SPLIT_CTX, now);

  check('G1 mid-flight move', 'pre-move night resolves Eastern', before.ok && before.tz, NYC);
  check('G1 mid-flight move', 'post-move night resolves Central', after.ok && after.tz, CHI);
  check('G1 mid-flight move', 'pre-move is 20:30 local',
    before.scheduledAt.setZone(before.tz).toFormat('HH:mm'), '20:30');
  check('G1 mid-flight move', 'post-move is 20:30 local',
    after.scheduledAt.setZone(after.tz).toFormat('HH:mm'), '20:30');
  check('G1 mid-flight move', 'UTC instants differ by the zone gap (1h)',
    (after.scheduledAt.toUTC().hour - before.scheduledAt.toUTC().hour + 24) % 24, 1);

  // Whole batch: zero drift across 181 nights AND a zone change AND two DST flips.
  let drift = 0, zones = new Set();
  for (let i = 0; i < 181; i++) {
    const d = DateTime.fromISO('2026-05-01').plus({ days: i }).toISODate();
    const r = materialize(
      intent({ policy: 'on_local_date', targetLocalDate: d, targetDaypart: 'bedtime' }),
      SPLIT_CTX, now);
    if (!r.ok) { drift++; continue; }
    zones.add(r.tz);
    if (r.scheduledAt.setZone(r.tz).toFormat('HH:mm') !== '20:30') drift++;
  }
  check('G1 mid-flight move', '181 nights, zero drift off 20:30 local', drift, 0);
  check('G1 mid-flight move', 'batch legitimately spans two zones', zones.size, 2);
}

// ---------------------------------------------------------------------------
// G2 — retroactive delivery guard. A missed night must NOT fire late.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-07-01T12:00:00Z');   // long past June 1

  const stale = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-01', targetDaypart: 'bedtime' }),
    NYC_CTX, now);
  check('G2 past guard', 'missed banked night EXPIRES, not delivers',
    stale.ok === false && stale.reason, 'target_in_past');

  // Inside the grace window it still goes out — a sweep hiccup should not
  // silently eat a goodnight message.
  const bed = DateTime.fromISO('2026-07-01T00:30:00Z');   // 8:30pm Jun30 EDT
  const justLate = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-30', targetDaypart: 'bedtime' }),
    NYC_CTX, bed.plus({ minutes: PAST_GRACE_MINUTES - 10 }));
  check('G2 past guard', `${PAST_GRACE_MINUTES - 10}min late still delivers`, justLate.ok, 'true');

  const tooLate = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-30', targetDaypart: 'bedtime' }),
    NYC_CTX, bed.plus({ minutes: PAST_GRACE_MINUTES + 10 }));
  check('G2 past guard', `${PAST_GRACE_MINUTES + 10}min late is refused`,
    tooLate.ok === false && tooLate.reason, 'target_in_past');

  const staleInstant = materialize(
    intent({ policy: 'at_instant', targetInstant: '2026-01-01T00:00:00Z' }), NYC_CTX, now);
  check('G2 past guard', 'stale at_instant refused',
    staleInstant.ok === false && staleInstant.reason, 'target_in_past');
}

// ---------------------------------------------------------------------------
// G3 — at_daypart ROLLS FORWARD; on_local_date does not. The distinction
//      between "next bedtime" and "the night of June 1st".
// ---------------------------------------------------------------------------
{
  // 11pm Eastern — today's bedtime is gone.
  const now = DateTime.fromISO('2026-07-02T03:00:00Z');
  const r = materialize(intent({ policy: 'at_daypart', targetDaypart: 'bedtime' }), NYC_CTX, now);
  check('G3 roll vs expire', 'open at_daypart rolls forward', r.ok && r.rolled, 'true');
  check('G3 roll vs expire', 'rolls to tomorrow 20:30 local',
    r.scheduledAt.setZone(r.tz).toFormat('yyyy-MM-dd HH:mm'), '2026-07-02 20:30');

  const dated = materialize(
    intent({ policy: 'at_daypart', targetDaypart: 'bedtime', targetLocalDate: '2026-06-01' }),
    NYC_CTX, now);
  check('G3 roll vs expire', 'EXPLICITLY dated at_daypart does not roll',
    dated.ok === false && dated.reason, 'target_in_past');

  const unknown = materialize(
    intent({ policy: 'at_daypart', targetDaypart: 'piano_lesson' }), NYC_CTX, now);
  check('G3 roll vs expire', 'undefined day-part is skipped not guessed',
    unknown.ok === false && unknown.reason, 'daypart_undefined');
}

// ---------------------------------------------------------------------------
// G4 — the gate. Never wakes a sleeping child; never fires during school.
// ---------------------------------------------------------------------------
{
  const asleep = DateTime.fromISO('2026-07-02T06:00:00Z');   // 2am EDT
  const g1 = gate(NYC_CTX, asleep);
  check('G4 gate', 'blocked while asleep', `${g1.allow}/${g1.reason}`, 'false/asleep');
  check('G4 gate', 'defers to 6:30am local wake',
    g1.deferTo.setZone(NYC).toFormat('HH:mm'), '06:30');

  const school = DateTime.fromISO('2026-07-02T14:00:00Z');   // 10am EDT Thursday
  check('G4 gate', 'blocked during school', gate(NYC_CTX, school).reason, 'school');

  const evening = DateTime.fromISO('2026-07-02T23:00:00Z');  // 7pm EDT
  check('G4 gate', 'allowed at dinner', gate(NYC_CTX, evening).allow, 'true');

  check('G4 gate', 'emergency is never gated', gate(NYC_CTX, asleep, 'emergency').allow, 'true');

  // Fail OPEN after repeated deferral — silence is worse than bad timing.
  const capped = gate(NYC_CTX, asleep, 'normal', MAX_DEFERS);
  check('G4 gate', 'defer chain is bounded',
    `${capped.allow}/${capped.reason}`, 'true/max_defers_exceeded');

  // Saturday has no `school` part; the child must be reachable at 10am.
  const sat = DateTime.fromISO('2026-07-04T14:00:00Z');
  check('G4 gate', 'weekend 10am is reachable (no school part)', gate(NYC_CTX, sat).allow, 'true');
}

// ---------------------------------------------------------------------------
// G5 — sender-side guard. The parent sees HER clock, not theirs.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-07-03T02:40:00Z');      // 10:40pm EDT / 9:40pm CDT
  const c = recipientContext(NYC_CTX, now, CHI);
  check('G5 send guard', 'child local time', c.localTime, '10:40 PM');
  check('G5 send guard', 'child zone abbr', c.zoneAbbr, 'EDT');
  check('G5 send guard', 'flagged unreachable', c.reachable, 'false');
  check('G5 send guard', 'blocking part named', c.dayPart, 'asleep');
  check('G5 send guard', 'offers breakfast alternative', c.deferTo, '6:30 AM');
  check('G5 send guard', 'skew vs Austin parent is 1h', c.skewHours, 1);
}

// ---------------------------------------------------------------------------
// G6 — terminal states and expiry are never re-materialized.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-07-01T12:00:00Z');
  for (const st of ['delivered', 'opened', 'expired', 'revoked']) {
    const r = materialize(
      intent({ policy: 'at_daypart', targetDaypart: 'bedtime', state: st }), NYC_CTX, now);
    check('G6 terminal', `${st} is untouchable`, r.ok === false && r.reason, 'terminal_state');
  }
  const dead = materialize(
    intent({ policy: 'at_daypart', targetDaypart: 'bedtime',
             expiresAt: '2026-06-01T00:00:00Z' }), NYC_CTX, now);
  check('G6 terminal', 'past retention window refuses',
    dead.ok === false && dead.reason, 'already_expired');
}

// ---------------------------------------------------------------------------
// G7 — DST. A bedtime intent must not drift across either transition.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-10-01T12:00:00Z');
  const oct = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-10-15', targetDaypart: 'bedtime' }),
    NYC_CTX, now);
  const dec = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-12-15', targetDaypart: 'bedtime' }),
    NYC_CTX, now);
  check('G7 DST', 'Oct bedtime 20:30 local',
    oct.scheduledAt.setZone(NYC).toFormat('HH:mm'), '20:30');
  check('G7 DST', 'Dec bedtime 20:30 local',
    dec.scheduledAt.setZone(NYC).toFormat('HH:mm'), '20:30');
  check('G7 DST', 'UTC shifted 1h across the Nov flip',
    (dec.scheduledAt.toUTC().hour - oct.scheduledAt.toUTC().hour + 24) % 24, 1);

  // when_reachable must never hand back an instant in the past.
  const w = nextReachableWindow(NYC_CTX, DateTime.fromISO('2026-11-01T05:30:00Z'));
  check('G7 DST', 'reachable window is never in the past',
    w.start >= DateTime.fromISO('2026-11-01T05:30:00Z'), 'true');
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) {
  if (r.group !== g) { g = r.group; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(50)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
