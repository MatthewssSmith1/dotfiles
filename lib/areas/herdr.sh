# Herdr area: private source plus reversible regular live configuration.

readonly HERDR_CONFIG_PATH='.config/herdr/config.toml'
readonly HERDR_SOURCE_PATH='.config/dotfiles/herdr/config.toml'
readonly HERDR_PREDECESSOR_CONTENT='[ui]
agent_panel_sort = "spaces"'
readonly HERDR_PREDECESSOR_MODE='664'

HERDR_CONFIG_ACTION=none
HERDR_CONFIG_ORIGIN=''
HERDR_CONFIG_IDENTITY=''
HERDR_CONFIG_HASH=''
HERDR_BACKUP=''
HERDR_BACKUP_IDENTITY=''

init_herdr_area() {
  AREA=herdr
  AREA_JOURNAL_PATHS=("$HOME/$HERDR_CONFIG_PATH")
  AREA_ATTACHMENT_VALIDATOR=validate_herdr_state
  HERDR_CONFIG_ACTION=none
  HERDR_CONFIG_ORIGIN=''
  HERDR_CONFIG_IDENTITY=''
  HERDR_CONFIG_HASH=''
  HERDR_BACKUP=''
  HERDR_BACKUP_IDENTITY=''
}

herdr_source() {
  printf '%s/packages/common/herdr/%s' "$DOTFILES_DIR" "$HERDR_SOURCE_PATH"
}

herdr_desired_hash() {
  sha256_file "$(herdr_source)"
}

herdr_predecessor_hash() {
  sha256_string "$HERDR_PREDECESSOR_CONTENT"$'\n'
}

validate_herdr_payload() {
  [[ "${PACKAGES[*]}" == 'common/herdr' ]] || die 'Herdr package closure must be exactly common/herdr'
  [[ "${#TARGET_PATHS[@]}" == 1 && "${TARGET_PATHS[0]}" == "$HERDR_SOURCE_PATH" ]] || \
    die 'Herdr package contains an unexpected target'
  [[ -f "$(herdr_source)" && ! -L "$(herdr_source)" && "$(stat -c %a -- "$(herdr_source)")" == 644 ]] || \
    die 'Herdr canonical config is missing or unsafe'
  file_contains_nul "$(herdr_source)" && die 'Herdr canonical config contains NUL bytes'
  return 0
}

validate_herdr_config_file() {
  local path="$1" expected_hash="$2" description="$3"
  validate_home_parent_chain "$path"
  [[ -f "$path" && ! -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" ]] || \
    die "$description is missing or unsafe: $path"
  [[ "$(sha256_file "$path")" == "$expected_hash" ]] || die "$description content has drifted: $path"
}

validate_herdr_backup() {
  local path="$1"
  validate_herdr_config_file "$path" "$(herdr_predecessor_hash)" 'Herdr predecessor backup'
  [[ "$(stat -c %a -- "$path")" == 600 ]] || die "Herdr predecessor backup has an unsafe mode: $path"
}

validate_herdr_state() {
  local state="$1" id path hash origin backup count
  [[ "$(jq '.attachments | length' "$state")" == 1 ]] || die 'Herdr state does not record exactly one config attachment'
  IFS=$'\t' read -r id path hash < <(jq -r '.attachments[0] | [.id,.path,.content_hash] | @tsv' "$state")
  [[ "$path" == "$HERDR_CONFIG_PATH" && "$id" =~ ^herdr-config-v1\.(created|predecessor-664)$ ]] || \
    die 'Herdr state records an unknown attachment'
  origin="${id#herdr-config-v1.}"
  validate_herdr_config_file "$HOME/$path" "$hash" 'managed Herdr config'
  count="$(jq '.backups | length' "$state")"
  if [[ "$origin" == predecessor-664 ]]; then
    [[ "$count" == 1 ]] || die 'Herdr predecessor state does not record exactly one backup'
    backup="$(jq -r '.backups[0]' "$state")"
    [[ "$backup" == ".local/state/dotfiles/v1/backups/herdr/config-$(herdr_predecessor_hash).bak" ]] || \
      die 'Herdr state records an unknown predecessor backup'
    validate_herdr_backup "$HOME/$backup"
    HERDR_BACKUP="$backup"
    capture_path_identity "$HOME/$backup" || die 'Herdr predecessor backup changed during preflight'
    HERDR_BACKUP_IDENTITY="$PATH_IDENTITY"
  else
    [[ "$count" == 0 ]] || die 'created Herdr state records an unexpected backup'
  fi
  HERDR_CONFIG_ORIGIN="$origin"
  HERDR_CONFIG_HASH="$hash"
  capture_path_identity "$HOME/$path" || die 'managed Herdr config changed during preflight'
  HERDR_CONFIG_IDENTITY="$PATH_IDENTITY"
}

preflight_new_herdr_config() {
  local path="$HOME/$HERDR_CONFIG_PATH"
  validate_home_parent_chain "$path"
  capture_path_identity "$path" || die 'Herdr config changed during preflight'
  HERDR_CONFIG_IDENTITY="$PATH_IDENTITY"
  if [[ "$PATH_IDENTITY" == absent ]]; then
    HERDR_CONFIG_ACTION=install
    HERDR_CONFIG_ORIGIN=created
    return
  fi
  validate_herdr_config_file "$path" "$(herdr_predecessor_hash)" 'reviewed Herdr predecessor config'
  [[ "$(stat -c %a -- "$path")" == "$HERDR_PREDECESSOR_MODE" ]] || \
    die "reviewed Herdr predecessor config has unexpected mode: $path"
  HERDR_CONFIG_ACTION=migrate
  HERDR_CONFIG_ORIGIN=predecessor-664
  HERDR_BACKUP=".local/state/dotfiles/v1/backups/herdr/config-$(herdr_predecessor_hash).bak"
  validate_home_parent_chain "$HOME/$HERDR_BACKUP"
  [[ ! -e "$HOME/$HERDR_BACKUP" && ! -L "$HOME/$HERDR_BACKUP" ]] || \
    die "Herdr predecessor backup destination already exists: $HOME/$HERDR_BACKUP"
  AREA_JOURNAL_PATHS+=("$HOME/$HERDR_BACKUP")
  record_managed_parents "$HERDR_BACKUP"
}

validate_herdr_syntax() {
  local binary temp status
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_HERDR_BIN:-}" ]]; then
    binary="$DOTFILES_TEST_HERDR_BIN"
  else
    binary="$(type -P herdr 2>/dev/null || true)"
  fi
  [[ -n "$binary" && -f "$binary" && ! -L "$binary" && -x "$binary" ]] || \
    die 'no directly executable Herdr runtime is available; run with --provision'
  temp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-herdr-config.XXXXXX")"
  mkdir -p "$temp/.config/herdr"
  cp -- "$(herdr_source)" "$temp/.config/herdr/config.toml"
  set +e
  unshare --user --map-root-user --net env -i HOME="$temp" PATH=/usr/bin:/bin \
    XDG_CONFIG_HOME="$temp/.config" XDG_DATA_HOME="$temp/.local/share" \
    XDG_STATE_HOME="$temp/.local/state" XDG_CACHE_HOME="$temp/.cache" MISE_OFFLINE=1 \
    "$binary" config check >/dev/null 2>&1
  status=$?
  set -e
  rm -rf -- "$temp"
  ((status == 0)) || die 'managed Herdr config failed herdr config check'
}

preflight_herdr() {
  init_herdr_area
  load_profile_closure herdr
  scan_packages
  validate_herdr_payload
  record_managed_parents '.local/state/dotfiles/v1/herdr.json'
  preflight_existing_state
  if [[ "$OLD_STATE" == false ]]; then
    preflight_new_herdr_config
  else
    [[ -z "$HERDR_BACKUP" ]] || AREA_JOURNAL_PATHS+=("$HOME/$HERDR_BACKUP")
    [[ "$HERDR_CONFIG_HASH" == "$(herdr_desired_hash)" ]] || HERDR_CONFIG_ACTION=install
  fi
  preflight_desired_targets
  run_stow_preflight
  validate_herdr_syntax
}

herdr_copy_no_clobber() {
  local source="$1" destination="$2" mode="$3" dir temporary
  dir="${destination%/*}"
  ensure_directory "$dir"
  temporary="$(mktemp "$dir/.${destination##*/}.herdr.XXXXXX")"
  track_temp_path "$temporary"
  cp -- "$source" "$temporary"
  chmod "$mode" "$temporary"
  install_regular_no_clobber "$temporary" "$destination" 'Herdr predecessor backup'
}

install_herdr_config() {
  local path="$HOME/$HERDR_CONFIG_PATH" desired source="$(herdr_source)"
  desired="$(< "$source")"
  if [[ "$HERDR_CONFIG_ACTION" == migrate ]]; then
    herdr_copy_no_clobber "$path" "$HOME/$HERDR_BACKUP" 0600
    validate_herdr_backup "$HOME/$HERDR_BACKUP"
    fault herdr-after-backup
  fi
  if [[ "$HERDR_CONFIG_ACTION" != none ]]; then
    write_transaction_string_atomic "$desired" "$path" 0600
    fault herdr-after-config
  fi
  HERDR_CONFIG_HASH="$(herdr_desired_hash)"
  validate_herdr_config_file "$path" "$HERDR_CONFIG_HASH" 'managed Herdr config'
}

build_herdr_state_json() {
  local packages='[]' targets='[]' dirs='[]' backups='[]' attachment index
  for index in "${!PACKAGES[@]}"; do packages="$(jq -c --arg v "${PACKAGES[index]}" '. + [$v]' <<< "$packages")"; done
  for index in "${!TARGET_PATHS[@]}"; do
    targets="$(jq -c --arg path "${TARGET_PATHS[index]}" --arg source "${TARGET_LEXICAL[index]}" \
      --arg resolved "${TARGET_SOURCES[index]}" '. + [{path:$path,source:$source,resolved_source:$resolved}]' <<< "$targets")"
  done
  for index in "${!MANAGED_DIRS[@]}"; do dirs="$(jq -c --arg v "${MANAGED_DIRS[index]}" '. + [$v]' <<< "$dirs")"; done
  [[ -z "$HERDR_BACKUP" ]] || backups="$(jq -cn --arg v "$HERDR_BACKUP" '[$v]')"
  attachment="$(jq -cn --arg id "herdr-config-v1.$HERDR_CONFIG_ORIGIN" --arg path "$HERDR_CONFIG_PATH" \
    --arg hash "$HERDR_CONFIG_HASH" '[{id:$id,path:$path,content_hash:$hash}]')"
  jq -cn --arg profile "$SELECTED_PROFILE" --arg checkout "$CHECKOUT_ROOT" --arg target "$TARGET_ROOT" \
    --argjson packages "$packages" --argjson targets "$targets" --argjson dirs "$dirs" \
    --argjson attachments "$attachment" --argjson backups "$backups" \
    '{schema_version:1,profile:$profile,area:"herdr",checkout_root:$checkout,target_root:$target,packages:$packages,
      targets:$targets,managed_directories:$dirs,attachments:$attachments,backups:$backups}'
}

apply_herdr() {
  local state_json
  begin_transaction
  remove_recorded_links_for_apply
  apply_stow_packages
  validate_applied_targets
  install_herdr_config
  state_json="$(build_herdr_state_json)"
  write_transaction_string_atomic "$state_json" "$AREA_STATE" 0600
  fault herdr-after-state
  TRANSACTION_ACTIVE=false
  log "applied Herdr area for profile '$SELECTED_PROFILE'"
}

restore_herdr_predecessor() {
  local path="$HOME/$HERDR_CONFIG_PATH" temporary dir="${HOME}/${HERDR_CONFIG_PATH%/*}"
  temporary="$(mktemp "$dir/.config.toml.herdr-restore.XXXXXX")"
  track_temp_path "$temporary"
  cp -- "$HOME/$HERDR_BACKUP" "$temporary"
  chmod "$HERDR_PREDECESSOR_MODE" "$temporary"
  replace_with_staged_regular "$temporary" "$path" "$HERDR_CONFIG_IDENTITY" 'managed Herdr config'
  remove_expected_path "$HOME/$HERDR_BACKUP" "$HERDR_BACKUP_IDENTITY" 'Herdr predecessor backup'
}

remove_herdr() {
  local state="$HOME/.local/state/dotfiles/v1/herdr.json" count index dir
  local managed_directories=()
  init_herdr_area
  if [[ ! -e "$state" && ! -L "$state" ]]; then log "area 'herdr' is not deployed; no changes made"; return 0; fi
  validate_state_file "$state"
  [[ "$(jq -r .target_root "$state")" == "$TARGET_ROOT" ]] || die 'existing Herdr state belongs to a different target root'
  SELECTED_PROFILE="$(jq -r .profile "$state")"
  count="$(jq '.targets | length' "$state")"
  for ((index=0; index<count; index++)); do validate_recorded_target "$state" "$index"; done
  validate_herdr_state "$state"
  while IFS= read -r dir; do validate_home_directory "$HOME/$dir"; managed_directories+=("$dir"); done < <(jq -r '.managed_directories[]' "$state")
  AREA_STATE="$state"; OLD_STATE=true; TARGET_PATHS=()
  while IFS= read -r dir; do TARGET_PATHS+=("$dir"); done < <(jq -r '.targets[].path' "$state")
  [[ -z "$HERDR_BACKUP" ]] || AREA_JOURNAL_PATHS+=("$HOME/$HERDR_BACKUP")
  begin_transaction
  if [[ "$HERDR_CONFIG_ORIGIN" == created ]]; then
    remove_expected_path "$HOME/$HERDR_CONFIG_PATH" "$HERDR_CONFIG_IDENTITY" 'managed Herdr config'
  else
    restore_herdr_predecessor
  fi
  fault herdr-remove-after-config
  for ((index=0; index<count; index++)); do remove_recorded_target "$state" "$index"; done
  remove_current_regular_path "$state" 'Herdr area state'
  prune_managed_directories "${managed_directories[@]}"
  TRANSACTION_ACTIVE=false
  log 'removed managed Herdr config and state; restored the reviewed predecessor when present and retained runtime data'
}
