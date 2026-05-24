#!/usr/bin/env bats
load lib/setup.bash

setup() {
  wt_test_setup
  source "$WT_REPO_ROOT/git-wt"
}

teardown() {
  wt_test_teardown
}

@test "cfg_repo_record returns all fields for a known repo" {
  run cfg_repo_record fixrepo
  [ "$status" -eq 0 ]
  wt_record_fields "$output" repo path worktree_root base default_branch herdr_workspace
  [ "$repo" = "fixrepo" ]
  [ "$path" = "$FIX/canonical" ]
  [ "$worktree_root" = "$FIX/wt_root" ]
  [ "$base" = "origin/main" ]
  [ "$default_branch" = "main" ]
  [ "$herdr_workspace" = "fixrepo" ]
}

@test "cfg_repo_record returns non-zero for an unknown repo" {
  run cfg_repo_record missing
  [ "$status" -ne 0 ]
  [ "$output" = "" ]
}

@test "cfg_each_repo_record emits one record per configured repo in stable order" {
  run cfg_each_repo_record
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]

  wt_record_fields "${lines[0]}" repo1 _path1 _root1 _base1 _default1 _workspace1
  wt_record_fields "${lines[1]}" repo2 _path2 _root2 _base2 _default2 _workspace2
  [ "$repo1" = "fixrepo" ]
  [ "$repo2" = "fixrepo2" ]
}

@test "cfg_reload makes a fresh write visible without restarting wt" {
  run cfg_repo_record later
  [ "$status" -ne 0 ]

  REPO=later VALUE="$FIX/later" yq -i '.repos[strenv(REPO)].path = strenv(VALUE)' "$WT_CONFIG"
  REPO=later VALUE="$FIX/later-wt" yq -i '.repos[strenv(REPO)].worktree_root = strenv(VALUE)' "$WT_CONFIG"
  REPO=later VALUE=origin/trunk yq -i '.repos[strenv(REPO)].base = strenv(VALUE)' "$WT_CONFIG"
  REPO=later VALUE=trunk yq -i '.repos[strenv(REPO)].default_branch = strenv(VALUE)' "$WT_CONFIG"

  cfg_reload
  run cfg_repo_record later
  [ "$status" -eq 0 ]
  wt_record_fields "$output" repo path worktree_root base default_branch herdr_workspace
  [ "$repo" = "later" ]
  [ "$path" = "$FIX/later" ]
  [ "$worktree_root" = "$FIX/later-wt" ]
  [ "$base" = "origin/trunk" ]
  [ "$default_branch" = "trunk" ]
  [ "$herdr_workspace" = "" ]
}

@test "cfg_repo_record preserves empty fields without shifting" {
  REPO=empty VALUE="$FIX/empty" yq -i '.repos[strenv(REPO)].path = strenv(VALUE)' "$WT_CONFIG"
  REPO=empty VALUE="$FIX/empty-wt" yq -i '.repos[strenv(REPO)].worktree_root = strenv(VALUE)' "$WT_CONFIG"
  REPO=empty VALUE=origin/main yq -i '.repos[strenv(REPO)].base = strenv(VALUE)' "$WT_CONFIG"
  REPO=empty VALUE=main yq -i '.repos[strenv(REPO)].default_branch = strenv(VALUE)' "$WT_CONFIG"
  cfg_reload

  run cfg_repo_record empty
  [ "$status" -eq 0 ]
  wt_record_fields "$output" repo path worktree_root base default_branch herdr_workspace
  [ "$repo" = "empty" ]
  [ "$path" = "$FIX/empty" ]
  [ "$worktree_root" = "$FIX/empty-wt" ]
  [ "$base" = "origin/main" ]
  [ "$default_branch" = "main" ]
  [ "$herdr_workspace" = "" ]
}

@test "cfg_repo_record expands {repo} templates" {
  yq -i '.defaults.worktree_root = strenv(FIX) + "/wt-{repo}"' "$WT_CONFIG"
  yq -i '.defaults.herdr_workspace = "team-{repo}"' "$WT_CONFIG"
  yq -i 'del(.repos.fixrepo.worktree_root)' "$WT_CONFIG"
  yq -i 'del(.repos.fixrepo.herdr_workspace)' "$WT_CONFIG"
  cfg_reload

  run cfg_repo_record fixrepo
  [ "$status" -eq 0 ]
  wt_record_fields "$output" repo _path worktree_root _base _default_branch herdr_workspace
  [ "$repo" = "fixrepo" ]
  [ "$worktree_root" = "$FIX/wt-fixrepo" ]
  [ "$herdr_workspace" = "team-fixrepo" ]
}
