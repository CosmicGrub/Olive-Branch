#!/usr/bin/env bash
# Update to the latest main (or --ref TAG). Same as deploy.sh.
exec "$(dirname "${BASH_SOURCE[0]}")/deploy.sh" "$@"
