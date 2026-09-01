# Git area converted to the lean package and guarded-attachment lifecycle.

readonly GIT_INCLUDE_BEGIN='# >>> dotfiles managed git includes >>>'
readonly GIT_INCLUDE_END='# <<< dotfiles managed git includes <<<'
readonly GIT_INCLUDE_TOKEN='dotfiles managed git includes'
readonly GIT_INCLUDE_BLOCK="$GIT_INCLUDE_BEGIN
[include]
	path = ~/.config/dotfiles/personal/git.conf
[include]
	path = ~/.gitconfig.local
$GIT_INCLUDE_END"

readonly GIT_BASELINE_TABLE='alias.co	checkout
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
rerere.autoupdate	true'

validate_git_environment() {
  local name
  if [[ -n "${XDG_CONFIG_HOME:-}" && "$XDG_CONFIG_HOME" != "$HOME/.config" ]]; then
    die "XDG_CONFIG_HOME is set to '$XDG_CONFIG_HOME'; unset it or set it to '$HOME/.config' before Git deployment"
  fi
  for name in GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS; do
    [[ -z "${!name+x}" ]] || die "$name is set; unset it before Git deployment"
  done
  while IFS= read -r name; do
    [[ "$name" =~ ^GIT_CONFIG_(KEY|VALUE)_[0-9]+$ ]] || continue
    die "$name is set; unset it before Git deployment"
  done < <(compgen -A variable GIT_CONFIG_)
}

validate_git_file() {
  local file="$1"
  git config --file "$file" --no-includes --list >/dev/null 2>&1 || die "$file is not valid Git configuration"
}

validate_github_vps_source() {
  local file="$DOTFILES_DIR/packages/ubuntu/git/.config/dotfiles/git/github-vps.conf" key
  local -a values=()
  validate_git_file "$file"
  while IFS= read -r key; do
    case "${key,,}" in
      dotfiles.github-vps.enabled|credential.https://github.com.helper|credential.https://github.com.usehttppath|credential.http://github.com.helper|credential.http://github.com.usehttppath) ;;
      *) die "Ubuntu GitHub source contains unexpected key: $key" ;;
    esac
  done < <(git config --file "$file" --no-includes --name-only --list)
  mapfile -t values < <(git config --file "$file" --no-includes --get-all dotfiles.github-vps.enabled 2>/dev/null || true)
  ((${#values[@]} == 1)) && [[ "${values[0]}" == true ]] || die 'Ubuntu GitHub marker source is not exact'
  for key in credential.https://github.com.helper credential.http://github.com.helper; do
    mapfile -t values < <(git config --file "$file" --no-includes --get-all "$key" 2>/dev/null || true)
    ((${#values[@]} == 2)) && [[ -z "${values[0]}" && "${values[1]}" == '!~/.local/share/dotfiles/bin/dotfiles-github-auth' ]] ||
      die "Ubuntu GitHub source has an unexpected $key chain"
  done
  for key in credential.https://github.com.useHttpPath credential.http://github.com.useHttpPath; do
    mapfile -t values < <(git config --file "$file" --no-includes --get-all "$key" 2>/dev/null || true)
    ((${#values[@]} == 1)) && [[ "${values[0]}" == true ]] || die "Ubuntu GitHub source requires exact $key=true"
  done
}

validate_git_closure() {
  local expected relative source mode index
  local -a expected_targets=(.config/dotfiles/personal/git.conf)
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "${PACKAGES[*]}" == 'common/git' ]] || die 'native Git closure must contain only common/git'
  else
    [[ "${PACKAGES[*]}" == 'upstream/git ubuntu/git common/git' ]] ||
      die 'Ubuntu Git closure must be exactly upstream, Ubuntu, and common Git'
    expected_targets+=(
      .config/dotfiles/git/github-vps.conf
      .config/git/config
      .local/bin/gh
      .local/share/dotfiles/bin/dotfiles-github-auth
    )
  fi
  lean_scan_expected_targets 'Git package' "${expected_targets[@]}"
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    relative="${LEAN_TARGET_PATHS[index]}"
    source="${LEAN_TARGET_SOURCES[index]}"
    mode=644
    [[ "$relative" != .local/share/dotfiles/bin/dotfiles-github-auth && "$relative" != .local/bin/gh ]] || mode=755
    [[ "$(stat -c %a -- "$source")" == "$mode" ]] || die "unexpected Git payload mode for $relative"
  done
  if [[ "$SELECTED_PROFILE" == ubuntu ]]; then
    validate_github_vps_source
    bash -n "$DOTFILES_DIR/packages/ubuntu/git/.local/share/dotfiles/bin/dotfiles-github-auth" ||
      die 'Ubuntu Git credential helper has invalid Bash syntax'
    bash -n "$DOTFILES_DIR/packages/ubuntu/git/.local/bin/gh" ||
      die 'Ubuntu gh policy launcher has invalid Bash syntax'
  fi
}

validate_git_local_layer() {
  local path="$HOME/.config/dotfiles/local/git.conf" mode
  validate_home_parent_chain "$path"
  [[ ! -e "$path" && ! -L "$path" ]] && return 0
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] ||
    die "host-local Git layer is not a readable regular non-symlink file: $path"
  path_owned_by_euid "$path" || die "$path has an unsafe owner"
  mode="$(stat -c %a -- "$path")"
  (((8#$mode & 022) == 0)) || die "$path is group- or other-writable"
  validate_git_file "$path"
}

validate_git_baseline() {
  local file key expected actual
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    file="$HOME/.config/git/config"
    validate_home_parent_chain "$file"
    [[ -f "$file" && ! -L "$file" ]] ||
      die 'Omarchy native ~/.config/git/config baseline is missing or not a regular file'
  else
    file="$DOTFILES_DIR/packages/upstream/git/.config/git/config"
    [[ -f "$file" && ! -L "$file" ]] || die 'Ubuntu upstream Git baseline payload is missing'
  fi
  validate_git_file "$file"
  while IFS=$'\t' read -r key expected; do
    actual="$(git config --file "$file" --get "$key" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] ||
      die "$file has unexpected $key: expected '$expected', found '$actual'"
  done <<< "$GIT_BASELINE_TABLE"
  GIT_BASELINE_FILE="$file"
}

validate_git_identity_inputs() {
  local name="${GIT_USER_NAME:-}" email="${GIT_USER_EMAIL:-}"
  if [[ -n "$name" || -n "$email" ]]; then
    [[ -n "$name" && -n "$email" ]] || die 'GIT_USER_NAME and GIT_USER_EMAIL must be supplied together'
    [[ "$name" != *$'\n'* && "$name" != *$'\r'* ]] || die 'GIT_USER_NAME must not contain line breaks'
    [[ "$email" != *$'\n'* && "$email" != *$'\r'* ]] || die 'GIT_USER_EMAIL must not contain line breaks'
  fi
}

git_identity_value() {
  local file="$1" key="$2" values=()
  mapfile -t values < <(git config --file "$file" --get-all "$key" 2>/dev/null || true)
  ((${#values[@]} <= 1)) || die "$file contains multiple $key values"
  printf '%s' "${values[0]:-}"
}

preflight_git_identity() {
  local path="$HOME/.gitconfig.local" key name email
  GIT_IDENTITY_ACTION=none
  validate_home_parent_chain "$path"
  if [[ -e "$path" || -L "$path" ]]; then
    [[ -f "$path" && ! -L "$path" ]] || die "$path must be a regular non-symlink file"
    path_owned_by_euid "$path" || die "$path has an unsafe owner"
    validate_git_file "$path"
    while IFS= read -r key; do
      case "${key,,}" in
        credential.*) die "$path contains credential configuration; it is identity-only" ;;
        include.*|includeif.*) die "$path contains an ambiguous identity include" ;;
      esac
    done < <(git config --file "$path" --name-only --list)
    name="$(git_identity_value "$path" user.name)"
    email="$(git_identity_value "$path" user.email)"
    [[ -n "$name" && -n "$email" && "$name" != 'Your Name' && "$email" != 'you@example.com' ]] ||
      die "$path must contain one non-placeholder user.name and user.email"
    [[ "$(stat -c %a -- "$path")" == 600 ]] || GIT_IDENTITY_ACTION=protect
  else
    [[ -n "${GIT_USER_NAME:-}" && -n "${GIT_USER_EMAIL:-}" ]] ||
      die 'missing Git identity; create ~/.gitconfig.local mode 0600 or set both GIT_USER_NAME and GIT_USER_EMAIL'
    GIT_IDENTITY_ACTION=create
  fi
}

apply_git_identity() {
  local path="$HOME/.gitconfig.local" temporary
  [[ "$GIT_IDENTITY_ACTION" != none ]] || return 0
  temporary="$(mktemp "$HOME/.gitconfig.local.tmp.XXXXXX")"
  track_temp_path "$temporary"
  if [[ "$GIT_IDENTITY_ACTION" == create ]]; then
    : > "$temporary"
    git config --file "$temporary" user.name "$GIT_USER_NAME"
    git config --file "$temporary" user.email "$GIT_USER_EMAIL"
  else
    cp -- "$path" "$temporary"
  fi
  chmod 0600 "$temporary"
  validate_git_file "$temporary"
  mv -fT -- "$temporary" "$path"
}

register_git_area() {
  local package
  load_profile_closure git
  lean_begin_area git "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
  lean_add_guarded_attachment git-global-includes-v2 .gitconfig "$GIT_INCLUDE_BEGIN" "$GIT_INCLUDE_END" \
    "$GIT_INCLUDE_TOKEN" "$GIT_INCLUDE_BLOCK" prepend 0644
}

preflight_git() {
  register_git_area
  validate_git_closure
  if [[ "$MODE" == remove ]]; then
    refuse_active_github_git_removal
    lean_preflight_area remove
    return
  fi
  validate_git_environment
  validate_git_identity_inputs
  validate_git_baseline
  validate_git_local_layer
  preflight_git_identity
  lean_preflight_area "$MODE"
  [[ "$MODE" != check ]] || validate_effective_git
}

refuse_active_github_git_removal() {
  local path="$HOME/.config/dotfiles/local/git.conf" value
  local managed="$HOME/.config/dotfiles/git/github-vps.conf"
  [[ ! -e "$path" && ! -L "$path" ]] && return 0
  validate_git_local_layer
  while IFS= read -r value; do
    [[ "$value" != "$managed" ]] ||
      die 'deactivate GitHub VPS access by removing its include from host-local git.conf before removing Git; the host file was preserved'
  done < <(git config --file "$path" --no-includes --type=path --get-regexp '^(include|includeIf\..*)\.path$' 2>/dev/null | cut -d ' ' -f2- || true)
}

git_url_section_matches() {
  local section="$1" url="$2" temporary output
  temporary="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-git-url.XXXXXX")"
  output="$(HOME="$temporary" XDG_CONFIG_HOME="$temporary" GIT_CONFIG_NOSYSTEM=1 \
    git -C "$temporary" -c "credential.$section.helper=dotfiles-match" \
    config --get-urlmatch credential.helper "$url" 2>/dev/null || true)"
  rm -rf -- "$temporary"
  [[ "$output" == dotfiles-match ]]
}

validate_active_github_git() {
  local expected_origin="file:$HOME/.config/dotfiles/git/github-vps.conf" key origin backend
  local record config_key raw_config_key value section selected_url is_managed managed_started=false index
  local -a values=() origins=() helpers=() records=()
  local -a selected_urls=(
    https://github.com/MatthewssSmith1/dotfiles
    https://github.com/MatthewssSmith1/dotfiles.git
    http://github.com/MatthewssSmith1/dotfiles
    http://github.com/MatthewssSmith1/dotfiles.git
    https://github.com/mimir-db/mimir-db
    https://github.com/mimir-db/mimir-db.git
    http://github.com/mimir-db/mimir-db
    http://github.com/mimir-db/mimir-db.git
    https://github.com/mimir-db/mimir-db-v0
    https://github.com/mimir-db/mimir-db-v0.git
    http://github.com/mimir-db/mimir-db-v0
    http://github.com/mimir-db/mimir-db-v0.git
  )
  mapfile -t values < <(git -C "$HOME" config --includes --get-all dotfiles.github-vps.enabled 2>/dev/null || true)
  ((${#values[@]} > 0)) || return 0
  mapfile -t origins < <(git -C "$HOME" config --includes --show-origin --get-all dotfiles.github-vps.enabled 2>/dev/null || true)
  ((${#values[@]} == 1 && ${#origins[@]} == 1)) || die 'active GitHub marker must have exactly one value and origin'
  [[ "${values[0]}" == true && "${origins[0]}" == "$expected_origin"$'\t'true ]] ||
    die 'active GitHub marker must be true and originate from the managed github-vps.conf'
  backend="${HOST_ROOT:-}/usr/bin/gh"
  [[ -x "$backend" && -f "$backend" && ! -L "$backend" ]] || die 'active GitHub configuration requires fixed /usr/bin/gh'
  for key in credential.https://github.com.helper credential.http://github.com.helper; do
    mapfile -t helpers < <(git -C "$HOME" config --includes --get-all "$key" 2>/dev/null || true)
    ((${#helpers[@]} == 2)) && [[ -z "${helpers[0]}" && "${helpers[1]}" == '!~/.local/share/dotfiles/bin/dotfiles-github-auth' ]] ||
      die "active GitHub configuration has an unexpected $key chain"
  done
  mapfile -d '' -t records < <(git -C "$HOME" config --includes --show-origin --null \
    --get-regexp '^credential\.(.*\.)?helper$' 2>/dev/null || true)
  for ((index=0; index + 1<${#records[@]}; index+=2)); do
    origin="${records[index]}"
    record="${records[index + 1]}"
    raw_config_key="${record%%$'\n'*}"
    config_key="$raw_config_key"
    value="${record#*$'\n'}"
    config_key="${config_key,,}"
    is_managed=false
    if [[ "$origin" == "$expected_origin" &&
      ( "$config_key" == credential.https://github.com.helper || "$config_key" == credential.http://github.com.helper ) &&
      ( -z "$value" || "$value" == '!~/.local/share/dotfiles/bin/dotfiles-github-auth' ) ]]; then
      is_managed=true
    fi
    if [[ "$is_managed" == true ]]; then
      managed_started=true
      continue
    fi
    if [[ "$config_key" == credential.helper ]]; then
      [[ "$managed_started" == false ]] ||
        die 'active GitHub configuration has a helper after the managed reset/router'
      continue
    fi
    section="${raw_config_key#credential.}"
    section="${section%.helper}"
    for selected_url in "${selected_urls[@]}"; do
      git_url_section_matches "$section" "$selected_url" || continue
      die "active GitHub configuration has an additional helper applicable to $selected_url"
    done
  done
  for key in credential.https://github.com.useHttpPath credential.http://github.com.useHttpPath; do
    mapfile -t values < <(git -C "$HOME" config --includes --get-all "$key" 2>/dev/null || true)
    ((${#values[@]} == 1)) && [[ "${values[0]}" == true ]] || die "active GitHub configuration requires exact $key=true"
    origin="$(git -C "$HOME" config --includes --show-origin --get "$key" 2>/dev/null || true)"
    [[ "$origin" == "$expected_origin"$'\t'true ]] || die "active $key does not originate from managed github-vps.conf"
  done
  if git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
    git -C "$PWD" config --local --includes --name-only --get-regexp '^credential\..*\.helper$|^credential\.helper$' >/dev/null 2>&1; then
    die 'repository-local credential helper override requires explicit review'
  fi
}

validate_effective_git() {
  local key expected actual origin
  [[ "$(git -C "$HOME" config --includes --get init.defaultBranch 2>/dev/null || true)" == main ]] ||
    die 'effective init.defaultBranch does not resolve to main'
  for key in user.name user.email; do
    [[ -n "$(git -C "$HOME" config --includes --get "$key" 2>/dev/null || true)" ]] ||
      die "effective $key is missing"
    origin="$(git -C "$HOME" config --includes --show-origin --get "$key" 2>/dev/null || true)"
    [[ "$origin" == file:"$HOME/.gitconfig.local"$'\t'* ]] ||
      die "effective $key does not originate from ~/.gitconfig.local"
  done
  while IFS=$'\t' read -r key expected; do
    [[ "$key" != init.defaultBranch ]] || continue
    actual="$(git -C "$HOME" config --includes --get "$key" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] || die "effective $key does not match the accepted baseline"
    origin="$(git -C "$HOME" config --includes --show-origin --get "$key" 2>/dev/null || true)"
    [[ "$origin" == file:"$HOME/.config/git/config"$'\t'* ]] ||
      die "effective $key does not originate from the accepted baseline"
  done <<< "$GIT_BASELINE_TABLE"
  validate_active_github_git
}

apply_git() {
  preflight_git
  apply_git_identity
  lean_apply_area
  validate_effective_git
  log "applied Git area for profile '$SELECTED_PROFILE'"
}

remove_git() {
  register_git_area
  refuse_active_github_git_removal
  lean_remove_area
  log 'removed exact managed Git links and include block; retained host-local identity'
}
