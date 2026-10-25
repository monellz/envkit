#!/usr/bin/env bash
set -euo pipefail

sudo pacman -S zsh zsh-completions
# chsh -s /usr/bin/zsh
sudo pacman -S fzf zoxide starship

# 字体
sudo pacman -S nerd-fonts
# 基础
sudo pacman -S noto-fonts noto-fonts-cjk noto-fonts-emoji
# 简体中文
sudo pacman -S adobe-source-han-sans-cn-fonts
# sudo yay -S noto-fonts-sc
# 更新字体缓存
# fc-cache -vf

# wm
sudo pacman -S hyprland qt5-wayland qt6-wayland
sudo pacman -S waybar

# 登录管理
sudo pacman -S sddm

# 文件管理器
sudo pacman -S yazi
sudo pacman -S fd
sudo pacman -S poppler

# 类似 Spotlight 的启动器
sudo pacman -S rofi rofi-calc

# 声音
# sudo pacman -S pipewire-pulse pipewire-alsa

# 微信

# 游戏
# steam/proton
# sudo pacman -S ttf-liberation


# fcitx5 输入法
# 用 fcitx5-configtool 配置
sudo pacman -S fcitx5-im fcitx5-rime rime-double-pinyin

# 其他
sudo pacman -S brightnessctl
sudo pacman -S bitwarden-cli

# 工具
sudo pacman -S btop bat

# ai
# yay -S perplexity


# 邮件
sudo pacman -S thunderbird


# 翻译
# ref: https://github.com/pot-app/pot-desktop
sudo pacman -S pot-translation
