#!/usr/bin/env bash
# Offline verification of the byte-pinned upstream snapshot tree: the pinned
# scope tables, accepted checksums, and every verify-side check used by
# `scripts/upstream verify` and by sync's candidate verification. Sourced by
# scripts/upstream after lib/common.sh with REPO_DIR and SCRIPT_NAME defined.

readonly SCHEMA_ID='https://github.com/MatthewssSmith1/dotfiles/blob/main/schemas/source-manifest.schema.json'

# Pinned upstream scope: which repositories sync may consume and which paths of
# each pinned commit become snapshot content. The reviewed proposal supplies
# only version-to-commit pins; this table is the documented inventory.
readonly OMARCHY_REPOSITORY='https://github.com/basecamp/omarchy'
readonly STARTER_REPOSITORY='https://github.com/LazyVim/starter'
readonly PKGS_REPOSITORY='https://github.com/omacom-io/omarchy-pkgs'

# id|source path|snapshot path|destination root|destination path
readonly OMARCHY_FILES=(
  'omarchy-git-config|config/git/config|packages/upstream/git/.config/git/config|home|.config/git/config'
  'omarchy-tmux-config|config/tmux/tmux.conf|packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf|home|.config/dotfiles/upstream/tmux/tmux.conf'
  'omarchy-starship-config|config/starship.toml|packages/upstream/starship/.config/starship.toml|home|.config/starship.toml'
  'omarchy-herdr-config|config/herdr/config.toml|packages/upstream/reference/omarchy/config/herdr/config.toml|reference|-'
  'omarchy-themed-neovim-template|default/themed/neovim.lua.tpl|packages/upstream/reference/omarchy/default/themed/neovim.lua.tpl|reference|-'
  'omarchy-theme-tokyo-night-colors|themes/tokyo-night/colors.toml|packages/upstream/reference/omarchy/themes/tokyo-night/colors.toml|reference|-'
  'omarchy-theme-tokyo-night-neovim|themes/tokyo-night/neovim.lua|packages/upstream/reference/omarchy/themes/tokyo-night/neovim.lua|reference|-'
)
readonly OMARCHY_TREE_ID_PREFIX='omarchy-bash'
readonly OMARCHY_TREE_PREFIX='default/bash'
readonly OMARCHY_TREE_SNAPSHOT_PREFIX='packages/upstream/reference/omarchy/default/bash'
# deployable id|reference id|source path|snapshot path|destination path|policy
readonly OMARCHY_BASH_DEPLOYABLE_FILES=(
  'omarchy-bash-deployable-shell|omarchy-bash-shell|default/bash/shell|packages/upstream/bash/.config/dotfiles/upstream/bash/shell|.config/dotfiles/upstream/bash/shell|none'
  'omarchy-bash-deployable-aliases|omarchy-bash-aliases|default/bash/aliases|packages/upstream/bash/.config/dotfiles/upstream/bash/aliases|.config/dotfiles/upstream/bash/aliases|ubuntu-bash-portability-policy'
  'omarchy-bash-deployable-fns-tmux|omarchy-bash-fns-tmux|default/bash/fns/tmux|packages/upstream/bash/.config/dotfiles/upstream/bash/fns/tmux|.config/dotfiles/upstream/bash/fns/tmux|ubuntu-bash-portability-policy'
  'omarchy-bash-deployable-inputrc|omarchy-bash-inputrc|default/bash/inputrc|packages/upstream/bash/.config/dotfiles/upstream/bash/inputrc|.config/dotfiles/upstream/bash/inputrc|none'
)

readonly STARTER_ID_PREFIX='lazyvim-starter'
readonly OVERLAY_ID_PREFIX='omarchy-nvim-overlay'
readonly OVERLAY_PREFIX='pkgbuilds/omarchy-nvim'
readonly OVERLAY_SUBTREES=('lua' 'plugin')
readonly OVERLAY_FILES=('lazyvim.json')
readonly NVIM_SNAPSHOT_PREFIX='packages/upstream/nvim/.config/nvim'
readonly NVIM_DESTINATION_PREFIX='.config/nvim'
readonly NVIM_INIT_POLICY_BLOB='b5ed50d32843ce277c75b3f8df8c0d151d83d049'
readonly NVIM_LAZY_POLICY_BLOB='2917c5139e4b4479c0f9156ddac803a6242864ec'
readonly LAZY_LOCK_ID='omarchy-nvim-lazy-lock'
readonly LAZY_LOCK_RELEASE='omarchy-nvim 2026.8.13-1'
readonly LAZY_LOCK_SNAPSHOT='packages/upstream/nvim/.config/nvim/lazy-lock.json'
readonly LAZY_LOCK_DESTINATION='.config/nvim/lazy-lock.json'
readonly LAZY_LOCK_SHA256='f8693f2607088055adef508221e288b378a8df97411e0d726cbdb672d963a8ca'
readonly NVIM_EVIDENCE_DIR='docs/artifacts/omarchy-nvim-2026.8.13-1'
readonly STABLE_DB_SHA256='343e0ad01825e9ef25b5def4dc5d0e10deb4ac50ffa38d28ad94f31eea23914d'
readonly PACKAGE_SHA256='ff7cca4d58198ef6ea0c16ff93bd0369b307a40fae4ed300f6a2a75bb444fe1f'
readonly SIGNATURE_SHA256='f369681f596df6107fc44d6c36cbfcb5228443ff4d001ef8d008320b8d8ea430'
readonly SIGNING_KEY_SHA256='15d6aac44df688165b2ea35fe0b23af239bbc66a6909c10a5c219e8d94b707de'
readonly STARTER_ARCHIVE_SHA256='d865d50211358358d3c3c1e356773c1e3de1e8964215d85eb1b4c77521e17488'

is_safe_relative_path() {
  local path="$1"
  local segment
  local -a segments

  [[ -n "$path" && "$path" != /* && "$path" != */ && "$path" != *'//'* && \
    "$path" != *[[:cntrl:]]* ]] || return 1
  IFS='/' read -r -a segments <<< "$path"
  ((${#segments[@]} > 0)) || return 1
  for segment in "${segments[@]}"; do
    [[ -n "$segment" && "$segment" != '.' && "$segment" != '..' ]] || return 1
  done
}

git_quiet() {
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git "$@"
}

hash_blob_file() {
  git_quiet hash-object --no-filters -- "$1"
}

hash_blob_stdin() {
  git_quiet hash-object --stdin
}

# Tests may use synthetic artifact records. Only the accepted real baseline
# is coupled to the signed-package evidence set beneath docs/artifacts/.
accepted_stable_artifact_present() {
  local manifest="$1"
  jq -e '
    any((.artifacts // [])[];
      .id == "omarchy-nvim-lazy-lock" and
      .provenance.trust == "verified signed stable package; archive omitted due size")
  ' "$manifest" >/dev/null
}

verify_nvim_artifact_evidence() {
  local root="$1" manifest="$2" evidence="$root/$NVIM_EVIDENCE_DIR"
  local evidence_file snapshot relative actual_signature_hash

  accepted_stable_artifact_present "$manifest" || return 0

  for evidence_file in README.md SHA256SUMS package.sig.b64 omarchy-signing-key.asc \
    repository.desc .PKGINFO .BUILDINFO retrieval.txt config.sha256; do
    [[ -f "$evidence/$evidence_file" && ! -L "$evidence/$evidence_file" ]] || \
      die "missing regular Neovim artifact evidence: $NVIM_EVIDENCE_DIR/$evidence_file"
  done
  grep -Fx "$STABLE_DB_SHA256  omarchy.db" "$evidence/SHA256SUMS" >/dev/null || \
    die 'stable repository database checksum evidence drifted'
  grep -Fx "$PACKAGE_SHA256  omarchy-nvim-2026.8.13-1-any.pkg.tar.zst" \
    "$evidence/SHA256SUMS" >/dev/null || die 'stable package checksum evidence drifted'
  grep -Fx "$SIGNATURE_SHA256  omarchy-nvim-2026.8.13-1-any.pkg.tar.zst.sig" \
    "$evidence/SHA256SUMS" >/dev/null || die 'stable package signature checksum evidence drifted'
  grep -Fx "$STARTER_ARCHIVE_SHA256  lazyvim-starter-803bc181d7c0d6d5eeba9274d9be49b287294d99.tar.gz" \
    "$evidence/SHA256SUMS" >/dev/null || die 'LazyVim starter archive checksum evidence drifted'
  actual_signature_hash="$(base64 -d "$evidence/package.sig.b64" | sha256sum | cut -d' ' -f1)"
  [[ "$actual_signature_hash" == "$SIGNATURE_SHA256" ]] || \
    die 'preserved detached signature bytes drifted'
  [[ "$(sha256_file "$evidence/omarchy-signing-key.asc")" == "$SIGNING_KEY_SHA256" ]] || \
    die 'preserved Omarchy signing key drifted'
  grep -Fx 'pkgver = 2026.8.13-1' "$evidence/.PKGINFO" >/dev/null || \
    die 'preserved package identity drifted'
  grep -Fx 'pkgbuild_sha256sum = c91107a63b402fd58c1a614fe67e2d9c8f9fe5da2638233b3eccbbd126c4b106' \
    "$evidence/.BUILDINFO" >/dev/null || die 'preserved PKGBUILD identity drifted'

  cmp -s "$evidence/config.sha256" <(
    while IFS= read -r snapshot; do
      relative="${snapshot#packages/upstream/nvim/.config/nvim/}"
      if jq -e --arg snapshot "$snapshot" '
        any(.sources[]; .snapshot == $snapshot and
          ((.transform | type) == "object" and .transform.type == "nvim-offline-bootstrap-policy"))
      ' "$manifest" >/dev/null; then
        grep -E "^[0-9a-f]{64}  ${relative//./\\.}$" "$evidence/config.sha256"
      else
        printf '%s  %s\n' "$(sha256_file "$root/$snapshot")" "$relative"
      fi
    done < <(jq -r '
      ([.sources[] | select(.snapshot | startswith("packages/upstream/nvim/.config/nvim/")) | .snapshot] +
       [(.artifacts // [])[] | select(.snapshot | startswith("packages/upstream/nvim/.config/nvim/")) | .snapshot])
      | sort[]
    ' "$manifest")
  ) || die 'committed Neovim snapshot differs from the signed-package extraction record'
}

validate_schema_file() {
  local schema="$1"

  [[ -f "$schema" && ! -L "$schema" ]] || die 'source manifest schema is missing or is not a regular file'
  jq empty "$schema" >/dev/null 2>&1 || die 'source manifest schema is malformed'
  jq -e --arg schema_id "$SCHEMA_ID" '
    .["$schema"] == "https://json-schema.org/draft/2020-12/schema" and
    .["$id"] == $schema_id and
    .type == "object" and
    .additionalProperties == false and
    .properties["$schema"].const == "../schemas/source-manifest.schema.json" and
    .properties.schema_version.const == 1 and
    .properties.snapshot_root.const == "packages/upstream"
  ' "$schema" >/dev/null || die 'source manifest schema is unsupported'
}

validate_manifest_file() {
  local manifest="$1"

  [[ -f "$manifest" && ! -L "$manifest" ]] || die 'source manifest is missing or is not a regular file'
  jq empty "$manifest" >/dev/null 2>&1 || die 'source manifest is malformed'
  jq -e '
    def keys_are($allowed): (keys | sort) == ($allowed | sort);
    def clean_string:
      type == "string" and length > 0 and (test("[[:cntrl:]]") | not);
    def git_mode: type == "string" and test("^100(644|755)$");
    def hex40: type == "string" and test("^[0-9a-f]{40}$");
    def hex64: type == "string" and test("^[0-9a-f]{64}$");
    def home_destination:
      type == "object" and keys_are(["root", "path", "mode"]) and
      .root == "home" and (.path | clean_string) and (.mode | git_mode);
    def reference_destination:
      type == "object" and keys_are(["root"]) and .root == "reference";
    def valid_transform:
      . == "none" or
      (type == "object" and keys_are(["type", "appended", "output_blob"]) and
        .type == "append" and
        (.appended | type == "string" and length > 0) and
        (.output_blob | hex40)) or
      (type == "object" and keys_are(["type", "replaces"]) and
        .type == "overwrite" and
        (.replaces | type == "object" and
          keys_are(["repository", "commit", "path", "blob", "mode"]) and
          (.repository | clean_string and test("^https://[^[:space:]]+$")) and
          (.commit | hex40) and
          (.path | clean_string) and
          (.blob | hex40) and
          (.mode | git_mode))) or
      (type == "object" and keys_are(["type", "output_blob"]) and
        (.type == "nvim-offline-bootstrap-policy" or
         .type == "ubuntu-bash-portability-policy") and (.output_blob | hex40));
    def valid_source:
      type == "object" and
      keys_are(["id", "repository", "release", "commit", "source", "snapshot", "destination", "transform"]) and
      (.id | clean_string and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
      (.repository | clean_string and test("^https://[^[:space:]]+$")) and
      (.release | clean_string) and
      (.commit | hex40) and
      (.source | type == "object" and keys_are(["path", "blob", "mode"])) and
      (.source.path | clean_string) and
      (.source.blob | hex40) and
      (.source.mode | git_mode) and
      (.snapshot | clean_string) and
      (.destination | (home_destination or reference_destination)) and
      (.transform | valid_transform) and
      ((.destination.root == "home") or (.transform == "none"));
    def valid_artifact:
      type == "object" and
      keys_are(["id", "release", "snapshot", "destination", "sha256", "provenance"]) and
      (.id | clean_string and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
      (.release | clean_string) and
      (.snapshot | clean_string) and
      (.destination | home_destination) and
      (.sha256 | hex64) and
      (.provenance | type == "object" and
        keys_are(["artifact", "artifact_sha256", "build_date", "extracted", "trust", "record"]) and
        (.artifact | clean_string) and
        (.artifact_sha256 | hex64) and
        (.build_date | clean_string) and
        (.extracted | clean_string) and
        (.trust | clean_string) and
        (.record | clean_string));
    type == "object" and
    ((keys - ["artifacts"]) | sort) == (["$schema", "schema_version", "snapshot_root", "sources"] | sort) and
    .["$schema"] == "../schemas/source-manifest.schema.json" and
    .schema_version == 1 and
    .snapshot_root == "packages/upstream" and
    (.sources | type == "array" and length > 0 and all(.[]; valid_source)) and
    ((has("artifacts") | not) or
      (.artifacts | type == "array" and length > 0 and all(.[]; valid_artifact))) and
    (([.sources[].id] + [(.artifacts // [])[].id]) as $ids |
      ($ids | length) == ($ids | unique | length)) and
    (([.sources[].snapshot] + [(.artifacts // [])[].snapshot]) as $snapshots |
      ($snapshots | length) == ($snapshots | unique | length)) and
    (([.sources[] | select(.destination.root == "home") | .destination.path] +
      [(.artifacts // [])[].destination.path]) as $targets |
      ($targets | length) == ($targets | unique | length))
  ' "$manifest" >/dev/null || die 'source manifest does not conform to schema version 1'

  jq -e --arg init_blob "$NVIM_INIT_POLICY_BLOB" --arg lazy_blob "$NVIM_LAZY_POLICY_BLOB" '
    ([.sources[] | select(.repository == "https://github.com/LazyVim/starter")] | length) == 0 or
    ([.sources[] | select((.transform | type) == "object" and
      .transform.type == "nvim-offline-bootstrap-policy") |
      [.id, .repository, .source.path, .snapshot, .transform.output_blob]] == [
        ["lazyvim-starter-init-lua", "https://github.com/LazyVim/starter", "init.lua",
          "packages/upstream/nvim/.config/nvim/init.lua", $init_blob],
        ["lazyvim-starter-lua-config-lazy-lua", "https://github.com/LazyVim/starter",
          "lua/config/lazy.lua", "packages/upstream/nvim/.config/nvim/lua/config/lazy.lua", $lazy_blob]
      ])
  ' "$manifest" >/dev/null || die 'Neovim offline bootstrap policy transform inventory is invalid'
}

# Verify one checkout-shaped tree (the active checkout or a sync candidate)
# against its own manifest, fully offline. Prints the recorded pins unless the
# second argument is 'quiet'.
verify_tree() {
  local root="$1"
  local report="${2:-report}"
  local schema="$root/schemas/source-manifest.schema.json"
  local manifest="$root/manifests/sources.json"

  validate_schema_file "$schema"
  validate_manifest_file "$manifest"

  local snapshot_root_rel snapshot_root
  snapshot_root_rel="$(jq -r '.snapshot_root' "$manifest")"
  is_safe_relative_path "$snapshot_root_rel" || die 'snapshot root is not a safe relative path'
  snapshot_root="$root/$snapshot_root_rel"
  [[ -d "$snapshot_root" && ! -L "$snapshot_root" ]] || \
    die 'snapshot root is missing or is not a directory'

  local -a ids=() repositories=() releases=() commits=() source_paths=() blobs=() source_modes=()
  local -a snapshot_paths=() destination_roots=() destination_paths=() destination_modes=()
  local -a transform_types=() appended_b64s=() output_blobs=()
  local id repository release commit source_path blob source_mode snapshot_path
  local destination_root destination_path destination_mode transform_type appended_b64 output_blob
  local replaces_path
  while IFS=$'\t' read -r id repository release commit source_path blob source_mode \
    snapshot_path destination_root destination_path destination_mode \
    transform_type appended_b64 output_blob replaces_path; do
    is_safe_relative_path "$source_path" || die "unsafe source path for $id: $source_path"
    is_safe_relative_path "$snapshot_path" || die "unsafe snapshot path for $id: $snapshot_path"
    [[ "$snapshot_path" == "$snapshot_root_rel/"* ]] || \
      die "snapshot path is outside $snapshot_root_rel for $id: $snapshot_path"
    case "$destination_root" in
      home)
        is_safe_relative_path "$destination_path" || \
          die "unsafe home-relative destination path for $id: $destination_path"
        [[ "$source_mode" == "$destination_mode" ]] || \
          die "source and destination modes differ for source $id"
        ;;
      reference) ;;
      *) die "unsupported destination root for $id" ;;
    esac
    case "$transform_type" in
      none|append|overwrite|nvim-offline-bootstrap-policy|ubuntu-bash-portability-policy) ;;
      *) die "unsupported transform for $id" ;;
    esac
    if [[ "$transform_type" == overwrite ]]; then
      is_safe_relative_path "$replaces_path" || \
        die "unsafe replaced source path for $id: $replaces_path"
    fi

    ids+=("$id")
    repositories+=("$repository")
    releases+=("$release")
    commits+=("$commit")
    source_paths+=("$source_path")
    blobs+=("$blob")
    source_modes+=("$source_mode")
    snapshot_paths+=("$snapshot_path")
    destination_roots+=("$destination_root")
    destination_paths+=("$destination_path")
    destination_modes+=("$destination_mode")
    transform_types+=("$transform_type")
    appended_b64s+=("$appended_b64")
    output_blobs+=("$output_blob")
  done < <(jq -r '.sources[] | [
    .id,
    .repository,
    .release,
    .commit,
    .source.path,
    .source.blob,
    .source.mode,
    .snapshot,
    .destination.root,
    (.destination.path // "-"),
    (.destination.mode // "-"),
    (if .transform == "none" then "none" else .transform.type end),
    (if (.transform | type) == "object" and .transform.type == "append"
      then (.transform.appended | @base64) else "-" end),
    (if (.transform | type) == "object" and
      (.transform.type == "append" or .transform.type == "nvim-offline-bootstrap-policy" or
       .transform.type == "ubuntu-bash-portability-policy")
      then .transform.output_blob else "-" end),
    (if (.transform | type) == "object" and .transform.type == "overwrite"
      then .transform.replaces.path else "-" end)
  ] | @tsv' "$manifest")

  local row deployable_id reference_id expected_source expected_snapshot expected_destination expected_policy
  for row in "${OMARCHY_BASH_DEPLOYABLE_FILES[@]}"; do
    IFS='|' read -r deployable_id reference_id expected_source expected_snapshot \
      expected_destination expected_policy <<< "$row"
    jq -e \
      --arg deployable_id "$deployable_id" \
      --arg reference_id "$reference_id" \
      --arg source "$expected_source" \
      --arg snapshot "$expected_snapshot" \
      --arg destination "$expected_destination" \
      --arg policy "$expected_policy" '
        ([.sources[] | select(.id == $deployable_id)] | length) == 1 and
        ([.sources[] | select(.id == $reference_id)] | length) == 1 and
        # Parenthesized so the bindings parse identically on jq 1.7 and 1.8.
        ((.sources[] | select(.id == $deployable_id)) as $deployable |
        (.sources[] | select(.id == $reference_id)) as $reference |
        $deployable.source.path == $source and
        $deployable.snapshot == $snapshot and
        $deployable.destination == {
          root: "home", path: $destination, mode: $deployable.source.mode
        } and
        (if $policy == "none" then $deployable.transform == "none"
         else $deployable.transform.type == $policy and
           ($deployable.transform.output_blob | test("^[0-9a-f]{40}$")) end) and
        $reference.snapshot == ("packages/upstream/reference/omarchy/" + $source) and
        $reference.destination == {root: "reference"} and
        $reference.transform == "none" and
        ($deployable | {repository, release, commit, source}) ==
          ($reference | {repository, release, commit, source}))
      ' "$manifest" >/dev/null || \
      die "deployable Bash source mapping is invalid for $deployable_id"
  done

  local -a artifact_ids=() artifact_releases=() artifact_snapshots=()
  local -a artifact_destinations=() artifact_modes=() artifact_hashes=() artifact_names=()
  local artifact_hash artifact_name
  while IFS=$'\t' read -r id release snapshot_path destination_path destination_mode \
    artifact_hash artifact_name; do
    is_safe_relative_path "$snapshot_path" || die "unsafe snapshot path for $id: $snapshot_path"
    [[ "$snapshot_path" == "$snapshot_root_rel/"* ]] || \
      die "snapshot path is outside $snapshot_root_rel for $id: $snapshot_path"
    is_safe_relative_path "$destination_path" || \
      die "unsafe home-relative destination path for $id: $destination_path"
    artifact_ids+=("$id")
    artifact_releases+=("$release")
    artifact_snapshots+=("$snapshot_path")
    artifact_destinations+=("$destination_path")
    artifact_modes+=("$destination_mode")
    artifact_hashes+=("$artifact_hash")
    artifact_names+=("$artifact_name")
    if [[ "$id" == "$LAZY_LOCK_ID" ]]; then
      [[ "$release" == "$LAZY_LOCK_RELEASE" && \
        "$snapshot_path" == "$LAZY_LOCK_SNAPSHOT" && \
        "$destination_path" == "$LAZY_LOCK_DESTINATION" && \
        "$destination_mode" == 100644 && "$artifact_hash" == "$LAZY_LOCK_SHA256" ]] || \
        die 'released lazy-lock artifact identity does not match the accepted baseline'
    fi
  done < <(jq -r '(.artifacts // [])[] | [
    .id,
    .release,
    .snapshot,
    .destination.path,
    .destination.mode,
    .sha256,
    .provenance.artifact
  ] | @tsv' "$manifest")

  local absolute_path relative_path package_file declared
  shopt -s nullglob dotglob globstar
  for absolute_path in "$snapshot_root"/**; do
    [[ -d "$absolute_path" && ! -L "$absolute_path" ]] && continue
    relative_path="${absolute_path#"$root/"}"
    # Deployment-framework package markers required by deployment.md live at the
    # top level of each upstream package root and are never snapshot content.
    package_file="${relative_path#"$snapshot_root_rel/"}"
    if [[ "$package_file" =~ ^[a-z0-9-]+/\.(stow-local-ignore|empty-package)$ ]]; then
      continue
    fi
    declared=false
    for snapshot_path in "${snapshot_paths[@]}" "${artifact_snapshots[@]}"; do
      if [[ "$relative_path" == "$snapshot_path" ]]; then
        declared=true
        break
      fi
    done
    [[ "$declared" == true ]] || die "undeclared snapshot inventory path: $relative_path"
  done
  shopt -u nullglob dotglob globstar

  local index actual_mode expected_mode actual_blob expected_blob
  local suffix_size file_size head_blob
  for index in "${!snapshot_paths[@]}"; do
    snapshot_path="${snapshot_paths[$index]}"
    absolute_path="$root/$snapshot_path"
    [[ -f "$absolute_path" && ! -L "$absolute_path" ]] || \
      die "missing or non-regular snapshot: $snapshot_path"

    if [[ "${destination_roots[$index]}" == home ]]; then
      expected_mode="${destination_modes[$index]#100}"
    else
      expected_mode="${source_modes[$index]#100}"
    fi
    actual_mode="$(stat -c '%a' -- "$absolute_path")"
    [[ "$actual_mode" == "$expected_mode" ]] || \
      die "snapshot mode drift for $snapshot_path: expected $expected_mode, found $actual_mode"

    case "${transform_types[$index]}" in
      append|nvim-offline-bootstrap-policy|ubuntu-bash-portability-policy) \
        expected_blob="${output_blobs[$index]}" ;;
      *) expected_blob="${blobs[$index]}" ;;
    esac
    actual_blob="$(hash_blob_file "$absolute_path")"
    [[ "$actual_blob" == "$expected_blob" ]] || \
      die "snapshot blob drift for $snapshot_path: expected $expected_blob, found $actual_blob"

    if [[ "${transform_types[$index]}" == append ]]; then
      # Replay the append transform offline: the snapshot must end with the
      # recorded appended bytes, and stripping them must reproduce the source.
      suffix_size="$(base64 -d <<< "${appended_b64s[$index]}" | wc -c)" || \
        die "unreadable appended bytes for ${ids[$index]}"
      file_size="$(stat -c '%s' -- "$absolute_path")"
      ((file_size > suffix_size)) || \
        die "recorded appended bytes are not a strict suffix of $snapshot_path"
      cmp -s <(tail -c "$suffix_size" -- "$absolute_path") \
        <(base64 -d <<< "${appended_b64s[$index]}") || \
        die "snapshot does not end with the recorded appended bytes: $snapshot_path"
      head_blob="$(head -c $((file_size - suffix_size)) -- "$absolute_path" | hash_blob_stdin)"
      [[ "$head_blob" == "${blobs[$index]}" ]] || \
        die "append transform replay drift for $snapshot_path: expected source blob ${blobs[$index]}, found $head_blob"
    fi
  done

  local reference_snapshot expected_policy
  for row in "${OMARCHY_BASH_DEPLOYABLE_FILES[@]}"; do
    IFS='|' read -r deployable_id reference_id expected_source expected_snapshot \
      expected_destination expected_policy <<< "$row"
    reference_snapshot="packages/upstream/reference/omarchy/$expected_source"
    if [[ "$expected_policy" == none ]]; then
      cmp -s -- "$root/$reference_snapshot" "$root/$expected_snapshot" || \
        die "deployable Bash payload differs from pinned reference: $expected_snapshot"
    else
      cmp -s -- "$root/$expected_snapshot" \
        <(apply_ubuntu_bash_portability_policy "$expected_source" "$root/$reference_snapshot") || \
        die "deployable Bash portability transform drifted: $expected_snapshot"
    fi
  done

  local actual_hash
  for index in "${!artifact_snapshots[@]}"; do
    snapshot_path="${artifact_snapshots[$index]}"
    absolute_path="$root/$snapshot_path"
    [[ -f "$absolute_path" && ! -L "$absolute_path" ]] || \
      die "missing or non-regular snapshot: $snapshot_path"
    expected_mode="${artifact_modes[$index]#100}"
    actual_mode="$(stat -c '%a' -- "$absolute_path")"
    [[ "$actual_mode" == "$expected_mode" ]] || \
      die "snapshot mode drift for $snapshot_path: expected $expected_mode, found $actual_mode"
    actual_hash="$(sha256_file "$absolute_path")"
    [[ "$actual_hash" == "${artifact_hashes[$index]}" ]] || \
      die "artifact hash drift for $snapshot_path: expected ${artifact_hashes[$index]}, found $actual_hash"
  done
  verify_nvim_artifact_evidence "$root" "$manifest"

  [[ "$report" != quiet ]] || return 0

  printf '[%s] verified %d pinned snapshot file(s)\n' "$SCRIPT_NAME" \
    "$((${#snapshot_paths[@]} + ${#artifact_snapshots[@]}))"
  for index in "${!ids[@]}"; do
    printf '[%s] pin %s: %s %s %s\n' \
      "$SCRIPT_NAME" "${ids[$index]}" "${repositories[$index]}" \
      "${releases[$index]}" "${commits[$index]}"
    printf '[%s] source %s: %s blob %s mode %s -> %s mode %s (transform: %s)\n' \
      "$SCRIPT_NAME" "${ids[$index]}" "${source_paths[$index]}" \
      "${blobs[$index]}" "${source_modes[$index]}" \
      "$(destination_label "${destination_roots[$index]}" "${destination_paths[$index]}")" \
      "${destination_modes[$index]}" "${transform_types[$index]}"
  done
  for index in "${!artifact_ids[@]}"; do
    printf '[%s] artifact %s: %s sha256 %s -> ~/%s (provenance: %s)\n' \
      "$SCRIPT_NAME" "${artifact_ids[$index]}" "${artifact_snapshots[$index]}" \
      "${artifact_hashes[$index]}" "${artifact_destinations[$index]}" \
      "${artifact_names[$index]}"
  done
}

destination_label() {
  local root="$1" path="$2"
  if [[ "$root" == home ]]; then
    printf '~/%s' "$path"
  else
    printf 'reference'
  fi
}

