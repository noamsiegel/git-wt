#!/usr/bin/env bash
# Sourced by every .bats file. Creates a per-test fixture.
#
# Exports:
#   $FIX               temp dir for this test
#   $FIX/remote.git    bare repo
#   $FIX/canonical     working repo with `main` checked out
#   $FIX/canonical2    second bare-clone "hoa" canonical (for multi-repo tests)
#   $FIX/wt_root       monorepo worktree root
#   $FIX/wt_root2      hoa worktree root
#   $FIX/config.yaml   wt config pointing at the fixture
#   $WT_CONFIG=$FIX/config.yaml
#   $WT_CACHE=$FIX/paths.cache
#   $PATH prepends a per-test bin containing the repo's wt binary
#
WT_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT_REPO_ROOT="$(cd "$WT_TESTS_DIR/.." && pwd)"

wt_test_setup() {
  FIX=$(mktemp -d -t wt-test.XXXXXX)
  export FIX

  # Bare "remote"
  git init --quiet --bare "$FIX/remote.git"

  # Canonical for "fixrepo"
  git clone --quiet "$FIX/remote.git" "$FIX/canonical"
  git -C "$FIX/canonical" config user.email "test@example.com"
  git -C "$FIX/canonical" config user.name "Test"
  git -C "$FIX/canonical" config commit.gpgsign false
  git -C "$FIX/canonical" config core.hooksPath "$HOME/.config/git/hooks"
  SKIP_PERSONAL_HOOKS=1 git -C "$FIX/canonical" commit --quiet --allow-empty -m "feat: init"
  git -C "$FIX/canonical" branch -M main
  git -C "$FIX/canonical" push --quiet -u origin main >/dev/null 2>&1

  # Canonical for second repo "fixrepo2"
  git init --quiet --bare "$FIX/remote2.git"
  git clone --quiet "$FIX/remote2.git" "$FIX/canonical2"
  git -C "$FIX/canonical2" config user.email "test@example.com"
  git -C "$FIX/canonical2" config user.name "Test"
  git -C "$FIX/canonical2" config commit.gpgsign false
  git -C "$FIX/canonical2" config core.hooksPath "$HOME/.config/git/hooks"
  SKIP_PERSONAL_HOOKS=1 git -C "$FIX/canonical2" commit --quiet --allow-empty -m "feat: init"
  git -C "$FIX/canonical2" branch -M main
  git -C "$FIX/canonical2" push --quiet -u origin main >/dev/null 2>&1

  mkdir -p "$FIX/wt_root" "$FIX/wt_root2" "$FIX/omp-wt-forbidden" "$FIX/bin"
  ln -s "$WT_REPO_ROOT/git-wt" "$FIX/bin/wt"

  cat > "$FIX/config.yaml" <<EOF
repos:
  fixrepo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
    herdr_workspace: fixrepo
    branch_patterns:
      - "^dev/ABC-[0-9]+-[a-z0-9-]+\$"
      - "^pr-[0-9]+\$"
  fixrepo2:
    path: $FIX/canonical2
    worktree_root: $FIX/wt_root2
    base: origin/main
    default_branch: main
    herdr_workspace: fixrepo2
    branch_patterns:
      - "^dev/INFRA-[0-9]+-[a-z0-9-]+\$"

forbidden_roots:
  - $FIX/omp-wt-forbidden
branch_max_length: 80
EOF
  export WT_CONFIG="$FIX/config.yaml"
  export WT_CACHE="$FIX/paths.cache"

  # PATH: repo wt binary first.
  export PATH="$FIX/bin:$PATH"

  hash -r 2>/dev/null || true   # clear bash command cache so PATH change takes effect
  # Sanity
  command -v wt >/dev/null || { echo "wt not on PATH" >&2; return 1; }

  # Build the path cache so hooks can be tested against this fixture.
  if ! wt doctor --install-hooks >"$FIX/doctor.log" 2>&1; then
    echo "wt doctor --install-hooks failed; output follows:" >&2
    cat "$FIX/doctor.log" >&2
    return 1
  fi
}

wt_test_teardown() {
  if [[ -n "${FIX:-}" && -d "$FIX" ]]; then
    rm -rf "$FIX"
  fi
}

# Convenience: create a worktree quickly in tests
wt_quick_new() {
  local branch="$1"
  wt new "$branch" >/dev/null 2>&1
}

# Invoke a global hook directly with the right cwd already set.
run_hook() {
  local hook="$1"; shift
  "$HOME/.config/git/hooks/$hook" "$@"
}
