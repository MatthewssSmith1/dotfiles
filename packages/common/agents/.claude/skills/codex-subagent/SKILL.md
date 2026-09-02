---
name: codex-subagent
description: Delegate tasks to subagents with the Codex CLI. Use when the user says "codex", or asks to implement a plan, review, or get a second opinion.
---

# Instructions

You orchestrate from the primary checkout; Codex executes bounded dispatches.

## Preflight

`codex login status`; otherwise tell the user and stop.

## Size the dispatch

A **dispatch** is one agent's bounded unit: the files it owns and a completion criterion it can check itself (gate green). Cut plan phases to dispatch grain, not domain headings: merge phases that share files; split a phase spanning disjoint areas so it can fan out. More than one write dispatch in flight: read [parallel-worktrees.md](parallel-worktrees.md).

## Invoke

Always `codex -p subagent exec` (profile: `~/.codex/subagent.config.toml`), never bare `codex`. Launch with the Bash sandbox off (`dangerouslyDisableSandbox: true`); Codex's own sandbox is the guard. Stacked sandboxes fail git and socket tests with EPERM, and Codex then reports a gate it never ran.

```bash
codex -p subagent exec --skip-git-repo-check -o <job>/<name>.out - <<'EOF'
...
EOF
```

- Prompt via heredoc. A prompt passed as an argument needs `</dev/null` or Codex blocks on stdin.
- `run_in_background: true`; the harness notifies on exit; read the `.out`.
- For simple work, override with `-c model_reasoning_effort="low"`.
- Prompt is self-contained: paths, snippets, constraints, gate command, exact output expected. Name the files the dispatch owns; edits elsewhere are allowed when the work needs them and are listed in the report. Say "single agent; do not spawn agents."
- Follow-up: `codex -p subagent exec resume --last -`. Flags are per invocation; repeat any override.

## Verify

The prompt ends: "Run `<gate>`; iterate until green; paste the last 20 lines of its output verbatim." Only pasted output counts; a summary is not a gate. Run the gate yourself once, review the diff, commit. Codex never commits.

## Sandbox

Profile default is read-only; read dispatches may run concurrently. Write dispatch: `--sandbox workspace-write`, confined to cwd. Writes outside cwd: `--add-dir <dir>`. Different root: `-C <dir>`.
