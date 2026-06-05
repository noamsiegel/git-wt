#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

@test "doctor passes on fresh fixture" {
  run wt doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"bash >= 4"*"PASS"* ]]
  [[ "$output" == *"yq (mikefarah/yq)"*"PASS"* ]]
  [[ "$output" == *"git available"*"PASS"* ]]
  [[ "$output" != *"herdr available"* ]]
  [[ "$output" != *"herdr server running"* ]]
  [[ "$output" == *"[fixrepo] canonical exists"*"PASS"* ]]
  [[ "$output" == *"[fixrepo] canonical on main"*"PASS"* ]]
  [[ "$output" == *"[fixrepo] canonical clean"*"PASS"* ]]
  [[ "$output" == *"no worktrees under forbidden_roots"*"PASS"* ]]
}

@test "doctor --install-hooks writes path cache" {
  rm -f "$WT_CACHE"
  run wt doctor --install-hooks
  [ "$status" -eq 0 ]
  [ -r "$WT_CACHE" ]
  grep -q "WT_CANONICAL_PATHS=" "$WT_CACHE"
  grep -q "$FIX/canonical" "$WT_CACHE"
  grep -q "WT_PATTERNS_fixrepo=" "$WT_CACHE"
  ! grep -q "declare -A" "$WT_CACHE"
  run /bin/bash -c "source '$WT_CACHE'; wt_repo_by_path '$FIX/canonical'"
  [ "$status" -eq 0 ]
  [ "$output" = "fixrepo" ]
  run /bin/bash -c "source '$WT_CACHE'; wt_repo_by_path '$FIX/canonical2'"
  [ "$status" -eq 0 ]
  [ "$output" = "fixrepo2" ]
}

@test "doctor reports dirty canonical as WARN, not FAIL" {
  touch "$FIX/canonical/dirty_file"
  run wt doctor
  [ "$status" -eq 0 ]                                  # WARN doesn't fail
  [[ "$output" == *"[fixrepo] canonical clean"*"WARN"* ]]
}

@test "doctor reports off-default-branch as FAIL" {
  git -C "$FIX/canonical" switch --quiet -c feature/foo
  run wt doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fixrepo] canonical on main"*"FAIL"* ]]
}


@test "doctor with missing config exits 30" {
  rm "$WT_CONFIG"
  run wt doctor
  [ "$status" -eq 30 ]
  [[ "$output" == *"config not readable"* ]]
}

@test "doctor flags registered worktree under forbidden root as external WARN" {
  git -C "$FIX/canonical" worktree add "$FIX/omp-wt-forbidden/ext-1" -b dev/ABC-1-ext >/dev/null 2>&1
  run wt doctor
  [ "$status" -eq 0 ]   # external is a WARN, not a hard fail
  [[ "$output" == *"no worktrees under forbidden_roots"*"WARN (external: 1)"* ]]
}

@test "doctor --worktree reports per-worktree health (exit 0)" {
  wt_quick_new dev/ABC-1-health
  run wt doctor --worktree ABC-1-health
  [ "$status" -eq 0 ]
  [[ "$output" == *"worktree ABC-1-health"* ]]
  [[ "$output" == *"node_modules"* ]]
  [[ "$output" == *"effective core.hooksPath"* ]]
  [[ "$output" == *"prunable worktree metadata"* ]]
}

@test "doctor --worktree unknown id exits 20" {
  run wt doctor --worktree nope
  [ "$status" -eq 20 ]
}

@test "doctor warns when a repo's local core.hooksPath overrides wt hooks" {
  git -C "$FIX/canonical" config core.hooksPath /tmp/some-other-hooks
  run wt doctor
  [[ "$output" == *"[fixrepo] effective hooks"*"WARN (local override: /tmp/some-other-hooks)"* ]]
}
