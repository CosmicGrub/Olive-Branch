#!/usr/bin/env node
/**
 * OLIVE BRANCH — the delivery worker's container healthcheck (ISS-069).
 *
 * Exit 0 = the worker ticked and succeeded recently; exit 1 = it has stopped, hung or fails every
 * tick (reason on stderr). Reads the heartbeat file tools/scheduler.mjs deliver-loop writes (see
 * tools/worker_heartbeat.mjs) and nothing else: no database, no network, so it is cheap and still
 * answers when Postgres is the thing that is down.
 */
import { evaluateHeartbeat, heartbeatFileFromEnv, readHeartbeatFile } from './worker_heartbeat.mjs';

const v = evaluateHeartbeat(readHeartbeatFile(heartbeatFileFromEnv(process.env)), Date.now());
if (!v.healthy) { console.error(`delivery worker unhealthy: ${v.reason}`); process.exit(1); }
process.exit(0);
