#!/usr/bin/env bash
set -euo pipefail

sudo pacman -S zsh zsh-completions
# chsh -s /usr/bin/zsh
sudo pacman -S fzf zoxide starship

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
sudo pacman -S hyprland qt5-wayland qt6-wayland
sudo pacman -S waybar

# login
sudo pacman -S sddm

# file manager
sudo pacman -S yazi
sudo pacman -S fd
sudo pacman -S poppler

# spotlight-like
sudo pacman -S rofi rofi-calc

# sound
# sudo pacman -S pipewire-pulse pipewire-alsa

# wechat

# game
# steam/proton
# sudo pacman -S ttf-liberation


# fcitx5
# use fcitx5-configtool to configure it
sudo pacman -S fcitx5-im fcitx5-rime rime-double-pinyin

# others
sudo pacman -S brightnessctl
sudo pacman -S bitwarden-cli

# tool
sudo pacman -S btop bat

# ai
# yay -S perplexity


# mail
sudo pacman -S thunderbird


# translator
# ref: https://github.com/pot-app/pot-desktop
sudo pacman -S pot-translation
