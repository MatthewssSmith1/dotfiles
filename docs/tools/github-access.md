# GitHub Access

Ubuntu Git deployment makes owner-routed HTTPS credentials and a constrained `gh` launcher available. They remain dormant until the host-local Git file includes the managed activation file. Omarchy receives neither payload.

Official documentation reviewed: 2026-08-29. Reconfirm live UI labels before changing repository settings.

## Inventory

| Repository                 | Visibility | Default | Routine PAT          |
| -------------------------- | ---------- | ------- | -------------------- |
| `MatthewssSmith1/dotfiles` | public     | `main`  | personal owner PAT   |
| `mimir-db/mimir-db`        | private    | `main`  | `mimir-db` owner PAT |
| `mimir-db/mimir-db-v0`     | private    | `main`  | `mimir-db` owner PAT |

All selected remotes use canonical credential-free `https://github.com/OWNER/REPOSITORY.git` URLs. The owner PATs are fine-grained, expire within 90 days, select only the repositories above, and grant only `Contents: read/write`, `Pull requests: read/write`, and mandatory Metadata read. `Workflows: write`, Administration, and every other optional permission remain disabled.

## Repository Rules

For public `MatthewssSmith1/dotfiles`, maintain an active ruleset on `main` that requires linear history, blocks force pushes, restricts deletion, has no bypass actors, and does not restrict ordinary updates. Squash and rebase merging are enabled; merge commits are disabled. PR and status-check requirements are not initially added.

The current unpaid plan does not enforce equivalent branch or tag rules on the two private repositories. Record them as unenforced, not unverified. Enable squash and rebase merging and disable merge commits, including on `mimir-db-v0`. Do not run destructive rejection probes there. Any writer PAT can still force-update or delete private refs and tags through Git or another API client. Revisit protections before expanding unattended use or after adopting a supporting plan.

Merge settings guide PR operations; they do not protect refs from direct writes. Agents push or merge only when Matt requests that remote operation. Force push, branch deletion, merge commits, and workflow-file writes are outside routine policy.

## Availability And Activation

Ubuntu deploys:

```text
~/.config/dotfiles/git/github-vps.conf
~/.local/share/dotfiles/bin/dotfiles-github-auth
~/.local/bin/gh
```

Without an activation marker, `~/.local/bin/gh` exact-execs `/usr/bin/gh` with untouched arguments and environment. It performs no policy parsing or bundle read. Activate both Git and `gh` by appending this to the real, safe `~/.config/dotfiles/local/git.conf` after generic helper settings:

```gitconfig
[include]
	path = ~/.config/dotfiles/git/github-vps.conf
```

The tracked file supplies the sole true activation marker, resets inherited GitHub helpers, installs the owner router, enables `useHttpPath`, and fails closed for HTTP. A marker from any other origin, duplicate marker, malformed activation, altered helper chain, or repository-local credential helper is an error. Active operation requires the regular fixed `/usr/bin/gh` backend.

Verify activation without displaying credentials:

```bash
command -v gh
git config --includes --show-origin --get-all dotfiles.github-vps.enabled
git config --includes --get-all credential.https://github.com.helper
git config --includes --get credential.https://github.com.useHttpPath
gh --help
dotfiles check git
```

The marker must be exactly `true` from `~/.config/dotfiles/git/github-vps.conf`; the helper chain must be one empty reset followed by `!~/.local/share/dotfiles/bin/dotfiles-github-auth`.

## Owner Bundles

Create the real EUID-owned directory as mode `0700` and install these files as regular EUID-owned mode-`0600` files through a trusted editor or hidden-input procedure:

```text
~/.config/dotfiles/local/secrets/github-MatthewssSmith1.env
~/.config/dotfiles/local/secrets/github-mimir-db.env
```

Each contains exactly one nonempty literal assignment:

```dotenv
GH_TOKEN=github_pat_placeholder
```

Replace the placeholder locally; never put a real value in chat, arguments, history, Git configuration, remotes, logs, tracked files, or a parent shell. Blank lines and lines beginning with `#` are ignored; exactly one other line must be a nonempty `GH_TOKEN` assignment. Extra assignments, duplicate names, control bytes, unsafe parents, links, broad modes, changed files, and oversized files fail closed. The Git-owned loader is independent of the generic Bash `dotfiles-secret` command.

Git credential `get` routes canonical HTTPS paths case-insensitively by owner. Unknown owners, malformed paths, HTTP, unsafe bundles, and missing bundles return `quit=1`, preventing fallback to a generic cache. `store` does nothing. `erase` does not alter bundles and instead directs the operator to rotate the PAT.

## Active `gh` Policy

`gh --help` is authoritative for the exact routine grammar. Its leading `MATT'S VPS GH POLICY` section applies even when native help lists additional features. Supported families are only `gh pr list`, `view`, `status`, `diff`, `create`, and `merge`. The launcher validates every argument and resolves one selected canonical repository before reading a bundle. Create and merge require one explicit `--repo OWNER/REPO`.

Merge requires exactly one of `--squash` or `--rebase` and exactly one full `--match-head-commit SHA`:

```bash
gh pr view 42 --json headRefOid
gh pr diff 42
gh pr merge 42 --squash --match-head-commit REVIEWED_SHA --repo OWNER/REPOSITORY
```

This rejects a changed head through native GitHub behavior. Browser, API, auth, alias, extension, repository, release, workflow, secret, variable, project, milestone, recovery, dry-run, merge-commit, administrator, auto-merge, and branch deletion flows are rejected before bundle access. Policy diagnostics begin `gh-vps-policy:`; policy rejection exits 77 and malformed invocation exits 64. Help and version need no token.

For active commands, repository selection is one validated repo option, then inherited `GH_REPO`, then one unambiguous canonical HTTPS `origin` from the current checkout or subdirectory. Malformed URLs, hostname-qualified values, aliases, credential URLs, HTTP/SSH remotes, malformed paths, and conflicting targets exit 64; valid but unselected repositories exit 77. Checkout URL rewriting, distinct fetch/push targets, multiplicity, unknown owners, and ambiguous origins fail closed. Inherited token, host, enterprise, config-directory, socket, and Git-config rerouting variables are removed. Only the selected `GH_TOKEN`, normalized `GH_REPO`, and `GH_HOST=github.com` reach fixed `/usr/bin/gh`; original command arguments and streams are preserved.

The launcher is deterministic routing and accidental-misuse control, not a sandbox. A same-user process can invoke `/usr/bin/gh`, another HTTP client, or read bundles. Direct backend bypass requires Matt's explicit instruction.

## Acceptance

After repository settings, activation, and manual PAT installation, verify one selected repository per owner: authenticated fetch, feature push, requested fast-forward `main` push, PR creation, reviewed-head squash/rebase merge, and workflow-file denial. Verify unknown-owner and unselected-private writes fail without prompts or helper fallback; public reads may still succeed. Do not run private force-push/deletion probes and never run `gh auth token` during audit.

After replacement routes pass, revoke the broader token formerly stored in `~/.config/gh/hosts.yml` from a trusted device. Confirm direct `/usr/bin/gh` has no stored authentication without displaying token data. Provider snapshots should exclude bundles where possible; otherwise treat snapshot access as token access.

## Deactivation And Rotation

Remove only the managed include from host-local `git.conf` to deactivate. The launcher immediately returns to untouched `/usr/bin/gh` pass-through and Git no longer receives the managed helper. This is rollback, not revocation; bundles and PATs remain valid until separately removed or revoked.

`dotfiles remove git` refuses while this activation include remains and does not edit the host-local file. Deactivate first, then remove the area.

Normal rotation:

1. Create an equal-or-narrower replacement for one owner.
2. Atomically replace only that owner's mode-`0600` bundle.
3. Verify Git and race-safe PR operations.
4. Revoke the old PAT and confirm it no longer writes.
5. Review repository selection, permissions, merge settings, rules, and expiry reminders.

Suspected compromise:

1. Revoke both VPS PATs from a trusted device.
2. Terminate VPS access and sessions when host access may be compromised.
3. Review security events, refs, merges, tags, releases, and token use.
4. Compare with trusted clones/backups and revert malicious additions.
5. Rotate every other same-user-readable secret and rebuild from a trusted image.

## References

- [Managing organization PAT policy](https://docs.github.com/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization)
- [Managing fine-grained PAT requests](https://docs.github.com/organizations/managing-programmatic-access-to-your-organization/reviewing-and-revoking-personal-access-tokens-in-your-organization)
- [Creating a fine-grained PAT](https://docs.github.com/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [Repository rulesets](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/managing-rulesets-for-a-repository)
- [Pull-request merge methods](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges)
- [`gh` environment variables](https://cli.github.com/manual/gh_help_environment)
