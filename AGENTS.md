# AGENTS.md

This file orients agents working on **git-wt** itself. Read `CONTEXT.md` for load-bearing invariants: canonical checkout parking, worktree record stream, branch policy, config snapshot, hook composition, and plugin lifecycle boundaries. See `README.md` for user-facing behavior.

## How to work here

- Code edits go in `git-wt`, the single sourceable bash binary. Keep existing section boundaries intact unless you are deliberately changing architecture.
- Tests go in `tests/*.bats`. Prefer focused bats coverage for helper seams and command behavior over broad golden-output assertions.
- Run targeted bats tests for changed behavior. For broad CLI changes, run `tests/run.sh`; it defaults to parallel jobs.
- Docs live in `README.md`, `CONTEXT.md`, `ROADMAP.md`, `CHANGELOG.md`, and `docs/`.
- Plugin contract changes must update `docs/plugin-contract.md`, manifest validation, and plugin tests together.
- Config behavior changes must update `docs/CONFIG.md`, `examples/config.example.yaml`, and tests that exercise config snapshots or hook-cache generation.
- Never make the canonical checkout writable by default. Canonical-as-parking-spot is the core invariant.
- Never make plugin failures fail worktree creation/removal/focus unless the plugin command itself is the requested operation.
- Never add hidden repo discovery or auto-cleanup. Managed repos and reaping stay explicit.
- Never introduce shared cross-repo libraries or frameworks here; this repo is a small CLI with a few earned seams.
- Dogfood `ai-trace`: AI-authored PRs must run `ai-trace pr-attach` and carry exactly one `🤖 ai-trace:` marker; direct emergency pushes without a PR must run `ai-trace gist-create` or `ai-trace collect` for local audit evidence.

## Docs index

Manual list for now. The placeholder block below can later be managed by agents-toc.

<!-- INDEX:START -->
<!-- Manual index. If agents-toc is installed later, let it own only this block. -->

- `README.md` — User-facing overview, install, usage, config example, hook chain, plugin commands, comparison, non-goals.
- `CONTEXT.md` — Maintainer/agent architecture context: invariants, module map, seams, API stability, ADRs.
- `ROADMAP.md` — Historical architecture audit and milestone plan for sourceability, records, branch policy, config snapshot, and plugin extraction.
- `CHANGELOG.md` — Release history and decisions by version.
- `docs/CONFIG.md` — Full `~/.config/wt/config.yaml` reference: fields, defaults, validation, safety consequences.
- `docs/COMPARISON.md` — Narrative comparison against adjacent worktree, stacked-PR, and VCS tools.
- `docs/plugin-contract.md` — Canonical `git-wt.plugin.v0` contract for out-of-process plugins.
- `examples/config.example.yaml` — Copyable config showing defaults, repos, branch patterns, protected refs, hooks, forbidden roots, and branch length.

<!-- INDEX:END -->
