# Neovim area: exact Kickstart retirement and one-time XDG runtime preservation.

readonly NVIM_LEGACY_MIGRATION_ID='nvim-kickstart-links-v1'
readonly NVIM_RUNTIME_MIGRATION_PREFIX='nvim-runtime-v1'

# Native Omarchy loader: a regular file wholly owned by bootstrap. Config-dir
# plugin/*.lua files are sourced after init, so personal overrides win over the
# native baseline's options.lua. A native refresh replaces ~/.config/nvim and
# leaves the loader absent; reattachment recreates it from these exact bytes.
readonly NVIM_NATIVE_PATH='.config/nvim/plugin/dotfiles-personal.lua'
readonly NVIM_NATIVE_BEGIN='-- >>> dotfiles nvim >>>'
readonly NVIM_NATIVE_END='-- <<< dotfiles nvim <<<'
readonly NVIM_NATIVE_TOKEN='dotfiles nvim'
readonly NVIM_NATIVE_BLOCK="$NVIM_NATIVE_BEGIN
-- Managed by dotfiles bootstrap; the native Omarchy baseline owns everything else.
local personal = vim.fn.expand('~/.config/dotfiles/nvim/personal.lua')
if (vim.uv or vim.loop).fs_stat(personal) then
  local ok, err = pcall(dofile, personal)
  if not ok then
    vim.schedule(function()
      vim.notify('dotfiles personal layer failed: ' .. tostring(err), vim.log.levels.WARN)
    end)
  end
end
$NVIM_NATIVE_END"

NVIM_NATIVE_ACTION=none
NVIM_NATIVE_ORIGIN=""

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
  NVIM_NATIVE_ACTION=none
  NVIM_NATIVE_ORIGIN=""
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
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    NVIM_EXPECTED_TARGETS=(.config/dotfiles/nvim/personal.lua)
    return 0
  fi
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
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "${PACKAGES[*]}" == 'common/nvim' ]] || \
      die 'native Omarchy Neovim package closure must be exactly common/nvim'
  else
    [[ "${PACKAGES[*]}" == 'upstream/nvim generic/nvim common/nvim' ]] || \
      die 'Neovim package closure must be exactly upstream/generic/common'
  fi
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
  # Native Omarchy deploys no upstream snapshot or lockfile; the installed
  # baseline owns plugins and their lock.
  [[ "$SELECTED_PROFILE" != omarchy ]] || return 0
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
  legacy_manifest_record "$relative" "$relative" nvim retire-kickstart-nvim-links || return 1
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
      .[2] == "nvim" and .[4] == "retire-kickstart-nvim-links" and (.[0] | startswith($prefix)))
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
    legacy_manifest_record '.config/nvim/init.lua' '.config/nvim/init.lua' nvim retire-kickstart-nvim-links || \
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
      select(.[2] == "nvim" and .[4] == "retire-kickstart-nvim-links") | .[0]' "$DOTFILES_DIR/manifests/legacy-links.json")
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

# The loader file is wholly bootstrap-owned: only origin `created` is legal,
# and any bytes outside the guarded block are drift, not host content.
nvim_attachment_preflight() {
  local policy="$1"
  guarded_attachment_preflight "$NVIM_NATIVE_PATH" "$NVIM_NATIVE_BEGIN" "$NVIM_NATIVE_END" "$NVIM_NATIVE_TOKEN" \
    "$NVIM_NATIVE_BLOCK" append "$policy"
  NVIM_NATIVE_ACTION="$GUARDED_ATTACHMENT_ACTION"
  NVIM_NATIVE_ORIGIN="$GUARDED_ATTACHMENT_ORIGIN"
  if [[ "$NVIM_NATIVE_ACTION" == insert ]]; then
    [[ "$NVIM_NATIVE_ORIGIN" == created ]] || \
      die "unrelated file exists at the native Neovim loader path: $HOME/$NVIM_NATIVE_PATH"
  else
    [[ "$(sha256_file "$HOME/$NVIM_NATIVE_PATH")" == "$(sha256_string "$NVIM_NATIVE_BLOCK"$'\n')" ]] || \
      die "native Neovim loader contains unmanaged content: $HOME/$NVIM_NATIVE_PATH"
  fi
}

preflight_new_nvim_attachment() {
  local root="$HOME/.config/nvim"
  validate_home_parent_chain "$root"
  [[ -d "$root" && ! -L "$root" && "$(stat -c %u -- "$root")" == "$EUID" ]] || \
    die "native Omarchy Neovim config is missing or unsafe: $root"
  [[ -f "$root/init.lua" && ! -L "$root/init.lua" ]] || \
    die "native Omarchy Neovim baseline is incomplete: $root/init.lua"
  nvim_attachment_preflight new
}

validate_nvim_state() {
  local state="$1" restored lock target profile id path hash
  profile="$(jq -r .profile "$state")"
  if [[ "$profile" == omarchy ]]; then
    [[ "$(jq '.attachments | length' "$state")" == 1 ]] || \
      die 'native Neovim state does not record exactly one attachment'
    IFS=$'\t' read -r id path hash < <(jq -r '.attachments[0] | [.id,.path,.content_hash] | @tsv' "$state")
    [[ "$id" == nvim-native-loader-v1.created && "$path" == "$NVIM_NATIVE_PATH" && \
      "$hash" == "$(sha256_string "$NVIM_NATIVE_BLOCK")" ]] || \
      die 'native Neovim state records an unknown attachment'
    [[ -z "$(jq -r '.restored_lock_sha256 // empty' "$state")" ]] || \
      die 'native Neovim state records a generic restore marker'
    [[ "$(jq '.backups | length' "$state")" == 0 ]] || die 'native Neovim state records unknown backups'
    nvim_attachment_preflight "$([[ "$MODE" == remove ]] && printf exact || printf new)"
    return 0
  fi
  [[ "$(jq '.attachments | length' "$state")" == 0 ]] || die 'Neovim state records unknown attachments'
  [[ "$profile" == generic || "$profile" == wsl ]] || die 'unknown Neovim state profile'
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
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$OLD_STATE" == true ]] || { log 'pending native Neovim loader: deployment state is absent'; return 1; }
    if [[ "$NVIM_NATIVE_ACTION" == insert ]]; then
      log 'pending native Neovim loader reattachment: apply --area nvim to reattach after the native refresh'
      return 1
    fi
    return 0
  fi
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
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    # The native package owns the baseline, plugins, lock, and runtime state;
    # Kickstart retirement, XDG renames, and restore machinery never run here.
    load_profile_closure nvim
    scan_packages
    validate_nvim_target_inventory
    validate_nvim_payload
    validate_nvim_executable
    record_managed_parents '.local/state/dotfiles/v1/nvim.json'
    AREA_JOURNAL_PATHS+=("$HOME/$NVIM_NATIVE_PATH")
    preflight_existing_state
    [[ "$OLD_STATE" == true ]] || preflight_new_nvim_attachment
    preflight_desired_targets
    run_stow_preflight
    return 0
  fi
  [[ "$SELECTED_PROFILE" == generic || "$SELECTED_PROFILE" == wsl ]] || \
    die "unsupported Neovim profile: $SELECTED_PROFILE"
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
  local attachments='[]' state
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    attachments="$(jq -cn --arg id 'nvim-native-loader-v1.created' --arg path "$NVIM_NATIVE_PATH" \
      --arg hash "$(sha256_string "$NVIM_NATIVE_BLOCK")" '[{id:$id,path:$path,content_hash:$hash}]')"
  fi
  state="$(build_area_state_json nvim "$attachments" "$(nvim_backups_json)")"
  [[ -z "$NVIM_PRESERVED_RESTORE" ]] || state="$(jq -c --arg hash "$NVIM_PRESERVED_RESTORE" '.restored_lock_sha256=$hash' <<< "$state")"
  printf '%s' "$state"
}

install_nvim_attachment() {
  [[ "$SELECTED_PROFILE" == omarchy ]] || return 0
  [[ "$NVIM_NATIVE_ACTION" == insert ]] || return 0
  write_guarded_attachment_only_atomic "$NVIM_NATIVE_PATH" "$NVIM_NATIVE_BLOCK" 0644 absent
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
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    begin_transaction
    apply_area_stow
    fault nvim-after-stow
    install_nvim_attachment
    fault nvim-after-attachment
    state_json="$(build_nvim_state_json)"
    write_transaction_string_atomic "$state_json" "$AREA_STATE" 0600
    fault nvim-after-state
    TRANSACTION_ACTIVE=false
    log "applied Neovim area for profile 'omarchy'; native baseline retained with personal loader"
    return 0
  fi
  begin_transaction
  retire_nvim_legacy_links
  retire_nvim_transitional_marker
  fault nvim-after-legacy-links
  move_nvim_runtime_roots
  apply_area_stow
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
  init_nvim_area
  begin_area_removal nvim restore-profile || return 0
  [[ "$SELECTED_PROFILE" != omarchy ]] || AREA_JOURNAL_PATHS+=("$HOME/$NVIM_NATIVE_PATH")
  begin_transaction
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    remove_guarded_attachment "$NVIM_NATIVE_PATH" "$NVIM_NATIVE_BEGIN" "$NVIM_NATIVE_END" "$NVIM_NATIVE_TOKEN" \
      "$NVIM_NATIVE_BLOCK" append created
    fault nvim-remove-after-attachment
  fi
  remove_recorded_area_targets nvim-remove-after-links
  remove_area_state_and_dirs 'Neovim area state'
  log 'removed managed Neovim links and state; retained runtime data, backups, preserved checkouts, credentials, and migration ledger'
}
