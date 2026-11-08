// Generates packages/ledger/test/vectors.json: golden inputs and the outputs the
// TypeScript engine (packages/ledger/src/ledger.ts) gives for them — the hash
// chain (entryHash, verifyChain, certify), the integer basis-point allocation,
// the split-from-percent helper and the canonical JSON serialiser. The Dart port
// (client/lib/court_export.dart: computeEntryHash, verifyChain, certify) is
// tested against the SAME file (client/test/ledger_vectors_test.dart), so the
// phone's "this export is intact" and the server's can never disagree. The
// ledger suite asserts this file equals a fresh generation.
//
// allocate / splitFromPayerShare / canonicalJson have no Dart port today; their
// vectors are the contract for one.
//
// usage: node tools/gen-ledger-vectors.mjs            (writes the file)
//        node tools/gen-ledger-vectors.mjs --print    (prints, writes nothing)
import { writeFileSync } from 'node:fs';
import {
  append, entryHash, verifyChain, certify, GENESIS, allocate, splitFromPayerShare, canonicalJson,
} from '../packages/ledger/src/ledger.mjs';

const C = '33333333-3333-4333-8333-333333333333';
const U1 = '11111111-1111-4111-8111-111111111111';
const U2 = '22222222-2222-4222-8222-222222222222';

function build(bodies, start = '2026-01-01T00:00:00.000Z') {
  const chain = [];
  bodies.forEach((body, i) => {
    const at = new Date(Date.parse(start) + i * 60_000).toISOString();
    chain.push(append(chain, { childId: C, authorId: i % 2 ? U2 : U1, at, body }));
  });
  return chain;
}
const clone = (c) => c.map((e) => ({ ...e }));

export function generate() {
  const out = {};
  const good = build(['first', 'second', 'third']);
  const unicode = build(['café déjà vu', '日本語のメッセージ', 'emoji 😀 and 👨‍👩‍👧', 'line\nbreak\r\nand\ttab', '"quoted" \\ back']);
  const empty = [];
  const single = build(['only']);

  const tamperedBody = clone(good); tamperedBody[1].body = 'edited after the fact';
  const brokenLink = clone(good); brokenLink[2].prevHash = 'f'.repeat(64);
  const gap = clone(good); gap[2].seq = 5;
  const badGenesis = clone(good); badGenesis[0].prevHash = 'e'.repeat(64);
  const timeTravel = build(['a', 'b', 'c']); timeTravel[2].at = '2025-12-31T00:00:00.000Z';
  const manyFaults = clone(good); manyFaults[0].body = 'x'; manyFaults[1].prevHash = 'd'.repeat(64); manyFaults[2].seq = 9;

  const chains = { empty, single, good, unicode, tamperedBody, brokenLink, gap, badGenesis, timeTravel, manyFaults };
  out.chains = {};
  for (const [name, chain] of Object.entries(chains)) {
    const v = verifyChain(chain);
    const att = certify(chain, C, '2026-02-01T00:00:00.000Z');
    out.chains[name] = {
      entries: chain,
      hashes: chain.map((e) => entryHash(e)),
      verify: { ok: v.ok, faults: v.ok ? [] : v.faults },
      attestation: att,
    };
  }
  out.genesis = GENESIS;

  const rules = {
    even: { dad: 5000, mom: 5000 },
    sixty: { dad: 6000, mom: 4000 },
    thirds: { a: 3333, b: 3333, c: 3334 },
    lopsided: { a: 1, b: 9999 },
    quarters: { a: 5000, b: 2500, c: 2500 },
    solo: { a: 10000 },
    tie: { zed: 5000, amy: 5000 },
    four: { x: 3333, y: 3333, z: 3333, w: 1 },
  };
  const amounts = [0, 1, 2, 3, 7, 99, 100, 101, 8900, 10001, 123456789];
  out.allocate = [];
  for (const [rname, rule] of Object.entries(rules)) {
    for (const cents of amounts) out.allocate.push({ rule: rname, bp: rule, cents, expect: allocate(cents, rule) });
  }
  out.allocateRefused = [
    { cents: 10.5, bp: { a: 5000, b: 5000 } }, { cents: -1, bp: { a: 5000, b: 5000 } },
    { cents: 10, bp: { a: 5000.5, b: 4999.5 } }, { cents: 10, bp: { a: 11000, b: -1000 } },
    { cents: 10, bp: {} }, { cents: 10, bp: { a: 5000, b: 4000 } },
  ].map((c) => { let refused = false; try { allocate(c.cents, c.bp); } catch { refused = true; } return { ...c, refused }; });

  out.splitFromPayerShare = [
    ['dad', ['mom'], 50], ['dad', ['mom'], 60], ['dad', ['mom'], 0], ['dad', ['mom'], 100], ['dad', [], 50],
    ['dad', ['zoe', 'amy'], 50], ['dad', ['b', 'a'], 33], ['dad', ['dad', 'mom'], 50], ['dad', ['a', 'b', 'c'], 25],
  ].map(([payer, others, pct]) => ({ payer, others, pct, expect: splitFromPayerShare(payer, others, pct) }));

  out.canonicalJson = [
    { b: 1, a: { d: 1, c: 2 } }, [3, 1, 2], { a: [1, { b: 2 }] }, [-0, 0, 1.5, 1e21, 0.1, 100],
    'a"b\né\u{1F600}', { 'é': 1, z: 2, a: 3, B: 4 }, { a: null, b: true, c: false, d: '' },
    { nested: { z: [{ y: 1, x: 2 }], a: {} } },
  ].map((v) => ({ value: v, expect: canonicalJson(v) }));

  return JSON.parse(JSON.stringify(out));
}

if (process.argv[1] && process.argv[1].endsWith('gen-ledger-vectors.mjs')) {
  const text = JSON.stringify(generate(), null, 1) + '\n';
  if (process.argv.includes('--print')) process.stdout.write(text);
  else { writeFileSync(new URL('../packages/ledger/test/vectors.json', import.meta.url), text); console.log('wrote packages/ledger/test/vectors.json', text.length, 'bytes'); }
}
