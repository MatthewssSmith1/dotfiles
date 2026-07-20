# Git area: preflight, apply, and removal; sourced by bootstrap.sh exactly once.

readonly MANAGED_BEGIN='# >>> dotfiles managed git includes >>>'
readonly MANAGED_END='# <<< dotfiles managed git includes <<<'
readonly MANAGED_MARKER_TOKEN='dotfiles managed git includes'
readonly MANAGED_BLOCK="$MANAGED_BEGIN
[include]
	path = ~/.config/dotfiles/personal/git.conf
[include]
	path = ~/.gitconfig.local
[include]
	path = ~/.config/dotfiles/local/git.conf
$MANAGED_END"

# Single source for the sixteen pinned baseline key/value pairs; the required-value
# check, the baseline key set, and the effective-value check all derive from it.
readonly GIT_BASELINE_TABLE='alias.co	checkout
alias.br	branch
alias.ci	commit
alias.st	status
init.defaultBranch	master
pull.rebase	true
push.autoSetupRemote	true
diff.algorithm	histogram
diff.colorMoved	plain
diff.mnemonicPrefix	true
commit.verbose	true
column.ui	auto
branch.sort	-committerdate
tag.sort	-version:refname
rerere.enabled	true
rerere.autoupdate	true'

init_git_area() {
  AREA=git
  AREA_JOURNAL_PATHS=(
    "$HOME/.gitconfig"
    "$HOME/.gitconfig.local"
    "$HOME/.config/dotfiles/local/git.conf"
    "$HOME/.local/state/dotfiles/v1/migrations.json"
  )
  register_migration_ledger_journal
  AREA_ATTACHMENT_VALIDATOR=validate_attachment_from_state
}

validate_managed_global() {
  local file="$1"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  [[ "$(stat -c %u -- "$file")" == "$EUID" ]] || return 1
  inspect_guarded_block "$file" "$MANAGED_BEGIN" "$MANAGED_END" "$MANAGED_MARKER_TOKEN" "$MANAGED_BLOCK"
}

validate_git_file() {
  local file="$1"
  git config --file "$file" --list >/dev/null 2>&1 || die "$file is not valid Git configuration"
}

validate_git_file_without_includes() {
  local file="$1"
  git config --file "$file" --no-includes --list >/dev/null 2>&1 || die "$file is not valid Git configuration"
}

git_values() {
  local file="$1" key="$2"
  git config --file "$file" --get-all "$key" 2>/dev/null || true
}

identity_value() {
  local file="$1" key="$2"
  local values=()
  mapfile -t values < <(git_values "$file" "$key")
  ((${#values[@]} <= 1)) || die "$file contains multiple $key values"
  printf '%s' "${values[0]:-}"
}

validate_identity_inputs() {
  local name="${GIT_USER_NAME:-}" email="${GIT_USER_EMAIL:-}"
  if [[ -n "$name" || -n "$email" ]]; then
    [[ -n "$name" && -n "$email" ]] || die 'GIT_USER_NAME and GIT_USER_EMAIL must be supplied together'
    [[ "$name" != *$'\n'* && "$name" != *$'\r'* ]] || die 'GIT_USER_NAME must not contain line breaks'
    [[ "$email" != *$'\n'* && "$email" != *$'\r'* ]] || die 'GIT_USER_EMAIL must not contain line breaks'
  fi
}

validate_git_environment() {
  local name
  if [[ -n "${XDG_CONFIG_HOME:-}" && "$XDG_CONFIG_HOME" != "$HOME/.config" ]]; then
    die "XDG_CONFIG_HOME is set to '$XDG_CONFIG_HOME'; unset it or set it to '$HOME/.config' before Git deployment"
  fi
  for name in GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT; do
    [[ -z "${!name+x}" ]] || die "$name is set; unset it before Git deployment"
  done
}

preflight_identity() {
  local path="$HOME/.gitconfig.local"
  local expected="$DOTFILES_DIR/.gitconfig.local"
  local source="$path" name email mode
  IDENTITY_ACTION=none
  IDENTITY_SOURCE=""
  IDENTITY_ADD_NAME=false
  IDENTITY_ADD_EMAIL=false
  IDENTITY_REMOVE_NAME=false
  IDENTITY_REMOVE_EMAIL=false
  IDENTITY_EXPECTED_IDENTITY=""
  validate_home_parent_chain "$path"

  if [[ -L "$path" ]]; then
    owned_legacy_link "$path" .gitconfig.local .gitconfig.local git migrate-stage-2 || \
      die "$path is an unknown identity symlink"
    [[ -f "$OWNED_LEGACY_SOURCE" && ! -L "$OWNED_LEGACY_SOURCE" ]] || \
      die "known legacy identity source is missing: $OWNED_LEGACY_SOURCE"
    source="$OWNED_LEGACY_SOURCE"
    IDENTITY_ACTION=copy
    IDENTITY_SOURCE="$OWNED_LEGACY_SOURCE"
  elif [[ -e "$path" ]]; then
    [[ -f "$path" ]] || die "$path exists but is not a regular file"
  else
    IDENTITY_ACTION=create
  fi

  if [[ "$IDENTITY_ACTION" == create ]]; then
    name=""
    email=""
  else
    validate_git_file "$source"
    if git config --file "$source" --name-only --list | while IFS= read -r key; do
      [[ "${key,,}" != include.* && "${key,,}" != includeif.* ]] || exit 1
    done; then
      :
    else
      die "$source contains an ambiguous identity include"
    fi
    name="$(identity_value "$source" user.name)"
    email="$(identity_value "$source" user.email)"
    if [[ "$name" == 'Your Name' || -z "$name" ]] && git config --file "$source" --get-all user.name >/dev/null 2>&1; then
      name=""
      IDENTITY_REMOVE_NAME=true
    fi
    if [[ "$email" == 'you@example.com' || -z "$email" ]] && git config --file "$source" --get-all user.email >/dev/null 2>&1; then
      email=""
      IDENTITY_REMOVE_EMAIL=true
    fi
  fi
  if [[ -z "$name" || -z "$email" ]]; then
    [[ -n "${GIT_USER_NAME:-}" && -n "${GIT_USER_EMAIL:-}" ]] || \
      die 'missing Git identity; set both GIT_USER_NAME and GIT_USER_EMAIL'
    [[ -n "$name" ]] || IDENTITY_ADD_NAME=true
    [[ -n "$email" ]] || IDENTITY_ADD_EMAIL=true
    [[ "$IDENTITY_ACTION" != none ]] || IDENTITY_ACTION=fill
  fi
  if [[ "$IDENTITY_ACTION" == none ]]; then
    mode="$(stat -c %a -- "$path")"
    [[ "$mode" == 600 ]] || IDENTITY_ACTION=protect
  fi
  capture_path_identity "$path" || die "Git identity path changed during preflight: $path"
  IDENTITY_EXPECTED_IDENTITY="$PATH_IDENTITY"
}

load_baseline_keys() {
  local file key
  declare -gA BASELINE_KEYS=()
  while IFS=$'\t' read -r key _; do BASELINE_KEYS["${key,,}"]=1; done <<< "$GIT_BASELINE_TABLE"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    file="$HOME/.config/git/config"
    validate_home_parent_chain "$file"
    [[ -f "$file" && ! -L "$file" ]] || die 'Omarchy native ~/.config/git/config baseline is missing or not a regular file'
  else
    file="$DOTFILES_DIR/packages/upstream/git/.config/git/config"
    [[ -f "$file" && ! -L "$file" ]] || die 'generic upstream Git baseline payload is missing'
    "$DOTFILES_DIR/scripts/upstream" verify >/dev/null || die 'pinned upstream Git snapshot verification failed'
  fi
  validate_git_file "$file"
  validate_required_baseline_values "$file"
  while IFS= read -r key; do BASELINE_KEYS["${key,,}"]=1; done < <(git config --file "$file" --name-only --list)
}

validate_required_baseline_values() {
  local file="$1" key expected actual
  while IFS=$'\t' read -r key expected; do
    actual="$(git config --file "$file" --get "$key" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] || \
      die "$file has unexpected $key: expected '$expected', found '$actual'"
  done <<< "$GIT_BASELINE_TABLE"
}

collect_legacy_settings() {
  local file="$1" entry key value lower include_path include_count=0
  MIGRATION_KEYS=()
  MIGRATION_VALUES=()
  validate_git_file "$file"
  while IFS= read -r -d '' entry; do
    key="${entry%%$'\n'*}"
    value="${entry#*$'\n'}"
    lower="${key,,}"
    case "$lower" in
      include.path)
        ((include_count += 1))
        ((include_count == 1)) || die 'ambiguous duplicate include in known legacy global config'
        if [[ "$value" == '~/'* ]]; then
          include_path="$HOME/${value:2}"
        else
          include_path="$value"
        fi
        [[ "$(realpath -m -s -- "$include_path")" == "$HOME/.gitconfig.local" ]] || \
          die "ambiguous include in known legacy global config: $value"
        continue
        ;;
      includeif.*) die 'ambiguous includeIf in known legacy global config' ;;
      user.name|user.email|init.defaultbranch|rebase.autostash) continue ;;
      credential.helper|credential.*.helper) ;;
      *) [[ -z "${BASELINE_KEYS[$lower]+x}" ]] || continue ;;
    esac
    MIGRATION_KEYS+=("$key")
    MIGRATION_VALUES+=("$value")
  done < <(git config --null --file "$file" --list)
}

validate_central_local() {
  local path="$HOME/.config/dotfiles/local/git.conf"
  local entry key lower actual=() expected=() i
  CENTRAL_ACTION=none
  CENTRAL_EXPECTED_IDENTITY=""
  validate_home_parent_chain "$path"
  if [[ -L "$path" ]]; then
    die "$path must not be a symlink"
  elif [[ -e "$path" ]]; then
    [[ -f "$path" ]] || die "$path exists but is not a regular file"
    validate_git_file "$path"
    while IFS= read -r -d '' entry; do
      key="${entry%%$'\n'*}"
      lower="${key,,}"
      case "$lower" in
        include.*|includeif.*) die "$path contains an ambiguous include" ;;
        user.name|user.email) die "$path conflicts with external Git identity" ;;
      esac
    done < <(git config --null --file "$path" --list)

    declare -A checked=()
    for key in "${MIGRATION_KEYS[@]}"; do
      lower="${key,,}"
      [[ -z "${checked[$lower]+x}" ]] || continue
      checked["$lower"]=1
      expected=()
      for i in "${!MIGRATION_KEYS[@]}"; do
        [[ "${MIGRATION_KEYS[i],,}" == "$lower" ]] && expected+=("${MIGRATION_VALUES[i]}")
      done
      actual=()
      mapfile -t actual < <(git_values "$path" "$lower")
      ((${#actual[@]} == ${#expected[@]})) || die "$path does not preserve required values for $lower"
      for i in "${!expected[@]}"; do
        [[ "${actual[i]}" == "${expected[i]}" ]] || die "$path does not preserve ordered values for $lower"
      done
    done
  else
    CENTRAL_ACTION=create
  fi
  capture_path_identity "$path" || die "central Git local path changed during preflight: $path"
  CENTRAL_EXPECTED_IDENTITY="$PATH_IDENTITY"
}

inspect_git_configuration() {
  git -C "$HOME" config --includes --show-origin --show-scope --list >/dev/null 2>&1 || \
    die 'current global or XDG Git configuration cannot be inspected with origin and scope'
}

refuse_repeated_legacy_migration() {
  [[ "$MIGRATION_REQUIRED" == true || "$IDENTITY_ACTION" == copy ]] || return 0
  preflight_migration git-legacy-v1 true 'Git legacy migration'
}

preflight_global() {
  local path="$HOME/.gitconfig"
  local expected="$DOTFILES_DIR/.gitconfig"
  GLOBAL_ACTION=none
  GLOBAL_KIND=managed
  GLOBAL_LEGACY_SOURCE=""
  GLOBAL_EXPECTED_IDENTITY=""
  MIGRATION_KEYS=()
  MIGRATION_VALUES=()
  MIGRATION_REQUIRED=false
  validate_home_parent_chain "$path"

  if [[ -L "$path" ]]; then
    owned_legacy_link "$path" .gitconfig .gitconfig git migrate-stage-2 || \
      die "$path is an unknown global-config symlink"
    GLOBAL_KIND=legacy
    GLOBAL_ACTION=replace
    MIGRATION_REQUIRED=true
    GLOBAL_LEGACY_SOURCE="$OWNED_LEGACY_SOURCE"
    collect_legacy_settings "$GLOBAL_LEGACY_SOURCE"
  elif [[ -e "$path" ]]; then
    [[ -f "$path" ]] || die "$path exists but is not a regular file"
    validate_managed_global "$path" || die "$path has a missing, malformed, nested, duplicate, or modified managed block"
    validate_git_file_without_includes "$path"
  else
    GLOBAL_KIND=absent
    GLOBAL_ACTION=create
  fi
  capture_path_identity "$path" || die "global Git path changed during preflight: $path"
  GLOBAL_EXPECTED_IDENTITY="$PATH_IDENTITY"
}

validate_attachment_from_state() {
  local state="$1" id path hash
  [[ "$(jq '.attachments | length' "$state")" == 1 ]] || die 'Git state does not record exactly one managed attachment'
  while IFS=$'\t' read -r id path hash; do
    [[ "$id" == git-global-includes-v1 && "$path" == .gitconfig ]] || die "unknown Git attachment in state: $id"
    [[ "$hash" == "$(sha256_string "$MANAGED_BLOCK")" ]] || die 'managed Git attachment hash is unknown'
    validate_home_parent_chain "$HOME/$path"
    validate_managed_global "$HOME/$path" || die "managed Git attachment has drifted: $HOME/$path"
    [[ "$MODE" == remove ]] || validate_git_file_without_includes "$HOME/$path"
  done < <(jq -r '.attachments[] | [.id,.path,.content_hash] | @tsv' "$state")
}

preflight_git() {
  validate_identity_inputs
  validate_git_environment
  init_git_area
  load_profile_closure git
  scan_packages
  record_managed_parents '.local/state/dotfiles/v1/git.json'
  load_baseline_keys
  preflight_global
  preflight_identity
  validate_central_local
  inspect_git_configuration
  validate_migrations_ledger
  refuse_repeated_legacy_migration
  preflight_existing_state
  preflight_desired_targets
  run_stow_preflight
}

apply_central_local() {
  local path="$HOME/.config/dotfiles/local/git.conf" temporary i
  [[ "$CENTRAL_ACTION" == create ]] || return 0
  ensure_directory "$(dirname -- "$path")"
  temporary="$(mktemp "$(dirname -- "$path")/.git.conf.tmp.XXXXXX")"
  track_temp_path "$temporary"
  chmod 0600 "$temporary"
  for i in "${!MIGRATION_KEYS[@]}"; do
    git config --file "$temporary" --add "${MIGRATION_KEYS[i]}" "${MIGRATION_VALUES[i]}"
  done
  validate_git_file "$temporary"
  track_temp_path "$temporary"
  replace_with_staged_regular "$temporary" "$path" "$CENTRAL_EXPECTED_IDENTITY" 'central Git local file'
}

apply_identity() {
  local path="$HOME/.gitconfig.local" temporary source
  [[ "$IDENTITY_ACTION" != none ]] || return 0
  ensure_directory "$HOME"
  temporary="$(mktemp "$HOME/.gitconfig.local.tmp.XXXXXX")"
  track_temp_path "$temporary"
  source="$path"
  [[ "$IDENTITY_ACTION" != copy ]] || source="$IDENTITY_SOURCE"
  if [[ "$IDENTITY_ACTION" == create ]]; then
    : > "$temporary"
  else
    cp -- "$source" "$temporary"
  fi
  chmod 0600 "$temporary"
  [[ "$IDENTITY_REMOVE_NAME" == false ]] || git config --file "$temporary" --unset-all user.name || true
  [[ "$IDENTITY_REMOVE_EMAIL" == false ]] || git config --file "$temporary" --unset-all user.email || true
  [[ "$IDENTITY_ADD_NAME" == false ]] || git config --file "$temporary" --add user.name "$GIT_USER_NAME"
  [[ "$IDENTITY_ADD_EMAIL" == false ]] || git config --file "$temporary" --add user.email "$GIT_USER_EMAIL"
  validate_git_file "$temporary"
  [[ -n "$(identity_value "$temporary" user.name)" && -n "$(identity_value "$temporary" user.email)" ]] || \
    die 'generated Git identity is incomplete'
  track_temp_path "$temporary"
  replace_with_staged_regular "$temporary" "$path" "$IDENTITY_EXPECTED_IDENTITY" 'Git identity file'
}

apply_global() {
  case "$GLOBAL_ACTION" in
    none) ;;
    create|replace) write_guarded_attachment_only_atomic .gitconfig "$MANAGED_BLOCK" 0644 "$GLOBAL_EXPECTED_IDENTITY" ;;
    *) die "unknown global action: $GLOBAL_ACTION" ;;
  esac
}

update_migrations_ledger() {
  local fingerprint source_material=""
  [[ "$MIGRATION_REQUIRED" == true || "$IDENTITY_ACTION" == copy ]] || return 0
  [[ "$GLOBAL_KIND" != legacy ]] || source_material+="$(sha256_file "$GLOBAL_LEGACY_SOURCE")"
  [[ "$IDENTITY_ACTION" != copy ]] || source_material+="$(sha256_file "$IDENTITY_SOURCE")"
  fingerprint="$(sha256_string "$source_material")"
  append_migration_ledger git-legacy-v1 "$fingerprint"
}

build_state_json() {
  local packages='[]' targets='[]' dirs='[]' attachments hash i
  for i in "${!PACKAGES[@]}"; do packages="$(jq -c --arg value "${PACKAGES[i]}" '. + [$value]' <<< "$packages")"; done
  for i in "${!TARGET_PATHS[@]}"; do
    targets="$(jq -c --arg path "${TARGET_PATHS[i]}" --arg source "${TARGET_LEXICAL[i]}" \
      --arg resolved "${TARGET_SOURCES[i]}" '. + [{path:$path,source:$source,resolved_source:$resolved}]' <<< "$targets")"
  done
  for i in "${!MANAGED_DIRS[@]}"; do dirs="$(jq -c --arg value "${MANAGED_DIRS[i]}" '. + [$value]' <<< "$dirs")"; done
  hash="$(sha256_string "$MANAGED_BLOCK")"
  attachments="$(jq -cn --arg hash "$hash" '[{id:"git-global-includes-v1",path:".gitconfig",content_hash:$hash}]')"
  jq -cn --arg profile "$SELECTED_PROFILE" --arg checkout "$CHECKOUT_ROOT" --arg target "$TARGET_ROOT" \
    --argjson packages "$packages" --argjson targets "$targets" --argjson dirs "$dirs" --argjson attachments "$attachments" \
    '{schema_version:1,profile:$profile,area:"git",checkout_root:$checkout,target_root:$target,packages:$packages,targets:$targets,managed_directories:$dirs,attachments:$attachments,backups:[]}'
}

validate_effective_git() {
  local name email branch key expected actual origin baseline_origin inspection
  branch="$(git -C "$HOME" config --includes --get init.defaultBranch 2>/dev/null || true)"
  name="$(git -C "$HOME" config --includes --get user.name 2>/dev/null || true)"
  email="$(git -C "$HOME" config --includes --get user.email 2>/dev/null || true)"
  [[ "$branch" == main ]] || die 'effective init.defaultBranch does not resolve to main'
  [[ -n "$name" && -n "$email" ]] || die 'effective Git identity is incomplete'
  origin="$(git -C "$HOME" config --includes --show-origin --show-scope --get init.defaultBranch 2>/dev/null || true)"
  [[ "$origin" == global$'\t'file:"$HOME/.config/dotfiles/personal/git.conf"$'\t'* ]] || \
    die 'effective init.defaultBranch does not originate from the personal Git layer'
  for key in user.name user.email; do
    origin="$(git -C "$HOME" config --includes --show-origin --show-scope --get "$key" 2>/dev/null || true)"
    [[ "$origin" == global$'\t'file:"$HOME/.gitconfig.local"$'\t'* ]] || \
      die "effective $key does not originate from ~/.gitconfig.local at global scope"
  done
  baseline_origin="$HOME/.config/git/config"
  while IFS=$'\t' read -r key expected; do
    # init.defaultBranch is asserted above as 'main' from the personal layer.
    [[ "$key" != init.defaultBranch ]] || continue
    actual="$(git -C "$HOME" config --includes --get "$key" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] || die "effective $key does not match the accepted baseline"
    origin="$(git -C "$HOME" config --includes --show-origin --show-scope --get "$key" 2>/dev/null || true)"
    [[ "$origin" == global$'\t'file:"$baseline_origin"$'\t'* ]] || \
      die "effective $key does not originate from the baseline Git layer at global scope"
  done <<< "$GIT_BASELINE_TABLE"
  inspection="$(git -C "$HOME" config --includes --show-origin --show-scope --get-regexp '.*' 2>/dev/null || true)"
  [[ -n "$inspection" ]] || die 'effective Git configuration has no origin and scope report'
}

apply_git() {
  local state_json
  begin_transaction
  apply_central_local
  fault after-local
  apply_identity
  fault after-identity
  remove_recorded_links_for_apply
  apply_stow_packages
  validate_applied_targets
  fault after-stow
  apply_global
  fault after-global
  update_migrations_ledger
  validate_effective_git
  fault before-state
  state_json="$(build_state_json)"
  write_transaction_string_atomic "$state_json" "$AREA_STATE" 0600
  TRANSACTION_ACTIVE=false
  fault after-state-commit
  log "applied Git area for profile '$SELECTED_PROFILE'"
}

remove_git() {
  local state="$HOME/.local/state/dotfiles/v1/git.json"
  local count index relative dir
  local managed_directories=()
  init_git_area
  if [[ ! -e "$state" && ! -L "$state" ]]; then
    log 'Git area is not deployed; no changes made'
    return
  fi
  validate_state_file "$state"
  [[ "$(jq -r .target_root "$state")" == "$TARGET_ROOT" ]] || die 'existing git state belongs to a different target root'
  count="$(jq '.targets | length' "$state")"
  for ((index=0; index<count; index++)); do validate_recorded_target "$state" "$index"; done
  validate_attachment_from_state "$state"
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
  fault remove-after-links
  remove_guarded_attachment .gitconfig "$MANAGED_BEGIN" "$MANAGED_END" "$MANAGED_MARKER_TOKEN" \
    "$MANAGED_BLOCK" prepend existing-final-newline true
  fault remove-after-global
  remove_current_regular_path "$state" 'Git area state'
  prune_managed_directories "${managed_directories[@]}"
  TRANSACTION_ACTIVE=false
  log 'removed managed Git links and global include block; retained identity, local settings, and migration ledger'
}
