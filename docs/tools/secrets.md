# Local Environment Bundles

Ubuntu Bash deploys `dotfiles-secret`, an offline launcher that passes
one host-owned environment assignment file to one child process. The repository
owns the launcher and format contract. The host owns every real bundle and any
application wrapper; dotfiles never creates, reads, copies, backs up, or
removes them.

GitHub VPS PAT bundles use the same safety principles but are loaded by the
independent Git-owned `dotfiles-github-auth` executable. Their exact names and
single-`GH_TOKEN` format are documented in [GitHub Access](github-access.md);
they are not generic `dotfiles-secret` bundles.

## Interface

```text
dotfiles-secret exec-env <bundle-name> -- <command> [args...]
dotfiles-secret check-env <bundle-name>
```

`exec-env` validates the complete bundle, overlays its assignments on the
inherited environment, and replaces itself with the requested command.
Arguments, signals, and child status are preserved. Bundle assignments override
inherited names only in the child; the interactive parent shell is unchanged.
`check-env` performs the same bundle validation, prints only `valid`, and does
not run a child. Neither operation displays bundle names or values.

Bundle names match `^[A-Za-z0-9][A-Za-z0-9._-]*$`, are at most 128 bytes, and
cannot be `.` or `..`. They are identifiers, not paths. A name resolves only to:

```text
~/.config/dotfiles/local/secrets/<bundle-name>.env
```

`HOME` and each directory through `local/` must be canonical, real,
EUID-owned, and not group- or other-writable. `secrets/` must additionally have
exact mode `0700`. A bundle must be a readable, nonempty, EUID-owned regular
non-symlink file with exact mode `0600`, no larger than 64 KiB. Unsafe or
changed paths fail closed.

## Assignment Format

Bundles are data and are never sourced or evaluated. Records use this exact
environment assignment format:

```dotenv
# Values remain literal.
TFY_API_KEY=example-placeholder
TOKEN_WITH_EQUALS=abc=def==
LITERAL_DOLLAR=$NOT_EXPANDED
VALUE_WITH_HASH=abc#still-part-of-the-value
EMPTY_VALUE=
```

Records are separated by LF; the final LF is optional. Blank lines and lines
whose first byte is `#` are ignored. Every other line splits at its first `=`.
Names match `^[A-Za-z_][A-Za-z0-9_]*$`; values are all literal bytes after that
separator, including spaces, additional `=`, `#`, dollar signs, backticks,
quotes, and backslashes. Empty values are valid. Duplicate names, NUL, CR,
other C0 controls except LF, more than 256 assignments, and a file with no
assignments are rejected.

There is no `export` prefix, quote removal, escaping, interpolation, command
substitution, inline comment, multiline value, or shell syntax. Prefer one
bundle per application or trust boundary rather than one global bundle.

## OpenCode Work Wrapper

Managed interactive Bash already routes plain `opencode` through the personal
profile. The host-owned `~/.config/dotfiles/local/bash.sh` may lazily inject the
work credential by overriding only the named work launcher:

```bash
opencode-work() {
  local launcher="$HOME/.local/share/dotfiles/bin/opencode-launch"
  if [[ ! -x "$launcher" ]]; then
    printf '%s\n' 'opencode work launcher is unavailable' >&2
    return 127
  fi
  command dotfiles-secret exec-env opencode -- "$launcher" work "$@"
}
```

Sourcing the host-local file performs no bundle read or network operation.
Calling `opencode-work` reads only `opencode.env`; plain `opencode`,
`opencode-personal`, and the tracked `c='opencode --auto'` alias remain personal
and do not receive the work credential. Do not define a host-local `opencode()`
unless intentionally replacing managed personal-default routing.

## Host Setup And Rotation

Create `~/.config/dotfiles/local/secrets/` as a real mode-`0700` directory. With
`umask 077`, create `opencode.env` using a trusted editor or input method that
does not place its value in command arguments, shell history, or repository
files, then verify exact mode `0600` and user ownership. Add the work wrapper to the
real host-local Bash file, start a new managed interactive Bash, and run:

```bash
dotfiles-secret check-env opencode
```

Then verify a real OpenCode launch without printing or logging the value. For
rotation, write a new mode-`0600` file in the same private directory and
atomically rename it over `opencode.env`. Each invocation rereads the bundle;
removing it makes future launches fail closed.

Bundles persist until the host rotates or removes them. Root, the VPS provider,
same-user processes, a compromised child, and backups or snapshots may read
them. Prefer a dedicated, scoped, expiring, independently revocable key where
available, and make backup inclusion an explicit host policy. Bash-area removal
retains `secrets/`, every bundle, `bash.sh`, any old `secrets.conf`, and any old
volatile runtime artifact.
