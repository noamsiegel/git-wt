#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

_source_wt() {
  source "$WT_REPO_ROOT/git-wt"
}

@test "branch_policy_match_repo returns unique matching repo" {
  _source_wt

  run branch_policy_match_repo dev/INFRA-123-platform

  [ "$status" -eq 0 ]
  [ "$output" = "fixrepo2" ]
}

@test "branch_policy_match_repo returns empty output when no repo matches" {
  _source_wt

  run branch_policy_match_repo feature/no-ticket

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "branch_policy_allows is the quiet shared policy predicate" {
  _source_wt

  run branch_policy_allows fixrepo dev/ABC-1-ok
  [ "$status" -eq 0 ]

  run branch_policy_allows fixrepo feature/nope
  [ "$status" -eq 1 ]

  yq -i '.branch_max_length = 10' "$WT_CONFIG"
  cfg_reload
  run branch_policy_allows fixrepo dev/ABC-1-too-long
  [ "$status" -eq 1 ]
}

@test "branch_policy_match_repo picks first repo on ambiguous match" {
  cat > "$WT_CONFIG" <<EOF
repos:
  first-repo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
    branch_patterns:
      - "^shared/[a-z]+$"
  second-repo:
    path: $FIX/canonical2
    worktree_root: $FIX/wt_root2
    base: origin/main
    default_branch: main
    branch_patterns:
      - "^shared/[a-z]+$"
branch_max_length: 80
EOF
  _source_wt

  run branch_policy_match_repo shared/topic

  [ "$status" -eq 0 ]
  [ "$output" = "first-repo" ]
}

@test "branch_policy_match_repo is case-sensitive" {
  _source_wt

  run branch_policy_match_repo dev/abc-123-lower

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "branch_policy_validate accepts branch under repo pattern" {
  _source_wt

  run branch_policy_validate fixrepo dev/ABC-123-valid

  [ "$status" -eq 0 ]
}

@test "branch_policy_validate rejects branch outside repo pattern" {
  _source_wt

  run branch_policy_validate fixrepo dev/INFRA-123-wrong-repo

  [ "$status" -eq 10 ]
  [[ "$output" == *"does not match any configured pattern for repo 'fixrepo'"* ]]
}

@test "branch_policy_validate allows repo with no patterns" {
  cat > "$WT_CONFIG" <<EOF
repos:
  openrepo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
branch_max_length: 80
EOF
  _source_wt

  run branch_policy_validate openrepo any/Branch.Shape_123

  [ "$status" -eq 0 ]
}

@test "branch_policy_emit_cache quotes regex special chars exactly" {
  cat > "$WT_CONFIG" <<EOF
repos:
  quoterepo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
    branch_patterns:
      - '^feat/(ABC|DEF)-[0-9]+-[a-z0-9._-]+$'
      - '^bugfix/[a-z]+[+][0-9]+$'
branch_max_length: 80
EOF
  _source_wt

  branch_policy_emit_cache quoterepo > "$FIX/patterns.body"
  printf 'WT_PATTERNS_quoterepo=(\n' > "$FIX/patterns.sh"
  cat "$FIX/patterns.body" >> "$FIX/patterns.sh"
  printf ')\n' >> "$FIX/patterns.sh"
  source "$FIX/patterns.sh"

  [ "${#WT_PATTERNS_quoterepo[@]}" -eq 2 ]
  [ "${WT_PATTERNS_quoterepo[0]}" = '^feat/(ABC|DEF)-[0-9]+-[a-z0-9._-]+$' ]
  [ "${WT_PATTERNS_quoterepo[1]}" = '^bugfix/[a-z]+[+][0-9]+$' ]
}

@test "branch_policy_emit_cache handles multiple patterns" {
  _source_wt

  mapfile -t emitted < <(branch_policy_emit_cache fixrepo)

  [ "${#emitted[@]}" -eq 2 ]
  [[ "${emitted[0]}" == *ABC* ]]
  [[ "${emitted[1]}" == *pr-* ]]
}

@test "generate_path_cache sanitizes pattern array names with dashes" {
  cat > "$WT_CONFIG" <<EOF
repos:
  repo-with-dash:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
    branch_patterns:
      - "^dash/[a-z]+$"
branch_max_length: 80
EOF

  run wt doctor --install-hooks

  [ "$status" -eq 0 ]
  source "$WT_CACHE"
  [ "${WT_PATTERNS_repo_with_dash[0]}" = '^dash/[a-z]+$' ]
}

@test "hook cache and runtime validation consume same updated regex source" {
  cat > "$WT_CONFIG" <<EOF
repos:
  fixrepo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
    herdr_workspace: fixrepo
    branch_patterns:
      - "^dev/ABC-[0-9]+-[a-z0-9-]+$"
      - "^q3/[A-Z]+-[0-9]+$"
  fixrepo2:
    path: $FIX/canonical2
    worktree_root: $FIX/wt_root2
    base: origin/main
    default_branch: main
    herdr_workspace: fixrepo2
    branch_patterns:
      - "^dev/INFRA-[0-9]+-[a-z0-9-]+$"
branch_max_length: 80
EOF
  wt doctor --install-hooks >/dev/null
  source "$WT_CACHE"
  _source_wt

  run wt new q3/OPS-77
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/OPS-77" ]
  mapfile -t runtime_patterns < <(cfg_branch_patterns fixrepo)
  cache_pattern="${WT_PATTERNS_fixrepo[1]}"
  runtime_pattern="${runtime_patterns[1]}"

  [ "$cache_pattern" = '^q3/[A-Z]+-[0-9]+$' ]
  [ "$runtime_pattern" = "$cache_pattern" ]
}

@test "wt new rejects duplicate issue key with different branch slug" {
  yq -i '.repos.fixrepo.branch_issue_key_regex = "dev/(ABC-[0-9]+)-[a-z0-9-]+$" | .repos.fixrepo.enforce_unique_issue_keys = true' "$WT_CONFIG"

  run wt new dev/ABC-123-first
  [ "$status" -eq 0 ]

  run wt new dev/ABC-123-second
  [ "$status" -eq 20 ]
  [[ "$output" == *"branch issue key 'ABC-123' already has worktree branch 'dev/ABC-123-first'"* ]]
  [[ "$output" == *"--allow-duplicate-issue-key"* ]]
  [ ! -d "$FIX/wt_root/ABC-123-second" ]
}

@test "wt new opt-out allows intentional duplicate issue key branch" {
  yq -i '.repos.fixrepo.branch_issue_key_regex = "dev/(ABC-[0-9]+)-[a-z0-9-]+$" | .repos.fixrepo.enforce_unique_issue_keys = true' "$WT_CONFIG"

  run wt new dev/ABC-124-first
  [ "$status" -eq 0 ]

  run wt new --allow-duplicate-issue-key dev/ABC-124-second
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ABC-124-second" ]
}
@test "wt move rejects duplicate issue key before creating worktree" {
  yq -i '.repos.fixrepo.branch_issue_key_regex = "dev/(ABC-[0-9]+)-[a-z0-9-]+$" | .repos.fixrepo.enforce_unique_issue_keys = true' "$WT_CONFIG"
  wt new dev/ABC-126-first >/dev/null
  printf 'dirty\n' > "$FIX/canonical/move.txt"

  run bash -c 'cd "$1" && wt move "$2"' _ "$FIX/canonical" dev/ABC-126-second
  [ "$status" -eq 20 ]
  [[ "$output" == *"branch issue key 'ABC-126' already has worktree branch 'dev/ABC-126-first'"* ]]
  [ ! -d "$FIX/wt_root/ABC-126-second" ]
}

@test "wt move opt-out allows intentional duplicate issue key branch" {
  yq -i '.repos.fixrepo.branch_issue_key_regex = "dev/(ABC-[0-9]+)-[a-z0-9-]+$" | .repos.fixrepo.enforce_unique_issue_keys = true' "$WT_CONFIG"
  wt new dev/ABC-127-first >/dev/null
  printf 'dirty\n' > "$FIX/canonical/move-opt-out.txt"

  run bash -c 'cd "$1" && wt move --allow-duplicate-issue-key "$2"' _ "$FIX/canonical" dev/ABC-127-second
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ABC-127-second" ]
}


@test "wt new preserves old behavior when issue-key regex is unset" {
  yq -i '.repos.fixrepo.enforce_unique_issue_keys = true' "$WT_CONFIG"

  run wt new dev/ABC-125-first
  [ "$status" -eq 0 ]

  run wt new dev/ABC-125-second
  [ "$status" -eq 0 ]
  [ -d "$FIX/wt_root/ABC-125-second" ]
}
