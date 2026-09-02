# Parallel dispatches in Worktrunk worktrees

Orchestrator stays on the primary checkout; each write dispatch gets a Worktrunk (`wt`) worktree. Three concurrent at most. `-y` skips project-hook approval prompts.

1. `wt -y switch --create <branch> --base <feature> --no-cd --format json` → `path`. Setup is the project's job: `.config/wt.toml` hooks and `.worktreeinclude`. A worktree arriving without deps is a project config gap; fix it there.
2. Launch each dispatch with `-C <path>` and its own `-o` file.
3. On exit: gate and review with `git -C <path> …`; commit there.
4. `wt -y merge -C <path> <feature>`: squash, rebase, remove worktree. Resolve conflicts here; recurring overlap means the dispatches were cut wrong.
