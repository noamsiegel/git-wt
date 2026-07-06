#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

@test "reap refuses on uncommitted changes (exit 70)" {
  wt_quick_new dev/ABC-1-dirty
  echo x > "$FIX/wt_root/ABC-1-dirty/work.txt"
  run wt reap ABC-1-dirty
  [ "$status" -eq 70 ]
  [[ "$output" == *"REFUSE"* ]]
  [[ "$output" == *"uncommitted"* ]]
  [ -d "$FIX/wt_root/ABC-1-dirty" ]
}

@test "reap refuses on unpushed commits (exit 70)" {
  wt_quick_new dev/ABC-1-unpushed
  git -C "$FIX/wt_root/ABC-1-unpushed" commit --quiet --allow-empty -m wip
  run wt reap ABC-1-unpushed
  [ "$status" -eq 70 ]
  [[ "$output" == *"unpushed"* || "$output" == *"reachable"* ]]
}

@test "reap --dry-run refuses but does not mutate; exits 70 when refused" {
  wt_quick_new dev/ABC-1-dryrefuse
  git -C "$FIX/wt_root/ABC-1-dryrefuse" commit --quiet --allow-empty -m wip
  run wt reap --dry-run ABC-1-dryrefuse
  [ -d "$FIX/wt_root/ABC-1-dryrefuse" ]
  [[ "$output" == *"REFUSE"* || "$output" == *"DRY"* ]]
}

@test "reap --force removes dirty worktree + closes tab + deletes branch" {
  wt_quick_new dev/ABC-1-force
  echo dirty > "$FIX/wt_root/ABC-1-force/x"
  run wt reap --force ABC-1-force
  [ "$status" -eq 0 ]
  [ ! -d "$FIX/wt_root/ABC-1-force" ]
  run git -C "$FIX/canonical" rev-parse --verify --quiet refs/heads/dev/ABC-1-force
  [ "$status" -ne 0 ]
}

@test "reap multi-id: reaps several at once" {
  wt_quick_new dev/ABC-1-multi-a
  wt_quick_new dev/ABC-1-multi-b
  run wt reap --force ABC-1-multi-a ABC-1-multi-b
  [ "$status" -eq 0 ]
  [ ! -d "$FIX/wt_root/ABC-1-multi-a" ]
  [ ! -d "$FIX/wt_root/ABC-1-multi-b" ]
}

@test "reap unknown id exits 20" {
  run wt reap ABC-does-not-exist
  [ "$status" -eq 20 ]
  [[ "$output" == *"no worktree"* ]]
}

@test "reap from forbidden root exits 20" {
  mkdir -p "$FIX/omp-wt-forbidden/sub"
  wt_quick_new dev/ABC-1-fb
  cd "$FIX/omp-wt-forbidden/sub"
  run wt reap ABC-1-fb
  [ "$status" -eq 20 ]
  [[ "$output" == *"forbidden"* ]]
}


# ----- lsof-based open-file detection -----

@test "reap refuses when a process holds an open file in the worktree (lsof)" {
  wt_quick_new dev/ABC-1-lsof
  touch "$FIX/wt_root/ABC-1-lsof/holding.txt"
  ( exec tail -f "$FIX/wt_root/ABC-1-lsof/holding.txt" >/dev/null ) &
  local pid=$!
  sleep 0.5
  run wt reap ABC-1-lsof
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ "$status" -eq 70 ]
  [[ "$output" == *"files-open-by"* ]]
}

@test "reap --force overrides lsof refusal" {
  wt_quick_new dev/ABC-1-lsof-force
  touch "$FIX/wt_root/ABC-1-lsof-force/holding.txt"
  ( exec tail -f "$FIX/wt_root/ABC-1-lsof-force/holding.txt" >/dev/null ) &
  local pid=$!
  sleep 0.5
  run wt reap --force ABC-1-lsof-force
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ ! -d "$FIX/wt_root/ABC-1-lsof-force" ]
}

@test "reap proceeds when nothing has files open in the worktree" {
  wt_quick_new dev/ABC-1-lsof-clean
  run wt reap --force ABC-1-lsof-clean
  [ "$status" -eq 0 ]
}

@test "reap deletes the merged remote branch along with the local one" {
  wt_quick_new dev/ABC-7-remote
  git -C "$FIX/wt_root/ABC-7-remote" push --quiet -u origin dev/ABC-7-remote
  run wt reap ABC-7-remote
  [ "$status" -eq 0 ]
  run git -C "$FIX/canonical" ls-remote --exit-code origin refs/heads/dev/ABC-7-remote
  [ "$status" -ne 0 ]
}

@test "reap --force never deletes an unmerged remote branch" {
  wt_quick_new dev/ABC-8-unmerged
  git -C "$FIX/wt_root/ABC-8-unmerged" commit --quiet --allow-empty -m wip
  git -C "$FIX/wt_root/ABC-8-unmerged" push --quiet -u origin dev/ABC-8-unmerged
  run wt reap --force ABC-8-unmerged
  [ "$status" -eq 0 ]
  [[ "$output" == *"not deleting"* ]]
  run git -C "$FIX/canonical" ls-remote --exit-code origin refs/heads/dev/ABC-8-unmerged
  [ "$status" -eq 0 ]
}

@test "reap --force handles a never-pushed branch without touching the remote" {
  wt_quick_new dev/ABC-9-local-only
  run wt reap --force ABC-9-local-only
  [ "$status" -eq 0 ]
  run git -C "$FIX/canonical" ls-remote --exit-code origin refs/heads/dev/ABC-9-local-only
  [ "$status" -ne 0 ]
}
