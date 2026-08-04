# Agents area: canonical shared instructions and skills plus tool bridges.

readonly AGENTS_BRIDGE_PATHS=(
  '.config/opencode/AGENTS.md'
  '.claude/CLAUDE.md'
)
readonly AGENTS_BRIDGE_LEXICAL=(
  '../../.agents/AGENTS.md'
  '../.agents/AGENTS.md'
)

init_agents_area() {
  AREA=agents
  AREA_JOURNAL_PATHS=()
  AREA_ATTACHMENT_VALIDATOR=validate_agents_state
}

validate_agents_state() {
  local state="$1" index checkout expected_source relative expected_lexical
  [[ "$(jq '.attachments | length' "$state")" == 0 ]] || die 'agents state records unknown attachments'
  [[ "$(jq '.backups | length' "$state")" == 0 ]] || die 'agents state records unknown backups'
  [[ "$(jq -c .packages "$state")" == '["common/agents"]' ]] || die 'agents state records an unexpected package closure'
  checkout="$(jq -r .checkout_root "$state")"
  expected_source="$checkout/packages/common/agents/.agents/AGENTS.md"
  for index in "${!AGENTS_BRIDGE_PATHS[@]}"; do
    [[ "$(jq -r ".targets[$index].path" "$state")" == "${AGENTS_BRIDGE_PATHS[index]}" ]] || \
      die 'agents state does not order bridges before canonical package targets'
    [[ "$(jq -r ".targets[$index].source" "$state")" == "${AGENTS_BRIDGE_LEXICAL[index]}" && \
      "$(jq -r ".targets[$index].resolved_source" "$state")" == "$expected_source" ]] || \
      die 'agents state records an unexpected instruction bridge'
  done
  [[ "$(jq '.targets | length' "$state")" -gt 2 ]] || die 'agents state has no package target closure'
  for ((index=2; index<$(jq '.targets | length' "$state"); index++)); do
    relative="$(jq -r ".targets[$index].path" "$state")"
    [[ "$relative" == .agents/* ]] || die "agents state records an out-of-area target: $relative"
    expected_source="$checkout/packages/common/agents/$relative"
    expected_lexical="$(realpath -m -s --relative-to="$(dirname -- "$TARGET_ROOT/$relative")" -- "$expected_source")"
    [[ "$(jq -r ".targets[$index].source" "$state")" == "$expected_lexical" && \
      "$(jq -r ".targets[$index].resolved_source" "$state")" == "$expected_source" ]] || \
      die "agents state records unexpected ownership for $relative"
  done
}

agents_package_source() {
  printf '%s' "$DOTFILES_DIR/packages/common/agents/.agents/AGENTS.md"
}

preflight_agents_skill_boundaries() {
  local allow_desired="${1:-false}" name destination path entry relative expected
  declare -A expected_paths=() expected_dirs=()
  while IFS=$'\t' read -r name destination; do
    path="$HOME/$destination"
    validate_home_parent_chain "$path"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
      continue
    fi
    [[ "$OLD_STATE" == true || "$allow_desired" == true ]] || die "unmanaged managed-skill directory conflict: $path"
    [[ -d "$path" && ! -L "$path" ]] || die "managed skill is not a directory: $path"
    expected_paths=()
    expected_dirs=()
    while IFS= read -r expected; do
      relative="${expected#"$destination"/}"
      expected_paths["$relative"]=1
      while [[ "$relative" == */* ]]; do
        relative="${relative%/*}"
        expected_dirs["$relative"]=1
      done
    done < <(jq -r --arg destination "$destination" \
      '.skills[] | select(.destination == $destination) | .files[].destination' \
      "$DOTFILES_DIR/manifests/agent-skills.lock.json")
    if [[ "$OLD_STATE" == true ]]; then
      while IFS= read -r expected; do
        relative="${expected#"$destination"/}"
        expected_paths["$relative"]=1
        while [[ "$relative" == */* ]]; do
          relative="${relative%/*}"
          expected_dirs["$relative"]=1
        done
      done < <(jq -r --arg prefix "$destination/" \
        '.targets[].path | select(startswith($prefix))' "$AREA_STATE")
    fi
    shopt -s dotglob nullglob globstar
    for entry in "$path"/**; do
      relative="${entry#"$path"/}"
      [[ -n "$relative" ]] || continue
      if [[ -L "$entry" ]]; then
        [[ -n "${expected_paths[$relative]+x}" ]] || die "extra file in managed skill directory: $entry"
      elif [[ -d "$entry" ]]; then
        [[ -n "${expected_dirs[$relative]+x}" ]] || die "extra directory in managed skill directory: $entry"
      else
        die "extra file in managed skill directory: $entry"
      fi
    done
    shopt -u dotglob nullglob globstar
  done < <(jq -r '.skills[] | [.name,.destination] | @tsv' "$DOTFILES_DIR/manifests/agent-skills.lock.json")
}

preflight_agents_bridges() {
  local index relative path source state_index
  source="$(agents_package_source)"
  for index in "${!AGENTS_BRIDGE_PATHS[@]}"; do
    relative="${AGENTS_BRIDGE_PATHS[index]}"
    path="$HOME/$relative"
    validate_home_parent_chain "$path"
    if [[ -L "$path" && "$(readlink -- "$path")" == "${AGENTS_BRIDGE_LEXICAL[index]}" && \
      "$(resolve_link "$path")" == "$source" ]]; then
      continue
    fi
    if [[ "$OLD_STATE" == true ]]; then
      state_index="$(state_target_index "$AREA_STATE" "$relative")"
      [[ -z "$state_index" ]] || continue
    fi
    [[ ! -e "$path" && ! -L "$path" ]] || die "unrelated destination conflict: $path"
  done
}

preflight_agents() {
  local relative
  init_agents_area
  "$DOTFILES_DIR/scripts/agent-skills" verify >/dev/null || die 'pinned agent skills verification failed'
  load_profile_closure agents
  scan_packages
  record_managed_parents '.local/state/dotfiles/v1/agents.json'
  for relative in "${AGENTS_BRIDGE_PATHS[@]}"; do
    AREA_JOURNAL_PATHS+=("$HOME/$relative")
    record_managed_parents "$relative"
  done
  preflight_existing_state
  preflight_agents_skill_boundaries
  preflight_desired_targets
  preflight_agents_bridges
  run_stow_preflight
}

build_agents_state_json() {
  local targets='[]' index source
  source="$(agents_package_source)"
  for index in "${!AGENTS_BRIDGE_PATHS[@]}"; do
    targets="$(jq -c --arg path "${AGENTS_BRIDGE_PATHS[index]}" \
      --arg lexical "${AGENTS_BRIDGE_LEXICAL[index]}" --arg resolved "$source" \
      '. + [{path:$path,source:$lexical,resolved_source:$resolved}]' <<< "$targets")"
  done
  build_area_state_json agents '[]' '[]' "$targets"
}

apply_agents_bridges() {
  local index source
  source="$(agents_package_source)"
  for index in "${!AGENTS_BRIDGE_PATHS[@]}"; do
    install_relative_bridge_no_clobber "$HOME/${AGENTS_BRIDGE_PATHS[index]}" \
      "${AGENTS_BRIDGE_LEXICAL[index]}" "$HOME/.agents/AGENTS.md" "$source" 'agents bridge'
  done
}

apply_agents() {
  local state_json
  begin_transaction
  apply_area_stow
  fault after-stow
  apply_agents_bridges
  fault after-agents-bridges
  preflight_agents_skill_boundaries true
  "$DOTFILES_DIR/scripts/agent-skills" verify >/dev/null || die 'pinned agent skills changed during apply'
  state_json="$(build_agents_state_json)"
  write_transaction_string_atomic "$state_json" "$AREA_STATE" 0600
  TRANSACTION_ACTIVE=false
  fault after-state-commit
  log "applied agents area for profile '$SELECTED_PROFILE'"
}

remove_agents() {
  init_agents_area
  begin_area_removal agents || return 0
  begin_transaction
  remove_recorded_area_targets remove-after-links
  remove_area_state_and_dirs 'agents area state'
  log 'removed managed agents links and state'
}
