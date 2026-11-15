# ios/ is a scaffold only

This folder is an **inert placeholder** for a future iOS app. It was generated with `flutter create --platforms=ios`
on Windows and has **never been built, run, signed or opened in Xcode** by a person. iOS work is **on hold until the
owner says the Android version is complete** (see `docs/roadmaps/IOS-ROADMAP.md`, which holds the parity table, the
gate and the wave plan).

What is configured: bundle id `com.olivebranch.oliveclient` (no underscores on iOS), display name, deployment target
15.0, usage strings (camera, microphone, photos, local network + Bonjour `_gp._tcp`), no tracking, a privacy manifest
(unverified, see the comments inside it), an empty entitlements stub, a plain launch screen, a Podfile.

What does not exist: Swift handlers for the Kotlin-only channels (`app.olive/kiosk`, `app.olive/webauthn`, the Wear sync
channel), CallKit/PushKit, passkeys, the push entitlement, signing, an app icon of our own. The Dart side already
degrades on those channels (see the roadmap).

Files in this folder must stay LF (`.gitattributes`). Do not add capabilities or code here before the go-ahead.
