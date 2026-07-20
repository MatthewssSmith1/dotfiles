#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly TMUX_COMPATIBILITY_CONFIG="$REPO_DIR/.tmux.conf"
readonly TMUX_BASELINE="$REPO_DIR/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf"
readonly TMUX_DISPATCHER="$REPO_DIR/packages/generic/tmux/.config/tmux/tmux.conf"
readonly TMUX_PERSISTENCE="$REPO_DIR/packages/common/tmux/.config/dotfiles/tmux/persistence.conf"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

readonly BOOTSTRAP_SOURCES=(
  "$REPO_DIR/bootstrap.sh"
  "$REPO_DIR/lib/common.sh"
  "$REPO_DIR/lib/host.sh"
  "$REPO_DIR/lib/engine.sh"
  "$REPO_DIR/lib/provisioning.sh"
  "$REPO_DIR/lib/areas/git.sh"
  "$REPO_DIR/lib/areas/bash.sh"
  "$REPO_DIR/lib/areas/tmux.sh"
  "$REPO_DIR/lib/areas/nvim.sh"
  "$REPO_DIR/lib/areas/zsh.sh"
  "$REPO_DIR/lib/areas/generic.sh"
)
for source_file in "${BOOTSTRAP_SOURCES[@]}"; do
  [[ -f "$source_file" ]] || fail "missing bootstrap source file: $source_file"
done
jq empty "$REPO_DIR/schemas/tmux-plugin-lock-v1.schema.json" \
  "$REPO_DIR/schemas/tmux-plugin-receipt-v1.schema.json" \
  "$REPO_DIR/schemas/tmux-parser-fixture-lock-v1.schema.json" \
  "$REPO_DIR/manifests/tmux-parser-fixtures.lock.json" || fail 'tmux schema or lock JSON is invalid'

bash -n \
  "${BOOTSTRAP_SOURCES[@]}" \
  "$REPO_DIR/scripts/upstream" \
  "$REPO_DIR/scripts/tmux-parser-fixtures" \
  "$TEST_DIR/stage2_bootstrap_test.sh" \
  "$TEST_DIR/stage3_bootstrap_test.sh" \
  "$TEST_DIR/stage5_bootstrap_test.sh" \
  "$TEST_DIR/stage6_engine_test.sh" \
  "$TEST_DIR/stage6_shell_test.sh" \
  "$TEST_DIR/stage6_matrix_test.sh" \
  "$TEST_DIR/stage6_ready_test.sh" \
  "$TEST_DIR/stage7_tmux_test.sh" \
  "$TEST_DIR/stage7_tmux_parser_fixture_test.sh" \
  "$TEST_DIR/stage7_tmux_parser_compatibility_test.sh" \
  "$TEST_DIR/stage7_tmux_provisioning_test.sh" \
  "$TEST_DIR/stage8_nvim_test.sh" \
  "$TEST_DIR/stage8_nvim_readiness_test.sh" \
  "$TEST_DIR/upstream_test.sh" \
  "$TEST_DIR/upstream_sync_test.sh" || fail 'a bootstrap Bash file has invalid syntax'

for file in "$TMUX_COMPATIBILITY_CONFIG" "$TMUX_BASELINE" "$TMUX_DISPATCHER" "$TMUX_PERSISTENCE"; do
  [[ -f "$file" && ! -L "$file" ]] || fail "tmux contract file is missing or unsafe: $file"
done
grep -Fq 'set -g prefix C-Space' "$TMUX_BASELINE" || fail 'relocated tmux baseline lost its primary prefix'
grep -Fq 'set -g prefix2 C-b' "$TMUX_BASELINE" || fail 'relocated tmux baseline lost its fallback prefix'
grep -Fq 'set -g mouse on' "$TMUX_BASELINE" || fail 'relocated tmux baseline lost mouse support'
grep -Fq 'set -g default-terminal "tmux-256color"' "$TMUX_BASELINE" || fail 'relocated tmux baseline lost tmux-256color'
grep -Fq 'source-file ~/.config/dotfiles/upstream/tmux/tmux.conf' "$TMUX_DISPATCHER" || \
  fail 'tmux dispatcher does not load the private upstream baseline first'
grep -Fq 'source-file ~/.config/dotfiles/tmux/persistence.conf' "$TMUX_DISPATCHER" || \
  fail 'tmux dispatcher does not load common persistence'
grep -Fq "set -g @plugin 'tmux-plugins/tpm'" "$TMUX_PERSISTENCE" || fail 'TPM plugin is not configured'
grep -Fq "set -g @plugin 'tmux-plugins/tmux-resurrect'" "$TMUX_PERSISTENCE" || fail 'tmux-resurrect is not configured'
grep -Fq "set -g @plugin 'tmux-plugins/tmux-continuum'" "$TMUX_PERSISTENCE" || fail 'tmux-continuum is not configured'
grep -Fq 'set -g @resurrect-hook-post-save-all "bash \"$HOME/.tmux/plugins/tmux-assistant-resurrect/scripts/save-assistant-sessions.sh\""' \
  "$TMUX_PERSISTENCE" || fail 'Assistant Resurrect save hook is not managed directly'
grep -Fq 'set -g @resurrect-hook-post-restore-all "bash \"$HOME/.tmux/plugins/tmux-assistant-resurrect/scripts/restore-assistant-sessions.sh\""' \
  "$TMUX_PERSISTENCE" || fail 'Assistant Resurrect restore hook is not managed directly'
! grep -Fq "set -g @plugin 'timvw/tmux-assistant-resurrect'" "$TMUX_PERSISTENCE" || \
  fail 'tmux-assistant-resurrect must not be TPM-loaded'
for config in "$TMUX_PERSISTENCE" "$TMUX_COMPATIBILITY_CONFIG"; do
  ! grep -Fq "set -g @plugin 'timvw/tmux-assistant-resurrect'" "$config" || \
    fail "Assistant Resurrect entrypoint remains TPM-loaded in $config"
  ! grep -Eq 'git[[:space:]]+clone|install_plugins' "$config" || \
    fail "tmux startup can mutate plugin checkouts through $config"
done

tpm_line="$(grep -nF "set -g @plugin 'tmux-plugins/tpm'" "$TMUX_PERSISTENCE" | cut -d: -f1)"
resurrect_line="$(grep -nF "set -g @plugin 'tmux-plugins/tmux-resurrect'" "$TMUX_PERSISTENCE" | cut -d: -f1)"
continuum_line="$(grep -nF "set -g @plugin 'tmux-plugins/tmux-continuum'" "$TMUX_PERSISTENCE" | cut -d: -f1)"
((tpm_line < resurrect_line && resurrect_line < continuum_line)) || \
  fail 'tmux plugins are not declared in dependency order with Continuum last'

grep -Fq "set -g @continuum-save-interval '5'" "$TMUX_PERSISTENCE" || fail 'Continuum does not save every five minutes'
grep -Fq "set -g @continuum-restore 'on'" "$TMUX_PERSISTENCE" || fail 'Continuum automatic restore is not enabled'
last_tmux_command="$(grep -Ev '^[[:space:]]*(#|$)' "$TMUX_PERSISTENCE" | tail -n 1)"
last_tmux_command="${last_tmux_command#"${last_tmux_command%%[![:space:]]*}"}"
[[ "$last_tmux_command" == "'run-shell \"\$HOME/.tmux/plugins/tpm/tpm\"'" ]] || \
  fail 'guarded TPM initialization is not the final tmux command'

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
"$TEST_DIR/stage5_bootstrap_test.sh"
"$TEST_DIR/stage6_engine_test.sh"
"$TEST_DIR/stage6_shell_test.sh"
"$TEST_DIR/stage6_matrix_test.sh"
"$TEST_DIR/stage6_ready_test.sh"
"$TEST_DIR/stage7_tmux_test.sh"
"$TEST_DIR/stage7_tmux_parser_fixture_test.sh"
"$TEST_DIR/stage7_tmux_provisioning_test.sh"
"$TEST_DIR/stage8_nvim_test.sh"
"$TEST_DIR/stage8_nvim_readiness_test.sh"

printf 'PASS: repository bootstrap checks\n'
