_dotfiles_bash_trace worktrunk
if [[ ${DOTFILES_BASH_VALIDATE_OWNERSHIP-} != 1 ]] && command -v wt >/dev/null 2>&1 && \
  [[ -x /usr/bin/unshare && -x /usr/bin/setpriv ]]; then
  _dotfiles_bash_init="$(/usr/bin/unshare --user --map-root-user --net \
    /usr/bin/setpriv --no-new-privs --bounding-set=-all --inh-caps=-all --ambient-caps=-all \
    /usr/bin/env MISE_OFFLINE=1 wt config shell init bash 2>/dev/null)" || _dotfiles_bash_init=""
  [[ -z $_dotfiles_bash_init ]] || eval "$_dotfiles_bash_init"
  unset _dotfiles_bash_init
fi
