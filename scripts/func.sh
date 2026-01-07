#!/usr/bin/env bash

backup() {
    local fn="$1"
    if [ ! -f "$fn" ]; then
        error "$fn does not exist or is not a regular file"
        return 1
    fi
    local datetime=$(date +%Y%m%d-%H%M%S)
    local dst_fn="$fn.bak.$datetime"
    info "Backing up: $fn -> $dst_fn"
    mv "$fn" "$dst_fn"
}

copy() {
    local src="$1"
    local dst="$2"
    local dst_parent="$(dirname "$dst")"

    if [ ! -d "$dst_parent" ]; then
        warn "Creating directory $dst_parent"
        mkdir -p $dst_parent
    fi

    if [ -e "$dst" ]; then
        backup $dst
    fi
    cp -f "$src" "$dst"
    ok "$src -> $dst: Copyed"
}


link() {
    local src="$1"
    local dst="$2"
    local dst_parent="$(dirname "$dst")"

    if [ ! -d "$dst_parent" ]; then
        warn "Creating directory $dst_parent"
        mkdir -p $dst_parent
    fi

    if [ -e "$dst" ]; then
        backup $dst
    fi
    ln -sf "$src" "$dst"
    ok "$src -> $dst: Linked"
}

