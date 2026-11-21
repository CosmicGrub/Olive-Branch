/**
 * OLIVE BRANCH - the plain-words release notes an update manifest carries.
 *
 * The CHANGELOG is written for the people who build the app; the manifest's notes are read by a grown-up on a phone, once,
 * deciding whether to tap "Download". So the notes live in their own small file, docs/release-notes/<version>.txt, written by
 * a person in adult words. `draft-release-notes.mjs` makes a starting point from the CHANGELOG (one line per ### heading) and
 * stamps it DRAFT; `build-update-package.mjs` refuses to package a file that still says DRAFT, so a machine's first guess can
 * never go out under the owner's signature.
 *
 * FILE FORMAT (plain text, UTF-8)
 *   # anything starting with "#" is a comment for the writer, ignored (except the DRAFT marker below)
 *   headline: One calm sentence, at most 100 characters.
 *   - One thing a grown-up would notice, in plain words. At most 300 characters.
 *   - Up to 12 of these.
 * A line of the form "# DRAFT ..." marks an unreviewed file and makes it unusable until a person deletes it.
 */
import { LIMITS } from './manifest_lib.mjs';

const lf = (s) => String(s).replace(/\r\n?/g, '\n');
const FORBIDDEN = new RegExp(`[<>\`${String.fromCharCode(0)}-${String.fromCharCode(31)}${String.fromCharCode(127)}-${String.fromCharCode(159)}]`);

/** Parses a notes file. Returns { headline, notes } or throws Error listing every problem. */
export function parseNotesFile(text) {
  const problems = [];
  let headline = null;
  const notes = [];
  let draft = false;
  lf(text).split('\n').forEach((raw, i) => {
    const line = raw.trim();
    const where = `line ${i + 1}`;
    if (line === '') return;
    if (line.startsWith('#')) { if (/^#\s*DRAFT\b/i.test(line)) draft = true; return; }
    if (/^headline:/i.test(line)) {
      if (headline !== null) problems.push(`${where}: a second headline`);
      headline = line.replace(/^headline:\s*/i, '').trim();
    } else if (line.startsWith('- ')) notes.push(line.slice(2).trim());
    else problems.push(`${where}: expected "headline: ...", "- a note" or a "#" comment`);
  });
  if (draft) problems.push('the file still carries a "# DRAFT" line: a person must rewrite the notes in plain words and delete that line first');
  if (headline === null || headline === '') problems.push('there is no "headline: ..." line');
  else if (headline.length > LIMITS.headlineChars) problems.push(`the headline is longer than ${LIMITS.headlineChars} characters`);
  else if (FORBIDDEN.test(headline)) problems.push('the headline must be plain text: no angle brackets, backticks or control characters');
  if (notes.length === 0) problems.push('there are no "- " notes');
  if (notes.length > LIMITS.notes) problems.push(`more than ${LIMITS.notes} notes`);
  notes.forEach((n, i) => {
    if (n === '') problems.push(`note ${i + 1} is empty`);
    else if (n.length > LIMITS.noteChars) problems.push(`note ${i + 1} is longer than ${LIMITS.noteChars} characters`);
    else if (FORBIDDEN.test(n)) problems.push(`note ${i + 1} must be plain text: no angle brackets, backticks or control characters`);
  });
  if (problems.length) throw new Error(`release notes: ${problems.join('; ')}`);
  return { headline, notes };
}

const plain = (s) => s
  .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
  .replace(/[`*_<>]/g, '')
  .replace(/\s*\([^)]*\)\s*/g, ' ')
  .replace(/\s+/g, ' ')
  .trim();

/** A DRAFT notes file from one CHANGELOG section body: its title and one starting line per "###" heading. */
export function draftNotesFromChangelog(section, title) {
  const heads = lf(section).split('\n').filter((l) => l.startsWith('### ')).map((l) => plain(l.slice(4))).filter(Boolean);
  const lines = [
    '# DRAFT - a machine made this from the CHANGELOG. Rewrite every line in plain words a grown-up on a phone would',
    '# understand (what changes for them, not what changed in the code), then delete this paragraph. Nothing is packaged',
    '# while it says DRAFT.',
    `headline: ${plain(String(title).split(':')[0]).slice(0, LIMITS.headlineChars)}`,
    ...heads.slice(0, LIMITS.notes).map((h) => `- ${h.slice(0, LIMITS.noteChars)}`),
  ];
  return `${lines.join('\n')}\n`;
}
