# Windows dev notes

This project has been built and verified, session after session, from a
Windows machine with the repo checked out on a `Z:` drive — a
network-mounted path, not a local NTFS volume, which does not behave like
one for tooling that assumes ordinary local-filesystem semantics. None of
that setup is exotic, but four specific gotchas have been hit and fixed
enough times, by feel, that they belong in a file instead of in a
contributor's head. None of what follows is a workaround for a bug in this
codebase — it is the cost of `Z:`'s network semantics and of Windows
lacking a native Postgres service and LiveKit toolchain, paid once here so
nobody re-derives it.

Read this alongside `tools/docker-dev/README.md` (the containerized dev
stack, a different concern — running the server, not running the test
suites) and `db/DEPLOYMENT.md` (the RLS role model the database suites
below depend on).

## The split: two environments, not one

Dart/Flutter is native on Windows and stays there. Everything `tools/verify.sh`
drives — the JS/TS suites, the database suites, LiveKit — needs WSL, because
`verify.sh` is a bash script and because Postgres and a real `livekit-server`
binary have no first-class Windows story here. Run both, from the two
matching shells, rather than hunting for a single environment that does
everything — one doesn't exist for this repo yet:

```powershell
# Windows — Dart/Flutter, matches .github/workflows/verify.yml's flutter-action pin
cd client
flutter analyze
flutter test
```

```bash
# WSL2 — everything tools/verify.sh drives
cd /mnt/z/.../scaffold   # or wherever this checkout is mounted inside WSL
bash tools/verify.sh
```

`verify.sh` itself already treats a missing Flutter/Android toolchain as a
gap, not a skip (see its own "MISSING TOOLCHAIN — not a skip, a gap" lines) —
that's this same split encoded in the script: it expects to be run from WSL
and expects the Dart side to have been checked separately.

## 1. Kotlin incremental compile on the `Z:` checkout

`client/android/gradle.properties` does not set `kotlin.incremental` today —
on purpose; it should not be committed either way (see below). The gotcha:
Kotlin's incremental compiler keeps a local build-history cache
(`build/kotlin/compileDebugKotlin/cacheable/...`) that it reads and writes
assuming ordinary local-filesystem semantics — file locking and timestamp
resolution in particular. `Z:` is a network-mounted drive, not a local NTFS
volume, and those semantics do not hold there. The result is a
`compileDebugKotlin` that fails or behaves inconsistently for reasons that
have nothing to do with the Kotlin source that changed — a stale or
half-written incremental cache, not a real compile error.

The fix is to disable incremental compilation for one clean build, then put
it back:

```properties
# client/android/gradle.properties — temporary, do not commit
kotlin.incremental=false
```

```powershell
cd client/android
./gradlew -q :app:compileDebugKotlin
```

Once that build is clean, delete the `kotlin.incremental=false` line again.
Leaving it in permanently is not free — every subsequent build becomes a
full non-incremental recompile instead of an incremental one, which is
noticeably slower on this module. This is a one-shot escape hatch for when
the cache has already gone bad, not a standing setting for this checkout.

## 2. `tools/verify.sh`'s JS/server suites need WSL

`verify.sh` is bash, and two of what it drives don't run natively on
Windows at all:

- **Postgres.** `verify.sh` connects over TCP (`-h localhost`, not a Unix
  socket — see the script's own comment on why) to a real Postgres 16
  cluster. `PGBIN` defaults to `/usr/lib/postgresql/16/bin` and `PORT`
  defaults to `5433`, matching the WSL2 Ubuntu-24.04 Postgres 16 install
  this project has actually been verified against locally, distinct from
  the port-5432 `postgres:` service container `.github/workflows/verify.yml`
  spins up in CI (same script, different `PORT` env, same result).
- **A real `livekit-server` binary**, for the live LiveKit suite
  (`packages/session-runtime/test/live.test.mjs`, run through
  `tools/with-livekit.sh`). `verify.sh` looks for it at
  `${LIVEKIT_BIN:-/tmp/livekit-server}` and treats it missing as a gap, not
  a skip.

Set the LiveKit binary up the same way `.github/workflows/verify.yml` does
(WSL2 is Linux, so the CI download works unmodified) — fetch the binary and
write a config at `/tmp/lk.yaml` with the exact key/secret this repo's own
test fixtures expect (`packages/session-runtime/test/live.test.mjs` and
`test/session.test.mjs` both hardcode `devkey` /
`devsecret_at_least_32_chars_long_xx`; a mismatched key here fails the suite
against a server that started up fine):

```bash
curl -sL -o /tmp/lk.tar.gz \
  https://github.com/livekit/livekit/releases/download/v1.8.0/livekit_1.8.0_linux_amd64.tar.gz
tar xzf /tmp/lk.tar.gz -C /tmp
printf 'port: 7880\nrtc:\n  tcp_port: 7881\n  port_range_start: 50000\n  port_range_end: 50020\n  use_external_ip: false\nkeys:\n  devkey: devsecret_at_least_32_chars_long_xx\nlogging:\n  level: warn\n' > /tmp/lk.yaml
```

`tools/with-livekit.sh` starts this server, waits for `127.0.0.1:7880` to
answer, runs the suite against it, and kills it afterward — it owns the
whole lifecycle, so once `/tmp/livekit-server` and `/tmp/lk.yaml` exist
there's nothing else to start by hand.

## 3. Dart/Flutter tests run natively on Windows, not in WSL

The other half of the split above: `flutter analyze` and `flutter test`
run directly against a native Windows Flutter install, not inside WSL.
`verify.sh`'s own Dart block confirms this is expected, not a workaround —
its `FLUTTER_BIN`/`FLUTTER_ROOT` defaults exist because there's no single
canonical toolchain location across the environments this script actually
runs in. Pin the same Flutter version CI pins (`subosito/flutter-action` in
`.github/workflows/verify.yml`, currently `3.44.8`) so a local
`flutter analyze`/`flutter test` result means the same thing CI's does —
this project has hit real framework-API drift (`Color.withValues()`,
`toARGB32()`) from an older pin before.

Two toolchains, two shells, run separately, added together — not a
temporary inconvenience to fix, just what this repo needs until (if ever)
Flutter's Linux/WSL story and this project's Windows dev setup converge.

## 4. esbuild needs a native reinstall after a cross-platform `npm i`

`esbuild` (`scaffold/package.json` — the `build` script that compiles every
package's `.ts` entry point to `.mjs`, and the `esbuild` devDependency
itself) ships a separate native binary package per platform
(`@esbuild/win32-x64`, `@esbuild/linux-x64`, ... — see
`package-lock.json`'s own `optionalDependencies`). `node_modules` lives on
the same `Z:`-mounted checkout both environments share, so running
`npm i`/`npm ci` from WSL populates it with the **Linux** esbuild binary; a
subsequent `npm run build` from native Windows then fails or silently runs
the wrong binary, because `node_modules/@esbuild/win32-x64` was never
installed.

Fix: reinstall `esbuild` itself from whichever side you're actually about
to build on. This forces npm to resolve and place the binary for the
platform running the command:

```powershell
cd scaffold
npm install esbuild
```

The generalized version of this: if a suite that ran clean in WSL an hour
ago now fails on Windows in a way that smells like a missing/wrong binary
rather than a code change, check which shell last ran `npm i` against this
`node_modules` before debugging anything else.
