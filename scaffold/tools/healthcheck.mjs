#!/usr/bin/env node
/**
 * OLIVE BRANCH — health check.
 *
 * Runs the `health_check` view and exits non-zero on any breach. Intended for
 * cron and for CI. A monitoring view that nothing queries is a comment; this is
 * what turns §20.2b's "no alerting" into alerting.
 */
import { execFileSync } from 'node:child_process';
const PSQL = process.env.PSQL_CMD;
if (!PSQL) { console.error('PSQL_CMD required'); process.exit(2); }
const [cmd, ...args] = PSQL.split(' ');
let out;
try {
  out = execFileSync(cmd, [...args,'-q','-t','-A','-F','\u0001','-c',
    'SELECT check_name, severity, observed, threshold, meaning FROM health_check ORDER BY severity, check_name;'],
    { encoding:'utf8' });
} catch (e) { console.error('ABORT: cannot query health_check'); process.exit(2); }

const rows = out.trim().split('\n').filter(Boolean).map(l => l.split('\u0001'));
if (!rows.length) { console.error('ABORT: health_check returned nothing'); process.exit(2); }

let breaches = 0;
console.log('\nHealth');
for (const [name, sev, observed, threshold, meaning] of rows) {
  const bad = Number(observed) > Number(threshold);
  if (bad) breaches++;
  console.log(`  ${bad ? 'BREACH' : '  ok  '}  ${sev.padEnd(8)} ${name.padEnd(28)} ${observed}`);
  if (bad) console.log(`          ${meaning}`);
}
console.log(`\n  ${rows.length} checks, ${breaches} breach(es)\n`);
process.exit(breaches ? 1 : 0);
