# Bash area converted to the lean package and guarded-attachment lifecycle.

readonly BASH_RC_BEGIN='# >>> dotfiles managed bash >>>'
readonly BASH_RC_END='# <<< dotfiles managed bash <<<'
readonly BASH_RC_TOKEN='dotfiles managed bash'
readonly BASH_RC_BLOCK="$BASH_RC_BEGIN
. \"\$HOME/.config/dotfiles/bash/rc.bash\"
$BASH_RC_END"
readonly BASH_STARSHIP_SELECTOR='aqua:starship/starship@1.26.0'

register_bash_area() {
  local package refresh=false
  load_profile_closure bash
  lean_begin_area bash "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
  [[ "$SELECTED_PROFILE" != omarchy ]] || refresh=true
  lean_add_guarded_attachment bash-rc-v2 .bashrc "$BASH_RC_BEGIN" "$BASH_RC_END" \
    "$BASH_RC_TOKEN" "$BASH_RC_BLOCK" append 0644 "$refresh"
}

validate_bash_closure() {
  local expected relative source mode index
  local -a expected_targets=(
    .config/dotfiles/bash/integrations.bash
    .config/dotfiles/bash/personal.bash
    .config/dotfiles/bash/rc.bash
  )
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "${PACKAGES[*]}" == 'common/bash' ]] || die 'native Bash closure must contain only common/bash'
    [[ -f "$HOME/.bashrc" && ! -L "$HOME/.bashrc" ]] ||
      die 'Omarchy native ~/.bashrc baseline is missing or not a regular file'
  else
    [[ "${PACKAGES[*]}" == 'upstream/bash upstream/starship ubuntu/bash common/bash' ]] ||
      die 'Ubuntu Bash closure must be exactly upstream Bash, Starship, Ubuntu, and common'
    expected_targets+=(
      .config/dotfiles/bash/env.bash
      .config/dotfiles/bash/init.bash
      .config/dotfiles/bash/ubuntu.bash
      .config/dotfiles/upstream/bash/aliases
      .config/dotfiles/upstream/bash/fns/tmux
      .config/dotfiles/upstream/bash/inputrc
      .config/dotfiles/upstream/bash/shell
      .config/mise/conf.d/40-dotfiles-bash-ubuntu.toml
      .config/starship.toml
      .local/share/dotfiles/bin/bat
      .local/share/dotfiles/bin/dotfiles-secret
      .local/share/dotfiles/bin/fd
    )
  fi
  lean_scan_packages
  ((${#LEAN_TARGET_PATHS[@]} == ${#expected_targets[@]})) || die 'Bash package target inventory is not exact'
  for expected in "${expected_targets[@]}"; do
    array_contains "$expected" "${LEAN_TARGET_PATHS[@]}" || die "Bash package closure is missing expected target: $expected"
  done
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    relative="${LEAN_TARGET_PATHS[index]}"
    source="${LEAN_TARGET_SOURCES[index]}"
    mode=644
    case "$relative" in .local/share/dotfiles/bin/*) mode=755 ;; esac
    [[ "$(stat -c %a -- "$source")" == "$mode" ]] || die "unexpected Bash payload mode for $relative"
    case "$relative" in *.bash|.local/share/dotfiles/bin/*) bash -n "$source" || die "invalid Bash payload syntax: $relative" ;; esac
  done
}

validate_bash_local_layer() {
  local path="$HOME/.config/dotfiles/local/bash.sh"
  validate_home_parent_chain "$path"
  [[ ! -e "$path" && ! -L "$path" ]] && return 0
  [[ -f "$path" && ! -L "$path" && -O "$path" && -r "$path" ]] ||
    die "host-local Bash layer is not a readable user-owned regular file: $path"
  file_contains_nul "$path" && die "host-local Bash layer contains NUL bytes: $path"
  bash -n "$path" || die "host-local Bash layer has invalid Bash syntax: $path"
}

bash_missing_guidance() {
  [[ "$SELECTED_PROFILE" != ubuntu ]] || command_capability_exists starship || {
    log "error: Starship is absent; install it manually with: mise install $BASH_STARSHIP_SELECTOR"
    return 1
  }
}

validate_ubuntu_bash_login_startup() {
  [[ "$SELECTED_PROFILE" == ubuntu ]] || return 0
  local account shell path
  account="$(getent passwd "$(id -u)")" || die 'could not determine the account login shell'
  shell="${account##*:}"
  [[ "${shell##*/}" == bash ]] || return 0
  for path in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bash_login"; do
    [[ ! -e "$path" && ! -L "$path" ]] || return 0
  done
  die 'Ubuntu Bash login startup is missing: ~/.profile, ~/.bash_profile, and ~/.bash_login are absent; manually restore a host-owned ~/.profile that sources ~/.bashrc, then rerun'
}

preflight_bash() {
  register_bash_area
  validate_bash_closure
  if [[ "$MODE" == remove ]]; then
    lean_preflight_area remove
    return
  fi
  validate_ubuntu_bash_login_startup
  validate_bash_local_layer
  bash_missing_guidance || return 1
  lean_preflight_area "$MODE"
}

apply_bash() {
  register_bash_area
  validate_bash_closure
  validate_bash_local_layer
  lean_apply_area
  log "applied Bash area for profile '$SELECTED_PROFILE'"
}

remove_bash() {
  register_bash_area
  lean_remove_area
  log 'removed exact managed Bash links and source block; retained host-local Bash data'
}
