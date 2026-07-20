# Generic deployment engine: manifests, state, transactions, Stow; sourced by bootstrap.sh exactly once.

TX_PATHS=()
TX_EXISTED=()
TX_SNAPSHOTS=()
TX_INITIAL_IDENTITIES=()
TX_EXPECTED_IDENTITIES=()
TX_MUTATED=()
TX_CREATED_DIRS=()
TX_RECOVERY_PATHS=()
TX_QUARANTINE_PATHS=()
TX_DIRECTORY_MOVE_SOURCES=()
TX_DIRECTORY_MOVE_DESTINATIONS=()
TX_DIRECTORY_MOVE_IDENTITIES=()
TX_DIRECTORY_MOVE_DONE=()
declare -A QUARANTINE_IDENTITIES=()
AREA=""
AREA_STATE=""
AREA_JOURNAL_PATHS=()
AREA_ATTACHMENT_VALIDATOR=""
AREA_ORDER=()
MANAGED_DIRS=()
PREFLIGHT_APPROVED_REPLACEMENTS=()
declare -A AREA_STATUS=()
declare -A AREA_DEPENDENCY_OK=()
declare -A AREA_PREFLIGHT_OK=()
declare -A APPROVED_REPLACEMENT_SOURCE=()
declare -A APPROVED_REPLACEMENT_AREA=()
declare -A APPROVED_REPLACEMENT_ACTION=()
declare -A APPROVED_REPLACEMENT_IDENTITY=()
DEPENDENCY_APT_INSTALL=()
DEPENDENCY_AREAS=()
DEPENDENCY_MODES=()
DEPENDENCY_PROFILES=()
DEPENDENCY_COMMANDS=()
DEPENDENCY_MANAGERS=()
DEPENDENCY_PACKAGES=()
DEPENDENCY_CLASSES=()

validate_area_manifest() {
  local manifest="$DOTFILES_DIR/manifests/areas.tsv"
  local line area status
  local fields=() schema_count=0
  [[ -f "$manifest" && ! -L "$manifest" ]] || die 'missing manifests/areas.tsv'
  AREA_ORDER=()
  AREA_STATUS=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != *$'\t'* && "$line" != *' '* ]] || die 'invalid area manifest'
    IFS='|' read -r -a fields <<< "$line"
    case "${fields[0]}" in
      schema)
        ((${#fields[@]} == 2)) && [[ "${fields[1]}" == 1 ]] || die 'invalid area manifest'
        ((schema_count += 1))
        ;;
      area)
        ((${#fields[@]} == 3)) || die 'invalid area manifest'
        area="${fields[1]}"
        status="${fields[2]}"
        [[ "$area" =~ ^[a-z0-9-]+$ ]] || die 'invalid area manifest'
        [[ "$status" == ready || "$status" == framework ]] || die 'invalid area manifest'
        [[ -z "${AREA_STATUS[$area]+x}" ]] || die "duplicate area '$area' in area manifest"
        AREA_ORDER+=("$area")
        AREA_STATUS["$area"]="$status"
        ;;
      *) die 'invalid area manifest' ;;
    esac
  done < "$manifest"
  ((schema_count == 1 && ${#AREA_ORDER[@]} > 0)) || die 'invalid area manifest'
}

validate_dependency_manifest() {
  local manifest="$DOTFILES_DIR/manifests/dependencies.tsv"
  local line kind area modes profiles command manager package class entry alias
  local fields=() schema_count=0 apt_count=0 native_count=0
  [[ -f "$manifest" && ! -L "$manifest" ]] || die 'missing manifests/dependencies.tsv'
  DEPENDENCY_APT_INSTALL=()
  DEPENDENCY_AREAS=()
  DEPENDENCY_MODES=()
  DEPENDENCY_PROFILES=()
  DEPENDENCY_COMMANDS=()
  DEPENDENCY_MANAGERS=()
  DEPENDENCY_PACKAGES=()
  DEPENDENCY_CLASSES=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != *$'\t'* && "$line" != *' '* ]] || die 'invalid dependency manifest'
    IFS='|' read -r -a fields <<< "$line"
    kind="${fields[0]}"
    case "$kind" in
      schema)
        ((${#fields[@]} == 2)) && [[ "${fields[1]}" == 2 ]] || die 'invalid dependency manifest'
        ((schema_count += 1))
        ;;
      manager)
        if [[ "${fields[1]:-}" == apt ]]; then
          ((${#fields[@]} == 6)) && [[ "${fields[*]:2}" == 'sudo apt-get install -y' ]] || \
            die 'invalid dependency manifest'
          DEPENDENCY_APT_INSTALL=("${fields[@]:2}")
          ((apt_count += 1))
        elif [[ "${fields[1]:-}" == native ]]; then
          ((${#fields[@]} == 2)) || die 'invalid dependency manifest'
          ((native_count += 1))
        else
          die 'invalid dependency manifest'
        fi
        ;;
      require)
        ((${#fields[@]} == 8)) || die 'invalid dependency manifest'
        area="${fields[1]}"; modes="${fields[2]}"; profiles="${fields[3]}"
        command="${fields[4]}"; manager="${fields[5]}"; package="${fields[6]}"; class="${fields[7]}"
        IFS='+' read -r -a aliases <<< "$command"
        ((${#aliases[@]} > 0)) || die 'invalid dependency manifest'
        for alias in "${aliases[@]}"; do [[ "$alias" =~ ^[a-z0-9-]+$ ]] || die 'invalid dependency manifest'; done
        for entry in ${area//,/ }; do [[ -n "${AREA_STATUS[$entry]+x}" ]] || die 'invalid dependency manifest'; done
        for entry in ${modes//,/ }; do [[ "$entry" == apply || "$entry" == check || "$entry" == remove || "$entry" == provision ]] || die 'invalid dependency manifest'; done
        for entry in ${profiles//,/ }; do [[ "$entry" == all || "$entry" == generic || "$entry" == wsl || "$entry" == omarchy ]] || die 'invalid dependency manifest'; done
        if [[ "$manager" == apt-package ]]; then
          [[ "$package" =~ ^[a-z0-9+.-]+$ ]] || die 'invalid dependency manifest'
        else
          [[ "$manager" == omarchy-native && "$package" == - ]] || die 'invalid dependency manifest'
        fi
        [[ "$class" == bootstrap-critical || "$class" == area || "$class" == provision ]] || die 'invalid dependency manifest'
        DEPENDENCY_AREAS+=("$area")
        DEPENDENCY_MODES+=("$modes")
        DEPENDENCY_PROFILES+=("$profiles")
        DEPENDENCY_COMMANDS+=("$command")
        DEPENDENCY_MANAGERS+=("$manager")
        DEPENDENCY_PACKAGES+=("$package")
        DEPENDENCY_CLASSES+=("$class")
        ;;
      *) die 'invalid dependency manifest' ;;
    esac
  done < "$manifest"
  ((schema_count == 1 && apt_count == 1 && native_count == 1 && ${#DEPENDENCY_AREAS[@]} > 0)) || \
    die 'invalid dependency manifest'
}

command_capability_exists() {
  local capability="$1" candidate
  local candidates=()
  IFS='+' read -r -a candidates <<< "$capability"
  for candidate in "${candidates[@]}"; do
    [[ "$(type -t -- "$candidate" 2>/dev/null || true)" == file ]] && return 0
  done
  return 1
}

check_manifest_dependencies() {
  local mode="$1" profile="$2" guidance="$3"
  local command manager package class entry existing install_word index selected
  local missing_commands=() missing_packages=() native_missing=() row_areas=()
  DEPENDENCY_CRITICAL_MISSING=false
  PROVISION_DEPENDENCY_MISSING=false
  AREA_DEPENDENCY_OK=()
  for entry in "${AREAS[@]}"; do AREA_DEPENDENCY_OK["$entry"]=true; done

  for index in "${!DEPENDENCY_AREAS[@]}"; do
    selected=false
    IFS=',' read -r -a row_areas <<< "${DEPENDENCY_AREAS[index]}"
    for entry in "${row_areas[@]}"; do
      if array_contains "$entry" "${AREAS[@]}"; then
        selected=true
        break
      fi
    done
    [[ "$selected" == true ]] || continue
    if ! csv_contains "${DEPENDENCY_MODES[index]}" "$mode"; then
      [[ "${PROVISION:-false}" == true ]] && csv_contains "${DEPENDENCY_MODES[index]}" provision || continue
    fi
    if ! csv_contains "${DEPENDENCY_PROFILES[index]}" all &&
      ! csv_contains "${DEPENDENCY_PROFILES[index]}" "$profile"; then
      continue
    fi
    command="${DEPENDENCY_COMMANDS[index]}"
    manager="${DEPENDENCY_MANAGERS[index]}"
    package="${DEPENDENCY_PACKAGES[index]}"
    class="${DEPENDENCY_CLASSES[index]}"
    [[ -n "$command" ]] || continue
    command_capability_exists "$command" && continue
    array_contains "$command" "${missing_commands[@]}" || missing_commands+=("$command")
    [[ "$class" != bootstrap-critical ]] || DEPENDENCY_CRITICAL_MISSING=true
    [[ "$class" != provision ]] || PROVISION_DEPENDENCY_MISSING=true
    if [[ "$class" != provision ]]; then
      for entry in "${row_areas[@]}"; do
        if array_contains "$entry" "${AREAS[@]}"; then AREA_DEPENDENCY_OK["$entry"]=false; fi
      done
    fi
    if [[ "$manager" == apt-package && "$guidance" == true ]]; then
      existing=false
      for entry in "${missing_packages[@]}"; do [[ "$entry" != "$package" ]] || existing=true; done
      [[ "$existing" == true ]] || missing_packages+=("$package")
    elif [[ "$manager" == omarchy-native ]]; then
      native_missing+=("$command")
    fi
  done

  ((${#missing_commands[@]} == 0)) && return 0
  if ((${#native_missing[@]} > 0)); then
    printf '[%s] error: missing required native owner commands:' "$SCRIPT_NAME" >&2
    printf ' %s' "${native_missing[@]}" >&2
    printf '\n' >&2
  elif ((${#missing_packages[@]} > 0)); then
    printf '[%s] error: missing required commands; install packages with:\n' "$SCRIPT_NAME" >&2
    printf '%s' "${DEPENDENCY_APT_INSTALL[0]}" >&2
    for install_word in "${DEPENDENCY_APT_INSTALL[@]:1}"; do printf ' %s' "$install_word" >&2; done
    printf ' %s' "${missing_packages[@]}" >&2
    printf '\n' >&2
  else
    printf '[%s] error: missing removal-required commands:' "$SCRIPT_NAME" >&2
    printf ' %s' "${missing_commands[@]}" >&2
    printf '\n' >&2
  fi
  return 1
}

acquire_lock() {
  exec {HOME_LOCK_FD}<"$HOME"
  if [[ "$MODE" == check ]]; then
    flock --shared --nonblock "$HOME_LOCK_FD" || die 'another mutating deployment holds the HOME lock'
  else
    flock --exclusive --nonblock "$HOME_LOCK_FD" || die 'another deployment holds the HOME lock'
  fi
  test_hold after-lock
}

validate_state_file() {
  local file="$1"
  local schema area basename value areas_json

  validate_home_parent_chain "$file"
  [[ -f "$file" && ! -L "$file" ]] || die "state is not a regular file: $file"
  [[ "$(stat -c %u -- "$file")" == "$EUID" ]] || die "state has an unsafe owner: $file"
  schema="$(jq -er '.schema_version | select(type == "number")' "$file" 2>/dev/null)" || \
    die "malformed or unknown deployment state: $file"
  [[ "$schema" =~ ^[0-9]+$ ]] || die "malformed or unknown deployment state: $file"
  ((schema <= 1)) || die "newer deployment state schema $schema is not supported: $file"
  ((schema == 1)) || die "unknown deployment state schema $schema: $file"
  areas_json="$(jq -cn '$ARGS.positional' --args "${AREA_ORDER[@]}")"
  # This jq expression is the authoritative v1 state validator; keep
  # schemas/deployment-state-v1.schema.json (documentation only) aligned with it.
  jq -e --argjson areas "$areas_json" '
    type == "object" and
    ((keys - ["area","attachments","backups","checkout_root","managed_directories","packages","profile","restored_lock_sha256","schema_version","target_root","targets"]) | length == 0) and
    ((keys | length) == 10 or ((keys | length) == 11 and has("restored_lock_sha256"))) and
    (.profile == "omarchy" or .profile == "generic" or .profile == "wsl") and
    (.area as $recorded | ($areas | index($recorded)) != null) and
    (.checkout_root | type == "string" and startswith("/")) and
    (.target_root | type == "string" and startswith("/")) and
    (.packages | type == "array" and all(.[]; type == "string" and test("^[a-z0-9-]+/[a-z0-9-]+$")) and
      ((unique | length) == length)) and
    (.targets | type == "array" and all(.[];
      type == "object" and (keys == ["path","resolved_source","source"]) and
      (.path | type == "string") and (.source | type == "string" and length > 0) and
      (.resolved_source | type == "string" and startswith("/"))) and
      ((map(.path) | unique | length) == length)) and
    (.managed_directories | type == "array" and all(.[]; type == "string")) and
    (.attachments | type == "array" and all(.[];
      type == "object" and (keys == ["content_hash","id","path"]) and
      (.id | type == "string" and test("^[a-z0-9][a-z0-9.-]*$")) and (.path | type == "string") and
      (.content_hash | type == "string" and test("^[0-9a-f]{64}$"))) and
      ((map(.id) | unique | length) == length) and
      ((map(.path) | unique | length) == length)) and
    (.backups | type == "array" and all(.[]; type == "string") and ((unique | length) == length)) and
    (if has("restored_lock_sha256") then
      .area == "nvim" and (.restored_lock_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
     else true end)
  ' "$file" >/dev/null || die "malformed or unknown deployment state: $file"

  area="$(jq -r .area "$file")"
  basename="${file##*/}"
  [[ "$basename" == "$area.json" ]] || die "state area does not match filename: $file"
  while IFS= read -r value; do safe_relative_path "$value" || die "unsafe target path in state: $value"; done \
    < <(jq -r '.targets[].path, .managed_directories[], .attachments[].path, .backups[]' "$file")
  while IFS= read -r value; do
    [[ "$(realpath -m -s -- "$value")" == "$value" ]] || die "state path is not resolved: $value"
  done < <(jq -r '.checkout_root, .target_root, .targets[].resolved_source' "$file")
}

validate_all_state() {
  local file
  local state_dir="$HOME/.local/state/dotfiles/v1"
  validate_home_directory "$state_dir"
  [[ -d "$state_dir" ]] || return 0
  shopt -s nullglob
  for file in "$state_dir"/*.json; do
    [[ "${file##*/}" == migrations.json ]] && continue
    validate_state_file "$file"
  done
  shopt -u nullglob
}

refuse_profile_mismatch() {
  local file profile
  local state_dir="$HOME/.local/state/dotfiles/v1"
  validate_home_directory "$state_dir"
  [[ -d "$state_dir" ]] || return 0
  shopt -s nullglob
  for file in "$state_dir"/*.json; do
    [[ "${file##*/}" == migrations.json ]] && continue
    profile="$(jq -r .profile "$file")"
    [[ "$profile" == "$SELECTED_PROFILE" ]] || \
      die "existing ${file##*/} state uses profile '$profile'; run --remove before changing profiles"
  done
  shopt -u nullglob
}

load_profile_closure() {
  local requested="$1"
  local file="$DOTFILES_DIR/profiles/$SELECTED_PROFILE.conf"
  local line area closure extra package found=false
  local packages=() seen=()
  PACKAGES=()

  [[ -f "$file" && ! -L "$file" ]] || die "missing profile manifest: $file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != \#* ]] || continue
    read -r area closure extra <<< "$line"
    [[ -n "$area" && -n "$closure" && -z "${extra:-}" ]] || die "malformed profile entry: $line"
    [[ -n "${AREA_STATUS[$area]+x}" ]] || die "profile lists an unknown area: $area"
    if array_contains "$area" "${seen[@]}"; then
      die "duplicate $area closure in $file"
    fi
    seen+=("$area")
    # Profile entries use comma-separated qualified IDs to keep order explicit.
    IFS=',' read -r -a packages <<< "$closure"
    ((${#packages[@]} > 0)) || die "malformed profile entry: $line"
    # Every listed package must exist even when its area is not selected.
    for package in "${packages[@]}"; do validate_package_root "$package"; done
    if [[ "$area" == "$requested" ]]; then
      PACKAGES=("${packages[@]}")
      found=true
    fi
  done < "$file"
  [[ "$found" == true ]] || die "profile has no $requested closure: $file"
}

validate_package_root() {
  local package="$1"
  local layer name root resolved packages_root
  [[ "$package" =~ ^([a-z0-9-]+)/([a-z0-9-]+)$ ]] || die "invalid qualified package ID: $package"
  layer="${BASH_REMATCH[1]}"
  name="${BASH_REMATCH[2]}"
  root="$DOTFILES_DIR/packages/$layer/$name"
  [[ -d "$root" && ! -L "$root" ]] || die "missing package root: packages/$package"
  resolved="$(cd -- "$root" && pwd -P)"
  packages_root="$(cd -- "$DOTFILES_DIR/packages" && pwd -P)"
  [[ "$resolved" == "$packages_root/"* ]] || die "package root escapes packages/: $package"
}

record_managed_parents() {
  local relative="$1"
  local parent="${relative%/*}"
  local path
  [[ "$parent" != "$relative" ]] || return 0
  while [[ -n "$parent" && "$parent" != . ]]; do
    path="$HOME/$parent"
    if declare -F area_retiring_managed_parent >/dev/null && area_retiring_managed_parent "$path"; then
      :
    else
      validate_home_directory "$path"
    fi
    if [[ -e "$path" || -L "$path" ]]; then
      :
    elif ! array_contains "$parent" "${MANAGED_DIRS[@]}"; then
      MANAGED_DIRS+=("$parent")
    fi
    [[ "$parent" == */* ]] || break
    parent="${parent%/*}"
  done
}

scan_packages() {
  local package layer name root path relative source target_parent lexical
  declare -gA TARGET_OWNER=()
  TARGET_PATHS=()
  TARGET_SOURCES=()
  TARGET_LEXICAL=()
  MANAGED_DIRS=()
  PREFLIGHT_APPROVED_REPLACEMENTS=()
  APPROVED_REPLACEMENT_SOURCE=()
  APPROVED_REPLACEMENT_AREA=()
  APPROVED_REPLACEMENT_ACTION=()
  APPROVED_REPLACEMENT_IDENTITY=()
  shopt -s dotglob nullglob globstar
  for package in "${PACKAGES[@]}"; do
    validate_package_root "$package"
    layer="${package%%/*}"
    name="${package#*/}"
    root="$DOTFILES_DIR/packages/$layer/$name"
    for path in "$root"/**/*; do
      relative="${path#"$root"/}"
      [[ "$relative" != .stow-local-ignore ]] || continue
      [[ "$relative" != .empty-package ]] || continue
      if [[ -L "$path" ]]; then
        die "package payload symlinks are not allowed: packages/$package/$relative"
      elif [[ -d "$path" ]]; then
        continue
      elif [[ ! -f "$path" ]]; then
        die "unsupported package payload: packages/$package/$relative"
      fi
      safe_relative_path "$relative" || die "unsafe package payload path: packages/$package/$relative"
      if [[ -n "${TARGET_OWNER[$relative]+x}" ]]; then
        die "duplicate payload target '$relative' in ${TARGET_OWNER[$relative]} and $package"
      fi
      TARGET_OWNER["$relative"]="$package"
      source="$(realpath -e -- "$path")"
      target_parent="$(dirname -- "$HOME/$relative")"
      lexical="$(realpath -m -s --relative-to="$target_parent" -- "$source")"
      TARGET_PATHS+=("$relative")
      TARGET_SOURCES+=("$source")
      TARGET_LEXICAL+=("$lexical")
      record_managed_parents "$relative"
    done
  done
  shopt -u dotglob nullglob globstar
}

state_target_index() {
  local state="$1"
  local relative="$2"
  jq -r --arg path "$relative" '.targets | map(.path == $path) | index(true) // empty' "$state"
}

validate_recorded_target() {
  local state="$1"
  local index="$2"
  local relative source resolved path actual_resolved
  relative="$(jq -r ".targets[$index].path" "$state")"
  source="$(jq -r ".targets[$index].source" "$state")"
  resolved="$(jq -r ".targets[$index].resolved_source" "$state")"
  path="$HOME/$relative"
  validate_home_parent_chain "$path"
  [[ -L "$path" ]] || die "recorded target is no longer a symlink: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "recorded target has an unsafe owner: $path"
  [[ "$(readlink -- "$path")" == "$source" ]] || die "recorded target has different lexical ownership: $path"
  actual_resolved="$(resolve_link "$path")"
  [[ "$actual_resolved" == "$resolved" ]] || die "recorded target has different resolved ownership: $path"
}

legacy_manifest_record() {
  local destination="$1" source_relative="$2" area="$3" action="$4"
  local manifest="$DOTFILES_DIR/manifests/legacy-links.json"
  local host_count record_count

  REVIEWED_LEGACY_ROOT=""
  safe_relative_path "$destination" && safe_relative_path "$source_relative" || return 1
  [[ -f "$manifest" && ! -L "$manifest" ]] || return 1
  host_count="$(jq --arg home "$TARGET_ROOT" '[.hosts[] | select(.home == $home)] | length' "$manifest" 2>/dev/null)" || return 1
  [[ "$host_count" == 1 ]] || return 1
  record_count="$(jq --arg home "$TARGET_ROOT" --arg destination "$destination" --arg source "$source_relative" \
    --arg area "$area" --arg action "$action" \
    '[.hosts[] | select(.home == $home) | .records[] |
      select(.[0] == $destination and .[1] == $source and .[2] == $area and .[4] == $action)] | length' \
    "$manifest" 2>/dev/null)" || return 1
  [[ "$record_count" == 1 ]] || return 1
  REVIEWED_LEGACY_ROOT="$(jq -er --arg home "$TARGET_ROOT" '.hosts[] | select(.home == $home) | .checkout_root |
    select(type == "string" and startswith("/"))' "$manifest" 2>/dev/null)" || return 1
  [[ "$(realpath -m -s -- "$REVIEWED_LEGACY_ROOT")" == "$REVIEWED_LEGACY_ROOT" ]] || return 1
}

legacy_link_owned_by() {
  local path="$1" expected="$2" fallback_source="$3"
  local value lexical resolved

  [[ -L "$path" ]] || return 1
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || return 1
  value="$(readlink -- "$path")"
  if [[ "$value" == /* ]]; then
    lexical="$(realpath -m -s -- "$value")"
  else
    lexical="$(realpath -m -s -- "$(dirname -- "$path")/$value")"
  fi
  [[ "$lexical" == "$expected" ]] || return 1
  resolved="$(resolve_link "$path")"
  [[ "$resolved" == "$expected" ]] || return 1
  if [[ -f "$expected" && ! -L "$expected" ]]; then
    [[ "$(stat -c %u -- "$expected")" == "$EUID" ]] || return 1
    OWNED_LEGACY_SOURCE="$expected"
  else
    [[ -f "$fallback_source" && ! -L "$fallback_source" ]] || return 1
    [[ "$(stat -c %u -- "$fallback_source")" == "$EUID" ]] || return 1
    OWNED_LEGACY_SOURCE="$fallback_source"
  fi
}

owned_legacy_link() {
  local path="$1" destination="$2" source_relative="$3" area="$4" action="$5"
  local current_source="$DOTFILES_DIR/$source_relative"
  local expected

  OWNED_LEGACY_SOURCE=""
  if known_link "$path" "$current_source"; then
    [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || return 1
    [[ -f "$current_source" && ! -L "$current_source" && \
      "$(stat -c %u -- "$current_source")" == "$EUID" ]] || return 1
    OWNED_LEGACY_SOURCE="$current_source"
    return 0
  fi
  [[ -L "$path" ]] || return 1
  legacy_manifest_record "$destination" "$source_relative" "$area" "$action" || return 1
  expected="$REVIEWED_LEGACY_ROOT/$source_relative"
  legacy_link_owned_by "$path" "$expected" "$current_source"
}

reviewed_legacy_link() {
  local path="$1" destination="$2" source_relative="$3" area="$4" action="$5"
  local current_source="$DOTFILES_DIR/$source_relative" expected

  OWNED_LEGACY_SOURCE=""
  legacy_manifest_record "$destination" "$source_relative" "$area" "$action" || return 1
  expected="$REVIEWED_LEGACY_ROOT/$source_relative"
  legacy_link_owned_by "$path" "$expected" "$current_source"
}

validate_attachment_id() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "invalid attachment ID: $1"
}

validate_migration_id() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "invalid migration ID: $1"
}

validate_guarded_block_definition() {
  local begin="$1" end="$2" marker_token="$3" block="$4"
  [[ -n "$begin" && -n "$end" && -n "$marker_token" && "$begin" != "$end" ]] || \
    die 'invalid guarded-block marker definition'
  [[ "$begin" != *$'\n'* && "$begin" != *$'\r'* && "$end" != *$'\n'* && "$end" != *$'\r'* ]] || \
    die 'invalid guarded-block marker definition'
  [[ "$begin" == *"$marker_token"* && "$end" == *"$marker_token"* ]] || \
    die 'guarded-block markers do not contain their marker token'
  [[ "$block" == "$begin"$'\n'* && "$block" == *$'\n'"$end" ]] || \
    die 'guarded block does not contain its exact marker pair'
}

capture_path_identity() {
  local path="$1" before after value hash
  PATH_IDENTITY=""
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    PATH_IDENTITY=absent
    return 0
  fi
  if [[ -L "$path" ]]; then
    before="$(stat -c '%d|%i|%u|%a|%s|%y' -- "$path")" || return 1
    value="$(readlink -- "$path")" || return 1
    after="$(stat -c '%d|%i|%u|%a|%s|%y' -- "$path")" || return 1
    [[ "$before" == "$after" ]] || return 1
    hash="$(sha256_string "$value")"
    PATH_IDENTITY="symlink:$(sha256_string "$before"):$hash"
    return 0
  fi
  if [[ -f "$path" ]]; then
    before="$(stat -c '%d|%i|%u|%a|%s|%y' -- "$path")" || return 1
    hash="$(sha256_file "$path")" || return 1
    after="$(stat -c '%d|%i|%u|%a|%s|%y' -- "$path")" || return 1
    [[ "$before" == "$after" ]] || return 1
    PATH_IDENTITY="regular:$(sha256_string "$before"):$hash"
    return 0
  fi
  before="$(stat -c '%F|%d|%i|%u|%a|%s|%y' -- "$path")" || return 1
  PATH_IDENTITY="other:$(sha256_string "$before")"
}

capture_path_content_identity() {
  local path="$1" before after value hash
  PATH_CONTENT_IDENTITY=""
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    PATH_CONTENT_IDENTITY=absent
    return 0
  fi
  if [[ -L "$path" ]]; then
    before="$(stat -c '%u|%a|%s|%y' -- "$path")" || return 1
    value="$(readlink -- "$path")" || return 1
    after="$(stat -c '%u|%a|%s|%y' -- "$path")" || return 1
    [[ "$before" == "$after" ]] || return 1
    PATH_CONTENT_IDENTITY="symlink:$(sha256_string "$before"):$(sha256_string "$value")"
    return 0
  fi
  if [[ -f "$path" ]]; then
    before="$(stat -c '%u|%a|%s|%y' -- "$path")" || return 1
    hash="$(sha256_file "$path")" || return 1
    after="$(stat -c '%u|%a|%s|%y' -- "$path")" || return 1
    [[ "$before" == "$after" ]] || return 1
    PATH_CONTENT_IDENTITY="regular:$(sha256_string "$before"):$hash"
    return 0
  fi
  before="$(stat -c '%F|%u|%a|%s|%y' -- "$path")" || return 1
  PATH_CONTENT_IDENTITY="other:$(sha256_string "$before")"
}

transaction_path_index() {
  local path="$1" index
  TRANSACTION_PATH_INDEX=""
  for index in "${!TX_PATHS[@]}"; do
    if [[ "${TX_PATHS[index]}" == "$path" ]]; then
      TRANSACTION_PATH_INDEX="$index"
      return 0
    fi
  done
  return 1
}

transaction_pre_identity() {
  local path="$1" index
  transaction_path_index "$path" || die "transaction mutation targets an unjournaled path: $path"
  index="$TRANSACTION_PATH_INDEX"
  if [[ "${TX_MUTATED[index]}" == true ]]; then
    TRANSACTION_PRE_IDENTITY="${TX_EXPECTED_IDENTITIES[index]}"
  else
    TRANSACTION_PRE_IDENTITY="${TX_INITIAL_IDENTITIES[index]}"
  fi
}

require_expected_pre_state() {
  local path="$1" expected="$2" description="$3" actual
  if [[ "$TRANSACTION_ACTIVE" == true && "$TRANSACTION_ROLLING_BACK" == false ]]; then
    transaction_pre_identity "$path"
    [[ "$expected" == "$TRANSACTION_PRE_IDENTITY" ]] || \
      die "$description uses a stale transaction pre-state: $path"
  fi
  capture_path_identity "$path" || die "$description could not inspect its current pre-state: $path"
  actual="$PATH_IDENTITY"
  [[ "$actual" == "$expected" ]] || die "$description changed before mutation: $path"
}

transaction_expected_identity() {
  local path="$1"
  [[ "$TRANSACTION_ACTIVE" == true ]] || die "transaction identity requested outside an active transaction: $path"
  transaction_pre_identity "$path"
  printf '%s' "$TRANSACTION_PRE_IDENTITY"
}

transaction_record_post_state() {
  local path="$1" index
  [[ "$TRANSACTION_ACTIVE" == true ]] || return 0
  transaction_path_index "$path" || die "transaction mutated an unjournaled path: $path"
  index="$TRANSACTION_PATH_INDEX"
  capture_path_identity "$path" || die "could not record transaction post-state: $path"
  TX_EXPECTED_IDENTITIES[index]="$PATH_IDENTITY"
  TX_MUTATED[index]=true
}

transaction_record_expected_state() {
  local path="$1" expected="$2" index
  [[ "$TRANSACTION_ACTIVE" == true ]] || return 0
  [[ "$TRANSACTION_ROLLING_BACK" == false ]] || return 0
  transaction_path_index "$path" || die "transaction mutated an unjournaled path: $path"
  index="$TRANSACTION_PATH_INDEX"
  capture_path_identity "$path" || die "could not verify transaction post-state: $path"
  [[ "$PATH_IDENTITY" == "$expected" ]] || die "transaction post-state differs from the recorded identity: $path"
  TX_EXPECTED_IDENTITIES[index]="$expected"
  TX_MUTATED[index]=true
}

allocate_same_directory_quarantine() {
  local path="$1" dir base candidate
  dir="$(dirname -- "$path")"
  base="${path##*/}"
  candidate="$(mktemp "$dir/.$base.dotfiles-quarantine.XXXXXX")"
  track_temp_path "$candidate"
  discard_tracked_temp_path "$candidate" 'quarantine allocation' || die "could not allocate quarantine path: $candidate"
  QUARANTINE_PATH="$candidate"
}

retain_transaction_recovery_path() {
  local path="$1"
  TRANSACTION_RECOVERY_REQUIRED=true
  array_contains "$path" "${TX_RECOVERY_PATHS[@]:-}" || TX_RECOVERY_PATHS+=("$path")
  printf '[%s] error: concurrent data preserved for manual recovery at %s\n' "$SCRIPT_NAME" "$path" >&2
}

restore_quarantine_no_clobber() {
  local quarantine="$1" path="$2" expected="${3:-${QUARANTINE_IDENTITIES[$1]:-}}"
  [[ -n "$expected" ]] || {
    printf '[%s] error: quarantine identity is unavailable for restoration: %s\n' "$SCRIPT_NAME" "$quarantine" >&2
    retain_transaction_recovery_path "$quarantine"
    return 1
  }
  capture_path_identity "$quarantine" || {
    retain_transaction_recovery_path "$quarantine"
    return 1
  }
  if [[ "$PATH_IDENTITY" != "$expected" ]]; then
    printf '[%s] warning: quarantine was replaced; leaving it in place: %s\n' "$SCRIPT_NAME" "$quarantine" >&2
    retain_transaction_recovery_path "$quarantine"
    return 1
  fi
  if mv -nT -- "$quarantine" "$path" 2>/dev/null &&
    [[ ! -e "$quarantine" && ! -L "$quarantine" ]]; then
    return 0
  fi
  retain_transaction_recovery_path "$quarantine"
  return 1
}

quarantine_expected_path() {
  local path="$1" expected="$2" description="$3" actual
  if [[ "$expected" == absent ]] || ! home_parent_chain_safe "$path"; then
    printf '[%s] error: %s cannot be quarantined safely: %s\n' "$SCRIPT_NAME" "$description" "$path" >&2
    return 1
  fi
  require_expected_pre_state "$path" "$expected" "$description"
  allocate_same_directory_quarantine "$path"
  if ! mv -nT -- "$path" "$QUARANTINE_PATH" 2>/dev/null ||
    [[ -e "$path" || -L "$path" ]] ||
    [[ ! -e "$QUARANTINE_PATH" && ! -L "$QUARANTINE_PATH" ]]; then
    [[ ! -e "$QUARANTINE_PATH" && ! -L "$QUARANTINE_PATH" ]] || \
      retain_transaction_recovery_path "$QUARANTINE_PATH"
    printf '[%s] error: %s changed before it could be quarantined safely: %s\n' "$SCRIPT_NAME" "$description" "$path" >&2
    return 1
  fi
  capture_path_identity "$QUARANTINE_PATH" || {
    restore_quarantine_no_clobber "$QUARANTINE_PATH" "$path" || true
    printf '[%s] error: %s could not be inspected after quarantine: %s\n' "$SCRIPT_NAME" "$description" "$path" >&2
    return 1
  }
  actual="$PATH_IDENTITY"
  if [[ "$actual" != "$expected" ]]; then
    QUARANTINE_IDENTITIES["$QUARANTINE_PATH"]="$actual"
    track_temp_path "$QUARANTINE_PATH"
    restore_quarantine_no_clobber "$QUARANTINE_PATH" "$path" "$actual" || true
    printf '[%s] error: %s changed before mutation; preserved the unexpected object: %s\n' "$SCRIPT_NAME" "$description" "$path" >&2
    return 1
  fi
  QUARANTINE_IDENTITIES["$QUARANTINE_PATH"]="$expected"
  track_temp_path "$QUARANTINE_PATH"
  if [[ "$TRANSACTION_ACTIVE" == true ]]; then
    array_contains "$QUARANTINE_PATH" "${TX_QUARANTINE_PATHS[@]:-}" || \
      TX_QUARANTINE_PATHS+=("$QUARANTINE_PATH")
  fi
  transaction_record_expected_state "$path" absent
}

discard_quarantine() {
  local quarantine="$1" description="$2" expected
  expected="${QUARANTINE_IDENTITIES[$quarantine]:-}"
  if [[ -z "$expected" ]]; then
    printf '[%s] error: %s quarantine identity is unavailable: %s\n' "$SCRIPT_NAME" "$description" "$quarantine" >&2
    [[ "$TRANSACTION_ROLLING_BACK" == true ]] && return 1
    die "$description quarantine identity is unavailable: $quarantine"
  fi
  test_hold before-quarantine-discard
  if ! capture_path_identity "$quarantine"; then
    [[ "$TRANSACTION_ACTIVE" != true ]] || retain_transaction_recovery_path "$quarantine"
    [[ "$TRANSACTION_ROLLING_BACK" == true ]] && return 1
    die "$description quarantine could not be inspected: $quarantine"
  fi
  if [[ "$PATH_IDENTITY" != "$expected" ]]; then
    printf '[%s] warning: %s quarantine was replaced; leaving it in place: %s\n' "$SCRIPT_NAME" "$description" "$quarantine" >&2
    [[ "$TRANSACTION_ACTIVE" != true ]] || retain_transaction_recovery_path "$quarantine"
    [[ "$TRANSACTION_ROLLING_BACK" == true ]] && return 1
    die "$description quarantine changed before discard: $quarantine"
  fi
  if ! discard_tracked_temp_path "$quarantine" "$description quarantine"; then
    [[ "$TRANSACTION_ACTIVE" != true ]] || retain_transaction_recovery_path "$quarantine"
    [[ "$TRANSACTION_ROLLING_BACK" == true ]] && return 1
    die "$description quarantine could not be discarded safely: $quarantine"
  fi
}

install_regular_no_clobber() {
  local source="$1" destination="$2" description="$3" quarantine="${4:-}" expected actual
  capture_path_identity "$source" || die "$description staged file changed before installation: $source"
  expected="$PATH_IDENTITY"
  require_expected_pre_state "$destination" absent "$description destination"
  # -T is essential here: if a directory appears after the identity check,
  # ln must fail rather than install the staged file inside that directory.
  if ! ln -T -- "$source" "$destination" 2>/dev/null; then
    [[ -z "$quarantine" ]] || retain_transaction_recovery_path "$quarantine"
    die "$description destination appeared concurrently; refusing to overwrite: $destination"
  fi
  transaction_record_expected_state "$destination" "$expected"
  capture_path_identity "$destination" || die "$description destination changed during installation: $destination"
  actual="$PATH_IDENTITY"
  [[ "$actual" == "$expected" ]] || die "$description destination was replaced concurrently: $destination"
  discard_tracked_temp_path "$source" "$description staged file" || \
    die "$description staged file could not be discarded safely: $source"
}

replace_with_staged_regular() {
  local source="$1" destination="$2" expected="$3" description="$4" quarantine=""
  test_hold before-atomic-rename
  if [[ "$expected" != absent ]]; then
    quarantine_expected_path "$destination" "$expected" "$description" || \
      die "$description changed before replacement: $destination"
    quarantine="$QUARANTINE_PATH"
  fi
  install_regular_no_clobber "$source" "$destination" "$description" "$quarantine"
  [[ -z "$quarantine" ]] || discard_quarantine "$quarantine" "$description"
}

remove_expected_path() {
  local path="$1" expected="$2" description="$3"
  quarantine_expected_path "$path" "$expected" "$description" || die "$description changed before removal: $path"
  discard_quarantine "$QUARANTINE_PATH" "$description"
}

remove_current_regular_path() {
  local path="$1" description="$2" expected
  [[ -f "$path" && ! -L "$path" ]] || die "$description is no longer a regular file: $path"
  capture_path_identity "$path" || die "$description changed during removal preflight: $path"
  expected="$PATH_IDENTITY"
  remove_expected_path "$path" "$expected" "$description"
}

# Sets GUARDED_BLOCK_STATUS to exact, absent, or malformed. Structural problems
# return 2 so area-specific validators can retain their established diagnostics.
inspect_guarded_block() {
  local file="$1" begin="$2" end="$3" marker_token="$4" block="$5" reject_remnants="${6:-false}"
  local line expected_line inside=false begin_count=0 end_count=0 found="" remnant=false

  validate_guarded_block_definition "$begin" "$end" "$marker_token" "$block"
  GUARDED_BLOCK_STATUS=absent
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$begin" ]]; then
      ((begin_count += 1))
      [[ "$inside" == false ]] || { GUARDED_BLOCK_STATUS=malformed; return 2; }
      inside=true
      found="$line"
    elif [[ "$line" == "$end" ]]; then
      ((end_count += 1))
      [[ "$inside" == true ]] || { GUARDED_BLOCK_STATUS=malformed; return 2; }
      found+=$'\n'"$line"
      inside=false
    elif [[ "$line" == *"$marker_token"* ]]; then
      GUARDED_BLOCK_STATUS=malformed
      return 2
    elif [[ "$inside" == true ]]; then
      found+=$'\n'"$line"
    elif [[ "$reject_remnants" == true ]]; then
      while IFS= read -r expected_line || [[ -n "$expected_line" ]]; do
        [[ -n "$expected_line" && "$expected_line" != "$begin" && "$expected_line" != "$end" ]] || continue
        [[ "$line" != "$expected_line" ]] || remnant=true
      done <<< "$block"
    fi
  done < "$file"
  if [[ "$inside" == true || "$begin_count" != "$end_count" || "$begin_count" -gt 1 ]]; then
    GUARDED_BLOCK_STATUS=malformed
    return 2
  fi
  if ((begin_count == 0)); then
    [[ "$remnant" == false ]] || { GUARDED_BLOCK_STATUS=malformed; return 2; }
    GUARDED_BLOCK_STATUS=absent
    return 1
  fi
  [[ "$found" == "$block" ]] || { GUARDED_BLOCK_STATUS=malformed; return 2; }
  GUARDED_BLOCK_STATUS=exact
}

guarded_attachment_preflight() {
  local relative="$1" begin="$2" end="$3" marker_token="$4" block="$5"
  local placement="$6" absence_policy="$7" path mode status=0

  safe_relative_path "$relative" || die "unsafe guarded attachment path: $relative"
  [[ "$placement" == prepend || "$placement" == append ]] || die "invalid guarded attachment placement: $placement"
  [[ "$absence_policy" == new || "$absence_policy" == exact || "$absence_policy" == refresh ]] || \
    die "invalid guarded attachment absence policy: $absence_policy"
  path="$HOME/$relative"
  validate_home_parent_chain "$path"
  GUARDED_ATTACHMENT_ACTION=none
  GUARDED_ATTACHMENT_IDENTITY=""
  # Area-defined v1 attachment IDs must retain this origin value. In particular,
  # append removal needs to know whether bootstrap inserted a newline separator.
  GUARDED_ATTACHMENT_ORIGIN=""
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    [[ "$absence_policy" == new ]] || die "recorded guarded attachment is absent: $path"
    GUARDED_ATTACHMENT_ACTION=insert
    GUARDED_ATTACHMENT_ORIGIN=created
    GUARDED_ATTACHMENT_IDENTITY=absent
    return 0
  fi
  [[ -f "$path" && ! -L "$path" ]] || die "guarded attachment is not a regular file: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "guarded attachment has an unsafe owner: $path"
  file_contains_nul "$path" && die "guarded attachment contains NUL bytes and cannot be edited safely: $path"
  if [[ ! -s "$path" ]]; then
    GUARDED_ATTACHMENT_ORIGIN=existing-empty
  else
    mode="$(tail -c 1 -- "$path")"
    if [[ -z "$mode" ]]; then
      GUARDED_ATTACHMENT_ORIGIN=existing-final-newline
    else
      GUARDED_ATTACHMENT_ORIGIN=existing-no-final-newline
    fi
  fi
  inspect_guarded_block "$path" "$begin" "$end" "$marker_token" "$block" \
    "$([[ "$absence_policy" == refresh ]] && printf true || printf false)" || status=$?
  case "$status:$GUARDED_BLOCK_STATUS" in
    0:exact) ;;
    1:absent)
      [[ "$absence_policy" == new || "$absence_policy" == refresh ]] || \
        die "recorded guarded attachment is absent: $path"
      GUARDED_ATTACHMENT_ACTION=insert
      ;;
    *) die "guarded attachment is partial, malformed, nested, duplicate, or modified: $path" ;;
  esac
  capture_path_identity "$path" || die "guarded attachment changed during preflight: $path"
  GUARDED_ATTACHMENT_IDENTITY="$PATH_IDENTITY"
}

write_guarded_block_atomic() {
  local relative="$1" block="$2" placement="$3" mode="$4" origin="$5"
  local expected="$6" path="$HOME/$relative" dir base temporary existing_mode quarantine="" source=""

  dir="$(dirname -- "$path")"
  base="${path##*/}"
  ensure_directory "$dir"
  test_hold before-guarded-replacement-quarantine
  if [[ "$expected" != absent ]]; then
    quarantine_expected_path "$path" "$expected" 'guarded attachment destination' || \
      die "guarded attachment changed before mutation: $path"
    quarantine="$QUARANTINE_PATH"
    source="$quarantine"
  fi
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  track_temp_path "$temporary"
  if [[ -n "$source" ]]; then
    existing_mode="$(stat -c %a -- "$source")"
  else
    existing_mode="$mode"
  fi
  if [[ "$placement" == prepend ]]; then
    printf '%s\n' "$block" > "$temporary"
    [[ -z "$source" ]] || dd if="$source" of="$temporary" oflag=append conv=notrunc status=none
  else
    : > "$temporary"
    [[ -z "$source" ]] || dd if="$source" of="$temporary" conv=notrunc status=none
    [[ "$origin" != existing-no-final-newline ]] || printf '\n' >> "$temporary"
    printf '%s\n' "$block" >> "$temporary"
  fi
  chmod "$existing_mode" "$temporary"
  install_regular_no_clobber "$temporary" "$path" 'guarded attachment' "$quarantine"
  [[ -z "$quarantine" ]] || discard_quarantine "$quarantine" 'guarded attachment destination'
}

write_guarded_attachment_only_atomic() {
  local relative="$1" block="$2" mode="$3" expected="${4:-absent}"
  local path="$HOME/$relative" dir base temporary quarantine=""

  safe_relative_path "$relative" || die "unsafe guarded attachment path: $relative"
  path="$HOME/$relative"
  validate_home_parent_chain "$path"
  dir="$(dirname -- "$path")"
  base="${path##*/}"
  ensure_directory "$dir"
  test_hold before-guarded-replacement-quarantine
  if [[ "$expected" != absent ]]; then
    quarantine_expected_path "$path" "$expected" 'guarded attachment destination' || \
      die "guarded attachment changed before mutation: $path"
    quarantine="$QUARANTINE_PATH"
  fi
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  track_temp_path "$temporary"
  printf '%s\n' "$block" > "$temporary"
  chmod "$mode" "$temporary"
  install_regular_no_clobber "$temporary" "$path" 'guarded attachment' "$quarantine"
  [[ -z "$quarantine" ]] || discard_quarantine "$quarantine" 'guarded attachment destination'
}

install_guarded_attachment() {
  local relative="$1" begin="$2" end="$3" marker_token="$4" block="$5"
  local placement="$6" create_mode="$7" absence_policy="$8"

  guarded_attachment_preflight "$relative" "$begin" "$end" "$marker_token" "$block" "$placement" "$absence_policy"
  [[ "$GUARDED_ATTACHMENT_ACTION" == insert ]] || return 0
  write_guarded_block_atomic "$relative" "$block" "$placement" "$create_mode" "$GUARDED_ATTACHMENT_ORIGIN" \
    "$GUARDED_ATTACHMENT_IDENTITY"
}

remove_guarded_attachment() {
  local relative="$1" begin="$2" end="$3" marker_token="$4" block="$5"
  local placement="$6" origin="$7" delete_empty="${8:-false}"
  local path="$HOME/$relative" dir base temporary line inside=false status mode expected quarantine

  guarded_attachment_preflight "$relative" "$begin" "$end" "$marker_token" "$block" "$placement" exact
  expected="$GUARDED_ATTACHMENT_IDENTITY"
  case "$origin" in
    created|existing-empty|existing-final-newline|existing-no-final-newline) ;;
    *) die "invalid guarded attachment origin: $origin" ;;
  esac
  dir="$(dirname -- "$path")"
  base="${path##*/}"
  test_hold before-guarded-replacement-quarantine
  quarantine_expected_path "$path" "$expected" 'guarded attachment removal source' || \
    die "guarded attachment changed before removal: $path"
  quarantine="$QUARANTINE_PATH"
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  track_temp_path "$temporary"
  mode="$(stat -c %a -- "$quarantine")"
  while true; do
    line=""
    status=0
    IFS= read -r line || status=$?
    if [[ "$line" == "$begin" ]]; then
      if [[ "$placement" == append && "$origin" == existing-no-final-newline ]]; then
        [[ ! -s "$temporary" ]] || truncate -s -1 -- "$temporary"
      fi
      inside=true
    elif [[ "$line" == "$end" ]]; then
      inside=false
    elif [[ "$inside" == false ]]; then
      printf '%s' "$line" >> "$temporary"
      ((status != 0)) || printf '\n' >> "$temporary"
    fi
    ((status == 0)) || break
  done < "$quarantine"
  chmod "$mode" "$temporary"
  if [[ ! -s "$temporary" && ( "$origin" == created || "$delete_empty" == true ) ]]; then
    discard_tracked_temp_path "$temporary" 'guarded attachment removal staging' || \
      die "guarded attachment removal staging changed before discard: $temporary"
    discard_quarantine "$quarantine" 'guarded attachment removal'
  else
    install_regular_no_clobber "$temporary" "$path" 'guarded attachment removal' "$quarantine"
    discard_quarantine "$quarantine" 'guarded attachment removal'
  fi
}

migration_ledger_path() {
  printf '%s' "$HOME/.local/state/dotfiles/v1/migrations.json"
}

register_migration_ledger_journal() {
  local path
  path="$(migration_ledger_path)"
  array_contains "$path" "${AREA_JOURNAL_PATHS[@]:-}" || AREA_JOURNAL_PATHS+=("$path")
  if [[ "$TRANSACTION_ACTIVE" == true ]]; then snapshot_path "$path"; fi
}

validate_migrations_ledger() {
  local path value
  path="$(migration_ledger_path)"
  validate_home_parent_chain "$path"
  [[ ! -e "$path" && ! -L "$path" ]] && return 0
  [[ -f "$path" && ! -L "$path" ]] || die "$path is not a regular file"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "migration ledger has an unsafe owner: $path"
  jq -e '
    type == "object" and keys == ["migrations","schema_version"] and .schema_version == 1 and
    (.migrations | type == "array" and all(.[];
      type == "object" and keys == ["backups","completed_at","id","source_fingerprint"] and
      (.id | type == "string" and test("^[a-z0-9][a-z0-9.-]*$")) and
      (.source_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
      (.completed_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
      (.backups | type == "array" and all(.[]; type == "string") and ((unique | length) == length))) and
      ((map(.id) | unique | length) == length) and
      ((map(.backups[]) | unique | length) == (map(.backups[]) | length)))
  ' "$path" >/dev/null || die "malformed or unknown migration ledger: $path"
  while IFS= read -r value; do
    safe_relative_path "$value" || die "unsafe retained migration backup path: $value"
    validate_home_parent_chain "$HOME/$value"
  done < <(jq -r '.migrations[].backups[]' "$path")
}

migration_is_completed() {
  local id="$1" path
  validate_migration_id "$id"
  validate_migrations_ledger
  path="$(migration_ledger_path)"
  [[ -f "$path" ]] || return 1
  jq -e --arg id "$id" '.migrations[] | select(.id == $id)' "$path" >/dev/null
}

preflight_migration() {
  local id="$1" source_present="$2" description="$3"
  [[ "$source_present" == true || "$source_present" == false ]] || die 'invalid migration source-presence flag'
  MIGRATION_STATUS=pending
  if migration_is_completed "$id"; then
    [[ "$source_present" == false ]] || die "$description is already recorded but its retired source reappeared"
    MIGRATION_STATUS=completed
  fi
}

append_migration_ledger() {
  local id="$1" fingerprint="$2"
  shift 2
  local path current='{"schema_version":1,"migrations":[]}' backups='[]' entry updated value read_identity

  validate_migration_id "$id"
  [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || die "invalid migration source fingerprint for $id"
  [[ "$TRANSACTION_ACTIVE" == true ]] || die 'migration ledger updates require an active area transaction'
  register_migration_ledger_journal
  path="$(migration_ledger_path)"
  validate_migrations_ledger
  migration_is_completed "$id" && die "migration is already recorded: $id"
  for value in "$@"; do
    safe_relative_path "$value" || die "unsafe retained migration backup path: $value"
    validate_home_parent_chain "$HOME/$value"
    backups="$(jq -c --arg value "$value" '. + [$value]' <<< "$backups")"
  done
  [[ "$(jq 'unique | length' <<< "$backups")" == "$(jq 'length' <<< "$backups")" ]] || \
    die "duplicate retained migration backup path for $id"
  capture_path_identity "$path" || die "migration ledger changed before it could be read: $path"
  read_identity="$PATH_IDENTITY"
  if [[ -f "$path" ]]; then current="$(< "$path")"; fi
  capture_path_identity "$path" || die "migration ledger changed while it was read: $path"
  [[ "$PATH_IDENTITY" == "$read_identity" ]] || die "migration ledger changed while it was read: $path"
  test_hold after-migration-ledger-read
  entry="$(jq -cn --arg id "$id" --arg fingerprint "$fingerprint" \
    --arg completed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson backups "$backups" \
    '{id:$id,source_fingerprint:$fingerprint,completed_at:$completed,backups:$backups}')"
  updated="$(jq -c --argjson entry "$entry" '.migrations += [$entry]' <<< "$current")"
  jq -e '([.migrations[].backups[]] | unique | length) == ([.migrations[].backups[]] | length)' \
    <<< "$updated" >/dev/null || die "retained migration backup path is already recorded for $id"
  write_string_atomic "$updated" "$path" 0600 "$read_identity"
}

preflight_existing_state() {
  AREA_STATE="$HOME/.local/state/dotfiles/v1/$AREA.json"
  OLD_STATE=false
  if [[ -e "$AREA_STATE" || -L "$AREA_STATE" ]]; then
    validate_state_file "$AREA_STATE"
    [[ "$(jq -r .target_root "$AREA_STATE")" == "$TARGET_ROOT" ]] || \
      die "existing $AREA state belongs to a different target root"
    OLD_STATE=true
    local count index dir path
    count="$(jq '.targets | length' "$AREA_STATE")"
    for ((index=0; index<count; index++)); do validate_recorded_target "$AREA_STATE" "$index"; done
    "$AREA_ATTACHMENT_VALIDATOR" "$AREA_STATE"
    while IFS= read -r dir; do
      path="$HOME/$dir"
      validate_home_directory "$path"
      array_contains "$dir" "${MANAGED_DIRS[@]}" || MANAGED_DIRS+=("$dir")
    done < <(jq -r '.managed_directories[]' "$AREA_STATE")
  fi
}

preflight_desired_targets() {
  local i relative path index
  for i in "${!TARGET_PATHS[@]}"; do
    relative="${TARGET_PATHS[i]}"
    path="$HOME/$relative"
    if declare -F area_retiring_desired_target >/dev/null && area_retiring_desired_target "$path"; then
      continue
    fi
    if [[ -L "$path" ]]; then
      [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "destination symlink has an unsafe owner: $path"
      if [[ "$(readlink -- "$path")" == "${TARGET_LEXICAL[i]}" && "$(resolve_link "$path")" == "${TARGET_SOURCES[i]}" ]]; then
        continue
      fi
      if [[ "$OLD_STATE" == true ]]; then
        index="$(state_target_index "$AREA_STATE" "$relative")"
        [[ -n "$index" ]] && continue
      fi
      if [[ -n "${APPROVED_REPLACEMENT_SOURCE[$relative]+x}" ]]; then
        reviewed_legacy_link "$path" "$relative" "${APPROVED_REPLACEMENT_SOURCE[$relative]}" \
          "${APPROVED_REPLACEMENT_AREA[$relative]}" "${APPROVED_REPLACEMENT_ACTION[$relative]}" || \
          die "approved legacy replacement no longer has reviewed ownership: $path"
        continue
      fi
      die "unrelated destination conflict: $path"
    elif [[ -e "$path" ]]; then
      die "unrelated destination conflict: $path"
    fi
  done
}

approve_legacy_replacement() {
  local relative="$1" source_relative="$2" area="$3" action="$4" path

  safe_relative_path "$relative" || die "unsafe approved replacement path: $relative"
  [[ "$area" == "$AREA" ]] || die "approved replacement area mismatch for $relative"
  [[ -n "${TARGET_OWNER[$relative]+x}" ]] || die "approved replacement is not a desired package target: $relative"
  [[ -z "${APPROVED_REPLACEMENT_SOURCE[$relative]+x}" ]] || die "duplicate approved replacement target: $relative"
  path="$HOME/$relative"
  validate_home_parent_chain "$path"
  reviewed_legacy_link "$path" "$relative" "$source_relative" "$area" "$action" || \
    die "legacy replacement is not an exact reviewed manifest record: $path"
  PREFLIGHT_APPROVED_REPLACEMENTS+=("$relative")
  APPROVED_REPLACEMENT_SOURCE["$relative"]="$source_relative"
  APPROVED_REPLACEMENT_AREA["$relative"]="$area"
  APPROVED_REPLACEMENT_ACTION["$relative"]="$action"
  capture_path_identity "$path" || die "legacy replacement changed during approval: $path"
  APPROVED_REPLACEMENT_IDENTITY["$relative"]="$PATH_IDENTITY"
}

remove_approved_legacy_replacements() {
  local relative path quarantine
  [[ "$TRANSACTION_ACTIVE" == true ]] || die 'approved legacy replacements must be removed inside an area transaction'
  for relative in "${PREFLIGHT_APPROVED_REPLACEMENTS[@]}"; do
    path="$HOME/$relative"
    test_hold before-approved-legacy-quarantine
    quarantine_expected_path "$path" "${APPROVED_REPLACEMENT_IDENTITY[$relative]}" \
      'approved legacy replacement' || die "approved legacy replacement changed before removal: $path"
    quarantine="$QUARANTINE_PATH"
    reviewed_legacy_link "$quarantine" "$relative" "${APPROVED_REPLACEMENT_SOURCE[$relative]}" \
      "${APPROVED_REPLACEMENT_AREA[$relative]}" "${APPROVED_REPLACEMENT_ACTION[$relative]}" || {
      if restore_quarantine_no_clobber "$quarantine" "$path"; then
        transaction_record_post_state "$path"
      fi
      die "quarantined legacy replacement does not have reviewed ownership: $path"
    }
    discard_quarantine "$quarantine" 'approved legacy replacement'
  done
}

run_stow_preflight() {
  local package layer name output status=0 target="$HOME"
  if ((${#PREFLIGHT_APPROVED_REPLACEMENTS[@]} > 0)) || \
    { declare -F area_requires_isolated_stow_preflight >/dev/null && area_requires_isolated_stow_preflight; } || \
    [[ "$OLD_STATE" == true && "$(jq -r .checkout_root "$AREA_STATE")" != "$CHECKOUT_ROOT" ]]; then
    target="$DOTFILES_DIR/lib/stow-preflight-target"
    [[ -d "$target" && ! -L "$target" ]] || die 'missing moved-checkout Stow preflight target'
  fi
  for package in "${PACKAGES[@]}"; do
    layer="${package%%/*}"
    name="${package#*/}"
    output="$(stow --dir="$DOTFILES_DIR/packages/$layer" --target="$target" --no-folding --stow "$name" --simulate 2>&1)" || status=$?
    if ((status != 0)); then
      [[ -z "$output" ]] || printf '%s\n' "$output" >&2
      die "Stow conflict preflight failed for $package"
    fi
    status=0
  done
}

snapshot_path() {
  local path="$1" index snapshot identity content_identity
  validate_home_parent_chain "$path"
  for index in "${!TX_PATHS[@]}"; do [[ "${TX_PATHS[index]}" != "$path" ]] || return 0; done
  capture_path_identity "$path" || die "could not capture transaction pre-state: $path"
  identity="$PATH_IDENTITY"
  capture_path_content_identity "$path" || die "could not capture transaction pre-state content: $path"
  content_identity="$PATH_CONTENT_IDENTITY"
  index="${#TX_PATHS[@]}"
  snapshot="$JOURNAL_DIR/$index"
  TX_PATHS+=("$path")
  TX_SNAPSHOTS+=("$snapshot")
  TX_INITIAL_IDENTITIES+=("$identity")
  TX_EXPECTED_IDENTITIES+=("$identity")
  TX_MUTATED+=(false)
  if [[ -e "$path" || -L "$path" ]]; then
    cp -a -- "$path" "$snapshot"
    capture_path_identity "$path" || die "transaction pre-state changed while journaling: $path"
    [[ "$PATH_IDENTITY" == "$identity" ]] || die "transaction pre-state changed while journaling: $path"
    capture_path_content_identity "$snapshot" || die "transaction snapshot could not be verified: $path"
    [[ "$PATH_CONTENT_IDENTITY" == "$content_identity" ]] || die "transaction snapshot differs from source: $path"
    TX_EXISTED+=(true)
  else
    TX_EXISTED+=(false)
  fi
}

snapshot_logically_absent_path() {
  local path="$1" index snapshot
  transaction_path_index "$path" && return 0
  index="${#TX_PATHS[@]}"; snapshot="$JOURNAL_DIR/$index"
  TX_PATHS+=("$path"); TX_SNAPSHOTS+=("$snapshot"); TX_INITIAL_IDENTITIES+=(absent)
  TX_EXPECTED_IDENTITIES+=(absent); TX_MUTATED+=(false); TX_EXISTED+=(false)
}

begin_transaction() {
  local path
  TX_PATHS=()
  TX_EXISTED=()
  TX_SNAPSHOTS=()
  TX_INITIAL_IDENTITIES=()
  TX_EXPECTED_IDENTITIES=()
  TX_MUTATED=()
  TX_CREATED_DIRS=()
  TX_RECOVERY_PATHS=()
  TX_QUARANTINE_PATHS=()
  TX_DIRECTORY_MOVE_SOURCES=()
  TX_DIRECTORY_MOVE_DESTINATIONS=()
  TX_DIRECTORY_MOVE_IDENTITIES=()
  TX_DIRECTORY_MOVE_DONE=()
  QUARANTINE_IDENTITIES=()
  TRANSACTION_RECOVERY_REQUIRED=false
  JOURNAL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-$AREA-journal.XXXXXX")"
  track_temp_path "$JOURNAL_DIR"
  snapshot_path "$AREA_STATE"
  for path in "${AREA_JOURNAL_PATHS[@]}"; do
    snapshot_path "$path"
  done
  for path in "${TARGET_PATHS[@]}"; do
    if declare -F area_retiring_desired_target >/dev/null && area_retiring_desired_target "$HOME/$path"; then
      snapshot_logically_absent_path "$HOME/$path"
    else
      snapshot_path "$HOME/$path"
    fi
  done
  if [[ "$OLD_STATE" == true ]]; then
    while IFS= read -r path; do snapshot_path "$HOME/$path"; done < <(jq -r '.targets[].path' "$AREA_STATE")
  fi
  TRANSACTION_ACTIVE=true
}

register_directory_move() {
  local source="$1" destination="$2" identity="$3"
  [[ "$TRANSACTION_ACTIVE" == true ]] || die 'directory moves require an active transaction'
  validate_home_parent_chain "$source"
  validate_home_parent_chain "$destination"
  [[ "$identity" != absent ]] || die "cannot register an absent directory move: $source"
  TX_DIRECTORY_MOVE_SOURCES+=("$source")
  TX_DIRECTORY_MOVE_DESTINATIONS+=("$destination")
  TX_DIRECTORY_MOVE_IDENTITIES+=("$identity")
  TX_DIRECTORY_MOVE_DONE+=(false)
}

move_registered_directory() {
  local index="$1" source destination expected
  source="${TX_DIRECTORY_MOVE_SOURCES[index]}"
  destination="${TX_DIRECTORY_MOVE_DESTINATIONS[index]}"
  expected="${TX_DIRECTORY_MOVE_IDENTITIES[index]}"
  capture_path_object_identity "$source" || die "runtime directory changed before move: $source"
  [[ "$PATH_OBJECT_IDENTITY" == "$expected" && -d "$source" && ! -L "$source" ]] || \
    die "runtime directory changed before move: $source"
  capture_path_object_identity "$destination" || die "runtime backup cannot be inspected: $destination"
  [[ "$PATH_OBJECT_IDENTITY" == absent ]] || die "runtime backup destination appeared: $destination"
  mv -nT -- "$source" "$destination" 2>/dev/null || die "runtime directory could not be renamed without clobber: $source"
  capture_path_object_identity "$destination" || die "runtime backup cannot be inspected after move: $destination"
  [[ "$PATH_OBJECT_IDENTITY" == "$expected" && ! -e "$source" && ! -L "$source" ]] || \
    die "runtime directory changed during move: $source"
  TX_DIRECTORY_MOVE_DONE[index]=true
}

rollback_directory_moves() {
  local index source destination expected failed=false
  for ((index=${#TX_DIRECTORY_MOVE_SOURCES[@]}-1; index>=0; index--)); do
    [[ "${TX_DIRECTORY_MOVE_DONE[index]}" == true ]] || continue
    source="${TX_DIRECTORY_MOVE_SOURCES[index]}"
    destination="${TX_DIRECTORY_MOVE_DESTINATIONS[index]}"
    expected="${TX_DIRECTORY_MOVE_IDENTITIES[index]}"
    capture_path_object_identity "$source" || { failed=true; continue; }
    [[ "$PATH_OBJECT_IDENTITY" == absent ]] || { failed=true; continue; }
    capture_path_object_identity "$destination" || { failed=true; continue; }
    [[ "$PATH_OBJECT_IDENTITY" == "$expected" ]] || { failed=true; continue; }
    if mv -nT -- "$destination" "$source" 2>/dev/null && [[ -d "$source" && ! -L "$source" ]]; then
      TX_DIRECTORY_MOVE_DONE[index]=false
    else
      failed=true
    fi
  done
  [[ "$failed" == false ]]
}

install_snapshot_no_clobber() {
  local snapshot="$1" path="$2" dir base temporary target
  dir="$(dirname -- "$path")"
  base="${path##*/}"
  if [[ -L "$snapshot" ]]; then
    target="$(readlink -- "$snapshot")"
    ln -s -- "$target" "$path" 2>/dev/null || return 1
    return 0
  fi
  if [[ -f "$snapshot" && ! -L "$snapshot" ]]; then
    temporary="$(mktemp "$dir/.$base.dotfiles-rollback.XXXXXX")"
    track_temp_path "$temporary"
    cp -a -- "$snapshot" "$temporary"
    if ! ln -- "$temporary" "$path" 2>/dev/null; then
      discard_tracked_temp_path "$temporary" 'rollback staging' || true
      return 1
    fi
    discard_tracked_temp_path "$temporary" 'rollback staging' || return 1
    return 0
  fi
  return 1
}

rollback_transaction() {
  local index path dir round failed=false expected quarantine=""
  test_hold before-rollback
  TRANSACTION_ROLLING_BACK=true
  set +e
  for ((index=${#TX_PATHS[@]}-1; index>=0; index--)); do
    [[ "${TX_MUTATED[index]}" == true ]] || continue
    path="${TX_PATHS[index]}"
    if ! home_parent_chain_safe "$path"; then
      failed=true
      continue
    fi
    test_hold before-rollback-path
    expected="${TX_EXPECTED_IDENTITIES[index]}"
    quarantine=""
    if [[ "$expected" == absent ]]; then
      capture_path_identity "$path"
      if [[ "$PATH_IDENTITY" != absent && -d "$path" && ! -L "$path" ]] &&
        declare -F area_retiring_managed_parent >/dev/null && area_retiring_managed_parent "$path"; then
        rmdir -- "$path" 2>/dev/null || true
        capture_path_identity "$path"
      fi
      if [[ "$PATH_IDENTITY" != absent ]]; then
        printf '[%s] error: rollback preserved unexpected concurrent object at %s\n' "$SCRIPT_NAME" "$path" >&2
        failed=true
        continue
      fi
    else
      QUARANTINE_PATH=""
      if ! capture_path_identity "$path" || [[ "$PATH_IDENTITY" != "$expected" ]]; then
        printf '[%s] error: rollback preserved unexpected concurrent object at %s\n' "$SCRIPT_NAME" "$path" >&2
        failed=true
        continue
      fi
      if quarantine_expected_path "$path" "$expected" 'transaction post-state'; then
        quarantine="$QUARANTINE_PATH"
      else
        failed=true
        continue
      fi
    fi
    if [[ "${TX_EXISTED[index]}" == true ]]; then
      ensure_directory "$(dirname -- "$path")" || { failed=true; continue; }
      if ! install_snapshot_no_clobber "${TX_SNAPSHOTS[index]}" "$path"; then
        [[ -z "$quarantine" ]] || retain_transaction_recovery_path "$quarantine"
        printf '[%s] error: rollback destination appeared concurrently; preserved it at %s\n' "$SCRIPT_NAME" "$path" >&2
        failed=true
        continue
      fi
    fi
    if [[ "${TX_EXISTED[index]}" == false ]]; then
      capture_path_identity "$path"
      if [[ "$PATH_IDENTITY" != absent ]]; then
        printf '[%s] error: rollback preserved object that appeared concurrently at %s\n' "$SCRIPT_NAME" "$path" >&2
        failed=true
      fi
    fi
    if [[ -n "$quarantine" ]]; then
      discard_quarantine "$quarantine" 'rollback post-state' || failed=true
    fi
    if declare -F area_retiring_managed_parent >/dev/null; then
      dir="$(dirname -- "$path")"
      while area_retiring_managed_parent "$dir"; do
        rmdir -- "$dir" 2>/dev/null || break
        dir="$(dirname -- "$dir")"
      done
    fi
  done
  rollback_directory_moves || failed=true
  for ((round=0; round<${#MANAGED_DIRS[@]}; round++)); do
    for dir in "${MANAGED_DIRS[@]:-}"; do [[ -n "$dir" ]] && rmdir -- "$HOME/$dir" 2>/dev/null || true; done
  done
  for ((index=${#TX_CREATED_DIRS[@]}-1; index>=0; index--)); do
    rmdir -- "${TX_CREATED_DIRS[index]}" 2>/dev/null || true
  done
  set -e
  TRANSACTION_ACTIVE=false
  TRANSACTION_ROLLING_BACK=false
  [[ "$failed" == false && "$TRANSACTION_RECOVERY_REQUIRED" == false ]] || {
    ROLLBACK_FAILED=true
    printf '[%s] error: rollback failed; inspect journal %s\n' "$SCRIPT_NAME" "$JOURNAL_DIR" >&2
    for path in "${TX_RECOVERY_PATHS[@]:-}"; do
      [[ -n "$path" ]] && printf '[%s] error: retained recovery object %s\n' "$SCRIPT_NAME" "$path" >&2
    done
    for path in "${TX_QUARANTINE_PATHS[@]:-}"; do
      if [[ -e "$path" || -L "$path" ]]; then
        printf '[%s] error: retained quarantined object %s\n' "$SCRIPT_NAME" "$path" >&2
      fi
    done
    return 1
  }
  log "rolled back incomplete deployment of area '$AREA'"
}

ensure_directory() {
  local dir="$1"
  local relative current component
  local components=()

  [[ "$dir" == "$HOME" || "$dir" == "$HOME/"* ]] || die "refusing to create directory outside HOME: $dir"
  validate_home_directory "$dir"
  [[ "$dir" != "$HOME" ]] || return 0
  relative="${dir#"$HOME"/}"
  current="$HOME"
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || die "unsafe directory component in $dir"
    current="$current/$component"
    if [[ -e "$current" || -L "$current" ]]; then
      [[ -d "$current" && ! -L "$current" ]] || die "cannot traverse managed directory: $current"
    else
      mkdir -- "$current"
      [[ -d "$current" && ! -L "$current" ]] || die "failed to create safe managed directory: $current"
      TX_CREATED_DIRS+=("$current")
    fi
  done
}

write_string_atomic() {
  local content="$1" destination="$2" mode="$3" expected="$4"
  local dir base temporary quarantine=""
  dir="$(dirname -- "$destination")"
  base="${destination##*/}"
  ensure_directory "$dir"
  require_expected_pre_state "$destination" "$expected" 'atomic write destination'
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  track_temp_path "$temporary"
  printf '%s\n' "$content" > "$temporary"
  chmod "$mode" "$temporary"
  test_hold before-atomic-rename
  if [[ "$expected" != absent ]]; then
    quarantine_expected_path "$destination" "$expected" 'atomic write destination' || \
      die "atomic write destination changed before replacement: $destination"
    quarantine="$QUARANTINE_PATH"
  fi
  install_regular_no_clobber "$temporary" "$destination" 'atomic write' "$quarantine"
  [[ -z "$quarantine" ]] || discard_quarantine "$quarantine" 'atomic write destination'
}

write_transaction_string_atomic() {
  local content="$1" destination="$2" mode="$3" expected
  expected="$(transaction_expected_identity "$destination")"
  write_string_atomic "$content" "$destination" "$mode" "$expected"
}

remove_recorded_links_for_apply() {
  local count index relative
  [[ "$OLD_STATE" == true ]] || return 0
  count="$(jq '.targets | length' "$AREA_STATE")"
  for ((index=0; index<count; index++)); do
    remove_recorded_target "$AREA_STATE" "$index"
  done
}

remove_recorded_target() {
  local state="$1" index="$2" relative path expected quarantine
  validate_recorded_target "$state" "$index"
  relative="$(jq -r ".targets[$index].path" "$state")"
  path="$HOME/$relative"
  capture_path_identity "$path" || die "recorded target changed during removal preflight: $path"
  expected="$PATH_IDENTITY"
  quarantine_expected_path "$path" "$expected" 'recorded package target' || \
    die "recorded target changed before removal: $path"
  quarantine="$QUARANTINE_PATH"
  validate_recorded_target_at_path "$state" "$index" "$quarantine" || \
    die "quarantined target does not retain recorded ownership: $path"
  discard_quarantine "$quarantine" 'recorded package target'
}

validate_recorded_target_at_path() {
  local state="$1" index="$2" path="$3" source resolved actual_resolved
  source="$(jq -r ".targets[$index].source" "$state")"
  resolved="$(jq -r ".targets[$index].resolved_source" "$state")"
  [[ -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" ]] || return 1
  [[ "$(readlink -- "$path")" == "$source" ]] || return 1
  actual_resolved="$(resolve_link "$path")"
  [[ "$actual_resolved" == "$resolved" ]]
}

apply_stow_packages() {
  local package layer name output status i path
  for package in "${PACKAGES[@]}"; do
    layer="${package%%/*}"
    name="${package#*/}"
    for i in "${!TARGET_PATHS[@]}"; do
      [[ "${TARGET_OWNER[${TARGET_PATHS[i]}]}" == "$package" ]] || continue
      path="$HOME/${TARGET_PATHS[i]}"
      transaction_pre_identity "$path"
      require_expected_pre_state "$path" "$TRANSACTION_PRE_IDENTITY" 'Stow package target'
    done
    status=0
    output="$(stow --dir="$DOTFILES_DIR/packages/$layer" --target="$HOME" --no-folding --stow "$name" 2>&1)" || status=$?
    [[ -z "$output" ]] || printf '%s\n' "$output" >&2
    for i in "${!TARGET_PATHS[@]}"; do
      [[ "${TARGET_OWNER[${TARGET_PATHS[i]}]}" == "$package" ]] || continue
      path="$HOME/${TARGET_PATHS[i]}"
      if [[ -L "$path" && "$(readlink -- "$path")" == "${TARGET_LEXICAL[i]}" && \
        "$(resolve_link "$path")" == "${TARGET_SOURCES[i]}" ]]; then
        record_applied_target_post_state "$i"
      fi
    done
    ((status == 0)) || return "$status"
  done
}

validate_applied_targets() {
  local i path
  for i in "${!TARGET_PATHS[@]}"; do
    path="$HOME/${TARGET_PATHS[i]}"
    [[ -L "$path" ]] || die "Stow did not create expected link: $path"
    [[ "$(readlink -- "$path")" == "${TARGET_LEXICAL[i]}" ]] || die "Stow created unexpected lexical link: $path"
    [[ "$(resolve_link "$path")" == "${TARGET_SOURCES[i]}" ]] || die "Stow created unexpected resolved link: $path"
    record_applied_target_post_state "$i"
  done
}

record_applied_target_post_state() {
  local index="$1" path expected pre_identity
  path="$HOME/${TARGET_PATHS[index]}"
  capture_path_identity "$path" || die "applied target changed while recording ownership: $path"
  expected="$PATH_IDENTITY"
  [[ -L "$path" && "$(readlink -- "$path")" == "${TARGET_LEXICAL[index]}" && \
    "$(resolve_link "$path")" == "${TARGET_SOURCES[index]}" ]] || \
    die "applied target changed while recording ownership: $path"
  transaction_pre_identity "$path"
  pre_identity="$TRANSACTION_PRE_IDENTITY"
  [[ "$expected" != "$pre_identity" ]] || return 0
  transaction_record_expected_state "$path" "$expected"
}

prune_managed_directories() {
  local rounds index dir
  local directories=("$@")
  rounds="${#directories[@]}"
  for ((index=0; index<rounds; index++)); do
    for dir in "${directories[@]}"; do
      validate_home_directory "$HOME/$dir"
      rmdir -- "$HOME/$dir" 2>/dev/null || true
    done
  done
}
