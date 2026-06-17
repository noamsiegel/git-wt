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

@test "adopt: rejects duplicate issue key creating worktree" {
  yq -i '.repos.fixrepo.branch_issue_key_regex = "dev/(ABC-[0-9]+)-[a-z0-9-]+$" | .repos.fixrepo.enforce_unique_issue_keys = true' "$WT_CONFIG"
  wt new dev/ABC-2-first >/dev/null
  cd "$FIX/canonical"
  git switch --quiet -c dev/ABC-2-second
  git commit --no-verify --quiet --allow-empty -m "feature work"
  git switch --quiet main

  run wt adopt dev/ABC-2-second
  [ "$status" -eq 20 ]
  [[ "$output" == *"branch issue key 'ABC-2' already has worktree branch 'dev/ABC-2-first'"* ]]
  [ ! -d "$FIX/wt_root/ABC-2-second" ]
}

@test "adopt: opt-out allows intentional duplicate issue key branch" {
  yq -i '.repos.fixrepo.branch_issue_key_regex = "dev/(ABC-[0-9]+)-[a-z0-9-]+$" | .repos.fixrepo.enforce_unique_issue_keys = true' "$WT_CONFIG"
  wt new dev/ABC-3-first >/dev/null
  cd "$FIX/canonical"
  git switch --quiet -c dev/ABC-3-second
  git commit --no-verify --quiet --allow-empty -m "feature work"
  git switch --quiet main

  run wt adopt dev/ABC-3-second --allow-duplicate-issue-key
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ABC-3-second" ]
}
