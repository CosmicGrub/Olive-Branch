/**
 * canvas.ts — MASTERFILE §9.1, §3.1. The shared annotation-canvas engine
 * (Dart port: client/lib/annotation_canvas.dart). Had zero test coverage of
 * its own anywhere in this repo until this pass — every prior guarantee
 * about undo/redo/erase was only ever exercised through the Dart port's own
 * widget tests, never directly against this, its declared source of truth.
 */
import { Canvas } from '../src/canvas.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const draw = (c, id, actorId) => c.add({
  id, actorId, actorKind: 'child', points: [[0, 0]], color: '#000', widthPx: 2,
});

// FA · undo() skips a self-erased stroke entirely, not just one erased by
// someone else — live-found bug: the original guard only checked
// `erasedBy !== actorId`, so a stroke the SAME actor erased fell through and
// was handed a fresh undoneAt, corrupting redo()'s later "most recently
// undone" ordering.
{
  const c = new Canvas();
  draw(c, 'a1', 'ivy');
  check('FA erase-then-undo', 'a1 erases cleanly', c.erase('a1', 'ivy'), 'true');
  draw(c, 'a2', 'ivy');
  const u1 = c.undo('ivy', 10);
  check('FA erase-then-undo', 'first undo() correctly hides a2', u1?.id, 'a2');
  const u2 = c.undo('ivy', 20);
  check('FA erase-then-undo',
    'second undo() must NOT resurrect the self-erased a1 into undo bookkeeping',
    u2, 'null');
  const r1 = c.redo('ivy');
  check('FA erase-then-undo', 'redo() restores a2 — the actually-expected stroke',
    r1?.id, 'a2');
}

// FB · the reverse ordering — undo a stroke first (legitimately), THEN erase
// that same stroke — was a second, independent gap: erase() left the stale
// undoneAt in place, so redo()'s comparison could still pick the
// now-erased stroke as its restoration target.
{
  const c = new Canvas();
  draw(c, 'a1', 'ivy');
  const u1 = c.undo('ivy', 10);
  check('FB undo-then-erase', 'undo() correctly hides a1', u1?.id, 'a1');
  check('FB undo-then-erase', 'a1 erases cleanly', c.erase('a1', 'ivy'), 'true');
  draw(c, 'a2', 'ivy');
  const u2 = c.undo('ivy', 20);
  check('FB undo-then-erase', 'undo() correctly hides a2', u2?.id, 'a2');
  const r1 = c.redo('ivy');
  check('FB undo-then-erase',
    'redo() must restore a2, not silently no-op on the erased a1',
    r1?.id, 'a2');
  const vis = c.visible().map(s => s.id);
  check('FB undo-then-erase', 'a1 never becomes visible again',
    vis.includes('a1'), 'false');
}

// FC · undo() still correctly refuses to reach past an erase by someone else
// — the fix narrowed the guard (dropped the `!== actorId` exception), it did
// not remove it.
{
  const c = new Canvas();
  draw(c, 'a1', 'ivy');
  c.erase('a1', 'dad');
  const u1 = c.undo('ivy', 10);
  check('FC other-actor-erase', 'undo() does not resurrect a stroke erased by someone else',
    u1, 'null');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
