/**
 * school — the school layer. MASTERFILE §11.5.
 *
 * The one package in the roster with real, shipped logic and no dedicated
 * suite of its own (it was wired into demo/src/play.ts's probe harness, but
 * never independently tested). Three things this settles and this file
 * proves: both-parents-expected flagging, duplicate-entry merging, and —
 * the sharpest edge — the NEVER_IN_SCHOOL_LAYER allowlist actually refusing
 * a grade/mark/attendance field, not just naming the intent to.
 */
import { isBothExpected, mergeDuplicates, bothExpectedUpcoming, papersDue,
  NEVER_IN_SCHOOL_LAYER, mayStore, auditSchoolPayload, BOTH_EXPECTED }
  from '../src/school.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const ev = (o = {}) => ({
  id: 'e1', kind: 'trip', label: 'Museum trip', date: '2026-09-01',
  enteredBy: 'dad', bothParentsExpected: false, scheduledParent: null, ...o,
});

// U · BOTH-PARENTS-EXPECTED — the events that actually cause trouble
{
  check('U both expected', 'a parents\' evening is flagged', isBothExpected('parents_evening'), 'true');
  check('U both expected', 'a performance is flagged', isBothExpected('performance'), 'true');
  check('U both expected', 'sports day is flagged', isBothExpected('sports_day'), 'true');
  check('U both expected', 'an ordinary trip is not flagged', isBothExpected('trip'), 'false');
  check('U both expected', 'photo day is not flagged', isBothExpected('photo_day'), 'false');
  check('U both expected', 'the exported list has exactly the three named kinds',
    [...BOTH_EXPECTED].sort().join(','), 'parents_evening,performance,sports_day');

  const upcoming = bothExpectedUpcoming([
    ev({ id: 'a', kind: 'performance', bothParentsExpected: true, date: '2026-09-10' }),
    ev({ id: 'b', kind: 'trip', bothParentsExpected: false, date: '2026-09-05' }),
    ev({ id: 'c', kind: 'sports_day', bothParentsExpected: true, date: '2026-08-01' }),
  ], '2026-08-16T00:00:00Z');
  check('U both expected', 'only the flagged, future event survives the filter',
    upcoming.map(e => e.id).join(','), 'a');
}

// V · DUPLICATE MERGING — two parents typing the same nativity play
{
  const dupes = mergeDuplicates([
    ev({ id: 'x1', enteredBy: 'dad', date: '2026-09-01', label: 'Museum Trip' }),
    ev({ id: 'x2', enteredBy: 'mum', date: '2026-09-01', label: 'museum trip' }),
    ev({ id: 'x3', enteredBy: 'dad', date: '2026-09-15', kind: 'photo_day', label: 'Photo day' }),
  ]);
  check('V duplicates', 'case- and whitespace-insensitive duplicates collapse to one',
    dupes.length, 2);
  check('V duplicates', 'the earliest of the duplicate entries is kept',
    dupes.find(e => e.date === '2026-09-01').id, 'x1');
  check('V duplicates', 'results are sorted by date',
    dupes.map(e => e.date).join(','), '2026-09-01,2026-09-15');

  const sameKindDifferentLabel = mergeDuplicates([
    ev({ id: 'y1', kind: 'trip', label: 'Museum', date: '2026-10-01' }),
    ev({ id: 'y2', kind: 'trip', label: 'Farm', date: '2026-10-01' }),
  ]);
  check('V duplicates', 'a different label on the same date/kind is NOT merged',
    sameKindDifferentLabel.length, 2);
}

// W · SCHOOL PAPER — the thing that comes home in a bag
{
  const papers = [
    { id: 'p1', title: 'Permission slip', artifactId: 'a1', photographedBy: 'dad',
      at: '2026-08-01T00:00:00Z', dueBy: '2026-08-20', preserved: false },
    { id: 'p2', title: 'Book list', artifactId: 'a2', photographedBy: 'mum',
      at: '2026-08-02T00:00:00Z', dueBy: '2026-08-10', preserved: false },
    { id: 'p3', title: 'Old newsletter', artifactId: 'a3', photographedBy: 'dad',
      at: '2026-07-01T00:00:00Z', dueBy: null, preserved: false },
  ];
  const due = papersDue(papers, '2026-08-11T00:00:00Z');
  check('W paper', 'only papers due on/after the reference date are returned, sorted',
    due.map(p => p.id).join(','), 'p1');
  check('W paper', 'a paper with no due date is never returned as "due"',
    due.some(p => p.id === 'p3'), 'false');
}

// X · THE BOUNDARY — what this layer will NEVER hold, actually enforced
{
  check('X boundary', 'grades are on the never-store list', mayStore('grades'), 'false');
  check('X boundary', 'attendance is refused', mayStore('attendance_record'), 'false');
  check('X boundary', 'an IEP is refused', mayStore('iep'), 'false');
  check('X boundary', 'an ordinary school event kind is allowed', mayStore('trip'), 'true');
  check('X boundary', 'eleven forbidden fields are named, not a shorter placeholder list',
    NEVER_IN_SCHOOL_LAYER.length, 11);

  const clean = auditSchoolPayload({ kind: 'trip', label: 'Museum', date: '2026-09-01' });
  check('X boundary', 'a clean event payload passes the audit', clean.ok, 'true');

  const leaky = auditSchoolPayload({
    kind: 'trip', label: 'Museum',
    nested: { attendance_record: '95%', teacher_comments: 'does well' },
  });
  check('X boundary', 'a leaked field deep in a nested payload is caught, not missed',
    leaky.ok, 'false');
  check('X boundary', 'both leaked fields are named, not just the first',
    leaky.leaks.sort().join(','), 'attendance_record,teacher_comments');

  const caseInsensitive = auditSchoolPayload({ GPA: 3.9 });
  check('X boundary', 'the audit is case-insensitive — GPA catches gpa',
    caseInsensitive.ok, 'false');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
