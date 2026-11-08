/* Olive Branch developer portal (mockup). No network calls anywhere in this file:
   data comes from routes.js (generated) and content.js (authored). */
(() => {
  'use strict';
  const P = window.PORTAL_DATA, C = window.PORTAL_CONTENT;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const el = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const safe = (fn) => { try { return fn(); } catch (e) { return null; } };
  const plural = (n, a, b) => `${n} ${n === 1 ? a : b}`;

  /* ============================================================ data prep */
  const wsRoute = {
    id: 'ws-v1-game-tables-socket', method: 'WS', path: '/v1/game-tables/:tableId/socket', area: 'Game tables', action: null,
    raw: true, ws: true, noSessionRequired: true, skipOuterSession: true, identityScopedByHandler: false, skipChildPayloadSweep: false, escalated: false,
    source: 'server/game_tables.mjs', lead: 'WebSocket upgrade on the same http.Server and port. The short-lived table token in ?token= is verified before the handshake completes; any failure destroys the socket at TCP level. See Realtime.',
    headNote: '', callers: ['the two participants, each holding a single-use table token from POST /v1/game-tables or .../join'], guards: [],
    errors: [], success: [101], shapes: [], bodyKeys: [], queryKeys: ['token'], tests: ['server/test/game_tables.test.mjs', 'packages/game-sync/test/table.test.mjs'], client: 'gameTables', badge: 'built',
    auth: { gate: 'table token', roles: [], child: true },
  };
  const proposed = C.proposedRoutes.map((p) => ({
    ...p, id: `proposed-${p.method.toLowerCase()}-${p.path.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase()}`,
    badge: 'proposed', lead: p.why, headNote: '', guards: [], tests: [], client: null, queryKeys: p.queryKeys || [],
    identityScopedByHandler: false, skipOuterSession: false, noSessionRequired: false, skipChildPayloadSweep: false, escalated: false,
    auth: { gate: p.action ? 'can(action)' : 'identity', roles: [], child: false },
  }));
  const built = [...P.routes, wsRoute];
  const ALL = [...built, ...proposed];
  const byId = new Map(ALL.map((r) => [r.id, r]));
  const ADULT_ROLES = P.authorize.roles;
  const AREAS = ['Auth and devices', 'Identity and time', 'Invites', 'Messages and media', 'Coordination', 'Calls', 'Game tables', 'Settings and preferences', 'Parent Learn', 'Archive and account', 'Operations', 'Other'];
  const tables = P.tables;
  const tmap = new Map(tables.map((t) => [t.name, t]));

  /** Which caller kinds can reach this route (derived, see the generator). */
  function whoSet(r) {
    const s = new Set();
    if (r.badge === 'proposed') return s;
    if (r.noSessionRequired) s.add('public');
    const g = (k) => r.guards.some((x) => x.kind === k);
    if (r.noSessionRequired && !r.ws) return s;
    if (r.action) {
      if (g('guardian_only')) { s.add('guardian'); return s; }
      r.auth.roles.forEach((x) => s.add(x));
      if (r.auth.child && !g('child_denied')) s.add('child');
      return s;
    }
    if (g('own_child_only') && !g('live_guardian_edge')) { s.add('child'); return s; }
    if (g('live_guardian_edge') || g('guardian_only')) { s.add('guardian'); return s; }
    ADULT_ROLES.forEach((x) => s.add(x));
    if (!g('child_denied')) s.add('child');
    return s;
  }
  ALL.forEach((r) => { r._who = whoSet(r); });

  /* ================================================================ utils */
  let toastT;
  function toast(msg) { const t = $('#toast'); t.textContent = msg; t.classList.add('on'); clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('on'), 1400); }
  async function copyText(text) {
    try { await navigator.clipboard.writeText(text); }
    catch (e) { const ta = document.createElement('textarea'); ta.value = text; ta.style.cssText = 'position:fixed;opacity:0'; document.body.appendChild(ta); ta.select(); try { document.execCommand('copy'); } catch (e2) { /* ignore */ } ta.remove(); }
    toast('Copied');
  }
  const RULES = {
    json: [[/\/\/.*$/, 'tc'], [/"(?:\\.|[^"\\])*"(?=\s*:)/, 'tk'], [/"(?:\\.|[^"\\])*"/, 'ts'], [/\b-?\d+(?:\.\d+)?\b/, 'tn'], [/\b(?:true|false|null)\b/, 'tw']],
    js: [[/\/\/.*$/, 'tc'], [/\/\*[\s\S]*?\*\//, 'tc'], [/`(?:\\.|[^`\\])*`/, 'ts'], [/'(?:\\.|[^'\\])*'/, 'ts'], [/"(?:\\.|[^"\\])*"/, 'ts'], [/\b(?:const|let|await|async|if|return|new|function|typeof)\b/, 'tw'], [/\b\d+(?:\.\d+)?\b/, 'tn']],
    bash: [[/#.*$/, 'tc'], [/'[^']*'/, 'ts'], [/"(?:\\.|[^"\\])*"/, 'ts'], [/\$\{?[A-Za-z_]\w*\}?/, 'tv'], [/(?<=\s)-{1,2}[A-Za-z][\w-]*/, 'tw'], [/\b(?:curl|docker|compose|npm|node|bash|cp|openssl|cd|psql|pg_dump|jq|grep|adb)\b/, 'tw']],
    http: [[/#.*$/, 'tc'], [/^(?:GET|POST|PUT|PATCH|DELETE|HTTP\/1\.1)\b/m, 'tw'], [/^[A-Za-z][\w-]*(?=:)/m, 'tk'], [/\b\d{3}\b/, 'tn']],
    sql: [[/--.*$/, 'tc'], [/'[^']*'/, 'ts'], [/\b(?:SELECT|FROM|WHERE|CREATE|TABLE|ALTER|ENABLE|FORCE|ROW|LEVEL|SECURITY|POLICY|ON|FOR|USING|INSERT|INTO|VALUES|UPDATE|DELETE|AND|OR|NOT|NULL|REFERENCES|PRIMARY|KEY)\b/, 'tw']],
    text: [],
  };
  const combo = {};
  function hl(code, lang) {
    const rules = RULES[lang] || [];
    if (!rules.length) return esc(code);
    const re = combo[lang] || (combo[lang] = new RegExp(rules.map((r) => `(${r[0].source})`).join('|'), 'gm'));
    re.lastIndex = 0;
    let out = '', last = 0, m;
    while ((m = re.exec(code))) {
      if (m[0] === '') { re.lastIndex++; continue; }
      const gi = m.findIndex((x, i) => i > 0 && x !== undefined);
      out += esc(code.slice(last, m.index)) + `<span class="${rules[gi - 1][1]}">${esc(m[0])}</span>`;
      last = m.index + m[0].length;
    }
    return out + esc(code.slice(last));
  }
  function codeEl(text, lang, title) {
    const w = el(`<div class="code"><div class="bar"><span></span><button type="button" class="copy" aria-label="Copy code">Copy</button></div><pre tabindex="0"><code></code></pre></div>`);
    $('.bar span', w).textContent = title || lang || 'code';
    $('code', w).innerHTML = hl(text, lang);
    const b = $('.copy', w);
    b.addEventListener('click', async () => { await copyText(text); b.textContent = 'Copied'; b.classList.add('done'); setTimeout(() => { b.textContent = 'Copy'; b.classList.remove('done'); }, 1400); });
    return w;
  }
  function hydrateCode(root) {
    $$('[data-code]', root).forEach((n) => { n.replaceWith(codeEl(n.textContent.replace(/^\n/, ''), n.dataset.code, n.dataset.title)); });
  }
  function initTabs(root) {
    $$('[data-tabs]', root).forEach((box, bi) => {
      if (box.dataset.ready) return; box.dataset.ready = '1';
      const tabs = $$('[role="tab"]', box), panels = $$(':scope > [role="tabpanel"]', box);
      tabs.forEach((t, i) => { t.id = t.id || `tab-${bi}-${i}-${Math.random().toString(36).slice(2, 6)}`; t.setAttribute('aria-controls', panels[i].id = panels[i].id || `${t.id}-p`); panels[i].setAttribute('aria-labelledby', t.id); });
      const sel = (i, focus) => { tabs.forEach((t, j) => { t.setAttribute('aria-selected', j === i); t.tabIndex = j === i ? 0 : -1; panels[j].hidden = j !== i; }); if (focus) tabs[i].focus(); };
      tabs.forEach((t, i) => {
        t.addEventListener('click', () => sel(i));
        t.addEventListener('keydown', (e) => {
          const k = e.key; let n = null;
          if (k === 'ArrowRight') n = (i + 1) % tabs.length; else if (k === 'ArrowLeft') n = (i - 1 + tabs.length) % tabs.length; else if (k === 'Home') n = 0; else if (k === 'End') n = tabs.length - 1;
          if (n !== null) { e.preventDefault(); sel(n, true); }
        });
      });
      sel(Math.max(0, tabs.findIndex((t) => t.getAttribute('aria-selected') === 'true')));
    });
  }
  const sCls = (s) => (s >= 500 ? 's5' : s >= 400 ? 's4' : 's2');
  const prettyPath = (p) => esc(p).replace(/:(\w+)/g, '<span class="pp">:$1</span>');
  const hash6 = (s) => { let h = 2166136261; for (const c of s) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return (h >>> 0).toString(16).padStart(8, '0'); };
  const fmtDur = (ms) => (ms % 3600000 === 0 ? ms / 3600000 + ' h' : ms % 60000 === 0 ? ms / 60000 + ' min' : ms / 1000 + ' s');
  const fmtBytes = (b) => (b >= 1048576 ? b / 1048576 + ' MiB' : b >= 1024 ? b / 1024 + ' KiB' : b + ' B');

  /* ============================================================== samples */
  const KEY_SAMPLES = {
    pin: '4821', currentPin: '4821', code: '483920', role: 'child', deviceId: '7c1f0a52-3b8e-4a0c-9d11-0b2f3c4d5e6f', deviceCredential: '<deviceCredential>',
    userId: C.DAD, childId: C.IVY, displayName: 'Dad', invitedEmail: 'sam@example.com', label: 'Grandma', amountCents: 4250, category: 'school',
    description: 'School trip', incurredOn: '2026-11-02', payerSharePercent: 50, receiptKey: null, game: 'checkers', partnerChildId: '<siblingChildId>', partnerUserId: C.MOM,
    ifMatch: 3, bloodType: 'O+', allergies: ['penicillin'], conditions: [], pediatricianName: 'Dr. Rao', pediatricianPhone: '+1 555 0100', pediatricianPractice: 'Elm Street Pediatrics',
    insuranceProvider: 'Acme Health', insuranceMemberId: 'ACM-0001', storageKey: 'media/ivy/2026-11-08/clip-01.mp4', durationMs: 42000, daypart: 'evening', preserve: false,
    targetLocalDate: '2026-11-09', captionKey: null, batchId: null, batchSeq: null, themePalette: 'olive', themeBrightness: 'light', body: 'Dropped the blue jacket in the bag.',
    token: '<fcm-registration-token>', platform: 'android', channel: 'push', themeKey: 'olive', continues: false, status: 'packed', minutes: 15, note: 'Skipped her nap.',
    kind: 'certified', windows: [{ dow: 1, start: '17:00', end: '19:00' }], enabled: true, text: 'Dear Ivy...', openOn: '2026-12-25', dose: '5 ml', takenAt: '2026-11-08T13:00:00.000Z',
    pattern: { kind: 'weekly' }, validFrom: '2026-11-15', name: 'Amoxicillin', schedule: 'twice daily', items: [], since: 'cursor', limit: 50,
  };
  const sampleFor = (k) => (k in KEY_SAMPLES ? KEY_SAMPLES[k] : /Ms$|Cents$|Percent$|Seq$|Count$/.test(k) ? 1 : /^(is|has|enabled)[A-Z]/.test(k) ? true : `<${k}>`);
  function sampleBody(r) {
    if (!r.bodyKeys.length || !['POST', 'PUT', 'PATCH', 'DELETE'].includes(r.method)) return null;
    const o = {}; r.bodyKeys.forEach((k) => { o[k] = sampleFor(k); }); return o;
  }
  const envName = (p) => '$' + p.replace(/([a-z])([A-Z])/g, '$1_$2').toUpperCase();
  function exPath(r, q) {
    let p = r.path.replace(/:(\w+)/g, (_, n) => envName(n));
    const qs = (r.queryKeys || []).filter((k) => k !== 'token');
    if (q && qs.length) p += '?' + qs.map((k) => `${k}=${k === 'kind' ? 'certified' : sampleFor(k)}`).join('&');
    return p;
  }
  function curlFor(r) {
    const body = sampleBody(r);
    const L = [`# OLIVE_BASE=http://127.0.0.1:8123   OLIVE_TOKEN=<SESSION_TOKEN>   (placeholders, not secrets)`];
    const open = r.method === 'GET' ? `curl -s "$OLIVE_BASE${exPath(r, true)}"` : `curl -s -X ${r.method} "$OLIVE_BASE${exPath(r, true)}"`;
    const parts = [open];
    if (!r.noSessionRequired) parts.push(`-H "authorization: Bearer $OLIVE_TOKEN"`);
    if (body) { parts.push(`-H "content-type: application/json"`); parts.push(`-d '${JSON.stringify(body)}'`); }
    L.push(parts.join(' \\\n  '));
    return L.join('\n');
  }
  function fetchFor(r) {
    const body = sampleBody(r);
    const path = r.path.replace(/:(\w+)/g, (_, n) => '${' + n + '}');
    const h = []; if (!r.noSessionRequired) h.push(`authorization: \`Bearer \${token}\``); if (body) h.push(`'content-type': 'application/json'`);
    return `const res = await fetch(\`\${BASE}${path}\`, {\n  method: '${r.method}',${h.length ? `\n  headers: { ${h.join(', ')} },` : ''}${body ? `\n  body: JSON.stringify(${JSON.stringify(body)}),` : ''}\n});\nconst requestId = res.headers.get('x-request-id');   // quote this in a bug report\nif (!res.ok) {\n  const { error } = await res.json();                  // snake_case code; branch on status + code\n  throw new ApiError(res.status, error, requestId);\n}\nconst data = await res.json();`;
  }

  /* ============================================================== router */
  const VIEWS = ['start', 'concepts', 'reference', 'try', 'data', 'realtime', 'jobs', 'security', 'changelog', 'runbooks', 'roadmap'];
  const TITLES = { start: 'Getting started', concepts: 'Concepts', reference: 'API reference', try: 'Try it (mock)', data: 'Data model', realtime: 'Realtime', jobs: 'Jobs and scheduler', security: 'Security model', changelog: 'Changelog and versioning', runbooks: 'Runbooks', roadmap: 'Roadmap' };
  const rendered = {};
  let current = null;
  function show(view, rest, user) {
    const v = VIEWS.includes(view) ? view : 'start';
    if (current !== v) {
      VIEWS.forEach((x) => { $('#v-' + x).hidden = x !== v; });
      $$('.side a').forEach((a) => { if (a.dataset.view === v) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current'); });
      document.title = `${TITLES[v]} - Olive Branch Developer Portal`;
      if (!rendered[v]) { rendered[v] = true; (renderers[v] || (() => {}))(); }
      current = v;
      window.scrollTo(0, 0);
      if (user) { const h = $(`#v-${v} h1`); if (h) { h.tabIndex = -1; h.focus({ preventScroll: true }); } }
    }
    closeSide();
    if (rest) handleRest(v, decodeURIComponent(rest));
  }
  function handleRest(v, rest) {
    if (v === 'reference') return openEp(rest, true);
    if (v === 'data') return selectTable(rest, true);
    if (v === 'try') return tryPick(rest);
    const t = document.getElementById(rest);
    if (t) t.scrollIntoView({ block: 'start' });
  }
  function route(user) { const raw = location.hash.slice(1) || 'start'; const i = raw.indexOf('/'); show(i < 0 ? raw : raw.slice(0, i), i < 0 ? '' : raw.slice(i + 1), user); }
  window.addEventListener('hashchange', () => route(true));

  /* sidebar */
  const side = $('#side'), scrim = $('#scrim'), menuBtn = $('#menuBtn');
  function closeSide() { side.dataset.open = 'false'; scrim.dataset.open = 'false'; menuBtn.setAttribute('aria-expanded', 'false'); }
  menuBtn.addEventListener('click', () => { const o = side.dataset.open !== 'true'; side.dataset.open = o; scrim.dataset.open = o; menuBtn.setAttribute('aria-expanded', o); if (o) $('a', side).focus(); });
  scrim.addEventListener('click', closeSide);

  /* theme */
  const themeBtn = $('#themeBtn');
  function effTheme() { const t = document.documentElement.getAttribute('data-theme'); return t || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'); }
  function syncThemeBtn() { const d = effTheme() === 'dark'; themeBtn.setAttribute('aria-pressed', d); themeBtn.setAttribute('aria-label', d ? 'Switch to light theme' : 'Switch to dark theme'); }
  themeBtn.addEventListener('click', () => { const n = effTheme() === 'dark' ? 'light' : 'dark'; document.documentElement.setAttribute('data-theme', n); safe(() => localStorage.setItem('ob-theme', n)); syncThemeBtn(); });
  matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', syncThemeBtn);
  syncThemeBtn();

  /* ============================================================== START */
  function renderStart() {
    const codes = Object.values(P.errorCatalog).reduce((a, b) => a + Object.keys(b).length, 0);
    const forced = tables.filter((t) => t.rlsForced).length;
    const stats = [
      [built.length, 'endpoints', `${built.length - 1} HTTP plus 1 WebSocket, parsed from source`],
      [tables.length, 'tables', `${forced} with FORCE row-level security`],
      [P.migrations.length, 'migrations', '0001 to 0038 (there is no 0019)'],
      [codes, 'distinct error codes', 'found in handlers and gate'],
      [P.bannedKeys.length, 'banned child-payload keys', 'checked on every child response'],
      [P.changelog.length, 'changelog entries', `latest ${P.specVersion}`],
    ];
    $('#statGrid').innerHTML = stats.map(([n, l, s]) => `<div class="card" role="group" aria-label="${esc(n + ' ' + l)}"><div class="stat">${n}</div><div class="lbl"><strong>${esc(l)}</strong><br>${esc(s)}</div></div>`).join('');
    // token inspector
    const b64u = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o)))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    const sample = () => `${b64u({ userId: C.DAD, roleName: 'guardian', childId: null, escalated: false, deviceId: '7c1f0a52-3b8e-4a0c-9d11-0b2f3c4d5e6f', exp: Date.now() + 3600000 })}.bW9jay1tYWMtbm90LXJlYWwtbm90LXNpZ25lZA`;
    const inp = $('#tokIn'), out = $('#tokOut');
    const decode = () => {
      const t = inp.value.trim(); if (!t) { out.innerHTML = ''; return; }
      const dot = t.lastIndexOf('.');
      try {
        if (dot < 1) throw new Error('A token has a "." between the payload and the MAC.');
        const pad = t.slice(0, dot).replace(/-/g, '+').replace(/_/g, '/');
        const json = decodeURIComponent(escape(atob(pad + '==='.slice((pad.length + 3) % 4))));
        const p = JSON.parse(json);
        const left = typeof p.exp === 'number' ? p.exp - Date.now() : null;
        const state = left === null ? '<span class="badge bad">no exp</span>' : left <= 0 ? '<span class="badge bad">expired</span>' : `<span class="badge built">valid for ${fmtDur(Math.round(left / 1000) * 1000)} more</span>`;
        out.innerHTML = `<div class="tablewrap" tabindex="0" role="region" aria-label="Decoded token"><table><tbody>${Object.entries(p).map(([k, v]) => `<tr><th scope="row">${esc(k)}</th><td class="mono">${esc(JSON.stringify(v))}${k === 'exp' && typeof v === 'number' ? ' <span style="color:var(--text-2)">(' + esc(new Date(v).toISOString()) + ')</span>' : ''}</td></tr>`).join('')}</tbody></table></div><p>${state} <span class="badge warn">MAC not verified here</span></p>`;
      } catch (e) { out.innerHTML = `<p><span class="badge bad">cannot decode</span> ${esc(e.message || 'not a session token')}</p>`; }
    };
    inp.addEventListener('input', decode);
    $('#tokSample').addEventListener('click', () => { inp.value = sample(); decode(); });
  }

  /* ========================================================== CONCEPTS */
  function renderConcepts() {
    // toc
    $('#conceptToc').innerHTML = $$('#v-concepts h2').map((h) => `<a class="tag" href="#concepts/${h.id}" style="text-decoration:none">${esc(h.firstChild.textContent.trim())}</a>`).join('');
    // role matrix
    const A = P.authorize, roles = A.roles;
    const head = `<thead><tr><th>Action</th>${roles.map((r) => `<th class="c">${esc(r.replace('_', ' '))}</th>`).join('')}<th class="c">child</th></tr></thead>`;
    const childYes = (a) => !(a.startsWith('expense.') || a === 'journal.read');
    const rows = A.actions.map((a) => {
      const w = A.writes.includes(a) ? ' <span class="badge info" title="Blocked for observer-only edges">write</span>' : A.contact.includes(a) ? ' <span class="badge info" title="Blocked at ladder step none">contact</span>' : '';
      return `<tr><td class="mono">${esc(a)}${w}</td>${roles.map((r) => `<td class="c">${A.roleCaps[r].includes(a) ? '<span class="yes" aria-label="yes">&#10003;</span>' : '<span class="no" aria-label="no">&ndash;</span>'}</td>`).join('')}<td class="c">${a === 'journal.read' || !childYes(a) ? '<span class="no" aria-label="never">never</span>' : a === 'letter' ? '<span class="yes" aria-label="only role">only</span>' : '<span class="yes" aria-label="own child, gate only">own</span>'}</td></tr>`;
    }).join('');
    $('#roleMatrix').innerHTML = head + `<tbody>${rows}</tbody>`;
    $('#denyTable').innerHTML = `<thead><tr><th>Deny reason</th><th>Meaning</th></tr></thead><tbody>${A.deny.map((d) => `<tr><td class="mono">${esc(d)}</td><td>${esc(C.deny[d] || '')}</td></tr>`).join('')}</tbody>`;
    // rls stats
    const forced = tables.filter((t) => t.rlsForced).length;
    $('#rlsStats').innerHTML = [[forced, 'tables with ENABLE + FORCE'], [tables.length - forced, 'tables with no RLS (see Data model)'], [tables.reduce((a, t) => a + t.policies.length, 0), 'policies'], [P.monitored.length, 'tables watched by health_check']].map(([n, l]) => `<div class="card"><div class="stat">${n}</div><div class="lbl">${esc(l)}</div></div>`).join('');
    // banned
    $('#bannedN').textContent = P.bannedKeys.length;
    $('#bannedList').innerHTML = P.bannedKeys.map((k) => `<span class="tag">${esc(k)}</span>`).join('');
    // errors
    const cat = P.errorCatalog;
    const gate = { 400: { bad_json: ['every route with a body'], bad_url: ['every route'], bad_path: ['malformed percent-escape'], child_scope_required: ['action route without :childId'] }, 401: { no_session: ['every authenticated route'], expired: [''], bad_signature: [''], malformed: [''], device_revoked: ['session carrying a deviceId'] }, 403: { wrong_child: ['child on another child\'s path'], escalation_required: ['route flagged escalated'] }, 404: { not_found: ['no route matches'] }, 413: { payload_too_large: ['body over the cap'] }, 429: { rate_limited: ['/v1/auth/*, game tables'] }, 500: { internal: ['unexpected exception'], child_payload_leak: ['banned key in a child response'] } };
    const merged = {};
    for (const [s, o] of Object.entries(gate)) for (const [c, r] of Object.entries(o)) ((merged[s] ??= {})[c] ??= []).push(...r.filter(Boolean).map((x) => '(gate) ' + x));
    for (const [s, o] of Object.entries(cat)) for (const [c, r] of Object.entries(o)) ((merged[s] ??= {})[c] ??= []).push(...r);
    $('#errorCatalog').innerHTML = Object.keys(merged).sort().map((s) => {
      const entries = Object.entries(merged[s]).sort();
      return `<details class="card" style="margin:8px 0"${+s === 403 ? ' open' : ''}><summary style="cursor:pointer;font-weight:600"><span class="status ${sCls(+s)}">${s}</span> &nbsp;${plural(entries.length, 'code', 'codes')}</summary><div class="chips" style="margin-top:10px">${entries.map(([c, r]) => `<span class="tag" title="${esc([...new Set(r)].slice(0, 6).join('; '))}">${esc(c)}</span>`).join('')}</div></details>`;
    }).join('') + '<p class="note-src">Hover a code to see where it comes from. Parsed from <code>status: N, body: { error: ... }</code> in the handlers plus the gate in <code>api.ts</code> and <code>index.mjs</code>.</p>';
    // limits
    const L = P.limits;
    const rows2 = [
      ['Session token lifetime', fmtDur(L.sessionTtlMs), 'auth.ts SESSION_TTL_MS'],
      ['Escalation lifetime (unused, see Security)', fmtDur(L.escalationTtlMs), 'auth.ts ESCALATION_TTL_MS'],
      ['Request body, verified session', fmtBytes(L.maxRequestBody), 'MAX_REQUEST_BODY_BYTES, overridable'],
      ['Request body, everyone else', fmtBytes(L.maxUnauthBody), 'MAX_UNAUTH_BODY_BYTES, overridable'],
      ['/v1/auth/* per client IP', `burst ${L.authRate.ipCapacity}, ${L.authRate.ipPerMin} per minute`, 'AUTH_RATE_IP_CAPACITY / _PER_MIN'],
      ['Login routes per userId or childId', `burst ${L.authRate.idCapacity}, ${L.authRate.idPerMin} per minute`, 'AUTH_RATE_ID_CAPACITY / _PER_MIN'],
      ['PIN attempts before lockout', `${L.pinMaxAttempts} wrong, then ${fmtDur(L.pinLockoutMs)}`, 'pool.ts PIN_MAX_ATTEMPTS'],
      ['Pairing code wrong-role attempts', `${L.deviceCodeMaxAttempts}, then locked for the code\'s life`, 'pool.ts DEVICE_CODE_MAX_ATTEMPTS'],
      ['WebAuthn challenge life', fmtDur(L.challengeTtlMs), 'single use'],
      ['Open or join a game table', `burst ${P.ws.httpRateCapacity}, then about 4 per minute`, 'game_tables.mjs'],
      ['Moves in a game', `burst ${P.ws.rateCapacity}, ${P.ws.rateRefillPerSecond} per second`, 'table.ts'],
    ];
    $('#limitsTable').innerHTML = `<thead><tr><th>Limit</th><th>Value</th><th>Where</th></tr></thead><tbody>${rows2.map(([a, b, c]) => `<tr><td>${esc(a)}</td><td class="mono">${esc(b)}</td><td class="mono" style="color:var(--text-2)">${esc(c)}</td></tr>`).join('')}</tbody>`;
    $('#v-concepts').querySelectorAll('[data-code]').length && hydrateCode($('#v-concepts'));
  }

  /* =========================================================== REFERENCE */
  const S = { q: '', area: '', role: '', status: '', methods: new Set(), noSession: false, noTest: false, noClient: false };
  let openId = null;
  function renderReference() {
    const used = AREAS.filter((a) => ALL.some((r) => r.area === a));
    $('#farea').innerHTML = '<option value="">All areas</option>' + used.map((a) => `<option>${esc(a)}</option>`).join('');
    const roles = [...ADULT_ROLES, 'child', 'public'];
    $('#frole').innerHTML = '<option value="">Any caller</option>' + roles.map((r) => `<option value="${r}">${r === 'public' ? 'No session (public)' : esc(r.replace('_', ' '))}</option>`).join('');
    const ms = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'WS'];
    $('#fmethods').innerHTML = ms.map((m) => `<button class="pill" aria-pressed="false" data-m="${m}">${m}</button>`).join('');
    $('#fq').addEventListener('input', (e) => { S.q = e.target.value.trim().toLowerCase(); drawList(); });
    $('#farea').addEventListener('change', (e) => { S.area = e.target.value; drawList(); });
    $('#frole').addEventListener('change', (e) => { S.role = e.target.value; drawList(); });
    $('#fstatus').addEventListener('change', (e) => { S.status = e.target.value; drawList(); });
    $('#fmethods').addEventListener('click', (e) => { const b = e.target.closest('button'); if (!b) return; const m = b.dataset.m; S.methods.has(m) ? S.methods.delete(m) : S.methods.add(m); b.setAttribute('aria-pressed', S.methods.has(m)); drawList(); });
    [['#fsession', 'noSession'], ['#fnotest', 'noTest'], ['#fnoclient', 'noClient']].forEach(([id, k]) => $(id).addEventListener('click', (e) => { S[k] = !S[k]; e.currentTarget.setAttribute('aria-pressed', S[k]); drawList(); }));
    $('#epList').addEventListener('click', (e) => {
      const b = e.target.closest('button.eph'); if (b) { toggleEp(b.closest('.ep').dataset.id); return; }
    });
    const dn = P.docs.documentedNotServed.length;
    $('#docsGap').innerHTML = `<strong class="t">Docs versus code</strong><p>MASTERFILE section 7 lists ${P.docs.documentedCount} routes in its code blocks. ${dn} of them are not served as written, and ${P.docs.servedNotDocumented.length} served routes are not in that listing. Many of the ${dn} were built under a different path (for example <code>/v1/auth/passkey/register</code> became <code>/v1/auth/webauthn/register/*</code>, and <code>POST /v1/ping</code> and <code>/v1/journal</code> were never routed, by design for the journal). The list comes from the generator's diff. The client declares five paths the server does not serve: ${P.clientOnly.map((c) => `<code>${esc(c.path)}</code>`).join(', ')}.</p>`;
    drawList();
  }
  function matches(r) {
    if (S.status && r.badge !== S.status) return false;
    if (S.area && r.area !== S.area) return false;
    if (S.methods.size && !S.methods.has(r.method)) return false;
    if (S.role) { if (r.badge === 'proposed') return false; if (!(r._who.has(S.role) || (S.role !== 'public' && r._who.has('public')))) return false; }
    if (S.noSession && !r.noSessionRequired) return false;
    if (S.noTest && (r.tests.length || r.badge === 'proposed')) return false;
    if (S.noClient && (r.client || r.badge === 'proposed')) return false;
    if (S.q) {
      const hay = `${r.method} ${r.path} ${r.action || ''} ${r.area} ${(r.errors || []).map((e) => e.status + ' ' + e.errors.join(' ')).join(' ')} ${r.lead || ''} ${(r.bodyKeys || []).join(' ')}`.toLowerCase();
      return S.q.split(/\s+/).every((t) => hay.includes(t));
    }
    return true;
  }
  function badgesFor(r) {
    const b = [];
    if (r.badge === 'proposed') b.push('<span class="badge proposed">proposed</span>'); else b.push('<span class="badge built">built</span>');
    if (r.dev) b.push('<span class="badge dev">dev only</span>');
    if (r.noSessionRequired && !r.dev && !r.ws) b.push('<span class="badge info">no session</span>');
    if (r.action) b.push(`<span class="tag">${esc(r.action)}</span>`); else if (r.badge === 'built' && !r.raw && !r.noSessionRequired) b.push('<span class="tag">identity</span>');
    return b.join('');
  }
  function drawList() {
    const list = $('#epList'); const f = ALL.filter(matches);
    $('#fcount').textContent = `${f.length} of ${ALL.length} endpoints`;
    if (!f.length) { list.innerHTML = '<div class="empty"><strong>No endpoints match.</strong><br>Clear a filter or search for an error code like <code>device_revoked</code>.</div>'; return; }
    const groups = new Map(); f.forEach((r) => { (groups.get(r.area) ?? groups.set(r.area, []).get(r.area)).push(r); });
    const order = [...groups.keys()].sort((a, b) => AREAS.indexOf(a) - AREAS.indexOf(b));
    list.innerHTML = order.map((a) => `<div class="area"><h3>${esc(a)}</h3><span>${groups.get(a).length}</span></div>` + groups.get(a).map((r) => `<div class="ep" id="ep-${r.id}" data-id="${r.id}" data-open="${r.id === openId}"><button type="button" class="eph" aria-expanded="${r.id === openId}" aria-controls="epb-${r.id}"><span class="m ${r.method}">${r.method}</span><span class="eppath">${prettyPath(r.path)}</span><span class="epmeta">${badgesFor(r)}</span></button><div class="epbody" id="epb-${r.id}" ${r.id === openId ? '' : 'hidden'}></div></div>`).join('')).join('');
    if (openId && byId.get(openId) && f.includes(byId.get(openId))) fillEp(openId);
  }
  function toggleEp(id) { if (openId === id) { openId = null; } else { openId = id; } drawList(); if (openId) { const e = document.getElementById('ep-' + id); e && $('button.eph', e).focus({ preventScroll: true }); history.replaceState(null, '', '#reference/' + id); } else history.replaceState(null, '', '#reference'); }
  function openEp(id, scroll) {
    const r = byId.get(id); if (!r) return;
    if (!matches(r)) { S.q = ''; S.area = ''; S.role = ''; S.status = ''; S.methods.clear(); S.noSession = S.noTest = S.noClient = false; $('#fq').value = ''; $('#farea').value = ''; $('#frole').value = ''; $('#fstatus').value = ''; $$('#fmethods .pill,#fsession,#fnotest,#fnoclient').forEach((b) => b.setAttribute('aria-pressed', 'false')); }
    openId = id; drawList();
    if (scroll) requestAnimationFrame(() => { const e = document.getElementById('ep-' + id); e && e.scrollIntoView({ block: 'start' }); });
  }
  function fillEp(id) {
    const r = byId.get(id); const body = $(`#epb-${id}`); if (!body || body.dataset.filled) return; body.dataset.filled = '1';
    const g = (k) => r.guards.find((x) => x.kind === k);
    const flags = [];
    if (r.noSessionRequired && !r.ws) flags.push('<span class="tag" title="Reachable with no session; the credential is in the path, body or signature">noSessionRequired</span>');
    if (r.identityScopedByHandler) flags.push('<span class="tag" title="action: null on a :childId path; the handler does its own identity check first">identityScopedByHandler</span>');
    if (r.skipOuterSession) flags.push('<span class="tag" title="Handler opens its own short sessions; holds no outer pooled connection (P-01)">skipOuterSession</span>');
    if (r.skipChildPayloadSweep) flags.push('<span class="tag" title="Exempt from the child-payload sweep: a deliberate full self-export">skipChildPayloadSweep</span>');
    if (r.escalated) flags.push('<span class="tag">escalated</span>');
    const params = [...r.path.matchAll(/:(\w+)/g)].map((m) => m[1]);
    const gateTxt = r.badge === 'proposed' ? 'Not built.' : r.noSessionRequired ? 'None. The credential is part of the request.' : r.action ? `<code>can('${esc(r.action)}', edges, :childId)</code> for adults; a child must own the path's childId, and expense.* is refused (P6).${r.guards.length ? ' The handler then narrows further (' + r.guards.map((x) => x.kind.replace(/_/g, ' ')).join(', ') + ').' : ''}` : `Identity only: the outer gate does not call <code>can()</code>.${r.guards.length ? ' The handler checks: ' + r.guards.map((x) => x.kind.replace(/_/g, ' ')).join(', ') + '.' : ' Scope comes from RLS and the principal.'}`;
    const lead = (r.lead && !/^Holds no outer pooled|^P-01\b/.test(r.lead)) ? r.lead : (r.headNote && !/^Holds no outer pooled|^P-01\b/.test(r.headNote) ? r.headNote : '');
    const short = lead.length > 560 ? lead.slice(0, 560).replace(/\s+\S*$/, '') + ' ...' : lead;
    const succ = (r.shapes || []);
    const respHtml = (succ.length ? succ.map((s) => `<div class="errrow"><span class="status ${sCls(s.status)}">${s.status}</span><div>${s.keys && s.keys.length ? `<div class="chips">${s.keys.map((k) => `<span class="tag">${esc(k)}</span>`).join('')}</div>` : s.helper ? `<span style="color:var(--text-2)">shape built by <code>${esc(s.helper)}()</code> in routes.mjs</span>` : '<span style="color:var(--text-2)">no body keys found</span>'}</div></div>`).join('') : (r.success || []).map((s) => `<div class="errrow"><span class="status ${sCls(s)}">${s}</span><div style="color:var(--text-2)">${r.method === 'GET' && r.path.includes('media') ? 'binary or JSON, see source' : 'body not statically determined'}</div></div>`).join(''));
    const errHtml = (r.errors || []).map((e) => `<div class="errrow"><span class="status ${sCls(e.status)}">${e.status}</span><div class="chips">${e.errors.map((c) => `<span class="tag">${esc(c)}</span>`).join('')}</div></div>`).join('');
    const gateErr = r.noSessionRequired ? '' : '<details style="margin-top:8px"><summary style="cursor:pointer;font-size:13px;color:var(--link)">Added by the gate on every authenticated route</summary><div class="chips" style="margin-top:8px"><span class="tag">401 no_session</span><span class="tag">401 expired | bad_signature | malformed</span><span class="tag">401 device_revoked</span>' + (r.action ? '<span class="tag">403 wrong_child</span><span class="tag">403 &lt;deny reason&gt;</span>' : '') + '<span class="tag">400 bad_json</span><span class="tag">413 payload_too_large</span><span class="tag">500 internal</span></div></details>';
    body.innerHTML = `
      ${short ? `<div class="note-src"><strong>From the source comment:</strong> ${esc(short)}</div>` : ''}
      <dl class="kv">
        <dt>Who may call</dt><dd>${r.badge === 'proposed' ? esc((r.callers || []).join('; ')) : r.callers.map((c) => esc(c)).join('<br>')}</dd>
        <dt>Authorization</dt><dd>${gateTxt}</dd>
        ${params.length ? `<dt>Path params</dt><dd class="chips">${params.map((p) => `<span class="tag">${esc(p)}</span>`).join('')}</dd>` : ''}
        ${r.queryKeys && r.queryKeys.length ? `<dt>Query</dt><dd class="chips">${r.queryKeys.map((p) => `<span class="tag">${esc(p)}</span>`).join('')}</dd>` : ''}
        ${r.bodyKeys && r.bodyKeys.length ? `<dt>Body keys</dt><dd class="chips">${r.bodyKeys.map((p) => `<span class="tag">${esc(p)}</span>`).join('')}</dd>` : ''}
        ${flags.length ? `<dt>Route flags</dt><dd class="chips">${flags.join('')}</dd>` : ''}
        ${r.source ? `<dt>Source</dt><dd class="mono">${esc(r.source)}</dd>` : ''}
        ${r.client ? `<dt>Client</dt><dd class="mono">api_client.dart: ${esc(r.client)}</dd>` : r.badge === 'built' ? '<dt>Client</dt><dd style="color:var(--text-2)">api_client.dart declares no constant for this path</dd>' : ''}
      </dl>
      ${r.badge === 'proposed' ? `<div class="callout proposed"><strong class="t">Proposed, not built</strong><p>Roadmap item <a href="#roadmap">${esc(r.ref)}</a>. The request and response below are a sketch of intent, not a contract.</p></div>` : ''}
      <h4>Responses</h4>${respHtml || '<p style="color:var(--text-2)">None recorded.</p>'}${errHtml}${gateErr}
      <h4>Example</h4><div class="tabs" data-tabs><div role="tablist" aria-label="Example language"><button role="tab" aria-selected="true">curl</button><button role="tab" aria-selected="false">fetch</button></div><div role="tabpanel" data-slot="curl"></div><div role="tabpanel" data-slot="fetch" hidden></div></div>
      ${r.badge === 'built' ? `<h4>Linked tests</h4>${r.tests.length ? `<div class="chips">${r.tests.map((t) => `<span class="tag">${esc(t)}</span>`).join('')}</div><p class="note-src" style="margin-top:8px">Test files whose text contains this path (a literal match, not a coverage claim).</p>` : '<p style="color:var(--text-2)">No test file mentions this path literally.</p>'}` : ''}
      <div class="frow" style="margin-top:14px"><a class="btn ghost" style="display:inline-flex;align-items:center;text-decoration:none" href="#try/${r.id}">Open in Try it (mock)</a><button class="pill" data-copylink="${r.id}">Copy link</button></div>`;
    $('[data-slot="curl"]', body).appendChild(codeEl(curlFor(r), 'bash', 'curl'));
    $('[data-slot="fetch"]', body).appendChild(codeEl(fetchFor(r), 'js', 'javascript'));
    initTabs(body);
    $('[data-copylink]', body).addEventListener('click', () => copyText(location.href.split('#')[0] + '#reference/' + r.id));
  }

  /* ============================================================ TRY IT */
  const WHO = {
    dad: { id: C.DAD, role: 'guardian', name: 'Dad' }, mom: { id: C.MOM, role: 'guardian', name: 'Mom' }, sitter: { id: 'bbbbbbbb-0000-4000-8000-000000000009', role: 'sitter', name: 'Sam' },
    stepparent: { id: 'bbbbbbbb-0000-4000-8000-000000000010', role: 'step_parent', name: 'Alex' }, ivy: { child: true, role: 'child', name: 'Ivy' }, 'ivy-other': { child: true, role: 'child', name: 'Ivy', other: true },
  };
  let tryReady = false;
  function renderTry() {
    $('#tEp').innerHTML = AREAS.map((a) => { const rs = built.filter((r) => r.area === a && !r.ws); return rs.length ? `<optgroup label="${esc(a)}">${rs.map((r) => `<option value="${r.id}">${r.method} ${esc(r.path)}</option>`).join('')}</optgroup>` : ''; }).join('');
    $('#tEp').addEventListener('change', () => tryLoad($('#tEp').value));
    $('#tSend').addEventListener('click', trySend);
    $('#tReset').addEventListener('click', () => tryLoad($('#tEp').value));
    $('#tWho').addEventListener('change', () => { tryParams(byId.get($('#tEp').value)); });
    tryReady = true;
    tryLoad(byId.has('get-v1-me') ? 'get-v1-me' : $('#tEp').value);
  }
  function tryPick(id) { if (!tryReady) return; const r = byId.get(id); if (!r || r.ws || r.badge === 'proposed') return; $('#tEp').value = id; tryLoad(id); }
  function tryParams(r) {
    const who = $('#tWho').value; const ps = [...r.path.matchAll(/:(\w+)/g)].map((m) => m[1]);
    $('#tParams').innerHTML = ps.map((p) => { const dflt = p === 'childId' ? (who === 'ivy-other' ? 'dddddddd-0000-4000-8000-0000000000ff' : C.IVY) : '00000000-0000-4000-8000-000000000001'; return `<label for="tp-${p}">:${esc(p)}</label><input class="input mono" id="tp-${p}" data-p="${p}" value="${esc(dflt)}">`; }).join('');
  }
  function tryLoad(id) {
    const r = byId.get(id); if (!r) return;
    tryParams(r);
    const b = sampleBody(r); $('#tBody').value = b ? JSON.stringify(b, null, 2) : ''; $('#tBody').disabled = !b && !['POST', 'PUT', 'PATCH'].includes(r.method);
    const opts = ['<option value="">Natural (decided by caller and body)</option>'];
    (r.success || []).forEach((s) => opts.push(`<option value="${s}|">${s} success</option>`));
    (r.errors || []).forEach((e) => e.errors.forEach((c) => { if (!/reason returned/.test(c)) opts.push(`<option value="${e.status}|${esc(c)}">${e.status} ${esc(c)}</option>`); }));
    $('#tForce').innerHTML = opts.join('');
    $('#tOut').innerHTML = '<p style="color:var(--text-2)">Send a request to see the replayed response.</p>'; $('#tStatus').innerHTML = ''; $('#tTime').textContent = ''; $('#tCurl').innerHTML = '';
  }
  function synth(r, who) {
    const c = C.canned[`${r.method} ${r.path}`]; if (c) return c(who.child ? { child: true, name: who.name } : { id: who.id, role: who.role, name: who.name });
    const sh = (r.shapes || []).find((s) => s.status === (r.success || [200])[0]) || (r.shapes || [])[0];
    if (!sh || !sh.keys.length) return sh && sh.helper ? { _note: `shape comes from ${sh.helper}() in routes.mjs; fields are not listed statically` } : { ok: true };
    const o = {};
    sh.keys.forEach((k) => {
      if (k.startsWith('...')) { o.ok = true; return; }
      o[k] = /^ok$/.test(k) ? true : /(^|[a-z])Id$|^id$/.test(k) ? '0b9f6a52-3c1d-4f0e-9d51-6a2a2d6c1e77' : /At$|^at$|^expires|Instant$/.test(k) ? '2026-11-08T14:02:11.000Z' : /^(token|sessionToken)$/.test(k) ? 'eyJ...<mock>' : /^(items|children|devices|overrides|reflections|doses|medications|expenses|notes|letters|history|changes|results|allergies|conditions)$/.test(k) ? [] : /^(state|status)$/.test(k) ? 'ok' : /^(role|roleName)$/.test(k) ? who.role : /^has|^is|enabled|escalated/.test(k) ? false : /Ms$|Cents$|Count$|^seq$|^version$/.test(k) ? 1 : /^(invite|record|card|theme|settings|order|event|session|bundle)$/.test(k) ? { _note: 'object; fields not statically listed' } : null;
    });
    return o;
  }
  function trySend() {
    const r = byId.get($('#tEp').value); const whoKey = $('#tWho').value; const who = WHO[whoKey] || { role: null };
    const params = {}; $$('#tParams [data-p]').forEach((i) => { params[i.dataset.p] = i.value.trim(); });
    let bodyObj = null, bodyErr = null; const bt = $('#tBody').value.trim();
    if (bt) { try { bodyObj = JSON.parse(bt); } catch (e) { bodyErr = e; } }
    const force = $('#tForce').value;
    let status = 200, body = null, why = '';
    const err = (s, e, extra) => { status = s; body = { error: e, ...(extra || {}) }; };
    const g = (k) => r.guards.find((x) => x.kind === k);
    if (force) {
      const [fs, fc] = force.split('|'); status = +fs;
      if (fc) { err(status, fc, C.cannedErrors[`${r.method} ${r.path}`]?.[status] ? { currentVersion: 4 } : null); } else body = synth(r, who);
      why = 'forced outcome';
    } else if (!r.noSessionRequired && whoKey === 'none') { err(401, 'no_session'); }
    else if (!r.noSessionRequired && whoKey === 'expired') { err(401, 'expired'); }
    else if (!r.noSessionRequired && whoKey === 'revoked') { err(401, 'device_revoked'); }
    else if (bodyErr && bt) { err(400, 'bad_json'); }
    else if (!r.noSessionRequired && r.action && who.child && who.other) { err(403, 'wrong_child'); }
    else if (!r.noSessionRequired && r.action && who.child && (r.action.startsWith('expense.'))) { err(403, 'P6_child_financial'); }
    else if (!r.noSessionRequired && r.action && !who.child && !r.auth.roles.includes(who.role)) { err(403, 'role_lacks_capability'); why = `${who.role} does not hold ${r.action}`; }
    else if (!r.noSessionRequired && who.child && g('child_denied')) { err(g('child_denied').status, g('child_denied').error || 'forbidden'); }
    else if (!r.noSessionRequired && who.child && g('guardian_only')) { err(403, 'guardian_only'); }
    else if (!r.noSessionRequired && !who.child && g('guardian_only') && who.role !== 'guardian') { err(403, 'guardian_only'); }
    else if (!r.noSessionRequired && !who.child && g('live_guardian_edge') && who.role !== 'guardian') { err(403, 'not_a_guardian_of_child'); }
    else if (!r.noSessionRequired && !who.child && g('own_child_only')) { err(403, 'not_this_child'); }
    else if (g('pin_proof') && !(bodyObj && bodyObj.pin)) { err(400, 'pin_required'); }
    else if (g('pin_proof') && bodyObj && String(bodyObj.pin) === '0000') { err(403, 'pin_incorrect'); why = 'mock rule: PIN 0000 is always wrong'; }
    else if (['POST', 'PUT', 'PATCH'].includes(r.method) && r.bodyKeys.length && (!bodyObj || !Object.keys(bodyObj).length)) { const c4 = ((r.errors || []).find((e) => e.status === 400)?.errors || []).filter((c) => c !== 'no_user_identity' && !/^reason returned|^\(dynamic/.test(c)); err(400, c4[0] || 'bad_request'); why = c4.length ? 'empty body: the first documented 400 for this route' : 'empty body: this route returns a validation reason from its validator (see source)'; }
    else { status = (r.success || [200])[0]; body = synth(r, who); }
    const rid = `req-${hash6(r.id + whoKey + Date.now())}${hash6(bt + status)}`.slice(0, 18);
    const ms = 6 + (parseInt(hash6(r.id + status), 16) % 34);
    $('#tStatus').innerHTML = `<span class="status ${sCls(status)}">${status}</span>`; $('#tTime').textContent = `${ms} ms (simulated)`;
    const filled = { ...r, path: r.path.replace(/:(\w+)/g, (_, n) => params[n] || ':' + n) };
    const curl = curlFor(r).replace(/\$([A-Z_]+)/g, (m, n) => m);
    $('#tCurl').innerHTML = ''; $('#tCurl').appendChild(codeEl(curl, 'bash', 'the equivalent real call (not sent)'));
    const hdrs = `content-type: application/json; charset=utf-8\ncache-control: no-store\nx-content-type-options: nosniff\nx-request-id: ${rid}`;
    $('#tOut').innerHTML = `<div class="hdrs" aria-label="Response headers">${esc(hdrs).replace(/\n/g, '<br>')}</div>${why ? `<p class="note-src">Why: ${esc(why)}</p>` : ''}`;
    $('#tOut').appendChild(codeEl(JSON.stringify(body, null, 2), 'json', 'response body (replayed)'));
    void filled;
  }

  /* ======================================================== DATA MODEL */
  let selTable = null; const DF = { q: '', forced: false, norls: false };
  function renderData() {
    const forced = tables.filter((t) => t.rlsForced).length;
    $('#dataLede').textContent = `${tables.length} tables across ${P.migrations.length} migrations, parsed from the SQL. ${forced} carry ENABLE and FORCE row-level security; ${tables.length - forced} do not. Pick a table to see its columns, keys, policies and neighbours.`;
    $('#dq').addEventListener('input', (e) => { DF.q = e.target.value.trim().toLowerCase(); drawMap(); });
    $('#dforced').addEventListener('click', (e) => { DF.forced = !DF.forced; if (DF.forced) DF.norls = false; syncPills(); drawMap(); });
    $('#dnorls').addEventListener('click', (e) => { DF.norls = !DF.norls; if (DF.norls) DF.forced = false; syncPills(); drawMap(); });
    const syncPills = () => { $('#dforced').setAttribute('aria-pressed', DF.forced); $('#dnorls').setAttribute('aria-pressed', DF.norls); };
    $('#dmap').addEventListener('click', (e) => { const b = e.target.closest('.tbtn'); if (b) selectTable(b.dataset.t); });
    drawMap(); selectTable(selTable || 'message_log', false, true);
  }
  function tmatch(t) {
    if (DF.forced && !t.rlsForced) return false; if (DF.norls && t.rlsEnabled) return false;
    if (DF.q) return t.name.includes(DF.q) || t.cols.some((c) => c.name.includes(DF.q));
    return true;
  }
  function drawMap() {
    const seen = new Set(); const sel = selTable && tmap.get(selTable);
    const rel = new Set(sel ? [...sel.fkTargets, ...tables.filter((x) => x.fkTargets.includes(sel.name)).map((x) => x.name)] : []);
    const dom = [...C.domains]; const rest = tables.filter((t) => !C.domains.some((d) => d[1].includes(t.name))).map((t) => t.name); if (rest.length) dom.push(['Other', rest]);
    $('#dmap').innerHTML = dom.map(([n, ts]) => {
      const vis = ts.filter((x) => tmap.has(x) && tmatch(tmap.get(x))); ts.forEach((x) => seen.add(x));
      if (!vis.length) return '';
      return `<div class="dom"><h3>${esc(n)} <span style="color:var(--text-3);font-weight:400">${vis.length}</span></h3><div class="tcloud">${vis.map((x) => { const t = tmap.get(x); return `<button type="button" class="tbtn${rel.has(x) ? ' rel' : ''}${sel && x !== sel.name && !rel.has(x) ? ' dim' : ''}" data-t="${x}" aria-pressed="${x === selTable}" title="${t.rlsForced ? 'FORCE RLS' : 'no RLS'}"><span class="dot ${t.rlsForced ? 'forced' : 'none'}" aria-hidden="true"></span>${x}<span class="sr-only">${t.rlsForced ? ', FORCE RLS' : ', no RLS'}</span></button>`; }).join('')}</div></div>`;
    }).join('') + `<p class="note-src"><span class="dot forced" style="display:inline-block"></span> FORCE RLS &nbsp; <span class="dot none" style="display:inline-block"></span> no RLS (application checks only). Highlighted tables are foreign-key neighbours of the selection.</p>`;
  }
  function selectTable(name, scroll, silent) {
    const t = tmap.get(name); if (!t) return;
    selTable = name; if (rendered.data) drawMap();
    const parents = t.fkTargets.filter((x) => x !== name), kids = tables.filter((x) => x.fkTargets.includes(name) && x.name !== name).map((x) => x.name);
    const pk = new Set(t.pk);
    const cols = t.cols.map((c) => `<tr><td class="mono">${esc(c.name)}${pk.has(c.name) ? ' <span class="badge info">pk</span>' : ''}</td><td class="mono">${esc(c.type)}</td><td>${c.fk ? `<button class="tbtn" data-go="${c.fk}">&rarr; ${esc(c.fk)}</button>` : ''}${c.addedIn ? ` <span class="badge info">added ${c.addedIn}</span>` : ''}</td></tr>`).join('');
    const rls = t.rlsForced ? '<span class="badge built">ENABLE + FORCE RLS</span>' : '<span class="badge warn">no RLS: application checks only</span>';
    const extra = name === 'message_log' ? '<span class="badge bad">append-only</span>' : name === 'medical_record_history' ? '<span class="badge bad">append-only</span>' : '';
    $('#dpane').innerHTML = `<div class="card"><div class="frow" style="margin:0 0 6px"><h3 style="margin:0;font-size:20px" class="mono">${esc(name)}</h3>${rls}${extra}</div>
      <p style="margin:4px 0 10px;color:var(--text-2)">Created in <code>${t.created}</code> &middot; ${plural(t.cols.length, 'column', 'columns')} &middot; ${plural(t.policies.length, 'policy', 'policies')} &middot; ${plural(t.triggers.length, 'trigger', 'triggers')} &middot; ${plural(t.indexes, 'index', 'indexes')}${t.rlsForced ? ` &middot; ${t.monitoredByHealthCheck ? 'watched by <code>rls_unforced</code>' : '<strong>not watched</strong> by <code>rls_unforced</code>'}` : ''}</p>
      <div class="erd" tabindex="0" role="group" aria-label="Foreign key neighbours of ${esc(name)} (scrollable)">${erd(t, parents, kids)}</div>
      <h4>Columns</h4><div class="tablewrap" tabindex="0" role="region" aria-label="Columns"><table><thead><tr><th>Column</th><th>Type</th><th>References</th></tr></thead><tbody>${cols}</tbody></table></div>
      ${t.policies.length ? `<h4>Policies</h4><div class="chips">${t.policies.map((p) => `<span class="tag" title="migration ${p.mig}">${esc(p.name)} <span style="color:var(--text-3)">${p.for}</span></span>`).join('')}</div>` : ''}
      ${t.triggers.length ? `<h4>Triggers</h4><div class="chips">${t.triggers.map((p) => `<span class="tag">${esc(p.name)} <span style="color:var(--text-3)">${esc(p.when)}</span></span>`).join('')}</div>` : ''}
      <h4>Referenced by (${kids.length})</h4><div class="chips">${kids.length ? kids.map((k) => `<button class="tbtn" data-go="${k}">${esc(k)}</button>`).join('') : '<span style="color:var(--text-2)">nothing</span>'}</div></div>`;
    $$('#dpane [data-go]').forEach((b) => b.addEventListener('click', () => selectTable(b.dataset.go)));
    $$('#dpane .nodeg').forEach((g) => { const go = () => selectTable(g.dataset.t); g.addEventListener('click', go); g.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); } }); });
    if (scroll) { if (innerWidth <= 1100) $('#dpane').scrollIntoView({ block: 'start' }); } else if (rendered.data && !silent) history.replaceState(null, '', '#data/' + name);
  }
  function erd(t, parents, kids) {
    const bh = 30, gap = 10, lim = 12, bw = 140; const kshow = kids.slice(0, lim);
    const kc = kshow.length + (kids.length > lim ? 1 : 0);
    const n = Math.max(parents.length, kc, 1);
    const H = n * (bh + gap) + 28, cy = H / 2 + 6, W = 460;
    const cut = (nm, k) => (nm.length > k ? nm.slice(0, k - 1) + '..' : nm);
    const node = (x, y, nm) => `<g class="nodeg" data-t="${nm}" tabindex="0" role="link" aria-label="Open ${nm}"><rect class="box" x="${x}" y="${y}" width="${bw}" height="${bh}" rx="7"/><text class="mono" x="${x + bw / 2}" y="${y + 19}" text-anchor="middle" font-size="10.5">${esc(cut(nm, 20))}</text></g>`;
    let s = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(t.name)} has ${parents.length} parents and ${kids.length} children">`;
    const lx = 4, rx = W - bw - 4, mx = (W - bw) / 2;
    const ys = (cnt, i) => 18 + i * (bh + gap) + (H - 24 - cnt * (bh + gap) + gap) / 2;
    parents.forEach((p, i) => { const y = ys(parents.length, i); s += `<path class="edge" d="M${lx + bw} ${y + bh / 2} C ${lx + bw + 40} ${y + bh / 2}, ${mx - 40} ${cy}, ${mx} ${cy}"/>` + node(lx, y, p); });
    kshow.forEach((k, i) => { const y = ys(kc, i); s += `<path class="edge" d="M${mx + bw} ${cy} C ${mx + bw + 40} ${cy}, ${rx - 40} ${y + bh / 2}, ${rx} ${y + bh / 2}"/>` + node(rx, y, k); });
    if (kids.length > lim) { const y = ys(kc, kshow.length); s += `<text x="${rx + bw / 2}" y="${y + 19}" text-anchor="middle" class="mut" font-size="10.5">+${kids.length - lim} more (listed below)</text>`; }
    s += `<g><rect class="boxc" x="${mx}" y="${cy - 22}" width="${bw}" height="44" rx="9"/><text class="mono" x="${mx + bw / 2}" y="${cy + 1}" text-anchor="middle" font-size="11" font-weight="700">${esc(cut(t.name, 20))}</text><text x="${mx + bw / 2}" y="${cy + 15}" text-anchor="middle" class="mut" font-size="10">${t.rlsForced ? 'FORCE RLS' : 'no RLS'}</text></g>`;
    s += `<text x="${lx}" y="11" class="mut" font-size="10">parents</text><text x="${rx}" y="11" class="mut" font-size="10">children</text></svg>`;
    return s;
  }

  /* ========================================================== REALTIME */
  function renderRealtime() {
    const W = P.ws;
    $('#wsGames').textContent = W.games.join(', ');
    const rows = [['Table token life (single use)', fmtDur(W.tokenTtlSeconds * 1000), 'TABLE_TOKEN_TTL_SECONDS'], ['Longest a table may live', fmtDur(W.maxLifetimeSeconds * 1000), 'TABLE_MAX_LIFETIME_SECONDS'], ['Largest client frame', fmtBytes(W.maxMessageBytes), 'MAX_MESSAGE_BYTES; the socket allows 4x before refusing outright'], ['Moves: burst then refill', `${W.rateCapacity}, then ${W.rateRefillPerSecond} per second`, 'table.ts'], ['Open or join over HTTP', `burst ${W.httpRateCapacity}, about 4 per minute`, 'game_tables.mjs'], ['Ping / pong deadline', `${fmtDur(W.pingIntervalMs)} / ${fmtDur(W.pongTimeoutMs)}`, 'a missed pong ends the table with peer_timeout'], ['Expiry sweep', fmtDur(W.sweepMs), 'closes unjoined and over-age tables']];
    $('#wsLimits').innerHTML = `<thead><tr><th>Limit</th><th>Value</th><th>Note</th></tr></thead><tbody>${rows.map(([a, b, c]) => `<tr><td>${esc(a)}</td><td class="mono">${esc(b)}</td><td style="color:var(--text-2)">${esc(c)}</td></tr>`).join('')}</tbody>`;
    const D = W.denyReasons;
    const cc = [['1000', 'normal close: expired, peer_join_failed, or the other seat left'], ['1001', 'server shutting down'], ['1003', 'malformed_json or malformed_message'], ['1008', 'a rejected move: out_of_turn, rate_limited, invalid_continuation, table_not_active'], ['1009', 'message_too_large'], ['1011', 'table_gone']];
    $('#wsReasons').innerHTML = `<thead><tr><th>Kind</th><th>Values</th></tr></thead><tbody>
      <tr><td>Refusal to open (403 body)</td><td class="chips">${D.open.map((x) => `<span class="tag">${x}</span>`).join('')}</td></tr>
      <tr><td>Refusal to join the socket</td><td class="chips">${D.join.map((x) => `<span class="tag">${x}</span>`).join('')}</td></tr>
      <tr><td>Rejected move</td><td class="chips">${D.move.map((x) => `<span class="tag">${x}</span>`).join('')}</td></tr>
      <tr><td>Table closed (state)</td><td class="chips">${D.closed.map((x) => `<span class="tag">${x}</span>`).join('')}</td></tr>
      <tr><td>table_closed reasons sent</td><td class="chips">${['peer_left', 'peer_error', 'peer_timeout', 'peer_join_failed'].map((x) => `<span class="tag">${x}</span>`).join('')}</td></tr>
      <tr><td>WebSocket close codes</td><td>${cc.map(([c, d]) => `<div><span class="tag">${c}</span> ${esc(d)}</div>`).join('')}</td></tr></tbody>`;
    hydrateCode($('#v-realtime'));
  }

  /* ================================================================ JOBS */
  function renderJobs() {
    const desc = {
      rematerialize: ['Sweeps every delivery_intent still pending, runs the real materialize() against a ChildCtx loaded from Postgres, and writes ready + scheduled_at, expired, or leaves it pending.', 'Without it nothing ever becomes ready.'],
      'reap-media': ['COPPA retention reaper. For each row artifacts_due_for_reaping() returns, deletes the blob first, then the row; writes a reap_tombstone on failure so a stuck row stays visible.', 'The only production caller of the reaper.'],
      'purge-challenges': ['Deletes auth_challenge rows older than the 5 minute TTL plus a 1 hour grace.', 'The login challenge endpoint is unauthenticated.'],
      backup: ['Dumps the database (and media), optional AES-256-GCM, prunes to 7 daily and 4 weekly, optional BACKUP_SYNC_COMMAND.', 'Skipped, not failed, unless BACKUP_DIR and BACKUP_DATABASE_URL are set.'],
      'health-alert': ['Runs tools/health-alert.mjs against the same database and reports its exit code; raises backup_stale when the newest dump is older than BACKUP_MAX_AGE_HOURS (36).', 'Last, so it sees the backup that just ran.'],
    };
    $('#jobTable').innerHTML = `<thead><tr><th>#</th><th>Job</th><th>What it does</th><th>Note</th></tr></thead><tbody>${P.jobs.map((j, i) => `<tr><td class="mono">${i + 1}</td><td class="mono">${esc(j)}</td><td>${esc((desc[j] || [''])[0])}</td><td style="color:var(--text-2)">${esc((desc[j] || ['', ''])[1])}</td></tr>`).join('')}</tbody>`;
    const L = P.limits, W = P.ws;
    const rows = [['Session token', fmtDur(L.sessionTtlMs), 'auth.ts'], ['Escalated session (no route uses it)', fmtDur(L.escalationTtlMs), 'auth.ts'], ['Signed media URL', '5 min', 'storage.ts SIGNED_URL_TTL_SECONDS'], ['WebAuthn challenge', fmtDur(L.challengeTtlMs), 'pool.ts CHALLENGE_TTL_MS'], ['PIN lockout', fmtDur(L.pinLockoutMs), 'after 5 wrong attempts'], ['Device pairing code', '~10 min', 'device_pairing_code.expires_at'], ['Game table join token', fmtDur(W.tokenTtlSeconds * 1000), 'single use'], ['Game table maximum life', fmtDur(W.maxLifetimeSeconds * 1000), 'swept every ' + fmtDur(W.sweepMs)], ['Game socket ping / pong', `${fmtDur(W.pingIntervalMs)} / ${fmtDur(W.pongTimeoutMs)}`, 'game_tables.mjs'], ['/healthz database probe', '3 s', 'index.mjs'], ['Graceful shutdown', '8 s', 'SHUTDOWN_DEADLINE_MS; compose stop_grace_period 15 s'], ['Postgres', 'pool 10, connect 10 s, statement 30 s, idle in tx 30 s', 'DB_POOL_MAX, DB_CONNECTION_TIMEOUT_MS, DB_STATEMENT_TIMEOUT_MS, DB_IDLE_IN_TX_TIMEOUT_MS'], ['Scheduler', `daily at ${3}:00 UTC`, 'SCHEDULER_HOUR_UTC / SCHEDULER_INTERVAL_MS']];
    $('#timerTable').innerHTML = `<thead><tr><th>Clock</th><th>Value</th><th>Where</th></tr></thead><tbody>${rows.map(([a, b, c]) => `<tr><td>${esc(a)}</td><td class="mono">${esc(b)}</td><td style="color:var(--text-2)">${esc(c)}</td></tr>`).join('')}</tbody>`;
    $('#healthChips').innerHTML = C.healthChecks.map(([n, s, m]) => `<div class="card" style="flex:1 1 260px"><span class="badge ${s === 'critical' ? 'bad' : 'warn'}">${s}</span> <code>${n}</code><p>${esc(m)}</p></div>`).join('');
  }

  /* ============================================================ SECURITY */
  function renderSecurity() {
    $('#chalTtl').textContent = P.limits.challengeTtlMs / 60000;
    $('#pinMax').textContent = P.limits.pinMaxAttempts;
    $('#scryptP').textContent = `N=${P.limits.scrypt.N}, r=${P.limits.scrypt.r}, p=${P.limits.scrypt.p}`;
  }

  /* =========================================================== CHANGELOG */
  let clShown = 14;
  function renderChangelog() {
    $('#clLede').textContent = `${P.changelog.length} entries, the latest ${P.specVersion} (${P.changelog[0].date}). Parsed from CHANGELOG.md. The spec version follows Semantic Versioning; it is not a shipped-software version.`;
    const draw = () => {
      const q = $('#clq').value.trim().toLowerCase(); const f = P.changelog.filter((v) => !q || (v.version + ' ' + v.title + ' ' + v.date).toLowerCase().includes(q));
      $('#clcount').textContent = `${f.length} of ${P.changelog.length}`;
      $('#clList').innerHTML = f.slice(0, clShown).map((v) => `<div class="tl"><span class="v">${esc(v.version)}</span><span class="d">${esc(v.date)}</span><p>${esc(v.title)}</p></div>`).join('') || '<div class="empty">No entries match.</div>';
      $('#clMore').hidden = f.length <= clShown;
    };
    $('#clq').addEventListener('input', () => { clShown = 14; draw(); });
    $('#clMore').addEventListener('click', () => { clShown += 30; draw(); });
    draw(); hydrateCode($('#v-changelog'));
  }

  /* ============================================================ RUNBOOKS */
  function renderRunbooks() {
    const root = $('#runbookList');
    C.runbooks.forEach((rb) => {
      const sec = el(`<section class="card" style="margin:0 0 18px" id="${rb.id}"><h2 style="margin:0 0 4px;font-size:20px">${esc(rb.title)} ${rb.derived ? '<span class="badge proposed">derived</span>' : ''} <a class="anchor" href="#runbooks/${rb.id}" aria-label="Link to ${esc(rb.title)}">#</a></h2><p style="color:var(--text-2);margin:0 0 6px">${esc(rb.when)}</p><ol class="steps"></ol>${rb.note ? `<div class="callout info"><p>${rb.note}</p></div>` : ''}</section>`);
      const ol = $('ol', sec);
      rb.steps.forEach((st) => { const li = el(`<li><div>${st.t}</div></li>`); if (st.code) li.appendChild(codeEl(st.code, st.lang, st.lang === 'text' ? 'reference' : 'copy and run')); ol.appendChild(li); });
      root.appendChild(sec);
    });
  }

  /* ============================================================= ROADMAP */
  const RF = { label: '', kind: '' };
  function renderRoadmap() {
    $('#roadProv').innerHTML = `<strong class="t">Provenance</strong><p>${esc(C.roadProvenance)}</p>`;
    const by = (k) => C.road.filter((x) => x.kind === k).length;
    $('#navRoad').textContent = C.road.length;
    const mk = (v, l, group) => `<button class="pill" aria-pressed="${RF[group] === v}" data-g="${group}" data-v="${v}">${l}</button>`;
    $('#roadFilters').innerHTML = [mk('', 'All labels', 'label'), mk('built', 'Built', 'label'), mk('proposed', 'Proposed', 'label'), mk('parked', 'Parked: online', 'label')].join('') + '<span style="width:12px"></span>' + [mk('', 'All kinds', 'kind'), mk('api', `API (${by('api')})`, 'kind'), mk('sec', `Security (${by('sec')})`, 'kind'), mk('data', `Data (${by('data')})`, 'kind'), mk('done', `Hardening done (${by('done')})`, 'kind')].join('');
    $('#roadFilters').addEventListener('click', (e) => { const b = e.target.closest('button'); if (!b) return; RF[b.dataset.g] = b.dataset.v; $$('#roadFilters button').forEach((x) => x.setAttribute('aria-pressed', RF[x.dataset.g] === x.dataset.v)); drawBoard(); });
    drawBoard();
  }
  function drawBoard() {
    const cols = [['now', 'Now (P0)'], ['next', 'Next (P1)'], ['later', 'Later (P2)'], ['parked', 'Parked: online'], ['built', 'Built and verified']];
    const kindName = { api: 'API', sec: 'Security', data: 'Data', done: 'Done' };
    $('#board').innerHTML = cols.map(([c, t]) => {
      const items = C.road.filter((x) => x.col === c && (!RF.label || x.label === RF.label) && (!RF.kind || x.kind === RF.kind));
      return `<section class="col" aria-label="${t}"><h3>${t}<span>${items.length}</span></h3>${items.map((x) => `<article class="ticket"><b>${esc(x.title)}</b><div class="tags"><span class="id">${esc(x.id)}</span><span class="badge ${x.label}">${x.label === 'parked' ? 'parked: online' : x.label}</span><span class="badge info">${kindName[x.kind]}</span>${x.sev ? `<span class="badge ${/high/.test(x.sev) ? 'bad' : 'warn'}">${esc(x.sev)}</span>` : ''}</div><p>${esc(x.body)}</p><div class="id">Evidence: ${esc(x.ev)}</div></article>`).join('') || '<p style="color:var(--text-2);font-size:13px;margin:6px">Nothing here with these filters.</p>'}</section>`;
    }).join('');
  }

  /* =================================================== COMMAND PALETTE */
  const pal = $('#pal'), palIn = $('#palIn'), palList = $('#palList'); let palItems = [], palSel = 0, lastFocus = null;
  function palIndex() {
    const out = [];
    VIEWS.forEach((v) => out.push({ k: 'section', t: TITLES[v], h: '#' + v }));
    ALL.forEach((r) => out.push({ k: r.badge === 'proposed' ? 'proposed' : 'endpoint', t: `${r.method} ${r.path}`, s: `${r.action || ''} ${r.area} ${(r.errors || []).flatMap((e) => e.errors).join(' ')}`, h: '#reference/' + r.id, m: r.method }));
    tables.forEach((t) => out.push({ k: 'table', t: t.name, s: t.cols.map((c) => c.name).join(' '), h: '#data/' + t.name }));
    Object.entries(P.errorCatalog).forEach(([s, o]) => Object.entries(o).forEach(([c, rs]) => out.push({ k: 'error ' + s, t: c, s: rs.join(' '), h: '#reference/' + (ALL.find((r) => `${r.method} ${r.path}` === rs[0])?.id || '') })));
    C.runbooks.forEach((r) => out.push({ k: 'runbook', t: r.title, h: '#runbooks/' + r.id }));
    return out;
  }
  let PI = null;
  function palDraw() {
    PI = PI || palIndex(); const q = palIn.value.trim().toLowerCase(); const terms = q.split(/\s+/).filter(Boolean);
    const scored = PI.map((i) => { const hay = (i.t + ' ' + (i.s || '')).toLowerCase(); if (!terms.every((t) => hay.includes(t))) return null; let sc = 0; terms.forEach((t) => { if (i.t.toLowerCase().includes(t)) sc += 3; if (i.t.toLowerCase().startsWith(t)) sc += 2; }); if (i.k === 'section') sc += 1; return [sc, i]; }).filter(Boolean);
    scored.sort((a, b) => b[0] - a[0]); palItems = (q ? scored : scored.filter((x) => x[1].k === 'section')).slice(0, 30).map((x) => x[1]); palSel = 0;
    palList.innerHTML = palItems.length ? palItems.map((i, n) => `<li role="option" id="po-${n}" aria-selected="${n === 0}" data-n="${n}">${i.m ? `<span class="m ${i.m}">${i.m}</span>` : ''}<span class="${i.m || i.k === 'table' || i.k.startsWith('error') ? 'mono' : ''}">${esc(i.t)}</span><span class="k">${esc(i.k)}</span></li>`).join('') : '<li aria-disabled="true" style="cursor:default">No results</li>';
    palIn.setAttribute('aria-activedescendant', palItems.length ? 'po-0' : '');
  }
  function palMove(d) { if (!palItems.length) return; palSel = (palSel + d + palItems.length) % palItems.length; $$('li', palList).forEach((li, n) => li.setAttribute('aria-selected', n === palSel)); const c = $('#po-' + palSel); palIn.setAttribute('aria-activedescendant', 'po-' + palSel); c && c.scrollIntoView({ block: 'nearest' }); }
  function palGo(n) { const i = palItems[n]; if (!i || !i.h || i.h.endsWith('/')) return; palClose(); location.hash = i.h; }
  function palOpen() { lastFocus = document.activeElement; pal.dataset.open = 'true'; palIn.value = ''; palDraw(); palIn.focus(); }
  function palClose() { pal.dataset.open = 'false'; (lastFocus && lastFocus.focus) && lastFocus.focus(); }
  $('#searchBtn').addEventListener('click', palOpen);
  palIn.addEventListener('input', palDraw);
  palList.addEventListener('click', (e) => { const li = e.target.closest('li[data-n]'); if (li) palGo(+li.dataset.n); });
  pal.addEventListener('mousedown', (e) => { if (e.target === pal) palClose(); });
  pal.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { e.preventDefault(); palClose(); }
    else if (e.key === 'ArrowDown') { e.preventDefault(); palMove(1); } else if (e.key === 'ArrowUp') { e.preventDefault(); palMove(-1); }
    else if (e.key === 'Enter') { e.preventDefault(); palGo(palSel); }
    else if (e.key === 'Tab') { e.preventDefault(); }
  });
  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); pal.dataset.open === 'true' ? palClose() : palOpen(); return; }
    const tag = (document.activeElement && document.activeElement.tagName) || '';
    if (e.key === '/' && !/INPUT|TEXTAREA|SELECT/.test(tag) && pal.dataset.open !== 'true') { e.preventDefault(); if (current !== 'reference') { location.hash = '#reference'; } setTimeout(() => $('#fq').focus(), 30); }
    if (e.key === 'Escape' && side.dataset.open === 'true') { closeSide(); menuBtn.focus(); }
  });

  /* ================================================================ boot */
  const renderers = { start: renderStart, concepts: renderConcepts, reference: renderReference, try: renderTry, data: renderData, realtime: renderRealtime, jobs: renderJobs, security: renderSecurity, changelog: renderChangelog, runbooks: renderRunbooks, roadmap: renderRoadmap };
  $('#navCount').textContent = built.length; $('#navTables').textContent = tables.length; $('#navRoad').textContent = C.road.length;
  $('#verChip').textContent = `spec ${P.specVersion}`;
  $('#sideFoot').innerHTML = `Generated ${esc(P.generated.at.slice(0, 10))} from <code>${built.length - 1 + 1} routes</code>, <code>${P.migrations.length} migrations</code> and CHANGELOG.md by <code>gen-routes.mjs</code>. Static parse; no server code was executed.`;
  hydrateCode(document); initTabs(document);
  route(false);
})();
