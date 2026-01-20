HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

setopt HIST_SAVE_NO_DUPS
setopt INC_APPEND_HISTORY

# up/down
bindkey "\e[A" history-beginning-search-backward
bindkey "\e[B" history-beginning-search-forward

setopt autocd

# vim mode
bindkey -v
# 让vim在插入/命令模式下都能使用backspace
bindkey -M viins '^?' backward-delete-char
bindkey -M vicmd '^?' backward-delete-char 

autoload -Uz compinit; compinit

alias l='ls -lah --color=auto'
alias la='ls -lAh --color=auto'
alias ll='ls -lh --color=auto'
alias ls='ls -G --color=auto'
alias lsa='ls -lah --color=auto'

source <(fzf --zsh)
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"


# ssh-agent
if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    ssh-agent -t 1h > "$XDG_RUNTIME_DIR/ssh-agent.env"
fi
if [[ -z "$SSH_AUTH_SOCK" || ! -S "$SSH_AUTH_SOCK" ]]; then
    source "$XDG_RUNTIME_DIR/ssh-agent.env" >/dev/null
fi
if ! ssh-add -l >/dev/null 2>&1; then
    ssh-add ~/.ssh/id_rsa 2>/dev/null
fi

# yazi
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    command yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd < "$tmp"
    [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
}

# proxy
proxy() {
    if [[ $# -eq 0 ]]; then
        echo "Warning: No command provided. Setting proxy globally in current shell." >&2
    fi
    https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 "$@"
}

unproxy() {
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    echo "Proxy variables unset."
}
# hugo/go
export GOPROXY=https://goproxy.cn/,direct
export HUGO_MODULE_PROXY=https://goproxy.cn/,direct

# path
export PATH=$HOME/.local/bin:$PATH
