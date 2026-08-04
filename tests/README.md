# Testing

Use the smallest suites that cover the change. `tests/run.sh` remains the
exhaustive gate, not the routine development loop.

## Focused Routing

| Changed scope | Run |
|---|---|
| Documentation only | No test unless it mirrors an executable contract |
| Static config, manifests, schemas, or shell source | `tests/contract_test.sh` |
| `lib/areas/git.sh` or Git packages | `tests/contract_test.sh`, `tests/git_test.sh` |
| Bash or zsh areas and packages | `tests/contract_test.sh`, `tests/shell_test.sh` |
| Tmux area, packages, plugins, or parser fixtures | `tests/contract_test.sh`, `tests/tmux_test.sh` |
| Neovim area, packages, restore, or runtime policy | `tests/contract_test.sh`, `tests/nvim_test.sh` |
| Agent area, packages, lock, or skill tooling | `tests/contract_test.sh`, `tests/agents_test.sh` |
| Herdr area or package | `tests/contract_test.sh`, `tests/herdr_test.sh` |
| Provisioning code or manifests | `tests/contract_test.sh`, `tests/provisioning_test.sh`, affected area suites |
| Upstream script, manifest, evidence, or snapshot | `tests/contract_test.sh`, `tests/upstream_test.sh`, affected area suites |
| Shared deployment primitives or topology | `tests/contract_test.sh`, `tests/engine_test.sh`, affected area suites |
| One test suite | That suite |

## Exhaustive Gate

Run focused suites while iterating. Run `tests/run.sh` before committing a
change to `bootstrap.sh`, shared deployment or provisioning code, the test
harness or runner, shared schemas or topology, an upstream refresh, or several
areas. If scope expands or ownership is unclear, use the broader gate.

## Reference Cost

Measured 2026-08-03 on a two-CPU VPS using the runner's automatic one-worker
mode. These are planning estimates, not performance contracts; the runner
prints current elapsed times. Tmux coverage and cost vary with local parser
fixtures and versions.

| Suite | Approximate time |
|---|---:|
| `contract_test.sh` | 2s |
| `herdr_test.sh` | 14s |
| `upstream_test.sh` | 25s |
| `tmux_test.sh` | 80s |
| `provisioning_test.sh` | 2m |
| `agents_test.sh` | 3m |
| `git_test.sh` | 4m |
| `nvim_test.sh` | 5m |
| `engine_test.sh` | 7m |
| `shell_test.sh` | 10m |
| `run.sh` | 33m |

Override bounded runner concurrency with `tests/run.sh --jobs COUNT` or
`TEST_JOBS=COUNT`; more workers can be slower on constrained hosts.
