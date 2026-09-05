# Windows Reproducibility Handoff

## Resume Here

This records a planning conversation on the Omarchy host. Windows provisioning
has not been implemented. Read root `AGENTS.md`, `windows/AGENTS.md`, and this
document, inspect the guest, then confirm the implementation scope with the user.
This handoff is context, not authorization to install software or change accounts.

The user plans to install Git for Windows and Codex desktop manually, clone this
repository onto the guest's local Windows disk, and resume with Codex there.
Use a separate checkout, not the Omarchy checkout through the shared folder.
The document must be committed and pushed before a fresh clone can receive it.

## Purpose

Make a fresh Windows environment useful again through repeatable provisioning
and configuration, with deliberate manual sign-ins. Keep the implementation
small and separate from the Linux deployment engine.

Most application editing/building happens over SSH on Ubuntu VPSs. Codex desktop
in Windows is primarily for maintaining Windows itself. There is one important
local development-tool requirement: an SST-based GitHub repository manages an
AWS work VPS, including `pnpm connect` and `pnpm stop`. Windows therefore needs
Node.js/npm/pnpm even though application development remains on Linux. The
personal Hetzner VPS is always on. The SST repository's name, required versions,
and authentication workflow have not been supplied.

## Agreed Decisions

- Use PowerShell for Windows automation; do not introduce Bash wrappers or batch
  scripts to avoid PowerShell. The user's familiar alternative was Command Prompt
  (`cmd.exe`), not Git Bash. No default interactive-shell change was requested.
- Windows Terminal and some version of PowerShell are already installed. Detect
  them first; distinguish Windows PowerShell 5.1 from PowerShell 7 before choosing
  a supported script runtime or installing anything additional.
- Use WinGet for Windows applications and mise for Node/pnpm. npm comes with Node.
  Keep one owner per tool: no duplicate WinGet Node or separate Corepack pnpm owner.
- Include Git, mise, GitHub CLI, Codex desktop, Tailscale, Windows Terminal, and the
  Nerd Font referenced by the existing Terminal configuration in the setup scope.
  Detect existing installations and verify current official package sources.
- Preserve the existing Terminal theme and unrelated Terminal settings. Include
  actual font installation, not just a font-family reference.
- Tailscale installation is useful; sign-in remains manual. Tailnet connections,
  account switching, routing, and SSH connectivity design are outside this task.
- Keep GitHub, AWS, Codex, and SSH authentication separate from managed settings.
  Do not copy host credentials or commit guest authentication/session state.
- No WSL. Defer Python, .NET, Docker, and other runtimes until a concrete need.
- OpenCode failed in an earlier guest attempt; diagnosing it is outside scope.
  Use Codex desktop for this work without assuming a permanent OpenCode limitation.

## Proposed Shape

These are recommendations to validate in the guest, not an already-designed API:

- Explicit networked install step with a reviewed application allowlist. Avoid
  blanket upgrades of unrelated software.
- Offline, repeatable apply step for narrowly owned settings, with dry-run and
  safe backup behavior. Preserve unrelated user configuration.
- Read-only check step reporting missing tools, wrong executable resolution,
  missing font, and managed-setting drift.
- Small PowerShell scripts under `windows/`, not a generic cross-platform engine.
  Retain the existing separation from `dotfiles.sh` and Stow.
- Project runtime requirements take precedence over a global fallback. Inspect
  the SST repository's mise configuration, `package.json`, and lockfile before
  selecting Node/pnpm versions. Do not copy Linux-only mise backends unverified.
- Desktop applications may follow supported updates; reproducibility here means
  repeatable setup and explicit ownership, not a frozen Windows image.

## First Guest Session

1. Read the references below and inspect Git status. Inventory Windows version,
   PowerShell executables/versions, Terminal distribution/settings path, WinGet,
   Git, mise, Node/npm/pnpm, installed font, Codex desktop, and Tailscale. Report
   what exists without exposing credentials or making changes.
2. Resolve script runtime requirements and installation sources. Ask for the SST
   repository location if needed; read its requirements without executing tasks.
   End this step with explicit tool owners and runtime-version choices.
3. Confirm the bounded implementation with the user, then implement and validate
   natively in Windows. Keep Linux behavior unchanged.
4. Document fresh-install bootstrap, repeat application, checks, and manual
   sign-ins. Report test results and remaining manual checks separately.

## Acceptance Checks

- Fresh-shell and actual Codex agent commands resolve Git, mise, Node, npm, and
  pnpm to the intended installations. Interactive PowerShell profile activation
  alone is insufficient: agent commands may omit profiles, and desktop processes
  may retain old PATH values. Choose supported mise shims or explicit `mise exec`
  as appropriate; test rather than adding duplicate runtimes.
- Reapplying is harmless; dry-run leaves files unchanged; unrelated Terminal
  profiles, settings, and shell customizations survive. Font and theme render
  correctly in the guest.
- Existing apps are detected and reported accurately. Installation failures are
  actionable; setup does not silently require broad administrator privileges or
  weaken execution policy globally.
- Validate SST runtime compatibility using non-mutating checks first. Commands
  such as `pnpm connect`, `pnpm stop`, deployments, and other AWS operations need
  explicit user approval: they can change infrastructure, access, or costs.
- Run the focused suites required by `tests/AGENTS.md`, plus Windows-native
  behavioral checks for new scripts. Report skips honestly; Linux-only checks
  cannot establish native Windows behavior.

## References and Boundaries

- `windows/README.md`, `windows/terminal/`: existing Terminal implementation.
- `docs/environments/windows-terminal.md`: SSH-client behavior and manual bindings.
- `docs/architecture.md`: deployment ownership and platform separation.
- `.agents/skills/applying-dotfiles/SKILL.md` and its `windows.md`: configuration
  workflow; read before changing or applying managed settings.
- `docs/tools/github-access.md`: mandatory before credential setup or remote writes.
- `tests/AGENTS.md`: authoritative test routing.
- `packages/common/tools/.config/mise/conf.d/20-dotfiles-tools.toml` and
  `packages/ubuntu/tools/.config/mise/conf.d/30-dotfiles-tools-ubuntu.toml`:
  existing Linux policy to consult, not wholesale Windows payloads.
- `docs/environments/omarchy.md`: existing host VM launch safeguards and lifecycle
  guidance. Guest setup must not operate Docker, VM disks, or `windows.boot`.
  VM backups remain separate from dotfiles reproducibility.

