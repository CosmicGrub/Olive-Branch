# Calls on the LAN (self-hosted Jitsi)

MASTERFILE section 16.2 number 6, third reversal (2026-11-09). Calls use the Jitsi stack that runs in Docker on the owner's PC. LiveKit is still in the code and is selected with `CALL_PROVIDER=livekit`; this page is about the default.

## What this does and does not give you

- Calls work **only on the home Wi-Fi** (the same network as this PC), **only while this PC is on**, and **only while calls are switched on**.
- There is **no push that rings a closed app from outside the house.** A call rings a device that is on the LAN and has the app reachable; away from home, nothing connects.
- The media bridge is your own PC. No third-party media service sees the child's audio or video (this is why Jitsi, not LiveKit Cloud, is the default for a child's product; it is not a claim of legal compliance).
- Jitsi cannot stop an observer-only guardian from publishing; the app joins them muted with a hang-up-only toolbar (advisory). LiveKit enforces it on the server.

## Switch calls on and off

From `scaffold/tools/jitsi-selfhost/` in Git Bash (Docker Desktop must be running):

```
./calls-on.sh                  # start Jitsi, wait until it answers, print the LAN URL
./calls-on.sh --server-env     # also write olive-server.env (mode 600) for the Olive server
./calls-off.sh                 # stop Jitsi (containers and config kept)
./calls-off.sh --down          # also remove the containers (volumes kept)
```

Both scripts address only the Jitsi compose project (`-p jitsi-docker`). They never touch the Olive server containers or anything else. The stack lives in `.jitsi-docker/` next to the scripts (created by `setup.sh`); point `JITSI_STACK_DIR` somewhere else if your checkout is elsewhere.

The first `calls-on.sh` adds JWT authentication to the stack's `.env` (guests off). If the stack is already running without it, the script refuses and asks for `--recreate`, because applying it restarts the Jitsi containers; run that when no call is in progress. The generated secret is never printed and is never rotated by the script.

## What the Olive server needs

After `./calls-on.sh --server-env`, copy the lines in `.jitsi-docker/olive-server.env` into `scaffold/.env`:

```
CALL_PROVIDER=jitsi
JITSI_APP_ID=olive-calls
JITSI_APP_SECRET=<hex, written for you>
JITSI_SERVER_URL=https://<this PC's LAN IP>:8443
```

The server validates these at boot. The secret must be hex of at least 32 bytes; the URL must be an `https://` origin. If they are missing the calls route answers 503 `call_provider_unavailable` before anyone is rung, and the app says calls are switched off. Restart only the Olive server container after changing them.

## Ports the PC must accept from the LAN

| Port | Protocol | What |
| --- | --- | --- |
| 8443 | TCP | Jitsi web and signalling (https, the address the app uses) |
| 10000 | UDP | the media bridge (the call itself) |
| 3478 | UDP and TCP | TURN relay (the app forces relay for the direct-path privacy rule) |
| 49160-49200 | UDP | TURN relay range |

`JVB_ADVERTISE_IPS`, `TURN_HOST` and `PUBLIC_URL` in `.jitsi-docker/.env` must all be this PC's current LAN IP. `calls-on.sh` refuses to start if they are missing or not https, and warns if they disagree. Give the PC a fixed address (a router reservation); if the IP changes, update those three, regenerate the certificate (below), rebuild the app, and update `JITSI_SERVER_URL`.

### Windows Firewall

Docker Desktop publishes the ports, but Windows Firewall may still block inbound LAN traffic. Allow them once, from an elevated PowerShell:

```
New-NetFirewallRule -DisplayName "Olive Jitsi" -Direction Inbound -Protocol TCP -LocalPort 8443,3478 -Action Allow -Profile Private
New-NetFirewallRule -DisplayName "Olive Jitsi media" -Direction Inbound -Protocol UDP -LocalPort 10000,3478,49160-49200 -Action Allow -Profile Private
```

`-Profile Private` limits this to a network Windows has classed as Private (set your home Wi-Fi to Private). Remove the rules with `Remove-NetFirewallRule -DisplayName "Olive Jitsi*"`.

## The self-signed certificate

The stack serves a self-signed certificate. The app does not turn off verification and has no trust-all. It trusts **one pinned public certificate** (`client/android/app/src/main/res/raw/jitsi_dev_cert.pem`) for **one LAN address** (the marked block in `network_security_config.xml`, main and debug); every other host keeps the platform's normal verification. If the PC's IP changes:

```
./generate-dev-cert.sh <new LAN IP>     # new cert with the right names, rewrites the trust scope in lockstep
./calls-off.sh && ./calls-on.sh         # nginx picks up the new cert
```

then rebuild and reinstall the app (a certificate baked into an installed app does not update itself) and commit the new public certificate and scope.

## Troubleshooting

- "Calls are switched off" in the app: the server has no valid `JITSI_*` values, or the stack is not running. Run `./calls-on.sh`, check `scaffold/.env`.
- The call screen says it cannot reach the call: the phone is not on the home Wi-Fi, the PC is asleep, a firewall rule is missing, or the LAN IP changed.
- Connects but no picture or sound: UDP 10000 or the TURN ports are blocked, or `JVB_ADVERTISE_IPS` is stale.
