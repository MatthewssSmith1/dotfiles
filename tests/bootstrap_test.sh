#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly TMUX_CONFIG="$REPO_DIR/.tmux.conf"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

readonly BOOTSTRAP_SOURCES=(
  "$REPO_DIR/bootstrap.sh"
  "$REPO_DIR/lib/common.sh"
  "$REPO_DIR/lib/host.sh"
  "$REPO_DIR/lib/engine.sh"
  "$REPO_DIR/lib/areas/git.sh"
  "$REPO_DIR/lib/areas/generic.sh"
)
for source_file in "${BOOTSTRAP_SOURCES[@]}"; do
  [[ -f "$source_file" ]] || fail "missing bootstrap source file: $source_file"
done

bash -n \
  "${BOOTSTRAP_SOURCES[@]}" \
  "$REPO_DIR/scripts/upstream" \
  "$TEST_DIR/stage2_bootstrap_test.sh" \
  "$TEST_DIR/stage3_bootstrap_test.sh" \
  "$TEST_DIR/upstream_test.sh" \
  "$TEST_DIR/upstream_sync_test.sh" || fail 'a bootstrap Bash file has invalid syntax'

[[ -f "$TMUX_CONFIG" ]] || fail '.tmux.conf is missing'
grep -Fq 'set -g mode-keys vi' "$TMUX_CONFIG" || fail 'tmux copy mode does not use Vim keys'
grep -Fq 'set -g status-keys vi' "$TMUX_CONFIG" || fail 'tmux prompts do not use Vim keys'
grep -Fq 'set -g mouse on' "$TMUX_CONFIG" || fail 'tmux mouse support is not enabled'
grep -Fq 'set -g history-limit 50000' "$TMUX_CONFIG" || fail 'tmux history limit is not configured'
grep -Fq 'set -g focus-events on' "$TMUX_CONFIG" || fail 'tmux focus events are not enabled'
grep -Fq 'set -s set-clipboard external' "$TMUX_CONFIG" || fail 'tmux OSC 52 clipboard export is not enabled'
grep -Fq 'bind -T copy-mode-vi v send-keys -X begin-selection' "$TMUX_CONFIG" || \
  fail 'tmux copy mode does not bind v to begin selection'
grep -Fq 'bind -T copy-mode-vi C-v send-keys -X rectangle-toggle' "$TMUX_CONFIG" || \
  fail 'tmux copy mode does not bind Ctrl-v to rectangular selection'
grep -Fq 'bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel' "$TMUX_CONFIG" || \
  fail 'tmux copy mode does not bind y to copy a selection'
grep -Fq 'bind -T copy-mode-vi Enter send-keys -X copy-selection-and-cancel' "$TMUX_CONFIG" || \
  fail 'tmux copy mode does not bind Enter to copy a selection'
grep -Fq "set -g @plugin 'tmux-plugins/tpm'" "$TMUX_CONFIG" || fail 'TPM plugin is not configured'
grep -Fq "set -g @plugin 'tmux-plugins/tmux-resurrect'" "$TMUX_CONFIG" || fail 'tmux-resurrect is not configured'
grep -Fq "set -g @plugin 'timvw/tmux-assistant-resurrect'" "$TMUX_CONFIG" || fail 'tmux-assistant-resurrect is not configured'
grep -Fq "set -g @plugin 'tmux-plugins/tmux-continuum'" "$TMUX_CONFIG" || fail 'tmux-continuum is not configured'

tpm_line="$(grep -nF "set -g @plugin 'tmux-plugins/tpm'" "$TMUX_CONFIG" | cut -d: -f1)"
resurrect_line="$(grep -nF "set -g @plugin 'tmux-plugins/tmux-resurrect'" "$TMUX_CONFIG" | cut -d: -f1)"
assistant_line="$(grep -nF "set -g @plugin 'timvw/tmux-assistant-resurrect'" "$TMUX_CONFIG" | cut -d: -f1)"
continuum_line="$(grep -nF "set -g @plugin 'tmux-plugins/tmux-continuum'" "$TMUX_CONFIG" | cut -d: -f1)"
((tpm_line < resurrect_line && resurrect_line < assistant_line && assistant_line < continuum_line)) || \
  fail 'tmux plugins are not declared in dependency order with Continuum last'

grep -Fq "set -g @continuum-save-interval '5'" "$TMUX_CONFIG" || fail 'Continuum does not save every five minutes'
grep -Fq "set -g @continuum-restore 'on'" "$TMUX_CONFIG" || fail 'Continuum automatic restore is not enabled'
last_tmux_command="$(grep -Ev '^[[:space:]]*(#|$)' "$TMUX_CONFIG" | tail -n 1)"
[[ "$last_tmux_command" == "run '~/.tmux/plugins/tpm/tpm'" ]] || fail 'TPM initialization is not the final tmux command'

mise_line="$(grep -n 'mise activate zsh' "$REPO_DIR/.zshrc" | cut -d: -f1)"
zoxide_line="$(grep -n 'zoxide init' "$REPO_DIR/.zshrc" | cut -d: -f1)"
((mise_line < zoxide_line)) || fail 'zoxide initializes before mise activation'

if grep -Eq '(^|[[:space:]])stow([[:space:]]+[^-][^[:space:]]*)?[[:space:]]+\.' \
  "${BOOTSTRAP_SOURCES[@]}"; then
  fail 'bootstrap can invoke the retired root Stow package'
fi

if grep -Eq '^[[:space:]]*stow[[:space:]]+(-[DR][[:space:]]+)?\.[[:space:]]*$' \
  "$REPO_DIR/README.md" "$REPO_DIR/.config/nvim/README.md"; then
  fail 'durable documentation advertises the retired root Stow package'
fi

stow_target="$(mktemp -d)"
trap 'rm -rf -- "$stow_target"' EXIT
root_stow_output="$(stow --dir="$REPO_DIR" --target="$stow_target" \
  --simulate --verbose=2 --stow . 2>&1)" || fail 'inert root Stow simulation failed'
if [[ "$root_stow_output" == *'LINK:'* || "$root_stow_output" == *'UNLINK:'* || \
  "$root_stow_output" == *'MKDIR:'* ]]; then
  fail 'the retired root Stow package still has a deployable payload'
fi

"$TEST_DIR/upstream_test.sh"
"$TEST_DIR/upstream_sync_test.sh"
"$TEST_DIR/stage2_bootstrap_test.sh"
"$TEST_DIR/stage3_bootstrap_test.sh"

printf 'PASS: repository bootstrap checks\n'
