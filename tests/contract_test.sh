#!/usr/bin/env bash
# Static repository contract checks: source integrity, schema and manifest
# validity, focused configuration contracts, and root-Stow inertness.

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

readonly TMUX_BASELINE="$REPO_DIR/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf"
readonly TMUX_DISPATCHER="$REPO_DIR/packages/ubuntu/tmux/.config/tmux/tmux.conf"
readonly TMUX_ADAPTER="$REPO_DIR/packages/ubuntu/tmux/.config/dotfiles/tmux/ubuntu.conf"
readonly OMARCHY_PRUNE="$REPO_DIR/packages/omarchy/tools/.local/bin/dotfiles-omarchy-prune"
readonly OMARCHY_AMDGPU_IPS="$REPO_DIR/packages/omarchy/tools/.local/bin/dotfiles-omarchy-amdgpu-ips"
readonly OMARCHY_THEME_SWITCHER="$REPO_DIR/packages/omarchy/desktop/.local/bin/dotfiles-omarchy-theme-switcher"
readonly OMARCHY_MENU_EXTENSION="$REPO_DIR/packages/omarchy/desktop/.config/omarchy/extensions/omarchy-menu.jsonc"

# Every dotfiles source exists, parses, and keeps strict mode.
readonly DOTFILES_SOURCES=(
  "$DOTFILES"
  "$REPO_DIR/lib/common.sh"
  "$REPO_DIR/lib/host.sh"
  "$REPO_DIR/lib/lean_engine.sh"
  "$REPO_DIR/lib/areas/git.sh"
  "$REPO_DIR/lib/areas/tools.sh"
  "$REPO_DIR/lib/areas/bash.sh"
  "$REPO_DIR/lib/areas/tmux.sh"
  "$REPO_DIR/lib/areas/nvim.sh"
  "$REPO_DIR/lib/areas/agents.sh"
  "$REPO_DIR/lib/areas/herdr.sh"
  "$REPO_DIR/lib/areas/desktop.sh"
  "$REPO_DIR/lib/areas/opencode.sh"
)
for source_file in "${DOTFILES_SOURCES[@]}"; do
  [[ -f "$source_file" ]] || fail "missing dotfiles source file: $source_file"
done
bash -n "${DOTFILES_SOURCES[@]}" \
  "$REPO_DIR/scripts/upstream" \
  "$REPO_DIR/scripts/agent-skills" \
  "$OMARCHY_PRUNE" "$OMARCHY_AMDGPU_IPS" "$OMARCHY_THEME_SWITCHER" ||
  fail 'a dotfiles Bash file has invalid syntax'
grep -Fq 'set -Eeuo pipefail' "$DOTFILES" || fail 'dotfiles strict mode is missing'
[[ -x "$DOTFILES" && ! -e "$REPO_DIR/bootstrap.sh" ]] || fail 'root command rename is incomplete'
[[ -x "$REPO_DIR/packages/common/tools/.local/bin/dotfiles" ]] || fail 'dotfiles launcher is not executable'
[[ -f "$OMARCHY_PRUNE" && ! -L "$OMARCHY_PRUNE" && -x "$OMARCHY_PRUNE" ]] ||
  fail 'Omarchy prune command is not a regular executable payload'
[[ -f "$OMARCHY_AMDGPU_IPS" && ! -L "$OMARCHY_AMDGPU_IPS" && -x "$OMARCHY_AMDGPU_IPS" ]] ||
  fail 'Omarchy AMDGPU IPS command is not a regular executable payload'
pass

# Production topology has exactly the native Omarchy and supported Ubuntu
# profiles.
profile_names="$(printf '%s\n' "$REPO_DIR"/profiles/*.conf | xargs -n1 basename | LC_ALL=C sort | tr '\n' ' ')"
[[ "$profile_names" == 'omarchy.conf ubuntu.conf ' ]] || fail "unexpected production profiles: $profile_names"
for profile in omarchy ubuntu; do
  [[ "$(grep -cve '^#' -e '^$' "$REPO_DIR/profiles/$profile.conf")" == 9 ]] || \
    fail "profile $profile does not list exactly nine entries"
done
[[ "$(grep -hE '^[a-z0-9-]+[[:space:]]+validation-only$' "$REPO_DIR"/profiles/*.conf | sort)" == $'desktop validation-only\nherdr validation-only\ntmux validation-only' ]] ||
  fail 'profile validation-only entries are not exact'
pass

# OpenCode is an optional, package-only area with parallel non-secret configs.
grep -qxF 'area|opencode|optional' "$REPO_DIR/manifests/areas.tsv" || fail 'OpenCode area is not optional'
for profile in omarchy ubuntu; do
  grep -qxF 'opencode common/opencode' "$REPO_DIR/profiles/$profile.conf" ||
    fail "$profile OpenCode closure is not final"
done
grep -Fq '|| "$1" == opencode' "$DOTFILES" || fail 'OpenCode is absent from lean dispatch'
opencode_package="$REPO_DIR/packages/common/opencode"
opencode_inventory="$(find "$opencode_package" -type f -printf '%P\n' | LC_ALL=C sort)"
[[ "$opencode_inventory" == $'.config/opencode/base.jsonc\n.config/opencode/dotfiles-tui.jsonc\n.config/opencode/profiles/personal.jsonc\n.config/opencode/profiles/work.jsonc\n.local/bin/dotfiles-opencode-profile\n.local/bin/opencode\n.local/bin/opencode-personal\n.local/bin/opencode-work\n.local/share/dotfiles/bin/opencode-launch' ]] ||
  fail 'OpenCode payload inventory is not exact'
jq empty "$opencode_package/.config/opencode/"*.jsonc "$opencode_package/.config/opencode/profiles/"*.jsonc ||
  fail 'managed OpenCode config is invalid JSON'
tui_config="$opencode_package/.config/opencode/dotfiles-tui.jsonc"
[[ "$(jq -r '."$schema"' "$tui_config")" == 'https://opencode.ai/tui.json' &&
  "$(jq -r '.keybinds.input_newline' "$tui_config")" == 'ctrl+return,shift+return,alt+return,ctrl+j' ]] ||
  fail 'managed OpenCode TUI config is not exact'
for executable in "$opencode_package/.local/bin/"* "$opencode_package/.local/share/dotfiles/bin/opencode-launch"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || fail "OpenCode launcher is not executable: $executable"
done
pass

# Desktop is native-only ownership with four exact private payloads. Ubuntu is
# validation-only, and default removal can select desktop only from v2 state.
desktop_fragment="$REPO_DIR/packages/omarchy/desktop/.config/dotfiles/omarchy/hypr/input.lua"
desktop_aliases="$REPO_DIR/packages/omarchy/desktop/.config/dotfiles/omarchy/XCompose"
expected_desktop_aliases=$'<Multi_key> <space> <a> : "AGENTS.md"\n<Multi_key> <p> <b> : "Continue discussing with me briefly."\n<Multi_key> <p> <d> : "Continue discussing with me, focussing on points we have yet to agree on."\n<Multi_key> <p> <t> : "What do you think/recommend? Discuss with me."'
grep -qxF 'desktop omarchy/desktop' "$REPO_DIR/profiles/omarchy.conf" || fail 'native desktop closure is not final'
grep -qxF 'desktop validation-only' "$REPO_DIR/profiles/ubuntu.conf" || fail 'Ubuntu desktop is not validation-only'
[[ "$(find "$REPO_DIR/packages/omarchy/desktop" -type f -printf '%P\n' | LC_ALL=C sort)" == \
  $'.config/dotfiles/omarchy/XCompose\n.config/dotfiles/omarchy/hypr/input.lua\n.config/omarchy/extensions/omarchy-menu.jsonc\n.local/bin/dotfiles-omarchy-theme-switcher' && -f "$desktop_fragment" ]] ||
  fail 'desktop package payload inventory is not exact'
[[ "$(< "$desktop_aliases")" == "$expected_desktop_aliases" ]] || fail 'desktop Compose aliases are not exact'
[[ -f "$OMARCHY_THEME_SWITCHER" && ! -L "$OMARCHY_THEME_SWITCHER" && -x "$OMARCHY_THEME_SWITCHER" &&
  "$(stat -c %a "$OMARCHY_THEME_SWITCHER")" == 755 ]] || fail 'desktop theme selector is not an exact executable payload'
[[ -f "$OMARCHY_MENU_EXTENSION" && ! -L "$OMARCHY_MENU_EXTENSION" ]] || fail 'desktop menu extension is not a regular payload'
grep -qxF 'readonly -a HIDDEN_THEMES=(' "$OMARCHY_THEME_SWITCHER" || fail 'theme denylist is not readonly'
expected_hidden=$'ethereal\nflexoki-light\nhackerman\nlast-horizon\nlumon\nlupine\nmiasma\nrose-pine\nvantablack\nwhite'
actual_hidden="$(awk '/^readonly -a HIDDEN_THEMES=\($/{inside=1; next} inside && /^\)/{exit} inside {sub(/^[[:space:]]+/, ""); print}' "$OMARCHY_THEME_SWITCHER")"
[[ "$actual_hidden" == "$expected_hidden" ]] || fail 'theme denylist names are not exact'
jq -e '
  keys == ["style.theme"] and
  .["style.theme"] == {
    "icon":"󰸌", "label":"Theme", "aliases":["theme", "themes"],
    "action":"theme=$(\"$HOME/.local/bin/dotfiles-omarchy-theme-switcher\"); [[ -n $theme ]] && omarchy-theme-set \"$theme\""
  }
' "$OMARCHY_MENU_EXTENSION" >/dev/null || fail 'desktop menu theme routing is not exact'
grep -Fq '|| "$1" == desktop' "$DOTFILES" || fail 'desktop is absent from lean dispatch'
grep -Fq 'for file in "$(lean_state_dir)"/*.json' "$DOTFILES" || fail 'default removal does not inspect ownership state'
! grep -Eq 'add_area[[:space:]]+desktop' "$DOTFILES" || fail 'default removal selects desktop without ownership'
! grep -Eq '(^|[;&|[:space:]])(omarchy-shell|hyprctl|omarchy[[:space:]]+restart|omarchy[[:space:]]+reload)([;&|[:space:]]|$)' \
  "$REPO_DIR/lib/areas/desktop.sh" || fail 'desktop invokes shell restart/reload'
! grep -Eq '^[[:space:]]*(omarchy[[:space:]]+menu[[:space:]]+refresh|dotfiles-omarchy-theme-switcher|omarchy-theme-(switcher|set))([;&|[:space:]]|$)' \
  "$REPO_DIR/lib/areas/desktop.sh" || fail 'desktop deployment invokes theme/menu runtime commands'
pass

# Herdr uses native validation-only ownership and one Ubuntu package-only
# closure. Ubuntu adds one exact policy preamble to the accepted config.
grep -Fq '|| "$1" == herdr' "$DOTFILES" ||
  fail 'Herdr is absent from lean dispatch'
grep -qxF 'herdr validation-only' "$REPO_DIR/profiles/omarchy.conf" || fail 'native Herdr is not validation-only'
grep -qxF 'herdr ubuntu/herdr' "$REPO_DIR/profiles/ubuntu.conf" || fail 'Ubuntu Herdr closure is not final'
herdr_reference="$REPO_DIR/packages/upstream/reference/omarchy/config/herdr/config.toml"
herdr_ubuntu="$REPO_DIR/packages/ubuntu/herdr/.config/herdr/config.toml"
herdr_preamble=$'onboarding = false\n\n[update]\nversion_check = false\nmanifest_check = true\n\n'
herdr_expected="$TEST_ROOT/herdr-ubuntu-expected.toml"
{ printf '%s' "$herdr_preamble"; cat "$herdr_reference"; } > "$herdr_expected"
cmp -s "$herdr_ubuntu" "$herdr_expected" || fail 'Ubuntu Herdr config is not the exact policy derivation'
! grep -qE '^(\[update\]|(onboarding|version_check|manifest_check)[[:space:]]*=)' "$herdr_reference" ||
  fail 'immutable Herdr reference contains Ubuntu policy'
[[ "$(grep -c '^onboarding = false$' "$herdr_ubuntu")" == 1 &&
  "$(grep -c '^version_check = false$' "$herdr_ubuntu")" == 1 &&
  "$(grep -c '^manifest_check = true$' "$herdr_ubuntu")" == 1 ]] ||
  fail 'Ubuntu Herdr policy values are not exact'
grep -qxF '"aqua:ogulcancelik/herdr" = "0.8.2"' \
  "$REPO_DIR/packages/ubuntu/herdr/.config/mise/conf.d/50-dotfiles-herdr-ubuntu.toml" ||
  fail 'Ubuntu Herdr selector is not exact'
[[ ! -e "$REPO_DIR/packages/common/herdr/.config/dotfiles/herdr/config.toml" ]] ||
  fail 'retired common Herdr adapter remains'
! grep -Eq 'require\|herdr\|[^|]*\|[^|]*\|unshare\|' "$REPO_DIR/manifests/dependencies.tsv" ||
  fail 'Herdr retains the unshare requirement'
pass

# Converted Git/tools topology is lean and mise configuration no longer belongs
# to Bash. Native tools do not select Node; Ubuntu carries the only fallback.
grep -qxF 'git upstream/git,ubuntu/git,common/git' "$REPO_DIR/profiles/ubuntu.conf" || fail 'Ubuntu Git closure is not final'
grep -qxF 'tools common/tools,omarchy/tools' "$REPO_DIR/profiles/omarchy.conf" || fail 'native tools closure is not final'
grep -qxF 'tools common/tools,ubuntu/tools' "$REPO_DIR/profiles/ubuntu.conf" || fail 'Ubuntu tools closure is not final'
[[ "$(find "$REPO_DIR/packages/omarchy/tools" -type f -printf '%P\n' | LC_ALL=C sort)" == \
  $'.local/bin/dotfiles-omarchy-amdgpu-ips\n.local/bin/dotfiles-omarchy-prune' ]] ||
  fail 'native tools package payload inventory is not exact'
grep -qxF 'readonly -a PACKAGES=(' "$OMARCHY_PRUNE" || fail 'Omarchy prune package inventory is not declared'
grep -qxF 'omarchy pkg drop "${PACKAGES[@]}"' "$OMARCHY_PRUNE" || fail 'Omarchy prune package inventory is not used safely'
grep -qxF 'readonly -a WEBAPPS=(' "$OMARCHY_PRUNE" || fail 'Omarchy prune web-app inventory is not declared'
grep -qxF 'for webapp in "${WEBAPPS[@]}"; do' "$OMARCHY_PRUNE" || fail 'Omarchy prune web-app inventory is not used safely'
grep -qxF '  OMARCHY_REMOVE_NOTIFY=false omarchy webapp remove "$webapp"' "$OMARCHY_PRUNE" ||
  fail 'Omarchy prune does not use supported web-app removal'
! grep -Eq '(^|[;&|[:space:]])(sudo|pacman|yay|rm|read)([;&|[:space:]]|$)' "$OMARCHY_PRUNE" ||
  fail 'Omarchy prune directly performs privileged, destructive, or interactive work'
! grep -Eq 'omarchy[[:space:]]+(hook|refresh|restart|update)' "$OMARCHY_PRUNE" ||
  fail 'Omarchy prune installs automation or invokes refresh/restart/update'
grep -qxF "readonly MANAGED_PATH='/etc/limine-entry-tool.d/90-dotfiles-amdgpu-ips.conf'" "$OMARCHY_AMDGPU_IPS" ||
  fail 'AMDGPU IPS managed path is not exact'
grep -qxF "readonly KERNEL_ARGUMENT='amdgpu.dcdebugmask=0x800'" "$OMARCHY_AMDGPU_IPS" ||
  fail 'AMDGPU IPS kernel argument is not exact'
for value in Framework 'Laptop 13 (AMD Ryzen AI 300 Series)' FRANMGCP09 1002:150e; do
  grep -Fq "$value" "$OMARCHY_AMDGPU_IPS" || fail "AMDGPU IPS hardware gate is missing: $value"
done
! grep -Eq '(product_serial|product_uuid|board_serial|machine-id)' "$OMARCHY_AMDGPU_IPS" ||
  fail 'AMDGPU IPS helper uses a unique machine identifier'
grep -Fq 'sudo install -D -o root -g root -m 0644 --' "$OMARCHY_AMDGPU_IPS" ||
  fail 'AMDGPU IPS helper does not use the narrow install boundary'
grep -Fq 'sudo rm -- "$target"' "$OMARCHY_AMDGPU_IPS" ||
  fail 'AMDGPU IPS helper does not use the narrow removal boundary'
! grep -Eq 'sudo[[:space:]]+(sh|bash|limine-mkinitcpio)' "$OMARCHY_AMDGPU_IPS" ||
  fail 'AMDGPU IPS helper uses an unsafe privileged shell or wraps Limine in sudo'
! grep -Eq '^[[:space:]]*(reboot|shutdown|pacman|curl|wget)([;&|[:space:]]|$)' "$OMARCHY_AMDGPU_IPS" ||
  fail 'AMDGPU IPS helper invokes reboot, package, or network commands'
[[ ! -e "$REPO_DIR/packages/generic/git/.empty-package" && ! -e "$REPO_DIR/packages/generic/git/.stow-local-ignore" ]] ||
  fail 'retired generic Git adapter remains'
[[ ! -e "$REPO_DIR/.gitconfig" ]] || fail 'retired root Git migration source remains'
! grep -Rqs 'locked = true' "$REPO_DIR/packages/common/tools" "$REPO_DIR/packages/ubuntu/tools" || fail 'managed mise locked mode remains'
! grep -Rqs '^node[[:space:]]*=' "$REPO_DIR/packages/common/tools" || fail 'native tools select Node'
[[ ! -e "$REPO_DIR/packages/common/bash/.config/mise/conf.d/20-dotfiles-common.toml" &&
  -z "$(find "$REPO_DIR/packages/generic/bash" -type f -print -quit 2>/dev/null)" ]] ||
  fail 'mise configuration remains owned by Bash packages'
pass

# Bash is a lean area. Native owns only personal payload and one refreshable
# source block; Ubuntu owns the portable closure and exact Starship selector.
grep -qxF 'bash common/bash' "$REPO_DIR/profiles/omarchy.conf" || fail 'native Bash closure is not personal-only'
grep -qxF 'bash upstream/bash,upstream/starship,ubuntu/bash,common/bash' "$REPO_DIR/profiles/ubuntu.conf" ||
  fail 'Ubuntu Bash closure is not final'
grep -Fq '|| "$1" == bash' "$DOTFILES" ||
  fail 'Bash is absent from lean dispatch'
grep -qxF '"aqua:starship/starship" = "1.26.0"' \
  "$REPO_DIR/packages/ubuntu/bash/.config/mise/conf.d/40-dotfiles-bash-ubuntu.toml" ||
  fail 'Ubuntu Bash does not own the exact Starship selector'
[[ -z "$(find "$REPO_DIR/packages/wsl" -type f -print -quit 2>/dev/null)" ]] || fail 'retired WSL payload remains'
for path in lib/areas/zsh.sh .zshrc .zsh_aliases .p10k.zsh; do
  [[ ! -e "$REPO_DIR/$path" && ! -L "$REPO_DIR/$path" ]] || fail "retired zsh path remains: $path"
done
[[ -z "$(find "$REPO_DIR/packages/common/zsh" -type f -print -quit 2>/dev/null)" ]] || fail 'retired zsh package payload remains'
! grep -Eq '(^|[|,[:space:]])zsh([|,[:space:]]|$)' "$REPO_DIR/manifests/areas.tsv" \
  "$REPO_DIR/manifests/dependencies.tsv" "$REPO_DIR/profiles/omarchy.conf" "$REPO_DIR/profiles/ubuntu.conf" ||
  fail 'zsh remains in executable topology'
pass

# Every schema and committed manifest is well-formed JSON, and each manifest
# with a schema validates against it (Draft 2020-12).
jq empty "$REPO_DIR"/schemas/*.schema.json || fail 'a schema file is invalid JSON'
jq empty "$REPO_DIR/manifests/sources.json" || fail 'a manifest file is invalid JSON'
if schema_validator_available; then
  for schema_file in "$REPO_DIR"/schemas/*.schema.json; do
    python3 - "$schema_file" <<'PYTHON' || fail "schema is not a valid Draft 2020-12 schema: $schema_file"
import json, sys
import jsonschema
with open(sys.argv[1]) as handle:
    jsonschema.Draft202012Validator.check_schema(json.load(handle))
PYTHON
  done
else
  printf 'WARN: python3-jsonschema unavailable; skipped schema self-validation\n' >&2
fi
validate_json_schema "$REPO_DIR/schemas/source-manifest.schema.json" "$REPO_DIR/manifests/sources.json"
shopt -s nullglob
versioned_schema_names=("$REPO_DIR"/schemas/*-v[0-9]*.schema.json)
shopt -u nullglob
((${#versioned_schema_names[@]} == 0)) || fail 'first-party schema filename contains a version suffix'
pass

# tmux is native validation-only and an Ubuntu package-only baseline plus a
# small portable help adapter. Retired plugin/parser machinery is absent.
for file in "$TMUX_BASELINE" "$TMUX_DISPATCHER" "$TMUX_ADAPTER"; do
  [[ -f "$file" && ! -L "$file" ]] || fail "tmux contract file is missing or unsafe: $file"
done
grep -qxF 'tmux validation-only' "$REPO_DIR/profiles/omarchy.conf" || fail 'native tmux is not validation-only'
grep -qxF 'tmux upstream/tmux,ubuntu/tmux' "$REPO_DIR/profiles/ubuntu.conf" || fail 'Ubuntu tmux closure is not final'
grep -Fq '|| "$1" == tmux' "$DOTFILES" ||
  fail 'tmux is absent from lean dispatch'
grep -Fq 'set -g prefix C-Space' "$TMUX_BASELINE" || fail 'relocated tmux baseline lost its primary prefix'
grep -Fq 'set -g prefix2 C-b' "$TMUX_BASELINE" || fail 'relocated tmux baseline lost its fallback prefix'
grep -Fq 'set -g mouse on' "$TMUX_BASELINE" || fail 'relocated tmux baseline lost mouse support'
grep -Fq 'set -g default-terminal "tmux-256color"' "$TMUX_BASELINE" || fail 'relocated tmux baseline lost tmux-256color'
grep -Fq 'source-file ~/.config/dotfiles/upstream/tmux/tmux.conf' "$TMUX_DISPATCHER" || \
  fail 'tmux dispatcher does not load the private upstream baseline first'
grep -Fq 'source-file ~/.config/dotfiles/tmux/ubuntu.conf' "$TMUX_DISPATCHER" || fail 'tmux dispatcher does not load the Ubuntu adapter'
grep -Fq 'display-popup' "$TMUX_ADAPTER" || fail 'tmux adapter lost its portable popup'
grep -Fq 'keybindings.txt' "$TMUX_ADAPTER" || fail 'tmux adapter lost static help'
! grep -Fq 'omarchy-menu-tmux-keybindings' "$TMUX_ADAPTER" || fail 'tmux adapter invokes an Omarchy-only command'
grep -qxF '"aqua:tmux/tmux-builds" = "3.7c"' \
  "$REPO_DIR/packages/ubuntu/tmux/.config/mise/conf.d/50-dotfiles-tmux-ubuntu.toml" || fail 'tmux selector is not exact'
for path in .tmux.conf packages/common/tmux packages/generic/tmux manifests/tmux-plugins.lock.json \
  manifests/tmux-parser-fixtures.lock.json scripts/tmux-parser-fixtures tests/tmux_parser_gate.sh \
  schemas/tmux-plugin-lock.schema.json schemas/tmux-plugin-receipt.schema.json schemas/tmux-parser-fixture-lock.schema.json; do
  [[ ! -e "$REPO_DIR/$path" && ! -L "$REPO_DIR/$path" ]] || fail "retired tmux machinery remains: $path"
done
pass


# Agents is the final package-only lean area. Legacy runtime, migration, and
# deployment-state-v1 machinery are absent from the executable topology.
grep -qxF 'agents common/agents' "$REPO_DIR/profiles/omarchy.conf" || fail 'native Agents closure is not final'
grep -qxF 'agents common/agents' "$REPO_DIR/profiles/ubuntu.conf" || fail 'Ubuntu Agents closure is not final'
grep -Fq '|| "$1" == agents' "$DOTFILES" || fail 'Agents is absent from lean dispatch'
for path in lib/engine.sh lib/areas/generic.sh tests/engine_test.sh tests/engine_profile_test.sh manifests/legacy-links.json; do
  [[ ! -e "$REPO_DIR/$path" && ! -L "$REPO_DIR/$path" ]] || fail "retired deployment machinery remains: $path"
done
! grep -Fq 'lib/engine.sh' "$DOTFILES" || fail 'dotfiles still sources the v1 engine'
pass

# Neovim is lean, Ubuntu-specific, and the last provisioning surface
# has been removed completely.
grep -qxF 'nvim upstream/nvim,ubuntu/nvim,common/nvim' "$REPO_DIR/profiles/ubuntu.conf" ||
  fail 'Ubuntu Neovim closure is not final'
grep -qxF 'nvim common/nvim' "$REPO_DIR/profiles/omarchy.conf" || fail 'native Neovim closure is not personal-only'
grep -Fq '|| "$1" == nvim' "$DOTFILES" || fail 'Neovim is absent from lean dispatch'
for path in lib/provisioning.sh manifests/provisioning.json schemas/provisioning-manifest.schema.json \
  schemas/provisioning-receipt.schema.json tests/provisioning_test.sh \
  packages/ubuntu/nvim/.local/share/dotfiles/bin/nvim-record-restore; do
  [[ ! -e "$REPO_DIR/$path" && ! -L "$REPO_DIR/$path" ]] || fail "retired provisioning/Neovim path remains: $path"
done
[[ -z "$(find "$REPO_DIR/packages/generic/nvim" -type f -print -quit 2>/dev/null)" ]] ||
  fail 'retired generic Neovim adapter remains'
! grep -Eq -- '--provision|--retire-provisioned' "$DOTFILES" || fail 'dotfiles still accepts provisioning flags'
pass

# The retired root Stow package stays unreachable and undeployable.
if grep -Eq '(^|[[:space:]])stow([[:space:]]+[^-][^[:space:]]*)?[[:space:]]+\.' \
  "${DOTFILES_SOURCES[@]}"; then
  fail 'dotfiles can invoke the retired root Stow package'
fi
if grep -Eq '^[[:space:]]*stow[[:space:]]+(-[DR][[:space:]]+)?\.[[:space:]]*$' \
  "$REPO_DIR/README.md"; then
  fail 'durable documentation advertises the retired root Stow package'
fi

if command -v stow >/dev/null 2>&1; then
  stow_target="$TEST_ROOT/root-stow-target"
  mkdir "$stow_target"
  root_stow_output="$(stow --dir="$REPO_DIR" --target="$stow_target" \
    --simulate --verbose=2 --stow . 2>&1)" || fail 'inert root Stow simulation failed'
  if [[ "$root_stow_output" == *'LINK:'* || "$root_stow_output" == *'UNLINK:'* || \
    "$root_stow_output" == *'MKDIR:'* ]]; then
    fail 'the retired root Stow package still has a deployable payload'
  fi
else
  printf 'SKIP: real GNU Stow unavailable; skipped retired root-package integration simulation\n'
fi
[[ ! -e "$REPO_DIR/.config/nvim" && ! -L "$REPO_DIR/.config/nvim" ]] || \
  fail 'retired repository-root Neovim tree returned to current HEAD'
pass

# Numbered rollout terminology belongs only to Git history, not current paths
# or content. Construct the expression so this contract does not match itself.
rollout_term='([Ss]tage|[Pp]hase)[-_ ]?[0-9]+'
while IFS= read -r tracked_path; do
  [[ -e "$REPO_DIR/$tracked_path" || -L "$REPO_DIR/$tracked_path" ]] || continue
  [[ ! "$tracked_path" =~ $rollout_term ]] || fail "numbered rollout term remains in tracked path: $tracked_path"
done < <(git -C "$REPO_DIR" ls-files --cached --others --exclude-standard)
if git -C "$REPO_DIR" grep --untracked -nEI "$rollout_term" -- . > "$TEST_ROOT/rollout-terms"; then
  TEST_OUTPUT="$(< "$TEST_ROOT/rollout-terms")"
  fail 'numbered rollout terminology remains in tracked content'
fi
pass

printf 'PASS: repository contract checks (%d groups)\n' "$TEST_COUNT"
