# Lean deployment primitives for vertically converted areas.
# This runtime intentionally does not import or mutate legacy v1 state.

LEAN_AREA=""
LEAN_PROFILE=""
LEAN_ENTRY_KIND=""
LEAN_STATE=""
LEAN_PACKAGES=()
LEAN_TARGET_PATHS=()
LEAN_TARGET_SOURCES=()
LEAN_TARGET_LEXICAL=()
LEAN_ATTACHMENT_IDS=()
LEAN_ATTACHMENT_PATHS=()
LEAN_ATTACHMENT_BEGINS=()
LEAN_ATTACHMENT_ENDS=()
LEAN_ATTACHMENT_TOKENS=()
LEAN_ATTACHMENT_BLOCKS=()
LEAN_ATTACHMENT_LEGACY_BLOCKS=()
LEAN_ATTACHMENT_PLACEMENTS=()
LEAN_ATTACHMENT_MODES=()
LEAN_ATTACHMENT_ORIGINS=()
LEAN_ATTACHMENT_BEFORE_HASHES=()
LEAN_ATTACHMENT_MANAGED_HASHES=()
LEAN_ATTACHMENT_PENDING_HASHES=()
LEAN_ATTACHMENT_PREFLIGHT_STATUSES=()
LEAN_ATTACHMENT_PREFLIGHT_IDENTITIES=()
LEAN_ATTACHMENT_PREFLIGHT_HASHES=()
LEAN_ATTACHMENT_REFRESHES=()
LEAN_ATTACHMENT_ANCHORS=()
LEAN_JSON_IDS=()
LEAN_JSON_PATHS=()
LEAN_JSON_VALIDATORS=()
LEAN_JSON_STATUSES=()
LEAN_JSON_FIELD_RESOURCES=()
LEAN_JSON_FIELD_POINTERS=()
LEAN_JSON_FIELD_TYPES=()
LEAN_JSON_FIELD_MANAGED=()
LEAN_JSON_FIELD_ORIGINALS=()
declare -A LEAN_TARGET_OWNER=()
AREA_ORDER=()
declare -A AREA_STATUS=()
declare -A AREA_DEPENDENCY_OK=()
declare -A AREA_PREFLIGHT_OK=()
DEPENDENCY_APT_INSTALL=()
DEPENDENCY_AREAS=()
DEPENDENCY_MODES=()
DEPENDENCY_PROFILES=()
DEPENDENCY_COMMANDS=()
DEPENDENCY_MANAGERS=()
DEPENDENCY_PACKAGES=()
DEPENDENCY_CLASSES=()

validate_area_manifest() {
  local manifest="$DOTFILES_DIR/manifests/areas.tsv" line area status
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
        area="${fields[1]}"; status="${fields[2]}"
        [[ "$area" =~ ^[a-z0-9-]+$ && ( "$status" == ready || "$status" == optional ) ]] || die 'invalid area manifest'
        [[ -z "${AREA_STATUS[$area]+x}" ]] || die "duplicate area '$area' in area manifest"
        AREA_ORDER+=("$area"); AREA_STATUS["$area"]="$status"
        ;;
      *) die 'invalid area manifest' ;;
    esac
  done < "$manifest"
  ((schema_count == 1 && ${#AREA_ORDER[@]} > 0)) || die 'invalid area manifest'
}

validate_dependency_manifest() {
  local manifest="$DOTFILES_DIR/manifests/dependencies.tsv"
  local line kind area modes profiles command manager package class entry alias
  local fields=() aliases=() schema_count=0 apt_count=0 native_count=0
  [[ -f "$manifest" && ! -L "$manifest" ]] || die 'missing manifests/dependencies.tsv'
  DEPENDENCY_APT_INSTALL=(); DEPENDENCY_AREAS=(); DEPENDENCY_MODES=(); DEPENDENCY_PROFILES=()
  DEPENDENCY_COMMANDS=(); DEPENDENCY_MANAGERS=(); DEPENDENCY_PACKAGES=(); DEPENDENCY_CLASSES=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != *$'\t'* && "$line" != *' '* ]] || die 'invalid dependency manifest'
    IFS='|' read -r -a fields <<< "$line"; kind="${fields[0]}"
    case "$kind" in
      schema)
        ((${#fields[@]} == 2)) && [[ "${fields[1]}" == 2 ]] || die 'invalid dependency manifest'
        ((schema_count += 1))
        ;;
      manager)
        if [[ "${fields[1]:-}" == apt ]]; then
          ((${#fields[@]} == 6)) && [[ "${fields[*]:2}" == 'sudo apt-get install -y' ]] || die 'invalid dependency manifest'
          DEPENDENCY_APT_INSTALL=("${fields[@]:2}"); ((apt_count += 1))
        elif [[ "${fields[1]:-}" == native ]]; then
          ((${#fields[@]} == 2)) || die 'invalid dependency manifest'; ((native_count += 1))
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
        for entry in ${modes//,/ }; do [[ "$entry" == apply || "$entry" == check || "$entry" == remove ]] || die 'invalid dependency manifest'; done
        for entry in ${profiles//,/ }; do [[ "$entry" == all || "$entry" == ubuntu || "$entry" == omarchy ]] || die 'invalid dependency manifest'; done
        if [[ "$manager" == apt-package ]]; then
          [[ "$package" =~ ^[a-z0-9+.-]+$ ]] || die 'invalid dependency manifest'
        else
          [[ "$manager" == omarchy-native && "$package" == - ]] || die 'invalid dependency manifest'
        fi
        [[ "$class" == bootstrap-critical || "$class" == area ]] || die 'invalid dependency manifest'
        DEPENDENCY_AREAS+=("$area"); DEPENDENCY_MODES+=("$modes"); DEPENDENCY_PROFILES+=("$profiles")
        DEPENDENCY_COMMANDS+=("$command"); DEPENDENCY_MANAGERS+=("$manager")
        DEPENDENCY_PACKAGES+=("$package"); DEPENDENCY_CLASSES+=("$class")
        ;;
      *) die 'invalid dependency manifest' ;;
    esac
  done < "$manifest"
  ((schema_count == 1 && apt_count == 1 && native_count == 1 && ${#DEPENDENCY_AREAS[@]} > 0)) || die 'invalid dependency manifest'
}

command_capability_exists() {
  local capability="$1" candidate hidden hidden_match candidates=()
  IFS='+' read -r -a candidates <<< "$capability"
  for candidate in "${candidates[@]}"; do
    if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_HIDE_COMMANDS:-}" ]]; then
      hidden_match=false
      for hidden in ${DOTFILES_TEST_HIDE_COMMANDS}; do [[ "$candidate" != "$hidden" ]] || { hidden_match=true; break; }; done
      [[ "$hidden_match" == false ]] || continue
    fi
    [[ "$(type -t -- "$candidate" 2>/dev/null || true)" == file ]] && return 0
  done
  return 1
}

check_manifest_dependencies() {
  local mode="$1" profile="$2" guidance="$3"
  local command manager package class entry install_word index selected
  local missing_commands=() missing_packages=() native_missing=() row_areas=()
  DEPENDENCY_CRITICAL_MISSING=false; AREA_DEPENDENCY_OK=()
  for entry in "${AREAS[@]}"; do AREA_DEPENDENCY_OK["$entry"]=true; done
  for index in "${!DEPENDENCY_AREAS[@]}"; do
    selected=false; IFS=',' read -r -a row_areas <<< "${DEPENDENCY_AREAS[index]}"
    for entry in "${row_areas[@]}"; do array_contains "$entry" "${AREAS[@]}" && { selected=true; break; }; done
    [[ "$selected" == true ]] || continue
    csv_contains "${DEPENDENCY_MODES[index]}" "$mode" || continue
    if ! csv_contains "${DEPENDENCY_PROFILES[index]}" all && ! csv_contains "${DEPENDENCY_PROFILES[index]}" "$profile"; then continue; fi
    command="${DEPENDENCY_COMMANDS[index]}"; manager="${DEPENDENCY_MANAGERS[index]}"
    package="${DEPENDENCY_PACKAGES[index]}"; class="${DEPENDENCY_CLASSES[index]}"
    command_capability_exists "$command" && continue
    array_contains "$command" "${missing_commands[@]}" || missing_commands+=("$command")
    [[ "$class" != bootstrap-critical ]] || DEPENDENCY_CRITICAL_MISSING=true
    for entry in "${row_areas[@]}"; do array_contains "$entry" "${AREAS[@]}" && AREA_DEPENDENCY_OK["$entry"]=false; done
    if [[ "$manager" == apt-package && "$guidance" == true ]]; then
      array_contains "$package" "${missing_packages[@]}" || missing_packages+=("$package")
    elif [[ "$manager" == omarchy-native ]]; then native_missing+=("$command"); fi
  done
  ((${#missing_commands[@]} == 0)) && return 0
  if ((${#native_missing[@]} > 0)); then
    printf '[%s] error: missing required native owner commands:' "$SCRIPT_NAME" >&2; printf ' %s' "${native_missing[@]}" >&2; printf '\n' >&2
  elif ((${#missing_packages[@]} > 0)); then
    printf '[%s] error: missing required commands; install packages with:\n' "$SCRIPT_NAME" >&2
    printf '%s' "${DEPENDENCY_APT_INSTALL[0]}" >&2
    for install_word in "${DEPENDENCY_APT_INSTALL[@]:1}"; do printf ' %s' "$install_word" >&2; done
    printf ' %s' "${missing_packages[@]}" >&2; printf '\n' >&2
  else
    printf '[%s] error: missing removal-required commands:' "$SCRIPT_NAME" >&2; printf ' %s' "${missing_commands[@]}" >&2; printf '\n' >&2
  fi
  return 1
}

validate_package_root() {
  local package="$1" layer name root resolved packages_root
  [[ "$package" =~ ^([a-z0-9-]+)/([a-z0-9-]+)$ ]] || die "invalid qualified package ID: $package"
  layer="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"; root="$DOTFILES_DIR/packages/$layer/$name"
  [[ -d "$root" && ! -L "$root" ]] || die "missing package root: packages/$package"
  resolved="$(cd -- "$root" && pwd -P)"; packages_root="$(cd -- "$DOTFILES_DIR/packages" && pwd -P)"
  [[ "$resolved" == "$packages_root/"* ]] || die "package root escapes packages/: $package"
}

load_profile_closure() {
  local requested="$1" file="$DOTFILES_DIR/profiles/$SELECTED_PROFILE.conf"
  local line area entry extra package found=false entry_kind packages=() seen=()
  PACKAGES=(); PROFILE_ENTRY_KIND=""
  [[ -f "$file" && ! -L "$file" ]] || die "missing profile manifest: $file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != \#* ]] || continue
    read -r area entry extra <<< "$line"
    [[ -n "$area" && -n "$entry" && -z "${extra:-}" ]] || die "malformed profile entry: $line"
    [[ -n "${AREA_STATUS[$area]+x}" ]] || die "profile lists an unknown area: $area"
    array_contains "$area" "${seen[@]}" && die "duplicate $area closure in $file"
    seen+=("$area"); packages=()
    if [[ "$entry" == validation-only ]]; then entry_kind=validation-only
    else
      entry_kind=packages
      [[ "$entry" != ,* && "$entry" != *, && "$entry" != *,,* ]] || die "malformed profile entry: $line"
      IFS=',' read -r -a packages <<< "$entry"
      ((${#packages[@]} > 0)) || die "malformed profile entry: $line"
      for package in "${packages[@]}"; do validate_package_root "$package"; done
    fi
    if [[ "$area" == "$requested" ]]; then PACKAGES=("${packages[@]}"); PROFILE_ENTRY_KIND="$entry_kind"; found=true; fi
  done < "$file"
  [[ "$found" == true ]] || die "profile has no $requested closure: $file"
}

lean_state_dir() {
  printf '%s' "$HOME/.local/state/dotfiles/v2"
}

lean_acquire_lock() {
  local mode="${1:-${MODE:-apply}}"
  exec {LEAN_HOME_LOCK_FD}<"$HOME"
  if [[ "$mode" == check ]]; then
    flock --shared --nonblock "$LEAN_HOME_LOCK_FD" || die 'another mutating deployment holds the HOME lock'
  else
    flock --exclusive --nonblock "$LEAN_HOME_LOCK_FD" || die 'another deployment holds the HOME lock'
  fi
}

lean_refuse_v1_state() {
  local old="$HOME/.local/state/dotfiles/v1/$LEAN_AREA.json"
  [[ ! -e "$old" && ! -L "$old" ]] ||
    die "legacy v1 deployment state exists for lean area '$LEAN_AREA' at $old; use the legacy checkout to remove it, or clean it up manually before using the v2 engine"
}

lean_validate_state_file() {
  local file="$1" value
  validate_home_parent_chain "$file"
  [[ -f "$file" && ! -L "$file" ]] || die "lean deployment state is not a regular file: $file"
  [[ "$(stat -c %u -- "$file")" == "$EUID" ]] || die "lean deployment state has an unsafe owner: $file"
  jq -e '
    def old_attachment_map($allow_empty):
      type == "object" and ($allow_empty or length > 0) and all(to_entries[];
      (.key | type == "string" and length > 0) and
      (.value | type == "object" and keys == ["before_sha256","id","origin"]) and
      (.value.id | type == "string" and test("^[a-z0-9][a-z0-9.-]*$")) and
      (.value.origin == "created" or .value.origin == "existing-empty" or
       .value.origin == "existing-final-newline" or .value.origin == "existing-no-final-newline") and
       (.value.before_sha256 == null or
        (.value.before_sha256 | type == "string" and test("^[0-9a-f]{64}$"))));
    def hash_or_null: . == null or (type == "string" and test("^[0-9a-f]{64}$"));
    def v3_attachment_map:
      type == "object" and all(to_entries[];
      (.key | type == "string" and length > 0) and
      (.value | type == "object" and keys == ["before_sha256","id","managed_sha256","origin","pending_sha256"]) and
      (.value.id | type == "string" and test("^[a-z0-9][a-z0-9.-]*$")) and
      (.value.origin == "created" or .value.origin == "existing-empty" or
       .value.origin == "existing-final-newline" or .value.origin == "existing-no-final-newline") and
      (.value.before_sha256 | hash_or_null) and (.value.managed_sha256 | hash_or_null) and
      (.value.pending_sha256 | hash_or_null) and
      (.value.managed_sha256 != null or .value.pending_sha256 != null));
    def scalar_type($kind):
      if $kind == "integer" then type == "number" and floor == .
      elif $kind == "number" then type == "number"
      elif $kind == "string" then type == "string"
      elif $kind == "boolean" then type == "boolean"
      elif $kind == "null" then . == null
      else false end;
    def resource_map($allow_empty):
      type == "object" and ($allow_empty or length > 0) and all(to_entries[];
        (.key | type == "string" and length > 0) and
        (.value | type == "object" and keys == ["fields","id","kind"]) and
        .value.kind == "json-scalar-fields" and
        (.value.id | type == "string" and test("^[a-z0-9][a-z0-9.-]*$")) and
        (.value.fields | type == "object" and length > 0 and all(to_entries[];
          (.key | type == "string" and test("^/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$")) and
          (.value | type == "object" and keys == ["managed","original","type"]) and
          (.value.type == "integer" or .value.type == "number" or .value.type == "string" or
           .value.type == "boolean" or .value.type == "null") and
          (.value.type as $field_type |
            (.value.managed | scalar_type($field_type)) and
            (.value.original | scalar_type($field_type))))));
    def base:
      (.area | type == "string" and test("^[a-z0-9-]+$")) and
      (.profile == "omarchy" or .profile == "ubuntu");
    type == "object" and base and
    ((keys == ["area","attachments","profile","version"] and .version == 1 and
      (.attachments | old_attachment_map(false))) or
     (keys == ["area","attachments","profile","resources","version"] and .version == 2 and
      (.attachments | old_attachment_map(true)) and (.resources | resource_map(false))) or
     (keys == ["area","attachments","profile","resources","version"] and .version == 3 and
      ((.attachments | length) + (.resources | length) > 0) and
      (.attachments | v3_attachment_map) and (.resources | resource_map(true))))
  ' "$file" >/dev/null || die "malformed or unknown lean deployment state: $file"
  [[ "${file##*/}" == "$(jq -r .area "$file").json" ]] || die "lean state area does not match filename: $file"
  while IFS= read -r value; do
    safe_relative_path "$value" || die "unsafe attachment path in lean state: $value"
  done < <(jq -r '.attachments | keys[]' "$file")
  if [[ "$(jq -r .version "$file")" != 1 ]]; then
    while IFS= read -r value; do
      safe_relative_path "$value" || die "unsafe JSON resource path in lean state: $value"
    done < <(jq -r '.resources | keys[]' "$file")
  fi
}

lean_validate_all_state() {
  local dir file profile
  dir="$(lean_state_dir)"
  validate_home_directory "$dir"
  [[ -d "$dir" ]] || return 0
  shopt -s nullglob
  for file in "$dir"/*.json; do
    lean_validate_state_file "$file"
    profile="$(jq -r .profile "$file")"
    [[ "$profile" == "$LEAN_PROFILE" ]] ||
      die "existing v2 state uses profile '$profile'; remove its areas with that profile before reapplying profile '$LEAN_PROFILE'"
  done
  shopt -u nullglob
}

lean_begin_area() {
  local area="$1" profile="$2" entry_kind="$3"
  [[ "$area" =~ ^[a-z0-9-]+$ ]] || die "invalid lean area: $area"
  [[ "$profile" == omarchy || "$profile" == ubuntu ]] || die "invalid lean profile: $profile"
  [[ "$entry_kind" == packages || "$entry_kind" == validation-only ]] || die "invalid lean entry kind: $entry_kind"
  LEAN_AREA="$area"
  LEAN_PROFILE="$profile"
  LEAN_ENTRY_KIND="$entry_kind"
  LEAN_STATE="$(lean_state_dir)/$area.json"
  LEAN_PACKAGES=()
  LEAN_TARGET_PATHS=()
  LEAN_TARGET_SOURCES=()
  LEAN_TARGET_LEXICAL=()
  LEAN_ATTACHMENT_IDS=()
  LEAN_ATTACHMENT_PATHS=()
  LEAN_ATTACHMENT_BEGINS=()
  LEAN_ATTACHMENT_ENDS=()
  LEAN_ATTACHMENT_TOKENS=()
  LEAN_ATTACHMENT_BLOCKS=()
  LEAN_ATTACHMENT_LEGACY_BLOCKS=()
  LEAN_ATTACHMENT_PLACEMENTS=()
  LEAN_ATTACHMENT_MODES=()
  LEAN_ATTACHMENT_ORIGINS=()
  LEAN_ATTACHMENT_BEFORE_HASHES=()
  LEAN_ATTACHMENT_MANAGED_HASHES=()
  LEAN_ATTACHMENT_PENDING_HASHES=()
  LEAN_ATTACHMENT_PREFLIGHT_STATUSES=()
  LEAN_ATTACHMENT_PREFLIGHT_IDENTITIES=()
  LEAN_ATTACHMENT_PREFLIGHT_HASHES=()
  LEAN_ATTACHMENT_REFRESHES=()
  LEAN_ATTACHMENT_ANCHORS=()
  LEAN_JSON_IDS=()
  LEAN_JSON_PATHS=()
  LEAN_JSON_VALIDATORS=()
  LEAN_JSON_STATUSES=()
  LEAN_JSON_FIELD_RESOURCES=()
  LEAN_JSON_FIELD_POINTERS=()
  LEAN_JSON_FIELD_TYPES=()
  LEAN_JSON_FIELD_MANAGED=()
  LEAN_JSON_FIELD_ORIGINALS=()
  LEAN_TARGET_OWNER=()
  LEAN_APPLY_STATE_IDENTITY=""
  LEAN_APPLY_STATE_HASH=""
  LEAN_APPLY_STATE_EXPECTED=false
  lean_refuse_v1_state
  lean_validate_all_state
}

lean_add_package() {
  local package="$1"
  [[ "$LEAN_ENTRY_KIND" == packages ]] || die 'validation-only areas cannot register packages'
  [[ "$package" =~ ^([a-z0-9-]+)/([a-z0-9-]+)$ ]] || die "invalid qualified package ID: $package"
  array_contains "$package" "${LEAN_PACKAGES[@]:-}" && die "duplicate lean package: $package"
  LEAN_PACKAGES+=("$package")
}

lean_add_guarded_attachment() {
  local id="$1" relative="$2" begin="$3" end="$4" token="$5" block="$6"
  local placement="$7" mode="$8" refresh="${9:-false}" anchor="${10:-}" legacy="${11:-}" existing
  [[ "$LEAN_ENTRY_KIND" == packages ]] || die 'validation-only areas cannot register attachments'
  [[ "$id" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "invalid attachment ID: $id"
  safe_relative_path "$relative" || die "unsafe guarded attachment path: $relative"
  [[ "$placement" == prepend || "$placement" == append || "$placement" == after-exact ]] ||
    die "invalid guarded attachment placement: $placement"
  [[ "$placement" == after-exact && -n "$anchor" || "$placement" != after-exact && -z "$anchor" ]] ||
    die 'invalid guarded attachment anchor'
  [[ "$mode" =~ ^0?[0-7]{3}$ ]] || die "invalid guarded attachment mode: $mode"
  [[ "$refresh" == true || "$refresh" == false ]] || die "invalid guarded attachment refresh policy: $refresh"
  [[ -n "$begin" && -n "$end" && -n "$token" && "$begin" != "$end" &&
    "$begin" == *"$token"* && "$end" == *"$token"* &&
    "$block" == "$begin"$'\n'* && "$block" == *$'\n'"$end" ]] || die 'invalid guarded attachment definition'
  [[ -z "$legacy" || ( "$legacy" != "$block" && "$legacy" == "$begin"$'\n'* && "$legacy" == *$'\n'"$end" ) ]] ||
    die 'invalid guarded attachment legacy definition'
  for existing in "${LEAN_ATTACHMENT_PATHS[@]:-}" "${LEAN_JSON_PATHS[@]:-}"; do
    [[ -n "$existing" ]] || continue
    [[ "$existing" != "$relative" ]] || die "duplicate guarded attachment path: $relative"
  done
  LEAN_ATTACHMENT_IDS+=("$id")
  LEAN_ATTACHMENT_PATHS+=("$relative")
  LEAN_ATTACHMENT_BEGINS+=("$begin")
  LEAN_ATTACHMENT_ENDS+=("$end")
  LEAN_ATTACHMENT_TOKENS+=("$token")
  LEAN_ATTACHMENT_BLOCKS+=("$block")
  LEAN_ATTACHMENT_LEGACY_BLOCKS+=("$legacy")
  LEAN_ATTACHMENT_PLACEMENTS+=("$placement")
  LEAN_ATTACHMENT_MODES+=("$mode")
  LEAN_ATTACHMENT_REFRESHES+=("$refresh")
  LEAN_ATTACHMENT_ANCHORS+=("$anchor")
}

lean_json_scalar_matches_type() {
  local value="$1" type="$2"
  jq -e --arg type "$type" '
    if $type == "integer" then type == "number" and floor == .
    elif $type == "number" then type == "number"
    elif $type == "string" then type == "string"
    elif $type == "boolean" then type == "boolean"
    elif $type == "null" then . == null
    else false end
  ' <<< "$value" >/dev/null 2>&1
}

# Register a fixed JSON object path and pointer/type/managed-JSON triples.
lean_add_json_scalar_fields() {
  local id="$1" relative="$2" validator="$3" pointer type managed existing resource_index
  shift 3
  [[ "$LEAN_ENTRY_KIND" == packages ]] || die 'validation-only areas cannot register JSON resources'
  [[ "$id" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "invalid JSON resource ID: $id"
  safe_relative_path "$relative" || die "unsafe JSON resource path: $relative"
  [[ "$(type -t -- "$validator" 2>/dev/null || true)" == function ]] || die "missing JSON resource validator: $validator"
  (($# > 0 && $# % 3 == 0)) || die 'JSON resource fields must be pointer/type/managed-value triples'
  for existing in "${LEAN_JSON_PATHS[@]:-}" "${LEAN_ATTACHMENT_PATHS[@]:-}"; do
    [[ -z "$existing" || "$existing" != "$relative" ]] || die "duplicate managed object path: $relative"
  done
  resource_index="${#LEAN_JSON_PATHS[@]}"
  LEAN_JSON_IDS+=("$id")
  LEAN_JSON_PATHS+=("$relative")
  LEAN_JSON_VALIDATORS+=("$validator")
  while (($# > 0)); do
    pointer="$1"; type="$2"; managed="$3"; shift 3
    [[ "$pointer" =~ ^/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$ ]] || die "unsupported JSON pointer: $pointer"
    [[ "$type" == integer || "$type" == number || "$type" == string || "$type" == boolean || "$type" == null ]] ||
      die "unsupported JSON scalar type: $type"
    managed="$(jq -er 'tojson' <<< "$managed" 2>/dev/null)" || die "invalid managed JSON scalar for $pointer"
    lean_json_scalar_matches_type "$managed" "$type" || die "managed JSON scalar has wrong type for $pointer"
    for existing in "${LEAN_JSON_FIELD_POINTERS[@]:-}"; do
      if [[ -n "$existing" ]]; then
        local field_index
        for field_index in "${!LEAN_JSON_FIELD_POINTERS[@]}"; do
          [[ "${LEAN_JSON_FIELD_RESOURCES[field_index]}" != "$resource_index" || "${LEAN_JSON_FIELD_POINTERS[field_index]}" != "$pointer" ]] ||
            die "duplicate JSON pointer: $pointer"
        done
        break
      fi
    done
    LEAN_JSON_FIELD_RESOURCES+=("$resource_index")
    LEAN_JSON_FIELD_POINTERS+=("$pointer")
    LEAN_JSON_FIELD_TYPES+=("$type")
    LEAN_JSON_FIELD_MANAGED+=("$managed")
    LEAN_JSON_FIELD_ORIGINALS+=("")
  done
}

lean_scan_packages() {
  local package layer name root packages_root path relative source parent lexical
  LEAN_TARGET_PATHS=()
  LEAN_TARGET_SOURCES=()
  LEAN_TARGET_LEXICAL=()
  LEAN_TARGET_OWNER=()
  packages_root="$(cd -- "$DOTFILES_DIR/packages" && pwd -P)"
  shopt -s dotglob nullglob globstar
  for package in "${LEAN_PACKAGES[@]}"; do
    layer="${package%%/*}"
    name="${package#*/}"
    root="$DOTFILES_DIR/packages/$layer/$name"
    [[ -d "$root" && ! -L "$root" ]] || die "missing package root: packages/$package"
    [[ "$(cd -- "$root" && pwd -P)" == "$packages_root/"* ]] || die "package root escapes packages/: $package"
    for path in "$root"/**/*; do
      relative="${path#"$root"/}"
      [[ "$relative" != .stow-local-ignore && "$relative" != .empty-package ]] || continue
      if [[ -L "$path" ]]; then
        die "package payload symlinks are not allowed: packages/$package/$relative"
      elif [[ -d "$path" ]]; then
        continue
      elif [[ ! -f "$path" ]]; then
        die "unsupported package payload: packages/$package/$relative"
      fi
      safe_relative_path "$relative" || die "unsafe package payload path: packages/$package/$relative"
      [[ -z "${LEAN_TARGET_OWNER[$relative]+x}" ]] ||
        die "duplicate payload target '$relative' in ${LEAN_TARGET_OWNER[$relative]} and $package"
      source="$(realpath -e -- "$path")"
      parent="$(dirname -- "$HOME/$relative")"
      lexical="$(realpath -m -s --relative-to="$parent" -- "$source")"
      LEAN_TARGET_OWNER["$relative"]="$package"
      LEAN_TARGET_PATHS+=("$relative")
      LEAN_TARGET_SOURCES+=("$source")
      LEAN_TARGET_LEXICAL+=("$lexical")
    done
  done
  shopt -u dotglob nullglob globstar
}

lean_link_is_exact() {
  local index="$1" path="$HOME/${LEAN_TARGET_PATHS[index]}"
  [[ -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" &&
    "$(readlink -- "$path")" == "${LEAN_TARGET_LEXICAL[index]}" &&
    "$(resolve_link "$path")" == "${LEAN_TARGET_SOURCES[index]}" ]]
}

lean_preflight_links() {
  local mode="$1" index path
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    path="$HOME/${LEAN_TARGET_PATHS[index]}"
    validate_home_parent_chain "$path"
    if [[ -e "$path" || -L "$path" ]]; then
      lean_link_is_exact "$index" || die "unrelated destination conflict: $path"
    elif [[ "$mode" == check ]]; then
      die "managed package link is absent: $path"
    fi
  done
}

lean_run_stow_preflight() {
  local mode="$1" package layer name output status
  local action=(--stow)
  [[ "$mode" != remove ]] || action=(--delete)
  for package in "${LEAN_PACKAGES[@]}"; do
    layer="${package%%/*}"
    name="${package#*/}"
    status=0
    output="$(stow --dir="$DOTFILES_DIR/packages/$layer" --target="$HOME" --no-folding "${action[@]}" "$name" --simulate 2>&1)" || status=$?
    [[ -z "$output" ]] || printf '%s\n' "$output" >&2
    ((status == 0)) || die "Stow conflict preflight failed for $package"
  done
}

lean_inspect_attachment() {
  local index="$1" path line inside=false line_number=0 anchor_line=0 begin_line=0
  local begin_count=0 end_count=0 anchor_count=0 found="" found_hash="" managed="" pending="" version="" state_has=false
  path="$HOME/${LEAN_ATTACHMENT_PATHS[index]}"
  LEAN_ATTACHMENT_STATUS=absent
  LEAN_ATTACHMENT_CURRENT_ORIGIN=created
  LEAN_ATTACHMENT_CURRENT_HASH=""
  LEAN_ATTACHMENT_FOUND_BLOCK=""
  if [[ ! -e "$path" && ! -L "$path" ]]; then return 0; fi
  [[ -f "$path" && ! -L "$path" ]] || die "guarded attachment is not a regular file: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "guarded attachment has an unsafe owner: $path"
  file_contains_nul "$path" && die "guarded attachment contains NUL bytes: $path"
  LEAN_ATTACHMENT_CURRENT_HASH="$(sha256_file "$path")"
  if [[ ! -s "$path" ]]; then
    LEAN_ATTACHMENT_CURRENT_ORIGIN=existing-empty
  elif [[ -z "$(tail -c 1 -- "$path")" ]]; then
    LEAN_ATTACHMENT_CURRENT_ORIGIN=existing-final-newline
  else
    LEAN_ATTACHMENT_CURRENT_ORIGIN=existing-no-final-newline
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number += 1))
    if [[ -n "${LEAN_ATTACHMENT_ANCHORS[index]}" && "$line" == "${LEAN_ATTACHMENT_ANCHORS[index]}" ]]; then
      ((anchor_count += 1)); anchor_line="$line_number"
    fi
    if [[ "$line" == "${LEAN_ATTACHMENT_BEGINS[index]}" ]]; then
      ((begin_count += 1)); [[ "$inside" == false ]] || { LEAN_ATTACHMENT_STATUS=malformed; return; }
      inside=true; found="$line"; begin_line="$line_number"
    elif [[ "$line" == "${LEAN_ATTACHMENT_ENDS[index]}" ]]; then
      ((end_count += 1)); [[ "$inside" == true ]] || { LEAN_ATTACHMENT_STATUS=malformed; return; }
      found+=$'\n'"$line"; inside=false
    elif [[ "$line" == *"${LEAN_ATTACHMENT_TOKENS[index]}"* ]]; then
      LEAN_ATTACHMENT_STATUS=malformed; return
    elif [[ "$inside" == true ]]; then
      found+=$'\n'"$line"
    fi
  done < "$path"
  if [[ "$inside" == true || "$begin_count" != "$end_count" || "$begin_count" -gt 1 ||
    ( -n "${LEAN_ATTACHMENT_ANCHORS[index]}" && ( "$anchor_count" != 1 || ( "$begin_count" == 1 && "$begin_line" != $((anchor_line + 1)) ) ) ) ]]; then
    LEAN_ATTACHMENT_STATUS=malformed
  elif ((begin_count == 0)); then
    LEAN_ATTACHMENT_STATUS=absent
  else
    found_hash="$(sha256_string "$found")"
    if [[ -f "$LEAN_STATE" ]]; then
      version="$(jq -r '.version' "$LEAN_STATE" 2>/dev/null)"
      if jq -e --arg path "${LEAN_ATTACHMENT_PATHS[index]}" '.attachments | has($path)' "$LEAN_STATE" >/dev/null 2>&1; then
        state_has=true
        if [[ "$version" == 3 ]]; then
          managed="$(jq -r --arg path "${LEAN_ATTACHMENT_PATHS[index]}" '.attachments[$path].managed_sha256 // ""' "$LEAN_STATE")"
          pending="$(jq -r --arg path "${LEAN_ATTACHMENT_PATHS[index]}" '.attachments[$path].pending_sha256 // ""' "$LEAN_STATE")"
        fi
      fi
    fi
    if [[ "$found" == "${LEAN_ATTACHMENT_BLOCKS[index]}" && "$managed" == "$found_hash" ]]; then
      LEAN_ATTACHMENT_STATUS=exact
    elif [[ "$found" == "${LEAN_ATTACHMENT_BLOCKS[index]}" && "$pending" == "$found_hash" ]]; then
      LEAN_ATTACHMENT_STATUS=pending
    elif [[ "$found" == "${LEAN_ATTACHMENT_BLOCKS[index]}" && "$state_has" == true && "$version" != 3 ]]; then
      LEAN_ATTACHMENT_STATUS=hashless
    elif [[ "$state_has" == true && "$version" != 3 && -n "${LEAN_ATTACHMENT_LEGACY_BLOCKS[index]}" &&
      "$found" == "${LEAN_ATTACHMENT_LEGACY_BLOCKS[index]}" ]]; then
      LEAN_ATTACHMENT_STATUS=legacy
    elif [[ -n "$pending" && "$pending" == "$found_hash" ]]; then
      LEAN_ATTACHMENT_STATUS=transitioned
    elif [[ -n "$managed" && "$managed" == "$found_hash" ]]; then
      LEAN_ATTACHMENT_STATUS=deployed
    else
      LEAN_ATTACHMENT_STATUS=malformed
    fi
  fi
  LEAN_ATTACHMENT_FOUND_BLOCK="$found"
}

lean_state_attachment_field() {
  local relative="$1" field="$2"
  jq -er --arg path "$relative" --arg field "$field" '.attachments[$path][$field]' "$LEAN_STATE" 2>/dev/null
}

lean_preflight_attachments() {
  local mode="$1" index relative path recorded_id recorded_origin recorded_hash state_count state_path registered state_has
  local state_version managed pending desired_hash found_hash
  LEAN_ATTACHMENT_ORIGINS=()
  LEAN_ATTACHMENT_BEFORE_HASHES=()
  LEAN_ATTACHMENT_MANAGED_HASHES=()
  LEAN_ATTACHMENT_PENDING_HASHES=()
  LEAN_ATTACHMENT_PREFLIGHT_STATUSES=()
  LEAN_ATTACHMENT_PREFLIGHT_IDENTITIES=()
  LEAN_ATTACHMENT_PREFLIGHT_HASHES=()
  if [[ -f "$LEAN_STATE" ]]; then
    state_count="$(jq '.attachments | length' "$LEAN_STATE")"
    if ((state_count != ${#LEAN_ATTACHMENT_PATHS[@]})); then
      [[ "$mode" == apply && "$state_count" -lt "${#LEAN_ATTACHMENT_PATHS[@]}" ]] ||
        die "lean state attachment set differs for area '$LEAN_AREA'"
      while IFS= read -r state_path; do
        registered=false
        for relative in "${LEAN_ATTACHMENT_PATHS[@]}"; do [[ "$state_path" != "$relative" ]] || registered=true; done
        [[ "$registered" == true ]] || die "lean state attachment set differs for area '$LEAN_AREA'"
      done < <(jq -r '.attachments | keys[]' "$LEAN_STATE")
    fi
  fi
  for index in "${!LEAN_ATTACHMENT_PATHS[@]}"; do
    relative="${LEAN_ATTACHMENT_PATHS[index]}"
    path="$HOME/$relative"
    lean_inspect_attachment "$index"
    [[ "$LEAN_ATTACHMENT_STATUS" != malformed ]] || die "guarded attachment is partial, malformed, duplicate, or modified: $HOME/$relative"
    capture_path_object_identity "$path" || die "could not inspect guarded attachment identity: $path"
    [[ "$PATH_OBJECT_IDENTITY" == absent || "$(sha256_file "$path")" == "$LEAN_ATTACHMENT_CURRENT_HASH" ]] ||
      die "guarded attachment changed during preflight: $path"
    LEAN_ATTACHMENT_PREFLIGHT_STATUSES+=("$LEAN_ATTACHMENT_STATUS")
    LEAN_ATTACHMENT_PREFLIGHT_IDENTITIES+=("$PATH_OBJECT_IDENTITY")
    LEAN_ATTACHMENT_PREFLIGHT_HASHES+=("$LEAN_ATTACHMENT_CURRENT_HASH")
    state_has=false
    if [[ -f "$LEAN_STATE" ]] && jq -e --arg path "$relative" '.attachments | has($path)' "$LEAN_STATE" >/dev/null; then state_has=true; fi
    [[ "$LEAN_ATTACHMENT_STATUS" != legacy || ( ( "$mode" == apply || "$mode" == remove ) && "$state_has" == true ) ]] ||
      die "guarded attachment differs from the current managed version: $HOME/$relative"
    if [[ "$state_has" == true ]]; then
      recorded_id="$(lean_state_attachment_field "$relative" id)" || die "lean state is missing attachment ownership: $relative"
      recorded_origin="$(lean_state_attachment_field "$relative" origin)"
      recorded_hash="$(jq -er --arg path "$relative" '.attachments[$path].before_sha256 // ""' "$LEAN_STATE")"
      [[ "$recorded_id" == "${LEAN_ATTACHMENT_IDS[index]}" ]] || die "lean attachment identity changed: $relative"
      LEAN_ATTACHMENT_ORIGINS+=("$recorded_origin")
      LEAN_ATTACHMENT_BEFORE_HASHES+=("$recorded_hash")
      state_version="$(jq -r '.version' "$LEAN_STATE")"
      managed=""; pending=""
      if [[ "$state_version" == 3 ]]; then
        managed="$(jq -r --arg path "$relative" '.attachments[$path].managed_sha256 // ""' "$LEAN_STATE")"
        pending="$(jq -r --arg path "$relative" '.attachments[$path].pending_sha256 // ""' "$LEAN_STATE")"
      fi
      desired_hash="$(sha256_string "${LEAN_ATTACHMENT_BLOCKS[index]}")"
      found_hash="$(sha256_string "$LEAN_ATTACHMENT_FOUND_BLOCK")"
      case "$LEAN_ATTACHMENT_STATUS" in
        hashless) managed="$desired_hash"; pending="" ;;
        legacy) managed="$found_hash"; [[ "$mode" != apply ]] || pending="$desired_hash" ;;
        deployed) [[ "$mode" != apply ]] || pending="$desired_hash" ;;
        transitioned) managed="$found_hash"; [[ "$mode" != apply ]] || pending="$desired_hash" ;;
        absent) [[ "$mode" != apply ]] || pending="$desired_hash" ;;
      esac
      LEAN_ATTACHMENT_MANAGED_HASHES+=("$managed")
      LEAN_ATTACHMENT_PENDING_HASHES+=("$pending")
      if [[ "$mode" == remove ]]; then
        [[ "$LEAN_ATTACHMENT_STATUS" == exact || "$LEAN_ATTACHMENT_STATUS" == deployed ||
          "$LEAN_ATTACHMENT_STATUS" == pending || "$LEAN_ATTACHMENT_STATUS" == transitioned ||
          "$LEAN_ATTACHMENT_STATUS" == hashless || "$LEAN_ATTACHMENT_STATUS" == legacy ||
          ( "$LEAN_ATTACHMENT_STATUS" == absent && ! -e "$HOME/$relative" && ! -L "$HOME/$relative" ) ]] ||
          die "recorded guarded attachment is modified or absent from a retained file: $HOME/$relative"
      elif [[ "$LEAN_ATTACHMENT_STATUS" == deployed || "$LEAN_ATTACHMENT_STATUS" == pending ||
        "$LEAN_ATTACHMENT_STATUS" == transitioned || "$LEAN_ATTACHMENT_STATUS" == legacy ]]; then
        [[ "$mode" == apply ]] || die "guarded attachment differs from the current managed version: $HOME/$relative"
      elif [[ "$LEAN_ATTACHMENT_STATUS" == absent ]]; then
        [[ "$mode" == apply ]] || die "recorded guarded attachment is absent: $HOME/$relative"
        if [[ "${LEAN_ATTACHMENT_REFRESHES[index]}" == true ]]; then
          LEAN_ATTACHMENT_ORIGINS[index]="$LEAN_ATTACHMENT_CURRENT_ORIGIN"
          LEAN_ATTACHMENT_BEFORE_HASHES[index]="$LEAN_ATTACHMENT_CURRENT_HASH"
        else
          [[ "$LEAN_ATTACHMENT_CURRENT_ORIGIN" == "$recorded_origin" && "$LEAN_ATTACHMENT_CURRENT_HASH" == "$recorded_hash" ]] ||
            die "guarded attachment pre-state changed before retry: $HOME/$relative"
        fi
      fi
    else
      [[ "$mode" == apply ]] || die "lean ownership state is absent for area '$LEAN_AREA'"
      [[ "$LEAN_ATTACHMENT_STATUS" == absent ]] || die "exact guarded attachment exists without v2 ownership state: $HOME/$relative"
      LEAN_ATTACHMENT_ORIGINS+=("$LEAN_ATTACHMENT_CURRENT_ORIGIN")
      LEAN_ATTACHMENT_BEFORE_HASHES+=("$LEAN_ATTACHMENT_CURRENT_HASH")
      LEAN_ATTACHMENT_MANAGED_HASHES+=("")
      LEAN_ATTACHMENT_PENDING_HASHES+=("$(sha256_string "${LEAN_ATTACHMENT_BLOCKS[index]}")")
    fi
  done
}

lean_json_pointer_value() {
  local file="$1" pointer="$2"
  jq -er --arg pointer "$pointer" '
    ($pointer | split("/")[1:]) as $path |
    reduce $path[] as $key ({found:true,value:.};
      if .found and (.value | type) == "object" and (.value | has($key)) then
        {found:true,value:.value[$key]}
      elif .found and (.value | type) == "array" and ($key | test("^(0|[1-9][0-9]*)$")) and
          (($key | tonumber) < (.value | length)) then
        {found:true,value:.value[$key | tonumber]}
      else {found:false} end) |
    select(.found) | (.value | tojson)
  ' "$file" 2>/dev/null
}

lean_validate_json_resource_file() {
  local index="$1" path="$2" field value
  validate_home_parent_chain "$path"
  [[ -f "$path" && ! -L "$path" ]] || die "JSON resource is not an EUID-owned regular file: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "JSON resource is not an EUID-owned regular file: $path"
  jq -e . "$path" >/dev/null 2>&1 || die "JSON resource is malformed: $path"
  "${LEAN_JSON_VALIDATORS[index]}" "$path" || die "JSON resource has an unsupported application shape: $path"
  for field in "${!LEAN_JSON_FIELD_POINTERS[@]}"; do
    [[ "${LEAN_JSON_FIELD_RESOURCES[field]}" == "$index" ]] || continue
    value="$(lean_json_pointer_value "$path" "${LEAN_JSON_FIELD_POINTERS[field]}")" ||
      die "JSON resource is missing registered pointer ${LEAN_JSON_FIELD_POINTERS[field]}: $path"
    lean_json_scalar_matches_type "$value" "${LEAN_JSON_FIELD_TYPES[field]}" ||
      die "JSON resource pointer has wrong scalar type ${LEAN_JSON_FIELD_POINTERS[field]}: $path"
  done
}

lean_preflight_json_resources() {
  local mode="$1" index field path state_count recorded_id recorded_type recorded_managed recorded_original
  local live all_managed all_original field_count state_field_count
  LEAN_JSON_STATUSES=()
  ((${#LEAN_JSON_PATHS[@]} > 0)) || return 0
  if [[ -f "$LEAN_STATE" ]]; then
    [[ "$(jq -r .version "$LEAN_STATE")" == 2 || "$(jq -r .version "$LEAN_STATE")" == 3 ]] ||
      die "lean state has no JSON resource ownership for area '$LEAN_AREA'"
    state_count="$(jq '.resources | length' "$LEAN_STATE")"
    ((state_count == ${#LEAN_JSON_PATHS[@]})) || die "lean state JSON resource set differs for area '$LEAN_AREA'"
  fi
  for index in "${!LEAN_JSON_PATHS[@]}"; do
    path="$HOME/${LEAN_JSON_PATHS[index]}"
    if [[ ! -e "$path" && ! -L "$path" && "$mode" == remove && -f "$LEAN_STATE" ]]; then
      LEAN_JSON_STATUSES+=(absent)
      continue
    fi
    lean_validate_json_resource_file "$index" "$path"
    if [[ -f "$LEAN_STATE" ]]; then
      recorded_id="$(jq -er --arg path "${LEAN_JSON_PATHS[index]}" '.resources[$path].id' "$LEAN_STATE" 2>/dev/null)" ||
        die "lean state is missing JSON resource ownership: ${LEAN_JSON_PATHS[index]}"
      [[ "$recorded_id" == "${LEAN_JSON_IDS[index]}" ]] || die "lean JSON resource identity changed: ${LEAN_JSON_PATHS[index]}"
      field_count=0
      for field in "${!LEAN_JSON_FIELD_POINTERS[@]}"; do
        [[ "${LEAN_JSON_FIELD_RESOURCES[field]}" == "$index" ]] || continue
        ((field_count += 1))
      done
      state_field_count="$(jq --arg path "${LEAN_JSON_PATHS[index]}" '.resources[$path].fields | length' "$LEAN_STATE")"
      ((field_count == state_field_count)) || die "lean state JSON pointer set differs: ${LEAN_JSON_PATHS[index]}"
    elif [[ "$mode" != apply ]]; then
      die "lean ownership state is absent for area '$LEAN_AREA'"
    fi
    all_managed=true; all_original=true
    for field in "${!LEAN_JSON_FIELD_POINTERS[@]}"; do
      [[ "${LEAN_JSON_FIELD_RESOURCES[field]}" == "$index" ]] || continue
      live="$(lean_json_pointer_value "$path" "${LEAN_JSON_FIELD_POINTERS[field]}")"
      if [[ -f "$LEAN_STATE" ]]; then
        recorded_type="$(jq -er --arg path "${LEAN_JSON_PATHS[index]}" --arg pointer "${LEAN_JSON_FIELD_POINTERS[field]}" \
          '.resources[$path].fields[$pointer].type' "$LEAN_STATE" 2>/dev/null)" || die "lean state is missing JSON pointer ownership: ${LEAN_JSON_FIELD_POINTERS[field]}"
        recorded_managed="$(jq -er --arg path "${LEAN_JSON_PATHS[index]}" --arg pointer "${LEAN_JSON_FIELD_POINTERS[field]}" \
          '.resources[$path].fields[$pointer].managed | tojson' "$LEAN_STATE")"
        recorded_original="$(jq -er --arg path "${LEAN_JSON_PATHS[index]}" --arg pointer "${LEAN_JSON_FIELD_POINTERS[field]}" \
          '.resources[$path].fields[$pointer].original | tojson' "$LEAN_STATE")"
        [[ "$recorded_type" == "${LEAN_JSON_FIELD_TYPES[field]}" && "$recorded_managed" == "${LEAN_JSON_FIELD_MANAGED[field]}" ]] ||
          die "lean JSON field registration changed: ${LEAN_JSON_FIELD_POINTERS[field]}"
        LEAN_JSON_FIELD_ORIGINALS[field]="$recorded_original"
        [[ "$live" == "$recorded_managed" ]] || all_managed=false
        [[ "$live" == "$recorded_original" ]] || all_original=false
      else
        LEAN_JSON_FIELD_ORIGINALS[field]="$live"
        all_managed=false
      fi
    done
    if [[ -f "$LEAN_STATE" ]]; then
      if [[ "$mode" == check ]]; then
        [[ "$all_managed" == true ]] || die "managed JSON fields differ: $path"
      else
        [[ "$all_managed" == true || "$all_original" == true ]] || die "managed JSON fields conflict: $path"
      fi
    fi
    if [[ "$all_managed" == true ]]; then LEAN_JSON_STATUSES+=(managed); else LEAN_JSON_STATUSES+=(original); fi
  done
}

lean_preflight_area() {
  local mode="$1"
  [[ "$mode" == apply || "$mode" == check || "$mode" == remove ]] || die "invalid lean operation: $mode"
  lean_refuse_v1_state
  lean_validate_all_state
  if [[ "$LEAN_ENTRY_KIND" == validation-only ]]; then
    [[ ${#LEAN_PACKAGES[@]} -eq 0 && ${#LEAN_ATTACHMENT_PATHS[@]} -eq 0 && ${#LEAN_JSON_PATHS[@]} -eq 0 ]] || die 'validation-only area has managed objects'
    [[ ! -e "$LEAN_STATE" && ! -L "$LEAN_STATE" ]] || die "validation-only area must not have state: $LEAN_STATE"
    return 0
  fi
  lean_scan_packages
  if ((${#LEAN_ATTACHMENT_PATHS[@]} > 0 || ${#LEAN_JSON_PATHS[@]} > 0)); then
    if [[ -e "$LEAN_STATE" || -L "$LEAN_STATE" ]]; then
      if [[ "$mode" == apply ]]; then
        capture_path_object_identity "$LEAN_STATE" || die "could not inspect lean state identity: $LEAN_STATE"
        LEAN_APPLY_STATE_IDENTITY="$PATH_OBJECT_IDENTITY"
        LEAN_APPLY_STATE_HASH="$(sha256_file "$LEAN_STATE")"
        LEAN_APPLY_STATE_EXPECTED=true
      fi
      lean_validate_state_file "$LEAN_STATE"
      [[ "$(jq -r .profile "$LEAN_STATE")" == "$LEAN_PROFILE" ]] || die "profile mismatch for area '$LEAN_AREA'"
    elif [[ "$mode" != apply ]]; then
      die "lean ownership state is absent for area '$LEAN_AREA'"
    else
      LEAN_APPLY_STATE_IDENTITY=absent
      LEAN_APPLY_STATE_HASH=""
      LEAN_APPLY_STATE_EXPECTED=true
    fi
  elif [[ -e "$LEAN_STATE" || -L "$LEAN_STATE" ]]; then
    die "package-only area must not have lean ownership state: $LEAN_STATE"
  fi
  lean_preflight_links "$mode"
  lean_run_stow_preflight "$mode"
  lean_preflight_attachments "$mode"
  lean_preflight_json_resources "$mode"
}

lean_ensure_directory() {
  local dir="$1" relative current component
  local components=()
  [[ "$dir" == "$HOME" || "$dir" == "$HOME/"* ]] || die "refusing to create directory outside HOME: $dir"
  validate_home_directory "$dir"
  [[ "$dir" != "$HOME" ]] || return 0
  relative="${dir#"$HOME"/}"
  current="$HOME"
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    current="$current/$component"
    if [[ -e "$current" || -L "$current" ]]; then
      [[ -d "$current" && ! -L "$current" ]] || die "cannot traverse managed directory: $current"
    else
      mkdir -- "$current"
    fi
  done
}

lean_build_state_json() {
  local attachments='{}' resources='{}' fields id path index field before managed pending
  for index in "${!LEAN_ATTACHMENT_PATHS[@]}"; do
    before="${LEAN_ATTACHMENT_BEFORE_HASHES[index]}"
    managed="${LEAN_ATTACHMENT_MANAGED_HASHES[index]:-}"
    pending="${LEAN_ATTACHMENT_PENDING_HASHES[index]:-}"
    if [[ -n "$before" ]]; then
      attachments="$(jq -c --arg path "${LEAN_ATTACHMENT_PATHS[index]}" --arg id "${LEAN_ATTACHMENT_IDS[index]}" \
        --arg origin "${LEAN_ATTACHMENT_ORIGINS[index]}" --arg before "$before" --arg managed "$managed" --arg pending "$pending" \
        '. + {($path):{id:$id,origin:$origin,before_sha256:$before,managed_sha256:(if $managed == "" then null else $managed end),pending_sha256:(if $pending == "" then null else $pending end)}}' <<< "$attachments")"
    else
      attachments="$(jq -c --arg path "${LEAN_ATTACHMENT_PATHS[index]}" --arg id "${LEAN_ATTACHMENT_IDS[index]}" \
        --arg origin "${LEAN_ATTACHMENT_ORIGINS[index]}" --arg managed "$managed" --arg pending "$pending" \
        '. + {($path):{id:$id,origin:$origin,before_sha256:null,managed_sha256:(if $managed == "" then null else $managed end),pending_sha256:(if $pending == "" then null else $pending end)}}' <<< "$attachments")"
    fi
  done
  if ((${#LEAN_JSON_PATHS[@]} > 0)); then
    for index in "${!LEAN_JSON_PATHS[@]}"; do
      fields='{}'
      for field in "${!LEAN_JSON_FIELD_POINTERS[@]}"; do
        [[ "${LEAN_JSON_FIELD_RESOURCES[field]}" == "$index" ]] || continue
        fields="$(jq -c --arg pointer "${LEAN_JSON_FIELD_POINTERS[field]}" --arg type "${LEAN_JSON_FIELD_TYPES[field]}" \
          --argjson original "${LEAN_JSON_FIELD_ORIGINALS[field]}" --argjson managed "${LEAN_JSON_FIELD_MANAGED[field]}" \
          '. + {($pointer):{type:$type,original:$original,managed:$managed}}' <<< "$fields")"
      done
      id="${LEAN_JSON_IDS[index]}"; path="${LEAN_JSON_PATHS[index]}"
      resources="$(jq -c --arg path "$path" --arg id "$id" --argjson fields "$fields" \
        '. + {($path):{id:$id,kind:"json-scalar-fields",fields:$fields}}' <<< "$resources")"
    done
  fi
  jq -cn --arg area "$LEAN_AREA" --arg profile "$LEAN_PROFILE" --argjson attachments "$attachments" --argjson resources "$resources" \
    '{version:3,profile:$profile,area:$area,attachments:$attachments,resources:$resources}'
}

lean_write_state_atomic() {
  local content dir base temporary temporary_hash temporary_identity source_hash source_identity
  ((${#LEAN_ATTACHMENT_PATHS[@]} > 0 || ${#LEAN_JSON_PATHS[@]} > 0)) || die 'refusing lean state write without guarded attachments'
  content="$(lean_build_state_json)"
  capture_path_object_identity "$LEAN_STATE" || die "could not inspect lean state identity: $LEAN_STATE"
  source_identity="$PATH_OBJECT_IDENTITY"
  source_hash=""
  [[ "$source_identity" == absent ]] || source_hash="$(sha256_file "$LEAN_STATE")"
  [[ "${LEAN_APPLY_STATE_EXPECTED:-false}" != true ||
    ( "$source_identity" == "$LEAN_APPLY_STATE_IDENTITY" && "$source_hash" == "$LEAN_APPLY_STATE_HASH" ) ]] ||
    die "lean state changed concurrently; refusing overwrite: $LEAN_STATE"
  if [[ "$source_identity" != absent && "$(jq -cS . "$LEAN_STATE")" == "$(jq -cS . <<< "$content")" ]]; then
    return 0
  fi
  dir="$(dirname -- "$LEAN_STATE")"
  base="${LEAN_STATE##*/}"
  lean_ensure_directory "$dir"
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  printf '%s\n' "$content" > "$temporary"
  chmod 0600 "$temporary"
  track_temp_path "$temporary"
  temporary_identity="$PATH_OBJECT_IDENTITY"
  temporary_hash="$(sha256_file "$temporary")"
  test_hold lean-before-state-rename
  capture_path_object_identity "$temporary" || die "could not recheck lean state temporary file: $temporary"
  if [[ "$PATH_OBJECT_IDENTITY" != "$temporary_identity" || "$(sha256_file "$temporary")" != "$temporary_hash" ]]; then
    retain_tracked_temp_path "$temporary"
    die "lean state temporary file changed before publication: $temporary"
  fi
  capture_path_object_identity "$LEAN_STATE" || die "could not recheck lean state identity: $LEAN_STATE"
  [[ "$PATH_OBJECT_IDENTITY" == "$source_identity" && ( "$source_identity" == absent || "$(sha256_file "$LEAN_STATE")" == "$source_hash" ) ]] ||
    die "lean state changed concurrently; refusing overwrite: $LEAN_STATE"
  mv -fT -- "$temporary" "$LEAN_STATE"
}

lean_replace_json_resource() {
  local index="$1" values="$2" path dir base temporary mode source_hash source_identity
  local temporary_hash temporary_identity
  local field updates='{}'
  path="$HOME/${LEAN_JSON_PATHS[index]}"
  [[ "${LEAN_JSON_STATUSES[index]}" != "$values" ]] || return 0
  lean_validate_json_resource_file "$index" "$path"
  source_hash="$(sha256_file "$path")"
  capture_path_object_identity "$path" || die "could not inspect JSON resource identity: $path"
  source_identity="$PATH_OBJECT_IDENTITY"
  mode="$(stat -c %a -- "$path")"; dir="$(dirname -- "$path")"; base="${path##*/}"
  for field in "${!LEAN_JSON_FIELD_POINTERS[@]}"; do
    [[ "${LEAN_JSON_FIELD_RESOURCES[field]}" == "$index" ]] || continue
    if [[ "$values" == managed ]]; then
      updates="$(jq -c --arg pointer "${LEAN_JSON_FIELD_POINTERS[field]}" --argjson value "${LEAN_JSON_FIELD_MANAGED[field]}" \
        '. + {($pointer):$value}' <<< "$updates")"
    else
      updates="$(jq -c --arg pointer "${LEAN_JSON_FIELD_POINTERS[field]}" --argjson value "${LEAN_JSON_FIELD_ORIGINALS[field]}" \
        '. + {($pointer):$value}' <<< "$updates")"
    fi
  done
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  track_temp_path "$temporary"
  temporary_identity="$PATH_OBJECT_IDENTITY"
  [[ -f "$temporary" && ! -L "$temporary" && "$(stat -c %u -- "$temporary")" == "$EUID" ]] ||
    die "unsafe JSON resource temporary file: $temporary"
  jq --argjson updates "$updates" '
    def pointer_path($root; $pointer):
      reduce ($pointer | split("/")[1:])[] as $key
        ({path: [], value: $root};
          if (.value | type) == "array" and ($key | test("^(0|[1-9][0-9]*)$")) then
            ($key | tonumber) as $index |
            {path: (.path + [$index]), value: .value[$index]}
          else
            {path: (.path + [$key]), value: .value[$key]}
          end) |
      .path;
    reduce ($updates | to_entries[]) as $update (.;
      . as $root | setpath(pointer_path($root; $update.key); $update.value))
  ' "$path" > "$temporary" || die "could not construct JSON resource replacement: $path"
  chmod "$mode" "$temporary"
  lean_validate_json_resource_file "$index" "$temporary"
  temporary_hash="$(sha256_file "$temporary")"
  test_hold lean-before-json-rename
  capture_path_object_identity "$temporary" || die "could not recheck JSON resource temporary file: $temporary"
  if [[ "$PATH_OBJECT_IDENTITY" != "$temporary_identity" || "$(sha256_file "$temporary")" != "$temporary_hash" ]]; then
    retain_tracked_temp_path "$temporary"
    die "JSON resource temporary file changed before publication: $temporary"
  fi
  capture_path_object_identity "$path" || die "could not recheck JSON resource identity: $path"
  [[ "$PATH_OBJECT_IDENTITY" == "$source_identity" && "$(sha256_file "$path")" == "$source_hash" ]] ||
    die "JSON resource changed concurrently; refusing overwrite: $path"
  mv -fT -- "$temporary" "$path"
  capture_path_object_identity "$temporary"
  [[ "$PATH_OBJECT_IDENTITY" == absent ]] || die "JSON resource temporary path remained after replacement: $temporary"
  lean_validate_json_resource_file "$index" "$path"
  LEAN_JSON_STATUSES[index]="$values"
}

lean_apply_stow() {
  local package layer name output status index path
  for package in "${LEAN_PACKAGES[@]}"; do
    layer="${package%%/*}"; name="${package#*/}"; status=0
    output="$(stow --dir="$DOTFILES_DIR/packages/$layer" --target="$HOME" --no-folding --stow "$name" 2>&1)" || status=$?
    [[ -z "$output" ]] || printf '%s\n' "$output" >&2
    ((status == 0)) || return "$status"
    for index in "${!LEAN_TARGET_PATHS[@]}"; do
      [[ "${LEAN_TARGET_OWNER[${LEAN_TARGET_PATHS[index]}]}" != "$package" ]] || {
        path="$HOME/${LEAN_TARGET_PATHS[index]}"
        lean_link_is_exact "$index" || die "Stow did not create the exact expected link: $path"
      }
    done
  done
}

lean_write_attachment() {
  local index="$1" path dir base temporary status origin source_hash source_identity source_mode
  local temporary_hash temporary_identity line read_status inside=false
  path="$HOME/${LEAN_ATTACHMENT_PATHS[index]}"
  origin="${LEAN_ATTACHMENT_ORIGINS[index]}"
  lean_inspect_attachment "$index"
  status="$LEAN_ATTACHMENT_STATUS"
  capture_path_object_identity "$path" || die "could not inspect guarded attachment identity: $path"
  [[ ( "$status" == "${LEAN_ATTACHMENT_PREFLIGHT_STATUSES[index]}" ||
      ( "${LEAN_ATTACHMENT_PREFLIGHT_STATUSES[index]}" == hashless && "$status" == exact ) ||
      ( "${LEAN_ATTACHMENT_PREFLIGHT_STATUSES[index]}" == legacy && "$status" == deployed ) ||
      ( "${LEAN_ATTACHMENT_PREFLIGHT_STATUSES[index]}" == transitioned && "$status" == deployed ) ) &&
    "$PATH_OBJECT_IDENTITY" == "${LEAN_ATTACHMENT_PREFLIGHT_IDENTITIES[index]}" &&
    "$LEAN_ATTACHMENT_CURRENT_HASH" == "${LEAN_ATTACHMENT_PREFLIGHT_HASHES[index]}" &&
    ( "$PATH_OBJECT_IDENTITY" == absent || "$(sha256_file "$path")" == "$LEAN_ATTACHMENT_CURRENT_HASH" ) ]] ||
    die "guarded attachment changed after preflight: $path"
  if [[ "$status" == exact || "$status" == hashless || "$status" == pending ]]; then
    LEAN_ATTACHMENT_MANAGED_HASHES[index]="$(sha256_string "${LEAN_ATTACHMENT_BLOCKS[index]}")"
    LEAN_ATTACHMENT_PENDING_HASHES[index]=""
    return 0
  fi
  [[ "$status" == absent || "$status" == legacy || "$status" == deployed || "$status" == transitioned ]] ||
    die "guarded attachment changed before apply: $path"
  if [[ "$status" == absent ]]; then
    [[ "$LEAN_ATTACHMENT_CURRENT_ORIGIN" == "$origin" && "$LEAN_ATTACHMENT_CURRENT_HASH" == "${LEAN_ATTACHMENT_BEFORE_HASHES[index]}" ]] ||
      die "guarded attachment changed before apply: $path"
  fi
  source_hash="$LEAN_ATTACHMENT_CURRENT_HASH"
  capture_path_object_identity "$path" || die "could not inspect guarded attachment identity: $path"
  source_identity="$PATH_OBJECT_IDENTITY"
  source_mode="${LEAN_ATTACHMENT_MODES[index]}"
  [[ "$status" == absent && "$origin" == created ]] || source_mode="$(stat -c %a -- "$path")"
  dir="$(dirname -- "$path")"; base="${path##*/}"
  lean_ensure_directory "$dir"
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  track_temp_path "$temporary"
  if [[ "$status" == legacy || "$status" == deployed || "$status" == transitioned ]]; then
    : > "$temporary"
    while true; do
      line=""; read_status=0; IFS= read -r line || read_status=$?
      if [[ "$line" == "${LEAN_ATTACHMENT_BEGINS[index]}" ]]; then
        printf '%s\n' "${LEAN_ATTACHMENT_BLOCKS[index]}" >> "$temporary"
        inside=true
      elif [[ "$inside" == true ]]; then
        [[ "$line" != "${LEAN_ATTACHMENT_ENDS[index]}" ]] || inside=false
      else
        printf '%s' "$line" >> "$temporary"
        ((read_status != 0)) || printf '\n' >> "$temporary"
      fi
      ((read_status == 0)) || break
    done < "$path"
  elif [[ "${LEAN_ATTACHMENT_PLACEMENTS[index]}" == prepend ]]; then
    printf '%s\n' "${LEAN_ATTACHMENT_BLOCKS[index]}" > "$temporary"
    [[ "$origin" == created ]] || dd if="$path" of="$temporary" oflag=append conv=notrunc status=none
  elif [[ "${LEAN_ATTACHMENT_PLACEMENTS[index]}" == append ]]; then
    : > "$temporary"
    [[ "$origin" == created ]] || dd if="$path" of="$temporary" conv=notrunc status=none
    [[ "$origin" != existing-no-final-newline ]] || printf '\n' >> "$temporary"
    printf '%s\n' "${LEAN_ATTACHMENT_BLOCKS[index]}" >> "$temporary"
  else
    : > "$temporary"
    while true; do
      line=""; read_status=0; IFS= read -r line || read_status=$?
      printf '%s' "$line" >> "$temporary"
      ((read_status != 0)) || printf '\n' >> "$temporary"
      if [[ "$line" == "${LEAN_ATTACHMENT_ANCHORS[index]}" ]]; then
        ((read_status == 0)) || die "guarded attachment anchor has no following line: $path"
        printf '%s\n' "${LEAN_ATTACHMENT_BLOCKS[index]}" >> "$temporary"
      fi
      ((read_status == 0)) || break
    done < "$path"
  fi
  chmod "$source_mode" "$temporary"
  capture_path_object_identity "$temporary" || die "could not inspect guarded attachment temporary file: $temporary"
  temporary_identity="$PATH_OBJECT_IDENTITY"; temporary_hash="$(sha256_file "$temporary")"
  test_hold lean-before-attachment-rename
  capture_path_object_identity "$temporary" || die "could not recheck guarded attachment temporary file: $temporary"
  [[ "$PATH_OBJECT_IDENTITY" == "$temporary_identity" && "$(sha256_file "$temporary")" == "$temporary_hash" ]] || {
    retain_tracked_temp_path "$temporary"
    die "guarded attachment temporary file changed before publication: $temporary"
  }
  capture_path_object_identity "$path" || die "could not recheck guarded attachment identity: $path"
  [[ "$PATH_OBJECT_IDENTITY" == "$source_identity" && ( "$source_identity" == absent || "$(sha256_file "$path")" == "$source_hash" ) ]] ||
    die "guarded attachment changed concurrently; refusing overwrite: $path"
  if [[ "$status" == absent && "$origin" == created ]]; then
    ln -T -- "$temporary" "$path" 2>/dev/null || { rm -f -- "$temporary"; die "guarded attachment destination appeared: $path"; }
    rm -- "$temporary"
  else
    mv -fT -- "$temporary" "$path"
  fi
  lean_inspect_attachment "$index"
  [[ "$LEAN_ATTACHMENT_STATUS" == exact || "$LEAN_ATTACHMENT_STATUS" == pending ]] ||
    die "guarded attachment apply did not converge: $path"
  LEAN_ATTACHMENT_MANAGED_HASHES[index]="$(sha256_string "${LEAN_ATTACHMENT_BLOCKS[index]}")"
  LEAN_ATTACHMENT_PENDING_HASHES[index]=""
}

lean_apply_area() {
  local index
  lean_preflight_area apply
  if [[ "$LEAN_ENTRY_KIND" == validation-only ]]; then return 0; fi
  # Persist every non-derivable origin before the first managed-object write.
  if ((${#LEAN_ATTACHMENT_PATHS[@]} > 0 || ${#LEAN_JSON_PATHS[@]} > 0)); then
    lean_write_state_atomic
    capture_path_object_identity "$LEAN_STATE" || die "could not inspect lean state identity: $LEAN_STATE"
    LEAN_APPLY_STATE_IDENTITY="$PATH_OBJECT_IDENTITY"
    LEAN_APPLY_STATE_HASH="$(sha256_file "$LEAN_STATE")"
    LEAN_APPLY_STATE_EXPECTED=true
  fi
  test_hold lean-after-state-write
  for index in "${!LEAN_JSON_PATHS[@]}"; do lean_replace_json_resource "$index" managed; done
  lean_apply_stow || return $?
  for index in "${!LEAN_ATTACHMENT_PATHS[@]}"; do lean_write_attachment "$index"; done
  if ((${#LEAN_ATTACHMENT_PATHS[@]} > 0)); then
    test_hold lean-before-final-state-write
    lean_write_state_atomic
  fi
}

lean_check_area() {
  lean_preflight_area check
}

lean_remove_stow() {
  local package layer name output status index index_target present
  for ((index=${#LEAN_PACKAGES[@]}-1; index>=0; index--)); do
    package="${LEAN_PACKAGES[index]}"; layer="${package%%/*}"; name="${package#*/}"; present=false
    for index_target in "${!LEAN_TARGET_PATHS[@]}"; do
      [[ "${LEAN_TARGET_OWNER[${LEAN_TARGET_PATHS[index_target]}]}" != "$package" ]] ||
        { [[ ! -e "$HOME/${LEAN_TARGET_PATHS[index_target]}" && ! -L "$HOME/${LEAN_TARGET_PATHS[index_target]}" ]] || present=true; }
    done
    [[ "$present" == true ]] || continue
    status=0
    output="$(stow --dir="$DOTFILES_DIR/packages/$layer" --target="$HOME" --no-folding --delete "$name" 2>&1)" || status=$?
    [[ -z "$output" ]] || printf '%s\n' "$output" >&2
    ((status == 0)) || return "$status"
  done
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    [[ ! -e "$HOME/${LEAN_TARGET_PATHS[index]}" && ! -L "$HOME/${LEAN_TARGET_PATHS[index]}" ]] ||
      die "Stow removal retained a managed link: $HOME/${LEAN_TARGET_PATHS[index]}"
  done
}

lean_remove_attachment() {
  local index="$1" path="$HOME/${LEAN_ATTACHMENT_PATHS[index]}" origin="${LEAN_ATTACHMENT_ORIGINS[index]}"
  local dir base temporary line status inside=false mode source_hash source_identity temporary_hash temporary_identity
  [[ -e "$path" || -L "$path" ]] || return 0
  lean_inspect_attachment "$index"
  [[ "$LEAN_ATTACHMENT_STATUS" == exact || "$LEAN_ATTACHMENT_STATUS" == deployed ||
    "$LEAN_ATTACHMENT_STATUS" == pending || "$LEAN_ATTACHMENT_STATUS" == transitioned ||
    "$LEAN_ATTACHMENT_STATUS" == hashless || "$LEAN_ATTACHMENT_STATUS" == legacy ]] ||
    die "recorded guarded attachment changed before removal: $path"
  source_hash="$(sha256_file "$path")"
  capture_path_object_identity "$path" || die "could not inspect guarded attachment identity: $path"
  source_identity="$PATH_OBJECT_IDENTITY"
  if [[ "$origin" == created ]]; then
    [[ "$(sha256_file "$path")" == "$(sha256_string "$LEAN_ATTACHMENT_FOUND_BLOCK"$'\n')" ]] ||
      die "created guarded attachment contains unrelated content: $path"
    test_hold lean-before-attachment-remove
    capture_path_object_identity "$path" || die "could not recheck guarded attachment identity: $path"
    [[ "$PATH_OBJECT_IDENTITY" == "$source_identity" && "$(sha256_file "$path")" == "$source_hash" ]] ||
      die "guarded attachment changed concurrently; refusing removal: $path"
    rm -- "$path"
    return 0
  fi
  dir="$(dirname -- "$path")"; base="${path##*/}"; mode="$(stat -c %a -- "$path")"
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  track_temp_path "$temporary"
  while true; do
    line=""; status=0; IFS= read -r line || status=$?
    if [[ "$line" == "${LEAN_ATTACHMENT_BEGINS[index]}" ]]; then
      if [[ "${LEAN_ATTACHMENT_PLACEMENTS[index]}" == append && "$origin" == existing-no-final-newline ]]; then
        [[ ! -s "$temporary" ]] || truncate -s -1 -- "$temporary"
      fi
      inside=true
    elif [[ "$line" == "${LEAN_ATTACHMENT_ENDS[index]}" ]]; then
      inside=false
    elif [[ "$inside" == false ]]; then
      printf '%s' "$line" >> "$temporary"
      ((status != 0)) || printf '\n' >> "$temporary"
    fi
    ((status == 0)) || break
  done < "$path"
  chmod "$mode" "$temporary"
  capture_path_object_identity "$temporary" || die "could not inspect guarded attachment temporary file: $temporary"
  temporary_identity="$PATH_OBJECT_IDENTITY"; temporary_hash="$(sha256_file "$temporary")"
  test_hold lean-before-attachment-remove
  capture_path_object_identity "$temporary" || die "could not recheck guarded attachment temporary file: $temporary"
  [[ "$PATH_OBJECT_IDENTITY" == "$temporary_identity" && "$(sha256_file "$temporary")" == "$temporary_hash" ]] || {
    retain_tracked_temp_path "$temporary"
    die "guarded attachment temporary file changed before publication: $temporary"
  }
  capture_path_object_identity "$path" || die "could not recheck guarded attachment identity: $path"
  [[ "$PATH_OBJECT_IDENTITY" == "$source_identity" && "$(sha256_file "$path")" == "$source_hash" ]] ||
    die "guarded attachment changed concurrently; refusing overwrite: $path"
  mv -fT -- "$temporary" "$path"
}

lean_remove_area() {
  local index state_hash state_identity
  lean_preflight_area remove
  [[ "$LEAN_ENTRY_KIND" != validation-only ]] || return 0
  for index in "${!LEAN_JSON_PATHS[@]}"; do
    [[ "${LEAN_JSON_STATUSES[index]}" == absent ]] || lean_replace_json_resource "$index" original
  done
  test_hold lean-after-json-remove
  lean_remove_stow || return $?
  for index in "${!LEAN_ATTACHMENT_PATHS[@]}"; do lean_remove_attachment "$index"; done
  if ((${#LEAN_ATTACHMENT_PATHS[@]} > 0 || ${#LEAN_JSON_PATHS[@]} > 0)); then
    lean_validate_state_file "$LEAN_STATE"
    state_hash="$(sha256_file "$LEAN_STATE")"
    capture_path_object_identity "$LEAN_STATE" || die "could not inspect lean state identity: $LEAN_STATE"
    state_identity="$PATH_OBJECT_IDENTITY"
    test_hold lean-before-state-remove
    capture_path_object_identity "$LEAN_STATE" || die "could not recheck lean state identity: $LEAN_STATE"
    [[ "$PATH_OBJECT_IDENTITY" == "$state_identity" && "$(sha256_file "$LEAN_STATE")" == "$state_hash" ]] ||
      die "lean state changed concurrently; refusing removal: $LEAN_STATE"
    rm -- "$LEAN_STATE"
  fi
}
