# The signed update manifest (schema 1)

What an installed Olive Branch app downloads to learn that a newer version exists, and what it checks before it believes
anything in it. The same rules are written four times and kept in step by tests: here (for people), in
[`update-manifest.schema.json`](update-manifest.schema.json) (JSON Schema, for tools), in
`scaffold/tools/update/manifest_lib.mjs` (the validator and the release-side checks), and in the app's
`client/lib/update_manifest.dart`. `scaffold/tools/update/test-vectors.json` is the shared truth: canonical strings, signatures
that verify, and a labelled set of documents that must be accepted or refused with a named code. How to publish one is
[RELEASING.md](RELEASING.md), "Publishing an update".

## What is trusted, and what is not

**Nothing that arrives over the network is trusted by where it came from.** A mirror, a CDN, a proxy, a captive portal or GitHub
itself can therefore not make the app believe anything. The app believes a manifest only if the Ed25519 signature over its
canonical form verifies under a **public key built into the app** (`--dart-define=OLIVE_UPDATE_PUBKEYS=...`). The matching
private key is held offline by the owner and never enters a repository, a workflow, a server or a chat. It then believes an APK
only if its size, every chunk hash and its SHA-256 match that signed manifest, its signing certificate is the pinned one and
the same as the installed app's, and its `versionCode` is strictly higher than the installed one.

## The document

One JSON object, `{ "manifest": { ... }, "signature": { ... } }`, UTF-8, at most **256 KiB**, no byte-order mark, no duplicate
keys, integers only (no fractions, no exponents, nothing beyond 2^53 - 1). The signature covers the `manifest` member only.

```json
{
  "manifest": {
    "schema": 1,
    "app": "com.olivebranch.olive_client",
    "channel": "stable",
    "versionName": "0.52.0",
    "versionCode": 5200,
    "minSupportedVersionCode": 5100,
    "sequence": 1795255200,
    "issuedAt": "2026-11-21T10:00:00Z",
    "expiresAt": "2027-05-20T10:00:00Z",
    "publishedAt": "2026-11-21T10:00:00Z",
    "headline": "A calmer first run",
    "notes": ["The first screen now explains who it is for.", "Fewer taps to reach a saved message."],
    "apks": [
      {
        "abi": "arm64-v8a",
        "size": 3145745,
        "sha256": "<64 lower-case hex digits: the whole file>",
        "signerSha256": "<64 hex digits: SHA-256 of the APK's signing certificate>",
        "chunkSize": 1048576,
        "chunks": ["<64 hex>", "<64 hex>", "<64 hex>", "<64 hex>"],
        "urls": ["https://downloads.example.org/olive/olive-0.52.0-direct-arm64-v8a.apk", "https://mirror.example.net/olive/olive-0.52.0-direct-arm64-v8a.apk"]
      }
    ]
  },
  "signature": { "alg": "ed25519", "kid": "1f7c31942912896a", "sig": "<64-byte signature, base64url>" }
}
```

| Member | Rule |
|---|---|
| `schema` | The integer `1`. A different number is refused (a future format ships as a new schema, never as a quiet change). |
| `app` | Exactly `com.olivebranch.olive_client`. A manifest for any other app is refused (`wrongApp`). |
| `channel` | `[a-z0-9][a-z0-9-]{0,31}`, for example `stable`. The app follows one channel; a manifest for another is refused (`wrongChannel`). |
| `versionName` | `MAJOR.MINOR.PATCH` (the app tolerates a `-suffix`; a *published* version never has one). |
| `versionCode` | Integer, 1 to 2147483647. **Derived**, never chosen: `major*10000 + minor*100 + patch` (RELEASING.md, "versionCode policy"). |
| `minSupportedVersionCode` | Integer, 1 to `versionCode`. An installed build below it makes **adults** see "Please update"; the child sees nothing and loses nothing. |
| `sequence` | Integer, 1 to 2^53 - 1, rising with every manifest the owner signs (the signing tool defaults it to the issue time in seconds). An app remembers the highest it has accepted and refuses a lower one (`replayed`). **Publisher rule:** a sequence may not exceed the issue time in seconds plus 86400 (`policyProblems`; the signer and the verifier enforce it). A phone that accepted a huge sequence would refuse every later manifest as replayed, with no recovery, because nothing can exceed it. The app should also keep the highest sequence per key id and ignore one implausibly far above the clock; that is the client lane's rule to adopt. |
| `issuedAt`, `expiresAt`, `publishedAt` | UTC `YYYY-MM-DDTHH:MM:SS[.mmm]Z`, real instants. `expiresAt` is after `issuedAt` and within 400 days of it: an old copy cannot be replayed for ever (`expired`). A manifest issued more than a day in the future is `notYetValid`. |
| `headline` | At most 100 characters, plain text, may be empty. |
| `notes` | At most 12 lines, each 1 to 300 characters, **plain words for a grown-up**. No angle brackets, no backticks, no control, invisible or bidirectional-override characters, no edge spaces. Shown as text, never rendered as anything else. |
| `apks` | 1 to 4 entries, one per `abi`. |
| `apks[].abi` | `arm64-v8a`, `armeabi-v7a`, `x86_64` or `universal`. The app takes its own ABI, else `universal`, else reports `noApkForDevice`. |
| `apks[].size` | Integer, 1 to 524288000 (500 MiB). Over the cap is refused before anything is downloaded (`sizeTooLarge`). |
| `apks[].sha256` | The whole file, 64 lower-case hex digits. |
| `apks[].signerSha256` | SHA-256 of the signing certificate. The app compares it with the downloaded file's certificate **and** with the installed app's: a build signed by anyone else is refused (`certMismatch`). |
| `apks[].chunkSize` | 16 KiB to 8 MiB. The release script uses 1 MiB. A download is resumable and verified chunk by chunk at this size. |
| `apks[].chunks` | Exactly `ceil(size / chunkSize)` lower-case hex SHA-256 digests, in order (the last chunk is the remainder), at most 32768. |
| `apks[].urls` | 1 to 4 addresses, the primary first, the rest mirrors. Published manifests use **https only**, a public host name, the default port, no credentials, no fragment, written in canonical form, at most 2000 characters. (A release build of the app refuses cleartext; the developer-only loopback exception of the transport policy is not for published manifests.) |
| `signature.alg` | `ed25519`. Anything else is refused. |
| `signature.kid` | A label (`[A-Za-z0-9._-]{1,32}`) naming which built-in key to verify with. The release tools use the first 16 hex digits of SHA-256 of the raw public key. An unknown `kid` is `unknownKey`. |
| `signature.sig` | The 64-byte Ed25519 signature, base64url. |

The publisher's validator additionally refuses members this version does not define (so a typo is never signed). The app
tolerates an unknown *signed* member, so a later schema can add one without breaking older apps.

## What is signed: the canonical form

The signature is over the bytes `"olive-update-manifest-v1\n"` (the **domain tag**, so this signature can never mean anything
else) followed by the **canonical JSON** of the `manifest` object, UTF-8:

- object keys sorted by UTF-16 code unit (not by code point: a character outside the Basic Multilingual Plane sorts by its
  surrogate pair), no whitespace anywhere;
- integers only, written in decimal with no sign for positives and no leading zeros; a fraction, an exponent or a value beyond
  2^53 - 1 has no canonical form and is refused;
- a string is written between `"` and `"`; `"` becomes `\"`, `\` becomes `\\`, **every control character below U+0020 becomes
  `\u00xx` in lower-case hex** (a newline is `\u000a`, never `\n`), and every other character is written as itself.

That last rule is **not** what `JSON.stringify` does, on purpose: the Dart client writes control characters this way and the two
must agree byte for byte. `test-vectors.json` pins it (`canonical`: input, canonical string, signing bytes in hex).

The file as published is ordinary pretty-printed JSON; whitespace and member order are not signed.

## What the app does with a manifest, in order

1. **Size.** More than 256 KiB is refused unread (`tooLarge`).
2. **A key to check against.** An app built without keys has no update feature and fails closed (`noKeyConfigured`).
3. **Strict parse.** Not JSON, a duplicate key, a float, a lone surrogate (`notJson`).
4. **Signature** under the key named by `kid` (`unknownKey`, `badSignature`). **Nothing that failed the signature is read further.**
5. **Shape and limits** of every member (`badShape`, `badUrl`, `sizeTooLarge`, `wrongApp`).
6. **Channel**, then the **clock** (`notYetValid`, `expired`).
7. **Replay**: `sequence` lower than the highest already accepted (`replayed`). The same sequence again is a harmless re-fetch.
8. **Rollback**: `versionCode` below the installed one (`rollback`). Equal is "up to date", never an install.
9. If newer: choose the file for this device, download it (resumable, chunk-verified, size-capped, https only, redirects
   judged hop by hop), verify the whole-file SHA-256, the zip structure, the signing certificate against the manifest's pin and
   the installed app, and the `versionCode` inside the file, and only then hand it to Android's installer. The system
   confirmation always appears; there is no silent install. A failed or interrupted download never leaves a partial file
   installable.

Steps 1 to 8 are implemented by `manifest_lib.mjs` and proved by this repository's tests against `test-vectors.json`; the client's parser must reproduce them. Step 9 is the app's download and install path (the client lane); this file states the contract it is built to, not that it exists.

### The shared vectors: what the client must replay

`scaffold/tools/update/test-vectors.json` (`vectorsFormat: 1`) is the single file both implementations are proved against. The client
lane's test should load **this** file (copy it in or read it by relative path; do not keep a second vector file with its own shape) and:

- `canonical[]`: for every `{ json, canonical, signingBytesHex }`, parse `json` with the strict parser, canonicalize, and expect `canonical`;
  the bytes that are signed (`signDomain` + canonical form) must equal `signingBytesHex`.
- `documents[]`: for every `{ name, text, ctx, expect }`, run the app's whole decision on the bytes of `text` with the trusted key
  `trust` (`strangerTrust` is a key the app does not hold), `ctx.channel`, `ctx.installedVersionCode`, `ctx.highestSeenSequence`
  (null: none) and the clock `ctx.nowIso`; with unknown members tolerated. `expect.ok` true means accepted with `expect.status`
  (`update` or `up-to-date`; `belowMinimum` means the installed build is under `minSupportedVersionCode`); false means refused with
  exactly the named `expect.code`, so a test fails if the codes differ, not merely if something is refused.
- The plain-text rules for `headline` and `notes` (no markup, backticks, control, invisible or bidirectional characters, no edge
  spaces) hold in this tolerant mode too: there are vectors for each, expected `badShape`.

The shape of this file replaces the interim golden-vector layout the client's first test used (`publicKey`, `keyId`, `signed`,
`signingBytesHex`, `canonicalCases`); that test must be rewritten to the layout above. The keys behind the vectors were discarded, so
the file holds no secret. Regenerating it (`gen-update-vectors.mjs`) changes every signature: do it only when the format changes, and
tell the client lane.

`scaffold/tools/update/verify-update-release.mjs` makes the same checks against a *published* manifest and every address in it
(primary and mirrors), which is how the owner proves a release before telling anyone.

## The signing key

Ed25519. Generated once, offline, by `tools/update/gen-update-key.mjs`, which refuses any path inside a git working tree.
Only the public half is built into the app. Two built-in keys at a time is the rotation story: a release signed by the old key
carries the new public key; once that release is widely installed, manifests switch to the new key. Losing the key means no
installed app can ever be updated in place by a manifest again until people reinstall a build carrying a new public key, so
RELEASING.md insists on an offline backup. A suspected leak is handled the same way as a loss: ship a build with a new key
signed by the old one, then retire the old.

## What this format deliberately does not do

- It does not make a download private: the address and the file are public by design. Nothing about a family is in it.
- It does not update the Play build: that flavor is updated only by Google Play and never reads a manifest.
- It does not push: an app polls, politely (at most daily, honouring a parent's data-saver and Wi-Fi-only choices).
- It never shows anything to a child. Every update surface is behind the adult gate.
