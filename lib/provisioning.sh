# Locked retained-tool provisioning and executable ownership; sourced by bootstrap.sh.

PROVISIONING_MANIFEST=""
PROVISIONING_RECEIPT=""
PROVISIONING_MANIFEST_SHA=""
PROVISIONING_PLATFORM=""
PROVISION_TOOL_IDS=()
MISE_BIN=""
PROVISIONING_RECEIPT_IDENTITY=""
PROVISIONING_RECEIPT_READ_IDENTITY=""
PROVISIONING_RECEIPT_READ_CONTENT=""
PROVISION_INSTALL_ACTIVE=false
PROVISION_INSTALL_COMMITTED=false
PROVISION_INSTALL_PATH=""
PROVISION_INSTALL_IDENTITY=""
PROVISION_INSTALL_LINK=""
PROVISION_INSTALL_LINK_IDENTITY=""
PROVISION_INSTALL_LAUNCHER=""
PROVISION_INSTALL_LAUNCHER_IDENTITY=""
PROVISION_INSTALL_LAUNCHER_QUARANTINE=""
PROVISION_INSTALL_LAUNCHER_QUARANTINE_IDENTITY=""
PROVISION_INSTALL_RECEIPT_IDENTITY=""
PROVISION_INSTALL_RECEIPT_QUARANTINE=""
PROVISION_INSTALL_RECEIPT_QUARANTINE_IDENTITY=""

provisioning_safe_path() {
  safe_relative_path "$1" && [[ "$1" != */ && "$1" != *//* ]]
}

provisioning_path_tree_identity() {
  local root="$1" path relative value=""
  local paths=()
  [[ -e "$root" || -L "$root" ]] || { PROVISIONING_TREE_IDENTITY=absent; return 0; }
  shopt -s dotglob globstar nullglob
  paths=("$root" "$root"/**)
  shopt -u dotglob globstar nullglob
  for path in "${paths[@]}"; do
    capture_path_identity "$path" || return 1
    relative="${path#"$root"}"
    value+="$relative|$PATH_IDENTITY"$'\n'
  done
  PROVISIONING_TREE_IDENTITY="$(sha256_string "$value")"
}

provisioning_allocate_quarantine() {
  local path="$1" candidate
  candidate="$(mktemp "${path%/*}/.${path##*/}.dotfiles-provisioning-quarantine.XXXXXX")"
  rm -- "$candidate"
  printf '%s' "$candidate"
}

provisioning_quarantine_expected_path() {
  local path="$1" expected="$2" description="$3" quarantine actual
  capture_path_identity "$path" || return 1
  [[ "$PATH_IDENTITY" == "$expected" && "$expected" != absent ]] || return 1
  quarantine="$(provisioning_allocate_quarantine "$path")"
  mv -nT -- "$path" "$quarantine" 2>/dev/null || return 1
  capture_path_identity "$quarantine" || return 1
  actual="$PATH_IDENTITY"
  if [[ "$actual" != "$expected" ]]; then
    if [[ ! -e "$path" && ! -L "$path" ]]; then mv -nT -- "$quarantine" "$path" 2>/dev/null || true; fi
    return 1
  fi
  track_temp_path "$quarantine"
  PROVISIONING_QUARANTINE_PATH="$quarantine"
}

provisioning_restore_quarantine() {
  local quarantine="$1" expected="$2" path="$3"
  [[ -n "$quarantine" && ! -e "$path" && ! -L "$path" ]] || return 1
  capture_path_identity "$quarantine" || return 1
  [[ "$PATH_IDENTITY" == "$expected" ]] || return 1
  mv -nT -- "$quarantine" "$path" 2>/dev/null || return 1
  [[ ! -e "$quarantine" && ! -L "$quarantine" ]]
}

provisioning_remove_installed_path() {
  local path="$1" expected="$2" description="$3" quarantine actual
  [[ -n "$path" && -n "$expected" ]] || return 0
  capture_path_identity "$path" || return 1
  if [[ "$PATH_IDENTITY" != "$expected" ]]; then
    printf '[%s] error: retained changed %s for manual recovery at %s\n' "$SCRIPT_NAME" "$description" "$path" >&2
    return 1
  fi
  quarantine="$(provisioning_allocate_quarantine "$path")"
  mv -nT -- "$path" "$quarantine" 2>/dev/null || return 1
  capture_path_identity "$quarantine" || return 1
  actual="$PATH_IDENTITY"
  if [[ "$actual" != "$expected" ]]; then
    if [[ ! -e "$path" && ! -L "$path" ]]; then mv -nT -- "$quarantine" "$path" 2>/dev/null || true; fi
    printf '[%s] error: retained changed %s for manual recovery at %s\n' "$SCRIPT_NAME" "$description" "$path" >&2
    return 1
  fi
  track_temp_path "$quarantine"
  discard_tracked_temp_path "$quarantine" "retained provisioning $description rollback"
}

provisioning_remove_installed_tree() {
  local path="$1" expected="$2" quarantine
  [[ -n "$path" && -n "$expected" ]] || return 0
  if ! provisioning_path_tree_identity "$path" || [[ "$PROVISIONING_TREE_IDENTITY" != "$expected" ]]; then
    printf '[%s] error: retained changed provisioning destination for manual recovery at %s\n' "$SCRIPT_NAME" "$path" >&2
    return 1
  fi
  quarantine="$(provisioning_allocate_quarantine "$path")"
  mv -nT -- "$path" "$quarantine" 2>/dev/null || return 1
  if ! provisioning_path_tree_identity "$quarantine" || [[ "$PROVISIONING_TREE_IDENTITY" != "$expected" ]]; then
    if [[ ! -e "$path" && ! -L "$path" ]]; then mv -nT -- "$quarantine" "$path" 2>/dev/null || true; fi
    printf '[%s] error: retained changed provisioning root for manual recovery at %s\n' "$SCRIPT_NAME" "$path" >&2
    return 1
  fi
  track_temp_path "$quarantine"
  discard_tracked_temp_path "$quarantine" 'retained provisioning root rollback'
}

provisioning_discard_quarantine() {
  local quarantine="$1" expected="$2" description="$3"
  [[ -n "$quarantine" ]] || return 0
  capture_path_identity "$quarantine" || return 1
  [[ "$PATH_IDENTITY" == "$expected" ]] || {
    printf '[%s] error: retained changed %s quarantine for manual recovery at %s\n' \
      "$SCRIPT_NAME" "$description" "$quarantine" >&2
    return 1
  }
  discard_tracked_temp_path "$quarantine" "retained provisioning $description quarantine"
}

reset_retained_provisioning_transaction() {
  PROVISION_INSTALL_ACTIVE=true; PROVISION_INSTALL_COMMITTED=false
  PROVISION_INSTALL_PATH=""; PROVISION_INSTALL_IDENTITY=""
  PROVISION_INSTALL_LINK=""; PROVISION_INSTALL_LINK_IDENTITY=""
  PROVISION_INSTALL_LAUNCHER=""; PROVISION_INSTALL_LAUNCHER_IDENTITY=""
  PROVISION_INSTALL_LAUNCHER_QUARANTINE=""; PROVISION_INSTALL_LAUNCHER_QUARANTINE_IDENTITY=""
  PROVISION_INSTALL_RECEIPT_IDENTITY=""
  PROVISION_INSTALL_RECEIPT_QUARANTINE=""; PROVISION_INSTALL_RECEIPT_QUARANTINE_IDENTITY=""
}

cleanup_retained_provisioning_transaction() {
  local failed=false
  [[ "$PROVISION_INSTALL_ACTIVE" == true && "$PROVISION_INSTALL_COMMITTED" == false ]] || return 0
  if [[ -n "$PROVISION_INSTALL_RECEIPT_IDENTITY" ]]; then
    provisioning_remove_installed_path "$PROVISIONING_RECEIPT" "$PROVISION_INSTALL_RECEIPT_IDENTITY" \
      'provisioning receipt' || failed=true
  fi
  if [[ -n "$PROVISION_INSTALL_RECEIPT_QUARANTINE" ]]; then
    provisioning_restore_quarantine "$PROVISION_INSTALL_RECEIPT_QUARANTINE" \
      "$PROVISION_INSTALL_RECEIPT_QUARANTINE_IDENTITY" "$PROVISIONING_RECEIPT" || failed=true
  fi
  if [[ -n "$PROVISION_INSTALL_LAUNCHER_IDENTITY" ]]; then
    provisioning_remove_installed_path "$PROVISION_INSTALL_LAUNCHER" "$PROVISION_INSTALL_LAUNCHER_IDENTITY" \
      'protected launcher' || failed=true
  fi
  if [[ -n "$PROVISION_INSTALL_LAUNCHER_QUARANTINE" ]]; then
    provisioning_restore_quarantine "$PROVISION_INSTALL_LAUNCHER_QUARANTINE" \
      "$PROVISION_INSTALL_LAUNCHER_QUARANTINE_IDENTITY" "$PROVISION_INSTALL_LAUNCHER" || failed=true
  fi
  [[ -z "$PROVISION_INSTALL_LINK" ]] || \
    provisioning_remove_installed_path "$PROVISION_INSTALL_LINK" "$PROVISION_INSTALL_LINK_IDENTITY" 'mise link' || failed=true
  [[ -z "$PROVISION_INSTALL_PATH" ]] || \
    provisioning_remove_installed_tree "$PROVISION_INSTALL_PATH" "$PROVISION_INSTALL_IDENTITY" || failed=true
  PROVISION_INSTALL_ACTIVE=false
  [[ "$failed" == false ]]
}

validate_provisioning_manifest() {
  local schema="$DOTFILES_DIR/schemas/provisioning-manifest-v1.schema.json"
  local proposal="$DOTFILES_DIR/manifests/proposals/2026-07-17-stage5-tool-pins.json"
  local value host url
  PROVISIONING_MANIFEST="$DOTFILES_DIR/manifests/provisioning.json"
  [[ -f "$schema" && ! -L "$schema" ]] || die 'missing provisioning manifest schema'
  [[ -f "$PROVISIONING_MANIFEST" && ! -L "$PROVISIONING_MANIFEST" ]] || die 'missing provisioning manifest'
  [[ -f "$proposal" && ! -L "$proposal" ]] || die 'missing accepted Stage 5 pin proposal'
  jq -e '.schema_version == 1 and .status == "accepted-for-preverified-link-installation" and
    .accepted_manifest == "manifests/provisioning.json" and
    (.previous_manifest_sha256s | type == "array" and unique == . and all(.[]; type == "string" and test("^[0-9a-f]{64}$")))' \
    "$proposal" >/dev/null || die 'invalid accepted Stage 5 pin proposal'
  jq -e '.type == "object" and .properties.schema_version.const == 1' "$schema" >/dev/null 2>&1 || \
    die 'invalid provisioning manifest schema'
  jq -e '
    type == "object" and keys == ["mise","platforms","schema_version","tools"] and
    .schema_version == 1 and
    (.platforms | type == "array" and length > 0 and all(.[]; . == "linux-x86_64") and unique == .) and
    (.mise | type == "object" and keys == ["artifact","destination","maximum_version","minimum_version","version"] and
      (.version | type == "string" and test("^[0-9]+[.][0-9]+[.][0-9]+$")) and
      (.minimum_version | type == "string" and test("^[0-9]+[.][0-9]+[.][0-9]+$")) and
      (.maximum_version | type == "string" and test("^[0-9]+[.][0-9]+[.][0-9]+$"))) and
    (.tools | type == "array" and length > 0 and all(.[];
      type == "object" and
       ((keys - ["areas","artifact","backend","commands","executable_identity","id","install_root","native_minimum","native_package","owner_policy","profiles","scope","version"]) | length == 0) and
      (["areas","artifact","backend","commands","id","install_root","owner_policy","profiles","scope","version"] - keys | length == 0) and
      (.id | type == "string" and test("^[a-z0-9-]+$")) and
      (.scope == "core" or .scope == "foundation") and
      (.areas | type == "array" and unique == . and all(.[]; type == "string" and test("^[a-z0-9-]+$"))) and
      (.profiles | type == "array" and length > 0 and unique == . and all(.[]; . == "generic" or . == "wsl")) and
      (.owner_policy == "locked-mise" or .owner_policy == "native-or-locked-mise") and
      (if .owner_policy == "native-or-locked-mise" then
        (.native_minimum | type == "string") and (.native_package | type == "string" and test("^[a-z0-9+.-]+$"))
       else (has("native_minimum") | not) and (has("native_package") | not) end) and
      (.backend | type == "string" and test("^(core:[a-z0-9-]+|aqua:[a-z0-9._-]+/[a-z0-9._-]+)$")) and
       (.version | type == "string" and test("^[0-9][0-9A-Za-z.-]*$")) and
       (if .id == "tmux" then
          (.executable_identity | type == "object" and keys == ["mode","sha256","size"] and
            .mode == "0755" and (.size | type == "number" and . > 0) and
            (.sha256 | type == "string" and test("^[0-9a-f]{64}$")))
        else (has("executable_identity") | not) end) and
      (.commands | type == "array" and length == 1 and all(.[];
        type == "object" and keys == ["launcher","name","path","probe_args","protected","version_pattern"] and
        (.name | type == "string" and test("^[a-z0-9-]+$")) and
        (.path | type == "string") and (.probe_args | type == "array" and length > 0 and all(.[]; type == "string")) and
        (.version_pattern | type == "string" and length > 0) and (.protected | type == "boolean") and
        (.launcher == null or (.launcher | type == "string")))))) and
    ([.tools[].id] | unique | length) == (.tools | length) and
    ([.tools[].commands[].name] | unique | length) == ([.tools[].commands[].name] | length) and
    ([.tools[].commands[].launcher | select(. != null)] | unique | length) == ([.tools[].commands[].launcher | select(. != null)] | length) and
    ([.tools[].install_root] | unique | length) == (.tools | length) and
    ([.tools[].artifact.url] | unique | length) == (.tools | length) and
    ([(.mise.artifact), (.tools[].artifact)] | all(.[];
      type == "object" and keys == ["allowed_origins","executable","format","inventory_sha256","platform","sha256","strip_components","url"] and
      .platform == "linux-x86_64" and (.url | type == "string" and test("^https://[^[:space:]]+$")) and
      (.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.inventory_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.format == "raw" or .format == "tar.gz" or .format == "tar.xz") and
      (.executable | type == "string") and (.strip_components == 0 or .strip_components == 1) and
      (.allowed_origins | type == "array" and length > 0 and unique == . and all(.[]; type == "string" and test("^[a-z0-9.-]+$")))))
  ' "$PROVISIONING_MANIFEST" >/dev/null || die 'malformed or unknown provisioning manifest'

  while IFS= read -r value; do provisioning_safe_path "$value" || die "unsafe provisioning path: $value"; done < <(
    jq -r '.mise.destination, .mise.artifact.executable, .tools[].install_root, .tools[].artifact.executable, .tools[].commands[].path, .tools[].commands[].launcher // empty' "$PROVISIONING_MANIFEST"
  )
  while IFS=$'\t' read -r url host; do
    [[ "$url" =~ ^https://([^/:?#]+)(/|$) ]] || die "invalid provisioning URL: $url"
    [[ "${BASH_REMATCH[1]}" == "$host" ]] || die "artifact origin is not allowlisted: $url"
  done < <(jq -r '[(.mise.artifact), (.tools[].artifact)][] | .url as $url | .allowed_origins[] | select($url | startswith("https://" + .)) | [$url, .] | @tsv' "$PROVISIONING_MANIFEST")
  # Every artifact must match at least one exact allowlisted host.
  while IFS= read -r url; do
    host="${url#https://}"; host="${host%%/*}"
    jq -e --arg url "$url" --arg host "$host" '[(.mise.artifact), (.tools[].artifact)][] | select(.url == $url) | .allowed_origins | index($host) != null' \
      "$PROVISIONING_MANIFEST" >/dev/null || die "artifact origin is not allowlisted: $url"
  done < <(jq -r '.mise.artifact.url, .tools[].artifact.url' "$PROVISIONING_MANIFEST")
  while IFS=$'\t' read -r value host url; do
    [[ "$value" == ".local/share/dotfiles/provisioning/tools/$host/$url" ]] || \
      die "tool install root is not canonical for $host"
  done < <(jq -r '.tools[] | [.install_root,.id,.version] | @tsv' "$PROVISIONING_MANIFEST")
  while IFS=$'\t' read -r value host; do
    [[ "$value" == "$host" ]] || die 'tool command path does not match its verified artifact executable'
  done < <(jq -r '.tools[] | [.commands[0].path,.artifact.executable] | @tsv' "$PROVISIONING_MANIFEST")
  while IFS= read -r value; do
    [[ -n "${AREA_STATUS[$value]+x}" ]] || die "provisioning manifest references unknown area '$value'"
  done < <(jq -r '.tools[].areas[]' "$PROVISIONING_MANIFEST")
  if jq -er '[.tools[].id, .tools[].backend, .tools[].commands[].name] | join("\n") | test("(^|\n)(opencode|opencode-openai-codex-auth|vite\\+?)(\n|$)"; "i")' \
    "$PROVISIONING_MANIFEST" | grep -qx true; then
    die 'provisioning manifest contains a Stage 5 excluded tool'
  fi
  PROVISIONING_MANIFEST_SHA="$(sha256_file "$PROVISIONING_MANIFEST")"
}

detect_provisioning_platform() {
  local machine
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_ARCH:-}" ]]; then
    machine="$DOTFILES_TEST_ARCH"
  else
    machine="$(uname -m)"
  fi
  case "$machine" in
    x86_64|amd64) PROVISIONING_PLATFORM=linux-x86_64 ;;
    *) die "unsupported provisioning architecture '$machine'" ;;
  esac
  jq -e --arg platform "$PROVISIONING_PLATFORM" '.platforms | index($platform) != null' "$PROVISIONING_MANIFEST" >/dev/null || \
    die "provisioning manifest does not support $PROVISIONING_PLATFORM"
}

validate_provisioning_receipt() {
  local value id backend version platform root executable expected_backend destination receipt_manifest active_version hash before
  PROVISIONING_RECEIPT="$HOME/.local/state/dotfiles/provisioning/v1/receipt.json"
  validate_home_parent_chain "$PROVISIONING_RECEIPT"
  capture_path_identity "$PROVISIONING_RECEIPT" || die 'provisioning receipt changed before validation'
  before="$PATH_IDENTITY"
  PROVISIONING_RECEIPT_IDENTITY="$before"
  [[ "$before" != absent ]] || return 0
  [[ -f "$PROVISIONING_RECEIPT" && ! -L "$PROVISIONING_RECEIPT" ]] || die 'provisioning receipt is symlinked or not a regular file'
  [[ "$(stat -c '%u:%a' -- "$PROVISIONING_RECEIPT")" == "$EUID:600" ]] || \
    die 'provisioning receipt has an unsafe owner or mode'
  jq -e '
    type == "object" and keys == ["launchers","manifest_sha256","schema_version","tools"] and .schema_version == 1 and
    (.manifest_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.tools | type == "array" and all(.[]; type == "object" and keys == ["backend","executable","executable_sha256","id","install_root","platform","version"] and
      (.executable_sha256 | type == "string" and test("^[0-9a-f]{64}$"))) and ([.[].id] | unique | length) == length) and
    (.launchers | type == "array" and all(.[]; type == "object" and keys == ["content_sha256","destination","tool_id"] and
      (.content_sha256 | type == "string" and test("^[0-9a-f]{64}$"))) and ([.[].destination] | unique | length) == length)
  ' "$PROVISIONING_RECEIPT" >/dev/null || die 'malformed or newer provisioning receipt'
  receipt_manifest="$(jq -r .manifest_sha256 "$PROVISIONING_RECEIPT")"
  if [[ "$receipt_manifest" != "$PROVISIONING_MANIFEST_SHA" ]]; then
    jq -e --arg hash "$receipt_manifest" '.previous_manifest_sha256s | index($hash) != null' \
      "$DOTFILES_DIR/manifests/proposals/2026-07-17-stage5-tool-pins.json" >/dev/null 2>&1 || \
      die 'provisioning receipt manifest identity is not accepted'
  fi
  while IFS= read -r value; do provisioning_safe_path "$value" || die "unsafe path in provisioning receipt: $value"; done < <(
    jq -r '.tools[].install_root, .tools[].executable, .launchers[].destination' "$PROVISIONING_RECEIPT"
  )
  while IFS=$'\t' read -r id backend version platform root executable; do
    if [[ "$id" == mise ]]; then
      destination="$(jq -r '.mise.destination' "$PROVISIONING_MANIFEST")"
      active_version="$(jq -r '.mise.version' "$PROVISIONING_MANIFEST")"
      [[ "$backend" == bootstrap:mise && "$version" == "$active_version" && "$platform" == "$PROVISIONING_PLATFORM" &&
        "$root" == "${destination%/*}" && "$executable" == "${destination##*/}" ]] || \
        die 'mise provisioning receipt identity does not match the active lock'
      hash="$(jq -r --arg id mise '.tools[] | select(.id == $id) | .executable_sha256' "$PROVISIONING_RECEIPT")"
      [[ -f "$HOME/$root/$executable" && ! -L "$HOME/$root/$executable" && "$(sha256_file "$HOME/$root/$executable")" == "$hash" ]] || \
        die 'mise provisioning receipt executable identity is invalid'
      continue
    fi
    expected_backend="$(jq -er --arg id "$id" '.tools[] | select(.id == $id) | .backend' "$PROVISIONING_MANIFEST" 2>/dev/null)" || \
      die "provisioning receipt contains unknown tool '$id'"
    [[ "$backend" == "$expected_backend" && "$platform" == "$PROVISIONING_PLATFORM" ]] || \
      die "provisioning receipt owner identity is invalid for $id"
    [[ "$root" == ".local/share/dotfiles/provisioning/tools/$id/"* ]] || \
      die "provisioning receipt install root is stale for $id"
  done < <(jq -r '.tools[] | [.id,.backend,.version,.platform,.install_root,.executable] | @tsv' "$PROVISIONING_RECEIPT")
  while IFS=$'\t' read -r id destination; do
    [[ "$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .commands[0].launcher // empty' "$PROVISIONING_MANIFEST")" == "$destination" ]] || \
      die "provisioning receipt launcher identity is invalid for $id"
  done < <(jq -r '.launchers[] | [.tool_id,.destination] | @tsv' "$PROVISIONING_RECEIPT")
  test_hold after-provisioning-receipt-validation-read
  capture_path_identity "$PROVISIONING_RECEIPT" || die 'provisioning receipt changed during validation'
  [[ "$PATH_IDENTITY" == "$before" ]] || die 'provisioning receipt changed during validation'
  PROVISIONING_RECEIPT_IDENTITY="$PATH_IDENTITY"
}

select_provisioning_tools() {
  local id scope profile area selected
  PROVISION_TOOL_IDS=()
  while IFS=$'\t' read -r id scope profile; do
    [[ "$profile" == "$SELECTED_PROFILE" ]] || continue
    selected=false
    if [[ "$EXPLICIT_AREA_SELECTION" == false ]]; then
      selected=true
    else
      while IFS= read -r area; do
        if array_contains "$area" "${AREAS[@]}" && [[ "${AREA_PREFLIGHT_OK[$area]:-false}" == true ]]; then selected=true; fi
      done < <(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .areas[]' "$PROVISIONING_MANIFEST")
    fi
    [[ "$selected" == true ]] && ! array_contains "$id" "${PROVISION_TOOL_IDS[@]}" && PROVISION_TOOL_IDS+=("$id")
  done < <(jq -r '.tools[] | .id as $id | .scope as $scope | .profiles[] | [$id,$scope,.] | @tsv' "$PROVISIONING_MANIFEST")
  return 0
}

version_at_least() {
  local actual="$1" minimum="$2" first
  first="$(printf '%s\n%s\n' "$actual" "$minimum" | sort -V | while IFS= read -r line; do printf '%s' "$line"; break; done)"
  [[ "$first" == "$minimum" ]]
}

path_candidates() {
  local name="$1" component candidate
  local components=()
  IFS=':' read -r -a components <<< "${PATH:-}"
  for component in "${components[@]}"; do
    [[ -n "$component" ]] || component=.
    candidate="$component/$name"
    [[ -f "$candidate" && -x "$candidate" ]] && printf '%s\n' "$candidate"
  done
}

resolve_mise_owner() {
  local candidate resolved version output status
  local candidates=() approved=()
  MISE_BIN=""
  if declare -F mise >/dev/null || [[ "$(type -t mise 2>/dev/null || true)" == alias ]]; then
    log 'error: mise is shadowed by a shell function or alias'
    return 1
  fi
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && ! array_contains "$candidate" "${candidates[@]}" && candidates+=("$candidate")
  done < <(path_candidates mise)
  for candidate in "${candidates[@]}"; do
    resolved="$(realpath -e -- "$candidate")" || { log "error: broken mise PATH candidate: $candidate"; return 1; }
    case "$candidate" in
      "$HOME/.local/bin/mise")
        [[ ! -L "$candidate" && "$resolved" == "$candidate" ]] || { log 'error: user mise must be a directly owned regular executable'; return 1; }
        approved+=("$candidate")
        ;;
      /usr/bin/mise|/usr/local/bin/mise)
        [[ ! -L "$candidate" && "$resolved" == "$candidate" ]] || { log "error: system mise symlink is not approved: $candidate"; return 1; }
        [[ "$(dpkg-query -S "$candidate" 2>/dev/null || true)" == mise:* ]] || { log "error: system mise has no approved package owner: $candidate"; return 1; }
        approved+=("$candidate")
        ;;
      *) log "error: unapproved mise PATH candidate: $candidate"; return 1 ;;
    esac
  done
  ((${#approved[@]} <= 1)) || { log 'error: ambiguous approved mise executables in PATH'; return 1; }
  if ((${#approved[@]} == 0)); then
    local destination="$HOME/$(jq -r '.mise.destination' "$PROVISIONING_MANIFEST")"
    if [[ -e "$destination" || -L "$destination" ]]; then
      [[ -f "$destination" && ! -L "$destination" && -x "$destination" && "$(realpath -e -- "$destination")" == "$destination" ]] || {
        log "error: mise destination conflict: $destination"; return 1;
      }
      approved+=("$destination")
    else
      return 2
    fi
  fi
  MISE_BIN="${approved[0]}"
  if output="$(run_mise_isolated "$MISE_BIN" --version 2>/dev/null)"; then status=0; else status=$?; fi
  if ((status != 0)); then
    log 'error: accepted mise version probe failed'
    case "$status" in 130|143) return "$status" ;; *) return 1 ;; esac
  fi
  IFS= read -r output <<< "$output"
  [[ "$output" =~ ([0-9]+[.][0-9]+[.][0-9]+) ]] || { log 'error: accepted mise returned an invalid version'; return 1; }
  version="${BASH_REMATCH[1]}"
  version_at_least "$version" "$(jq -r '.mise.minimum_version' "$PROVISIONING_MANIFEST")" || {
    log "error: existing mise $version is older than the accepted minimum"; return 1;
  }
  version_at_least "$(jq -r '.mise.maximum_version' "$PROVISIONING_MANIFEST")" "$version" || {
    log "error: existing mise $version is newer than the tested compatibility range"; return 1;
  }
  return 0
}

run_mise_isolated() {
  local binary="$1"; shift
  local temp status
  temp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise-env.XXXXXX")"
  set +e
  unshare --user --map-root-user --net env MISE_OFFLINE=1 MISE_YES=1 MISE_GLOBAL_CONFIG_FILE="$temp/global.toml" \
    MISE_CONFIG_DIR="$temp/config" MISE_CACHE_DIR="$temp/cache" MISE_STATE_DIR="$temp/state" \
    MISE_DATA_DIR="$temp/data" "$binary" "$@"
  status=$?
  set -e
  rm -rf -- "$temp"
  return "$status"
}

mise_link_path() {
  local backend="$1" version="$2"
  if [[ "$backend" == core:* ]]; then
    backend="${backend#core:}"
  else
    backend="${backend//:/-}"
    backend="${backend//\//-}"
  fi
  printf '%s/.local/share/mise/installs/%s/%s' "$HOME" "$backend" "$version"
}

run_mise_write() {
  local binary="$1"; shift
  local temp status
  temp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise-write.XXXXXX")"
  set +e
  MISE_OFFLINE=1 MISE_YES=1 MISE_GLOBAL_CONFIG_FILE="$temp/global.toml" \
    MISE_CONFIG_DIR="$temp/config" MISE_CACHE_DIR="$temp/cache" MISE_STATE_DIR="$temp/state" \
    MISE_DATA_DIR="$HOME/.local/share/mise" "$binary" "$@"
  status=$?
  set -e
  rm -rf -- "$temp"
  return "$status"
}

run_offline_probe() {
  local executable="$1"; shift
  local temp status
  temp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tool-probe.XXXXXX")"
  set +e
  unshare --user --map-root-user --net env -i HOME="$temp/home" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$temp/config" XDG_DATA_HOME="$temp/data" \
    XDG_STATE_HOME="$temp/state" XDG_CACHE_HOME="$temp/cache" MISE_OFFLINE=1 NO_COLOR=1 \
    "$executable" "$@"
  status=$?
  set -e
  rm -rf -- "$temp"
  return "$status"
}

check_selected_provisioning_dependencies() {
  local command package format existing
  local commands=(curl sha256sum sort env unshare)
  local packages=(curl coreutils coreutils coreutils util-linux)
  local missing=()
  local missing_packages=()
  for format in $(jq -r --argjson ids "$(jq -cn '$ARGS.positional' --args "${PROVISION_TOOL_IDS[@]}")" \
    '.tools[] | select(.id as $id | $ids | index($id) != null) | .artifact.format' "$PROVISIONING_MANIFEST"); do
    [[ "$format" == raw ]] || { commands+=(tar); packages+=(tar); }
    [[ "$format" != tar.xz ]] || { commands+=(xz); packages+=(xz-utils); }
  done
  for command in "${!commands[@]}"; do
    command_capability_exists "${commands[command]}" && continue
    array_contains "${commands[command]}" "${missing[@]}" || missing+=("${commands[command]}")
    package="${packages[command]}"; existing=false
    array_contains "$package" "${missing_packages[@]}" && existing=true
    [[ "$existing" == true ]] || missing_packages+=("$package")
  done
  ((${#missing[@]} == 0)) && return 0
  printf '[%s] error: missing provisioning prerequisites; install packages with:\n' "$SCRIPT_NAME" >&2
  printf '%s' "${DEPENDENCY_APT_INSTALL[0]}" >&2
  for command in "${DEPENDENCY_APT_INSTALL[@]:1}"; do printf ' %s' "$command" >&2; done
  printf ' %s' "${missing_packages[@]}" >&2
  printf '\n' >&2
  return 1
}

url_host_allowed() {
  local url="$1" allowed_json="$2" host
  [[ "$url" =~ ^https://([^/:?#]+)(/|$) ]] || return 1
  host="${BASH_REMATCH[1]}"
  jq -en --arg host "$host" --argjson allowed "$allowed_json" '$allowed | index($host) != null' >/dev/null
}

download_locked_artifact() {
  local id="$1" artifact_json="$2" destination="$3"
  local url allowed expected headers status location line redirects=0
  url="$(jq -r .url <<< "$artifact_json")"
  allowed="$(jq -c .allowed_origins <<< "$artifact_json")"
  expected="$(jq -r .sha256 <<< "$artifact_json")"
  while :; do
    ((redirects <= 5)) || die "too many redirects downloading $id"
    url_host_allowed "$url" "$allowed" || die "download redirect for $id uses an unapproved origin: $url"
    headers="$(mktemp "${TMPDIR:-/tmp}/dotfiles-download-headers.XXXXXX")"
    track_temp_path "$headers"
    curl --silent --show-error --fail --proto '=https' --max-redirs 0 --dump-header "$headers" --output "$destination" "$url"
    status=""; location=""
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ "$line" != HTTP/* ]] || { status="${line#* }"; status="${status%% *}"; }
      [[ "${line,,}" != location:* ]] || { location="${line#*:}"; location="${location# }"; }
    done < "$headers"
    case "$status" in
      2??) break ;;
      3??) [[ -n "$location" ]] || die "redirect for $id omitted Location"; url="$location"; ((redirects += 1)) ;;
      *) die "unexpected HTTP status ${status:-unknown} downloading $id" ;;
    esac
  done
  [[ "$(sha256_file "$destination")" == "$expected" ]] || die "artifact checksum mismatch for $id"
}

archive_members_safe() {
  local archive="$1" format="$2" expected_inventory="$3" member details actual_inventory
  local tar_args=()
  case "$format" in tar.gz) tar_args=(-tzf) ;; tar.xz) tar_args=(-tJf) ;; *) return 1 ;; esac
  actual_inventory="$(tar "${tar_args[@]}" "$archive" | sha256sum | while read -r hash _; do printf '%s' "$hash"; done)" || return 1
  [[ "$actual_inventory" == "$expected_inventory" ]] || return 1
  while IFS= read -r member || [[ -n "$member" ]]; do
    member="${member#./}"
    [[ -n "$member" && "$member" != /* && "/$member/" != *'/../'* &&
      "$member" != *$'\n'* && "$member" != *$'\r'* ]] || return 1
  done < <(tar "${tar_args[@]}" "$archive")
  details="$(tar "${tar_args[@]/-t/-tv}" "$archive")" || return 1
  while IFS= read -r member || [[ -n "$member" ]]; do
    case "${member:0:1}" in -|d|l) ;; *) return 1 ;; esac
  done <<< "$details"
}

extracted_links_safe() {
  local root="$1" canonical path resolved
  canonical="$(realpath -e -- "$root")" || return 1
  (
    shopt -s dotglob globstar nullglob
    for path in "$root"/**; do
      [[ -L "$path" ]] || continue
      resolved="$(realpath -m -- "$path")" || return 1
      [[ "$resolved" == "$canonical"/* ]] || return 1
    done
  )
}

extract_locked_artifact() {
  local artifact_json="$1" archive="$2" root="$3"
  local format executable strip inventory
  format="$(jq -r .format <<< "$artifact_json")"
  executable="$(jq -r .executable <<< "$artifact_json")"
  strip="$(jq -r .strip_components <<< "$artifact_json")"
  inventory="$(jq -r .inventory_sha256 <<< "$artifact_json")"
  mkdir -- "$root"
  case "$format" in
    raw)
      if [[ "$executable" == */* ]]; then ensure_directory "$root/${executable%/*}"; fi
      cp -- "$archive" "$root/$executable"
      chmod 0755 "$root/$executable"
      ;;
    tar.gz|tar.xz)
      archive_members_safe "$archive" "$format" "$inventory" || die 'artifact archive inventory is unexpected or unsafe'
      if [[ "$format" == tar.gz ]]; then
        tar -xzf "$archive" --no-same-owner --no-same-permissions --strip-components="$strip" -C "$root"
      else
        tar -xJf "$archive" --no-same-owner --no-same-permissions --strip-components="$strip" -C "$root"
      fi
      extracted_links_safe "$root" || die 'artifact contains a symlink outside its install root'
      ;;
  esac
  [[ -f "$root/$executable" && ! -L "$root/$executable" && -x "$root/$executable" ]] || \
    die "artifact did not contain expected executable $executable"
}

launcher_content() {
  local executable="$1"
  printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$executable"
}

launcher_hash() {
  sha256_string "$1"$'\n'
}

receipt_launcher_hash() {
  local destination="$1"
  [[ -f "$PROVISIONING_RECEIPT" ]] || return 1
  jq -er --arg destination "$destination" '.launchers[] | select(.destination == $destination) | .content_sha256' "$PROVISIONING_RECEIPT" 2>/dev/null
}

preflight_launcher() {
  local destination_rel="$1" content="$2" destination old_hash current_hash
  destination="$HOME/$destination_rel"
  PREFLIGHT_LAUNCHER_IDENTITY=""
  validate_home_parent_chain "$destination"
  capture_path_identity "$destination" || { log "error: launcher destination changed during preflight: $destination"; return 1; }
  PREFLIGHT_LAUNCHER_IDENTITY="$PATH_IDENTITY"
  [[ -e "$destination" || -L "$destination" ]] || return 0
  [[ -f "$destination" && ! -L "$destination" ]] || { log "error: launcher destination conflict: $destination"; return 1; }
  current_hash="$(sha256_file "$destination")"
  [[ "$current_hash" == "$(launcher_hash "$content")" ]] && return 0
  old_hash="$(receipt_launcher_hash "$destination_rel" || true)"
  [[ -n "$old_hash" && "$current_hash" == "$old_hash" ]] || { log "error: unrelated launcher destination conflict: $destination"; return 1; }
}

tool_receipt_valid() {
  local id="$1" root executable expected actual backend version platform active_root active_executable active_backend active_version link_path
  local identity_mode identity_size identity_sha
  [[ -f "$PROVISIONING_RECEIPT" ]] || return 1
  root="$(jq -er --arg id "$id" '.tools[] | select(.id == $id) | .install_root' "$PROVISIONING_RECEIPT" 2>/dev/null)" || return 1
  executable="$(jq -er --arg id "$id" '.tools[] | select(.id == $id) | .executable' "$PROVISIONING_RECEIPT" 2>/dev/null)" || return 1
  expected="$(jq -er --arg id "$id" '.tools[] | select(.id == $id) | .executable_sha256' "$PROVISIONING_RECEIPT" 2>/dev/null)" || return 1
  backend="$(jq -er --arg id "$id" '.tools[] | select(.id == $id) | .backend' "$PROVISIONING_RECEIPT" 2>/dev/null)" || return 1
  version="$(jq -er --arg id "$id" '.tools[] | select(.id == $id) | .version' "$PROVISIONING_RECEIPT" 2>/dev/null)" || return 1
  platform="$(jq -er --arg id "$id" '.tools[] | select(.id == $id) | .platform' "$PROVISIONING_RECEIPT" 2>/dev/null)" || return 1
  active_root="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .install_root' "$PROVISIONING_MANIFEST")"
  active_executable="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .artifact.executable' "$PROVISIONING_MANIFEST")"
  active_backend="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .backend' "$PROVISIONING_MANIFEST")"
  active_version="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .version' "$PROVISIONING_MANIFEST")"
  [[ "$root" == "$active_root" && "$executable" == "$active_executable" && "$backend" == "$active_backend" &&
    "$version" == "$active_version" && "$platform" == "$PROVISIONING_PLATFORM" ]] || return 1
  [[ -f "$HOME/$root/$executable" && ! -L "$HOME/$root/$executable" && -x "$HOME/$root/$executable" ]] || return 1
  actual="$(sha256_file "$HOME/$root/$executable")"
  [[ "$actual" == "$expected" ]] || return 1
  if jq -e --arg id "$id" '.tools[] | select(.id == $id) | has("executable_identity")' \
    "$PROVISIONING_MANIFEST" >/dev/null; then
    IFS=$'\t' read -r identity_mode identity_size identity_sha < <(jq -r --arg id "$id" '
      .tools[] | select(.id == $id) |
      [.executable_identity.mode, (.executable_identity.size | tostring), .executable_identity.sha256] | @tsv
    ' "$PROVISIONING_MANIFEST")
    [[ "$(stat -c '0%a:%s' -- "$HOME/$root/$executable")" == "$identity_mode:$identity_size" &&
      "$actual" == "$identity_sha" && "$expected" == "$identity_sha" ]] || return 1
  fi
  link_path="$(mise_link_path "$backend" "$version")"
  [[ -L "$link_path" && "$(realpath -e -- "$link_path")" == "$HOME/$root" ]]
}

native_tool_suitable() {
  local id="$1" name args pattern minimum package path resolved output version owner
  [[ "$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .owner_policy' "$PROVISIONING_MANIFEST")" == native-or-locked-mise ]] || return 1
  name="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .commands[0].name' "$PROVISIONING_MANIFEST")"
  ! declare -F "$name" >/dev/null || return 1
  [[ "$(type -t -- "$name" 2>/dev/null || true)" != alias ]] || return 1
  path="$(type -P -- "$name" 2>/dev/null || true)"
  [[ "$path" == /usr/bin/* || "$path" == /bin/* ]] || return 1
  resolved="$(realpath -e -- "$path" 2>/dev/null || true)"
  [[ "$resolved" == /usr/bin/* || "$resolved" == /bin/* ]] || return 1
  package="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .native_package' "$PROVISIONING_MANIFEST")"
  owner="$(dpkg-query -S "$resolved" 2>/dev/null || true)"
  [[ "$owner" == "$package:"* || "$owner" == "$package:"*:* ]] || return 1
  mapfile -t args < <(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .commands[0].probe_args[]' "$PROVISIONING_MANIFEST")
  output="$(run_offline_probe "$resolved" "${args[@]}" 2>/dev/null)" || return 1
  IFS= read -r output <<< "$output"
  case "$id" in
    tmux) [[ "$output" =~ ^tmux[[:space:]]+(.+)$ ]] || return 1; version="${BASH_REMATCH[1]}" ;;
    neovim) [[ "$output" =~ ^NVIM[[:space:]]+v(.+)$ ]] || return 1; version="${BASH_REMATCH[1]}" ;;
    starship) [[ "$output" =~ ^starship[[:space:]]+([^[:space:]]+) ]] || return 1; version="${BASH_REMATCH[1]}" ;;
    *) return 1 ;;
  esac
  minimum="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .native_minimum' "$PROVISIONING_MANIFEST")"
  version_at_least "$version" "$minimum"
}

verify_tool_probe() {
  local id="$1" executable="$2" pattern output
  local args=()
  mapfile -t args < <(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .commands[0].probe_args[]' "$PROVISIONING_MANIFEST")
  pattern="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .commands[0].version_pattern' "$PROVISIONING_MANIFEST")"
  output="$(run_offline_probe "$executable" "${args[@]}" 2>/dev/null)" || return 1
  IFS= read -r output <<< "$output"
  [[ "$output" =~ $pattern ]]
}

resolve_protected_command() {
  local name="$1" expected="$2" candidate resolved first="" expected_resolved index
  local candidates=()
  if declare -F "$name" >/dev/null || [[ "$(type -t -- "$name" 2>/dev/null || true)" == alias ]]; then
    log "error: protected command '$name' is shadowed by a shell function or alias"
    return 1
  fi
  expected_resolved="$(realpath -e -- "$expected" 2>/dev/null)" || { log "error: protected owner is missing for '$name': $expected"; return 1; }
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    ! array_contains "$candidate" "${candidates[@]}" && candidates+=("$candidate")
  done < <(path_candidates "$name")
  ((${#candidates[@]} > 0)) || { log "error: protected command '$name' is not in PATH"; return 1; }
  first="$(realpath -e -- "${candidates[0]}")" || return 1
  [[ "$first" == "$expected_resolved" ]] || {
    log "error: protected command '$name' is shadowed by ${candidates[0]}"; return 1;
  }
  [[ ! -L "${candidates[0]}" ]] || { log "error: protected command '$name' resolves through a symlink"; return 1; }
  for ((index=1; index<${#candidates[@]}; index++)); do
    candidate="${candidates[index]}"
    resolved="$(realpath -e -- "$candidate")" || return 1
    case "$candidate" in
      /usr/bin/"$name"|/bin/"$name") ;;
      *) log "error: protected command '$name' has an unapproved additional PATH candidate: $candidate"; return 1 ;;
    esac
  done
}

provision_tool_status() {
  local id="$1" root executable launcher name content content_hash
  native_tool_suitable "$id" && return 0
  root="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .install_root' "$PROVISIONING_MANIFEST")"
  executable="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .artifact.executable' "$PROVISIONING_MANIFEST")"
  tool_receipt_valid "$id" || {
    [[ ! -e "$HOME/$root" && ! -L "$HOME/$root" ]] || log "error: unreceipted or drifted retained install for $id: $HOME/$root"
    return 1
  }
  verify_tool_probe "$id" "$HOME/$root/$executable" || { log "error: version probe drift for $id"; return 1; }
  launcher="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .commands[0].launcher // empty' "$PROVISIONING_MANIFEST")"
  if [[ -n "$launcher" ]]; then
    name="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .commands[0].name' "$PROVISIONING_MANIFEST")"
    content="$(launcher_content "$HOME/$root/$executable")"
    content_hash="$(launcher_hash "$content")"
    jq -e --arg id "$id" --arg destination "$launcher" --arg hash "$content_hash" '
      [.launchers[] | select(.tool_id == $id)] ==
      [{tool_id:$id,destination:$destination,content_sha256:$hash}]
    ' "$PROVISIONING_RECEIPT" >/dev/null 2>&1 || return 1
    [[ -f "$HOME/$launcher" && ! -L "$HOME/$launcher" && "$(stat -c %a -- "$HOME/$launcher")" == 755 &&
      "$(sha256_file "$HOME/$launcher")" == "$content_hash" ]] || return 1
    resolve_protected_command "$name" "$HOME/$launcher" || return 1
  fi
  return 0
}

print_provisioning_plan() {
  local id installed=missing status
  log 'provisioning network plan (no download has started):'
  if ((${#PROVISION_TOOL_IDS[@]} == 0)); then
    log 'no runtime-tool network actions are selected'
    return 0
  fi
  if resolve_mise_owner; then status=0; else status=$?; fi
  if ((status == 0)); then
    installed=compatible
  elif ((status != 2)); then
    case "$status" in 70|130|143) return "$status" ;; *) return 1 ;; esac
  fi
  if [[ "$installed" == missing ]]; then
    jq -r '"  mise: installed=missing target=" + .mise.version + " artifact=" + .mise.artifact.url + " origins=" + (.mise.artifact.allowed_origins | join(",")) + " destination=~/" + .mise.destination' "$PROVISIONING_MANIFEST"
  fi
  for id in "${PROVISION_TOOL_IDS[@]}"; do
    if provision_tool_status "$id"; then
      continue
    fi
    jq -r --arg id "$id" '.tools[] | select(.id == $id) | "  " + .id + ": target=" + .version + " backend=" + .backend + " artifact=" + .artifact.url + " origins=" + (.artifact.allowed_origins | join(",")) + " root=~/" + .install_root' "$PROVISIONING_MANIFEST"
  done
}

ensure_receipt_file() {
  local dir content expected
  if [[ -e "$PROVISIONING_RECEIPT" || -L "$PROVISIONING_RECEIPT" ]]; then
    read_provisioning_receipt
    [[ -z "$PROVISIONING_RECEIPT_IDENTITY" ||
      "$PROVISIONING_RECEIPT_READ_IDENTITY" == "$PROVISIONING_RECEIPT_IDENTITY" ]] || \
      die 'provisioning receipt appeared or changed since transaction start'
    PROVISIONING_RECEIPT_IDENTITY="$PROVISIONING_RECEIPT_READ_IDENTITY"
    return 0
  fi
  dir="${PROVISIONING_RECEIPT%/*}"
  ensure_directory "$dir"
  capture_path_identity "$PROVISIONING_RECEIPT" || die 'provisioning receipt changed before creation'
  expected="$PATH_IDENTITY"
  [[ "$expected" == absent && ( -z "$PROVISIONING_RECEIPT_IDENTITY" ||
    "$PROVISIONING_RECEIPT_IDENTITY" == absent ) ]] || \
    die 'provisioning receipt destination appeared concurrently'
  content="$(jq -cn --arg hash "$PROVISIONING_MANIFEST_SHA" '{schema_version:1,manifest_sha256:$hash,tools:[],launchers:[]}')"
  write_string_atomic "$content" "$PROVISIONING_RECEIPT" 0600 "$expected"
  verify_provisioning_receipt_write "$content"
}

read_provisioning_receipt() {
  local before
  validate_home_parent_chain "$PROVISIONING_RECEIPT"
  capture_path_identity "$PROVISIONING_RECEIPT" || die 'provisioning receipt changed before it was read'
  before="$PATH_IDENTITY"
  [[ "$before" != absent && -f "$PROVISIONING_RECEIPT" && ! -L "$PROVISIONING_RECEIPT" ]] || \
    die 'provisioning receipt is symlinked, absent, or not a regular file'
  [[ "$(stat -c '%u:%a' -- "$PROVISIONING_RECEIPT")" == "$EUID:600" ]] || \
    die 'provisioning receipt has an unsafe owner or mode'
  PROVISIONING_RECEIPT_READ_CONTENT="$(< "$PROVISIONING_RECEIPT")"
  test_hold after-provisioning-receipt-read
  capture_path_identity "$PROVISIONING_RECEIPT" || die 'provisioning receipt changed while it was read'
  [[ "$PATH_IDENTITY" == "$before" ]] || die 'provisioning receipt changed while it was read'
  PROVISIONING_RECEIPT_READ_IDENTITY="$before"
}

verify_provisioning_receipt_write() {
  local content="$1" expected_identity="${2:-}"
  [[ -f "$PROVISIONING_RECEIPT" && ! -L "$PROVISIONING_RECEIPT" ]] || \
    die 'provisioning receipt post-state is not a regular file'
  [[ "$(stat -c '%u:%a' -- "$PROVISIONING_RECEIPT")" == "$EUID:600" ]] || \
    die 'provisioning receipt post-state has an unsafe owner or mode'
  [[ "$(sha256_file "$PROVISIONING_RECEIPT")" == "$(sha256_string "$content"$'\n')" ]] || \
    die 'provisioning receipt post-state has unexpected content'
  capture_path_identity "$PROVISIONING_RECEIPT" || die 'provisioning receipt post-state is unreadable'
  [[ -z "$expected_identity" || "$PATH_IDENTITY" == "$expected_identity" ]] || \
    die 'provisioning receipt changed during post-state verification'
  PROVISIONING_RECEIPT_IDENTITY="$PATH_IDENTITY"
}

write_receipt_update() {
  local content="$1" expected="$2"
  write_string_atomic "$content" "$PROVISIONING_RECEIPT" 0600 "$expected"
  verify_provisioning_receipt_write "$content"
}

record_tool_receipt() {
  local id="$1" backend="$2" version="$3" root="$4" executable="$5" hash content expected
  hash="$(sha256_file "$HOME/$root/$executable")"
  ensure_receipt_file
  read_provisioning_receipt
  expected="$PROVISIONING_RECEIPT_READ_IDENTITY"
  content="$(jq -c --arg manifest "$PROVISIONING_MANIFEST_SHA" --arg id "$id" --arg backend "$backend" --arg version "$version" \
    --arg platform "$PROVISIONING_PLATFORM" --arg root "$root" --arg executable "$executable" --arg hash "$hash" '
      .manifest_sha256=$manifest | .tools = ([.tools[] | select(.id != $id)] + [{id:$id,backend:$backend,version:$version,platform:$platform,install_root:$root,executable:$executable,executable_sha256:$hash}])
    ' <<< "$PROVISIONING_RECEIPT_READ_CONTENT")"
  write_receipt_update "$content" "$expected"
}

install_transaction_launcher() {
  local destination_rel="$1" content="$2" destination expected="$PREFLIGHT_LAUNCHER_IDENTITY"
  local temporary quarantine=""
  destination="$HOME/$destination_rel"
  ensure_directory "${destination%/*}"
  require_expected_pre_state "$destination" "$expected" 'protected launcher'
  temporary="$(mktemp "${destination%/*}/.${destination##*/}.provisioning-launcher.XXXXXX")"
  track_temp_path "$temporary"
  printf '%s\n' "$content" > "$temporary"
  chmod 0755 "$temporary"
  if [[ "$expected" != absent ]]; then
    provisioning_quarantine_expected_path "$destination" "$expected" 'protected launcher' || \
      die "protected launcher changed before replacement: $destination"
    quarantine="$PROVISIONING_QUARANTINE_PATH"
    PROVISION_INSTALL_LAUNCHER_QUARANTINE="$quarantine"
    PROVISION_INSTALL_LAUNCHER_QUARANTINE_IDENTITY="$expected"
  fi
  install_regular_no_clobber "$temporary" "$destination" 'protected launcher install' "$quarantine"
  capture_path_identity "$destination" || die 'protected launcher post-state is unreadable'
  PROVISION_INSTALL_LAUNCHER="$destination"
  PROVISION_INSTALL_LAUNCHER_IDENTITY="$PATH_IDENTITY"
  [[ -f "$destination" && ! -L "$destination" && "$(stat -c %a -- "$destination")" == 755 &&
    "$(sha256_file "$destination")" == "$(launcher_hash "$content")" ]] || \
    die 'protected launcher post-state differs from its staged content'
}

build_combined_tool_receipt() {
  local id="$1" backend="$2" version="$3" root="$4" executable="$5" launcher="$6" launcher_hash_value="$7"
  local base expected executable_hash
  ensure_directory "${PROVISIONING_RECEIPT%/*}"
  capture_path_identity "$PROVISIONING_RECEIPT" || die 'provisioning receipt changed before combined update'
  expected="$PATH_IDENTITY"
  [[ -z "$PROVISIONING_RECEIPT_IDENTITY" || "$expected" == "$PROVISIONING_RECEIPT_IDENTITY" ]] || \
    die 'provisioning receipt appeared or changed before combined update'
  if [[ "$expected" == absent ]]; then
    base="$(jq -cn --arg hash "$PROVISIONING_MANIFEST_SHA" \
      '{schema_version:1,manifest_sha256:$hash,tools:[],launchers:[]}')"
  else
    read_provisioning_receipt
    [[ "$PROVISIONING_RECEIPT_READ_IDENTITY" == "$expected" ]] || \
      die 'provisioning receipt changed during combined update read'
    base="$PROVISIONING_RECEIPT_READ_CONTENT"
  fi
  executable_hash="$(sha256_file "$HOME/$root/$executable")"
  PROVISIONING_COMBINED_RECEIPT_CONTENT="$(jq -c --arg manifest "$PROVISIONING_MANIFEST_SHA" \
    --arg id "$id" --arg backend "$backend" --arg version "$version" --arg platform "$PROVISIONING_PLATFORM" \
    --arg root "$root" --arg executable "$executable" --arg executable_hash "$executable_hash" \
    --arg launcher "$launcher" --arg launcher_hash "$launcher_hash_value" '
      .manifest_sha256=$manifest |
      .tools = ([.tools[] | select(.id != $id)] + [{id:$id,backend:$backend,version:$version,platform:$platform,
        install_root:$root,executable:$executable,executable_sha256:$executable_hash}]) |
      .launchers = ([.launchers[] | select(.tool_id != $id and .destination != $launcher)] +
        (if $launcher == "" then [] else [{tool_id:$id,destination:$launcher,content_sha256:$launcher_hash}] end))
    ' <<< "$base")"
  PROVISIONING_COMBINED_RECEIPT_EXPECTED="$expected"
}

write_combined_tool_receipt_cas() {
  local content="$1" expected="$2" temporary quarantine=""
  temporary="$(mktemp "${PROVISIONING_RECEIPT%/*}/.receipt.json.provisioning.XXXXXX")"
  track_temp_path "$temporary"
  printf '%s\n' "$content" > "$temporary"
  chmod 0600 "$temporary"
  require_expected_pre_state "$PROVISIONING_RECEIPT" "$expected" 'combined provisioning receipt'
  if [[ "$expected" != absent ]]; then
    provisioning_quarantine_expected_path "$PROVISIONING_RECEIPT" "$expected" 'combined provisioning receipt' || \
      die 'provisioning receipt changed before combined update commit'
    quarantine="$PROVISIONING_QUARANTINE_PATH"
    PROVISION_INSTALL_RECEIPT_QUARANTINE="$quarantine"
    PROVISION_INSTALL_RECEIPT_QUARANTINE_IDENTITY="$expected"
  fi
  install_regular_no_clobber "$temporary" "$PROVISIONING_RECEIPT" 'combined provisioning receipt install' "$quarantine"
  capture_path_identity "$PROVISIONING_RECEIPT" || die 'combined provisioning receipt post-state is unreadable'
  PROVISION_INSTALL_RECEIPT_IDENTITY="$PATH_IDENTITY"
  test_hold provisioning-tool-after-combined-receipt
  fault provisioning-tool-after-combined-receipt
  verify_provisioning_receipt_write "$content" "$PROVISION_INSTALL_RECEIPT_IDENTITY"
}

verify_combined_tool_transaction() {
  local id="$1" backend="$2" version="$3" root_rel="$4" executable="$5" launcher="$6" launcher_hash_value="$7"
  local root
  root="$HOME/$root_rel"
  if [[ -n "$PROVISION_INSTALL_PATH" ]]; then
    provisioning_path_tree_identity "$root" || return 1
    [[ "$PROVISIONING_TREE_IDENTITY" == "$PROVISION_INSTALL_IDENTITY" ]] || return 1
  fi
  if [[ -n "$PROVISION_INSTALL_LINK" ]]; then
    capture_path_identity "$PROVISION_INSTALL_LINK" || return 1
    [[ "$PATH_IDENTITY" == "$PROVISION_INSTALL_LINK_IDENTITY" && -L "$PROVISION_INSTALL_LINK" &&
      "$(realpath -e -- "$PROVISION_INSTALL_LINK" 2>/dev/null || true)" == "$root" ]] || return 1
  fi
  if [[ -n "$launcher" ]]; then
    capture_path_identity "$HOME/$launcher" || return 1
    [[ "$PATH_IDENTITY" == "$PROVISION_INSTALL_LAUNCHER_IDENTITY" && -f "$HOME/$launcher" &&
      ! -L "$HOME/$launcher" && "$(stat -c %a -- "$HOME/$launcher")" == 755 &&
      "$(sha256_file "$HOME/$launcher")" == "$launcher_hash_value" ]] || return 1
  fi
  capture_path_identity "$PROVISIONING_RECEIPT" || return 1
  [[ "$PATH_IDENTITY" == "$PROVISION_INSTALL_RECEIPT_IDENTITY" ]] || return 1
  verify_provisioning_receipt_write "$PROVISIONING_COMBINED_RECEIPT_CONTENT" \
    "$PROVISION_INSTALL_RECEIPT_IDENTITY" || return 1
  tool_receipt_valid "$id" || return 1
  jq -e --arg id "$id" --arg destination "$launcher" --arg hash "$launcher_hash_value" '
    if $destination == "" then ([.launchers[] | select(.tool_id == $id)] | length) == 0
    else [.launchers[] | select(.tool_id == $id)] ==
      [{tool_id:$id,destination:$destination,content_sha256:$hash}] end
  ' "$PROVISIONING_RECEIPT" >/dev/null
}

commit_combined_tool_transaction() {
  local failed=false
  # The verified new receipt is the commit point. Old rollback objects are no
  # longer allowed to trigger reversal of the committed root or launcher.
  PROVISION_INSTALL_COMMITTED=true
  PROVISION_INSTALL_ACTIVE=false
  test_hold provisioning-tool-after-commit-before-cleanup
  if [[ -n "$PROVISION_INSTALL_RECEIPT_QUARANTINE" ]]; then
    if provisioning_discard_quarantine "$PROVISION_INSTALL_RECEIPT_QUARANTINE" \
      "$PROVISION_INSTALL_RECEIPT_QUARANTINE_IDENTITY" 'receipt'; then
      PROVISION_INSTALL_RECEIPT_QUARANTINE=""
    else
      retain_tracked_temp_path "$PROVISION_INSTALL_RECEIPT_QUARANTINE"
      printf '[%s] error: committed provisioning retained old receipt recovery path: %s\n' \
        "$SCRIPT_NAME" "$PROVISION_INSTALL_RECEIPT_QUARANTINE" >&2
      failed=true
    fi
  fi
  if [[ -n "$PROVISION_INSTALL_LAUNCHER_QUARANTINE" ]]; then
    if provisioning_discard_quarantine "$PROVISION_INSTALL_LAUNCHER_QUARANTINE" \
      "$PROVISION_INSTALL_LAUNCHER_QUARANTINE_IDENTITY" 'launcher'; then
      PROVISION_INSTALL_LAUNCHER_QUARANTINE=""
    else
      retain_tracked_temp_path "$PROVISION_INSTALL_LAUNCHER_QUARANTINE"
      printf '[%s] error: committed provisioning retained old launcher recovery path: %s\n' \
        "$SCRIPT_NAME" "$PROVISION_INSTALL_LAUNCHER_QUARANTINE" >&2
      failed=true
    fi
  fi
  [[ "$failed" == false ]]
}

verify_mise_transaction() {
  local version="$1" destination_rel="$2" destination="$HOME/$destination_rel"
  provisioning_path_tree_identity "$destination" || return 1
  [[ "$PROVISIONING_TREE_IDENTITY" == "$PROVISION_INSTALL_IDENTITY" ]] || return 1
  capture_path_identity "$PROVISIONING_RECEIPT" || return 1
  [[ "$PATH_IDENTITY" == "$PROVISION_INSTALL_RECEIPT_IDENTITY" ]] || return 1
  verify_provisioning_receipt_write "$PROVISIONING_COMBINED_RECEIPT_CONTENT" \
    "$PROVISION_INSTALL_RECEIPT_IDENTITY" || return 1
  jq -e --arg version "$version" --arg platform "$PROVISIONING_PLATFORM" \
    --arg root "${destination_rel%/*}" --arg executable "${destination_rel##*/}" \
    --arg hash "$(sha256_file "$destination")" '
      [.tools[] | select(.id == "mise")] == [{id:"mise",backend:"bootstrap:mise",version:$version,
        platform:$platform,install_root:$root,executable:$executable,executable_sha256:$hash}] and
      ([.launchers[] | select(.tool_id == "mise")] | length) == 0
    ' "$PROVISIONING_RECEIPT" >/dev/null
}

install_mise() {
  local artifact destination destination_rel dir payload stage version expected staged_identity staged_tree_identity
  artifact="$(jq -c .mise.artifact "$PROVISIONING_MANIFEST")"
  destination_rel="$(jq -r .mise.destination "$PROVISIONING_MANIFEST")"
  destination="$HOME/$destination_rel"
  version="$(jq -r .mise.version "$PROVISIONING_MANIFEST")"
  validate_home_parent_chain "$destination"
  capture_path_identity "$destination" || die 'mise destination changed at transaction start'
  expected="$PATH_IDENTITY"
  [[ "$expected" == absent ]] || die "mise destination conflict: $destination"
  reset_retained_provisioning_transaction
  dir="${destination%/*}"; ensure_directory "$dir"
  payload="$(mktemp "$dir/.mise-download.XXXXXX")"; track_temp_path "$payload"
  download_locked_artifact mise "$artifact" "$payload"
  test_hold provisioning-mise-after-download
  stage="$(mktemp "$dir/.mise-install.XXXXXX")"; track_temp_path "$stage"
  cp -- "$payload" "$stage"; chmod 0755 "$stage"
  capture_path_identity "$stage" || die 'staged mise identity is unreadable'
  staged_identity="$PATH_IDENTITY"
  provisioning_path_tree_identity "$stage" || die 'staged mise post-state is unreadable'
  staged_tree_identity="$PROVISIONING_TREE_IDENTITY"
  [[ "$expected" == absent ]] || die 'mise transaction did not start from an absent destination'
  install_regular_no_clobber "$stage" "$destination" 'mise install'
  PROVISION_INSTALL_PATH="$destination"; PROVISION_INSTALL_IDENTITY="$staged_tree_identity"
  capture_path_identity "$destination" || die 'installed mise identity is unreadable'
  [[ "$PATH_IDENTITY" == "$staged_identity" ]] || die 'installed mise differs from staging'
  provisioning_path_tree_identity "$destination" || die 'installed mise post-state is unreadable'
  [[ "$PROVISIONING_TREE_IDENTITY" == "$staged_tree_identity" ]] || die 'installed mise post-state differs from staging'
  MISE_BIN="$destination"
  fault provisioning-mise-after-install
  build_combined_tool_receipt mise bootstrap:mise "$version" "${destination_rel%/*}" \
    "${destination_rel##*/}" '' ''
  fault provisioning-mise-before-combined-receipt
  write_combined_tool_receipt_cas "$PROVISIONING_COMBINED_RECEIPT_CONTENT" \
    "$PROVISIONING_COMBINED_RECEIPT_EXPECTED"
  test_hold provisioning-mise-before-commit
  test_signal provisioning-mise-before-commit
  verify_mise_transaction "$version" "$destination_rel" || \
    die 'mise transaction post-state verification failed'
  commit_combined_tool_transaction || die 'mise transaction committed with retained cleanup recovery paths'
}

install_locked_tool() {
  local id="$1" root_rel root parent artifact archive stage executable backend version launcher content link_path
  local root_start_identity staged_identity launcher_hash_value=""
  native_tool_suitable "$id" && { log "$id uses a suitable distro-owned executable"; return 0; }
  root_rel="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .install_root' "$PROVISIONING_MANIFEST")"
  root="$HOME/$root_rel"; parent="${root%/*}"
  artifact="$(jq -c --arg id "$id" '.tools[] | select(.id == $id) | .artifact' "$PROVISIONING_MANIFEST")"
  executable="$(jq -r .executable <<< "$artifact")"
  backend="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .backend' "$PROVISIONING_MANIFEST")"
  version="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .version' "$PROVISIONING_MANIFEST")"
  launcher="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .commands[0].launcher // empty' "$PROVISIONING_MANIFEST")"
  if tool_receipt_valid "$id"; then
    [[ -n "$launcher" ]] || return 0
    content="$(launcher_content "$root/$executable")"
    launcher_hash_value="$(launcher_hash "$content")"
    preflight_launcher "$launcher" "$content" || die "launcher ownership preflight failed for $id"
    reset_retained_provisioning_transaction
    install_transaction_launcher "$launcher" "$content"
    fault provisioning-tool-after-launcher
    build_combined_tool_receipt "$id" "$backend" "$version" "$root_rel" "$executable" \
      "$launcher" "$launcher_hash_value"
    fault provisioning-tool-before-combined-receipt
    write_combined_tool_receipt_cas "$PROVISIONING_COMBINED_RECEIPT_CONTENT" \
      "$PROVISIONING_COMBINED_RECEIPT_EXPECTED"
    test_hold provisioning-tool-before-commit
    verify_combined_tool_transaction "$id" "$backend" "$version" "$root_rel" "$executable" \
      "$launcher" "$launcher_hash_value" || die "retained launcher transaction post-state verification failed for $id"
    test_hold provisioning-tool-before-committed-cleanup
    commit_combined_tool_transaction || die "retained launcher transaction commit failed for $id"
    log "repaired retained launcher for $id"
    return 0
  fi
  capture_path_identity "$root" || die "retained install destination changed at transaction start for $id"
  root_start_identity="$PATH_IDENTITY"
  [[ "$root_start_identity" == absent ]] || die "retained install destination conflict for $id: $root"
  if [[ -n "$launcher" ]]; then
    content="$(launcher_content "$root/$executable")"
    launcher_hash_value="$(launcher_hash "$content")"
    preflight_launcher "$launcher" "$content" || die "launcher ownership preflight failed for $id"
  fi
  link_path="$(mise_link_path "$backend" "$version")"
  if [[ -e "$link_path" || -L "$link_path" ]]; then
    [[ -L "$link_path" && "$(realpath -e -- "$link_path")" == "$root" ]] || \
      die "mise already records unrelated $backend@$version at $link_path"
  fi
  ensure_directory "$parent"
  reset_retained_provisioning_transaction
  archive="$(mktemp "$parent/.$id-download.XXXXXX")"; track_temp_path "$archive"
  download_locked_artifact "$id" "$artifact" "$archive"
  stage="$(mktemp -d "$parent/.$id-install.XXXXXX")"; track_temp_path "$stage"
  extract_locked_artifact "$artifact" "$archive" "$stage/root"
  if jq -e --arg id "$id" '.tools[] | select(.id == $id) | has("executable_identity")' \
    "$PROVISIONING_MANIFEST" >/dev/null; then
    local expected_mode expected_size expected_sha
    IFS=$'\t' read -r expected_mode expected_size expected_sha < <(jq -r --arg id "$id" \
      '.tools[] | select(.id == $id) | [.executable_identity.mode, (.executable_identity.size | tostring), .executable_identity.sha256] | @tsv' \
      "$PROVISIONING_MANIFEST")
    [[ "$(stat -c '0%a:%s' -- "$stage/root/$executable")" == "$expected_mode:$expected_size" && \
      "$(sha256_file "$stage/root/$executable")" == "$expected_sha" ]] || \
      die "installed executable identity did not match lock for $id"
  fi
  verify_tool_probe "$id" "$stage/root/$executable" || die "installed executable version did not match lock for $id"
  provisioning_path_tree_identity "$stage/root" || die "staged retained install identity is unreadable for $id"
  staged_identity="$PROVISIONING_TREE_IDENTITY"
  test_hold provisioning-tool-after-staging
  require_expected_pre_state "$root" "$root_start_identity" 'retained install destination'
  mv -nT -- "$stage/root" "$root" 2>/dev/null || die "retained install could not be installed without clobber for $id"
  [[ ! -e "$stage/root" && ! -L "$stage/root" && -d "$root" && ! -L "$root" ]] || \
    die "retained install destination appeared concurrently for $id: $root"
  PROVISION_INSTALL_PATH="$root"; PROVISION_INSTALL_IDENTITY="$staged_identity"
  provisioning_path_tree_identity "$root" || die "retained install post-state is unreadable for $id"
  [[ "$PROVISIONING_TREE_IDENTITY" == "$staged_identity" ]] || die "retained install differs from staging for $id"
  fault provisioning-tool-after-root
  if ! run_mise_write "$MISE_BIN" link "$backend@$version" "$root" >/dev/null; then
    if [[ -L "$link_path" && "$(realpath -e -- "$link_path" 2>/dev/null || true)" == "$root" ]]; then
      capture_path_identity "$link_path" || die "failed mise link post-state is unreadable for $id"
      PROVISION_INSTALL_LINK="$link_path"; PROVISION_INSTALL_LINK_IDENTITY="$PATH_IDENTITY"
    fi
    die "mise failed to link verified install for $id"
  fi
  [[ -L "$link_path" && "$(realpath -e -- "$link_path")" == "$root" ]] || \
    die "mise link post-state is invalid for $id"
  capture_path_identity "$link_path" || die "mise link post-state is unreadable for $id"
  PROVISION_INSTALL_LINK="$link_path"; PROVISION_INSTALL_LINK_IDENTITY="$PATH_IDENTITY"
  fault provisioning-tool-after-link
  if [[ -n "$launcher" ]]; then
    install_transaction_launcher "$launcher" "$content"
  fi
  fault provisioning-tool-after-launcher
  build_combined_tool_receipt "$id" "$backend" "$version" "$root_rel" "$executable" \
    "$launcher" "$launcher_hash_value"
  fault provisioning-tool-before-combined-receipt
  write_combined_tool_receipt_cas "$PROVISIONING_COMBINED_RECEIPT_CONTENT" \
    "$PROVISIONING_COMBINED_RECEIPT_EXPECTED"
  test_hold provisioning-tool-before-commit
  verify_combined_tool_transaction "$id" "$backend" "$version" "$root_rel" "$executable" \
    "$launcher" "$launcher_hash_value" || die "retained tool transaction post-state verification failed for $id"
  test_hold provisioning-tool-before-committed-cleanup
  commit_combined_tool_transaction || die "retained tool transaction commit failed for $id"
  log "installed locked $id $version"
}

run_provisioning() {
  local plan_printed="${1:-false}" id overall=0 status
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    check_omarchy_neovim_drift
    return
  fi
  if ((${#PROVISION_TOOL_IDS[@]} == 0)); then
    log 'no retained tools are mapped to the selected areas'
    return 0
  fi
  check_selected_provisioning_dependencies || return 1
  if [[ "$plan_printed" != true ]]; then
    if print_provisioning_plan; then status=0; else status=$?; fi
    ((status == 0)) || return "$status"
  fi
  if resolve_mise_owner; then status=0; else status=$?; fi
  if ((status != 0)); then
    if ((status != 2)); then
      case "$status" in 70|130|143) return "$status" ;; *) return 1 ;; esac
    fi
    if [[ "$MODE" == check ]]; then
      overall=1
    else
      install_mise
    fi
  fi
  for id in "${PROVISION_TOOL_IDS[@]}"; do
    if provision_tool_status "$id"; then
      log "$id is converged"
      continue
    fi
    if [[ "$MODE" == check ]]; then
      log "pending locked provisioning: $id"
      overall=1
      continue
    fi
    set +e
    ( set -Eeuo pipefail; trap cleanup EXIT; install_locked_tool "$id" )
    status=$?
    set -e
    if ((status != 0)); then
      case "$status" in 70|130|143) return "$status" ;; esac
      overall=1
    elif ! provision_tool_status "$id"; then
      log "error: $id did not converge to its protected owner after installation"
      overall=1
    fi
  done
  ((overall == 0))
}

check_omarchy_core_drift() {
  local core_file="$HOME/.local/share/omarchy/version" command_file="$HOME/.local/share/omarchy/bin/omarchy-version"
  local installed accepted
  [[ "$SELECTED_PROFILE" == omarchy ]] || return 0
  validate_home_parent_chain "$core_file"
  [[ -f "$core_file" && ! -L "$core_file" ]] || { log 'error: missing or unsafe Omarchy core version metadata'; return 1; }
  [[ -f "$command_file" && ! -L "$command_file" && -x "$command_file" ]] || { log 'error: missing or unsafe native omarchy-version owner'; return 1; }
  local lines=()
  mapfile -t lines < "$core_file"
  ((${#lines[@]} == 1)) && [[ "${lines[0]}" =~ ^v?[0-9]+([.][0-9]+){2}$ ]] || { log 'error: malformed Omarchy core version metadata'; return 1; }
  installed="${lines[0]#v}"
  accepted="$(jq -er '[.sources[] | select(.repository == "https://github.com/basecamp/omarchy") | .release] | unique | if length == 1 then .[0] else error("ambiguous Omarchy release") end' "$DOTFILES_DIR/manifests/sources.json")" || {
    log 'error: active source manifest has no unique Omarchy release'; return 1;
  }
  accepted="${accepted#v}"
  [[ "$installed" == "$accepted" ]] || log "warning: Omarchy core version drift: installed=$installed recorded=$accepted"
}

check_omarchy_neovim_drift() {
  local installed accepted package output path owner
  [[ "$SELECTED_PROFILE" == omarchy ]] || return 0
  declare -F nvim >/dev/null && { log 'error: native nvim is shadowed by an exported function'; return 1; }
  path="$(type -P -- nvim 2>/dev/null || true)"
  [[ -n "$path" ]] || { log 'error: missing native nvim executable'; return 1; }
  path="$(realpath -e -- "$path")" || { log 'error: native nvim executable cannot be resolved'; return 1; }
  owner="$(pacman -Qo "$path" 2>/dev/null)" || { log 'error: native nvim has no pacman owner'; return 1; }
  [[ "$owner" =~ [[:space:]]owned[[:space:]]by[[:space:]]omarchy-nvim[[:space:]] ]] || { log 'error: native nvim is not owned by omarchy-nvim'; return 1; }
  output="$(pacman -Q omarchy-nvim 2>/dev/null)" || { log 'error: missing native omarchy-nvim package'; return 1; }
  [[ "$output" =~ ^omarchy-nvim[[:space:]]+([^[:space:]]+)$ ]] || { log 'error: malformed omarchy-nvim package identity'; return 1; }
  installed="${BASH_REMATCH[1]}"
  package="$(jq -r '.pins[] | select(.id == "omarchy-pkgs") | .package_identity' "$DOTFILES_DIR/manifests/proposals/2026-07-20-stage8-neovim-stable.json")"
  accepted="${package#omarchy-nvim }"
  [[ "$installed" == "$accepted" ]] || log "warning: omarchy-nvim package drift: installed=$installed recorded=$accepted"
}
