# Releasing git-wt

## Pre-release checks

1. Run `bats tests` and confirm all tests pass.
2. Run `bash -n git-wt`.
3. Confirm `git status` is clean before the version bump.
4. Check `WT_VERSION` near the top of `git-wt` matches the intended release.

## Cut release

1. Bump `WT_VERSION="X.Y.Z"` in `git-wt`.
2. Prepend a `## [vX.Y.Z]` entry to `CHANGELOG.md` with Added / Changed / Fixed sections as applicable.
3. Commit and tag in this order:

   ```bash
   git add -A
   git commit -m "Release vX.Y.Z"
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main
   git push origin vX.Y.Z
   ```

4. Create GitHub release only after both pushes succeed:

   ```bash
   gh release create vX.Y.Z --notes "..."
   ```

## Homebrew tap update

1. In `~/Documents/GitHub/homebrew-tap`, update `Formula/git-wt.rb` URL and `sha256` for `vX.Y.Z`.
2. Verify formula installs these pkgshare assets:
   - `plugins-registry.json`
   - `docs/`
3. Verify formula uses `inreplace` so `WT_PLUGIN_REGISTRY` points at the installed `pkgshare/plugins-registry.json`.
4. This check is mandatory: v0.9.0 was re-cut because pkgshare registry/docs install was missed.
5. Upgrade and smoke test:

   ```bash
   brew update
   brew upgrade noamsiegel/tap/git-wt
   wt --version
   wt plugin install nonexistent
   ```

6. `wt plugin install nonexistent` must show registry entries including `herdr`, `zed`, and `cmux`.

## Adding a new registry plugin

1. Update root `plugins-registry.json`; this is the file copied into formula `pkgshare`.
2. Bump `WT_VERSION`.
3. Release as above. Homebrew users receive the new `pkgshare/plugins-registry.json` on upgrade.

## Recovery

- Push failed before tag push: fix the push failure, then push `main`, then push `vX.Y.Z`; create GitHub release only after both succeed.
- Tag misaligned after failed push or premature release: delete the bad remote tag/release, recreate annotated tag on the intended commit, push tag again, then recreate release notes.
- Stale shim breaks push: inspect `.git/hooks/pre-push`, remove obsolete `guardrails` shim, reinstall current hook chain, rerun release push.
- Plugin registry missing after install: formula failed to install pkgshare assets or `inreplace` missed `WT_PLUGIN_REGISTRY`. Fix formula, re-cut release, then rerun brew upgrade and smoke tests.
