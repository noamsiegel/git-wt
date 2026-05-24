#!/usr/bin/env bats
load lib/setup.bash

setup() {
  wt_test_setup
  export WT_PLUGIN_DIR="$FIX/plugins"
  export WT_PLUGIN_CONFIG="$FIX/plugins.json"
  export WT_PLUGIN_REGISTRY="$FIX/plugins-registry.json"
  export GIT_CONFIG_GLOBAL="$FIX/gitconfig"
  mkdir -p "$WT_PLUGIN_DIR"
  git config --global url."file://$FIX/remotes/".insteadOf "https://github.com/local/"
}

teardown() { wt_test_teardown; }

_make_plugin_checkout() {
  local root="$1" name="$2" api_versions="${3:-[\"git-wt.plugin.v0\"]}" capabilities="${4:-absent}"
  mkdir -p "$root/wt-$name"
  if [[ "$capabilities" = absent ]]; then
    cat > "$root/wt-$name/wt-plugin.json" <<EOF
{
  "api_versions": $api_versions,
  "name": "$name",
  "executable": "wt-$name",
  "events": ["wt:worktree-created"],
  "version": "0.0.0"
}
EOF
  else
    cat > "$root/wt-$name/wt-plugin.json" <<EOF
{
  "api_versions": $api_versions,
  "name": "$name",
  "executable": "wt-$name",
  "events": ["wt:worktree-created"],
  "capabilities": $capabilities,
  "version": "0.0.0"
}
EOF
  fi
  cat > "$root/wt-$name/wt-$name" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  manifest) cat "$(dirname "$0")/wt-plugin.json" ;;
  health) echo '{"ok":true,"version":"0.0.0","errors":[]}' ;;
  event) cat >/dev/null ;;
  *) exit 10 ;;
esac
EOF
  chmod +x "$root/wt-$name/wt-$name"
}

_git_init_plugin() {
  local root="$1" name="$2"
  git -C "$root/wt-$name" init -q
  git -C "$root/wt-$name" config user.email test@example.com
  git -C "$root/wt-$name" config user.name Test
  git -C "$root/wt-$name" add .
  git -C "$root/wt-$name" commit -qm init
  git clone --quiet --bare "$root/wt-$name" "$root/wt-$name.git"
}

@test "bare-name install resolves through curated registry" {
  _make_plugin_checkout "$FIX/remotes" herdr
  _git_init_plugin "$FIX/remotes" herdr
  cat > "$WT_PLUGIN_REGISTRY" <<'EOF'
{"api_version":"git-wt.plugin.v0","plugins":[{"name":"herdr","repo":"local/wt-herdr","description":"local","tier":"first-party","api_versions":["git-wt.plugin.v0"]}]}
EOF

  run wt plugin install herdr

  [ "$status" -eq 0 ]
  [[ "$output" == *"installed and enabled"* ]]
  [ -x "$WT_PLUGIN_DIR/wt-herdr/wt-herdr" ]
}

@test "unknown bare-name install does not fall back to noamsiegel/wt-name" {
  cat > "$WT_PLUGIN_REGISTRY" <<'EOF'
{"api_version":"git-wt.plugin.v0","plugins":[{"name":"herdr","repo":"noamsiegel/wt-herdr","description":"herdr","tier":"first-party","api_versions":["git-wt.plugin.v0"]}]}
EOF

  run wt plugin install nonexistent

  [ "$status" -eq 20 ]
  [[ "$output" == *"Unknown plugin: nonexistent"* ]]
  [[ "$output" == *"Known plugins:"* ]]
  [[ "$output" == *"  herdr"* ]]
  [[ "$output" == *"wt plugin install <owner>/wt-<name>"* ]]
  [[ "$output" != *"noamsiegel/wt-nonexistent"* ]]
}

@test "explicit owner repo install path is preserved" {
  _make_plugin_checkout "$FIX/remotes" thing
  _git_init_plugin "$FIX/remotes" thing

  run env WT_PLUGIN_REGISTRY="$FIX/missing.json" wt plugin install local/wt-thing

  [ "$status" -eq 0 ]
  [ -x "$WT_PLUGIN_DIR/wt-thing/wt-thing" ]
}

@test "plugin validate succeeds for compatible plugin without capabilities" {
  _make_plugin_checkout "$FIX/checkouts" demo

  run wt plugin validate "$FIX/checkouts/wt-demo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: plugin demo is valid"* ]]
  [[ "$output" == *"capabilities: 0"* ]]
}

@test "plugin validate reports detailed errors for broken plugin" {
  mkdir -p "$FIX/broken-plugin"
  cat > "$FIX/broken-plugin/wt-plugin.json" <<'EOF'
{"api_versions":["git-wt.plugin.v999"],"name":"broken","executable":"wrong","events":[]}
EOF

  run wt plugin validate "$FIX/broken-plugin"

  [ "$status" -ne 0 ]
  [[ "$output" == *"incompatible plugin API versions"* ]]
  [[ "$output" == *"events must be a non-empty array"* ]]
  [[ "$output" == *"executable must be wt-broken"* ]]
}

@test "install rejects incompatible api_versions" {
  _make_plugin_checkout "$FIX/remotes" bad '["git-wt.plugin.v999"]'
  _git_init_plugin "$FIX/remotes" bad
  cat > "$WT_PLUGIN_REGISTRY" <<'EOF'
{"api_version":"git-wt.plugin.v0","plugins":[{"name":"bad","repo":"local/wt-bad","description":"bad","tier":"first-party","api_versions":["git-wt.plugin.v999"]}]}
EOF

  run wt plugin install bad

  [ "$status" -eq 20 ]
  [[ "$output" == *"incompatible plugin API versions"* ]]
  [ ! -e "$WT_PLUGIN_DIR/wt-bad" ]
}

@test "enable rejects incompatible installed plugin" {
  _make_plugin_checkout "$WT_PLUGIN_DIR" bad '["git-wt.plugin.v999"]'

  run wt plugin enable bad

  [ "$status" -eq 20 ]
  [[ "$output" == *"incompatible with this wt"* ]]
}

@test "singular api_version remains compatible with deprecation warning" {
  mkdir -p "$FIX/remotes/wt-legacy"
  cat > "$FIX/remotes/wt-legacy/wt-plugin.json" <<'EOF'
{"api_version":"git-wt.plugin.v0","name":"legacy","executable":"wt-legacy","events":["wt:worktree-created"],"version":"0.0.0"}
EOF
  cat > "$FIX/remotes/wt-legacy/wt-legacy" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  health) echo '{"ok":true,"version":"0.0.0","errors":[]}' ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$FIX/remotes/wt-legacy/wt-legacy"
  _git_init_plugin "$FIX/remotes" legacy
  cat > "$WT_PLUGIN_REGISTRY" <<'EOF'
{"api_version":"git-wt.plugin.v0","plugins":[{"name":"legacy","repo":"local/wt-legacy","description":"legacy","tier":"first-party","api_versions":["git-wt.plugin.v0"]}]}
EOF

  run wt plugin install legacy

  [ "$status" -eq 0 ]
  [[ "$output" == *"deprecated api_version"* ]]
  [ -x "$WT_PLUGIN_DIR/wt-legacy/wt-legacy" ]
}

@test "capabilities array is accepted when present" {
  _make_plugin_checkout "$FIX/checkouts" caps '["git-wt.plugin.v0"]' '["tab.focus","tab.close","tab.query"]'

  run wt plugin validate "$FIX/checkouts/wt-caps"

  [ "$status" -eq 0 ]
  [[ "$output" == *"capabilities: 3"* ]]
}
