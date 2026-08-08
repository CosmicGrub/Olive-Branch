#!/usr/bin/env bash
# Vendor jitsi/docker-jitsi-meet at a pinned tag and lay Olive's env overrides
# on top of it. Does NOT start the stack — see ../with-jitsi.sh for that.
#
# LOCAL DEV/TEST ONLY, same status as tools/local-call-room-server.mjs.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# Re-verify this against https://github.com/jitsi/docker-jitsi-meet/tags
# before bumping — pin deliberately, don't float on `master`.
JITSI_TAG=${JITSI_TAG:-stable-11146-1}
CHECKOUT_DIR=.jitsi-docker

if [ -d "$CHECKOUT_DIR" ]; then
  echo "$CHECKOUT_DIR already exists — remove it first if you want a clean re-clone."
else
  echo "Cloning jitsi/docker-jitsi-meet @ $JITSI_TAG into $CHECKOUT_DIR ..."
  git clone --depth 1 --branch "$JITSI_TAG" \
    https://github.com/jitsi/docker-jitsi-meet.git "$CHECKOUT_DIR"
fi

cd "$CHECKOUT_DIR"

if [ ! -f .env ]; then
  cp env.example .env
  echo "Applying olive.env overrides on top of upstream env.example ..."
  # Append rather than sed-replace: docker-jitsi-meet's .env is read
  # top-to-bottom by docker compose's env_file loader, and a later
  # assignment of the same key wins — simplest way to layer without
  # depending on upstream's exact line numbers/comments staying stable.
  {
    echo ""
    echo "# --- Olive overrides (../olive.env) below this line ---"
    grep -v '^#' ../olive.env | grep -v '^$'
  } >> .env
else
  echo ".env already exists — not overwriting. Diff ../olive.env against it by hand if upstream's env.example changed."
fi

# Windows-only: see docker-compose.override.yml's own header comment for why.
# Harmless to copy on other platforms too — compose only applies the volume
# overrides it declares, and named volumes work fine on Linux/macOS as well.
cp ../docker-compose.override.yml .

if [ ! -x gen-passwords.sh ]; then
  echo "gen-passwords.sh missing or not executable in $CHECKOUT_DIR — checkout may be incomplete." >&2
  exit 1
fi
./gen-passwords.sh

mkdir -p ~/.jitsi-meet-cfg/{web,transcripts,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb,jigasi,jibri}

cat <<'EOF'

Setup complete. Next:
  ../with-jitsi.sh          # bring the stack up, wait for health
  ../with-jitsi.sh down     # tear it down

Web UI once running: https://127.0.0.1:8443 (self-signed cert, expect a
browser warning — that's expected for this dev stack).
EOF
