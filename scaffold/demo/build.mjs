#!/usr/bin/env node
/**
 * Builds the single-file demo: bundles the real engines, inlines them into the
 * shell, and writes DEMO.html. Self-contained — no server, no network, no
 * build step for the reader.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import * as esbuild from 'esbuild';

const built = esbuild.buildSync({
  entryPoints: ['demo/src/bridge.ts'], bundle: true, format: 'iife',
  globalName: 'TL', platform: 'browser', write: false,
  logLevel: 'error', minify: true,
});

const bridge = built.outputFiles[0].text;
const shell = readFileSync('demo/shell.html', 'utf8');
const out = shell.replace('/*__BRIDGE__*/', () => bridge);
writeFileSync('../DEMO.html', out);
console.log(`DEMO.html written — ${(out.length / 1024).toFixed(0)} KB, self-contained`);
