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

autoload -Uz compinit; compinit

alias l='ls -lah --color=auto'
alias la='ls -lAh --color=auto'
alias ll='ls -lh --color=auto'
alias ls='ls -G --color=auto'
alias lsa='ls -lah --color=auto'

source <(fzf --zsh)
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"

# proxy
# hugo/go
export GOPROXY=https://goproxy.cn/,direct
export HUGO_MODULE_PROXY=https://goproxy.cn/,direct

# path
export PATH=$HOME/.local/bin:$PATH
