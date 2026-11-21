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
import { createCipheriv, createDecipheriv, createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes, scryptSync } from 'node:crypto';
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

/** Folder names a cloud-sync client keeps its mirrored files in. A key written under one is copied to somebody else's servers. */
const SYNCED_FOLDER = /^(onedrive|dropbox|icloud ?drive|icloud|mobile documents|google ?drive|googledrive|box|box sync|box drive|mega|megasync|pcloud ?drive|nextcloud|owncloud|tresorit|proton ?drive)(\s*[-(].*)?$/i;

/** Where the owner's own cloud-sync clients say they keep files (their environment variables), when set. */
function syncedRoots(env = process.env) {
  return [env.OneDrive, env.OneDriveConsumer, env.OneDriveCommercial, env.DROPBOX_PATH]
    .filter((x) => typeof x === 'string' && x.length > 2 && existsSync(x));
}

/**
 * Why [p] may not hold a private key, or null when it may. A path is refused when it is relative (ambiguous about where
 * it lands), when it is inside this repository's tree, or when any folder above it holds a `.git` (so any repository,
 * worktree or submodule checkout, not only this one). A path under a cloud-synced folder (OneDrive, Dropbox, iCloud Drive,
 * Google Drive and the like, by folder name or by the client's own environment variable) is refused too: the key would be
 * copied to another company's servers. [env] exists for tests.
 */
export function keyPathProblem(p, env = process.env) {
  if (typeof p !== 'string' || p === '') return 'no path given';
  if (!isAbsolute(p)) return 'the key path must be absolute, so there is no doubt where the key lands';
  const anc = realExistingAncestor(p);
  const here = fold(anc);
  let repo;
  try { repo = fold(realpathSync(OWN_REPO)); } catch { repo = fold(resolve(OWN_REPO)); }
  if (here === repo || here.startsWith(repo + sep) || fold(resolve(p)).startsWith(fold(resolve(OWN_REPO)) + sep)) {
    return 'that path is inside the Olive Branch repository tree. This repository is public; a signing key must live outside it';
  }
  const segs = [...resolve(p).split(/[\\/]+/), ...anc.split(/[\\/]+/)];
  if (segs.some((s) => SYNCED_FOLDER.test(s)) || syncedRoots(env).some((r) => fold(resolve(p)).startsWith(fold(resolve(r)) + sep) || here.startsWith(fold(realpathSync(r)) + sep) || here === fold(realpathSync(r)))) {
    return 'that path is inside a cloud-synced folder (OneDrive, Dropbox, iCloud Drive, Google Drive or similar), which would copy the key to a third party. Use a local folder or a removable drive that is not synced';
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

/** The shortest passphrase gen-update-key accepts. */
export const MIN_PASSPHRASE = 14;
/** scrypt cost for the key file: about 128 MiB and a fraction of a second here, and expensive for anyone guessing offline. */
const SCRYPT = Object.freeze({ N: 1 << 17, r: 8, p: 1, maxmem: 512 * 1024 * 1024 });
const ENVELOPE_TAG = ['olive', 'update', 'key'].join('-');

/**
 * The key file's text. With a passphrase it is a small JSON envelope: the PKCS#8 key encrypted with AES-256-GCM under a key
 * derived by scrypt (memory-hard, so guessing is costly even with graphics cards). OpenSSL's own encrypted PEM was not used
 * because it fixes the derivation at 2048 PBKDF2 rounds, which is cheap to brute-force. Without a passphrase it is plain
 * PKCS#8 PEM (only the folder's permissions protect it; gen-update-key makes the owner ask for that out loud).
 */
export function exportPrivateKey(privateKey, passphrase) {
  const der = privateKey.export({ type: 'pkcs8', format: 'der' });
  if (!passphrase) return privateKey.export({ type: 'pkcs8', format: 'pem' });
  const salt = randomBytes(16), iv = randomBytes(12);
  const kdf = scryptSync(passphrase.normalize('NFKC'), salt, 32, SCRYPT);
  const c = createCipheriv('aes-256-gcm', kdf, iv);
  c.setAAD(Buffer.from(ENVELOPE_TAG));
  const ct = Buffer.concat([c.update(der), c.final()]);
  return `${JSON.stringify({ format: ENVELOPE_TAG, v: 1, kdf: 'scrypt', N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p, salt: salt.toString('base64'), iv: iv.toString('base64'), tag: c.getAuthTag().toString('base64'), ct: ct.toString('base64') })}\n`;
}

/** Decrypts an envelope written by exportPrivateKey; throws a plain message when the passphrase is wrong or the file was changed. */
function openEnvelope(text, passphrase) {
  let e;
  try { e = JSON.parse(text); } catch { return null; }
  if (!e || e.format !== ENVELOPE_TAG) return null;
  if (e.v !== 1 || e.kdf !== 'scrypt' || !Number.isInteger(e.N) || e.N < (1 << 14) || e.N > (1 << 20) || e.r !== 8 || e.p !== 1) throw new Error('the key file uses a format this tool does not read');
  if (!passphrase) throw new Error('the key file is encrypted and the passphrase is missing or wrong');
  try {
    const kdf = scryptSync(passphrase.normalize('NFKC'), Buffer.from(e.salt, 'base64'), 32, { N: e.N, r: e.r, p: e.p, maxmem: SCRYPT.maxmem });
    const d = createDecipheriv('aes-256-gcm', kdf, Buffer.from(e.iv, 'base64'));
    d.setAAD(Buffer.from(ENVELOPE_TAG));
    d.setAuthTag(Buffer.from(e.tag, 'base64'));
    return Buffer.concat([d.update(Buffer.from(e.ct, 'base64')), d.final()]);
  } catch { throw new Error('the key file is encrypted and the passphrase is missing or wrong'); }
}

/** Reads a key file written by gen-update-key.mjs. Throws with a plain message on any problem. Returns { privateKey, publicRaw, kid, trust }. */
export function loadUpdateKey(path, passphrase) {
  const problem = keyPathProblem(path);
  if (problem) throw new Error(`refusing to read a signing key from that path: ${problem}`);
  if (!existsSync(path) || !statSync(path).isFile()) throw new Error('no key file at that path');
  const text = readFileSync(path, 'utf8');
  let privateKey;
  const der = openEnvelope(text, passphrase);
  try {
    privateKey = der ? createPrivateKey({ key: der, format: 'der', type: 'pkcs8' }) : createPrivateKey({ key: text, format: 'pem', ...(passphrase ? { passphrase } : {}) });
  } catch (e) {
    throw new Error(/ENCRYPTED/.test(text) ? 'the key file is encrypted and the passphrase is missing or wrong' : 'the file is not a readable private key');
  }
  if (privateKey.asymmetricKeyType !== 'ed25519') throw new Error('the key is not an Ed25519 key');
  const publicRaw = rawPublicKey(createPublicKey(privateKey));
  const kid = kidOf(publicRaw);
  return { privateKey, publicRaw, kid, trust: trustEntry(kid, publicRaw) };
}
