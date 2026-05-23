#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

@test "resume focuses existing tab and prints cd command" {
  wt_quick_new dev/ABC-1-resume

  run wt resume ABC-1-resume

  [ "$status" -eq 0 ]
  [[ "$output" == *"ready"* ]]
  [[ "$output" == *"cd $FIX/wt_root/ABC-1-resume"* ]]
  [[ "$output" == *"tab"* ]]
}

@test "resume creates missing tab for existing worktree" {
  wt_quick_new dev/ABC-1-resume-missing
  tab_id=$(awk -F'\t' '$3=="ABC-1-resume-missing" {print $1; exit}' "$WT_HERDR_STATE/tabs.tsv")
  herdr tab close "$tab_id" >/dev/null

  run wt resume ABC-1-resume-missing

  [ "$status" -eq 0 ]
  [[ "$output" == *"ready"* ]]
  awk -F'\t' '$3=="ABC-1-resume-missing" {found=1} END {exit found ? 0 : 1}' "$WT_HERDR_STATE/tabs.tsv"
}

@test "close-tab closes tab but keeps worktree" {
  wt_quick_new dev/ABC-1-close-tab

  run wt close-tab ABC-1-close-tab

  [ "$status" -eq 0 ]
  [[ "$output" == *"closed"* ]]
  [ -d "$FIX/wt_root/ABC-1-close-tab" ]
  ! awk -F'\t' '$3=="ABC-1-close-tab" {found=1} END {exit found ? 0 : 1}' "$WT_HERDR_STATE/tabs.tsv"
}

@test "close-tab refuses working agent without force" {
  wt_quick_new dev/ABC-1-close-working
  awk -F'\t' -v OFS='\t' '$3=="ABC-1-close-working"{$5="working"} {print}' \
    "$WT_HERDR_STATE/tabs.tsv" > "$WT_HERDR_STATE/tabs.tsv.new"
  mv "$WT_HERDR_STATE/tabs.tsv.new" "$WT_HERDR_STATE/tabs.tsv"

  run wt close-tab ABC-1-close-working

  [ "$status" -eq 70 ]
  [[ "$output" == *"agent_status=working"* ]]
  awk -F'\t' '$3=="ABC-1-close-working" {found=1} END {exit found ? 0 : 1}' "$WT_HERDR_STATE/tabs.tsv"
}

@test "tidy reports active dirty and close-tab actions" {
  wt_quick_new dev/ABC-1-tidy-dirty
  echo dirty > "$FIX/wt_root/ABC-1-tidy-dirty/work.txt"
  wt_quick_new dev/ABC-1-tidy-clean

  run wt tidy

  [ "$status" -eq 0 ]
  [[ "$output" == *"active-dirty"* ]]
  [[ "$output" == *"ABC-1-tidy-dirty"* ]]
  [[ "$output" == *"wt close-tab ABC-1-tidy-clean"* ]]
}
