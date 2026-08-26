# Host detection and profile selection; sourced by dotfiles.sh exactly once.

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
  local version_path="$HOST_ROOT/usr/share/omarchy/version"
  local command_path="$HOST_ROOT/usr/bin/omarchy"
  local version_present=false command_present=false
  local version_marker="" package_identity="" command_identity=""
  local version_lines=()
  local kernel=""
  local system

  if [[ "${DOTFILES_TESTING:-}" == 1 ]]; then
    [[ -n "$HOST_ROOT" && "$HOST_ROOT" != / ]] || die 'host detection tests require an isolated host root'
  fi
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
  [[ "$system" == Linux ]] || die "unsupported host operating system: $system"
  [[ "$IS_WSL" == false ]] || die 'WSL hosts are not supported'

  parse_os_release
  [[ -e "$version_path" || -L "$version_path" ]] && version_present=true
  [[ -e "$command_path" || -L "$command_path" ]] && command_present=true
  if [[ "$version_present" != "$command_present" ]]; then
    die 'partial Omarchy installation: /usr/share/omarchy/version and /usr/bin/omarchy must both be present'
  fi

  DETECTED_PROFILE=""
  DETECTED_CLASS=unsupported
  HOST_SUPPORTED=false
  if [[ "$version_present" == true ]]; then
    [[ -f "$version_path" && ! -L "$version_path" ]] || \
      die 'invalid Omarchy signal: /usr/share/omarchy/version must be a regular non-symlink file'
    [[ -f "$command_path" && ! -L "$command_path" && -x "$command_path" ]] || \
      die 'invalid Omarchy signal: /usr/bin/omarchy must be an executable regular non-symlink file'
    mapfile -t version_lines < "$version_path"
    ((${#version_lines[@]} == 1)) || die 'malformed or unsupported Omarchy v4 family marker'
    version_marker="${version_lines[0]}"
    [[ -n "$version_marker" &&
      "$version_marker" =~ ^4\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]] || \
      die 'malformed or unsupported Omarchy v4 family marker'
    [[ "$OS_ID" == omarchy ]] || \
      die "contradictory host signals: native Omarchy files require ID=omarchy, found ID=${OS_ID:-missing}"
    package_identity="$(omarchy_package_identity /usr/share/omarchy/version)" || \
      die 'invalid Omarchy package authority for /usr/share/omarchy/version'
    command_identity="$(omarchy_package_identity /usr/bin/omarchy)" || \
      die 'invalid Omarchy package authority for /usr/bin/omarchy'
    [[ "$package_identity" == "$command_identity" &&
      "$package_identity" =~ ^omarchy\ 4\.[0-9A-Za-z.+-]+$ ]] || \
      die 'Omarchy signals do not have exact v4 package authority'
    DETECTED_PROFILE=omarchy
    DETECTED_CLASS=omarchy
    HOST_SUPPORTED=true
  elif [[ "$OS_ID" == omarchy ]]; then
    die 'partial Omarchy installation: ID=omarchy requires native version and command signals'
  elif ubuntu_2404_or_newer; then
    DETECTED_PROFILE=ubuntu
    DETECTED_CLASS=ubuntu
    HOST_SUPPORTED=true
  elif [[ "$OS_ID" == ubuntu ]]; then
    die "unsupported Ubuntu release: ${OS_VERSION_ID:-missing}; version 24.04 or newer is required"
  else
    die "unsupported Linux distribution: ID=${OS_ID:-missing} VERSION_ID=${OS_VERSION_ID:-missing}"
  fi
}

omarchy_package_identity() {
  local path="$1" metadata owner="" recorded_path recorded_owner package
  if [[ "${DOTFILES_TESTING:-}" == 1 ]]; then
    metadata="$HOST_ROOT/var/lib/dotfiles-test/pacman-owners.tsv"
    [[ -n "$HOST_ROOT" && "$HOST_ROOT" != / && -f "$metadata" ]] || return 1
    while IFS=$'\t' read -r recorded_path recorded_owner; do
      [[ "$recorded_path" == "$path" ]] || continue
      [[ -z "$owner" ]] || return 1
      owner="$recorded_owner"
    done < "$metadata"
    [[ -n "$owner" ]] || return 1
    printf '%s' "$owner"
    return 0
  fi

  [[ -x /usr/bin/pacman ]] || return 1
  package="$(/usr/bin/pacman -Qqo -- "$path" 2>/dev/null)" || return 1
  [[ "$package" == omarchy ]] || return 1
  /usr/bin/pacman -Q omarchy 2>/dev/null
}

select_profile() {
  SELECTED_PROFILE="$DETECTED_PROFILE"
  if [[ -n "$PROFILE_OVERRIDE" ]]; then
    case "$DETECTED_CLASS:$PROFILE_OVERRIDE" in
      omarchy:omarchy|ubuntu:ubuntu) ;;
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

check_omarchy_core_drift() {
  local installed installed_version accepted
  [[ "$SELECTED_PROFILE" == omarchy ]] || return 0
  installed="$(omarchy_package_identity /usr/share/omarchy/version 2>/dev/null || true)"
  [[ "$installed" =~ ^omarchy[[:space:]]4\.[0-9A-Za-z.+-]+$ ]] || {
    log 'error: Omarchy core has no accepted package identity'
    return 1
  }
  accepted="$(jq -er '[.sources[] | select(.repository == "https://github.com/basecamp/omarchy") | .release] | unique | if length == 1 then .[0] else error("ambiguous Omarchy release") end' "$DOTFILES_DIR/manifests/sources.json")" || {
    log 'error: active source manifest has no unique Omarchy release'
    return 1
  }
  accepted="omarchy ${accepted#v}"
  installed_version="${installed#omarchy }"
  installed_version="${installed_version%-*}"
  [[ "omarchy $installed_version" == "$accepted" ]] || log "warning: Omarchy core package drift: installed=$installed recorded=$accepted"
}
