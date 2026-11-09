# Operator guide: certificate pinning and rotation

The Flutter client can pin the Olive API host's public key so that a
user-installed or compromised certificate authority cannot read or alter
traffic (a rogue access point with an installed root, a corporate or school
TLS-inspection box, a malicious VPN). Design:
`docs/superpowers/specs/2026-11-08-server-snoop-hardening-design.md` section 4.1.

## What is pinned

The SHA-256 of a certificate's SubjectPublicKeyInfo (the SPKI hash), base64
encoded. It is matched against any certificate in the chain the server
presents, so you can pin the leaf key, an intermediate, or both. Pinning the
intermediate survives routine leaf renewal with a new key; pinning the leaf key
requires keeping that key across renewals. Recommended: pin the **intermediate**
plus a **backup pin** for a key you hold offline.

## Rules the client enforces

* Pinning applies only to a `https://` base URL that is not loopback or
  `10.0.2.2`. Dev base URLs are never pinned.
* Release builds with pinning requested need **at least two pins** (a primary
  and a backup pin). With fewer, the transport refuses to be created: a single
  pin that is lost bricks every installed app.
* Release builds refuse any `http://` base URL, loopback included.
* A pin mismatch fails the request before any byte (including the bearer token)
  is written.

## Computing a pin

```sh
# from the live server (the intermediate is the second certificate)
openssl s_client -connect api.example.com:443 -servername api.example.com -showcerts </dev/null \
  | awk '/BEGIN CERT/{n++} n==2' | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64

# from a key file you hold offline (the backup pin)
openssl pkey -in backup.key -pubout -outform der | openssl dgst -sha256 -binary | base64
```

## Shipping pins

Pins are build-time values, never committed:

```sh
flutter build apk --release \
  --dart-define=OLIVE_API_BASE_URL=https://api.example.com \
  --dart-define=OLIVE_API_PINS=primaryPinBase64,backupPinBase64
```

## Rotation procedure

1. **Release N**: ship the app with the current pin and a *backup pin* for a key
   that does not yet exist on the server (generate it, keep it offline).
2. Wait until the share of installs on release N or later is high enough that
   you accept the rest being locked out until they update (the in-app update
   prompt is the remedy for those).
3. **Rotate the server key** to the backup key (new certificate issued with that
   key). Installs on N or later still match the backup pin.
4. **Release N+1**: ship with the *new* current pin and a *new* backup pin.
5. Retire the old pin from the build after N+1 is widespread.

Never rotate to a key whose pin has not been in a released app for at least one
full release cycle. An emergency rotation (key compromise) without a shipped
backup pin means a forced app update; plan for it by always shipping a backup.

## Android network security config

`android/app/src/main/res/xml/network_security_config.xml` blocks cleartext
traffic and does not trust user-installed CAs for the platform stack (WebViews
and plugins that use it). The debug source set overrides it to allow
`localhost` and `10.0.2.2` only. Dart's `dart:io` does not read this file, so
the Dart-level policy in `lib/server_transport_policy.dart` is authoritative for
the API client; the XML covers everything else in the process.
