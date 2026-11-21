#!/usr/bin/env node
/**
 * OLIVE BRANCH - make the offline update-signing key (docs/RELEASING.md, "The signing key").
 *
 *   node tools/update/gen-update-key.mjs --out /absolute/path/outside/any/repo/olive-update.key (--passphrase-env NAME | --no-passphrase)
 *
 * Run it ONCE, on a machine you control, and keep the file offline (a drive in a drawer, a password manager's file
 * store). It writes the PRIVATE key only to the path you choose, refuses a path inside any git working tree (and says why),
 * refuses a folder that a cloud service syncs (OneDrive, Dropbox, iCloud Drive, Google Drive), refuses to overwrite a file that is there, and prints only the PUBLIC half: the `kid:key` entry to build into the app with
 *   --dart-define=OLIVE_UPDATE_PUBKEYS=<that entry>
 * A second file, <out>.pub, holds the same public entry. The private key is never printed.
 *
 * --passphrase-env NAME  encrypt the key file under the passphrase held in environment variable NAME (read, never printed;
 *                        at least 14 characters). AES-256-GCM under a scrypt-derived key, so guessing offline is costly.
 * --no-passphrase        the explicit alternative: a plain PKCS#8 file that only its folder's permissions protect (mode 0600
 *                        here; on Windows put it in a folder only you can read). One of the two is required, so a plain
 *                        key is always a decision, never a default.
 *
 * LOSING THE KEY means no installed app can ever be updated in place by a manifest again (the apps hold only the public half)
 * until people reinstall a build carrying a new public key. KEEP A BACKUP of the file, offline, in a second place.
 *
 * Exit: 0 written, 1 refused or failed.
 */
import { existsSync, writeFileSync, chmodSync, statSync } from 'node:fs';
import { dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { MIN_PASSPHRASE, exportPrivateKey, generateUpdateKey, keyPathProblem } from './key_lib.mjs';

function parse(argv) {
  const o = { out: null, passphraseEnv: null, noPassphrase: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--out') o.out = argv[++i];
    else if (a === '--passphrase-env') o.passphraseEnv = argv[++i];
    else if (a === '--no-passphrase') o.noPassphrase = true;
    else if (a === '-h' || a === '--help') o.help = true;
    else throw new Error(`unknown argument: ${a}`);
  }
  return o;
}

export function run(argv, env = process.env, log = console.log) {
  let o;
  try { o = parse(argv); } catch (e) { log(`gen-update-key: ${e.message}`); return 1; }
  if (o.help || !o.out) { log('usage: node tools/update/gen-update-key.mjs --out /absolute/path/outside/any/repo/olive-update.key (--passphrase-env NAME | --no-passphrase)'); return o.help ? 0 : 1; }
  if (!!o.passphraseEnv === o.noPassphrase) { log('gen-update-key: REFUSED. Choose exactly one: --passphrase-env NAME (recommended) or --no-passphrase (a plain key file). Nothing was written.'); return 1; }
  const bad = keyPathProblem(o.out);
  if (bad) { log(`gen-update-key: REFUSED. ${bad}. Nothing was written.`); return 1; }
  if (existsSync(o.out) || existsSync(o.out + '.pub')) { log('gen-update-key: REFUSED. A file already exists there; this tool never overwrites a key. Nothing was written.'); return 1; }
  if (!existsSync(dirname(o.out)) || !statSync(dirname(o.out)).isDirectory()) { log('gen-update-key: REFUSED. The folder does not exist; create it first so there is no doubt where the key goes.'); return 1; }
  let passphrase = null;
  if (o.passphraseEnv) {
    passphrase = env[o.passphraseEnv];
    if (!passphrase || [...passphrase].length < MIN_PASSPHRASE) { log(`gen-update-key: REFUSED. Environment variable ${o.passphraseEnv} is empty or shorter than ${MIN_PASSPHRASE} characters (a few ordinary words make a good passphrase).`); return 1; }
  }
  const k = generateUpdateKey();
  writeFileSync(o.out, exportPrivateKey(k.privateKey, passphrase), { flag: 'wx', mode: 0o600 });
  try { chmodSync(o.out, 0o600); } catch { /* not supported on this file system */ }
  writeFileSync(`${o.out}.pub`, `${k.trust}\n`, { flag: 'wx' });
  log('Update-signing key written.');
  log(`  private key   ${o.out}   (${passphrase ? 'encrypted' : 'NOT encrypted'}; keep it offline and back it up)`);
  log(`  public entry  ${o.out}.pub`);
  log(`  key id        ${k.kid}`);
  log('');
  log('Build this into the app (the public half only):');
  log(`  --dart-define=OLIVE_UPDATE_PUBKEYS=${k.trust}`);
  log('');
  log('Never copy the private key into the repository, a workflow, a chat or an issue.');
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = run(process.argv.slice(2));
