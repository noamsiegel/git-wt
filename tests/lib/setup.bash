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
  export HOME="$FIX/home"
  mkdir -p "$HOME/.config/git/hooks"

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
  wt_install_test_hooks

  # Build the path cache so hooks can be tested against this fixture.
  if ! wt doctor --install-hooks >"$FIX/doctor.log" 2>&1; then
    echo "wt doctor --install-hooks failed; output follows:" >&2
    cat "$FIX/doctor.log" >&2
    return 1
  fi
}

wt_install_test_hooks() {
  local hooks_dir="$HOME/.config/git/hooks"
  mkdir -p "$hooks_dir"

  cat > "$hooks_dir/_wt-chain" <<'EOF'
#!/usr/bin/env bash
set -e
common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
repo_hook="$common_dir/hooks/$(basename "$0")"
if [[ -x "$repo_hook" ]]; then
  self_real=$(realpath "$0" 2>/dev/null || echo "$0")
  hook_real=$(realpath "$repo_hook" 2>/dev/null || echo "$repo_hook")
  if [[ "$self_real" != "$hook_real" ]]; then
    exec "$repo_hook" "$@"
  fi
fi
exit 0
EOF
  chmod +x "$hooks_dir/_wt-chain"

  cat > "$hooks_dir/pre-commit" <<'EOF'
#!/usr/bin/env bash
set -e

WT_CACHE="${WT_CACHE:-$HOME/.config/wt/paths.cache}"

exec_chain() {
  local common_dir repo_hook
  common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
  repo_hook="$common_dir/hooks/$(basename "$0")"
  if [[ -x "$repo_hook" && "$(realpath "$repo_hook")" != "$(realpath "$0")" ]]; then
    WT_HOOK_NEXT="$repo_hook" exec "$repo_hook" "$@"
  fi
  exit 0
}

[[ -r "$WT_CACHE" ]] || exec_chain "$@"
source "$WT_CACHE" 2>/dev/null || exec_chain "$@"

canonical_git=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exec_chain "$@"
toplevel=$(dirname "$canonical_git")
repo="${WT_REPO_BY_PATH[$toplevel]:-}"
[[ -z "$repo" ]] && exec_chain "$@"

gd=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || exec_chain "$@"
cd=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exec_chain "$@"

if [[ "$gd" == "$cd" ]]; then
  printf '\n\033[31m═══ wt: refusing to commit in canonical checkout ═══\033[0m\n' >&2
  printf '  repo: %s\n' "$repo" >&2
  printf '  path: %s\n' "$toplevel" >&2
  printf '\n  canonical is read-only — work belongs in a worktree.\n' >&2
  exit 1
fi

exec_chain "$@"
EOF
  chmod +x "$hooks_dir/pre-commit"

  cat > "$hooks_dir/pre-push" <<'EOF'
#!/usr/bin/env bash
set -e

WT_CACHE="${WT_CACHE:-$HOME/.config/wt/paths.cache}"

tmp=$(mktemp -t wt-prepush.XXXXXX)
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"

exec_chain() {
  local common_dir repo_hook
  common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
  repo_hook="$common_dir/hooks/$(basename "$0")"
  if [[ -x "$repo_hook" && "$(realpath "$repo_hook")" != "$(realpath "$0")" ]]; then
    WT_HOOK_NEXT="$repo_hook" exec "$repo_hook" "$@" < "$tmp"
  fi
  exit 0
}

[[ -r "$WT_CACHE" ]] || exec_chain "$@"
source "$WT_CACHE" 2>/dev/null || exec_chain "$@"

canonical_git=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exec_chain "$@"
toplevel=$(dirname "$canonical_git")
repo="${WT_REPO_BY_PATH[$toplevel]:-}"
[[ -z "$repo" ]] && exec_chain "$@"

[[ "${WT_HOOK_ENFORCE_BRANCH_NAMES:-false}" == "true" ]] || exec_chain "$@"

patterns_var="WT_PATTERNS_${repo//[^a-zA-Z0-9_]/_}[@]"
patterns=("${!patterns_var}")

fail=0
while read -r local_ref local_sha _remote_ref _remote_sha; do
  [[ -z "$local_ref" ]] && continue
  branch="${local_ref#refs/heads/}"
  [[ "$local_sha" == "0000000000000000000000000000000000000000" ]] && continue
  [[ "$local_ref" == "$branch" ]] && continue

  matched=0
  for p in "${patterns[@]}"; do
    if [[ "$branch" =~ $p ]]; then matched=1; break; fi
  done
  if (( matched == 0 )); then
    printf '\033[31mwt pre-push: rejected branch name\033[0m: %s\n' "$branch" >&2
    printf 'allowed patterns for repo %s:\n' "$repo" >&2
    for p in "${patterns[@]}"; do printf '  %s\n' "$p" >&2; done
    printf 'bypass with: git push --no-verify\n' >&2
    fail=1
  fi
done < "$tmp"

if (( fail == 1 )); then
  exit 1
fi

exec_chain "$@"
EOF
  chmod +x "$hooks_dir/pre-push"

  cat > "$hooks_dir/post-checkout" <<'EOF'
#!/usr/bin/env bash
set -e

WT_CACHE="${WT_CACHE:-$HOME/.config/wt/paths.cache}"

exec_chain() {
  local common_dir repo_hook
  common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
  repo_hook="$common_dir/hooks/$(basename "$0")"
  if [[ -x "$repo_hook" && "$(realpath "$repo_hook")" != "$(realpath "$0")" ]]; then
    WT_HOOK_NEXT="$repo_hook" exec "$repo_hook" "$@"
  fi
  exit 0
}

flag="${3:-}"
[[ "$flag" == "1" ]] || exec_chain "$@"

[[ -r "$WT_CACHE" ]] || exec_chain "$@"
source "$WT_CACHE" 2>/dev/null || exec_chain "$@"

canonical_git=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exec_chain "$@"
toplevel=$(dirname "$canonical_git")
repo="${WT_REPO_BY_PATH[$toplevel]:-}"
[[ -z "$repo" ]] && exec_chain "$@"

gd=$(git rev-parse --git-dir 2>/dev/null)
cd=$(git rev-parse --git-common-dir 2>/dev/null)
[[ "$gd" == "$cd" ]] || exec_chain "$@"

WT_CONFIG_FILE="${WT_CONFIG:-$HOME/.config/wt/config.yaml}"
default_branch=$(REPO="$repo" yq -r '.repos[strenv(REPO)].default_branch // .defaults.default_branch // "main"' "$WT_CONFIG_FILE" 2>/dev/null) || exec_chain "$@"

current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exec_chain "$@"
if [[ "$current" != "$default_branch" ]]; then
  printf '\n\033[31m═══ wt: canonical checkout left %s ═══\033[0m\n' "$default_branch" >&2
  printf '  repo: %s\n' "$repo" >&2
  printf '  now on: %s\n' "$current" >&2
fi

exec_chain "$@"
EOF
  chmod +x "$hooks_dir/post-checkout"

  ln -s "$hooks_dir/_wt-chain" "$hooks_dir/commit-msg"
  ln -s "$hooks_dir/_wt-chain" "$hooks_dir/post-merge"
  ln -s "$hooks_dir/_wt-chain" "$hooks_dir/prepare-commit-msg"
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
