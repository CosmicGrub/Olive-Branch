// Generates client/test/vectors/play_frame_vectors.json: golden inputs and outputs of tools/play_frame.mjs. The Dart
// port (client/lib/play_frame.dart) is tested against the SAME file; tools/test/play_frame_vectors.test.mjs asserts
// the file equals a fresh generation. usage: node tools/gen-play-frame-vectors.mjs   (writes)   |   --print
import { writeFileSync } from 'node:fs';
import { deriveSessionKeys, seal, bucketFor } from './play_frame.mjs';

const hex = (b) => Buffer.from(b).toString('hex');
export function generate() {
  const dh1 = Buffer.alloc(32, 0x11), dh2 = Buffer.alloc(32, 0x22), sid = Buffer.alloc(16, 0x33);
  const k = deriveSessionKeys(dh1, dh2, sid);
  const payloads = [
    ['tiny move', '{"col":3}'],
    ['a uno play', JSON.stringify({ play: 'red-7', draw: 0, say: 'uno' })],
    ['a 300 byte state', JSON.stringify({ s: 'x'.repeat(280) })],
    ['a 5000 byte state', JSON.stringify({ s: 'y'.repeat(4990) })],
    ['empty object', '{}'],
  ];
  return {
    keys: { dh1: hex(dh1), dh2: hex(dh2), sid: hex(sid), c2s: hex(k.c2s), s2c: hex(k.s2c), sas: hex(k.sas) },
    frames: payloads.map(([label, text], i) => {
      const p = Buffer.from(text);
      const seq = i + 1;
      return { label, payload: hex(p), seq, bucket: bucketFor(p.length), frame: hex(seal(k.c2s, sid, seq, p)) };
    }),
    bigSeq: { seq: 4294967297, frame: hex(seal(k.c2s, sid, 4294967297, Buffer.from('{}'))) },
  };
}
if (process.argv[1]?.endsWith('gen-play-frame-vectors.mjs')) {
  const out = JSON.stringify({ generatedBy: 'tools/gen-play-frame-vectors.mjs', ...generate() }, null, 1) + String.fromCharCode(10);
  if (process.argv.includes('--print')) process.stdout.write(out);
  else writeFileSync(new URL('../client/test/vectors/play_frame_vectors.json', import.meta.url), out);
}
