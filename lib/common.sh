# Shared helpers and process lifecycle; sourced by dotfiles.sh exactly once.

TEMP_PATHS=()
TEMP_OBJECT_IDENTITIES=()
TEMP_RECURSIVE=()
RETAINED_TEMP_PATHS=()

# Test the destination at emission time: callers may redirect either stream.
log_color_enabled() {
  [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]
}

# Quoted area/profile identifiers are emphasized within the current foreground.
log_styled_text() {
  local text="$1" style="${2:-}" quoted="^([^']*)('[^']+')"
  printf '%s' "$style"
  while [[ "$text" =~ $quoted ]]; do
    printf '%s\033[1m%s\033[0m%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$style"
    text="${text:${#BASH_REMATCH[0]}}"
  done
  printf '%s\033[0m' "$text"
}

log_message() {
  local level="$1" message="$2" label="" style="" phrase rest=""
  local reset=$'\033[0m' bold=$'\033[1m' dim=$'\033[2m'
  case "$level" in
    info) style=$'\033[36m' ;;
    success) style=$'\033[32m' ;;
    warning) style=$'\033[33m'; label='warning: ' ;;
    error) style=$'\033[1;31m'; label='error: ' ;;
    neutral) style="" ;;
  esac
  if ! log_color_enabled; then
    printf '[%s] %s%s\n' "$SCRIPT_NAME" "$label" "$message"
    return
  fi
  printf '%s[%s]%s ' "$dim" "$SCRIPT_NAME" "$reset"
  if [[ -n "$label" ]]; then
    printf '%s%s%s' "$style" "$label" "$reset"
  else
    # Color the status clause; explanations retain the default foreground.
    phrase="${message%%;*}"
    [[ "$message" != *';'* ]] || rest=";${message#*;}"
    log_styled_text "$phrase" "$style"
    message="$rest"
  fi
  # Installation guidance stays readable and copyable, with only the command bold.
  if [[ "$message" == *'with: '* ]]; then
    log_styled_text "${message%%with: *}with: "
    printf '%s%s%s\n' "$bold" "${message#*with: }" "$reset"
  else
    log_styled_text "$message"
    printf '\n'
  fi
}

log() { log_message info "$*"; }
log_success() { log_message success "$*"; }
log_neutral() { log_message neutral "$*"; }
log_warning() { log_message warning "$*" >&2; }
log_error() { log_message error "$*" >&2; }

log_command() {
  if log_color_enabled; then
    printf '\033[1m%s\033[0m\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

die() {
  log_error "$*"
  exit 1
}

cleanup() {
  local status=$?
  local path

  if declare -F cleanup_before_temp_paths >/dev/null; then
    cleanup_before_temp_paths || true
  fi
  for path in "${TEMP_PATHS[@]}"; do
    if array_contains "$path" "${RETAINED_TEMP_PATHS[@]:-}"; then
      continue
    fi
    discard_tracked_temp_path "$path" cleanup || true
  done
  exit "$status"
}

retain_tracked_temp_path() {
  local path="$1"
  tracked_temp_path_index "$path" || die "cannot retain untracked temporary path: $path"
  array_contains "$path" "${RETAINED_TEMP_PATHS[@]:-}" || RETAINED_TEMP_PATHS+=("$path")
}

tracked_temp_path_index() {
  local path="$1" index
  TRACKED_TEMP_PATH_INDEX=""
  for index in "${!TEMP_PATHS[@]}"; do
    if [[ "${TEMP_PATHS[index]}" == "$path" ]]; then
      TRACKED_TEMP_PATH_INDEX="$index"
      return 0
    fi
  done
  return 1
}

# Canonical EUID-ownership test for paths dotfiles is about to trust.
path_owned_by_euid() {
  [[ "$(stat -c %u -- "$1")" == "$EUID" ]]
}

track_temp_path() {
  local path="$1" index recursive=false
  capture_path_object_identity "$path" || die "could not track temporary path: $path"
  [[ "$PATH_OBJECT_IDENTITY" != absent ]] || die "cannot track absent temporary path: $path"
  [[ ! -d "$path" || -L "$path" ]] || recursive=true
  if tracked_temp_path_index "$path"; then
    index="$TRACKED_TEMP_PATH_INDEX"
    TEMP_OBJECT_IDENTITIES[index]="$PATH_OBJECT_IDENTITY"
    TEMP_RECURSIVE[index]="$recursive"
  else
    TEMP_PATHS+=("$path")
    TEMP_OBJECT_IDENTITIES+=("$PATH_OBJECT_IDENTITY")
    TEMP_RECURSIVE+=("$recursive")
  fi
}

discard_tracked_temp_path() {
  local path="$1" context="${2:-temporary cleanup}" index expected recursive
  if ! tracked_temp_path_index "$path"; then
    log_warning "refusing untracked $context path deletion: $path"
    return 1
  fi
  index="$TRACKED_TEMP_PATH_INDEX"
  expected="${TEMP_OBJECT_IDENTITIES[index]}"
  recursive="${TEMP_RECURSIVE[index]}"
  capture_path_object_identity "$path" || {
    log_warning "could not inspect $context path; leaving it in place: $path"
    return 1
  }
  [[ "$PATH_OBJECT_IDENTITY" != absent ]] || return 0
  if [[ "$PATH_OBJECT_IDENTITY" != "$expected" ]]; then
    log_warning "$context path was replaced; leaving it in place: $path"
    return 1
  fi
  if [[ "$recursive" == true ]]; then
    rm -rf -- "$path" || return 1
  else
    rm -- "$path" || return 1
  fi
  capture_path_object_identity "$path" && [[ "$PATH_OBJECT_IDENTITY" == absent ]]
}

capture_path_object_identity() {
  local path="$1" value type
  PATH_OBJECT_IDENTITY=""
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    PATH_OBJECT_IDENTITY=absent
    return 0
  fi
  if [[ -L "$path" ]]; then
    type=symlink
  elif [[ -f "$path" ]]; then
    type=regular
  elif [[ -d "$path" ]]; then
    type=directory
  else
    type="other:$(stat -c %F -- "$path")" || return 1
  fi
  value="$type|$(stat -c '%d|%i|%u' -- "$path")" || return 1
  PATH_OBJECT_IDENTITY="$(sha256_string "$value")"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

validate_test_environment() {
  if [[ -n "${DOTFILES_TEST_HOLD_AT:-}${DOTFILES_TEST_HOLD_DIR:-}" && "${DOTFILES_TESTING:-}" != 1 ]]; then
    die 'DOTFILES_TEST_HOLD_* requires DOTFILES_TESTING=1'
  fi
  if [[ -n "${DOTFILES_TEST_HIDE_COMMANDS:-}" && "${DOTFILES_TESTING:-}" != 1 ]]; then
    die 'DOTFILES_TEST_HIDE_COMMANDS requires DOTFILES_TESTING=1'
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
  elif [[ -n "${DOTFILES_TEST_HOST_ROOT:-}${DOTFILES_TEST_UNAME:-}${DOTFILES_TEST_ARCH:-}" ]]; then
    die 'test host overrides require DOTFILES_TESTING=1'
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

sha256_file() {
  sha256sum -- "$1" | while read -r hash _; do printf '%s' "$hash"; done
}

sha256_string() {
  printf '%s' "$1" | sha256sum | while read -r hash _; do printf '%s' "$hash"; done
}

file_contains_nul() {
  ! cmp -s -- "$1" <(LC_ALL=C tr -d '\000' < "$1")
}

csv_contains() {
  local csv="$1" expected="$2" entry
  local entries=()
  IFS=',' read -r -a entries <<< "$csv"
  for entry in "${entries[@]}"; do [[ "$entry" != "$expected" ]] || return 0; done
  return 1
}

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do [[ "$item" != "$needle" ]] || return 0; done
  return 1
}
