// The play frame golden vectors: fresh generation equals the file; every frame round-trips; sizes sit on buckets only;
// a flipped bit, a wrong key and a different session each fail to open.
import { readFileSync } from 'node:fs';
import { generate } from '../gen-play-frame-vectors.mjs';
import { open, BUCKETS } from '../play_frame.mjs';

let pass = 0, fail = 0;
const ok = (c, n) => { if (c) pass++; else { fail++; console.error('FAIL: ' + n); } };
const throws = (f) => { try { f(); return false; } catch { return true; } };

const file = JSON.parse(readFileSync(new URL('../../client/test/vectors/play_frame_vectors.json', import.meta.url), 'utf8'));
const { generatedBy, ...body } = file;
ok(JSON.stringify(body) === JSON.stringify(generate()), 'play_frame_vectors.json equals a fresh generation (run node tools/gen-play-frame-vectors.mjs)');
const key = Buffer.from(file.keys.c2s, 'hex'), sid = Buffer.from(file.keys.sid, 'hex');
for (const f of file.frames) {
  const frame = Buffer.from(f.frame, 'hex');
  ok(open(key, sid, frame).toString('hex') === f.payload, `round trip: ${f.label}`);
  ok(BUCKETS.includes(frame.length - 9 - 16), `size on a bucket: ${f.label}`);
  const flipped = Buffer.from(frame); flipped[20] ^= 1;
  ok(throws(() => open(key, sid, flipped)), `bit flip rejected: ${f.label}`);
  ok(throws(() => open(Buffer.from(file.keys.s2c, 'hex'), sid, frame)), `wrong direction key rejected: ${f.label}`);
  ok(throws(() => open(key, Buffer.alloc(16, 9), frame)), `other session rejected: ${f.label}`);
}
const sizes = new Set(file.frames.filter((f) => f.payload.length / 2 + 2 <= 256).map((f) => f.frame.length));
ok(sizes.size === 1, 'a tiny move and a uno play are the same size on the wire');
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
