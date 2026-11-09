# Server snoop hardening: threat model and design

Date: 2026-11-08. Status: DRAFT, implemented in the same PR.

Owner requirement (verbatim): "i also want the server to build in security
against those that may try to peek into the games and the network that the app
connected to."

Scope: the Node server (`scaffold/server/*`), the packages it mounts, the
deployment files, and the Flutter client's server-facing layer
(`api_client.dart` and a new transport-policy file). Out of scope: the
device-to-device local-play stack (another agent owns it); this document only
fixes the interface the server-side relay must stay compatible with.

## 1. Assets

| Asset | Why it matters |
| --- | --- |
| A1 Game state and moves, including hidden hands | A child's play is private; a relay that can read a hand can cheat or profile |
| A2 Social graph and timing: who plays with whom, when, how long | Reveals custody pattern, routine, which sibling is at which house |
| A3 The family's network identity: IP, SSID, BSSID, LAN addresses, location inferable from IP or timing | Locates a child; identifies a household across sessions |
| A4 Session tokens, device credentials, join tokens, pairing codes | Bearer material; theft is impersonation |
| A5 Co-view position and content choice (what a child is watching or reading) | Behavioural data about a child |

## 2. Attackers

| Id | Attacker | Capability |
| --- | --- | --- |
| T1 | Passive or active observer on the child's or grown-up's Wi-Fi or cellular | Sniff, MITM, rogue AP, captive portal, TLS strip, DNS spoof |
| T2 | Curious or malicious party on the same LAN | Read or tamper with traffic, ARP spoof, mDNS listen |
| T3 | Compromised or curious operator, DB reader, log reader, backup reader | Reads rows, logs, metrics, heap, backups |
| T4 | Another authenticated user (another family) | Valid session, guesses ids, replays tokens |
| T5 | Internet scanner | Fingerprints the server, enumerates, brute forces unauthenticated surface |

## 3. Findings today (file:line on `origin/main` ced056f)

Severity: H = breaks a stated asset, M = weakens it, L = hygiene.

### Transport (T1, T2, T5)

- F-01 (H) The server only speaks plain HTTP and plain WS. `index.mjs:277`
  (`createServer` from `node:http`), `index.mjs:414` (`server.listen`).
  `docker-compose.prod.yml:88-95` states there is no TLS terminator and
  nothing enforces that one exists. A deployment can go live in cleartext and
  the process will not notice.
- F-02 (M) No HSTS, no `frame-ancestors`/`X-Frame-Options`, no
  `Referrer-Policy`, no `Content-Security-Policy` on API responses.
  `index.mjs:303` sets only `cache-control: no-store` and `nosniff`.
  Signed media (`signed_media.mjs:84-90`) sets `private, max-age=300` and
  `nosniff` only.
- F-03 (M) `TRUST_PROXY=1` trusts only the rightmost `X-Forwarded-For` entry
  (`rate_limit.mjs:109-117`). That is correct for exactly one proxy hop and
  wrong for two (CDN plus ingress): every client behind the CDN then shares the
  CDN's address bucket. There is no hop count, no IP syntax validation, and
  `X-Forwarded-Proto` is never consulted, so the server cannot tell whether a
  request really arrived over TLS.
- F-04 (M) CORS is closed only by omission. Nothing asserts it, so a later
  middleware could open it unnoticed. No `OPTIONS` test exists.
- F-05 (L) The client may point at any base URL, including cleartext to a
  public host, in release builds. `networked_checkers_lobby_screen.dart:34`
  defaults to `http://10.0.2.2:8080` with a free-text field; the original
  disclosure is `CHANGELOG.md:7904`. The Android manifest sets no
  `networkSecurityConfig` (`client/android/app/src/main/AndroidManifest.xml`),
  and Dart's `dart:io` ignores that file anyway, so a Dart-level guard is
  required in addition to the XML.
- F-06 (M) No certificate or public-key pinning anywhere in the client
  (`api_client.dart:135`: bare `http.Client()`). A user-installed or
  compromised CA lets T1 read every request including session refresh.

### Game confidentiality (T1, T3, T4)

- F-10 (H, latent) The only server-relayed play today is checkers over
  `game_tables.mjs`. The relay parses every move (`game_tables.mjs:388`,
  `table.ts:parseClientMessage`) and forwards plaintext coordinates
  (`game_tables.mjs:402`). That is acceptable for an open board, but there is
  no sealed mode, so any future game with a hidden hand (Uno, Go Fish) built on
  this relay would be fully readable by the operator and by anyone with a
  memory dump. Co-view (`packages/co-view/src/coview.ts`) is pure logic with no
  transport yet; its messages (position, rate, content id) would be plaintext
  on the same relay.
- F-11 (M) The WebSocket join token travels in the URL query string
  (`game_tables.mjs:248`, `url.searchParams.get('token')`). Reverse proxies and
  CDNs log URLs by default, so the bearer ends up in third-party logs. A
  subprotocol or first-frame carrier does not appear in request logs.
- F-12 (M) Existence oracle on table ids: `join` answers 404
  `table_not_found` for an unknown id, 409 `table_not_pending` for a known
  non-pending one and 403 `not_a_participant` for a known one that is not the
  caller's (`game_tables.mjs:187-201`). Ids are 192-bit random so enumeration
  is infeasible, but the three shapes still tell a holder of a leaked id
  whether it is live. Make unknown, not-yours and not-pending indistinguishable.
- F-13 (L) `ws` is created with no `Origin` policy
  (`game_tables.mjs:319`). Not exploitable today (the join token is required
  and is not ambient), recorded so a future cookie-based path is not added
  without one.

### Network identity (T3)

- F-20 (M) `clientIp()` returns the raw address (`rate_limit.mjs:108-117`) and
  both limiters use it as a map key (`rate_limit.mjs:89,97`). Nothing is
  persisted, but raw addresses sit in process memory for the life of the
  process, and so in any heap snapshot or core dump. Rate limiting does not
  need the address, only a stable pseudonym for the current window.
- F-21 (L) The access log is already free of addresses and query strings
  (`observability.mjs:30-35`), which is correct. But error paths print whole
  error objects: `index.mjs:404` (`console.error(e)`), `index.mjs:331`
  (`healthz: database unreachable` with the pg error) and
  `routes.mjs:443,1395,1403,1515`. pg errors carry the failing statement's
  `detail` (it can contain key values such as ids). No structured redaction.
- F-22 (L) No test stops a future migration or request schema from
  introducing an `ip`, `ssid`, `bssid`, `mac`, `hostname`, `lan_address` or
  geolocation column or accepted body key. Today none exists (checked all
  migrations through 0044 and every `c.body` read in `routes.mjs`).
- F-23 (M) `/internal/metrics` is gated by loopback plus the absence of
  `x-forwarded-for`, `forwarded` and `x-real-ip` (`observability.mjs:93`).
  A proxy that terminates TLS on the same host and does not stamp those headers
  (or stamps a different one, such as `cf-connecting-ip`, `x-forwarded-proto`,
  `via`) would make it publicly reachable. Content is aggregate-only (route
  templates, counts, pool sizes), so impact is low, but the gate should fail
  closed on any proxy marker and the docs must tell operators to block
  `/internal/` at the edge.

### Anti-snooping at the API (T4, T5)

- F-30 (L) `/healthz` returns different bodies for up and down
  (`{"status":"ok"}` vs `{"status":"db_unreachable"}`, `index.mjs:332`),
  which tells an unauthenticated caller about database state. The status code
  must stay 503 (the CI smoke job and Docker healthchecks key on it), but the
  body can be a fixed generic shape.
- F-31 (L) 401 bodies name the reason (`no_session` vs `expired` vs
  `bad_signature`, `api.ts:435-438`). Acceptable (the client needs `expired`
  to refresh) and not an oracle for another user's data. Documented, not
  changed.
- F-32 (ok) Verified good, tests kept or added: constant-time compares for
  session MAC (`auth.ts:294`), device credential (`pool.ts:4790`), join token
  (`table.ts:224`), PIN (`auth.ts:62`); device credential stored as SHA-256 only
  (`pool.ts:4782`); revoked-device check on every request (`api.ts:451`);
  wrong-child 403 is the same for existing and non-existing child ids
  (`api.ts:474`); webauthn challenge uniform (`index.mjs:128-150`); unknown
  method on a known path is a generic 404 (`api.ts:400`); no `Server` or
  `X-Powered-By` banner (raw `node:http`).
- F-33 (L) Pairing redeem answers distinct 404/410/403/423/409 by reason
  (`routes.mjs:848-858`). Distinguishing needs a live code in hand and the
  global miss budget (`rate_limit.mjs:137`) caps guessing at 20/min, so the
  oracle is not exploitable beyond what the legitimate user sees. Accepted and
  documented; the 6-digit code stays single-use with a short TTL.

### Defence in depth (T3)

- F-40 (M) No boot-time assertion about the deployment shape. A production
  process with no TLS terminator, `TRUST_PROXY` unset behind a proxy, or a
  `DATABASE_URL` to a remote host without TLS will start and serve
  (`index.mjs:36-55` checks only `DEV_LOGIN` and secrets).
- F-41 (ok) RLS stays forced (migrations 0039-0044), the app connects as
  `app_owner` NOSUPERUSER NOBYPASSRLS, migrations run unprivileged
  (`tools/test/migrate_nonsuper.test.mjs`). No change; the new tests do not
  alter this.

## 4. Design

### 4.1 Transport

The server does not terminate TLS. Production is a reverse proxy
(`docs/operators/proxy-and-tls.md` gives Caddy and nginx examples) in front of
loopback-bound port 8123. The server therefore enforces what it can:

- `server/transport.mjs` (pure, injectable env):
  - `checkBootTransport(env)` returns `{problems, warnings}`. When
    `NODE_ENV=production`: require `PUBLIC_BASE_URL` to be `https://` (host
    only, no path), require `TRUST_PROXY=1` and a `TRUST_PROXY_HOPS` integer
    1-4, and when `DATABASE_URL` has a non-local host, require
    `sslmode=verify-full|verify-ca`. `ALLOW_INSECURE_TRANSPORT=1` downgrades
    the transport problems to warnings; the compose file pins it to the literal
    `"0"` (like `DEV_LOGIN`). CI's image smoke test has no
    `NODE_ENV`, so it is unaffected.
  - `requestIsSecure(req, env)`: with `TRUST_PROXY=1`, true only when the
    `X-Forwarded-Proto` entry that the Nth-from-right proxy added is `https`;
    without it, true only for a loopback socket in dev.
  - In production every request that is not `requestIsSecure` (except
    `/healthz`, which the in-container probe calls on loopback) is answered
    refused. A `308` redirect is wrong for an API (a client would re-send the
    POST body and its bearer token), so the answer is a generic
    `400 {"error":"https_required"}` and a metric increment. The exemptions
    are the in-container probes: a direct loopback request with no proxy header
    to `/healthz` or `/internal/metrics`. Plain HTTP is never served content.
  - `SECURITY_HEADERS`: `strict-transport-security: max-age=63072000;
    includeSubDomains` (preload only when the operator sets
    `HSTS_PRELOAD=1`, because preload is irreversible for a domain),
    `x-content-type-options: nosniff`, `x-frame-options: DENY`,
    `referrer-policy: no-referrer`, `content-security-policy:
    default-src 'none'; frame-ancestors 'none'`,
    `cross-origin-resource-policy: same-site`, `permissions-policy:
    interest-cohort=(), geolocation=(), camera=(), microphone=()`,
    `cache-control: no-store` (media keeps its own `private, max-age=300`).
    HSTS is sent only on requests that are `requestIsSecure`.
  - CORS: no `access-control-*` header is ever sent; `OPTIONS` is a generic
    404. A test asserts it, so opening CORS is a deliberate, reviewed change.
- Client: `lib/server_transport_policy.dart` (pure Dart, unit-tested):
  - `OliveTransportPolicy.checkBaseUrl(Uri, {release})` rejects `http` unless
    the host is loopback, `10.0.2.2` or `localhost` AND the build is not
    release. A release build refuses cleartext to every host including
    loopback (loopback is only for debug).
  - `PinSet`: SPKI SHA-256 pins, at least one primary and one backup in a
    release build. dart:io exposes only the LEAF certificate of a connection, so
    pins name the server's leaf key (not an intermediate); certificates are
    renewed with the same key and a key change goes through the backup-pin
    procedure. Pinning is off for dev base URLs. A release build with pinning
    requested and fewer than two well-formed pins refuses every request
    (fails closed). Pin values are not invented here: they are injected with
    `--dart-define=OLIVE_API_PINS=pin1,pin2` at build time (decision D-2).
  - `createPinnedClient(...)` wires the verification into an `HttpClient`
    through `connectionFactory` and a post-handshake check before any bytes are
    written (see 4.1.1). `OliveTransport.clientFor(baseUrl)` is the one place
    `api_client.dart` and `auth_session.dart` get their default client.
  - Android `network_security_config.xml` (main: cleartext off, system CAs
    only, user CAs not trusted) and a debug-only override that permits
    `localhost` and `10.0.2.2`.

4.1.1 Why a post-handshake check: `badCertificateCallback` only fires for
certificates that already failed validation, so it cannot implement pinning on
a valid chain. The pinned client uses `HttpClient.connectionFactory` to open a
`SecureSocket` (the SDK uses a factory's socket as-is for direct https, which
was checked in `http_impl.dart`), read `peerCertificate`, compare the SPKI hash
and destroy the socket on mismatch before the request is written. Chain-level
verification and hostname checks by the platform still run first. A unit test
proves it against a real local TLS server: on a mismatch the server's request
counter stays at zero.

### 4.2 Game confidentiality: the sealed relay envelope

Principle: for any server-relayed play or co-view, the server is a dumb,
authenticated courier of opaque bytes. Keys are created on the two devices
(from the pairing PAKE output, `tools/pake_cpace.mjs`, plus a per-room salt)
and never sent to the server. The server cannot read moves, hands, positions
or content ids.

Envelope (`packages/game-sync/src/relay_envelope.ts`, version 1):

```
{ "v": 1, "t": "sealed", "seq": <uint32>, "ct": "<base64url>" }
```

- Exactly these four keys. Any other key (`move`, `from`, `to`, `hand`,
  `card`, `seat`, `pos`, `contentId`, ...) is rejected: the envelope has no
  plaintext field at all except routing (`v`, `t`, `seq`). The server adds
  `dir` (its own seat number) on the way out, the client never declares it.
- Room id is a capability: `t_` plus 24 random bytes (existing `newTableId`),
  never derived from any user or child id (T1 in `table.ts`), and a room is
  reachable only with a single-use, seat-bound, 3-minute join token.
- Size buckets: `ct` decodes to exactly 256, 1024 or 4096 bytes (padding is
  inside the AEAD plaintext, added by the sender). Anything else is rejected.
  A fixed bucket hides message type and move size from the operator and from a
  passive observer of the TLS record sizes.
- Per-direction sequence: `seq` must be strictly greater than the previous
  `seq` from that seat; replays and reorders are dropped (close 1008). The
  server tracks only the last number, not content. The receiving client binds
  `seq`, `dir` and the room id into the AEAD associated data, so a relay that
  rewrites `seq` or swaps directions produces an authentication failure
  on the receiving device.
- AEAD interface (compatible in spirit with the local-play framing): XChaCha20-
  Poly1305 or AES-256-GCM, 96-bit nonce = 32-bit direction || 64-bit counter,
  associated data = `"olive-relay-v1" || roomId || dir || seq`, key = HKDF of
  the pairing secret with the room id as salt, and a fresh key per room so a
  nonce can never repeat across rooms. The counter equals `seq`.
- Plaintext tripwire: the server decodes `ct` and rejects bytes that are valid
  JSON, valid UTF-8 text or more than 85% printable ASCII. True ciphertext
  fails that test with probability about 2^-190 for 256 bytes; a client bug that
  sends padded JSON fails it immediately. This is a tripwire, not a proof of
  encryption (a server cannot prove that), and it is documented as such.
- TTL: a room dies at the existing 60-minute ceiling and 3-minute join
  window (`table.ts` T5/T7). No persistence: sealed rooms never touch
  Postgres or disk, and no envelope is logged. The access log records route
  templates only (`observability.mjs`), and a test pins that no body or
  query reaches the log.
- A table is created `sealed` by creating it with `game: "sealed-v1"`. A sealed
  table accepts only `t: "sealed"` frames, and a checkers table accepts only
  `move` frames: no mixed modes, so a downgrade cannot be forced mid-room.

Legacy checkers stays on its plaintext `move` relay (the board is public and
the shipped client speaks it). It is documented as the only plaintext game and
cannot be used for hidden-hand games: a test asserts `SUPPORTED_GAMES` maps each
game to exactly one mode.

Co-view will use `sealed-v1` rooms; the control messages in `coview.ts` become
the AEAD plaintext. Nothing in this PR changes `coview.ts`.

### 4.3 Network-identity minimisation

- `server/netid.mjs`: `anonKey(req, env, now)` returns
  `HMAC-SHA256(saltOfTheDay, normalisedAddress)` truncated to 16 bytes, base64url.
  The salt is 32 random bytes generated at boot and rotated every 24 hours
  (a rotation simply resets the rate-limit buckets, which a restart already
  does; the salt is never written anywhere). IPv4 keeps /32, IPv6 is reduced to its /64. Limiters
  (`rate_limit.mjs`) take this key, never the address; the address never
  becomes a string that outlives the request handler.
- `clientIp` is replaced by `peerAddress(req, env)` with proper hop counting:
  with `TRUST_PROXY=1` and `TRUST_PROXY_HOPS=N` the address is the entry N
  from the right, syntax-validated with `net.isIP`; fewer entries than hops, or
  an invalid entry, falls back to the socket address (so a spoofed header
  can only ever hurt the spoofer's own bucket). The old single-hop behaviour is
  the default for `TRUST_PROXY=1` with `TRUST_PROXY_HOPS` unset (N=1).
- No address, hostname, SSID, BSSID, MAC or LAN address is accepted in any
  request body: `server/test/network_identity_sweep.test.mjs` walks every
  registered route's source for `c.body.<key>` reads and every migration for
  column names, and fails on a denylist (`ip`, `ip_address`, `ssid`, `bssid`,
  `mac`, `hostname`, `lan_ip`, `latitude`, `longitude`, `geo`, `wifi`,
  `network_name`). At runtime `api.handle` rejects, with a generic 400 and
  before the handler runs, any JSON body containing such a key at any depth
  (extends the child-payload sweep idea to requests).
- No reverse DNS, no GeoIP: asserted by a source sweep (no `dns`, `geoip`,
  `maxmind` import in `server/` or `packages/`).
- Logging: `safeLog.mjs` provides `errorLine(err)` that records name, pg
  `code`, and a truncated message with uuids, emails and numbers redacted; no
  stack by default (`LOG_STACKS=1` for local debugging only), no `detail` or
  `where`. All `console.error(e)` in `index.mjs` use it.
- `/internal/metrics` fails closed on any proxy marker header (`x-forwarded-*`,
  `forwarded`, `x-real-ip`, `via`, `cf-connecting-ip`, `true-client-ip`,
  `x-envoy-*`, `x-original-forwarded-for`). It exposes no per-family or
  per-network data (route templates, aggregate counters, pool sizes) and a test
  asserts the snapshot's key set.

### 4.4 Anti-snooping at the API

- Game tables: unknown, not-yours and not-pending are all
  `404 {"error":"not_found"}` with identical timing path (no DB work happens
  before the in-memory participant check, so no timing difference exists).
- `/healthz` body is `{"status":"ok"}` or `{"status":"unavailable"}` with 200 and 503.
- WebSocket token: server accepts the join token from the
  `Sec-WebSocket-Protocol` header (`olive.v1, <token>`; subprotocol `olive.v1`
  is echoed, the token never is) in addition to the legacy query parameter.
  When a proxy is configured the operator docs require not logging query
  strings. Client migration to the header form is a follow-up because the
  networked-checkers client files belong to another agent; the server side is
  ready and tested (decision D-3).
- Enumeration: the existing per-IP/per-identifier/global-miss limiters stay;
  they now key on `anonKey`. Table create/join already rate-limit per
  principal.
- Fingerprinting: unchanged generic `404 {"error":"not_found"}` for unknown
  paths and methods (asserted for `OPTIONS`, `TRACE`, `PROPFIND`, a
  trailing-slash path and a path-traversal path); no stack traces in any
  response (asserted by forcing a handler throw); no `Server` or
  `X-Powered-By`.

### 4.5 Defence in depth

- `checkBootTransport` (above) adds boot-time assertions.
- DB: no migration is added; RLS and role rules are untouched. A hygiene
  test (`network_identity_sweep`) is the guard that the schema stays free of
  network-identity columns.
- Secrets: `secrets.mjs` already validates the three signing secrets. New:
  `INTERNAL_METRICS_TOKEN`, when set, must be at least 16 bytes (hex) in
  production.

## 5. Decisions and recommendations

- D-1 Terminate TLS at a reverse proxy, not in Node. Recommend Caddy (automatic
  certificates, HTTP/3, sane TLS defaults) or nginx. Needs an infra owner and a
  domain; this PR delivers the assertions and the config, not the cert.
- D-2 Pin values. Recommend pinning the SPKI of the intermediate (or the leaf
  key with a backup key generated and stored offline) rather than the leaf
  certificate, shipping two pins, and rotating by publishing the backup in the
  app at least one release before using it. Needs the real host and certificate.
  Until then the pin set is empty and pinning is off; a release build with
  pinning requested and fewer than two pins refuses to start.
- D-3 Move the table join token out of the URL once the networked-checkers
  client is free to edit. Server accepts both now.
- D-4 Future hidden-hand games and co-view use `sealed-v1`; do not extend the
  plaintext `move` relay.
- D-5 Ship checkers on the plaintext relay for now (public board); revisit when
  the local-play AEAD framing lands, then retire the plaintext mode.

## 6. Test plan

Server (real Postgres 16 in a throwaway container on port 5460):
`transport.test.mjs`, `relay_envelope.test.mjs`, `sealed_relay.test.mjs`
(real `ws` clients), `network_identity.test.mjs`,
`network_identity_sweep.test.mjs`, `snoop_api.test.mjs` (IDOR/oracle,
fingerprint, healthz), existing `game_tables`, `http_hardening`, `infra`,
`routes`, `security_round2*` suites unchanged and green. Client: Dart unit
tests for the transport policy; `flutter analyze` clean; full `flutter test`.
