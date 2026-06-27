# =========================
# INSTANT PROMPT
# =========================

# Must stay at top for Powerlevel10k instant prompt rendering.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# =========================
# SHELL BEHAVIOR
# =========================

# History Configuration
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

# =========================
# KEY BINDINGS
# =========================

# Vim mode
KEYTIMEOUT=1
bindkey -v

# Delete in insert mode: delete character under cursor
bindkey -M viins "^[[3~" delete-char
# Ctrl+Right in insert mode: move forward one word
bindkey -M viins "^[[1;5C" forward-word
# Ctrl+Left in insert mode: move backward one word
bindkey -M viins "^[[1;5D" backward-word

# Ctrl+p in insert mode: search history backward by current prefix
bindkey -M viins '^p' history-search-backward
# Ctrl+n in insert mode: search history forward by current prefix
bindkey -M viins '^n' history-search-forward

# Home in insert mode: move to start of line
bindkey -M viins "^[[H" beginning-of-line
# End in insert mode: move to end of line
bindkey -M viins "^[[F" end-of-line

# =========================
# ZINIT
# =========================

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Install Zinit if not present
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname "$ZINIT_HOME")"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "${ZINIT_HOME}/zinit.zsh"

# Theme: Powerlevel10k (loaded immediately for instant prompt)
zinit ice depth=1
zinit light romkatv/powerlevel10k

# =========================
# PLUGINS
# =========================

zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Completion replay (must run after async plugins load)
zinit cdreplay -q

# =========================
# COMPLETION SYSTEM
# =========================

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# Disable compfix warnings (WSL compatibility)
ZSH_DISABLE_COMPFIX=true

# =========================
# PATH
# =========================

path_prepend() {
  [[ -d "$1" && ":$PATH:" != *":$1:"* ]] && export PATH="$1:$PATH"
}

path_append() {
  [[ -d "$1" && ":$PATH:" != *":$1:"* ]] && export PATH="$PATH:$1"
}

eval_if_available() {
  command -v "$1" >/dev/null 2>&1 && eval "$("${@:2}")"
}

# Core utilities
path_prepend "$HOME/.local/bin"

# Bun (Primary JavaScript runtime)
export BUN_INSTALL="$HOME/.bun"
path_prepend "$BUN_INSTALL/bin"

# pnpm (Backup package manager)
export PNPM_HOME="$HOME/.local/share/pnpm"
path_prepend "$PNPM_HOME"
path_prepend "$PNPM_HOME/bin"

# Development Tools
path_append "/usr/local/go/bin"        # Go
path_append "$HOME/.fly/bin"           # Fly.io
path_append "$HOME/.opencode/bin"      # OpenCode

# =========================
# TOOL INITIALIZATION
# =========================

# Bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# Zoxide: Improved `cd`
eval_if_available zoxide zoxide init --cmd cd zsh

# Mise: Manage multiple versions of tools
eval_if_available mise mise activate zsh

# Fuzzy finder
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# WorkTrunk
if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi

# Vite+
[ -s "$HOME/.vite-plus/env" ] && source "$HOME/.vite-plus/env"

# ALIASES
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases
[[ -f ~/.zsh_aliases.local ]] && source ~/.zsh_aliases.local

# Load Powerlevel10k config
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
