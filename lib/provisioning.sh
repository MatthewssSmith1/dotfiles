# Locked retained-tool provisioning and executable ownership; sourced by bootstrap.sh.

PROVISIONING_MANIFEST=""
PROVISIONING_RECEIPT=""
PROVISIONING_MANIFEST_SHA=""
PROVISIONING_PLATFORM=""
PROVISION_TOOL_IDS=()
MISE_BIN=""

provisioning_safe_path() {
  safe_relative_path "$1" && [[ "$1" != */ && "$1" != *//* ]]
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
      ((keys - ["areas","artifact","backend","commands","id","install_root","native_minimum","native_package","owner_policy","profiles","scope","version"]) | length == 0) and
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
  local value id backend version platform root executable expected_backend destination receipt_manifest active_version hash
  PROVISIONING_RECEIPT="$HOME/.local/state/dotfiles/provisioning/v1/receipt.json"
  validate_home_parent_chain "$PROVISIONING_RECEIPT"
  [[ -e "$PROVISIONING_RECEIPT" || -L "$PROVISIONING_RECEIPT" ]] || return 0
  [[ -f "$PROVISIONING_RECEIPT" && ! -L "$PROVISIONING_RECEIPT" ]] || die 'provisioning receipt is symlinked or not a regular file'
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
  local candidate resolved version output
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
  output="$(run_mise_isolated "$MISE_BIN" --version 2>/dev/null)" || { log 'error: accepted mise version probe failed'; return 1; }
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
    TEMP_PATHS+=("$headers")
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
    [[ -n "$member" && "$member" != /* && "/$member/" != *'/../'* ]] || return 1
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
  validate_home_parent_chain "$destination"
  [[ -e "$destination" || -L "$destination" ]] || return 0
  [[ -f "$destination" && ! -L "$destination" ]] || { log "error: launcher destination conflict: $destination"; return 1; }
  current_hash="$(sha256_file "$destination")"
  [[ "$current_hash" == "$(launcher_hash "$content")" ]] && return 0
  old_hash="$(receipt_launcher_hash "$destination_rel" || true)"
  [[ -n "$old_hash" && "$current_hash" == "$old_hash" ]] || { log "error: unrelated launcher destination conflict: $destination"; return 1; }
}

tool_receipt_valid() {
  local id="$1" root executable expected actual backend version platform active_root active_executable active_backend active_version link_path
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
  local id="$1" root executable launcher name content
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
    [[ -f "$HOME/$launcher" && ! -L "$HOME/$launcher" && "$(sha256_file "$HOME/$launcher")" == "$(launcher_hash "$content")" ]] || return 1
    resolve_protected_command "$name" "$HOME/$launcher" || return 1
  fi
  return 0
}

print_provisioning_plan() {
  local id installed=missing status
  log 'provisioning network plan (no download has started):'
  set +e
  resolve_mise_owner
  status=$?
  set -e
  if ((status == 0)); then
    installed=compatible
  elif ((status != 2)); then
    return 1
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
  local dir content
  [[ -f "$PROVISIONING_RECEIPT" ]] && return 0
  dir="${PROVISIONING_RECEIPT%/*}"
  ensure_directory "$dir"
  content="$(jq -cn --arg hash "$PROVISIONING_MANIFEST_SHA" '{schema_version:1,manifest_sha256:$hash,tools:[],launchers:[]}')"
  write_string_atomic "$content" "$PROVISIONING_RECEIPT" 0600
}

write_receipt_update() {
  local content="$1"
  write_string_atomic "$content" "$PROVISIONING_RECEIPT" 0600
}

record_tool_receipt() {
  local id="$1" backend="$2" version="$3" root="$4" executable="$5" hash content
  hash="$(sha256_file "$HOME/$root/$executable")"
  ensure_receipt_file
  content="$(jq -c --arg manifest "$PROVISIONING_MANIFEST_SHA" --arg id "$id" --arg backend "$backend" --arg version "$version" \
    --arg platform "$PROVISIONING_PLATFORM" --arg root "$root" --arg executable "$executable" --arg hash "$hash" '
      .manifest_sha256=$manifest | .tools = ([.tools[] | select(.id != $id)] + [{id:$id,backend:$backend,version:$version,platform:$platform,install_root:$root,executable:$executable,executable_sha256:$hash}])
    ' "$PROVISIONING_RECEIPT")"
  write_receipt_update "$content"
}

record_launcher_receipt() {
  local id="$1" destination="$2" hash="$3" content
  content="$(jq -c --arg id "$id" --arg destination "$destination" --arg hash "$hash" '
    .launchers = ([.launchers[] | select(.destination != $destination)] + [{tool_id:$id,destination:$destination,content_sha256:$hash}])
  ' "$PROVISIONING_RECEIPT")"
  write_receipt_update "$content"
}

install_mise() {
  local artifact destination destination_rel dir payload stage version
  artifact="$(jq -c .mise.artifact "$PROVISIONING_MANIFEST")"
  destination_rel="$(jq -r .mise.destination "$PROVISIONING_MANIFEST")"
  destination="$HOME/$destination_rel"
  version="$(jq -r .mise.version "$PROVISIONING_MANIFEST")"
  validate_home_parent_chain "$destination"
  [[ ! -e "$destination" && ! -L "$destination" ]] || die "mise destination conflict: $destination"
  dir="${destination%/*}"; ensure_directory "$dir"
  payload="$(mktemp "$dir/.mise-download.XXXXXX")"; TEMP_PATHS+=("$payload")
  download_locked_artifact mise "$artifact" "$payload"
  stage="$(mktemp "$dir/.mise-install.XXXXXX")"; TEMP_PATHS+=("$stage")
  cp -- "$payload" "$stage"; chmod 0755 "$stage"
  mv -- "$stage" "$destination"
  MISE_BIN="$destination"
  record_tool_receipt mise bootstrap:mise "$version" "${destination_rel%/*}" mise
}

install_locked_tool() {
  local id="$1" root_rel root parent artifact archive stage executable backend version launcher content link_path
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
    preflight_launcher "$launcher" "$content" || die "launcher ownership preflight failed for $id"
    write_string_atomic "$content" "$HOME/$launcher" 0755
    record_launcher_receipt "$id" "$launcher" "$(launcher_hash "$content")"
    log "repaired retained launcher for $id"
    return 0
  fi
  [[ ! -e "$root" && ! -L "$root" ]] || die "retained install destination conflict for $id: $root"
  if [[ -n "$launcher" ]]; then
    content="$(launcher_content "$root/$executable")"
    preflight_launcher "$launcher" "$content" || die "launcher ownership preflight failed for $id"
  fi
  link_path="$(mise_link_path "$backend" "$version")"
  if [[ -e "$link_path" || -L "$link_path" ]]; then
    [[ -L "$link_path" && "$(realpath -e -- "$link_path")" == "$root" ]] || \
      die "mise already records unrelated $backend@$version at $link_path"
  fi
  ensure_directory "$parent"
  archive="$(mktemp "$parent/.$id-download.XXXXXX")"; TEMP_PATHS+=("$archive")
  download_locked_artifact "$id" "$artifact" "$archive"
  stage="$(mktemp -d "$parent/.$id-install.XXXXXX")"; TEMP_PATHS+=("$stage")
  extract_locked_artifact "$artifact" "$archive" "$stage/root"
  verify_tool_probe "$id" "$stage/root/$executable" || die "installed executable version did not match lock for $id"
  mv -- "$stage/root" "$root"
  if ! run_mise_write "$MISE_BIN" link "$backend@$version" "$root" >/dev/null; then
    rm -rf -- "$root"
    die "mise failed to link verified install for $id"
  fi
  record_tool_receipt "$id" "$backend" "$version" "$root_rel" "$executable"
  if [[ -n "$launcher" ]]; then
    write_string_atomic "$content" "$HOME/$launcher" 0755
    record_launcher_receipt "$id" "$launcher" "$(launcher_hash "$content")"
  fi
  log "installed locked $id $version"
}

run_provisioning() {
  local id overall=0 status
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    check_omarchy_neovim_drift
    return
  fi
  if ((${#PROVISION_TOOL_IDS[@]} == 0)); then
    log 'no retained tools are mapped to the selected areas'
    return 0
  fi
  check_selected_provisioning_dependencies || return 1
  print_provisioning_plan || return 1
  set +e
  resolve_mise_owner
  status=$?
  set -e
  if ((status != 0)); then
    if ((status != 2)); then return 1; fi
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
  package="$(jq -r '.pins[] | select(.id == "omarchy-pkgs") | .package_identity' "$DOTFILES_DIR/manifests/proposals/2026-07-17-initial-pins.json")"
  accepted="${package#omarchy-nvim }"
  [[ "$installed" == "$accepted" ]] || log "warning: omarchy-nvim package drift: installed=$installed recorded=$accepted"
}
