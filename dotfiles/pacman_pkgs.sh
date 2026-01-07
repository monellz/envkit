#!/usr/bin/env bash
set -euo pipefail

# fonts
sudo pacman -S nerd-fonts
# chinese
sudo pacman -S noto-fonts noto-fonts-cjk
# for simplified chinese
sudo pacman -S adobe-source-han-sans-cn-fonts
# sudo yay -S noto-fonts-sc

# wm
sudo pacman -S hyprland
sudo pacman -S waybar

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
sudo pacman -S btop

