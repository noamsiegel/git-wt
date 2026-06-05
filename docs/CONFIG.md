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
| `protected_refs` | string array | empty | no | Exact names or regexes consumed by the guardrails personal hook layer when running in a wt-managed repo. git-wt core stores this in config but does not enforce protected refs itself. |
| `worktree_symlinks` | string array | empty | no | Repo-relative paths symlinked from the canonical checkout into each new worktree by `wt new`. Repo list replaces defaults (no merge). See Worktree bootstrap. |
| `setup_command` | string | none | no | Shell command run (`bash -c`) inside each new worktree after creation. Best-effort: failure warns, never fails `wt new`. See Worktree bootstrap. |

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
| `worktree_symlinks` | string array | no | yes (replaces) | Repo-relative paths to symlink into new worktrees. If present, replaces the default list. |
| `setup_command` | string | no | yes | Per-repo bootstrap command run in new worktrees. |

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

`wt new` can seed a fresh worktree with gitignored env files and run a setup
command, so new worktrees are usable without manual copying or re-installing
dependencies.

```yaml
defaults:
  # Symlink these gitignored files from the canonical checkout into each new
  # worktree (live coupling; the worktree shares the canonical's copy).
  worktree_symlinks:
    - .env.local
    - .envrc-personal
  # Run after creation, with cwd = the new worktree. Best-effort.
  setup_command: "direnv allow"

repos:
  my-repo:
    worktree_symlinks:
      - .env
    setup_command: "direnv allow && yarn install"
```

### `worktree_symlinks`

- Each entry is a path relative to the repo root.
- On `wt new`, git-wt creates `worktree/<path>` as a symlink to `canonical/<path>`.
- Never clobbers: if `worktree/<path>` already exists (tracked, or copied via `.worktreeinclude`), the entry is skipped.
- Missing source: if `canonical/<path>` does not exist, git-wt warns and continues — `wt new` still succeeds.
- Path-escape entries (absolute, or containing `..`) are refused with a warning.
- Repo-level `worktree_symlinks` replaces the defaults list (no merge), mirroring `branch_patterns`.
- Contrast with `.worktreeinclude`, which *copies* gitignored files into the worktree. `worktree_symlinks` *links* them — use it for files you want kept in a single source of truth; use `.worktreeinclude` for files each worktree should own independently.
- Security: only the exact paths you list are linked. Never use it to bulk-link a directory of secrets you do not intend to expose in every worktree.

### `setup_command`

- A single shell string, run as `bash -c "<command>"` with the working directory set to the new worktree, after symlinks are created.
- Best-effort: a non-zero exit prints a warning but does not undo or fail worktree creation (consistent with the plugin-failure invariant — see CONTEXT.md).
- Typical uses: `direnv allow`, dependency install (`yarn install`, `uv sync`), or a project bootstrap script. Prefer fast, idempotent commands.
- It runs only on `wt new` (not `wt adopt`, `wt move`, or `wt pr`).
- Special value `auto`: detect the toolchain from lockfiles at the worktree root and run the matching cache-backed installer, then `direnv allow` if an `.envrc` is present. Detection (each runs if its lockfile + tool are present; multiple may run for polyglot repos):
  - `uv.lock` → `uv sync`
  - `bun.lockb` / `bun.lock` → `bun install`
  - `pnpm-lock.yaml` → `pnpm install`
  - `yarn.lock` → `yarn install`
  - `package-lock.json` → `npm ci`
  Each step is best-effort (missing tool or failed install warns, never fails `wt new`). Heavy dependency dirs are never copied or symlinked across worktrees — the installer's global cache (uv/bun/pnpm) keeps per-worktree installs cheap. Put `setup_command: auto` in `defaults` to auto-provision every repo.

Inspect whether a worktree's symlinks and dependencies are in place with
`wt doctor --worktree <id>`.

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
