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
}

@test "doctor reports dirty canonical as WARN, not FAIL" {
  touch "$FIX/canonical/dirty_file"
  run wt doctor
  [ "$status" -eq 0 ]                                  # WARN doesn't fail
  [[ "$output" == *"[fixrepo] canonical clean"*"WARN"* ]]
}

@test "doctor reports off-default-branch as WARN" {
  git -C "$FIX/canonical" switch --quiet -c feature/foo
  run wt doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[fixrepo] canonical on main"*"WARN"* ]]
}


@test "doctor with missing config exits 30" {
  rm "$WT_CONFIG"
  run wt doctor
  [ "$status" -eq 30 ]
  [[ "$output" == *"config not readable"* ]]
}
