#!/usr/bin/env bats

load lib/setup

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

# Write a `git` stub that answers `ls-remote` deterministically (no network)
# and passes every other invocation through to the real binary. Detects
# `ls-remote` anywhere in the args so both `git ls-remote …` and
# `git -C <dir> ls-remote …` are covered.
_write_git_stub() {
  mkdir -p "$FIX/gitstub"
  cat > "$FIX/gitstub/git" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do
  if [[ "$a" == "ls-remote" ]]; then
    printf '%s\tHEAD\n' deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
    exit 0
  fi
done
exec "${REAL_GIT:?REAL_GIT unset}" "$@"
STUB
  chmod +x "$FIX/gitstub/git"
}

# Regression: `wt version --latest` must not crash under `set -u` when wt is
# NOT installed from a git clone (e.g. Homebrew). The non-clone branch only
# assigns upstream_sha, so local_sha must be pre-initialized — otherwise the
# `[[ -n "$local_sha" ... ]]` comparison trips nounset.
@test "version --latest: non-clone install does not trip set -u" {
  _write_git_stub
  mkdir -p "$FIX/noclone"
  # Copy (not symlink) so wt_install_dir resolves to a dir with no .git.
  cp "$WT_REPO_ROOT/git-wt" "$FIX/noclone/git-wt"
  chmod +x "$FIX/noclone/git-wt"

  cd "$FIX/canonical"
  REAL_GIT="$(command -v git)" PATH="$FIX/gitstub:$PATH" \
    run "$FIX/noclone/git-wt" version --latest

  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" == *"upstream HEAD"* ]]
}

# A real clone install reports its comparison without crashing.
@test "version --latest: clone install compares cleanly" {
  _write_git_stub
  # The repo checkout is a clone (worktree .git file), so run it in place.
  cd "$FIX/canonical"
  REAL_GIT="$(command -v git)" PATH="$FIX/gitstub:$PATH" \
    run "$WT_REPO_ROOT/git-wt" version --latest

  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
}
