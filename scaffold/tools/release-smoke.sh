#!/usr/bin/env bash
# Install a RELEASE APK on the already-booted emulator, launch MainActivity, watch it for a fixed window and
# save the evidence. Run inside reactivecircus/android-emulator-runner (.github/workflows/release-smoke.yml);
# it can also be run by hand against any adb device:  bash tools/release-smoke.sh <apk> <outdir> [seconds]
#
# Evidence written to <outdir>: logcat.txt, alive.txt (one "<second> <pid>" per second; empty pid = process gone),
# am-start.txt, activities.txt, screenshot.png. The verdict is tools/release-smoke-eval.mjs (unit-tested).
# Never uninstalls anything from a real device: it is meant for a throwaway emulator.
#
# Install (ISS-025): the result of every uninstall is LOGGED (install.txt is the single record, also echoed), because
# it used to be thrown away and a failed run said only "adb install failed". When the install is refused with
# INSTALL_FAILED_UPDATE_INCOMPATIBLE (a copy of the app signed with another key is still on the device) the script does
# what that error asks for: pm uninstall, pm clear, then installs once more, logging each step. After the verdict the
# app is uninstalled again (an EXIT trap, so a failed run cleans up too), so nothing is left behind in the emulator.
set -u
APK="${1:?apk path}"; OUT="${2:?output dir}"; WINDOW="${3:-20}"
PKG=com.olivebranch.olive_client
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
: > "$OUT/alive.txt"

adb wait-for-device
adb logcat -G 16M >/dev/null 2>&1 || true
# Whatever happens next, leave the emulator without the app. Logged, never silent, never fatal.
final_uninstall() {
  local r; r="$(adb uninstall "$PKG" 2>&1 | tr -d '\r')"
  echo "final uninstall: ${r:-<no output>}" | tee -a "$OUT/install.txt"
}
trap final_uninstall EXIT

# log <text...>: one line into install.txt and the console.
log() { echo "$*" | tee -a "$OUT/install.txt"; }
: > "$OUT/install.txt"

# A cached AVD can carry the app from an earlier run signed with a different debug key. A smoke test wants a fresh install.
pre="$(adb uninstall "$PKG" 2>&1 | tr -d '\r')"
log "pre-install uninstall: ${pre:-<no output>}"

try_install() { # prints adb's whole answer, returns its status
  local r rc; r="$(adb install -r "$APK" 2>&1)"; rc=$?
  r="$(printf '%s' "$r" | tr -d '\r')"
  log "adb install -r (exit $rc): ${r:-<no output>}"
  return "$rc"
}
if ! try_install; then
  if grep -q 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' "$OUT/install.txt"; then
    log "install refused as INSTALL_FAILED_UPDATE_INCOMPATIBLE: removing the other copy with pm uninstall / pm clear, then retrying once"
    log "pm uninstall: $(adb shell pm uninstall "$PKG" 2>&1 | tr -d '\r')"
    log "pm clear: $(adb shell pm clear "$PKG" 2>&1 | tr -d '\r')"
    try_install || { echo "FAIL  adb install failed again after pm uninstall / pm clear (see $OUT/install.txt)"; exit 1; }
  else
    echo "FAIL  adb install failed (see $OUT/install.txt)"; exit 1
  fi
fi
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
