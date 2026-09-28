#!/usr/bin/env bash
set -Eeuo pipefail
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

[[ -x /usr/bin/stow ]] || fail 'GNU Stow is needed to verify package ignore semantics'

run_area() {
  local home="$1" host="$2" profile="$3" operation="$4" phase="${5:-ok}" repo="${6:-$REPO_DIR}"
  HOME="$home" TARGET_ROOT="$home" HOST_ROOT="$host" DOTFILES_DIR="$repo" NVIM_LIB_DIR="$REPO_DIR/lib" SCRIPT_NAME=nvim-test SELECTED_PROFILE="$profile" MODE="$operation" \
    NVIM_PHASE="$phase" DOTFILES_TESTING=1 bash -c '
    set -Eeuo pipefail
    source "$NVIM_LIB_DIR/common.sh"
    source "$NVIM_LIB_DIR/host.sh"
    source "$NVIM_LIB_DIR/lean_engine.sh"
    source "$NVIM_LIB_DIR/areas/nvim.sh"
    validate_area_manifest
    nvim_provision_prerequisites() { printf "prerequisites\n" >> "$HOME/phases"; [[ "$NVIM_PHASE" != prereq ]]; }
    nvim_provision_editor() { printf "editor\n" >> "$HOME/phases"; [[ "$NVIM_PHASE" != editor ]]; }
    validate_nvim_prerequisites() { :; }
    nvim_provision_mise() { printf "%s" "$HOME/mise"; }
    case "$MODE" in apply) apply_nvim ;; remove) remove_nvim ;; check) preflight_nvim ;; esac
  '
}

native="$(make_host nvim-native linux omarchy 4.0.1)"
mkdir -p "$native/usr/bin"
printf '#!/bin/sh\nprintf "NVIM v0.12.4\\n"\n' > "$native/usr/bin/nvim"
chmod 755 "$native/usr/bin/nvim"
record_pacman_ownership "$native" 'neovim 0.12.4-1' /usr/bin/nvim
ubuntu="$(make_host nvim-ubuntu linux)"

for profile in omarchy ubuntu; do
  host="$ubuntu"; [[ "$profile" != omarchy ]] || host="$native"
  home="$(new_home "nvim-$profile")"
  mkdir -p "$home/.local/share/nvim-matt" "$home/.local/share/nvim" "$home/.config/nvim"
  printf 'untouched\n' > "$home/.local/share/nvim/sentinel"
  printf 'untouched\n' > "$home/.local/share/nvim-matt/sentinel"
  if [[ "$profile" == ubuntu ]]; then
    mkdir -p "$home/mise/bin"
    printf '#!/bin/sh\nprintf "NVIM v0.12.4\\n"\n' > "$home/mise/bin/nvim"
    chmod 755 "$home/mise/bin/nvim"
  fi
  if run_area "$home" "$host" "$profile" apply prereq >/dev/null 2>&1; then fail 'prerequisite failure succeeded'; fi
  [[ ! -e "$home/.config/nvim-matt/init.lua" ]] || fail 'preflight/provision failure wrote links'
  run_area "$home" "$host" "$profile" apply >/dev/null
  [[ -L "$home/.config/nvim-matt" && ! -L "$home/.config/nvim-matt/init.lua" &&
    ! -L "$home/.config/nvim-matt/lazy-lock.json" && -L "$home/.local/bin/nvim" ]] ||
    fail "$profile personal config missing"
  [[ ! -e "$home/.config/nvim/init.lua" ]] || fail "$profile default editor changed"
  [[ "$(< "$home/phases")" == $'prerequisites\nprerequisites\neditor' ]] || fail 'apply phases out of order'
  run_area "$home" "$host" "$profile" apply >/dev/null
  [[ "$(< "$home/.local/share/nvim-matt/sentinel")" == untouched ]] || fail 'editor data changed'
  if run_area "$home" "$host" "$profile" check >/dev/null 2>&1; then
    fail 'check passed without installed plugins'
  fi
  while IFS= read -r plugin; do mkdir -p "$home/.local/share/nvim-matt/lazy/$plugin"; done \
    < <(jq -r 'keys[]' "$home/.config/nvim-matt/lazy-lock.json")
  artifact="$home/.local/share/nvim-matt/mason/packages/sqlfluff/mason-receipt.json"
  mkdir -p "$(dirname -- "$artifact")" "$home/.local/state/nvim-matt"
  printf 'installed\n' > "$artifact"
  lock_hash="$(sha256sum "$home/.config/nvim-matt/lazy-lock.json")"; lock_hash="${lock_hash%% *}"
  extras_hash="$(sha256sum "$home/.config/nvim-matt/lazyvim.json")"; extras_hash="${extras_hash%% *}"
  jq -cn --arg file "$artifact" --arg lock "$lock_hash" --arg extras "$extras_hash" \
    '{version:1,files:[$file],lock_sha256:$lock,extras_sha256:$extras}' > "$home/.local/state/nvim-matt/dotfiles-ready.json"
  run_area "$home" "$host" "$profile" check >/dev/null
  jq '.extras_sha256 = ("0" * 64)' "$home/.local/state/nvim-matt/dotfiles-ready.json" > "$home/bad-receipt"
  mv -- "$home/bad-receipt" "$home/.local/state/nvim-matt/dotfiles-ready.json"
  if run_area "$home" "$host" "$profile" check >/dev/null 2>&1; then fail 'stale extras readiness passed check'; fi
  jq -cn --arg file "$artifact" --arg lock "$lock_hash" --arg extras "$extras_hash" \
    '{version:1,files:[$file],lock_sha256:$lock,extras_sha256:$extras}' > "$home/.local/state/nvim-matt/dotfiles-ready.json"
  rm -- "$artifact"
  if run_area "$home" "$host" "$profile" check >/dev/null 2>&1; then fail 'missing Mason artifact passed check'; fi
  if [[ "$profile" == ubuntu ]]; then rm -- "$home/mise/bin/nvim"; fi
  run_area "$home" "$host" "$profile" remove >/dev/null
  [[ ! -L "$home/.local/bin/nvim" && ! -L "$home/.config/nvim-matt" ]] || fail 'remove retained links'
  [[ "$(< "$home/.local/share/nvim-matt/sentinel")" == untouched ]] || fail 'remove changed editor data'
  pass
done

# Old symlink targets are recognized lexically even when deleted from checkout.
home="$(new_home nvim-migrate)"
mkdir -p "$home/.config/dotfiles/nvim" "$home/.config/nvim/plugin" "$home/.local/state/dotfiles/v2"
printf 'native baseline\n' > "$home/.config/nvim/init.lua"
ln -s "$REPO_DIR/packages/common/nvim/.config/dotfiles/nvim/personal.lua" "$home/.config/dotfiles/nvim/personal.lua"
block="$(bash -c 'source "$1/lib/areas/nvim.sh"; printf %s "$NVIM_NATIVE_BLOCK"' _ "$REPO_DIR")"
printf '%s\n' "$block" > "$home/.config/nvim/plugin/dotfiles-personal.lua"
hash="$(printf '%s' "$block" | sha256sum)"; hash="${hash%% *}"
jq -cn --arg hash "$hash" '{version:3,area:"nvim",profile:"omarchy",resources:{},attachments:{".config/nvim/plugin/dotfiles-personal.lua":{id:"nvim-native-loader",origin:"created",before_sha256:null,managed_sha256:$hash,pending_sha256:null}}}' > "$home/.local/state/dotfiles/v2/nvim.json"
if run_area "$home" "$native" omarchy apply editor >/dev/null 2>&1; then fail 'failed editor provision succeeded'; fi
[[ -L "$home/.config/dotfiles/nvim/personal.lua" && -f "$home/.local/state/dotfiles/v2/nvim.json" ]] || fail 'failed migration lost legacy ownership'
[[ ! -e "$home/.local/state/dotfiles/v2/nvim.json.migrating" ]] || fail 'migration created a stranded state'
run_area "$home" "$native" omarchy apply >/dev/null
[[ ! -L "$home/.config/dotfiles/nvim/personal.lua" && ! -e "$home/.config/nvim/plugin/dotfiles-personal.lua" &&
  ! -e "$home/.local/state/dotfiles/v2/nvim.json" && "$(< "$home/.config/nvim/init.lua")" == 'native baseline' ]] || fail 'migration failed'
pass

# Atomic application rewrites must land in a disposable repository directory,
# without replacing the managed directory link or editing the real checkout.
fixture="$TEST_ROOT/checkout"
mkdir -p "$fixture/packages/common" "$fixture/packages/ubuntu" "$fixture/profiles" "$fixture/manifests"
cp -a "$REPO_DIR/packages/common/nvim" "$fixture/packages/common/nvim"
cp -a "$REPO_DIR/packages/ubuntu/nvim" "$fixture/packages/ubuntu/nvim"
printf 'nvim common/nvim\n' > "$fixture/profiles/omarchy.conf"
cp "$REPO_DIR/manifests/areas.tsv" "$fixture/manifests/areas.tsv"
home="$(new_home nvim-atomic)"
run_area "$home" "$native" omarchy apply ok "$fixture" >/dev/null
config="$home/.config/nvim-matt"
[[ -L "$config" ]] || fail 'personal config is not a directory link'
jq '.extras += ["test.extra"]' "$config/lazyvim.json" > "$config/lazyvim.tmp"
mv -- "$config/lazyvim.tmp" "$config/lazyvim.json"
[[ -L "$config" && ! -L "$config/lazyvim.json" ]] || fail 'atomic rewrite displaced config link'
jq -e '.extras[-1] == "test.extra"' "$fixture/packages/common/nvim/.config/nvim-matt/lazyvim.json" >/dev/null ||
  fail 'atomic rewrite missed disposable tracked config'
jq -e '.extras[-1] != "test.extra"' "$REPO_DIR/packages/common/nvim/.config/nvim-matt/lazyvim.json" >/dev/null ||
  fail 'atomic rewrite changed real checkout'
printf 'return {}\n' > "$fixture/packages/common/nvim/.config/nvim-matt/lua/plugins/new-personal.lua"
run_area "$home" "$native" omarchy apply ok "$fixture" >/dev/null
[[ -f "$config/lua/plugins/new-personal.lua" && -L "$config" ]] ||
  fail 'new personal Lua file required deployment manifest edits'
run_area "$home" "$native" omarchy remove ok "$fixture" >/dev/null
[[ ! -L "$config" && -f "$fixture/packages/common/nvim/.config/nvim-matt/lazyvim.json" ]] ||
  fail 'removal changed source config'
pass

home="$(new_home nvim-preflight-conflict)"
mkdir -p "$home/.config/nvim-matt"
printf 'mine\n' > "$home/.config/nvim-matt/init.lua"
if run_area "$home" "$native" omarchy apply >/dev/null 2>&1; then fail 'unmanaged config conflict passed preflight'; fi
[[ "$(< "$home/.config/nvim-matt/init.lua")" == mine && ! -e "$home/phases" &&
  ! -e "$home/.local/bin/nvim" ]] || fail 'preflight conflict caused writes or provisioning'
pass

# Ubuntu's deleted package links remain identifiable by their literal targets.
home="$(new_home nvim-ubuntu-migrate)"
mkdir -p "$home/.config/nvim/lua/config" "$home/.config/dotfiles/nvim" "$home/.local/share/nvim"
ln -s "$REPO_DIR/packages/upstream/nvim/.config/nvim/init.lua" "$home/.config/nvim/init.lua"
ln -s "$REPO_DIR/packages/upstream/nvim/.config/nvim/lua/config/lazy.lua" "$home/.config/nvim/lua/config/lazy.lua"
ln -s "$REPO_DIR/packages/ubuntu/nvim/.config/dotfiles/nvim/ubuntu.lua" "$home/.config/dotfiles/nvim/ubuntu.lua"
printf 'unmanaged\n' > "$home/.config/nvim/notes.lua"
printf 'runtime\n' > "$home/.local/share/nvim/sentinel"
mkdir -p "$home/.local/share/nvim-matt"
printf 'personal data\n' > "$home/.local/share/nvim-matt/sentinel"
run_area "$home" "$ubuntu" ubuntu apply >/dev/null
[[ ! -L "$home/.config/nvim/init.lua" && ! -L "$home/.config/nvim/lua/config/lazy.lua" &&
  ! -L "$home/.config/dotfiles/nvim/ubuntu.lua" && "$(< "$home/.config/nvim/notes.lua")" == unmanaged &&
  "$(< "$home/.local/share/nvim/sentinel")" == runtime ]] || fail 'Ubuntu migration removed unrelated data or left old links'
run_area "$home" "$ubuntu" ubuntu apply >/dev/null
run_area "$home" "$ubuntu" ubuntu remove >/dev/null
[[ "$(< "$home/.local/share/nvim-matt/sentinel")" == 'personal data' ]] || fail 'Ubuntu removal changed editor data'
pass

home="$(new_home nvim-remove-legacy)"
mkdir -p "$home/.config/nvim/plugin" "$home/.local/state/dotfiles/v2" "$home/.config/dotfiles/nvim"
printf '%s\n' "$block" > "$home/.config/nvim/plugin/dotfiles-personal.lua"
ln -s "$REPO_DIR/packages/common/nvim/.config/dotfiles/nvim/personal.lua" "$home/.config/dotfiles/nvim/personal.lua"
jq -cn --arg hash "$hash" '{version:3,area:"nvim",profile:"omarchy",resources:{},attachments:{".config/nvim/plugin/dotfiles-personal.lua":{id:"nvim-native-loader",origin:"created",before_sha256:null,managed_sha256:$hash,pending_sha256:null}}}' > "$home/.local/state/dotfiles/v2/nvim.json"
run_area "$home" "$native" omarchy remove >/dev/null
[[ ! -e "$home/.local/state/dotfiles/v2/nvim.json" && ! -L "$home/.config/dotfiles/nvim/personal.lua" &&
  ! -e "$home/.config/nvim/plugin/dotfiles-personal.lua" && ! -e "$home/phases" ]] || fail 'legacy removal required runtime or provisioning'
pass

# Exact legacy source identity, unsafe parent traversal, and unmanaged files.
home="$(new_home nvim-conflict)"
mkdir -p "$home/.config/dotfiles/nvim" "$home/.config/nvim"
ln -s "$REPO_DIR/packages/upstream/nvim/.config/nvim/README.md" "$home/.config/nvim/init.lua"
printf 'unmanaged\n' > "$home/.config/nvim/README.md"
run_area "$home" "$native" omarchy apply >/dev/null
[[ -L "$home/.config/nvim/init.lua" && "$(< "$home/.config/nvim/README.md")" == unmanaged ]] ||
  fail 'unrelated default-editor objects were removed'
run_area "$home" "$native" omarchy remove >/dev/null
pass

home="$(new_home nvim-unsafe-parent)"
outside="$(new_home nvim-outside)"
mkdir -p "$home/.config" "$outside/nvim"
ln -s "$outside" "$home/.config/dotfiles"
ln -s "$REPO_DIR/packages/common/nvim/.config/dotfiles/nvim/personal.lua" "$outside/nvim/personal.lua"
if run_area "$home" "$native" omarchy apply >/dev/null 2>&1; then fail 'unsafe legacy parent passed preflight'; fi
[[ ! -e "$home/.config/nvim-matt/init.lua" && -L "$outside/nvim/personal.lua" ]] || fail 'unsafe parent mutated deployment'
pass

# Resolve effective native specs without evaluating their Lua; polling survives
# native's replacement of the entire current theme directory.
home="$(new_home nvim-theme)"
mkdir -p "$home/.local/state/omarchy/current/theme"
theme_dir="$REPO_DIR/packages/upstream/reference/omarchy/themes"
module_dir="$REPO_DIR/packages/common/nvim/.config/nvim-matt/lua"
for slug in everforest catppuccin tokyo-night; do
  printf '%s\n' "$slug" > "$home/.local/state/omarchy/current/theme.name"
  cp "$theme_dir/$slug/neovim.lua" "$home/.local/state/omarchy/current/theme/neovim.lua"
  expected=everforest
  [[ "$slug" != catppuccin ]] || expected=catppuccin-nvim
  [[ "$slug" != tokyo-night ]] || expected=tokyonight-night
  result="$(HOME="$home" XDG_STATE_HOME="$home/other-state" NVIM_THEME_MODULE="$module_dir" nvim --headless -u NONE \
    '+lua package.path=vim.env.NVIM_THEME_MODULE.."/?.lua;"..package.path; print(require("config.dotfiles_theme").resolve().colorscheme)' +qa 2>&1)"
  [[ "$result" == "$expected" ]] || fail "$slug native spec was not resolved: $result"
done
printf 'unknown\n' > "$home/.local/state/omarchy/current/theme.name"
printf 'error("executed")\n' > "$home/.local/state/omarchy/current/theme/neovim.lua"
result="$(HOME="$home" XDG_STATE_HOME="$home/other-state" NVIM_THEME_MODULE="$module_dir" nvim --headless -u NONE \
  '+lua package.path=vim.env.NVIM_THEME_MODULE.."/?.lua;"..package.path; print(require("config.dotfiles_theme").resolve().colorscheme)' +qa 2>&1)"
[[ "$result" == *tokyonight-night* && "$result" == *'unsupported native theme'* ]] || fail 'unsupported native Lua was used without a warning'
printf 'everforest\n' > "$home/.local/state/omarchy/current/theme.name"
cp "$theme_dir/everforest/neovim.lua" "$home/.local/state/omarchy/current/theme/neovim.lua"
printf '\n-- user note\n' >> "$home/.local/state/omarchy/current/theme/neovim.lua"
result="$(HOME="$home" NVIM_THEME_MODULE="$module_dir" nvim --headless -u NONE \
  '+lua package.path=vim.env.NVIM_THEME_MODULE.."/?.lua;"..package.path; print(require("config.dotfiles_theme").resolve().colorscheme)' +qa 2>&1)"
[[ "$result" == everforest ]] || fail 'harmless native comment rejected'
printf '\nvim.cmd("bad")\n' >> "$home/.local/state/omarchy/current/theme/neovim.lua"
result="$(HOME="$home" NVIM_THEME_MODULE="$module_dir" nvim --headless -u NONE \
  '+lua package.path=vim.env.NVIM_THEME_MODULE.."/?.lua;"..package.path; print(require("config.dotfiles_theme").resolve().colorscheme)' +qa 2>&1)"
[[ "$result" == *tokyonight-night* && "$result" == *'spec differs'* ]] || fail 'changed native spec lacked fallback warning'
# The first failed reload must not mark the desired theme as applied.
result="$(HOME="$home" NVIM_THEME_MODULE="$module_dir" nvim --headless -u NONE \
  '+lua package.path=vim.env.NVIM_THEME_MODULE.."/?.lua;"..package.path; local m=require("config.dotfiles_theme"); local calls=0; vim.cmd.colorscheme=function() calls=calls+1; if calls==1 then error("temporary") end end; m.apply({colorscheme="retry"}); m.apply({colorscheme="retry"}); print("attempts="..calls)' +qa 2>&1)"
[[ "$result" == *attempts=2* ]] || fail 'failed theme application was not retried'
# The provision-time LazyVim spec must not request an uncloned theme or start a timer.
result="$(HOME="$home" DOTFILES_NVIM_PROVISIONING=1 NVIM_THEME_MODULE="$module_dir" nvim --headless -u NONE \
  '+lua package.path=vim.env.NVIM_THEME_MODULE.."/?.lua;"..package.path; local specs=dofile(vim.env.NVIM_THEME_MODULE.."/plugins/theme.lua"); local opts={}; specs[4].opts(nil,opts); print("provision="..opts.colorscheme)' +qa 2>&1)"
[[ "$result" == provision=habamax ]] || fail 'provision selected native colorscheme before plugin install'
# A changed native spec with the same slug must be applied once after success;
# failure keeps its identity pending until a later poll succeeds.
cp "$theme_dir/everforest/neovim.lua" "$home/.local/state/omarchy/current/theme/neovim.lua"
result="$(HOME="$home" NVIM_THEME_MODULE="$module_dir" nvim --headless -u NONE \
  '+lua package.path=vim.env.NVIM_THEME_MODULE.."/?.lua;"..package.path; local m=require("config.dotfiles_theme"); local calls=0; vim.cmd.colorscheme=function() calls=calls+1; if calls==1 then error("transient") end end; package.loaded.everforest={setup=function() end}; m.watch(); local path=vim.env.HOME.."/.local/state/omarchy/current/theme/neovim.lua"; local lines=vim.fn.readfile(path); table.insert(lines,"-- updated"); vim.fn.writefile(lines,path); vim.wait(3300); print("watch-attempts="..calls)' +qa 2>&1)"
[[ "$result" == *watch-attempts=2* ]] || fail "watcher did not retry changed same-slug native input: $result"
pass

printf 'PASS: Neovim area (%d groups)\n' "$TEST_COUNT"
