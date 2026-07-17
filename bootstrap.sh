#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/host.sh"
source "$SCRIPT_DIR/lib/engine.sh"
source "$SCRIPT_DIR/lib/areas/git.sh"

MODE=apply
PROFILE_OVERRIDE=""
AREAS=()

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

main() {
  local area

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

  validate_dependency_manifest

  if [[ "$MODE" == remove ]]; then
    check_manifest_dependencies remove all true || exit 1
    acquire_lock
    validate_all_state
    validate_migrations_ledger
    for area in "${AREAS[@]}"; do "remove_$area"; done
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
  for area in "${AREAS[@]}"; do "preflight_$area"; done
  if [[ "$MODE" == check ]]; then
    log "Git preflight passed for profile '$SELECTED_PROFILE'; no changes made"
  else
    for area in "${AREAS[@]}"; do "apply_$area"; done
  fi
}

main "$@"
