# Neovim area: exact Kickstart retirement and one-time XDG runtime preservation.

readonly NVIM_LEGACY_MIGRATION_ID='nvim-kickstart-links-v1'
readonly NVIM_RUNTIME_MIGRATION_PREFIX='nvim-runtime-v1'

NVIM_FOLDED_LEGACY=false
NVIM_LEGACY_PATHS=()
NVIM_LEGACY_IDENTITIES=()
NVIM_RUNTIME_KINDS=()
NVIM_RUNTIME_SOURCES=()
NVIM_RUNTIME_BACKUPS=()
NVIM_RUNTIME_IDENTITIES=()
NVIM_RUNTIME_FINGERPRINTS=()
NVIM_RUNTIME_PENDING=()
NVIM_PRESERVED_RESTORE=""
NVIM_TRANSITIONAL_MARKER=""
NVIM_TRANSITIONAL_MARKER_IDENTITY=""

init_nvim_area() {
  AREA=nvim
  AREA_JOURNAL_PATHS=()
  AREA_ATTACHMENT_VALIDATOR=validate_nvim_state
  NVIM_FOLDED_LEGACY=false
  NVIM_LEGACY_PATHS=()
  NVIM_LEGACY_IDENTITIES=()
  NVIM_RUNTIME_KINDS=()
  NVIM_RUNTIME_SOURCES=()
  NVIM_RUNTIME_BACKUPS=()
  NVIM_RUNTIME_IDENTITIES=()
  NVIM_RUNTIME_FINGERPRINTS=()
  NVIM_RUNTIME_PENDING=()
  NVIM_PRESERVED_RESTORE=""
  NVIM_TRANSITIONAL_MARKER=""
  NVIM_TRANSITIONAL_MARKER_IDENTITY=""
  register_migration_ledger_journal
}

area_retiring_managed_parent() {
  [[ "$AREA" == nvim && "$NVIM_FOLDED_LEGACY" == true &&
    ( "$1" == "$HOME/.config/nvim" || "$1" == "$HOME/.config/nvim/"* ) ]]
}

area_retiring_desired_target() {
  local path="$1" legacy
  [[ "$AREA" == nvim ]] || return 1
  for legacy in "${NVIM_LEGACY_PATHS[@]:-}"; do
    [[ -n "$legacy" ]] || continue
    [[ "$path" == "$legacy" || "$path" == "$legacy/"* ]] && return 0
  done
  return 1
}

area_requires_isolated_stow_preflight() {
  [[ "$AREA" == nvim && ${#NVIM_LEGACY_PATHS[@]} -gt 0 ]]
}

nvim_expected_targets() {
  NVIM_EXPECTED_TARGETS=(
    .config/dotfiles/nvim/generic.lua
    .config/dotfiles/nvim/personal.lua
    .config/nvim/.gitignore
    .config/nvim/.neoconf.json
    .config/nvim/LICENSE
    .config/nvim/README.md
    .config/nvim/init.lua
    .config/nvim/lazy-lock.json
    .config/nvim/lazyvim.json
    .config/nvim/lua/config/autocmds.lua
    .config/nvim/lua/config/keymaps.lua
    .config/nvim/lua/config/lazy.lua
    .config/nvim/lua/config/options.lua
    .config/nvim/lua/config/remote_clipboard.lua
    .config/nvim/lua/dotfiles_policy.lua
    .config/nvim/lua/plugins/all-themes.lua
    .config/nvim/lua/plugins/disable-news-alert.lua
    .config/nvim/lua/plugins/dotfiles-runtime-policy.lua
    .config/nvim/lua/plugins/example.lua
    .config/nvim/lua/plugins/omarchy-theme-hotreload.lua
    .config/nvim/lua/plugins/snacks-animated-scrolling-off.lua
    .config/nvim/lua/plugins/theme.lua
    .config/nvim/plugin/after/transparency.lua
    .config/nvim/stylua.toml
    .local/share/dotfiles/bin/nvim-record-restore
    .local/share/dotfiles/bin/nvim-restore
  )
}

validate_nvim_target_inventory() {
  local path
  local -A expected=() actual=()
  nvim_expected_targets
  [[ "${PACKAGES[*]}" == 'upstream/nvim generic/nvim common/nvim' ]] || \
    die 'Neovim package closure must be exactly upstream/generic/common'
  for path in "${NVIM_EXPECTED_TARGETS[@]}"; do expected["$path"]=1; done
  for path in "${TARGET_PATHS[@]}"; do actual["$path"]=1; done
  for path in "${NVIM_EXPECTED_TARGETS[@]}"; do
    [[ -n "${actual[$path]+x}" ]] || die "Neovim package closure is missing expected target: $path"
  done
  for path in "${TARGET_PATHS[@]}"; do
    [[ -n "${expected[$path]+x}" ]] || die "Neovim package closure contains unexpected target: $path"
  done
  ((${#TARGET_PATHS[@]} == ${#NVIM_EXPECTED_TARGETS[@]})) || die 'Neovim package target inventory is not unique'
}

validate_nvim_payload() {
  local index path mode
  for index in "${!TARGET_PATHS[@]}"; do
    path="${TARGET_PATHS[index]}"; mode="$(stat -c %a -- "${TARGET_SOURCES[index]}")"
    if [[ "$path" == .local/share/dotfiles/bin/* ]]; then
      [[ "$mode" == 755 ]] || die "Neovim helper is not mode 755: $path"
    else
      [[ "$mode" == 644 ]] || die "Neovim payload is not mode 644: $path"
    fi
    file_contains_nul "${TARGET_SOURCES[index]}" && die "Neovim payload contains NUL bytes: $path"
  done
  jq -e 'type == "object" and length > 0 and (.["lazy.nvim"].commit | test("^[0-9a-f]{40}$"))' \
    "$DOTFILES_DIR/packages/upstream/nvim/.config/nvim/lazy-lock.json" >/dev/null || die 'invalid deployed Neovim lockfile'
  "$DOTFILES_DIR/scripts/upstream" verify >/dev/null || die 'pinned upstream Neovim snapshot verification failed'
}

validate_nvim_executable() {
  local executable output
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_NVIM_BIN:-}" ]]; then
    executable="$DOTFILES_TEST_NVIM_BIN"
  else
    executable="$(command -v nvim 2>/dev/null || true)"
  fi
  [[ -n "$executable" && -f "$executable" && ! -L "$executable" && -x "$executable" ]] || \
    die 'no directly executable Neovim runtime is available'
  output="$(run_offline_probe "$executable" --version 2>/dev/null)" || die 'Neovim version probe failed'
  [[ "$output" == NVIM\ v* ]] || die 'Neovim version probe returned invalid output'
}

nvim_lexical_link_target() {
  local path="$1" value
  value="$(readlink -- "$path")"
  if [[ "$value" == /* ]]; then realpath -m -s -- "$value"; else realpath -m -s -- "$(dirname -- "$path")/$value"; fi
}

nvim_reviewed_link() {
  local path="$1" relative="$2" expected lexical resolved expected_resolved
  [[ -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" ]] || return 1
  legacy_manifest_record "$relative" "$relative" nvim replace-stage-8 || return 1
  expected="$REVIEWED_LEGACY_ROOT/$relative"
  lexical="$(nvim_lexical_link_target "$path")"
  resolved="$(realpath -m -- "$path")"
  expected_resolved="$(realpath -m -- "$expected")"
  [[ "$lexical" == "$expected" && "$resolved" == "$expected_resolved" ]]
}

nvim_reviewed_container() {
  local relative="$1" path="$HOME/$1"
  [[ -d "$path" && ! -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" ]] || return 1
  jq -e --arg home "$TARGET_ROOT" --arg prefix "$relative/" '
    any(.hosts[] | select(.home == $home) | .records[];
      .[2] == "nvim" and .[4] == "replace-stage-8" and (.[0] | startswith($prefix)))
  ' "$DOTFILES_DIR/manifests/legacy-links.json" >/dev/null
}

nvim_require_owned_ancestors() {
  local path="$1" relative current component
  local components=()
  relative="${path#"$HOME"/}"
  current="$HOME"
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    current="$current/$component"
    [[ ! -e "$current" || ( -d "$current" && ! -L "$current" && "$(stat -c %u -- "$current")" == "$EUID" ) ]] || \
      die "Neovim XDG ancestor is not an owner-controlled directory: $current"
  done
}

preflight_nvim_legacy() {
  local root="$HOME/.config/nvim" relative path expected_root fingerprint_data="" state
  state="$HOME/.local/state/dotfiles/v1/nvim.json"
  [[ ! -e "$state" && ! -L "$state" ]] || return 0
  validate_home_parent_chain "$root"
  if [[ -L "$root" ]]; then
    legacy_manifest_record '.config/nvim/init.lua' '.config/nvim/init.lua' nvim replace-stage-8 || \
      die 'folded Neovim legacy topology is not reviewed for this HOME'
    expected_root="$REVIEWED_LEGACY_ROOT/.config/nvim"
    [[ "$(stat -c %u -- "$root")" == "$EUID" && "$(nvim_lexical_link_target "$root")" == "$expected_root" &&
      "$(realpath -m -- "$root")" == "$(realpath -m -- "$expected_root")" ]] || \
      die "$root is not the exact reviewed folded Kickstart link"
    capture_path_identity "$root" || die 'folded Kickstart link changed during preflight'
    NVIM_FOLDED_LEGACY=true
    NVIM_LEGACY_PATHS+=("$root"); NVIM_LEGACY_IDENTITIES+=("$PATH_IDENTITY")
    AREA_JOURNAL_PATHS+=("$root")
    fingerprint_data="folded|$expected_root"
  elif [[ -e "$root" ]]; then
    [[ -d "$root" ]] || die "$root is unrelated host data"
    while IFS= read -r relative; do
      path="$HOME/$relative"
      [[ -e "$path" || -L "$path" ]] || continue
      if [[ -d "$path" && ! -L "$path" ]]; then
        nvim_reviewed_container "${path#"$HOME"/}" || die "unreviewed container in Kickstart tree: $path"
        continue
      fi
      nvim_reviewed_link "$path" "$relative" || die "unrelated or modified object in reviewed Kickstart topology: $path"
      capture_path_identity "$path" || die "Kickstart link changed during preflight: $path"
      NVIM_LEGACY_PATHS+=("$path"); NVIM_LEGACY_IDENTITIES+=("$PATH_IDENTITY")
      AREA_JOURNAL_PATHS+=("$path")
      fingerprint_data+="$relative|$(nvim_lexical_link_target "$path")"$'\n'
    done < <(jq -r --arg home "$TARGET_ROOT" '.hosts[] | select(.home == $home) | .records[] |
      select(.[2] == "nvim" and .[4] == "replace-stage-8") | .[0]' "$DOTFILES_DIR/manifests/legacy-links.json")
    shopt -s dotglob globstar nullglob
    for path in "$root"/**/* "$root"/*; do
      if [[ -d "$path" && ! -L "$path" ]]; then
        nvim_reviewed_container "${path#"$HOME"/}" || die "unreviewed container in Kickstart tree: $path"
        continue
      fi
      array_contains "$path" "${NVIM_LEGACY_PATHS[@]:-}" || die "unreviewed object in Kickstart tree: $path"
    done
    shopt -u dotglob globstar nullglob
  fi
  if ((${#NVIM_LEGACY_PATHS[@]} > 0)); then
    migration_is_completed "$NVIM_LEGACY_MIGRATION_ID" && die 'retired Kickstart links reappeared after recorded migration'
    NVIM_LEGACY_FINGERPRINT="$(sha256_string "$fingerprint_data")"
  fi
}

nvim_tree_fingerprint() {
  local root="$1" path relative value="" type
  local paths=()
  shopt -s dotglob globstar nullglob
  paths=("$root" "$root"/**)
  shopt -u dotglob globstar nullglob
  for path in "${paths[@]}"; do
    relative="${path#"$root"}"
    if [[ -L "$path" ]]; then type="l|$(readlink -- "$path")"
    elif [[ -f "$path" ]]; then type="f|$(sha256_file "$path")"
    elif [[ -d "$path" ]]; then type=d
    else die "unsupported object in Neovim runtime root: $path"
    fi
    value+="$relative|$type"$'\n'
  done
  NVIM_TREE_FINGERPRINT="$(sha256_string "$value")"
}

nvim_resolve_xdg_root() {
  local kind="$1" base root
  case "$kind" in
    data) base="${XDG_DATA_HOME:-$HOME/.local/share}" ;;
    state) base="${XDG_STATE_HOME:-$HOME/.local/state}" ;;
    cache) base="${XDG_CACHE_HOME:-$HOME/.cache}" ;;
  esac
  base="${base%/}"
  [[ "$base" == /* && "$(realpath -m -s -- "$base")" == "$base" && "$base" == "$HOME/"* ]] || \
    die "XDG_${kind^^}_HOME must be a canonical path beneath HOME"
  root="$(realpath -m -s -- "$base/nvim")"
  [[ "$root" == "$HOME/"* ]] || die "Neovim $kind root resolves outside HOME: $root"
  validate_home_parent_chain "$root"
  nvim_require_owned_ancestors "$(dirname -- "$root")"
  NVIM_XDG_ROOT="$root"
}

allocate_nvim_runtime_backup() {
  local source="$1" stamp candidate counter=0 ledger
  stamp="${DOTFILES_TEST_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
  candidate="$source.$stamp.bak"; ledger="$(migration_ledger_path)"
  while [[ -e "$candidate" || -L "$candidate" ]] || { [[ -f "$ledger" ]] && jq -e --arg p "${candidate#"$HOME"/}" 'any(.migrations[].backups[]; . == $p)' "$ledger" >/dev/null; }; do
    ((counter += 1)); candidate="$source.$stamp.$counter.bak"
  done
  NVIM_RUNTIME_BACKUP="$candidate"
}

preflight_nvim_runtime_migrations() {
  local kind id source fingerprint backup relative
  for kind in data state cache; do
    id="$NVIM_RUNTIME_MIGRATION_PREFIX-$kind"
    nvim_resolve_xdg_root "$kind"; source="$NVIM_XDG_ROOT"
    NVIM_RUNTIME_KINDS+=("$kind"); NVIM_RUNTIME_SOURCES+=("$source")
    if migration_is_completed "$id"; then
      backup="$(jq -r --arg id "$id" '.migrations[] | select(.id == $id) | .backups[0] // empty' "$(migration_ledger_path)")"
      fingerprint="$(jq -r --arg id "$id" '.migrations[] | select(.id == $id) | .source_fingerprint' "$(migration_ledger_path)")"
      if [[ -n "$backup" ]]; then
        nvim_tree_fingerprint "$HOME/$backup"
        [[ "$NVIM_TREE_FINGERPRINT" == "$fingerprint" ]] || die "retained Neovim $kind backup fingerprint drifted"
      fi
      NVIM_RUNTIME_BACKUPS+=("$backup"); NVIM_RUNTIME_IDENTITIES+=(""); NVIM_RUNTIME_FINGERPRINTS+=("$fingerprint"); NVIM_RUNTIME_PENDING+=(false)
      continue
    fi
    if [[ -e "$source" || -L "$source" ]]; then
      [[ -d "$source" && ! -L "$source" && "$(stat -c %u -- "$source")" == "$EUID" ]] || die "Neovim $kind root is unsafe: $source"
      nvim_tree_fingerprint "$source"; fingerprint="$NVIM_TREE_FINGERPRINT"
      capture_path_object_identity "$source" || die "Neovim $kind root changed during preflight"
      NVIM_RUNTIME_IDENTITIES+=("$PATH_OBJECT_IDENTITY")
      allocate_nvim_runtime_backup "$source"; backup="$NVIM_RUNTIME_BACKUP"
      relative="${backup#"$HOME"/}"
      NVIM_RUNTIME_BACKUPS+=("$relative")
    else
      fingerprint="$(sha256_string "absent|$kind|${source#"$HOME"/}")"
      NVIM_RUNTIME_IDENTITIES+=(absent); NVIM_RUNTIME_BACKUPS+=("")
    fi
    NVIM_RUNTIME_FINGERPRINTS+=("$fingerprint"); NVIM_RUNTIME_PENDING+=(true)
  done
}

preflight_nvim_transitional_marker() {
  local base marker value
  base="${XDG_STATE_HOME:-$HOME/.local/state}"
  [[ "$base" == /* ]] || die 'XDG_STATE_HOME must be absolute'
  marker="$(realpath -m -s -- "$base/dotfiles/nvim-restored-lock")"
  [[ "$marker" == "$HOME/"* ]] || die "transitional Neovim marker resolves outside HOME: $marker"
  validate_home_parent_chain "$marker"
  [[ -e "$marker" || -L "$marker" ]] || return 0
  [[ -f "$marker" && ! -L "$marker" && "$(stat -c %u -- "$marker")" == "$EUID" &&
    "$(stat -c %a -- "$marker")" == 600 ]] || die 'transitional Neovim restore marker is unsafe'
  IFS= read -r value < "$marker" || true
  [[ "$value" =~ ^[0-9a-f]{64}$ && "$(stat -c %s -- "$marker")" == 65 ]] || \
    die 'transitional Neovim restore marker is malformed'
  capture_path_identity "$marker" || die 'transitional Neovim restore marker changed during preflight'
  NVIM_TRANSITIONAL_MARKER="$marker"; NVIM_TRANSITIONAL_MARKER_IDENTITY="$PATH_IDENTITY"
  AREA_JOURNAL_PATHS+=("$marker")
}

validate_nvim_state() {
  local state="$1" restored lock target
  [[ "$(jq '.attachments | length' "$state")" == 0 ]] || die 'Neovim state records unknown attachments'
  [[ "$(jq -r .profile "$state")" == generic || "$(jq -r .profile "$state")" == wsl ]] || die 'native Omarchy Neovim remains deferred to Stage 9'
  restored="$(jq -r '.restored_lock_sha256 // empty' "$state")"
  if [[ -n "$restored" ]]; then
    target="$HOME/.config/nvim/lazy-lock.json"
    [[ -f "$target" ]] || die 'deployed Neovim lockfile is missing'
    lock="$(sha256_file "$target")"
    [[ "$restored" == "$lock" ]] || : # A stale marker is retained until explicit restore.
  fi
}

require_nvim_runtime_ledger_for_state() {
  local kind
  [[ "$OLD_STATE" == true ]] || return 0
  for kind in data state cache; do
    migration_is_completed "$NVIM_RUNTIME_MIGRATION_PREFIX-$kind" || \
      die "existing Neovim state lacks completed $kind runtime migration ledger"
  done
}

check_nvim_restore_convergence() {
  local restored lock
  [[ "$OLD_STATE" == true ]] || { log 'pending Neovim restore: deployment state is absent'; return 1; }
  restored="$(jq -r '.restored_lock_sha256 // empty' "$AREA_STATE")"
  lock="$(sha256_file "$HOME/.config/nvim/lazy-lock.json")"
  if [[ -z "$restored" ]]; then
    log 'pending Neovim restore: restored_lock_sha256 is absent'
    return 1
  fi
  if [[ "$restored" != "$lock" ]]; then
    log "stale Neovim restore: restored lock $restored differs from deployed lock $lock"
    return 1
  fi
}

preflight_nvim() {
  init_nvim_area
  [[ "$SELECTED_PROFILE" == generic || "$SELECTED_PROFILE" == wsl ]] || die 'native Omarchy Neovim is deferred to Stage 9'
  load_profile_closure nvim
  preflight_nvim_legacy
  scan_packages
  validate_nvim_target_inventory
  validate_nvim_payload
  validate_nvim_executable
  record_managed_parents '.local/state/dotfiles/v1/nvim.json'
  validate_migrations_ledger
  preflight_existing_state
  require_nvim_runtime_ledger_for_state
  preflight_nvim_runtime_migrations
  preflight_nvim_transitional_marker
  if [[ "$OLD_STATE" == true ]]; then
    local old_restored old_lock
    old_restored="$(jq -r '.restored_lock_sha256 // empty' "$AREA_STATE")"
    old_lock="$(sha256_file "$HOME/.config/nvim/lazy-lock.json")"
    [[ -n "$old_restored" && "$old_restored" == "$old_lock" ]] && NVIM_PRESERVED_RESTORE="$old_restored"
  fi
  preflight_desired_targets
  run_stow_preflight
}

retire_nvim_legacy_links() {
  local index path
  for index in "${!NVIM_LEGACY_PATHS[@]}"; do
    path="${NVIM_LEGACY_PATHS[index]}"
    remove_expected_path "$path" "${NVIM_LEGACY_IDENTITIES[index]}" 'reviewed Kickstart link'
  done
}

move_nvim_runtime_roots() {
  local index source backup
  for index in "${!NVIM_RUNTIME_KINDS[@]}"; do
    [[ "${NVIM_RUNTIME_PENDING[index]}" == true && "${NVIM_RUNTIME_IDENTITIES[index]}" != absent ]] || continue
    source="${NVIM_RUNTIME_SOURCES[index]}"; backup="$HOME/${NVIM_RUNTIME_BACKUPS[index]}"
    register_directory_move "$source" "$backup" "${NVIM_RUNTIME_IDENTITIES[index]}"
    move_registered_directory "$((${#TX_DIRECTORY_MOVE_SOURCES[@]} - 1))"
    nvim_tree_fingerprint "$backup"
    [[ "$NVIM_TREE_FINGERPRINT" == "${NVIM_RUNTIME_FINGERPRINTS[index]}" ]] || die 'Neovim runtime backup differs after rename'
    fault "nvim-after-${NVIM_RUNTIME_KINDS[index]}-move"
  done
}

retire_nvim_transitional_marker() {
  [[ -n "$NVIM_TRANSITIONAL_MARKER" ]] || return 0
  remove_expected_path "$NVIM_TRANSITIONAL_MARKER" "$NVIM_TRANSITIONAL_MARKER_IDENTITY" \
    'transitional Neovim restore marker'
}

nvim_backups_json() {
  local value result='[]'
  for value in "${NVIM_RUNTIME_BACKUPS[@]}"; do [[ -z "$value" ]] || result="$(jq -c --arg v "$value" '. + [$v]' <<< "$result")"; done
  printf '%s' "$result"
}

build_nvim_state_json() {
  local packages='[]' targets='[]' dirs='[]' backups index state
  for index in "${!PACKAGES[@]}"; do packages="$(jq -c --arg v "${PACKAGES[index]}" '. + [$v]' <<< "$packages")"; done
  for index in "${!TARGET_PATHS[@]}"; do
    targets="$(jq -c --arg path "${TARGET_PATHS[index]}" --arg source "${TARGET_LEXICAL[index]}" --arg resolved "${TARGET_SOURCES[index]}" '. + [{path:$path,source:$source,resolved_source:$resolved}]' <<< "$targets")"
  done
  for index in "${!MANAGED_DIRS[@]}"; do dirs="$(jq -c --arg v "${MANAGED_DIRS[index]}" '. + [$v]' <<< "$dirs")"; done
  backups="$(nvim_backups_json)"
  state="$(jq -cn --arg profile "$SELECTED_PROFILE" --arg checkout "$CHECKOUT_ROOT" --arg target "$TARGET_ROOT" --argjson packages "$packages" --argjson targets "$targets" --argjson dirs "$dirs" --argjson backups "$backups" '{schema_version:1,profile:$profile,area:"nvim",checkout_root:$checkout,target_root:$target,packages:$packages,targets:$targets,managed_directories:$dirs,attachments:[],backups:$backups}')"
  [[ -z "$NVIM_PRESERVED_RESTORE" ]] || state="$(jq -c --arg hash "$NVIM_PRESERVED_RESTORE" '.restored_lock_sha256=$hash' <<< "$state")"
  printf '%s' "$state"
}

commit_nvim_migrations() {
  local index backup
  if ((${#NVIM_LEGACY_PATHS[@]} > 0)); then append_migration_ledger "$NVIM_LEGACY_MIGRATION_ID" "$NVIM_LEGACY_FINGERPRINT"; fi
  for index in "${!NVIM_RUNTIME_KINDS[@]}"; do
    [[ "${NVIM_RUNTIME_PENDING[index]}" == true ]] || continue
    backup="${NVIM_RUNTIME_BACKUPS[index]}"
    if [[ -n "$backup" ]]; then
      append_migration_ledger "$NVIM_RUNTIME_MIGRATION_PREFIX-${NVIM_RUNTIME_KINDS[index]}" "${NVIM_RUNTIME_FINGERPRINTS[index]}" "$backup"
    else
      append_migration_ledger "$NVIM_RUNTIME_MIGRATION_PREFIX-${NVIM_RUNTIME_KINDS[index]}" "${NVIM_RUNTIME_FINGERPRINTS[index]}"
    fi
  done
}

apply_nvim() {
  local state_json
  begin_transaction
  retire_nvim_legacy_links
  retire_nvim_transitional_marker
  fault nvim-after-legacy-links
  move_nvim_runtime_roots
  remove_recorded_links_for_apply
  apply_stow_packages
  validate_applied_targets
  fault nvim-after-stow
  state_json="$(build_nvim_state_json)"
  write_transaction_string_atomic "$state_json" "$AREA_STATE" 0600
  fault nvim-after-state
  commit_nvim_migrations
  fault nvim-after-ledger
  TRANSACTION_ACTIVE=false
  log "applied Neovim area for profile '$SELECTED_PROFILE'; plugin restore remains explicit/first-launch"
}

remove_nvim() {
  local state="$HOME/.local/state/dotfiles/v1/nvim.json" count index dir
  local managed_directories=()
  init_nvim_area
  if [[ ! -e "$state" && ! -L "$state" ]]; then log "area 'nvim' is not deployed; no changes made"; return 0; fi
  validate_state_file "$state"
  [[ "$(jq -r .target_root "$state")" == "$TARGET_ROOT" ]] || die 'existing Neovim state belongs to a different target root'
  SELECTED_PROFILE="$(jq -r .profile "$state")"
  count="$(jq '.targets | length' "$state")"
  for ((index=0; index<count; index++)); do validate_recorded_target "$state" "$index"; done
  validate_nvim_state "$state"
  while IFS= read -r dir; do validate_home_directory "$HOME/$dir"; managed_directories+=("$dir"); done < <(jq -r '.managed_directories[]' "$state")
  AREA_STATE="$state"; OLD_STATE=true; TARGET_PATHS=()
  while IFS= read -r dir; do TARGET_PATHS+=("$dir"); done < <(jq -r '.targets[].path' "$state")
  begin_transaction
  for ((index=0; index<count; index++)); do remove_recorded_target "$state" "$index"; done
  fault nvim-remove-after-links
  remove_current_regular_path "$state" 'Neovim area state'
  prune_managed_directories "${managed_directories[@]}"
  TRANSACTION_ACTIVE=false
  log 'removed managed Neovim links and state; retained runtime data, backups, preserved checkouts, credentials, and migration ledger'
}
