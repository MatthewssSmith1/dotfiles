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

# Install Zinit if its entrypoint is not initialized.
if [ ! -r "$ZINIT_HOME/zinit.zsh" ]; then
   mkdir -p "$(dirname "$ZINIT_HOME")"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

if [[ ! -f "$ZINIT_HOME/zinit.zsh" || -L "$ZINIT_HOME/zinit.zsh" ||
  ! -O "$ZINIT_HOME/zinit.zsh" || ! -r "$ZINIT_HOME/zinit.zsh" ]]; then
  print -u2 -- "unsafe Zinit entrypoint: $ZINIT_HOME/zinit.zsh"
  return 1
fi
source "${ZINIT_HOME}/zinit.zsh"

zinit_plugins_root="${ZINIT_HOME:h}/plugins"
zinit_plugins_ready=true
for zinit_plugin_dir in \
  romkatv---powerlevel10k \
  zsh-users---zsh-syntax-highlighting \
  zsh-users---zsh-autosuggestions \
  Aloxaf---fzf-tab; do
  [[ -d "$zinit_plugins_root/$zinit_plugin_dir" && ! -L "$zinit_plugins_root/$zinit_plugin_dir" &&
    -O "$zinit_plugins_root/$zinit_plugin_dir" &&
    -d "$zinit_plugins_root/$zinit_plugin_dir/.git" && ! -L "$zinit_plugins_root/$zinit_plugin_dir/.git" &&
    -O "$zinit_plugins_root/$zinit_plugin_dir/.git" ]] || \
    zinit_plugins_ready=false
done

if $zinit_plugins_ready; then
  # Local-only loading: Git refuses every network protocol during plugin setup.
  GIT_ALLOW_PROTOCOL=file zinit ice depth=1
  GIT_ALLOW_PROTOCOL=file zinit light romkatv/powerlevel10k

  # =========================
  # PLUGINS
  # =========================

  GIT_ALLOW_PROTOCOL=file zinit light zsh-users/zsh-syntax-highlighting
  GIT_ALLOW_PROTOCOL=file zinit light zsh-users/zsh-autosuggestions
  GIT_ALLOW_PROTOCOL=file zinit light Aloxaf/fzf-tab

  # Completion replay (must run after async plugins load)
  GIT_ALLOW_PROTOCOL=file zinit cdreplay -q
fi
unset zinit_plugin_dir zinit_plugins_ready zinit_plugins_root

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

# Go
path_append "/usr/local/go/bin"
path_append "$HOME/go/bin"

# Bun (Primary JavaScript runtime)
export BUN_INSTALL="$HOME/.bun"
path_prepend "$BUN_INSTALL/bin"

# pnpm (Backup package manager)
export PNPM_HOME="$HOME/.local/share/pnpm"
path_prepend "$PNPM_HOME"
path_prepend "$PNPM_HOME/bin"

# Development Tools
path_append "$HOME/.fly/bin"           # Fly.io
path_append "$HOME/.opencode/bin"      # OpenCode

# =========================
# TOOL INITIALIZATION
# =========================

# Bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# Mise: Manage multiple versions of tools
eval_if_available mise env MISE_OFFLINE=1 mise activate zsh

# Zoxide: Improved `cd`
eval_if_available zoxide zoxide init --cmd cd zsh

# Fuzzy finder
if command -v fzf >/dev/null 2>&1; then
  for _dotfiles_fzf_file in /usr/share/fzf/completion.zsh /usr/share/doc/fzf/examples/completion.zsh; do
    [[ ! -r "$_dotfiles_fzf_file" ]] || { source "$_dotfiles_fzf_file"; break; }
  done
  for _dotfiles_fzf_file in /usr/share/fzf/key-bindings.zsh /usr/share/doc/fzf/examples/key-bindings.zsh; do
    [[ ! -r "$_dotfiles_fzf_file" ]] || { source "$_dotfiles_fzf_file"; break; }
  done
  unset _dotfiles_fzf_file
fi

# WorkTrunk
if command -v wt >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1; then
  _dotfiles_wt_init="$(unshare --user --map-current-user --net env MISE_OFFLINE=1 wt config shell init zsh 2>/dev/null)" || \
    _dotfiles_wt_init=""
  [[ -z $_dotfiles_wt_init ]] || eval "$_dotfiles_wt_init"
  unset _dotfiles_wt_init
fi

# Vite+
[ -s "$HOME/.vite-plus/env" ] && source "$HOME/.vite-plus/env"

# ALIASES
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases
[[ -f ~/.zsh_aliases.local && ! -L ~/.zsh_aliases.local && -O ~/.zsh_aliases.local && -r ~/.zsh_aliases.local ]] && \
  source ~/.zsh_aliases.local

# Load Powerlevel10k config
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
