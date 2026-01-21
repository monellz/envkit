#!/usr/bin/env bash
set -euo pipefail

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $SHELL_DIR)
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

ROOT_CRT=$PROJECT_DIR/services/my_caddy_root.crt

ZOTERO_BASE="$HOME/.zotero/zotero"
PROFILE_REL=$(awk -F= '
  /^\[Profile/ {inprof=1; isdef=0; isrel=0; path=""}
  inprof && /^Default=1/ {isdef=1}
  inprof && /^IsRelative=1/ {isrel=1}
  inprof && /^Path=/ {path=$2}
  inprof && /^\[/ && $0 !~ /^\[Profile/ {inprof=0}
  inprof && isdef && isrel && path!="" {print path; exit}
' "$ZOTERO_BASE/profiles.ini")
ZOTERO_PROFILE="$ZOTERO_BASE/$PROFILE_REL"

info "this script should be run locally"
info "zotero_profile: $ZOTERO_PROFILE"

docker run --rm --network=host \
  -v "$ZOTERO_PROFILE:/zotero-profile" \
  -v "$ROOT_CRT:/root.crt:ro" \
  debian:bookworm-slim bash -lc '
    apt-get update && apt-get install -y --no-install-recommends libnss3-tools ca-certificates
    certutil -L -d sql:/zotero-profile | head
    certutil -A -d sql:/zotero-profile -n "Caddy Local CA" -t "CT,c,c" -i /root.crt
    certutil -L -d sql:/zotero-profile | grep -F "Caddy Local CA" || true
  '
