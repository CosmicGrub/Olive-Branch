// OLIVE BRANCH - the signalling mailbox for the 'lan-p2p' call provider (MASTERFILE 16.2 #6, 5.19).
//
// Two devices set up a direct call by passing a few small messages (offer, answer, ICE candidates, bye, mode)
// through the server's AUTHENTICATED call routes. This is only the mailbox behind those routes: it never sees
// audio or video (that flows device to device, or through a TURN relay, never through here) and it stores nothing
// durable. It is a bounded in-memory queue per call session with a lifetime, so a restart simply ends open calls'
// setup (the call log row, written first, stays the record).
//
// Isolation is the route's job (it only reaches this after the session check proves the principal is one of the
// two participants of THAT child's call); this module additionally never lets one side read its own messages back
// and never mixes sessions. Bounds: 400 messages and 16 KiB per message, 256 live sessions, 10 minutes.
export const SIGNAL_KINDS = Object.freeze(['offer', 'answer', 'ice', 'restart', 'mode', 'bye']);
export const SIGNAL_ROLES = Object.freeze(['caller', 'callee']);

export function createSignalHub({
  maxPerSession = 400, maxBytes = 16 * 1024, ttlMs = 10 * 60 * 1000, maxSessions = 256,
  presenceTtlMs = 15 * 1000, now = () => Date.now(),
} = {}) {
  const sessions = new Map(); // id -> { createdAt, seq, msgs: [], waiters: Set<fn>, closed }
  const presence = new Map(); // childId -> lastSeenMs

  const wake = (s) => { for (const w of [...s.waiters]) w(); s.waiters.clear(); };
  const sweep = () => {
    const t = now();
    for (const [id, s] of sessions) if (t - s.createdAt > ttlMs) { wake(s); sessions.delete(id); }
    for (const [k, at] of presence) if (t - at > presenceTtlMs * 4) presence.delete(k);
  };
  const getOrMake = (id) => {
    let s = sessions.get(id);
    if (!s) {
      if (sessions.size >= maxSessions) sweep();
      if (sessions.size >= maxSessions) return null;
      s = { createdAt: now(), seq: 0, msgs: [], waiters: new Set(), closed: false };
      sessions.set(id, s);
    }
    return s;
  };

  return {
    /** { ok:true, seq } or { ok:false, error }. */
    post(sessionId, fromRole, kind, payload) {
      if (!SIGNAL_ROLES.includes(fromRole)) return { ok: false, error: 'bad_role' };
      if (!SIGNAL_KINDS.includes(kind)) return { ok: false, error: 'bad_kind' };
      if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) return { ok: false, error: 'bad_payload' };
      let size;
      try { size = Buffer.byteLength(JSON.stringify(payload)); } catch { return { ok: false, error: 'bad_payload' }; }
      if (size > maxBytes) return { ok: false, error: 'too_large' };
      const s = getOrMake(sessionId);
      if (!s) return { ok: false, error: 'busy' };
      if (s.closed) return { ok: false, error: 'closed' };
      if (s.msgs.length >= maxPerSession) return { ok: false, error: 'too_many' };
      s.seq += 1;
      s.msgs.push({ seq: s.seq, from: fromRole, kind, payload });
      if (kind === 'bye') s.closed = true;
      wake(s);
      return { ok: true, seq: s.seq };
    },
    /**
     * The messages the OTHER side sent after `after`. Waits up to waitMs (clamped to 8 s) for one to arrive, so a
     * poll costs one request per message, not one per tick. { messages, closed }.
     */
    async read(sessionId, forRole, after = 0, waitMs = 0) {
      const pick = () => {
        const s = sessions.get(sessionId);
        if (!s) return { messages: [], closed: false };
        const messages = s.msgs.filter((m) => m.seq > after && m.from !== forRole);
        return { messages, closed: s.closed };
      };
      const first = pick();
      const wait = Math.max(0, Math.min(8000, Number(waitMs) || 0));
      if (first.messages.length || first.closed || wait === 0) return first;
      const s = getOrMake(sessionId);
      if (!s) return first;
      await new Promise((resolve) => {
        const done = () => { clearTimeout(timer); s.waiters.delete(done); resolve(); };
        const timer = setTimeout(done, wait);
        s.waiters.add(done);
      });
      return pick();
    },
    /** Called when the call is ended through the end route: tells a waiting poll and refuses further posts. */
    close(sessionId) {
      const s = getOrMake(sessionId);
      if (s) { s.closed = true; wake(s); }
    },
    /** A child's device just asked about incoming calls: it is awake and reaching this server. */
    touchChild(childId) { presence.set(childId, now()); sweep(); },
    childRecentlySeen(childId) {
      const at = presence.get(childId);
      return at !== undefined && now() - at <= presenceTtlMs;
    },
    get size() { return sessions.size; },
  };
}
