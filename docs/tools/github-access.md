# GitHub Access

Status: provisional policy for repository review. Credential routing and the
constrained `gh` launcher described here are not implemented yet. Apply no PAT
or host-authentication step until its repository support is reviewed and ready.

Official documentation reviewed: 2026-08-29. Live UI not yet reconfirmed.

## Workflow

Before changing GitHub access, credentials, remotes, protected branches, or pull
requests:

1. Inventory the repository with the worksheet below.
2. Compare its live GitHub settings with the baseline and identify exceptions.
3. Apply reviewed ruleset and merge-setting changes from a trusted human admin
   session.
4. Record justified exceptions here before relying on them operationally.
5. Create or rotate PATs only after repository selection and local credential
   routing are ready.
6. Verify authentication, authorization, and ruleset behavior separately.

Completion: every selected repository has an explicit disposition; its live
settings match either the baseline or a recorded exception; credentials contain
only the reviewed repositories and permissions.

## Repository Worksheet

Review this repository and each immediate Git repository under `~/dev/*`.
Retain the worksheet host-locally if private repository names should not be
tracked.

```text
OWNER/REPOSITORY:
visibility:
default branch:
local fetch URL:
local push URL:
current protection/ruleset:
current merge methods:
automation or bypass actors:
Actions workflows present:
unattended workflow edits required:
releases published:
immutable release tag patterns:
PAT selected: yes/no
PAT owner: MatthewssSmith1/mimir-db/none
baseline exceptions and reason:
```

Stop before applying the baseline when the default branch is not `main`, an
automation actor relies on bypass or direct protected-branch writes, required
checks are already enforced, release tags have an established policy, or an
agent must modify `.github/workflows/**`.

## Repository Baseline

For each selected repository, use an active branch ruleset targeting the default
branch, which should be `main` before rollout:

- Require linear history.
- Block force pushes.
- Restrict deletions.
- Leave the bypass list empty.
- Leave restrict updates disabled so requested fast-forward updates remain
  possible.
- Do not initially require a pull request.
- Preserve existing required status checks until they are deliberately reviewed;
  do not add new required checks without a stable check contract.

Under repository pull-request merge settings:

- Enable squash merging.
- Enable rebase merging.
- Disable merge commits.

Prefer repository rulesets. Use an organization ruleset only when the current
GitHub plan supports it and all selected repositories share the same policy.
Inspect the resulting active rule and bypass list after saving it.

Direct fast-forward pushes to `main` are permitted by policy but remain an
explicit remote operation: an agent performs one only when Matt requests it.
Force pushes, protected-branch deletion, and nonlinear merges are prohibited.

## Release And Workflow Exceptions

`Contents: write` can create, update, and delete unprotected refs and GitHub
release objects. For release-producing repositories, inventory immutable tag
patterns and add appropriate tag rulesets. Tag protection does not make the
associated GitHub release object immutable; record that residual capability.

The baseline PAT omits `Workflows: write`. A PAT-authenticated push that adds or
modifies `.github/workflows/**` should fail. Handle such work through a separate
human-reviewed credential or explicitly revise this policy; do not silently
broaden every routine PAT.

## Fine-Grained PAT Profile

Use one fine-grained PAT per GitHub resource owner:

| Token label | Resource owner |
|---|---|
| `vps-git-personal` | `MatthewssSmith1` |
| `vps-git-mimir-db` | `mimir-db` |

For each token:

- Expiration: 90 days or the shorter organization maximum.
- Repository access: only worksheet entries marked selected for that owner.
- Repository permission `Contents`: read and write.
- Repository permission `Pull requests`: read and write.
- `Metadata`: mandatory read-only access supplied by GitHub.
- Every other optional repository, organization, and account permission: no
  access.

For `mimir-db`, inspect organization settings for fine-grained PAT access,
approval, and maximum lifetime. Matt administers these settings. Confirm GitHub
recognizes the acting account as an organization owner when relying on automatic
approval.

These limits are effective, not complete isolation:

- Selected-repository access limits private access and writes. Fine-grained PATs
  retain read access to public GitHub resources, including unselected public
  repositories.
- `Contents: write` includes ordinary Git writes plus unprotected refs, tags,
  and releases.
- GitHub treats a PAT holder as Matt's identity; it does not distinguish an
  instructed agent from an attacker holding the token.

Create tokens manually in GitHub's UI from a trusted device. Install each value
through the reviewed hidden-input or trusted-editor procedure once local routing
is ready. Keep values out of chat, command arguments, shell history, Git config,
remote URLs, logs, tracked files, and long-lived parent-shell environments.

## Git And CLI Policy

Selected GitHub remotes use canonical HTTPS URLs. Existing GitHub SSH keys,
credential helpers, repository-local overrides, and `gh` stored authentication
must not provide a broader write route.

The intended Ubuntu implementation routes HTTPS credentials by canonical owner
and fails closed for unknown GitHub contexts. It installs a real
`~/.local/bin/gh` executable found through `PATH`, not an alias or shell
function. The launcher will support a reviewed PR workflow, provisionally:

- `gh pr list`, `view`, `status`, and `diff`.
- `gh pr create`.
- `gh pr merge` using squash or rebase behavior.

The launcher will reject arbitrary API access, aliases, extensions, token
display, and repository, release, workflow, secret, variable, or administrative
mutation before reading a PAT bundle.

This launcher is deterministic routing and accidental-misuse control, not a
sandbox. A same-user process can invoke `/usr/bin/gh`, use another HTTP client,
or read a host-owned PAT bundle. After old stored authentication is revoked,
direct `/usr/bin/gh` should have no stored credential, but the Unix user remains
the actual trust boundary.

Until this implementation lands, inspect current behavior rather than assuming
the intended constraints exist. Never run `gh auth token` during an audit.

## UI Review

GitHub UI labels and locations can change. Follow the official documentation
linked below and update the review date when this procedure is reconfirmed.

For each repository:

1. Open **Settings > General > Pull Requests** and set the baseline merge
   methods.
2. Open **Settings > Rules > Rulesets** and inspect existing branch and tag
   rulesets before adding or editing one.
3. Create or update an active branch ruleset targeting the default branch with
   the baseline rules and no bypass actors.
4. Inspect the saved active rule and effective target.
5. Review tag rulesets where releases are published.
6. Record every exception in the worksheet before continuing.

For the organization, inspect **Settings > Personal access tokens** before token
creation. Verify access, approval, lifetime, and pending-request policy.

Apply protections before installing durable writer PATs. Keep an independent
trusted administrative session available while changing rules. If a live
negative probe is necessary, temporarily target a disposable branch with the
same reviewed rules; remove that target before deleting the branch.

## Verification

Distinguish failure classes:

- Authentication: GitHub received no usable credential.
- Authorization: the credential lacks repository selection or permission.
- Ruleset: authentication and permission succeeded, but repository policy
  rejected the operation.

Safe acceptance checks for each owner after implementation:

- Authenticated fetch succeeds for a selected repository.
- A feature-branch push succeeds.
- A requested direct fast-forward `main` push succeeds.
- PR creation and squash/rebase merge succeed.
- Merge-commit merge is unavailable or rejected.
- A write to an unselected repository fails; public read may still succeed.
- A PAT-authenticated workflow-file change fails without `Workflows: write`.
- Unknown-owner and insecure-HTTP credential requests fail without prompting or
  falling through to another GitHub credential.

Use a disposable protected target for force-update and deletion probes; do not
probe destructive behavior against a real default branch.

## Rotation And Incident Response

Normal rotation:

1. Create an equal-or-narrower replacement PAT for one owner.
2. Atomically replace only that owner's mode-`0600` host bundle.
3. Verify HTTPS fetch/push and supported PR operations.
4. Revoke the old PAT and confirm it no longer writes.
5. Update expiry reminders and review repository selection, permissions,
   rulesets, merge methods, and exceptions for drift.

Suspected compromise:

1. Revoke both VPS PATs from a trusted device.
2. Revoke VPS access and terminate sessions if host access may be compromised.
3. Review GitHub security/audit events, refs, merges, tags, releases, and token
   usage.
4. Compare protected history with trusted clones and backups; revert malicious
   additions without rewriting protected history.
5. Rotate every other secret readable by the compromised Unix user.
6. Rebuild the VPS from a trusted image before issuing replacement credentials.

## References

- [Managing organization PAT policy](https://docs.github.com/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization)
- [Managing fine-grained PAT requests](https://docs.github.com/organizations/managing-programmatic-access-to-your-organization/reviewing-and-revoking-personal-access-tokens-in-your-organization)
- [Creating a fine-grained PAT](https://docs.github.com/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [Available fine-grained PAT permissions](https://docs.github.com/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens)
- [Repository rulesets](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/managing-rulesets-for-a-repository)
- [Rules available for rulesets](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [Pull-request merge methods](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges)
- [`gh` environment variables](https://cli.github.com/manual/gh_help_environment)
