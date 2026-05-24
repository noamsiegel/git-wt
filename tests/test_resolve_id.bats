#!/usr/bin/env bats
load lib/setup.bash

setup() {
  FIX=$(mktemp -d -t wt-resolve.XXXXXX)
  export FIX
  mkdir -p "$FIX/repo1" "$FIX/repo2" "$FIX/wt1/shared" "$FIX/wt1/only-one" "$FIX/wt2/shared"
  export WT_CONFIG="$FIX/config.yaml"
  export WT_CACHE="$FIX/paths.cache"
  cat > "$WT_CONFIG" <<EOF
repos:
  one:
    path: $FIX/repo1
    worktree_root: $FIX/wt1
    default_branch: main
  two:
    path: $FIX/repo2
    worktree_root: $FIX/wt2
    default_branch: main
EOF
  source "$WT_REPO_ROOT/git-wt"
  git_in() {
    case "$1" in
      "$FIX/repo1")
        printf '%s\n' \
          "worktree $FIX/repo1" \
          "HEAD aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
          "branch refs/heads/main" \
          "" \
          "worktree $FIX/wt1/only-one" \
          "HEAD bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" \
          "branch refs/heads/dev/only-one" \
          "" \
          "worktree $FIX/wt1/shared" \
          "HEAD cccccccccccccccccccccccccccccccccccccccc" \
          "branch refs/heads/dev/shared"
        ;;
      "$FIX/repo2")
        printf '%s\n' \
          "worktree $FIX/repo2" \
          "HEAD dddddddddddddddddddddddddddddddddddddddd" \
          "branch refs/heads/main" \
          "" \
          "worktree $FIX/wt2/shared" \
          "HEAD eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" \
          "branch refs/heads/dev/shared"
        ;;
      *) return 1 ;;
    esac
  }
}

teardown() {
  [[ -n "${FIX:-}" && -d "$FIX" ]] && rm -rf "$FIX"
}

@test "wt_resolve_id returns existing id record" {
  run wt_resolve_id only-one
  [ "$status" -eq 0 ]
  IFS=$'\t' read -r repo id path _rp_path branch sha kind <<< "$output"
  [ "$repo" = "one" ]
  [ "$id" = "only-one" ]
  [ "$path" = "$FIX/wt1/only-one" ]
  [ "$branch" = "dev/only-one" ]
  [ "$sha" = "bbbbbbbbbb" ]
  [ "$kind" = "worktree" ]
}

@test "wt_resolve_id returns non-zero for missing id" {
  run wt_resolve_id missing
  [ "$status" -ne 0 ]
  [ "$output" = "" ]
}

@test "wt_resolve_id returns non-zero for ambiguous id across repos" {
  run wt_resolve_id shared
  [ "$status" -ne 0 ]
  [ "$output" = "" ]
}

@test "wt_resolve_id --repo resolves ambiguous id within one repo" {
  run wt_resolve_id --repo two shared
  [ "$status" -eq 0 ]
  IFS=$'\t' read -r repo id path _rp_path branch sha kind <<< "$output"
  [ "$repo" = "two" ]
  [ "$id" = "shared" ]
  [ "$path" = "$FIX/wt2/shared" ]
  [ "$branch" = "dev/shared" ]
  [ "$sha" = "eeeeeeeeee" ]
  [ "$kind" = "worktree" ]
}

@test "wt_resolve_id ignores canonical checkout basename" {
  run wt_resolve_id repo1
  [ "$status" -ne 0 ]
  [ "$output" = "" ]
}
