# Host detection and profile selection; sourced by bootstrap.sh exactly once.

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
