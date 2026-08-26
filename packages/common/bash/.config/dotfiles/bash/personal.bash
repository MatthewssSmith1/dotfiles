_dotfiles_bash_trace personal

# pnpm (Backup package manager); v11 installs global binaries under $PNPM_HOME/bin.
export PNPM_HOME="$HOME/.local/share/pnpm"
for _dotfiles_bash_pnpm_dir in "$PNPM_HOME" "$PNPM_HOME/bin"; do
  case ":$PATH:" in
    *":$_dotfiles_bash_pnpm_dir:"*) ;;
    *) PATH="$_dotfiles_bash_pnpm_dir:$PATH" ;;
  esac
done
unset _dotfiles_bash_pnpm_dir
export PATH
