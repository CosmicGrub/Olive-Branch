# Olive Branch: iOS roadmap

> **ON HOLD.** iOS waves do not start until **the owner says the Android version is complete.** Until then the
> only iOS things in the repository are three idle markers: the inert `scaffold/client/ios/` folder, this document,
> and one advisory CI job (`.github/workflows/ios-compile.yml`). No Swift bridge, CallKit, PushKit, Keychain or passkey
> code, no entitlements beyond an empty stub, and no per-plugin iOS fixes are to be written before that go-ahead.
> Android stays first and must never be blocked, slowed or regressed by anything here.

*Written 2026-11-13 against `main` at v0.51.0 plus unreleased work. Every claim marked **(unverified)** was not
checked against a build, a device or the vendor's page. Nothing here has ever run on an iPhone or iPad.*

## 1. Goal and ordering rule

Goal: the same family-first, offline-first app on iPhone and iPad, honest about what Apple's platform will and will
not let a child shell do.

Rule: **Android first and complete; iOS waves start only after the owner declares the Android completion gate met.**
The gate (all must be true, and the owner decides, not CI):

1. The offline parity waves are merged (MASTERFILE section 22.2 has no remaining row that blocks a first family).
2. The server is hosted and tested by a real family on real devices (not only CI and a local container).
3. The store-readiness audit for Google Play is done and the Android app has been through a closed test.
4. The parity table below shows every Android row `Done` or an explicit owner-accepted `Won't`.

## 2. What exists today (the scaffold)

- `scaffold/client/ios/`: a `flutter create` project (Flutter 3.44.8) with: bundle id `com.olivebranch.oliveclient`,
  display name "Olive Branch", deployment target **iOS 15.0**, plain-English usage strings, `NSBonjourServices`
  `_gp._tcp` (from `localServiceType` in `local_discovery.dart`), no tracking, a privacy manifest (flagged unverified
  inside the file), an empty entitlements stub, a plain launch screen in the Olive palette, the default Flutter
  placeholder icon (the Android icon is also still the Flutter default, so there was nothing to derive), a standard
  Podfile, and `ios/README.md`.
- Bundle id: iOS ids allow letters, digits, hyphen and dot, not underscore, so Android's `com.olivebranch.olive_client`
  became `com.olivebranch.oliveclient` (lower case to match Android; Apple compares ids case-insensitively).
  Changing it now costs nothing; changing it after the first App Store Connect record does.
- Deployment target 15.0 is the highest plugin minimum: `firebase_core`/`firebase_messaging` 15.0; `flutter_webrtc`,
  `livekit_client`, `bonsoir_darwin`, `image_picker_ios`, `flutter_secure_storage_darwin` 13.0; `mobile_scanner` 12.0.
  (Read from the plugins' own `Package.swift`/podspec files in the local pub cache.)
- **Plugin iOS support: every native plugin in `pubspec.yaml` ships an iOS implementation** (`livekit_client`,
  `flutter_webrtc`, `image_picker`, `path_provider`, `firebase_core`, `firebase_messaging`, `flutter_tts`, `bonsoir`,
  `flutter_secure_storage`, `mobile_scanner`). `pretty_qr_code`, `cryptography`, `http`, `web_socket_channel` are pure
  Dart. None lack iOS support. The gaps are the app's own Kotlin bridges (table below). `local_auth`, `passkeys` and
  other Apple-specific packages are not dependencies today.
- What the scaffold guarantees: only that a no-codesign build compiles on a macOS runner, and only to the extent the
  advisory job has been seen green (section 6). It guarantees nothing about behaviour.

### Dart channel behaviour on iOS today (read from the code, not run)

- `KioskChannel.start()/mode()/isFullyLocked()` do not catch `MissingPluginException`; the only caller,
  `kiosk_shell.dart` `_engage()`, catches everything and falls back to `LockMode.none`, and subscribes to `events()`
  with an `onError` swallow. `stop()` and `beginCallHandoff()` catch it themselves.
- `WebAuthnChannel` converts `MissingPluginException` to `WebAuthnUnavailable` (maps to `PasskeyOutcome.unavailable`).
- `WearSyncChannel` returns early unless `Platform.isAndroid`.
- `push_channel.dart` treats iOS as push-capable; without `GoogleService-Info.plist`, `Firebase.initializeApp()` fails
  into the existing `PushInitializationError`, not a crash.
- Conclusion: no Dart change is needed for the scaffold to be safe. A tidier explicit "unsupported on this platform"
  result for `KioskChannel` is **deferred** to wave iOS-2 (owner constraint: only a tiny, harmless-to-Android guard was
  allowed before the go-ahead, and none was needed).

## 3. Parity table (a living checklist)

**How to keep it current.** Every merged Android wave that adds, changes or removes a native dependency, platform
channel, permission or background behaviour must add or adjust its row here *in the same PR* (one line is enough) and
set the *Android status*. iOS status stays `Not started` until the owner opens the iOS waves. A row an Android PR
forgot is a review finding.

Android status values: `Done`, `Partial`, `Not built`. iOS status: `Not started`, `Scaffold only`, `Done`, `Won't`.

| Feature | Android implementation | iOS equivalent or gap | Android status | iOS status |
|---|---|---|---|---|
| Child lock / kiosk (5.20, 8.3) | `KioskBridge.kt`: lock-task / Device Owner | No app can lock a device. Options: Guided Access (user-enabled, cannot be turned on by an app); Screen Time / Family Controls API (needs the `com.apple.developer.family-controls` entitlement, which Apple must approve; approval **unverified**); Apple's own Screen Time as the parent's tool. Honest iOS child shell: a full-screen, adult-gated "child mode" inside the app that cannot stop the child leaving the app, plus setup instructions for Guided Access. Say so in the UI; do not promise a lock | Done (per MASTERFILE) | Not started |
| Passkeys / WebAuthn (7.1, 8.1) | `WebAuthnBridge.kt`: Credential Manager | `AuthenticationServices` (`ASAuthorizationPlatformPublicKeyCredentialProvider`) plus Associated Domains entitlement and a served `apple-app-site-association` file on the server's domain (needs the production domain) | Done (device run per file header) | Not started |
| Calls (LiveKit, 5.19) | `livekit_client` + `flutter_webrtc`, normal Flutter route | Both plugins support iOS (13.0+). Camera/mic strings present. For incoming calls while the app is closed: CallKit plus PushKit VoIP push; Apple requires a CallKit report for every VoIP push **(unverified: re-read the current rule)**. The offline-first direction (owner, 2026-11-07) parks online calls, so this is last | Partial (never run against real LiveKit Cloud) | Not started |
| Local play, no internet (8.16, Track B) | `bonsoir` mDNS (`_gp._tcp`) + local HTTP turn sync | `bonsoir_darwin` supports iOS. iOS 14+ prompts for Local Network access on first browse/advertise; needs `NSLocalNetworkUsageDescription` + `NSBonjourServices` (present). There is no API to pre-check the permission; design a "waiting for permission" state. A foreground local HTTP server works; it is suspended in the background. MultipeerConnectivity is an alternative but a second transport to build and test: not recommended. Needs physical devices (Simulator is not a real LAN) | Done (hardware-verified) | Not started |
| Secure storage | `flutter_secure_storage` (Android Keystore) | Same plugin, Keychain. Decide accessibility class (`first_unlock_this_device` recommended: survives reboot, never leaves the device) and a keychain access group if an extension appears later | Done | Not started |
| Local encrypted store (8.16.2) | Pure Dart AES-GCM | Identical (no native code) | Done | Not started |
| Push notifications (11) | `firebase_messaging` (FCM) | Same plugin through APNs: needs `GoogleService-Info.plist`, an APNs key uploaded to Firebase, the `aps-environment` entitlement and Push Notifications capability. The server already has an APNs sender (never sent live) | Partial (no live endpoint) | Not started |
| Background execution | Foreground-oriented; FCM wakeups | iOS suspends apps quickly. `UIBackgroundModes` is deliberately empty. Candidates later: `remote-notification`, `voip` (only with CallKit), `audio` only if a feature really plays in the background. Do not enable speculatively; each needs App Review justification | n/a | Not started |
| Haptics | Flutter `HapticFeedback` | Same API (Taptic Engine); no work expected | Done | Not started |
| Text to speech (8.8.5) | `flutter_tts` (Android TTS) | Same plugin (AVSpeechSynthesizer), on device. Voices differ; check each supported locale | Done | Not started |
| Camera / photo / video | `image_picker`, `mobile_scanner` | Both support iOS; strings present. Gallery use (`ImageSource.gallery` exists in the code) means `NSPhotoLibraryUsageDescription` stays | Done | Not started |
| File export (deletion bundle) | `path_provider` | Same plugin; the share sheet is the natural export path (check how the Android flow hands the file over) | Done | Not started |
| Wear OS companion (21.5) | `WearSyncBridge.kt` | Not applicable. An Apple Watch app is a separate target (WatchConnectivity) and a separate product decision, not a port | Done | Won't (this roadmap) |
| Home screen widgets | None known | WidgetKit if ever wanted | Not built | Not started |
| Theming / launch screen | Flutter tokens | Same tokens; iOS launch screen is a plain light Olive colour. Add a dark variant and logo when a logo exists | Done | Scaffold only |

## 4. Wave plan (not started)

Sizes: S under a day, M a few days, L a week or more. Anything beyond editing Dart needs a Mac, a cloud Mac or a CI runner.

| Wave | Content | Size | Depends on | Verification |
|---|---|---|---|---|
| iOS-0 | Owner go-ahead; Apple Developer account; decide Mac access (own Mac, rented cloud Mac, or CI only) | S (owner) | Android gate | n/a |
| iOS-1 | Get `flutter build ios --no-codesign` green on CI; fix plugin/Podfile/SPM issues; regenerate and review the privacy manifest from a real Xcode privacy report | S to M | iOS-0 | macOS CI runner; Simulator launch |
| iOS-2 | Platform abstraction: explicit "unsupported on this platform" results (kiosk first), honest iOS child-shell mode, UI copy | S | iOS-1 | Host unit tests with Platform overrides; Simulator |
| iOS-3 | Secure storage and local store on iOS; the first-run flow end to end offline | M | iOS-1 | Physical iPhone (Keychain differs on Simulator) |
| iOS-4 | Local play: Bonjour, Local Network permission flow, foreground HTTP sync | M | iOS-3 | Two physical devices on one LAN (iPhone + iPad); TestFlight |
| iOS-5 | Passkeys (`AuthenticationServices`), Associated Domains, AASA on the real domain | M | Hosted server, iOS-3 | Physical device |
| iOS-6 | Push: APNs key, entitlement, Firebase config, token registration, receive | M | Hosted server | Physical device (Simulator push via Firebase is unreliable, unverified) |
| iOS-7 | Calls: LiveKit on iOS; then CallKit + PushKit if wanted | L | iOS-6, calls un-parked by owner | Two devices on cellular and Wi-Fi |
| iOS-8 | Apple child-safety review: Kids Category decision, parental gate, privacy labels, in-app deletion, export compliance; TestFlight external test; submission | M to L | all wanted waves | App Review itself |
| iOS-9 (optional) | Family Controls entitlement application and a Screen Time based lock | L plus Apple's decision | iOS-8 | Physical device |

## 5. What needs the owner

- **Apple Developer Program membership** (annual fee; amount **unverified**, check the current price). Individual vs
  organisation: an organisation enrolment needs a D-U-N-S number and a legal entity; the seller name shown in the App
  Store is the account holder's. Decide before the first App Store Connect record; it is hard to change later.
- **A Mac** (or a cloud Mac service) for signing, Simulator, Instruments and device runs. Windows cannot build iOS.
  CI on `macos-latest` can compile but cannot sign unless secrets are configured.
- An Apple ID with two-factor, registered devices, certificates and provisioning: via `fastlane match` (private
  certificate repository) or Xcode Cloud; either needs a deliberate secrets decision.
- App Store Connect record, privacy "nutrition label", age rating, support URL, privacy policy URL.
- **Kids Category and child data.** Read on developer.apple.com on 2026-11-13 through a page-text fetch that covered only
  the first 100,000 of about 114,000 characters: guideline 1.3 (Kids Category: no links out, no purchasing
  opportunities unless behind a parental gate), 5.1.4(a) (apps intended primarily for kids should not include
  third-party analytics or advertising), 5.1.1(v) (account creation requires in-app account deletion), 2.5.4 (VoIP as a
  permitted background purpose). **Not verified:** PushKit wording (in the unread tail or elsewhere), exact current
  numbering and full text, and whether this app (a family tool used by adults and children) should enrol in the Kids
  Category at all. Re-read the live page and decide with the owner. Whether Firebase (`firebase_messaging`) counts as
  "third-party analytics" for a Kids Category app must be checked **(unverified)**.
- **Parental gate**: an adult gate exists in the app (adult-gate card, PIN); whether it satisfies Apple's expectations
  of a gate is unverified.
- **VoIP push rules**: if PushKit is used, every VoIP push must result in a CallKit call report (unverified: confirm).
- **In-app account deletion**: the app has a deletion flow (6 to 12 month recovery window, owner decision); confirm it
  meets 5.1.1(v), including the recovery-window wording.
- **Export compliance (encryption)**: the app uses TLS, AES-256-GCM and PBKDF2 (standard algorithms) and a custom
  PAKE-style pairing exchange. The standard-algorithms exemption likely covers the first group; the custom PAKE needs a
  deliberate review before answering the `ITSAppUsesNonExemptEncryption` question. `Info.plist` does not set that key
  yet; set it only after the review. (Not legal advice; **unverified**.)

## 6. Advisory CI result

`.github/workflows/ios-compile.yml` runs `flutter pub get` and `flutter build ios --no-codesign --debug` on
`macos-latest` for pull requests touching `scaffold/client/**` and on manual dispatch, with `continue-on-error: true`,
uploads the log and writes a job summary. It is not in branch protection and the required checks are unchanged.
GitHub-hosted standard runners being free for public repositories is GitHub's documented policy; it was **not
verified** from this session (billing pages not read). Per the owner constraint the job is observed once and not
iterated to green before the go-ahead.

**First run result:** see the section below, filled in after the first observed run.

RESULT_PLACEHOLDER

## 7. Risks and open decisions

| Decision | Recommendation |
|---|---|
| Is a child-lock promise possible on iOS? | No. Do not market one. Offer the honest in-app child mode plus Guided Access instructions; consider iOS-9 only if the owner wants it |
| Kids Category or general category | Decide at iOS-8 after re-reading the live guidelines; the SDK question (Firebase) may push toward the general category with a child-safety design |
| Organisation vs individual Apple account | Organisation if the product will be commercial; start the D-U-N-S request early (lead time is outside our control) |
| Local network permission UX | Explain before the system prompt; treat denial as a normal state with a recovery path |
| MultipeerConnectivity vs Bonjour + HTTP | Keep Bonjour + HTTP (one transport, already hardware-verified on Android) |
| Bundle id spelling | Keep `com.olivebranch.oliveclient`; treat it as final at the first App Store Connect record |
| Placeholder icons | A real icon set is needed for both stores; at the latest in the store-readiness audit |
| iOS minimum 15.0 | Revisit only if Firebase's minimum rises; share of devices still on older iOS is unverified |
