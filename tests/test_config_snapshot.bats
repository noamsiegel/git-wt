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

@test "cfg_bootstrap_linked_dirs parses structured linked dirs" {
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].path = "deps/node_modules"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].source = "canonical"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].drift_files[0] = "deps/yarn.lock"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].drift_files[1] = "deps/package.json"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].required_paths[0] = ".bin/vitest"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].required_paths[1] = ".bin/tsc"' "$WT_CONFIG"
  cfg_reload

  run cfg_bootstrap_linked_dirs fixrepo
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  IFS=$'\034' read -r path source drift_files required_paths <<< "$output"
  [ "$path" = "deps/node_modules" ]
  [ "$source" = "canonical" ]
  [ "$drift_files" = "deps/yarn.lock\ndeps/package.json" ]
  [ "$required_paths" = ".bin/vitest\n.bin/tsc" ]
}

@test "repo bootstrap linked dirs replace defaults" {
  yq -i '.defaults.bootstrap.linked_dirs[0].path = "default/node_modules"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].path = "repo/node_modules"' "$WT_CONFIG"
  cfg_reload

  run cfg_bootstrap_linked_dirs fixrepo
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  IFS=$'\034' read -r path _source _drift_files _required_paths <<< "$output"
  [ "$path" = "repo/node_modules" ]
}

@test "cfg_bootstrap_env_symlinks emits legacy worktree_symlinks when structured env symlinks absent" {
  yq -i '.repos.fixrepo.worktree_symlinks[0] = ".env.local"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.worktree_symlinks[1] = "apps/web/.env.local"' "$WT_CONFIG"
  cfg_reload

  run cfg_bootstrap_env_symlinks fixrepo
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = ".env.local" ]
  [ "${lines[1]}" = "apps/web/.env.local" ]
}

@test "cfg_bootstrap_post_create emits legacy setup_command when structured post_create absent" {
  yq -i '.repos.fixrepo.setup_command = "touch SETUP_RAN"' "$WT_CONFIG"
  cfg_reload

  run cfg_bootstrap_post_create fixrepo
  [ "$status" -eq 0 ]
  [ "$output" = "touch SETUP_RAN" ]
}

@test "path cache emits WT_AUTOPUSH=true per repo by default" {
  generate_path_cache
  grep -q '^WT_AUTOPUSH_fixrepo=true$' "$WT_CACHE"
  grep -q '^WT_AUTOPUSH_fixrepo2=true$' "$WT_CACHE"
}

@test "repos.<name>.hooks.autopush=false flows into the path cache" {
  yq -i '.repos.fixrepo2.hooks.autopush = false' "$WT_CONFIG"
  cfg_reload

  generate_path_cache
  grep -q '^WT_AUTOPUSH_fixrepo=true$' "$WT_CACHE"
  grep -q '^WT_AUTOPUSH_fixrepo2=false$' "$WT_CACHE"
}

@test "defaults.hooks.autopush=false applies to every repo; explicit repo true overrides" {
  yq -i '.defaults.hooks.autopush = false' "$WT_CONFIG"
  yq -i '.repos.fixrepo.hooks.autopush = true' "$WT_CONFIG"
  cfg_reload

  generate_path_cache
  grep -q '^WT_AUTOPUSH_fixrepo=true$' "$WT_CACHE"
  grep -q '^WT_AUTOPUSH_fixrepo2=false$' "$WT_CACHE"
}
