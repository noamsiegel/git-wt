# Worktree environment issues audit

Date: 2026-06-04

Scope: issues observed while using `wt`, OMP-created PR worktrees, and common `git worktree` edge cases that can break local verification.

## Observed issues from this session

| Issue | Evidence | Current `wt` coverage |
|---|---|---|
| PR worktrees did not have JS dependencies | `~/.omp/wt/8107-26e4021/node_modules` and `~/.omp/wt/8074-26e4021/node_modules` were absent. | Not handled. |
| PR worktree did not have a Python virtualenv | `~/.omp/wt/8107-26e4021/.venv` was absent. | Partially handled only for `wt`-created worktrees via `wt-bootstrap`; not handled for OMP-created worktrees. |
| PR worktree did not have `.env` | `~/.omp/wt/8107-26e4021/.env` was absent. | Only handled if the canonical checkout has `.worktreeinclude` and it lists the file. |
| Monorepo has no `.worktreeinclude` | No `/Users/noam.siegel/Documents/GitHub/monorepo/.worktreeinclude` was present. | No monorepo env-copy contract exists. |
| Local verification was weaker than intended | PR #8107 commit used `--no-verify` because JS deps were missing in the worktree; CI passed later. | Not handled by `wt`. |
| OMP worktrees are registered in monorepo Git metadata | `git worktree list --porcelain` listed `/Users/noam.siegel/.omp/wt/8074-26e4021` and `/Users/noam.siegel/.omp/wt/8107-26e4021`. | `wt` can see them indirectly, but should treat them as external/forbidden. |
| `wt doctor` missed forbidden-root worktrees | `wt doctor` reported `no worktrees under forbidden_roots PASS` while registered worktrees existed under `/Users/noam.siegel/.omp/wt`. | Bug: current check validates configured worktree roots, not actual registered worktree paths. |
| `wt cd` resolved forbidden OMP worktrees | `wt cd 8107-26e4021` returned `/Users/noam.siegel/.omp/wt/8107-26e4021`. | Gap: should refuse or loudly warn. |
| `wt status` refused from canonical checkout | `wt status` in `/Users/noam.siegel/Documents/GitHub/monorepo` exited with canonical read-only error. | UX gap: read-only commands should be safe from canonical. |
| Monorepo local hooks override global wt hooks | `git config --local core.hooksPath` in monorepo returned `.githooks`. | Known gap: local repo hooks win over global wt hook path. |
| Stale prunable worktree metadata exists | `git worktree list --porcelain` listed `/private/tmp/pr-7685-worktree` as prunable with a missing gitdir. | `wt repair` or `git worktree prune` can clean it, but doctor should surface it. |
| `hoa` canonical checkout is not healthy | `wt doctor` reported `hoa canonical on main WARN (feat/portal-scraper-system)` and `hoa canonical clean WARN (dirty)`. | Config hygiene issue; not a `wt` code bug. |

## Existing `wt` behavior checked

| Feature | Current behavior |
|---|---|
| `.worktreeinclude` copy | `wt` copies gitignored files from canonical when the canonical checkout has `.worktreeinclude`; tracked files are never duplicated. |
| Copy mechanism | `wt` copies matching ignored files with `cp -p`; this is fine for small env/config files, but not ideal for large dependency trees. |
| Bootstrap plugin | `wt-bootstrap` approves tracked `.envrc` files and creates a bare `.venv` when root `.envrc` expects `.venv/bin`. It does not install dependencies. |
| Branch collision guard | `wt new` blocks when the target branch already exists locally or on origin. |
| Stale metadata repair | `wt repair` runs `git worktree prune`. |
| Forbidden root creation guard | `wt new` rejects targets under `forbidden_roots`; doctor/cd/status coverage is incomplete. |

## Common worktree edge cases from external research

Sources checked: Git official `git worktree` docs, public writeups about `git worktree` env files and dependency setup, and `.worktreeinclude` convention writeups.

| Edge case | Why it matters | `wt` coverage |
|---|---|---|
| Ignored env/config files are not Git-managed | `.env`, `.env.local`, IDE settings, and local credentials are often required but absent in new worktrees. | Partial via `.worktreeinclude`; monorepo lacks the file. |
| Dependency directories are per-worktree | `node_modules`, Python venvs, and build caches are not shared by Git worktrees; each worktree needs install/bootstrap. | Not handled except bare `.venv` creation. |
| Blindly sharing `node_modules` can be wrong | Branches can have different lockfiles or dependency versions; symlink/copy can create subtle mismatches. | No policy. |
| Disk explosion from duplicated deps/build caches | Multiple worktrees can duplicate heavy ignored dirs. | No dedupe/COW/cache strategy. |
| Hooks are shared or overridden depending on config | Git hooks can be global, repo-local, or worktree-specific; local `core.hooksPath` can bypass wt hooks. | Partial; doctor checks global hook but not effective per-repo hook precedence. |
| Per-worktree Git config is opt-in | Git supports `extensions.worktreeConfig` and `git config --worktree`; sparse checkout and some settings should be per-worktree. | Not handled. |
| Sparse checkout should be per-worktree | Shared sparse settings can corrupt expectations across worktrees. | Not handled. |
| Submodules are not automatically initialized | New worktrees may need `git submodule update --init --recursive`; Git docs warn submodule support with worktrees is incomplete. | Not handled. |
| Branch already checked out elsewhere | Git prevents the same branch being checked out in two worktrees. | Covered by Git and partly by `wt new`. |
| Manual deletion leaves stale admin metadata | Removing a worktree directory by hand leaves prunable entries. | Repair exists; doctor should surface. |
| Moving worktrees can break gitdir links | Git docs recommend `git worktree repair` after moves. | Repair exists. |
| Wrong-directory edits | Multiple checkouts increase risk of editing canonical/main or the wrong worktree. | Strong canonical guard exists; `wt status` read-only UX needs adjustment. |

## Recommended fixes

1. Fix `wt doctor` forbidden-root validation to enumerate actual `git worktree list --porcelain` paths for every configured repo and flag registered worktrees under `forbidden_roots`.
2. Make read-only commands such as `wt status`, `wt list`, and `wt cd` safe and useful from canonical checkouts while keeping mutation commands blocked.
3. Make `wt cd` refuse or warn when the selected worktree path is under `forbidden_roots`.
4. Add `wt doctor --worktree <id>` or equivalent health check for:
   - expected env files present;
   - direnv allowed;
   - `.venv` present and usable;
   - JS package manager dependencies present where needed;
   - effective `core.hooksPath` after local/global/worktree precedence;
   - prunable Git worktree metadata.
5. Add a per-repo bootstrap profile rather than copying heavy dependency directories blindly.
6. Add or generate a monorepo `.worktreeinclude` for small required ignored files such as `.envrc-personal`, `.env`, and `.env.local`, subject to explicit secret-copy policy.
7. Decide whether OMP-created worktrees should be registered in canonical repo metadata at all. If they remain registered, `wt` should label them external/forbidden and avoid operating on them.
8. Add tests for `.worktreeinclude`, forbidden-root detection, canonical read-only commands, and effective hooks-path detection.

## Decision questions asked

These policy questions were asked during review and resolved in the section below:

1. Env files: copy, symlink, or delegate to setup command?
2. Dependency bootstrap: diagnose only, run setup command, or clone/cache dependencies?
3. OMP boundary: invisible, external read-only, or first-class `wt` worktrees?
4. Hook policy: warning, doctor failure, or dispatcher install?
5. Canonical health: warning-only, fail non-main only, or fail dirty and non-main?

## Decisions captured from review

| Topic | Decision / follow-up |
|---|---|
| Dependency bootstrap | Use a configured setup command. `wt` should be able to run safe per-repo bootstrap after worktree creation, rather than only diagnosing missing dependencies. |
| Canonical health severity | Fail when canonical checkout is not on the configured default branch. Keep dirty canonical state as warning-only for now. |
| Env files | Symlink allowlist: create symlinks in each worktree for explicitly allowlisted env files from canonical/shared secrets directory; fail or warn when a target is missing. Do not wildcard `.env*`. |
| OMP overlap | Keep separate, bridge: `wt` remains the persistent human worktree manager; OMP remains ephemeral agent workspace manager; `wt` detects and labels OMP worktrees as external/read-only. |
| Hook enforcement | Install dispatcher: effective hooks should chain repo-local hooks and `wt` guardrails rather than letting local `core.hooksPath` bypass `wt`. |

## Implemented (this branch)

The following shipped in `git-wt` + `tests/` (see CHANGELOG `[Unreleased]`):

| Change | Where | Notes |
|---|---|---|
| `worktree_symlinks` config + symlinking on `wt new` | `_cfg_load`/`cfg_worktree_symlinks`, `link_worktree_symlinks`, `cmd_new` | Symlink allowlist; skips existing files, warns on missing source, refuses `..`/absolute paths. Repo list replaces defaults. |
| `setup_command` config + run on `wt new` | `run_setup_command`, `cmd_new` | Best-effort `bash -c`; non-zero exit warns, never fails `wt new`. |
| Canonical-not-on-default → FAIL | `cmd_doctor` | Dirty canonical stays WARN. |
| Forbidden-root detection fix | `cmd_doctor`, `path_under_forbidden` | Enumerates real `git worktree list` paths; surfaces OMP/external worktrees as `WARN (external: N)`, not a hard fail. |
| External labeling + read-only-from-canonical | `cmd_list`, `cmd_status`, `cmd_cd` | `list`/`status` mark `(external)`; `cd` warns but prints path; all three dropped the canonical guard. |
| `wt doctor --worktree <id>` | `cmd_doctor_worktree` | Read-only health: symlinks, `node_modules`, `.venv`, direnv, effective `core.hooksPath`, prunable metadata. |
| Local `core.hooksPath` override detection | `cmd_doctor` | Per-repo WARN when a local hooksPath bypasses wt's global hooks. |
| Hook dispatcher (`wt install-hooks` / `uninstall-hooks` / `hook-run`) | `cmd_install_hooks`, `cmd_uninstall_hooks`, `cmd_hook_run` | Routes a repo's local `core.hooksPath` through a wt dispatcher: runs the fail-open wt guard, then chains the repo's original hooks. Reversible, idempotent. Restores the canonical-commit guard in repos (monorepo/hoa) whose local hooksPath bypassed wt. |

Covered by `tests/test_doctor.bats`, `tests/test_list_status.bats`, `tests/test_worktree_bootstrap.bats`, and `tests/test_install_hooks.bats` (full suite green).

## Deferred

- **Symlink/setup parity for `wt adopt` / `wt move` / `wt pr`.** Bootstrap currently runs only on `wt new`. The other worktree-creating commands could grow the same step if needed.
- **Centralizing the global hooks on `wt hook-run`.** The chezmoi-managed global hooks (`~/.config/git/hooks/`) still inline their own guard logic; they could be slimmed to call `wt hook-run` so there is a single guard implementation. Out of scope for the `git-wt` binary (those scripts live in the dotfiles layer).
