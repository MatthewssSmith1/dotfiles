# Bash area: managed payload, reversible startup attachments, and ownership checks.

readonly BASH_RC_BEGIN='# >>> dotfiles managed bash rc >>>'
readonly BASH_RC_END='# <<< dotfiles managed bash rc <<<'
readonly BASH_RC_TOKEN='dotfiles managed bash rc'
readonly BASH_RC_BLOCK="$BASH_RC_BEGIN
case \$- in
  *i*) ;;
  *) return 0 ;;
esac
. \"\$HOME/.config/dotfiles/bash/rc.bash\"
return 0
$BASH_RC_END"

readonly BASH_LOGIN_BEGIN='# >>> dotfiles managed bash login >>>'
readonly BASH_LOGIN_END='# <<< dotfiles managed bash login <<<'
readonly BASH_LOGIN_TOKEN='dotfiles managed bash login'
readonly BASH_LOGIN_BLOCK="$BASH_LOGIN_BEGIN
if [ -n \"\${BASH_VERSION-}\" ]; then
  if [ -r \"\$HOME/.bashrc\" ]; then . \"\$HOME/.bashrc\"; fi
  return 0
fi
$BASH_LOGIN_END"

readonly BASH_NATIVE_BEGIN='# >>> dotfiles managed bash common >>>'
readonly BASH_NATIVE_END='# <<< dotfiles managed bash common <<<'
readonly BASH_NATIVE_TOKEN='dotfiles managed bash common'
readonly BASH_NATIVE_BLOCK="$BASH_NATIVE_BEGIN
. \"\$HOME/.config/dotfiles/bash/rc.bash\"
$BASH_NATIVE_END"
readonly BASH_SANDBOX_UNSHARE=/usr/bin/unshare
readonly BASH_SANDBOX_MOUNT=/usr/bin/mount
readonly BASH_SANDBOX_SETPRIV=/usr/bin/setpriv

init_bash_area() {
  AREA=bash
  AREA_JOURNAL_PATHS=()
  AREA_ATTACHMENT_VALIDATOR=validate_bash_attachments_from_state
  BASH_RC_ORIGIN=""
  BASH_LOGIN_ORIGIN=""
  BASH_LOGIN_PATH=""
  BASH_RC_ACTION=none
  BASH_LOGIN_ACTION=none
}

bash_expected_targets() {
  BASH_EXPECTED_TARGETS=(
    .config/dotfiles/bash/integrations.bash
    .config/dotfiles/bash/personal.bash
    .config/dotfiles/bash/rc.bash
    .config/mise/conf.d/20-dotfiles-common.toml
  )
  if [[ "$SELECTED_PROFILE" != omarchy ]]; then
    BASH_EXPECTED_TARGETS+=(
      .config/dotfiles/bash/env.bash
      .config/dotfiles/bash/generic.bash
      .config/dotfiles/bash/init.bash
      .config/dotfiles/upstream/bash/aliases
      .config/dotfiles/upstream/bash/fns/tmux
      .config/dotfiles/upstream/bash/inputrc
      .config/dotfiles/upstream/bash/shell
      .config/mise/conf.d/30-dotfiles-profile.toml
      .config/starship.toml
      .local/share/dotfiles/bin/bat
      .local/share/dotfiles/bin/fd
    )
  fi
  [[ "$SELECTED_PROFILE" != wsl ]] || BASH_EXPECTED_TARGETS+=(.config/dotfiles/bash/wsl.bash)
}

validate_bash_target_inventory() {
  local relative expected actual
  local -A expected_map=() actual_map=()

  bash_expected_targets
  for relative in "${BASH_EXPECTED_TARGETS[@]}"; do
    [[ -z "${expected_map[$relative]+x}" ]] || die "duplicate expected Bash target: $relative"
    expected_map["$relative"]=1
  done
  for relative in "${TARGET_PATHS[@]}"; do actual_map["$relative"]=1; done
  for expected in "${BASH_EXPECTED_TARGETS[@]}"; do
    [[ -n "${actual_map[$expected]+x}" ]] || die "Bash package closure is missing expected target: $expected"
  done
  for actual in "${TARGET_PATHS[@]}"; do
    [[ -n "${expected_map[$actual]+x}" ]] || die "Bash package closure contains unexpected target: $actual"
  done
  ((${#TARGET_PATHS[@]} == ${#BASH_EXPECTED_TARGETS[@]})) || die 'Bash package target inventory is not unique'
}

validate_bash_payload_modes_and_syntax() {
  local index relative source expected_mode mode
  for index in "${!TARGET_PATHS[@]}"; do
    relative="${TARGET_PATHS[index]}"
    source="${TARGET_SOURCES[index]}"
    expected_mode=644
    case "$relative" in
      .local/share/dotfiles/bin/bat|.local/share/dotfiles/bin/fd) expected_mode=755 ;;
    esac
    mode="$(stat -c %a -- "$source")"
    [[ "$mode" == "$expected_mode" ]] || die "unexpected Bash payload mode $mode for $relative; expected $expected_mode"
    case "$relative" in
      *.bash|.local/share/dotfiles/bin/*) bash -n "$source" || die "managed Bash payload has invalid syntax: $relative" ;;
    esac
  done
  if [[ "$SELECTED_PROFILE" != omarchy ]]; then
    "$DOTFILES_DIR/scripts/upstream" verify >/dev/null || die 'pinned upstream Bash snapshot verification failed'
  fi
}

validate_bash_local_layer() {
  local path="$HOME/.config/dotfiles/local/bash.sh"
  validate_home_parent_chain "$path"
  [[ ! -e "$path" && ! -L "$path" ]] && return 0
  [[ -f "$path" && ! -L "$path" ]] || die "host-local Bash layer is symlinked or not a regular file: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "host-local Bash layer has an unsafe owner: $path"
  [[ -r "$path" ]] || die "host-local Bash layer is not readable: $path"
  file_contains_nul "$path" && die "host-local Bash layer contains NUL bytes and cannot be sourced safely: $path"
  bash -n "$path" || die "host-local Bash layer has invalid Bash syntax: $path"
}

validate_bash_isolation_capability() {
  local tool sandbox source target setup dropped status=0
  for tool in "$BASH_SANDBOX_UNSHARE" "$BASH_SANDBOX_MOUNT" "$BASH_SANDBOX_SETPRIV"; do
    [[ -x "$tool" && ! -L "$tool" ]] || \
      die "required Bash isolation tool is unavailable at $tool; install util-linux from the profile package manager"
  done

  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bash-isolation.XXXXXX")"
  source="$sandbox/source"
  target="$sandbox/target"
  setup="$sandbox/setup.bash"
  dropped="$sandbox/dropped.bash"
  track_temp_path "$sandbox"
  mkdir -- "$source" "$target"
  printf '%s\n' \
    'set -Eeuo pipefail' \
    'if : 2>/dev/null > "$PROBE_TARGET/write"; then exit 91; fi' \
    'if "$PROBE_MOUNT" -o remount,bind,rw "$PROBE_TARGET" >/dev/null 2>&1; then exit 92; fi' \
    > "$dropped"
  printf '%s\n' \
    'set -Eeuo pipefail' \
    '"$PROBE_MOUNT" --bind "$PROBE_SOURCE" "$PROBE_TARGET"' \
    '"$PROBE_MOUNT" -o remount,bind,ro "$PROBE_TARGET"' \
    'exec "$PROBE_SETPRIV" --no-new-privs --bounding-set=-all --inh-caps=-all --ambient-caps=-all /usr/bin/bash "$PROBE_DROPPED"' \
    > "$setup"
  chmod 0500 "$setup" "$dropped"

  set +e
  "$BASH_SANDBOX_UNSHARE" --user --map-root-user --mount --net /usr/bin/env \
    PROBE_SOURCE="$source" PROBE_TARGET="$target" PROBE_MOUNT="$BASH_SANDBOX_MOUNT" \
    PROBE_SETPRIV="$BASH_SANDBOX_SETPRIV" PROBE_DROPPED="$dropped" \
    /usr/bin/bash "$setup" >/dev/null 2>&1
  status=$?
  set -e
  ((status == 0)) || die 'Bash isolation is unavailable; enable unprivileged user, mount, and network namespaces and install util-linux (unshare, mount, setpriv)'
}

bash_attachment_origin() {
  local id="$1" prefix="$2" origin
  [[ "$id" == "$prefix".* ]] || return 1
  origin="${id#"$prefix".}"
  case "$origin" in
    created|existing-empty|existing-final-newline|existing-no-final-newline) printf '%s' "$origin" ;;
    *) return 1 ;;
  esac
}

select_bash_login_path() {
  local relative
  for relative in .bash_profile .bash_login .profile; do
    if [[ -e "$HOME/$relative" || -L "$HOME/$relative" ]]; then
      BASH_LOGIN_PATH="$relative"
      return 0
    fi
  done
  BASH_LOGIN_PATH=.bash_profile
}

validate_bash_attachments_from_state() {
  local state="$1" count id path hash origin status
  local rows=()
  count="$(jq '.attachments | length' "$state")"
  if [[ "$(jq -r .profile "$state")" == omarchy ]]; then
    [[ "$count" == 1 ]] || die 'native Bash state does not record exactly one attachment'
  else
    [[ "$count" == 2 ]] || die 'generic/WSL Bash state does not record exactly two attachments'
  fi
  mapfile -t rows < <(jq -r '.attachments[] | [.id,.path,.content_hash] | @tsv' "$state")
  for status in "${rows[@]}"; do
    IFS=$'\t' read -r id path hash <<< "$status"
    if [[ "$(jq -r .profile "$state")" == omarchy ]]; then
      [[ "$path" == .bashrc && "$hash" == "$(sha256_string "$BASH_NATIVE_BLOCK")" ]] || \
        die "unknown native Bash attachment in state: $id"
      origin="$(bash_attachment_origin "$id" bash-native-rc-v1)" || die "unknown native Bash attachment in state: $id"
      BASH_RC_ORIGIN="$origin"
      guarded_attachment_preflight .bashrc "$BASH_NATIVE_BEGIN" "$BASH_NATIVE_END" "$BASH_NATIVE_TOKEN" \
        "$BASH_NATIVE_BLOCK" append "$([[ "$MODE" == remove ]] && printf exact || printf refresh)"
      BASH_RC_ACTION="$GUARDED_ATTACHMENT_ACTION"
      if [[ "$BASH_RC_ACTION" == insert ]]; then BASH_RC_ORIGIN="$GUARDED_ATTACHMENT_ORIGIN"; fi
    elif [[ "$path" == .bashrc ]]; then
      [[ "$hash" == "$(sha256_string "$BASH_RC_BLOCK")" ]] || die 'managed Bash rc attachment hash is unknown'
      BASH_RC_ORIGIN="$(bash_attachment_origin "$id" bash-rc-v1)" || die "unknown Bash rc attachment in state: $id"
      guarded_attachment_preflight .bashrc "$BASH_RC_BEGIN" "$BASH_RC_END" "$BASH_RC_TOKEN" \
        "$BASH_RC_BLOCK" prepend exact
      BASH_RC_ACTION="$GUARDED_ATTACHMENT_ACTION"
    else
      [[ "$path" == .bash_profile || "$path" == .bash_login || "$path" == .profile ]] || \
        die "unknown Bash login attachment path in state: $path"
      [[ "$hash" == "$(sha256_string "$BASH_LOGIN_BLOCK")" ]] || die 'managed Bash login attachment hash is unknown'
      BASH_LOGIN_ORIGIN="$(bash_attachment_origin "$id" bash-login-v1)" || die "unknown Bash login attachment in state: $id"
      [[ -z "$BASH_LOGIN_PATH" ]] || die 'Bash state records duplicate login attachments'
      BASH_LOGIN_PATH="$path"
      guarded_attachment_preflight "$path" "$BASH_LOGIN_BEGIN" "$BASH_LOGIN_END" "$BASH_LOGIN_TOKEN" \
        "$BASH_LOGIN_BLOCK" prepend exact
      BASH_LOGIN_ACTION="$GUARDED_ATTACHMENT_ACTION"
    fi
  done
  if [[ "$(jq -r .profile "$state")" != omarchy ]]; then
    [[ -n "$BASH_RC_ORIGIN" && -n "$BASH_LOGIN_ORIGIN" && -n "$BASH_LOGIN_PATH" ]] || \
      die 'Bash state does not identify both required attachments'
  fi
}

preflight_new_bash_attachments() {
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ -e "$HOME/.bashrc" || -L "$HOME/.bashrc" ]] || die 'native Omarchy Bash baseline ~/.bashrc is missing'
    guarded_attachment_preflight .bashrc "$BASH_NATIVE_BEGIN" "$BASH_NATIVE_END" "$BASH_NATIVE_TOKEN" \
      "$BASH_NATIVE_BLOCK" append refresh
    BASH_RC_ACTION="$GUARDED_ATTACHMENT_ACTION"
    BASH_RC_ORIGIN="$GUARDED_ATTACHMENT_ORIGIN"
    return 0
  fi

  guarded_attachment_preflight .bashrc "$BASH_RC_BEGIN" "$BASH_RC_END" "$BASH_RC_TOKEN" \
    "$BASH_RC_BLOCK" prepend new
  BASH_RC_ACTION="$GUARDED_ATTACHMENT_ACTION"
  BASH_RC_ORIGIN="$GUARDED_ATTACHMENT_ORIGIN"
  select_bash_login_path
  guarded_attachment_preflight "$BASH_LOGIN_PATH" "$BASH_LOGIN_BEGIN" "$BASH_LOGIN_END" "$BASH_LOGIN_TOKEN" \
    "$BASH_LOGIN_BLOCK" prepend new
  BASH_LOGIN_ACTION="$GUARDED_ATTACHMENT_ACTION"
  BASH_LOGIN_ORIGIN="$GUARDED_ATTACHMENT_ORIGIN"
}

configure_bash_journal() {
  AREA_JOURNAL_PATHS=("$HOME/.bashrc")
  [[ -z "$BASH_LOGIN_PATH" ]] || AREA_JOURNAL_PATHS+=("$HOME/$BASH_LOGIN_PATH")
}

bash_shell_shadow_absent() {
  local name="$1" kind
  kind="$(type -t -- "$name" 2>/dev/null || true)"
  if [[ "$kind" == alias || "$kind" == function ]]; then
    log "error: managed Bash command '$name' is shadowed by a shell $kind"
    return 1
  fi
}

bash_validate_shell_shadows() {
  local name
  for name in mise starship fzf zoxide eza rg bat fd wt; do
    bash_shell_shadow_absent "$name" || return 1
  done
}

bash_distro_owner_matches() {
  local candidate="$1" package="$2" resolved owner query=/usr/bin/dpkg-query
  resolved="$(realpath -e -- "$candidate" 2>/dev/null)" || return 1
  if [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_DPKG_QUERY:-}" ]]; then query="$DOTFILES_TEST_DPKG_QUERY"; fi
  [[ -x "$query" ]] || return 1
  owner="$("$query" -S "$resolved" 2>/dev/null || true)"
  [[ "$owner" == "$package:"* || "$owner" == "$package:"*:* ]]
}

bash_candidate_is_distro_path() {
  local candidate="$1"
  case "$candidate" in /usr/bin/*|/bin/*) return 0 ;; esac
  [[ "${DOTFILES_TESTING:-}" == 1 && -n "${DOTFILES_TEST_BASH_DISTRO_BIN:-}" && \
    "$candidate" == "${DOTFILES_TEST_BASH_DISTRO_BIN%/}/"* ]]
}

bash_validate_distro_command() {
  local name="$1" package="$2" candidate
  local candidates=()
  bash_shell_shadow_absent "$name" || return 1
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && ! array_contains "$candidate" "${candidates[@]}" && candidates+=("$candidate")
  done < <(path_candidates "$name")
  ((${#candidates[@]} > 0)) || { log "error: required distro command '$name' is missing"; return 1; }
  for candidate in "${candidates[@]}"; do
    bash_candidate_is_distro_path "$candidate" || {
      log "error: distro command '$name' has an unapproved PATH candidate: $candidate"; return 1;
    }
    bash_distro_owner_matches "$candidate" "$package" || {
      log "error: distro command '$name' has no approved $package owner: $candidate"; return 1;
    }
  done
}

bash_validate_wrapper() {
  local name="$1" package="$2" expected="$3"
  shift 3
  local candidate alternative found=false
  local candidates=()
  bash_shell_shadow_absent "$name" || return 1
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && ! array_contains "$candidate" "${candidates[@]}" && candidates+=("$candidate")
  done < <(path_candidates "$name")
  ((${#candidates[@]} > 0)) || { log "error: managed wrapper '$name' is missing"; return 1; }
  [[ "${candidates[0]}" == "$expected" ]] || {
    log "error: managed wrapper '$name' is not the first recorded package owner"; return 1;
  }
  if [[ ${DOTFILES_BASH_CONTROLLED_VALIDATION-} == 1 ]]; then
    [[ ! -L "$expected" && "$(realpath -e -- "$expected")" == "$(realpath -e -- "$DOTFILES_DIR/packages/generic/bash/.local/share/dotfiles/bin/$name")" ]] || {
      log "error: controlled wrapper '$name' does not use the package source"; return 1;
    }
  else
    [[ -L "$expected" && "$(resolve_link "$expected")" == "$(realpath -e -- "$DOTFILES_DIR/packages/generic/bash/.local/share/dotfiles/bin/$name")" ]] || {
      log "error: deployed wrapper '$name' does not have recorded package ownership"; return 1;
    }
  fi
  for candidate in "${candidates[@]:1}"; do
    bash_candidate_is_distro_path "$candidate" && bash_distro_owner_matches "$candidate" "$package" || {
      log "error: managed wrapper '$name' has an unapproved additional PATH candidate: $candidate"; return 1;
    }
  done
  for alternative in "$@"; do
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      bash_candidate_is_distro_path "$candidate" || continue
      if bash_distro_owner_matches "$candidate" "$package"; then found=true; break 2; fi
    done < <(path_candidates "$alternative")
  done
  [[ "$found" == true ]] || { log "error: managed wrapper '$name' has no approved distro executable"; return 1; }
}

bash_validate_optional_mise_command() {
  local id="$1" name="$2" root executable expected candidate resolved selected
  local candidates=()
  bash_shell_shadow_absent "$name" || return 1
  provision_tool_status "$id" || return 1
  root="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .install_root' "$PROVISIONING_MANIFEST")"
  executable="$(jq -r --arg id "$id" '.tools[] | select(.id == $id) | .artifact.executable' "$PROVISIONING_MANIFEST")"
  expected="$HOME/$root/$executable"
  selected="$(bash_mise_which_readonly "$name" 2>/dev/null || true)"
  [[ -n "$selected" && "$(realpath -e -- "$selected" 2>/dev/null)" == "$(realpath -e -- "$expected" 2>/dev/null)" ]] || {
    log "error: optional mise command '$name' does not resolve to its retained owner"; return 1;
  }
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && ! array_contains "$candidate" "${candidates[@]}" && candidates+=("$candidate")
  done < <(path_candidates "$name")
  for candidate in "${candidates[@]}"; do
    resolved="$(realpath -e -- "$candidate" 2>/dev/null)" || return 1
    if [[ "$resolved" != "$(realpath -e -- "$expected")" && "$candidate" != "$HOME/.local/share/mise/shims/$name" ]]; then
      log "error: optional mise command '$name' has an unapproved PATH candidate: $candidate"
      return 1
    fi
  done
}

bash_mise_which_readonly() {
  local name="$1" temporary output status=0 config_file=""
  temporary="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise-which.XXXXXX")"
  if [[ ${DOTFILES_BASH_CONTROLLED_VALIDATION-} == 1 ]]; then
    config_file="$DOTFILES_DIR/packages/generic/bash/.config/mise/conf.d/30-dotfiles-profile.toml"
  fi
  set +e
  output="$(unshare --user --map-root-user --mount --net env \
    REAL_HOME="$HOME" TEMP_ROOT="$temporary" MISE_BINARY="$MISE_BIN" MISE_NAME="$name" \
    MISE_VALIDATION_CONFIG_FILE="$config_file" bash -c '
      set -Eeuo pipefail
      mount --bind "$REAL_HOME" "$REAL_HOME"
      mount -o remount,bind,ro "$REAL_HOME" 2>/dev/null || true
      home_mount_options=""
      while read -r _ _ _ _ mountpoint options _; do
        [[ "$mountpoint" == "$REAL_HOME" ]] && home_mount_options="$options"
      done < /proc/self/mountinfo
      [[ ",$home_mount_options," == *,ro,* ]]
      if [[ -n "$MISE_VALIDATION_CONFIG_FILE" ]]; then
        exec env HOME="$REAL_HOME" MISE_OFFLINE=1 MISE_CACHE_DIR="$TEMP_ROOT/cache" \
          MISE_STATE_DIR="$TEMP_ROOT/state" MISE_DATA_DIR="$REAL_HOME/.local/share/mise" \
          MISE_CONFIG_FILE="$MISE_VALIDATION_CONFIG_FILE" "$MISE_BINARY" which "$MISE_NAME"
      fi
      exec env HOME="$REAL_HOME" MISE_OFFLINE=1 MISE_CACHE_DIR="$TEMP_ROOT/cache" \
        MISE_STATE_DIR="$TEMP_ROOT/state" MISE_DATA_DIR="$REAL_HOME/.local/share/mise" \
        MISE_CONFIG_DIR="$REAL_HOME/.config/mise" "$MISE_BINARY" which "$MISE_NAME"
    ')" || status=$?
  set -e
  track_temp_path "$temporary"
  discard_tracked_temp_path "$temporary" 'mise validation environment' || true
  ((status == 0)) || return "$status"
  printf '%s' "$output"
}

validate_bash_interactive_ownership() {
  [[ "$SELECTED_PROFILE" != omarchy ]] || return 0
  local status=0 activation
  resolve_mise_owner || status=$?
  ((status == 0)) || { log 'error: managed Bash requires an approved mise owner'; return 1; }
  activation="$(MISE_OFFLINE=1 "$MISE_BIN" activate bash 2>/dev/null)" || {
    log 'error: approved mise owner could not produce offline Bash activation'; return 1;
  }
  [[ -z "$activation" ]] || eval "$activation"
  provision_tool_status starship || { log 'error: managed Bash requires an approved Starship owner'; return 1; }
  bash_validate_distro_command fzf fzf || return 1
  bash_validate_distro_command zoxide zoxide || return 1
  bash_validate_distro_command eza eza || return 1
  bash_validate_distro_command rg ripgrep || return 1
  local wrapper_bin="$HOME/.local/share/dotfiles/bin"
  [[ ${DOTFILES_BASH_CONTROLLED_VALIDATION-} != 1 ]] || wrapper_bin="${DOTFILES_BASH_VALIDATION_BIN:?}"
  bash_validate_wrapper bat bat "$wrapper_bin/bat" bat batcat || return 1
  bash_validate_wrapper fd fd-find "$wrapper_bin/fd" fd fdfind || return 1
  if command -v wt >/dev/null 2>&1 || declare -F wt >/dev/null || [[ "$(type -t wt 2>/dev/null || true)" == alias ]]; then
    bash_validate_optional_mise_command worktrunk wt || {
      log 'error: optional Worktrunk command has an unapproved owner'; return 1;
    }
  fi
}

write_bash_validation_script() {
  local destination="$1" validation="$2" rc_source="$3"
  {
    printf 'set +e\n'
    printf 'source %q || exit 1\n' "$rc_source"
    if [[ "$validation" == ownership ]]; then
      printf 'DOTFILES_DIR=%q\n' "$DOTFILES_DIR"
      printf 'source %q\n' "$DOTFILES_DIR/lib/provisioning.sh"
      printf 'PROVISIONING_MANIFEST=%q\n' "$PROVISIONING_MANIFEST"
      printf 'PROVISIONING_RECEIPT=%q\n' "$PROVISIONING_RECEIPT"
      printf 'PROVISIONING_MANIFEST_SHA=%q\n' "$PROVISIONING_MANIFEST_SHA"
      printf 'PROVISIONING_PLATFORM=%q\n' "$PROVISIONING_PLATFORM"
      printf 'SELECTED_PROFILE=%q\n' "$SELECTED_PROFILE"
      declare -f log array_contains sha256_file sha256_string resolve_link \
        bash_shell_shadow_absent bash_distro_owner_matches \
        bash_candidate_is_distro_path bash_validate_distro_command bash_validate_wrapper bash_validate_optional_mise_command \
        bash_mise_which_readonly validate_bash_interactive_ownership
      printf 'validate_bash_interactive_ownership || exit 1\n'
    elif [[ "$validation" == host-shadows ]]; then
      declare -f log bash_shell_shadow_absent bash_validate_shell_shadows
      printf 'bash_validate_shell_shadows || exit 1\n'
    fi
    printf 'printf "%%s\\n" %q\n' '__DOTFILES_BASH_VALIDATION_OK__'
  } > "$destination"
  chmod 0600 "$destination"
}

prepare_bash_network_sentinels() {
  local directory="$1" name
  mkdir -p -- "$directory"
  for name in curl wget ssh scp sudo apt apt-get pacman dnf yum apk snap flatpak npm pnpm yarn bun pip pip3; do
    printf '%s\n' '#!/usr/bin/env bash' \
      'printf "%s:%s\n" "${0##*/}" "$*" >> "${DOTFILES_NETWORK_SENTINEL_LOG:?}"' \
      'exit 97' > "$directory/$name"
    chmod 0755 "$directory/$name"
  done
  printf '%s\n' '#!/usr/bin/env bash' \
    'case " ${*:-} " in' \
    "  *' clone '*|*' fetch '*|*' pull '*|*' push '*|*' ls-remote '*|*' submodule '*)" \
    '    printf "git:%s\n" "$*" >> "${DOTFILES_NETWORK_SENTINEL_LOG:?}"' \
    '    exit 97' \
    '    ;;' \
    'esac' \
    'exec /usr/bin/git "$@"' > "$directory/git"
  chmod 0755 "$directory/git"
}

validate_controlled_bash_result() {
  local output="$1" errors="$2" status="$3" line filtered=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      'bash: cannot set terminal process group'*|'bash: no job control in this shell') ;;
      *) filtered+="${filtered:+$'\n'}$line" ;;
    esac
  done < "$errors"
  if ((status != 0)) || [[ "$(< "$output")" != '__DOTFILES_BASH_VALIDATION_OK__' ]] || [[ -n "$filtered" ]]; then
    [[ ! -s "$output" ]] && [[ -z "$filtered" ]] || printf '%s%s\n' "$(< "$output")" "$filtered" >&2
    die 'controlled managed Bash validation failed'
  fi
}

run_controlled_bash() {
  local source_mode="$1" ownership="$2" script output errors sentinels sentinel_log status=0
  local rc_source="$HOME/.config/dotfiles/bash/rc.bash"
  script="$(mktemp "${TMPDIR:-/tmp}/dotfiles-bash-validation.XXXXXX")"
  output="$(mktemp "${TMPDIR:-/tmp}/dotfiles-bash-output.XXXXXX")"
  errors="$(mktemp "${TMPDIR:-/tmp}/dotfiles-bash-errors.XXXXXX")"
  sentinels="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bash-sentinels.XXXXXX")"
  sentinel_log="$sentinels/network-attempted"
  track_temp_path "$script"
  track_temp_path "$output"
  track_temp_path "$errors"
  track_temp_path "$sentinels"
  prepare_bash_network_sentinels "$sentinels/bin"
  if [[ "$source_mode" == checkout ]]; then
    rc_source="$DOTFILES_DIR/packages/common/bash/.config/dotfiles/bash/rc.bash"
  fi
  write_bash_validation_script "$script" ownership "$rc_source"
  set +e
  HOME="$HOME" PATH="$sentinels/bin:$PATH" DOTFILES_NETWORK_SENTINEL_LOG="$sentinel_log" \
    DOTFILES_BASH_VALIDATE_OWNERSHIP=1 DOTFILES_BASH_SKIP_HOST_LOCAL=1 DOTFILES_BASH_TRACE= \
    DOTFILES_BASH_CONTROLLED_VALIDATION="$([[ "$source_mode" == checkout ]] && printf 1 || printf 0)" \
    DOTFILES_BASH_VALIDATION_ROOT="$DOTFILES_DIR/packages/common/bash/.config/dotfiles/bash" \
    DOTFILES_BASH_VALIDATION_GENERIC="$([[ "$SELECTED_PROFILE" == omarchy ]] || printf '%s' "$DOTFILES_DIR/packages/generic/bash/.config/dotfiles/bash")" \
    DOTFILES_BASH_VALIDATION_WSL="$([[ "$SELECTED_PROFILE" == wsl ]] && printf '%s' "$DOTFILES_DIR/packages/wsl/bash/.config/dotfiles/bash")" \
    DOTFILES_BASH_VALIDATION_UPSTREAM="$DOTFILES_DIR/packages/upstream/bash/.config/dotfiles/upstream/bash" \
    DOTFILES_BASH_VALIDATION_BIN="$DOTFILES_DIR/packages/generic/bash/.local/share/dotfiles/bin" \
    PS1= BASH_ENV= HISTFILE=/dev/null bash --noprofile --norc -i "$script" > "$output" 2> "$errors"
  status=$?
  set -e
  [[ ! -e "$sentinel_log" ]] || die 'controlled managed Bash validation attempted a network-capable command'
  validate_controlled_bash_result "$output" "$errors" "$status"
}

run_sandboxed_bash_local_validation() {
  local source="$HOME/.config/dotfiles/local/bash.sh"
  local sandbox sandbox_home sentinels sentinel_log script output errors sandbox_ready status=0
  [[ -e "$source" || -L "$source" ]] || return 0
  validate_bash_local_layer

  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bash-local.XXXXXX")"
  sandbox_home="$sandbox/home"
  sentinels="$sandbox/sentinels"
  sentinel_log="$sandbox/network-attempted"
  script="$sandbox/validate.bash"
  output="$sandbox/output"
  errors="$sandbox/errors"
  sandbox_ready="$sandbox/isolation-ready"
  track_temp_path "$sandbox"
  mkdir -p -- "$sandbox_home/.config/dotfiles/local"
  cp -p -- "$source" "$sandbox_home/.config/dotfiles/local/bash.sh"
  chmod 0400 "$sandbox_home/.config/dotfiles/local/bash.sh"
  prepare_bash_network_sentinels "$sentinels"
  write_bash_validation_script "$script" host-shadows \
    "$DOTFILES_DIR/packages/common/bash/.config/dotfiles/bash/rc.bash"

  set +e
  "$BASH_SANDBOX_UNSHARE" --user --map-root-user --mount --net /usr/bin/env \
    REAL_HOME="$HOME" SANDBOX_HOME="$sandbox_home" SENTINELS="$sentinels" SENTINEL_LOG="$sentinel_log" \
    SCRIPT="$script" OUTPUT="$output" ERRORS="$errors" SANDBOX_READY="$sandbox_ready" DOTFILES_DIR="$DOTFILES_DIR" \
    SELECTED_PROFILE="$SELECTED_PROFILE" /usr/bin/bash -c '
      set -Eeuo pipefail
      /usr/bin/mount --bind "$REAL_HOME" "$REAL_HOME"
      /usr/bin/mount -o remount,bind,ro "$REAL_HOME" 2>/dev/null || true
      home_mount_options=""
      while read -r _ _ _ _ mountpoint options _; do
        [[ "$mountpoint" == "$REAL_HOME" ]] && home_mount_options="$options"
      done < /proc/self/mountinfo
      [[ ",$home_mount_options," == *,ro,* ]]
      : > "$SANDBOX_READY"
      exec /usr/bin/setpriv --no-new-privs --bounding-set=-all --inh-caps=-all --ambient-caps=-all \
        /usr/bin/env HOME="$SANDBOX_HOME" PATH="$SENTINELS:/usr/bin:/bin" TERM=dumb PS1= BASH_ENV= HISTFILE=/dev/null \
        DOTFILES_NETWORK_SENTINEL_LOG="$SENTINEL_LOG" DOTFILES_BASH_VALIDATE_OWNERSHIP=1 \
        DOTFILES_BASH_CONTROLLED_VALIDATION=1 DOTFILES_BASH_TRACE= \
        DOTFILES_BASH_VALIDATION_ROOT="$DOTFILES_DIR/packages/common/bash/.config/dotfiles/bash" \
        DOTFILES_BASH_VALIDATION_GENERIC="$([[ "$SELECTED_PROFILE" == omarchy ]] || printf "%s" "$DOTFILES_DIR/packages/generic/bash/.config/dotfiles/bash")" \
        DOTFILES_BASH_VALIDATION_WSL="$([[ "$SELECTED_PROFILE" == wsl ]] && printf "%s" "$DOTFILES_DIR/packages/wsl/bash/.config/dotfiles/bash")" \
        DOTFILES_BASH_VALIDATION_UPSTREAM="$DOTFILES_DIR/packages/upstream/bash/.config/dotfiles/upstream/bash" \
        DOTFILES_BASH_VALIDATION_BIN="$DOTFILES_DIR/packages/generic/bash/.local/share/dotfiles/bin" \
        /usr/bin/bash --noprofile --norc -i "$SCRIPT" > "$OUTPUT" 2> "$ERRORS"
    '
  status=$?
  set -e
  [[ -e "$sandbox_ready" ]] || \
    die 'host-local Bash validation could not establish its sandbox; enable unprivileged user, mount, and network namespaces'
  [[ ! -e "$sentinel_log" ]] || die 'host-local Bash validation attempted a network-capable command'
  validate_controlled_bash_result "$output" "$errors" "$status"
}

preflight_bash() {
  init_bash_area
  load_profile_closure bash
  scan_packages
  validate_bash_target_inventory
  validate_bash_payload_modes_and_syntax
  validate_bash_isolation_capability
  record_managed_parents '.local/state/dotfiles/v1/bash.json'
  validate_bash_local_layer
  preflight_existing_state
  if [[ "$OLD_STATE" == false ]]; then preflight_new_bash_attachments; fi
  configure_bash_journal
  preflight_desired_targets
  run_stow_preflight
  if [[ "$MODE" == check ]]; then
    run_controlled_bash "$([[ "$OLD_STATE" == true ]] && printf deployed || printf checkout)" true
    run_sandboxed_bash_local_validation
  elif [[ "${PROVISION:-false}" == false ]]; then
    run_controlled_bash "$([[ "$OLD_STATE" == true ]] && printf deployed || printf checkout)" true
    run_sandboxed_bash_local_validation
  fi
}

install_bash_attachments() {
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    install_guarded_attachment .bashrc "$BASH_NATIVE_BEGIN" "$BASH_NATIVE_END" "$BASH_NATIVE_TOKEN" \
      "$BASH_NATIVE_BLOCK" append 0644 refresh
    return 0
  fi
  install_guarded_attachment .bashrc "$BASH_RC_BEGIN" "$BASH_RC_END" "$BASH_RC_TOKEN" \
    "$BASH_RC_BLOCK" prepend 0644 "$([[ "$OLD_STATE" == true ]] && printf exact || printf new)"
  install_guarded_attachment "$BASH_LOGIN_PATH" "$BASH_LOGIN_BEGIN" "$BASH_LOGIN_END" "$BASH_LOGIN_TOKEN" \
    "$BASH_LOGIN_BLOCK" prepend 0644 "$([[ "$OLD_STATE" == true ]] && printf exact || printf new)"
}

build_bash_state_json() {
  local packages='[]' targets='[]' dirs='[]' attachments='[]' i id
  for i in "${!PACKAGES[@]}"; do packages="$(jq -c --arg value "${PACKAGES[i]}" '. + [$value]' <<< "$packages")"; done
  for i in "${!TARGET_PATHS[@]}"; do
    targets="$(jq -c --arg path "${TARGET_PATHS[i]}" --arg source "${TARGET_LEXICAL[i]}" \
      --arg resolved "${TARGET_SOURCES[i]}" '. + [{path:$path,source:$source,resolved_source:$resolved}]' <<< "$targets")"
  done
  for i in "${!MANAGED_DIRS[@]}"; do dirs="$(jq -c --arg value "${MANAGED_DIRS[i]}" '. + [$value]' <<< "$dirs")"; done
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    id="bash-native-rc-v1.$BASH_RC_ORIGIN"
    attachments="$(jq -cn --arg id "$id" --arg hash "$(sha256_string "$BASH_NATIVE_BLOCK")" \
      '[{id:$id,path:".bashrc",content_hash:$hash}]')"
  else
    attachments="$(jq -cn --arg rc_id "bash-rc-v1.$BASH_RC_ORIGIN" --arg login_id "bash-login-v1.$BASH_LOGIN_ORIGIN" \
      --arg login "$BASH_LOGIN_PATH" --arg rc_hash "$(sha256_string "$BASH_RC_BLOCK")" \
      --arg login_hash "$(sha256_string "$BASH_LOGIN_BLOCK")" \
      '[{id:$rc_id,path:".bashrc",content_hash:$rc_hash},{id:$login_id,path:$login,content_hash:$login_hash}]')"
  fi
  jq -cn --arg profile "$SELECTED_PROFILE" --arg checkout "$CHECKOUT_ROOT" --arg target "$TARGET_ROOT" \
    --argjson packages "$packages" --argjson targets "$targets" --argjson dirs "$dirs" --argjson attachments "$attachments" \
    '{schema_version:1,profile:$profile,area:"bash",checkout_root:$checkout,target_root:$target,packages:$packages,targets:$targets,managed_directories:$dirs,attachments:$attachments,backups:[]}'
}

apply_bash() {
  local state_json
  begin_transaction
  remove_recorded_links_for_apply
  apply_stow_packages
  validate_applied_targets
  fault bash-after-stow
  install_bash_attachments
  fault bash-after-attachments
  run_controlled_bash deployed true
  run_sandboxed_bash_local_validation
  fault bash-after-validation
  state_json="$(build_bash_state_json)"
  write_transaction_string_atomic "$state_json" "$AREA_STATE" 0600
  TRANSACTION_ACTIVE=false
  fault bash-after-state-commit
  log "applied Bash area for profile '$SELECTED_PROFILE'"
}

remove_bash() {
  local state="$HOME/.local/state/dotfiles/v1/bash.json" count index relative dir
  local managed_directories=()
  init_bash_area
  if [[ ! -e "$state" && ! -L "$state" ]]; then
    log "area 'bash' is not deployed; no changes made"
    return 0
  fi
  validate_state_file "$state"
  [[ "$(jq -r .target_root "$state")" == "$TARGET_ROOT" ]] || die 'existing bash state belongs to a different target root'
  SELECTED_PROFILE="$(jq -r .profile "$state")"
  count="$(jq '.targets | length' "$state")"
  for ((index=0; index<count; index++)); do validate_recorded_target "$state" "$index"; done
  validate_bash_attachments_from_state "$state"
  while IFS= read -r dir; do
    validate_home_directory "$HOME/$dir"
    managed_directories+=("$dir")
  done < <(jq -r '.managed_directories[]' "$state")

  AREA_STATE="$state"
  OLD_STATE=true
  TARGET_PATHS=()
  while IFS= read -r relative; do TARGET_PATHS+=("$relative"); done < <(jq -r '.targets[].path' "$state")
  configure_bash_journal
  begin_transaction
  if [[ "$SELECTED_PROFILE" != omarchy ]]; then
    remove_guarded_attachment "$BASH_LOGIN_PATH" "$BASH_LOGIN_BEGIN" "$BASH_LOGIN_END" "$BASH_LOGIN_TOKEN" \
      "$BASH_LOGIN_BLOCK" prepend "$BASH_LOGIN_ORIGIN"
    fault bash-remove-after-login
    remove_guarded_attachment .bashrc "$BASH_RC_BEGIN" "$BASH_RC_END" "$BASH_RC_TOKEN" \
      "$BASH_RC_BLOCK" prepend "$BASH_RC_ORIGIN"
  else
    remove_guarded_attachment .bashrc "$BASH_NATIVE_BEGIN" "$BASH_NATIVE_END" "$BASH_NATIVE_TOKEN" \
      "$BASH_NATIVE_BLOCK" append "$BASH_RC_ORIGIN"
  fi
  fault bash-remove-after-attachments
  for ((index=0; index<count; index++)); do
    remove_recorded_target "$state" "$index"
  done
  fault bash-remove-after-links
  remove_current_regular_path "$state" 'Bash area state'
  prune_managed_directories "${managed_directories[@]}"
  TRANSACTION_ACTIVE=false
  log 'removed managed Bash links and startup attachments; retained provisioning and host-local Bash data'
}
