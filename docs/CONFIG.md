# git-wt config reference

Source of truth for `~/.config/wt/config.yaml` as consumed by git-wt v0.9.0.

## File path

Default path:

```text
~/.config/wt/config.yaml
```

Override for tests or alternate profiles:

```bash
WT_CONFIG=/path/to/config.yaml wt list
```

The file must be readable before any command runs. `require_deps` fails with exit code 30 if it is missing or unreadable.

## Shape

```yaml
defaults:
  worktree_root: ~/code/.worktrees/{repo}
  base: origin/main
  default_branch: main
  herdr_workspace: "{repo}"
  branch_patterns:
    - "^yourname/[a-z0-9-]+$"
  protected_refs:
    - main

hooks:
  enforce_branch_names: false

repos:
  my-repo:
    path: ~/code/my-repo
    worktree_root: ~/code/.worktrees/my-repo
    base: origin/main
    default_branch: main
    herdr_workspace: code
    branch_patterns:
      - "^yourname/[A-Z]+-[0-9]+-[a-z0-9-]+$"
  branch_issue_key_regex: "^[^/]+/([A-Z]+-[0-9]+)-"
  enforce_unique_issue_keys: true

forbidden_roots: []
branch_max_length: 80
```

## Interpolation

For repo fields read through git-wt's config snapshot, literal `{repo}` is replaced with the repo key from `repos:`.

Example:

```yaml
defaults:
  worktree_root: ~/code/.worktrees/{repo}
```

For repo `git-wt`, `cfg_repo_record` exposes `~/code/.worktrees/git-wt`.

## Top-level fields

| Field | Type | Default in code | Required? | Used by | Validation / behavior |
|---|---|---:|---|---|---|
| `defaults` | map | empty | no | config snapshot | Supplies fallback values for repo fields. |
| `hooks.enforce_branch_names` | boolean-ish string | `false` | no | `generate_path_cache`, hook scripts | Serialized to `WT_CACHE` as `WT_HOOK_ENFORCE_BRANCH_NAMES`. Opt-in push-time branch validation. |
| `repos` | map | empty | yes for useful operation | all repo/worktree commands | Each key is a repo name. Commands fail or no-op if no configured repos exist, depending on command path. |
| `forbidden_roots` | string array | empty | no | `guard_forbidden`, `generate_path_cache` | Any command using `guard_forbidden` refuses to operate when current path or target path is under one of these roots. |
| `branch_max_length` | integer-like string | `80` | no | `branch_policy_validate` | Branch names longer than this fail before worktree creation or hook-time validation. |

## `defaults` fields

Defaults are inherited by every repo unless the repo overrides the field.

| Field | Type | Default in code | Required? | Meaning |
|---|---|---:|---|---|
| `worktree_root` | string path | none | yes, via default or repo | Directory under which `wt new`, `wt adopt`, and `wt pr` create worktrees. Supports `{repo}` interpolation. |
| `base` | git ref string | none | yes, via default or repo | Ref used as starting point for new worktrees, usually `origin/main`. |
| `default_branch` | branch name | none | yes, via default or repo | Branch canonical checkout should be parked on, and branch used for reachability checks. |
| `herdr_workspace` | string | none | no | Legacy/reference tab workspace value exposed in config records. Plugins may use their own config instead. Supports `{repo}` interpolation. |
| `branch_patterns` | string array | empty | no | Bash extended regular expressions accepted for branch names. Repos with no patterns allow any branch name that passes length validation. |
| `branch_issue_key_regex` | Bash ERE string | empty | no | Optional issue-key extractor used by `wt new`, `wt move`, and `wt adopt`. If unset, the duplicate issue-key guard is disabled. The first capture group is the key; without a group, the whole match is the key. |
| `enforce_unique_issue_keys` | boolean-ish string | unset/false | no | When true and `branch_issue_key_regex` extracts a key, reject creating/adopting another non-canonical worktree branch in the same repo with the same key but a different full branch unless `--allow-duplicate-issue-key` is passed. |
| `protected_refs` | string array | empty | no | Exact names or regexes consumed by the guardrails personal hook layer when running in a wt-managed repo. git-wt core stores this in config but does not enforce protected refs itself. |
| `worktree_symlinks` | string array | empty | no | Legacy alias for `bootstrap.env.symlinks` when structured env symlinks absent. Repo list replaces defaults (no merge). |
| `setup_command` | string | none | no | Legacy alias for `bootstrap.post_create` when structured post-create absent. `auto` keeps lockfile-aware setup behavior. |
| `hooks.autopush` | boolean-ish string | `true` | no | Whether the post-commit hook auto-pushes worktree branches for repos inheriting this default. Only the literal `false` disables. Serialized to `WT_CACHE` as `WT_AUTOPUSH_<repo>`. |

## `repos.<name>` fields

Each entry under `repos:` declares one canonical checkout.

| Field | Type | Required? | Inherits from `defaults`? | Meaning |
|---|---|---|---|---|
| `path` | string path | yes | no | Canonical checkout path. Must point to a Git repository for `wt doctor`, `wt new`, and hook safety to work. |
| `worktree_root` | string path | yes | yes | Directory where this repo's worktrees live. |
| `base` | git ref string | yes | yes | Starting ref for new worktrees. `wt new` best-effort fetches `${base#origin/}` from origin first. |
| `default_branch` | branch name | yes | yes | Canonical parking branch and comparison branch for `status`, `tidy`, `audit`, and `reap`. |
| `herdr_workspace` | string | no | yes | Workspace name retained for tab-plugin compatibility and config records. |
| `branch_patterns` | string array | no | yes | Repo-specific branch regexes. If present, they replace default patterns for this repo. |
| `protected_refs` | string array | no | yes | Guardrails hook policy input for protected branches. |
| `worktree_symlinks` | string array | no | yes (replaces) | Legacy env symlink list. Used only when `bootstrap.env.symlinks` absent. |
| `setup_command` | string | no | yes | Legacy post-create command. Used only when `bootstrap.post_create` absent. |
| `branch_issue_key_regex` | string | no | yes | Bash ERE extracting issue key from branch. First capture group wins; whole match fallback. Empty disables duplicate issue-key guard. |
| `enforce_unique_issue_keys` | boolean-ish string | no | yes | Opt-in duplicate issue-key worktree guard for `wt new`, `wt move`, `wt adopt`. |
| `hooks.autopush` | boolean-ish string | no | yes | Per-repo autopush off-switch. Set `false` for repos whose worktree branches are ephemeral staging (e.g. direct-main repos) so autopush stops leaking them to origin. Only the literal `false` disables; anything else stays on (autopush is the safety default). Serialized as `WT_AUTOPUSH_<repo>` in the path cache. |

Repo keys should be stable and shell-friendly: lowercase letters, digits, `_`, and `-` are safest. `wt onboard` sanitizes proposed names by lowercasing and replacing unsupported characters with `-`.

## Branch patterns

Patterns are Bash extended regular expressions, not glob patterns.

```yaml
defaults:
  branch_patterns:
    - "^noam/[A-Z]+-[0-9]+-[a-z0-9-]+$"
    - "^pr-[0-9]+$"
```

Behavior:

- `wt new` chooses a repo by `--repo`, current directory inference, first matching branch pattern, then first configured repo.
- `branch_policy_validate` rejects names longer than `branch_max_length` first.
- If a repo has at least one pattern, branch must match one of them.
- If a repo has no patterns, any branch name is allowed after length validation.
- `hooks.enforce_branch_names: true` makes generated pre-push hook cache enforce the same patterns at push time.

## Issue-key uniqueness guard

This optional guard catches accidental wrong-ticket work, for example creating `noam/ABC-123-admin-polish` while `noam/ABC-123-api-fix` already has a worktree in the same repo. It is generic: git-wt only extracts keys from branch names and compares existing non-canonical worktree branches. It does **not** call Linear, and it does **not** validate parent/child issue relationships.

```yaml
defaults:
  branch_issue_key_regex: "^[^/]+/([A-Z]+-[0-9]+)-"
  enforce_unique_issue_keys: true
```

Behavior:

- Disabled unless `enforce_unique_issue_keys` is true and `branch_issue_key_regex` is non-empty.
- Checks only configured worktrees for the same repo, not every local/remote branch.
- Allows the same full branch name to proceed to normal existing-branch/path checks.
- Rejects same key with different full branch before worktree creation.
- Intentional stacked/split work can pass `--allow-duplicate-issue-key`.

## Protected refs

```yaml
defaults:
  protected_refs:
    - main
    - master
    - "^release/.*$"
```

`protected_refs` is for the guardrails personal hook layer. git-wt core does not directly block protected-ref pushes from this field. The intended chain is:

1. git-wt global hook runs from `~/.config/git/hooks/`;
2. it invokes `~/.git-hooks-personal/<hook>` when present;
3. guardrails reads wt-managed repo policy and blocks protected refs.

Use server-side branch protection for hard compliance.

## Forbidden roots

```yaml
forbidden_roots:
  - /tmp/omp-agent-sandboxes
  - ~/Library/Caches/some-tool/worktrees
```

`guard_forbidden` resolves the current directory and target paths with `realpath` where possible. If a path is equal to or nested under a forbidden root, wt exits with guardrail code 20.

Use this to keep git-wt from creating or operating in directory trees owned by other isolation systems.

## Worktree bootstrap

`wt new` seeds a worktree in this order: copy small ignored files from
`.worktreeinclude`, create configured bootstrap symlinks, write generated port
exports, run direnv handling, then run post-create commands. Dependency dirs
are symlinked only when configured in `bootstrap.linked_dirs`; they are never
copied by `.worktreeinclude` or installed by git-wt.

```yaml
defaults:
  bootstrap:
    env:
      # Symlink small gitignored env files from the canonical checkout.
      symlinks:
        - .env.local
        - .envrc-personal
      # auto = root .envrc plus tracked nested .envrc files.
      # true = root .envrc only. false = disabled.
      direnv: auto
    ports:
      strategy: deterministic-hash
      output: .wt/ports.env
      variables:
        APP_PORT:
          base: 17000
          span: 1000
    post_create:
      - auto

repos:
  my-repo:
    bootstrap:
      env:
        symlinks:
          - .env
          - .envrc-personal
        direnv: auto
      linked_dirs:
        - path: apps/web/node_modules
          source: canonical
          drift_files:
            - apps/web/package.json
            - apps/web/yarn.lock
          required_paths:
            - .bin/vitest
            - .bin/tsc
      ports:
        strategy: deterministic-hash
        output: .wt/ports.env
        variables:
          WEB_PORT:
            base: 18000
            span: 1000
      post_create:
        - auto
```

### `bootstrap.env.symlinks`

- Each entry is a path relative to the repo root.
- On `wt new` or `wt bootstrap --repair`, git-wt creates
  `worktree/<path>` symlink to `canonical/<path>`.
- Existing targets are never clobbered.
- Missing sources warn and bootstrap continues.
- Path escapes (absolute paths or `..`) are refused.
- Repo-level structured env symlinks replace defaults; they do not merge.
- Legacy `worktree_symlinks` remains compatible: when
  `bootstrap.env.symlinks` is absent, git-wt reads `worktree_symlinks`.
- Security: only exact listed paths are linked. Do not bulk-link directory
  secrets you do not intend to expose in every worktree.

### `bootstrap.linked_dirs`

- Each entry `path` is a repo-relative dependency directory.
- `source: canonical` is the supported source. Empty source also means
  canonical.
- On `wt new` or `wt bootstrap --repair`, git-wt creates
  `worktree/<path>` symlink to `canonical/<path>`.
- Linked dirs are symlink-only. They are never copied or installed by git-wt.
- Put heavy dependency dirs such as `node_modules` here, not in
  `.worktreeinclude`.
- `.worktreeinclude` remains copy-only for small ignored files a worktree
  should own independently.
- Existing targets are never clobbered. If a target exists and is not a
  symlink to the expected canonical source, git-wt warns and leaves it
  unchanged.
- Missing canonical source warns and bootstrap continues.
- Unsafe `path`, `drift_files`, and `required_paths` entries (absolute paths or
  entries containing `..`) are refused.
- `drift_files` are repo-relative files, typically lockfiles or package
  manifests. Doctor compares canonical and worktree contents.
- `required_paths` are checked under the canonical linked dir source, for
  example `.bin/vitest` under `apps/web/node_modules`.
- Repo-level structured linked dirs replace defaults; they do not merge.

### `bootstrap.env.direnv`

- `auto`: authorize root `.envrc` and every tracked nested `.envrc`.
- `true`: authorize root `.envrc`.
- `false`: skip structured direnv handling.
- Empty value preserves legacy behavior: `setup_command: auto` still runs its
  direnv handling when structured `bootstrap.post_create` is absent.

### `bootstrap.ports`

- `strategy` supports `deterministic-hash`.
- `output` defaults to `.wt/ports.env`.
- Each `variables.<NAME>` entry requires integer `base` and positive `span`.
- Variable names must match `^[A-Z_][A-Z0-9_]*$`.
- Port value is deterministic per repo, worktree id, and variable name:
  `base + hash(repo:id:NAME) % span`.
- Output file starts with git-wt's generated marker and is overwritten only
  when that marker is present. Existing unmarked files are left unchanged.
- Projects must source `.wt/ports.env` from `.envrc` or `.envrc-personal` if
  shell commands need the generated variables:

```bash
if [ -f .wt/ports.env ]; then
  source .wt/ports.env
fi
```

### `bootstrap.post_create`

- Ordered list of best-effort post-create actions run after env symlinks,
  linked dirs, ports, and structured direnv handling.
- Item `auto` runs lockfile-aware setup:
  - `uv.lock` → `uv sync`
  - `bun.lockb` / `bun.lock` → `bun install`
  - `pnpm-lock.yaml` → `pnpm install`
  - `yarn.lock` → `yarn install`
  - `package-lock.json` → `npm ci`
  plus direnv authorization for root and tracked nested `.envrc` files.
- Other items run as `bash -c "<item>"` with cwd set to the worktree.
- Non-zero exit prints a warning but does not undo or fail worktree creation.
- Legacy `setup_command` remains compatible: when `bootstrap.post_create` is
  absent, git-wt reads `setup_command`. `setup_command: auto` keeps legacy
  lockfile-aware behavior.

Inspect bootstrap state without mutation:

```bash
wt bootstrap --check <id>
wt doctor --worktree <id>
```

`wt bootstrap --repair <id>` reruns idempotent bootstrap for existing
worktrees. It recreates missing configured symlinks and generated ports; it
does not install dependencies.

## Hooks

```yaml
hooks:
  enforce_branch_names: true
```

`wt doctor --install-hooks` writes `~/.config/wt/paths.cache`. The cache includes:

- canonical paths and realpaths;
- worktree roots and realpaths;
- forbidden roots and realpaths;
- `WT_HOOK_ENFORCE_BRANCH_NAMES`;
- Bash 3-compatible repo-by-path lookup arrays plus `wt_repo_by_path`;
- per-repo branch pattern arrays.

When `enforce_branch_names` is false, branch-pattern checks still run in `wt new`; push-time hook enforcement stays off.

## Plugin paths and config

Plugin install state is not configured in `~/.config/wt/config.yaml`.

| Environment variable | Default | Meaning |
|---|---|---|
| `WT_PLUGIN_REGISTRY` | `plugins-registry.json` next to the `git-wt` binary | Curated bare-name plugin registry. Homebrew formula must install this file and patch/default the path correctly. |
| `WT_PLUGIN_DIR` | `${XDG_DATA_HOME:-$HOME/.local/share}/git-wt/plugins` | Installed plugin checkouts or links. |
| `WT_PLUGIN_CONFIG` | `${XDG_CONFIG_HOME:-$HOME/.config}/git-wt/plugins.json` | Enabled plugin names. |

See `docs/plugin-contract.md` for manifest and event payload details.

## Validation summary

git-wt intentionally keeps config validation pragmatic:

- unreadable config: command fails before dispatch;
- wrong yq dialect: command fails before dispatch;
- missing `path` / `worktree_root` / `base` / `default_branch`: downstream git or path operations fail when the field is needed;
- unknown repo passed to `wt new --repo`: validation error;
- branch longer than `branch_max_length`: validation error;
- branch not matching configured patterns: validation error;
- forbidden root match: guardrail error;
- hook cache stale after config edits: run `wt doctor --install-hooks`.

## Minimal config

```yaml
defaults:
  worktree_root: ~/code/.worktrees/{repo}
  base: origin/main
  default_branch: main
  branch_patterns:
    - "^noam/[A-Z]+-[0-9]+-[a-z0-9-]+$"
    - "^pr-[0-9]+$"

repos:
  git-wt:
    path: ~/Documents/GitHub/git-wt

hooks:
  enforce_branch_names: true

forbidden_roots: []
branch_max_length: 80
```

## After editing config

Run:

```bash
wt doctor --install-hooks
```

This regenerates hook cache so commit/push hooks see new canonical paths, worktree roots, forbidden roots, and branch patterns.
