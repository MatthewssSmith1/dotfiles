#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

readonly MENU="$REPO_DIR/packages/omarchy/desktop/.config/dotfiles/omarchy/menu-dotfiles.jsonc"
readonly HELPER="$REPO_DIR/packages/omarchy/desktop/.local/libexec/dotfiles-menu"

menu_json="$TEST_ROOT/menu.json"
{ printf '{\n'; cat "$MENU"; printf '  "__sentinel": null\n}\n'; } > "$menu_json"
jq -e '
  del(.__sentinel) |
  (keys | sort) == ([
    "dotfiles", "dotfiles.apply", "dotfiles.areas", "dotfiles.check", "dotfiles.reference",
    "dotfiles.reference.help", "dotfiles.reference.list", "dotfiles.system",
    "dotfiles.system.amdgpu", "dotfiles.system.amdgpu.apply", "dotfiles.system.amdgpu.remove",
    "dotfiles.system.amdgpu.status", "dotfiles.system.fingerprint",
    "dotfiles.system.fingerprint.apply", "dotfiles.system.fingerprint.remove",
    "dotfiles.system.fingerprint.status", "dotfiles.system.prune"
  ] | sort) and
  .dotfiles == {icon:"󰒓",label:"Dotfiles",aliases:["dotfiles"]} and
  ."dotfiles.check".action == "\"$HOME/.local/libexec/dotfiles-menu\" check-all" and
  ."dotfiles.apply".action == "\"$HOME/.local/libexec/dotfiles-menu\" apply-all" and
  ."dotfiles.areas".action == "\"$HOME/.local/libexec/dotfiles-menu\" areas" and
  all(to_entries[]; (.value.label | type) == "string") and
  all(keys[]; startswith("dotfiles"))
' "$menu_json" >/dev/null || fail 'Dotfiles menu hierarchy, labels, icons, or routes differ'
! jq -e 'del(.__sentinel) | keys[] | select(test("(^|\\.)(theme|windows)(\\.|$)"))' "$menu_json" >/dev/null ||
  fail 'Dotfiles submenu duplicates sibling Theme or Windows routes'
[[ -f "$HELPER" && ! -L "$HELPER" && -x "$HELPER" ]] || fail 'Dotfiles menu helper is missing or unsafe'
pass

runtime="$TEST_ROOT/runtime"
checkout="$runtime/checkout"
helper="$checkout/packages/omarchy/desktop/.local/libexec/dotfiles-menu"
bin="$runtime/bin"
mkdir -p "$(dirname -- "$helper")" "$checkout/manifests" "$checkout/profiles" "$bin"
for command_name in bash readlink dirname mktemp rm tail mv; do
  ln -s "$(command -v "$command_name")" "$bin/$command_name"
done
cp "$HELPER" "$helper"
cp "$REPO_DIR/manifests/areas.tsv" "$checkout/manifests/areas.tsv"
: > "$checkout/profiles/omarchy.conf"
: > "$checkout/profiles/ubuntu.conf"
cat > "$checkout/dotfiles.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$DOTFILES_TRACE"
printf 'dotfiles output: %s\n' "$*"
exit "${COMMAND_STATUS:-0}"
SCRIPT
for name in dotfiles-amdgpu-ips dotfiles-polkit-fingerprint dotfiles-omarchy-prune; do
  cat > "$bin/$name" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\0' "${0##*/}" "$@" > "$SYSTEM_TRACE"
printf 'system output: %s %s\n' "${0##*/}" "$*"
exit "${COMMAND_STATUS:-0}"
SCRIPT
done
cat > "$bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$OMARCHY_TRACE"
if [[ "$1 $2" == 'menu select' ]]; then
  if [[ -n "${MENU_RESPONSES:-}" && -s "$MENU_RESPONSES" ]]; then
    IFS= read -r selection < "$MENU_RESPONSES"
    printf '%s\n' "$selection"
    temporary="$MENU_RESPONSES.next"
    tail -n +2 "$MENU_RESPONSES" > "$temporary"
    mv "$temporary" "$MENU_RESPONSES"
  else
    printf '%s' "${MENU_SELECTION:-}"
  fi
  exit "${MENU_STATUS:-0}"
fi
if [[ "$1 $2" == 'launch terminal' && "${RUN_TERMINAL:-}" == 1 ]]; then
  rm -f -- "$INSTALLED_HELPER"
  exec "$3" "${@:4}"
fi
exit "${OMARCHY_STATUS:-0}"
SCRIPT
cat > "$bin/notify-send" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$NOTIFY_TRACE"
SCRIPT
chmod 0755 "$helper" "$checkout/dotfiles.sh" "$bin/omarchy" "$bin/notify-send" \
  "$bin/dotfiles-amdgpu-ips" "$bin/dotfiles-polkit-fingerprint" "$bin/dotfiles-omarchy-prune"
ln -s "$checkout/dotfiles.sh" "$bin/dotfiles"
export DOTFILES_TRACE="$runtime/dotfiles.trace" SYSTEM_TRACE="$runtime/system.trace" OMARCHY_TRACE="$runtime/omarchy.trace"
export NOTIFY_TRACE="$runtime/notify.trace"

run_helper() {
  HOME="$runtime/home" PATH="$bin" COMMAND_STATUS="${COMMAND_STATUS:-0}" \
    MENU_SELECTION="${MENU_SELECTION:-}" MENU_STATUS="${MENU_STATUS:-0}" \
    MENU_RESPONSES="${MENU_RESPONSES:-}" \
    "$helper" "$@" <<< '' > "$runtime/stdout" 2> "$runtime/stderr"
}

# Public actions open a terminal with the already-resolved helper and exact ID.
for id in check-all apply-all amdgpu-status amdgpu-apply amdgpu-remove \
  fingerprint-status fingerprint-apply fingerprint-remove prune list help; do
  run_helper "$id" || fail "public Dotfiles menu action failed: $id"
  mapfile -d '' -t args < "$OMARCHY_TRACE"
  [[ "${args[0]} ${args[1]}" == 'launch terminal' && "${args[2]}" == "$helper" &&
    "${args[3]}" == --run && "${args[4]}" == "$id" && ${#args[@]} == 5 ]] ||
    fail "public Dotfiles menu terminal route differs: $id"
done
pass

# Terminal-side IDs dispatch exactly and preserve output plus exit status.
declare -A expected=(
  [check-all]='dotfiles check' [apply-all]='dotfiles apply' [list]='dotfiles list' [help]='dotfiles help'
  [amdgpu-status]='dotfiles-amdgpu-ips status' [amdgpu-apply]='dotfiles-amdgpu-ips apply'
  [amdgpu-remove]='dotfiles-amdgpu-ips remove' [fingerprint-status]='dotfiles-polkit-fingerprint status'
  [fingerprint-apply]='dotfiles-polkit-fingerprint apply' [fingerprint-remove]='dotfiles-polkit-fingerprint remove'
  [prune]='dotfiles-omarchy-prune'
)
for id in "${!expected[@]}"; do
  COMMAND_STATUS=23
  if run_helper --run "$id"; then fail "terminal action lost failure status: $id"; else status=$?; fi
  [[ "$status" == 23 && "$(< "$runtime/stdout")" == *"${expected[$id]}"* &&
    "$(< "$runtime/stdout")" == *'Exit code: 23'* ]] || fail "terminal action output/status differs: $id"
done
unset COMMAND_STATUS
for action in check apply remove; do
  run_helper --run "$action-area" desktop || fail "area terminal action failed: $action"
  mapfile -d '' -t area_args < "$DOTFILES_TRACE"
  [[ "${area_args[*]}" == "$action desktop" ]] || fail "area terminal dispatch differs: $action"
done
pass

# Area selection comes from the manifest, uses friendly labels, then dispatches
# the exact area command. Empty status-1 output is cancellation; other selector
# failures and unknown output are errors.
printf '%s\n' 'OpenCode (optional)' Check > "$runtime/menu.responses"
MENU_RESPONSES="$runtime/menu.responses" run_helper areas || fail 'optional area selection failed'
mapfile -d '' -t menu_args < "$OMARCHY_TRACE"
[[ "${menu_args[0]} ${menu_args[1]}" == 'launch terminal' && "${menu_args[2]}" == "$helper" &&
  "${menu_args[3]} ${menu_args[4]} ${menu_args[5]}" == '--run check-area opencode' ]] ||
  fail 'optional area action dispatch differs'
printf '%s\n' 'area|future-tools|optional' >> "$checkout/manifests/areas.tsv"
printf '%s\n' 'Future-tools (optional)' Apply > "$runtime/menu.responses"
MENU_RESPONSES="$runtime/menu.responses" run_helper areas || fail 'dynamic manifest area selection failed'
mapfile -d '' -t dynamic_args < "$OMARCHY_TRACE"
[[ "${dynamic_args[3]} ${dynamic_args[4]} ${dynamic_args[5]}" == '--run apply-area future-tools' ]] ||
  fail 'area choices are not derived from the current manifest'
MENU_SELECTION= MENU_STATUS=1 run_helper areas || fail 'selector cancellation was treated as an error'
for failure in status output; do
  if [[ "$failure" == status ]]; then MENU_SELECTION=selector-error MENU_STATUS=7; else MENU_SELECTION=unknown MENU_STATUS=0; fi
  if run_helper areas; then fail "selector $failure was accepted"; fi
done
rm -f "$OMARCHY_TRACE"
printf '%s\n' 'OpenCode (optional)' Invalid > "$runtime/menu.responses"
if MENU_RESPONSES="$runtime/menu.responses" run_helper areas; then fail 'invalid area action selection was accepted'; fi
mapfile -d '' -t invalid_action_args < "$OMARCHY_TRACE"
[[ "${invalid_action_args[0]} ${invalid_action_args[1]}" == 'menu select' ]] ||
  fail 'invalid area action launched a terminal command'
unset MENU_SELECTION MENU_STATUS
for args in 'unknown' '--run unknown' '--run check-area missing' '--run check-area desktop extra'; do
  read -r -a words <<< "$args"
  if run_helper "${words[@]}"; then fail "invalid helper invocation was accepted: $args"; fi
done
pass

# Missing graphical launcher reports both stderr and a desktop notification.
mv "$bin/omarchy" "$runtime/omarchy.saved"
if run_helper areas; then fail 'missing graphical launcher was accepted'; else status=$?; fi
[[ "$status" == 127 && "$(< "$runtime/stderr")" == *'required graphical launcher not found: omarchy'* ]] ||
  fail 'missing graphical launcher error/status differs'
mapfile -d '' -t notify_args < "$NOTIFY_TRACE"
[[ "${notify_args[*]}" == 'Dotfiles menu required graphical launcher not found: omarchy' ]] ||
  fail 'missing graphical launcher notification differs'
mv "$runtime/omarchy.saved" "$bin/omarchy"
pass

# Missing commands are distinct failures, and an already-resolved helper keeps
# running after its installed link is removed.
mv "$bin/dotfiles-amdgpu-ips" "$bin/dotfiles-amdgpu-ips.missing"
if run_helper --run amdgpu-status; then fail 'missing system helper was accepted'; else status=$?; fi
[[ "$status" == 127 && "$(< "$runtime/stderr")" == *'command not found: dotfiles-amdgpu-ips'* ]] ||
  fail 'missing helper error/status differs'
installed_helper="$runtime/home/.local/libexec/dotfiles-menu"
mkdir -p "$(dirname -- "$installed_helper")"
ln -s "$helper" "$installed_helper"
RUN_TERMINAL=1 INSTALLED_HELPER="$installed_helper" HOME="$runtime/home" PATH="$bin" \
  "$installed_helper" check-all <<< '' >/dev/null ||
  fail 'resolved helper did not survive removal of the installed link'
[[ ! -e "$installed_helper" && ! -L "$installed_helper" ]] || fail 'terminal fixture did not remove the installed helper link'
pass

printf 'PASS: %s Dotfiles desktop menu test groups\n' "$TEST_COUNT"
