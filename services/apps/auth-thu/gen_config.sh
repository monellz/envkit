#!/usr/bin/env bash
set -euo pipefail

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $(dirname $(dirname $SHELL_DIR)))

SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

read -rp "Enter username: " USERNAME
read -rsp "Enter password: " PASSWORD
read -rp "Enable debug? [true/false] (default: true): " DEBUG_INPUT
DEBUG="${DEBUG_INPUT:-true}"

if [[ "$DEBUG" != "true" && "$DEBUG" != "false" ]]; then
    warn "Invalid input for debug, using default: true"
    DEBUG=true
fi


CONFIG_DIR=$PROJECT_DIR/services/configs/auth-thu
mkdir -p $CONFIG_DIR
OUTPUT_DIR=$CONFIG_DIR/auth-thu.json

cat <<EOF > "$OUTPUT_DIR"
{
  "username": "$USERNAME",
  "password": "$PASSWORD",
  "debug": $DEBUG
}
EOF
