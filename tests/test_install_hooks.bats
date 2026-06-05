#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

# Point fixrepo's canonical at a custom team-hooks dir with an observable
# pre-commit, simulating a repo whose local core.hooksPath bypasses wt.
_seed_team_hooks() {
  mkdir -p "$FIX/teamhooks"
  cat > "$FIX/teamhooks/pre-commit" <<EOF
#!/usr/bin/env bash
echo RAN >> "$FIX/teamlog"
EOF
  chmod +x "$FIX/teamhooks/pre-commit"
  git -C "$FIX/canonical" config --local core.hooksPath "$FIX/teamhooks"
}

@test "hook-run pre-commit blocks in canonical, allows in a worktree" {
  run bash -c "cd '$FIX/canonical' && wt hook-run pre-commit"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to commit in canonical"* ]]

  wt_quick_new dev/ABC-1-hr
  run bash -c "cd '$FIX/wt_root/ABC-1-hr' && wt hook-run pre-commit"
  [ "$status" -eq 0 ]
}

@test "hook-run is fail-open outside any configured repo" {
  run bash -c "cd '$FIX' && wt hook-run pre-commit"
  [ "$status" -eq 0 ]
}

@test "install-hooks points local core.hooksPath at the dispatcher dir" {
  _seed_team_hooks
  run wt install-hooks --repo fixrepo
  [ "$status" -eq 0 ]
  local disp="$HOME/.config/wt/repo-hooks/fixrepo"
  [ "$(git -C "$FIX/canonical" config --local --get core.hooksPath)" = "$disp" ]
  [ -x "$disp/_wt-dispatch" ]
  [ -L "$disp/pre-commit" ]
  [ -L "$disp/pre-push" ]
  [ "$(cat "$disp/.wt-orig-hookspath")" = "$FIX/teamhooks" ]
}

@test "after install, a commit in canonical is blocked" {
  _seed_team_hooks
  wt install-hooks --repo fixrepo >/dev/null
  run git -C "$FIX/canonical" commit --allow-empty -m "should be blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to commit in canonical"* ]]
}

@test "after install, a worktree commit is allowed and the team hook still runs" {
  _seed_team_hooks
  wt_quick_new dev/ABC-1-wtok
  wt install-hooks --repo fixrepo >/dev/null
  run git -C "$FIX/wt_root/ABC-1-wtok" commit --allow-empty -m "ok"
  [ "$status" -eq 0 ]
  [ -f "$FIX/teamlog" ]
  grep -q RAN "$FIX/teamlog"
}

@test "uninstall-hooks restores the original hooksPath and removes the dispatcher" {
  _seed_team_hooks
  wt install-hooks --repo fixrepo >/dev/null
  local disp="$HOME/.config/wt/repo-hooks/fixrepo"
  [ -d "$disp" ]
  run wt uninstall-hooks --repo fixrepo
  [ "$status" -eq 0 ]
  [ "$(git -C "$FIX/canonical" config --local --get core.hooksPath)" = "$FIX/teamhooks" ]
  [ ! -d "$disp" ]
}

@test "install-hooks is idempotent and preserves the true original hooksPath" {
  _seed_team_hooks
  wt install-hooks --repo fixrepo >/dev/null
  wt install-hooks --repo fixrepo >/dev/null
  local disp="$HOME/.config/wt/repo-hooks/fixrepo"
  # sidecar must still hold the team dir, NOT the dispatcher dir.
  [ "$(cat "$disp/.wt-orig-hookspath")" = "$FIX/teamhooks" ]
}

@test "install-hooks unknown repo exits 10" {
  run wt install-hooks --repo nope
  [ "$status" -eq 10 ]
}

@test "install-hooks chains hook names present in the original hooks dir" {
  _seed_team_hooks
  # add a non-default team hook so install must carry it over
  cat > "$FIX/teamhooks/commit-msg" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FIX/teamhooks/commit-msg"
  wt install-hooks --repo fixrepo >/dev/null
  local disp="$HOME/.config/wt/repo-hooks/fixrepo"
  [ -L "$disp/commit-msg" ]
}
