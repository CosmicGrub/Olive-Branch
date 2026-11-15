/**
 * OLIVE BRANCH -- decides whether `tools/smoke-stack.mjs` may be pointed at a target.
 *
 * Why this is its own module: the smoke test WRITES rows (a family, guardians, an invite,
 * a message). Checking only the container names it was given is not enough, because
 * --base is what it actually talks to: `--base http://127.0.0.1:8130` with no containers,
 * or with the olive-fresh containers, would still write into whatever listens on 8130.
 * So the check starts from the PORT: which container publishes it, is that one protected,
 * and are the containers the operator named really that server and its own database.
 * Pure (a container listing in, a verdict out) so it is tested without Docker.
 *
 * Fail closed: if the listing could not be read, or the target cannot be shown to be a
 * test stack, the answer is "refuse" unless the operator passes the explicit override.
 */

/** The owner's long-lived stacks. The smoke test must never write to them. */
export const PROTECTED = [/^olive-live/, /^olive-sim/, /^wt-sec3/, /^olive-healthrls/, /^olive-prod/, /^jitsi/];
export const isProtectedName = (name) => PROTECTED.some((re) => re.test(String(name)));

const LOOPBACK = new Set(['127.0.0.1', 'localhost', '[::1]', '::1']);

/** Host port numbers out of a `docker ps` Ports column ("0.0.0.0:8123->8000/tcp, [::]:8123->8000/tcp"). */
export function publishedHostPorts(portsField) {
  const out = new Set();
  for (const part of String(portsField ?? '').split(',')) {
    const m = /:(\d+)(?:-(\d+))?->/.exec(part.trim());
    if (!m) continue;
    const lo = Number(m[1]), hi = m[2] ? Number(m[2]) : lo;
    for (let p = lo; p <= hi && p - lo < 1000; p++) out.add(p);
  }
  return out;
}

/** `docker ps --format '{{.Names}}\t{{.Ports}}\t{{.Label "com.docker.compose.project"}}'` output -> rows. */
export function parseDockerListing(text) {
  return String(text ?? '').split(/\r?\n/).filter(Boolean).map((line) => {
    const [name = '', ports = '', project = ''] = line.split('\t');
    return { name: name.trim(), ports, project: project.trim() };
  }).filter((r) => r.name);
}

/**
 * @param {{ base: string, dbContainer?: string, serverContainer?: string,
 *           containers: ({name:string, ports:string, project?:string}[] | null),
 *           override?: boolean }} o   containers === null means "could not list them"
 * @returns {{ ok: boolean, problems: string[], publisher: string|null }}
 */
export function judgeSmokeTarget({ base, dbContainer = '', serverContainer = '', containers, override = false }) {
  const problems = [];
  let url;
  try { url = new URL(base); } catch { return { ok: false, publisher: null, problems: [`--base is not a URL: ${base}`] }; }
  const port = Number(url.port || (url.protocol === 'https:' ? 443 : 80));
  const loopback = LOOPBACK.has(url.hostname);

  // The names the operator gave, protected or not.
  for (const n of [dbContainer, serverContainer].filter(Boolean)) {
    if (isProtectedName(n)) problems.push(`container "${n}" belongs to a long-lived stack`);
  }

  if (containers === null) {
    problems.push('could not list running containers, so the target cannot be shown to be a test stack');
  } else {
    const publishers = containers.filter((c) => publishedHostPorts(c.ports).has(port));
    for (const p of publishers) {
      if (isProtectedName(p.name)) problems.push(`--base port ${port} is published by "${p.name}", a long-lived stack`);
    }
    const byName = new Map(containers.map((c) => [c.name, c]));
    if (serverContainer) {
      const s = byName.get(serverContainer);
      if (!s) problems.push(`--server-container "${serverContainer}" is not running`);
      else if (!publishedHostPorts(s.ports).has(port)) {
        problems.push(`--server-container "${serverContainer}" does not publish --base port ${port}`
          + (publishers.length ? ` (that port belongs to "${publishers.map((p) => p.name).join('", "')}")` : ''));
      }
    }
    if (dbContainer) {
      const d = byName.get(dbContainer);
      if (!d) problems.push(`--db-container "${dbContainer}" is not running`);
      else {
        // Its own database: same compose project as whatever answers on --base. Unknown labels fail closed.
        const anchor = serverContainer ? byName.get(serverContainer) : publishers[0];
        if (!anchor) problems.push(`--db-container "${dbContainer}" cannot be tied to the server on port ${port}`);
        else if (!d.project || !anchor.project || d.project !== anchor.project) {
          problems.push(`--db-container "${dbContainer}" is not in the same compose project as "${anchor.name}"`);
        }
      }
    }
    // A port match only means something on THIS machine: a remote host that happens to use a
    // local container's port is not that container. Anything not on loopback cannot be shown to
    // be a test stack. (A native server on a free loopback port is allowed: nothing protected
    // publishes it.)
    if (!loopback) {
      problems.push(`--base host "${url.hostname}" is not this machine, so it cannot be shown to be a test stack`);
    }
  }

  const publisher = containers ? (containers.find((c) => publishedHostPorts(c.ports).has(port))?.name ?? null) : null;
  if (override && problems.length) return { ok: true, publisher, problems: problems.map((p) => `overridden: ${p}`) };
  return { ok: problems.length === 0, problems, publisher };
}
