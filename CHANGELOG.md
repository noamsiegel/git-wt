# Changelog

All notable changes to this project will be documented in this file.

## [v0.10.7] — hook cache repo lookup alignment

### Fixed
- `wt_repo_by_path` now emits one repo name per cached repo path, keeping `WT_REPO_PATHS` and `WT_REPO_NAMES` aligned when canonical paths and realpaths are identical.

## [v0.10.6] — Bash 3-compatible hook cache

### Fixed
- `wt doctor --install-hooks` now writes a Bash 3-compatible `paths.cache`, replacing the associative `WT_REPO_BY_PATH` map with parallel arrays plus `wt_repo_by_path`. This avoids `declare -A` failures when Git invokes hooks through macOS `/bin/bash`.

## [v0.10.5] — branch and worktree state seams

### Changed
- Centralized branch policy behind `branch_policy_allows`, so command-time validation and `wt hook-run pre-push` share the same quiet predicate, including maximum branch length.
- Centralized worktree clean/pushed/reachable state behind `worktree_state_record` and `worktree_reap_refusals`, so `status`, `tidy`, and `reap` consume one safety/state surface.

## [v0.10.4] — setup_command: auto toolchain detection

### Added
- `setup_command: auto` (works in `defaults` or per-repo): on `wt new`, detect the toolchain from lockfiles at the worktree root and run the matching cache-backed installer — `uv.lock`→`uv sync`, `bun.lockb`/`bun.lock`→`bun install`, `pnpm-lock.yaml`→`pnpm install`, `yarn.lock`→`yarn install`, `package-lock.json`→`npm ci` — then `direnv allow` if an `.envrc` is present. Multiple run for polyglot repos. Each step is best-effort (missing tool or failed install warns, never fails `wt new`). Removes the need to hand-write a per-repo install command.

## [v0.10.3] — install-hooks auto-handles direnv-managed hooksPath

### Added
- `wt install-hooks` now detects when a repo's `.envrc` manages `core.hooksPath` (which direnv would re-apply and clobber the dispatcher) and, if the `.envrc` sources a user-local file last (e.g. `source_env .envrc-personal`), appends the dispatcher override to that file (idempotently) and runs `direnv allow`. If no user-local source is found, it warns. Makes direnv-managed repos a one-command install.

## [v0.10.2] — doctor recognizes the wt dispatcher

### Fixed
- `wt doctor` no longer warns "local override" for a repo whose `core.hooksPath` points at the wt dispatcher (`~/.config/wt/repo-hooks/<repo>`); it now reports `PASS (wt dispatcher)`. Genuine third-party overrides still warn.

### Docs
- README: document how to keep `wt install-hooks` working in repos whose `.envrc`/direnv manages `core.hooksPath` (put the override in the user-local `.envrc-personal` that `.envrc` sources last).

## [v0.10.1] — install-hooks name-filter hardening

### Fixed
- `wt install-hooks` no longer creates bogus hook symlinks for non-hook entries in the original hooks dir: directories (e.g. `__pycache__`) and dotted/helper files (e.g. `run-pre-commit-hooks.py`, `*.sample`) are skipped — only real (extensionless, executable) git hook names are wired through the dispatcher.
- `wt install-hooks` now removes stale hook symlinks from a previous install before regenerating, so shrinking a repo's hook set doesn't leave dangling dispatcher entries.

## [v0.10.0] — worktree env bootstrap, doctor health, hook dispatcher

### Added
- `worktree_symlinks` config (per-repo + `defaults`): on `wt new`, symlinks listed gitignored paths from the canonical checkout into the new worktree (live coupling, vs `.worktreeinclude` which copies). Skips files that already exist, warns on a missing source, refuses `..`/absolute path-escape entries. A repo list replaces the defaults list (no merge).
- `setup_command` config (per-repo + `defaults`): runs `bash -c "<cmd>"` in a freshly created worktree after symlinks. Best-effort — a non-zero exit warns but never fails or undoes `wt new`. Runs only on `wt new`.
- `wt doctor --worktree <id>`: read-only per-worktree health report (configured `worktree_symlinks` present/dangling, `node_modules` when a root `package.json` exists, `.venv`, direnv `.envrc`, effective `core.hooksPath`, and prunable worktree metadata).
- `wt doctor` now flags any registered worktree under a `forbidden_roots` path as `WARN (external: N)` (e.g. agent-isolation worktrees), and warns per repo when a local `core.hooksPath` overrides wt's global hooks. Use `wt install-hooks` to restore the wt guard in such repos.
- `wt install-hooks [--repo <n>]` / `wt uninstall-hooks [--repo <n>]`: point a repo's local `core.hooksPath` at a generated dispatcher that runs the wt guardrail (`wt hook-run`) and then chains the repo's original hooks. This restores wt's canonical-commit guard in repos whose local `core.hooksPath` (e.g. a team-managed `.githooks`) would otherwise bypass wt's global hooks. Reversible via `uninstall-hooks`; idempotent.
- `wt hook-run <hook>` (internal): pure, fail-open git-hook guardrail invoked by the dispatcher — refuses commits in a canonical checkout, and validates branch names on push when `hooks.enforce_branch_names` is on.

### Changed
- `wt list`, `wt status`, and `wt cd` are now read-only-safe from inside a canonical checkout (previously refused with exit 20). External (forbidden-root) worktrees are labeled `(external)` in `list`/`status`; `wt cd` to one prints the path but warns on stderr. Mutating commands still refuse from canonical.
- `wt doctor` now treats a canonical checkout parked off its `default_branch` as a FAIL (exit 1) instead of a warning. A dirty canonical remains a warning.

### Fixed
- `wt doctor`'s forbidden-root check now enumerates actual registered worktrees (via `git worktree list`) instead of only comparing configured `worktree_root` paths, so externally-created worktrees under a forbidden root are detected.

## [0.9.7] — version --latest crash fix

### Fixed
- `wt version --latest` no longer aborts with `local_sha: unbound variable` on non-clone installs (e.g. Homebrew). The non-clone branch set only `upstream_sha`, so the later `[[ -n "$local_sha" … ]]` comparison tripped `set -u`; both variables are now initialized to empty.

## [0.9.6] \u2014 wt move

### Added
- `wt move <branch>`: relocate uncommitted canonical work to a brand-new worktree. Stashes staged + unstaged + untracked in canonical, creates the worktree off `base`, and pops the stash inside it. Refuses when canonical is clean (use `wt new`) or not on the default branch (use `wt adopt --commit-wip`). On `git worktree add` failure the stash is automatically restored to canonical. Aliased as `wt mv`.

## [0.9.5] \u2014 path-cache shell compatibility fix

### Fixed
- `wt doctor --install-hooks` now writes `WT_REPO_BY_PATH` as alternating key/value pairs in `~/.config/wt/paths.cache`, so both Bash Git hooks and Zsh prompt startup can source the same cache without arithmetic parsing errors on absolute paths like `/opt/homebrew/...`.

## [0.9.4] — path-cache shell quoting fix

### Fixed
- Superseded by v0.9.5; v0.9.4 fixed Bash parsing but still emitted a cache shape that Zsh prompt startup could not source correctly.

## [0.9.3] — config-required split (fix wt --version, plugin validate without config)

### Fixed
- `wt --version`, `wt --help`, `wt onboard`, `wt upgrade`, and all `wt plugin` subcommands now work without a wt config file at `$WT_CONFIG`. Previously, every command bailed with "config not readable" before dispatching, which broke `brew test git-wt` (runs in a fresh tmp HOME) and any plugin-author CI that wants to run `git-wt plugin validate .` without a configured wt setup.
- Split `require_deps` (basic tools: bash, yq, git, realpath) from `require_config` (config-readable check). Worktree-operating commands still require config and fail loudly if it's absent.

## [0.9.2] — conventions documented (RELEASING + TSV + JSON parser)

### Added
- `RELEASING.md`: ~60-line release checklist with pkgshare audit (formula must install `plugins-registry.json` + `docs/` + inreplace `WT_PLUGIN_REGISTRY`), recovery notes, and registry-update workflow.
- `CONTEXT.md` TSV record convention section: cites `wt_record_fields`, explains why `IFS=$'\t'` is a footgun.
- `docs/plugin-contract.md` JSON-parser convention: yq is canonical (already required by git-wt); Python yq is incompatible.

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
