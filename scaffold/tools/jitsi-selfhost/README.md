# Self-hosted Jitsi — §16.2 #6 Step 2

**Status: staged and container-level verified; not yet verified on real
hardware.** This directory sets up a local `docker-jitsi-meet` stack so
Step 2 (self-host Prosody/Jicofo/JVB) can be brought up on the dev machine,
the same way `tools/local-call-room-server.mjs` already stands in for the
production room-coordination API — LOCAL DEV/TEST ONLY, not a production
deployment plan.

**What "verified" means here, precisely:** the full stack was actually
brought up on this dev machine (not just written and assumed to work), hit
three real bugs in the process (all below, all fixed), and — once
healthy — Prosody's own live-rendered config was inspected directly to
confirm `authentication = "jitsi-anonymous"` with no forced-lobby or
auth-gated moderator config, which is the actual mechanism that fixes the
meet.jit.si finding. A full WebRTC join was **not** verified — the
self-signed cert blocks it from both a browser (confirmed:
`net::ERR_CERT_AUTHORITY_INVALID`) and would equally block the Flutter SDK
on a real device (see "the self-signed cert" below). That gap, plus
physical two-device re-verification, is what's left before this Step can be
called done.

## Why this exists

The v0.46.0 finding (MASTERFILE §16.2 #6 callout, CHANGELOG `[0.46.0]`): the
public `meet.jit.si` server puts new/unclaimed rooms into a moderator-approval
lobby that nothing in this app can ever clear, because meet.jit.si requires an
*authenticated* (Google/Facebook/GitHub-login) moderator before anyone can be
granted the MUC moderator affiliation — confirmed as a server-side anti-abuse
policy specific to that public deployment
([jitsi/jitsi-meet#13753](https://github.com/jitsi/jitsi-meet/issues/13753)),
not something `configOverrides`/`featureFlags` in `call_screen.dart` can
disable client-side. `FeatureFlags.lobbyModeEnabled: false` (already set)
only hides the in-call lobby *toggle UI* — it doesn't touch the server policy
that auto-enabled `membersOnly` before that UI was ever reachable.

Self-hosting resolves this because the "must be an authenticated moderator"
rule is 8x8's policy layered onto meet.jit.si specifically, not a default
behavior of the open-source Prosody/Jicofo stack. `docker-jitsi-meet`'s
default **anonymous domain** (no `ENABLE_AUTH`) makes the *first participant
to join* the moderator automatically, with no login — so the lobby is
available (a moderator can turn it on) but never auto-engages against a
fresh room the way it does on meet.jit.si.

## What this does NOT decide

- **Whether `mod_auth_token` (JWT) replaces room-name secrecy as the auth
  boundary — still undecided, per the MASTERFILE callout.** This scaffold
  deliberately leaves `ENABLE_AUTH`/`AUTH_TYPE` unset (anonymous domain) so
  I1 (room name never guessable) stays the security boundary, matching what
  `packages/session-runtime/src/rooms.ts`'s `Grant`/`mintToken` already
  produce. If Olive later needs revocable per-call tokens (e.g., to kick a
  removed guardian mid-call rather than waiting for the room to cycle),
  that's a real reason to revisit this — not done here.
- **Production hosting** (real domain, real TLS via Let's Encrypt, a host
  with a stable public IP, `JVB_ADVERTISE_IPS` set to that IP). This is a
  localhost dev stack only.
- **The COPPA sub-processor disclosure rewrite.** Once this is the thing a
  real call runs against, the disclosure names Olive itself, not 8x8/Jitsi
  — that's a documentation/legal task, not code, and isn't done by standing
  up a dev stack.

## Three real bugs, found by actually running this, not by reading the compose file

1. **Docker Desktop's containerd-snapshotter image store corrupts these
   images' user resolution.** First `docker compose up` failed on every
   container with `unable to find user s6: no matching entries in passwd
   file` — reproduced even with a bare `docker run --entrypoint sh`, so it
   wasn't a compose/volume issue. Root cause: Docker Desktop's
   `UseContainerdSnapshotter` setting
   (`%APPDATA%\Docker\settings-store.json`) was `true`; the classic
   `overlay2` graphdriver doesn't have this bug. Fixed by setting it to
   `false` and restarting Docker Desktop, then re-pulling the images clean.
   Not specific to this project — worth knowing if any other image on this
   machine starts failing the same way.
2. **JVB's colibri HTTP port collides with `server/index.mjs`.** Upstream
   default is `8080` for both. `docker compose ps` showed
   `127.0.0.1:8080->8080/tcp` on the `jvb` container after first bringing
   the stack up — not something reading `docker-compose.yml` alone would
   have caught, since the collision is with *this* project's own server,
   not anything in docker-jitsi-meet. Fixed: `JVB_COLIBRI_PORT=8181` in
   `olive.env`.
3. **Prosody can't write its own TLS cert on a Windows bind mount.**
   `docker-jitsi-meet`'s default `${CONFIG}/storage/prosody:/var/lib/prosody`
   bind mount, when `CONFIG` is a Windows host path (`/c/Users/...` or
   `C:\Users\...`), loses POSIX ownership through Docker Desktop's
   file-sharing translation layer — Prosody's container (uid 1000) can
   never write into it, so cert generation silently fails
   (`The directory /var/lib/prosody is not owned by the current user`),
   which cascades into Jicofo and JVB's XMPP connections to Prosody
   failing outright (`No stream features to proceed with`) — not a
   cosmetic warning, the whole signaling chain was down. Fixed:
   `docker-compose.override.yml` gives Prosody's two writable paths named
   Docker volumes instead (see that file's own header comment for why
   named volumes sidestep this). `setup.sh` installs it automatically.

## A real constraint this surfaced: UDP media over `adb reverse`

Step 1's two-device USB testing pattern (`adb reverse tcp:8787 tcp:8787`,
per `call_screen.dart`'s header comment) only forwards **TCP**. Jitsi
Videobridge's media path is **UDP** (port 10000 by default) — `adb reverse`
cannot tunnel it. That means the room-coordination HTTP call can keep working
over the USB loopback trick, but the actual call media cannot, once the
target server is a local JVB instead of meet.jit.si's public, real-IP-reachable
one.

Two ways to get real UDP media reachability from a physical device to this
dev-machine stack, neither implemented here yet:
1. Put the phone on the same WiFi network as the dev machine and set
   `JVB_ADVERTISE_IPS` to the dev machine's LAN IP (same class of hardcoded-IP
   fragility the old `192.168.1.78` bug already burned this project once —
   see CHANGELOG `[0.46.0]`, "Fixed"). Whatever replaces it should not
   hardcode an IP the same way.
2. `adb reverse` the TCP signaling/web ports only, and rely on JVB's TCP
   fallback (`org.ice4j.ice.harvest.ALLOWED_INTERFACES` / Jitsi's
   `TCP_HARVESTER` mode) — works but adds latency and isn't how Jitsi is
   normally run.

## A second real constraint: the self-signed cert

`docker-jitsi-meet` serves HTTPS with a **self-signed** cert unless
`ENABLE_LETSENCRYPT`/`LETSENCRYPT_DOMAIN` are set, which need a real public
DNS name — not available for a localhost dev stack. `network_security_config.xml`
(`client/android/app/src/main/res/xml/`) only whitelists cleartext HTTP to
`127.0.0.1` for the room-coordination call; it says nothing about trusting a
TLS cert, and `jitsi_meet_flutter_sdk` has no client-side "skip cert
validation" flag. A physical device will reject the self-hosted stack's TLS
handshake outright until either:
- a `<trust-anchors>` entry + bundled CA resource is added to
  `network_security_config.xml` for local dev builds only, or
- the stack runs behind a tunnel (Cloudflare Tunnel / ngrok) that terminates
  with a real, publicly-issued cert.

Neither is done here. Browser-only checks (Task #3) don't hit this, since a
desktop browser can click through a self-signed warning; the Jitsi SDK on a
real device cannot.

Physical two-device re-verification (the standard this project holds itself
to — MASTERFILE §16.2 #6: "verified rather than trusted from code review")
is **not done as part of this scaffold** — this session has no attached
Android hardware, and the cert-trust gap above would block it even if it
did. What *was* done: full container-health verification, plus reading
Prosody's actual live-rendered config to confirm the anonymous-domain /
no-forced-lobby mechanism is really in effect (see the status note at the
top) — stronger than "the compose file looks right" but still short of a
real call connecting.

## Setup

Pinned to `stable-11146-1` (current stable tag as of this writing — checked
via the `jitsi/docker-jitsi-meet` GitHub releases; re-verify before bumping).

```bash
./setup.sh
```

This clones `jitsi/docker-jitsi-meet` at the pinned tag into `.jitsi-docker/`
(gitignored — it's a vendored third-party checkout, not Olive source), lays
`olive.env` on top of the upstream `env.example`, and runs `gen-passwords.sh`.
It does not start the stack.

```bash
../with-jitsi.sh          # bring the stack up, wait for health, leave running
../with-jitsi.sh down     # tear it down
```

Once running, the web UI is at `https://127.0.0.1:8443` (self-signed cert —
expect a browser warning; that's expected for a dev stack). Point
`local-call-room-server.mjs` at it with:

```bash
JITSI_SERVER_URL=https://127.0.0.1:8443 node tools/local-call-room-server.mjs
```

## `olive.env` decisions, explained

| Setting | Value | Why |
|---|---|---|
| `ENABLE_AUTH` | unset (off) | Anonymous domain — first joiner is moderator, no login, no auto-lobby. The thing this whole exercise is for. |
| `ENABLE_GUESTS` | unset (off) | Only relevant when `ENABLE_AUTH=1`; not applicable here. |
| `HTTP_PORT` / `HTTPS_PORT` | `8000` / `8443` | Upstream defaults. No collision with this project's `server/index.mjs` (`:8080`) or `local-call-room-server.mjs` (`:8787`). |
| `JVB_COLIBRI_PORT` | `8181` | Upstream default (`8080`) collides with `server/index.mjs`'s own `PORT` default — found by actually bringing the stack up, see "Three real bugs" above, not assumed from reading the compose file. |
| `PUBLIC_URL` | commented out | Defaults to `https://localhost:8443`, correct for the dev-only scope here. |
| `JVB_ADVERTISE_IPS` | commented out, with instructions | Must be set to the dev machine's real LAN IP before a physical device can exchange media — see the UDP constraint above. Deliberately not hardcoded to a specific IP in this checked-in file, for the exact reason CHANGELOG `[0.46.0]` documents about the old `192.168.1.78` bug. |
