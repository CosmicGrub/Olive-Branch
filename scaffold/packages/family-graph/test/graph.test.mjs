/**
 * family-graph — adversarial suite.
 * MASTERFILE §5.1, §8.1, §17.1, §17.3, P6, P7.
 */
import { can, isSingleGuardianViable } from '../src/authorize.mjs';
import { withSession, withSystemSession, SessionContextError } from '../src/session.mjs';

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}
const NOW = new Date('2026-07-26T12:00:00Z');
const CHILD_A = 'aaaa', CHILD_B = 'bbbb';

const edge = (o = {}) => ({
  childId: CHILD_A, userId: 'dad', role: 'guardian', scope: {},
  observerOnly: false, restricted: false,
  validFrom: '2020-01-01T00:00:00Z', validTo: null,
  expiresAt: null, closedAt: null, ladderStep: null, ...o,
});
const why = (d) => d.allow ? 'allow' : d.reason;

// ---------------------------------------------------------------------------
// H1 — P7. No argument to can() returns allow for journal.read.
// ---------------------------------------------------------------------------
{
  const roles = ['guardian','step_parent','trusted_adult','sitter','coordinator',
                 'foster_parent','caseworker','therapist'];
  let leaked = 0;
  for (const role of roles) {
    // Maximally privileged construction: full scope, court tier, open ladder.
    const d = can('journal.read',
      [edge({ role, scope: { 'journal.read': true } })],
      CHILD_A, NOW, role, { court: true });
    if (d.allow) leaked++;
  }
  check('H1 P7', 'no role can read the journal', leaked, 0);
  check('H1 P7', 'denial names the prohibition',
    why(can('journal.read', [edge()], CHILD_A, NOW, 'guardian', { court: true })),
    'P7_journal_never');
  // Even with no edge at all the reason must be P7, not no_edge — the check
  // happens before edge resolution so the answer never depends on the graph.
  check('H1 P7', 'checked before edge resolution',
    why(can('journal.read', [], CHILD_A, NOW)), 'P7_journal_never');
}

// ---------------------------------------------------------------------------
// H2 — P6. A child role never reaches a financial surface.
// ---------------------------------------------------------------------------
{
  check('H2 P6', 'child cannot view expenses',
    why(can('expense.view', [edge()], CHILD_A, NOW, 'child')), 'P6_child_financial');
  check('H2 P6', 'child cannot create expenses',
    why(can('expense.create', [edge()], CHILD_A, NOW, 'child')), 'P6_child_financial');
  // expense.resolve (accept/dispute/reimburse) -- added alongside the real
  // expense backend; P6's own startsWith('expense.') check already covers
  // any new expense.* action without modification, but this is proven here
  // rather than assumed.
  check('H2 P6', 'child cannot resolve expenses either',
    why(can('expense.resolve', [edge()], CHILD_A, NOW, 'child')), 'P6_child_financial');
  check('H2 P6', 'guardian still can',
    can('expense.view', [edge()], CHILD_A, NOW, 'guardian').allow, 'true');
  check('H2 P6', 'guardian can resolve',
    can('expense.resolve', [edge()], CHILD_A, NOW, 'guardian').allow, 'true');
  // §17.3 observer -- expense.resolve is a real decision, not a read; an
  // observer-only guardian must be refused the same way expense.create
  // already is.
  check('H2 P6', 'an observer-only guardian cannot resolve an expense',
    why(can('expense.resolve', [edge({ observerOnly: true })], CHILD_A, NOW, 'guardian')),
    'observer_readonly');
  // coordinator holds expense.view (read-only, MASTERFILE's own "Read-only
  // across... the expense ledger") but never expense.resolve -- a real
  // decision belongs to a guardian party to it, not a court-appointed reader.
  check('H2 P6', 'a coordinator cannot resolve an expense -- read-only role',
    why(can('expense.resolve', [edge({ role: 'coordinator' })], CHILD_A, NOW, 'coordinator')),
    'role_lacks_capability');
}

// ---------------------------------------------------------------------------
// H2b -- emergency_card.edit, added alongside the real medications/
// emergency-card backend. Not P6-blocked (this is medical, not financial)
// but guardian-only to write: MASTERFILE's own "sitter role readable"
// carve-out (§7.7/§9.6.3) is read-only, never write.
// ---------------------------------------------------------------------------
{
  check('H2b medical', 'guardian can edit the emergency card',
    can('emergency_card.edit', [edge()], CHILD_A, NOW, 'guardian').allow, 'true');
  check('H2b medical', 'a sitter can VIEW the emergency card -- the real, narrow '
    + 'read carve-out this role exists for',
    can('emergency_card.view', [edge({ role: 'sitter' })], CHILD_A, NOW, 'sitter').allow, 'true');
  check('H2b medical', 'a sitter cannot EDIT the emergency card -- read-only, never write',
    why(can('emergency_card.edit', [edge({ role: 'sitter' })], CHILD_A, NOW, 'sitter')),
    'role_lacks_capability');
  check('H2b medical', 'a step_parent can VIEW medications but cannot LOG a dose -- '
    + 'a real, pre-existing ROLE_CAPS distinction, not new to this pass',
    why(can('medication.log', [edge({ role: 'step_parent' })], CHILD_A, NOW, 'step_parent')),
    'role_lacks_capability');
  // §17.3 observer -- editing the emergency card is a real write.
  check('H2b medical', 'an observer-only guardian cannot edit the emergency card',
    why(can('emergency_card.edit', [edge({ observerOnly: true })], CHILD_A, NOW, 'guardian')),
    'observer_readonly');
}

// ---------------------------------------------------------------------------
// H3 — LATERAL PRIVILEGE. Guardian of one sibling must not reach the other.
//      sibling_link creates a traversal path; this is the obvious escalation.
// ---------------------------------------------------------------------------
{
  const edges = [edge({ childId: CHILD_A })];
  check('H3 lateral', 'guardian of A can act on A',
    can('call', edges, CHILD_A, NOW).allow, 'true');
  check('H3 lateral', 'guardian of A CANNOT act on sibling B',
    why(can('call', edges, CHILD_B, NOW)), 'no_edge');
  check('H3 lateral', 'nor read sibling B homework',
    why(can('homework.view', edges, CHILD_B, NOW)), 'no_edge');
  check('H3 lateral', 'nor preserve sibling B archive',
    why(can('archive.preserve', edges, CHILD_B, NOW)), 'no_edge');
}

// ---------------------------------------------------------------------------
// H4 — the four ways an edge stops counting.
// ---------------------------------------------------------------------------
{
  check('H4 edge lifecycle', 'closed edge denies (deceased parent)',
    why(can('call', [edge({ closedAt: '2026-01-01T00:00:00Z' })], CHILD_A, NOW)),
    'edge_closed');
  check('H4 edge lifecycle', 'expired sitter token denies',
    why(can('medication.log',
      [edge({ role: 'sitter', expiresAt: '2026-07-25T00:00:00Z' })], CHILD_A, NOW)),
    'edge_expired');
  check('H4 edge lifecycle', 'live sitter token allows',
    can('medication.log',
      [edge({ role: 'sitter', expiresAt: '2026-07-27T00:00:00Z' })], CHILD_A, NOW).allow,
    'true');
  check('H4 edge lifecycle', 'order not yet in force denies',
    why(can('call', [edge({ validFrom: '2027-01-01T00:00:00Z' })], CHILD_A, NOW)),
    'outside_validity');
  check('H4 edge lifecycle', 'ended validity window denies',
    why(can('call', [edge({ validTo: '2026-01-01T00:00:00Z' })], CHILD_A, NOW)),
    'outside_validity');
  check('H4 edge lifecycle', 'protective order denies',
    why(can('call', [edge({ restricted: true })], CHILD_A, NOW)), 'restricted');
}

// ---------------------------------------------------------------------------
// H5 — the contact ladder. Step 'none' blocks contact but not a coordinator read.
// ---------------------------------------------------------------------------
{
  check('H5 ladder', "step 'none' blocks calls",
    why(can('call', [edge({ ladderStep: 'none' })], CHILD_A, NOW)), 'ladder_none');
  check('H5 ladder', "step 'none' blocks messages",
    why(can('message', [edge({ ladderStep: 'none' })], CHILD_A, NOW)), 'ladder_none');
  check('H5 ladder', "step 'supervised' permits calls",
    can('call', [edge({ ladderStep: 'supervised' })], CHILD_A, NOW).allow, 'true');
  check('H5 ladder', "coordinator read survives step 'none'",
    can('calendar.view',
      [edge({ role: 'coordinator', ladderStep: 'none' })], CHILD_A, NOW).allow, 'true');
  check('H5 ladder', 'null ladder defaults to open',
    can('call', [edge({ ladderStep: null })], CHILD_A, NOW).allow, 'true');
}

// ---------------------------------------------------------------------------
// H6 — §17.3 observer tier. The reluctant parent watches, cannot act.
// ---------------------------------------------------------------------------
{
  const obs = [edge({ observerOnly: true })];
  check('H6 observer', 'can view homework', can('homework.view', obs, CHILD_A, NOW).allow, 'true');
  check('H6 observer', 'can view archive',  can('archive.view',  obs, CHILD_A, NOW).allow, 'true');
  check('H6 observer', 'CANNOT annotate',   why(can('homework.annotate', obs, CHILD_A, NOW)), 'observer_readonly');
  check('H6 observer', 'CANNOT edit calendar', why(can('calendar.edit', obs, CHILD_A, NOW)), 'observer_readonly');
  check('H6 observer', 'CANNOT change settings', why(can('settings', obs, CHILD_A, NOW)), 'observer_readonly');
  check('H6 observer', 'CANNOT claim a need', why(can('list.claim', obs, CHILD_A, NOW)), 'observer_readonly');
  check('H6 observer', 'CAN still call', can('call', obs, CHILD_A, NOW).allow, 'true');
}

// ---------------------------------------------------------------------------
// H7 — role capability boundaries.
// ---------------------------------------------------------------------------
{
  check('H7 roles', 'trusted adult cannot edit the calendar',
    why(can('calendar.edit', [edge({ role: 'trusted_adult' })], CHILD_A, NOW)),
    'role_lacks_capability');
  check('H7 roles', 'trusted adult cannot claim a need',
    why(can('list.claim', [edge({ role: 'trusted_adult' })], CHILD_A, NOW)),
    'role_lacks_capability');
  check('H7 roles', 'sitter cannot call the child',
    why(can('call', [edge({ role: 'sitter' })], CHILD_A, NOW)), 'role_lacks_capability');
  check('H7 roles', 'sitter CAN read the emergency card',
    can('emergency_card.view', [edge({ role: 'sitter' })], CHILD_A, NOW).allow, 'true');
  check('H7 roles', 'coordinator has NO child-facing surface',
    why(can('call', [edge({ role: 'coordinator' })], CHILD_A, NOW)),
    'role_lacks_capability');
  check('H7 roles', 'therapist may advance the ladder',
    can('ladder.advance', [edge({ role: 'therapist' })], CHILD_A, NOW).allow, 'true');
  check('H7 roles', 'guardian may NOT advance the ladder',
    why(can('ladder.advance', [edge({ role: 'guardian' })], CHILD_A, NOW)),
    'role_lacks_capability');
  check('H7 roles', 'explicit scope false overrides role default',
    why(can('calendar.edit', [edge({ scope: { 'calendar.edit': false } })], CHILD_A, NOW)),
    'scope_denied');
}

// ---------------------------------------------------------------------------
// H8 — §2.11 / §16.1 #3. Raw export is never withheld; certified is tiered.
// ---------------------------------------------------------------------------
{
  check('H8 export', 'raw export allowed off the court tier',
    can('export.raw', [edge()], CHILD_A, NOW, 'guardian', { court: false }).allow, 'true');
  check('H8 export', 'certified export requires the court tier',
    why(can('export.certified', [edge()], CHILD_A, NOW, 'guardian', { court: false })),
    'tier_required');
  check('H8 export', 'certified export allowed on the court tier',
    can('export.certified', [edge()], CHILD_A, NOW, 'guardian', { court: true }).allow, 'true');
  check('H8 export', 'raw export survives an observer-only edge',
    can('export.raw', [edge({ observerOnly: true })], CHILD_A, NOW).allow, 'true');
}

// ---------------------------------------------------------------------------
// H9 — §17.1 single-guardian mode. One parent is a complete product.
// ---------------------------------------------------------------------------
{
  check('H9 single guardian', 'one live guardian is viable',
    isSingleGuardianViable([edge()], CHILD_A, NOW), 'true');
  check('H9 single guardian', 'every core action works with one guardian',
    ['call','message','homework.view','homework.annotate','calendar.edit',
     'archive.preserve','export.raw','medication.log']
      .every(a => can(a, [edge()], CHILD_A, NOW).allow), 'true');
  check('H9 single guardian', 'a closed second edge does not break the first',
    can('call', [edge(), edge({ userId: 'mom', closedAt: '2026-01-01T00:00:00Z' })],
        CHILD_A, NOW).allow, 'true');
  check('H9 single guardian', 'restricted edge does not shadow a live one',
    can('call', [edge({ userId: 'mom', restricted: true }), edge()], CHILD_A, NOW).allow,
    'true');
  check('H9 single guardian', 'no live guardian is not viable',
    isSingleGuardianViable([edge({ closedAt: '2026-01-01T00:00:00Z' })], CHILD_A, NOW),
    'false');
}

// ---------------------------------------------------------------------------
// H10 — session context. The leak that a pooled connection makes invisible.
// ---------------------------------------------------------------------------
{
  const log = [];
  const client = {
    query: async (sql, params) => { log.push({ sql: sql.replace(/\s+/g,' ').trim(), params }); return { rows: [] }; },
    release: () => log.push({ sql: 'RELEASE' }),
  };
  const pool = { connect: async () => client };

  await withSession(pool, { verified: true, userId: 'dad', roleName: 'guardian', childId: CHILD_A },
    async () => 'ok');

  const setCall = log.find(l => l.sql.includes('set_config'));
  check('H10 session', 'opens a transaction first', log[0].sql, 'BEGIN');
  check('H10 session', 'uses set_config with is_local = true',
    /set_config\('app\.role', +\$1, true\)/.test(setCall.sql), 'true');
  check('H10 session', 'never interpolates context into SQL',
    setCall.params.join('|'), `guardian|${CHILD_A}|dad`);
  check('H10 session', 'commits', log.some(l => l.sql === 'COMMIT'), 'true');
  check('H10 session', 'releases the connection', log.at(-1).sql, 'RELEASE');
  check('H10 session', 'no plain SET leaks past the transaction',
    log.some(l => /^SET (?!LOCAL)/i.test(l.sql)), 'false');

  // On throw: rollback AND release. A leaked connection with live context is
  // the cross-tenant read.
  const log2 = [];
  const c2 = { query: async (s) => { log2.push(s.replace(/\s+/g,' ').trim()); return { rows: [] }; },
               release: () => log2.push('RELEASE') };
  let threw = false;
  try {
    await withSession({ connect: async () => c2 },
      { verified: true, userId: 'dad', roleName: 'guardian', childId: CHILD_A },
      async () => { throw new Error('boom'); });
  } catch { threw = true; }
  check('H10 session', 'propagates the callback error', threw, 'true');
  check('H10 session', 'rolls back on throw', log2.includes('ROLLBACK'), 'true');
  check('H10 session', 'releases on throw', log2.at(-1), 'RELEASE');
  check('H10 session', 'does NOT commit on throw', log2.includes('COMMIT'), 'false');

  // Malformed principals fail loudly rather than matching nothing.
  const bad = async (ctx) => {
    try { await withSession(pool, ctx, async () => 1); return 'allowed'; }
    catch (e) { return e instanceof SessionContextError ? 'rejected' : 'other'; }
  };
  check('H10 session', 'child role with no childId is rejected',
    await bad({ verified: true, userId: null, roleName: 'child', childId: null }), 'rejected');
  check('H10 session', 'guardian with no userId is rejected',
    await bad({ verified: true, userId: null, roleName: 'guardian', childId: CHILD_A }), 'rejected');
  check('H10 session', 'unverified principal is rejected',
    await bad({ verified: false, userId: 'dad', roleName: 'guardian', childId: CHILD_A }), 'rejected');

  // The sweep runs with no principal and must not carry a child context.
  const log3 = [];
  const c3 = { query: async (s, p) => { log3.push({ s: s.replace(/\s+/g,' ').trim(), p }); return { rows: [] }; },
               release: () => {} };
  await withSystemSession({ connect: async () => c3 }, async () => 1);
  const sysSet = log3.find(l => l.s.includes('set_config'));
  check('H10 session', 'system session sets role=system, no child',
    /'app\.role', 'system'/.test(sysSet.s) && /'app\.child_id', ''/.test(sysSet.s), 'true');
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) {
  if (r.group !== g) { g = r.group; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(52)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
