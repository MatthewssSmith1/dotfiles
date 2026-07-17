# Architecture

## Goals

- Provide consistent development-tool behavior across native Omarchy, generic
  Linux, WSL, and remote Linux systems.
- Use real native Omarchy defaults where they are installed and managed by
  Omarchy.
- Reproduce important Omarchy behavior elsewhere from immutable, reviewed
  inputs.
- Keep upstream, portability, personal, and host-local changes distinguishable.
- Let each configuration area deploy and fail independently.
- Make updates and migrations explicit, reviewable, and recoverable.

## Non-Goals

The initial migration does not aim to:

- Reproduce Hyprland, Waybar, wallpaper, hardware, or other desktop setup.
- Preserve the current Kickstart Neovim configuration.
- Import existing zsh aliases, keybindings, or functions into Bash.
- Keep every current tmux binding.
- Make package installations byte-identical across platforms.
- Follow Omarchy's development branch automatically.
- Fetch live baseline configuration during bootstrap or shell startup.
- Implement portable coordinated theme switching.

## Configuration Layers

Configuration has four ordered conceptual layers:

```text
Omarchy baseline
+ portability adapter
+ shared personal configuration
+ host-local configuration
```

### Omarchy Baseline

The baseline is an untouched representation of selected upstream defaults. On
native Omarchy, the installed files are authoritative. Generic systems use
synchronized snapshots from pinned upstream inputs.

### Portability Adapter

The adapter contains only changes needed to make the baseline work outside its
native environment. It must not contain personal preferences.

### Shared Personal Configuration

The personal layer contains deliberate preferences that apply across machines
and override the baseline. Examples include Git's `main` default branch and
Neovim relative line numbers.

### Host-Local Configuration

The local layer contains untracked identity, machine-specific settings, and
environment-specific overrides. It must remain outside Stow payloads.

Not every tool requires all four physical files, but every change must have a
clear owner in this model.

## Locations

```text
~/dotfiles/                    Git checkout by convention
~/.config/dotfiles/            Active configuration fragments
~/.config/dotfiles/local/      Untracked host-local fragments
~/.local/state/dotfiles/       Applied profile and package state
```

The checkout convention is not a hard-coded dependency. Bootstrap resolves its
own location and must work from another path.

Tracked baseline, adapter, and personal files under `~/.config/dotfiles/` are
normally Stow links. `local/` is always a real, untracked directory. Git
identity is a deliberate exception stored as a real `~/.gitconfig.local` file.

## Profiles

| Profile | Baseline behavior |
|---------|-------------------|
| Omarchy | Use installed native defaults and attach shared layers safely |
| Generic | Deploy pinned snapshots plus generic portability adapters |
| WSL | Inherit Generic and add only required WSL behavior |

Profiles describe the host a configuration is deployed on. The client
terminal is a separate concern: Windows Terminal guidance in
[`docs/environments/windows-terminal.md`](../environments/windows-terminal.md)
applies to any host reached from Windows Terminal, including generic VPSs
over SSH, not only the WSL profile.

The primary implementation and validation host is the upgraded Ubuntu 24.04
WSL distro. See [WSL](../environments/wsl.md).

### Detection Signals

Bootstrap derives host facts without consulting saved deployment state:

| Fact | Authoritative signal |
|------|----------------------|
| Native Omarchy | Both `~/.local/share/omarchy/version` is a regular file and `~/.local/share/omarchy/bin/omarchy-version` is executable |
| WSL | Lowercased `/proc/sys/kernel/osrelease` contains `microsoft` |
| Linux distribution | `ID` and `VERSION_ID` parsed from `/etc/os-release` without executing it |

A partial Omarchy installation, where only one Omarchy signal exists, is an
error rather than a generic fallback. Simultaneous valid Omarchy and WSL
signals are an unsupported conflict. WSL environment variables such as
`WSL_INTEROP` are diagnostic only because they may be absent in some process
contexts.

Automatic selection follows this order:

| Host facts | Selected profile | Support status |
|------------|------------------|----------------|
| Valid Omarchy, not WSL | Omarchy | Supported |
| WSL plus Ubuntu 24.04 or newer | WSL | Primary target |
| Non-WSL Linux plus Ubuntu 24.04 or newer | Generic | Primary target |
| WSL plus another distribution or older Ubuntu | WSL | Detected but unsupported for mutating apply |
| Other Linux | Generic | Detected but not initially validated |
| Non-Linux or conflicting signals | None | Unsupported |

`--check` reports detected-but-unsupported hosts without mutation. Mutating
apply refuses them. Portable files should remain distro-neutral where
practical, but support for another distribution is accepted only after its
dependency and behavior tests exist.

### Explicit Overrides

An explicit `--profile` changes selection only where the host can safely
support that profile:

| Detected host | `omarchy` | `wsl` | `generic` |
|---------------|-----------|-------|-----------|
| Omarchy | Allow | Reject | Reject |
| Supported WSL | Reject | Allow | Allow with a warning that WSL adapters are omitted |
| Supported generic Linux | Reject | Reject | Allow |
| Unsupported or conflicting | Reject | Reject | Reject |

Profile names are lowercase and exact. Bootstrap re-detects host facts on every
run; state is used for cleanup and mismatch refusal, never as detection
authority.

## Areas

The default areas are:

- Git
- Bash and related shell tools
- tmux
- Neovim
- Transitional zsh configuration

No `--area` selection means all default areas. Repeated `--area` options select
only those areas. Omitting a previously deployed area does not remove it. A
conflict in one selected area must not prevent an unrelated area from being
deployed independently.

## Ownership Boundaries

- Omarchy owns native refresh-managed baseline files and native development
  packages.
- This repository owns synchronized generic baselines, portability adapters,
  shared personal layers, deployment metadata, and guarded attachment content.
- The host owns local identity, local overrides, credentials, and unrelated
  regular files.
- Platform package managers own stable generic CLI dependencies where
  practical.
- Mise owns workstation language runtimes and approved user-scoped tools. Lean
  into mise wherever it can absorb tool-management complexity, including
  locked versions, user-scoped installs without `sudo`, and verified prebuilt
  tools, rather than inventing bespoke installers.
- Projects retain higher precedence through their own mise and tool files.
  Vite+ is project-owned through those files and has no global bootstrap owner.
- OpenCode and `opencode-openai-codex-auth` remain host-owned and untouched,
  pending a separately reviewed later lifecycle and preservation proof.

Executable ownership checks cover inherited exported functions, candidates on
bootstrap's effective `PATH`, mise resolution from neutral and controlled
project directories, and, after Stage 6, the managed interactive shell.
Unexported aliases and functions in an arbitrary parent shell are not inherited;
bootstrap does not parse unrelated startup files in an attempt to infer them.

Native refresh-managed destinations must remain regular files rather than
links into this checkout. Concrete attachment and executable rules are in
[Deployment](deployment.md).

## Architecture Acceptance Criteria

- Each deployed file or managed block has one identifiable owner and layer.
- Profiles produce the intended baseline without hiding host mismatches.
- Areas can be selected, installed, checked, and removed independently.
- Profile detection and every override produce deterministic diagnostics.
- A profile change is refused until existing deployment state is removed
  explicitly.
- No host-local or credential file is linked into the checkout.
- Native refreshes can replace native baselines without overwriting shared
  personal source files.
- Normal startup and bootstrap do not silently update upstream baselines.
