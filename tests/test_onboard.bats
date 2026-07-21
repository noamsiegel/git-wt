#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

# Make a fresh git repo inside the fixture sandbox.
_mk_new_repo() {
  local name="$1"
  local remote="$FIX/$name-remote.git"
  local clone="$FIX/$name"
  git init --quiet --bare "$remote"
  git clone --quiet "$remote" "$clone"
  git -C "$clone" config user.email "test@example.com"
  git -C "$clone" config user.name "Test"
  git -C "$clone" config commit.gpgsign false
  git -C "$clone" config core.hooksPath "$HOME/.config/git/hooks"
  git -C "$clone" commit --quiet --allow-empty -m init
  git -C "$clone" branch -M main
  git -C "$clone" push --quiet -u origin main >/dev/null 2>&1
  echo "$clone"
}

@test "onboard: --yes adds a fresh repo to config and regenerates cache" {
  local repo
  repo=$(_mk_new_repo myproj)

  # snapshot config before
  before=$(grep -c '^  ' "$WT_CONFIG" || true)

  run wt onboard "$repo" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"added"* ]]

  # Config now contains myproj
  grep -q '^  myproj:' "$WT_CONFIG"
  # Cache rebuilt with myproj entry
  grep -q "$repo" "$WT_CACHE"
  # Same process should reload config before cache/list consumers run.
  run wt list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[myproj]"* ]]
}

@test "onboard: refuses non-git directory" {
  mkdir -p "$FIX/notgit"
  run wt onboard "$FIX/notgit" --yes
  [ "$status" -eq 10 ]
  [[ "$output" == *"not a git repo"* ]]
}

@test "onboard: rejects duplicate name pointing elsewhere" {
  local repo
  repo=$(_mk_new_repo dup)
  wt onboard "$repo" --yes >/dev/null
  # Make another repo and try to onboard with the SAME name
  local repo2
  repo2=$(_mk_new_repo othersrc)
  run wt onboard "$repo2" --name dup --yes
  [ "$status" -eq 10 ]
  [[ "$output" == *"taken"* ]]
}

@test "onboard: re-onboarding the same path is idempotent" {
  local repo
  repo=$(_mk_new_repo same)
  wt onboard "$repo" --yes >/dev/null
  run wt onboard "$repo" --yes
  [ "$status" -eq 0 ]
  # Config still has one entry
  [ "$(grep -c '^  same:' "$WT_CONFIG")" -eq 1 ]
}

@test "onboard: installs dispatcher when repo has team-managed core.hooksPath" {
  local repo
  repo=$(_mk_new_repo teamhooks)
  # Simulate husky/lefthook/.githooks setup
  mkdir -p "$repo/.githooks"
  git -C "$repo" config core.hooksPath .githooks

  run wt onboard "$repo" --yes
  [ "$status" -eq 0 ]
  grep -q '^  teamhooks:' "$WT_CONFIG"
  [ "$(git -C "$repo" config --local core.hooksPath)" != ".githooks" ]
}

@test "onboard: --name override is sanitized and used" {
  local repo
  repo=$(_mk_new_repo srcA)
  run wt onboard "$repo" --name "Pretty.Name 1" --yes
  [ "$status" -eq 0 ]
  grep -q '^  pretty-name-1:' "$WT_CONFIG"
}

@test "onboard from inside a worktree resolves to the canonical" {
  local repo
  repo=$(_mk_new_repo wtree)
  # create a worktree somewhere
  mkdir -p "$FIX/wtree-extras"
  git -C "$repo" worktree add -b wt-test "$FIX/wtree-extras/feature" main
  cd "$FIX/wtree-extras/feature"
  run wt onboard . --yes
  [ "$status" -eq 0 ]
  # Config should reference the canonical, not the worktree
  grep -A1 '^  wtree:' "$WT_CONFIG" | grep -q "$repo"
}


@test "onboard: composes team hooks while enabling wt dispatcher" {
  local repo marker
  repo=$(_mk_new_repo composed)
  marker="$FIX/team-post-checkout"
  mkdir -p "$repo/.githooks"
  cat > "$repo/.githooks/post-checkout" <<HOOK
#!/usr/bin/env bash
echo "\$1 \$2 \$3" >> "$marker"
HOOK
  chmod +x "$repo/.githooks/post-checkout"
  git -C "$repo" config core.hooksPath .githooks

  run wt onboard "$repo" --yes

  [ "$status" -eq 0 ]
  [ "$(git -C "$repo" config --local core.hooksPath)" != ".githooks" ]

  cd "$repo"
  run git switch -c feature/canonical-escape

  [ "$status" -ne 0 ]
  [[ "$output" == *"canonical checkout restored"* ]]
  [ "$(git branch --show-current)" = "main" ]
  [[ "$output" == *"wt new"* ]]
  [ -s "$marker" ]
  grep -q ' 1$' "$marker"
}
