#!/usr/bin/env bats
load lib/setup.bash

setup() {
  FIX=$(mktemp -d -t wt-records.XXXXXX)
  export FIX
  mkdir -p "$FIX/canonical" "$FIX/wt_root/ABC-1-normal" "$FIX/elsewhere/ABC-2-external" "$FIX/real/ABC-3-linked"
  ln -s "$FIX/real/ABC-3-linked" "$FIX/wt_root/ABC-3-linked"
  export WT_CONFIG="$FIX/config.yaml"
  export WT_CACHE="$FIX/paths.cache"
  cat > "$WT_CONFIG" <<EOF
repos:
  fixrepo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    default_branch: main
EOF
  source "$WT_REPO_ROOT/git-wt"
  git_in() {
    if [[ "$1" == "$FIX/canonical" && "$2 $3 $4" == "worktree list --porcelain" ]]; then
      printf '%s\n' \
        "worktree $FIX/canonical" \
        "HEAD 1111111111111111111111111111111111111111" \
        "branch refs/heads/main" \
        "" \
        "worktree $FIX/wt_root/ABC-1-normal" \
        "HEAD 2222222222222222222222222222222222222222" \
        "branch refs/heads/dev/ABC-1-normal" \
        "" \
        "worktree $FIX/elsewhere/ABC-2-external" \
        "HEAD 3333333333333333333333333333333333333333" \
        "detached" \
        "" \
        "worktree $FIX/wt_root/ABC-3-linked" \
        "HEAD 4444444444444444444444444444444444444444" \
        "branch refs/heads/dev/ABC-3-linked"
      return 0
    fi
    return 1
  }
}

teardown() {
  [[ -n "${FIX:-}" && -d "$FIX" ]] && rm -rf "$FIX"
}

_record_for_id() {
  wt_each_worktree fixrepo | awk -F '\t' -v id="$1" '$2 == id { print }'
}

@test "wt_each_worktree emits canonical record with canonical marker" {
  run wt_each_worktree fixrepo
  [ "$status" -eq 0 ]
  canonical=$(printf '%s\n' "$output" | awk -F '\t' '$2 == "canonical" { print }')
  [[ "$canonical" == *$'\tcanonical' ]]
  [[ "$canonical" == *$'\tmain\t1111111111\tcanonical' ]]
}

@test "wt_each_worktree emits normal worktree id branch and short sha" {
  record=$(_record_for_id ABC-1-normal)
  wt_record_fields "$record" repo id path rp_path branch sha kind
  [ "$repo" = "fixrepo" ]
  [ "$id" = "ABC-1-normal" ]
  [ "$path" = "$FIX/wt_root/ABC-1-normal" ]
  [ "$branch" = "dev/ABC-1-normal" ]
  [ "$sha" = "2222222222" ]
  [ "$kind" = "worktree" ]
}

@test "wt_each_worktree emits detached worktree with empty branch" {
  record=$(_record_for_id ABC-2-external)
  wt_record_fields "$record" _repo id path _rp_path branch sha kind
  [ "$id" = "ABC-2-external" ]
  [ "$path" = "$FIX/elsewhere/ABC-2-external" ]
  [ "$branch" = "" ]
  [ "$sha" = "3333333333" ]
  [ "$kind" = "worktree" ]
}

@test "wt_each_worktree preserves worktrees outside configured worktree_root" {
  record=$(_record_for_id ABC-2-external)
  [[ "$record" == *"$FIX/elsewhere/ABC-2-external"* ]]
}

@test "wt_each_worktree collapses symlinked paths in rp_path" {
  record=$(_record_for_id ABC-3-linked)
  wt_record_fields "$record" _repo _id path rp_path _branch _sha kind
  [ "$path" = "$FIX/wt_root/ABC-3-linked" ]
  [ "$rp_path" = "$(rp "$FIX/real/ABC-3-linked")" ]
  [ "$kind" = "worktree" ]
}

@test "wt_each_worktree emits one record per porcelain worktree stanza" {
  run wt_each_worktree fixrepo
  [ "$status" -eq 0 ]
  count=$(printf '%s\n' "$output" | awk 'END { print NR }')
  [ "$count" -eq 4 ]
}
