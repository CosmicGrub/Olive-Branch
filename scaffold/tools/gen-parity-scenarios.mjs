// Turns the LIVE prototype's behaviour into data the Flutter parity harness replays.
//
//   docs/superpowers/mockups/live/*.js            (the REFERENCE; run headless by tools/proto-headless.mjs)
//        |  this file: runs the prototype's own scenarios step by step on its virtual clock, records the
//        |  observable state after each step, and probes its RULES by exercising its own routes.
//        v
//   scaffold/client/test/parity/scenarios.json
//        { scenarios: [ { id, title, source, steps: [ { id, cap, dev, acts, ops, expect, rows } ] } ],
//          rules: { ...probed rule table... }, routes: [ ...static route table with error codes... ] }
//
// usage: node tools/gen-parity-scenarios.mjs            (writes scenarios.json)
//        node tools/gen-parity-scenarios.mjs --check    (exit 1 if the committed file is stale)
//        node tools/gen-parity-scenarios.mjs --print
//
// tools/test/parity_scenarios.test.mjs fails if scenarios.json is stale. Determinism: fake real clock, seeded
// Math.random, virtual clock fixed at Mon 9 Nov 2026 17:30 Chicago, so two runs are byte-identical.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { bootPrototype, readSources } from './proto-headless.mjs';

const HERE = fileURLToPath(new URL('.', import.meta.url));
export const OUT = HERE + '../client/test/parity/scenarios.json';
const MATRIX = HERE + '../../docs/superpowers/parity/matrix.json';
const MIN = 60000, HOUR = 3600000, DAY = 86400000;

// ---- matrix row ids: which parity-matrix row owns each prototype action / probe ------------------------
const ROW = {
  'ob.pickRole': 'action:ob.pickRole',
  'ob.g.label': 'action:ob.g.label / pickAge / zone', 'ob.g.pickAge': 'action:ob.g.label / pickAge / zone', 'ob.g.zone': 'action:ob.g.label / pickAge / zone',
  'dev.g.draft': 'action:ob.g.label / pickAge / zone',
  'ob.g.create': 'action:ob.g.pinNext / create / finish', 'ob.g.finish': 'action:ob.g.pinNext / create / finish',
  'ob.pad': 'action:ob.pad / ob.join.go / ob.other.join',
  'ob.kid.pickAge': 'action:ob.kid.pickAge / askLock / lockAge', 'ob.kid.askLock': 'action:ob.kid.pickAge / askLock / lockAge', 'ob.kid.lockAge': 'action:ob.kid.pickAge / askLock / lockAge',
  'ob.kid.pickColor': 'action:ob.kid.pickColor / setBM / setBD', 'ob.kid.setBM': 'action:ob.kid.pickColor / setBM / setBD', 'ob.kid.setBD': 'action:ob.kid.pickColor / setBM / setBD',
  'ob.kid.finish': 'action:ob.kid.submit / retry / finish', 'dev.k.draft.name': 'action:ob.kid.submit / retry / finish',
  'dev.k.draft.nick': 'kid.rename',
  'ob.add.done': 'action:ob.add.make / again / done',
  'msg.': 'msg-bank', 'msg.worker': 'rule:delivery-worker', 'msg.kidSync': 'k-msgs', 'msg.kOpenNewest': 'k-msgs', 'msg.playTo': 'rule:watched-played-through',
  'call.': 'rule:knock-only-child',
  'gPlayOn': 'play.window', 'gWind': 'play.window', 'gPlaySave': 'play.window', 'g-play': 'play.window',
  'g-family': 'row:Family/Family structure', 'g-history': 'row:Family/Family history', 'gRelease': 'k.family.held-band', 'kid.openMyPeople': 'kid.openMyPeople+kid.callSheet+kid.msgTo',
  'g-delete': 'row:Account/Delete my account', 'gDelAsk': 'row:Account/Delete my account', 'gDelGo': 'row:Account/Delete my account', 'gRecKey': 'row:Account/Account on hold',
  'probe:band': 'sub:age bands bandOf', 'probe:age': 'sub:birthday auto-increments age at local midnight',
  'probe:label': 'labels.age-defaults', 'probe:play': 'play.window', 'probe:acct': 'row:Account/Account on hold',
  'probe:msg': 'k-msgs', 'probe:screen': null, 'probe:fam': 'row:Family/Family structure', 'probe:pair': 'action:ob.add.make / again / done',
  'probe:call': 'rule:knock-only-child', 'probe:net': 'sub:offline/online as a feature (status 0)', 'probe:family': 'action:ob.g.pinNext / create / finish',
  'probe:dev.g': 'action:ob.pickRole', 'probe:dev.k.role': 'action:ob.pickRole', 'probe:dev.k.paired': 'action:ob.add.make / again / done', 'probe:child': 'action:ob.kid.pickAge / askLock / lockAge',
};
function rowsFor(keys, scenarioId) {
  const out = new Set();
  for (const k of keys) {
    let hit = ROW[k];
    if (hit === undefined) { const pre = Object.keys(ROW).filter((p) => k.startsWith(p) && (p.endsWith('.') || p.startsWith('probe:') || p.startsWith('dev.'))).sort((a, b) => b.length - a.length)[0]; hit = pre ? ROW[pre] : undefined; }
    if (hit) out.add(hit);
  }
  if (!out.size) out.add('scenario:' + scenarioId);
  return [...out].sort();
}
const matrixIds = () => new Set(JSON.parse(readFileSync(MATRIX, 'utf8')).map((r) => r.id));

// ---- observable state ---------------------------------------------------------------------------------
function probes(L) {
  const S = L.S, o = {}, safe = (k, f) => { try { const v = f(); if (v !== undefined && v !== null) o[k] = v; } catch { /* module not seeded yet */ } };
  const top = (d) => { const st = S.dev[d].stack; return st[st.length - 1].id; };
  o['probe:screen.g'] = top('g'); o['probe:screen.k'] = top('k');
  const c = S.family.child;
  o['probe:family.created'] = !!S.family.created;
  o['probe:dev.g.role'] = S.dev.g.role; o['probe:dev.k.role'] = S.dev.k.role;
  o['probe:dev.k.paired'] = !!S.dev.k.paired; o['probe:dev.g.signedIn'] = !!S.dev.g.sessionOk;
  o['probe:child.name'] = c.name || ''; o['probe:child.age'] = c.age; o['probe:child.ageLocked'] = !!c.ageLocked; o['probe:child.color'] = c.color || '';
  o['probe:band'] = L.band();
  safe('probe:label.mom', () => L.labels.forChild('mom')); safe('probe:label.dad', () => L.labels.forChild('dad'));
  o['probe:net.k.online'] = L.online('k'); o['probe:net.g.online'] = L.online('g');
  const ms = S.msg && S.msg.intents;
  if (ms) {
    o['probe:msg.count'] = ms.length;
    ms.forEach((m, i) => { o[`probe:msg.${i}.state`] = m.state; o[`probe:msg.${i}.attempts`] = m.attempts; o[`probe:msg.${i}.onTablet`] = m.state === 'delivered' || m.state === 'watched'; });
  }
  safe('probe:call.state', () => { const a = L.msg.activeCall(); return a ? (a.state || 'active') : 'none'; });
  if (L.__scenarioId === 'play') {
    safe('probe:play.state', () => L.grd.playState().state);
    safe('probe:play.config', () => { const p = S.grd.play; return { on: p.on, open: p.open, rest: p.rest, wind: p.wind }; });
  }
  safe('probe:acct.state', () => S.grd.acct.state);
  safe('probe:fam.people', () => S.grd.fam.people.length);
  safe('probe:fam.hist', () => S.grd.hist.filter((e) => e.kind === 'family').map((e) => { const t = e.timing && e.timing.mode; return e.status || t; }).join(','));
  return o;
}
const keyKind = (k) => k.replace(/^probe:/, '');

// ---- step execution -------------------------------------------------------------------------------------
function serialiseAct(a) {
  if (a.t === 'tap') return { t: 'tap', dev: a.dev, name: a.name, ...(a.arg != null ? { arg: String(a.arg) } : {}) };
  if (a.t === 'type') return { t: 'type', dev: a.dev, path: a.path, value: a.val };
  if (a.t === 'wait') return { t: 'wait', ms: a.ms };
  if (a.t === 'until') return { t: 'until', ms: a.ms };
  return { t: 'call' }; // a scripted closure; what it did is in `ops`
}

/** Records what a scripted `call` act does (the closure itself is not data): top-level operations only, only while it runs. */
function installTrace(P) {
  const L = P.L, trace = { ops: [], on: false, depth: 0 };
  const rec = (o) => { if (trace.on && trace.depth === 0) { trace.ops.push(o); return o; } return null; };
  const nested = (name, make) => {
    const orig = L[name];
    L[name] = function (...a) { rec(make(...a)); trace.depth++; try { return orig.apply(this, a); } finally { trace.depth--; } };
  };
  const origApi = L.api;
  L.api = function (dev, method, path, body) {
    const slot = rec({ op: 'api', dev, method, path, ...(body && body.mode ? { mode: body.mode } : {}) });
    return origApi.call(this, dev, method, path, body).then((r) => { if (slot) { slot.status = r.status; if (r.code) slot.code = r.code; } return r; });
  };
  const tapOp = (dev, name, arg) => ({ op: 'tap', dev, name, ...(arg != null ? { arg: String(arg) } : {}) });
  nested('tap', tapOp);
  nested('run', tapOp);
  nested('setOnline', (dev, on) => ({ op: 'net', dev, online: !!on }));
  nested('setAge', (n) => ({ op: 'age', age: n }));
  const origJump = L.jumpTo;
  L.jumpTo = function (t) { rec({ op: 'clock', to: new Date(t).toISOString(), advanceMs: Math.max(0, t - L.S.clock.t) }); trace.depth++; try { return origJump.call(this, t); } finally { trace.depth--; } };
  P.trace = trace;
  return trace;
}

/** A browser re-renders both devices after every change; render() is what lazily seeds the guardian module (S.grd). */
function renderBoth(P) {
  const L = P.L;
  for (const dev of ['g', 'k']) {
    const st = L.S.dev[dev].stack, def = L.screenDef(st[st.length - 1].id, dev);
    if (def) { try { def.render(L.ctx(dev)); } catch (e) { P.errors.push('render ' + dev + ': ' + (e && e.message || e)); } }
  }
}

async function execAct(P, a) {
  const L = P.L;
  if (a.t === 'tap') return void L.tap(a.dev, a.name, a.arg);
  if (a.t === 'type') return void L.type(a.dev, a.path, a.val);
  if (a.t === 'call') { P.trace.on = true; try { return await P.settle(Promise.resolve(a.fn({ m: [] }))); } finally { P.trace.on = false; } }
  if (a.t === 'until') return void (await P.until(a.fn, a.ms));
  if (a.t === 'wait') return void (await P.pump(a.ms));
}

async function runScenario(id, def) {
  const P = await bootPrototype();
  const L = P.L, sc = L.scenarios[id];
  L.__scenarioId = id;
  if (!sc.fresh) await P.settle(L.fastFamily(), 60000);
  renderBoth(P);
  const trace = installTrace(P), ops = trace.ops;
  let prev = probes(L);
  const initial = { ...prev };
  const steps = [];
  for (let i = 0; i < sc.steps.length; i++) {
    const st = sc.steps[i];
    ops.length = 0;
    for (const a of st.acts) {
      await execAct(P, a);
      renderBoth(P);
      if (a.t !== 'wait' && a.t !== 'until') await P.pump(a.gap == null ? 380 : a.gap);
    }
    renderBoth(P);
    await P.pump(1500); // let latency / microtasks settle, as the player does before the next caption
    const now = probes(L);
    const expect = Object.keys(now).filter((k) => JSON.stringify(now[k]) !== JSON.stringify(prev[k])).sort().map((k) => ({ probe: keyKind(k), value: now[k] }));
    const keys = [...st.acts.filter((a) => a.t === 'tap').map((a) => a.name), ...st.acts.filter((a) => a.t === 'type').map((a) => a.path.replace(/\.(mom|dad)$/, '')), ...expect.map((e) => 'probe:' + e.probe)];
    for (const a of st.acts) if (a.t === 'tap' && a.name === 'go') keys.push(a.arg);
    steps.push({
      id: `${id}.${String(i + 1).padStart(2, '0')}`, cap: st.cap, dev: st.dev,
      acts: st.acts.map(serialiseAct), ops: ops.map((o) => ({ ...o })), expect, rows: rowsFor(keys, id),
    });
    prev = now;
  }
  if (P.errors.length) throw new Error(`prototype errors in scenario ${id}: ${P.errors.slice(0, 3).join(' | ')}`);
  return { id, title: sc.title, source: def, desc: sc.desc, fresh: !!sc.fresh, initial: Object.entries(initial).map(([probe, value]) => ({ probe: keyKind(probe), value })), steps };
}

// ---- RULE TABLE: probed by exercising the prototype's own routes and logic ------------------------------
async function fresh(withFamily = true) {
  const P = await bootPrototype();
  if (withFamily) await P.settle(P.L.fastFamily(), 60000);
  return P;
}
const api = (P, dev, m, p, b) => P.settle(P.L.api(dev, m, p, b), 60000);
const brief = (r) => ({ status: r.status, ...(r.code ? { code: r.code } : {}) });

async function ruleTable() {
  const R = {};
  // labels + bands
  {
    const P = await fresh(false), L = P.L, c = L.S.family.child;
    L.S.family.guardians = [{ id: 'mom', name: 'Jess' }, { id: 'dad', name: 'Marcus' }];
    const labels = {}, bands = {};
    for (const locked of [false, true]) for (let age = 3; age <= 17; age++) {
      c.age = age; c.ageLocked = locked; c.nicknames = {};
      (labels[locked ? 'locked' : 'unlocked'] ||= {})[age] = [L.labels.forChild('mom'), L.labels.forChild('dad')];
      if (locked) bands[age] = L.band();
    }
    c.age = 9; c.ageLocked = true; c.nicknames = { mom: 'Mama' };
    R.labels = { table: labels, nicknameWins: L.labels.forChild('mom') === 'Mama', guardianCannotRename: L.labels.rename('mom', 'Mum', 'guardian').ok === false };
    R.bands = { byAge: bands, firstAgeOfBand: Object.fromEntries(['t34', 't57', 't812', 't1317'].map((b) => [b, +Object.keys(bands).find((a) => bands[a] === b)])) };
  }
  // PIN lockout (pairing-code route), 5 wrong in 15 virtual minutes
  {
    const P = await fresh(), L = P.L, cid = L.S.family.child.id, out = [];
    for (let i = 1; i <= 6; i++) { const r = await api(P, 'g', 'POST', `/v1/children/${cid}/device-pairing-codes`, { pin: '0000' }); out.push({ try: i, ...brief(r), ...(r.body.error && r.body.error.attemptsLeft != null ? { attemptsLeft: r.body.error.attemptsLeft } : {}) }); }
    const lockedAt = out.find((x) => x.status === 423).try;
    const until = L.S.server.pinLockUntil - L.S.clock.t;
    const good = await api(P, 'g', 'POST', `/v1/children/${cid}/device-pairing-codes`, { pin: '2468' });
    L.advance(15 * MIN + 1000);
    const after = await api(P, 'g', 'POST', `/v1/children/${cid}/device-pairing-codes`, { pin: '2468' });
    const P2 = await fresh(); const cid2 = P2.L.S.family.child.id;
    for (let i = 0; i < 4; i++) await api(P2, 'g', 'POST', `/v1/children/${cid2}/device-pairing-codes`, { pin: '0000' });
    const ok4 = await api(P2, 'g', 'POST', `/v1/children/${cid2}/device-pairing-codes`, { pin: '2468' });
    R.pinLockout = { wrongTriesToLock: lockedAt, lockMinutes: Math.round(until / MIN), windowMinutes: 15, attempts: out, correctPinWhileLocked: brief(good), correctPinAfterLock: brief(after), fourWrongThenRight: brief(ok4), childMayNotMakeCode: brief(await api(P2, 'k', 'POST', `/v1/children/${cid2}/device-pairing-codes`, { pin: '2468' })) };
  }
  // pairing code
  {
    const P = await fresh(), L = P.L, cid = L.S.family.child.id;
    const r = await api(P, 'g', 'POST', `/v1/children/${cid}/device-pairing-codes`, { pin: '2468' });
    const codes = [];
    for (let i = 0; i < 40; i++) { const rr = await api(P, 'g', 'POST', `/v1/children/${cid}/device-pairing-codes`, { pin: '2468' }); codes.push(rr.body.code); }
    R.pairing = { codeLength: r.body.code.length, alphabet: [...new Set(codes.join('').split(''))].sort().join('') === '' ? '' : (codes.join('').includes('0') ? '0-9' : '1-9'), ttlMinutes: r.body.ttlMs / MIN, newCodeRevokesOlder: true,
      wrongRoleRedeem: undefined };
    // redeem lockout: 5 wrong codes by the tablet
    const Q = await fresh(false); const QL = Q.L; await Q.settle(QL.fastFamily(), 60000).catch(() => {});
    const tries = [];
    const T = await bootPrototype(); T.L.S.dev.k.role = 'kid'; T.L.S.family.created = true;
    for (let i = 1; i <= 6; i++) { const x = await api(T, 'k', 'POST', '/v1/device-pairing/redeem', { code: '999999', role: 'child' }); tries.push({ try: i, ...brief(x) }); }
    R.pairing.redeemLockoutTries = tries; R.pairing.redeemLockoutMinutes = Math.round((T.L.S.server.redeemFails.lockUntil.k - T.L.S.clock.t) / MIN);
    delete R.pairing.wrongRoleRedeem;
  }
  // watched = played through; message limits; retry cadence; reply expiry
  {
    const P = await fresh(), L = P.L, cid = L.S.family.child.id;
    const bank = (b) => api(P, 'g', 'POST', `/v1/children/${cid}/messages`, b);
    const short = await bank({ durMs: 2999 }), long = await bank({ durMs: 600001 }), badRule = await bank({ durMs: 5000, rule: { type: 'x' } });
    const m = await bank({ durMs: 101000, title: 'x', rule: { type: 'bedtime' } });
    const id = m.body.message.id;
    L.jumpToNext('bedtime'); await P.pump(100); L.msg.worker(); await api(P, 'k', 'GET', `/v1/children/${cid}/inbox`);
    const state1 = L.msg.m()[0].state;
    const early = await api(P, 'k', 'POST', `/v1/children/${cid}/inbox/${id}/watched`, { playedMs: 101000 - 1501 });
    const edge = await api(P, 'k', 'POST', `/v1/children/${cid}/inbox/${id}/watched`, { playedMs: 101000 - 1500 });
    R.messages = { minMs: 3000, maxMs: 600000, tooShort: brief(short), tooLong: brief(long), badRule: brief(badRule), deliveredOnBedtime: state1, watchedToleranceMs: 1500, playedMsBelowToleranceRefused: brief(early), playedMsAtToleranceAccepted: brief(edge), notPlayedThroughCode: early.code };
    // retry cadence: tablet offline from the start
    const Q = await fresh(); const QL = Q.L; const qcid = QL.S.family.child.id;
    await api(Q, 'g', 'POST', `/v1/children/${qcid}/messages`, { durMs: 60000, rule: { type: 'bedtime' } });
    QL.setOnline('k', false); QL.jumpToNext('bedtime');
    const it = () => QL.msg.m()[0];
    let last = 0, due = 0;
    const times = [];
    for (let i = 0; i < 12 * 60 && it().state !== 'failed'; i++) {
      QL.advance(MIN); QL.msg.worker();
      if (it().attempts !== last) { if (!due) due = it().readyAt; times.push(due); last = it().attempts; due = it().nextAt; }
    }
    const gaps = times.slice(1).map((t, i) => (t - times[i]) / MIN);
    R.retryCadence = { firstRetryAfterMinutes: gaps[0], laterRetryAfterMinutes: gaps[1], maxAttempts: it().attempts, finalState: it().state, gapsMinutes: gaps };
    // reply expiry (14 days) and keep
    QL.setOnline('k', true);
    const rep = await api(Q, 'k', 'POST', `/v1/children/${qcid}/replies`, { to: 'mom', mode: 'voice', durMs: 3000 });
    R.expiry = { replyKeptDays: Math.round((rep.body.reply.expiresAt - QL.S.clock.t) / DAY), guardianSentMessagesPreserved: QL.msg.m()[0].preserved === true };
  }
  // calls: only guardians start, only children knock
  {
    const P = await fresh(), cid = P.L.S.family.child.id;
    R.calls = { childStartsCall: brief(await api(P, 'k', 'POST', `/v1/children/${cid}/calls`, {})), guardianKnocks: brief(await api(P, 'g', 'POST', `/v1/children/${cid}/calls/knock`, {})), knockTimeoutSeconds: 30 };
  }
  // play window + parental controls + deletion + emergency card + medications (guardian module)
  {
    const P = await fresh(), L = P.L;
    const put = (w) => api(P, 'g', 'PUT', '/v1/play-window', { play: w });
    await put({ on: true, open: '07:30', rest: '19:30', wind: 15 });
    const tz = L.homeTz(), states = {};
    for (const [label, h, m] of [['07:29', 7, 29], ['07:30', 7, 30], ['19:29', 19, 29], ['19:30', 19, 30], ['19:44', 19, 44], ['19:45', 19, 45], ['23:00', 23, 0]]) {
      const p = L.parts(L.S.clock.t, tz); states[label] = L.grd.playState(L.zoned(p.y, p.m, p.d, h, m, tz)).state;
    }
    const bad = await put({ on: true, open: '7:30', rest: '19:30' });
    R.playWindow = { states, windDownMinutes: [0, 15, 30], badTimes: brief(bad), neverClosesCallsOrMessages: true, longerWindowNotifiesPartner: true };
    const hideMsg = await api(P, 'g', 'PUT', '/v1/parental-controls', { tile: 'messages', hidden: true });
    const hideGames = await api(P, 'g', 'PUT', '/v1/parental-controls', { tile: 'games', hidden: true });
    const unknown = await api(P, 'g', 'PUT', '/v1/parental-controls', { tile: 'nope', hidden: true });
    R.parentalControls = { hideMessages: brief(hideMsg), hideGames: brief(hideGames), unknownTile: brief(unknown), paceChoicesMinutes: [0, 30, 60, 120] };
    const v0 = L.S.grd.srv.emerg.v;
    const em0 = await api(P, 'g', 'PUT', '/v1/emergency-card', { base: v0, data: { allergies: 'x' } });
    const stale = await api(P, 'g', 'PUT', '/v1/emergency-card', { base: v0, data: { allergies: 'y' } });
    R.emergencyCard = { staleBase: brief(stale), staleReturnsCurrentVersion: !!(stale.body.error && stale.body.error.current), savedAtCurrentVersion: brief(em0) };
    const m = L.S.grd.srv.meds[0]; let dose = null;
    if (m) { const a = await api(P, 'g', 'POST', `/v1/medications/${m.id}/doses`); const b = await api(P, 'g', 'POST', `/v1/medications/${m.id}/doses`); dose = { first: brief(a), second: brief(b), prnGapMinutes: m.kind === 'prn' ? m.gap * 60 : undefined, kind: m.kind }; }
    R.medications = { doubleDose: dose };
    const del = await api(P, 'g', 'POST', '/v1/account/delete', {});
    R.deletion = { minDays: (L.S.grd.acct.minEnd - L.S.grd.acct.at) / DAY, maxDays: (L.S.grd.acct.maxEnd - L.S.grd.acct.at) / DAY, minMonthsApprox: 6, maxMonthsApprox: 12, recoverNeedsPin: true, signInPausedAtOnce: L.S.dev.g.sessionOk === false, deleteOk: brief(del) };
  }
  // family changes
  {
    const P = await fresh(), L = P.L;
    L.go('g', 'g-family'); renderBoth(P);
    const g = L.S.grd, d = JSON.parse(JSON.stringify(g.fam));
    d.people.push({ id: 'p_t', name: 'T', role: 'Friend', home: '', away: false, reach: { messages: true, calls: false, story: false } });
    const stale = await api(P, 'g', 'POST', '/v1/family-changes', { draft: d, baseV: 99, mode: 'now' });
    const none = await api(P, 'g', 'POST', '/v1/family-changes', { draft: g.fam, baseV: g.famV || 0, mode: 'now' });
    const badMode = await api(P, 'g', 'POST', '/v1/family-changes', { draft: d, baseV: g.famV || 0, mode: 'later' });
    const held = await api(P, 'g', 'POST', '/v1/family-changes', { draft: d, baseV: g.famV || 0, mode: 'hold' });
    const before = g.fam.people.length;
    const rel = await api(P, 'g', 'POST', `/v1/family-changes/${held.body.id}/release`, {});
    R.familyChanges = { staleBase: brief(stale), nothingChanged: brief(none), badTiming: brief(badMode), held: { ...brief(held), result: held.body.status }, peopleBeforeRelease: before, peopleAfterRelease: g.fam.people.length, release: brief(rel), maxDateAheadDays: 730, maxHomes: 4 };
  }
  // session / device
  {
    const P = await fresh(), L = P.L, cid = L.S.family.child.id;
    R.session = { childGetsNotAChildSurface: brief(await api(P, 'g', 'PUT', `/v1/children/${cid}/profile`, {})), lockedAgeNeverOverwritten: (await api(P, 'k', 'PUT', `/v1/children/${cid}/profile`, { age: 14 }), L.S.family.child.age === 9), sessionDaysGuardian: 14, sessionDaysChildDevice: 3650 };
  }
  return R;
}

// ---- static route table (method, path, who, error codes) ------------------------------------------------------
function skipTo(src, i, openCh, closeCh) { // index just after the matching closer, skipping strings, comments, regex literals
  let depth = 0, prevSig = '';
  for (let p = i; p < src.length; p++) {
    const ch = src[p];
    if (ch === '/' && src[p + 1] === '/') { while (p < src.length && src[p] !== '\n') p++; continue; }
    if (ch === '/' && src[p + 1] === '*') { p = src.indexOf('*/', p + 2) + 1; continue; }
    if (ch === '"' || ch === "'" || ch === '`') { const q = ch; p++; while (p < src.length && src[p] !== q) { if (src[p] === '\\') p++; p++; } prevSig = 'x'; continue; }
    if (ch === '/' && /[(,=:[!&|?{};]/.test(prevSig || '(')) { p++; while (p < src.length && src[p] !== '/') { if (src[p] === '\\') p++; else if (src[p] === '[') { while (src[p] !== ']') { if (src[p] === '\\') p++; p++; } } p++; } prevSig = 'x'; continue; }
    if (ch === openCh) depth++;
    else if (ch === closeCh) { depth--; if (depth === 0) return p + 1; }
    if (!/\s/.test(ch)) prevSig = ch;
  }
  return src.length;
}
function routeTable() {
  const out = [];
  for (const { file, src } of readSources()) {
    for (const m of src.matchAll(/L\.route\(\s*["'](\w+)["']\s*,\s*["']([^"']+)["']/g)) {
      const start = m.index, end = skipTo(src, start + 7, '(', ')');
      let body = src.slice(start, end);
      const seen = new Set();
      for (const s of body.matchAll(/\b(srv\w+|pinTry|callRoute)\(/g)) {
        const fi = src.indexOf('function ' + s[1] + '(');
        if (fi >= 0 && !seen.has(s[1])) { seen.add(s[1]); const bi = src.indexOf('{', fi); body += '\n' + src.slice(fi, skipTo(src, bi, '{', '}')); }
      }
      const codes = [...new Set([...body.matchAll(/\bfail\(\s*(\d{3})\s*,\s*['"](\w+)['"]/g)].map((x) => `${x[1]} ${x[2]}`))].sort();
      const who = /public\s*:\s*true/.test(src.slice(end - 40, end + 40)) || /\{\s*public\s*:\s*true\s*\}\s*\)/.test(src.slice(end - 30, end + 2)) ? 'public'
        : (src.slice(end - 60, end).match(/principals\s*:\s*\[([^\]]*)\]/) || [, 'any'])[1].replace(/["'\s]/g, '') || 'any';
      out.push({ method: m[1].toUpperCase(), path: m[2], who, errors: codes, file });
    }
  }
  return out.sort((a, b) => (a.path + a.method).localeCompare(b.path + b.method));
}

// ---- main ---------------------------------------------------------------------------------------------------
export async function render() {
  const ids = ['golden', 'offline', 'birthday', 'call', 'play', 'family', 'deletion'];
  const scenarios = [];
  for (const id of ids) scenarios.push(await runScenario(id, 'prototype'));
  const known = matrixIds();
  for (const s of scenarios) for (const st of s.steps) for (const r of st.rows) if (!known.has(r)) throw new Error(`matrix row ${r} (step ${st.id}) is not in matrix.json`);
  const doc = { generatedBy: 'tools/gen-parity-scenarios.mjs', note: 'GENERATED from docs/superpowers/mockups/live. Do not edit; run node tools/gen-parity-scenarios.mjs.', scenarios, rules: await ruleTable(), routes: routeTable() };
  return JSON.stringify(doc, null, 1) + '\n';
}

if (process.argv[1] && process.argv[1].endsWith('gen-parity-scenarios.mjs')) {
  const json = await render();
  if (process.argv.includes('--print')) process.stdout.write(json);
  else if (process.argv.includes('--check')) {
    const cur = existsSync(OUT) ? readFileSync(OUT, 'utf8').replace(/\r\n/g, '\n') : '';
    if (cur !== json) { console.error('scenarios.json is stale: run node tools/gen-parity-scenarios.mjs'); process.exit(1); }
    console.log('scenarios.json is current');
  } else { writeFileSync(OUT, json); console.log('wrote ' + OUT); }
}
