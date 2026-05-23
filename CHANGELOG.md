# Changelog

All notable changes to this project will be documented in this file.

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

### Not in this release
- A `wt` Homebrew formula. Install via clone + symlink for now.
