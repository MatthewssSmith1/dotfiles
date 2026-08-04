#!/usr/bin/env bash
# Herdr regular-config ownership, reversible predecessor migration, and dispatch.

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_herdr="$TEST_ROOT/herdr"
cat > "$fake_herdr" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf 'herdr 0.7.5\n' ;;
  config) [[ "${2:-}" == check ]] ;;
  *) exit 1 ;;
esac
SCRIPT
chmod 0755 "$fake_herdr"

run_herdr_area() {
  local home="$1" profile="$2" operation="$3" fail_at="${4:-}" mode=apply
  [[ "$operation" != check ]] || mode=check
  [[ "$operation" != remove ]] || mode=remove
  HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
    SCRIPT_NAME=herdr-test SELECTED_PROFILE="$profile" MODE="$mode" DOTFILES_TESTING=1 \
    DOTFILES_TEST_HERDR_BIN="$fake_herdr" DOTFILES_TEST_FAIL_AT="$fail_at" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/provisioning.sh"
      source "$DOTFILES_DIR/lib/areas/herdr.sh"
      AREA_ORDER=(git bash tmux nvim zsh agents herdr)
      AREA_STATUS=([git]=ready [bash]=ready [tmux]=ready [nvim]=ready [zsh]=ready [agents]=ready [herdr]=ready)
      if [[ "$MODE" == remove ]]; then remove_herdr
      elif [[ "$MODE" == check ]]; then preflight_herdr
      else preflight_herdr; apply_herdr
      fi
    '
}

config_source="$REPO_DIR/packages/common/herdr/.config/dotfiles/herdr/config.toml"
grep -qF 'prefix = "ctrl+space"' "$config_source" || fail 'Herdr prefix is not Ctrl+Space'
grep -qF 'version_check = false' "$config_source" || fail 'Herdr update checks remain enabled'
grep -qF 'split_vertical = "prefix+v"' "$config_source" || fail 'Herdr vertical split key is missing'
grep -qF 'split_horizontal = "prefix+h"' "$config_source" || fail 'Herdr horizontal split key is missing'
grep -qF 'previous_workspace = "alt+up"' "$config_source" || fail 'Herdr workspace navigation is missing'
for profile in generic wsl omarchy; do
  grep -qxF 'herdr common/herdr' "$REPO_DIR/profiles/$profile.conf" || fail "$profile lacks the Herdr closure"
done
pass

# A fresh deployment creates only the regular live config; runtime siblings stay native.
home="$(new_home herdr-created)"
mkdir -p "$home/.config/herdr"
printf 'runtime\n' > "$home/.config/herdr/session.json"
cp -a "$home" "$TEST_ROOT/herdr-check-before"
run_herdr_area "$home" generic check >/dev/null
diff --no-dereference -r "$home" "$TEST_ROOT/herdr-check-before" >/dev/null || fail 'Herdr check mutated HOME'
run_herdr_area "$home" generic apply >/dev/null
cmp -s "$home/.config/herdr/config.toml" "$config_source" || fail 'managed Herdr config differs from source'
[[ -f "$home/.config/herdr/config.toml" && ! -L "$home/.config/herdr/config.toml" && \
  "$(stat -c %a -- "$home/.config/herdr/config.toml")" == 600 ]] || fail 'managed Herdr config is not a private regular file'
[[ "$(< "$home/.config/herdr/session.json")" == runtime ]] || fail 'Herdr runtime sibling changed'
state="$home/.local/state/dotfiles/v1/herdr.json"
jq -e '.profile == "generic" and .packages == ["common/herdr"] and .backups == [] and
  .attachments[0].id == "herdr-config-v1.created" and .attachments[0].path == ".config/herdr/config.toml"' \
  "$state" >/dev/null || fail 'created Herdr state is incorrect'
run_herdr_area "$home" generic check >/dev/null
run_herdr_area "$home" generic remove >/dev/null
[[ ! -e "$home/.config/herdr/config.toml" && -f "$home/.config/herdr/session.json" && ! -e "$state" ]] || \
  fail 'created Herdr removal changed runtime data or retained ownership'
pass

# The reviewed predecessor is backed up, replaced, and restored byte-for-byte with its mode.
home="$(new_home herdr-predecessor)"
mkdir -p "$home/.config/herdr"
printf '[ui]\nagent_panel_sort = "spaces"\n' > "$home/.config/herdr/config.toml"
chmod 0664 "$home/.config/herdr/config.toml"
cp -a "$home/.config/herdr/config.toml" "$TEST_ROOT/herdr-predecessor-original"
run_herdr_area "$home" wsl apply >/dev/null
state="$home/.local/state/dotfiles/v1/herdr.json"
backup_rel="$(jq -r '.backups[0]' "$state")"
[[ "$(jq -r '.attachments[0].id' "$state")" == herdr-config-v1.predecessor-664 ]] || fail 'predecessor origin was not recorded'
[[ -f "$home/$backup_rel" && "$(stat -c %a -- "$home/$backup_rel")" == 600 ]] || fail 'predecessor backup is unsafe'
cmp -s "$home/$backup_rel" "$TEST_ROOT/herdr-predecessor-original" || fail 'predecessor backup bytes changed'
run_herdr_area "$home" wsl remove >/dev/null
cmp -s "$home/.config/herdr/config.toml" "$TEST_ROOT/herdr-predecessor-original" || fail 'predecessor bytes were not restored'
[[ "$(stat -c %a -- "$home/.config/herdr/config.toml")" == 664 && ! -e "$home/$backup_rel" ]] || \
  fail 'predecessor mode or backup cleanup is wrong'
pass

# Unknown live configs refuse without mutation.
home="$(new_home herdr-conflict)"
mkdir -p "$home/.config/herdr"
printf 'unrelated = true\n' > "$home/.config/herdr/config.toml"
before="$(sha256sum "$home/.config/herdr/config.toml")"
if run_herdr_area "$home" omarchy apply >/dev/null 2>&1; then fail 'unrelated Herdr config was adopted'; fi
[[ "$before" == "$(sha256sum "$home/.config/herdr/config.toml")" && ! -e "$home/.local/state/dotfiles/v1/herdr.json" ]] || \
  fail 'Herdr conflict refusal mutated HOME'
pass

# Apply and removal faults restore exact pre-transaction trees.
home="$(new_home herdr-apply-rollback)"
mkdir -p "$home/.config/herdr"
printf '[ui]\nagent_panel_sort = "spaces"\n' > "$home/.config/herdr/config.toml"
chmod 0664 "$home/.config/herdr/config.toml"
cp -a "$home" "$TEST_ROOT/herdr-apply-before"
if run_herdr_area "$home" generic apply herdr-after-config >/dev/null 2>&1; then fail 'faulted Herdr apply succeeded'; fi
diff --no-dereference -r "$home" "$TEST_ROOT/herdr-apply-before" >/dev/null || fail 'Herdr apply rollback changed HOME'
run_herdr_area "$home" generic apply >/dev/null
cp -a "$home" "$TEST_ROOT/herdr-remove-before"
if run_herdr_area "$home" generic remove herdr-remove-after-config >/dev/null 2>&1; then fail 'faulted Herdr removal succeeded'; fi
diff --no-dereference -r "$home" "$TEST_ROOT/herdr-remove-before" >/dev/null || fail 'Herdr removal rollback changed HOME'
pass

printf 'PASS: Herdr area checks (%d groups)\n' "$TEST_COUNT"
