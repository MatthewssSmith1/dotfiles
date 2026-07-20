#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/host.sh"
source "$SCRIPT_DIR/lib/engine.sh"
source "$SCRIPT_DIR/lib/provisioning.sh"
source "$SCRIPT_DIR/lib/areas/git.sh"
source "$SCRIPT_DIR/lib/areas/bash.sh"
source "$SCRIPT_DIR/lib/areas/tmux.sh"
source "$SCRIPT_DIR/lib/areas/nvim.sh"
source "$SCRIPT_DIR/lib/areas/zsh.sh"
source "$SCRIPT_DIR/lib/areas/generic.sh"

MODE=apply
PROFILE_OVERRIDE=""
AREAS=()
PROVISION=false
EXPLICIT_AREA_SELECTION=false

usage() {
  printf 'usage: %s [apply|--check|--remove] [--provision] [--profile omarchy|generic|wsl] [--area <area> ...]\n' "$SCRIPT_NAME" >&2
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
  local operation_seen=false provision_seen=false profile_seen=false

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
      --provision)
        [[ "$provision_seen" == false ]] || usage
        PROVISION=true
        provision_seen=true
        ;;
      --profile)
        (($# >= 2)) || usage
        [[ "$profile_seen" == false ]] || usage
        PROFILE_OVERRIDE="$2"
        profile_seen=true
        shift
        ;;
      --profile=*)
        [[ "$profile_seen" == false ]] || usage
        PROFILE_OVERRIDE="${1#*=}"
        profile_seen=true
        ;;
      --area)
        (($# >= 2)) || usage
        EXPLICIT_AREA_SELECTION=true
        add_area "$2"
        shift
        ;;
      --area=*)
        EXPLICIT_AREA_SELECTION=true
        add_area "${1#*=}"
        ;;
      *) usage ;;
    esac
    shift
  done

  [[ "$MODE" != remove || "$PROVISION" == false ]] || die '--provision is invalid with --remove'

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

enforce_wsl_shell_rollout_sequence() {
  local bash_state="$HOME/.local/state/dotfiles/v1/bash.json"
  local zsh_state="$HOME/.local/state/dotfiles/v1/zsh.json"
  [[ "$MODE" == apply && "$SELECTED_PROFILE" == wsl ]] || return 0

  if array_contains bash "${AREAS[@]}" && [[ ! -f "$bash_state" ]]; then
    [[ "$EXPLICIT_AREA_SELECTION" == true ]] && ! array_contains zsh "${AREAS[@]}" ||
      die "first WSL Bash deployment must explicitly select --area bash without zsh"
  fi
  if array_contains zsh "${AREAS[@]}" && [[ ! -f "$zsh_state" ]]; then
    [[ -f "$bash_state" ]] || die "first WSL zsh deployment requires a completed earlier --area bash apply"
    [[ "$EXPLICIT_AREA_SELECTION" == true ]] && ! array_contains bash "${AREAS[@]}" ||
      die "first WSL zsh deployment must explicitly select --area zsh without bash after Bash smoke testing"
    if ! (
      set -Eeuo pipefail
      MODE=check
      PROVISION=false
      AREAS=(bash)
      preflight_bash
    ); then
      die 'existing Bash deployment is degraded; run ./bootstrap.sh --check --area bash, repair it, and complete Bash smoke testing before the first zsh apply'
    fi
  fi
}

validate_selected_areas() {
  local area
  for area in "${AREAS[@]}"; do
    [[ -n "${AREA_STATUS[$area]+x}" ]] || die "unknown area '$area'"
    if [[ "$MODE" != remove && "${AREA_STATUS[$area]}" == framework ]]; then
      if [[ "$PROVISION" == true && "$EXPLICIT_AREA_SELECTION" == true &&
        ${#AREAS[@]} -eq 1 && "${AREAS[0]}" == tmux ]]; then
        continue
      fi
      die "area '$area' is framework-only in this checkout; its payload deploys in a later stage"
    fi
  done
}

tmux_plugin_provisioning_requested() {
  [[ "$PROVISION" == true && "$EXPLICIT_AREA_SELECTION" == true &&
    ${#AREAS[@]} -eq 1 && "${AREAS[0]}" == tmux ]]
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
      bash) remove_bash ;;
      tmux) remove_tmux ;;
      nvim) remove_nvim ;;
      zsh) remove_zsh ;;
      *) remove_generic "$area" ;;
    esac
    return 0
  fi
  case "$area" in
    git) preflight_git ;;
    bash) preflight_bash ;;
    tmux) preflight_tmux ;;
    nvim) preflight_nvim ;;
    zsh) preflight_zsh ;;
    *) preflight_generic "$area" ;;
  esac
  if [[ "$MODE" == check ]]; then
    if [[ "$area" == nvim ]]; then check_nvim_restore_convergence; fi
    log "area '$area' preflight passed for profile '$SELECTED_PROFILE'; no changes made"
    return 0
  fi
  case "$area" in
    git) apply_git ;;
    bash) apply_bash ;;
    tmux) apply_tmux ;;
    nvim) apply_nvim ;;
    zsh) apply_zsh ;;
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
    if [[ "${AREA_DEPENDENCY_OK[$area]:-true}" != true || "${AREA_PREFLIGHT_OK[$area]:-true}" != true ]]; then
      overall=1
      continue
    fi
    # A subshell in a condition context silently loses errexit, so run it as a
    # plain command with errexit paused; run_area rearms strict mode itself.
    set +e
    ( run_area "$area" )
    status=$?
    set -e
    case "$status" in
      70)
        printf "[%s] error: rollback failed for area '%s'; stopping before further areas\n" \
          "$SCRIPT_NAME" "$area" >&2
        exit 70
        ;;
      130|143) exit "$status" ;;
    esac
    if ((status != 0)); then
      overall=1
    fi
  done
  ((overall == 0)) || exit 1
}

preflight_selected_areas() {
  local skip_area="${1:-}" only_area="${2:-}" area status overall=0
  [[ -n "$only_area" ]] || AREA_PREFLIGHT_OK=()
  for area in "${AREAS[@]}"; do
    [[ -z "$only_area" || "$area" == "$only_area" ]] || continue
    if [[ -n "$skip_area" && "$area" == "$skip_area" ]]; then
      AREA_PREFLIGHT_OK["$area"]=false
      continue
    fi
    if [[ "${AREA_DEPENDENCY_OK[$area]:-true}" != true ]]; then
      AREA_PREFLIGHT_OK["$area"]=false
      continue
    fi
    set +e
    (
      set -Eeuo pipefail
      trap cleanup EXIT
      case "$area" in
        git) preflight_git ;;
        bash) preflight_bash ;;
        tmux) preflight_tmux ;;
        nvim) preflight_nvim ;;
        zsh) preflight_zsh ;;
        *) preflight_generic "$area" ;;
      esac
    )
    status=$?
    set -e
    if ((status == 0)); then
      AREA_PREFLIGHT_OK["$area"]=true
    else
      case "$status" in 70|130|143) exit "$status" ;; esac
      AREA_PREFLIGHT_OK["$area"]=false
      overall=1
    fi
  done
  ((overall == 0))
}

main() {
  local dependency_status=0 provisioning_status=0 area_status=0 run_status=0 native_status=0 area
  local plugin_plan_status=0 plugin_status=0
  local deferred_runtime_areas=()
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
  check_manifest_dependencies "$MODE" "$SELECTED_PROFILE" true || dependency_status=1
  [[ "$DEPENDENCY_CRITICAL_MISSING" == false ]] || exit 1
  validate_provisioning_manifest
  detect_provisioning_platform
  acquire_lock
  validate_all_state
  validate_migrations_ledger
  refuse_profile_mismatch
  validate_provisioning_receipt
  enforce_wsl_shell_rollout_sequence
  check_omarchy_core_drift || native_status=1
  if ((native_status != 0)); then
    for area in "${AREAS[@]}"; do AREA_DEPENDENCY_OK["$area"]=false; done
  fi
  if tmux_plugin_provisioning_requested; then
    set +e
    tmux_preflight_plugin_provision_plan
    plugin_plan_status=$?
    set -e
    case "$plugin_plan_status" in 70|130|143) exit "$plugin_plan_status" ;; esac
    # Runtime selection needs the requested area identity, but this is not a
    # configuration-preflight success marker.
    if [[ "${AREA_DEPENDENCY_OK[tmux]:-false}" == true ]]; then
      AREA_PREFLIGHT_OK[tmux]=true
      select_provisioning_tools
      AREA_PREFLIGHT_OK[tmux]=false
    else
      PROVISION_TOOL_IDS=()
    fi
    if print_provisioning_plan; then provisioning_status=0; else provisioning_status=$?; fi
    case "$provisioning_status" in 70|130|143) exit "$provisioning_status" ;; esac
    ((provisioning_status == 0)) || plugin_plan_status=1
    provisioning_status=0
    if ((${#TMUX_PLUGIN_IDS[@]} > 0)); then
      print_tmux_plugin_provisioning_plan
    fi
    if [[ "${AREA_DEPENDENCY_OK[tmux]:-false}" != true ||
      "$PROVISION_DEPENDENCY_MISSING" == true || "$plugin_plan_status" != 0 ]]; then
      provisioning_status=1
    elif [[ "$MODE" == check ]]; then
      set +e
      run_provisioning true
      provisioning_status=$?
      set -e
      case "$provisioning_status" in 70|130|143) exit "$provisioning_status" ;; esac
      [[ "$TMUX_PLUGIN_PLAN_PENDING" == false ]] || {
        log 'pending locked provisioning: tmux plugins'
        provisioning_status=1
      }
    else
      set +e
      run_provisioning true
      provisioning_status=$?
      set -e
      case "$provisioning_status" in 70|130|143) exit "$provisioning_status" ;; esac
      if ((provisioning_status == 0)); then
        set +e
        tmux_apply_plugin_provisioning
        plugin_status=$?
        set -e
        case "$plugin_status" in 70|130|143) exit "$plugin_status" ;; esac
        ((plugin_status == 0)) || provisioning_status=1
      fi
    fi
    if ((provisioning_status == 0)); then
      preflight_selected_areas || area_status=1
    else
      area_status=1
    fi
  else
    if [[ "$PROVISION" == true ]]; then
      for area in "${AREAS[@]}"; do
        if jq -e --arg area "$area" 'any(.tools[]; .areas | index($area) != null)' "$PROVISIONING_MANIFEST" >/dev/null; then
          deferred_runtime_areas+=("$area")
        fi
      done
    fi
    if ((${#deferred_runtime_areas[@]} > 0)); then
      for area in "${deferred_runtime_areas[@]}"; do AREA_PREFLIGHT_OK["$area"]=false; done
      for area in "${AREAS[@]}"; do
        array_contains "$area" "${deferred_runtime_areas[@]}" && continue
        preflight_selected_areas '' "$area" || area_status=1
      done
    else
      preflight_selected_areas || area_status=1
    fi
    if [[ "$PROVISION" == true ]]; then
      if [[ "$PROVISION_DEPENDENCY_MISSING" == true ]]; then
        provisioning_status=1
      else
        for area in "${deferred_runtime_areas[@]:-}"; do
          [[ -n "$area" && "${AREA_DEPENDENCY_OK[$area]:-false}" == true ]] && AREA_PREFLIGHT_OK["$area"]=true
        done
        select_provisioning_tools
        for area in "${deferred_runtime_areas[@]:-}"; do [[ -z "$area" ]] || AREA_PREFLIGHT_OK["$area"]=false; done
        set +e
        run_provisioning
        provisioning_status=$?
        set -e
        case "$provisioning_status" in 70|130|143) exit "$provisioning_status" ;; esac
      fi
      if ((${#deferred_runtime_areas[@]} > 0)); then
        if ((provisioning_status == 0)); then
          for area in "${deferred_runtime_areas[@]}"; do preflight_selected_areas '' "$area" || area_status=1; done
        else
          for area in "${deferred_runtime_areas[@]}"; do AREA_PREFLIGHT_OK["$area"]=false; done
          area_status=1
        fi
      fi
    fi
  fi
  set +e
  ( run_selected_areas )
  run_status=$?
  set -e
  case "$run_status" in 70|130|143) exit "$run_status" ;; esac
  ((run_status == 0)) || area_status=1
  ((dependency_status == 0 && provisioning_status == 0 && native_status == 0 && area_status == 0)) || exit 1
}

main "$@"
