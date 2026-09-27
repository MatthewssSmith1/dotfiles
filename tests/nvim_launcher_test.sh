#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

launcher="$REPO_DIR/packages/common/nvim/.local/bin/nvim"
personal="$REPO_DIR/packages/common/bash/.config/dotfiles/bash/personal.bash"
home="$TEST_ROOT/home with spaces"
mkdir -p "$home/.local/bin" "$home/editor/bin" "$home/node/bin" "$TEST_ROOT/bin"
cp "$launcher" "$home/.local/bin/nvim"
chmod +x "$home/.local/bin/nvim"
printf '#!/bin/bash\nprintf "%%s\n" "$NVIM_APPNAME" "$PATH" "$@" > "$HOME/editor-output"\nprintf "%%s\n" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" > "$HOME/editor-roots"\nexit 23\n' > "$home/editor/bin/nvim"
printf '#!/bin/bash\nif [[ "$1" == where && "$2" == -C && "$3" == "$HOME" ]]; then\n  case "$4" in aqua:neovim/neovim@0.12.4) printf "%%s\n" "$HOME/editor";; node@lts) printf "%%s\n" "$HOME/node";; esac\nelse exit 1; fi\n' > "$TEST_ROOT/bin/mise"
printf '#!/bin/bash\nif [[ "$1" == -e ]]; then exit 0; fi\n' > "$home/node/bin/node"
printf '#!/bin/bash\ncommand -v node >/dev/null || exit 1\nprintf "10.0.0\n"\n' > "$home/node/bin/npm"
chmod +x "$home/editor/bin/nvim" "$home/node/bin/node" "$home/node/bin/npm" "$TEST_ROOT/bin/mise"

# Force fallback independently of the host's installed Node.
printf '#!/bin/bash\nexit 1\n' > "$TEST_ROOT/bin/node"
chmod +x "$TEST_ROOT/bin/node"

status=0
HOME="$home" PATH="$TEST_ROOT/bin:/usr/bin:/bin" NVIM_APPNAME=other XDG_CONFIG_HOME=/custom/config XDG_DATA_HOME=/custom/data XDG_STATE_HOME=/custom/state XDG_CACHE_HOME=/custom/cache "$home/.local/bin/nvim" 'one two' '--literal' || status=$?
[[ "$status" == 23 ]] || fail 'launcher did not forward exit code'
mapfile -t output < "$home/editor-output"
[[ "${output[0]}" == nvim-matt && "${output[2]}" == 'one two' && "${output[3]}" == '--literal' ]] || fail 'launcher did not scope appname and forward arguments'
[[ "${output[1]}" == "$home/node/bin:"* ]] || fail 'desktop launch did not resolve Node via mise'
mapfile -t roots < "$home/editor-roots"
[[ "${roots[*]}" == "$home/.config $home/.local/share $home/.local/state $home/.cache" ]] || fail 'launcher roots differ from deployment'

HOME="$home" PATH="$TEST_ROOT/bin:/usr/bin:/bin" bash -c '
  _dotfiles_bash_trace() { :; }
  EDITOR=nvim VISUAL=/usr/bin/nvim
  source "$1"
  [[ "$EDITOR" == "$HOME/.local/bin/nvim" && "$VISUAL" == "$HOME/.local/bin/nvim" ]] || exit 1
  status=0
  nvim "shell argument" || status=$?
  [[ "$status" == 23 ]] || exit 1
  /usr/bin/grep -qxF "shell argument" "$HOME/editor-output" || exit 1
  EDITOR=custom VISUAL=custom
  source "$1"
  [[ "$EDITOR" == custom && "$VISUAL" == custom ]]
' _ "$personal" || fail 'shell editor integration failed'

rm "$TEST_ROOT/bin/mise"
status=0
HOME="$home" PATH="$TEST_ROOT/bin:/usr/bin:/bin" "$home/.local/bin/nvim" >/dev/null 2>&1 || status=$?
[[ "$status" == 127 ]] || fail 'missing mise did not fail without recursion'
pass
