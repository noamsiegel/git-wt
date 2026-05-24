#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

@test "resume without tab plugin exits with install hint" {
  wt_quick_new dev/ABC-1-resume

  run wt resume ABC-1-resume

  [ "$status" -eq 30 ]
  [[ "$output" == *"wt plugin install herdr"* ]]
}

@test "close-tab without tab plugin exits with install hint" {
  wt_quick_new dev/ABC-1-close-tab

  run wt close-tab ABC-1-close-tab

  [ "$status" -eq 30 ]
  [[ "$output" == *"wt plugin install herdr"* ]]
  [ -d "$FIX/wt_root/ABC-1-close-tab" ]
}

@test "tidy reports active dirty and safe reap actions without tab state" {
  wt_quick_new dev/ABC-1-tidy-dirty
  echo dirty > "$FIX/wt_root/ABC-1-tidy-dirty/work.txt"
  wt_quick_new dev/ABC-1-tidy-clean
  git -C "$FIX/wt_root/ABC-1-tidy-clean" push --quiet -u origin dev/ABC-1-tidy-clean

  run wt tidy

  [ "$status" -eq 0 ]
  [[ "$output" == *"ABC-1-tidy-dirty"* ]]
  [[ "$output" == *"active-dirty"* ]]
  [[ "$output" == *"safe-reap-candidate"* ]]
  [[ "$output" != *"close-tab"* ]]
}
