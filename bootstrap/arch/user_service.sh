#!/usr/bin/env bash
set -euo pipefail

# this script should be run by user

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $(dirname $SHELL_DIR))
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh



# ssh-agent
systemctl --user enable --now ssh-agent
ssh-add ~/.ssh/id_rsa
# ssh-add -l

# sound
# sudo pacman -S pipewire-pulse pipewire-alsa
systemctl --user enable --now pipiewire-pulse
warn "Reboot is needed to make sound work well"

