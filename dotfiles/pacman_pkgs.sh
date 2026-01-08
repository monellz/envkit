#!/usr/bin/env bash
set -euo pipefail

# fonts
sudo pacman -S nerd-fonts
# basic
sudo pacman -S noto-fonts noto-fonts-cjk noto-fonts-emoji
# for simplified chinese
sudo pacman -S adobe-source-han-sans-cn-fonts
# sudo yay -S noto-fonts-sc
# update font cache
# fc-cache -vf

# wm
sudo pacman -S hyprland
sudo pacman -S waybar

# login
sudo pacman -S sddm

# file manager
sudo pacman -S yazi

# sound
# sudo pacman -S pipewire-pulse pipewire-alsa

# wechat

# game
# steam/proton


# fcitx5
# use fcitx5-configtool to configure it
sudo pacman -S fcitx5-im fcitx5-rime

# others
sudo pacman -S brightnessctl

# tool
sudo pacman -S btop bat

