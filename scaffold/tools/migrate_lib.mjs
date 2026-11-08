/**
 * Pure helpers for tools/migrate.mjs, split out so they can be unit-tested
 * without a database (migrate.mjs runs its whole body at import time).
 *
 * S-C8 — LINE ENDINGS. The runner records a SHA-256 of each applied migration
 * and REFUSES to run when a file's hash no longer matches (M3). The hash used
 * to be taken over the file's raw bytes, so the same migration hashed
 * differently from an LF checkout (CI, Linux, the database that applied it)
 * and a CRLF checkout (a Windows working tree with core.autocrlf=true), and a
 * developer's volume was reported as "changed after being applied" without a
 * byte of the schema having changed. Hashes are now taken over the text with
 * every CRLF (and any stray CR) normalised to LF, which is exactly what the
 * repository stores (.gitattributes pins `*.sql text eol=lf`). Hashes already
 * recorded by an LF checkout are unchanged, so no stored checksum needs
 * rewriting.
 */
import { createHash } from 'node:crypto';

/** The canonical text a migration is hashed over: LF line endings, no BOM. */
export function normalizeMigrationText(text) {
  return text.replace(/^﻿/, '').replace(/\r\n?/g, '\n');
}

/** SHA-256 (hex) of a migration's canonical text. */
export function migrationChecksum(text) {
  return createHash('sha256').update(normalizeMigrationText(text)).digest('hex');
}
