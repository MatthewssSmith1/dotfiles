---
name: codex-subagent
description: Delegate a bounded task to the Codex CLI. Use when the user says "codex" or asks for an independent second opinion or review.
---

# Instructions

You orchestrate; Codex executes bounded subtasks.

## Preflight

Codex must be present and authenticated; check with `codex login status`. Otherwise tell the user and stop.

## Invoke

Always `codex exec`, never bare `codex` (requires a TTY).

```bash
codex exec -m <model> -c model_reasoning_effort="<effort>" \
  --sandbox <mode> --skip-git-repo-check \
  "$PROMPT" 2>/dev/null
```

- `2>/dev/null` drops the progress/reasoning stream; stdout carries the final message. On failure or empty output, rerun without it to see the error.
- Long prompts via stdin: `codex exec ... - <<'EOF' ... EOF`.
- Follow-ups: `codex exec resume --last "<prompt>"` (repeat the same flags).
- Prompts must be self-contained: Codex cannot see this conversation. Include file paths, relevant snippets, constraints, and the exact output expected back.

## Model and effort

Only `gpt-5.6-terra` or `gpt-5.6-sol`; only `low` or `medium` effort.

| Task | Model | Effort |
|---|---|---|
| Mechanical: lookup, rename, format, one-file question | terra | low |
| Routine bugfix or small feature with a clear spec | terra | medium |
| Hard question needing a fast pass: triage, second opinion, cheap scan | sol | low |
| Complex feature, cross-module refactor, subtle bug, security/adversarial review, design tradeoffs | sol | medium |

Unsure: start terra/medium, escalate to sol/medium on a weak result.

## Sandbox

### Read (`--sandbox read-only`)

- Default; analysis, review, plans. Tasks may run concurrently.
- Reads the entire filesystem — pass absolute paths for files outside the repo; never copy them in.

### Write (`--sandbox workspace-write`)

- Only when edits are requested. Review the diff before accepting it.
- At most one write task at a time per checkout.
- Writes are confined to the cwd tree. Edits outside it: `--add-dir <dir>` (repeatable; grants write — scope to the one dir needed). Task rooted in a different directory entirely: `-C <dir>` instead. Prefer `--add-dir`; it keeps the repo as primary root.
