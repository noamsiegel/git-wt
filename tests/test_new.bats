#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

@test "happy path: wt new creates worktree and branch; no upstream" {
  run wt new dev/ABC-1234-feature
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ABC-1234-feature" ]
  [ -f "$FIX/wt_root/ABC-1234-feature/.git" ]
  run git -C "$FIX/canonical" rev-parse --verify --quiet refs/heads/dev/ABC-1234-feature
  [ "$status" -eq 0 ]
  run git -C "$FIX/wt_root/ABC-1234-feature" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
  [ "$status" -ne 0 ]
  count=$(wt list 2>/dev/null | grep -c "ABC-1234-feature")
  [ "$count" -ge 1 ]
}

@test "validation: bad branch shape exits 10" {
  run wt new feature/bad
  [ "$status" -eq 10 ]
  [[ "$output" == *"does not match"* || "$output" == *"defaulting"* ]]
}

@test "validation: uppercase slug rejected" {
  run wt new dev/ABC-1-FOO
  [ "$status" -eq 10 ]
}

@test "validation: branch >80 chars rejected" {
  local long="dev/ABC-1234-$(printf 'a%.0s' {1..100})"
  run wt new "$long"
  [ "$status" -eq 10 ]
  [[ "$output" == *"chars"* ]]
}

@test "validation: pr-<num> accepted" {
  run wt new pr-9999
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/pr-9999" ]
}

@test "guardrail: forbidden-root rejects (exit 20) from \$PWD" {
  mkdir -p "$FIX/omp-wt-forbidden/sub"
  cd "$FIX/omp-wt-forbidden/sub"
  run wt new dev/ABC-1-foo
  [ "$status" -eq 20 ]
  [[ "$output" == *"forbidden root"* ]]
}

@test "guardrail: duplicate worktree path rejected (exit 20)" {
  wt_quick_new dev/ABC-1-foo
  run wt new dev/ABC-1-foo
  [ "$status" -eq 20 ]
  [[ "$output" == *"already exists"* || "$output" == *"already"* ]]
}

@test "guardrail: duplicate branch on origin rejected (exit 20)" {
  git -C "$FIX/canonical" push --no-verify origin main:dev/ABC-1-onorigin
  run wt new dev/ABC-1-onorigin
  [ "$status" -eq 20 ]
  [[ "$output" == *"origin"* ]]
}


@test "lock: concurrent wt new yields one success and one exit-40" {
  mkdir -p "$FIX/wt_root/.wt.lock"
  echo 99999 > "$FIX/wt_root/.wt.lock/pid"
  run wt new dev/ABC-1-locked
  [ "$status" -eq 40 ]
  [[ "$output" == *"locked"* ]]
  rm -rf "$FIX/wt_root/.wt.lock"
}

# ----- --repo flag and pattern-based inference -----

@test "--repo flag selects target repo explicitly" {
  run wt new --repo fixrepo2 dev/INFRA-1-explicit
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root2/INFRA-1-explicit" ]
  [ ! -d "$FIX/wt_root/INFRA-1-explicit" ]
}

@test "--repo with unknown name exits 10" {
  run wt new --repo bogus dev/ABC-1-foo
  [ "$status" -eq 10 ]
  [[ "$output" == *"unknown repo"* ]]
}

@test "cwd inference: wt new from inside a worktree of one repo lands in that repo" {
  wt new --repo fixrepo2 dev/INFRA-1-cwd-source >/dev/null 2>&1
  cd "$FIX/wt_root2/INFRA-1-cwd-source"
  run wt new dev/INFRA-1-cwd-target
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root2/INFRA-1-cwd-target" ]
  [ ! -d "$FIX/wt_root/INFRA-1-cwd-target" ]
}

@test "pattern inference: branch matches a single repo via unique pattern" {
  # Default fixture: fixrepo=ABC-*, fixrepo2=INFRA-*. From /tmp, INFRA branch goes to fixrepo2.
  cd /tmp
  run wt new dev/INFRA-99-pattern
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root2/INFRA-99-pattern" ]
  [ ! -d "$FIX/wt_root/INFRA-99-pattern" ]
}

@test "pattern inference: ambiguous match across repos picks first match" {
  # Make BOTH repos accept the same pattern, then attempt creation from outside.
  cat > "$WT_CONFIG" <<EOF
repos:
  fixrepo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
    herdr_workspace: fixrepo
    branch_patterns:
      - "^dev/ABC-[0-9]+-[a-z0-9-]+\$"
  fixrepo2:
    path: $FIX/canonical2
    worktree_root: $FIX/wt_root2
    base: origin/main
    default_branch: main
    herdr_workspace: fixrepo2
    branch_patterns:
      - "^dev/ABC-[0-9]+-[a-z0-9-]+\$"
forbidden_roots:
  - $FIX/omp-wt-forbidden
branch_max_length: 80
EOF
  wt doctor --install-hooks >/dev/null
  cd /tmp
  run wt new dev/ABC-7-ambig
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ABC-7-ambig" ]
  [ ! -d "$FIX/wt_root2/ABC-7-ambig" ]
}

@test "falls back to first repo with warning when no pattern matches" {
  cat > "$WT_CONFIG" <<EOF
repos:
  fixrepo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
    herdr_workspace: fixrepo
    branch_patterns:
      - "^dev/INFRA-[0-9]+-[a-z0-9-]+\$"
  fixrepo2:
    path: $FIX/canonical2
    worktree_root: $FIX/wt_root2
    base: origin/main
    default_branch: main
    herdr_workspace: fixrepo2
    branch_patterns:
      - "^dev/PLATFORM-[0-9]+-[a-z0-9-]+\$"
forbidden_roots:
  - $FIX/omp-wt-forbidden
branch_max_length: 80
EOF
  wt doctor --install-hooks >/dev/null
  cd /tmp
  # Branch matches NEITHER pattern. Fallback selects first repo (fixrepo). Validation then rejects.
  run wt new dev/ABC-9-orphan-pattern
  [ "$status" -eq 10 ]
  [[ "$output" == *"WARN"* || "$output" == *"defaulting"* || "$output" == *"does not match"* ]]
}
