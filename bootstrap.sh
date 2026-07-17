#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly MANAGED_BEGIN='# >>> dotfiles managed git includes >>>'
readonly MANAGED_END='# <<< dotfiles managed git includes <<<'
readonly MANAGED_BLOCK="$MANAGED_BEGIN
[include]
	path = ~/.config/dotfiles/personal/git.conf
[include]
	path = ~/.gitconfig.local
[include]
	path = ~/.config/dotfiles/local/git.conf
$MANAGED_END"

MODE=apply
PROFILE_OVERRIDE=""
AREAS=()
TEMP_PATHS=()
TRANSACTION_ACTIVE=false
TRANSACTION_ROLLING_BACK=false
ROLLBACK_FAILED=false
JOURNAL_DIR=""
TX_PATHS=()
TX_EXISTED=()
TX_SNAPSHOTS=()
TX_CREATED_DIRS=()
DEPENDENCY_APT_INSTALL=()
DEPENDENCY_AREAS=()
DEPENDENCY_MODES=()
DEPENDENCY_PROFILES=()
DEPENDENCY_COMMANDS=()
DEPENDENCY_MANAGERS=()
DEPENDENCY_PACKAGES=()

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

die() {
  printf '[%s] error: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

cleanup() {
  local status=$?
  local path

  if [[ "$TRANSACTION_ACTIVE" == true && "$TRANSACTION_ROLLING_BACK" == false ]]; then
    rollback_transaction || true
  fi
  for path in "${TEMP_PATHS[@]}"; do
    [[ "$ROLLBACK_FAILED" != true || "$path" != "$JOURNAL_DIR" ]] || continue
    rm -rf -- "$path"
  done
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  printf 'usage: %s [apply|--check|--remove] [--profile omarchy|generic|wsl] [--area git ...]\n' "$SCRIPT_NAME" >&2
  exit 1
}

add_area() {
  local area="$1"
  local existing

  [[ "$area" == git ]] || die "area '$area' is not implemented in Stage 2"
  for existing in "${AREAS[@]}"; do
    [[ "$existing" != "$area" ]] || return 0
  done
  AREAS+=("$area")
}

parse_cli() {
  local operation_seen=false

  while (($# > 0)); do
    case "$1" in
      apply)
        [[ "$operation_seen" == false ]] || usage
        MODE=apply
        operation_seen=true
        ;;
      --check)
        [[ "$operation_seen" == false ]] || usage
        MODE=check
        operation_seen=true
        ;;
      --remove)
        [[ "$operation_seen" == false ]] || usage
        MODE=remove
        operation_seen=true
        ;;
      --profile)
        (($# >= 2)) || usage
        PROFILE_OVERRIDE="$2"
        shift
        ;;
      --profile=*)
        PROFILE_OVERRIDE="${1#*=}"
        ;;
      --area)
        (($# >= 2)) || usage
        add_area "$2"
        shift
        ;;
      --area=*)
        add_area "${1#*=}"
        ;;
      *) usage ;;
    esac
    shift
  done

  if [[ -n "$PROFILE_OVERRIDE" ]]; then
    [[ "$MODE" != remove ]] || die '--profile is invalid with --remove'
    case "$PROFILE_OVERRIDE" in
      omarchy|generic|wsl) ;;
      *) die "invalid profile '$PROFILE_OVERRIDE'; expected omarchy, generic, or wsl" ;;
    esac
  fi
  ((${#AREAS[@]} > 0)) || AREAS=(git)
}

validate_test_environment() {
  if [[ -n "${DOTFILES_TEST_FAIL_AT:-}" && "${DOTFILES_TESTING:-}" != 1 ]]; then
    die 'DOTFILES_TEST_FAIL_AT requires DOTFILES_TESTING=1'
  fi
  if [[ -n "${DOTFILES_TEST_HOLD_AT:-}${DOTFILES_TEST_HOLD_DIR:-}" && "${DOTFILES_TESTING:-}" != 1 ]]; then
    die 'DOTFILES_TEST_HOLD_* requires DOTFILES_TESTING=1'
  fi
  if [[ "${DOTFILES_TESTING:-}" == 1 ]]; then
    if [[ -n "${DOTFILES_TEST_HOST_ROOT:-}" ]]; then
      [[ "$DOTFILES_TEST_HOST_ROOT" == /* && -d "$DOTFILES_TEST_HOST_ROOT" ]] || \
        die 'DOTFILES_TEST_HOST_ROOT must be an absolute existing directory'
      HOST_ROOT="${DOTFILES_TEST_HOST_ROOT%/}"
    fi
    if [[ -n "${DOTFILES_TEST_HOLD_AT:-}${DOTFILES_TEST_HOLD_DIR:-}" ]]; then
      [[ -n "${DOTFILES_TEST_HOLD_AT:-}" && "${DOTFILES_TEST_HOLD_DIR:-}" == /* &&
        -d "$DOTFILES_TEST_HOLD_DIR" && ! -L "$DOTFILES_TEST_HOLD_DIR" ]] || \
        die 'test hold requires a point and an absolute existing regular directory'
    fi
  elif [[ -n "${DOTFILES_TEST_HOST_ROOT:-}${DOTFILES_TEST_UNAME:-}" ]]; then
    die 'test host overrides require DOTFILES_TESTING=1'
  fi
}

fault() {
  local point="$1"
  if [[ "${DOTFILES_TESTING:-}" == 1 && "${DOTFILES_TEST_FAIL_AT:-}" == "$point" ]]; then
    die "injected test failure at $point"
  fi
}

test_hold() {
  local point="$1"
  [[ "${DOTFILES_TESTING:-}" == 1 && "${DOTFILES_TEST_HOLD_AT:-}" == "$point" ]] || return 0
  : > "$DOTFILES_TEST_HOLD_DIR/$point.ready"
  while [[ ! -e "$DOTFILES_TEST_HOLD_DIR/$point.release" ]]; do sleep 0.02; done
}

safe_relative_path() {
  local path="$1"
  [[ -n "$path" && "$path" != /* && "$path" != . && "$path" != .. ]] || return 1
  [[ "/$path/" != *'/../'* && "/$path/" != *'/./'* ]] || return 1
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
}

home_parent_chain_safe() {
  local path="$1"
  local relative parent current component resolved
  local components=()

  [[ "$path" == "$HOME" || "$path" == "$HOME/"* ]] || return 1
  [[ "$path" != "$HOME" ]] || return 0
  relative="${path#"$HOME"}"
  relative="${relative#/}"
  parent="${relative%/*}"
  [[ "$parent" != "$relative" ]] || parent=""
  current="$HOME"
  if [[ -n "$parent" ]]; then
    IFS='/' read -r -a components <<< "$parent"
    for component in "${components[@]}"; do
      [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
      current="$current/$component"
      [[ ! -L "$current" ]] || return 1
      [[ ! -e "$current" || -d "$current" ]] || return 1
    done
  fi
  resolved="$(realpath -m -- "$(dirname -- "$path")")" || return 1
  [[ "$resolved" == "$TARGET_ROOT" || "$resolved" == "$TARGET_ROOT/"* ]]
}

validate_home_parent_chain() {
  local path="$1"
  home_parent_chain_safe "$path" || die "managed path has a symlinked, non-directory, or escaping parent: $path"
}

validate_home_directory() {
  local path="$1"
  validate_home_parent_chain "$path"
  if [[ -e "$path" || -L "$path" ]]; then
    [[ -d "$path" && ! -L "$path" ]] || die "managed directory is symlinked or not a directory: $path"
  fi
}

resolve_link() {
  local path="$1"
  local value
  value="$(readlink -- "$path")"
  if [[ "$value" == /* ]]; then
    realpath -m -- "$value"
  else
    realpath -m -- "$(dirname -- "$path")/$value"
  fi
}

known_link() {
  local path="$1"
  local expected="$2"
  local value
  local lexical
  local resolved

  [[ -L "$path" ]] || return 1
  value="$(readlink -- "$path")"
  if [[ "$value" == /* ]]; then
    lexical="$(realpath -m -s -- "$value")"
  else
    lexical="$(realpath -m -s -- "$(dirname -- "$path")/$value")"
  fi
  resolved="$(resolve_link "$path")"
  [[ "$lexical" == "$expected" && "$resolved" == "$expected" ]]
}

owned_legacy_link() {
  local path="$1" destination="$2" source_relative="$3"
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
    '[.hosts[] | select(.home == $home) | .records[] |
      select(.[0] == $destination and .[1] == $source and .[2] == "git" and .[4] == "migrate-stage-2")] | length' \
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

sha256_file() {
  sha256sum -- "$1" | while read -r hash _; do printf '%s' "$hash"; done
}

sha256_string() {
  printf '%s' "$1" | sha256sum | while read -r hash _; do printf '%s' "$hash"; done
}

parse_os_release() {
  local file="$HOST_ROOT/etc/os-release"
  local line key value quote
  OS_ID=""
  OS_VERSION_ID=""

  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -n "$line" && "$line" != \#* && "$line" == *=* ]] || continue
    key="${line%%=*}"
    case "$key" in ID|VERSION_ID) ;; *) continue ;; esac
    value="${line#*=}"
    if [[ "$value" == \"* || "$value" == \'* ]]; then
      quote="${value:0:1}"
      [[ ${#value} -ge 2 && "${value: -1}" == "$quote" ]] || die "malformed $key in $file"
      value="${value:1:${#value}-2}"
      [[ "$value" != *\\* ]] || die "escaped $key in $file is not supported"
    fi
    [[ "$value" =~ ^[A-Za-z0-9._+-]+$ ]] || die "invalid $key in $file"
    if [[ "$key" == ID ]]; then
      [[ -z "$OS_ID" ]] || die "duplicate ID in $file"
      OS_ID="${value,,}"
    else
      [[ -z "$OS_VERSION_ID" ]] || die "duplicate VERSION_ID in $file"
      OS_VERSION_ID="$value"
    fi
  done < "$file"
}

ubuntu_2404_or_newer() {
  local major minor
  [[ "$OS_ID" == ubuntu && "$OS_VERSION_ID" =~ ^([0-9]+)(\.([0-9]+))?([.][0-9]+)*$ ]] || return 1
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[3]:-0}"
  ((10#$major > 24 || (10#$major == 24 && 10#$minor >= 4)))
}

detect_host() {
  local version_path="$HOME/.local/share/omarchy/version"
  local command_path="$HOME/.local/share/omarchy/bin/omarchy-version"
  local version_signal=false
  local command_signal=false
  local kernel=""
  local system

  [[ -f "$version_path" && ! -L "$version_path" ]] && version_signal=true
  [[ -f "$command_path" && -x "$command_path" ]] && command_signal=true
  [[ "$version_signal" == "$command_signal" ]] || \
    die 'partial Omarchy installation: version file and omarchy-version executable must both be present'

  system="$(uname -s)"
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_UNAME:-}" ]]; then
    system="$DOTFILES_TEST_UNAME"
  fi
  IS_WSL=false
  if [[ "$system" == Linux && -f "$HOST_ROOT/proc/sys/kernel/osrelease" ]]; then
    IFS= read -r kernel < "$HOST_ROOT/proc/sys/kernel/osrelease" || true
    kernel="${kernel,,}"
    [[ "$kernel" == *microsoft* ]] && IS_WSL=true
  fi

  parse_os_release
  DETECTED_PROFILE=""
  DETECTED_CLASS=unsupported
  HOST_SUPPORTED=false
  if [[ "$version_signal" == true && "$IS_WSL" == true ]]; then
    die 'conflicting host signals: Omarchy and WSL were both detected'
  elif [[ "$system" != Linux ]]; then
    DETECTED_CLASS=unsupported
  elif [[ "$version_signal" == true ]]; then
    DETECTED_PROFILE=omarchy
    DETECTED_CLASS=omarchy
    HOST_SUPPORTED=true
  elif [[ "$IS_WSL" == true ]]; then
    DETECTED_PROFILE=wsl
    if ubuntu_2404_or_newer; then
      DETECTED_CLASS=supported-wsl
      HOST_SUPPORTED=true
    else
      DETECTED_CLASS=unsupported-wsl
    fi
  else
    DETECTED_PROFILE=generic
    if ubuntu_2404_or_newer; then
      DETECTED_CLASS=supported-generic
      HOST_SUPPORTED=true
    else
      DETECTED_CLASS=unsupported-generic
    fi
  fi
}

select_profile() {
  SELECTED_PROFILE="$DETECTED_PROFILE"
  if [[ -n "$PROFILE_OVERRIDE" ]]; then
    case "$DETECTED_CLASS:$PROFILE_OVERRIDE" in
      omarchy:omarchy|supported-wsl:wsl|supported-generic:generic) ;;
      supported-wsl:generic)
        log 'warning: generic profile selected on WSL; WSL adapters are omitted'
        ;;
      *) die "profile '$PROFILE_OVERRIDE' is not allowed for detected host class '$DETECTED_CLASS'" ;;
    esac
    SELECTED_PROFILE="$PROFILE_OVERRIDE"
  fi

  [[ -n "$SELECTED_PROFILE" ]] || die 'unsupported host: no deployment profile is available'
  if [[ "$HOST_SUPPORTED" != true ]]; then
    if [[ "$MODE" == check ]]; then
      log "detected profile '$SELECTED_PROFILE' is not supported for mutation on ${OS_ID:-unknown} ${OS_VERSION_ID:-unknown}"
      return 1
    fi
    die "detected profile '$SELECTED_PROFILE' is not supported for mutating apply"
  fi
  log "detected host class '$DETECTED_CLASS'; selected profile '$SELECTED_PROFILE'"
}

csv_contains() {
  local csv="$1" expected="$2" entry
  local entries=()
  IFS=',' read -r -a entries <<< "$csv"
  for entry in "${entries[@]}"; do [[ "$entry" != "$expected" ]] || return 0; done
  return 1
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
    [[ -n "$line" && "$line" != *$'\t'* && "$line" != *' '* ]] || die 'invalid Git dependency manifest'
    IFS='|' read -r -a fields <<< "$line"
    kind="${fields[0]}"
    case "$kind" in
      schema)
        ((${#fields[@]} == 2)) && [[ "${fields[1]}" == 1 ]] || die 'invalid Git dependency manifest'
        ((schema_count += 1))
        ;;
      manager)
        if [[ "${fields[1]:-}" == apt ]]; then
          ((${#fields[@]} == 6)) && [[ "${fields[*]:2}" == 'sudo apt-get install -y' ]] || \
            die 'invalid Git dependency manifest'
          DEPENDENCY_APT_INSTALL=("${fields[@]:2}")
          ((apt_count += 1))
        elif [[ "${fields[1]:-}" == native ]]; then
          ((${#fields[@]} == 2)) || die 'invalid Git dependency manifest'
          ((native_count += 1))
        else
          die 'invalid Git dependency manifest'
        fi
        ;;
      require)
        ((${#fields[@]} == 7)) || die 'invalid Git dependency manifest'
        area="${fields[1]}"; modes="${fields[2]}"; profiles="${fields[3]}"
        command="${fields[4]}"; manager="${fields[5]}"; package="${fields[6]}"
        [[ "$area" == git && "$command" =~ ^[a-z0-9-]+$ ]] || die 'invalid Git dependency manifest'
        for entry in ${modes//,/ }; do [[ "$entry" == apply || "$entry" == check || "$entry" == remove ]] || die 'invalid Git dependency manifest'; done
        for entry in ${profiles//,/ }; do [[ "$entry" == all || "$entry" == generic || "$entry" == wsl || "$entry" == omarchy ]] || die 'invalid Git dependency manifest'; done
        if [[ "$manager" == apt ]]; then
          [[ "$package" =~ ^[a-z0-9+.-]+$ ]] || die 'invalid Git dependency manifest'
        else
          [[ "$manager" == native && "$package" == - ]] || die 'invalid Git dependency manifest'
        fi
        DEPENDENCY_AREAS+=("$area")
        DEPENDENCY_MODES+=("$modes")
        DEPENDENCY_PROFILES+=("$profiles")
        DEPENDENCY_COMMANDS+=("$command")
        DEPENDENCY_MANAGERS+=("$manager")
        DEPENDENCY_PACKAGES+=("$package")
        ;;
      *) die 'invalid Git dependency manifest' ;;
    esac
  done < "$manifest"
  ((schema_count == 1 && apt_count == 1 && native_count == 1 && ${#DEPENDENCY_AREAS[@]} > 0)) || \
    die 'invalid Git dependency manifest'
}

check_manifest_dependencies() {
  local mode="$1" profile="$2" guidance="$3"
  local command manager package entry existing install_word index
  local missing_commands=() missing_packages=() native_missing=()

  for index in "${!DEPENDENCY_AREAS[@]}"; do
    [[ "${DEPENDENCY_AREAS[index]}" == git ]] || continue
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
  local schema area basename value

  validate_home_parent_chain "$file"
  [[ -f "$file" && ! -L "$file" ]] || die "state is not a regular file: $file"
  schema="$(jq -er '.schema_version | select(type == "number")' "$file" 2>/dev/null)" || \
    die "malformed or unknown deployment state: $file"
  [[ "$schema" =~ ^[0-9]+$ ]] || die "malformed or unknown deployment state: $file"
  ((schema <= 1)) || die "newer deployment state schema $schema is not supported: $file"
  ((schema == 1)) || die "unknown deployment state schema $schema: $file"
  jq -e '
    type == "object" and
    ((keys - ["area","attachments","backups","checkout_root","managed_directories","packages","profile","schema_version","target_root","targets"]) | length == 0) and
    (keys | length == 10) and
    (.profile == "omarchy" or .profile == "generic" or .profile == "wsl") and
    (.area == "git" or .area == "bash" or .area == "tmux" or .area == "nvim" or .area == "zsh") and
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
  local file="$DOTFILES_DIR/profiles/$SELECTED_PROFILE.conf"
  local line area package extra found=false
  PACKAGES=()

  [[ -f "$file" && ! -L "$file" ]] || die "missing profile manifest: $file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != \#* ]] || continue
    read -r area package extra <<< "$line"
    [[ -n "$area" && -n "$package" && -z "${extra:-}" ]] || die "malformed profile entry: $line"
    [[ "$area" == git ]] || die "profile contains an area not implemented in Stage 2: $area"
    [[ "$found" == false ]] || die "duplicate git closure in $file"
    while [[ -n "$package" ]]; do
      PACKAGES+=("$package")
      package=""
    done
    found=true
  done < "$file"
  [[ "$found" == true ]] || die "profile has no git closure: $file"

  # Profile entries use comma-separated qualified IDs to keep order explicit.
  IFS=',' read -r -a PACKAGES <<< "${PACKAGES[0]}"
}

validate_package_root() {
  local package="$1"
  local layer area root resolved packages_root
  [[ "$package" =~ ^([a-z0-9-]+)/(git)$ ]] || die "invalid qualified package ID: $package"
  layer="${BASH_REMATCH[1]}"
  area="${BASH_REMATCH[2]}"
  root="$DOTFILES_DIR/packages/$layer/$area"
  [[ -d "$root" && ! -L "$root" ]] || die "missing package root: packages/$package"
  resolved="$(cd -- "$root" && pwd -P)"
  packages_root="$(cd -- "$DOTFILES_DIR/packages" && pwd -P)"
  [[ "$resolved" == "$packages_root/"* ]] || die "package root escapes packages/: $package"
}

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do [[ "$item" != "$needle" ]] || return 0; done
  return 1
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
  local package layer area root path relative source target_parent lexical
  declare -gA TARGET_OWNER=()
  TARGET_PATHS=()
  TARGET_SOURCES=()
  TARGET_LEXICAL=()
  MANAGED_DIRS=()
  shopt -s dotglob nullglob globstar
  for package in "${PACKAGES[@]}"; do
    validate_package_root "$package"
    layer="${package%%/*}"
    area="${package#*/}"
    root="$DOTFILES_DIR/packages/$layer/$area"
    for path in "$root"/**/*; do
      relative="${path#"$root"/}"
      [[ "$relative" != .stow-local-ignore ]] || continue
      [[ "$package:$relative" != generic/git:.stage2-empty ]] || continue
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

validate_managed_global() {
  local file="$1"
  local line inside=false begin=0 end=0 block=""
  [[ -f "$file" && ! -L "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$MANAGED_BEGIN" ]]; then
      ((begin += 1))
      [[ "$inside" == false ]] || return 1
      inside=true
      block="$line"
    elif [[ "$line" == "$MANAGED_END" ]]; then
      ((end += 1))
      [[ "$inside" == true ]] || return 1
      block+=$'\n'"$line"
      inside=false
    elif [[ "$line" == *'dotfiles managed git includes'* ]]; then
      return 1
    elif [[ "$inside" == true ]]; then
      block+=$'\n'"$line"
    fi
  done < "$file"
  [[ "$inside" == false && "$begin" == 1 && "$end" == 1 && "$block" == "$MANAGED_BLOCK" ]]
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
  validate_home_parent_chain "$path"

  if [[ -L "$path" ]]; then
    owned_legacy_link "$path" .gitconfig.local .gitconfig.local || die "$path is an unknown identity symlink"
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
}

load_baseline_keys() {
  local file key
  declare -gA BASELINE_KEYS=()
  for key in alias.co alias.br alias.ci alias.st init.defaultbranch pull.rebase \
    push.autosetupremote diff.algorithm diff.colormoved diff.mnemonicprefix \
    commit.verbose column.ui branch.sort tag.sort rerere.enabled rerere.autoupdate; do
    BASELINE_KEYS["$key"]=1
  done
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
  done <<'EOF'
alias.co	checkout
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
rerere.autoupdate	true
EOF
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
}

inspect_git_configuration() {
  git -C "$HOME" config --includes --show-origin --show-scope --list >/dev/null 2>&1 || \
    die 'current global or XDG Git configuration cannot be inspected with origin and scope'
}

validate_migrations_ledger() {
  local path="$HOME/.local/state/dotfiles/v1/migrations.json"
  validate_home_parent_chain "$path"
  [[ ! -e "$path" && ! -L "$path" ]] && return 0
  [[ -f "$path" && ! -L "$path" ]] || die "$path is not a regular file"
  jq -e '
    type == "object" and keys == ["migrations","schema_version"] and .schema_version == 1 and
    (.migrations | type == "array" and all(.[];
      type == "object" and keys == ["backups","completed_at","id","source_fingerprint"] and
      (.id | type == "string") and (.source_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
      (.completed_at | type == "string") and (.backups | type == "array")))
  ' "$path" >/dev/null || die "malformed or unknown migration ledger: $path"
}

refuse_repeated_legacy_migration() {
  local path="$HOME/.local/state/dotfiles/v1/migrations.json"
  [[ "$MIGRATION_REQUIRED" == true || "$IDENTITY_ACTION" == copy ]] || return 0
  [[ -f "$path" ]] || return 0
  jq -e '.migrations[] | select(.id == "git-legacy-v1")' "$path" >/dev/null || return 0
  die 'Git legacy migration is already recorded but legacy files reappeared'
}

preflight_global() {
  local path="$HOME/.gitconfig"
  local expected="$DOTFILES_DIR/.gitconfig"
  GLOBAL_ACTION=none
  GLOBAL_KIND=managed
  GLOBAL_LEGACY_SOURCE=""
  MIGRATION_KEYS=()
  MIGRATION_VALUES=()
  MIGRATION_REQUIRED=false
  validate_home_parent_chain "$path"

  if [[ -L "$path" ]]; then
    owned_legacy_link "$path" .gitconfig .gitconfig || die "$path is an unknown global-config symlink"
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

preflight_existing_state() {
  GIT_STATE="$HOME/.local/state/dotfiles/v1/git.json"
  OLD_STATE=false
  if [[ -e "$GIT_STATE" || -L "$GIT_STATE" ]]; then
    validate_state_file "$GIT_STATE"
    [[ "$(jq -r .target_root "$GIT_STATE")" == "$TARGET_ROOT" ]] || die 'Git state belongs to a different target root'
    OLD_STATE=true
    local count index dir path
    count="$(jq '.targets | length' "$GIT_STATE")"
    for ((index=0; index<count; index++)); do validate_recorded_target "$GIT_STATE" "$index"; done
    validate_attachment_from_state "$GIT_STATE"
    while IFS= read -r dir; do
      path="$HOME/$dir"
      validate_home_directory "$path"
      array_contains "$dir" "${MANAGED_DIRS[@]}" || MANAGED_DIRS+=("$dir")
    done < <(jq -r '.managed_directories[]' "$GIT_STATE")
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
        index="$(state_target_index "$GIT_STATE" "$relative")"
        [[ -n "$index" ]] && continue
      fi
      die "unrelated destination conflict: $path"
    elif [[ -e "$path" ]]; then
      die "unrelated destination conflict: $path"
    fi
  done
}

run_stow_preflight() {
  local package layer area output status=0 target="$HOME"
  if [[ "$OLD_STATE" == true && "$(jq -r .checkout_root "$GIT_STATE")" != "$CHECKOUT_ROOT" ]]; then
    target="$DOTFILES_DIR/tests/fixtures/empty-home"
    [[ -d "$target" && ! -L "$target" ]] || die 'missing moved-checkout Stow preflight target'
  fi
  for package in "${PACKAGES[@]}"; do
    layer="${package%%/*}"
    area="${package#*/}"
    output="$(stow --dir="$DOTFILES_DIR/packages/$layer" --target="$target" --no-folding --stow "$area" --simulate 2>&1)" || status=$?
    if ((status != 0)); then
      [[ -z "$output" ]] || printf '%s\n' "$output" >&2
      die "Stow conflict preflight failed for $package"
    fi
    status=0
  done
}

preflight_git() {
  load_profile_closure
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
  JOURNAL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-git-journal.XXXXXX")"
  TEMP_PATHS+=("$JOURNAL_DIR")
  for path in "$HOME/.gitconfig" "$HOME/.gitconfig.local" \
    "$HOME/.config/dotfiles/local/git.conf" "$GIT_STATE" \
    "$HOME/.local/state/dotfiles/v1/migrations.json"; do
    snapshot_path "$path"
  done
  for path in "${TARGET_PATHS[@]}"; do snapshot_path "$HOME/$path"; done
  if [[ "$OLD_STATE" == true ]]; then
    while IFS= read -r path; do snapshot_path "$HOME/$path"; done < <(jq -r '.targets[].path' "$GIT_STATE")
  fi
  TRANSACTION_ACTIVE=true
}

rollback_transaction() {
  local index path dir failed=false
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
  log 'rolled back incomplete Git deployment'
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

apply_central_local() {
  local path="$HOME/.config/dotfiles/local/git.conf" temporary i
  [[ "$CENTRAL_ACTION" == create ]] || return 0
  ensure_directory "$(dirname -- "$path")"
  temporary="$(mktemp "$(dirname -- "$path")/.git.conf.tmp.XXXXXX")"
  TEMP_PATHS+=("$temporary")
  chmod 0600 "$temporary"
  for i in "${!MIGRATION_KEYS[@]}"; do
    git config --file "$temporary" --add "${MIGRATION_KEYS[i]}" "${MIGRATION_VALUES[i]}"
  done
  validate_git_file "$temporary"
  mv -fT -- "$temporary" "$path"
}

apply_identity() {
  local path="$HOME/.gitconfig.local" temporary source
  [[ "$IDENTITY_ACTION" != none ]] || return 0
  ensure_directory "$HOME"
  temporary="$(mktemp "$HOME/.gitconfig.local.tmp.XXXXXX")"
  TEMP_PATHS+=("$temporary")
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
  mv -fT -- "$temporary" "$path"
}

apply_global() {
  local path="$HOME/.gitconfig"
  case "$GLOBAL_ACTION" in
    none) ;;
    create|replace) write_string_atomic "$MANAGED_BLOCK" "$path" 0644 ;;
    *) die "unknown global action: $GLOBAL_ACTION" ;;
  esac
}

remove_recorded_links_for_apply() {
  local count index relative
  [[ "$OLD_STATE" == true ]] || return 0
  count="$(jq '.targets | length' "$GIT_STATE")"
  for ((index=0; index<count; index++)); do
    relative="$(jq -r ".targets[$index].path" "$GIT_STATE")"
    rm -- "$HOME/$relative"
  done
}

apply_stow_packages() {
  local package layer area output status
  for package in "${PACKAGES[@]}"; do
    layer="${package%%/*}"
    area="${package#*/}"
    status=0
    output="$(stow --dir="$DOTFILES_DIR/packages/$layer" --target="$HOME" --no-folding --stow "$area" 2>&1)" || status=$?
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

update_migrations_ledger() {
  local path="$HOME/.local/state/dotfiles/v1/migrations.json"
  local current='{"schema_version":1,"migrations":[]}' fingerprint entry updated source_material=""
  [[ "$MIGRATION_REQUIRED" == true || "$IDENTITY_ACTION" == copy ]] || return 0
  if [[ -f "$path" ]]; then current="$(< "$path")"; fi
  if jq -e '.migrations[] | select(.id == "git-legacy-v1")' <<< "$current" >/dev/null; then
    die 'Git legacy migration is already recorded but legacy files reappeared'
  fi
  [[ "$GLOBAL_KIND" != legacy ]] || source_material+="$(sha256_file "$GLOBAL_LEGACY_SOURCE")"
  [[ "$IDENTITY_ACTION" != copy ]] || source_material+="$(sha256_file "$IDENTITY_SOURCE")"
  fingerprint="$(sha256_string "$source_material")"
  entry="$(jq -cn --arg id git-legacy-v1 --arg fingerprint "$fingerprint" --arg completed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{id:$id,source_fingerprint:$fingerprint,completed_at:$completed,backups:[]}')"
  updated="$(jq -c --argjson entry "$entry" '.migrations += [$entry]' <<< "$current")"
  write_string_atomic "$updated" "$path" 0600
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
    actual="$(git -C "$HOME" config --includes --get "$key" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] || die "effective $key does not match the accepted baseline"
    origin="$(git -C "$HOME" config --includes --show-origin --show-scope --get "$key" 2>/dev/null || true)"
    [[ "$origin" == global$'\t'file:"$baseline_origin"$'\t'* ]] || \
      die "effective $key does not originate from the baseline Git layer at global scope"
  done <<'EOF'
alias.co	checkout
alias.br	branch
alias.ci	commit
alias.st	status
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
rerere.autoupdate	true
EOF
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
  write_string_atomic "$state_json" "$GIT_STATE" 0600
  TRANSACTION_ACTIVE=false
  fault after-state-commit
  log "applied Git area for profile '$SELECTED_PROFILE'"
}

write_without_managed_block() {
  local source="$1" destination="$2"
  local dir base temporary line inside=false status mode
  dir="$(dirname -- "$destination")"
  base="${destination##*/}"
  temporary="$(mktemp "$dir/.$base.tmp.XXXXXX")"
  TEMP_PATHS+=("$temporary")
  mode="$(stat -c %a -- "$source")"
  while true; do
    line=""
    status=0
    IFS= read -r line || status=$?
    if [[ "$line" == "$MANAGED_BEGIN" ]]; then
      inside=true
    elif [[ "$line" == "$MANAGED_END" ]]; then
      inside=false
    elif [[ "$inside" == false ]]; then
      printf '%s' "$line" >> "$temporary"
      ((status != 0)) || printf '\n' >> "$temporary"
    fi
    ((status == 0)) || break
  done < "$source"
  chmod "$mode" "$temporary"
  if [[ -s "$temporary" ]]; then
    mv -fT -- "$temporary" "$destination"
  else
    rm -- "$temporary" "$destination"
  fi
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

remove_git() {
  local state="$HOME/.local/state/dotfiles/v1/git.json"
  local count index relative dir
  local managed_directories=()
  if [[ ! -e "$state" && ! -L "$state" ]]; then
    log 'Git area is not deployed; no changes made'
    return
  fi
  validate_state_file "$state"
  [[ "$(jq -r .target_root "$state")" == "$TARGET_ROOT" ]] || die 'Git state belongs to a different target root'
  count="$(jq '.targets | length' "$state")"
  for ((index=0; index<count; index++)); do validate_recorded_target "$state" "$index"; done
  validate_attachment_from_state "$state"
  while IFS= read -r dir; do
    validate_home_directory "$HOME/$dir"
    managed_directories+=("$dir")
  done < <(jq -r '.managed_directories[]' "$state")

  GIT_STATE="$state"
  OLD_STATE=true
  TARGET_PATHS=()
  while IFS= read -r relative; do TARGET_PATHS+=("$relative"); done < <(jq -r '.targets[].path' "$state")
  begin_transaction
  for ((index=0; index<count; index++)); do
    relative="$(jq -r ".targets[$index].path" "$state")"
    rm -- "$HOME/$relative"
  done
  fault remove-after-links
  write_without_managed_block "$HOME/.gitconfig" "$HOME/.gitconfig"
  fault remove-after-global
  rm -- "$state"
  prune_managed_directories "${managed_directories[@]}"
  TRANSACTION_ACTIVE=false
  log 'removed managed Git links and global include block; retained identity, local settings, and migration ledger'
}

main() {
  parse_cli "$@"
  ((EUID != 0)) || die 'run bootstrap as the non-root workstation user'
  [[ -n "${HOME:-}" && -d "$HOME" ]] || die 'HOME must refer to an existing directory'
  HOST_ROOT=""
  validate_test_environment

  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  readonly DOTFILES_DIR="$SCRIPT_DIR"
  CHECKOUT_ROOT="$(cd -- "$DOTFILES_DIR" && pwd -P)"
  TARGET_ROOT="$(cd -- "$HOME" && pwd -P)"
  HOST_ROOT="${HOST_ROOT:-}"
  [[ -n "$HOST_ROOT" ]] || HOST_ROOT=""

  validate_dependency_manifest

  if [[ "$MODE" == remove ]]; then
    check_manifest_dependencies remove all true || exit 1
    acquire_lock
    validate_all_state
    validate_migrations_ledger
    remove_git
    return
  fi
  validate_identity_inputs
  detect_host
  select_profile
  check_manifest_dependencies "$MODE" "$SELECTED_PROFILE" true || exit 1
  acquire_lock
  validate_all_state
  validate_migrations_ledger
  refuse_profile_mismatch
  preflight_git
  if [[ "$MODE" == check ]]; then
    log "Git preflight passed for profile '$SELECTED_PROFILE'; no changes made"
  else
    apply_git
  fi
}

main "$@"
