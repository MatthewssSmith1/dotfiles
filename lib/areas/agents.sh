# Agents area: canonical shared instructions, managed skills, and exact tool bridges.

readonly AGENTS_BRIDGE_PATHS=(
  '.config/opencode/AGENTS.md'
  '.claude/CLAUDE.md'
)
readonly AGENTS_BRIDGE_LEXICAL=(
  '../../.agents/AGENTS.md'
  '../.agents/AGENTS.md'
)

agents_package_source() {
  printf '%s' "$DOTFILES_DIR/packages/common/agents/.agents/AGENTS.md"
}

register_agents_area() {
  local package
  load_profile_closure agents
  lean_begin_area agents "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
  lean_scan_packages
}

agents_target_is_exact() {
  local relative="$1" index
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    [[ "${LEAN_TARGET_PATHS[index]}" != "$relative" ]] || { lean_link_is_exact "$index"; return; }
  done
  return 1
}

agents_managed_skill_destinations() {
  local target relative
  declare -A destinations=()
  for target in "${LEAN_TARGET_PATHS[@]}"; do
    [[ "$target" == .agents/skills/*/* ]] || continue
    relative="${target#.agents/skills/}"
    destinations[".agents/skills/${relative%%/*}"]=1
  done
  printf '%s\n' "${!destinations[@]}"
}

validate_agents_closure() {
  local relative source index
  [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == common/agents ]] ||
    die 'Agents closure must contain only common/agents'
  if [[ "$MODE" != remove ]]; then
    "$DOTFILES_DIR/scripts/agent-skills" verify >/dev/null || die 'managed agent skills verification failed'
  fi
  array_contains '.agents/AGENTS.md' "${LEAN_TARGET_PATHS[@]}" || die 'Agents package is missing canonical instructions'
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    relative="${LEAN_TARGET_PATHS[index]}"; source="${LEAN_TARGET_SOURCES[index]}"
    [[ "$relative" == .agents/AGENTS.md || "$relative" == .agents/skills/* ]] ||
      die "Agents package has an out-of-area target: $relative"
    [[ "$(stat -c %a -- "$source")" == 644 ]] || die "unexpected Agents payload mode: $relative"
  done
}

preflight_agents_skill_boundaries() {
  local mode="$1" destination path entry relative expected exact_count
  declare -A expected_paths=() expected_dirs=()
  while IFS= read -r destination; do
    path="$HOME/$destination"
    validate_home_parent_chain "$path"
    [[ -e "$path" || -L "$path" ]] || continue
    [[ -d "$path" && ! -L "$path" ]] || die "managed skill is not a directory: $path"
    expected_paths=(); expected_dirs=(); exact_count=0
    for expected in "${LEAN_TARGET_PATHS[@]}"; do
      [[ "$expected" == "$destination"/* ]] || continue
      relative="${expected#"$destination"/}"
      expected_paths["$relative"]=1
      while [[ "$relative" == */* ]]; do relative="${relative%/*}"; expected_dirs["$relative"]=1; done
      agents_target_is_exact "$expected" && ((exact_count += 1))
    done
    shopt -s dotglob nullglob globstar
    for entry in "$path"/**; do
      relative="${entry#"$path"/}"
      [[ -n "$relative" ]] || continue
      if [[ -L "$entry" || -f "$entry" ]]; then
        [[ -n "${expected_paths[$relative]+x}" ]] || die "extra file in managed skill directory: $entry"
      elif [[ -d "$entry" ]]; then
        [[ -n "${expected_dirs[$relative]+x}" ]] || die "extra directory in managed skill directory: $entry"
      else
        die "extra file in managed skill directory: $entry"
      fi
    done
    shopt -u dotglob nullglob globstar
    if [[ "$mode" == apply && "$exact_count" == 0 ]]; then
      die "personal directory conflicts with managed skill: $path"
    fi
  done < <(agents_managed_skill_destinations)
}

remove_empty_agents_skill_directories() {
  local destination path index
  local directories=()
  while IFS= read -r destination; do
    path="$HOME/$destination"
    [[ -d "$path" && ! -L "$path" ]] || continue
    directories=()
    shopt -s dotglob nullglob globstar
    directories=("$path"/**/)
    shopt -u dotglob nullglob globstar
    for ((index=${#directories[@]}-1; index>=0; index--)); do
      rmdir -- "${directories[index]}" 2>/dev/null || true
    done
    rmdir -- "$path" 2>/dev/null || true
  done < <(agents_managed_skill_destinations)
}

agents_bridge_is_exact() {
  local index="$1" path="$HOME/${AGENTS_BRIDGE_PATHS[index]}" source
  source="$(agents_package_source)"
  [[ -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" &&
    "$(readlink -- "$path")" == "${AGENTS_BRIDGE_LEXICAL[index]}" &&
    "$(resolve_link "$path")" == "$source" ]]
}

preflight_agents_bridges() {
  local mode="$1" index path
  for index in "${!AGENTS_BRIDGE_PATHS[@]}"; do
    path="$HOME/${AGENTS_BRIDGE_PATHS[index]}"
    validate_home_parent_chain "$path"
    if [[ -e "$path" || -L "$path" ]]; then
      agents_bridge_is_exact "$index" || die "unrelated destination conflict: $path"
    elif [[ "$mode" == check ]]; then
      die "managed Agents bridge is absent: $path"
    fi
  done
}

preflight_agents() {
  register_agents_area
  validate_agents_closure
  preflight_agents_skill_boundaries "$MODE"
  lean_preflight_area "$MODE"
  preflight_agents_bridges "$MODE"
}

apply_agents_bridges() {
  local index path
  [[ -L "$HOME/.agents/AGENTS.md" && "$(resolve_link "$HOME/.agents/AGENTS.md")" == "$(agents_package_source)" ]] ||
    die 'Agents canonical instructions are not package-owned'
  for index in "${!AGENTS_BRIDGE_PATHS[@]}"; do
    agents_bridge_is_exact "$index" && continue
    path="$HOME/${AGENTS_BRIDGE_PATHS[index]}"
    lean_ensure_directory "$(dirname -- "$path")"
    ln -sT -- "${AGENTS_BRIDGE_LEXICAL[index]}" "$path" 2>/dev/null ||
      die "Agents bridge destination appeared concurrently; refusing to overwrite: $path"
    agents_bridge_is_exact "$index" || die "Agents bridge did not converge: $path"
  done
}

apply_agents() {
  preflight_agents
  lean_apply_area
  apply_agents_bridges
  "$DOTFILES_DIR/scripts/agent-skills" verify >/dev/null || die 'managed agent skills changed during apply'
  log "applied Agents area for profile '$SELECTED_PROFILE'"
}

remove_agents() {
  local index path
  register_agents_area
  validate_agents_closure
  preflight_agents_skill_boundaries remove
  lean_preflight_area remove
  preflight_agents_bridges remove
  for index in "${!AGENTS_BRIDGE_PATHS[@]}"; do
    path="$HOME/${AGENTS_BRIDGE_PATHS[index]}"
    agents_bridge_is_exact "$index" && rm -- "$path"
  done
  ((${#LEAN_ATTACHMENT_PATHS[@]} == 0 && ${#LEAN_JSON_PATHS[@]} == 0)) ||
    die 'Agents remove bypasses guarded teardown but guarded resources are registered'
  lean_remove_stow
  remove_empty_agents_skill_directories
  log 'removed exact managed Agents links and bridges'
}
