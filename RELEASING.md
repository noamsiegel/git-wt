# Releasing git-wt

Two release paths. Both end with the GitHub Actions workflow at `.github/workflows/release.yml` bumping the Homebrew tap formula automatically.

## Pre-release checks (every release)

1. `bats tests` — all tests pass.
2. `bash -n git-wt` — syntax check.
3. `git status` — clean working tree.
4. `CHANGELOG.md` — has an entry for the version being cut.

## Path A — full automation (recommended)

Use when releasing from the standard `main` branch with a CHANGELOG entry already prepended.

1. Prepend the `## [vX.Y.Z]` entry to `CHANGELOG.md`. Commit.
2. From the GitHub Actions UI, run `release` workflow with the desired version-bump kind (`patch` / `minor` / `major`).
3. The workflow does the rest:
   - Computes `vX.Y.Z` from the latest tag + bump kind
   - Verifies the CHANGELOG entry exists
   - Patches `WT_VERSION="X.Y.Z"` in `git-wt`, commits, pushes
   - Creates annotated tag `vX.Y.Z`, pushes tag
   - Creates GitHub release with tag notes
   - Triggers `homebrew` job: opens a PR in `noamsiegel/homebrew-tap` updating `Formula/git-wt.rb` URL + sha256
4. Review and merge the homebrew-tap PR.
5. Smoke test:

   ```bash
   brew update
   brew upgrade noamsiegel/tap/git-wt
   wt --version
   wt plugin install nonexistent   # must list herdr, zed, cmux
   ```

## Path B — manual tag (fallback)

Use when you need to release a non-main commit, or when the workflow_dispatch route is unavailable.

1. Bump `WT_VERSION="X.Y.Z"` in `git-wt`. Prepend CHANGELOG entry. Commit:

   ```bash
   git add -A
   git commit -m "Release vX.Y.Z"
   ```

2. Tag and push:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main
   git push origin vX.Y.Z
   ```

3. Create the GitHub release (the workflow's `release` job only runs on `workflow_dispatch`, so you do it manually here):

   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "..."
   ```

4. The `homebrew` job in `release.yml` fires automatically on the tag push and opens the formula-bump PR. No manual sha256 computation or formula edit needed.
5. Review/merge the homebrew-tap PR.
6. Smoke test (same as Path A).

## Homebrew formula invariants

The `homebrew` job updates URL + sha256 only. The rest of `Formula/git-wt.rb` is invariant and must keep these properties:

- pkgshare installs:
  - `plugins-registry.json`
  - `docs/`
- `inreplace` rewrites `WT_PLUGIN_REGISTRY` to point at `pkgshare/plugins-registry.json`.
- v0.9.0 was re-cut because pkgshare assets weren't installed; this check is mandatory if you ever rewrite the formula.

## Adding a new registry plugin

1. Update root `plugins-registry.json` (it's copied into `pkgshare`).
2. Bump `WT_VERSION` and release via Path A or B.
3. Homebrew users receive the new `pkgshare/plugins-registry.json` on the next `brew upgrade`.

## Recovery

| Failure | Fix |
|---|---|
| Workflow fails after pushing main but before tagging | Re-run workflow with same inputs; `Sync WT_VERSION` step is idempotent (`git diff --quiet` skips when already bumped). |
| Tag pushed but homebrew job failed (e.g. token expired) | Re-run the `homebrew` job alone from the Actions UI, or push the tag again (delete + re-push) to retrigger. |
| Tag misaligned (wrong commit) | Delete remote tag (`git push --delete origin vX.Y.Z`), delete release, retag on correct commit, push again. |
| Formula PR opened but doesn't merge | Manually edit URL/sha256 in `homebrew-tap`'s `Formula/git-wt.rb`, commit, merge. |
| Stale `pre-push` shim breaks push | Inspect `.git/hooks/pre-push`, remove obsolete `guardrails` shim, reinstall current hook chain. |

## Required secret

`HOMEBREW_TAP_TOKEN` must be set in this repo's secrets, with `contents: write` on `noamsiegel/homebrew-tap`. Without it, the `homebrew` job fails and the formula bump must be done manually.
