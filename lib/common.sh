# Shared helpers and process lifecycle; sourced by bootstrap.sh exactly once.

TEMP_PATHS=()
TEMP_OBJECT_IDENTITIES=()
TEMP_RECURSIVE=()
RETAINED_TEMP_PATHS=()
TRANSACTION_ACTIVE=false
TRANSACTION_ROLLING_BACK=false
ROLLBACK_FAILED=false
TRANSACTION_RECOVERY_REQUIRED=false
JOURNAL_DIR=""

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
  if declare -F cleanup_retained_provisioning_transaction >/dev/null; then
    cleanup_retained_provisioning_transaction || ROLLBACK_FAILED=true
  fi
  if declare -F cleanup_before_temp_paths >/dev/null; then
    cleanup_before_temp_paths || true
  fi
  for path in "${TEMP_PATHS[@]}"; do
    if array_contains "$path" "${RETAINED_TEMP_PATHS[@]:-}"; then
      continue
    fi
    [[ "$ROLLBACK_FAILED" != true || "$path" != "$JOURNAL_DIR" ]] || continue
    if declare -p TX_RECOVERY_PATHS >/dev/null 2>&1 && \
      array_contains "$path" "${TX_RECOVERY_PATHS[@]:-}"; then
      continue
    fi
    if [[ "$ROLLBACK_FAILED" == true ]] && declare -p TX_QUARANTINE_PATHS >/dev/null 2>&1 && \
      array_contains "$path" "${TX_QUARANTINE_PATHS[@]:-}"; then
      continue
    fi
    discard_tracked_temp_path "$path" cleanup || true
  done
  # Reserved status 70 tells the caller to stop all further area mutation.
  if [[ "$ROLLBACK_FAILED" == true ]]; then
    exit 70
  fi
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
    printf '[%s] warning: refusing untracked %s path deletion: %s\n' "$SCRIPT_NAME" "$context" "$path" >&2
    return 1
  fi
  index="$TRACKED_TEMP_PATH_INDEX"
  expected="${TEMP_OBJECT_IDENTITIES[index]}"
  recursive="${TEMP_RECURSIVE[index]}"
  capture_path_object_identity "$path" || {
    printf '[%s] warning: could not inspect %s path; leaving it in place: %s\n' "$SCRIPT_NAME" "$context" "$path" >&2
    return 1
  }
  [[ "$PATH_OBJECT_IDENTITY" != absent ]] || return 0
  if [[ "$PATH_OBJECT_IDENTITY" != "$expected" ]]; then
    printf '[%s] warning: %s path was replaced; leaving it in place: %s\n' "$SCRIPT_NAME" "$context" "$path" >&2
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
  if [[ -n "${DOTFILES_TEST_FAIL_AT:-}" && "${DOTFILES_TESTING:-}" != 1 ]]; then
    die 'DOTFILES_TEST_FAIL_AT requires DOTFILES_TESTING=1'
  fi
  if [[ -n "${DOTFILES_TEST_SIGNAL_AT:-}" && "${DOTFILES_TESTING:-}" != 1 ]]; then
    die 'DOTFILES_TEST_SIGNAL_AT requires DOTFILES_TESTING=1'
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
  elif [[ -n "${DOTFILES_TEST_HOST_ROOT:-}${DOTFILES_TEST_UNAME:-}${DOTFILES_TEST_ARCH:-}" ]]; then
    die 'test host overrides require DOTFILES_TESTING=1'
  fi
}

fault() {
  local point="$1"
  if [[ "${DOTFILES_TESTING:-}" == 1 && "${DOTFILES_TEST_FAIL_AT:-}" == "$point" ]]; then
    die "injected test failure at $point"
  fi
}

test_signal() {
  local point="$1"
  [[ "${DOTFILES_TESTING:-}" == 1 && "${DOTFILES_TEST_SIGNAL_AT:-}" == "$point" ]] || return 0
  kill -TERM "$$"
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
