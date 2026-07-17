# WSL

## Status

This document defines the accepted migration host and manual preparation. The
dotfiles behavior described here remains planned until its implementation stage
passes.

Notes for Ubuntu under WSL2 on Windows. The WSL profile inherits the generic
profile and adds only required WSL behavior; see
[Architecture](../omarchy-alignment/architecture.md). Key handling is a
client-terminal concern covered in
[Windows Terminal](windows-terminal.md).

## Current State And Target

The current WSL host was upgraded to Ubuntu 24.04 LTS and is the primary
implementation and validation host. Ubuntu 24.04 ships tmux 3.4, below the 3.5
baseline target; see
[tmux](../omarchy-alignment/tools/tmux.md#runtime-and-terminals).

## Completed Upgrade

The prior side-by-side rollout was superseded by a separately managed in-place
upgrade. The migration now assumes the validated Ubuntu 24.04 host. Export,
rollback, and distro lifecycle remain operator responsibilities outside
bootstrap.

The original preparation commands are retained below as general WSL recovery
reference.

### 1. Discover actual distro names

From PowerShell, inspect installed and available distributions instead of
assuming launcher names:

```powershell
wsl --list --verbose
wsl --list --online
```

Use the exact installed name in every export command and confirm the offered
Ubuntu 24.04 identifier before installation.

### 2. Export and verify the existing distro

From PowerShell, export a full restorable image of the distro before touching
anything:

```powershell
wsl --shutdown
wsl --export <ExistingDistroName> D:\backups\ubuntu-2204.tar
Get-FileHash D:\backups\ubuntu-2204.tar -Algorithm SHA256
```

Check destination free space first and store the digest with the backup. A WSL
export protects the distro filesystem; it does not necessarily preserve
registration metadata, launcher integration, or default-user selection.

Verify recoverability by importing the archive under a temporary name and
booting it before relying on the backup:

```powershell
wsl --import Ubuntu-restore-test C:\wsl\ubuntu-restore-test D:\backups\ubuntu-2204.tar
wsl --distribution Ubuntu-restore-test
```

Remove only that temporary verification import after checking important files.
Data stored on mounted Windows drives or other distributions requires its own
backup plan.

### 3. Install Ubuntu 24.04 beside 22.04

Install Ubuntu 24.04 as a second distro alongside the existing one. The
existing 22.04 distro stays untouched and bootable, reducing migration risk and
providing a clean bootstrap validation host:

```powershell
wsl --install Ubuntu-24.04
```

Migrate data deliberately through `\\wsl$\<DistroName>\...` paths or a shared
mounted drive. Keep 22.04 throughout implementation and stabilization.
Unregistering it is a separate destructive user decision and is never part of
bootstrap or this migration plan.

An in-place `do-release-upgrade` is not the accepted migration path. If chosen
outside this project, it requires its own prerequisites, rollback plan, and
post-upgrade validation.

## Manual Package Step

Bootstrap never uses `sudo`; it prints the exact command for missing
dependencies. The expected set on a fresh WSL host matches
[generic Linux](generic.md#manual-package-step). The locked Aqua tmux fallback
uses a verified prebuilt artifact and adds no source-build dependencies.
