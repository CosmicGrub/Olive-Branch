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
adb install -r "$APK" > "$OUT/install.txt" 2>&1 || { cat "$OUT/install.txt"; echo "FAIL  adb install failed"; exit 1; }
adb logcat -b all -c
adb shell am start -W -n "$PKG/.MainActivity" > "$OUT/am-start.txt" 2>&1 || true
cat "$OUT/am-start.txt"

for i in $(seq 1 "$WINDOW"); do
  sleep 1
  pid="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' | awk '{print $1}')"
  echo "$i $pid" >> "$OUT/alive.txt"
done

adb exec-out screencap -p > "$OUT/screenshot.png" 2>/dev/null || true
adb shell dumpsys activity activities > "$OUT/activities.txt" 2>&1 || true
adb logcat -b all -d -v threadtime > "$OUT/logcat.txt" 2>&1 || true

node "$HERE/release-smoke-eval.mjs" --pkg "$PKG" --dir "$OUT" --min-samples "$WINDOW" | tee "$OUT/verdict.txt"
exit "${PIPESTATUS[0]}"
