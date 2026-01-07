#!/usr/bin/env bash
set -euo pipefail

# this script should be run by user

sudo systemctl enable --now systemd-networkd
sudo systemctl enable --now systemd-resolved

sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
