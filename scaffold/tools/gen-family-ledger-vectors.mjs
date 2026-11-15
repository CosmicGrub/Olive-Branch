// Generates client/test/vectors/family_ledger_vectors.json: golden inputs and the outputs of tools/family_ledger.mjs.
// The Dart port (client/lib/family_ledger.dart) is tested against the SAME file
// (client/test/family_ledger_vectors_test.dart); tools/test/family_ledger_vectors.test.mjs asserts the file equals a
// fresh generation. usage: node tools/gen-family-ledger-vectors.mjs   (writes)   |   --print
import { writeFileSync } from 'node:fs';
import {
  agreeCertBytes, edSignBytes, entryHash, fromJsonValue, publicKeyOf, signedBytes, voteBytes, edVerifyBytes,
} from './family_ledger.mjs';

const hex = (b) => Buffer.from(b).toString('hex');
const fill = (n, tag) => Buffer.alloc(n, tag);
const b = (buf) => ({ $b: hex(buf) });

const momSeed = fill(32, 1), dadSeed = fill(32, 2), kidSeed = fill(32, 3);
const momPub = publicKeyOf(momSeed), dadPub = publicKeyOf(dadSeed), kidPub = publicKeyOf(kidSeed);
// Any 32 bytes will do for an agreement key here: the certificate is only a signature over them.
const momAgree = fill(32, 0xa1), dadAgree = fill(32, 0xa2);
const momCert = edSignBytes(momSeed, agreeCertBytes(momAgree, momPub));
const dadCert = edSignBytes(dadSeed, agreeCertBytes(dadAgree, dadPub));
const T0 = 1800000000000;

const fid = fill(16, 9), momGid = fill(16, 1), dadGid = fill(16, 2);
const policy = { add: 'all', settle: 24, carerAct: 'all', carerLook: 'one' };

export function generate() {
  const certs = [
    { label: 'agreement certificate (mom)', kind: 'cert', seed: hex(momSeed), agree: hex(momAgree), expectSig: hex(momCert) },
    { label: 'agreement certificate (dad)', kind: 'cert', seed: hex(dadSeed), agree: hex(dadAgree), expectSig: hex(dadCert) },
  ];
  // [label, entry type, signing seed, labels of the parents, time, body]
  const entryDefs = [
    ['genesis', 'genesis', momSeed, [], T0, {
      v: 1, fid: b(fid), gid: b(momGid), name: 'Mom', dev: { key: b(momPub), agree: b(momAgree), cert: b(momCert) },
      policy, legacyFids: ['local-AAAAAAAAAAAAAAAAAAAAAA'], fkc: b(fill(32, 0xf1)), gkc: b(fill(32, 0xf2)),
    }],
    ['legacy child device', 'device.add', momSeed, ['genesis'], T0 + 1000, {
      kind: 'child', gid: null, childId: 'ivy', name: 'Ivy tablet', dev: { key: b(kidPub), agree: null, cert: null },
      legacy: true, orig: 1700000001000,
    }],
    ['member.add (a second parent)', 'member.add', momSeed, ['legacy child device'], T0 + 2000, {
      gid: b(dadGid), name: 'Dad', kind: 'guardian',
      profile: { preset: 'parent', caps: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], children: null, from: null, until: null },
      dev: { key: b(dadPub), agree: b(dadAgree), cert: b(dadCert) },
      proposal: { id: b(fill(16, 77)), exp: T0 + 2000 + 14 * 86400000, electorate: [b(momGid)], rule: 'all' },
    }],
    ['policy.set (tighten)', 'policy.set', momSeed, ['member.add (a second parent)'], T0 + 3000, {
      policy: { add: 'all', settle: 72, carerAct: 'all', carerLook: 'all' }, exp: null,
    }],
    ['key.rotate (epoch 1)', 'key.rotate', momSeed, ['policy.set (tighten)'], T0 + 4000, {
      epoch: 1, fkc: b(fill(32, 0xe1)), gkc: b(fill(32, 0xe2)),
      wraps: [{ to: b(momPub), fk: b(fill(80, 0x51)), gk: b(fill(80, 0x52)) }, { to: b(kidPub), fk: b(fill(80, 0x53)), gk: null }],
    }],
  ];
  const byLabel = {};
  const entries = entryDefs.map(([label, type, seed, prevLabels, issuedAt, body]) => {
    const prev = prevLabels.map((l) => byLabel[l].hash);
    const bytes = signedBytes({ type, prev, body: fromJsonValue(body), signer: publicKeyOf(seed), issuedAt });
    const sig = edSignBytes(seed, bytes);
    const hash = hex(entryHash(bytes, sig));
    byLabel[label] = { hash };
    return { label, kind: 'entry', type, seed: hex(seed), prev, issuedAt, body, bytes: hex(bytes), sig: hex(sig), hash };
  });
  const target = Buffer.from(byLabel['member.add (a second parent)'].hash, 'hex');
  const voteDefs = [
    ['yes vote by the candidate', dadSeed, 'yes', T0 + 2500],
    ['no vote by a parent', momSeed, 'no', T0 + 2600],
  ];
  const votes = voteDefs.map(([label, seed, answer, at]) => {
    const bytes = voteBytes(target, answer, publicKeyOf(seed), at);
    return { label, kind: 'vote', seed: hex(seed), target: hex(target), answer, at, bytes: hex(bytes), sig: hex(edSignBytes(seed, bytes)) };
  });
  return [...certs, ...entries, ...votes];
}

// Used by the Node test only.
export const selfCheck = (cases) => cases.every((c) => {
  const pub = publicKeyOf(Buffer.from(c.seed, 'hex'));
  if (c.kind === 'cert') return edVerifyBytes(pub, agreeCertBytes(Buffer.from(c.agree, 'hex'), pub), Buffer.from(c.expectSig, 'hex'));
  return edVerifyBytes(pub, Buffer.from(c.bytes, 'hex'), Buffer.from(c.sig, 'hex'));
});

if (process.argv[1]?.endsWith('gen-family-ledger-vectors.mjs')) {
  const out = JSON.stringify({ generatedBy: 'tools/gen-family-ledger-vectors.mjs', cases: generate() }, null, 1) + String.fromCharCode(10);
  if (process.argv.includes('--print')) process.stdout.write(out);
  else writeFileSync(new URL('../client/test/vectors/family_ledger_vectors.json', import.meta.url), out);
}
