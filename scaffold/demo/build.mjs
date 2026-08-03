#!/usr/bin/env node
/**
 * Builds the single-file demo: bundles the real engines, inlines them into the
 * shell, and writes DEMO.html. Self-contained — no server, no network, no
 * build step for the reader.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

execFileSync('npx', ['esbuild', 'demo/src/bridge.ts', '--bundle', '--format=iife',
  '--global-name=TL', '--platform=browser', '--outfile=/tmp/bridge.js',
  '--log-level=error', '--minify'], { stdio: 'inherit' });

const bridge = readFileSync('/tmp/bridge.js', 'utf8');
const shell = readFileSync('demo/shell.html', 'utf8');
const out = shell.replace('/*__BRIDGE__*/', () => bridge);
writeFileSync('../DEMO.html', out);
console.log(`DEMO.html written — ${(out.length / 1024).toFixed(0)} KB, self-contained`);
