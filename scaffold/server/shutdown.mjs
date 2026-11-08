// OLIVE BRANCH — graceful shutdown (audit P-14). Side-effect-free: takes the
// pieces to close, so it is testable without a real process signal.
//
// THE BUG: server/index.mjs did `server.close(cb)` and waited for `cb`.
// http.Server.close() only stops ACCEPTING; it fires its callback once every
// existing connection has ended -- and an upgraded WebSocket (a network
// checkers table) never ends on its own, nor does an idle keep-alive socket.
// So SIGTERM never completed: the process sat there until the orchestrator's
// SIGKILL (docker's 10 s default), pool.end() never ran, and in-flight
// writes got no chance to finish.
//
// THE ORDER:
//   1. stop accepting (server.close), and close the game-table sockets with
//      1001 "going away" -- clients see a clean close, not a reset;
//   2. closeIdleConnections() right away (keep-alive sockets between
//      requests carry nothing worth waiting for);
//   3. give in-flight requests `deadlineMs` (default 8 s, < docker's 10 s
//      default and < the stop_grace_period docker-compose.prod.yml now sets)
//      to finish;
//   4. at the deadline closeAllConnections() -- whatever is left is cut;
//   5. pool.end() EXACTLY ONCE, then resolve.
// The handler is idempotent: a second SIGTERM/SIGINT while shutting down
// returns the same promise (never a second pool.end(), which would throw
// "Called end on pool more than once" into an unhandled rejection).

export const DEFAULT_SHUTDOWN_DEADLINE_MS = 8000;

/**
 * @param {{ server: import('node:http').Server,
 *           wss?: { clients: Set<any>, close: (cb?: ()=>void)=>void } | null,
 *           pool?: { end: ()=>Promise<void> } | null,
 *           stopTimers?: Array<()=>void>,
 *           deadlineMs?: number,
 *           log?: (line: string) => void }} o
 * @returns {() => Promise<void>}
 */
export function createShutdown({
  server, wss = null, pool = null, stopTimers = [],
  deadlineMs = DEFAULT_SHUTDOWN_DEADLINE_MS, log = () => {},
}) {
  let inFlight = null;
  return function shutdown(reason = 'signal') {
    if (inFlight) return inFlight;
    inFlight = (async () => {
      log(`shutdown: begin (${reason})`);
      for (const stop of stopTimers) { try { stop(); } catch { /* best effort */ } }

      const closed = new Promise((resolve) => server.close(() => resolve('closed')));
      if (wss) {
        for (const ws of wss.clients) {
          try { ws.close(1001, 'server_shutdown'); } catch { /* already gone */ }
        }
      }
      server.closeIdleConnections?.();

      let timer;
      const deadline = new Promise((resolve) => {
        timer = setTimeout(() => resolve('deadline'), deadlineMs);
        timer.unref?.();
      });
      const outcome = await Promise.race([closed, deadline]);
      clearTimeout(timer);
      if (outcome === 'deadline') {
        log(`shutdown: ${deadlineMs}ms deadline reached, cutting remaining connections`);
        // ws clients that ignored the close frame: terminate them hard.
        if (wss) for (const ws of wss.clients) { try { ws.terminate(); } catch { /* ignore */ } }
        server.closeAllConnections?.();
      }
      if (wss) await new Promise((resolve) => wss.close(() => resolve()));
      if (pool) {
        try { await pool.end(); }
        catch (e) { log(`shutdown: pool.end failed: ${e?.message ?? e}`); }
      }
      log('shutdown: complete');
    })();
    return inFlight;
  };
}
