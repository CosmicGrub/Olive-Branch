#!/usr/bin/env bash
# Generates a self-signed TLS cert for the local Jitsi web/XMPP endpoint with
# a proper subjectAltName (SAN) extension, then wires it into both halves
# that must stay in sync:
#
#   1. The running stack's persisted cert location
#      (${CONFIG}/storage/web/keys/{cert.crt,cert.key} — see docker-jitsi-
#      meet's own /etc/s6-overlay/scripts/config: a cert already present
#      there is reused as-is, never regenerated, so this only needs to run
#      once unless you deliberately want a new cert).
#   2. client/android/app/src/debugLan/res/ — a GITIGNORED, debug-only overlay:
#      raw/jitsi_dev_cert.pem (the public cert only) and a
#      network-security-config rendered from network_security_config.debug.template.xml
#      for the LAN address(es) passed. Nothing LAN-specific is committed and a
#      release build never includes it. The private key is NOT written anywhere
#      in the repo and lives only in the CONFIG storage dir on the dev machine
#      that generated it.
#
# WHY a SAN is required, not optional: docker-jitsi-meet's own self-signed
# cert generation (`openssl req -new -x509 ... -subj "/CN=*"`) produces a
# cert with a legacy CN wildcard and ZERO extensions — confirmed via
# `openssl x509 -noout -ext subjectAltName` returning "No extensions in
# certificate". Modern TLS clients (Chrome/Chromium since ~2017, Android's
# default TLS stack used by jitsi_meet_flutter_sdk's underlying OkHttp/
# React-Native layer) ignore CN entirely for hostname verification and
# require SAN. Without this, even a device that's been told to TRUST the
# cert's issuer would still fail with a hostname-mismatch error — a second,
# separate failure mode from the "untrusted self-signed cert" one, and one
# that a bare CA-trust fix would not have caught.
#
# Usage:
#   ./generate-dev-cert.sh                    # SAN: 127.0.0.1, localhost
#   ./generate-dev-cert.sh 192.168.1.42       # + a LAN IP for WiFi-based
#                                                device testing (see
#                                                README.md's UDP/adb-reverse
#                                                section for why you'd need
#                                                this at all)
#
# Deliberately NOT auto-detecting or hardcoding a LAN IP by default — that
# is exactly the class of bug CHANGELOG [0.46.0] already fixed once
# (devRoomServerBase's old 192.0.2.78). Pass it explicitly, on purpose,
# when you actually need it, and regenerate when it changes.
#
# Re-running this after the app has already been built means the Android
# res/raw copy changes — rebuild the app afterward, or the old cert (still
# baked into the installed APK) won't match the new one on the server and
# you're back to a trust failure, just a differently-shaped one.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

CONFIG_DIR="${CONFIG:-$HOME/.jitsi-meet-cfg}"
KEYS_DIR="$CONFIG_DIR/storage/web/keys"
OVERLAY_DIR="${OLIVE_OVERLAY_DIR:-../../client/android/app/src/debugLan/res}"
ANDROID_RAW_DIR="$OVERLAY_DIR/raw"
ANDROID_XML_DIR="$OVERLAY_DIR/xml"
ANDROID_CERT_NAME="jitsi_dev_cert.pem"
TEMPLATE="./network_security_config.debug.template.xml"

mkdir -p "$KEYS_DIR"
mkdir -p "$ANDROID_RAW_DIR" "$ANDROID_XML_DIR"

SAN="IP:127.0.0.1,DNS:localhost"
for extra in "$@"; do
  SAN="$SAN,IP:$extra"
done
echo "Generating dev cert with SAN: $SAN"

# Git Bash/MSYS otherwise mangles the -subj value below (it starts with
# "/O=", which its path-conversion heuristic reads as a C: drive path) —
# scope the exclusion to just that value so -out/-keyout's genuine paths
# still convert normally.
MSYS2_ARG_CONV_EXCL="/O=" openssl req -new -x509 -days 3650 -nodes \
  -out "$KEYS_DIR/cert.crt" \
  -keyout "$KEYS_DIR/cert.key" \
  -subj "/O=Olive Branch Dev/OU=Jitsi self-host (local, not production)/CN=Olive Branch dev Jitsi" \
  -addext "subjectAltName=$SAN" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"

chmod 600 "$KEYS_DIR/cert.key"
cp "$KEYS_DIR/cert.crt" "$ANDROID_RAW_DIR/$ANDROID_CERT_NAME"

# Render the debug-only network-security-config overlay from the tracked template,
# with the trust scope in lockstep with the SAN list just written (cert SAN and
# trust scope must never drift). See nsc-scope.sh for exactly what is rewritten.
. ./nsc-scope.sh
cp "$TEMPLATE" "$ANDROID_XML_DIR/network_security_config.xml"
nsc_rewrite "$ANDROID_XML_DIR/network_security_config.xml" "$@"

echo ""
echo "Wrote:"
echo "  $KEYS_DIR/cert.crt + cert.key  (private key stays local, never committed)"
echo "  $ANDROID_RAW_DIR/$ANDROID_CERT_NAME  (public cert; gitignored debug overlay, never committed)"
echo "  $ANDROID_XML_DIR/network_security_config.xml  (gitignored debug overlay)"
echo ""
echo "Next:"
echo "  1. Restart the web container so nginx picks up the new cert:"
echo "       docker compose -f .jitsi-docker/docker-compose.yml restart web"
echo "  2. Rebuild the DEBUG Android app; the overlay trusts the pinned cert for the LAN"
echo "     address(es) above only. Release builds never include it."
