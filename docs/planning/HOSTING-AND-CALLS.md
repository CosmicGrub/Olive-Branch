# Hosting, calls, store distribution and multi-family readiness

Research and decisions, snapshot 2026-11-14. Sources are third-party where noted; verify prices and policies on the providers' own pages before relying on them.

## Chosen direction (now)

- **Server:** the dev stack runs in Docker on the owner's PC (project `olive-fresh`, loopback port with `adb reverse` to the test devices). This is the default until the owner says otherwise.
- **Calls:** the owner's self-hosted Jitsi stack (`scaffold/tools/jitsi-selfhost`), started on demand, behind a call-provider switch. LiveKit stays selectable. Calls work on the home network only while the PC is on and calls are switched on. No push yet to ring a closed app.
- **Scrapped for much later:** Oracle Always Free, any VPS, the Cloudflare tunnel, and self-hosted LiveKit hosting. Their partial work is kept on branches (`feat/vps-deploy-kit`, `feat/live-server-bake`).

## Hosting options researched

| Option | Verdict |
|---|---|
| Oracle Cloud Always Free (ARM, reduced to about 2 OCPU and 12 GB in 2026) | Only free option that stays up without a PC. Idle instances can be reclaimed (CPU p95, network and memory all under 20 percent over 7 days; memory counts on ARM only), capacity errors are common, card verification reported by third parties but not stated on Oracle's page. Scrapped for now. |
| Oracle AMD micro VMs (two, 1 GB each) | Only enough for one to three families with swap. |
| Render free web service plus free hosted Postgres | Sleeps after about 15 minutes; free Postgres reportedly expires after 30 days. Test only. |
| Fly.io, Railway, Heroku | No usable free tier for new accounts. |
| Home PC or spare always-on box with a Cloudflare tunnel | A tunnel carries web traffic, not WebRTC media (UDP), so it cannot carry calls. Quick-tunnel addresses change on restart. |
| Small paid VPS (Hetzner about EUR 4-5 a month, others similar) | The reliable fallback once real families depend on the server. |

## Calling options for long distance

1. **Peer-to-peer WebRTC with free signalling plus STUN and TURN.** Signalling messages encrypted with the pairing key so any relay sees only ciphertext; Cloudflare STUN is free; Cloudflare TURN includes a first 1,000 GB a month (shared allowance, then $0.05 per GB, per their pricing docs). Good for one-to-one and small groups. A closed app cannot ring without a push service (FCM carries only a wake-up ping). Planned as a `p2p` provider next to Jitsi and LiveKit.
2. **Private network (Tailscale free personal plan) with the Docker servers.** Fastest long-distance path for the owner's own family and testing; every device needs the app and the PC must be on.
3. **Free hosted media services** (public Jitsi, LiveKit Cloud free tier, Daily, Agora). Quick, but each is a third-party processor of a child's live video, which the amended COPPA rule requires disclosing. Short tests only.
4. **Self-hosted media on a VPS** when hosting resumes.

Same-room calls over Wi-Fi (peer-to-peer on the local network, no STUN or TURN) are the cheapest case and are planned as a feature.

## Store distribution (plan for it now)

- A store version needs a real always-on backend with backups, a security review, data-processing agreements with the host and a privacy policy; the PC and free tiers are not enough. Peer-to-peer media keeps video off the servers, which cuts cost and legal exposure.
- Third parties that receive a minor's data must be disclosed (amended COPPA, Google's Data Safety form, Apple's privacy labels). Apple's Kids Category reportedly restricts third-party analytics and ads; assume none and verify Guideline 1.3 and 5.1.4. Keep the child build free of analytics and ad SDKs (it is today).
- Google Play: one-time developer fee; personal accounts created after November 2023 reportedly must run a closed test with 12 testers for 14 continuous days before production (third-party reports; organisation accounts are exempt). Apple: annual developer fee and a Mac for iOS builds.
- Calls on stores: Android needs a foreground service and a declaration for full-screen call alerts; iOS needs CallKit and PushKit. iOS has no real child-lock equivalent; plan an in-app child mode plus Guided Access instructions.
- Release engineering: ship an app bundle with proper signing (an offline-held keystore), remove the "Server address" setting from store builds, bake in the production address with certificate pinning.
- Do now: keep the child build free of third-party SDKs; keep the call-provider switch with peer-to-peer as the store-safe default; write the privacy policy, data inventory and retention policy early; commission the external crypto review; add iOS on its own roadmap later.

## Multi-family readiness (5 to 10 families at first)

- Capacity is small (roughly 40 to 60 devices); one small server is plenty. The risks are isolation between families, onboarding without the owner present, and operations.
- Priorities: finish S-B11 and the family tenant isolation (S-D26); add invite-only sign-up with a family cap, a waitlist and a kill switch; run the 10-family simulation (PR #179) and keep its fast subset in CI; backups with a tested restore drill; monitoring with no per-family data; a minimum-app-version gate; consent form and in-app acceptance record for the closed beta.
- A beta path that fits the store rules: waves of two or three families; the 12-tester Google rule is met by real families.
- Calls stay inside each family; cross-family contact (a grandparent or sitter) happens only through an explicit guardian invite.
