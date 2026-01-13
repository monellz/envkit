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
link ${BASE_DIR}/zsh/.zshrc ~/.zshrc
link ${BASE_DIR}/zsh/.zshenv ~/.zshenv

link ${BASE_DIR}/.vimrc ~/.vimrc

link ${BASE_DIR}/.gitconfig ~/.gitconfig

link ${BASE_DIR}/ssh/config ~/.ssh/config

link ${BASE_DIR}/ghostty/config ~/.config/ghostty/config

link ${BASE_DIR}/hypr/hyprland.conf ~/.config/hypr/hyprland.conf

link ${BASE_DIR}/waybar/config.jsonc ~/.config/waybar/config.jsonc
link ${BASE_DIR}/waybar/style.css ~/.config/waybar/style.css

# https://gist.github.com/yagehu/7bec7492afd5ba846f99abb00c850d01
link ${BASE_DIR}/rime/default.custom.yaml ~/.local/share/fcitx5/rime/default.custom.yaml

