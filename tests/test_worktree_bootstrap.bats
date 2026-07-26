#!/usr/bin/env bats
load lib/setup.bash

setup() { wt_test_setup; }
teardown() { wt_test_teardown; }

# Rewrite the fixture config for a single repo, injecting extra repo-level YAML
# ($1, already indented 4 spaces), then refresh the path cache.
_write_config() {
  cat > "$WT_CONFIG" <<EOF
repos:
  fixrepo:
    path: $FIX/canonical
    worktree_root: $FIX/wt_root
    base: origin/main
    default_branch: main
    branch_patterns:
      - "^dev/ABC-[0-9]+-[a-z0-9-]+\$"
      - "^pr-[0-9]+\$"
${1}
forbidden_roots:
  - $FIX/omp-wt-forbidden
branch_max_length: 80
EOF
  wt doctor --install-hooks >/dev/null 2>&1 || true
}

_configure_linked_dir() {
  _write_config ""
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].path = "deps/node_modules"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].source = "canonical"' "$WT_CONFIG"
  wt doctor --install-hooks >/dev/null 2>&1 || true
}

_configure_ports() {
  _write_config ""
  yq -i '.repos.fixrepo.bootstrap.ports.strategy = "deterministic-hash"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.ports.output = ".wt/ports.env"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.ports.variables.TEST_API_PORT.base = 17000' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.ports.variables.TEST_API_PORT.span = 100' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.ports.variables.TEST_ADMIN_PORT.base = 18000' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.ports.variables.TEST_ADMIN_PORT.span = 100' "$WT_CONFIG"
  wt doctor --install-hooks >/dev/null 2>&1 || true
}

@test "worktree_symlinks links a configured gitignored file into the worktree" {
  echo "SECRET=1" > "$FIX/canonical/.env.local"
  _write_config "    worktree_symlinks:
      - .env.local"
  run wt new dev/ABC-1-sym
  [ "$status" -eq 0 ]
  [ -L "$FIX/wt_root/ABC-1-sym/.env.local" ]
  [ "$(cat "$FIX/wt_root/ABC-1-sym/.env.local")" = "SECRET=1" ]
}

@test "worktree_symlinks never clobbers a file already placed in the worktree" {
  # .worktreeinclude copies the file first; the symlink step must then skip it,
  # leaving the copied regular file (not a symlink) in place.
  echo ".env.shared" > "$FIX/canonical/.gitignore"
  echo "SHARED=1" > "$FIX/canonical/.env.shared"
  echo ".env.shared" > "$FIX/canonical/.worktreeinclude"
  _write_config "    worktree_symlinks:
      - .env.shared"
  run wt new dev/ABC-1-noclobber
  [ "$status" -eq 0 ]
  [ ! -L "$FIX/wt_root/ABC-1-noclobber/.env.shared" ]
  [ -f "$FIX/wt_root/ABC-1-noclobber/.env.shared" ]
  [ "$(cat "$FIX/wt_root/ABC-1-noclobber/.env.shared")" = "SHARED=1" ]
}

@test "worktree_symlinks missing source warns but does not fail wt new" {
  _write_config "    worktree_symlinks:
      - .does-not-exist"
  run wt new dev/ABC-1-missing
  [ "$status" -eq 0 ]
  [[ "$output" == *"source missing"* ]]
  [ ! -e "$FIX/wt_root/ABC-1-missing/.does-not-exist" ]
}

@test "worktree_symlinks refuses path-escape entries" {
  _write_config "    worktree_symlinks:
      - ../evil"
  run wt new dev/ABC-1-escape
  [ "$status" -eq 0 ]
  [[ "$output" == *"refusing unsafe path"* ]]
  [ ! -e "$FIX/wt_root/evil" ]
}

@test "setup_command runs in the new worktree" {
  _write_config "    setup_command: \"touch SETUP_RAN\""
  run wt new dev/ABC-1-setup
  [ "$status" -eq 0 ]
  [ -f "$FIX/wt_root/ABC-1-setup/SETUP_RAN" ]
}

@test "failing setup_command warns but wt new still succeeds" {
  _write_config "    setup_command: \"exit 7\""
  run wt new dev/ABC-1-setupfail
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup_command failed (exit 7)"* ]]
  [ -d "$FIX/wt_root/ABC-1-setupfail" ]
}

@test "setup_command: auto is a no-op when no lockfile/.envrc at the worktree root" {
  _write_config "    setup_command: auto"
  run wt new dev/ABC-1-autonoop
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-setup: nothing to do"* ]]
}

@test "setup_command: auto runs the detected installer (uv.lock → uv)" {
  # fake uv on PATH (\$FIX/bin is first on PATH) that records its invocation
  printf '#!/usr/bin/env bash\necho "uv %s" >> "%s/uv-calls"\n' '$*' "$FIX" > "$FIX/bin/uv"
  chmod +x "$FIX/bin/uv"
  # put uv.lock on origin/main so the new worktree checks it out
  echo lock > "$FIX/canonical/uv.lock"
  git -C "$FIX/canonical" add uv.lock
  git -C "$FIX/canonical" commit --no-verify -q -m "add uv.lock"
  git -C "$FIX/canonical" push -q origin main
  _write_config "    setup_command: auto"
  run wt new dev/ABC-1-autouv
  [ "$status" -eq 0 ]
  grep -q 'uv sync' "$FIX/uv-calls"
}

@test "setup_command: auto allows root and nested tracked .envrc" {
  # fake direnv on PATH (\$FIX/bin is first) that records its allow targets
  printf '#!/usr/bin/env bash\necho "%s" >> "%s/direnv-calls"\n' '$*' "$FIX" > "$FIX/bin/direnv"
  chmod +x "$FIX/bin/direnv"
  # root + nested .envrc on origin/main so the new worktree checks them out
  echo "export ROOT=1" > "$FIX/canonical/.envrc"
  mkdir -p "$FIX/canonical/sub"
  echo "export SUB=1" > "$FIX/canonical/sub/.envrc"
  git -C "$FIX/canonical" add .envrc sub/.envrc
  git -C "$FIX/canonical" commit --no-verify -q -m "add nested .envrc"
  git -C "$FIX/canonical" push -q origin main
  _write_config "    setup_command: auto"
  run wt new dev/ABC-1-envrc
  [ "$status" -eq 0 ]
  # both the root and the nested tracked .envrc were authorized
  grep -q '^allow \.$' "$FIX/direnv-calls"
  grep -q 'allow sub/.envrc' "$FIX/direnv-calls"
  [[ "$output" == *"direnv allow (2 .envrc)"* ]]
}

@test "bootstrap linked_dirs symlinks deps/node_modules from canonical" {
  echo "deps/node_modules" > "$FIX/canonical/.gitignore"
  git -C "$FIX/canonical" add .gitignore
  git -C "$FIX/canonical" commit --no-verify -q -m "ignore linked deps"
  git -C "$FIX/canonical" push -q origin main
  mkdir -p "$FIX/canonical/deps/node_modules/.bin"
  echo "vitest" > "$FIX/canonical/deps/node_modules/.bin/vitest"
  _configure_linked_dir

  run wt new dev/ABC-1-linked-deps
  [ "$status" -eq 0 ]
  [ -L "$FIX/wt_root/ABC-1-linked-deps/deps/node_modules" ]
  [ "$(readlink "$FIX/wt_root/ABC-1-linked-deps/deps/node_modules")" = "$FIX/canonical/deps/node_modules" ]
}

@test "bootstrap linked_dirs missing source warns but wt new succeeds" {
  _configure_linked_dir

  run wt new dev/ABC-1-linked-missing
  [ "$status" -eq 0 ]
  [[ "$output" == *"bootstrap linked_dirs: source missing, skipped: deps/node_modules"* ]]
  [ -d "$FIX/wt_root/ABC-1-linked-missing" ]
  [ ! -e "$FIX/wt_root/ABC-1-linked-missing/deps/node_modules" ]
}

@test "bootstrap linked_dirs never clobbers existing target" {
  mkdir -p "$FIX/canonical/deps/node_modules"
  echo "existing" > "$FIX/canonical/deps/node_modules/existing.txt"
  git -C "$FIX/canonical" add deps/node_modules/existing.txt
  git -C "$FIX/canonical" commit --no-verify -q -m "add existing target"
  git -C "$FIX/canonical" push -q origin main
  _configure_linked_dir

  run wt new dev/ABC-1-linked-noclobber
  [ "$status" -eq 0 ]
  [ ! -L "$FIX/wt_root/ABC-1-linked-noclobber/deps/node_modules" ]
  [ -f "$FIX/wt_root/ABC-1-linked-noclobber/deps/node_modules/existing.txt" ]
  [ "$(cat "$FIX/wt_root/ABC-1-linked-noclobber/deps/node_modules/existing.txt")" = "existing" ]
}

@test "bootstrap linked_dirs refuses unsafe path" {
  mkdir -p "$FIX/canonical/deps/node_modules"
  _write_config ""
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].path = "../node_modules"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].source = "canonical"' "$WT_CONFIG"
  wt doctor --install-hooks >/dev/null 2>&1 || true

  run wt new dev/ABC-1-linked-unsafe
  [ "$status" -eq 0 ]
  [[ "$output" == *"bootstrap linked_dirs: refusing unsafe path: ../node_modules"* ]]
  [ ! -e "$FIX/wt_root/node_modules" ]
}

@test "bootstrap ports writes marked deterministic env exports" {
  _configure_ports

  run wt new dev/ABC-1-ports
  [ "$status" -eq 0 ]
  [ -f "$FIX/wt_root/ABC-1-ports/.wt/ports.env" ]
  head -n 1 "$FIX/wt_root/ABC-1-ports/.wt/ports.env" | grep -q '^# generated by wt bootstrap; safe to delete$'
  grep -Eq '^export TEST_API_PORT=170[0-9][0-9]$' "$FIX/wt_root/ABC-1-ports/.wt/ports.env"
  grep -Eq '^export TEST_ADMIN_PORT=180[0-9][0-9]$' "$FIX/wt_root/ABC-1-ports/.wt/ports.env"
}

@test "bootstrap ports does not clobber existing unmarked env file" {
  mkdir -p "$FIX/canonical/.wt"
  echo "USER_PORT=1" > "$FIX/canonical/.wt/ports.env"
  git -C "$FIX/canonical" add .wt/ports.env
  git -C "$FIX/canonical" commit --no-verify -q -m "add unmarked ports"
  git -C "$FIX/canonical" push -q origin main
  _configure_ports

  run wt new dev/ABC-1-ports-noclobber
  [ "$status" -eq 0 ]
  [[ "$output" == *"bootstrap ports: existing unmarked file, skipped: .wt/ports.env"* ]]
  [ "$(cat "$FIX/wt_root/ABC-1-ports-noclobber/.wt/ports.env")" = "USER_PORT=1" ]
}

@test "wt bootstrap --repair recreates missing linked dir symlink" {
  mkdir -p "$FIX/canonical/deps/node_modules"
  _configure_linked_dir
  wt new dev/ABC-1-repair >/dev/null
  rm "$FIX/wt_root/ABC-1-repair/deps/node_modules"

  run wt bootstrap --repair ABC-1-repair
  [ "$status" -eq 0 ]
  [ -L "$FIX/wt_root/ABC-1-repair/deps/node_modules" ]
  [ "$(readlink "$FIX/wt_root/ABC-1-repair/deps/node_modules")" = "$FIX/canonical/deps/node_modules" ]
}

# --- wt bootstrap --check coverage --------------------------------------
#
# --check is what tooling keys off to decide whether a worktree needs
# provisioning, so a finding it fails to report is worse than no check at all.

_configure_linked_dir_and_symlink() {
  _write_config "    worktree_symlinks:
      - .envrc-personal"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].path = "deps/node_modules"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].source = "canonical"' "$WT_CONFIG"
  wt doctor --install-hooks >/dev/null 2>&1 || true
}

@test "bootstrap --check reports a missing symlink even when linked_dirs exist" {
  # The regression: the symlink checks used to be skipped entirely whenever any
  # linked_dirs record was present, so a repo configuring both reported clean.
  echo "personal" > "$FIX/canonical/.envrc-personal"
  mkdir -p "$FIX/canonical/deps/node_modules"
  _configure_linked_dir_and_symlink
  wt new dev/ABC-1-check-symlink >/dev/null
  rm -f "$FIX/wt_root/ABC-1-check-symlink/.envrc-personal"

  run wt bootstrap --check ABC-1-check-symlink
  [[ "$output" == *"symlink .envrc-personal"* ]]
  [[ "$output" == *"WARN"* ]]
  [ "$status" -ne 0 ]
}

@test "bootstrap --check exits 0 on a fully provisioned worktree" {
  echo "personal" > "$FIX/canonical/.envrc-personal"
  mkdir -p "$FIX/canonical/deps/node_modules"
  _configure_linked_dir_and_symlink
  wt new dev/ABC-1-check-clean >/dev/null

  run wt bootstrap --check ABC-1-check-clean
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARN"* ]]
}

@test "bootstrap --check exits non-zero for a missing linked dir" {
  mkdir -p "$FIX/canonical/deps/node_modules"
  _configure_linked_dir
  wt new dev/ABC-1-check-linked >/dev/null
  rm -f "$FIX/wt_root/ABC-1-check-linked/deps/node_modules"

  run wt bootstrap --check ABC-1-check-linked
  [[ "$output" == *"WARN (missing/not expected symlink)"* ]]
  [ "$status" -ne 0 ]
}

@test "bootstrap --check reports stale canonical deps as INFO, not a finding" {
  # This row describes the CANONICAL checkout's install being older than the
  # lockfile. --repair cannot change it and it stays true until someone reinstalls
  # there, so counting it as a WARN made --check permanently non-zero for every
  # worktree of such a repo and destroyed its use as a provisioning gate.
  #
  # package.json is COMMITTED so the worktree has identical content and the drift
  # row passes; that isolates the stale mtime comparison as the only finding.
  mkdir -p "$FIX/canonical/deps/node_modules/.bin"
  echo "vitest" > "$FIX/canonical/deps/node_modules/.bin/vitest"
  echo "{}" > "$FIX/canonical/package.json"
  echo "deps/node_modules" > "$FIX/canonical/.gitignore"
  git -C "$FIX/canonical" add package.json .gitignore
  git -C "$FIX/canonical" commit --no-verify -q -m "add lockfile and ignore linked deps"
  git -C "$FIX/canonical" push -q origin main
  _write_config ""
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].path = "deps/node_modules"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].source = "canonical"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].drift_files[0] = "package.json"' "$WT_CONFIG"
  yq -i '.repos.fixrepo.bootstrap.linked_dirs[0].required_paths[0] = ".bin/vitest"' "$WT_CONFIG"
  wt doctor --install-hooks >/dev/null 2>&1 || true
  wt new dev/ABC-1-check-stale >/dev/null
  # Make the lockfile newer than the installed deps: that is what "stale" means.
  touch "$FIX/canonical/package.json"

  run wt bootstrap --check ABC-1-check-stale
  [[ "$output" == *"canonical deps may be stale"* ]]
  [[ "$output" != *"WARN (canonical deps may be stale)"* ]]
  [[ "$output" != *"WARN"* ]]
  [ "$status" -eq 0 ]
}

@test "bootstrap --check reads bootstrap.env.symlinks, not just the legacy key" {
  # The health check used to read cfg_worktree_symlinks while run_bootstrap
  # provisioned from cfg_bootstrap_env_symlinks, so a repo using the current
  # bootstrap.env.symlinks key was never checked under any condition. Check and
  # repair must agree on what should exist.
  echo "personal" > "$FIX/canonical/.envrc-personal"
  _write_config ""
  yq -i '.repos.fixrepo.bootstrap.env.symlinks[0] = ".envrc-personal"' "$WT_CONFIG"
  wt doctor --install-hooks >/dev/null 2>&1 || true
  wt new dev/ABC-1-env-symlink >/dev/null
  [ -e "$FIX/wt_root/ABC-1-env-symlink/.envrc-personal" ]
  rm -f "$FIX/wt_root/ABC-1-env-symlink/.envrc-personal"

  run wt bootstrap --check ABC-1-env-symlink
  [[ "$output" == *"symlink .envrc-personal"* ]]
  [[ "$output" == *"WARN"* ]]
  [ "$status" -ne 0 ]
}
