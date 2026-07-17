# Generic framework area: preflight, apply, and removal for areas without
# attachments or migration payloads; sourced by bootstrap.sh exactly once.

init_generic_area() {
  AREA="$1"
  AREA_JOURNAL_PATHS=()
  AREA_ATTACHMENT_VALIDATOR=validate_no_attachments_from_state
}

validate_no_attachments_from_state() {
  local state="$1"
  [[ "$(jq '.attachments | length' "$state")" == 0 ]] || \
    die "area '$AREA' state records unknown attachments"
}

preflight_generic() {
  init_generic_area "$1"
  load_profile_closure "$AREA"
  scan_packages
  record_managed_parents ".local/state/dotfiles/v1/$AREA.json"
  preflight_existing_state
  preflight_desired_targets
  run_stow_preflight
}

build_generic_state_json() {
  local packages='[]' targets='[]' dirs='[]' i
  for i in "${!PACKAGES[@]}"; do packages="$(jq -c --arg value "${PACKAGES[i]}" '. + [$value]' <<< "$packages")"; done
  for i in "${!TARGET_PATHS[@]}"; do
    targets="$(jq -c --arg path "${TARGET_PATHS[i]}" --arg source "${TARGET_LEXICAL[i]}" \
      --arg resolved "${TARGET_SOURCES[i]}" '. + [{path:$path,source:$source,resolved_source:$resolved}]' <<< "$targets")"
  done
  for i in "${!MANAGED_DIRS[@]}"; do dirs="$(jq -c --arg value "${MANAGED_DIRS[i]}" '. + [$value]' <<< "$dirs")"; done
  jq -cn --arg profile "$SELECTED_PROFILE" --arg area "$AREA" --arg checkout "$CHECKOUT_ROOT" --arg target "$TARGET_ROOT" \
    --argjson packages "$packages" --argjson targets "$targets" --argjson dirs "$dirs" \
    '{schema_version:1,profile:$profile,area:$area,checkout_root:$checkout,target_root:$target,packages:$packages,targets:$targets,managed_directories:$dirs,attachments:[],backups:[]}'
}

apply_generic() {
  local state_json
  begin_transaction
  remove_recorded_links_for_apply
  apply_stow_packages
  validate_applied_targets
  fault after-stow
  fault before-state
  state_json="$(build_generic_state_json)"
  write_string_atomic "$state_json" "$AREA_STATE" 0600
  TRANSACTION_ACTIVE=false
  fault after-state-commit
  log "applied $AREA area for profile '$SELECTED_PROFILE'"
}

remove_generic() {
  local state count index relative dir
  local managed_directories=()
  init_generic_area "$1"
  state="$HOME/.local/state/dotfiles/v1/$AREA.json"
  if [[ ! -e "$state" && ! -L "$state" ]]; then
    log "area '$AREA' is not deployed; no changes made"
    return
  fi
  validate_state_file "$state"
  [[ "$(jq -r .target_root "$state")" == "$TARGET_ROOT" ]] || \
    die "existing $AREA state belongs to a different target root"
  count="$(jq '.targets | length' "$state")"
  for ((index=0; index<count; index++)); do validate_recorded_target "$state" "$index"; done
  validate_no_attachments_from_state "$state"
  while IFS= read -r dir; do
    validate_home_directory "$HOME/$dir"
    managed_directories+=("$dir")
  done < <(jq -r '.managed_directories[]' "$state")

  AREA_STATE="$state"
  OLD_STATE=true
  TARGET_PATHS=()
  while IFS= read -r relative; do TARGET_PATHS+=("$relative"); done < <(jq -r '.targets[].path' "$state")
  begin_transaction
  for ((index=0; index<count; index++)); do
    relative="$(jq -r ".targets[$index].path" "$state")"
    rm -- "$HOME/$relative"
  done
  fault remove-after-links
  rm -- "$state"
  prune_managed_directories "${managed_directories[@]}"
  TRANSACTION_ACTIVE=false
  log "removed managed $AREA links and state"
}
