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

sudo pacman -S dkms linux-headers
sudo pacman -S nvidia-open-dkms 
sudo pacman -S nvtop

# early load is necessary
# ref: https://wiki.archlinux.org/title/NVIDIA#Early_loading
USE_SUDO=1 copy $SHELL_DIR/etc/modules-load.d/nvidia.conf /etc/modules-load.d/nvidia.conf

