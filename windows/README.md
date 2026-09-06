# Windows setup

Windows setup runs manually in the guest, separately from `dotfiles.sh`, Stow, and the Linux adapters. Use a checkout on the guest's local disk. Windows PowerShell 5.1 is sufficient; PowerShell 7 is also supported.

## Install and configure

Install Microsoft App Installer (WinGet) if missing, then run:

```powershell
winget install --id Git.Git --exact --source winget
git clone https://github.com/MatthewssSmith1/dotfiles.git C:\dotfiles
cd C:\dotfiles
powershell -NoProfile -ExecutionPolicy Bypass -File windows\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File windows\install.ps1
```

`apps.json` is the application allowlist. Installation accepts package/source agreements, installs missing apps, and preserves existing versions. Run as your normal user and approve individual UAC prompts when required. A failure reports the package and exit code; resolve it and rerun. Updates are separate from bootstrap: use individual WinGet updates when needed.

| Tool | Owner / source |
| --- | --- |
| Git | WinGet `Git.Git` |
| mise | WinGet `jdx.mise` |
| jq (Bash test prerequisite) | WinGet `jqlang.jq` |
| GitHub CLI | WinGet `GitHub.cli` |
| Codex desktop | WinGet `9PLM9XGG6VKS`, `msstore` source; detected as `OpenAI.Codex` |
| Tailscale | WinGet `Tailscale.Tailscale` |
| Windows Terminal | WinGet `Microsoft.WindowsTerminal` |
| Zed IDE | WinGet `ZedIndustries.Zed` |
| FiraCode Nerd Font Mono | `install-font.ps1`, checksum-pinned Nerd Fonts archive |
| Node / npm / pnpm | mise; installed separately below; npm comes with Node |

All WinGet entries except Codex use the `winget` source. The font installer registers six Mono styles for the current user and caches the verified archive under `%LOCALAPPDATA%\dotfiles\cache`. It refuses to overwrite different existing font files.

Open Windows Terminal once to create its settings, then apply configuration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\apply.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File windows\apply.ps1
```

Apply adds WinGet Links and mise shims to the user PATH and merges `terminal/managed-settings.json` into Terminal settings. It preserves unrelated PATH entries, profiles, font options, schemes, actions, and keybindings. Only managed per-profile overrides are removed. Reapplying unchanged configuration writes nothing; dry-run writes nothing and displays the proposed result.

Restart Terminal and Codex to pick up PATH changes. If their parent process still has the old environment, sign out and back in. To refresh only the current PowerShell process:

```powershell
. .\windows\apply.ps1 -SessionOnly
```

## Node and pnpm

Install the Windows defaults separately after the base setup:

```powershell
mise use --global --fuzzy node@24 pnpm@12
node --version
npm.cmd --version
pnpm --version
```

This saves `node = "24"` and `pnpm = "12"` in the user mise configuration. Node 24 is the selected LTS line. Use `mise upgrade node pnpm` for deliberate updates within those major versions. Keep mise as the owner of both tools; npm is bundled with Node.

Project requirements take precedence over these defaults. The inspected `superbuilders/matts-vps-devbox` requires Node >=24.11 and uses an exact `packageManager` version in `package.json` alongside its lockfile. Keep that project pin exact even though the user defaults use major versions. Review the project's instructions and requirements when setting up another checkout.

The devbox documents Linux/WSL operator hosts. Runtime resolution and passing unit tests do not establish native Windows compatibility for its AWS and SSH operations. Infrastructure commands such as `pnpm connect`, `pnpm stop`, and deployments are separate from this setup.

## Sign-ins

Authenticate GitHub manually:

```powershell
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
gh auth status
```

Use the account with the required repository access and complete organization approval or SSO when prompted. Use the system credential store; investigate any plaintext-storage fallback. Windows uses native GitHub CLI authentication; the Ubuntu-only credential router in [GitHub access](../docs/tools/github-access.md) does not apply here.

Git commit name and email are separate from authentication. Configure your preferred identity before committing. Sign into Codex and Tailscale manually. AWS credentials, SSH keys, tailnet routing, and account switching remain separate from setup; never commit credentials or session files.

## Check and validate

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\check.ps1 -RequireRuntimes
powershell -NoProfile -ExecutionPolicy Bypass -File windows\test.ps1
```

Check reports missing apps, PATH drift, executable resolution, font registration/files, and Terminal drift. `-RequireRuntimes` also fails when Node/npm/pnpm are missing or resolve incorrectly. Omit it when checking only the base setup. Authentication and SST operational compatibility are not checked.

Native tests use temporary fixtures for dry-run, preservation, repeatability, backups, malformed settings, and PATH merging. For repository changes, follow [test routing](../tests/AGENTS.md); run the contract and Windows Terminal Bash suites in a supported Linux checkout when required. Confirm the font/theme visually in a new Terminal tab. Fresh-guest installation remains a separate validation step.

## Troubleshooting

- **Command not found:** restart the terminal application, or refresh the current PowerShell session with `apply.ps1 -SessionOnly`. Run checks in both an ordinary fresh shell and the agent's execution context.
- **Wrong Node executable:** Windows combines machine and user PATH, so a machine-level Node installation can precede mise shims. Resolve duplicate ownership. Codex's bundled tools are separate from the managed runtimes.
- **Restricted agent access:** an agent sandbox may not reach user-local WinGet or mise directories. Use approved execution rather than changing filesystem permissions or installing duplicate tools.
- **Terminal path ambiguity:** pass `-SettingsPath` to apply/check for a nonstandard installation. Stable packaged and unpackaged paths are detected automatically.
- **Terminal JSON comments or trailing commas:** PowerShell 5.1 requires strict JSON and stops before writing. Use an independently installed PowerShell 7 for JSONC parsing if needed.

SSH keybinding unbinds and modified Enter mappings are manual steps described in [Windows Terminal guidance](../docs/environments/windows-terminal.md).

## Rollback

User PATH backups are stored under `%LOCALAPPDATA%\dotfiles\backups` when PATH changes. The first Terminal change preserves `settings.json.bak`; later changes use unique backups. Restore the chosen backup after reviewing subsequent user edits.

Uninstall selected apps through Windows Settings or WinGet and the user font through Windows Fonts settings. These scripts do not change shell profiles, the default shell, or global execution policy. Host Docker, VM disks, `windows.boot`, and VM backups remain outside guest setup.
