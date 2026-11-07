#!/usr/bin/env node
// Watch-together drift controller simulation. DESIGN-STAGE TOOL, not wired into verify.sh.
// Question it answers: with a leader (guardian) broadcasting {position, rate, sentAt} every
// TICK seconds over an unreliable-latency channel, does a follower (child device) converge
// and stay within tolerance, and does it ever have to hard-seek?
//
// Controller zones (starting points taken from community watch-party designs, tuned for a kid:
// we prefer a gentle speed nudge over a visible jump):
//   |err| <= DEAD            -> do nothing
//   DEAD < |err| <= SEEK     -> nudge playbackRate within [1-RATE_BAND, 1+RATE_BAND]
//   |err| > SEEK             -> hard seek (visible skip)
//
// usage: node sync-sim.mjs

const DEAD = 0.15, SEEK = 2.0, RATE_BAND = 0.05, TICK = 2, DURATION = 600;

function mulberry(a) { return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

function run({ startOffset, meanLatency, jitter, clockErr, loss, seed, pauseAt, skew = 0.005 }) {
  const rnd = mulberry(seed);
  let followerPos = -startOffset, followerRate = 1;
  let leaderPos = 0, paused = false;
  let latest = null, hardSeeks = 0, maxErrAfter30 = 0, convergedAt = null, errSum = 0, errN = 0;
  const inflight = [];
  const dt = 0.05, STEPS = Math.round(DURATION / dt), TICK_STEPS = Math.round(TICK / dt);
  for (let k = 0; k < STEPS; k++) {
    const t = k * dt;
    if (pauseAt && k === Math.round(pauseAt / dt)) paused = true;
    if (pauseAt && k === Math.round((pauseAt + 20) / dt)) paused = false;
    if (!paused) leaderPos += dt;
    if (k % TICK_STEPS === 0 && rnd() >= loss) {
      const lat = Math.max(0.01, meanLatency + (rnd() - 0.5) * 2 * jitter);
      inflight.push({ arriveAt: t + lat, pos: leaderPos, paused, trueLat: lat });
    }
    for (let i = inflight.length - 1; i >= 0; i--) if (inflight[i].arriveAt <= t) { latest = { ...inflight[i], rxAt: t }; inflight.splice(i, 1); }
    if (latest) {
      // follower estimates latency from a (possibly wrong) clock model
      const est = latest.trueLat + clockErr;
      const expected = latest.paused ? latest.pos : latest.pos + est + (t - latest.rxAt);
      const err = followerPos - expected; // + = ahead
      latest = { ...latest, _used: true };
      if (Math.abs(err) > SEEK) { followerPos = expected; followerRate = 1; hardSeeks++; }
      else if (Math.abs(err) > DEAD) followerRate = 1 - Math.max(-RATE_BAND, Math.min(RATE_BAND, err * 0.5));
      else followerRate = 1;
      if (latest.paused) followerRate = 0;
    }
    followerPos += dt * followerRate * (1 + skew); // follower's own clock runs slightly fast
    const trueErr = followerPos - leaderPos;
    if (t > 30) { maxErrAfter30 = Math.max(maxErrAfter30, Math.abs(trueErr)); errSum += Math.abs(trueErr); errN++; }
    if (convergedAt === null && Math.abs(trueErr) < 0.25 && t > 1) convergedAt = t;
  }
  return { hardSeeks, convergedAt: convergedAt?.toFixed(1), meanErrAfter30: (errSum / errN).toFixed(3), maxErrAfter30: maxErrAfter30.toFixed(3) };
}

const cases = [
  ['clean wifi, child joins 3 s late',          { startOffset: 3, meanLatency: 0.08, jitter: 0.03, clockErr: 0.0, loss: 0.0,  seed: 1 }],
  ['jittery wifi, joins 8 s late',               { startOffset: 8, meanLatency: 0.25, jitter: 0.2,  clockErr: 0.0, loss: 0.1,  seed: 2 }],
  ['cellular, 0.5 s clock misestimate',          { startOffset: 3, meanLatency: 0.4,  jitter: 0.3,  clockErr: 0.5, loss: 0.2,  seed: 3 }],
  ['guardian pauses for 20 s mid-show',          { startOffset: 1, meanLatency: 0.1,  jitter: 0.05, clockErr: 0.0, loss: 0.05, seed: 4, pauseAt: 120 }],
  ['bad: 40% tick loss, 1 s jitter',             { startOffset: 5, meanLatency: 0.5,  jitter: 1.0,  clockErr: 0.3, loss: 0.4,  seed: 5 }],
];
console.log(`controller: dead ${DEAD}s, seek >${SEEK}s, rate band +/-${RATE_BAND * 100}%, tick ${TICK}s, run ${DURATION}s\n`);
for (const [name, c] of cases) console.log(name.padEnd(40), JSON.stringify(run(c)));
