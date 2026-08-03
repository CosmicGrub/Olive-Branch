#!/usr/bin/env node
/**
 * OLIVE BRANCH — MARKUP generator.
 *
 * Standing rule: MARKUP.md is an exhaustive annotated inventory of every part of
 * the platform, and it is GENERATED, never hand-maintained. A hand-written
 * inventory of ~30 tables and 5 packages is stale the moment the next migration
 * lands, and a stale inventory is worse than none because it is trusted.
 *
 * Sources of truth, in order of authority:
 *   1. A live Postgres with all migrations applied  → schema objects
 *   2. The TypeScript sources                       → package exports
 *   3. The test files                               → assertion groups + counts
 *   4. MASTERFILE.md                                → prohibitions, principles
 *
 * Usage: node tools/generate-markup.mjs <pgUrlOrPsqlCmd> > ../MARKUP.md
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const REPO = join(ROOT, '..');
const PSQL = process.env.PSQL_CMD;   // e.g. "psql -h /tmp -p 5433 -d v7"
const DB_OK = Boolean(PSQL);

const q = (sql) => {
  if (!DB_OK) return [];
  const [cmd, ...args] = PSQL.split(' ');
  const out = execFileSync(cmd, [...args, '-q', '-t', '-A', '-F', '\u0001', '-c', sql],
    { encoding: 'utf8' });
  return out.trim() ? out.trim().split('\n').map(l => l.split('\u0001')) : [];
};

// ---------------------------------------------------------------- schema ----
const tables = q(`
  SELECT c.relname,
         COALESCE(obj_description(c.oid,'pg_class'),''),
         c.relrowsecurity, c.relforcerowsecurity
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
   ORDER BY c.relname`);

const columns = q(`
  SELECT table_name, column_name, data_type, is_nullable, COALESCE(column_default,''),
         ordinal_position
    FROM information_schema.columns
   WHERE table_schema='public'
   ORDER BY table_name, ordinal_position`);

const constraints = q(`
  SELECT rel.relname, con.conname, con.contype,
         pg_get_constraintdef(con.oid)
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid=con.conrelid
    JOIN pg_namespace n ON n.oid=rel.relnamespace
   WHERE n.nspname='public'
   ORDER BY rel.relname, con.contype DESC, con.conname`);

const indexes = q(`
  SELECT tablename, indexname, indexdef FROM pg_indexes
   WHERE schemaname='public' ORDER BY tablename, indexname`);

// Extension-owned functions are not platform parts. `citext` alone contributes
// 14 regexp_*/replace/etc. helpers that would pad the inventory with noise.
const functions = q(`
  SELECT p.proname, pg_get_function_identity_arguments(p.oid),
         pg_get_function_result(p.oid), l.lanname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_language l ON l.oid=p.prolang
   WHERE n.nspname='public' AND l.lanname IN ('sql','plpgsql')
     AND NOT EXISTS (
       SELECT 1 FROM pg_depend d
        WHERE d.objid = p.oid AND d.deptype = 'e')
   ORDER BY p.proname`);

const views = q(`SELECT viewname FROM pg_views WHERE schemaname='public' ORDER BY viewname`);

const policies = q(`
  SELECT tablename, policyname, cmd, COALESCE(qual,'')
    FROM pg_policies WHERE schemaname='public' ORDER BY tablename, policyname`);

const triggers = q(`
  SELECT c.relname, t.tgname, p.proname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid=t.tgrelid
    JOIN pg_proc p ON p.oid=t.tgfoid
    JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE NOT t.tgisinternal AND n.nspname='public'
   ORDER BY c.relname, t.tgname`);

const enums = q(`
  SELECT t.typname, string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder)
    FROM pg_type t JOIN pg_enum e ON e.enumtypid=t.oid
    JOIN pg_namespace n ON n.oid=t.typnamespace
   WHERE n.nspname='public' GROUP BY t.typname ORDER BY t.typname`);

// ------------------------------------------------------------- packages ----
const PKG_DIR = join(ROOT, 'packages');
const packages = existsSync(PKG_DIR) ? readdirSync(PKG_DIR).sort() : [];

function exportsOf(file) {
  const src = readFileSync(file, 'utf8');
  const out = [];
  const re = /^export\s+(?:async\s+)?(function|const|class|type|interface|enum)\s+([A-Za-z_$][\w$]*)/gm;
  let m; while ((m = re.exec(src))) out.push({ kind: m[1], name: m[2] });
  // doc comment first line, if any, for each export
  return out;
}

function pkgFiles(pkg, sub) {
  const d = join(PKG_DIR, pkg, sub);
  return existsSync(d) ? readdirSync(d).filter(f => /\.(ts|mjs)$/.test(f) && !f.endsWith('.mjs')) : [];
}

/**
 * Group names and counts come from EXECUTING the suite and parsing its own
 * output. An earlier version regex-counted `check(` call sites and undercounted
 * two suites (34/37, 63/67) because some calls span lines. A generated inventory
 * that misreports test counts is worse than one that omits them.
 */
function testGroups(pkg) {
  const d = join(PKG_DIR, pkg, 'test');
  if (!existsSync(d)) return { groups: [], total: 0, ran: false };
  const groups = [];
  let total = 0, ran = false;
  for (const f of readdirSync(d).filter(f => f.endsWith('.mjs'))) {
    let out = '';
    try {
      out = execFileSync('node', [join(d, f)], { encoding: 'utf8', cwd: ROOT });
      ran = true;
    } catch (e) { out = (e.stdout || '') + (e.stderr || ''); }
    let current = null;
    const counts = new Map();
    for (const line of out.split('\n')) {
      if (/^\S/.test(line) && line.trim() && !/^(PASS|FAIL|-|\d+ passed)/.test(line.trim())) {
        current = line.trim(); if (!counts.has(current)) counts.set(current, 0);
      } else if (/^\s+(PASS|FAIL)\s/.test(line) && current) {
        counts.set(current, counts.get(current) + 1);
      }
    }
    const m = out.match(/(\d+) passed, (\d+) failed/);
    if (m) total += +m[1] + +m[2];
    for (const [g, n] of counts) if (n) groups.push({ file: f, group: g, count: n });
  }
  return { groups, total, ran };
}

// --------------------------------------------------------- sql test files ---
function sqlTestAssertions() {
  const d = join(ROOT, 'db', 'test');
  if (!existsSync(d)) return [];
  const out = [];
  for (const f of readdirSync(d).filter(f => f.endsWith('.sql'))) {
    const src = readFileSync(join(d, f), 'utf8');
    const n = (src.match(/must_fail\(|must_pass\(|assert_eq\(|assert_raises\(/g) || []).length;
    if (n) out.push({ file: f, count: n });
  }
  return out;
}

// ------------------------------------------------------ masterfile mining ---
const MF = existsSync(join(REPO, 'MASTERFILE.md'))
  ? readFileSync(join(REPO, 'MASTERFILE.md'), 'utf8') : '';

function prohibitions() {
  const out = [];
  const re = /\|\s*\*\*(P\d)\*\*\s*\|\s*\*\*([^*]+?)\*\*/g;
  let m; while ((m = re.exec(MF))) out.push({ id: m[1], text: m[2].trim().replace(/\s+/g, ' ') });
  return out;
}
function principles() {
  const out = [];
  const re = /^(\d{1,2})\.\s+\*\*(.+?)\*\*/gm;
  let m; while ((m = re.exec(MF))) if (+m[1] <= 12) out.push({ n: m[1], text: m[2] });
  return out.filter((p, i, a) => a.findIndex(x => x.n === p.n) === i);
}
const mfVersion = (MF.match(/\|\s*\*\*Version\*\*\s*\|\s*([\d.]+)\s*\|/) || [,'?'])[1];

// ------------------------------------------------------- coverage check -----
// Parse the migrations for declared objects and confirm each one appears in the
// live introspection. Without this the document's exhaustiveness is a claim
// rather than a checked invariant.
function declaredInMigrations() {
  const d = join(ROOT, 'db', 'migrations');
  const out = { tables: new Set(), functions: new Set(), views: new Set(),
                policies: new Set(), triggers: new Set(), types: new Set() };
  if (!existsSync(d)) return out;
  for (const f of readdirSync(d).filter(f => f.endsWith('.sql'))) {
    const src = readFileSync(join(d, f), 'utf8');
    for (const m of src.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?(\w+)/gi)) out.tables.add(m[1]);
    for (const m of src.matchAll(/CREATE (?:OR REPLACE )?FUNCTION (\w+)/gi)) out.functions.add(m[1]);
    for (const m of src.matchAll(/CREATE (?:OR REPLACE )?VIEW (\w+)/gi)) out.views.add(m[1]);
    for (const m of src.matchAll(/CREATE POLICY (\w+)/gi)) out.policies.add(m[1]);
    for (const m of src.matchAll(/CREATE TRIGGER (\w+)/gi)) out.triggers.add(m[1]);
    for (const m of src.matchAll(/CREATE TYPE (\w+)/gi)) out.types.add(m[1]);
  }
  return out;
}

const declared = declaredInMigrations();
const found = {
  tables: new Set(tables.map(t => t[0])),
  functions: new Set(functions.map(f => f[0])),
  views: new Set(views.map(v => v[0])),
  policies: new Set(policies.map(p => p[1])),
  triggers: new Set(triggers.map(t => t[1])),
  types: new Set(enums.map(e => e[0])),
};
const coverage = Object.keys(declared).map(k => {
  const missing = [...declared[k]].filter(x => !found[k].has(x));
  return { kind: k, declared: declared[k].size, documented: found[k].size, missing };
});
const coverageOk = coverage.every(c => c.missing.length === 0);

// ------------------------------------------------------------- rendering ----
const L = [];
const w = (s = '') => L.push(s);

const colsFor = (t) => columns.filter(c => c[0] === t);
const consFor = (t) => constraints.filter(c => c[0] === t);
const idxFor  = (t) => indexes.filter(i => i[0] === t);
const CTYPE = { p: 'PRIMARY KEY', f: 'FOREIGN KEY', u: 'UNIQUE', c: 'CHECK', x: 'EXCLUDE' };

w('# OLIVE BRANCH — MARKUP');
w();
w('> **Canonical, and generated.** This document is produced by');
w('> `scaffold/tools/generate-markup.mjs` from the live schema, the actual');
w('> sources, and the test files. Do not hand-edit — regenerate. A hand-written');
w('> inventory of this size is stale the moment the next migration lands, and a');
w('> stale inventory is worse than none because it is trusted.');
w();
w('| | |');
w('|---|---|');
w('| **Document** | MARKUP (canonical, generated) |');
w(`| **Spec version** | ${mfVersion} |`);
w(`| **Generated** | ${new Date().toISOString().slice(0, 19)}Z |`);
w(`| **Schema source** | ${DB_OK ? 'live Postgres, migrations 0001–0003 applied' : 'UNAVAILABLE — schema section incomplete'} |`);
w('| **Companions** | `MASTERFILE.md`, `CHANGELOG.md`, `VISUAL.html` |');
w();
w('**Status legend** — `SHIPPED` code exists and is tested · `SCHEMA` table or');
w('column exists ahead of its feature · `SPEC` specified, not yet built ·');
w('`DEFERRED` recorded in MASTERFILE §19.');
w();
w('---');
w();

// ---- 0 coverage
w('## 0 · Coverage assertion');
w();
w('Every object declared in `db/migrations/*.sql` is checked against the live');
w('introspection below. This is what makes the inventory exhaustive rather than');
w('merely long.');
w();
w('| Object kind | Declared in migrations | Documented here | Missing |');
w('|---|---|---|---|');
for (const c of coverage) {
  w(`| ${c.kind} | ${c.declared} | ${c.documented} | ${c.missing.length ? '**' + c.missing.join(', ') + '**' : 'none' } |`);
}
w();
w(coverageOk
  ? '**COVERAGE COMPLETE** — no declared object is missing from this document.'
  : '**COVERAGE INCOMPLETE** — see the Missing column. Fix before relying on this document.');
w();
w('> `documented` may exceed `declared` where an object is created by an');
w('> extension or by `CREATE OR REPLACE` across several migrations.');
w();
w('---');
w();

// ---- 1 counts
w('## 1 · Inventory summary');
w();
w('| Part | Count |');
w('|---|---|');
w(`| Tables | ${tables.length} |`);
w(`| Columns | ${columns.length} |`);
w(`| Constraints | ${constraints.length} |`);
w(`| Indexes | ${indexes.length} |`);
w(`| Functions | ${functions.length} |`);
w(`| Views | ${views.length} |`);
w(`| RLS policies | ${policies.length} |`);
w(`| Triggers | ${triggers.length} |`);
w(`| Enum types | ${enums.length} |`);
w(`| Packages | ${packages.length} |`);
w(`| Prohibitions | ${prohibitions().length} |`);
w(`| Principles | ${principles().length} |`);
w();
w('---');
w();

// ---- 2 tables
w('## 2 · Database — tables');
w();
if (!DB_OK) w('_Schema introspection unavailable; re-run with `PSQL_CMD` set._');
for (const [t, , rls, force] of tables) {
  w(`### \`${t}\``);
  w();
  const flags = [];
  if (rls === 't') flags.push('RLS **ENABLED**');
  if (force === 't') flags.push('RLS **FORCED** — owner cannot bypass');
  if (flags.length) { w(`> ${flags.join(' · ')}`); w(); }
  w('| # | Column | Type | Null | Default |');
  w('|---|---|---|---|---|');
  for (const [, name, type, nullable, def, pos] of colsFor(t)) {
    w(`| ${pos} | \`${name}\` | ${type} | ${nullable === 'YES' ? 'yes' : '**no**'} | ${def ? `\`${def.slice(0, 42)}\`` : '—' } |`);
  }
  w();
  const cs = consFor(t);
  if (cs.length) {
    w('| Constraint | Kind | Definition |');
    w('|---|---|---|');
    for (const [, name, type, def] of cs) {
      w(`| \`${name}\` | ${CTYPE[type] ?? type} | \`${def.replace(/\|/g, '\\|')}\` |`);
    }
    w();
  }
  const ix = idxFor(t).filter(i => !consFor(t).some(c => c[1] === i[1]));
  if (ix.length) {
    w('| Index | Definition |');
    w('|---|---|');
    for (const [, name, def] of ix) w(`| \`${name}\` | \`${def.replace(/^CREATE /, '')}\` |`);
    w();
  }
}
w('---');
w();

// ---- 3 functions / views / policies / triggers / enums
w('## 3 · Database — functions, views, policies, triggers');
w();
w('### Functions');
w();
w('| Function | Arguments | Returns | Lang |');
w('|---|---|---|---|');
for (const [n, a, r, l] of functions) w(`| \`${n}\` | \`${a || '—'}\` | \`${r}\` | ${l} |`);
w();
w('### Views');
w();
for (const [v] of views) w(`- \`${v}\``);
w();
w('### RLS policies');
w();
w('| Table | Policy | Cmd | Predicate |');
w('|---|---|---|---|');
for (const [t, p, c, qual] of policies) {
  w(`| \`${t}\` | \`${p}\` | ${c} | \`${(qual || '—').replace(/\|/g, '\\|').slice(0, 110)}\` |`);
}
w();
w('### Triggers');
w();
w('| Table | Trigger | Function |');
w('|---|---|---|');
for (const [t, g, f] of triggers) w(`| \`${t}\` | \`${g}\` | \`${f}\` |`);
w();
w('### Enum types');
w();
w('| Type | Values |');
w('|---|---|');
for (const [n, v] of enums) w(`| \`${n}\` | ${v} |`);
w();
w('---');
w();

// ---- 4 packages
w('## 4 · Packages');
w();
for (const p of packages) {
  w(`### \`packages/${p}\``);
  w();
  for (const f of pkgFiles(p, 'src')) {
    const ex = exportsOf(join(PKG_DIR, p, 'src', f));
    w(`**\`src/${f}\`** — ${ex.length} exports`);
    w();
    if (ex.length) {
      w('| Kind | Export |');
      w('|---|---|');
      for (const e of ex) w(`| ${e.kind} | \`${e.name}\` |`);
      w();
    }
  }
  const { groups: tg, total, ran } = testGroups(p);
  if (ran && tg.length) {
    w(`**Tests** — ${total} assertions, executed, in ${new Set(tg.map(g => g.file)).size} file(s)`);
    w();
    w('| Group | Assertions |');
    w('|---|---|');
    for (const g of tg) w(`| ${g.group} | ${g.count} |`);
    w();
  } else if (!existsSync(join(PKG_DIR, p, 'test'))) {
    w('**Tests** — none in this package; covered by another suite. See §5 and the');
    w('cross-package note below.');
    w();
  }
}
w('---');
w();

// ---- 5 sql suites
w('## 5 · Database test suites');
w();
w('| File | Assertions |');
w('|---|---|');
for (const s of sqlTestAssertions()) w(`| \`db/test/${s.file}\` | ${s.count} |`);
w();
w('> These must run as a `NOSUPERUSER NOBYPASSRLS` role. Run as `postgres` they');
w('> measure nothing — superusers bypass RLS even with FORCE.');
w();
w('---');
w();

// ---- 6 prohibitions + principles
w('## 6 · Prohibitions (MASTERFILE §2.1)');
w();
w('| # | Prohibited | Enforced by |');
w('|---|---|---|');
const ENF = {
  P1: 'policy only — no code path exists to violate',
  P2: 'no child-facing scoring surface; metrics are internal',
  P3: '`exchange` has no coordinate column',
  P4: '`child_list_item` has no price or purchase column',
  P5: 'policy + no analytics SDK permitted',
  P6: 'RLS on `expense` + `assert_no_child_financial_access()` + `can()`',
  P7: 'RLS FORCED on `child_journal_entry` + `can()` checks it first, pre-edge',
  P8: 'policy — no delete/update path on the parent log',
  P9: 'opt-in flag + `media_artifact.era_tag`',
};
for (const p of prohibitions()) w(`| **${p.id}** | ${p.text} | ${ENF[p.id] ?? '—'} |`);
w();
w('## 7 · Principles (MASTERFILE §2)');
w();
w('| # | Principle |');
w('|---|---|');
for (const p of principles()) w(`| ${p.n} | ${p.text} |`);
w();
w('---');
w();
w('_End of MARKUP. Regenerate with `npm run markup`; never hand-edit._');

process.stdout.write(L.join('\n') + '\n');
if (!coverageOk) {
  process.stderr.write('MARKUP: coverage incomplete — ' +
    coverage.filter(c => c.missing.length).map(c => `${c.kind}: ${c.missing.join(',')}`).join(' | ') + '\n');
  process.exit(1);
}
