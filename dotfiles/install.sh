#!/usr/bin/env bash
set -euo pipefail

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $SHELL_DIR)
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh


BASE_DIR=$SHELL_DIR
info "Base Dir: $BASE_DIR"

# dotfiles links
link ${BASE_DIR}/.vimrc ~/.vimrc

link ${BASE_DIR}/.gitconfig ~/.gitconfig

link ${BASE_DIR}/ssh/config ~/.ssh/config

link ${BASE_DIR}/hypr/hyprland.conf ~/.config/hypr/hyprland.conf

link ${BASE_DIR}/waybar/config.jsonc ~/.config/waybar/config.jsonc
link ${BASE_DIR}/waybar/style.css ~/.config/waybar/style.css

