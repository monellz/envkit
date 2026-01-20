#!/usr/bin/env bash

maysudo() {
    if [[ "${USE_SUDO:-0}" == 1 ]]; then
	sudo "$@"
    else
        "$@"
    fi
}

backup() {
    local fn="$1"
    if [ ! -f "$fn" ]; then
        error "$fn does not exist or is not a regular file"
        return 1
    fi
    local datetime=$(date +%Y%m%d-%H%M%S)
    local dst_fn="$fn.bak.$datetime"
    info "Backing up: $fn -> $dst_fn"
    maysudo mv "$fn" "$dst_fn"
}

copy() {
    local src="$1"
    local dst="$2"
    local dst_parent="$(dirname "$dst")"

    if [ ! -e $src ]; then
	warn "$src: Skip due to source missing"
	return 0
    fi

    if [ ! -d "$dst_parent" ]; then
        warn "Creating directory $dst_parent"
        maysudo mkdir -p $dst_parent
    fi

    if [ -e "$dst" ]; then
        if cmp -s $src $dst; then
            ok "$src -> $dst: Already up-to-date, copy skipped"
            return 0
        fi        
        backup $dst
    fi

    maysudo cp -f "$src" "$dst"
    ok "$src -> $dst: Copyed"
}


link() {
    local src="$1"
    local dst="$2"
    local dst_parent="$(dirname "$dst")"

    if [ ! -e $src ]; then
	warn "$src: Skip due to source missing"
	return 0
    fi

    if [ ! -d "$dst_parent" ]; then
        warn "Creating directory $dst_parent"
        maysudo mkdir -p $dst_parent
    fi

    if [ -L "$dst" ]; then
        local target="$(readlink $dst)"
	if [ "$target" = "$src" ]; then
	    ok "$src -> $dst: Already correctly linked"
	    return 0
	fi
    fi

    if [ -e "$dst" ]; then
        backup $dst
    fi

    maysudo ln -sf "$src" "$dst"
    ok "$src -> $dst: Linked"
}
