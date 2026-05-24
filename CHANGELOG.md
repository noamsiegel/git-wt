# Changelog

All notable changes to this project will be documented in this file.

## [0.9.1] — architecture docs

### Added
- `CONTEXT.md` with load-bearing invariants, module map, real vs hypothetical seams, public API stability, and ADRs.
- `AGENTS.md` orienting agents working on this repo itself.
- `docs/COMPARISON.md` with full narrative competitor analysis (Worktrunk, wtp, gwq, git-spice, Git Town, Graphite, jj) and coexistence guidance.
- `docs/CONFIG.md`: full `~/.config/wt/config.yaml` reference — every field, default, validation rule, and safety consequence.
- `docs/plugins.md`: shared comparison table for the wt-* plugin family (consumed by each plugin’s README).

### Changed
- `README.md` competitive section reformatted to the agents-toc-style table (`Tool | What it manages | Where state lives | When it acts`) and links to the new comparison doc.
- Renamed and sharpened `## Non-goals` as `## What it doesn’t do`.
- Minimal-config example now uses `base: origin/main` to match actual `wt new` fetch/start behavior.

## [0.9.0] — full-hybrid plugin ecosystem

### Added
- Added `plugins-registry.json` as the curated bare-name plugin registry, seeded with first-party `herdr`.
- Added `wt plugin validate <path>` for plugin authors to validate manifests, executables, API compatibility, capabilities shape, and health JSON before publishing.
- Added `docs/plugin-contract.md` as the canonical `git-wt.plugin.v0` contract, including manifest schema, event payloads, capabilities, health protocol, trust model, and v1 criteria.

### Changed
- Bare plugin names now resolve only through the curated registry; unknown bare names fail with known plugins and explicit third-party install instructions.
- Plugin manifests now prefer `api_versions: ["git-wt.plugin.v0"]`; singular `api_version` remains compatible with a deprecation warning.
- Install and enable now reject plugins whose API versions do not intersect host-supported APIs.
- Manifest `events` are lifecycle subscriptions; `capabilities` are separate action declarations and default to `[]` when absent.
- README now points plugin authors at the contract doc, documents registry-vs-explicit installs and `wt plugin validate`, and positions git-wt against adjacent worktree/stack tools.

## [0.8.0] — config snapshot

### Added
- Added `cfg_repo_record`, `cfg_each_repo_record`, and `cfg_reload` as the shared config snapshot interface for canonical repo fields after defaults and `{repo}` expansion.

### Changed
- `wt doctor --install-hooks`, doctor repo checks, and onboard cache refresh now consume repo config through snapshot records instead of repeated field lookups.

## [0.7.0] — branch policy module

### Added
- Added `branch_policy_match_repo`, `branch_policy_validate`, and `branch_policy_emit_cache` as the single branch-pattern policy surface for repo inference, runtime validation, and hook-cache generation.

### Changed
- `wt new`, branch validation, and `wt doctor --install-hooks` now consume branch patterns through the shared policy helpers so hook cache output and runtime validation stay in sync.

## [0.6.0] — worktree record stream

### Added
- Added `wt_each_worktree` and `wt_resolve_id` as the single TSV domain stream for worktree identity, realpaths, branches, SHAs, and canonical/worktree classification.

### Changed
- `list`, `status`, `audit`, `reap`, `tidy`, `repair`, and id consumers now use the shared worktree record stream instead of reparsing porcelain output independently.

## [0.5.0] — sourceable core, safe lifecycle JSON, plugin-only tabs

### Added
- `git-wt` can now be sourced by tests and shell tooling without auto-running `main`.
- Lifecycle events now use one safe JSON emitter with `api_version`, timestamp, and RFC 8259 escaping via `yq`.

### Changed
- Removed bundled herdr tab management from core. Worktree create/remove/focus events are dispatched only through enabled plugins.
- `list`, `status`, `audit`, `tidy`, and `repair` no longer read tab state directly; tab columns are omitted until plugin query events exist.
- `focus`, `close-tab`, and `resume` now require a tab plugin and point users at `wt plugin install herdr`.

### Removed
- `WT_PLUGIN_ONLY`, `WT_HAS_HERDR`, direct `herdr` invocations, and bundled herdr helper functions.

## [0.4.0] — wt-herdr plugin available; bundled herdr deprecated

### Added
- **`wt plugin install herdr`** now clones [noamsiegel/wt-herdr](https://github.com/noamsiegel/wt-herdr), the reference implementation of the `git-wt.plugin.v0` contract for herdr tab management.
- **`WT_PLUGIN_ONLY=1`** environment variable. When set, the bundled herdr code in git-wt core becomes a no-op; the wt-herdr plugin is the only thing managing tabs. Use this to validate the plugin-only future before v0.5.0 removes the bundled code.

### Deprecated
- The bundled herdr code in `git-wt` core. It still works (default behavior) but `require_deps` now prints a deprecation warning. Silence with `WT_QUIET_HERDR=1`. The code will be deleted in v0.5.0; install the wt-herdr plugin and set `WT_PLUGIN_ONLY=1` to adopt early.

### Notes
- This is the **bridge release** to the plugin-only future. v0.5.0 will remove ~300 lines of herdr-specific bash from `git-wt` core and require the plugin.
- The `git-wt.plugin.v0` contract is unchanged from v0.3.0; wt-herdr is the reference implementation.

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
