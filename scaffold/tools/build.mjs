// OLIVE BRANCH — build every TS package to its sibling .mjs, one esbuild
// call per entry. Replaces the single 75-step "&&" chain package.json used to
// carry, which had grown past Windows cmd.exe's 8191-character command-line
// limit (npm runs scripts through cmd.exe there) — the chain was one entry
// from breaking and the jokebook package was that entry. Linux/CI never hit
// the limit, so this changes nothing about what CI builds; it only stops the
// next package from breaking local verification on Windows.
//
// Each row below is the exact argument list its esbuild CLI step used to
// carry, verbatim, so the two are auditable side by side; `toOptions()`
// maps only the flags that list actually uses and refuses anything else, so
// a new flag can never be silently dropped. Add a package by adding a row.
import { build } from "esbuild";

const ENTRIES = [
  ["--format=esm","--platform=node","packages/time-engine/src/time.ts","--outfile=packages/time-engine/src/time.mjs"],
  ["--format=esm","--platform=node","packages/delivery-engine/src/materialize.ts","--outfile=packages/delivery-engine/src/materialize.mjs"],
  ["--format=esm","--platform=node","packages/delivery-engine/src/gate.ts","--outfile=packages/delivery-engine/src/gate.mjs"],
  ["--format=esm","--platform=node","packages/family-graph/src/authorize.ts","--outfile=packages/family-graph/src/authorize.mjs"],
  ["--format=esm","--platform=node","packages/family-graph/src/session.ts","--outfile=packages/family-graph/src/session.mjs"],
  ["--format=esm","--platform=node","packages/session-runtime/src/rooms.ts","--outfile=packages/session-runtime/src/rooms.mjs"],
  ["--format=esm","--platform=node","packages/session-runtime/src/livekit-token.ts","--outfile=packages/session-runtime/src/livekit-token.mjs"],
  ["--format=esm","--platform=node","packages/child-lock/src/lock.ts","--outfile=packages/child-lock/src/lock.mjs"],
  ["--format=esm","--platform=node","packages/messaging/src/pipeline.ts","--outfile=packages/messaging/src/pipeline.mjs"],
  ["--format=esm","--platform=node","packages/auth/src/auth.ts","--outfile=packages/auth/src/auth.mjs"],
  ["--format=esm","--platform=node","packages/storage/src/retention.ts","--outfile=packages/storage/src/retention.mjs"],
  ["--format=esm","--platform=node","packages/storage/src/storage.ts","--outfile=packages/storage/src/storage.mjs"],
  ["--format=esm","--platform=node","packages/api/src/api.ts","--outfile=packages/api/src/api.mjs"],
  ["--format=esm","--platform=node","packages/transport/src/push.ts","--outfile=packages/transport/src/push.mjs"],
  ["--format=esm","--platform=node","packages/transport/src/fcm.ts","--outfile=packages/transport/src/fcm.mjs"],
  ["--format=esm","--platform=node","packages/transport/src/apns.ts","--outfile=packages/transport/src/apns.mjs"],
  ["--format=esm","--platform=node","packages/transport/src/notify.ts","--outfile=packages/transport/src/notify.mjs"],
  ["packages/homework/src/capture.ts","--format=esm","--platform=node","--outfile=packages/homework/src/capture.mjs"],
  ["packages/homework/src/snapshot.ts","--format=esm","--platform=node","--outfile=packages/homework/src/snapshot.mjs"],
  ["packages/homework/src/measure.ts","--format=esm","--platform=node","--outfile=packages/homework/src/measure.mjs"],
  ["packages/homework/src/hints.ts","--format=esm","--platform=node","--outfile=packages/homework/src/hints.mjs"],
  ["packages/homework/src/split.ts","--format=esm","--platform=node","--outfile=packages/homework/src/split.mjs"],
  ["packages/homework/src/capture-route.ts","--format=esm","--platform=node","--outfile=packages/homework/src/capture-route.mjs"],
  ["packages/custody/src/schedule.ts","--format=esm","--platform=node","--outfile=packages/custody/src/schedule.mjs"],
  ["--format=esm","--platform=node","packages/annotation/src/canvas.ts","--outfile=packages/annotation/src/canvas.mjs"],
  ["--format=esm","--platform=node","packages/care/src/care.ts","--outfile=packages/care/src/care.mjs"],
  ["--format=esm","--platform=node","packages/agency/src/agency.ts","--outfile=packages/agency/src/agency.mjs"],
  ["--format=esm","--platform=node","packages/ledger/src/sha256.ts","--outfile=packages/ledger/src/sha256.mjs"],
  ["--format=esm","--platform=node","packages/ledger/src/ledger.ts","--outfile=packages/ledger/src/ledger.mjs"],
  ["--format=esm","--platform=node","packages/archive/src/archive.ts","--outfile=packages/archive/src/archive.mjs"],
  ["--format=esm","--platform=node","packages/phase3/src/phase3.ts","--outfile=packages/phase3/src/phase3.mjs"],
  ["packages/games/src/games.ts","--format=esm","--platform=node","--outfile=packages/games/src/games.mjs"],
  ["packages/games/src/games2.ts","--format=esm","--platform=node","--outfile=packages/games/src/games2.mjs"],
  ["packages/games/src/games2.ts","--bundle","--external:./games.ts","--format=esm","--platform=node","--outfile=packages/games/src/games2.mjs"],
  ["packages/games/src/games3.ts","--format=esm","--platform=node","--outfile=packages/games/src/games3.mjs"],
  ["packages/games/src/favorites.ts","--format=esm","--platform=node","--outfile=packages/games/src/favorites.mjs"],
  ["packages/live/src/live.ts","--format=esm","--platform=node","--outfile=packages/live/src/live.mjs"],
  ["packages/showcase/src/showcase.ts","--format=esm","--platform=node","--outfile=packages/showcase/src/showcase.mjs"],
  ["packages/onboarding/src/onboarding.ts","--format=esm","--platform=node","--outfile=packages/onboarding/src/onboarding.mjs"],
  ["packages/palette/src/palette.ts","--format=esm","--platform=node","--outfile=packages/palette/src/palette.mjs"],
  ["packages/calendar/src/calendar.ts","--format=esm","--platform=node","--outfile=packages/calendar/src/calendar.mjs"],
  ["packages/storyteller/src/storyteller.ts","--format=esm","--platform=node","--outfile=packages/storyteller/src/storyteller.mjs"],
  ["--format=esm","--platform=node","packages/activities/src/activities.ts","--outfile=packages/activities/src/activities.mjs"],
  ["--format=esm","--platform=node","packages/session-runtime/src/security.ts","--outfile=packages/session-runtime/src/security.mjs"],
  ["--format=esm","--platform=node","packages/storyteller/src/library.ts","--outfile=packages/storyteller/src/library.mjs"],
  ["--format=esm","--platform=node","packages/showcase/src/exchange.ts","--outfile=packages/showcase/src/exchange.mjs"],
  ["--format=esm","--platform=node","packages/guardian/src/guardian.ts","--outfile=packages/guardian/src/guardian.mjs"],
  ["--format=esm","--platform=node","packages/live/src/around.ts","--outfile=packages/live/src/around.mjs"],
  ["--format=esm","--platform=node","packages/maturation/src/maturation.ts","--outfile=packages/maturation/src/maturation.mjs"],
  ["--format=esm","--platform=node","packages/maturation/src/rungs.ts","--outfile=packages/maturation/src/rungs.mjs"],
  ["--format=esm","--platform=node","packages/maturation/src/family.ts","--outfile=packages/maturation/src/family.mjs"],
  ["--format=esm","--platform=node","packages/a11y/src/a11y.ts","--outfile=packages/a11y/src/a11y.mjs"],
  ["--format=esm","--platform=node","packages/offline/src/offline.ts","--outfile=packages/offline/src/offline.mjs"],
  ["--format=esm","--platform=node","packages/i18n/src/i18n.ts","--outfile=packages/i18n/src/i18n.mjs"],
  ["--format=esm","--platform=node","packages/print/src/print.ts","--outfile=packages/print/src/print.mjs"],
  ["--format=esm","--platform=node","packages/observer/src/observer.ts","--outfile=packages/observer/src/observer.mjs"],
  ["--format=esm","--platform=node","packages/toddler/src/toddler.ts","--outfile=packages/toddler/src/toddler.mjs"],
  ["--format=esm","--platform=node","packages/emergency/src/emergency.ts","--outfile=packages/emergency/src/emergency.mjs"],
  ["--format=esm","--platform=node","packages/school/src/school.ts","--outfile=packages/school/src/school.mjs"],
  ["--format=esm","--platform=node","packages/globalaudit/src/globalaudit.ts","--outfile=packages/globalaudit/src/globalaudit.mjs"],
  ["--format=esm","--platform=node","packages/devices/src/devices.ts","--outfile=packages/devices/src/devices.mjs"],
  ["--format=esm","--platform=node","packages/transport/src/channels.ts","--outfile=packages/transport/src/channels.mjs"],
  ["--format=esm","--platform=node","packages/devices/src/postures.ts","--outfile=packages/devices/src/postures.mjs"],
  ["--format=esm","--platform=node","packages/guardian/src/pending.ts","--outfile=packages/guardian/src/pending.mjs"],
  ["--format=esm","--platform=node","packages/live/src/modes.ts","--outfile=packages/live/src/modes.mjs"],
  ["--format=esm","--platform=node","packages/live/src/camera.ts","--outfile=packages/live/src/camera.mjs"],
  ["--format=esm","--platform=node","packages/live/src/lifecycle.ts","--outfile=packages/live/src/lifecycle.mjs"],
  ["--format=esm","--platform=node","packages/live/src/pane.ts","--outfile=packages/live/src/pane.mjs"],
  ["--format=esm","--platform=node","packages/signal/src/signal.ts","--outfile=packages/signal/src/signal.mjs"],
  ["--format=esm","--platform=node","packages/a11y/src/matrix.ts","--outfile=packages/a11y/src/matrix.mjs"],
  ["--format=esm","--platform=node","packages/motion/src/motion.ts","--outfile=packages/motion/src/motion.mjs"],
  ["--format=esm","--platform=node","packages/live/src/stream.ts","--outfile=packages/live/src/stream.mjs"],
  ["--format=esm","--platform=node","packages/budget/src/budget.ts","--outfile=packages/budget/src/budget.mjs"],
  ["--format=esm","--platform=node","--packages=external","packages/db/src/pool.ts","--outfile=packages/db/src/pool.mjs"],
  ["--format=esm","--platform=node","packages/auth/src/attestation.ts","--outfile=packages/auth/src/attestation.mjs"],
  ["--format=esm","--platform=node","packages/jokes/src/jokes.ts","--outfile=packages/jokes/src/jokes.mjs"],
];

function toOptions(args) {
  const o = { entryPoints: [], format: undefined, platform: undefined, outfile: undefined,
    bundle: false, external: [], packages: undefined, logLevel: "warning" };
  for (const a of args) {
    if (a.startsWith("--format=")) o.format = a.slice(9);
    else if (a.startsWith("--platform=")) o.platform = a.slice(11);
    else if (a.startsWith("--outfile=")) o.outfile = a.slice(10);
    else if (a === "--bundle") o.bundle = true;
    else if (a.startsWith("--external:")) o.external.push(a.slice(11));
    else if (a.startsWith("--packages=")) o.packages = a.slice(11);
    else if (!a.startsWith("-")) o.entryPoints.push(a);
    else throw new Error("tools/build.mjs: unrecognised esbuild flag " + a + " — add it to toOptions()");
  }
  if (o.external.length === 0) delete o.external;
  if (o.packages === undefined) delete o.packages;
  return o;
}

let failed = 0;
for (const args of ENTRIES) {
  try { await build(toOptions(args)); }
  catch (e) { failed++; console.error("build failed for", args.join(" "), "\n", e.message); }
}
if (failed) { console.error(failed + " build step(s) failed"); process.exit(1); }
