/**
 * messaging — capture/playback adversarial suite. MASTERFILE §9.5, §8.2.4, §10.1.
 */
import { DateTime } from 'luxon';
import {
  captureMessage, openReceipt, retentionOnOpen,
  UNOPENED_RETENTION_DAYS, OPENED_RETENTION_DAYS, ARTIFACT_GRACE_DAYS,
} from '../src/pipeline.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (group, name, actual, expected) => {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
};

const NYC = 'America/New_York', CHI = 'America/Chicago';
const ALL = [0,1,2,3,4,5,6];
const CHILD = 'aaaa', DAD = 'dad';
const NOW = DateTime.fromISO('2026-07-26T18:00:00Z');   // 2pm EDT

const DAYPARTS = [
  { kind:'asleep', startsLocal:'21:00', endsLocal:'06:30', daysOfWeek:ALL, reachable:false },
  { kind:'wake', startsLocal:'06:30', endsLocal:'08:00', daysOfWeek:ALL, reachable:true },
  { kind:'after_school', startsLocal:'15:00', endsLocal:'18:30', daysOfWeek:ALL, reachable:true },
  { kind:'bedtime', startsLocal:'20:30', endsLocal:'21:00', daysOfWeek:ALL, reachable:true },
];
const CTX = { homeTz: NYC, dayParts: DAYPARTS, tzIntervals: [] };
const SPLIT = { homeTz: NYC, dayParts: DAYPARTS, tzIntervals: [
  { tz: CHI, start: null, end: '2026-08-01T22:00:00Z' },
  { tz: NYC, start: '2026-08-01T22:00:00Z', end: null },
]};

const edge = (o={}) => ({ childId: CHILD, userId: DAD, role:'guardian', scope:{},
  observerOnly:false, restricted:false, validFrom:'2020-01-01T00:00:00Z',
  validTo:null, expiresAt:null, closedAt:null, ladderStep:null, ...o });

const cap = (o={}) => captureMessage({
  childId: CHILD, senderId: DAD, senderRole:'guardian',
  storageKey:'k/1', durationMs: 42000, targetLocalDate: null,
  daypart:'bedtime', preserve: false, ...o,
}, [edge()], CTX, NOW);

// -------------------------------------------------------------------------
// M1 — THE SEAM. The artifact must outlive the intent that points at it.
// -------------------------------------------------------------------------
{
  const r = cap();
  check('M1 retention seam', 'capture succeeds', r.ok, 'true');

  const aExp = DateTime.fromISO(r.artifact.expiresAt);
  const iExp = DateTime.fromISO(r.intent.expiresAt);
  check('M1 retention seam', 'artifact outlives the intent', aExp > iExp, 'true');
  check('M1 retention seam', `slack is exactly ${ARTIFACT_GRACE_DAYS} days`,
    Math.round(aExp.diff(iExp, 'days').days), ARTIFACT_GRACE_DAYS);
  check('M1 retention seam', `intent lives ${UNOPENED_RETENTION_DAYS}d past delivery`,
    Math.round(iExp.diff(NOW, 'days').days) >= UNOPENED_RETENTION_DAYS, 'true');

  // A preserved artifact has NO clock — §5.6 CHECK makes the alternative
  // unrepresentable, so the pipeline must emit null rather than a date.
  const p = cap({ preserve: true });
  check('M1 retention seam', 'preserved artifact carries no clock',
    p.artifact.expiresAt, 'null');
  check('M1 retention seam', 'preservation is attributed',
    p.artifact.preservedBy, DAD);
}

// -------------------------------------------------------------------------
// M2 — authorization is the first gate, and every revocation path closes it.
// -------------------------------------------------------------------------
{
  const deny = (mod) => {
    const r = captureMessage({
      childId: CHILD, senderId: DAD, senderRole:'guardian', storageKey:'k/1',
      durationMs: 1000, targetLocalDate: null, daypart:'bedtime', preserve:false,
    }, [edge(mod)], CTX, NOW);
    return r.ok ? 'ALLOWED' : r.reason;
  };
  check('M2 authorization', 'closed edge cannot capture',
    deny({ closedAt:'2026-07-01T00:00:00Z' }), 'not_authorized');
  check('M2 authorization', 'protective order cannot capture',
    deny({ restricted:true }), 'not_authorized');
  check('M2 authorization', 'ladder none cannot capture',
    deny({ ladderStep:'none' }), 'not_authorized');
  check('M2 authorization', 'trusted adult CAN message',
    deny({ role:'trusted_adult' }), 'ALLOWED');
  check('M2 authorization', 'sitter cannot message',
    deny({ role:'sitter' }), 'not_authorized');
  check('M2 authorization', 'coordinator has no child-facing surface',
    deny({ role:'coordinator' }), 'not_authorized');

  // §17.3 — an observer may watch. Sending a message is participation, but
  // `message` is not in the WRITES list, so observers retain it deliberately:
  // a reluctant parent saying goodnight is the outcome we want.
  check('M2 authorization', 'observer may still send a message',
    deny({ observerOnly:true }), 'ALLOWED');
}

// -------------------------------------------------------------------------
// M3 — empty recordings and dead target dates.
// -------------------------------------------------------------------------
{
  check('M3 input guards', 'zero-length recording refused',
    (cap({ durationMs: 0 })).reason, 'empty_recording');
  check('M3 input guards', 'negative duration refused',
    (cap({ durationMs: -1 })).reason, 'empty_recording');
  check('M3 input guards', 'a night already past is refused',
    (cap({ targetLocalDate:'2026-06-01' })).reason, 'target_date_in_past');
  check('M3 input guards', 'a future night is accepted',
    (cap({ targetLocalDate:'2026-09-01' })).ok, 'true');
}

// -------------------------------------------------------------------------
// M4 — policy selection follows the promise being made.
// -------------------------------------------------------------------------
{
  check('M4 policy', 'no date → at_daypart (next bedtime, may roll)',
    cap().intent.policy, 'at_daypart');
  check('M4 policy', 'explicit date → on_local_date (fixed night)',
    cap({ targetLocalDate:'2026-09-01' }).intent.policy, 'on_local_date');
  check('M4 policy', 'batch metadata is carried through',
    cap({ batchId:'b1', batchSeq: 41 }).intent.batchSeq, 41);
}

// -------------------------------------------------------------------------
// M5 — capture zone is HER zone at capture, not the sender's.
// -------------------------------------------------------------------------
{
  // Dad is in Chicago; she is in Chicago too until Aug 1, then Eastern.
  const r = captureMessage({
    childId: CHILD, senderId: DAD, senderRole:'guardian', storageKey:'k/2',
    durationMs: 9000, targetLocalDate:null, daypart:'bedtime', preserve:false,
  }, [edge()], SPLIT, NOW);
  check('M5 capture zone', 'stamped with HER zone at capture',
    r.artifact.capturedTz, CHI);

  const later = DateTime.fromISO('2026-09-01T18:00:00Z');
  const r2 = captureMessage({
    childId: CHILD, senderId: DAD, senderRole:'guardian', storageKey:'k/3',
    durationMs: 9000, targetLocalDate:null, daypart:'bedtime', preserve:false,
  }, [edge()], SPLIT, later);
  check('M5 capture zone', 'follows her home again after the move',
    r2.artifact.capturedTz, NYC);
}

// -------------------------------------------------------------------------
// M6 — §8.2.4 receipts render in HER frame at OPEN time, not capture time.
// -------------------------------------------------------------------------
{
  const opened = DateTime.fromISO('2026-09-02T11:04:00Z');   // 7:04am EDT
  const r = openReceipt(SPLIT, opened, 'wake');
  check('M6 receipt', 'local time in her zone', r.localTime, '7:04 AM');
  check('M6 receipt', 'zone is her zone at OPEN', r.zone, NYC);
  check('M6 receipt', 'phrase carries day-part context',
    r.phrase, 'Watched at 7:04 AM her time — before school.');

  // Recorded while she was in Texas, opened after she flew home. The receipt
  // must read Eastern, because that is the fact the parent wants.
  const beforeMove = DateTime.fromISO('2026-07-20T02:00:00Z');
  check('M6 receipt', 'a pre-move open reads Central',
    openReceipt(SPLIT, beforeMove, 'bedtime').zone, CHI);
  check('M6 receipt', 'no day-part → no dangling em dash',
    openReceipt(SPLIT, opened, 'free').phrase, 'Watched at 7:04 AM her time.');
  check('M6 receipt', 'null day-part is safe',
    openReceipt(SPLIT, opened, null).phrase, 'Watched at 7:04 AM her time.');
}

// -------------------------------------------------------------------------
// M7 — §10.1 opening shortens retention and can never lengthen it.
// -------------------------------------------------------------------------
{
  const opened = DateTime.fromISO('2026-07-27T00:00:00Z');
  const long = opened.plus({ days: 90 }).toISO();
  const short = opened.plus({ days: 5 }).toISO();

  check('M7 retention', `open shortens a 90d clock to ${OPENED_RETENTION_DAYS}d`,
    Math.round(DateTime.fromISO(retentionOnOpen(long, opened, false))
      .diff(opened,'days').days), OPENED_RETENTION_DAYS);
  check('M7 retention', 'open does NOT lengthen a shorter clock',
    Math.round(DateTime.fromISO(retentionOnOpen(short, opened, false))
      .diff(opened,'days').days), 5);
  check('M7 retention', 'preserved artifact keeps no clock',
    retentionOnOpen(long, opened, true), 'null');
  check('M7 retention', 'null clock on an unpreserved artifact gets one',
    retentionOnOpen(null, opened, false) !== null, 'true');
}

// -------------------------------------------------------------------------
// M8 — a CHILD sender (§9.5, 0019_child_message_sender.sql). Closes the
// audit finding "child_async_video_sender_identity schema change": before
// that migration, `senderRole:'child'` reached `can()` with structurally
// empty edges (a child never holds a guardianship edge to herself) and was
// always refused `not_authorized` — the schema had no way to attribute a
// capture to a child at all. Now it is a real, distinct authorization path.
// -------------------------------------------------------------------------
{
  const childCap = (o={}) => captureMessage({
    childId: CHILD, senderRole:'child', senderChildId: CHILD,
    storageKey:'k/child-1', durationMs: 6000, targetLocalDate: null,
    daypart:'bedtime', preserve: false, ...o,
  }, [], CTX, NOW);   // empty edges — a child holds no edge to herself, and
                       // none is needed for her own self-authored send.

  const r = childCap();
  check('M8 child sender', 'a child sending about herself succeeds', r.ok, 'true');
  check('M8 child sender', 'authorId is null, never a forged app_user id',
    r.artifact?.authorId, 'null');
  check('M8 child sender', 'authorChildId names the real sending child',
    r.artifact?.authorChildId, CHILD);
  check('M8 child sender', 'senderId is null on the intent too',
    r.intent?.senderId, 'null');
  check('M8 child sender', 'senderChildId names the real sending child',
    r.intent?.senderChildId, CHILD);
  // M1's own seam guarantee (artifact outlives intent) is untouched by which
  // branch computed the sender — retention math runs identically after.
  check('M8 child sender', 'the retention seam still holds for a child capture',
    DateTime.fromISO(r.artifact.expiresAt) > DateTime.fromISO(r.intent.expiresAt), 'true');

  // No senderChildId at all — the field a real HTTP caller can never
  // actually omit (server/routes.mjs derives it from the verified session,
  // never the body), but captureMessage() itself must still refuse it
  // rather than silently writing a null-attributed row.
  check('M8 child sender', 'a missing senderChildId is refused, not silently accepted',
    childCap({ senderChildId: undefined }).reason, 'child_sender_mismatch');

  // THE SHARED-DEVICE CASE the audit finding named by name: two siblings on
  // one kiosk, and a capture that claims to be from the WRONG one. api.ts's
  // own gateway (`principal.childId !== childId`) can never let real HTTP
  // traffic reach this shape (messages_route.test.mjs's own "D auth" group
  // proves that lock separately) — this is the SECOND, independent lock,
  // proven directly against the pure function so it is not merely assumed
  // to exist behind the first one.
  check('M8 child sender', 'a capture claiming a DIFFERENT child as sender is refused',
    childCap({ childId: CHILD, senderChildId: 'sibling-child-id' }).reason,
    'child_sender_mismatch');

  // §9.8.1 — preservation is a guardian election, never a child's to make.
  check('M8 child sender', 'a child cannot preserve her own sent artifact',
    childCap({ preserve: true }).reason, 'child_cannot_preserve');

  // The `guardian` path (M2's own suite) is unaffected — the branch is
  // chosen strictly by `senderRole`, and a plain guardian capture with a
  // real edge still succeeds exactly as before this file's own M1 proved.
  check('M8 child sender', "senderRole:'guardian' still succeeds, unaffected by the new branch",
    cap().ok, 'true');
  check('M8 child sender', 'a guardian capture still names authorId, never authorChildId',
    cap().artifact.authorChildId, 'null');
}

// -------------------------------------------------------------------------
let g = '';
for (const r of rows) {
  if (r.group !== g) { g = r.group; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(52)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
