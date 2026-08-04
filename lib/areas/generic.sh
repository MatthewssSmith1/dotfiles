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

apply_generic() {
  local state_json
  begin_transaction
  apply_area_stow
  fault after-stow
  fault before-state
  state_json="$(build_area_state_json "$AREA")"
  write_transaction_string_atomic "$state_json" "$AREA_STATE" 0600
  TRANSACTION_ACTIVE=false
  fault after-state-commit
  log "applied $AREA area for profile '$SELECTED_PROFILE'"
}

remove_generic() {
  init_generic_area "$1"
  begin_area_removal "$AREA" || return 0
  begin_transaction
  remove_recorded_area_targets remove-after-links
  remove_area_state_and_dirs "area '$AREA' state"
  log "removed managed $AREA links and state"
}
