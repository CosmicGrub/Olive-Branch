// Drift guard: client/test/vectors/call_grant_vectors.json equals a fresh generation, and the jitsi vectors
// carry exactly the contract the Dart client parses (provider, jwt, room, serverURL; nothing livekit; no secret).
import { readFileSync } from 'node:fs';
import { generate } from '../gen-call-grant-vectors.mjs';

let pass = 0, fail = 0;
const ok = (c, n) => { if (c) pass++; else { fail++; console.error('FAIL: ' + n); } };
const file = JSON.parse(readFileSync(new URL('../../client/test/vectors/call_grant_vectors.json', import.meta.url), 'utf8'));
const { generatedBy, ...body } = file;
ok(JSON.stringify(body) === JSON.stringify(await generate()), 'call_grant_vectors.json equals a fresh generation (run node tools/gen-call-grant-vectors.mjs)');
for (const v of file.vectors.filter((x) => x.body.provider === 'jitsi' && !x.body.error)) {
  ok(['jwt', 'room', 'serverURL'].every((k) => typeof v.body[k] === 'string'), `${v.label}: jwt/room/serverURL present`);
  ok(!('token' in v.body) && !('wsURL' in v.body), `${v.label}: no livekit fields`);
  ok(!JSON.stringify(v.body).includes(file.appSecretHex), `${v.label}: secret not in body`);
}
ok(file.vectors.some((v) => v.body.provider === 'livekit' && 'token' in v.body), 'a livekit vector keeps token/wsURL');
ok(file.vectors.some((v) => v.body.error === 'call_provider_unavailable' && v.status === 503), 'an unavailable vector is present');
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
