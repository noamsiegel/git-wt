#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

# Rewrite the fixture config for a single repo, injecting extra repo-level YAML
# ($1, already indented 4 spaces), then refresh the path cache.
_write_config() {
  cat > "$WT_CONFIG" <<EOF
repos:
  fixrepo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
    branch_patterns:
      - "^dev/ABC-[0-9]+-[a-z0-9-]+\$"
      - "^pr-[0-9]+\$"
${1}
forbidden_roots:
  - $FIX/omp-wt-forbidden
branch_max_length: 80
EOF
  wt doctor --install-hooks >/dev/null 2>&1 || true
}

@test "worktree_symlinks links a configured gitignored file into the worktree" {
  echo "SECRET=1" > "$FIX/canonical/.env.local"
  _write_config "    worktree_symlinks:
      - .env.local"
  run wt new dev/ABC-1-sym
  [ "$status" -eq 0 ]
  [ -L "$FIX/wt_root/ABC-1-sym/.env.local" ]
  [ "$(cat "$FIX/wt_root/ABC-1-sym/.env.local")" = "SECRET=1" ]
}

@test "worktree_symlinks never clobbers a file already placed in the worktree" {
  # .worktreeinclude copies the file first; the symlink step must then skip it,
  # leaving the copied regular file (not a symlink) in place.
  echo ".env.shared" > "$FIX/canonical/.gitignore"
  echo "SHARED=1" > "$FIX/canonical/.env.shared"
  echo ".env.shared" > "$FIX/canonical/.worktreeinclude"
  _write_config "    worktree_symlinks:
      - .env.shared"
  run wt new dev/ABC-1-noclobber
  [ "$status" -eq 0 ]
  [ ! -L "$FIX/wt_root/ABC-1-noclobber/.env.shared" ]
  [ -f "$FIX/wt_root/ABC-1-noclobber/.env.shared" ]
  [ "$(cat "$FIX/wt_root/ABC-1-noclobber/.env.shared")" = "SHARED=1" ]
}

@test "worktree_symlinks missing source warns but does not fail wt new" {
  _write_config "    worktree_symlinks:
      - .does-not-exist"
  run wt new dev/ABC-1-missing
  [ "$status" -eq 0 ]
  [[ "$output" == *"source missing"* ]]
  [ ! -e "$FIX/wt_root/ABC-1-missing/.does-not-exist" ]
}

@test "worktree_symlinks refuses path-escape entries" {
  _write_config "    worktree_symlinks:
      - ../evil"
  run wt new dev/ABC-1-escape
  [ "$status" -eq 0 ]
  [[ "$output" == *"refusing unsafe path"* ]]
  [ ! -e "$FIX/wt_root/evil" ]
}

@test "setup_command runs in the new worktree" {
  _write_config "    setup_command: \"touch SETUP_RAN\""
  run wt new dev/ABC-1-setup
  [ "$status" -eq 0 ]
  [ -f "$FIX/wt_root/ABC-1-setup/SETUP_RAN" ]
}

@test "failing setup_command warns but wt new still succeeds" {
  _write_config "    setup_command: \"exit 7\""
  run wt new dev/ABC-1-setupfail
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup_command failed (exit 7)"* ]]
  [ -d "$FIX/wt_root/ABC-1-setupfail" ]
}
