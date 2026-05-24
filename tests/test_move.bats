#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

@test "move: relocates uncommitted work from canonical to a new worktree" {
  cd "$FIX/canonical"
  echo "in-progress edit" > work.txt
  echo "untracked too" > untracked.txt

  run wt move dev/ABC-1-relocate
  [ "$status" -eq 0 ]
  [[ "$output" == *"moved"* ]]
  [ -d "$FIX/wt_root/ABC-1-relocate" ]

  # Files moved to the worktree
  [ -f "$FIX/wt_root/ABC-1-relocate/work.txt" ]
  [ -f "$FIX/wt_root/ABC-1-relocate/untracked.txt" ]
  run cat "$FIX/wt_root/ABC-1-relocate/work.txt"
  [ "$output" = "in-progress edit" ]

  # Canonical is clean and parked on main
  cur=$(git -C "$FIX/canonical" rev-parse --abbrev-ref HEAD)
  [ "$cur" = "main" ]
  [ ! -f "$FIX/canonical/work.txt" ]
  [ ! -f "$FIX/canonical/untracked.txt" ]

  # New branch exists at worktree's HEAD
  run git -C "$FIX/wt_root/ABC-1-relocate" rev-parse --abbrev-ref HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "dev/ABC-1-relocate" ]

  # No leftover stash in canonical
  run git -C "$FIX/canonical" stash list
  [ -z "$output" ]
}

@test "move: preserves staged-vs-unstaged split" {
  cd "$FIX/canonical"
  echo "will be staged" > staged.txt
  echo "will stay modified" > modified.txt
  git add staged.txt

  run wt move dev/ABC-2-split
  [ "$status" -eq 0 ]

  # staged.txt should be staged in the new worktree
  run git -C "$FIX/wt_root/ABC-2-split" diff --cached --name-only
  [[ "$output" == *"staged.txt"* ]]

  # modified.txt should be untracked in the new worktree (it was uncommitted+untracked before staging)
  [ -f "$FIX/wt_root/ABC-2-split/modified.txt" ]
}

@test "move: refuses clean canonical (exit 20)" {
  cd "$FIX/canonical"
  run wt move dev/ABC-3-clean
  [ "$status" -eq 20 ]
  [[ "$output" == *"clean"* ]]
  [[ "$output" == *"wt new"* ]]
}

@test "move: refuses non-default-branch canonical (exit 20)" {
  cd "$FIX/canonical"
  git switch --quiet -c some-feature
  echo dirty > work.txt
  run wt move dev/ABC-4-wrong-branch
  [ "$status" -eq 20 ]
  [[ "$output" == *"some-feature"* ]]
  [[ "$output" == *"wt adopt"* ]]
}

@test "move: rejects invalid branch shape (exit 10)" {
  cd "$FIX/canonical"
  echo dirty > work.txt
  run wt move bad-shape-no-prefix
  [ "$status" -eq 10 ]
  [[ "$output" == *"does not match"* ]]
}

@test "move: rolls back stash on worktree-add failure" {
  cd "$FIX/canonical"
  echo dirty > work.txt

  # Pre-create the target path so 'git worktree add' will fail.
  mkdir -p "$FIX/wt_root/ABC-5-rollback"
  touch "$FIX/wt_root/ABC-5-rollback/blocker"

  run wt move dev/ABC-5-rollback
  [ "$status" -eq 20 ]   # caught by guardrail "target path already exists"
  # Either it caught before stashing (clean canonical), or it rolled the stash back.
  cur=$(git -C "$FIX/canonical" rev-parse --abbrev-ref HEAD)
  [ "$cur" = "main" ]
  # work.txt should still be in canonical (either never stashed, or stash popped back)
  [ -f "$FIX/canonical/work.txt" ]
}

@test "move: refuses when target branch already exists locally (exit 20)" {
  cd "$FIX/canonical"
  git branch dev/ABC-6-exists
  echo dirty > work.txt

  run wt move dev/ABC-6-exists
  [ "$status" -eq 20 ]
  [[ "$output" == *"already exists locally"* ]]
}

@test "move: refuses from inside a worktree (exit 20)" {
  cd "$FIX/canonical"
  run wt new dev/ABC-7-existing-wt
  [ "$status" -eq 0 ]

  cd "$FIX/wt_root/ABC-7-existing-wt"
  echo dirty > work.txt

  run wt move dev/ABC-7-from-wt
  [ "$status" -eq 20 ]
  [[ "$output" == *"canonical"* ]]
}

@test "move: --repo override works when run from outside any repo" {
  cd "$FIX/canonical"
  echo dirty > work.txt
  # Move cwd outside any configured repo
  cd "$FIX"

  run wt move --repo fixrepo dev/ABC-8-override
  # From outside canonical, the cwd guard fails. --repo override path expects to find canonical dirty.
  # This validates the explicit-repo path: cfg lookup succeeds; cwd-based 'canonical' check is bypassed.
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ABC-8-override" ]
  [ -f "$FIX/wt_root/ABC-8-override/work.txt" ]
}
