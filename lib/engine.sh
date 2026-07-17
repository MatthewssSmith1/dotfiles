# Generic deployment engine: manifests, state, transactions, Stow; sourced by bootstrap.sh exactly once.

TX_PATHS=()
TX_EXISTED=()
TX_SNAPSHOTS=()
TX_CREATED_DIRS=()
AREA=""
AREA_STATE=""
AREA_JOURNAL_PATHS=()
AREA_ATTACHMENT_VALIDATOR=""
AREA_ORDER=()
declare -A AREA_STATUS=()
DEPENDENCY_APT_INSTALL=()
DEPENDENCY_AREAS=()
DEPENDENCY_MODES=()
DEPENDENCY_PROFILES=()
DEPENDENCY_COMMANDS=()
DEPENDENCY_MANAGERS=()
DEPENDENCY_PACKAGES=()

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
  local line kind area modes profiles command manager package entry
  local fields=() schema_count=0 apt_count=0 native_count=0
  [[ -f "$manifest" && ! -L "$manifest" ]] || die 'missing manifests/dependencies.tsv'
  DEPENDENCY_APT_INSTALL=()
  DEPENDENCY_AREAS=()
  DEPENDENCY_MODES=()
  DEPENDENCY_PROFILES=()
  DEPENDENCY_COMMANDS=()
  DEPENDENCY_MANAGERS=()
  DEPENDENCY_PACKAGES=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != *$'\t'* && "$line" != *' '* ]] || die 'invalid dependency manifest'
    IFS='|' read -r -a fields <<< "$line"
    kind="${fields[0]}"
    case "$kind" in
      schema)
        ((${#fields[@]} == 2)) && [[ "${fields[1]}" == 1 ]] || die 'invalid dependency manifest'
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
        ((${#fields[@]} == 7)) || die 'invalid dependency manifest'
        area="${fields[1]}"; modes="${fields[2]}"; profiles="${fields[3]}"
        command="${fields[4]}"; manager="${fields[5]}"; package="${fields[6]}"
        [[ "$command" =~ ^[a-z0-9-]+$ ]] || die 'invalid dependency manifest'
        for entry in ${area//,/ }; do [[ -n "${AREA_STATUS[$entry]+x}" ]] || die 'invalid dependency manifest'; done
        for entry in ${modes//,/ }; do [[ "$entry" == apply || "$entry" == check || "$entry" == remove ]] || die 'invalid dependency manifest'; done
        for entry in ${profiles//,/ }; do [[ "$entry" == all || "$entry" == generic || "$entry" == wsl || "$entry" == omarchy ]] || die 'invalid dependency manifest'; done
        if [[ "$manager" == apt ]]; then
          [[ "$package" =~ ^[a-z0-9+.-]+$ ]] || die 'invalid dependency manifest'
        else
          [[ "$manager" == native && "$package" == - ]] || die 'invalid dependency manifest'
        fi
        DEPENDENCY_AREAS+=("$area")
        DEPENDENCY_MODES+=("$modes")
        DEPENDENCY_PROFILES+=("$profiles")
        DEPENDENCY_COMMANDS+=("$command")
        DEPENDENCY_MANAGERS+=("$manager")
        DEPENDENCY_PACKAGES+=("$package")
        ;;
      *) die 'invalid dependency manifest' ;;
    esac
  done < "$manifest"
  ((schema_count == 1 && apt_count == 1 && native_count == 1 && ${#DEPENDENCY_AREAS[@]} > 0)) || \
    die 'invalid dependency manifest'
}

check_manifest_dependencies() {
  local mode="$1" profile="$2" guidance="$3"
  local command manager package entry existing install_word index selected
  local missing_commands=() missing_packages=() native_missing=() row_areas=()

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
    csv_contains "${DEPENDENCY_MODES[index]}" "$mode" || continue
    if ! csv_contains "${DEPENDENCY_PROFILES[index]}" all &&
      ! csv_contains "${DEPENDENCY_PROFILES[index]}" "$profile"; then
      continue
    fi
    command="${DEPENDENCY_COMMANDS[index]}"
    manager="${DEPENDENCY_MANAGERS[index]}"
    package="${DEPENDENCY_PACKAGES[index]}"
    [[ -n "$command" ]] || continue
    command -v "$command" >/dev/null 2>&1 && continue
    array_contains "$command" "${missing_commands[@]}" || missing_commands+=("$command")
    if [[ "$manager" == apt && "$guidance" == true ]]; then
      existing=false
      for entry in "${missing_packages[@]}"; do [[ "$entry" != "$package" ]] || existing=true; done
      [[ "$existing" == true ]] || missing_packages+=("$package")
    elif [[ "$manager" == native ]]; then
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
    ((keys - ["area","attachments","backups","checkout_root","managed_directories","packages","profile","schema_version","target_root","targets"]) | length == 0) and
    (keys | length == 10) and
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
      (.id | type == "string") and (.path | type == "string") and
      (.content_hash | type == "string" and test("^[0-9a-f]{64}$")))) and
    (.backups | type == "array" and all(.[]; type == "string"))
  ' "$file" >/dev/null || die "malformed or unknown deployment state: $file"

  area="$(jq -r .area "$file")"
  basename="${file##*/}"
  [[ "$basename" == "$area.json" ]] || die "state area does not match filename: $file"
  while IFS= read -r value; do safe_relative_path "$value" || die "unsafe target path in state: $value"; done \
    < <(jq -r '.targets[].path, .managed_directories[], .attachments[].path' "$file")
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
    validate_home_directory "$path"
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
      lexical="$(realpath -m --relative-to="$target_parent" -- "$source")"
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
  [[ "$(readlink -- "$path")" == "$source" ]] || die "recorded target has different lexical ownership: $path"
  actual_resolved="$(resolve_link "$path")"
  [[ "$actual_resolved" == "$resolved" ]] || die "recorded target has different resolved ownership: $path"
}

owned_legacy_link() {
  local path="$1" destination="$2" source_relative="$3" area="$4" action="$5"
  local current_source="$DOTFILES_DIR/$source_relative"
  local manifest="$DOTFILES_DIR/manifests/legacy-links.json"
  local value lexical host_count record_count old_root expected resolved

  OWNED_LEGACY_SOURCE=""
  if known_link "$path" "$current_source"; then
    OWNED_LEGACY_SOURCE="$current_source"
    return 0
  fi
  [[ -L "$path" && -f "$manifest" && ! -L "$manifest" ]] || return 1
  host_count="$(jq --arg home "$TARGET_ROOT" '[.hosts[] | select(.home == $home)] | length' "$manifest" 2>/dev/null)" || return 1
  [[ "$host_count" == 1 ]] || return 1
  record_count="$(jq --arg home "$TARGET_ROOT" --arg destination "$destination" --arg source "$source_relative" \
    --arg area "$area" --arg action "$action" \
    '[.hosts[] | select(.home == $home) | .records[] |
      select(.[0] == $destination and .[1] == $source and .[2] == $area and .[4] == $action)] | length' \
    "$manifest" 2>/dev/null)" || return 1
  [[ "$record_count" == 1 ]] || return 1
  old_root="$(jq -er --arg home "$TARGET_ROOT" '.hosts[] | select(.home == $home) | .checkout_root |
    select(type == "string" and startswith("/"))' "$manifest" 2>/dev/null)" || return 1
  [[ "$(realpath -m -s -- "$old_root")" == "$old_root" ]] || return 1
  expected="$old_root/$source_relative"
  value="$(readlink -- "$path")"
  if [[ "$value" == /* ]]; then
    lexical="$(realpath -m -s -- "$value")"
  else
    lexical="$(realpath -m -s -- "$(dirname -- "$path")/$value")"
  fi
  [[ "$lexical" == "$expected" ]] || return 1
  if [[ -e "$path" ]]; then
    resolved="$(resolve_link "$path")"
    [[ "$resolved" == "$expected" ]] || return 1
    OWNED_LEGACY_SOURCE="$expected"
  else
    [[ -f "$current_source" && ! -L "$current_source" ]] || return 1
    OWNED_LEGACY_SOURCE="$current_source"
  fi
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
    if [[ -L "$path" ]]; then
      if [[ "$(readlink -- "$path")" == "${TARGET_LEXICAL[i]}" && "$(resolve_link "$path")" == "${TARGET_SOURCES[i]}" ]]; then
        continue
      fi
      if [[ "$OLD_STATE" == true ]]; then
        index="$(state_target_index "$AREA_STATE" "$relative")"
        [[ -n "$index" ]] && continue
      fi
      die "unrelated destination conflict: $path"
    elif [[ -e "$path" ]]; then
      die "unrelated destination conflict: $path"
    fi
  done
}

run_stow_preflight() {
  local package layer name output status=0 target="$HOME"
  if [[ "$OLD_STATE" == true && "$(jq -r .checkout_root "$AREA_STATE")" != "$CHECKOUT_ROOT" ]]; then
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
  local path="$1" index snapshot
  validate_home_parent_chain "$path"
  for index in "${!TX_PATHS[@]}"; do [[ "${TX_PATHS[index]}" != "$path" ]] || return 0; done
  index="${#TX_PATHS[@]}"
  snapshot="$JOURNAL_DIR/$index"
  TX_PATHS+=("$path")
  TX_SNAPSHOTS+=("$snapshot")
  if [[ -e "$path" || -L "$path" ]]; then
    cp -a -- "$path" "$snapshot"
    TX_EXISTED+=(true)
  else
    TX_EXISTED+=(false)
  fi
}

begin_transaction() {
  local path
  JOURNAL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-$AREA-journal.XXXXXX")"
  TEMP_PATHS+=("$JOURNAL_DIR")
  snapshot_path "$AREA_STATE"
  for path in "${AREA_JOURNAL_PATHS[@]}"; do
    snapshot_path "$path"
  done
  for path in "${TARGET_PATHS[@]}"; do snapshot_path "$HOME/$path"; done
  if [[ "$OLD_STATE" == true ]]; then
    while IFS= read -r path; do snapshot_path "$HOME/$path"; done < <(jq -r '.targets[].path' "$AREA_STATE")
  fi
  TRANSACTION_ACTIVE=true
}

rollback_transaction() {
  local index path dir failed=false
  test_hold before-rollback
  TRANSACTION_ROLLING_BACK=true
  set +e
  for ((index=${#TX_PATHS[@]}-1; index>=0; index--)); do
    path="${TX_PATHS[index]}"
    if ! home_parent_chain_safe "$path"; then
      failed=true
      continue
    fi
    rm -rf -- "$path" || failed=true
    if [[ "${TX_EXISTED[index]}" == true ]]; then
      ensure_directory "$(dirname -- "$path")" || failed=true
      cp -a -- "${TX_SNAPSHOTS[index]}" "$path" || failed=true
    fi
  done
  for dir in "${MANAGED_DIRS[@]:-}"; do [[ -n "$dir" ]] && rmdir -- "$HOME/$dir" 2>/dev/null || true; done
  for ((index=${#TX_CREATED_DIRS[@]}-1; index>=0; index--)); do
    rmdir -- "${TX_CREATED_DIRS[index]}" 2>/dev/null || true
  done
  set -e
  TRANSACTION_ACTIVE=false
  TRANSACTION_ROLLING_BACK=false
  [[ "$failed" == false ]] || {
    ROLLBACK_FAILED=true
    printf '[%s] error: rollback failed; inspect journal %s\n' "$SCRIPT_NAME" "$JOURNAL_DIR" >&2
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
  local content="$1" destination="$2" mode="$3"
  local dir base temporary
  dir="$(dirname -- "$destination")"
  base="${destination##*/}"
  ensure_directory "$dir"
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  TEMP_PATHS+=("$temporary")
  printf '%s\n' "$content" > "$temporary"
  chmod "$mode" "$temporary"
  test_hold before-atomic-rename
  mv -fT -- "$temporary" "$destination"
}

remove_recorded_links_for_apply() {
  local count index relative
  [[ "$OLD_STATE" == true ]] || return 0
  count="$(jq '.targets | length' "$AREA_STATE")"
  for ((index=0; index<count; index++)); do
    relative="$(jq -r ".targets[$index].path" "$AREA_STATE")"
    rm -- "$HOME/$relative"
  done
}

apply_stow_packages() {
  local package layer name output status
  for package in "${PACKAGES[@]}"; do
    layer="${package%%/*}"
    name="${package#*/}"
    status=0
    output="$(stow --dir="$DOTFILES_DIR/packages/$layer" --target="$HOME" --no-folding --stow "$name" 2>&1)" || status=$?
    [[ -z "$output" ]] || printf '%s\n' "$output" >&2
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
  done
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
