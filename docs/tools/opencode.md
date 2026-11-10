# OpenCode

## Ownership and runtime

OpenCode is optional and package-only on both Linux profiles. **OpenCode v2 is
required**; migrated with 2.0.32, current pin 2.1.2 (npm `@opencode/cli`). Dotfiles deploys configuration,
not an OpenCode installer or updater:

```text
~/.config/dotfiles/opencode/personal.jsonc
~/.config/dotfiles/opencode/work.jsonc
~/.config/dotfiles/opencode/cli.json
~/.config/dotfiles/opencode/runtime/index.js
~/.local/bin/opencode-personal
~/.local/bin/opencode-work
~/.local/share/dotfiles/bin/opencode-launch
```

Omarchy retains its native mise wrapper and all `~/.config/opencode/` files.
On Ubuntu or other Linux hosts, install v2 separately using a supported upstream
method before launching a managed profile. Use the same shared payload; there is
no parallel v1 implementation or automatic fallback. The launcher refuses v1.
Upgrade older hosts before deploying these native-v2 profiles.

OpenCode owns credentials, sessions, databases, service registration, plugins,
caches, package metadata, and generated preferences. Herdr owns its integration.
The agents area separately owns the global `AGENTS.md` bridge. Apply, check, and
remove are local/offline and never install runtimes or copy credentials/databases.

## Profiles and launching

```text
agent-profile               -> print personal or work
agent-profile personal|work -> persist and select immediately (OpenCode and Claude)
opencode                    -> selected profile in managed interactive Bash
c                           -> selected profile with --auto
c-personal / c-work         -> explicit named profile
opencode-personal           -> opencode-launch personal -> native v2
opencode-work               -> opencode-launch work -> native v2
```

The host-owned `~/.config/dotfiles/local/agent-profile` contains exactly
`personal` or `work` followed by LF. Missing, invalid, symlinked, or foreign-owned
state defaults new shells to personal. `agent-profile` writes an atomic mode-0600
replacement; existing shells retain their selection until switched/reloaded. Dotfiles
lifecycle commands never manage that file. The same selection drives `claude`; see
[Agents](agents.md#claude-code-settings). The work launcher uses an inherited
`TFY_API_KEY` or loads the host `truefoundry` bundle through `dotfiles-secret`, and
otherwise fails closed; see [Local Environment Bundles](secrets.md). Secrets stay
outside the repository. Personal falls back to native OpenCode when the optional
launcher is absent.

The launcher uses the first executable `opencode` on PATH, validates its major
version, supplies `OPENCODE_CONFIG`, and merges keybindings over the host's global
CLI preferences through `OPENCODE_CLI_CONFIG_CONTENT`. Inherited inline server
configuration, v1 TUI overrides, and server URL overrides are cleared.

Interactive, `run`, `mini`, `api`, `models`, and `auth` operations use private
servers (`--standalone`). This ensures the selected profile and work credential
environment reach the server, rather than reusing a service started by another
profile. **Private servers share normal OpenCode application data**: these profiles
are configuration choices, not separate accounts or security sandboxes. XDG paths
are not relocated. Explicit `--server` connections are rejected by named launchers.

Use `command opencode` for native administration (`service`, `debug`, `mcp`,
`session`, `stats`, `reload`, `pair`, `plugin`); named launchers reject these rather
than silently targeting a shared service with a different profile. Use `/mcps`
inside the chosen profile for MCP status/sign-in. `serve` and `acp` start their own
servers; runtime upgrade/uninstall remain native host operations. Managed config
disables OpenCode update checks, leaving runtime ownership with the host installer.

## Reviewed behavior

Personal uses native ChatGPT subscription OAuth and discovered OpenAI models;
no authentication plugin or OpenAI provider catalog is needed. Neither profile
forces a primary model. Both use **Build: blue** (`#7aa2f7`) and **Plan: orange**
(`#ff9e64`). Personal subagent defaults:

- `general`, `explore`, `compaction`: GPT-6.1 Sol Fast, medium.
- `posthog`: GPT-6.1 Sol, low; `title`: GPT-6 Luna, low.

**Work routes every model through TrueFoundry.** It declares the reviewed gateway
catalog via `aisdk:@ai-sdk/openai-compatible`, reads `TFY_API_KEY`, and native
provider policies deny every other provider, including ChatGPT OAuth. Catalog:
Claude Fable 5.1 and Haiku, Opus, and Sonnet 5.5 (`claude-group/`), Gemini 4 Argon
(`gemini-group/`), and GPT-6 Astra and GPT-6.1 Sol (`openai-group/`). All default to
medium effort with none/low/medium/high variants.

Gateway models are not in OpenCode's catalog, so they would fall back to 200k context and
32k output; each declares an explicit `limit` with the vendor maxima from models.dev:
Claude 1,000,000/128,000, GPT 1,050,000 (922,000 input)/128,000, Argon 1,048,576/32,768.
Lower `limit.context` if the gateway rejects long requests. Claude models set
`compatibility.cacheFormat: "anthropic"` because the OpenAI-compatible adapter otherwise
sends no prompt-cache markers.

Work subagents are split by capability, not model. Each agent's model is only a default:
the parent may pass `model` on a `subagent` call to run any catalog model. Defaults:

- `general`: Claude Opus 5.5, medium; `explore`, `compaction`, `posthog`: Claude Sonnet 5.5, medium.
- `title`: Claude Haiku 5.5, low.
- `review` (work only): GPT-6.1 Sol, high. A deny-by-default allow-list grants read, grep,
  glob, skill, and only `git diff`/`log`/`show`/`status` in the shell; no edits, web, or
  nested subagents. Its prompt returns a verdict, severity-ordered findings, and unverified areas.

Validate real gateway requests on the work host before relying on the profile.

The built-in `opencode.config.compatibility` plugin is disabled to avoid automatic
Claude Code/agents compatibility scanning. Shared skills are explicitly discovered
from `~/.agents/skills`; OpenCode-native skill discovery remains available.

Beyond the PostHog boundary below, V2's own permission defaults apply; the Codex
CLI is not blocked.

PostHog connects at startup, with Code Mode disabled so its tools retain the
`posthog_*` names used by the permission boundary. Those tools are denied globally
and allowed only for the custom read-only `posthog` subagent, which on work also cannot
start nested subagents. Primary agents delegate
through `subagent`; the specialist's prompt requires an explicit request for writes.
Use `/mcps` in the named profile to sign in. OAuth state remains OpenCode-owned.

Global config files (`config.json`, `opencode.json`, `opencode.jsonc`) may be absent.
Apply/check reject both v1 `plugin`/`provider` and v2 `plugins`/`providers` declarations
in existing globals to preserve reviewed profile boundaries. Other project,
injected, and managed configuration remains outside this area's validation.
The reviewed JSONC subset is full-line `//` comments and trailing commas.

## Terminal preferences and themes

V2 uses one global `~/.config/opencode/cli.json`, not layered `tui.json(c)` files.
The managed overlay contains keybindings only; host preferences and theme remain
host-owned. Newline: Ctrl/Shift/Alt+Enter or Ctrl+J. Stash: Ctrl+S; restore: Ctrl+Y;
clear: Ctrl+X K; exit: Ctrl+X Q. Conflicting queue shortcuts are disabled.

Omarchy's global CLI config uses the terminal-derived `system` theme. No palette
snapshot or second native theme selector is introduced.

On Ubuntu, both named launchers select the generated CLI overlay when the common
theme helper and its palette are available. It retains the shared keybindings and
sets `theme.name` to the explicit `dotfiles-host` palette discovered under the global
OpenCode `themes/` directory. Provider/profile settings and Herdr integration remain
inherited. Ubuntu OpenCode apply synchronizes that output. Quit and restart existing
sessions after changing themes; see [theme operations](theming.md#ubuntu-contract).
The v2 overlay path is covered by offline tests; visual acceptance on a v2 Ubuntu
host is still an operator check.

Omarchy broadcasts `SIGUSR2` to all `opencode` processes on theme changes. The small
managed server plugin absorbs that signal so a private server does not terminate;
the terminal client handles its own palette refresh. Its real directory is resolved
before loading because plugin roots cannot contain Stow entrypoints resolving outside
that root. Unlike the retired trial plugin, it does not rewrite shell/XDG environments.

## Lifecycle and migration

```bash
~/dotfiles/dotfiles.sh check opencode
~/dotfiles/dotfiles.sh apply opencode
~/dotfiles/dotfiles.sh check opencode
~/dotfiles/dotfiles.sh remove opencode
```

Apply/remove retire only exact symlinks from earlier managed layouts, including
the v1 TUI overlay and isolated `opencode-v2` trial links. Unrelated files and links
are preserved. Removal releases the seven current links, never native configuration,
the runtime, integration files, credentials, or application data.

The previous 2.0.18 trial's runtime under `~/.local/share/opencode-v2-runtime` and
data under `~/.local/share/opencode-v2/personal` are deliberately retained but unused.
Its history diverged from normal OpenCode after the initial v1 snapshot. Do not
overwrite the normal database with that snapshot or assume the histories synchronize.
Archive/export any needed trial sessions before separately removing those directories.

Restart a named profile after changing server settings. Do not restart an active
shared service merely to deploy these overlays. Acceptance includes model/agent
selection, permissions, shared skills, PostHog sign-in, Herdr session tracking,
mode colors, keybindings, theme switching, and work gateway requests on its host.

Validated on the initial 2.0.32 host: contract/OpenCode/CLI suites, apply/check,
personal TUI startup and Ctrl+X Q exit. Disposable servers loaded both profiles
without normalization warnings, exposed the configured blue/orange agents, excluded
the compatibility scanner, loaded the runtime plugin, and survived `SIGUSR2`.
These checks made no model requests and used no work credentials. Visual palette
acceptance, Herdr tracking, PostHog sign-in, and real TrueFoundry requests remain
operator checks; no compatibility claim is implied for the host-owned v1 Herdr TUI plugin.

Revalidated on Ubuntu with 2.1.2, installed through a host-local mise pin
(`~/.config/mise/config.toml`, not the shared tools area): apply/check, both launchers'
version gate, `models` on a private server, headless TUI startup, and `SIGUSR2`
survival once the runtime plugin had loaded. The first private-server starts after
upgrading failed twice with `Location plugins did not finish activating`; later
starts succeeded.
