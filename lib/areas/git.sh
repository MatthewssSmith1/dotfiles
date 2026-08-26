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
  for name in GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT; do
    [[ -z "${!name+x}" ]] || die "$name is set; unset it before Git deployment"
  done
}

validate_git_file() {
  local file="$1"
  git config --file "$file" --no-includes --list >/dev/null 2>&1 || die "$file is not valid Git configuration"
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
    [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "$path has an unsafe owner"
    validate_git_file "$path"
    while IFS= read -r key; do
      case "${key,,}" in include.*|includeif.*) die "$path contains an ambiguous identity include" ;; esac
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
  if [[ "$MODE" == remove ]]; then
    register_git_area
    lean_preflight_area remove
    return
  fi
  validate_git_environment
  validate_git_identity_inputs
  validate_git_baseline
  preflight_git_identity
  register_git_area
  lean_preflight_area "$MODE"
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
}

apply_git() {
  apply_git_identity
  register_git_area
  lean_apply_area
  validate_effective_git
  log "applied Git area for profile '$SELECTED_PROFILE'"
}

remove_git() {
  register_git_area
  lean_remove_area
  log 'removed exact managed Git links and include block; retained host-local identity'
}
