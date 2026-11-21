#!/usr/bin/env node
/**
 * OLIVE BRANCH - start the plain-words release notes for a version from its CHANGELOG section.
 *
 *   node tools/update/draft-release-notes.mjs 0.52.0
 *
 * Writes docs/release-notes/0.52.0.txt (never over an existing file) stamped "# DRAFT". A person rewrites it in adult words
 * and deletes the DRAFT paragraph; tools/update/build-update-package.mjs refuses a file that still says DRAFT.
 * Format and why: tools/update/notes_lib.mjs and docs/UPDATE-MANIFEST.md.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { REPO, changelogSection, parseVersion } from '../release_lib.mjs';
import { draftNotesFromChangelog } from './notes_lib.mjs';

export const notesPathFor = (version, root = REPO) => join(root, 'docs', 'release-notes', `${version}.txt`);

/** The title after the date in "## [x.y.z] - date - title", or null. */
export function changelogTitle(text, version) {
  const head = `## [${version}]`;
  const line = String(text).replace(/\r\n/g, '\n').split('\n').find((l) => l.startsWith(head));
  if (!line) return null;
  const parts = line.slice(head.length).split(' — ');
  return parts.length >= 3 ? parts.slice(2).join(' — ').trim() : null;
}

export function run(argv, log = console.log) {
  const version = (argv[0] || '').replace(/^v/, '');
  try { parseVersion(version); } catch { log('usage: node tools/update/draft-release-notes.mjs <MAJOR.MINOR.PATCH>'); return 1; }
  const out = notesPathFor(version);
  if (existsSync(out)) { log(`draft-release-notes: ${out} already exists; edit it, this tool never overwrites notes a person wrote.`); return 1; }
  const text = readFileSync(join(REPO, 'CHANGELOG.md'), 'utf8');
  let section;
  try { section = changelogSection(text, version); } catch (e) { log(`draft-release-notes: ${e.message}`); return 1; }
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, draftNotesFromChangelog(section, changelogTitle(text, version) || `Version ${version}`), { flag: 'wx' });
  log(`wrote ${out}\nRewrite it in plain words and delete the DRAFT paragraph before packaging.`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = run(process.argv.slice(2));
