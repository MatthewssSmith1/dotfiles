_dotfiles_bash_trace environment

[[ -v EDITOR ]] || export EDITOR=nvim
[[ -v VISUAL ]] || export VISUAL=nvim
[[ -v SUDO_EDITOR ]] || export SUDO_EDITOR="$EDITOR"
[[ -v BAT_THEME ]] || export BAT_THEME=ansi
[[ -v MANROFFOPT ]] || export MANROFFOPT=-c
[[ -v MANPAGER ]] || export MANPAGER="sh -c 'col -bx | bat -l man -p'"

_dotfiles_bash_path=""
_dotfiles_bash_add_path() {
  local _candidate="$1"
  [[ -n $_candidate ]] || return 0
  case ":$_dotfiles_bash_path:" in
    *":$_candidate:"*) return 0 ;;
  esac
  if [[ -z $_dotfiles_bash_path ]]; then
    _dotfiles_bash_path="$_candidate"
  else
    _dotfiles_bash_path+=":$_candidate"
  fi
}

_dotfiles_bash_add_path "$HOME/.local/bin"
_dotfiles_bash_private_bin="$HOME/.local/share/dotfiles/bin"
if [[ ${DOTFILES_BASH_CONTROLLED_VALIDATION-} == 1 && -n ${DOTFILES_BASH_VALIDATION_BIN-} ]]; then
  _dotfiles_bash_private_bin="$DOTFILES_BASH_VALIDATION_BIN"
fi
_dotfiles_bash_add_path "$_dotfiles_bash_private_bin"
[[ ! -d "$HOME/.opencode/bin" ]] || _dotfiles_bash_add_path "$HOME/.opencode/bin"

IFS=: read -r -a _dotfiles_bash_inherited_path <<< "${PATH-}"
for _dotfiles_bash_component in "${_dotfiles_bash_inherited_path[@]}"; do
  case "$_dotfiles_bash_component" in
    ""|"$HOME/.fzf/bin"|"$HOME/.deno/bin"|"$HOME/.nvm"|"$HOME/.nvm/"*|"$HOME/.local/share/vite-plus"*) continue ;;
  esac
  _dotfiles_bash_add_path "$_dotfiles_bash_component"
done
for _dotfiles_bash_component in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
  _dotfiles_bash_add_path "$_dotfiles_bash_component"
done
export PATH="$_dotfiles_bash_path"

unset -f _dotfiles_bash_add_path
unset _dotfiles_bash_component _dotfiles_bash_inherited_path _dotfiles_bash_path _dotfiles_bash_private_bin
