_dotfiles_bash_trace personal

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

_dotfiles_opencode_profile_directory_safe() {
  local directory="$HOME/.config/dotfiles/local" component mode
  for component in "$HOME" "$HOME/.config" "$HOME/.config/dotfiles" "$directory"; do
    [[ -d "$component" && ! -L "$component" && -O "$component" ]] || return 1
    mode="$(stat -c %a -- "$component")" || return 1
    ((8#$mode & 0022)) && return 1
  done
  return 0
}

_dotfiles_opencode_profile_read() {
  local path="$HOME/.config/dotfiles/local/opencode-profile" value size
  _dotfiles_opencode_profile_directory_safe || return 1
  [[ -f "$path" && ! -L "$path" && -O "$path" && -r "$path" ]] || return 1
  IFS= read -r value < "$path" || return 1
  case "$value" in personal|work) ;; *) return 1 ;; esac
  size="$(stat -c %s -- "$path")" || return 1
  [[ "$size" == $((${#value} + 1)) ]] || return 1
  printf '%s\n' "$value"
}

OPENCODE_DEFAULT_PROFILE="$(_dotfiles_opencode_profile_read 2>/dev/null)" || OPENCODE_DEFAULT_PROFILE=personal
export -n OPENCODE_DEFAULT_PROFILE 2>/dev/null || true

opencode-profile() {
  local profile path directory
  if (($# == 0)); then
    printf '%s\n' "$OPENCODE_DEFAULT_PROFILE"
    return 0
  fi
  if (($# != 1)); then
    printf '%s\n' 'usage: opencode-profile [personal|work]' >&2
    return 2
  fi
  profile="$1"
  case "$profile" in personal|work) ;; *)
    printf '%s\n' 'usage: opencode-profile [personal|work]' >&2
    return 2
  esac

  path="$HOME/.config/dotfiles/local/opencode-profile"
  directory="${path%/*}"
  _dotfiles_opencode_profile_directory_safe || return 1
  if [[ -e "$path" || -L "$path" ]]; then
    [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 1
  fi
  (
    local temporary
    umask 077
    temporary="$(mktemp "$directory/.opencode-profile.XXXXXX")" || exit 1
    trap 'rm -f -- "$temporary"' EXIT
    printf '%s\n' "$profile" > "$temporary" || exit 1
    chmod 0600 "$temporary" || exit 1
    command mv -f -- "$temporary" "$path" || exit 1
    trap - EXIT
  ) || return 1
  OPENCODE_DEFAULT_PROFILE="$profile"
  export -n OPENCODE_DEFAULT_PROFILE 2>/dev/null || true
  printf '%s\n' "$profile"
}

opencode() {
  case "$OPENCODE_DEFAULT_PROFILE" in
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
      printf 'invalid OpenCode profile: %s\n' "$OPENCODE_DEFAULT_PROFILE" >&2
      return 2
      ;;
  esac
}

claude() {
  local launcher="$HOME/.local/bin/claude-dotfiles"
  if [[ -x "$launcher" ]]; then
    "$launcher" "$@"
  else
    command claude "$@"
  fi
}

alias ocp='opencode-profile'
alias c-personal='opencode-personal'
alias c-work='opencode-work'
