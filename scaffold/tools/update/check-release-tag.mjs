#!/usr/bin/env node
/**
 * OLIVE BRANCH - does a release tag name the version this checkout really is? (used by .github/workflows/release-artifacts.yml)
 *
 *   node tools/update/check-release-tag.mjs v0.52.0
 *
 * A tag `vX.Y.Z` is accepted only when the five version places agree (the same check CI runs: tools/test/version_sync.test.mjs),
 * the newest CHANGELOG entry is X.Y.Z, pubspec says `X.Y.Z+<derived build number>`, and the versionCode it implies is the one
 * RELEASING.md derives. So a mistyped or moved tag can never produce build artifacts labelled with the wrong version.
 * Exit: 0 fine, 1 a problem (printed).
 */
import { pathToFileURL } from 'node:url';
import { buildNumber, parseVersion, readVersions, versionProblems } from '../release_lib.mjs';

/** Pure: a list of problems for [tag] given the versions read from the tree (empty = fine). */
export function tagProblems(tag, v) {
  const out = [];
  const m = /^v(\d+\.\d+\.\d+)$/.exec(String(tag));
  if (!m) return [`"${tag}" is not a release tag of the form vMAJOR.MINOR.PATCH`];
  let version;
  try { parseVersion(m[1]); version = m[1]; buildNumber(version); } catch (e) { return [e.message]; }
  out.push(...versionProblems(v));
  if (v.changelog.version !== version) out.push(`the tag says ${version} but the CHANGELOG's newest entry is ${v.changelog.version}`);
  if (v.pubspecName !== version) out.push(`the tag says ${version} but pubspec.yaml says ${v.pubspecName}`);
  if (v.pubspecBuild !== String(buildNumber(version))) out.push(`pubspec.yaml build number ${v.pubspecBuild} is not the derived ${buildNumber(version)}`);
  return out;
}

export function run(argv, log = console.log) {
  const problems = tagProblems(argv[0], readVersions());
  if (problems.length) { problems.forEach((p) => log(`check-release-tag: ${p}`)); return 1; }
  log(`check-release-tag: ${argv[0]} matches this checkout (versionCode ${buildNumber(argv[0].slice(1))})`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = run(process.argv.slice(2));
