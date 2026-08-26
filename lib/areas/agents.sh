# Agents area: canonical shared instructions, pinned skills, and exact tool bridges.

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

validate_agents_closure() {
  local destination expected relative source index
  [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == common/agents ]] ||
    die 'Agents closure must contain only common/agents'
  if [[ "$MODE" != remove ]]; then
    "$DOTFILES_DIR/scripts/agent-skills" verify >/dev/null || die 'pinned agent skills verification failed'
  fi
  while IFS= read -r destination; do
    array_contains "$destination" "${LEAN_TARGET_PATHS[@]}" ||
      die "Agents package is missing locked skill target: $destination"
  done < <(jq -r '.skills[].files[].destination' "$DOTFILES_DIR/manifests/agent-skills.lock.json")
  ((${#LEAN_TARGET_PATHS[@]} == 1 + $(jq '[.skills[].files[]] | length' "$DOTFILES_DIR/manifests/agent-skills.lock.json"))) ||
    die 'Agents package target inventory is not exact'
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
    while IFS= read -r expected; do
      relative="${expected#"$destination"/}"
      expected_paths["$relative"]=1
      while [[ "$relative" == */* ]]; do relative="${relative%/*}"; expected_dirs["$relative"]=1; done
      agents_target_is_exact "$expected" && ((exact_count += 1))
    done < <(jq -r --arg destination "$destination" \
      '.skills[] | select(.destination == $destination) | .files[].destination' \
      "$DOTFILES_DIR/manifests/agent-skills.lock.json")
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
      die "unmanaged managed-skill directory conflict: $path"
    fi
  done < <(jq -r '.skills[].destination' "$DOTFILES_DIR/manifests/agent-skills.lock.json")
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
  register_agents_area
  validate_agents_closure
  preflight_agents_skill_boundaries apply
  lean_apply_area
  apply_agents_bridges
  "$DOTFILES_DIR/scripts/agent-skills" verify >/dev/null || die 'pinned agent skills changed during apply'
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
  lean_remove_stow
  log 'removed exact managed Agents links and bridges'
}
