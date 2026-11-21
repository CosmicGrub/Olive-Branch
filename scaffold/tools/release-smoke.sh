#!/usr/bin/env bash
# Install a RELEASE APK on the already-booted emulator, launch MainActivity, watch it for a fixed window and
# save the evidence. Run inside reactivecircus/android-emulator-runner (.github/workflows/release-smoke.yml);
# it can also be run by hand against any adb device:  bash tools/release-smoke.sh <apk> <outdir> [seconds]
#
# Evidence written to <outdir>: logcat.txt, alive.txt (one "<second> <pid>" per second; empty pid = process gone),
# am-start.txt, activities.txt, screenshot.png. The verdict is tools/release-smoke-eval.mjs (unit-tested).
# Never uninstalls anything from a real device: it is meant for a throwaway emulator.
set -u
APK="${1:?apk path}"; OUT="${2:?output dir}"; WINDOW="${3:-20}"
PKG=com.olivebranch.olive_client
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
: > "$OUT/alive.txt"

adb wait-for-device
adb logcat -G 16M >/dev/null 2>&1 || true
# A cached AVD can carry the app from an earlier run signed with a different debug key (INSTALL_FAILED_UPDATE_INCOMPATIBLE when
# the cached snapshot is stale and the emulator cold-boots from the saved userdata). A smoke test wants a fresh install.
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb install -r "$APK" > "$OUT/install.txt" 2>&1 || { cat "$OUT/install.txt"; echo "FAIL  adb install failed"; exit 1; }
adb logcat -b all -c
adb shell am start -W -n "$PKG/.MainActivity" > "$OUT/am-start.txt" 2>&1 || true
cat "$OUT/am-start.txt"

for i in $(seq 1 "$WINDOW"); do
  sleep 1
  pid="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')"
  # One retry: a single transient adb failure must not read as "the process died". A real death stays empty.
  [ -n "$pid" ] || { sleep 0.2; pid="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')"; }
  pid="$(echo $pid)"   # normalise whitespace; every listed pid is kept, the verdict looks for one common to all samples
  echo "$i $pid" >> "$OUT/alive.txt"
done

adb exec-out screencap -p > "$OUT/screenshot.png" 2>/dev/null || true
adb shell dumpsys activity activities > "$OUT/activities.txt" 2>&1 || true
adb logcat -b all -d -v threadtime > "$OUT/logcat.txt" 2>&1 || true

node "$HERE/release-smoke-eval.mjs" --pkg "$PKG" --dir "$OUT" --min-samples "$WINDOW" | tee "$OUT/verdict.txt"
exit "${PIPESTATUS[0]}"
