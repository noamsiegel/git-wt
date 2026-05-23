#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

# --- pre-push -----------------------------------------------------------

@test "pre-push: valid branch passes (exit 0)" {
  wt_quick_new dev/ABC-1-prepush-ok
  cd "$FIX/wt_root/ABC-1-prepush-ok"
  run bash -c 'echo "refs/heads/dev/ABC-1-prepush-ok deadbeef refs/heads/dev/ABC-1-prepush-ok 0000000000000000000000000000000000000000" | "$HOME/.config/git/hooks/pre-push" origin fake-url'
  [ "$status" -eq 0 ]
}

@test "pre-push: bad branch passes when branch enforcement disabled" {
  cd "$FIX/canonical"
  run bash -c 'echo "refs/heads/feature/bad deadbeef refs/heads/feature/bad 0000000000000000000000000000000000000000" | "$HOME/.config/git/hooks/pre-push" origin fake-url'
  [ "$status" -eq 0 ]
}

@test "pre-push: bad branch rejected when branch enforcement enabled" {
  yq -i '.hooks.enforce_branch_names = true' "$WT_CONFIG"
  wt doctor --install-hooks >/dev/null
  cd "$FIX/canonical"
  run bash -c 'echo "refs/heads/feature/bad deadbeef refs/heads/feature/bad 0000000000000000000000000000000000000000" | "$HOME/.config/git/hooks/pre-push" origin fake-url'
  [ "$status" -eq 1 ]
  [[ "$output" == *"rejected branch name"* ]]
  [[ "$output" == *"feature/bad"* ]]
  [[ "$output" == *"--no-verify"* ]]
}
@test "pre-push: unconfigured repo passes through (exit 0)" {
  outside=$(mktemp -d)
  git init --quiet "$outside" && cd "$outside" && git commit --quiet --allow-empty -m init
  run bash -c 'echo "refs/heads/anything-here deadbeef refs/heads/anything-here 0000000000000000000000000000000000000000" | "$HOME/.config/git/hooks/pre-push" origin fake-url'
  [ "$status" -eq 0 ]
  rm -rf "$outside"
}

@test "pre-push: chains repo-local hook" {
  # Install a repo-local pre-push that records being run
  marker="$FIX/repo-local-prepush.ran"
  mkdir -p "$FIX/canonical/.git/hooks"
  cat > "$FIX/canonical/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
echo ran > "$marker"
exit 0
EOF
  chmod +x "$FIX/canonical/.git/hooks/pre-push"
  cd "$FIX/canonical"
  run bash -c 'echo "refs/heads/dev/ABC-1-chain deadbeef refs/heads/dev/ABC-1-chain 0000000000000000000000000000000000000000" | "$HOME/.config/git/hooks/pre-push" origin fake-url'
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
}

# --- post-checkout -----------------------------------------------------

@test "post-checkout: warns in canonical when off main" {
  cd "$FIX/canonical"
  git switch --quiet -c feature/foo
  run "$HOME/.config/git/hooks/post-checkout" 0 0 1
  [ "$status" -eq 0 ]   # advisory, never blocks
  [[ "$output" == *"canonical checkout left main"* ]]
}

@test "post-checkout: silent in canonical when on main" {
  cd "$FIX/canonical"
  run "$HOME/.config/git/hooks/post-checkout" 0 0 1
  [ "$status" -eq 0 ]
  [[ "$output" != *"canonical checkout left"* ]]
}

@test "post-checkout: silent in worktree" {
  wt_quick_new dev/ABC-1-pc-worktree
  cd "$FIX/wt_root/ABC-1-pc-worktree"
  run "$HOME/.config/git/hooks/post-checkout" 0 0 1
  [ "$status" -eq 0 ]
  [[ "$output" != *"canonical checkout"* ]]
}

@test "post-checkout: silent in unrelated repo" {
  outside=$(mktemp -d)
  git init --quiet "$outside" && cd "$outside" && git commit --quiet --allow-empty -m init
  run "$HOME/.config/git/hooks/post-checkout" 0 0 1
  [ "$status" -eq 0 ]
  [[ "$output" == "" ]]
  rm -rf "$outside"
}

# --- pre-commit (Option C — canonical read-only) -----------------------

@test "pre-commit: refuses commit in canonical (exit 1)" {
  cd "$FIX/canonical"
  run "$HOME/.config/git/hooks/pre-commit"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to commit in canonical"* ]]
}

@test "pre-commit: real git commit in canonical is blocked" {
  cd "$FIX/canonical"
  echo x > work.txt
  git add work.txt
  run git commit -m "should fail"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing"* || "$output" == *"canonical"* ]]
}

@test "pre-commit: real git commit in canonical with --no-verify bypasses" {
  cd "$FIX/canonical"
  echo x > work.txt
  git add work.txt
  run git commit --no-verify -m "bypass"
  [ "$status" -eq 0 ]
}

@test "pre-commit: passes in worktree" {
  wt_quick_new dev/ABC-1-pc-allow
  cd "$FIX/wt_root/ABC-1-pc-allow"
  echo y > work.txt
  git add work.txt
  run git commit -m "ok"
  [ "$status" -eq 0 ]
}

@test "pre-commit: unconfigured repo passes through" {
  outside=$(mktemp -d)
  git init --quiet "$outside" && cd "$outside"
  echo z > z.txt; git add z.txt
  run git -c user.email=t@e.com -c user.name=t commit -m ok
  [ "$status" -eq 0 ]
  rm -rf "$outside"
}

# --- generic chain shims (commit-msg, post-merge, etc.) ----------------

@test "chain shim: commit-msg passes through silently when no repo-local hook" {
  cd "$FIX/canonical"
  echo "test message" > /tmp/wt-msg-$$
  run "$HOME/.config/git/hooks/commit-msg" /tmp/wt-msg-$$
  rm -f /tmp/wt-msg-$$
  [ "$status" -eq 0 ]
}

@test "chain shim: commit-msg chains to repo-local hook" {
  marker="$FIX/commit-msg.ran"
  mkdir -p "$FIX/canonical/.git/hooks"
  cat > "$FIX/canonical/.git/hooks/commit-msg" <<EOF
#!/usr/bin/env bash
echo ran > "$marker"
exit 0
EOF
  chmod +x "$FIX/canonical/.git/hooks/commit-msg"
  cd "$FIX/canonical"
  echo "msg" > /tmp/wt-msg-$$
  run "$HOME/.config/git/hooks/commit-msg" /tmp/wt-msg-$$
  rm -f /tmp/wt-msg-$$
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
}

@test "chain shim: post-merge chains and passes args through" {
  marker="$FIX/post-merge.args"
  mkdir -p "$FIX/canonical/.git/hooks"
  cat > "$FIX/canonical/.git/hooks/post-merge" <<EOF
#!/usr/bin/env bash
echo "\$@" > "$marker"
exit 0
EOF
  chmod +x "$FIX/canonical/.git/hooks/post-merge"
  cd "$FIX/canonical"
  run "$HOME/.config/git/hooks/post-merge" 1
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
  read -r got < "$marker"
  [ "$got" = "1" ]
}

@test "chain shim: post-merge does not recurse" {
  # Repo-local hook IS the global one (symlink loop) — recursion guard must catch.
  mkdir -p "$FIX/canonical/.git/hooks"
  ln -sfn "$HOME/.config/git/hooks/post-merge" "$FIX/canonical/.git/hooks/post-merge"
  cd "$FIX/canonical"
  # Should exit 0 cleanly, not infinite-loop or fail.
  run "$HOME/.config/git/hooks/post-merge" 1
  [ "$status" -eq 0 ]
}

@test "chain shim: prepare-commit-msg passes through when no local hook" {
  cd "$FIX/canonical"
  echo "x" > /tmp/wt-pcmsg-$$
  run "$HOME/.config/git/hooks/prepare-commit-msg" /tmp/wt-pcmsg-$$ message
  rm -f /tmp/wt-pcmsg-$$
  [ "$status" -eq 0 ]
}
