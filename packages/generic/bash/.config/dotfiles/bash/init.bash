_dotfiles_bash_eval_initializer() {
  local _initializer
  _initializer="$("$@" 2>/dev/null)" || return 0
  [[ -z $_initializer ]] || eval "$_initializer"
}

_dotfiles_bash_trace mise
if [[ ${DOTFILES_BASH_VALIDATE_OWNERSHIP-} != 1 ]] && command -v mise >/dev/null 2>&1; then
  _dotfiles_bash_eval_initializer env MISE_OFFLINE=1 mise activate bash
fi

_dotfiles_bash_trace starship
if [[ ${DOTFILES_BASH_VALIDATE_OWNERSHIP-} != 1 && ${TERM:-} != dumb ]] && command -v starship >/dev/null 2>&1; then
  _dotfiles_bash_eval_initializer command starship init bash
fi

_dotfiles_bash_trace zoxide
if [[ ${DOTFILES_BASH_VALIDATE_OWNERSHIP-} != 1 ]] && command -v zoxide >/dev/null 2>&1; then
  _dotfiles_bash_eval_initializer command zoxide init bash
fi

_dotfiles_bash_trace fzf
if [[ ${DOTFILES_BASH_VALIDATE_OWNERSHIP-} != 1 ]] && command -v fzf >/dev/null 2>&1; then
  [[ -v FZF_CTRL_T_OPTS ]] || export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always {}'"
  [[ -v FZF_ALT_C_OPTS ]] || export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons=auto {}'"
  for _dotfiles_fzf_file in /usr/share/fzf/completion.bash /usr/share/doc/fzf/examples/completion.bash; do
    [[ ! -r "$_dotfiles_fzf_file" ]] || { source "$_dotfiles_fzf_file"; break; }
  done
  for _dotfiles_fzf_file in /usr/share/fzf/key-bindings.bash /usr/share/doc/fzf/examples/key-bindings.bash; do
    [[ ! -r "$_dotfiles_fzf_file" ]] || { source "$_dotfiles_fzf_file"; break; }
  done
  unset _dotfiles_fzf_file
fi

_dotfiles_bash_trace inputrc
if [[ ${DOTFILES_BASH_VALIDATE_OWNERSHIP-} != 1 ]]; then
  _dotfiles_bash_inputrc="$HOME/.config/dotfiles/upstream/bash/inputrc"
  [[ ${DOTFILES_BASH_CONTROLLED_VALIDATION-} != 1 ]] || _dotfiles_bash_inputrc="${DOTFILES_BASH_VALIDATION_UPSTREAM:?}/inputrc"
  [[ ! -r "$_dotfiles_bash_inputrc" ]] || bind -f "$_dotfiles_bash_inputrc" 2>/dev/null
  unset _dotfiles_bash_inputrc
fi

unset -f _dotfiles_bash_eval_initializer
