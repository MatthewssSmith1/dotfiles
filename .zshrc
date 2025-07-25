# Add deno completions to search path
if [[ ":$FPATH:" != *":/home/matt/.zsh/completions:"* ]]; then export FPATH="/home/matt/.zsh/completions:$FPATH"; fi
ZSH_DISABLE_COMPFIX=true

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export PATH="$HOME/.fly/bin:/home/matt/.local/bin:$PATH"

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "${ZINIT_HOME}/zinit.zsh"

zinit ice depth=1; zinit light romkatv/powerlevel10k

zinit light zsh-users/zsh-syntax-highlighting
# zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins
# zinit snippet OMZP::git
# zinit snippet OMZP::sudo
# zinit snippet OMZP::ubuntu
# zinit snippet OMZP::command-not-found
# zinit snippet OMZP::rust

# autoload -Uz compinit && compinit

zinit cdreplay -q

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word

HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

alias ..="cd .."
alias ...="cd ../.."

alias c='clear'
alias ls='ls --color'
alias vi='nvim'
alias vim='nvim'
alias npm='pnpm'
alias r='cargo watch -q -c -w templates -w src -x run'
alias t='cargo watch -q -c -w templates -w styles -s ./tailwind.sh'
alias gac='git add . && git commit -m'
alias gpo='git push origin'
alias gco='git checkout'
alias ar='php artisan'
alias crd='composer run dev'
alias supabase='npx supabase'
alias sandbox='pnpm sandbox'
alias s='pnpm sandbox:log'
alias d='cd dream'
alias dev='pnpm dev'
alias dezone="find . -type f -name '*Zone.Identifier' -delete"
alias w="windsurf"

# eval "$(fzf --zsh)"
eval "$(zoxide init --cmd cd zsh)"

# Turso
export PATH="$PATH:/home/matt/.turso"

eval "$(rbenv init -)"

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME="$HOME/android_sdk"
export PATH="$PATH:$HOME/android_sdk/cmdline-tools/latest/bin"
export PATH=$PATH:/mnt/c/Users/matth/AppData/Local/Android/Sdk/platform-tools

export PATH=$PATH:/usr/local/go/bin

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="/home/matt/.config/herd-lite/bin:$PATH"
export PHP_INI_SCAN_DIR="/home/matt/.config/herd-lite/bin:$PHP_INI_SCAN_DIR"
. "/home/matt/.deno/env"

# pnpm
export PNPM_HOME="/home/matt/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
