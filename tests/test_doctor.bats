#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }


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

_configure_linked_deps() {
  _write_config ""
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].path = "deps/node_modules"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].source = "canonical"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].drift_files[0] = "deps/yarn.lock"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].required_paths[0] = ".bin/vitest"' "$WT_CONFIG"
  wt doctor --install-hooks >/dev/null 2>&1 || true
}

_create_canonical_deps() {
  mkdir -p "$FIX/canonical/deps/node_modules/.bin"
  echo "vitest" > "$FIX/canonical/deps/node_modules/.bin/vitest"
  echo "lock" > "$FIX/canonical/deps/yarn.lock"
  git -C "$FIX/canonical" add deps/yarn.lock
  git -C "$FIX/canonical" commit --no-verify -q -m "add lockfile"
  git -C "$FIX/canonical" push -q origin main
  touch "$FIX/canonical/deps/node_modules" "$FIX/canonical/deps/node_modules/.bin/vitest"
}
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
  [[ "$output" == *"worktree_symlinks"*"INFO"* ]]
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

@test "doctor --worktree reports linked symlink PASS" {
  _create_canonical_deps
  _configure_linked_deps
  wt new dev/ABC-1-doctor-pass >/dev/null

  run wt doctor --worktree ABC-1-doctor-pass
  [[ "$output" == *"linked deps/node_modules"*"PASS"* ]]
  [[ "$output" == *"source deps/node_modules"*"PASS"* ]]
  [[ "$output" == *"drift deps/yarn.lock"*"PASS"* ]]
}

@test "doctor --worktree reports linked symlink WARN when missing" {
  _create_canonical_deps
  _configure_linked_deps
  wt new dev/ABC-1-doctor-link-missing >/dev/null
  rm "$FIX/wt_root/ABC-1-doctor-link-missing/deps/node_modules"

  run wt doctor --worktree ABC-1-doctor-link-missing
  [[ "$output" == *"linked deps/node_modules"*"WARN (missing/not expected symlink)"* ]]
}

@test "doctor --worktree reports source WARN when canonical dependency dir missing" {
  echo "lock" > "$FIX/canonical/deps.lock"
  _configure_linked_deps
  wt new dev/ABC-1-doctor-source-missing >/dev/null

  run wt doctor --worktree ABC-1-doctor-source-missing
  [[ "$output" == *"source deps/node_modules"*"WARN (canonical deps missing)"* ]]
}

@test "doctor --worktree reports drift WARN when lockfile differs" {
  _create_canonical_deps
  _configure_linked_deps
  wt new dev/ABC-1-doctor-drift >/dev/null
  echo "changed" > "$FIX/wt_root/ABC-1-doctor-drift/deps/yarn.lock"

  run wt doctor --worktree ABC-1-doctor-drift
  [[ "$output" == *"drift deps/yarn.lock"*"WARN"* ]]
}

@test "doctor --worktree reports deps WARN when required binary is absent" {
  mkdir -p "$FIX/canonical/deps/node_modules/.bin"
  echo "lock" > "$FIX/canonical/deps/yarn.lock"
  git -C "$FIX/canonical" add deps/yarn.lock
  git -C "$FIX/canonical" commit --no-verify -q -m "add lockfile"
  git -C "$FIX/canonical" push -q origin main
  touch "$FIX/canonical/deps/node_modules"
  _configure_linked_deps
  wt new dev/ABC-1-doctor-deps-missing >/dev/null

  run wt doctor --worktree ABC-1-doctor-deps-missing
  [[ "$output" == *"deps deps/node_modules"*"WARN"* ]]
}
