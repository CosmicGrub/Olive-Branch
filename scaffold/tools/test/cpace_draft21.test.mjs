// CPace draft-irtf-cfrg-cpace-21, suite CPACE-X25519-SHA512: the published appendix B.1 vectors against the Node
// reference (tools/pake_cpace.mjs), byte for byte. The vectors are in client/test/vectors/cpace_draft21_vectors.json
// (the Dart test client/test/cpace_draft21_test.dart reads the same file). Also: an independent RFC 7748 ladder
// written here (no OpenSSL) agrees with OpenSSL, so the low-order results do not rest on one library's behaviour.
import { readFileSync } from 'node:fs';
import {
  DSI, S_IN_BYTES, lv, lvCat, decodeUCoordinate, generatorString, generatorHash, generator, scalarMultVfy, x25519,
  transcriptIr, transcriptOc, iskFromTranscript, sidOutput, channelId, run,
} from '../pake_cpace.mjs';

let pass = 0, fail = 0;
const ok = (cond, name) => { if (cond) pass++; else { fail++; console.error('FAIL: ' + name); } };
const hx = (h) => Buffer.from(h, 'hex');
const eq = (got, want, name) => ok(Buffer.from(got).toString('hex') === want, `${name}: got ${Buffer.from(got).toString('hex')} want ${want}`);

const V = JSON.parse(readFileSync(new URL('../../client/test/vectors/cpace_draft21_vectors.json', import.meta.url), 'utf8'));

// the suite constants
ok(DSI === 'CPace255', 'DSI is exactly CPace255');
ok(S_IN_BYTES === 128, 'SHA-512 input block size 128');

// B.1.1 generator
const g = V.b11_generator, prs = hx(g.prs), ci = hx(g.ci), sid = hx(g.sid);
ok(hx(g.dsi).toString() === DSI, 'B.1.1 DSI bytes');
const gs = generatorString(prs, sid, ci);
eq(gs, g.generatorString, 'B.1.1 generator_string');
ok(gs.length === 170, 'B.1.1 generator_string is 170 bytes');
ok(gs[1 + 8 + 1 + 8] === g.zpadLength, 'B.1.1 the zero padding is length-prefixed (0x6d = 109)');
eq(generatorHash(prs, sid, ci), g.generatorStringHash, 'B.1.1 hash of the generator string');
eq(decodeUCoordinate(hx(g.generatorStringHash)), g.decodedFieldElement, 'B.1.1 decoded field element (bit 255 cleared)');
eq(generator(prs, sid, ci), g.g, 'B.1.1 generator g');

// B.1.2 / B.1.3 messages, B.1.4 K
const gen = hx(g.g);
const Ya = scalarMultVfy(hx(V.b12_messageA.ya), gen), Yb = scalarMultVfy(hx(V.b13_messageB.yb), gen);
eq(Ya, V.b12_messageA.Ya, 'B.1.2 Ya');
eq(Yb, V.b13_messageB.Yb, 'B.1.3 Yb');
eq(x25519(hx(V.b12_messageA.ya), Yb), V.b14_K, 'B.1.4 K from ya,Yb');
eq(x25519(hx(V.b13_messageB.yb), Ya), V.b14_K, 'B.1.4 K from yb,Ya');
const K = hx(V.b14_K);

// B.1.5 initiator/responder
const adA = hx(V.b12_messageA.adA), adB = hx(V.b13_messageB.adB);
const tir = transcriptIr(Ya, adA, Yb, adB);
eq(tir, V.b15_iskIr.transcriptIr, 'B.1.5 transcript_ir');
eq(Buffer.concat([lvCat(Buffer.from(DSI + '_ISK'), sid, K), tir]), V.b15_iskIr.iskInput, 'B.1.5 lv_cat(DSI_ISK,sid,K)||transcript_ir');
eq(iskFromTranscript(sid, K, tir), V.b15_iskIr.isk, 'B.1.5 ISK (initiator/responder)');

// B.1.6 parallel execution (symmetric mode; Olive does not use it, the helper exists so the whole appendix is covered)
const toc = transcriptOc(Ya, adA, Yb, adB);
eq(toc, V.b16_iskOc.transcriptOc, 'B.1.6 transcript_oc');
eq(Buffer.concat([lvCat(Buffer.from(DSI + '_ISK'), sid, K), toc]), V.b16_iskOc.iskInput, 'B.1.6 lv_cat(DSI_ISK,sid,K)||transcript_oc');
eq(iskFromTranscript(sid, K, toc), V.b16_iskOc.isk, 'B.1.6 ISK (parallel execution)');

// B.1.7 optional session id output
eq(sidOutput(tir), V.b17_sidOutput.ir, 'B.1.7 sid output (ir)');
eq(sidOutput(toc), V.b17_sidOutput.oc, 'B.1.7 sid output (oc)');

// a whole run through run(): the same inputs reach the draft's ISK
{
  const r = run({ prsC: prs, prsA: prs, sid, ci, yc: hx(V.b12_messageA.ya), ya: hx(V.b13_messageB.yb), adC: adA, adA: adB });
  eq(r.gC, g.g, 'run(): child generator');
  eq(r.Yc, V.b12_messageA.Ya, 'run(): child share is the draft Ya');
  eq(r.Ya, V.b13_messageB.Yb, 'run(): adult share is the draft Yb');
  eq(r.iskC, V.b15_iskIr.isk, 'run(): child ISK is the draft ISK_IR');
  eq(r.iskA, V.b15_iskIr.isk, 'run(): adult ISK is the draft ISK_IR');
}

// B.1.10 low order points and non-canonical encodings
const L = V.b110_lowOrder, s = hx(L.s);
L.u.forEach((u, i) => {
  const n = i.toString(16);
  eq(scalarMultVfy(s, hx(u)), L.q[i], `B.1.10 q${n} = scalar_mult_vfy(s, u${n})`);
  if (L.mustAbortIndices.includes(i)) {
    let threw = false;
    try { x25519(s, hx(u)); } catch { threw = true; }
    ok(threw, `B.1.10 u${n} aborts the exchange`);
    let threw2 = false;
    try { x25519(hx(V.b12_messageA.ya), hx(u)); } catch { threw2 = true; }
    ok(threw2, `B.1.10 u${n} as the peer's message aborts`);
  } else {
    ok(!scalarMultVfy(s, hx(u)).every((x) => x === 0), `B.1.10 u${n} is not an abort case (non-canonical but not low order)`);
  }
});

// independent RFC 7748 Montgomery ladder (BigInt, no OpenSSL) against OpenSSL, on the vectors and on random input
const P = (1n << 255n) - 19n;
const le = (b) => { let r = 0n; for (let i = b.length - 1; i >= 0; i--) r = (r << 8n) | BigInt(b[i]); return r; };
const toLe = (n) => { const o = Buffer.alloc(32); for (let i = 0; i < 32; i++) { o[i] = Number(n & 255n); n >>= 8n; } return o; };
const md = (a) => ((a % P) + P) % P;
const mpow = (b, e) => { let r = 1n; b = md(b); while (e > 0n) { if (e & 1n) r = md(r * b); b = md(b * b); e >>= 1n; } return r; };
function ladder(k32, u32) {
  const k = Buffer.from(k32); k[0] &= 248; k[31] &= 127; k[31] |= 64;
  const kk = le(k);
  const u = Buffer.from(u32); u[31] &= 127;
  const x1 = md(le(u)); let x2 = 1n, z2 = 0n, x3 = x1, z3 = 1n, swap = 0n;
  for (let t = 254n; t >= 0n; t--) {
    const kt = (kk >> t) & 1n; swap ^= kt;
    if (swap) { [x2, x3] = [x3, x2]; [z2, z3] = [z3, z2]; }
    swap = kt;
    const A = md(x2 + z2), AA = md(A * A), B = md(x2 - z2), BB = md(B * B), E = md(AA - BB);
    const C = md(x3 + z3), D = md(x3 - z3), DA = md(D * A), CB = md(C * B);
    x3 = md((DA + CB) ** 2n); z3 = md(x1 * md((DA - CB) ** 2n));
    x2 = md(AA * BB); z2 = md(E * md(AA + 121665n * E));
  }
  if (swap) { [x2, x3] = [x3, x2]; [z2, z3] = [z3, z2]; }
  return toLe(md(x2 * mpow(z2, P - 2n)));
}
eq(ladder(hx('a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4'), hx('e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c')),
  'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552', 'RFC 7748 section 5.2 vector 1 for the independent ladder');
L.u.forEach((u, i) => eq(ladder(s, hx(u)), L.q[i], `independent ladder agrees with the draft on q${i.toString(16)}`));
{
  let state = 12345n, agree = 0;
  const next = () => { state = (state * 6364136223846793005n + 1442695040888963407n) & ((1n << 64n) - 1n); return state; };
  for (let n = 0; n < 40; n++) {
    const k = Buffer.alloc(32), u = Buffer.alloc(32);
    for (let i = 0; i < 32; i++) { k[i] = Number(next() >> 56n); u[i] = Number(next() >> 56n); }
    if (scalarMultVfy(k, u).equals(ladder(k, u))) agree++;
  }
  ok(agree === 40, `OpenSSL and the independent ladder agree on 40 random inputs (${agree}/40)`);
}

// the channel identifier encoding: lv(initiator identity) || lv(responder identity), initiator = the child
{
  const cpk = Buffer.alloc(32, 7), afp = Buffer.alloc(16, 9);
  const got = channelId({ cpk, afp, fid: 'f', an: 'Mom' });
  const want = Buffer.concat([lv(cpk), lv(Buffer.concat([lv(afp), lv(Buffer.from('f')), lv(Buffer.from('Mom'))]))]);
  ok(got.equals(want), 'channel identifier = lv(child key) || lv(lv(fingerprint) || lv(family) || lv(name))');
  ok(!got.equals(channelId({ cpk, afp, fid: 'g', an: 'Mom' })) && !got.equals(channelId({ cpk, afp, fid: 'f', an: 'Mum' })), 'every field is bound');
}

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
