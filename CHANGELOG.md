# Changelog

All notable changes to this project will be documented in this file.

## [0.3.0] — plugin interface (stage 1 of two-stage herdr extraction)

### Added
- **Plugin interface (`git-wt.plugin.v0` draft contract).** Plugins are executables named `wt-<name>` installed under `$WT_PLUGIN_DIR` (default `~/.local/share/git-wt/plugins/`), with a sibling `wt-plugin.json` manifest declaring `api_version`, `name`, `executable`, `events`, `version`. Core fires four lifecycle events as JSON on stdin: `wt:worktree-created`, `wt:worktree-removed`, `wt:focus`, `wt:list`. Plugin failures warn but never fail git operations.
- **`wt plugin` subcommand** with `install`, `link`, `list`, `enable`, `disable`, `remove`, `emit`, `health` operations. See `wt plugin --help`.
- **6 new bats tests** covering install/enable/disable/emit/remove/health.

### Notes
- Contract is explicitly `v0` (draft). May change before promoting to `v1` once a couple of external plugins validate it in practice.
- Existing herdr behavior is unchanged. v0.4.0+ will extract bundled herdr to a separate `wt-herdr` plugin (stage 2).

## [0.2.1] — version-sync hotfix

Fix `WT_VERSION` constant to match the release tag (was stuck at 0.1.0).

## [0.1.0] — initial public release

### Added
- Worktree lifecycle CLI: `wt new`, `adopt`, `pr`, `reap`, `list`, `status`, `cd`, `focus`, `resume`, `close-tab`, `tidy`, `audit`, `repair`, `doctor`, `init`, `onboard`.
- Hook installation at `~/.config/git/hooks/` with:
  - `pre-commit`: refuses commits in canonical checkouts of configured repos.
  - `pre-push`: validates branch names against per-repo patterns (opt-in via `hooks.enforce_branch_names: true`).
  - `post-commit`: auto-pushes worktree branches to their private remote with `--force-with-lease` (gated by guardrails branch-guard if installed).
  - `post-checkout`: warns when canonical leaves its default branch.
  - `_wt-chain`: generic shim symlinked from other hook types that delegates to per-repo `.git/hooks/<name>` if present.
- Personal-hook bridge: each hook sources `_wt-personal.sh` and invokes
  `~/.git-hooks-personal/<hook>` if installed, composing cleanly with
  [guardrails](https://github.com/noamsiegel/guardrails) or similar layers.
- bats test suite (`tests/`).

### Security hardening
- Env-poisoning defense: `WT_HOOK_RUNNING=1` alone does NOT bypass — requires `WT_HOOK_NEXT` to also be set, which only happens via legitimate `exec_chain` propagation.
- Autopush gating: post-commit runs guardrails branch-guard against synthesized pre-push input before launching the background push.

### Known limitations
- macOS only (heavily tested). Linux probably works but untested in CI.
- bash >= 4 required (macOS's system bash 3.2 is not enough).

### Herdr is optional
- `herdr` is **fully optional**. When not installed, wt warns once (silenceable with `WT_QUIET_HERDR=1`) and core commands (`new`, `adopt`, `pr`, `list`, `status`, `cd`, `reap`, `tidy`, `audit`, `repair`, `doctor`, `init`, `onboard`) all work — they just skip tab creation/binding. Commands that require tabs (`focus`, `close-tab`, `resume`) explicitly die with a useful message when herdr is absent.

### `.worktreeinclude` (Claude Code / VS Code compatibility)
- `wt new` reads `<canonical>/.worktreeinclude` and copies matching gitignored files into the new worktree. Tracked files are never duplicated. Matches the conventions used by Claude Code and VS Code's git extension.

### Versioning and self-update
- `wt version` prints the current version. `wt version --latest` compares against upstream `HEAD` and reports drift.
- `wt upgrade` runs `git fetch && git pull --ff-only` in the install dir (must be a git clone).

### Branch policy unification
- `protected_refs` (newline list of literals or regex) can now live in `~/.config/wt/config.yaml` under `defaults` or per-repo. The guardrails personal hook layer reads it automatically when running in a wt-managed repo. Env vars (`PROTECTED_BRANCHES_LIST`, `PROTECTED_BRANCH_REGEX`) remain as fallback for non-wt repos.

### Security hardening (this release)
- C4: post-commit autopush now runs the FULL guardrails pre-push (not just branch-guard) before launching the background push, and pushes by HEAD SHA instead of branch name to close the TOCTOU window.
- C5: `WT_HOOK_NEXT` realpath is validated against the repo's `.git/hooks/` dir before honoring the recursion-skip. An attacker setting both `WT_HOOK_RUNNING=1` and `WT_HOOK_NEXT=/bin/true` can no longer bypass the chain.

### Not in this release
- A `wt` Homebrew formula. Install via clone + symlink for now.
