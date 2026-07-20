# Managed Bash dispatcher. Startup attachments source this file directly.
[[ $- == *i* ]] || return 0

if [[ ${__DOTFILES_BASH_RC_PID-} == "$BASHPID" && $(declare -p __DOTFILES_BASH_RC_PID 2>/dev/null) != declare\ -x\ * ]]; then
  return 0
fi
__DOTFILES_BASH_RC_PID="$BASHPID"
export -n __DOTFILES_BASH_RC_PID 2>/dev/null || true

_dotfiles_bash_trace() {
  [[ -n ${DOTFILES_BASH_TRACE-} ]] || return 0
  printf '%s\n' "$1" >> "$DOTFILES_BASH_TRACE"
}

_dotfiles_bash_root="$HOME/.config/dotfiles/bash"
_dotfiles_bash_generic="$_dotfiles_bash_root/generic.bash"
_dotfiles_bash_wsl="$_dotfiles_bash_root/wsl.bash"
if [[ ${DOTFILES_BASH_CONTROLLED_VALIDATION-} == 1 ]]; then
  _dotfiles_bash_root="${DOTFILES_BASH_VALIDATION_ROOT:?}"
  _dotfiles_bash_generic="${DOTFILES_BASH_VALIDATION_GENERIC-}/generic.bash"
  _dotfiles_bash_wsl="${DOTFILES_BASH_VALIDATION_WSL-}/wsl.bash"
fi

if [[ -r "$_dotfiles_bash_generic" ]]; then
  source "$_dotfiles_bash_generic"
fi
if [[ -r "$_dotfiles_bash_wsl" ]]; then
  source "$_dotfiles_bash_wsl"
fi
source "$_dotfiles_bash_root/integrations.bash"
source "$_dotfiles_bash_root/personal.bash"

_dotfiles_bash_local="$HOME/.config/dotfiles/local/bash.sh"
if [[ ${DOTFILES_BASH_SKIP_HOST_LOCAL-} != 1 && -f "$_dotfiles_bash_local" &&
  ! -L "$_dotfiles_bash_local" && -O "$_dotfiles_bash_local" && -r "$_dotfiles_bash_local" ]]; then
  _dotfiles_bash_trace host-local
  source "$_dotfiles_bash_local"
fi

unset _dotfiles_bash_generic _dotfiles_bash_local _dotfiles_bash_root _dotfiles_bash_wsl
