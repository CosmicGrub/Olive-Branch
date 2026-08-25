/**
 * docker-compose.dev.yml — host-interface binding + credential-override
 * regression tests.
 *
 * 21a1c92 (v0.49.32) restricted `server`/`callroom` to 127.0.0.1-only
 * (they previously published on every host interface) but never touched
 * `db`'s own port mapping, which shipped "5434:5432" — bound to every
 * interface — protected only by a hardcoded `POSTGRES_PASSWORD: postgres`
 * with no override, while seed-dev.mjs fills that same database with
 * real-shaped family data (a child's name and birth date, a guardian
 * identity, an active custody-order pattern, a delivered video-message
 * artifact) for the exact physical-device testing this stack exists for.
 * Any device on the same WiFi/LAN could reach real Postgres directly, no
 * session/auth layer involved at all. This file exists so that specific
 * bug class — a service in this compose file published on 0.0.0.0 instead
 * of loopback — cannot regress silently again, for `db` or for any future
 * service added here.
 *
 * No live Docker/Postgres needed — this is pure static analysis of the
 * committed compose file and .env.example, the same "read the file and
 * assert on its text" approach tools/check-markup.mjs already uses for
 * MARKUP/CHANGELOG/DEMO correspondence.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SCAFFOLD = fileURLToPath(new URL('../../../', import.meta.url));
// Normalized to LF right after reading, not left as whatever the checkout
// happens to produce: docker-compose.dev.yml is CRLF on disk here (a
// Windows checkout with no .gitattributes rule pinning *.yml to LF — the
// same class of gotcha 0e97a43/#38 hit in push_channel_test's Dart RegExp,
// where a literal `\n` silently stopped matching on CRLF). serviceBlock()
// below does a plain string indexOf for its "\n  <name>:\n" marker, which
// has no `\r?` escape-hatch the way a regex would, so normalizing once
// here — rather than sprinkling `\r?` through every pattern — is the
// robust fix for this file specifically.
const COMPOSE = readFileSync(SCAFFOLD + 'docker-compose.dev.yml', 'utf8').replace(/\r\n/g, '\n');
const ENV_EXAMPLE = readFileSync(SCAFFOLD + '.env.example', 'utf8').replace(/\r\n/g, '\n');

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

// Pull one top-level service's own text out of the compose file, from its
// "  <name>:" header (two-space indent, this file's own convention under
// `services:`) to the next such header or `volumes:`, whichever comes
// first — good enough for this file's stable, hand-written shape without
// pulling in a YAML parser this repo doesn't otherwise depend on.
function serviceBlock(name) {
  const marker = `\n  ${name}:\n`;
  const start = COMPOSE.indexOf(marker);
  if (start === -1) return null;
  const body = COMPOSE.slice(start + marker.length);
  const next = body.search(/^  \w+:\n|^volumes:\n/m);
  return next === -1 ? body : body.slice(0, next);
}

// Every `- "host:container"` (or `- "host:port:container"`) entry — the
// actual host-interface binding Docker applies. A bare "PORT:PORT" with no
// host prefix publishes on 0.0.0.0, every interface; only a "127.0.0.1:"
// prefix restricts it to loopback. Quoted list items are unambiguous here
// — this file's only other list items (volume mounts) are unquoted.
function portEntries(text) {
  return [...text.matchAll(/^\s*-\s*"([^"]+)"\s*$/gm)].map((m) => m[1]);
}

// A · db — the finding itself.
{
  const db = serviceBlock('db');
  check('A db', 'db service block is found', db !== null, true);
  const ports = portEntries(db || '');
  check('A db', 'db publishes exactly one port', ports.length, 1);
  check('A db', 'db port 5434 is loopback-bound, not "5434:5432" on every interface',
    ports[0], '127.0.0.1:5434:5432');
}

// B · server / callroom — the two services 21a1c92 already fixed. A
// regression guard, not new coverage: nothing here should ever be able to
// silently widen either binding back to 0.0.0.0 again.
{
  check('B server', 'server port stays loopback-bound',
    portEntries(serviceBlock('server') || '')[0], '127.0.0.1:8123:8123');
  check('B callroom', 'callroom port stays loopback-bound',
    portEntries(serviceBlock('callroom') || '')[0], '127.0.0.1:8787:8787');
}

// C · every port in the whole file, no exceptions — the general form of A:
// any service ever added here that publishes a port without a
// "127.0.0.1:" host prefix fails this suite, not just the three known
// today.
{
  const allPorts = portEntries(COMPOSE);
  check('C all', 'exactly the three known ports were found (db, server, callroom)',
    allPorts.length, 3);
  const unbound = allPorts.filter((p) => !p.startsWith('127.0.0.1:'));
  check('C all', 'every published port across the whole stack is loopback-bound',
    unbound.join(',') || '(none)', '(none)');
}

// D · db's Postgres password — no longer a bare hardcoded literal, now
// reads from the same ${VAR} .env mechanism SESSION_SECRET/DEV_LOGIN
// already use (see the block right below it in the same file).
{
  const db = serviceBlock('db') || '';
  check('D password', 'POSTGRES_PASSWORD is NOT committed as the bare literal "postgres"',
    /POSTGRES_PASSWORD:\s*postgres\s*$/m.test(db), false);
  check('D password', 'POSTGRES_PASSWORD reads from the ${POSTGRES_PASSWORD...} env-var mechanism',
    /POSTGRES_PASSWORD:\s*\$\{POSTGRES_PASSWORD\b/.test(db), true);
}

// E · .env.example documents the new override, same as SESSION_SECRET/DEV_LOGIN.
{
  check('E env-example', '.env.example documents POSTGRES_PASSWORD as a settable var',
    /^POSTGRES_PASSWORD=/m.test(ENV_EXAMPLE), true);
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
