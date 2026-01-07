#!/usr/bin/env bash

info() { echo -e "${blue}===>${reset} $*"; }
ok() { echo -e "${green}[OK]${reset} $*"; }
warn() { echo -e "${yellow}[WARN]${reset} $*"; }
error() { echo -e "${red}$[ERR]${reset} $*" >&2; }
