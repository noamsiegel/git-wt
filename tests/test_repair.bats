#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

@test "repair removes stale lock from dead pid" {
  mkdir -p "$FIX/wt_root/.wt.lock"
  echo 99999 > "$FIX/wt_root/.wt.lock/pid"
  # Auto-answer y to prompts
  run bash -c 'yes y | wt repair'
  [ "$status" -eq 0 ]
  [ ! -d "$FIX/wt_root/.wt.lock" ]
}

@test "repair detects orphan herdr tab (cwd missing)" {
  wt_quick_new dev/ABC-1-orphan
  # remove worktree dir to create orphan tab
  rm -rf "$FIX/wt_root/ABC-1-orphan"
  run bash -c 'yes y | wt repair'
  [ "$status" -eq 0 ]
  [[ "$output" == *"cwd missing"* || "$output" == *"reconciling"* ]]
}

@test "repair from forbidden root exits 20" {
  mkdir -p "$FIX/omp-wt-forbidden/x"
  cd "$FIX/omp-wt-forbidden/x"
  run wt repair
  [ "$status" -eq 20 ]
}
