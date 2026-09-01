#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/host.sh"
source "$SCRIPT_DIR/lib/lean_engine.sh"
source "$SCRIPT_DIR/lib/areas/git.sh"
source "$SCRIPT_DIR/lib/areas/tools.sh"
source "$SCRIPT_DIR/lib/areas/bash.sh"
source "$SCRIPT_DIR/lib/areas/tmux.sh"
source "$SCRIPT_DIR/lib/areas/nvim.sh"
source "$SCRIPT_DIR/lib/areas/agents.sh"
source "$SCRIPT_DIR/lib/areas/herdr.sh"
source "$SCRIPT_DIR/lib/areas/desktop.sh"
source "$SCRIPT_DIR/lib/areas/opencode.sh"

MODE=""
PROFILE_OVERRIDE=""
AREAS=()

usage() {
  printf 'usage: %s {apply|check|remove|list|help} ...\n' "$SCRIPT_NAME" >&2
  exit 1
}

help_text() {
  cat <<EOF
usage:
  $SCRIPT_NAME apply [--profile omarchy|ubuntu] [area ...]
  $SCRIPT_NAME check [--profile omarchy|ubuntu] [area ...]
  $SCRIPT_NAME remove [area ...]
  $SCRIPT_NAME list
  $SCRIPT_NAME help [command]
  $SCRIPT_NAME --help
EOF
}

command_help() {
  case "$1" in
    apply|check)
      printf 'usage: %s %s [--profile omarchy|ubuntu] [area ...]\n' "$SCRIPT_NAME" "$1"
      ;;
    remove) printf 'usage: %s remove [area ...]\n' "$SCRIPT_NAME" ;;
    list) printf 'usage: %s list\n' "$SCRIPT_NAME" ;;
    help) printf 'usage: %s help [command]\n' "$SCRIPT_NAME" ;;
    *) usage ;;
  esac
}

add_area() {
  local area="$1" existing

  [[ "$area" =~ ^[a-z0-9-]+$ ]] || die "invalid area name '$area'"
  for existing in "${AREAS[@]}"; do
    [[ "$existing" != "$area" ]] || return 0
  done
  AREAS+=("$area")
}

parse_cli() {
  local profile_seen=false area_seen=false

  (($# > 0)) || { help_text >&2; exit 1; }
  case "$1" in
    --help)
      (($# == 1)) || usage
      help_text
      exit 0
      ;;
    help)
      (($# <= 2)) || usage
      if (($# == 1)); then help_text; else command_help "$2"; fi
      exit 0
      ;;
    apply|check|remove|list) MODE="$1"; shift ;;
    *) usage ;;
  esac

  if [[ "$MODE" == list ]]; then
    (($# == 0)) || usage
    return 0
  fi

  while (($# > 0)); do
    case "$1" in
      --profile)
        [[ "$MODE" != remove ]] || die '--profile is invalid with remove'
        (($# >= 2)) && [[ "$profile_seen" == false && "$area_seen" == false ]] || usage
        PROFILE_OVERRIDE="$2"
        profile_seen=true
        shift 2
        continue
        ;;
      -*) usage ;;
      *)
        area_seen=true
        add_area "$1"
        ;;
    esac
    shift
  done

  if [[ -n "$PROFILE_OVERRIDE" ]]; then
    case "$PROFILE_OVERRIDE" in
      omarchy|ubuntu) ;;
      *) die "invalid profile '$PROFILE_OVERRIDE'; expected omarchy or ubuntu" ;;
    esac
  fi
}

select_default_areas() {
  local area
  ((${#AREAS[@]} == 0)) || return 0
  for area in "${AREA_ORDER[@]}"; do
    if [[ "${AREA_STATUS[$area]}" == ready ]]; then
      AREAS+=("$area")
    fi
  done
  ((${#AREAS[@]} > 0)) || die 'no ready areas are defined in manifests/areas.tsv'
}

# Area membership derives from manifests/areas.tsv (loaded by
# validate_area_manifest before any lifecycle work).
lean_area() {
  [[ -n "${AREA_STATUS[$1]+x}" ]]
}

prepare_selected_lean_state() {
  local area found=false
  LEAN_PROFILE="$SELECTED_PROFILE"
  for area in "${AREAS[@]}"; do
    lean_area "$area" || continue
    found=true
    LEAN_AREA="$area"
    lean_refuse_v1_state
  done
  [[ "$found" == false ]] || lean_validate_all_state
}

# Package-only ownership is derived from the active profile. Attachment owners
# are selected only from v2 state; v1 is never interpreted as lean ownership.
select_lean_remove_areas() {
  local explicit_area_count="$1" file base area
  if ((explicit_area_count == 0)); then
    add_area tools
    add_area tmux
    add_area agents
    [[ "$SELECTED_PROFILE" != ubuntu ]] || add_area nvim
    add_area herdr
    add_area opencode
    shopt -s nullglob
    for file in "$(lean_state_dir)"/*.json; do
      base="${file##*/}"
      area="${base%.json}"
      lean_area "$area" || die "v2 state records an unconverted area: $area"
      add_area "$area"
    done
    shopt -u nullglob
  fi
}

list_configuration() {
  local area detected=""

  readonly DOTFILES_DIR="$SCRIPT_DIR"
  validate_area_manifest
  printf 'profiles:\n  omarchy\n  ubuntu\nareas:\n'
  for area in "${AREA_ORDER[@]}"; do
    printf '  %s %s\n' "$area" "${AREA_STATUS[$area]}"
  done

  HOST_ROOT=""
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_HOST_ROOT:-}" ]]; then
    HOST_ROOT="${DOTFILES_TEST_HOST_ROOT%/}"
  fi
  detected="$(detect_host 2>/dev/null && printf '%s' "$DETECTED_PROFILE")" || detected=""
  [[ -z "$detected" ]] || printf 'selected-profile: %s\n' "$detected"
}

validate_selected_areas() {
  local area
  for area in "${AREAS[@]}"; do
    [[ -n "${AREA_STATUS[$area]+x}" ]] || die "unknown area '$area'"
  done
}

area_entrypoint() {
  local verb="$1" area="$2"
  lean_area "$area" && declare -F "${verb}_${area}" >/dev/null ||
    die "area '$area' has no lean implementation"
  "${verb}_${area}"
}

run_area() {
  local area="$1"
  # This function runs in a per-area subshell started with errexit paused;
  # rearm strict mode and the traps the subshell reset.
  set -Eeuo pipefail
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ "$MODE" == remove ]]; then
    area_entrypoint remove "$area"
    return 0
  fi
  area_entrypoint preflight "$area"
  if [[ "$MODE" == check ]]; then
    log "area '$area' preflight passed for profile '$SELECTED_PROFILE'; no changes made"
    return 0
  fi
  area_entrypoint apply "$area"
}

run_selected_areas() {
  local area status
  for area in "${AREAS[@]}"; do
    if [[ "${AREA_DEPENDENCY_OK[$area]:-true}" != true || "${AREA_PREFLIGHT_OK[$area]:-true}" != true ]]; then
      return 1
    fi
    # A subshell in a condition context silently loses errexit, so run it as a
    # plain command with errexit paused; run_area rearms strict mode itself.
    set +e
    ( run_area "$area" )
    status=$?
    set -e
    case "$status" in 130|143) exit "$status" ;; esac
    if ((status != 0)); then
      return "$status"
    fi
  done
}

preflight_selected_areas() {
  local skip_area="${1:-}" only_area="${2:-}" area status
  [[ -n "$only_area" ]] || AREA_PREFLIGHT_OK=()
  for area in "${AREAS[@]}"; do
    [[ -z "$only_area" || "$area" == "$only_area" ]] || continue
    if [[ -n "$skip_area" && "$area" == "$skip_area" ]]; then
      AREA_PREFLIGHT_OK["$area"]=false
      return 1
    fi
    if [[ "${AREA_DEPENDENCY_OK[$area]:-true}" != true ]]; then
      AREA_PREFLIGHT_OK["$area"]=false
      return 1
    fi
    set +e
    (
      set -Eeuo pipefail
      trap cleanup EXIT
      area_entrypoint preflight "$area"
    )
    status=$?
    set -e
    if ((status == 0)); then
      AREA_PREFLIGHT_OK["$area"]=true
    else
      case "$status" in 130|143) exit "$status" ;; esac
      AREA_PREFLIGHT_OK["$area"]=false
      return 1
    fi
  done
}

main() {
  local dependency_status=0 area_status=0 run_status=0 native_status=0 area
  local explicit_area_count
  parse_cli "$@"
  if [[ "$MODE" == list ]]; then
    list_configuration
    return
  fi
  explicit_area_count="${#AREAS[@]}"
  ((EUID != 0)) || die 'run dotfiles as the non-root workstation user'
  [[ -n "${HOME:-}" && -d "$HOME" ]] || die 'HOME must refer to an existing directory'
  HOST_ROOT=""
  validate_test_environment

  readonly DOTFILES_DIR="$SCRIPT_DIR"
  TARGET_ROOT="$(cd -- "$HOME" && pwd -P)"
  HOST_ROOT="${HOST_ROOT:-}"
  [[ -n "$HOST_ROOT" ]] || HOST_ROOT=""

  validate_area_manifest
  validate_dependency_manifest

  if [[ "$MODE" == remove ]]; then
    detect_host
    select_profile
    select_lean_remove_areas "$explicit_area_count"
    if ((${#AREAS[@]} == 0)); then
      log 'no deployed areas are recorded; no changes made'
      return
    fi
    validate_selected_areas
    check_manifest_dependencies remove "$SELECTED_PROFILE" true || exit 1
    lean_acquire_lock
    prepare_selected_lean_state
    preflight_selected_areas || return 1
    run_selected_areas
    return
  fi
  select_default_areas
  validate_selected_areas
  detect_host
  select_profile
  check_manifest_dependencies "$MODE" "$SELECTED_PROFILE" true || dependency_status=1
  [[ "$DEPENDENCY_CRITICAL_MISSING" == false ]] || exit 1
  lean_acquire_lock
  prepare_selected_lean_state
  check_omarchy_core_drift || native_status=1
  if ((native_status != 0)); then
    for area in "${AREAS[@]}"; do AREA_DEPENDENCY_OK["$area"]=false; done
  fi
  if preflight_selected_areas; then
    set +e
    ( run_selected_areas )
    run_status=$?
    set -e
    case "$run_status" in 130|143) exit "$run_status" ;; esac
    ((run_status == 0)) || area_status=1
  else
    area_status=1
  fi
  ((dependency_status == 0 && native_status == 0 && area_status == 0)) || exit 1
}

main "$@"
