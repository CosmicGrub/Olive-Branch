/**
 * OLIVE BRANCH - the owner's offline update-signing key: where it may live, how it is made, how it is read.
 *
 * The private key is the one thing that can make every installed app believe "a newer version exists". It therefore
 *   - is generated and used only on the owner's own machine, by the two scripts that import this file;
 *   - is written ONLY to a path the owner chooses, and never to a path inside any git working tree: this repository is
 *     public, and a key that has ever sat in a working tree is one `git add .` away from being published;
 *   - is never printed, never put in an environment variable by these tools, and never passed to CI. The workflow in
 *     .github/workflows/release-artifacts.yml has no secret and no signing step by design.
 * What the app needs is the PUBLIC half, printed as one `kid:key` entry for --dart-define=OLIVE_UPDATE_PUBKEYS.
 */
import { existsSync, realpathSync, statSync, readFileSync } from 'node:fs';
import { createPrivateKey, createPublicKey, generateKeyPairSync } from 'node:crypto';
import { dirname, isAbsolute, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { kidOf, rawPublicKey, trustEntry } from './manifest_lib.mjs';

/** The working tree this script lives in (scaffold/tools/update -> repository root). */
export const OWN_REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

const fold = (p) => (process.platform === 'win32' || process.platform === 'darwin' ? p.toLowerCase() : p);

/** The deepest ancestor of [p] (or [p] itself) that exists, resolved through symlinks. */
function realExistingAncestor(p) {
  let cur = resolve(p);
  for (;;) {
    if (existsSync(cur)) return realpathSync(cur);
    const up = dirname(cur);
    if (up === cur) return cur;
    cur = up;
  }
}

/**
 * Why [p] may not hold a private key, or null when it may. A path is refused when it is relative (ambiguous about where
 * it lands), when it is inside this repository's tree, or when any folder above it holds a `.git` (so any repository,
 * worktree or submodule checkout, not only this one).
 */
export function keyPathProblem(p) {
  if (typeof p !== 'string' || p === '') return 'no path given';
  if (!isAbsolute(p)) return 'the key path must be absolute, so there is no doubt where the key lands';
  const anc = realExistingAncestor(p);
  const here = fold(anc);
  let repo;
  try { repo = fold(realpathSync(OWN_REPO)); } catch { repo = fold(resolve(OWN_REPO)); }
  if (here === repo || here.startsWith(repo + sep) || fold(resolve(p)).startsWith(fold(resolve(OWN_REPO)) + sep)) {
    return 'that path is inside the Olive Branch repository tree. This repository is public; a signing key must live outside it';
  }
  for (let cur = anc; ; ) {
    if (existsSync(join(cur, '.git'))) return 'that path is inside a git working tree. Keep the signing key outside every repository';
    const up = dirname(cur);
    if (up === cur) break;
    cur = up;
  }
  return null;
}

/** A fresh Ed25519 key pair. { privateKey, publicRaw, kid, trust } */
export function generateUpdateKey() {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const publicRaw = rawPublicKey(publicKey);
  const kid = kidOf(publicRaw);
  return { privateKey, publicRaw, kid, trust: trustEntry(kid, publicRaw) };
}

/** PKCS#8 PEM of a private key; encrypted (AES-256 under a passphrase) when one is given. */
export function exportPrivateKey(privateKey, passphrase) {
  return passphrase
    ? privateKey.export({ type: 'pkcs8', format: 'pem', cipher: 'aes-256-cbc', passphrase })
    : privateKey.export({ type: 'pkcs8', format: 'pem' });
}

/** Reads a key file written by gen-update-key.mjs. Throws with a plain message on any problem. Returns { privateKey, publicRaw, kid, trust }. */
export function loadUpdateKey(path, passphrase) {
  const problem = keyPathProblem(path);
  if (problem) throw new Error(`refusing to read a signing key from that path: ${problem}`);
  if (!existsSync(path) || !statSync(path).isFile()) throw new Error('no key file at that path');
  const pem = readFileSync(path, 'utf8');
  let privateKey;
  try { privateKey = createPrivateKey({ key: pem, format: 'pem', ...(passphrase ? { passphrase } : {}) }); } catch (e) {
    throw new Error(/passphrase|bad decrypt|PEM_do_header|unsupported/i.test(String(e.message)) ? 'the key file is encrypted and the passphrase is missing or wrong' : 'the file is not a readable private key');
  }
  if (privateKey.asymmetricKeyType !== 'ed25519') throw new Error('the key is not an Ed25519 key');
  const publicRaw = rawPublicKey(createPublicKey(privateKey));
  const kid = kidOf(publicRaw);
  return { privateKey, publicRaw, kid, trust: trustEntry(kid, publicRaw) };
}
