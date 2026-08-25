/**
 * storage — FilesystemStorage. MASTERFILE §10.1, §5.6, §20.2b.
 *
 * MemoryStorage, reap(), and signed-URL verification already have real
 * coverage in packages/api/test/stack.test.mjs. This file is scoped to what
 * that one doesn't touch: FilesystemStorage, the real (non-memory, non-mock)
 * StoragePort implementation added to close the "only one implementation,
 * and it's test-only" half of the object-storage gap. Every check below
 * does real disk I/O against a throwaway temp directory — no bytes are
 * faked or assumed.
 */
import { promises as fs } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { FilesystemStorage } from '../src/storage.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const root = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-storage-test-'));

// P · REAL DISK I/O — put/get/delete/exists actually touch bytes on disk
{
  const st = new FilesystemStorage(root);
  const bytes = Buffer.from('a real photograph, or close enough for a test');

  check('P filesystem', 'a key that was never put does not exist',
    await st.exists('media/never-written'), 'false');
  check('P filesystem', 'get() on a missing key returns null, not a throw',
    await st.get('media/never-written'), 'null');

  const putResult = await st.put('media/ivy-1.jpg', bytes);
  check('P filesystem', 'put() echoes the key back', putResult.key, 'media/ivy-1.jpg');
  check('P filesystem', 'put() returns a real md5 etag, not a placeholder',
    /^[0-9a-f]{32}$/.test(putResult.etag), 'true');

  const onDisk = await fs.readFile(path.join(root, 'media/ivy-1.jpg'));
  check('P filesystem', 'the bytes genuinely landed on disk, byte-for-byte',
    onDisk.equals(bytes), 'true');

  check('P filesystem', 'exists() is true once written', await st.exists('media/ivy-1.jpg'), 'true');
  const readBack = await st.get('media/ivy-1.jpg');
  check('P filesystem', 'get() reads back exactly what was written',
    readBack.equals(bytes), 'true');

  const deleted = await st.delete('media/ivy-1.jpg');
  check('P filesystem', 'delete() reports true for a key that existed', deleted, 'true');
  check('P filesystem', 'the file is actually gone from disk',
    await fs.access(path.join(root, 'media/ivy-1.jpg')).then(() => 'still there').catch(() => 'gone'),
    'gone');
  const deletedAgain = await st.delete('media/ivy-1.jpg');
  check('P filesystem', 'deleting an already-gone key reports false, not a throw',
    deletedAgain, 'false');
}

// Q · NESTED KEYS — a real storage key carries directory structure
{
  const st = new FilesystemStorage(root);
  await st.put('children/ivy/shows/2026-08-16.mp4', Buffer.from('show bytes'));
  await st.put('children/ivy/homework/algebra.jpg', Buffer.from('worksheet bytes'));
  await st.put('children/wren/shows/2026-08-16.mp4', Buffer.from('other kid, same date'));

  const ivyKeys = await st.list('children/ivy/');
  check('Q nested keys', 'list() finds both of ivy\'s keys, sorted',
    ivyKeys.join(','), 'children/ivy/homework/algebra.jpg,children/ivy/shows/2026-08-16.mp4');
  check('Q nested keys', 'list() does not cross into a different child\'s prefix',
    ivyKeys.some(k => k.includes('wren')), 'false');

  const allShows = await st.list('children/');
  check('Q nested keys', 'a shallower prefix finds all three', allShows.length, 3);
}

// R · PATH TRAVERSAL — a key can never escape the storage root
{
  const st = new FilesystemStorage(root);
  let threw = false;
  try { await st.put('../../outside.txt', Buffer.from('x')); }
  catch { threw = true; }
  check('R traversal', 'a key that would escape root is refused, not written', threw, 'true');
  check('R traversal', 'nothing was written outside the root',
    await fs.access(path.join(root, '..', '..', 'outside.txt')).then(() => 'exists').catch(() => 'absent'),
    'absent');
}

// S · SIGNED URLS — same shape and verification path as MemoryStorage's
{
  const st = new FilesystemStorage(root);
  const url = st.signedUrl('media/ivy-1.jpg', 300, 1_000_000);
  check('S signed urls', 'the key is present, percent-encoded', url.includes('media%2Fivy-1.jpg'), 'true');
  check('S signed urls', 'carries an expiry and a signature', /exp=\d+&sig=/.test(url), 'true');

  // verifySignedKey() — the real counterpart signed-url-serving routes
  // actually call, proven against THIS instance's own real signature, not
  // a hand-rolled one — real HMAC-shaped output, real expiry math.
  const params = new URLSearchParams(url.split('?')[1]);
  const exp = Number(params.get('exp'));
  const sig = params.get('sig');
  check('S signed urls', 'a real, freshly-minted signature verifies ok, well before its expiry',
    st.verifySignedKey('media/ivy-1.jpg', exp, sig, 1_000_000).ok, 'true');
  check('S signed urls', 'the SAME signature is refused once real time has passed its real expiry',
    st.verifySignedKey('media/ivy-1.jpg', exp, sig, (exp + 1) * 1000).ok, 'false');
  check('S signed urls', 'an expired verification names the real reason',
    st.verifySignedKey('media/ivy-1.jpg', exp, sig, (exp + 1) * 1000).reason, 'expired');
  check('S signed urls', 'the identical signature does NOT verify for a DIFFERENT key — '
    + 'the signature genuinely binds the key, not just the expiry',
    st.verifySignedKey('media/some-other-key.jpg', exp, sig, 1_000_000).ok, 'false');
  check('S signed urls', 'a tampered signature is refused, not silently accepted',
    st.verifySignedKey('media/ivy-1.jpg', exp, `${sig.slice(0, -1)}x`, 1_000_000).ok, 'false');
  check('S signed urls', 'a bad signature (not expiry) names the real reason',
    st.verifySignedKey('media/ivy-1.jpg', exp, `${sig.slice(0, -1)}x`, 1_000_000).reason, 'bad_signature');

  // A signature minted by a DIFFERENT FilesystemStorage instance (its own,
  // independently-random secret) must not verify against this one — proves
  // verifySignedKey() genuinely checks against ITS OWN instance secret, not
  // some shared/global one.
  const otherSt = new FilesystemStorage(root);
  const otherUrl = otherSt.signedUrl('media/ivy-1.jpg', 300, 1_000_000);
  const otherSig = new URLSearchParams(otherUrl.split('?')[1]).get('sig');
  check('S signed urls', 'a signature from a DIFFERENT storage instance does not verify here '
    + '— each instance really does hold its own independent secret',
    st.verifySignedKey('media/ivy-1.jpg', exp, otherSig, 1_000_000).ok, 'false');
}

// T · CONTRACT PARITY — FilesystemStorage satisfies the same port MemoryStorage does
{
  const st = new FilesystemStorage(root);
  const required = ['put', 'get', 'delete', 'exists', 'signedUrl', 'list', 'verifySignedKey'];
  check('T contract', 'implements every StoragePort method',
    required.every(m => typeof st[m] === 'function'), 'true');
}

await fs.rm(root, { recursive: true, force: true });

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
