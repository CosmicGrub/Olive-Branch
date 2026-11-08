#!/usr/bin/env node
// OLIVE BRANCH — decrypt a backup the scheduler's `backup` job encrypted
// (BACKUP_ENCRYPTION_PASSPHRASE set). The inverse of tools/backup_lib.mjs's
// encryptFile(); restore the result with tools/restore-db.sh /
// tools/restore-media.sh exactly as an unencrypted backup.
//
//   BACKUP_ENCRYPTION_PASSPHRASE='...' \
//     node tools/backup-decrypt.mjs backups/olive_<db>_<ts>.dump.enc /tmp/restore.dump
//
// Exit: 0 ok, 1 wrong passphrase / corrupted / tampered (AES-GCM is
// authenticated: a flipped bit anywhere is refused, never silently
// mis-decrypted), 2 usage.
import { decryptFile } from './backup_lib.mjs';

const [, , src, dst] = process.argv;
const passphrase = process.env.BACKUP_ENCRYPTION_PASSPHRASE;
if (!src || !dst || !passphrase) {
  console.error('usage: BACKUP_ENCRYPTION_PASSPHRASE=... node tools/backup-decrypt.mjs <in.enc> <out>');
  process.exit(2);
}
try {
  await decryptFile(src, dst, passphrase);
  console.log(`decrypted: ${dst}`);
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
