#!/usr/bin/env bash
# Library (sourced by generate-dev-cert.sh and its test): rewrite the Android
# network-security-config trust scope for the self-hosted Jitsi.
#
# The ONLY extra trust the app ever grants is the one pinned public cert in
# res/raw/jitsi_dev_cert.pem, for the LAN address(es) between the
# OLIVE-LAN-JITSI-BEGIN/END markers of the main and debug configs. The base
# config (system CAs only, no cleartext) is never touched. No LAN IP argument
# means the block is emptied: NO extra trust at all.
#
#   nsc_rewrite <xml-file> [lan-ip ...]
nsc_rewrite() {
  local f="$1"; shift
  local crlf=0
  [ -f "$f" ] || { echo "  (skip: $f not found)"; return 0; }
  # tr, not grep: Git-for-Windows grep strips the CR before matching.
  if [ "$(tr -cd '\r' < "$f" | wc -c)" -gt 0 ]; then crlf=1; fi
  sed -i 's/\r$//' "$f"
  grep -q 'OLIVE-LAN-JITSI-BEGIN' "$f" && grep -q 'OLIVE-LAN-JITSI-END' "$f" || {
    echo "  $f has no OLIVE-LAN-JITSI markers; refusing to edit" >&2; return 1; }
  local tmp; tmp="$(mktemp)"
  awk -v ips="$*" '
    /OLIVE-LAN-JITSI-BEGIN/ { print; inblock = 1; hdr = 1; next }
    /OLIVE-LAN-JITSI-END/   { inblock = 0; print; next }
    inblock && hdr {
      print
      if ($0 ~ /-->/) {
        hdr = 0
        n = split(ips, a, " ")
        if (n > 0) {
          print "    <domain-config cleartextTrafficPermitted=\"false\">"
          for (i = 1; i <= n; i++) print "        <domain includeSubdomains=\"false\">" a[i] "</domain>"
          print "        <trust-anchors>"
          print "            <certificates src=\"@raw/jitsi_dev_cert\" />"
          print "            <certificates src=\"system\" />"
          print "        </trust-anchors>"
          print "    </domain-config>"
        }
      }
      next
    }
    inblock { next }
    { print }
  ' "$f" > "$tmp"
  cat "$tmp" > "$f"; rm -f "$tmp"
  [ "$crlf" = 1 ] && sed -i 's/$/\r/' "$f"
  echo "  network-security-config scope updated: $f"
  return 0
}
