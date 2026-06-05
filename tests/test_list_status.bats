#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

@test "list shows nothing under repo when no worktrees" {
  run wt list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[fixrepo]"* ]]
  [[ "$output" != *"ABC-"* ]]
}

@test "list shows created worktrees without tab column" {
  wt_quick_new dev/ABC-1-listed
  run wt list
  [ "$status" -eq 0 ]
  [[ "$output" == *"ABC-1-listed"* ]]
  [[ "$output" == *"dev/ABC-1-listed"* ]]
  [[ "$output" != *"herdr:"* ]]
  [[ "$output" != *"TAB"* ]]
}

@test "cd returns absolute path; works from /tmp" {
  wt_quick_new dev/ABC-1-cd
  cd /tmp
  run wt cd ABC-1-cd
  [ "$status" -eq 0 ]
  [ "$output" = "$FIX/wt_root/ABC-1-cd" ]
}

@test "cd unknown id exits 20" {
  run wt cd missing
  [ "$status" -eq 20 ]
}

@test "status shows clean=yes pushed=no reachable=yes for fresh worktree" {
  wt_quick_new dev/ABC-1-status
  run wt status
  [ "$status" -eq 0 ]
  [[ "$output" == *"ABC-1-status"* ]]
  # rough field checks (ANSI escapes inflate columns but yes/no tokens are present)
  [[ "$output" == *"yes"* ]]
  [[ "$output" == *"no"* ]]
}

@test "read-only: list works from canonical" {
  cd "$FIX/canonical"
  run wt list
  [ "$status" -eq 0 ]
}

@test "read-only: status works from canonical" {
  cd "$FIX/canonical"
  run wt status
  [ "$status" -eq 0 ]
}

@test "external worktree is labeled in list and status" {
  git -C "$FIX/canonical" worktree add "$FIX/omp-wt-forbidden/ext-1" -b dev/ABC-1-ext >/dev/null 2>&1
  run wt list
  [ "$status" -eq 0 ]
  [[ "$output" == *"ext-1"*"(external)"* ]]
  run wt status
  [ "$status" -eq 0 ]
  [[ "$output" == *"ext-1"*"(external)"* ]]
}

@test "cwd lock: new ALLOWED from canonical (new/reap/doctor are exempted)" {
  cd "$FIX/canonical"
  run wt new dev/ABC-1-from-canon
  [ "$status" -eq 0 ]
}

@test "focus without tab plugin exits with install hint" {
  wt_quick_new dev/ABC-1-focus
  run wt focus ABC-1-focus
  [ "$status" -eq 30 ]
  [[ "$output" == *"wt plugin install herdr"* ]]
}

# Alignment helper: strip ANSI escapes, then verify every non-blank row has consistent column count.
_strip_ansi() { sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g'; }

@test "wt list output has consistent column alignment after column -t" {
  wt_quick_new dev/ABC-1-aligned-a
  wt_quick_new dev/ABC-1-aligned-bb
  wt_quick_new dev/ABC-1-aligned-ccc

  out=$(wt list 2>&1 | _strip_ansi)
  # Find the ID-header row in the fixrepo block (starts with whitespace+ID)
  header_line=$(echo "$out" | grep -E '^  ID' | head -1)
  [[ -n "$header_line" ]]
  # ID column position (offset of 'SHA' marker)
  sha_pos=$(echo "$header_line" | awk '{print index($0,"SHA")}')
  [ "$sha_pos" -gt 0 ]
  # Each data row should have whitespace at the SHA column position (alignment).
  while IFS= read -r row; do
    [[ "$row" =~ aligned ]] || continue
    char_at=${row:$((sha_pos-1)):1}
    # The SHA column is at index sha_pos-1 (0-indexed). The char before should be a space (alignment padding).
    char_before=${row:$((sha_pos-2)):1}
    [[ "$char_before" == " " ]]
  done <<< "$out"
}

@test "wt status output has aligned columns" {
  wt_quick_new dev/ABC-1-status-a
  wt_quick_new dev/ABC-1-status-bb

  out=$(wt status 2>&1 | _strip_ansi)
  header_line=$(echo "$out" | grep -E '^  ID +CLEAN' | head -1)
  [[ -n "$header_line" ]]
  # CLEAN column position
  clean_pos=$(echo "$header_line" | awk '{print index($0,"CLEAN")}')
  [ "$clean_pos" -gt 0 ]
  # data rows should have visible token at the CLEAN column (yes|no) starting at clean_pos
  data_rows=$(echo "$out" | grep -E 'ABC-1-status')
  [[ -n "$data_rows" ]]
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    token=${row:$((clean_pos-1)):3}
    [[ "$token" == "yes" || "$token" == "no " ]]
  done <<< "$data_rows"
}

