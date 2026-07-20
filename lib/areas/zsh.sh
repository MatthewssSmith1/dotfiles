# Transitional zsh area: frozen payload plus local-alias and Vite+ migrations.

readonly ZSH_LOCAL_MIGRATION_ID='zsh-local-alias-v1'
readonly ZSH_VITE_MIGRATION_ID='zsh-vite-retirement-v1'
readonly ZSH_LOCAL_PATH='.config/dotfiles/local/zsh_aliases.zsh'
readonly ZSH_LEGACY_LOCAL_PATH='.zsh_aliases.local'
readonly ZSH_VITE_BLOCK='# Vite+ bin (https://viteplus.dev)
. "$HOME/.vite-plus/env"
'

init_zsh_area() {
  AREA=zsh
  AREA_JOURNAL_PATHS=()
  AREA_ATTACHMENT_VALIDATOR=validate_zsh_state
  ZSH_LOCAL_ACTION=none
  ZSH_LOCAL_SOURCE=""
  ZSH_LOCAL_LINK_IDENTITY=""
  ZSH_LOCAL_FINGERPRINT=""
  ZSH_LOCAL_BACKUP=""
  ZSH_VITE_ACTION=none
  ZSH_VITE_FINGERPRINT=""
  ZSH_VITE_EXPECTED_IDENTITY=""
  ZSH_VITE_BACKUP=""
  register_migration_ledger_journal
}

zsh_expected_targets() {
  ZSH_EXPECTED_TARGETS=(.p10k.zsh .zsh_aliases .zshrc)
}

validate_zsh_target_inventory() {
  local relative expected actual
  local -A expected_map=() actual_map=()

  zsh_expected_targets
  for relative in "${ZSH_EXPECTED_TARGETS[@]}"; do expected_map["$relative"]=1; done
  for relative in "${TARGET_PATHS[@]}"; do actual_map["$relative"]=1; done
  for expected in "${ZSH_EXPECTED_TARGETS[@]}"; do
    [[ -n "${actual_map[$expected]+x}" ]] || die "zsh package closure is missing expected target: $expected"
  done
  for actual in "${TARGET_PATHS[@]}"; do
    [[ -n "${expected_map[$actual]+x}" ]] || die "zsh package closure contains unexpected target: $actual"
  done
  ((${#TARGET_PATHS[@]} == ${#ZSH_EXPECTED_TARGETS[@]})) || die 'zsh package target inventory is not unique'
}

read_file_bytes() {
  local path="$1" sentinel=$'\034'
  FILE_BYTES="$(command cat -- "$path"; printf '%s' "$sentinel")"
  FILE_BYTES="${FILE_BYTES%"$sentinel"}"
}

count_literal_occurrences() {
  local value="$1" needle="$2"
  LITERAL_COUNT=0
  while [[ "$value" == *"$needle"* ]]; do
    value="${value#*"$needle"}"
    ((LITERAL_COUNT += 1))
  done
}

validate_packaged_zshrc() {
  local path="$1" expected='source "$HOME/.config/dotfiles/local/zsh_aliases.zsh"'
  read_file_bytes "$path"
  count_literal_occurrences "$FILE_BYTES" "$expected"
  [[ "$LITERAL_COUNT" == 1 ]] || die 'managed .zshrc does not contain exactly one central local-alias source'
  [[ "$FILE_BYTES" == *'-f "$HOME/.config/dotfiles/local/zsh_aliases.zsh"'* &&
    "$FILE_BYTES" == *'! -L "$HOME/.config/dotfiles/local/zsh_aliases.zsh"'* &&
    "$FILE_BYTES" == *'-O "$HOME/.config/dotfiles/local/zsh_aliases.zsh"'* ]] ||
    die 'managed .zshrc does not enforce central local-alias file safety'
  [[ "$FILE_BYTES" != *'.zsh_aliases.local'* ]] || die 'managed .zshrc still references .zsh_aliases.local'
  [[ "$FILE_BYTES" != *'.vite-plus/env'* && "$FILE_BYTES" != *'# Vite+'* ]] || \
    die 'managed .zshrc still initializes Vite+'
}

validate_zsh_payload() {
  local index relative source mode
  for index in "${!TARGET_PATHS[@]}"; do
    relative="${TARGET_PATHS[index]}"
    source="${TARGET_SOURCES[index]}"
    mode="$(stat -c %a -- "$source")"
    [[ "$mode" == 644 ]] || die "unexpected zsh payload mode $mode for $relative; expected 644"
    zsh -n "$source" || die "managed zsh payload has invalid syntax: $relative"
  done
  cmp -s -- "$DOTFILES_DIR/.zsh_aliases" "$DOTFILES_DIR/packages/common/zsh/.zsh_aliases" || \
    die 'packaged .zsh_aliases differs from its compatibility source'
  cmp -s -- "$DOTFILES_DIR/.p10k.zsh" "$DOTFILES_DIR/packages/common/zsh/.p10k.zsh" || \
    die 'packaged .p10k.zsh differs from its compatibility source'
  validate_packaged_zshrc "$DOTFILES_DIR/packages/common/zsh/.zshrc"
}

validate_real_local_file() {
  local path="$1" description="$2"
  validate_home_parent_chain "$path"
  [[ ! -e "$path" && ! -L "$path" ]] && return 1
  [[ -f "$path" && ! -L "$path" ]] || die "$description is symlinked or not a regular file: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "$description has an unsafe owner: $path"
  [[ -r "$path" ]] || die "$description is not readable: $path"
}

validate_zsh_migration_source() {
  local path="$1" fingerprint="$2" description="$3"
  [[ -f "$path" && ! -L "$path" ]] || die "$description is symlinked or not a regular file: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "$description has an unsafe owner: $path"
  [[ -r "$path" ]] || die "$description is not readable: $path"
  file_contains_nul "$path" && die "$description contains NUL bytes and cannot be copied safely: $path"
  [[ "$(sha256_file "$path")" == "$fingerprint" ]] || die "$description changed during migration: $path"
}

validate_new_zsh_backup() {
  local path="$1" fingerprint="$2"
  validate_home_parent_chain "$path"
  [[ -f "$path" && ! -L "$path" ]] || die "new retained zsh migration backup is missing or unsafe: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "new retained zsh migration backup has an unsafe owner: $path"
  [[ "$(stat -c %a -- "$path")" == 600 ]] || die "new retained zsh migration backup has an unsafe mode: $path"
  [[ "$(sha256_file "$path")" == "$fingerprint" ]] || die "new retained zsh migration backup hash does not match its source: $path"
}

allocate_zsh_backup() {
  local label="$1" fingerprint="$2" candidate counter=0 ledger
  local parent='.local/state/dotfiles/v1/backups/zsh'
  ledger="$(migration_ledger_path)"
  candidate="$parent/$label-${fingerprint:0:16}.bak"
  while [[ -e "$HOME/$candidate" || -L "$HOME/$candidate" ]] ||
    { [[ -f "$ledger" ]] && jq -e --arg value "$candidate" 'any(.migrations[].backups[]; . == $value)' "$ledger" >/dev/null; }; do
    ((counter += 1))
    candidate="$parent/$label-${fingerprint:0:16}.$counter.bak"
  done
  validate_home_parent_chain "$HOME/$candidate"
  ZSH_ALLOCATED_BACKUP="$candidate"
}

zsh_ledger_backups_json() {
  local path
  path="$(migration_ledger_path)"
  if [[ ! -f "$path" ]]; then
    printf '[]'
    return 0
  fi
  jq -c --arg local "$ZSH_LOCAL_MIGRATION_ID" --arg vite "$ZSH_VITE_MIGRATION_ID" \
    '[.migrations[] | select(.id == $local or .id == $vite) | .backups[]]' "$path"
}

validate_zsh_retained_backups() {
  local id fingerprint relative path
  while IFS=$'\t' read -r id fingerprint relative; do
    path="$HOME/$relative"
    validate_home_parent_chain "$path"
    [[ -f "$path" && ! -L "$path" ]] || die "retained zsh migration backup is missing or unsafe: $path"
    [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "retained zsh migration backup has an unsafe owner: $path"
    [[ "$(stat -c %a -- "$path")" == 600 ]] || die "retained zsh migration backup has an unsafe mode: $path"
    [[ "$(sha256_file "$path")" == "$fingerprint" ]] || die "retained zsh migration backup hash has drifted: $path"
  done < <(jq -r --arg local "$ZSH_LOCAL_MIGRATION_ID" --arg vite "$ZSH_VITE_MIGRATION_ID" '
    .migrations[] | select(.id == $local or .id == $vite) |
    select((.backups | length) == 1) | [.id,.source_fingerprint,.backups[0]] | @tsv
  ' "$(migration_ledger_path)" 2>/dev/null || true)
  if [[ -f "$(migration_ledger_path)" ]]; then
    jq -e --arg local "$ZSH_LOCAL_MIGRATION_ID" --arg vite "$ZSH_VITE_MIGRATION_ID" '
      all(.migrations[] | select(.id == $local or .id == $vite); (.backups | length) == 1)
    ' "$(migration_ledger_path)" >/dev/null || die 'zsh migration ledger does not record exactly one backup per completed migration'
  fi
}

validate_zsh_state() {
  local state="$1" expected
  [[ "$(jq '.attachments | length' "$state")" == 0 ]] || die 'zsh state records unknown attachments'
  expected="$(zsh_ledger_backups_json)"
  jq -e --argjson expected "$expected" '(.backups | sort) == ($expected | sort)' "$state" >/dev/null || \
    die 'zsh state does not match its retained migration backups'
  validate_zsh_retained_backups
}

preflight_zsh_local_aliases() {
  local source="$HOME/$ZSH_LEGACY_LOCAL_PATH" destination="$HOME/$ZSH_LOCAL_PATH" source_present=false

  validate_home_parent_chain "$source"
  if [[ -L "$source" ]]; then
    reviewed_legacy_link "$source" "$ZSH_LEGACY_LOCAL_PATH" "$ZSH_LEGACY_LOCAL_PATH" \
      zsh migrate-local-stage-6 || die "$source is not the exact reviewed legacy local-alias link"
    ZSH_LOCAL_SOURCE="$OWNED_LEGACY_SOURCE"
    capture_path_identity "$source" || die "reviewed zsh local-alias link changed during preflight: $source"
    ZSH_LOCAL_LINK_IDENTITY="$PATH_IDENTITY"
    source_present=true
  elif [[ -e "$source" ]]; then
    die "$source is unrelated host data; expected the reviewed legacy link"
  fi

  preflight_migration "$ZSH_LOCAL_MIGRATION_ID" "$source_present" 'zsh local-alias migration'
  if [[ "$MIGRATION_STATUS" == completed ]]; then
    validate_real_local_file "$destination" 'retained zsh local-alias file' || \
      die "completed zsh local-alias migration is missing its retained destination: $destination"
    return 0
  fi

  if [[ "$source_present" == false ]]; then
    validate_real_local_file "$destination" 'zsh local-alias destination' || true
    return 0
  fi

  ZSH_LOCAL_FINGERPRINT="$(sha256_file "$ZSH_LOCAL_SOURCE")"
  validate_zsh_migration_source "$ZSH_LOCAL_SOURCE" "$ZSH_LOCAL_FINGERPRINT" 'reviewed zsh local-alias source'
  if validate_real_local_file "$destination" 'zsh local-alias destination'; then
    cmp -s -- "$ZSH_LOCAL_SOURCE" "$destination" || \
      die "$destination diverges from the reviewed zsh local-alias source; refusing to merge"
    ZSH_LOCAL_ACTION=reuse
  else
    ZSH_LOCAL_ACTION=create
  fi
  allocate_zsh_backup "$ZSH_LOCAL_MIGRATION_ID" "$ZSH_LOCAL_FINGERPRINT"
  ZSH_LOCAL_BACKUP="$ZSH_ALLOCATED_BACKUP"
}

preflight_zsh_vite_retirement() {
  local path="$HOME/.zshenv" source_present=false residue prefix suffix

  validate_home_parent_chain "$path"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    preflight_migration "$ZSH_VITE_MIGRATION_ID" false 'zsh Vite+ hook retirement'
    return 0
  fi
  [[ -f "$path" && ! -L "$path" ]] || die "host .zshenv is symlinked or not a regular file: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "host .zshenv has an unsafe owner: $path"
  file_contains_nul "$path" && die "host .zshenv contains NUL bytes and cannot be edited safely: $path"
  read_file_bytes "$path"
  count_literal_occurrences "$FILE_BYTES" "$ZSH_VITE_BLOCK"
  if ((LITERAL_COUNT > 1)); then
    die "$path contains an ambiguous duplicate reviewed Vite+ block"
  elif ((LITERAL_COUNT == 1)); then
    prefix="${FILE_BYTES%%"$ZSH_VITE_BLOCK"*}"
    suffix="${FILE_BYTES#*"$ZSH_VITE_BLOCK"}"
    residue="$prefix$suffix"
    [[ "$residue" != *'Vite+ bin (https://viteplus.dev)'* && "$residue" != *'.vite-plus/env'* ]] || \
      die "$path contains an ambiguous additional Vite+ hook"
    source_present=true
  elif [[ "$FILE_BYTES" == *'Vite+ bin (https://viteplus.dev)'* || "$FILE_BYTES" == *'.vite-plus/env'* ]]; then
    die "$path contains a partial or modified reviewed Vite+ block"
  fi

  preflight_migration "$ZSH_VITE_MIGRATION_ID" "$source_present" 'zsh Vite+ hook retirement'
  [[ "$source_present" == true ]] || return 0
  ZSH_VITE_ACTION=retire
  ZSH_VITE_FINGERPRINT="$(sha256_file "$path")"
  capture_path_identity "$path" || die "host .zshenv changed during migration preflight: $path"
  ZSH_VITE_EXPECTED_IDENTITY="$PATH_IDENTITY"
  allocate_zsh_backup "$ZSH_VITE_MIGRATION_ID" "$ZSH_VITE_FINGERPRINT"
  ZSH_VITE_BACKUP="$ZSH_ALLOCATED_BACKUP"
}

preflight_zsh_legacy_packages() {
  local relative path index candidate
  [[ "$OLD_STATE" == false ]] || return 0
  for relative in .p10k.zsh .zsh_aliases .zshrc; do
    path="$HOME/$relative"
    [[ -L "$path" ]] || continue
    index=""
    for candidate in "${!TARGET_PATHS[@]}"; do
      if [[ "${TARGET_PATHS[candidate]}" == "$relative" ]]; then
        index="$candidate"
        break
      fi
    done
    if [[ -n "$index" && "$(readlink -- "$path")" == "${TARGET_LEXICAL[index]}" && \
      "$(resolve_link "$path")" == "${TARGET_SOURCES[index]}" ]]; then
      continue
    fi
    approve_legacy_replacement "$relative" "$relative" zsh replace-stage-6
  done
}

configure_zsh_journal() {
  local path
  for path in "$HOME/$ZSH_LOCAL_PATH" "$HOME/$ZSH_LEGACY_LOCAL_PATH" "$HOME/.zshenv"; do
    array_contains "$path" "${AREA_JOURNAL_PATHS[@]:-}" || AREA_JOURNAL_PATHS+=("$path")
  done
  [[ -z "$ZSH_LOCAL_BACKUP" ]] || AREA_JOURNAL_PATHS+=("$HOME/$ZSH_LOCAL_BACKUP")
  [[ -z "$ZSH_VITE_BACKUP" ]] || AREA_JOURNAL_PATHS+=("$HOME/$ZSH_VITE_BACKUP")
}

preflight_zsh() {
  init_zsh_area
  load_profile_closure zsh
  scan_packages
  validate_zsh_target_inventory
  validate_zsh_payload
  record_managed_parents '.local/state/dotfiles/v1/zsh.json'
  validate_migrations_ledger
  preflight_zsh_local_aliases
  preflight_zsh_vite_retirement
  validate_zsh_retained_backups
  preflight_existing_state
  preflight_zsh_legacy_packages
  configure_zsh_journal
  preflight_desired_targets
  run_stow_preflight
}

write_file_copy_no_clobber() {
  local source="$1" destination="$2" mode="$3" hold_point="${4:-before-retained-file-return}" dir base temporary
  dir="$(dirname -- "$destination")"
  base="${destination##*/}"
  ensure_directory "$dir"
  [[ "$(stat -c %u -- "$dir")" == "$EUID" ]] || die "retained-file parent has an unsafe owner: $dir"
  [[ ! -e "$destination" && ! -L "$destination" ]] || die "refusing to overwrite retained file: $destination"
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  track_temp_path "$temporary"
  cp -- "$source" "$temporary"
  chmod "$mode" "$temporary"
  test_hold before-atomic-rename
  install_regular_no_clobber "$temporary" "$destination" 'retained file'
  test_hold "$hold_point"
}

apply_zsh_local_aliases() {
  local destination="$HOME/$ZSH_LOCAL_PATH"
  [[ "$ZSH_LOCAL_ACTION" != none ]] || return 0
  validate_zsh_migration_source "$ZSH_LOCAL_SOURCE" "$ZSH_LOCAL_FINGERPRINT" 'reviewed zsh local-alias source'
  if [[ "$ZSH_LOCAL_ACTION" == create ]]; then
    write_file_copy_no_clobber "$ZSH_LOCAL_SOURCE" "$destination" 0600 after-zsh-local-destination-install
  fi
  fault zsh-after-local-destination
  validate_zsh_migration_source "$ZSH_LOCAL_SOURCE" "$ZSH_LOCAL_FINGERPRINT" 'reviewed zsh local-alias source'
  write_file_copy_no_clobber "$ZSH_LOCAL_SOURCE" "$HOME/$ZSH_LOCAL_BACKUP" 0600 after-zsh-local-backup-install
  validate_new_zsh_backup "$HOME/$ZSH_LOCAL_BACKUP" "$ZSH_LOCAL_FINGERPRINT"
  fault zsh-after-local-backup
}

validate_active_zshrc() {
  local path="$HOME/.zshrc"
  [[ -L "$path" && "$(resolve_link "$path")" == "$(realpath -e -- "$DOTFILES_DIR/packages/common/zsh/.zshrc")" ]] || \
    die 'active .zshrc is not the managed package link'
  validate_packaged_zshrc "$path"
}

remove_zsh_legacy_local() {
  local path="$HOME/$ZSH_LEGACY_LOCAL_PATH" quarantine
  [[ "$ZSH_LOCAL_ACTION" != none ]] || return 0
  test_hold before-zsh-local-quarantine
  quarantine_expected_path "$path" "$ZSH_LOCAL_LINK_IDENTITY" 'reviewed zsh local-alias link' || \
    die 'reviewed zsh local-alias link changed before removal'
  quarantine="$QUARANTINE_PATH"
  reviewed_legacy_link "$quarantine" "$ZSH_LEGACY_LOCAL_PATH" "$ZSH_LEGACY_LOCAL_PATH" \
    zsh migrate-local-stage-6 || {
      if restore_quarantine_no_clobber "$quarantine" "$path"; then
        transaction_record_post_state "$path"
      fi
      die 'quarantined zsh local-alias link does not have reviewed ownership'
    }
  [[ "$OWNED_LEGACY_SOURCE" == "$ZSH_LOCAL_SOURCE" ]] || die 'reviewed zsh local-alias source changed ownership during migration'
  validate_zsh_migration_source "$OWNED_LEGACY_SOURCE" "$ZSH_LOCAL_FINGERPRINT" 'reviewed zsh local-alias source'
  validate_new_zsh_backup "$HOME/$ZSH_LOCAL_BACKUP" "$ZSH_LOCAL_FINGERPRINT"
  discard_quarantine "$quarantine" 'reviewed zsh local-alias link'
}

apply_zsh_vite_retirement() {
  local path="$HOME/.zshenv" mode prefix suffix updated dir base temporary quarantine
  [[ "$ZSH_VITE_ACTION" == retire ]] || return 0
  validate_real_local_file "$path" 'host .zshenv' || die 'host .zshenv disappeared during Vite+ migration'
  [[ "$(sha256_file "$path")" == "$ZSH_VITE_FINGERPRINT" ]] || die 'host .zshenv changed during Vite+ migration'
  mode="$(stat -c %a -- "$path")"
  write_file_copy_no_clobber "$path" "$HOME/$ZSH_VITE_BACKUP" 0600 after-zsh-vite-backup-install
  validate_new_zsh_backup "$HOME/$ZSH_VITE_BACKUP" "$ZSH_VITE_FINGERPRINT"
  fault zsh-after-vite-backup
  validate_zsh_migration_source "$path" "$ZSH_VITE_FINGERPRINT" 'host .zshenv'
  validate_new_zsh_backup "$HOME/$ZSH_VITE_BACKUP" "$ZSH_VITE_FINGERPRINT"
  test_hold before-zshenv-replacement-quarantine
  quarantine_expected_path "$path" "$ZSH_VITE_EXPECTED_IDENTITY" 'host .zshenv' || \
    die 'host .zshenv changed before Vite+ retirement'
  quarantine="$QUARANTINE_PATH"
  validate_zsh_migration_source "$quarantine" "$ZSH_VITE_FINGERPRINT" 'quarantined host .zshenv'
  read_file_bytes "$quarantine"
  prefix="${FILE_BYTES%%"$ZSH_VITE_BLOCK"*}"
  suffix="${FILE_BYTES#*"$ZSH_VITE_BLOCK"}"
  updated="$prefix$suffix"
  dir="$(dirname -- "$path")"
  base="${path##*/}"
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  track_temp_path "$temporary"
  printf '%s' "$updated" > "$temporary"
  chmod "$mode" "$temporary"
  install_regular_no_clobber "$temporary" "$path" 'host .zshenv replacement' "$quarantine"
  discard_quarantine "$quarantine" 'host .zshenv'
  fault zsh-after-vite-retirement
}

update_zsh_migration_ledger() {
  if [[ "$ZSH_LOCAL_ACTION" != none ]]; then
    append_migration_ledger "$ZSH_LOCAL_MIGRATION_ID" "$ZSH_LOCAL_FINGERPRINT" "$ZSH_LOCAL_BACKUP"
    fault zsh-after-local-ledger
  fi
  if [[ "$ZSH_VITE_ACTION" == retire ]]; then
    append_migration_ledger "$ZSH_VITE_MIGRATION_ID" "$ZSH_VITE_FINGERPRINT" "$ZSH_VITE_BACKUP"
    fault zsh-after-vite-ledger
  fi
}

build_zsh_state_json() {
  local packages='[]' targets='[]' dirs='[]' backups index
  for index in "${!PACKAGES[@]}"; do packages="$(jq -c --arg value "${PACKAGES[index]}" '. + [$value]' <<< "$packages")"; done
  for index in "${!TARGET_PATHS[@]}"; do
    targets="$(jq -c --arg path "${TARGET_PATHS[index]}" --arg source "${TARGET_LEXICAL[index]}" \
      --arg resolved "${TARGET_SOURCES[index]}" '. + [{path:$path,source:$source,resolved_source:$resolved}]' <<< "$targets")"
  done
  for index in "${!MANAGED_DIRS[@]}"; do dirs="$(jq -c --arg value "${MANAGED_DIRS[index]}" '. + [$value]' <<< "$dirs")"; done
  backups="$(zsh_ledger_backups_json)"
  jq -cn --arg profile "$SELECTED_PROFILE" --arg checkout "$CHECKOUT_ROOT" --arg target "$TARGET_ROOT" \
    --argjson packages "$packages" --argjson targets "$targets" --argjson dirs "$dirs" --argjson backups "$backups" \
    '{schema_version:1,profile:$profile,area:"zsh",checkout_root:$checkout,target_root:$target,packages:$packages,targets:$targets,managed_directories:$dirs,attachments:[],backups:$backups}'
}

apply_zsh() {
  local state_json
  begin_transaction
  apply_zsh_local_aliases
  remove_recorded_links_for_apply
  remove_approved_legacy_replacements
  fault zsh-after-legacy-links
  apply_stow_packages
  validate_applied_targets
  fault zsh-after-stow
  validate_active_zshrc
  fault zsh-after-active-validation
  remove_zsh_legacy_local
  fault zsh-after-local-source-removal
  apply_zsh_vite_retirement
  update_zsh_migration_ledger
  state_json="$(build_zsh_state_json)"
  write_transaction_string_atomic "$state_json" "$AREA_STATE" 0600
  fault zsh-after-state
  TRANSACTION_ACTIVE=false
  log "applied transitional zsh area for profile '$SELECTED_PROFILE'"
}

remove_zsh() {
  local state="$HOME/.local/state/dotfiles/v1/zsh.json" count index relative dir
  local managed_directories=()
  init_zsh_area
  if [[ ! -e "$state" && ! -L "$state" ]]; then
    log "area 'zsh' is not deployed; no changes made"
    return 0
  fi
  validate_state_file "$state"
  [[ "$(jq -r .target_root "$state")" == "$TARGET_ROOT" ]] || die 'existing zsh state belongs to a different target root'
  SELECTED_PROFILE="$(jq -r .profile "$state")"
  count="$(jq '.targets | length' "$state")"
  for ((index=0; index<count; index++)); do validate_recorded_target "$state" "$index"; done
  validate_migrations_ledger
  validate_zsh_state "$state"
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
    remove_recorded_target "$state" "$index"
  done
  fault zsh-remove-after-links
  remove_current_regular_path "$state" 'zsh area state'
  fault zsh-remove-after-state
  prune_managed_directories "${managed_directories[@]}"
  TRANSACTION_ACTIVE=false
  log 'removed managed zsh links and state; retained local aliases, Zinit, history, migration backups, ledger, and Vite+ retirement'
}
