#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/host.sh"
source "$SCRIPT_DIR/lib/engine.sh"
source "$SCRIPT_DIR/lib/areas/git.sh"
source "$SCRIPT_DIR/lib/areas/generic.sh"

MODE=apply
PROFILE_OVERRIDE=""
AREAS=()

usage() {
  printf 'usage: %s [apply|--check|--remove] [--profile omarchy|generic|wsl] [--area <area> ...]\n' "$SCRIPT_NAME" >&2
  exit 1
}

add_area() {
  local area="$1"
  local existing

  [[ "$area" =~ ^[a-z0-9-]+$ ]] || die "invalid area name '$area'"
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

select_recorded_areas() {
  local file base
  local state_dir="$HOME/.local/state/dotfiles/v1"
  ((${#AREAS[@]} == 0)) || return 0
  [[ -d "$state_dir" ]] || return 0
  shopt -s nullglob
  for file in "$state_dir"/*.json; do
    base="${file##*/}"
    if [[ "$base" != migrations.json ]]; then
      add_area "${base%.json}"
    fi
  done
  shopt -u nullglob
}

validate_selected_areas() {
  local area
  for area in "${AREAS[@]}"; do
    [[ -n "${AREA_STATUS[$area]+x}" ]] || die "unknown area '$area'"
    if [[ "$MODE" != remove && "${AREA_STATUS[$area]}" == framework ]]; then
      die "area '$area' is framework-only in this checkout; its payload deploys in a later stage"
    fi
  done
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
    case "$area" in
      git) remove_git ;;
      *) remove_generic "$area" ;;
    esac
    return 0
  fi
  case "$area" in
    git) preflight_git ;;
    *) preflight_generic "$area" ;;
  esac
  if [[ "$MODE" == check ]]; then
    log "area '$area' preflight passed for profile '$SELECTED_PROFILE'; no changes made"
    return 0
  fi
  case "$area" in
    git) apply_git ;;
    *) apply_generic "$area" ;;
  esac
}

# Collect the selected areas' recorded managed directories before removal so
# directories a first-removed area could not prune (still busy with a later
# area's state or links) are re-pruned once every selected area is removed.
collect_selected_managed_dirs() {
  local area file dir
  REMOVE_PRUNE_DIRS=()
  for area in "${AREAS[@]}"; do
    file="$HOME/.local/state/dotfiles/v1/$area.json"
    [[ -f "$file" ]] || continue
    while IFS= read -r dir; do
      validate_home_directory "$HOME/$dir"
      REMOVE_PRUNE_DIRS+=("$dir")
    done < <(jq -r '.managed_directories[]' "$file")
  done
  return 0
}

# Once no recorded state or retained ledger remains, the deployment's own state
# directory chain is empty scaffolding; prune it bottom-up while empty.
prune_state_chain_if_unrecorded() {
  local state_dir="$HOME/.local/state/dotfiles/v1"
  local remaining=""
  if [[ -d "$state_dir" ]]; then
    remaining="$(find "$state_dir" -mindepth 1 -print -quit)"
  fi
  [[ -z "$remaining" ]] || return 0
  prune_managed_directories '.local/state/dotfiles/v1' '.local/state/dotfiles' '.local/state' '.local'
}

run_selected_areas() {
  local area status overall=0
  for area in "${AREAS[@]}"; do
    # A subshell in a condition context silently loses errexit, so run it as a
    # plain command with errexit paused; run_area rearms strict mode itself.
    set +e
    ( run_area "$area" )
    status=$?
    set -e
    if ((status == 70)); then
      printf "[%s] error: rollback failed for area '%s'; stopping before further areas\n" \
        "$SCRIPT_NAME" "$area" >&2
      exit 70
    fi
    if ((status != 0)); then
      overall=1
    fi
  done
  ((overall == 0)) || exit 1
}

main() {
  parse_cli "$@"
  ((EUID != 0)) || die 'run bootstrap as the non-root workstation user'
  [[ -n "${HOME:-}" && -d "$HOME" ]] || die 'HOME must refer to an existing directory'
  HOST_ROOT=""
  validate_test_environment

  readonly DOTFILES_DIR="$SCRIPT_DIR"
  CHECKOUT_ROOT="$(cd -- "$DOTFILES_DIR" && pwd -P)"
  TARGET_ROOT="$(cd -- "$HOME" && pwd -P)"
  HOST_ROOT="${HOST_ROOT:-}"
  [[ -n "$HOST_ROOT" ]] || HOST_ROOT=""

  validate_area_manifest
  validate_dependency_manifest

  if [[ "$MODE" == remove ]]; then
    select_recorded_areas
    if ((${#AREAS[@]} == 0)); then
      log 'no deployed areas are recorded; no changes made'
      return
    fi
    validate_selected_areas
    check_manifest_dependencies remove all true || exit 1
    acquire_lock
    validate_all_state
    validate_migrations_ledger
    collect_selected_managed_dirs
    run_selected_areas
    prune_managed_directories "${REMOVE_PRUNE_DIRS[@]}"
    prune_state_chain_if_unrecorded
    return
  fi
  select_default_areas
  validate_selected_areas
  detect_host
  select_profile
  check_manifest_dependencies "$MODE" "$SELECTED_PROFILE" true || exit 1
  acquire_lock
  validate_all_state
  validate_migrations_ledger
  refuse_profile_mismatch
  run_selected_areas
}

main "$@"
