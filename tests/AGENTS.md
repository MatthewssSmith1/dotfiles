# Testing

Use the smallest suite that covers the change. `tests/run.sh` is the exhaustive gate, not the routine loop.

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
| Agent area, packages, or skill tooling | `tests/contract_test.sh`, `tests/agents_test.sh` |
| Herdr area or package | `tests/contract_test.sh`, `tests/herdr_test.sh` |
| Desktop area or package | `tests/contract_test.sh`, `tests/desktop_test.sh` |
| Upstream script, manifest, evidence, or snapshot | `tests/contract_test.sh`, `tests/upstream_test.sh`, affected area suites |
| Windows Terminal managed settings or merge script | `tests/contract_test.sh`, `tests/windows_terminal_test.sh` |
| Deployment primitives, topology, or profile parsing | `tests/contract_test.sh`, `tests/lean_engine_test.sh`, affected area suites |
| Public CLI or launcher | `tests/contract_test.sh`, `tests/cli_test.sh` |
| Test harness or runner | `tests/run.sh` |
| One test suite | That suite |

## Exhaustive Gate

Run focused suites while iterating. Run `tests/run.sh` before committing a change to `dotfiles.sh`, shared deployment code, the test harness or runner, shared schemas or topology, an upstream refresh, or several areas. If scope expands or ownership is unclear, use the broader gate.

## Reference Cost

Expensive suites are `shell_test.sh` (~10m), `git_test.sh` (~4m), `agents_test.sh` (~3m), and `lean_engine_test.sh` (~1m); full `tests/run.sh` is ~30m on constrained hosts. The runner prints current timings. Override concurrency with `tests/run.sh --jobs COUNT` or `TEST_JOBS=COUNT` and inspect the suite list with `tests/run.sh --list`.
