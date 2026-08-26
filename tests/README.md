# Testing

Use the smallest suites that cover the change. `tests/run.sh` remains the
exhaustive gate, not the routine development loop.

## Focused Routing

| Changed scope | Run |
|---|---|
| Documentation only | No test unless it mirrors an executable contract |
| Static config, manifests, schemas, or shell source | `tests/contract_test.sh` |
| Host detection or profile mapping | `tests/contract_test.sh`, `tests/host_test.sh` |
| `lib/areas/git.sh` or Git packages | `tests/contract_test.sh`, `tests/git_test.sh` |
| `lib/areas/tools.sh` or mise packages | `tests/contract_test.sh`, `tests/tools_test.sh` |
| Bash area and packages | `tests/contract_test.sh`, `tests/shell_test.sh` |
| `dotfiles-secret` helper | `tests/contract_test.sh`, `tests/secrets_test.sh` |
| Tmux area or packages | `tests/contract_test.sh`, `tests/tmux_test.sh` |
| Neovim area, packages, restore, or runtime policy | `tests/contract_test.sh`, `tests/nvim_test.sh` |
| Agent area, packages, lock, or skill tooling | `tests/contract_test.sh`, `tests/agents_test.sh` |
| Herdr area or package | `tests/contract_test.sh`, `tests/herdr_test.sh` |
| Desktop area or package | `tests/contract_test.sh`, `tests/desktop_test.sh` |
| Upstream script, manifest, evidence, or snapshot | `tests/contract_test.sh`, `tests/upstream_test.sh`, affected area suites |
| Windows Terminal managed settings or merge script | `tests/contract_test.sh`, `tests/windows_terminal_test.sh` |
| Deployment primitives, topology, or profile parsing | `tests/contract_test.sh`, `tests/lean_engine_test.sh`, affected area suites |
| Public CLI or launcher | `tests/contract_test.sh`, `tests/cli_test.sh` |
| Test harness or runner | `tests/run.sh` |
| One test suite | That suite |

## Exhaustive Gate

Run focused suites while iterating. Run `tests/run.sh` before committing a
change to `dotfiles.sh`, shared deployment code, the test
harness or runner, shared schemas or topology, an upstream refresh, or several
areas. If scope expands or ownership is unclear, use the broader gate.

## Reference Cost

Measured 2026-08-03 on a two-CPU VPS using the runner's automatic one-worker
mode. These are planning estimates, not performance contracts; the runner
prints current elapsed times.

| Suite | Approximate time |
|---|---:|
| `contract_test.sh` | 2s |
| `herdr_test.sh` | 14s |
| `upstream_test.sh` | 25s |
| `tmux_test.sh` | 10s |
| `agents_test.sh` | 3m |
| `git_test.sh` | 4m |
| `nvim_test.sh` | 10s |
| `lean_engine_test.sh` | 1m |
| `shell_test.sh` | 10m |
| `run.sh` | 33m |

Override bounded runner concurrency with `tests/run.sh --jobs COUNT` or
`TEST_JOBS=COUNT`; more workers can be slower on constrained hosts. Use
`tests/run.sh --list` to inspect the canonical suite list without running it.
