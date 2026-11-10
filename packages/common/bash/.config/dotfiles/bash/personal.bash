_dotfiles_bash_trace personal

alias dot='dotfiles'
alias ts='tailscale'
alias m='mimir'
alias mr='mise run'

# Interactive mise shims can precede ~/.local/bin; always enter the personal editor.
nvim() {
  if [[ -x "$HOME/.local/bin/nvim" ]]; then
    "$HOME/.local/bin/nvim" "$@"
  else
    command nvim "$@"
  fi
}

if [[ -x "$HOME/.local/bin/nvim" ]]; then
  case "${EDITOR:-}" in ''|nvim|/usr/bin/nvim) export EDITOR="$HOME/.local/bin/nvim" ;; esac
  case "${VISUAL:-}" in ''|nvim|/usr/bin/nvim) export VISUAL="$HOME/.local/bin/nvim" ;; esac
fi

# pnpm (Backup package manager); v11 installs global binaries under $PNPM_HOME/bin.
export PNPM_HOME="$HOME/.local/share/pnpm"
for _dotfiles_bash_pnpm_dir in "$PNPM_HOME" "$PNPM_HOME/bin"; do
  case ":$PATH:" in
    *":$_dotfiles_bash_pnpm_dir:"*) ;;
    *) PATH="$_dotfiles_bash_pnpm_dir:$PATH" ;;
  esac
done
unset _dotfiles_bash_pnpm_dir
export PATH

_dotfiles_agent_profile_directory_safe() {
  local directory="$HOME/.config/dotfiles/local" component mode
  for component in "$HOME" "$HOME/.config" "$HOME/.config/dotfiles" "$directory"; do
    [[ -d "$component" && ! -L "$component" && -O "$component" ]] || return 1
    mode="$(stat -c %a -- "$component")" || return 1
    ((8#$mode & 0022)) && return 1
  done
  return 0
}

_dotfiles_agent_profile_read() {
  local path="$HOME/.config/dotfiles/local/agent-profile" value size
  _dotfiles_agent_profile_directory_safe || return 1
  [[ -f "$path" && ! -L "$path" && -O "$path" && -r "$path" ]] || return 1
  IFS= read -r value < "$path" || return 1
  case "$value" in personal|work) ;; *) return 1 ;; esac
  size="$(stat -c %s -- "$path")" || return 1
  [[ "$size" == $((${#value} + 1)) ]] || return 1
  printf '%s\n' "$value"
}

DOTFILES_AGENT_PROFILE="$(_dotfiles_agent_profile_read 2>/dev/null)" || DOTFILES_AGENT_PROFILE=personal
export -n DOTFILES_AGENT_PROFILE 2>/dev/null || true

agent-profile() {
  local profile path directory
  if (($# == 0)); then
    printf '%s\n' "$DOTFILES_AGENT_PROFILE"
    return 0
  fi
  if (($# != 1)); then
    printf '%s\n' 'usage: agent-profile [personal|work]' >&2
    return 2
  fi
  profile="$1"
  case "$profile" in personal|work) ;; *)
    printf '%s\n' 'usage: agent-profile [personal|work]' >&2
    return 2
  esac

  path="$HOME/.config/dotfiles/local/agent-profile"
  directory="${path%/*}"
  _dotfiles_agent_profile_directory_safe || return 1
  if [[ -e "$path" || -L "$path" ]]; then
    [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 1
  fi
  (
    local temporary
    umask 077
    temporary="$(mktemp "$directory/.agent-profile.XXXXXX")" || exit 1
    trap 'rm -f -- "$temporary"' EXIT
    printf '%s\n' "$profile" > "$temporary" || exit 1
    chmod 0600 "$temporary" || exit 1
    command mv -f -- "$temporary" "$path" || exit 1
    trap - EXIT
  ) || return 1
  DOTFILES_AGENT_PROFILE="$profile"
  export -n DOTFILES_AGENT_PROFILE 2>/dev/null || true
  printf '%s\n' "$profile"
}

opencode() {
  case "$DOTFILES_AGENT_PROFILE" in
    personal)
      local launcher="$HOME/.local/share/dotfiles/bin/opencode-launch"
      if [[ -x "$launcher" ]]; then
        "$launcher" personal "$@"
      else
        command opencode "$@"
      fi
      ;;
    work) opencode-work "$@" ;;
    *)
      printf 'invalid agent profile: %s\n' "$DOTFILES_AGENT_PROFILE" >&2
      return 2
      ;;
  esac
}

claude() {
  case "$DOTFILES_AGENT_PROFILE" in
    personal)
      local launcher="$HOME/.local/bin/claude-dotfiles"
      if [[ -x "$launcher" ]]; then
        "$launcher" personal "$@"
      else
        command claude "$@"
      fi
      ;;
    work) claude-work "$@" ;;
    *)
      printf 'invalid agent profile: %s\n' "$DOTFILES_AGENT_PROFILE" >&2
      return 2
      ;;
  esac
}

alias c-personal='opencode-personal'
alias c-work='opencode-work'
alias cx-personal='claude-personal'
alias cx-work='claude-work'
