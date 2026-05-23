#!/usr/bin/env bats
load lib/setup.bash

setup() {
  wt_test_setup
  # Simulate an inbound PR: push a branch on the bare remote at pull/N/head
  git -C "$FIX/canonical" commit --no-verify --quiet --allow-empty -m "PR head commit"
  git -C "$FIX/canonical" push --quiet origin HEAD:refs/pull/42/head
  git -C "$FIX/canonical" reset --hard HEAD~1   # rewind canonical back
}

teardown() { wt_test_teardown; }

@test "pr fetches pull/<n>/head into a worktree" {
  run wt pr 42
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/pr-42" ]
  cur=$(git -C "$FIX/wt_root/pr-42" rev-parse --abbrev-ref HEAD)
  [ "$cur" = "pr-42" ]
}

@test "pr nonexistent number fails" {
  run wt pr 999999
  [ "$status" -ne 0 ]
}

@test "pr bad arg exits 10" {
  run wt pr foo
  [ "$status" -eq 10 ]
}

@test "pr duplicate refused" {
  wt pr 42 >/dev/null 2>&1
  run wt pr 42
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* || "$output" == *"path"* ]]
}
