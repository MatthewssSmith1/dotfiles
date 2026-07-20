# tmux area: XDG migration, native attachment, and isolated runtime validation.

readonly TMUX_XDG_MIGRATION_ID='tmux-xdg-config-v1'
readonly TMUX_LEGACY_PATH='.tmux.conf'
readonly TMUX_NATIVE_PATH='.config/tmux/tmux.conf'
readonly TMUX_NATIVE_BEGIN='# >>> dotfiles tmux >>>'
readonly TMUX_NATIVE_END='# <<< dotfiles tmux <<<'
readonly TMUX_NATIVE_TOKEN='dotfiles tmux'
readonly TMUX_NATIVE_BLOCK="$TMUX_NATIVE_BEGIN
if-shell 'test -r \"\$HOME/.config/dotfiles/tmux/persistence.conf\"' \\
  'source-file \"\$HOME/.config/dotfiles/tmux/persistence.conf\"'
$TMUX_NATIVE_END"

TMUX_CLIENT_BIN=""
TMUX_CLIENT_VERSION=""
TMUX_CLIENT_OWNER=""
TMUX_ACTIVE_SERVER_SEEN=false
TMUX_ACTIVE_SERVER_TRANSITION=false
TMUX_ACTIVE_SERVER_SAME_OWNER=false
TMUX_ISOLATED_BIN=""
TMUX_ISOLATED_SOCKET=""
TMUX_ISOLATED_TMPDIR=""
TMUX_ISOLATED_SANDBOX=""
TMUX_ISOLATED_PID=""
TMUX_ISOLATED_PROC_IDENTITY=""
TMUX_PLUGIN_LOCK=""
TMUX_PLUGIN_RECEIPT=""
TMUX_PLUGIN_LOCK_SHA=""
TMUX_PLUGIN_RECEIPT_IDENTITY=""
TMUX_PLUGIN_PLAN_PENDING=false
TMUX_PLUGIN_PLAN_REFUSED=false
TMUX_PLUGIN_TX_ACTIVE=false
TMUX_PLUGIN_TX_COMMITTED=false
TMUX_PLUGIN_RECEIPT_QUARANTINE=""
TMUX_PLUGIN_RECEIPT_QUARANTINE_IDENTITY=""
TMUX_PLUGIN_RECEIPT_INSTALLED_IDENTITY=""
TMUX_PLUGIN_CREATED_DIRS=()
TMUX_PLUGIN_ACTIONS=()
TMUX_PLUGIN_IDS=()
TMUX_PLUGIN_DIRECTORIES=()
TMUX_PLUGIN_REPOSITORIES=()
TMUX_PLUGIN_PREFLIGHT_REPOSITORIES=()
TMUX_PLUGIN_COMMITS=()
TMUX_PLUGIN_TREES=()
TMUX_PLUGIN_PREFLIGHT_IDENTITIES=()
TMUX_PLUGIN_REFUSAL_REASONS=()
TMUX_PLUGIN_STAGES=()
TMUX_PLUGIN_STAGE_IDENTITIES=()
TMUX_PLUGIN_QUARANTINES=()
TMUX_PLUGIN_QUARANTINE_IDENTITIES=()
TMUX_PLUGIN_INSTALLED_IDENTITIES=()

cleanup_before_temp_paths() {
  [[ -z "${TMUX_ISOLATED_BIN:-}" || -z "${TMUX_ISOLATED_SOCKET:-}" || -z "${TMUX_ISOLATED_TMPDIR:-}" ]] || \
    tmux_stop_isolated_validation
}

init_tmux_area() {
  AREA=tmux
  AREA_JOURNAL_PATHS=()
  AREA_ATTACHMENT_VALIDATOR=validate_tmux_attachments_from_state
  TMUX_NATIVE_ORIGIN=""
  TMUX_NATIVE_ACTION=none
  TMUX_LEGACY_ACTION=none
  TMUX_LEGACY_SOURCE=""
  TMUX_LEGACY_IDENTITY=""
  TMUX_LEGACY_FINGERPRINT=""
  TMUX_ACTIVE_SERVER_SEEN=false
  TMUX_ACTIVE_SERVER_TRANSITION=false
  TMUX_ACTIVE_SERVER_SAME_OWNER=false
  register_migration_ledger_journal
}

tmux_expected_targets() {
  case "$SELECTED_PROFILE" in
    generic)
      TMUX_EXPECTED_TARGETS=(
        .config/dotfiles/upstream/tmux/tmux.conf
        .config/dotfiles/tmux/generic.conf
        .config/dotfiles/tmux/persistence.conf
        .config/tmux/tmux.conf
      )
      ;;
    wsl)
      TMUX_EXPECTED_TARGETS=(
        .config/dotfiles/upstream/tmux/tmux.conf
        .config/dotfiles/tmux/generic.conf
        .config/dotfiles/tmux/persistence.conf
        .config/dotfiles/tmux/wsl.conf
        .config/tmux/tmux.conf
      )
      ;;
    omarchy) TMUX_EXPECTED_TARGETS=(.config/dotfiles/tmux/persistence.conf) ;;
    *) die "unsupported tmux profile: $SELECTED_PROFILE" ;;
  esac
}

validate_tmux_target_inventory() {
  local relative expected actual
  local -A expected_map=() actual_map=()
  tmux_expected_targets
  for relative in "${TMUX_EXPECTED_TARGETS[@]}"; do
    [[ -z "${expected_map[$relative]+x}" ]] || die "duplicate expected tmux target: $relative"
    expected_map["$relative"]=1
  done
  for relative in "${TARGET_PATHS[@]}"; do actual_map["$relative"]=1; done
  for expected in "${TMUX_EXPECTED_TARGETS[@]}"; do
    [[ -n "${actual_map[$expected]+x}" ]] || die "tmux package closure is missing expected target: $expected"
  done
  for actual in "${TARGET_PATHS[@]}"; do
    [[ -n "${expected_map[$actual]+x}" ]] || die "tmux package closure contains unexpected target: $actual"
  done
  ((${#TARGET_PATHS[@]} == ${#TMUX_EXPECTED_TARGETS[@]})) || die 'tmux package target inventory is not unique'
}

validate_tmux_plugin_lock() {
  local lock="$DOTFILES_DIR/manifests/tmux-plugins.lock.json"
  local schema="$DOTFILES_DIR/schemas/tmux-plugin-lock-v1.schema.json"
  local persistence="$DOTFILES_DIR/packages/common/tmux/.config/dotfiles/tmux/persistence.conf"
  local line declaration
  local persistence_declarations=() lock_declarations=() persistence_hooks=() lock_hooks=()

  [[ -f "$schema" && ! -L "$schema" && -f "$lock" && ! -L "$lock" ]] || die 'tmux plugin lock or schema is missing'
  jq -e '
    type == "object" and
    keys == ["$schema","area","plugin_root","plugins","provision_command","resurrect_root","retained_paths","schema_version"] and
    .["$schema"] == "../schemas/tmux-plugin-lock-v1.schema.json" and .schema_version == 1 and .area == "tmux" and
    .plugin_root == ".tmux/plugins" and .resurrect_root == ".tmux/resurrect" and
    .provision_command == ["bootstrap.sh","--provision","--area","tmux"] and
    .retained_paths == [".tmux/plugins",".tmux/resurrect"] and
    (.plugins | type == "array" and length == 4 and all(.[];
      type == "object" and
      (.id | test("^[a-z0-9]+(-[a-z0-9]+)*$")) and (.role == "manager" or .role == "plugin") and
      (.repository | test("^https://github[.]com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$")) and
      (.commit | test("^[0-9a-f]{40}$")) and
      (.directory | test("^[A-Za-z0-9._-]+$")) and (.directory != "." and .directory != "..") and
      (if .loading == "tpm" then
        keys == ["commit","declaration","directory","id","loading","repository","role"] and
        (.declaration | test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"))
       elif .loading == "managed-hooks" then
        keys == ["commit","directory","hooks","id","loading","repository","role"] and
        .id == "tmux-assistant-resurrect" and .role == "plugin" and
        .hooks == {"@resurrect-hook-post-save-all":"scripts/save-assistant-sessions.sh",
          "@resurrect-hook-post-restore-all":"scripts/restore-assistant-sessions.sh"}
       else false end))) and
    ([.plugins[].id] | unique | length) == (.plugins | length) and
    ([.plugins[].directory] | unique | length) == (.plugins | length) and
    [.plugins[].id] == ["tpm","tmux-resurrect","tmux-assistant-resurrect","tmux-continuum"] and
    [.plugins[].loading] == ["tpm","tpm","managed-hooks","tpm"] and
    .plugins[0].role == "manager" and .plugins[-1].id == "tmux-continuum"
  ' "$lock" >/dev/null || die 'malformed or unknown tmux plugin lock'
  [[ -f "$persistence" && ! -L "$persistence" ]] || die 'missing tmux persistence payload'
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" == *'@plugin'* ]]; then
      if [[ "$line" =~ ^[[:space:]]*set[[:space:]]+-g[[:space:]]+@plugin[[:space:]]+\'([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)\'[[:space:]]*$ ]]; then
        persistence_declarations+=("${BASH_REMATCH[1]}")
      else
        die "malformed tmux persistence plugin declaration: $line"
      fi
    elif [[ "$line" == *'@resurrect-hook-'* ]]; then
      case "$line" in
        'set -g @resurrect-hook-post-save-all "bash \"$HOME/.tmux/plugins/tmux-assistant-resurrect/scripts/save-assistant-sessions.sh\""')
          persistence_hooks+=('@resurrect-hook-post-save-all|scripts/save-assistant-sessions.sh') ;;
        'set -g @resurrect-hook-post-restore-all "bash \"$HOME/.tmux/plugins/tmux-assistant-resurrect/scripts/restore-assistant-sessions.sh\""')
          persistence_hooks+=('@resurrect-hook-post-restore-all|scripts/restore-assistant-sessions.sh') ;;
        *) die "malformed or unmanaged tmux Resurrect hook declaration: $line" ;;
      esac
    fi
  done < "$persistence"
  mapfile -t lock_declarations < <(jq -r '.plugins[] | select(.loading == "tpm") | .declaration' "$lock")
  [[ "${#persistence_declarations[@]}" == "${#lock_declarations[@]}" ]] || \
    die 'tmux persistence plugin declaration inventory differs from the lock'
  for declaration in "${!lock_declarations[@]}"; do
    [[ "${persistence_declarations[declaration]}" == "${lock_declarations[declaration]}" ]] || \
      die 'tmux persistence plugin declarations differ in identity or order from the lock'
  done
  mapfile -t lock_hooks < <(jq -r '.plugins[] | select(.loading == "managed-hooks") | .hooks |
    to_entries | sort_by(if .key == "@resurrect-hook-post-save-all" then 0 else 1 end) | .[] | [.key,.value] | join("|")' "$lock")
  [[ "${persistence_hooks[*]}" == "${lock_hooks[*]}" && ${#persistence_hooks[@]} -eq 2 ]] || \
    die 'tmux managed Resurrect hooks differ in identity or order from the lock'
}

tmux_git() {
  env -i HOME=/nonexistent PATH=/usr/bin:/bin LC_ALL=C GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false /usr/bin/git \
    -c core.fsmonitor=false -c core.hooksPath=/dev/null -c credential.helper= \
    -c protocol.allow=never -c protocol.https.allow=always "$@"
}

tmux_git_readonly() {
  GIT_OPTIONAL_LOCKS=0 tmux_git "$@"
}

tmux_init_plugin_contract() {
  TMUX_PLUGIN_LOCK="$DOTFILES_DIR/manifests/tmux-plugins.lock.json"
  TMUX_PLUGIN_RECEIPT="$HOME/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
  TMUX_PLUGIN_LOCK_SHA="$(sha256_file "$TMUX_PLUGIN_LOCK")"
}

tmux_existing_home_chain_owned() {
  local path="$1" relative parent current component
  local components=()
  [[ "$path" == "$HOME/"* ]] || return 1
  parent="${path%/*}"; relative="${parent#"$HOME"/}"; current="$HOME"
  [[ "$parent" != "$HOME" ]] || return 0
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    current="$current/$component"
    [[ -e "$current" || -L "$current" ]] || continue
    [[ -d "$current" && ! -L "$current" && "$(stat -c %u -- "$current")" == "$EUID" ]] || return 1
  done
}

validate_tmux_plugin_receipt() {
  local before after receipt_hash schema="$DOTFILES_DIR/schemas/tmux-plugin-receipt-v1.schema.json"
  tmux_init_plugin_contract
  [[ -f "$schema" && ! -L "$schema" ]] || die 'missing tmux plugin receipt schema'
  jq -e '.properties.schema_version.const == 1' "$schema" >/dev/null 2>&1 || \
    die 'invalid tmux plugin receipt schema'
  validate_home_parent_chain "$TMUX_PLUGIN_RECEIPT"
  tmux_existing_home_chain_owned "$TMUX_PLUGIN_RECEIPT" || \
    die 'tmux plugin receipt has an unsafe managed parent'
  TMUX_PLUGIN_RECEIPT_IDENTITY=absent
  [[ -e "$TMUX_PLUGIN_RECEIPT" || -L "$TMUX_PLUGIN_RECEIPT" ]] || return 0
  [[ -f "$TMUX_PLUGIN_RECEIPT" && ! -L "$TMUX_PLUGIN_RECEIPT" ]] || \
    die 'tmux plugin receipt is symlinked or not a regular file'
  [[ "$(stat -c %u -- "$TMUX_PLUGIN_RECEIPT")" == "$EUID" ]] || \
    die 'tmux plugin receipt has an unsafe owner'
  [[ "$(stat -c %a -- "$TMUX_PLUGIN_RECEIPT")" == 600 ]] || \
    die 'tmux plugin receipt has an unsafe mode'
  capture_path_identity "$TMUX_PLUGIN_RECEIPT" || die 'tmux plugin receipt changed before validation'
  before="$PATH_IDENTITY"
  jq -e '
    type == "object" and keys == ["lock_sha256","plugins","schema_version"] and
    .schema_version == 1 and (.lock_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.plugins | type == "array" and all(.[];
      type == "object" and keys == ["commit","directory","id","repository","tree"] and
      (.id | type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
      (.repository | type == "string" and test("^https://github[.]com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$")) and
      (.commit | type == "string" and test("^[0-9a-f]{40}$")) and
      (.tree | type == "string" and test("^[0-9a-f]{40}$")) and
      (.directory | type == "string" and test("^[A-Za-z0-9._-]+$")) and
      (.directory != "." and .directory != "..")) and
      ([.[].id] | unique | length) == length and ([.[].directory] | unique | length) == length)
  ' "$TMUX_PLUGIN_RECEIPT" >/dev/null || die 'malformed or newer tmux plugin receipt'
  receipt_hash="$(jq -r .lock_sha256 "$TMUX_PLUGIN_RECEIPT")"
  if [[ "$receipt_hash" == "$TMUX_PLUGIN_LOCK_SHA" ]]; then
    jq -e --slurpfile lock "$TMUX_PLUGIN_LOCK" '
      (.plugins | map({id,repository,commit,directory})) ==
      ($lock[0].plugins | map({id,repository,commit,directory}))
    ' "$TMUX_PLUGIN_RECEIPT" >/dev/null || die 'tmux plugin receipt metadata is corrupt for the active lock'
  else
    die 'tmux plugin receipt lock identity is not the active known lock'
  fi
  capture_path_identity "$TMUX_PLUGIN_RECEIPT" || die 'tmux plugin receipt changed during validation'
  after="$PATH_IDENTITY"
  [[ "$after" == "$before" ]] || die 'tmux plugin receipt changed during validation'
  TMUX_PLUGIN_RECEIPT_IDENTITY="$after"
}

tmux_plugin_paths_safe() {
  local root="$1" path unsafe
  validate_home_parent_chain "$root"
  for path in "$HOME/.tmux" "$HOME/.tmux/plugins"; do
    [[ -e "$path" || -L "$path" ]] || continue
    [[ -d "$path" && ! -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" ]] || return 1
  done
  [[ -e "$root" || -L "$root" ]] || return 0
  [[ -d "$root" && ! -L "$root" ]] || return 1
  unsafe="$(/usr/bin/find "$root" -xdev ! -uid "$EUID" -print -quit 2>/dev/null)" || return 1
  [[ -z "$unsafe" ]]
}

tmux_inspect_plugin_checkout() {
  local path="$1" expected_repository="$2" value status_output superproject
  local remotes=() urls=()
  TMUX_CHECKOUT_HEAD=""; TMUX_CHECKOUT_TREE=""; TMUX_CHECKOUT_IDENTITY=""; TMUX_CHECKOUT_ERROR=""
  validate_home_parent_chain "$path"
  [[ -d "$path" && ! -L "$path" && -d "$path/.git" && ! -L "$path/.git" ]] || {
    TMUX_CHECKOUT_ERROR='is not an ordinary non-symlinked checkout'; return 1;
  }
  tmux_plugin_paths_safe "$path" || { TMUX_CHECKOUT_ERROR='has unsafe ownership or a symlinked managed path'; return 1; }
  [[ "$(tmux_git_readonly -C "$path" rev-parse --is-inside-work-tree 2>/dev/null)" == true &&
    "$(tmux_git_readonly -C "$path" rev-parse --is-bare-repository 2>/dev/null)" == false ]] || {
    TMUX_CHECKOUT_ERROR='has invalid worktree topology'; return 1;
  }
  value="$(tmux_git_readonly -C "$path" rev-parse --show-toplevel 2>/dev/null)" || {
    TMUX_CHECKOUT_ERROR='has unreadable worktree topology'; return 1;
  }
  [[ "$(realpath -e -- "$value")" == "$(realpath -e -- "$path")" ]] || {
    TMUX_CHECKOUT_ERROR='is not its own worktree root'; return 1;
  }
  value="$(tmux_git_readonly -C "$path" rev-parse --absolute-git-dir 2>/dev/null)" || {
    TMUX_CHECKOUT_ERROR='has an unreadable Git directory'; return 1;
  }
  [[ "$(realpath -e -- "$value")" == "$(realpath -e -- "$path/.git")" ]] || {
    TMUX_CHECKOUT_ERROR='uses linked or external Git metadata'; return 1;
  }
  value="$(tmux_git_readonly -C "$path" rev-parse --git-common-dir 2>/dev/null)" || return 1
  [[ "$(realpath -e -- "$path/$value")" == "$(realpath -e -- "$path/.git")" ]] || {
    TMUX_CHECKOUT_ERROR='uses a non-ordinary common Git directory'; return 1;
  }
  superproject="$(tmux_git_readonly -C "$path" rev-parse --show-superproject-working-tree 2>/dev/null)" || return 1
  [[ -z "$superproject" ]] || { TMUX_CHECKOUT_ERROR='is a linked submodule worktree'; return 1; }
  mapfile -t remotes < <(tmux_git_readonly -C "$path" remote 2>/dev/null) || return 1
  ((${#remotes[@]} == 1)) && [[ "${remotes[0]}" == origin ]] || {
    TMUX_CHECKOUT_ERROR='does not have origin as its only remote'; return 1;
  }
  mapfile -t urls < <(tmux_git_readonly -C "$path" remote get-url --all origin 2>/dev/null) || return 1
  ((${#urls[@]} == 1)) && [[ "${urls[0]}" == "$expected_repository" ]] || {
    TMUX_CHECKOUT_ERROR='has unknown, noncanonical, or ambiguous origin metadata'; return 1;
  }
  TMUX_CHECKOUT_HEAD="$(tmux_git_readonly -C "$path" rev-parse --verify HEAD 2>/dev/null)" || {
    TMUX_CHECKOUT_ERROR='has an unreadable HEAD'; return 1;
  }
  TMUX_CHECKOUT_TREE="$(tmux_git_readonly -C "$path" rev-parse --verify 'HEAD^{tree}' 2>/dev/null)" || {
    TMUX_CHECKOUT_ERROR='has an unreadable tree'; return 1;
  }
  status_output="$(tmux_git_readonly -C "$path" status --porcelain=v1 --untracked-files=all --ignore-submodules=none 2>/dev/null)" || {
    TMUX_CHECKOUT_ERROR='has unreadable worktree status'; return 1;
  }
  [[ -z "$status_output" ]] || { TMUX_CHECKOUT_ERROR='is dirty, including untracked files or submodule drift'; return 1; }
  value="$(stat -c '%d|%i|%u|%a' -- "$path")|$(stat -c '%d|%i|%u|%a' -- "$path/.git")|$expected_repository|$TMUX_CHECKOUT_HEAD|$TMUX_CHECKOUT_TREE|$status_output"
  TMUX_CHECKOUT_IDENTITY="$(sha256_string "$value")"
}

tmux_reviewed_legacy_repository() {
  local repository="$1"
  [[ "$repository" =~ ^https://github[.]com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)$ ]] || return 1
  printf 'https://git::@github.com/%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

tmux_validate_managed_hook_scripts() {
  local root="$1" directory script path
  while IFS=$'\t' read -r directory script; do
    path="$root/$directory/$script"
    [[ -f "$path" && ! -L "$path" && -x "$path" && "$(stat -c %u -- "$path")" == "$EUID" ]] || {
      log "error: managed tmux assistant hook is missing or unsafe: $path"
      return 1
    }
  done < <(jq -r '.plugins[] | select(.loading == "managed-hooks") | .directory as $directory |
    .hooks | to_entries[] | [$directory,.value] | @tsv' "$TMUX_PLUGIN_LOCK")
}

tmux_receipt_tree_for_id() {
  local id="$1"
  [[ -f "$TMUX_PLUGIN_RECEIPT" ]] || return 1
  jq -er --arg id "$id" '.plugins[] | select(.id == $id) | .tree' "$TMUX_PLUGIN_RECEIPT" 2>/dev/null
}

tmux_validate_plugin_root_entries() {
  local allow_missing="$1" root="$HOME/$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")" path base
  local expected=() actual=()
  mapfile -t expected < <(jq -r '.plugins[].directory' "$TMUX_PLUGIN_LOCK")
  [[ -d "$root" && ! -L "$root" ]] || [[ "$allow_missing" == true ]] || {
    log "error: exact tmux plugin closure is missing: $root"; return 1;
  }
  [[ -d "$root" && ! -L "$root" ]] || return 0
  shopt -s dotglob nullglob
  for path in "$root"/*; do actual+=("${path##*/}"); done
  shopt -u dotglob nullglob
  for base in "${actual[@]}"; do
    array_contains "$base" "${expected[@]}" || {
      log "error: unexpected tmux plugin closure entry: $base"; return 1;
    }
  done
  if [[ "$allow_missing" == false && ${#actual[@]} -ne ${#expected[@]} ]]; then
    log 'error: tmux plugin closure has missing entries'
    return 1
  fi
}

tmux_validate_exact_plugin_closure() {
  local root path id directory repository commit expected_tree receipt_hash
  validate_tmux_plugin_lock
  validate_tmux_plugin_receipt
  receipt_hash="$(jq -r .lock_sha256 "$TMUX_PLUGIN_RECEIPT" 2>/dev/null || true)"
  [[ "$receipt_hash" == "$TMUX_PLUGIN_LOCK_SHA" ]] || {
    log 'error: exact tmux plugin closure has no receipt for the active lock'; return 1;
  }
  root="$HOME/$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")"
  tmux_plugin_paths_safe "$root" || { log 'error: tmux plugin root has unsafe ownership or topology'; return 1; }
  tmux_validate_plugin_root_entries false || return 1
  while IFS=$'\t' read -r id directory repository commit; do
    path="$root/$directory"
    tmux_inspect_plugin_checkout "$path" "$repository" || {
      log "error: tmux plugin $id $TMUX_CHECKOUT_ERROR: $path"; return 1;
    }
    [[ "$TMUX_CHECKOUT_HEAD" == "$commit" ]] || {
      log "error: tmux plugin commit drift: $path"; return 1;
    }
    expected_tree="$(tmux_receipt_tree_for_id "$id")" || {
      log "error: tmux plugin receipt has no tree for $id"; return 1;
    }
    [[ "$TMUX_CHECKOUT_TREE" == "$expected_tree" ]] || {
      log "error: tmux plugin tree differs from its receipt: $path"; return 1;
    }
  done < <(jq -r '.plugins[] | [.id,.directory,.repository,.commit] | @tsv' "$TMUX_PLUGIN_LOCK")
  tmux_validate_managed_hook_scripts "$root" || return 1
  [[ "$(sha256_file "$TMUX_PLUGIN_LOCK")" == "$TMUX_PLUGIN_LOCK_SHA" ]] || {
    log 'error: tmux plugin lock changed during closure validation'; return 1;
  }
}

tmux_preflight_plugin_provision_plan() {
  local root path id directory repository legacy_repository preflight_repository commit receipt_hash receipt_tree action reason root_refusal="" root_inspectable=true
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_TMUX_PLUGIN_PLAN_STATUS:-}" ]]; then
    case "$DOTFILES_TEST_TMUX_PLUGIN_PLAN_STATUS" in 70|130|143) return "$DOTFILES_TEST_TMUX_PLUGIN_PLAN_STATUS" ;; esac
    die 'DOTFILES_TEST_TMUX_PLUGIN_PLAN_STATUS must be 70, 130, or 143'
  fi
  validate_tmux_plugin_lock
  validate_tmux_plugin_receipt
  root="$HOME/$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")"
  if ! tmux_plugin_paths_safe "$root"; then
    log 'error: tmux plugin root has unsafe ownership or topology'
    root_refusal='plugin root has unsafe ownership or topology'
    root_inspectable=false
  elif ! tmux_validate_plugin_root_entries true; then
    root_refusal='plugin root contains an unexpected entry'
    root_inspectable=false
  fi
  receipt_hash="$(jq -r .lock_sha256 "$TMUX_PLUGIN_RECEIPT" 2>/dev/null || true)"
  TMUX_PLUGIN_PLAN_PENDING=false
  TMUX_PLUGIN_PLAN_REFUSED=false
  TMUX_PLUGIN_ACTIONS=(); TMUX_PLUGIN_IDS=(); TMUX_PLUGIN_DIRECTORIES=(); TMUX_PLUGIN_REPOSITORIES=()
  TMUX_PLUGIN_PREFLIGHT_REPOSITORIES=()
  TMUX_PLUGIN_COMMITS=(); TMUX_PLUGIN_TREES=(); TMUX_PLUGIN_PREFLIGHT_IDENTITIES=(); TMUX_PLUGIN_REFUSAL_REASONS=()
  TMUX_PLUGIN_STAGES=(); TMUX_PLUGIN_STAGE_IDENTITIES=(); TMUX_PLUGIN_QUARANTINES=()
  TMUX_PLUGIN_QUARANTINE_IDENTITIES=(); TMUX_PLUGIN_INSTALLED_IDENTITIES=()
  while IFS=$'\t' read -r id directory repository commit; do
    path="$root/$directory"; action=install; receipt_tree=""; reason=""; preflight_repository="$repository"
    if [[ "$root_inspectable" == false ]]; then
      action=refuse; reason="$root_refusal"
      TMUX_PLUGIN_TREES+=(""); TMUX_PLUGIN_PREFLIGHT_IDENTITIES+=(absent)
    elif [[ -e "$path" || -L "$path" ]]; then
      if ! tmux_inspect_plugin_checkout "$path" "$repository"; then
        legacy_repository="$(tmux_reviewed_legacy_repository "$repository")"
        if [[ "$TMUX_CHECKOUT_ERROR" == 'has unknown, noncanonical, or ambiguous origin metadata' ]] &&
          tmux_inspect_plugin_checkout "$path" "$legacy_repository"; then
          action=normalize-origin
          preflight_repository="$legacy_repository"
          reason='reviewed legacy https://git::@github.com origin requires staged canonical replacement'
          TMUX_PLUGIN_TREES+=("$TMUX_CHECKOUT_TREE")
          TMUX_PLUGIN_PREFLIGHT_IDENTITIES+=("$TMUX_CHECKOUT_IDENTITY")
        else
          reason="$TMUX_CHECKOUT_ERROR"
          log "error: refusing tmux plugin $id because it $reason: $path"
          action=refuse
          TMUX_PLUGIN_TREES+=(""); TMUX_PLUGIN_PREFLIGHT_IDENTITIES+=("")
        fi
      else
        if [[ "$TMUX_CHECKOUT_HEAD" == "$commit" ]]; then
          if [[ "$receipt_hash" == "$TMUX_PLUGIN_LOCK_SHA" ]]; then
            receipt_tree="$(tmux_receipt_tree_for_id "$id")" || {
              reason='active receipt entry is missing'; action=refuse;
            }
            if [[ "$action" != refuse && "$TMUX_CHECKOUT_TREE" != "$receipt_tree" ]]; then
              reason='active receipt tree is corrupt'; action=refuse
              log "error: active tmux plugin receipt tree is corrupt for $id"
            elif [[ "$action" != refuse ]]; then
              action=exact
            fi
          else
            action=adopt
          fi
        else
          action=replace
        fi
        TMUX_PLUGIN_TREES+=("$TMUX_CHECKOUT_TREE")
        TMUX_PLUGIN_PREFLIGHT_IDENTITIES+=("$TMUX_CHECKOUT_IDENTITY")
      fi
    else
      TMUX_PLUGIN_TREES+=("")
      TMUX_PLUGIN_PREFLIGHT_IDENTITIES+=(absent)
    fi
    if [[ "$action" == refuse ]]; then TMUX_PLUGIN_PLAN_REFUSED=true; fi
    case "$action" in install|replace|normalize-origin|adopt) TMUX_PLUGIN_PLAN_PENDING=true ;; esac
    TMUX_PLUGIN_ACTIONS+=("$action"); TMUX_PLUGIN_IDS+=("$id"); TMUX_PLUGIN_DIRECTORIES+=("$directory")
    TMUX_PLUGIN_REPOSITORIES+=("$repository"); TMUX_PLUGIN_COMMITS+=("$commit")
    TMUX_PLUGIN_PREFLIGHT_REPOSITORIES+=("$preflight_repository")
    TMUX_PLUGIN_REFUSAL_REASONS+=("$reason")
    TMUX_PLUGIN_STAGES+=(""); TMUX_PLUGIN_STAGE_IDENTITIES+=(""); TMUX_PLUGIN_QUARANTINES+=("")
    TMUX_PLUGIN_QUARANTINE_IDENTITIES+=(""); TMUX_PLUGIN_INSTALLED_IDENTITIES+=("")
  done < <(jq -r '.plugins[] | [.id,.directory,.repository,.commit] | @tsv' "$TMUX_PLUGIN_LOCK")
  [[ "$(sha256_file "$TMUX_PLUGIN_LOCK")" == "$TMUX_PLUGIN_LOCK_SHA" ]] || \
    die 'tmux plugin lock changed during plan construction'
  if [[ -n "$root_refusal" ]]; then TMUX_PLUGIN_PLAN_REFUSED=true; fi
  [[ "$TMUX_PLUGIN_PLAN_REFUSED" == false ]]
}

print_tmux_plugin_provisioning_plan() {
  local index action network
  log 'tmux plugin plan (offline classification):'
  for index in "${!TMUX_PLUGIN_IDS[@]}"; do
    action="${TMUX_PLUGIN_ACTIONS[index]}"; network=none
    [[ "$action" != install && "$action" != replace && "$action" != normalize-origin ]] || network=fetch-exact-depth-1
    printf '  %s: action=%s network=%s repository=%s commit=%s destination=~/%s/%s\n' \
      "${TMUX_PLUGIN_IDS[index]}" "$action" "$network" "${TMUX_PLUGIN_REPOSITORIES[index]}" \
      "${TMUX_PLUGIN_COMMITS[index]}" "$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")" \
      "${TMUX_PLUGIN_DIRECTORIES[index]}"
    [[ -z "${TMUX_PLUGIN_REFUSAL_REASONS[index]}" ]] || \
      printf '    refusal=%s\n' "${TMUX_PLUGIN_REFUSAL_REASONS[index]}"
  done
}

tmux_plugin_create_directory_chain() {
  local dir="$1" relative current component
  local components=()
  validate_home_directory "$dir"
  relative="${dir#"$HOME"/}"; current="$HOME"
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    current="$current/$component"
    if [[ -e "$current" || -L "$current" ]]; then
      [[ -d "$current" && ! -L "$current" && "$(stat -c %u -- "$current")" == "$EUID" ]] || \
        die "unsafe tmux plugin transaction directory: $current"
    else
      mkdir -m 0700 -- "$current"
      TMUX_PLUGIN_CREATED_DIRS+=("$current")
    fi
  done
}

tmux_stage_locked_plugin() {
  local index="$1" root stage repository commit
  root="$HOME/$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")"
  repository="${TMUX_PLUGIN_REPOSITORIES[index]}"; commit="${TMUX_PLUGIN_COMMITS[index]}"
  stage="$(mktemp -d "$root/.${TMUX_PLUGIN_DIRECTORIES[index]}.dotfiles-stage.XXXXXX")"
  chmod 0700 "$stage"
  track_temp_path "$stage"
  TMUX_PLUGIN_STAGES[index]="$stage"
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_TMUX_FETCH:-}" ]]; then
    [[ "$DOTFILES_TEST_TMUX_FETCH" == /* && -x "$DOTFILES_TEST_TMUX_FETCH" ]] || \
      die 'DOTFILES_TEST_TMUX_FETCH must be an absolute executable'
    "$DOTFILES_TEST_TMUX_FETCH" "$repository" "$commit" "$stage"
  else
    tmux_git -C "$stage" init --initial-branch=dotfiles-staging
    tmux_git -C "$stage" remote add origin "$repository"
    tmux_git -C "$stage" fetch --no-tags --no-recurse-submodules --depth=1 origin "$commit"
    tmux_git -C "$stage" checkout --detach "$commit"
  fi
  tmux_inspect_plugin_checkout "$stage" "$repository" || \
    die "staged tmux plugin ${TMUX_PLUGIN_IDS[index]} $TMUX_CHECKOUT_ERROR"
  [[ "$TMUX_CHECKOUT_HEAD" == "$commit" ]] || die "staged tmux plugin ${TMUX_PLUGIN_IDS[index]} has the wrong commit"
  if [[ -f "$TMUX_PLUGIN_RECEIPT" && "$(jq -r .lock_sha256 "$TMUX_PLUGIN_RECEIPT")" == "$TMUX_PLUGIN_LOCK_SHA" ]]; then
    local receipt_tree
    receipt_tree="$(tmux_receipt_tree_for_id "${TMUX_PLUGIN_IDS[index]}")"
    [[ "$TMUX_CHECKOUT_TREE" == "$receipt_tree" ]] || \
      die "active tmux plugin receipt tree is corrupt for ${TMUX_PLUGIN_IDS[index]}"
  fi
  TMUX_PLUGIN_TREES[index]="$TMUX_CHECKOUT_TREE"
  TMUX_PLUGIN_STAGE_IDENTITIES[index]="$TMUX_CHECKOUT_IDENTITY"
}

tmux_plugin_allocate_quarantine() {
  local path="$1" candidate
  candidate="$(mktemp -d "${path%/*}/.${path##*/}.dotfiles-quarantine.XXXXXX")"
  rmdir -- "$candidate"
  printf '%s' "$candidate"
}

tmux_plugin_quarantine_replacements() {
  local index root path quarantine
  root="$HOME/$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")"
  for index in "${!TMUX_PLUGIN_IDS[@]}"; do
    case "${TMUX_PLUGIN_ACTIONS[index]}" in replace|normalize-origin) ;; *) continue ;; esac
    path="$root/${TMUX_PLUGIN_DIRECTORIES[index]}"
    tmux_inspect_plugin_checkout "$path" "${TMUX_PLUGIN_PREFLIGHT_REPOSITORIES[index]}" || \
      die "tmux plugin ${TMUX_PLUGIN_IDS[index]} changed before quarantine: $TMUX_CHECKOUT_ERROR"
    [[ "$TMUX_CHECKOUT_IDENTITY" == "${TMUX_PLUGIN_PREFLIGHT_IDENTITIES[index]}" ]] || \
      die "tmux plugin ${TMUX_PLUGIN_IDS[index]} changed before quarantine"
    quarantine="$(tmux_plugin_allocate_quarantine "$path")"
    mv -nT -- "$path" "$quarantine" 2>/dev/null || \
      die "tmux plugin ${TMUX_PLUGIN_IDS[index]} could not be quarantined without clobber"
    [[ ! -e "$path" && ! -L "$path" && -d "$quarantine" ]] || \
      die "tmux plugin ${TMUX_PLUGIN_IDS[index]} changed during quarantine"
    TMUX_PLUGIN_QUARANTINES[index]="$quarantine"
    TMUX_PLUGIN_QUARANTINE_IDENTITIES[index]="${TMUX_PLUGIN_PREFLIGHT_IDENTITIES[index]}"
    tmux_inspect_plugin_checkout "$quarantine" "${TMUX_PLUGIN_PREFLIGHT_REPOSITORIES[index]}" || \
      die "quarantined tmux plugin ${TMUX_PLUGIN_IDS[index]} $TMUX_CHECKOUT_ERROR"
    [[ "$TMUX_CHECKOUT_IDENTITY" == "${TMUX_PLUGIN_PREFLIGHT_IDENTITIES[index]}" ]] || \
      die "quarantined tmux plugin ${TMUX_PLUGIN_IDS[index]} changed identity"
  done
}

tmux_plugin_install_stages() {
  local index root path stage
  root="$HOME/$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")"
  for index in "${!TMUX_PLUGIN_IDS[@]}"; do
    case "${TMUX_PLUGIN_ACTIONS[index]}" in install|replace|normalize-origin) ;; *) continue ;; esac
    path="$root/${TMUX_PLUGIN_DIRECTORIES[index]}"; stage="${TMUX_PLUGIN_STAGES[index]}"
    [[ ! -e "$path" && ! -L "$path" ]] || \
      die "tmux plugin destination appeared before no-clobber install: $path"
    tmux_inspect_plugin_checkout "$stage" "${TMUX_PLUGIN_REPOSITORIES[index]}" || \
      die "staged tmux plugin ${TMUX_PLUGIN_IDS[index]} changed before install: $TMUX_CHECKOUT_ERROR"
    [[ "$TMUX_CHECKOUT_IDENTITY" == "${TMUX_PLUGIN_STAGE_IDENTITIES[index]}" ]] || \
      die "staged tmux plugin ${TMUX_PLUGIN_IDS[index]} changed before install"
    mv -nT -- "$stage" "$path" 2>/dev/null || \
      die "tmux plugin ${TMUX_PLUGIN_IDS[index]} could not be installed without clobber"
    [[ ! -e "$stage" && ! -L "$stage" && -d "$path" ]] || \
      die "tmux plugin destination appeared concurrently: $path"
    TMUX_PLUGIN_STAGES[index]=""
    TMUX_PLUGIN_INSTALLED_IDENTITIES[index]="${TMUX_PLUGIN_STAGE_IDENTITIES[index]}"
    tmux_inspect_plugin_checkout "$path" "${TMUX_PLUGIN_REPOSITORIES[index]}" || \
      die "installed tmux plugin ${TMUX_PLUGIN_IDS[index]} $TMUX_CHECKOUT_ERROR"
    [[ "$TMUX_CHECKOUT_HEAD" == "${TMUX_PLUGIN_COMMITS[index]}" &&
      "$TMUX_CHECKOUT_TREE" == "${TMUX_PLUGIN_TREES[index]}" &&
      "$TMUX_CHECKOUT_IDENTITY" == "${TMUX_PLUGIN_STAGE_IDENTITIES[index]}" ]] || \
      die "installed tmux plugin ${TMUX_PLUGIN_IDS[index]} differs from staging"
  done
}

tmux_verify_plugin_transaction_closure() {
  local index root path base allowed
  local entries=()
  root="$HOME/$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")"
  for index in "${!TMUX_PLUGIN_IDS[@]}"; do
    path="$root/${TMUX_PLUGIN_DIRECTORIES[index]}"
    tmux_inspect_plugin_checkout "$path" "${TMUX_PLUGIN_REPOSITORIES[index]}" || return 1
    [[ "$TMUX_CHECKOUT_HEAD" == "${TMUX_PLUGIN_COMMITS[index]}" &&
      "$TMUX_CHECKOUT_TREE" == "${TMUX_PLUGIN_TREES[index]}" ]] || return 1
  done
  tmux_validate_managed_hook_scripts "$root" || return 1
  shopt -s dotglob nullglob
  for path in "$root"/*; do entries+=("$path"); done
  shopt -u dotglob nullglob
  for path in "${entries[@]}"; do
    base="${path##*/}"; allowed=false
    array_contains "$base" "${TMUX_PLUGIN_DIRECTORIES[@]}" && allowed=true
    array_contains "$path" "${TMUX_PLUGIN_QUARANTINES[@]}" && allowed=true
    [[ "$allowed" == true ]] || return 1
  done
}

tmux_build_plugin_receipt() {
  local index plugins='[]'
  for index in "${!TMUX_PLUGIN_IDS[@]}"; do
    plugins="$(jq -c --arg id "${TMUX_PLUGIN_IDS[index]}" \
      --arg repository "${TMUX_PLUGIN_REPOSITORIES[index]}" --arg commit "${TMUX_PLUGIN_COMMITS[index]}" \
      --arg tree "${TMUX_PLUGIN_TREES[index]}" --arg directory "${TMUX_PLUGIN_DIRECTORIES[index]}" \
      '. + [{id:$id,repository:$repository,commit:$commit,tree:$tree,directory:$directory}]' <<< "$plugins")"
  done
  jq -cn --arg hash "$TMUX_PLUGIN_LOCK_SHA" --argjson plugins "$plugins" \
    '{schema_version:1,lock_sha256:$hash,plugins:$plugins}'
}

tmux_write_plugin_receipt_cas() {
  local content="$1" dir temporary quarantine="" actual installed
  dir="${TMUX_PLUGIN_RECEIPT%/*}"
  tmux_plugin_create_directory_chain "$dir"
  capture_path_identity "$TMUX_PLUGIN_RECEIPT" || die 'tmux plugin receipt changed before commit'
  [[ "$PATH_IDENTITY" == "$TMUX_PLUGIN_RECEIPT_IDENTITY" ]] || die 'tmux plugin receipt changed before commit'
  temporary="$(mktemp "$dir/.tmux-plugins.json.tmp.XXXXXX")"
  track_temp_path "$temporary"
  printf '%s\n' "$content" > "$temporary"
  chmod 0600 "$temporary"
  if [[ "$TMUX_PLUGIN_RECEIPT_IDENTITY" != absent ]]; then
    quarantine="$(tmux_plugin_allocate_quarantine "$TMUX_PLUGIN_RECEIPT")"
    mv -nT -- "$TMUX_PLUGIN_RECEIPT" "$quarantine" 2>/dev/null || \
      die 'tmux plugin receipt could not be quarantined without clobber'
    TMUX_PLUGIN_RECEIPT_QUARANTINE="$quarantine"
    TMUX_PLUGIN_RECEIPT_QUARANTINE_IDENTITY="$TMUX_PLUGIN_RECEIPT_IDENTITY"
    capture_path_identity "$quarantine" || die 'quarantined tmux plugin receipt is unreadable'
    actual="$PATH_IDENTITY"
    if [[ "$actual" != "$TMUX_PLUGIN_RECEIPT_IDENTITY" ]]; then
      if mv -nT -- "$quarantine" "$TMUX_PLUGIN_RECEIPT" 2>/dev/null &&
        [[ ! -e "$quarantine" && ! -L "$quarantine" ]]; then
        TMUX_PLUGIN_RECEIPT_QUARANTINE=""
        TMUX_PLUGIN_RECEIPT_QUARANTINE_IDENTITY=""
      fi
      die 'tmux plugin receipt changed during commit'
    fi
  fi
  mv -nT -- "$temporary" "$TMUX_PLUGIN_RECEIPT" 2>/dev/null || \
    die 'tmux plugin receipt destination appeared concurrently'
  [[ ! -e "$temporary" && ! -L "$temporary" && -f "$TMUX_PLUGIN_RECEIPT" && ! -L "$TMUX_PLUGIN_RECEIPT" ]] || \
    die 'tmux plugin receipt was not committed atomically'
  capture_path_identity "$TMUX_PLUGIN_RECEIPT" || die 'tmux plugin receipt commit post-state is unreadable'
  installed="$PATH_IDENTITY"
  TMUX_PLUGIN_RECEIPT_INSTALLED_IDENTITY="$installed"
  test_hold tmux-plugin-before-receipt-commit
  [[ "$(stat -c '%u:%a' -- "$TMUX_PLUGIN_RECEIPT")" == "$EUID:600" ]] || \
    die 'tmux plugin receipt commit has unsafe ownership or mode'
  [[ "$(sha256_file "$TMUX_PLUGIN_RECEIPT")" == "$(sha256_string "$content"$'\n')" ]] || \
    die 'tmux plugin receipt commit has unexpected content'
  capture_path_identity "$TMUX_PLUGIN_RECEIPT" || die 'tmux plugin receipt changed during post-commit verification'
  [[ "$PATH_IDENTITY" == "$installed" ]] || die 'tmux plugin receipt changed during post-commit verification'
  TMUX_PLUGIN_RECEIPT_IDENTITY="$PATH_IDENTITY"
  TMUX_PLUGIN_TX_COMMITTED=true
}

tmux_remove_unchanged_plugin_checkout() {
  local path="$1" repository="$2" expected="$3" quarantine
  tmux_inspect_plugin_checkout "$path" "$repository" || return 1
  [[ "$TMUX_CHECKOUT_IDENTITY" == "$expected" ]] || return 1
  quarantine="$(tmux_plugin_allocate_quarantine "$path")"
  mv -nT -- "$path" "$quarantine" 2>/dev/null || return 1
  [[ ! -e "$path" && ! -L "$path" ]] || return 1
  if ! tmux_inspect_plugin_checkout "$quarantine" "$repository"; then
    mv -nT -- "$quarantine" "$path" 2>/dev/null || true
    return 1
  fi
  if [[ "$TMUX_CHECKOUT_IDENTITY" != "$expected" ]]; then
    mv -nT -- "$quarantine" "$path" 2>/dev/null || true
    return 1
  fi
  rm -rf -- "$quarantine"
  [[ ! -e "$quarantine" && ! -L "$quarantine" ]]
}

tmux_restore_plugin_quarantine() {
  local quarantine="$1" path="$2" repository="$3" expected="$4"
  [[ -n "$quarantine" && ! -e "$path" && ! -L "$path" ]] || return 1
  tmux_inspect_plugin_checkout "$quarantine" "$repository" || return 1
  [[ "$TMUX_CHECKOUT_IDENTITY" == "$expected" ]] || return 1
  mv -nT -- "$quarantine" "$path" 2>/dev/null || return 1
  [[ ! -e "$quarantine" && ! -L "$quarantine" && -d "$path" ]]
}

tmux_restore_receipt_quarantine() {
  [[ -n "$TMUX_PLUGIN_RECEIPT_QUARANTINE" ]] || return 0
  [[ ! -e "$TMUX_PLUGIN_RECEIPT" && ! -L "$TMUX_PLUGIN_RECEIPT" ]] || return 1
  capture_path_identity "$TMUX_PLUGIN_RECEIPT_QUARANTINE" || return 1
  [[ "$PATH_IDENTITY" == "$TMUX_PLUGIN_RECEIPT_QUARANTINE_IDENTITY" ]] || return 1
  mv -nT -- "$TMUX_PLUGIN_RECEIPT_QUARANTINE" "$TMUX_PLUGIN_RECEIPT" 2>/dev/null || return 1
  TMUX_PLUGIN_RECEIPT_QUARANTINE=""
}

tmux_remove_uncommitted_plugin_receipt() {
  [[ -n "$TMUX_PLUGIN_RECEIPT_INSTALLED_IDENTITY" ]] || return 0
  capture_path_identity "$TMUX_PLUGIN_RECEIPT" || return 1
  [[ "$PATH_IDENTITY" == "$TMUX_PLUGIN_RECEIPT_INSTALLED_IDENTITY" ]] || {
    printf '[%s] error: retained changed uncommitted tmux plugin receipt for manual recovery at %s\n' \
      "$SCRIPT_NAME" "$TMUX_PLUGIN_RECEIPT" >&2
    return 1
  }
  rm -- "$TMUX_PLUGIN_RECEIPT" || return 1
  [[ ! -e "$TMUX_PLUGIN_RECEIPT" && ! -L "$TMUX_PLUGIN_RECEIPT" ]] || return 1
  TMUX_PLUGIN_RECEIPT_INSTALLED_IDENTITY=""
}

tmux_rollback_plugin_transaction() {
  local index root path failed=false
  root="$HOME/$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")"
  if ! tmux_remove_uncommitted_plugin_receipt; then
    printf '[%s] error: uncommitted tmux plugin receipt remains at %s\n' \
      "$SCRIPT_NAME" "$TMUX_PLUGIN_RECEIPT" >&2
    failed=true
  fi
  for ((index=${#TMUX_PLUGIN_IDS[@]}-1; index>=0; index--)); do
    [[ -n "${TMUX_PLUGIN_INSTALLED_IDENTITIES[index]}" ]] || continue
    path="$root/${TMUX_PLUGIN_DIRECTORIES[index]}"
    if ! tmux_remove_unchanged_plugin_checkout "$path" "${TMUX_PLUGIN_REPOSITORIES[index]}" \
      "${TMUX_PLUGIN_INSTALLED_IDENTITIES[index]}"; then
      printf '[%s] error: rollback preserved changed tmux plugin at %s\n' "$SCRIPT_NAME" "$path" >&2
      failed=true
    fi
  done
  for ((index=${#TMUX_PLUGIN_IDS[@]}-1; index>=0; index--)); do
    [[ -n "${TMUX_PLUGIN_QUARANTINES[index]}" ]] || continue
    path="$root/${TMUX_PLUGIN_DIRECTORIES[index]}"
    if ! tmux_restore_plugin_quarantine "${TMUX_PLUGIN_QUARANTINES[index]}" "$path" \
        "${TMUX_PLUGIN_PREFLIGHT_REPOSITORIES[index]}" "${TMUX_PLUGIN_QUARANTINE_IDENTITIES[index]}"; then
      printf '[%s] error: rollback retained old tmux plugin for recovery at %s\n' \
        "$SCRIPT_NAME" "${TMUX_PLUGIN_QUARANTINES[index]}" >&2
      failed=true
    else
      TMUX_PLUGIN_QUARANTINES[index]=""
    fi
  done
  if ! tmux_restore_receipt_quarantine; then
    printf '[%s] error: retained old tmux plugin receipt for manual recovery at %s; destination=%s\n' \
      "$SCRIPT_NAME" "$TMUX_PLUGIN_RECEIPT_QUARANTINE" "$TMUX_PLUGIN_RECEIPT" >&2
    failed=true
  fi
  [[ "$failed" == false ]] || return 1
  log 'rolled back incomplete tmux plugin provisioning'
}

tmux_discard_plugin_transaction_quarantines() {
  local index quarantine failed=false
  for index in "${!TMUX_PLUGIN_IDS[@]}"; do
    quarantine="${TMUX_PLUGIN_QUARANTINES[index]}"
    [[ -n "$quarantine" ]] || continue
    if tmux_remove_unchanged_plugin_checkout "$quarantine" "${TMUX_PLUGIN_PREFLIGHT_REPOSITORIES[index]}" \
      "${TMUX_PLUGIN_QUARANTINE_IDENTITIES[index]}"; then
      TMUX_PLUGIN_QUARANTINES[index]=""
    else
      printf '[%s] error: retained changed tmux plugin quarantine at %s\n' "$SCRIPT_NAME" "$quarantine" >&2
      failed=true
    fi
  done
  if [[ -n "$TMUX_PLUGIN_RECEIPT_QUARANTINE" ]]; then
    capture_path_identity "$TMUX_PLUGIN_RECEIPT_QUARANTINE" || failed=true
    if [[ "$PATH_IDENTITY" == "$TMUX_PLUGIN_RECEIPT_QUARANTINE_IDENTITY" ]]; then
      rm -- "$TMUX_PLUGIN_RECEIPT_QUARANTINE" || failed=true
      TMUX_PLUGIN_RECEIPT_QUARANTINE=""
    else
      printf '[%s] error: retained changed tmux plugin receipt quarantine at %s\n' \
        "$SCRIPT_NAME" "$TMUX_PLUGIN_RECEIPT_QUARANTINE" >&2
      failed=true
    fi
  fi
  [[ "$failed" == false ]]
}

tmux_cleanup_plugin_stages() {
  local index stage failed=false
  for index in "${!TMUX_PLUGIN_STAGES[@]}"; do
    stage="${TMUX_PLUGIN_STAGES[index]}"
    [[ -n "$stage" && ( -e "$stage" || -L "$stage" ) ]] || continue
    discard_tracked_temp_path "$stage" 'tmux plugin staging' || failed=true
  done
  [[ "$failed" == false ]]
}

tmux_prune_plugin_created_directories() {
  local index
  for ((index=${#TMUX_PLUGIN_CREATED_DIRS[@]}-1; index>=0; index--)); do
    rmdir -- "${TMUX_PLUGIN_CREATED_DIRS[index]}" 2>/dev/null || true
  done
}

tmux_plugin_transaction_exit() {
  local status="$1" failed=false
  trap - EXIT INT TERM
  set +e
  if [[ "$TMUX_PLUGIN_TX_COMMITTED" == true ]]; then
    tmux_discard_plugin_transaction_quarantines || failed=true
  elif [[ "$TMUX_PLUGIN_TX_ACTIVE" == true ]]; then
    tmux_rollback_plugin_transaction || failed=true
  fi
  tmux_cleanup_plugin_stages || failed=true
  tmux_prune_plugin_created_directories
  if [[ "$failed" == true && "$TMUX_PLUGIN_TX_COMMITTED" == false ]]; then
    printf '[%s] error: tmux plugin rollback failed; retained objects require manual recovery\n' "$SCRIPT_NAME" >&2
    exit 70
  fi
  [[ "$failed" == false ]] || status=1
  exit "$status"
}

tmux_apply_plugin_provisioning() (
  local index root receipt
  set -Eeuo pipefail
  trap 'tmux_plugin_transaction_exit $?' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ "$TMUX_PLUGIN_PLAN_PENDING" == false ]]; then
    log 'tmux plugins are converged'
    return 0
  fi
  [[ "$TMUX_PLUGIN_PLAN_REFUSED" == false ]] || die 'refused tmux plugin plan cannot be applied'
  TMUX_PLUGIN_TX_ACTIVE=true
  TMUX_PLUGIN_TX_COMMITTED=false
  TMUX_PLUGIN_CREATED_DIRS=()
  TMUX_PLUGIN_RECEIPT_QUARANTINE=""
  TMUX_PLUGIN_RECEIPT_QUARANTINE_IDENTITY=""
  TMUX_PLUGIN_RECEIPT_INSTALLED_IDENTITY=""
  [[ "$(sha256_file "$TMUX_PLUGIN_LOCK")" == "$TMUX_PLUGIN_LOCK_SHA" ]] || \
    die 'tmux plugin lock changed before staging'
  root="$HOME/$(jq -r .plugin_root "$TMUX_PLUGIN_LOCK")"
  tmux_plugin_create_directory_chain "$root"
  for index in "${!TMUX_PLUGIN_IDS[@]}"; do
    case "${TMUX_PLUGIN_ACTIONS[index]}" in install|replace|normalize-origin) tmux_stage_locked_plugin "$index" ;; esac
  done
  test_hold tmux-plugin-after-staging
  fault tmux-plugin-after-staging
  tmux_plugin_quarantine_replacements
  test_hold tmux-plugin-after-quarantine
  fault tmux-plugin-after-quarantine
  tmux_plugin_install_stages
  test_hold tmux-plugin-after-install
  fault tmux-plugin-after-install
  tmux_verify_plugin_transaction_closure || die 'tmux plugin closure verification failed before receipt commit'
  [[ "$(sha256_file "$TMUX_PLUGIN_LOCK")" == "$TMUX_PLUGIN_LOCK_SHA" ]] || \
    die 'tmux plugin lock changed before receipt commit'
  receipt="$(tmux_build_plugin_receipt)"
  test_hold tmux-plugin-before-receipt
  fault tmux-plugin-before-receipt
  tmux_write_plugin_receipt_cas "$receipt"
  test_hold tmux-plugin-after-receipt
  fault tmux-plugin-after-receipt
  log 'provisioned exact receipted tmux plugin closure'
)

tmux_version_from_output() {
  local output="$1"
  [[ "$output" =~ ^tmux[[:space:]]+([^[:space:]]+)$ ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

tmux_report_old_version() {
  local version="$1" context="$2" options=()
  version_at_least "$version" 3.5 && return 0
  version_at_least "$version" 3.3 || options+=(allow-passthrough)
  options+=(extended-keys-format)
  log "warning: $context tmux $version is older than 3.5; inert options: ${options[*]}"
}

tmux_distro_owner_matches() {
  local candidate="$1" package="$2" resolved owner query=/usr/bin/dpkg-query
  resolved="$(realpath -e -- "$candidate" 2>/dev/null)" || return 1
  [[ "${DOTFILES_TESTING:-}" != 1 || -z "${DOTFILES_TEST_TMUX_DPKG_QUERY:-}" ]] || query="$DOTFILES_TEST_TMUX_DPKG_QUERY"
  [[ -x "$query" ]] || return 1
  owner="$("$query" -S "$resolved" 2>/dev/null || true)"
  [[ "$owner" == "$package:"* || "$owner" == "$package:"*:* ]]
}

resolve_tmux_client_owner() {
  local candidate resolved output root executable launcher managed candidate_path owner
  local candidates=()
  TMUX_CLIENT_BIN=""; TMUX_CLIENT_VERSION=""; TMUX_CLIENT_OWNER=""
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_TMUX_BIN:-}" ]]; then
    TMUX_CLIENT_BIN="$(realpath -e -- "$DOTFILES_TEST_TMUX_BIN")"
    TMUX_CLIENT_OWNER="${DOTFILES_TEST_TMUX_OWNER:-test-owner}"
  else
    ! declare -F tmux >/dev/null && [[ "$(type -t tmux 2>/dev/null || true)" != alias ]] || {
      log "error: tmux is shadowed by a shell function or alias"; return 1;
    }
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] && ! array_contains "$candidate" "${candidates[@]}" && candidates+=("$candidate")
    done < <(path_candidates tmux)
    ((${#candidates[@]} > 0)) || { log 'error: no tmux client is available'; return 1; }
    candidate_path="${candidates[0]}"
    resolved="$(realpath -e -- "$candidate_path" 2>/dev/null)" || { log 'error: selected tmux client is broken'; return 1; }
    if [[ "$SELECTED_PROFILE" == omarchy ]]; then
      [[ "$candidate_path" == /usr/bin/tmux || "$candidate_path" == /bin/tmux ]] || {
        log "error: native tmux has an unapproved owner path: $candidate_path"; return 1;
      }
      owner="$(pacman -Qo "$resolved" 2>/dev/null || true)"
      [[ "$owner" =~ [[:space:]]owned[[:space:]]by[[:space:]]tmux[[:space:]] ]] || {
        log 'error: native tmux is not owned by the tmux package'; return 1;
      }
      TMUX_CLIENT_BIN="$resolved"; TMUX_CLIENT_OWNER=native:tmux
    else
      launcher="$HOME/$(jq -r --arg id tmux '.tools[] | select(.id == $id) | .commands[0].launcher' "$PROVISIONING_MANIFEST")"
      if [[ "$candidate_path" == "$launcher" ]]; then
        provision_tool_status tmux || { log 'error: selected tmux launcher does not have retained provisioning ownership'; return 1; }
        root="$(jq -r --arg id tmux '.tools[] | select(.id == $id) | .install_root' "$PROVISIONING_MANIFEST")"
        executable="$(jq -r --arg id tmux '.tools[] | select(.id == $id) | .artifact.executable' "$PROVISIONING_MANIFEST")"
        TMUX_CLIENT_BIN="$HOME/$root/$executable"; TMUX_CLIENT_OWNER=locked-mise:tmux
      else
        [[ "$candidate_path" == /usr/bin/tmux || "$candidate_path" == /bin/tmux ]] && tmux_distro_owner_matches "$candidate_path" tmux || {
          log "error: selected tmux client has an unapproved owner: $candidate_path"; return 1;
        }
        for managed in "${candidates[@]}"; do
          [[ "$managed" == /usr/bin/tmux || "$managed" == /bin/tmux ]] && tmux_distro_owner_matches "$managed" tmux || {
            log "error: tmux has an unapproved PATH candidate: $managed"; return 1;
          }
        done
        TMUX_CLIENT_BIN="$resolved"; TMUX_CLIENT_OWNER=distro:tmux
      fi
    fi
  fi
  [[ -f "$TMUX_CLIENT_BIN" && ! -L "$TMUX_CLIENT_BIN" && -x "$TMUX_CLIENT_BIN" ]] || {
    log 'error: selected tmux owner is not a directly executable regular file'; return 1;
  }
  output="$(run_offline_probe "$TMUX_CLIENT_BIN" -V 2>/dev/null)" || { log 'error: selected tmux version probe failed'; return 1; }
  IFS= read -r output <<< "$output"
  TMUX_CLIENT_VERSION="$(tmux_version_from_output "$output")" || { log 'error: selected tmux returned an invalid version'; return 1; }
  tmux_report_old_version "$TMUX_CLIENT_VERSION" 'selected client'
  log "selected tmux client $TMUX_CLIENT_VERSION owner=$TMUX_CLIENT_OWNER executable=$TMUX_CLIENT_BIN"
}

validate_tmux_terminfo() {
  local output
  output="$(infocmp -x tmux-256color 2>/dev/null)" || die 'tmux-256color terminfo is unavailable or unusable'
  [[ "$output" == *tmux-256color* ]] || die 'tmux-256color terminfo probe returned the wrong entry'
}

tmux_query_active_pids() {
  local label socket current output pid version default_socket
  TMUX_ACTIVE_LABELS=(); TMUX_ACTIVE_SOCKETS=(); TMUX_ACTIVE_PIDS=(); TMUX_ACTIVE_VERSIONS=()
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_TMUX_SERVER_RECORDS:-}" ]]; then
    while IFS='|' read -r label socket pid version; do
      TMUX_ACTIVE_LABELS+=("$label"); TMUX_ACTIVE_SOCKETS+=("$socket")
      TMUX_ACTIVE_PIDS+=("$pid"); TMUX_ACTIVE_VERSIONS+=("$version")
    done <<< "$DOTFILES_TEST_TMUX_SERVER_RECORDS"
    return 0
  fi
  default_socket="${TMUX_TMPDIR:-/tmp}/tmux-$EUID/default"
  current="${TMUX:-}"
  for label in default current; do
    if [[ "$label" == default ]]; then
      socket="$default_socket"
    else
      [[ -n "$current" ]] || continue
      socket="${current%%,*}"
      [[ "$socket" == /* ]] || continue
      [[ "$socket" != "$default_socket" ]] || continue
    fi
    output="$(env -u TMUX "$TMUX_CLIENT_BIN" -S "$socket" display-message -p '#{pid}|#{version}' 2>/dev/null || true)"
    IFS='|' read -r pid version <<< "$output"
    if [[ "$pid" =~ ^[0-9]+$ && -n "$version" ]]; then
      TMUX_ACTIVE_LABELS+=("$label"); TMUX_ACTIVE_SOCKETS+=("$socket")
      TMUX_ACTIVE_PIDS+=("$pid"); TMUX_ACTIVE_VERSIONS+=("$version")
    elif [[ -S "$socket" && "$(stat -c %u -- "$socket" 2>/dev/null || true)" == "$EUID" ]]; then
      TMUX_ACTIVE_LABELS+=("$label"); TMUX_ACTIVE_SOCKETS+=("$socket")
      TMUX_ACTIVE_PIDS+=(""); TMUX_ACTIVE_VERSIONS+=("")
    fi
  done
}

inspect_active_tmux_servers() {
  local index label socket pid version proc_root=/proc executable owner selected selected_owner proc_before proc_after
  [[ "${DOTFILES_TESTING:-}" != 1 || "${DOTFILES_TEST_TMUX_SKIP_ACTIVE:-}" != 1 ]] || return 0
  [[ "${DOTFILES_TESTING:-}" != 1 || -z "${DOTFILES_TEST_TMUX_PROC_ROOT:-}" ]] || proc_root="$DOTFILES_TEST_TMUX_PROC_ROOT"
  selected="$(realpath -e -- "$TMUX_CLIENT_BIN")"
  selected_owner="$(stat -c %u -- "$selected")"
  tmux_query_active_pids
  for index in "${!TMUX_ACTIVE_LABELS[@]}"; do
    label="${TMUX_ACTIVE_LABELS[index]}"; socket="${TMUX_ACTIVE_SOCKETS[index]}"
    pid="${TMUX_ACTIVE_PIDS[index]}"; version="${TMUX_ACTIVE_VERSIONS[index]}"
    TMUX_ACTIVE_SERVER_SEEN=true
    if [[ -z "$pid" ]]; then
      TMUX_ACTIVE_SERVER_TRANSITION=true
      log "warning: $label tmux server socket exists but is unqueryable: socket=$socket"
      continue
    fi
    [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] || {
      TMUX_ACTIVE_SERVER_TRANSITION=true
      log "warning: $label tmux server returned an invalid PID: $pid socket=$socket"
      continue
    }
    proc_before="$(stat -Lc '%d:%i:%u' -- "$proc_root/$pid" 2>/dev/null || true)"
    executable="$(readlink -e -- "$proc_root/$pid/exe" 2>/dev/null || true)"
    owner="$(stat -Lc %u -- "$proc_root/$pid/exe" 2>/dev/null || true)"
    proc_after="$(stat -Lc '%d:%i:%u' -- "$proc_root/$pid" 2>/dev/null || true)"
    if [[ -z "$proc_before" || "$proc_before" != "$proc_after" || -z "$executable" || -z "$owner" ]]; then
      TMUX_ACTIVE_SERVER_TRANSITION=true
      log "warning: active tmux server PID $pid is in transition; /proc executable ownership is unavailable"
      continue
    fi
    if [[ "$owner" != "$selected_owner" || "$executable" != "$selected" ]]; then
      TMUX_ACTIVE_SERVER_TRANSITION=true
      log "warning: $label tmux server transition: socket=$socket pid=$pid reported-version=${version:-unknown} executable=$executable owner=${owner:-unknown}; selected=$selected"
    else
      TMUX_ACTIVE_SERVER_SAME_OWNER=true
      tmux_report_old_version "$version" "$label server PID $pid"
      log "$label tmux server socket=$socket pid=$pid reported-version=$version matches the selected owner"
    fi
  done
}

report_tmux_active_server_guidance() {
  if [[ "$TMUX_ACTIVE_SERVER_TRANSITION" == true ]]; then
    log 'active tmux ownership differs or is unqueryable; manually save, exit clients, run tmux kill-server, start the selected tmux owner, then restore'
  elif [[ "$TMUX_ACTIVE_SERVER_SAME_OWNER" == true ]]; then
    log 'the active tmux server was left untouched; if its configuration may be legacy, run tmux source-file ~/.config/tmux/tmux.conf once'
  fi
}

tmux_validation_source() {
  local mode="$1" relative="$2"
  if [[ "$mode" == deployed ]]; then
    printf '%s' "$HOME/$relative"
  else
    case "$relative" in
      .config/tmux/tmux.conf) printf '%s' "$DOTFILES_DIR/packages/generic/tmux/$relative" ;;
      .config/dotfiles/upstream/tmux/tmux.conf) printf '%s' "$DOTFILES_DIR/packages/upstream/tmux/$relative" ;;
      .config/dotfiles/tmux/generic.conf) printf '%s' "$DOTFILES_DIR/packages/generic/tmux/$relative" ;;
      .config/dotfiles/tmux/wsl.conf) printf '%s' "$DOTFILES_DIR/packages/wsl/tmux/$relative" ;;
      .config/dotfiles/tmux/persistence.conf) printf '%s' "$DOTFILES_DIR/packages/common/tmux/$relative" ;;
      *) return 1 ;;
    esac
  fi
}

tmux_isolated_exec() {
  unshare --user --map-root-user --net -- env -u TMUX HOME="$TMUX_VALIDATION_HOME" \
    TMUX_TMPDIR="$TMUX_ISOLATED_TMPDIR" PATH=/usr/bin:/bin "$TMUX_ISOLATED_BIN" -L "$TMUX_ISOLATED_SOCKET" "$@"
}

tmux_stop_isolated_validation() {
  local sandbox="${TMUX_ISOLATED_SANDBOX:-}" status=1 attempt process_identity
  [[ -n "${TMUX_ISOLATED_BIN:-}" && -n "${TMUX_ISOLATED_SOCKET:-}" && -n "${TMUX_ISOLATED_TMPDIR:-}" ]] || return 0
  tmux_isolated_exec kill-server >/dev/null 2>&1 || true
  for ((attempt=0; attempt<100; attempt++)); do
    process_identity="$(stat -Lc '%d:%i:%u' -- "/proc/${TMUX_ISOLATED_PID:-invalid}" 2>/dev/null || true)"
    if [[ -n "$TMUX_ISOLATED_PID" && -n "$TMUX_ISOLATED_PROC_IDENTITY" &&
      "$process_identity" != "$TMUX_ISOLATED_PROC_IDENTITY" ]]; then
      status=0
      break
    fi
    sleep 0.02
  done
  if ((status != 0)); then
    [[ -z "$sandbox" ]] || retain_tracked_temp_path "$sandbox"
    printf '[%s] error: isolated tmux server did not terminate; retained recovery root: %s\n' \
      "$SCRIPT_NAME" "${sandbox:-unknown}" >&2
    TMUX_ISOLATED_BIN=""; TMUX_ISOLATED_SOCKET=""; TMUX_ISOLATED_TMPDIR=""; TMUX_ISOLATED_SANDBOX=""
    TMUX_ISOLATED_PID=""; TMUX_ISOLATED_PROC_IDENTITY=""
    return 1
  fi
  TMUX_ISOLATED_BIN=""; TMUX_ISOLATED_SOCKET=""; TMUX_ISOLATED_TMPDIR=""; TMUX_ISOLATED_SANDBOX=""
  TMUX_ISOLATED_PID=""; TMUX_ISOLATED_PROC_IDENTITY=""
}

validate_tmux_isolated_config() {
  local mode="$1" sandbox config relative source output errors status=0 value option
  local -a expected_diagnostics=()
  local -A seen_diagnostics=()
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tmux-validation.XXXXXX")"
  track_temp_path "$sandbox"
  TMUX_VALIDATION_HOME="$sandbox/home"
  TMUX_ISOLATED_TMPDIR="$sandbox/socket-root"
  TMUX_ISOLATED_SOCKET="dotfiles-$PPID-$RANDOM-$RANDOM"
  TMUX_ISOLATED_BIN="$TMUX_CLIENT_BIN"
  TMUX_ISOLATED_SANDBOX="$sandbox"
  mkdir -- "$TMUX_VALIDATION_HOME" "$TMUX_ISOLATED_TMPDIR"
  unshare --user --map-root-user --net true >/dev/null 2>&1 || \
    die 'isolated tmux validation could not establish a denied-network namespace'

  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    mkdir -p -- "$TMUX_VALIDATION_HOME/.config/tmux" "$TMUX_VALIDATION_HOME/.config/dotfiles/tmux"
    cp -p -- "$HOME/$TMUX_NATIVE_PATH" "$TMUX_VALIDATION_HOME/$TMUX_NATIVE_PATH"
    cp -p -- "$(tmux_validation_source "$mode" .config/dotfiles/tmux/persistence.conf)" \
      "$TMUX_VALIDATION_HOME/.config/dotfiles/tmux/persistence.conf"
    inspect_guarded_block "$TMUX_VALIDATION_HOME/$TMUX_NATIVE_PATH" "$TMUX_NATIVE_BEGIN" "$TMUX_NATIVE_END" \
      "$TMUX_NATIVE_TOKEN" "$TMUX_NATIVE_BLOCK" false || status=$?
    if ((status == 1)); then printf '\n%s\n' "$TMUX_NATIVE_BLOCK" >> "$TMUX_VALIDATION_HOME/$TMUX_NATIVE_PATH"; status=0; fi
    ((status == 0)) || die 'native tmux validation copy has a malformed managed attachment'
  else
    tmux_expected_targets
    for relative in "${TMUX_EXPECTED_TARGETS[@]}"; do
      source="$(tmux_validation_source "$mode" "$relative")" || die "unknown tmux validation target: $relative"
      mkdir -p -- "$(dirname -- "$TMUX_VALIDATION_HOME/$relative")"
      cp -p -- "$source" "$TMUX_VALIDATION_HOME/$relative"
    done
  fi
  config="$TMUX_VALIDATION_HOME/.config/tmux/tmux.conf"
  errors="$sandbox/start-errors"
  if ! version_at_least "$TMUX_CLIENT_VERSION" 3.3; then expected_diagnostics+=(allow-passthrough); fi
  if ! version_at_least "$TMUX_CLIENT_VERSION" 3.5; then expected_diagnostics+=(extended-keys-format); fi
  set +e
  tmux_isolated_exec -f /dev/null new-session -d -s dotfiles-validation 2> "$errors"
  status=$?
  set -e
  if ((status != 0)); then
    [[ ! -s "$errors" ]] || command cat -- "$errors" >&2
    die 'isolated tmux validation server failed to start'
  fi
  TMUX_ISOLATED_PID="$(tmux_isolated_exec display-message -p '#{pid}')"
  [[ "$TMUX_ISOLATED_PID" =~ ^[0-9]+$ && "$TMUX_ISOLATED_PID" -gt 1 ]] || \
    die 'isolated tmux validation server returned an invalid PID'
  TMUX_ISOLATED_PROC_IDENTITY="$(stat -Lc '%d:%i:%u' -- "/proc/$TMUX_ISOLATED_PID" 2>/dev/null || true)"
  [[ -n "$TMUX_ISOLATED_PROC_IDENTITY" ]] || die 'isolated tmux validation server process identity is unavailable'
  : > "$errors"
  set +e
  tmux_isolated_exec source-file "$config" 2> "$errors"
  status=$?
  set -e
  if ((${#expected_diagnostics[@]} == 0)); then
    ((status == 0)) || {
      [[ ! -s "$errors" ]] || command cat -- "$errors" >&2
      die 'isolated tmux configuration failed to load'
    }
  else
    ((status != 0)) || die 'isolated tmux parser accepted inert compatibility options without notices'
  fi
  output="$(< "$errors")"
  if [[ -n "$output" ]]; then
    while IFS= read -r value || [[ -n "$value" ]]; do
      option=""
      [[ "$value" != *allow-passthrough* ]] || option=allow-passthrough
      if [[ "$value" == *extended-keys-format* ]]; then
        [[ -z "$option" ]] || die "isolated tmux configuration combined compatibility diagnostics: $value"
        option=extended-keys-format
      fi
      [[ -n "$option" && "$value" == *"invalid option: $option"* ]] || \
        die "isolated tmux configuration emitted an unexpected diagnostic: $value"
      array_contains "$option" "${expected_diagnostics[@]}" || \
        die "isolated tmux configuration emitted an unexpected compatibility diagnostic: $value"
      [[ -z "${seen_diagnostics[$option]+x}" ]] || \
        die "isolated tmux configuration repeated the $option diagnostic"
      seen_diagnostics[$option]=1
    done <<< "$output"
  fi
  for option in "${expected_diagnostics[@]}"; do
    [[ -n "${seen_diagnostics[$option]+x}" ]] || \
      die "isolated tmux configuration omitted the expected $option diagnostic"
  done
  value="$(tmux_isolated_exec display-message -p '#{version}')"
  [[ "$value" == "$TMUX_CLIENT_VERSION" ]] || die "isolated tmux server version mismatch: client=$TMUX_CLIENT_VERSION server=$value"
  [[ "$(tmux_isolated_exec show-options -gv prefix)" == C-Space ]] || die 'isolated tmux primary prefix is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv prefix2)" == C-b ]] || die 'isolated tmux fallback prefix is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv default-terminal)" == tmux-256color ]] || die 'isolated tmux default terminal is incorrect'
  output="$(tmux_isolated_exec show-options -gv terminal-overrides)"
  [[ "$(while IFS= read -r value; do [[ "$value" == '*:RGB' ]] && printf 'match\n'; done <<< "$output")" == match ]] || \
    die 'isolated tmux RGB override is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv set-clipboard)" == on ]] || die 'isolated tmux clipboard option is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv mouse)" == on ]] || die 'isolated tmux mouse option is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv base-index)" == 1 ]] || die 'isolated tmux window base index is incorrect'
  [[ "$(tmux_isolated_exec show-options -wgv pane-base-index)" == 1 ]] || die 'isolated tmux pane base index is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv status-position)" == top && \
    "$(tmux_isolated_exec show-options -gv status-interval)" == 5 && \
    "$(tmux_isolated_exec show-options -gv status-left-length)" == 30 && \
    "$(tmux_isolated_exec show-options -gv status-right-length)" == 50 && \
    "$(tmux_isolated_exec show-options -gv window-status-separator)" == '' ]] || \
    die 'isolated tmux status contract is incorrect'
  output="$(tmux_isolated_exec list-keys -T copy-mode-vi)"
  [[ "$output" == *' v '*'send-keys -X begin-selection'* ]] || die 'isolated tmux copy selection binding is incorrect'
  [[ "$output" == *' y '*'send-keys -X copy-selection-and-cancel'* ]] || die 'isolated tmux copy binding is incorrect'
  output="$(tmux_isolated_exec list-keys -T prefix)"
  [[ "$output" == *' h '*'split-window -v -c "#{pane_current_path}"'* ]] || die 'isolated tmux vertical split binding is incorrect'
  [[ "$output" == *' v '*'split-window -h -c "#{pane_current_path}"'* ]] || die 'isolated tmux horizontal split binding is incorrect'
  [[ "$output" == *' x '*'kill-pane'* ]] || die 'isolated tmux kill-pane binding is incorrect'
  [[ "$output" == *' q '*"source-file $TMUX_VALIDATION_HOME/.config/tmux/tmux.conf"* && \
    "$output" == *'display-message "Configuration reloaded"'* ]] || die 'isolated tmux reload binding is incorrect'
  output="$(tmux_isolated_exec list-keys -T root)"
  [[ "$output" == *' M-Enter '*'split-window -v -c "#{pane_current_path}"'* ]] || die 'isolated tmux Alt-Enter binding is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv @continuum-save-interval)" == 5 ]] || \
    die 'isolated tmux persistence interval is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv @continuum-restore)" == on ]] || \
    die 'isolated tmux persistence restore option is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv @resurrect-hook-post-save-all)" == \
    "bash \"$TMUX_VALIDATION_HOME/.tmux/plugins/tmux-assistant-resurrect/scripts/save-assistant-sessions.sh\"" ]] || \
    die 'isolated tmux Assistant Resurrect save hook is incorrect'
  [[ "$(tmux_isolated_exec show-options -gv @resurrect-hook-post-restore-all)" == \
    "bash \"$TMUX_VALIDATION_HOME/.tmux/plugins/tmux-assistant-resurrect/scripts/restore-assistant-sessions.sh\"" ]] || \
    die 'isolated tmux Assistant Resurrect restore hook is incorrect'
  if ((${#expected_diagnostics[@]} == 0)); then
    log "validated isolated tmux $TMUX_CLIENT_VERSION parser: config diagnostics=none"
  else
    log "validated isolated tmux $TMUX_CLIENT_VERSION parser: config diagnostics=${expected_diagnostics[*]}"
  fi
  tmux_stop_isolated_validation || die "isolated tmux validation cleanup failed; retained recovery root: $sandbox"
  discard_tracked_temp_path "$sandbox" 'tmux isolated validation' || die 'could not remove tmux validation environment safely'
}

tmux_attachment_origin() {
  local id="$1" origin
  [[ "$id" == tmux-native-config-v1.* ]] || return 1
  origin="${id#tmux-native-config-v1.}"
  case "$origin" in
    existing-empty|existing-final-newline|existing-no-final-newline) printf '%s' "$origin" ;;
    *) return 1 ;;
  esac
}

validate_tmux_attachments_from_state() {
  local state="$1" profile count id path hash
  profile="$(jq -r .profile "$state")"; count="$(jq '.attachments | length' "$state")"
  if [[ "$profile" != omarchy ]]; then
    [[ "$count" == 0 ]] || die 'generic/WSL tmux state records unknown attachments'
    return 0
  fi
  [[ "$count" == 1 ]] || die 'native tmux state does not record exactly one attachment'
  IFS=$'\t' read -r id path hash < <(jq -r '.attachments[0] | [.id,.path,.content_hash] | @tsv' "$state")
  [[ "$path" == "$TMUX_NATIVE_PATH" && "$hash" == "$(sha256_string "$TMUX_NATIVE_BLOCK")" ]] || \
    die 'native tmux state records an unknown attachment'
  TMUX_NATIVE_ORIGIN="$(tmux_attachment_origin "$id")" || die 'native tmux state records an unknown attachment origin'
  guarded_attachment_preflight "$TMUX_NATIVE_PATH" "$TMUX_NATIVE_BEGIN" "$TMUX_NATIVE_END" "$TMUX_NATIVE_TOKEN" \
    "$TMUX_NATIVE_BLOCK" append "$([[ "$MODE" == remove ]] && printf exact || printf refresh)"
  TMUX_NATIVE_ACTION="$GUARDED_ATTACHMENT_ACTION"
  [[ "$TMUX_NATIVE_ACTION" != insert ]] || TMUX_NATIVE_ORIGIN="$GUARDED_ATTACHMENT_ORIGIN"
}

preflight_new_tmux_attachment() {
  local path="$HOME/$TMUX_NATIVE_PATH"
  validate_home_parent_chain "$path"
  [[ -f "$path" && ! -L "$path" ]] || die "native Omarchy tmux config is missing or not a regular file: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "native Omarchy tmux config has an unsafe owner: $path"
  guarded_attachment_preflight "$TMUX_NATIVE_PATH" "$TMUX_NATIVE_BEGIN" "$TMUX_NATIVE_END" "$TMUX_NATIVE_TOKEN" \
    "$TMUX_NATIVE_BLOCK" append refresh
  TMUX_NATIVE_ACTION="$GUARDED_ATTACHMENT_ACTION"
  TMUX_NATIVE_ORIGIN="$GUARDED_ATTACHMENT_ORIGIN"
}

preflight_tmux_xdg_migration() {
  local path="$HOME/$TMUX_LEGACY_PATH" source_present=false
  validate_home_parent_chain "$path"
  if [[ -L "$path" ]]; then
    owned_legacy_link "$path" "$TMUX_LEGACY_PATH" "$TMUX_LEGACY_PATH" tmux replace-stage-7 || \
      die "$path is not the exact reviewed legacy tmux link"
    TMUX_LEGACY_SOURCE="$OWNED_LEGACY_SOURCE"
    TMUX_LEGACY_FINGERPRINT="$(sha256_file "$TMUX_LEGACY_SOURCE")"
    capture_path_identity "$path" || die 'reviewed legacy tmux link changed during preflight'
    TMUX_LEGACY_IDENTITY="$PATH_IDENTITY"
    source_present=true
  elif [[ -e "$path" ]]; then
    die "$path is unrelated host data; expected the exact reviewed legacy tmux link"
  fi
  preflight_migration "$TMUX_XDG_MIGRATION_ID" "$source_present" 'tmux XDG config migration'
  [[ "$MIGRATION_STATUS" != pending || "$source_present" != true ]] || TMUX_LEGACY_ACTION=retire
}

validate_tmux_wsl_adapter() {
  local source="$DOTFILES_DIR/packages/wsl/tmux/.config/dotfiles/tmux/wsl.conf" line
  [[ -f "$source" && ! -L "$source" ]] || die 'WSL tmux adapter is missing or unsafe'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] || die 'WSL tmux adapter must contain no commands'
  done < "$source"
}

validate_tmux_payload() {
  local index relative source mode
  for index in "${!TARGET_PATHS[@]}"; do
    relative="${TARGET_PATHS[index]}"; source="${TARGET_SOURCES[index]}"; mode="$(stat -c %a -- "$source")"
    [[ "$mode" == 644 ]] || die "unexpected tmux payload mode $mode for $relative; expected 644"
    file_contains_nul "$source" && die "tmux payload contains NUL bytes: $relative"
  done
  [[ -f "$DOTFILES_DIR/.tmux.conf" && ! -L "$DOTFILES_DIR/.tmux.conf" ]] || die 'tmux compatibility source is missing'
  if [[ "$SELECTED_PROFILE" != omarchy ]]; then
    "$DOTFILES_DIR/scripts/upstream" verify >/dev/null || die 'pinned upstream tmux snapshot verification failed'
  fi
  [[ "$SELECTED_PROFILE" != wsl ]] || validate_tmux_wsl_adapter
  validate_tmux_plugin_lock
}

configure_tmux_journal() {
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    AREA_JOURNAL_PATHS+=("$HOME/$TMUX_NATIVE_PATH")
  else
    AREA_JOURNAL_PATHS+=("$HOME/$TMUX_LEGACY_PATH")
  fi
}

preflight_tmux() {
  init_tmux_area
  load_profile_closure tmux
  scan_packages
  validate_tmux_target_inventory
  validate_tmux_payload
  validate_tmux_terminfo
  resolve_tmux_client_owner || die 'tmux client ownership validation failed'
  tmux_validate_exact_plugin_closure || die 'tmux plugin closure is not exact; only --provision --area tmux may repair it'
  inspect_active_tmux_servers
  record_managed_parents '.local/state/dotfiles/v1/tmux.json'
  if [[ "$SELECTED_PROFILE" != omarchy ]]; then preflight_tmux_xdg_migration; fi
  preflight_existing_state
  if [[ "$SELECTED_PROFILE" == omarchy && "$OLD_STATE" == false ]]; then preflight_new_tmux_attachment; fi
  configure_tmux_journal
  preflight_desired_targets
  run_stow_preflight
  validate_tmux_isolated_config checkout
}

retire_tmux_legacy_link() {
  local path="$HOME/$TMUX_LEGACY_PATH" quarantine
  [[ "$TMUX_LEGACY_ACTION" == retire ]] || return 0
  test_hold before-tmux-legacy-quarantine
  quarantine_expected_path "$path" "$TMUX_LEGACY_IDENTITY" 'reviewed legacy tmux link' || \
    die 'reviewed legacy tmux link changed before retirement'
  quarantine="$QUARANTINE_PATH"
  owned_legacy_link "$quarantine" "$TMUX_LEGACY_PATH" "$TMUX_LEGACY_PATH" tmux replace-stage-7 || {
    if restore_quarantine_no_clobber "$quarantine" "$path"; then transaction_record_post_state "$path"; fi
    die 'quarantined legacy tmux link no longer has reviewed ownership'
  }
  [[ "$OWNED_LEGACY_SOURCE" == "$TMUX_LEGACY_SOURCE" && "$(sha256_file "$OWNED_LEGACY_SOURCE")" == "$TMUX_LEGACY_FINGERPRINT" ]] || \
    die 'reviewed legacy tmux compatibility source changed during retirement'
  discard_quarantine "$quarantine" 'reviewed legacy tmux link'
  append_migration_ledger "$TMUX_XDG_MIGRATION_ID" "$TMUX_LEGACY_FINGERPRINT"
}

install_tmux_attachment() {
  [[ "$SELECTED_PROFILE" == omarchy ]] || return 0
  install_guarded_attachment "$TMUX_NATIVE_PATH" "$TMUX_NATIVE_BEGIN" "$TMUX_NATIVE_END" "$TMUX_NATIVE_TOKEN" \
    "$TMUX_NATIVE_BLOCK" append 0644 "$([[ "$OLD_STATE" == true ]] && printf refresh || printf refresh)"
}

build_tmux_state_json() {
  local packages='[]' targets='[]' dirs='[]' attachments='[]' index id
  for index in "${!PACKAGES[@]}"; do packages="$(jq -c --arg value "${PACKAGES[index]}" '. + [$value]' <<< "$packages")"; done
  for index in "${!TARGET_PATHS[@]}"; do
    targets="$(jq -c --arg path "${TARGET_PATHS[index]}" --arg source "${TARGET_LEXICAL[index]}" \
      --arg resolved "${TARGET_SOURCES[index]}" '. + [{path:$path,source:$source,resolved_source:$resolved}]' <<< "$targets")"
  done
  for index in "${!MANAGED_DIRS[@]}"; do dirs="$(jq -c --arg value "${MANAGED_DIRS[index]}" '. + [$value]' <<< "$dirs")"; done
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    id="tmux-native-config-v1.$TMUX_NATIVE_ORIGIN"
    attachments="$(jq -cn --arg id "$id" --arg path "$TMUX_NATIVE_PATH" --arg hash "$(sha256_string "$TMUX_NATIVE_BLOCK")" \
      '[{id:$id,path:$path,content_hash:$hash}]')"
  fi
  jq -cn --arg profile "$SELECTED_PROFILE" --arg checkout "$CHECKOUT_ROOT" --arg target "$TARGET_ROOT" \
    --argjson packages "$packages" --argjson targets "$targets" --argjson dirs "$dirs" --argjson attachments "$attachments" \
    '{schema_version:1,profile:$profile,area:"tmux",checkout_root:$checkout,target_root:$target,packages:$packages,targets:$targets,managed_directories:$dirs,attachments:$attachments,backups:[]}'
}

apply_tmux() {
  local state_json
  begin_transaction
  remove_recorded_links_for_apply
  apply_stow_packages
  validate_applied_targets
  fault tmux-after-stow
  install_tmux_attachment
  fault tmux-after-attachment
  validate_tmux_isolated_config deployed
  fault tmux-after-isolated-validation
  retire_tmux_legacy_link
  fault tmux-after-migration
  state_json="$(build_tmux_state_json)"
  write_transaction_string_atomic "$state_json" "$AREA_STATE" 0600
  fault tmux-after-state
  TRANSACTION_ACTIVE=false
  report_tmux_active_server_guidance
  log "applied tmux area for profile '$SELECTED_PROFILE'"
}

remove_tmux() {
  local state="$HOME/.local/state/dotfiles/v1/tmux.json" count index dir
  local managed_directories=()
  init_tmux_area
  if [[ ! -e "$state" && ! -L "$state" ]]; then
    log "area 'tmux' is not deployed; no changes made"
    return 0
  fi
  validate_state_file "$state"
  [[ "$(jq -r .target_root "$state")" == "$TARGET_ROOT" ]] || die 'existing tmux state belongs to a different target root'
  SELECTED_PROFILE="$(jq -r .profile "$state")"
  count="$(jq '.targets | length' "$state")"
  for ((index=0; index<count; index++)); do validate_recorded_target "$state" "$index"; done
  validate_tmux_attachments_from_state "$state"
  while IFS= read -r dir; do validate_home_directory "$HOME/$dir"; managed_directories+=("$dir"); done \
    < <(jq -r '.managed_directories[]' "$state")
  AREA_STATE="$state"; OLD_STATE=true; TARGET_PATHS=()
  while IFS= read -r dir; do TARGET_PATHS+=("$dir"); done < <(jq -r '.targets[].path' "$state")
  configure_tmux_journal
  begin_transaction
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    remove_guarded_attachment "$TMUX_NATIVE_PATH" "$TMUX_NATIVE_BEGIN" "$TMUX_NATIVE_END" "$TMUX_NATIVE_TOKEN" \
      "$TMUX_NATIVE_BLOCK" append "$TMUX_NATIVE_ORIGIN"
  fi
  fault tmux-remove-after-attachment
  for ((index=0; index<count; index++)); do remove_recorded_target "$state" "$index"; done
  fault tmux-remove-after-links
  remove_current_regular_path "$state" 'tmux area state'
  fault tmux-remove-after-state
  prune_managed_directories "${managed_directories[@]}"
  TRANSACTION_ACTIVE=false
  log 'removed managed tmux configuration and state; retained plugins, Resurrect data, and migration ledger'
}
