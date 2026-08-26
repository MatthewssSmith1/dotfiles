_dotfiles_bash_trace ubuntu
_dotfiles_bash_root_dir="${_dotfiles_bash_root:-$HOME/.config/dotfiles/bash}"
[[ ${DOTFILES_BASH_CONTROLLED_VALIDATION-} != 1 ]] || _dotfiles_bash_root_dir="${DOTFILES_BASH_VALIDATION_UBUNTU:?}"
source "$_dotfiles_bash_root_dir/env.bash"

_dotfiles_bash_upstream="$HOME/.config/dotfiles/upstream/bash"
if [[ ${DOTFILES_BASH_CONTROLLED_VALIDATION-} == 1 ]]; then
  _dotfiles_bash_upstream="${DOTFILES_BASH_VALIDATION_UPSTREAM:?}"
fi

_dotfiles_bash_trace upstream-shell
source "$_dotfiles_bash_upstream/shell"
_dotfiles_bash_trace upstream-aliases
source "$_dotfiles_bash_upstream/aliases"
_dotfiles_bash_trace upstream-tmux
source "$_dotfiles_bash_upstream/fns/tmux"
_dotfiles_bash_herdr="$HOME/.config/dotfiles/bash/fns/herdr"
[[ ! -r "$_dotfiles_bash_herdr" ]] || source "$_dotfiles_bash_herdr"
source "$_dotfiles_bash_root_dir/init.bash"

unset _dotfiles_bash_herdr _dotfiles_bash_root_dir _dotfiles_bash_upstream
