// Scripted ACTORS: a guardian, a co-guardian, a sitter and each child's device,
// driven through the app's REAL server routes. A step that cannot be done today
// (no such route / the route refuses a legitimate request) is recorded as a GAP
// or a FAIL with the route name and the evidence. A step is never faked.
import { randomBytes } from 'node:crypto';
import { fmtVirtual } from './seed.mjs';
import { sleep } from './util.mjs';

const OK = [200, 201];

/** A minimal but real MP4 header: passes the server's magic-byte sniff (video/mp4). */
export function tinyMp4(n = 1800) {
  return Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypisom'), Buffer.from([0, 0, 2, 0]),
    Buffer.from('isomiso2'), randomBytes(n)]);
}

export function newCtx({ client, rec, fams, admin = null, worker = null, plan = null }) {
  return { client, rec, fams, admin, worker, plan, state: new Map(), gaps: new Map(), fails: [], notes: [], checks: 0 };
}
export const st = (ctx, fam) => {
  let s = ctx.state.get(fam.n);
  if (!s) ctx.state.set(fam.n, s = { g: [], kids: [], kidTok: [], devices: [], health: 'idle', step: 'waiting', steps: 0, ok: 0, bad: 0, artifacts: {} });
  return s;
};

export function addGap(ctx, id, title, routes, evidence) {
  if (ctx.gaps.has(id)) return;
  const gap = { id, title, routes, evidence };
  ctx.gaps.set(id, gap);
  ctx.rec.emit('gap', gap);
}

/** One recorded step: do a real request, record the outcome, update the family tile. */
export async function S(ctx, fam, id, title, method, path, opts = {}, { expect = OK, note } = {}) {
  await ctx.rec.gate();
  const s = st(ctx, fam);
  s.step = title; s.health = s.bad ? 'warn' : 'run';
  ctx.rec.emit('step.start', { fam: fam.n, id, title });
  const res = await ctx.client.call(method, path, { ...opts, fam: fam.n });
  const ok = expect.includes(res.status);
  s.steps++; ok ? s.ok++ : s.bad++;
  ctx.rec.emit('step', { fam: fam.n, id, title, route: `${method} ${path.replace(/[0-9a-f]{8}-[0-9a-f-]{27}/g, ':id').split('?')[0]}`,
    status: res.status, ms: Math.round(res.ms * 10) / 10, ok, note });
  if (!ok) {
    ctx.fails.push({ fam: fam.n, id, title, route: `${method} ${path}`, status: res.status, body: res.body });
    s.health = 'warn';
  }
  res.ok = ok;
  return res;
}

const vclock = (ctx, label) => ctx.rec.emit('clock', { virtual: label });

/** Wait (real time) until virtual hour `vh` of the compressed day, honouring pause/speed. */
export async function untilVirtual(ctx, vh) {
  if (!ctx.plan) return;
  for (;;) {
    await ctx.rec.gate();
    const target = ctx.plan.realAt(vh), now = Date.now();
    if (now >= target) return;
    await sleep(Math.min(250, (target - now) / ctx.rec.speed));
    if (ctx.rec.speed !== 1) {          // speed changes shift the plan, keep it simple: skip ahead proportionally
      const late = (target - Date.now()) * (1 - 1 / ctx.rec.speed);
      ctx.plan.startMs -= Math.max(0, late) * 0.2;
    }
  }
}

// ---------------------------------------------------------------------------
// ONBOARDING
// ---------------------------------------------------------------------------
export async function probeMissingOnboardingRoutes(ctx, fam) {
  // Real attempts, recorded as evidence. Run once for the whole simulation.
  const cands = [
    ['POST', '/v1/auth/signup', { displayName: 'x', email: 'x@olive-sim.invalid' }, 'G1', 'No server sign-up: nothing creates an account (app_user) through the API'],
    ['POST', '/v1/families', { name: 'x' }, 'G2', 'No family-creation route: a family/household cannot be created through the API'],
    ['POST', '/v1/children', { displayName: 'x', birthDate: '2020-01-01' }, 'G3', 'No child-creation route: a child row cannot be created through the API'],
  ];
  const tok = st(ctx, fam).g[0]?.token;
  for (const [m, p, b, id, title] of cands) {
    const r = await ctx.client.call(m, p, { token: tok, body: b, fam: fam.n });
    if (r.status === 404 || r.status === 405) addGap(ctx, id, title, [`${m} ${p}`], `${m} ${p} -> ${r.status} ${JSON.stringify(r.body)}`);
    else ctx.notes.push(`unexpected: ${m} ${p} -> ${r.status}`);
  }
  const coview = await ctx.client.call('POST', `/v1/children/${fam.kids[0].id}/co-view`, { token: tok, body: {}, fam: fam.n });
  if (coview.status === 404) addGap(ctx, 'G9', 'No co-viewing (read/watch-together) server route: only the sealed relay (game-tables) exists, so co-view session setup/authorisation cannot be driven',
    ['POST /v1/children/:childId/co-view', 'POST /v1/co-view'], `POST /v1/children/:childId/co-view -> ${coview.status}`);
  const restore = await ctx.client.call('POST', '/v1/me/restore', { token: tok, body: {}, fam: fam.n });
  if (restore.status === 404) addGap(ctx, 'G8', 'Deletion has no recovery route: the 6-12 month recovery window has no server API (restore/undelete)',
    ['POST /v1/me/restore'], `POST /v1/me/restore -> ${restore.status}`);
  const med = await ctx.client.call('POST', `/v1/children/${fam.kids[0].id}/medications`, { token: tok, body: { name: 'x', dose: '1', slots: ['am'] }, fam: fam.n });
  if (med.status === 404) addGap(ctx, 'G6', 'No route creates a medication (or an exchange bag item): only list, dose-log and bag-status exist, so these were seeded by SQL',
    ['POST /v1/children/:childId/medications', 'POST /v1/children/:childId/exchange/bag-items'], `POST /v1/children/:childId/medications -> ${med.status}`);
}

export async function onboard(ctx, fam) {
  const s = st(ctx, fam);
  s.health = 'run';
  // guardians: sign in (dev-login: the only way to get a session without a ceremony), set PIN, read /me
  for (const g of fam.guardians) {
    const t0 = Date.now();
    const token = await ctx.client.login({ userId: g.id });
    ctx.rec.emit('step', { fam: fam.n, id: 'O1', title: `Sign in ${g.name} (dev-login)`, route: 'POST /v1/auth/dev-login',
      status: token ? 200 : 0, ms: Date.now() - t0, ok: !!token });
    s.steps++; token ? s.ok++ : s.bad++;
    s.g.push({ ...g, token });
    if (!token) { ctx.fails.push({ fam: fam.n, id: 'O1', title: 'dev-login', route: 'POST /v1/auth/dev-login' }); continue; }
    await S(ctx, fam, 'O2', `${g.name} sets a control PIN`, 'POST', '/v1/me/pin', { token, body: { pin: g.pin } }, { expect: [200] });
    await S(ctx, fam, 'O3', `${g.name} reads /me`, 'GET', '/v1/me', { token });
  }
  const g1 = s.g[0];
  // child devices: dev-login only supplies a fallback token; the REAL route is pairing
  for (const k of fam.kids) {
    const code = await S(ctx, fam, 'P1', `Pairing code for ${k.name} (${k.band})`, 'POST', `/v1/children/${k.id}/device-pairing-codes`,
      { token: g1.token, body: { pin: g1.pin } }, { expect: [201] });
    let tok = null;
    if (code.ok) {
      const red = await S(ctx, fam, 'P2', `${k.name}'s tablet redeems the code`, 'POST', '/v1/device-pairing/redeem',
        { body: { code: code.body.numericCode, role: 'child' } }, { expect: [201] });
      if (red.ok) {
        tok = red.body.sessionToken;
        s.devices.push({ childId: k.id, deviceId: red.body.deviceId, deviceCredential: red.body.deviceCredential, code: code.body.numericCode, codeId: code.body.id });
        await S(ctx, fam, 'P3', `${k.name}'s device refreshes its session`, 'POST', '/v1/auth/session/refresh',
          { body: { deviceId: red.body.deviceId, deviceCredential: red.body.deviceCredential } }, { expect: [200] });
        // a second redeem of the same code must be refused (single use)
        await S(ctx, fam, 'P4', 'Same code redeemed twice is refused', 'POST', '/v1/device-pairing/redeem',
          { body: { code: code.body.numericCode, role: 'child' } }, { expect: [409, 404, 410] });
      }
    }
    if (!tok) tok = await ctx.client.login({ childId: k.id });
    s.kids.push(k); s.kidTok.push(tok);
  }
  // sitter / helper invite: invite -> read -> accept -> bootstrap. Then discover the missing edge.
  if (fam.sitter) await sitterInvite(ctx, fam);
  s.health = 'ok';
}

async function sitterInvite(ctx, fam) {
  const s = st(ctx, fam), g1 = s.g[0], k = fam.kids[0];
  const inv = await S(ctx, fam, 'I1', `Invite ${fam.sitter} as sitter`, 'POST', `/v1/children/${k.id}/guardianships`,
    { token: g1.token, body: { role: 'sitter', label: fam.sitter, invitedEmail: fam.sitterEmail, pin: g1.pin } }, { expect: [201] });
  if (!inv.ok) return;
  const id = inv.body.invite.id;
  s.sitterInviteId = id;
  await S(ctx, fam, 'I2', 'Sitter opens the invite (no session)', 'GET', `/v1/guardian-invites/${id}`, {}, { expect: [200] });
  await S(ctx, fam, 'I3', 'Sitter accepts', 'POST', `/v1/guardian-invites/${id}/accept`, { body: {} }, { expect: [200] });
  const boot = await S(ctx, fam, 'I4', 'Sitter account bootstrapped', 'POST', `/v1/guardian-invites/${id}/bootstrap`,
    { body: { displayName: fam.sitter } }, { expect: [201] });
  if (!boot.ok) return;
  s.sitter = { userId: boot.body.userId, token: boot.body.token };
  // What can the brand-new sitter do now? A real sitter would read the child's now/handover.
  const r = await ctx.client.call('GET', `/v1/children/${k.id}/handover-notes`, { token: boot.body.token, fam: fam.n });
  ctx.rec.emit('step', { fam: fam.n, id: 'I5', title: 'Sitter reads the handover notes', route: 'GET /v1/children/:id/handover-notes', status: r.status, ms: Math.round(r.ms), ok: r.status === 200 });
  if (r.status !== 200) {
    addGap(ctx, 'G4', 'Accepting a guardian invite never creates the guardianship edge: the invited sitter gets an account and a session but zero access, and no route finishes the job',
      ['POST /v1/guardian-invites/:inviteId/accept', 'POST /v1/guardian-invites/:inviteId/bootstrap'],
      `after accept+bootstrap, sitter GET /v1/children/:childId/handover-notes -> ${r.status} ${JSON.stringify(r.body)}`);
    s.steps++; s.bad++;
  } else { s.steps++; s.ok++; }
}

// ---------------------------------------------------------------------------
// THE DAY (compressed onto real time, see seed.dayPlan)
// ---------------------------------------------------------------------------
export async function sendMessage(ctx, fam, fromChild, kid, { daypart = 'bedtime' } = {}) {
  const s = st(ctx, fam), idx = fam.kids.indexOf(kid);
  const token = fromChild ? s.kidTok[idx] : s.g[0].token;
  const up = await S(ctx, fam, 'M1', `${fromChild ? kid.name : s.g[0].name} records a video note`, 'POST', `/v1/children/${kid.id}/media`,
    { token, body: { bytes: tinyMp4().toString('base64') } }, { expect: [201] });
  if (!up.ok) return null;
  const msg = await S(ctx, fam, 'M2', `Bank the message for ${daypart}`, 'POST', `/v1/children/${kid.id}/messages`,
    { token, body: { storageKey: up.body.storageKey, durationMs: 4200, daypart } }, { expect: [201] });
  if (!msg.ok) return null;
  s.artifacts[kid.id] = { intentId: msg.body.id, artifactId: msg.body.artifactId, storageKey: up.body.storageKey };
  return msg.body;
}

export async function dayFlow(ctx, fam) {
  const s = st(ctx, fam), g1 = s.g[0], g2 = s.g[1] ?? null;
  const kid = fam.kids[0], kidTok = s.kidTok[0];
  const pace = (label) => vclock(ctx, label);

  await untilVirtual(ctx, 15.05); pace(fmtVirtual(15.1));
  // the child's first look at the world, and the guardian's
  for (let i = 0; i < fam.kids.length; i++) {
    const k = fam.kids[i];
    await S(ctx, fam, 'D1', `${k.name} (${k.band}) opens Now`, 'GET', `/v1/children/${k.id}/now`, { token: s.kidTok[i] });
    await S(ctx, fam, 'D2', `${k.name}'s inbox (empty)`, 'GET', `/v1/children/${k.id}/inbox`, { token: s.kidTok[i] });
  }
  await S(ctx, fam, 'D3', 'Guardian ribbon (live day-parts)', 'GET', `/v1/children/${kid.id}/ribbon`, { token: g1.token });
  await S(ctx, fam, 'D4', 'Presence / on-duty', 'GET', `/v1/children/${kid.id}/presence`, { token: g1.token });
  await S(ctx, fam, 'D5', 'Availability windows', 'GET', `/v1/children/${kid.id}/availability`, { token: g1.token });

  await untilVirtual(ctx, 15.5); pace('15:30');
  // message: guardian banks one for bedtime; the child banks one back
  await sendMessage(ctx, fam, false, kid);
  await sendMessage(ctx, fam, true, kid);
  await S(ctx, fam, 'D6', 'Guardian sets theme', 'PUT', `/v1/children/${kid.id}/theme`,
    { token: g1.token, body: { themePalette: ['olive', 'calmModern', 'warmGrounded', 'softPlayful'][fam.n % 4], themeBrightness: fam.n % 2 ? 'dark' : 'light' } }, { expect: [200, 204] });
  await S(ctx, fam, 'D7', 'Child profile', 'PUT', `/v1/children/${kid.id}/profile`, { token: kidTok, body: { gender: fam.n % 2 ? 'girl' : 'boy' } }, { expect: [200, 204] });
  await S(ctx, fam, 'D8', 'Game favourites (child)', 'PUT', `/v1/children/${kid.id}/game-favorites`, { token: g1.token, body: { favoriteKinds: ['checkers', 'hangman'] } }, { expect: [200, 204] });
  await S(ctx, fam, 'D9', 'Hide an activity (play settings)', 'PUT', `/v1/children/${kid.id}/activity-overrides/uno`, { token: g1.token, body: { visible: fam.n % 3 !== 0 } }, { expect: [200, 204] });
  await S(ctx, fam, 'D10', 'Own availability windows', 'PUT', '/v1/me/availability', { token: g1.token, body: [{ weekday: 1, startLocal: '17:00', endLocal: '19:00', note: 'home from work' }] }, { expect: [200, 204] });
  await S(ctx, fam, 'D12', 'Parent Learn settings', 'PUT', '/v1/learn/settings', { token: g1.token, body: { framing: 'neutral', rulesList: true } }, { expect: [200, 204] });
  await S(ctx, fam, 'D11', 'House rules', 'PUT', `/v1/children/${kid.id}/learn/house-rules`, { token: g1.token, body: { rules: [{ category: 'screens', text: 'Tablets rest at dinner' }] } }, { expect: [200, 204] });

  await untilVirtual(ctx, 16.5); pace('16:30');
  // calls: authorisation and setup only. No media flows in this stack.
  const call = await S(ctx, fam, 'C1', 'Guardian starts a call (token mint, no media)', 'POST', `/v1/children/${kid.id}/calls`, { token: g1.token, body: {} }, { expect: [200, 201] });
  if (call.ok && call.body?.sessionId) {
    await S(ctx, fam, 'C2', `${kid.name} joins the call (authorised)`, 'POST', `/v1/children/${kid.id}/calls/${call.body.sessionId}/join`, { token: kidTok, body: {} }, { expect: [200, 201] });
    if (st(ctx, fam).bad && ctx.fails.at(-1)?.body?.error === 'bad_path') addGap(ctx, 'G7', 'DEFECT: POST /calls mints a sessionId as 32 hex chars with no dashes, but the :sessionId join/end routes (strictIds) refuse anything that is not a dashed uuid (400 bad_path): a started call can never be joined or ended through the API',
      ['POST /v1/children/:childId/calls', 'POST /v1/children/:childId/calls/:sessionId/join', 'POST /v1/children/:childId/calls/:sessionId/end'], `sessionId ${call.body.sessionId} -> 400 bad_path`);
    await S(ctx, fam, 'C3', 'Call ended', 'POST', `/v1/children/${kid.id}/calls/${call.body.sessionId}/end`, { token: g1.token, body: {} }, { expect: [200] });
  }

  await untilVirtual(ctx, 17.0); pace('17:00');
  // money, medicine, notes, the bag
  const exp = await S(ctx, fam, 'E1', 'Log a shared expense', 'POST', `/v1/children/${kid.id}/expenses`,
    { token: g1.token, body: { description: 'Soccer cleats', amountCents: 4500 + fam.n * 100, category: 'activity', incurredOn: new Date().toISOString().slice(0, 10), payerSharePercent: 50 } }, { expect: [201, 200] });
  await S(ctx, fam, 'E2', 'List expenses', 'GET', `/v1/children/${kid.id}/expenses`, { token: (g2 ?? g1).token });
  if (g2 && exp.ok && exp.body?.id) await S(ctx, fam, 'E3', 'Co-guardian accepts the expense', 'POST', `/v1/children/${kid.id}/expenses/${exp.body.id}/accept`, { token: g2.token, body: {} }, { expect: [200, 201] });
  await S(ctx, fam, 'N1', 'List medications', 'GET', `/v1/children/${kid.id}/medications`, { token: g1.token });
  await S(ctx, fam, 'N2', 'Log a dose', 'POST', `/v1/children/${kid.id}/medications/${fam.medicationId}/doses`, { token: g1.token, body: { slot: 'am' } }, { expect: [201, 200] });
  if (g2) await S(ctx, fam, 'N3', 'Double dose is refused (409)', 'POST', `/v1/children/${kid.id}/medications/${fam.medicationId}/doses`, { token: g2.token, body: { slot: 'am' } }, { expect: [409] });
  await S(ctx, fam, 'N4', 'Emergency card read', 'GET', `/v1/children/${kid.id}/emergency-card`, { token: g1.token });
  await S(ctx, fam, 'N5', 'Care note (tone guarded)', 'POST', `/v1/children/${kid.id}/care-notes`, { token: g1.token, body: { items: [{ kind: 'sleep', note: 'slept through the night' }] } }, { expect: [201, 200] });
  await S(ctx, fam, 'N6', 'Handover note', 'POST', `/v1/children/${kid.id}/handover-notes`, { token: g1.token, body: { body: 'Bag is by the door.' } }, { expect: [201, 200] });
  await S(ctx, fam, 'N7', 'Bag item marked sent', 'POST', `/v1/children/${kid.id}/exchange/bag-items/${fam.bagItemId}`, { token: g1.token, body: { sent: true } }, { expect: [200] });
  if (fam.custody) {
    await S(ctx, fam, 'X1', 'Custody order read', 'GET', `/v1/children/${kid.id}/custody-order`, { token: g1.token });
    await S(ctx, fam, 'X2', 'Running late (15 min)', 'POST', `/v1/children/${kid.id}/exchange/running-late`, { token: g1.token, body: { etaMinutes: 15 } }, { expect: [201, 200] });
    await S(ctx, fam, 'X3', 'Exchange arrival', 'POST', `/v1/children/${kid.id}/exchange/arrival`, { token: g1.token, body: {} }, { expect: [201, 200, 409] });
  }
  await S(ctx, fam, 'L1', `${kid.name} seals a letter for later`, 'POST', `/v1/children/${kid.id}/letters`, { token: kidTok, body: { body: 'Hello future me.', openAtAge: kid.age + 5 } }, { expect: [201, 200] });
  await S(ctx, fam, 'L2', 'Letters listed', 'GET', `/v1/children/${kid.id}/letters`, { token: kidTok });

  // bedtime: the harness delivery worker has made the messages deliverable
  await untilVirtual(ctx, 20.6); pace('20:36');
  for (let i = 0; i < 12 && ctx.worker; i++) { await ctx.worker.tick(); const r = await ctx.client.call('GET', `/v1/children/${kid.id}/inbox`, { token: kidTok, fam: fam.n }); if (r.body?.entries?.length) break; await sleep(500); }
  const inbox = await S(ctx, fam, 'R1', `${kid.name} opens the inbox after bedtime starts`, 'GET', `/v1/children/${kid.id}/inbox`, { token: kidTok });
  const first = inbox.body?.entries?.[0];
  if (!first) {
    s.bad++; ctx.fails.push({ fam: fam.n, id: 'R1', title: 'message delivered to the child', route: 'GET /v1/children/:childId/inbox', status: inbox.status, body: inbox.body });
  } else {
    await S(ctx, fam, 'R2', 'Child opens the message', 'POST', `/v1/children/${kid.id}/inbox/${first.id}/opened`, { token: kidTok, body: {} }, { expect: [200, 201] });
    const art = s.artifacts[kid.id];
    if (art?.artifactId) {
      const media = await S(ctx, fam, 'R3', 'Message media fetched (signed URL minted)', 'GET', `/v1/children/${kid.id}/messages/${art.artifactId}/media`, { token: kidTok });
      if (media.ok) art.signedUrl = media.body.signedUrl;
    }
  }
  await S(ctx, fam, 'R4', 'Security events feed', 'GET', `/v1/children/${kid.id}/security-events`, { token: g1.token });
}

/** Last steps of a family's day: export, device revoke, deletion. */
export async function wrapUp(ctx, fam) {
  const s = st(ctx, fam), g1 = s.g[0], g2 = s.g[1] ?? null, kid = fam.kids[0];
  await untilVirtual(ctx, 21.2); vclock(ctx, '21:12');
  await S(ctx, fam, 'Z1', 'Certified export (PIN step-up)', 'GET', `/v1/children/${kid.id}/export?kind=certified`, { token: g1.token, headers: { 'x-guardian-pin': g1.pin } });
  await S(ctx, fam, 'Z2', 'Raw export (PIN step-up)', 'GET', `/v1/children/${kid.id}/export`, { token: g1.token, headers: { 'x-guardian-pin': g1.pin } });
  const dev = s.devices[0];
  if (dev) {
    await S(ctx, fam, 'Z3', 'Revoke the child device', 'POST', `/v1/children/${dev.childId}/paired-devices/${dev.deviceId}/revoke`, { token: g1.token, body: { pin: g1.pin } }, { expect: [200, 204] });
    await S(ctx, fam, 'Z4', 'Revoked device can no longer refresh', 'POST', '/v1/auth/session/refresh', { body: { deviceId: dev.deviceId, deviceCredential: dev.deviceCredential } }, { expect: [401] });
  }
  // account deletion: only a co-guardian is deleted (a single guardian would end the family's simulation)
  if (g2 && fam.n % 3 === 1) {
    const del = await S(ctx, fam, 'Z5', `${g2.name} deletes their account`, 'POST', '/v1/me/delete', { token: g2.token, body: {} }, { expect: [200] });
    if (del.ok) {
      const again = await ctx.client.login({ userId: g2.id });
      ctx.rec.emit('step', { fam: fam.n, id: 'Z6', title: 'Deleted guardian cannot sign in', route: 'POST /v1/auth/dev-login', status: again ? 200 : 403, ok: !again });
      s.steps++; again ? s.bad++ : s.ok++;
    }
  }
  s.health = s.bad ? 'warn' : 'ok'; s.step = 'day complete';
}
