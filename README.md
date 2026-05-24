# wt

> Parallel-safe git worktree CLI for agentic coding sessions.

`wt` is a tiny, opinionated tool that lets you run multiple AI coding sessions
(Claude Code, Cursor, OMP, plain shells) against the same repository **at the
same time** without conflicts. It does this by enforcing one simple rule:

> The canonical checkout is a parking spot.
> All real work happens in worktrees.

Each worktree is isolated and auto-pushed to its own private branch on every
commit — so work never gets trapped on local disk when an agent crashes or you
switch contexts. Tab management is provided by plugins such as `wt-herdr`.

## Why this exists

Running multiple AI coding agents in parallel against one repo creates three
predictable failure modes:

1. **Concurrent edits to the same files.** Two agents modify `src/auth.ts`
   simultaneously. Resolution is manual, error-prone, and breaks the agents'
   mental models.
2. **Dirty canonical checkouts.** Agent A leaves uncommitted changes in
   `main`. Agent B's `git pull` fails. Or worse, one of them rebases and
   destroys the other's WIP.
3. **Local-only branches that never reach the remote.** Agent finishes a
   feature, you tab away, agent crashes — and the branch lives only on your
   laptop until a backup runs (if one ever does).

`wt` makes (1) impossible by giving each session its own worktree, (2)
impossible by structurally refusing commits in canonical, and (3) impossible
by autopushing every commit to a private remote branch immediately.

## Mental model

| Layer | Path | Discipline |
|---|---|---|
| Canonical checkout | `repos.<name>.path` | Always on `main`. Never edited. A parking spot. |
| Worktrees | `repos.<name>.worktree_root/<id>` | All real work. One per active branch. |
| Tab plugins | Optional lifecycle subscribers | Visible anchors for switching between sessions. |

`wt new <id>` creates a worktree and branches from `origin/main`. `wt reap <id>`
cleans it up when you're done. Install `wt-herdr` if you want tab creation/focus.

## Installation

Requires bash >= 4, git >= 2.43, [yq](https://github.com/mikefarah/yq)
(Go fork), and `realpath`.

```bash
brew install bash yq
git clone https://github.com/noamsiegel/git-wt.git ~/.local/share/git-wt
# Install as `git-wt` so it's invokable as `git wt`.
ln -s ~/.local/share/git-wt/git-wt ~/.local/bin/git-wt
# Convenience alias:
ln -s ~/.local/share/git-wt/git-wt ~/.local/bin/wt
```

Then bootstrap with `wt init` to install global git hooks at
`~/.config/git/hooks/` and create the config at `~/.config/wt/config.yaml`.

## Usage

```bash
wt new noam/AUTH-123-add-sso     # new worktree off origin/main
wt list                           # all active worktrees
wt cd AUTH-123                    # print absolute worktree path
wt adopt feature/wip              # move an existing branch into a worktree
wt reap AUTH-123                  # clean up worktree, remove branch
wt doctor                         # diagnose setup, dependencies, hook wiring
wt upgrade                        # git pull in the install dir
wt version --latest               # check upstream for updates
```

## Configuration

```yaml
# ~/.config/wt/config.yaml
defaults:
  default_branch: main
  herdr_workspace: code

repos:
  my-monorepo:
    path: ~/code/my-monorepo
    worktree_root: ~/code/worktrees/my-monorepo
    base: main
    branch_patterns:
      - '^(yourname)/[A-Z]+-[0-9]+-[a-z0-9-]+$'
      - '^pr-[0-9]+$'

  other-repo:
    path: ~/code/other
    worktree_root: ~/code/worktrees/other
    base: main
```

## Hook chain

`wt` installs four real git hooks at `~/.config/git/hooks/` plus a generic
dispatcher (`_wt-chain`) for everything else. Each hook:

1. Does wt's job (canonical-refuse, branch validation, autopush).
2. Invokes any **personal hook layer** at `~/.git-hooks-personal/<name>`
   (e.g. [guardrails](https://github.com/noamsiegel/guardrails)).
3. Chains to the repo-local `.git/hooks/<name>` if one exists.

This composes cleanly with existing per-repo hook systems (Husky, lefthook,
pre-commit framework, custom orchestrators) without needing to know about
them.

## Copying gitignored files into worktrees (`.worktreeinclude`)

`wt new` copies gitignored files matching patterns in `<canonical>/.worktreeinclude`
into the new worktree. Format matches Claude Code's and VS Code's conventions:
**only files that are BOTH gitignored AND match a pattern are copied.** Tracked
files are never duplicated.

Example `.worktreeinclude`:

```
# Copy local env into every worktree
.env
.env.local

# Copy local IDE settings
.vscode/settings.json
```

Patterns support `*`, `?`, `**`. Comments start with `#`.

## Plugins (v0.3.0+)

git-wt fires lifecycle events that plugins can subscribe to:
`wt:worktree-created`, `wt:worktree-removed`, and `wt:focus`.
Plugins are stand-alone executables named `wt-<name>` installed under
`~/.local/share/git-wt/plugins/`. The contract is JSON-on-stdin so plugins
can be written in any language.

```bash
# Install + enable a plugin
wt plugin install tmux          # → noamsiegel/wt-tmux (if it exists)
wt plugin install owner/wt-kitty

# Manage
wt plugin list
wt plugin disable tmux
wt plugin remove tmux

# Develop a plugin locally
wt plugin link /path/to/wt-mything   # symlinks instead of cloning
wt plugin emit mything wt:focus --id repo--feature-x   # manually fire one event
```

Install the reference tab plugin with `wt plugin install herdr`. Without a tab
plugin, worktree commands still work; tab-only commands (`focus`, `close-tab`,
`resume`) exit with an install hint.

The contract is documented in CHANGELOG.md and is **explicitly draft (`git-wt.plugin.v0`)**.

## Bypass / escape hatches

| Goal | How |
|---|---|
| Commit in canonical (advisory only) | `git commit --no-verify` |
| Skip autopush for this commit | `WT_NO_AUTOPUSH=1 git commit ...` |
| Skip autopush's branch-guard pre-check | `WT_NO_AUTOPUSH_BRANCH_GUARD=1 git commit ...` |
| Allow pushing branch not matching pattern | `WT_HOOK_ENFORCE_BRANCH_NAMES=false` (per-shell) or `git push --no-verify` |
| Uninstall completely | `git config --global --unset core.hooksPath` and remove the directory |

## Non-goals

- Replacing Graphite or any other stacked-PR tool — `wt` doesn't talk to
  PR systems.
- Auto-discovering repos. You add repos by editing the config.
- A TUI. `wt list` / `wt status` are line-oriented.
- Auto-cleanup. Reaping is always explicit.

## License

MIT. See [LICENSE](./LICENSE).
