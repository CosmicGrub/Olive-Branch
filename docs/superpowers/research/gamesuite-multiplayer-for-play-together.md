# GameSuite multiplayer machinery, and what Olive Branch's Play together suite actually needs from it

Status: RESEARCH, read-only. Docs only; no code, test, total or MARKUP change. Date: 2026-11-08.
Owner request (verbatim): "lets use some of the multiplayer process, protocols and functions that were built into the android arcade (gamesuite) project for use in the play together. search that project in order to find what this app actually need for the play together suite."

## 0. Provenance, method and caveats

- **GameSuite** (`Z:\GameSuite`, GitHub CosmicGrub). `main` (533e636) is 48 commits behind `session/wave-3`
  (18d9b53, "Data safety, Nearby admission, relay URL check ...", 2026-11-07), which is checked out in
  `Z:\GameSuite-wt-game-kit` with other sessions' uncommitted edits. I did not read that dirty tree. I extracted
  the committed tree of 18d9b53 with `git archive` into a scratch directory and read that, so **every GameSuite
  citation below is `path:line` at `session/wave-3 @ 18d9b53`** (the multiplayer hardening, spectators, session health,
  seat grid and relay wave-5 work are only on that branch, not on `main`). `session/tests-audit` was not needed.
  Nothing under `Z:\GameSuite` was modified; no build, no git write there.
- **Olive Branch** citations are `path:line` at `origin/main @ c09ecd5` (this worktree).
- Verification legend used for every GameSuite and Olive Branch capability:
  **D** = exercised on real hardware; **E** = automated end to end over real sockets/processes (no device);
  **U** = unit tests only; **C** = claimed or designed only; **N** = not built.
- Two corrections to the brief, so nobody chases the wrong file:
  1. `scaffold/client/lib/device_channels.dart` is the push-notification channel capability table (FCM/APNs/Fire),
     not game transport (`device_channels.dart:34-71`). The play-together transport is `local_discovery.dart`,
     `local_session.dart` and `local_pairing.dart`.
  2. MASTERFILE §2.1's P1-P11 (`MASTERFILE.md:249-268`) are: P1 synthetic parent voice, **P2 punitive streaks or
     engagement scoring shown to the child**, **P3 live location**, P4 purchase mechanics, P5 behavioural ads/data
     brokerage, **P6 any financial surface visible to a child**, P7 parent access to the private journal, P8 log
     deletion, P9 resurfacing pre-separation archive, P10 appearance modification of a child's video, **P11 no
     remote control of a child's device**. The brief's other rules (no error text, no stranger contact) live in
     §5.23.2 (calm wording, `MASTERFILE.md:5179`), §5.14/§5.17 (who may contact a child) and the code-level audit
     `live_games.dart:367-401`. I cite P-numbers by their MASTERFILE meaning and the others by section.

## 1. Executive summary (15 lines)

1. GameSuite's multiplayer is **host-authoritative, full-state-broadcast**: one device runs the rules engine, others render
   a versioned `StateSync` and send `Intent`s (`UnoNetMessage.kt:22-79`). Olive Branch's Uno **already does the same**
   (`game_uno.dart:49-62`, `:319-343`, `:356-460`). The architecture is not the gap.
2. The gap is everything *around* the move: GameSuite has a **versioned envelope, a sender-identity rule, resync on
   startup/reconnect, session-end handling, a shared game contract and an in-memory test relay**. Olive Branch has none
   of these for games (`local_pairing.dart:180-190`, four unrelated payload dialects).
3. **Olive Branch has a real, present silent-desync bug class.** `LocalPairingController.sendTurn` returns silently when
   the peer is lost (`local_pairing.dart:181-184`); Connect 4 applies a move locally before sending
   (`game_connect4.dart:130-139`); Uno's authority fires several `unawaited` full-state POSTs in a row with no sequence
   number (`game_uno.dart:385-412`), so a late packet can overwrite a newer one; nothing resyncs after "re-found".
4. **Olive Branch has a present child-safety exposure** that GameSuite audited and fixed in its own transports: the
   local server accepts a turn from *any* device on the LAN (`local_session.dart:82-103`), the child's display name is
   broadcast over mDNS to the whole network (`local_discovery.dart:92-96`), the first resolved peer wins with no
   confirmation (`local_pairing.dart:145-156`) and the request body is read unbounded (`local_session.dart:91`).
5. Olive Branch is **ahead** of GameSuite in places: a send/receive child-safety payload audit
   (`live_games.dart:367-401`), device-boundary team privacy (`game_seat.dart:1-60`), a sequence-numbered, size-capped,
   untrusted-input message design with TS-generated golden vectors (`co_view_logic.dart:1-20`,
   `tools/gen-coview-vectors.mjs:1-8`), and layout/accessibility rules. Do not regress these by porting GameSuite shapes.
6. Most of GameSuite's size is **online, stranger-facing or competitive** (relay rooms, matchmaking queue, Elo buckets,
   quick-chat, stats, achievements, streaks, free-text display names). That is out of scope or prohibited
   (P2, offline-first direction); section 4 lists each with reasons.
7. The **Rust core is Air Hockey physics and ambient-music DSP only** (`rust/gamesuite-sim/src/lib.rs:1-60`,
   `rust/gamesuite-audio/src/lib.rs:1-25`); it has no networking, no deterministic-replay API and UniFFI generates Kotlin,
   not Dart. **Do not reuse it.**
8. Languages differ (Kotlin/Rust vs Dart/TS), so almost everything is **port-the-design**, plus **port-the-test-vectors**
   where Olive Branch already has the TS-engine-plus-Dart-runner pattern. No GameSuite wire format should be copied
   byte for byte: the two apps never talk to each other.
9. GameSuite's own verification is thinner than its README suggests for the multiplayer layer: 2-device Nearby UNO was
   run on Fold 5 + Tab S9 once, early; every hardening since is U/E only (`UNBUILT-ITEMS.md:G`, README:2224). Treat
   GameSuite's "built" as "design evidence", not "proven".
10. Recommended adoption, in order: **(1)** a versioned play envelope with session id, sequence/ack, hello/resume and
    request-state, with golden vectors; **(2)** pairing admission and sender binding (neutral mDNS label, grown-up
    confirmation, per-session key); **(3)** a shared `PlayGameSpec`/`PlayTransport` contract plus an in-memory loopback
    harness so the two-device paths become unit-testable; **(4)** calm session-end and resume (authority snapshot to the
    local store, one shared notice); **(5)** rematch handshake, authority-only bots, seeded deals, state digest.
11. Deferred or declined: grown-up spectator on a third device (design the role in, do not ship), host migration,
    idle-turn timers/AFK, quick-chat, matchmaking, rating, stats, relay hosting, Nearby Connections, Rust FFI.
12. Party-toolkit ideas that fit a family: dice, coin, who-goes-first, turn order, a number-free sand timer chosen by the
    grown-up. Excluded: scoreboard, life points, round tracker, game clock and "who pays" (P2, P6).
13. Sizes: items 1-3 are M each; 4 is M; 5 is S+S+S+S. Nothing needs the network or an account.
14. Real-device checks must include a hostile peer (a third device or PC posting to `/turn`) and a mid-game Wi-Fi drop;
    the plan is in section 5.12.
15. Owner decisions are in section 6 (pairing-security level, persistent session vs POST-per-turn, authority snapshot
    persistence, whether to design for more than two devices, whether to build the table-tools subset).

---

## 2. Inventory of GameSuite's multiplayer machinery (session/wave-3 @ 18d9b53)

### 2.1 The game contract: how a game plugs in

| Piece | What it is | Cite | Verif. |
|---|---|---|---|
| `GameModule` | Lifecycle interface every game implements: `gameId`, `displayName`, `category`, `minPlayers`, `maxPlayers`, `supportedModes`, `init(GameContext)`, `startMatch()`, `pause()/resume()`, `endMatch(GameResult)`, `abortMatch()` (wave-3 addition) | `shared/src/commonMain/kotlin/com/gamesuite/core/GameModule.kt:11-44` | U |
| `PlayMode` | `SINGLE_DEVICE_PASS_AND_PLAY`, `DUAL_SCREEN` (permanently abandoned), `LOCAL_AD_HOC`, `ONLINE`, `SINGLE_PLAYER_VS_BOT` | `GameModule.kt:59-86` | n/a |
| `GameContext` | What the shell hands a game: `activeMode`, `players: List<PlayerInfo>`, `localPlayerIndex` (-1 = spectator), `transport` | `GameModule.kt:88-96` | U |
| `PlayerInfo` | `playerId`, `displayName`, `isBot`, `teamId` (-1 = none) | `GameModule.kt:97-104` | U |
| `GameResult` / `abortMatch()` | A leave or connection loss is `wasAborted = true`, which the session manager never records | `GameModule.kt:105+`, `GameChrome.kt:71-72` | U |
| `GameHubSpec` + `GameHubSpecs` | Declarative per-game spec (modes, options, seat ranges, `networkedGames`, `spectatorGames = setOf("uno")`) from which the Hub and the lobbies are built | `core/GameHub.kt:166-193`, `core/GameHubSpecs.kt:39-53` | U |
| `GameSessionManager.launchGame` | Builds a `GameContext` (creating the transport for local modes, or taking an already-connected Nearby/Online one) and resets per-launch `LaunchOptions` | `core/GameSessionManager.kt:226-267` | U |
| `ResumableGame` / `SnapshotHistory` | `snapshot(): String?` / `restore(String): Boolean`; a game returns `null` for networked modes ("that state lives with the other players") | `core/Resumable.kt:7-78`, `UnoGame.kt:135-173` | U |

Notes. The contract is thin on purpose: a game never touches sockets, only `MultiplayerTransport` and `GameContext`
(README "Design notes worth remembering"). **There is no shared wire base class**: every game defines its own sealed
message class (`UnoNetMessage`, `TicTacToeNetMessage`, `CheckersNetMessage`, ...) with the same three-part shape
(`StateSync`, `Intent`/`MoveRequest`, `RequestState`), copied by hand
(`TicTacToeNetMessage.kt:1-26`, `CheckersNetMessage.kt:15-49`). The README claims CPU bots are "fake players that respond to the
same transport messages a human would" (README "Design notes"); the code does not do that, the host engine drives bot
seats directly (`UnoGame.kt:712-713`). That claim is **C**, not implemented.

### 2.2 Session and lobby lifecycle

- **Nearby host lobby**: host starts advertising with a neutral label plus a 4-character random code, never a player
  name or device model (`NearbyAdmission.kt:26-30`); accepts a connection only while the lobby is open and a seat is free
  (`NearbyAdmission.kt:19-20`, `NearbyConnectionsTransport.kt:206-217`); each guest sends `JoinRequest(clientPlayerId,
  displayName)`; the host **assigns** every seat id, treating the guest's id as a proposal (`NearbyRoster.kt:116-199`,
  `NearbyLobbyProtocol.kt:10-72`); host sends each guest its own `GameStart(gameRoute, players, yourPlayerId?,
  gameDisplayName?)`; the host is always `players[0]`, `localPlayerIndex == 0` (`UnoGame.kt:61`).
  **U** for the decisions (`NearbyRosterTest`, `NearbyAdmissionTest`, `EndpointIdentityMapTest`); the Android Nearby
  callbacks and Compose lobby are "compile-verified glue" (README:2224).
- **Online (relay) lobby**: `host` returns `hosted{roomCode, reconnectToken}`; `join{roomCode, playerId}` returns
  `joined{hostPlayerId, reconnectToken, players}` (`server/index.js:1-45`, cases at `:500`, `:570`); guests act only on
  a `GameStart` stamped as coming from the host (`OnlineLobbyProtocol.kt:156-162`); `Hello`/`OnlineLateJoinResponder`
  handle a member who arrives after Start (`OnlineLobbyProtocol.kt:35-45`, `:100-134`); `Ready` and `RosterUpdate` are
  additive lobby messages (`:47-63`). **E** (real client against real relay in `OnlineRelayEndToEndTest`, skipped where
  Node is missing) and Node suites; never deployed (`UNBUILT-ITEMS.md:A`).
- **Seats/CPU fill/ready**: `LobbySeatLimits.canStart(guests, cpus)`, `maxCpus`, CPU seats `cpu-N` with `isBot`, a guest
  can never claim a `cpu-` id (`transport/LobbySeats.kt:7-9,28-80`, `OnlineLobbyProtocol.kt:148-153`); 30-second "start
  anyway" ready check (Online only; Nearby ready-check **N**) (`WAVE-5-MULTIPLAYER-DESIGN.md:614-676`).
- **Leaving**: a leave or connection loss is an abort that records nothing (`GameChrome.kt:71-72,123-137`).

### 2.3 Turn and state sync model

Authoritative host, full-state broadcast, not lockstep and not an event log.

- UNO: `StateSync(version:Int, state:UnoState)` after every commit; `Intent(UnoIntentPayload)` from guests;
  `RequestState` from a guest after its listener registers and after a reconnect (`UnoNetMessage.kt:22-79`,
  `UnoGame.kt:87-115`, `:768-775`, `:817-905`).
- Receiver rule: drop a `StateSync` whose `version <= lastAppliedRemoteVersion` (`UnoGame.kt:875-881`), and accept
  `StateSync` only from `players[0]` (`UnoGame.kt:891`).
- Board games send the engine's own snapshot string instead of a typed state (`CheckersNetMessage.StateSync(version,
  snapshot, lastMove, hops)` and `MoveRequest(baseVersion, from, path)`; the host drops a request whose `baseVersion` is
  stale) (`CheckersNetMessage.kt:27-40`). That `baseVersion` check is the one optimistic-concurrency idea in the suite.
- Serialization is kotlinx JSON (UTF-8), decoded with `ignoreUnknownKeys` so a newer host can add fields
  (`RemoteStateChecks.kt:11-12`, `LobbyJson` at `NearbyLobbyProtocol.kt:35`). Optional wire fields are *omitted* for
  honest older guests rather than always sent (`NearbyLobbyProtocol.kt:51-56`). There is **no explicit protocol version
  field** anywhere; compatibility is "unknown keys ignored" plus "both devices should run the same version"
  (`NearbyLobbyProtocol.kt:30-35`).
- `SyncEpoch`: a guest drops any version it has already seen, so a host game object that was recreated and restarted its
  counter at 0 froze every guest. Each new host object now starts its counter at a fresh epoch in the top 11 bits
  (`core/SyncEpoch.kt:5-35`). **U** (`SyncEpochTest`). This is the only session-identity mechanism.

### 2.4 Transports

| Transport | What it is | Cite | Verif. |
|---|---|---|---|
| `LocalPassAndPlayTransport` | Same device; echoes `send` straight back to the listener | `shared/.../LocalPassAndPlayTransport.kt:1-50` | U |
| `NearbyConnectionsTransport` | Google Nearby, `Strategy.P2P_CLUSTER`, bytes payloads, endpoint ids translated to seat ids by `NearbyGameRouter`; `fromPlayerId` is derived from the endpoint, never from the payload (`:255-263`) | `app/.../transport/NearbyConnectionsTransport.kt:57-270` | **D once** (UNO, Fold 5 + Tab S9; README item 11); hardening since is U |
| `OnlineTransport` | OkHttp WebSocket to the relay; one `WireMessage` envelope; reconnect with token; exposes `sessionEnd`, `awayPlayers`, `isReconnecting` | `OnlineTransport.kt:63-120,291,360-425` | E |
| `LanMultiplayerTransport` | JVM only: UDP-broadcast discovery plus a persistent TCP connection per guest, newline-delimited JSON, the **host relays and stamps** every frame | `shared/src/jvmMain/.../LanMultiplayerTransport.kt:30-110` | E (real sockets; `LanBotMatchRunner` bot-vs-bot across two processes/devices) but **not wired into the Android app** |

The `MultiplayerTransport` interface is the whole abstraction: `connect`, `disconnect`, `send(from, to?, payload)`,
`onMessageReceived((fromPlayerId, payload))`, `onPlayerJoined`, `onPlayerLeft`, default-no-op `onReconnected`
(`shared/.../transport/MultiplayerTransport.kt:14-61`). Its KDoc fixes the **identity rule**: over a network the receiver's
`fromPlayerId` is established by the transport (endpoint, relay-registered seat, host stamp), never written by the sender,
and games should check an intent against the seat it acts for and accept state only from `players[0]` (`:32-42`).

Relay wire protocol (JSON text frames): `host`, `join` (optionally with `reconnectToken` or `spectator:true`),
`message{toPlayerId|null, payloadBase64}`, `leave`; server frames `hosted`, `joined`, `reconnected`, `playerJoined`,
`playerDisconnected`, `playerReconnected`, `playerLeft`, `message{fromPlayerId}`, `error{code}`; wave-5 adds `peek`,
`lock`, `started`, `kick`, `chat`, `queue`, `queueCancel`, `claim` (`server/index.js:1-90`, dispatch at
`:500-837`). Room codes are 4 characters from a 32-symbol alphabet with no 0/O/1/I (`server/index.js:96-103`,
`NearbyAdmission.kt:13`); caps: 8 seats, 500 rooms, 64 KiB frames, 30 min idle reap (`server/index.js:103-117`).

### 2.5 Reconnect and rejoin

- Relay holds a dropped seat for `RECONNECT_GRACE_MS` (30 s), others see `playerDisconnected`, then `playerLeft` after
  expiry (`server/index.js:60-68,117`). A resume needs the seat's secret 192-bit `reconnectToken`; vacated seats are
  retired for the life of the room (`server/index.js:46-58`, README "Online relay" hardening). **E** (`smoke-test.js`,
  `identity-test.js` with mutation checks, `OnlineTransportIdentityTest`).
- Client: five retries with 1/2/4/8/8 s backoff (`OnlineTransport.kt:291`), then `connectionError`; on resume it fires
  `onReconnected`, and the game re-requests state (guest) or re-broadcasts (host) (`UnoGame.kt:105-113`).
- Bug fixed on the way: the resync was being sent on the dead pre-drop socket; the resumed socket is now published
  before the game is told (README:2273-2279).
- **Nearby has no reconnect story** (`MultiplayerTransport.kt:54-58`). UNO's `snapshot()` returns null when networked
  (`UnoGame.kt:173`): there is no resume after process death.

### 2.6 Spectators

`join{spectator:true}` gets a read-only seat outside the 8-seat cap; the host learns of a watcher when it sends
`RequestState`; the host streams every commit to it through `unoRedactForSpectator` (public table only: counts, discard,
colour, turn, direction, scores) (`UnoGame.kt:63-85,839-843`, `UnoRedaction.kt:25-34`). A non-roster id can never move
(`UnoGame.kt:907-910`, `:862`). Late arrivals are answered by `OnlineLateJoinResponder`. Only UNO is in `spectatorGames`
(`GameHubSpecs.kt:39`). **U** (`UnoSpectatorTest`, `OnlineLateJoinResponderTest`); watching on a device was never done
(`PAUSED-2026-10-18.md`: "UNO Watch" still to test). Spectator is a shell concept only for UNO because every other game
would need its own redaction.

### 2.7 Timeouts, AFK, host migration, session end

- **Idle-turn timer: N** (deferred; code-review finding 7, `CODE-REVIEW-WAVES-1-4.md:27`, `UNBUILT-ITEMS.md:A`).
  An idle guest stalls several card games indefinitely.
- **Host migration: N** (research sketch only, `WAVE-5-MULTIPLAYER-DESIGN.md:272-290`). v1 aborts the match.
- **Session end: built.** `SessionHealthSource` (`sessionEnd`, `awayPlayers`, `isReconnecting`, `sessionHostId`) and the
  pure `sessionNoticeFor(...)` decide `RECONNECTING / HOST_AWAY / PLAYER_AWAY / HOST_LEFT / CONNECTION_LOST`;
  the chrome turns a final one into an abort that records nothing (`transport/SessionHealth.kt:5-75`,
  `uikit/SessionHealthOverlay.kt`, `GameChrome.kt`). The KDoc explains the design constraint: a game registers a *single*
  `onPlayerLeft` setter, so the shell cannot add a second listener and the transport exposes observable state instead
  (`SessionHealth.kt:14-20`). **U** (`SessionHealthTest`); "In-game Host left dialog never reached a started match"
  (`UNBUILT-ITEMS.md:G`).

### 2.8 Desync detection and resync

- Detection is **only** the monotonic `version` plus drop-old rule. There is **no checksum, state hash or divergence
  check anywhere** (I grepped `checksum|crc|stateHash|desync` across main, shared and the relay: only comments).
- Resync is pull-based: `RequestState` at startup, after a reconnect, and by a new watcher. The authority never
  verifies a guest is in step.
- Because the model is authoritative-and-render, a guest cannot diverge in rules; the risk is only a stale or missing
  snapshot. That is why the design works without hashes.

### 2.9 Rematch

TicTacToe/Chess/Checkers send a `PlayAgain` intent that the host applies and then alternates the opening seat
(`TicTacToeGame.kt:473-499`, `CheckersNetMessage.kt:46-48`). Known hole, recorded by the transport audit: the host applies
a `PlayAgain` from any seated player at any time (README:2288-2290; "handed off", `UNBUILT-ITEMS.md:B`).

### 2.10 Seating, teams, bots

- Teams are `PlayerInfo.teamId`, set when the *local* setup builds the roster (`i % 2`) (`core/GameHub.kt:267,275`,
  `SavedGameStore.kt:38,75`); the outcome resolver treats a teammate's win as a win (`core/LocalOutcomes.kt:27-52`).
  The Nearby/Online lobbies have **no team assignment UI** (README:632-635 note, `WAVE-5-MULTIPLAYER-DESIGN.md:350`).
- Bots: shared `CpuDifficulty`/`CpuLevel` (Easy to Expert), UNO's `UnoBot` uses only public information
  (hand sizes), drawn only on the host (`UnoBot.kt:1-50`, `UnoGame.kt:712-713`). The "guest drives a bot seat" bug was
  found by the 3-4 seat audit and fixed with an early return (`WAVE-5-MULTIPLAYER-DESIGN.md:628-640`).
- The 3-4 seat audit (`NetworkedSeatAuditTest`, `ThreeFourSeatLobbyTest`) runs every networked engine over an in-memory
  relay for 3 and 4 seats with hidden-hand leak checks. **U**, and a genuinely good pattern.

### 2.11 Randomness and hidden information

- The host shuffles with an **unseeded** local RNG once (`UnoGame.kt:216-217`, reshuffle `:1068-1076`); the KDoc is
  explicit that a replicated-simulation design would deal different hands per device, hence host-authoritative
  (`UnoNetMessage.kt:14-20`). The seed is never shared.
- Resume carries the draw-pile *order* in the snapshot rather than a seed (`UnoGame.kt:119-121`). Daily puzzles derive a
  seed from `LocalDate.toEpochDay()` at the navigation call site (README:2128-2133).
- **Hidden information**: the host sends each recipient a copy with every other hand replaced by same-length placeholder
  cards (`UnoRedaction.kt:9-23`); spectators get all hands redacted; the draw pile order is not part of the state, so it
  cannot leak (`UnoRedaction.kt:25-31`). This was a real leak in the first version (every peer received every hand;
  README "UNO" hardening). Same pattern in Word Tiles racks and Dominoes (`TileNetRedactionTest`).

### 2.12 Cheating and validation

Host validates every intent against the **transport-stamped sender**: the intent's claimed seat index must be the
sender's seat, and `ChooseColor`/`ResolveChallenge` carry no index at all and act on whichever seat the host's state says
is waiting (`UnoGame.kt:907-945`). Non-host `StateSync` is refused (`:891`). Wire inputs are plausibility-checked
before use (`TicTacToeGame.kt:617`, `CheckersNetMessage.kt:66-72`, `RemoteStateChecks.kt:8-9`). The relay stamps ids from
the socket, caps frames at 64 KiB, rate-limits per IP and per socket, and sanitises names (`server/index.js:96-117`,
`server/ratelimit.js`, `server/sanitize.js`, audit `03-safety-privacy.md`). Threat model: friends, not a hostile host
(`WAVE-5-MULTIPLAYER-DESIGN.md:284-290`).

### 2.13 Accessibility, layout

Reduced motion via `LocalReducedMotion`, TalkBack live regions for session notices, text scale, Fold-aware layout (UNO
table adaptive seating fixed on a real Fold 5 and tablet, main commit 533e636). **D** for UNO table layout on devices;
the 40-game rollout is mostly code-read (`UNBUILT-ITEMS.md:G`).

### 2.14 Things that exist but are online/competitive

Matchmaking queue with skill buckets and CPU fill (`server/queue.js`, `WAVE-5-MULTIPLAYER-DESIGN.md:170-300`),
room metadata/peek/lock/kick (`server/rooms-meta.js`), quick-chat phrase ids (`server/quickchat.js`,
`quickchat-allowlist.json`), per-IP rate limits, `Elo` bucket idea (`OnlineRatingStore` **N**), persistent per-game stats,
achievements, streaks (`core/Achievements.kt`, `core/Streaks.kt`, `stats/`), Party Toolkit (8 tabs incl. Score Keeper,
Who Pays, Game Clock, Round Tracker) (`docs/PARTY_TOOLKIT_DESIGN.md`, `PAUSED-2026-10-18.md`).

### 2.15 The Rust sim core's role

`gamesuite-sim` is a line-for-line port of the Air Hockey physics/collision/scoring loop so the 60 Hz tick avoids GC
pauses (`rust/gamesuite-sim/src/lib.rs:1-20`); state is owned by an `AirHockeySim` UniFFI object driven by `tick(dt)`
and read by `snapshot()`. It uses unseeded `rand::random` (`lib.rs:450-458`), has no serialisation for the wire, no
rollback or lockstep support and no Dart binding (UniFFI is generating Kotlin here, `uniffi-bindgen`).
`gamesuite-audio` is the ambient pad synth. Neither participates in multiplayer. **Verdict: not reusable for Olive
Branch, and not sensible via FFI** (section 4, row 24).

### 2.16 Tests: what is verified and how

- `app/src/test` + `shared/*Test`: 381 test files; the wave-3 commit message reports "5224 unit tests, 0 failures"
  (self-reported, not re-run by me).
- **`FakeRelay`**: an in-memory relay that stamps `fromPlayerId`, never echoes to the sender, and delivers only in `pump()`
  so a send never re-enters the receiver on the sender's stack (`app/src/test/.../transport/FakeRelay.kt:1-60`). Used by
  `NetworkedSeatAuditTest`, every `*NetworkedTest`, `UnoNetworkedEndToEndTest`.
- **Hostile-peer tests**: `OnlineTransportIdentityTest` (scripted relay via MockWebServer asserting exact frames),
  `LanTransportIdentityTest` (a hostile raw-socket guest), `server/identity-test.js` (attacks the relay; confirmed to fail
  against the original relay), and a control in `NearbyIdentityEndToEndTest` that reproduces the old attack.
- **Mutation checking by hand**: one deliberate breakage at a time against the tests that should catch it (README:2262-2272).
- **Drift guard across languages**: `server/gen-seat-ranges.js --check` regenerates `seat-ranges.json` from the Kotlin Hub
  specs and exits 1 on difference, plus `HubSpecServerParityTest` (`server/gen-seat-ranges.js:1-22`,
  `HubSpecServerParityTest.kt:23-36`). This is the **same pattern** Olive Branch uses for vectors.
- **Cross-device bot runner**: `LanBotMatchRunner` + `LanBotMatchInstrumentedTest` drive a full bot-vs-bot match over a real
  LAN between two processes/devices, each deciding only for its own seat (`shared/src/jvmMain/.../LanBotMatchRunner.kt:1-40`).
- **Not verified**: Nearby on any hardware since the wave-3 hardening, Fold inner screen, quick-chat client (not built),
  host-left dialog, relay deployment (`UNBUILT-ITEMS.md:A,F,G`).

### 2.17 Verification ladder for the capabilities that matter here

| Capability | Level | Basis |
|---|---|---|
| UNO over Nearby, 2 devices (deal, plays, guest intent, wild colour) | **D** | README item 11 (Fold 5 + Tab S9). Multi-round, challenge, catch-uno, >2 devices, reconnect: not driven (README:621-635) |
| Host-assigned seat ids, endpoint identity map, admission policy | U | `NearbyRosterTest`, `EndpointIdentityMapTest`, `NearbyAdmissionTest`; no 2-device run (README:2224) |
| Relay protocol, reconnect, retirement, rate limits | E | `server/*-test.js`, `OnlineRelayEndToEndTest` |
| Per-recipient hand redaction | U | `UnoNetworkedGuestTest`, `TileNetRedactionTest`, `NetworkedSeatAuditTest` |
| Spectator, late join, session health | U | `UnoSpectatorTest`, `OnlineLateJoinResponderTest`, `SessionHealthTest` |
| Nearby reconnect, ready check, kick on Nearby, idle timer, host migration | N | `MultiplayerTransport.kt:54-58`, `UNBUILT-ITEMS.md:A` |
| Quick-chat client, matchmaking client, deep links | N | `UNBUILT-ITEMS.md:A` |
| Bots "as transport fake players" | C | README design note vs `UnoGame.kt:712` |

---

## 3. Inventory of Olive Branch's current play-together process (origin/main @ c09ecd5)

### 3.1 Architecture in one picture

```
games_hub.dart (hard-coded tiles)  ->  game_<x>.dart screen  ->  LocalPairingController (ChangeNotifier)
                                                                    |-> LocalDiscovery  (bonsoir mDNS, '_olivebranch._tcp')
                                                                    |-> LocalSessionServer (dart:io HttpServer, POST /turn)
                                                                    '-> LocalSessionClient (one HttpClient POST per turn)
```

### 3.2 Discovery and session lifecycle

- **Discovery**: `LocalDiscovery` broadcasts and browses `_olivebranch._tcp` with TXT `role` and `name`
  (`local_discovery.dart:42,65-108`). The service name is `'$displayName-$role'` and the TXT `name` is the display name
  (`:92-96`); callers pass the *child's* name when the child's device plays (`games_hub.dart:102`, `localName`).
  A device filters out its own broadcast (`:136`), a found service must be resolved before it is connectable
  (`:123-143`), and a vanished service raises `lost` (`:144-146`). **D**.
- **Transport**: `LocalSessionServer.start()` binds `InternetAddress.anyIPv4` port 0 (all interfaces; the fix for the
  VPN-interface race found on hardware) and serves exactly one route, `POST /turn`; a body that does not parse as a JSON
  object gets 400; there is no auth, no sender identity and **no body-size cap** (`local_session.dart:81-104`,
  `:91`). `LocalSessionClient.sendTurn` makes a fresh `HttpClient`, POSTs JSON with a 5 s timeout, raises a calm
  `LocalSessionException` on failure (`:125-157`). The server never writes a response body; "need the answer" flows need an
  independent reverse POST (memory + `game_uno.dart:55-62`). **D**.
- **Pairing controller**: phases `searching, found, peerLost, error` (`local_pairing.dart:65`); `mySide` is derived from the
  device's *own* role only (`role == 'ivy' ? Side.a : Side.b`, `:89`); `start()` checks for a local network, starts the
  server, then discovery (`:118-143`); first resolved peer wins and later resolutions are ignored while a peer is held
  (`:145-156`); on `lost` the peer is **cleared** so a re-resolution can land (the hardware-found fix) and the phase becomes
  `peerLost` (`:158-172`); `sendTurn` is a no-op when there is no peer (`:180-184`) and moves to `error` on a transport
  failure (`:185-189`). **D** for the pair/peer-lost/re-found cycle (a real OS kill of the tablet app was recovered).
- **Capacity**: exactly two physical devices; one device may host several seats (`game_seat.dart:1-20`, MASTERFILE
  "Right now, together", `MASTERFILE.md:2763-2780`).

### 3.3 Game catalogue and how games register

There is **no game contract**. A game is a `StatefulWidget` that constructs its own `LocalPairingController`, subscribes to
`incomingTurns`, and defines its own payload shape (`game_uno.dart:150-200`, `game_connect4.dart:119-162`,
`game_war.dart:218-296`). Registration is by hand-editing `MoreGamesSections` (`games_hub.dart:152-178` for the five
"on this table" games) and two separate age tables, `hubGameMinAge` and `localPlayMinAge`
(`game_logic.dart:248,267`). Two older registries exist for other purposes: `GameMeta`/`catalogue` for the async
turn-based kinds (`game_logic.dart:49+`) and `LiveGame`/`register()` for during-a-call games, which refuses any game
whose `minViableLatencyMs < 200` (`live_games.dart:44-86`).

### 3.4 Wire formats today (four dialects)

| Game | Discriminator | Messages | Cite |
|---|---|---|---|
| Uno | `type` | `uno_state_delta` (authority to peer: `myHandForPeer`, `opponentHandCount`, discard, colour, mover, winner, `unoVulnerableSeatId`, `pendingWildDrawFour`), `uno_action` (peer to authority) | `game_uno.dart:319-343,356-460` |
| War | `type` | `war_deal` (26 cards to the peer), `war_reveal` (`roundNumber`, `played`) | `game_war.dart:236-296` |
| Connect 4 | `type` | `connect4_move{column}` | `game_connect4.dart:138,148` |
| Pictionary | `kind`+`turnKind` | `drawingRevealed`, `guessSubmitted`, `guessResult` (word present only when solved) | `game_pictionary.dart:60-110` |
| Puzzle | `kind` | `piecePuzzle{puzzleId,...}` | `game_puzzle.dart:85,99` |
| Twenty Questions | none (bare payload) | prompt, rounds, leader | `local_session_test.dart:20` |

No version field, no session id, no sequence number, no timestamp, no sender, no digest, no mac in any dialect.

### 3.5 Turn sync model per game

- **Uno**: authority-with-redaction. The dealing device (Side.b) holds the only `UnoSession`; the other device receives its
  own full hand and the opponent's *count* only (`game_uno.dart:49-62,319-343`). Peer actions are requests the authority
  validates and **always answers** with a fresh state, a bug found by review where a silent refusal stranded the peer on
  "Sending..." (`:356-371`). vs-peer is fixed at 2 seats, vs-CPU is 2-4 seats on one device (`:40-48`). Hidden information
  is correct for two seats; teammates' hands never share a device by design (`game_seat.dart:28-57`, memory note).
- **War**: each device holds its own pile; the dealer sends the peer's 26 cards once (`war_deal`), then reveals are
  exchanged (`game_war.dart:236-296`). A `war_deal` is accepted from any POST at any time and replaces the game
  (`:275-286`).
- **Connect 4**: **lockstep replicated**. Each side applies the other's `connect4_move` to whichever side is "to move"
  locally (`game_connect4.dart:148-162`), having already applied its own move optimistically before sending
  (`:130-139`). "Play again" is purely local on each device (`:164`).
- **Pictionary / Puzzle**: finished-snapshot-per-turn exchanges.
- **Randomness**: `Random()` unseeded on the dealing device (`game_uno.dart:155`, `game_war.dart:218`,
  `live_games.dart:202-214`); the dealer functions take an injectable `Random` (`dealUno(seatOrder, _rand)`,
  `dealWar(_rand)`), which is what makes seeded tests possible.

### 3.6 Child-safety guardrails already in code

`liveForbidden` lists `score, points, streak, record, best, highScore, reactionMs, accuracy, rank, timeLeft, countdown`
and `auditLiveView()` walks any outgoing payload at any depth; every game calls it before `sendTurn`
(`live_games.dart:367-401`, `game_uno.dart:337`, `game_war.dart:260`). It caught a real collision (a field named `points`
silently refusing every drawing) on hardware (`game_pictionary.dart:60-72`). The audit is **send-side only**. Uno reports
only the winner of the round, never a tally (`game_uno.dart:36-40`); no game persists win/loss.

### 3.7 Reconnect and peer-lost

A "stepped out of range" message is shown while the peer is lost and the local game view is kept (`local_pairing.dart:158-172`,
each game's `build()`, e.g. `game_connect4.dart:215-237`). **Nothing is re-sent when the peer is found again**, and
`sendTurn` during the gap is dropped without a trace (`local_pairing.dart:181-184`). The wording follows §5.23.2.
There is no resume after process death (the hardware run had to re-pair "from scratch").

### 3.8 Co-viewing (designed, parked)

`co_view_logic.dart` is the strongest existing message design in the repo: sealed `CoViewMsg` with a `seq`, a `maxMessageBytes`
cap, C1 (only a guardian leads), C2 (every inbound message untrusted: parsed, size-capped, range-checked), C3 ("a stale or
replayed seq is ignored, which is what makes a mid-session switch of transport safe"), C4 (allowance bounds)
(`co_view_logic.dart:1-20,37-41`); an abstract `CoViewTransport` whose inbound messages arrive *with the sender's
authenticated `Principal` supplied by the transport, never read from the body* (`co_view_session.dart:1-52`), and
an in-memory `LoopbackTransport.pair` for tests (`:34-58`). Golden vectors are generated by the TS engine and replayed by
the Dart port, and CI fails if the engine changes without regenerating (`tools/gen-coview-vectors.mjs:1-8`,
`tools/verify.sh:59`). The design doc is `docs/superpowers/specs/2026-11-07-co-viewing-design.md` (owner decisions 1-4
recorded; PR #128). **This is the template for the play envelope**: it is GameSuite's identity rule plus sequence numbers
plus golden vectors, already in the repo.

### 3.9 Online side (parked)

`packages/game-sync/src/table.ts` is a 2-seat, checkers-only relay core: T1 opaque table id, T2 single-use join token, T3
server-assigned seat on every relayed message, T4 family-graph authorisation, T5 minutes-long TTL, T6 turn alternation,
rate bucket (`RATE_CAPACITY = 8`) and `MAX_MESSAGE_BYTES = 1024`, T7 **no reconnect** ("either seat dropping closes the table")
(`table.ts:11-50,244-265`). The client entry is `networked_checkers_lobby_screen.dart` (dev-login based). Parked by the
offline-first direction.

### 3.10 Tests and verification

- `local_session_test.dart`: 6 real-loopback HTTP tests (round trip, in-order sequential turns, malformed refused, unknown
  path 404, closed port fails honestly, no banned phrase) (`:12-96`). **E**.
- Engines: `uno_session_test.dart` (37 tests), `uno_bot_test.dart`, `uno_deck_test.dart`, `game_war_test.dart` (13, incl. a
  two-sided protocol simulation), `connect4_engine_test.dart`, `connect4_bot_test.dart`, `together_puzzle_test.dart` (11),
  `game_pictionary_wire_test.dart` (10, incl. the word-secrecy guard), `perf_local_discovery_dispose_test.dart` (4). **U**.
- **The vs-peer widget path is not unit-testable today** and says so: `game_uno_test.dart:1-14` covers vs-CPU only because
  vs-peer "needs a genuine mDNS pairing handshake between two real devices". There is no in-memory transport for games
  (the only one is `LoopbackTransport` for co-view).
- Hardware: Twenty Questions full round both directions, Connect 4 vs-CPU, War real deal 26/26, Pictionary and Uno
  partially (memory notes), two real bugs fixed (VPN-interface bind race, stuck peer-lost). The newest client changes have
  not been run on a Fold 5 or Tab S9 FE (`MASTERFILE.md:36`).

---

## 4. Gap analysis

Key. **(a)** Olive Branch already has an equal or better one. **(b)** Lacks it and needs it. **(c)** Lacks it and
should not adopt it. Adoption kinds: **design** = port-the-design, **protocol** = port-the-protocol (wire-compatible),
**vectors** = port-the-test-vectors, **code** = reuse-code. Nothing is **protocol** or **code** here because the two apps
never interoperate and the languages differ; the one place wire compatibility could matter is the parked relay (row 19).

| # | GameSuite capability | Olive Branch today | Class | Kind | Reasoning |
|---|---|---|---|---|---|
| 1 | Game contract (`GameModule`, `GameContext`, `PlayerInfo`, Hub spec) | Per-screen ad-hoc; hand-edited tile list; two age tables | **b** | design | Needed so games share pairing, sessions, notices, tests (5.3). Do not copy `GameCategory`/`PlayMode.DUAL_SCREEN`; fold/tabletop is a layout concern (already `ff.Posture`). |
| 2 | `MultiplayerTransport` with transport-stamped sender | `LocalPairingController` is a transport but stamps nothing | **b** | design | The stamped-sender rule is the single most valuable idea (`MultiplayerTransport.kt:32-42`). co-view already follows it (`co_view_session.dart:1-52`). |
| 3 | Admission: neutral advertised label, accept only while lobby open, seat cap, host-assigned ids | mDNS broadcasts the child's name; first peer wins; no confirmation; any LAN device may POST | **b** (safety) | design | `NearbyAdmission.kt:9-30`, `NearbyRoster.kt:116-199`. Present exposure, see 5.2. GameSuite's own KDoc notes Nearby `authenticationDigits` are unused (`NearbyConnectionsTransport.kt:54-55`): GameSuite never got to a confirmed pairing either. |
| 4 | Seat grid, CPU fill, ready check (Online) | CPU seats only in vs-CPU Uno; 2 devices | **a / c** | none | Two devices, one grown-up and one child: a ready check is a screen of friction. Ready = both are on the Found screen. CPU fill is already in vs-CPU. |
| 5 | Authoritative host + full-state `StateSync` + version | Uno same shape, no version; Connect 4 lockstep | **a** for Uno, **b** for versioning | design | Keep the shape; add the missing ordering (item 1). |
| 6 | Intent validation against the stamped sender | Authority checks `turnSeatId` but cannot know who sent | **b** | design | Needs sender binding (item 2). |
| 7 | Per-recipient hidden-hand redaction | Uno: `myHandForPeer` + count | **a** | none | Equal for 2 seats. Add a golden vector for the redacted payload so a refactor cannot leak (item 5). |
| 8 | Seeded/deterministic shuffles | Unseeded `Random()`; injectable | **b** (modest) | design + vectors | GameSuite itself does **not** have this (host-shuffles once, snapshot carries pile order). Value is test determinism and snapshot restore, never lockstep sharing in hidden-info games (5.6). |
| 9 | Reconnect: grace, token, `RequestState`, host re-broadcast | Peer-lost message only; no resync; silent drop | **b** | design | Highest felt value (5.1, 5.4). |
| 10 | `SyncEpoch` (session-scoped counters) | No counters at all | **b** | design | Replaced by a random `sid` in the envelope (simpler than epoch arithmetic). |
| 11 | Session-end states + one chrome notice (`sessionNoticeFor`) | Each game renders its own peer-lost view | **b** | design | `SessionHealth.kt:35-75`; copy must follow §5.23.2 ("Nothing is lost"). |
| 12 | Spectator (read-only, redacted stream) | None; exactly 2 devices | **b-later** | design | Grown-up "co-viewer" is attractive but needs a third device or a mirror; see 5.9. Design the role into the envelope, do not ship. |
| 13 | Late-join responder (`Hello`) | N/A (2 devices; Found screen) | **a** | none | `hello` in the envelope replaces it. |
| 14 | Rematch (`PlayAgain`) | Local-only reset per device; can diverge | **b** | design | Needs a handshake that is gentle for a child (5.5). Avoid GameSuite's hole (any seat, any time). |
| 15 | Bots: tiers, public-information-only, host drives, never a guest | 3-tier `uno_bot.dart`, `connect4_bot.dart`; vs-CPU local | **a** | none (rule only) | Adopt the one rule: CPU seats are driven by the authority device only (`UnoGame.kt:712-713`), relevant if CPU seats ever join vs-peer. |
| 16 | Teams (`teamId`) | `Seat.teamId`, interleaved so teammates never share a device | **a (better)** | none | `game_seat.dart` encodes privacy as a device boundary; GameSuite's lobbies cannot assign teams at all. |
| 17 | `ResumableGame` snapshots; Undo | None for any game; peer-lost keeps in-memory state only | **b** | design | OS killed the tablet app during hardware testing. Authority-side snapshot to the local store (5.4). GameSuite refuses to resume networked games (`UnoGame.kt:173`); Olive Branch's 2-device case differs and can do better. Undo: no (a child taking back a move is a design call, not a transport one). |
| 18 | Quick-chat (phrase ids, relay allowlist, rate limits, mute) | None | **c** (now) | none | The server half is the best "no free text" design in either repo, but a child and grown-up in the same room need no chat, and the client half is unbuilt even in GameSuite (`03-safety-privacy.md:4.2`). Revisit as grown-up-curated "reactions" only (decision D5). |
| 19 | Relay: rooms/codes/peek/lock/kick/rate limits/matchmaking/rating | `table.ts` (checkers only, 2 seats, no reconnect) | **c** now, **b** when online unparks | design | Strangers, public rooms and Elo are the opposite of the product. If online resumes, port *rooms-meta, ratelimit, reconnect tokens, retirement* into `scaffold/server` as TS, not the GameSuite server. |
| 20 | Relay hardening: frame cap, rate bucket, sanitised names, caps | `table.ts` has them; the **local** server has none | **b** | design | Frame cap and string sanitising for peer-supplied text on the local path (5.2). |
| 21 | Stats, achievements, streaks, win/loss history | None, by design | **c** | none | P2. Do not adopt `core/Achievements.kt`, `core/Streaks.kt`, `stats/`, `LocalOutcomes`. (GameSuite has its own open bug: equal winners each recorded as WIN, `UNBUILT-ITEMS.md:C`.) |
| 22 | Party Toolkit | None | **b** (subset) | design | Dice, coin, first player, turn order, number-free sand timer fit; Scoreboard, Life Points, Round Tracker, Game Clock, Who Pays do not (P2, P6) (5.10). |
| 23 | Fold-aware layout, reduced motion, TalkBack notices | `form_factors.dart` postures, §8.21 a11y, per-game tabletop layouts | **a** | none | Olive Branch's rules are stricter (read-aloud, targets). Do not import GameSuite chrome. |
| 24 | Rust sim/audio core | Dart-only | **c** | none (**not** code reuse) | Air Hockey physics and a pad synth. No networking, unseeded RNG, Kotlin-only bindings. Dart FFI via `uniffi-dart` is third-party and experimental; a cross-compile toolchain (cargo-ndk, 3 ABIs) and a second build system for zero multiplayer benefit. |
| 25 | `FakeRelay` + engine tests over it | `LoopbackTransport` for co-view only; vs-peer untested | **b** | design | Highest test value per line (5.3, 5.12). |
| 26 | Hostile-peer test suites, mutation checks | None for the local server | **b** | design | Add a hostile-peer suite for `/turn` (5.2, 5.12). |
| 27 | Generated-JSON drift guard (`gen-seat-ranges.js --check`) | `tools/gen-*-vectors.mjs` | **a (equal)** | vectors | Same pattern both sides; use Olive Branch's. |
| 28 | `LanBotMatchRunner` (bot-vs-bot over a real LAN) | `main_local_*_test.dart` dev entries (manual) | **b** (nice) | design | A scripted two-device bot match makes the hardware pass repeatable (5.12). |
| 29 | `LanMultiplayerTransport` (persistent TCP, host relays/stamps, newline-JSON) | One POST per turn | **b-optional** | design | Gives instant presence and ordering. Olive Branch deliberately chose dumb POSTs (`local_session.dart:32-37`); decide after the envelope exists (D2). Not wired into GameSuite's app either. |
| 30 | Idle-turn timer / AFK kick | None | **c** | none | A timer is pressure (the brief's rule); the child must never be timed out or blamed. Use a calm "waiting for X" and an always-available leave. |
| 31 | Host migration | None | **c** | none | Two devices; if the authority device is gone the game pauses calmly or ends. Too heavy, and hidden-info games cannot migrate without the successor holding everything (`WAVE-5...:272-290`). |
| 32 | Desync detection | None | GameSuite has none either | design (new) | Cheap digest for lockstep games (5.8). |
| 33 | Nearby Connections (Play Services) | mDNS (`bonsoir`) | **c** | none | Android-only, Play Services dependency, legacy location permission on API 29-31 (`03-safety-privacy.md:1`), and iOS is a stated target. The Flutter Nearby plugin ecosystem was already judged "thin and partly stale" in GameSuite's own engine decision (`ENGINE_DECISION.md:204,231`). mDNS is hardware-verified here. |
| 34 | Free-text display names to strangers | Names are family-local | **c** | none | GameSuite's own audit rates this High (N1). |
| 35 | Deep-link/share invites, room-code UX | N/A | **c** | none | Codes and invites imply strangers or the internet. |

---

## 5. What Olive Branch actually needs: prioritised, sized list

Sizes: **S** < 1 day, **M** 1-3 days, **L** > 3 days (same legend as GameSuite's audits). Ordered by value to a child and
a grown-up in the same room first, then risk. Dependency graph at the end of 5.1.

### 5.1 Priority 1. The play envelope: versioned, sequenced, resumable (M)

**Why first.** It fixes three live defects at once: silently dropped turns, reordered full-state packets, and no resync
after "re-found". It is also the base for everything else.

**GameSuite sources.** `MultiplayerTransport.kt:32-61` (identity rule, `onReconnected`), `UnoNetMessage.kt:22-79`
(StateSync/Intent/RequestState), `CheckersNetMessage.kt:27-49` (`baseVersion`), `UnoGame.kt:87-115,875-905` (drop-old,
host-only state, startup race), `SyncEpoch.kt:5-35` (why session scoping matters), README:2273-2279 (resync sent on the dead
socket). Olive Branch's own `co_view_logic.dart:1-20` (C2, C3) is the closer template and should be reused for style.

**Olive Branch files to change.** New pure module `scaffold/packages/play-sync/src/envelope.ts` (TS reference) with
`scaffold/tools/gen-playsync-vectors.mjs` and `packages/play-sync/test/vectors.json`, a Dart port
`client/lib/play_envelope.dart` (+ `play_envelope_test.dart` running the shared vectors), then
`local_pairing.dart` (wrap `sendTurn`/`incomingTurns` in the envelope, queue while peer-lost, emit on re-found),
`local_session.dart` (body cap, content-type check). Migrate games one at a time, shimming the legacy payloads for one
release (D10): Connect 4 first, then War, Puzzle, Pictionary, Uno last.

**Proposed envelope v1** (JSON, UTF-8; a proposal to review, not a decision):

```json
{ "v": 1, "sid": "9f2c41d07a3b88e1", "n": 17, "ack": 15, "t": "intent",
  "g": "uno", "p": { "...game payload..." }, "d": "9f3a1c2e", "mac": "..." }
```

| Field | Rule |
|---|---|
| `v` | Integer protocol version. A receiver accepts `v <= own`, ignores unknown fields (GameSuite `NetJson`, `RemoteStateChecks.kt:11-12`), and answers `hello_ok` with the highest common version. A message with no `v` is the legacy dialect, handled by a shim for one release. |
| `sid` | 64-bit random session id minted by the authority at `hello`. Replaces GameSuite's `SyncEpoch` (a fresh `sid` simply resets both counters, no epoch arithmetic). Messages with an unknown `sid` are dropped (stray/hostile). |
| `n` / `ack` | Per-sender monotonic counter and the highest peer `n` seen. Receiver drops `n <= lastN` for ordering-sensitive kinds (`event`, `intent`); a `state` snapshot is idempotent, latest `n` wins, older is dropped. A gap in `event` kinds triggers `req_state`. This is `co_view_logic.dart` C3, applied to games. |
| `t` | `hello`, `hello_ok`, `state` (authority to peer, already redacted for that recipient), `intent` (peer to authority), `event` (lockstep move), `req_state`, `rematch`, `rematch_ok`, `bye`. |
| `g` | Game id from the registry (5.3). |
| `p` | Game payload. **Audited by `auditLiveView` on send and on receive.** The receive-side audit is new: a peer must not be able to push `score`/`streak`/`countdown` keys into the child's screen. |
| `d` | Optional 32-bit digest of the *public* state after applying the message (5.8). |
| `mac` | Optional until D1 is decided; truncated HMAC-SHA256 over the canonical fields with the session key from 5.2. |
| Caps | Default 8 KiB; 64 KiB only for the stroke snapshot kinds; larger is rejected with 413 and never parsed (co-view uses 512 bytes, `co_view_logic.dart` `maxMessageBytes`). |
| Sender identity | The receiver derives the sender from the authenticated session, **never** from `p` or a `from` field (GameSuite rule, `MultiplayerTransport.kt:32-42`; co-view rule, `co_view_session.dart:1-10`). |

**Reconnect/resume behaviour (this is the GameSuite lesson applied).**
1. `sendTurn` while no peer is held must **queue** the envelope (bounded, e.g. 32) and mark it unsent, not return
   (replaces `local_pairing.dart:181-184`).
2. On re-found, both sides exchange `hello{resume:true, sid, lastN}`; the authority answers with a fresh `state` for the
   recipient (redacted), and re-sends any unacked `intent`s once. The resync is sent only after the peer's `hello` arrives,
   i.e. after the peer's server is reachable (GameSuite's "resync sent to the dead socket" bug, README:2273-2279).
3. A request the authority refuses is still answered with the unchanged `state` (already Olive Branch practice,
   `game_uno.dart:356-371`; GameSuite's equivalent is `UnoGame.kt:892-899`). Make it a rule of the envelope, not a
   per-game remark.
4. Startup race: a guest that opens the game screen after the authority dealt sends `req_state` on `hello_ok`
   (GameSuite `UnoGame.kt:96`). Today `_dealForPeer` sends once (`game_uno.dart:309-317`).

**Child-safety implications.** Strictly positive: no new data; errors stay calm (the existing `LocalSessionException`
wording, `local_session.dart:148-157`); the receive-side audit closes a P2 path. Keep every new user-visible string inside
§5.23.2's banned-phrase list. Nothing in the envelope may carry a name, timestamp of play, or any tally.

**How to test.** Golden vectors (TS engine generates, Dart replays, CI fails on drift, exactly
`tools/gen-coview-vectors.mjs:1-8` / `verify.sh:59`): accept/drop for `n`/`ack`, unknown `sid`, oversized, wrong `v`,
legacy shim, the digest function, the redaction of a Uno `state`. Then the in-memory harness of 5.3 for scripted
disconnect/reconnect. Hardware checks in 5.12.

### 5.2 Priority 2. Pairing admission and sender binding (M)

**Why.** Today any device on the same Wi-Fi can POST a turn, and the child's name is broadcast to that Wi-Fi.
This is the exact family of problems GameSuite's "Transport identity hardening" pass found and fixed
(README:2188-2252) and the one it left half-done for Nearby (no per-guest approval, `authenticationDigits` unused,
`NearbyConnectionsTransport.kt:51-56`). A shared Wi-Fi at a grandparent's block, a hotel, a school or a flat is a normal
setting for this app.

**GameSuite sources.** `NearbyAdmission.kt:9-30` (accept only while the lobby is open and a seat is free, neutral label
plus a 4-character code), `NearbyRoster.kt:116-199` (host assigns ids, guest id is a proposal), `NearbyLobbyProtocol.kt:10-35`
(why endpoint ids are per-observer), `LobbyIdentity.kt` (`guestSeatIndex` rejects blank/duplicate/seat 0),
`OnlineLobbyProtocol.kt:156-170` (act only on a `GameStart` from the host id), `OnlineLobbyProtocol.kt:78-85` and
`NearbyLobbyProtocol.kt:75-76` (`sanitized()`/`lobbyRejectionText`: strip control characters, cap length for any
peer-supplied string), `server/index.js:46-58` (secret per-seat token; retirement), `identity-test.js` (the attack list).

**Olive Branch files to change.** `local_discovery.dart` (advertise a neutral service name and TXT such as
`olive-<4 hex>` with no `name`, no child name, role only as `child|guardian` or not at all), `local_pairing.dart`
(a `confirm` phase between `found` and `playing`: the **grown-up** taps a plain-words confirmation, never the child; peer
string sanitised before display, e.g. `game_war.dart:374` currently renders `'Found $peerName nearby'`),
`local_session.dart` (add `POST /hello`, per-session key, constant-time token compare, remote-address pinning to the
resolved peer, 413 on oversize, and the existing 400 on junk).

**Design options (decision D1).**
- **A (recommended):** ephemeral X25519 key agreement in `hello`; both screens show a 2-digit-pair short authentication
  string derived from the shared secret; the grown-up confirms "same numbers"; the session key HMACs every envelope.
  This is the numeric-comparison idea GameSuite left unused. Needs one dependency (e.g. the `cryptography` package),
  which is local-only and offline.
- **B (minimum):** admission window plus a grown-up tap plus a random session token carried in every envelope and remote
  address pinning. Stops accidental and casual cross-talk; does not stop an active attacker on the same LAN (HTTP is
  cleartext).
- **C:** do nothing (status quo). Not recommended.

A short numeric code used as a *shared secret* is **not** adequate (10^6 HMAC trials offline); use it only as a confirmation
string over a key agreement.

**Child-safety implications.** This is the P-relevant change. The child never enters or reads codes; the grown-up confirms.
A child's name is never in a network broadcast. Failures stay silent from the child's point of view ("Looking nearby...")
and informative only on the grown-up's confirm screen. It also serves §5.17's contact rules: a stranger device can no longer
inject content (Pictionary guess text, a `war_deal`) into the child's screen.

**How to test.** Unit: constant-time compare, replay of a captured `hello`, remote-address mismatch, sanitiser
(control characters, length, bidi marks). Hostile-peer suite (GameSuite's `identity-test.js` style, one attack per test,
confirmed to *fail* against the old server): third device posts `/turn` without a token, with a stale `sid`, with an
oversized body, with a forged `war_deal`; a second mDNS advertiser of the same service type arriving first. Hardware: 5.12.

### 5.3 Priority 3. A shared game contract, registry-driven hub, and an in-memory harness (M)

**Why.** Five games each re-implement pairing, subscription, peer-lost views, payload parsing and (not at all) tests.
The contract is what lets items 1, 2 and 4 be written once. The in-memory harness is what lets the vs-peer paths be tested
at all (`game_uno_test.dart:1-14` admits it cannot).

**GameSuite sources.** `GameModule.kt:11-44`, `GameContext`/`PlayerInfo` (`:88-104`), `GameHubSpec` (`GameHub.kt:166-193`) and the
spec-driven lobbies, `FakeRelay.kt:1-60`, `NetworkedSeatAuditTest` (the "every networked engine, 3-4 seats, no leak" sweep),
`HubSpecServerParityTest`.

**Proposal (names are placeholders).**

```dart
class PlayGameSpec {            // one const per game; the hub and age gates are generated from this
  final String id, title;
  final int minAge, minSeats, maxSeats;
  final Set<PlayMode> modes;    // passAndPlay, vsCpu, pair   (online reserved, parked)
  final bool competitive, hiddenInfo;
  final int protocolVersion;
  final PlayGame Function(PlayContext) create;
}
class PlayContext { PlayMode mode; SeatRoster roster; String localSeatId; PlayTransport transport; Random rng; }
abstract class PlayGame { void start(); void onEnvelope(PlayEnvelope e); String? snapshot(); bool restore(String s); void dispose(); }
abstract class PlayTransport {  // implemented by LocalPairingTransport and LoopbackPlayTransport
  Stream<PlayEnvelope> get incoming;  Stream<PeerPresence> get presence;  Future<void> send(PlayEnvelope e);
}
```

Reuse what exists rather than invent: `SeatRoster`/`Seat` (`game_seat.dart:28-75`) is already the seat model;
`CoViewTransport` + `LoopbackTransport.pair` (`co_view_session.dart:24-58`) is already the transport-plus-in-memory-twin
pattern; `GameMeta`/`LiveGame` already carry min age and co-op flags. The spec **replaces** `hubGameMinAge`/`localPlayMinAge`
and the hand-written tiles in `games_hub.dart:152-178`, and `register()`'s "refuse reflex games" rule
(`live_games.dart:80-86`) becomes a spec validation (`competitive` games need a handicap path per §9.2; reflex games
rejected; payload audit mandatory). Keep `Side` out of new code: seats are string ids (the Uno engine already did this,
`game_seat.dart:1-20`), so a later third device is possible without a rewrite (D4).

**Olive Branch files.** New `client/lib/play_game.dart`, `play_transport.dart`, `play_loopback.dart`;
`games_hub.dart`, `game_logic.dart` (age tables), the five `game_*.dart` screens (thin wrapper: UI only), tests.
Do not rewrite game engines (`uno_session.dart`, `connect4_engine.dart` are pure and tested).

**Child-safety implications.** The spec is the natural place to make the P-rules structural: `hiddenInfo` games must declare
a redaction function (checked by a test); a `competitive` flag requires the §9.2 handicap path; no spec field may be named
in `liveForbidden`. Nothing child-visible changes.

**How to test.** A `LoopbackPlayTransport.pair()` with a scripted drop/reorder/duplicate/delay knob (the GameSuite
`FakeRelay.drop`/`pump` idea, `FakeRelay.kt:60+`). Sweep test over every registered spec: starts, syncs, no hidden-info leak
through the transport, peer vanishing mid-match leaves a calm state, as `NetworkedSeatAuditTest` does. Add a
`HubSpec` parity test like `HubSpecServerParityTest` so the min-age table and the registry cannot diverge.

### 5.4 Priority 4. Calm session end and resume (M)

**Why.** Today: peer lost shows a message but the game's future is undefined; an OS kill loses the game; nothing is shared
between games.

**GameSuite sources.** `SessionHealth.kt:5-75` (`sessionNoticeFor`: ended session beats everything; own reconnect beats
someone else's absence; spectators and the local device never report themselves), `SessionHealthOverlay.kt`,
`GameChrome.kt:71-72,123-137,201` (leave = abort that records nothing; save before aborting), `Resumable.kt:7-78`
(`snapshot`/`restore` contract: returns false on a stale or corrupt snapshot and leaves the engine untouched; never
throws; carries everything needed to continue honestly, including the draw-pile order).

**Olive Branch files.** `local_pairing.dart` (expose `PairingPhase` plus an `awayFor` duration and a terminal `ended`
after a generous quiet period, calm), a shared `PlaySessionNotice` widget used by every game in place of the five
`_MessageView`/`_Status` copies (`game_war.dart:333`, `game_connect4.dart:234`, ...), `play_game.dart` snapshot hooks, the
local store (the on-device LocalStore from the offline-first work) for the authority snapshot.

**What it should do.**
- Authority device writes `snapshot()` after each committed move to the local store, under a key scoped to the session;
  deletes it on game end or on the grown-up choosing "Finish for now". Never stores an outcome, a tally or a history
  (P2); only the state needed to continue.
- On relaunch a grown-up sees "Carry on with Uno?" The child's screen shows the same calm line as today. The guest side
  stores nothing: it is rebuilt by `hello` plus `state`.
- If the authority device is gone for good, the pair ends calmly: "Nothing is lost. We can start again whenever you like"
  (wording reviewed against §5.23.2; D11), no result recorded.

**Child-safety implications.** The snapshot contains hand contents (child's game state); keep it in the on-device store with
the rest of her local data, cleared by the existing clear-local-data screen. No timers-as-pressure: the "ended" threshold
is silent, never a countdown.

**How to test.** Pure `snapshot`/`restore` round trips per game (GameSuite's rule: reject stale/corrupt, never throw).
Loopback script: kill the authority harness mid-game, rebuild from the stored snapshot, re-found, assert the peer's state
equals before. Hardware: 5.12.

### 5.5 Priority 5. Rematch handshake, authority-only bots, seeded deals, state digest (S + S + S + S)

1. **Rematch (S).** `rematch` from either side, `rematch_ok` from the other, then the authority deals. No "Play again"
   that silently resets one device (`game_connect4.dart:164`). Wording must not pressure ("Again?" is the grown-up's
   voice). Fix GameSuite's hole: honour `rematch` only after a finished game and only from a seated peer
   (README:2288-2290). Base: `TicTacToeGame.kt:473-499`.
2. **Authority-only bots (S).** A rule in the spec and a test: CPU seats act only where `localSeatId` is the authority.
   Base: `UnoGame.kt:712-713`, the 3-4 seat audit finding (`WAVE-5...:628-640`). Needed the moment vs-peer Uno gets CPU
   seats (the engine already supports 2-4 seats).
3. **Seeded deals (S).** `dealUno`, `dealWar` and `newDeck` already take a `Random`. Add a specified PRNG (e.g. splitmix64)
   and a Fisher-Yates with an unbiased `nextInt` implemented identically in the TS reference and Dart, so golden vectors can
   pin "this seed gives this deal". Purpose: test determinism and snapshot size. **Do not** ship the seed to the peer in
   hidden-information games: the seed *is* the deck (see 5.6).
4. **State digest (S).** See 5.8.

### 5.6 Seeded deterministic shuffles for hidden-information card games

What GameSuite actually does is **not** seeded: the host shuffles once with a local RNG and distributes redacted copies, and
resume stores the pile order (`UnoGame.kt:216-217,119-121`). For Olive Branch:
- Lockstep games with **public** randomness (Connect 4 first mover, a shared puzzle id, a dice roll in a table tool) can
  share a seed: both devices derive the same outcome and the digest in 5.8 proves it.
- **Hidden-information** games (Uno, War) must keep the shuffle on the authority only and send redacted copies. A shared
  seed would give the peer the whole deck. Seeds are for the authority's own determinism: reproducible tests, small
  snapshots (seed + move count instead of pile order), and reproducing a reported bug.
- Specify the PRNG and the shuffle in the TS reference and publish vectors; do not rely on `dart:math` `Random(seed)`
  staying stable across SDK versions.

### 5.7 Reconnect and resume: summary of what to copy and what not

Copy: token-less version of "seat is held, peer told 'away' not 'left'" (here: `peerLost` is *away*, ends only by choice or a
long silence); request-state on startup and on re-found; authority re-broadcast on re-found; resync only after the peer is
confirmed reachable; always answer a refused request with the current state. Do **not** copy: retry counts/backoff for a
cloud socket (Olive Branch's retry is mDNS re-resolution), reconnect tokens against room-code strangers (replaced by the
session key of 5.2), the 30 s grace (the child must never feel a clock; use no visible countdown).

### 5.8 Desync detection (new; GameSuite has none)

For lockstep games (Connect 4, tic-tac-toe, checkers if added) attach `d = fnv1a32(canonicalPublicState)` to each `event`;
the receiver recomputes after applying and on mismatch sends `req_state`; the authority replies with `state`. For
authority-with-redaction games (Uno, War) the digest covers only the public fields (top card, colour, turn, counts), which the
peer *can* recompute from the delta it receives, so it catches a corrupted or mis-ordered delta but not a hidden-hand error.
Canonicalisation (key order, number formatting) is the only subtle part and is exactly what golden vectors are for. Keep
`d` optional and ignore it when absent so older builds interoperate. Never show a digest or a mismatch to the child.

### 5.9 Spectator as co-viewer for grown-ups (L, defer; design the role in now)

GameSuite's spectator is the right shape: a read-only role that receives the public view (every hand redacted) and can never
act, enforced in the *engine* not the UI (`UnoGame.kt:862,907-910`, `UnoRedaction.kt:25-34`). For Olive Branch:
- It needs a **third device** (or a mirror of the child's screen), which contradicts today's hard cap of two devices
  (`game_seat.dart:14-20`). Decide D4 before building.
- If built: role `watcher` in `hello`; authority streams `state` redacted for nobody (public view); the watcher sends
  nothing but `hello` and `req_state`; the child's screen shows nothing different. **No scores, no counts beyond the
  rules-required hand size, no names beyond what the table already shows** to anyone (P2).
- It must never become remote control (P11): a watcher has no input path at all. Co-viewing's "guardian leads, child
  follows" (`co_view_logic.dart` C1) is a separate, owner-decided feature; keep it out of games.
- Cheaper stand-ins that need no third device: the grown-up simply plays (the product's actual use), or a one-way
  "show on the big screen" later.

### 5.10 Party-toolkit ideas that fit a family

Source: `docs/PARTY_TOOLKIT_DESIGN.md` and the wave-3 additions (`PAUSED-2026-10-18.md`). The Toolkit is deliberately *not*
`GameModule`s; it is a bundled utility screen, which is also the right shape for Olive Branch ("Table tools" inside Play
together, not new catalogue games).

| Tool | Fit | Notes |
|---|---|---|
| Dice (d6, d4-d20 picker), Coin toss | **Yes** | `PartyToolkitLogic.rollDice/flipCoin` are `Random`-injectable pure functions; port the design and give the vectors a seeded RNG. Show the result, no running tally, no history list for the child. |
| First player / Turn order | **Yes** | "Who goes first?" is a common friction point for a child and a grown-up; random pick with a gentle animation; reduced-motion respected. |
| Teams splitter | **Maybe** | Useful for 2v2 Uno; the family decides teams; no ranking. Olive Branch's interleaved seat model already covers it. |
| Sand timer ("Hourglass") | **Only as a grown-up-chosen, number-free visual** | No digits, no alarm, no countdown the child can fail (the brief's timers-as-pressure rule). Off by default. |
| Random letter / Card dealer | **Maybe** | Fine as an aid to word games; low priority. |
| Scoreboard, Life Points, Round Tracker, Game Clock | **No** | P2: scores and tallies for a child. |
| Who Pays | **No** | P6: financial surface visible to a child. |
| Persistence of tool state | **No** | Nothing persisted except what a grown-up asked for; no history across sessions. |

Size S-M for the first four rows, after items 1-3. Decision D6.

### 5.11 GameSuite bugs and hardening lessons that apply to Olive Branch

From README "Fixes and hardening", "Transport identity hardening", "Reconnect", the code-review and the wave-5 audits:

1. **Sender spoofing**: validate an intent's claimed seat against the transport-stamped sender (`UnoGame.kt:907-934`). Olive
   Branch cannot yet tell who sent a POST (5.2).
2. **Guest accepted state from anyone**: accept `StateSync` only from the host id (`UnoGame.kt:891`; still open for TicTacToe/
   Chess, README:2288). Olive Branch accepts a `war_deal` or a state delta from any POST (`game_war.dart:275-286`,
   `game_uno.dart:434`).
3. **Hidden-info leak** (every hand sent to every peer, fixed by per-recipient redaction): already right here for two seats;
   pin it with a vector.
4. **"Which seat am I" bug** (`humanIndex()` showed the host's hand on a guest, README:604-616): Olive Branch encodes
   `_mySeatId` from the pairing side (`game_uno.dart:190`); keep a test per mode.
5. **Version freeze after host object recreation** (`SyncEpoch`): use a random `sid`, never a counter that restarts.
6. **Resync sent on the dead connection** (README:2273-2279): send state only after `hello`.
7. **Startup race**: a guest listener registered after the first broadcast needs `req_state` (`UnoGame.kt:87-97`).
8. **Silent refusal strands the peer**: always answer (already found independently, `game_uno.dart:356-371`).
9. **Rematch accepted from any seat at any time** (README:2288-2290).
10. **Zombie match when the other side vanishes** (`WAVE-5...:71-73`, fixed by `SessionHealth`): define a terminal state.
11. **Single `onPlayerLeft` setter**: expose observable state, not a one-slot callback (`SessionHealth.kt:14-20`).
    `LocalPairingController` is already a `ChangeNotifier`; keep it that way.
12. **Unbounded and unsanitised peer input**: frame cap and `sanitized()` for names and any peer string shown on screen.
13. **Constants duplicated across languages without a test** (`ONLINE_MAX_SEATS` vs `MAX_PLAYERS_PER_ROOM`, `WAVE-5...:79-80`,
    fixed by `gen-seat-ranges.js --check`): Olive Branch's vector drift guard is the same cure; apply it to the envelope.
14. **Bots driven on the wrong device** (UNO guests sent spurious intents for bot seats): authority-only rule.
15. **Mixed app versions in one match**: omit new fields for old peers, ignore unknown keys, and say "both devices should
    run the same version" out loud (`NearbyLobbyProtocol.kt:30-35`, README:2243-2247 "Upgrade order matters"). Olive
    Branch's two test devices are routinely on different builds (`scaffold/tools/device-sync.sh` exists to push the same live
    build to both, PR #162).
16. **Stats layer defects** (losses recorded as draws; equal winners each recorded as WIN, `UNBUILT-ITEMS.md:C`): a reason not to
    adopt the stats layer at all (P2).
17. **Docs claiming more than the code**: README says bots are transport "fake players"; the engine drives them directly.
    Treat GameSuite README claims as leads to verify, not facts (the verification ladder in 2.17).
18. **Design docs written before code**: `WAVE-5-MULTIPLAYER-DESIGN.md` has a measured "what S4 actually built, with deviations"
    appendix (`:614-676`). That honesty habit (EXISTS / NEW / GAP legend, `:8-9`) is worth copying into any Olive Branch
    play-sync spec.

### 5.12 Real-device test plan (Fold 5 + Tab S9 FE) and automation

Use `scaffold/tools/device-sync.sh` to put the same build on both, the wireless-adb setup in the project notes, and the
existing `main_local_*_test.dart` dev entries. Checks (each is pass/fail and gets a logged result):

1. **Resume after drop**: mid-Uno and mid-Connect-4, turn Wi-Fi off on the tablet for 10 s, on again; both screens show the
   calm line, then the same board; no move lost, none duplicated.
2. **Resume after kill**: kill the authority app, relaunch, "Carry on", same hands (5.4). Kill the guest app, relaunch:
   state rebuilt by `hello`/`state`.
3. **Reorder**: with the authority issuing several state updates quickly (declare, catch, accept in a row,
   `game_uno.dart:385-412`), assert the peer ends on the newest (use an adb-forwarded delay proxy, or a PC relay between the
   two devices).
4. **Hostile peer**: from a PC on the same Wi-Fi, (a) advertise a second `_olivebranch._tcp` service first, (b) POST `/turn`
   without a token, with a stale `sid`, with a 5 MB body, with a forged `war_deal`. Expect: ignored, no UI change on the
   child's screen, no crash, no child name visible in `dns-sd -B`/`avahi-browse` output.
5. **VPN**: always-on VPN on one device (the earlier bind race) with the new `hello`.
6. **Posture**: fold/unfold and tabletop mid-game; state preserved.
7. **Mixed versions**: previous build on one device, new on the other; the legacy shim plays one full game.
8. **Scripted bot-vs-bot over the real transport** on both devices (the `LanBotMatchRunner` idea,
   `LanBotMatchRunner.kt:1-40`) so the pass is repeatable and does not depend on a person tapping.

Hardware verification has a documented failure mode here (screen lock, Doze, mDNS flakiness, wireless-adb drops); script the
runs and keep a note of any device-side cause so a flake is not mistaken for a regression.

### 5.13 Dependency order

```
5.1a envelope + vectors (pure)  ->  5.3 contract + loopback  ->  5.1b migrate games + resume
                  \                                              \
                   '->  5.2 admission + binding (needs hello)     '->  5.4 snapshot/notice  ->  5.5 rematch/bots/seed/digest
5.10 table tools after 5.3.   5.9 spectator only after decisions D4.   Online relay port only after unpark.
```

---

## 6. Risks and open owner decisions (each with my recommendation)

### Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | A hostile or stray device on the LAN can already inject turns and read the child's name from mDNS. | 5.2, ship the neutral label first (a one-line change) even before the crypto decision. |
| R2 | Silent desync (dropped/reordered turns) is happening today and is invisible in tests because vs-peer is untestable. | 5.1 plus 5.3's harness before any new game. |
| R3 | Scope creep: GameSuite is mostly online/competitive. Importing it wholesale violates offline-first and P2. | Section 4 classes (c); this document is the guard. |
| R4 | A crypto dependency and SAS UX add complexity to a flow a grown-up does once. | Option B is the fallback; keep the confirm screen one tap. |
| R5 | Version skew between the two family devices. | `v`, legacy shim for one release, `device-sync.sh`. |
| R6 | Over-engineering a two-device, two-seat system with N-device machinery. | Design seat ids as strings, but build only 2 devices; do not port rooms, queues, ready checks. |
| R7 | Snapshots persist a child's hands and board. | On-device only, scoped, deleted at game end and by clear-local-data, never an outcome (P2). |
| R8 | GameSuite verification is thinner than its docs (2.17); copying "built" code may import unverified behaviour. | Port designs and tests, not code; re-prove on Olive Branch's hardware. |
| R9 | Co-viewing's leader/follower model sits near P11 (no remote control of a child's device). Not part of games, but a spectator or watcher feature must never gain input. | Watcher has no input path (5.9); co-view's own decisions stand. |
| R10 | The two repos share an owner but diverge in language; a "shared protocol" would couple release schedules. | No shared code; share only vectors-style discipline and documents. |

### Owner decisions

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | Pairing security level | A) X25519 + short-string confirm by the grown-up, signed envelopes; B) grown-up tap + session token + address pinning, cleartext; C) status quo | **A**, with B shipped first as the minimum. Neutral mDNS label and body cap now regardless. |
| D2 | Keep one-POST-per-turn, or move to a persistent session (`dart:io` WebSocket upgrade on the same server) | Keep POST + seq/ack; or persistent | **Keep POST** (the stated design, `local_session.dart:32-37`); revisit only if device runs show presence flakiness after the envelope lands. The persistent TCP model exists as evidence in `LanMultiplayerTransport.kt`. |
| D3 | Persist the authority's snapshot to survive an OS kill | yes (authority only) / no | **Yes**, authority only, deleted at game end, no outcomes. |
| D4 | Design for more than two devices (sibling tablet, second grown-up, watcher)? | Strings for seat ids and a `watcher` role, ship 2 only / hard cap 2 | **Design in, ship 2.** Revisit when a concrete family need appears. |
| D5 | Any reactions/quick-chat | none / grown-up-curated phrase ids / emotes | **None now.** If wanted later: phrase ids only, grown-up-chosen set, no sound, no ranking words (GameSuite `quickchat-allowlist.json` is the model). |
| D6 | Build the Table tools subset (dice, coin, who goes first, turn order, number-free sand timer) | yes / no | **Yes, small, after 5.3**; exclude score, life, round, game clock, who-pays. |
| D7 | Share code between GameSuite and Olive Branch | none / vectors only / library | **No code sharing.** Documents and the drift-guard discipline only. |
| D8 | Use the Rust core via FFI | yes / no | **No.** |
| D9 | When online is unparked, which relay | port GameSuite's server / extend `scaffold/server` + `table.ts` | **Extend Olive Branch's server** with GameSuite's reconnect-token, retirement and rate-limit designs; never public rooms or matchmaking. |
| D10 | Legacy payload support window | one release / two / none | **One release** with a shim and a version field; both test devices updated by `device-sync.sh`. |
| D11 | Copy for terminal and away states ("stepped out of range", "Nothing is lost", authority gone) | owner review | Keep §5.23.2 wording; owner to approve the three strings before they ship. |
| D12 | Rematch voice and trigger | grown-up only / either | **Either side may ask; the other accepts**; wording from the grown-up's voice, never "You lost". |

---

## Appendix A. File index

GameSuite (session/wave-3 @ 18d9b53): `shared/src/commonMain/kotlin/com/gamesuite/core/{GameModule,Resumable}.kt`,
`.../transport/{MultiplayerTransport,LocalPassAndPlayTransport}.kt`, `.../games/{tictactoe,checkers,chess,mancala}/*NetMessage.kt`,
`shared/src/jvmMain/.../transport/LanMultiplayerTransport.kt`, `shared/src/jvmMain/.../testing/LanBotMatchRunner.kt`,
`app/src/main/java/com/gamesuite/transport/{NearbyConnectionsTransport,NearbyAdmission,NearbyRoster,NearbyLobbyProtocol,OnlineLobbyProtocol,OnlineTransport,LobbySeats,LobbyIdentity,SessionHealth}.kt`,
`.../core/{GameSessionManager,GameHub,GameHubSpecs,SyncEpoch,RemoteStateChecks,LocalOutcomes,Achievements,Streaks}.kt`,
`.../games/uno/{UnoGame,UnoNetMessage,UnoRedaction,UnoBot}.kt`, `server/{index,rooms-meta,ratelimit,sanitize,quickchat,queue,gen-seat-ranges}.js`,
`app/src/test/.../transport/{FakeRelay,NetworkedSeatAuditTest,OnlineTransportIdentityTest,NearbyIdentityEndToEndTest,SessionHealthTest,HubSpecServerParityTest}.kt`,
`docs/roadmap/{WAVE-5-MULTIPLAYER-DESIGN,UNBUILT-ITEMS,CODE-REVIEW-WAVES-1-4}.md`, `docs/audit/03-safety-privacy.md`,
`docs/PARTY_TOOLKIT_DESIGN.md`, `rust/gamesuite-{sim,audio}/src/lib.rs`, README "Fixes and hardening", "Transport identity hardening".

Olive Branch (origin/main @ c09ecd5): `scaffold/client/lib/{local_discovery,local_session,local_pairing,local_play_screen,live_games,games_hub,game_picker,game_logic,game_seat,game_uno,uno_session,game_war,game_connect4,game_pictionary,game_puzzle,co_view_logic,co_view_session}.dart`,
`scaffold/client/test/{local_session_test,game_uno_test,uno_session_test,game_war_test,game_pictionary_wire_test,co_view_session_test}.dart`,
`scaffold/packages/{game-sync/src/table.ts,co-view/src/coview.ts}`, `scaffold/tools/{gen-coview-vectors.mjs,verify.sh,device-sync.sh}`,
`MASTERFILE.md` §2.1, §5.14, §5.17, §5.21.1, §5.23.2, §9.2, "Right now, together" (`:2763`), `docs/superpowers/specs/2026-11-07-co-viewing-design.md`,
`docs/superpowers/parity/MATRIX.md` (Local ad-hoc play row, Child games and creative).
