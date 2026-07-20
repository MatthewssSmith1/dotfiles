#!/usr/bin/env bash

set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fail() { printf 'stage8_nvim_readiness_test: %s\n' "$1" >&2; exit 1; }

[[ "$(awk -F'|' '$1 == "area" && $2 == "nvim" {print $3}' "$REPO_DIR/manifests/areas.tsv")" == framework ]] ||
  fail 'the live Neovim readiness row is not framework'
for profile in generic wsl; do
  [[ "$(awk '$1 == "nvim" {print $2}' "$REPO_DIR/profiles/$profile.conf")" == \
    upstream/nvim,generic/nvim,common/nvim ]] || fail "$profile future-ready closure is incomplete"
done
[[ "$(awk '$1 == "nvim" {print $2}' "$REPO_DIR/profiles/omarchy.conf")" == common/nvim ]] ||
  fail 'native profile unexpectedly includes the deferred upstream/generic adapter'

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
home="$fixture/home"
config="$home/xdg/config/nvim"
data="$home/xdg/data/nvim"
mkdir -p "$config" "$data/lazy/lazy.nvim/lua/lazy/core" "$home/.config/dotfiles/nvim" \
  "$home/.local/state/dotfiles/v1" "$fixture/bin"
cp -a "$REPO_DIR/packages/upstream/nvim/.config/nvim/." "$config/"
cp -a "$REPO_DIR/packages/generic/nvim/.config/nvim/." "$config/"
cp "$REPO_DIR/packages/generic/nvim/.config/dotfiles/nvim/generic.lua" "$home/.config/dotfiles/nvim/generic.lua"
cp "$REPO_DIR/packages/common/nvim/.config/dotfiles/nvim/personal.lua" "$home/.config/dotfiles/nvim/personal.lua"

cat > "$data/lazy/lazy.nvim/lua/lazy/init.lua" <<'LUA'
local M = {}
function M.setup(opts)
  assert(opts.install.missing == false, "missing plugin installation is enabled")
  assert(opts.checker.enabled == false, "Lazy checker is enabled")
  assert(opts.rocks.enabled == false, "Lua rocks are enabled")
  assert(opts.local_spec == true, "project-local specs are disabled")

  local policy = dofile(vim.fn.stdpath("config") .. "/lua/plugins/dotfiles-runtime-policy.lua")
  local seen = {}
  for _, spec in ipairs(policy) do
    seen[spec[1]] = spec
  end
  for _, name in ipairs({ "mason-org/mason.nvim", "nvim-treesitter/nvim-treesitter" }) do
    local spec = assert(seen[name], "missing runtime policy for " .. name)
    assert(spec.build == false, name .. " retains an automatic build")
    local values = { ensure_installed = { "network-sentinel" } }
    spec.opts(nil, values)
    assert(#values.ensure_installed == 0, name .. " retains automatic installers")
  end
  assert(seen["saghen/blink.cmp"].opts.fuzzy.prebuilt_binaries.download == false,
    "Blink binary download is enabled")
  package.loaded["lazy.core.config"] = {
    plugins = { local_project = { url = "https://example.invalid/project.git", dir = vim.fn.stdpath("data") .. "/missing-local" } },
  }
  vim.fn.writefile({ "runtime-policy-ok" }, vim.env.STAGE8_REPORT)
end
return M
LUA
cat > "$data/lazy/lazy.nvim/lua/lazy/core/config.lua" <<'LUA'
return package.loaded["lazy.core.config"] or { plugins = {} }
LUA
git -C "$data/lazy/lazy.nvim" init -q
git -C "$data/lazy/lazy.nvim" -c user.name=test -c user.email=test@example.invalid add .
git -C "$data/lazy/lazy.nvim" -c user.name=test -c user.email=test@example.invalid commit -qm locked
lazy_commit="$(git -C "$data/lazy/lazy.nvim" rev-parse HEAD)"
jq -cn --arg commit "$lazy_commit" '{"lazy.nvim":{branch:"main",commit:$commit}}' > "$config/lazy-lock.json"
lock_hash="$(sha256sum "$config/lazy-lock.json" | cut -d' ' -f1)"
jq -cn --arg hash "$lock_hash" \
  '{schema_version:1,area:"nvim",profile:"generic",restored_lock_sha256:$hash}' \
  > "$home/.local/state/dotfiles/v1/nvim.json"

real_git="$(command -v git)"
cat > "$fixture/bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
for arg in "$@"; do
  case "$arg" in clone|fetch|pull|push|ls-remote|submodule)
    printf '%s\n' "$*" >> "$STAGE8_NETWORK_LOG"
    exit 97
  esac
done
exec "$STAGE8_REAL_GIT" "$@"
EOF
for command in curl wget; do
  cat > "$fixture/bin/$command" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "$STAGE8_NETWORK_LOG"
exit 97
EOF
  chmod 0755 "$fixture/bin/$command"
done
chmod 0755 "$fixture/bin/git"
: > "$fixture/network.log"

HOME="$home" XDG_CONFIG_HOME="$home/xdg/config" XDG_DATA_HOME="$home/xdg/data" \
  XDG_STATE_HOME="$home/xdg/state" XDG_CACHE_HOME="$home/xdg/cache" \
  PATH="$fixture/bin:$PATH" STAGE8_REAL_GIT="$real_git" STAGE8_NETWORK_LOG="$fixture/network.log" \
  STAGE8_REPORT="$fixture/report" nvim --headless -u "$config/init.lua" -i NONE +qa >/dev/null 2>"$fixture/nvim.err" || {
    cat "$fixture/nvim.err" >&2
    fail 'isolated real Neovim startup failed'
  }
[[ "$(< "$fixture/report")" == runtime-policy-ok ]] || fail 'real startup did not evaluate runtime policy'
[[ ! -s "$fixture/network.log" ]] || fail 'ordinary restored startup attempted a network-capable command'

# Native remains deferred even in a synthetic future-ready manifest.
if HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
  SCRIPT_NAME=stage8-ready SELECTED_PROFILE=omarchy DOTFILES_TESTING=1 DOTFILES_TEST_NVIM_BIN="$(command -v nvim)" \
  bash -c 'set -Eeuo pipefail; source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh";
    source "$DOTFILES_DIR/lib/provisioning.sh"; source "$DOTFILES_DIR/lib/areas/nvim.sh"; preflight_nvim' \
  >/dev/null 2>&1; then
  fail 'future readiness admitted native Omarchy Neovim before Stage 9'
fi

printf 'stage8_nvim_readiness_test: PASS\n'
