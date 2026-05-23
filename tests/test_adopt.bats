#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

@test "adopt: moves an existing branch from canonical into a worktree" {
  cd "$FIX/canonical"
  git switch --quiet -c dev/ABC-1-adopt
  git commit --no-verify --quiet --allow-empty -m "feature work"
  git switch --quiet main   # back to main so canonical is clean and adopt can proceed

  run wt adopt dev/ABC-1-adopt
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ABC-1-adopt" ]
  # canonical now parked on main
  cur=$(git -C "$FIX/canonical" rev-parse --abbrev-ref HEAD)
  [ "$cur" = "main" ]
  # The worktree has the branch
  run git -C "$FIX/wt_root/ABC-1-adopt" rev-parse --abbrev-ref HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "dev/ABC-1-adopt" ]
}

@test "adopt: --id override produces friendly path" {
  cd "$FIX/canonical"
  git switch --quiet -c 09-21-ugly_branch_name
  git commit --no-verify --quiet --allow-empty -m wip
  git switch --quiet main

  run wt adopt 09-21-ugly_branch_name --id ugly
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ugly" ]
  [ ! -d "$FIX/wt_root/09-21-ugly_branch_name" ]
}

@test "adopt: refuses dirty canonical (exit 20)" {
  echo dirt > "$FIX/canonical/dirty.txt"
  run wt adopt main
  [ "$status" -eq 20 ]
  [[ "$output" == *"uncommitted"* ]]
}

@test "adopt: refuses nonexistent branch (exit 20)" {
  run wt adopt does-not-exist
  [ "$status" -eq 20 ]
  [[ "$output" == *"does not exist locally"* ]]
}

@test "adopt: rolls back herdr tab failure" {
  cd "$FIX/canonical"
  git switch --quiet -c dev/ABC-1-adopt-rollback
  git commit --no-verify --quiet --allow-empty -m wip
  git switch --quiet main

  WT_HERDR_FAIL_CREATE=1 run wt adopt dev/ABC-1-adopt-rollback
  [ "$status" -eq 50 ]
  [ ! -d "$FIX/wt_root/ABC-1-adopt-rollback" ]
}

@test "adopt --commit-wip: dirty canonical with pending changes succeeds" {
  cd "$FIX/canonical"
  git switch --quiet -c dev/ABC-1-wip
  echo "in-progress work" > work.txt
  # canonical is dirty AND on the feature branch

  run wt adopt dev/ABC-1-wip --commit-wip
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ABC-1-wip" ]

  # The dirty file traveled with the branch as a WIP commit
  run git -C "$FIX/wt_root/ABC-1-wip" log --oneline -1
  [[ "$output" == *"WIP: pre-wt-adopt snapshot"* ]]
  [ -f "$FIX/wt_root/ABC-1-wip/work.txt" ]

  # Canonical is back on main and clean
  cur=$(git -C "$FIX/canonical" rev-parse --abbrev-ref HEAD)
  [ "$cur" = "main" ]
  run git -C "$FIX/canonical" status --porcelain
  [ -z "$output" ]
}

@test "adopt --commit-wip: refuses when canonical is on a different branch than the adopt target" {
  cd "$FIX/canonical"
  git switch --quiet -c dev/ABC-1-mismatch
  git commit --no-verify --quiet --allow-empty -m wip
  git switch --quiet main
  echo dirt > "$FIX/canonical/loose.txt"
  # Canonical is dirty but on main, not on dev/ABC-1-mismatch

  run wt adopt dev/ABC-1-mismatch --commit-wip
  [ "$status" -eq 20 ]
  [[ "$output" == *"requires canonical to be on"* ]]
}
