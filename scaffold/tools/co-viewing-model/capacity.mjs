#!/usr/bin/env node
// Co-viewing capacity + cost model. DESIGN-STAGE TOOL, not wired into verify.sh.
// Every number below is an ASSUMPTION or a quoted vendor figure; re-check before use.
//
// Sourced (docs.livekit.io/cloud/quotas-and-limits, fetched 2026-11-07):
//   Build plan: 5,000 WebRTC participant-min/month, 50 GB/month downstream, 100 concurrent participants.
// Secondary-source only (UNVERIFIED, third-party blogs): overage ~$0.0004/participant-min, ~$0.10-0.12/GB.
// Ship/Scale included amounts conflict between sources, so they are NOT modelled here.
//
// usage: node capacity.mjs [--mbps 1.5] [--hours 2] [--families 5] [--sessionsPerWeek 7]

const arg = (k, d) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > -1 ? Number(process.argv[i + 1]) : d;
};

const mbps = arg('mbps', 1.5);               // ASSUMED video bitrate delivered to the child
const hours = arg('hours', 2);               // length of one watch-along
const families = arg('families', 5);
const perWeek = arg('sessionsPerWeek', 7);

const BUILD = { participantMin: 5000, downstreamGB: 50 };
const RATE_MIN = 0.0004, RATE_GB_LO = 0.10, RATE_GB_HI = 0.12; // unverified

const gbPerHourPerViewer = (mbps * 3600) / 8 / 1000; // Mb/s -> MB/h -> GB/h

function scenario(name, { publishers, viewers, bitrate }) {
  const gbHr = (bitrate * 3600) / 8 / 1000;
  const partMin = (publishers + viewers) * hours * 60;
  const gb = viewers * gbHr * hours; // downstream only is metered per the quotas page
  return { name, partMin, gb };
}

const sessionsPerMonth = families * perWeek * (30 / 7);
const rows = [
  scenario('A. Screen-share: parent publishes, child views', { publishers: 1, viewers: 1, bitrate: mbps }),
  scenario('B. Synced local playback: data channel only (no media)', { publishers: 1, viewers: 1, bitrate: 0.001 }),
  scenario('C. Two-way face call alongside A (camera both ways, ~0.6 Mbps each)', { publishers: 1, viewers: 1, bitrate: mbps + 0.6 }),
];

console.log(`Assumptions: ${mbps} Mbps to child, ${hours} h/session, ${families} families x ${perWeek}/wk = ${sessionsPerMonth.toFixed(0)} sessions/month\n`);
for (const r of rows) {
  const monthMin = r.partMin * sessionsPerMonth;
  const monthGB = r.gb * sessionsPerMonth;
  const overMin = Math.max(0, monthMin - BUILD.participantMin);
  const overGB = Math.max(0, monthGB - BUILD.downstreamGB);
  const costLo = overMin * RATE_MIN + overGB * RATE_GB_LO;
  const costHi = overMin * RATE_MIN + overGB * RATE_GB_HI;
  const buildSessions = Math.floor(Math.min(BUILD.participantMin / r.partMin, r.gb ? BUILD.downstreamGB / r.gb : Infinity));
  console.log(r.name);
  console.log(`  per session: ${r.partMin} participant-min, ${r.gb.toFixed(2)} GB downstream`);
  console.log(`  Build plan fits ~${buildSessions} such sessions/month (binding limit: ${BUILD.participantMin / r.partMin < (r.gb ? BUILD.downstreamGB / r.gb : Infinity) ? 'participant-minutes' : 'bandwidth'})`);
  console.log(`  pilot month: ${monthMin.toFixed(0)} participant-min, ${monthGB.toFixed(1)} GB; metered overage vs Build allowance ~$${costLo.toFixed(2)}-$${costHi.toFixed(2)} (unverified rates, excludes any plan fee)\n`);
}
console.log(`Reference: 1 viewer-hour at ${mbps} Mbps = ${gbPerHourPerViewer.toFixed(3)} GB`);
