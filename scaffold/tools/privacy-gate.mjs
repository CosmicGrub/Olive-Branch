#!/usr/bin/env node
/**
 * OLIVE BRANCH -- privacy gate.
 *
 * This repository is PUBLIC. A real gate, not a reminder: it reads the lines a
 * commit/branch ADDS and exits NON-ZERO if any of them carries something that
 * must never be published:
 *
 *   identity      the current OS/git user name, host name, e-mail local part and
 *                 anything in PRIVACY_GATE_EXTRA (read at run time, so the gate
 *                 never has to contain the very names it exists to catch), plus
 *                 any literal user segment of a home-directory path
 *   path          local filesystem paths and drive letters (drive-letter paths, the
 *                 Users and home trees of macOS/Linux/Windows, WSL and Git-Bash drive
 *                 mounts, UNC shares)
 *   email         e-mail addresses (placeholder domains and noreply bots allowed)
 *   ip            IPv4 / IPv6 addresses and MACs (loopback, 0.0.0.0, the Android
 *                 emulator host alias, RFC 5737 / RFC 3849 documentation ranges
 *                 and ::1 are allowed)
 *   secret        cloud/API keys, tokens, private-key blocks, JWTs, and quoted
 *                 password/secret/token assignments with a real-looking value
 *   private-link  private artifact / chat / share / tunnel links
 *   sensitive-file  google-services.json, GoogleService-Info.plist, keystores,
 *                 key.properties, local.properties, .env, *.pem/*.p12 ...
 *   device        adb serials spelled out literally, default Windows machine names
 *
 * Usage (run from anywhere inside the repo):
 *   node tools/privacy-gate.mjs                 staged changes (the pre-commit case)
 *   node tools/privacy-gate.mjs --range A...B   everything a branch adds over A
 *   node tools/privacy-gate.mjs --stdin         a unified diff on stdin
 *   node tools/privacy-gate.mjs --text FILE     every line of FILE counts as added
 *                                               (commit messages, PR bodies)
 *   --quiet                                     print only the verdict line
 *
 * Exit codes:  0 clean   1 HIT(S) FOUND   2 could not run (fail CLOSED: a gate that
 * cannot read the diff must not say "clean").
 *
 * Escape hatch, deliberately narrow: a line may carry
 *     privacy-gate: allow <rule>[,<rule>...]
 * to waive exactly those rules on exactly that line (and it is reported). There is
 * no file-level or wildcard waiver. Findings print a REDACTED excerpt so a secret
 * that trips the gate is not copied into CI logs.
 */
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { userInfo, hostname, homedir } from 'node:os';
import { basename } from 'node:path';
import { pathToFileURL } from 'node:url';

// ---------------------------------------------------------------- normalise --
// Hostile input: zero-width / soft-hyphen characters spliced into an address,
// full-width look-alikes (U+FF20 for @), URL-encoded drive paths. Fold all of
// that away before matching.
const INVISIBLE = /[\u00AD\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]/g;
export function normaliseLine(line) {
  let s = String(line).replace(/\r$/, '').replace(INVISIBLE, '');
  try { s = s.normalize('NFKC'); } catch { /* lone surrogates: keep as is */ }
  return s;
}
function percentDecoded(s) {
  if (!s.includes('%')) return null;
  try { const d = decodeURIComponent(s); return d === s ? null : d; } catch { return null; }
}

// -------------------------------------------------------------------- rules --
const PLACEHOLDER_USERS = new Set([
  'user', 'users', 'username', 'you', 'me', 'name', 'yourname', 'youruser', 'your-user',
  'your_username', 'your-name', 'foo', 'bar', 'example', 'someone', 'somebody', 'runner',
  'runneradmin', 'node', 'app', 'postgres', 'ubuntu', 'public', 'default', 'all', 'shared',
  'home', 'root', 'x', 'xxx', 'dev', 'developer', 'build', 'ci', 'agent', 'jenkins',
  '%username%', '$user', '${user}', '$home', '~', '.', '..',
]);
const isPlaceholderSegment = (seg) =>
  seg === '' || /^[.\u2026]+$/.test(seg) || PLACEHOLDER_USERS.has(seg.toLowerCase()) || /^[<{\[$%].*[>}\]%]?$/.test(seg) || /^\*+$/.test(seg);

// Email: domains that cannot identify a person.
const SAFE_EMAIL_DOMAINS = /(^|[.-])(example(\.(com|org|net))?|test|invalid|localhost|local)([.-]|$)|\.(test|invalid|localhost|local|example)$/i;
const SAFE_EMAILS = new Set([
  'noreply@anthropic.com', 'noreply@github.com', 'git@github.com', 'git@gitlab.com',
  'git@bitbucket.org', 'security@github.com',
]);
const SAFE_EMAIL_LOCALS = /^(noreply|no-reply|donotreply|do-not-reply)$/i;

// IPv4: loopback, unspecified, the Android emulator host alias, documentation ranges.
function ipv4Allowed(o) {
  const [a, b, c] = o;
  if (a === 127) return true;
  if (a === 0 && b === 0 && c === 0) return true;      // 0.0.0.0
  if (a === 10 && b === 0 && c === 2) return true;     // 10.0.2.x emulator network
  if (a === 192 && b === 0 && c === 2) return true;    // 192.0.2.0/24  RFC 5737
  if (a === 198 && b === 51 && c === 100) return true; // 198.51.100.0/24
  if (a === 203 && b === 0 && c === 113) return true;  // 203.0.113.0/24
  if (a === 255 && b === 255 && c === 255) return true;// broadcast / netmask literal
  if (a === 255) return true;                          // netmasks (255.255.255.0 ...)
  return false;
}

const SECRET_PATTERNS = [
  ['aws-access-key', /\b(?:AKIA|ASIA|AGPA|AIDA|AROA|ANPA)[0-9A-Z]{16}\b/],
  ['github-token', /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b/],
  ['slack-token', /\bxox[abprs]-[A-Za-z0-9-]{10,}\b/],
  ['google-api-key', /\bAIza[0-9A-Za-z_-]{35}\b/],
  ['firebase-server-key', /\bAAAA[A-Za-z0-9_-]{7}:[A-Za-z0-9_-]{100,}\b/],
  ['stripe-key', /\b(?:sk|rk)_live_[0-9A-Za-z]{16,}\b/],
  ['anthropic-key', /\bsk-ant-[A-Za-z0-9_-]{20,}\b/],
  ['openai-style-key', /\bsk-(?:proj-)?[A-Za-z0-9_-]{32,}\b/],
  ['private-key-block', /-----BEGIN (?:[A-Z]+ )*PRIVATE KEY(?: BLOCK)?-----/],
  ['jwt', /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/],
  ['bearer-token', /\bBearer\s+(?!\$|\{|<|token\b|xxx|your|test|abc|dev)[A-Za-z0-9._~+/-]{24,}=*/],
];
// name = "value" / name: "value" where the value looks like a real credential.
const ASSIGN_RE = /\b([A-Za-z0-9_.-]{0,40}(?:password|passwd|passphrase|secret|token|api[_-]?key|apikey|private[_-]?key|credential|store_?pass)[A-Za-z0-9_.-]{0,40})\b["']?\s{0,4}[:=]\s{0,4}["']([^"'\s]{12,200})["']/i;
const PLACEHOLDER_VALUE = /^(?:\$|\{\{|<|%|\$\{|process\.env|env\[|change[-_]?me|your[-_]|example|dummy|sample|placeholder|test|fake|mock|redacted|xxx|\*{3,}|\.{3,}|none|null|undefined|secret$|password|devsecret|devkey|abcdef|12345)/i;
function entropy(s) {
  const f = new Map(); for (const ch of s) f.set(ch, (f.get(ch) ?? 0) + 1);
  let h = 0; for (const n of f.values()) { const p = n / s.length; h -= p * Math.log2(p); }
  return h;
}

const PRIVATE_LINKS = [
  /\bhttps?:\/\/(?:www\.)?claude\.ai\/(?:artifact|code|chat|share|project|public\/artifacts|new\?)/i,
  /\bhttps?:\/\/[a-z0-9-]+\.claudeusercontent\.com\b/i,
  /\bhttps?:\/\/(?:docs|drive|sheets|slides)\.google\.com\/(?:document|spreadsheets|presentation|file|drive|open|forms)\/[^\s)'"]*/i,
  /\bhttps?:\/\/(?:www\.)?notion\.(?:so|site)\/[^\s)'"]*[0-9a-f]{16,}/i,
  /\bhttps?:\/\/(?:www\.)?dropbox\.com\/(?:s|sh|scl)\//i,
  /\bhttps?:\/\/(?:1drv\.ms|onedrive\.live\.com|[a-z0-9-]+\.sharepoint\.com)\//i,
  /\bhttps?:\/\/[a-z0-9-]+\.(?:ngrok(?:-free)?\.(?:app|io|dev)|trycloudflare\.com|loca\.lt|ts\.net|serveo\.net)\b/i,
  /\bhttps?:\/\/(?:www\.)?figma\.com\/(?:file|design|board|proto)\//i,
  /\bhttps?:\/\/(?:app\.)?slack\.com\/(?:archives|client)\//i,
  /\bhttps?:\/\/hooks\.slack\.com\/services\//i,
  /\bhttps?:\/\/discord(?:app)?\.com\/api\/webhooks\//i,
];

const SENSITIVE_FILE_BASENAMES = [
  /^google-services\.json$/i, /^googleservice-info\.plist$/i, /^key\.properties$/i,
  /^local\.properties$/i, /^\.env$/i, /^\.env\.(?![\w.-]*(?:example|sample|template|dist)$)[\w.-]+$/i,
  /\.(?:keystore|jks|pem|p12|pfx|p8|mobileprovision|gpg|asc)$/i,
  /^id_(?:rsa|dsa|ecdsa|ed25519)(?:\.pub)?$/i, /^\.npmrc$/i, /^\.netrc$/i,
  /^service-?account.*\.json$/i, /^credentials\.json$/i,
];
const SENSITIVE_CONTENT = /"(?:mobilesdk_app_id|current_key|client_secret|private_key_id)"\s*:\s*"[^"]{6,}"/;

function pathHits(s) {
  const hits = [];
  // Drive-letter paths:  C:\x  C:/x   (not http://  not  a:b)
  // The segment after the slash must be >= 2 characters, so regex classes such as
  // `d:\d+` or `x:/a` are not mistaken for a path.
  for (const m of s.matchAll(/(?<![A-Za-z0-9_])([A-Za-z]):[\\/](?=[A-Za-z0-9_.$~-]{2})/g)) {
    const rest = s.slice(m.index + m[0].length);
    const u = /^Users[\\/]([^\\/\s'"`<>]*)/i.exec(rest);
    if (u && isPlaceholderSegment(u[1])) continue;   // C:\Users\<name> in documentation
    hits.push(['path', m[0] + rest.slice(0, 12)]);
  }
  // Windows user profile (works even for the unusual no-drive form).
  for (const m of s.matchAll(/(?:^|[^A-Za-z0-9_])[\\/]Users[\\/]([^\\/\s'"`<>]+)/g)) {
    if (!isPlaceholderSegment(m[1])) hits.push(['path', m[0].trim()]);
  }
  // Unix / macOS / WSL / Git-Bash style.
  for (const m of s.matchAll(/(?:^|[^A-Za-z0-9_.-])\/(?:Users|home)\/([^\\/\s'"`<>:;,)]+)/g)) {
    if (!isPlaceholderSegment(m[1])) hits.push(['path', m[0].trim()]);
  }
  for (const m of s.matchAll(/(?:^|[^A-Za-z0-9_.-])\/(?:mnt\/[a-z]|[a-z])\/(?:Users|Documents and Settings|Downloads|Desktop|Program Files)\b(?:\/([^\\/\s'"`<>:;,)]*))?/g)) {
    if (m[1] !== undefined && /Users/.test(m[0]) && isPlaceholderSegment(m[1])) continue; // privacy-gate: allow path
    hits.push(['path', m[0].trim()]);
  }
  for (const m of s.matchAll(/(?:^|[^A-Za-z0-9_.\\/-])\\\\[A-Za-z0-9_.-]{2,}\\[A-Za-z0-9_.$-]+/g)) {
    hits.push(['path', m[0].trim()]);                           // UNC: server + share
  }
  for (const m of s.matchAll(/(?:^|[^A-Za-z0-9_.-])\/(?:root|var\/folders|private\/var\/folders)\/[^\s'"`<>]+/g)) {
    if (!/^\/root\/?$/.test(m[0].trim())) hits.push(['path', m[0].trim()]);
  }
  return hits;
}

function emailHits(s) {
  const hits = [];
  for (const m of s.matchAll(/(?<![A-Za-z0-9._%+-])([A-Za-z0-9._%+-]+)@((?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,})(?![A-Za-z0-9-])/g)) {
    const local = m[1], domain = m[2];
    if (/^(?:this|super|return|break|continue)$/.test(local)) continue; // Kotlin labels: this@Foo.bar
    const full = `${local}@${domain}`.toLowerCase();
    if (SAFE_EMAILS.has(full) || SAFE_EMAIL_LOCALS.test(local) || SAFE_EMAIL_DOMAINS.test(domain)) continue;
    // `pkg@1.2.3.tgz`-style spec: a "domain" whose labels are all numeric/version-like
    if (/^[0-9.]+$/.test(domain.replace(/\.[A-Za-z]{2,}$/, ''))) continue;
    // `@scope/pkg@x`: the local part is a package name directly after a slash is not an address
    if (/^\d/.test(domain) && /\.(?:tgz|zip|gz|json|js|ts)$/i.test(domain)) continue;
    hits.push(['email', m[0]]);
  }
  return hits;
}

function ipHits(s) {
  const hits = [];
  for (const m of s.matchAll(/(?<![0-9A-Za-z.])((?:\d{1,3}\.){3}\d{1,3})(?![0-9A-Za-z]|\.\d)/g)) {
    const o = m[1].split('.').map(Number);
    if (o.some((n) => n > 255)) continue;
    // Four-part dotted numbers glued to a v/version/semver prefix are versions.
    const before = s.slice(Math.max(0, m.index - 10), m.index);
    if (/(?:v|version|ver|@|~|\^|>=|<=|==|=)\s*$/i.test(before) && o[0] < 100 && !before.endsWith('=')) continue;
    if (ipv4Allowed(o)) continue;
    hits.push(['ip', m[1]]);
  }
  // IPv6 (>= 4 hex groups, so 12:34:56 clock times do not trip it) and MACs.
  for (const m of s.matchAll(/(?<![0-9A-Fa-f:])((?:[0-9A-Fa-f]{1,4}:){3,7}[0-9A-Fa-f]{1,4})(?![0-9A-Fa-f:])/g)) {
    if (/^2001:0?db8:/i.test(m[1])) continue;                     // RFC 3849
    if (/^(?:\d{1,2}:){3,}\d{1,2}$/.test(m[1])) continue;         // 00:00:00:00 timestamps
    hits.push(['ip', m[1]]);
  }
  // Compressed form (link-local / unique-local). A real address has a 4-digit leading hextet
  // or 4+ groups; that keeps CSS ::after, C++ A::B and SQL x::date out.
  for (const m of s.matchAll(/(?<![0-9A-Za-z:])([0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)::([0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)(?![0-9A-Za-z:])/g)) {
    if (/^2001:0?db8:/i.test(m[0])) continue;
    const left = m[1].split(':'), right = m[2].split(':');
    if (!(left.some((g) => g.length === 4) || left.length + right.length >= 4)) continue;
    hits.push(['ip', m[0]]);
  }
  return hits;
}

function secretHits(s) {
  const hits = [];
  for (const [name, re] of SECRET_PATTERNS) {
    const m = re.exec(s);
    if (m) hits.push(['secret', `${name}: ${m[0]}`]);
  }
  // scheme://user:password@host with a password that is neither the user name nor a dev placeholder
  for (const m of s.matchAll(/\b[a-z][a-z0-9+.-]*:\/\/([^\s:@\/'"<>]+):([^\s@\/'"<>]{8,})@[^\s'"<>]+/gi)) {
    const pw = m[2];
    if (pw.toLowerCase() === m[1].toLowerCase() || PLACEHOLDER_VALUE.test(pw) || /[${}<>*]/.test(pw)) continue;
    if (entropy(pw) < 2.8) continue;
    hits.push(['secret', `url-credentials: ${m[0]}`]);
  }
  const a = ASSIGN_RE.exec(s);
  if (a) {
    const v = a[2];
    const wordy = /^[a-z0-9]+(?:[-_.][a-z0-9]+)+$/i.test(v) && !/[A-Z].*[a-z].*[0-9]|[0-9].*[A-Za-z].*[0-9].*[A-Za-z]/.test(v) && v.length < 40;
    if (!PLACEHOLDER_VALUE.test(v) && !/[${}<>]/.test(v) && !/^(?:https?:\/\/|\/)/.test(v) && !wordy
        && v.length >= 16 && entropy(v) >= 3.5 && /[0-9]/.test(v) && /[A-Za-z]/.test(v)) {
      hits.push(['secret', `${a[1]} = ${v}`]);
    }
  }
  if (SENSITIVE_CONTENT.test(s)) hits.push(['sensitive-file', 'google/firebase/service-account credential field']);
  return hits;
}

function linkHits(s) {
  const hits = [];
  for (const re of PRIVATE_LINKS) { const m = re.exec(s); if (m) hits.push(['private-link', m[0]]); }
  return hits;
}

function deviceHits(s) {
  const hits = [];
  for (const m of s.matchAll(/\badb(?:\.exe)?\s+(?:-[a-zA-Z]\s+\S+\s+)*-s\s+(?!\$|"\$|'\$|<|%|\{|\[|SERIAL\b|serial\b|device\b)([A-Za-z0-9._:-]{6,})/g)) {
    hits.push(['device', `adb -s ${m[1]}`]);
  }
  for (const m of s.matchAll(/\bANDROID_SERIAL\s*=\s*(?!\$|"\$|<|%|\{)["']?([A-Za-z0-9._:-]{6,})/g)) {
    hits.push(['device', `ANDROID_SERIAL=${m[1]}`]);
  }
  for (const m of s.matchAll(/\b(?:DESKTOP|LAPTOP|WORKSTATION|PC)-[A-Z0-9]{7}\b/g)) hits.push(['device', m[0]]);
  return hits;
}

// Identity tokens known only at run time.
const GENERIC_IDENTITIES = new Set([
  'root', 'user', 'runner', 'runneradmin', 'admin', 'administrator', 'node', 'docker', 'ubuntu',
  'github', 'postgres', 'localhost', 'build', 'builder', 'ci', 'agent', 'default', 'system',
  'home', 'test', 'tester', 'dev', 'devs', 'nobody', 'unknown', 'public', 'guest',
]);
export function runtimeIdentities(env = process.env, extra = []) {
  const out = new Set();
  const add = (v) => {
    if (typeof v !== 'string') return;
    for (const t of v.split(/[\s,;]+/)) {
      const x = t.trim().replace(/^['"]|['"]$/g, '');
      if (x.length >= 4 && !GENERIC_IDENTITIES.has(x.toLowerCase())) out.add(x.toLowerCase());
    }
  };
  try { add(userInfo().username); } catch { /* no passwd entry */ }
  try { add(hostname()); } catch { /* ignore */ }
  try { add(basename(homedir())); } catch { /* ignore */ }
  for (const k of ['USERNAME', 'USER', 'LOGNAME', 'COMPUTERNAME', 'HOSTNAME']) add(env[k]);
  add(env.PRIVACY_GATE_EXTRA);
  for (const v of extra) add(v);
  const git = (k) => {
    const r = spawnSync('git', ['config', '--get', k], { encoding: 'utf8' });
    return r.status === 0 ? r.stdout.trim() : '';
  };
  const name = git('user.name'), mail = git('user.email');
  if (mail) { add(mail); add(mail.split('@')[0]); }
  if (name) for (const w of name.split(/\s+/)) add(w);
  return [...out];
}
function identityHits(s, identities) {
  const hits = [];
  // A public GitHub owner/repo path or container-registry ref is public by design.
  const low = s.toLowerCase()
    .replace(/(?:github\.com|ghcr\.io|githubusercontent\.com|api\.github\.com)[/:][\w.-]+(?:\/[\w.-]+)?/g, ' ');
  for (const id of identities) {
    let from = 0;
    for (;;) {
      const i = low.indexOf(id, from);
      if (i < 0) break;
      const b = low[i - 1], a = low[i + id.length];
      if (!(b && /[a-z0-9]/.test(b)) && !(a && /[a-z0-9]/.test(a))) { hits.push(['identity', id]); break; }
      from = i + 1;
    }
  }
  return hits;
}

function waived(raw) {
  const m = /privacy-gate:\s*allow\s+([a-z0-9,\s-]+)/i.exec(raw);
  return m ? new Set(m[1].toLowerCase().split(/[\s,]+/).filter(Boolean)) : new Set();
}
const redact = (v) => {
  const t = String(v);
  if (t.length <= 8) return t.slice(0, 2) + '***';
  return `${t.slice(0, 4)}...(${t.length} chars)`;
};

// Every matcher is linear-ish on ordinary lines, but a minified bundle or a hostile megabyte
// line can drive a backtracking one quadratic. Windowing bounds the worst case: each window
// is small, windows overlap so a token on the seam is still seen in one of them.
const WINDOW = 4096, OVERLAP = 512;
function chunked(v, fn) {
  if (v.length <= WINDOW) return fn(v);
  const out = [];
  for (let at = 0; at < v.length; at += WINDOW - OVERLAP) {
    out.push(...fn(v.slice(at, at + WINDOW)));
    if (at + WINDOW >= v.length) break;
  }
  return out;
}

/** Scan ONE added line. Returns [{rule, excerpt}] */
export function scanLine(raw, identities = []) {
  const allow = waived(raw);
  const line = normaliseLine(raw);
  const variants = [line];
  const dec = percentDecoded(line); if (dec) variants.push(normaliseLine(dec));
  const found = [];
  for (const v of variants) {
    for (const h of chunked(v, (c) => [...pathHits(c), ...emailHits(c), ...ipHits(c), ...secretHits(c),
                                       ...linkHits(c), ...deviceHits(c), ...identityHits(c, identities)])) {
      const rule = h[0];
      if (allow.has(rule)) continue;
      found.push({ rule, excerpt: h[1] });
    }
  }
  const seen = new Set();
  return found.filter((f) => { const k = f.rule + '|' + f.excerpt; if (seen.has(k)) return false; seen.add(k); return true; });
}

/** Rules that look at a PATH, not at content. */
export function scanPath(path) {
  const base = String(path).replace(/\\/g, '/').split('/').pop() ?? '';
  const found = [];
  for (const re of SENSITIVE_FILE_BASENAMES) {
    if (re.test(base)) { found.push({ rule: 'sensitive-file', excerpt: base }); break; }
  }
  // A path that itself embeds a person's name or a drive letter.
  for (const h of pathHits(String(path).replace(/^/, ' '))) found.push({ rule: h[0], excerpt: h[1] });
  return found;
}

// --------------------------------------------------------------- diff parse --
const unquote = (p) => {
  let s = p.replace(/\t.*$/, '');
  if (s.startsWith('"') && s.endsWith('"')) s = s.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  return s;
};
/** Parse a unified diff into [{file, line, text}] added lines + [{file}] touched paths. */
export function parseAddedLines(diff) {
  const added = [], paths = [];
  let file = null, ln = 0;
  for (const raw of String(diff).split('\n')) {
    if (raw.startsWith('diff --git ')) { file = null; continue; }
    if (raw.startsWith('+++ ')) {
      const p = unquote(raw.slice(4));
      if (p === '/dev/null') { file = null; continue; }
      file = p.replace(/^b\//, '');
      paths.push(file);
      continue;
    }
    if (raw.startsWith('--- ') || raw.startsWith('index ') || raw.startsWith('new file') ||
        raw.startsWith('deleted file') || raw.startsWith('similarity') || raw.startsWith('rename ') ||
        raw.startsWith('old mode') || raw.startsWith('new mode') || raw.startsWith('Binary files')) {
      if (raw.startsWith('Binary files') && file === null) {
        const m = /^Binary files .* and (.+) differ$/.exec(raw);
        if (m && m[1] !== '/dev/null') paths.push(unquote(m[1]).replace(/^b\//, ''));
      }
      continue;
    }
    const h = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(raw);
    if (h) { ln = Number(h[1]); continue; }
    if (file === null) continue;
    if (raw.startsWith('+')) { added.push({ file, line: ln, text: raw.slice(1) }); ln++; }
    else if (raw.startsWith(' ')) ln++;
    // '-' lines and '\ No newline' do not advance the new-file line counter
  }
  return { added, paths };
}

/** Core: diff text -> findings. */
export function scanDiff(diff, { identities = runtimeIdentities() } = {}) {
  const { added, paths } = parseAddedLines(diff);
  const findings = [];
  for (const p of new Set(paths)) {
    for (const f of scanPath(p)) findings.push({ file: p, line: 0, ...f });
  }
  for (const a of added) {
    for (const f of scanLine(a.text, identities)) findings.push({ file: a.file, line: a.line, ...f });
  }
  return { findings, addedLines: added.length, files: new Set(paths).size };
}

/** Every line of `text` is treated as added (commit messages etc). */
export function scanText(text, label = 'text', { identities = runtimeIdentities() } = {}) {
  const findings = [];
  String(text).split('\n').forEach((t, i) => {
    for (const f of scanLine(t, identities)) findings.push({ file: label, line: i + 1, ...f });
  });
  return { findings, addedLines: String(text).split('\n').length, files: 1 };
}

// --------------------------------------------------------------------- CLI --
function git(args) {
  const r = spawnSync('git', ['-c', 'core.quotepath=false', ...args],
    { encoding: 'utf8', maxBuffer: 512 * 1024 * 1024 });
  if (r.error || r.status !== 0) {
    throw new Error(`git ${args.join(' ')} failed: ${(r.error?.message ?? r.stderr ?? '').toString().trim()}`);
  }
  return r.stdout;
}
const DIFF_OPTS = ['--no-color', '--no-ext-diff', '-U0', '--diff-filter=ACMR', '--no-renames', '--binary'];
function stripBinaryBlobs(diff) {
  // --binary emits base85 "literal" blocks; we only want the headers for those.
  const out = []; let skip = false;
  for (const l of diff.split('\n')) {
    if (l.startsWith('GIT binary patch')) { skip = true; continue; }
    if (skip) { if (l.startsWith('diff --git ')) skip = false; else continue; }
    out.push(l);
  }
  return out.join('\n');
}

export function main(argv = process.argv.slice(2), io = { out: console.log, err: console.error }) {
  const quiet = argv.includes('--quiet');
  let result, label;
  try {
    const i = (f) => argv.indexOf(f);
    if (i('--stdin') >= 0) { result = scanDiff(readFileSync(0, 'utf8')); label = 'stdin diff'; }
    else if (i('--text') >= 0) {
      const f = argv[i('--text') + 1]; if (!f) throw new Error('--text needs a file');
      result = scanText(readFileSync(f, 'utf8'), f); label = f;
    } else if (i('--range') >= 0) {
      const r = argv[i('--range') + 1]; if (!r) throw new Error('--range needs A...B');
      result = scanDiff(stripBinaryBlobs(git(['diff', ...DIFF_OPTS, r]))); label = r;
    } else {
      result = scanDiff(stripBinaryBlobs(git(['diff', '--cached', ...DIFF_OPTS]))); label = 'staged changes';
    }
  } catch (e) {
    io.err(`privacy-gate: CANNOT RUN (${e.message}) -- failing closed`);
    return 2;
  }
  const { findings, addedLines, files } = result;
  for (const f of findings) {
    if (quiet) continue;
    io.err(`  PRIVACY HIT  ${f.file}${f.line ? ':' + f.line : ''}  [${f.rule}]  ${redact(f.excerpt)}`);
  }
  if (findings.length) {
    io.err(`privacy-gate: ${findings.length} hit(s) in ${label} -- NOT clean. Remove them, or (only for a `
      + `genuine placeholder) waive one line with "privacy-gate: allow <rule>".`);
    return 1;
  }
  io.out(`privacy-gate: clean (${addedLines} added line(s), ${files} file(s) in ${label})`);
  return 0;
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  process.exitCode = main();
}
