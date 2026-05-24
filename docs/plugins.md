# git-wt plugins

This page compares current `git-wt.plugin.v0` plugins. The protocol source of truth remains [`docs/plugin-contract.md`](./plugin-contract.md); this page is only product-level plugin positioning.

## Plugin comparison

| Plugin | Integrates with | What it does on `wt:worktree-created` | What it does on `wt:worktree-removed` | Focus/list behavior | Capabilities |
|---|---|---|---|---|---|
| [`wt-herdr`](https://github.com/noamsiegel/wt-herdr) | [herdr](https://github.com/noamsiegel/herdr) terminal-tab manager | Creates workspace if absent and creates tab with worktree cwd. | Closes matching herdr tab; no-op if no tab/workspace. | `wt:focus` focuses matching tab; `wt:list` returns empty successful result until query shape is specified. | Events include created, removed, focus, list; current manifest uses legacy singular `api_version` and no `capabilities` field. |
| [`wt-cmux`](https://github.com/noamsiegel/wt-cmux) | [cmux](https://github.com/manaflow-ai/cmux) native macOS terminal multiplexer | Creates or selects matching cmux workspace, attaches git-wt metadata, sends `cd <worktree>`. | Finds cmux workspace by stored worktree-path metadata and closes it; missing workspace no-op. | `wt:focus` selects matching workspace; no `wt:list` subscription. | `tab.focus`, `tab.close`. |
| [`wt-zed`](https://github.com/noamsiegel/wt-zed) | Zed editor CLI | Runs `zed -n <worktree-path>` to open a new window. | Best-effort no-op because documented Zed CLI lacks non-interactive close-workspace command. | No focus/list subscription. | None. |

## What these plugins don't do

- They do not define `git-wt.plugin.v0`; git-wt owns the contract.
- They do not manage git worktree naming, branch policy, cleanup, or adoption rules.
- They do not install or configure the integrated application.
- They do not auto-update themselves; plugin installation and upgrades are explicit user actions.
- They do not share a runtime framework. Each plugin stays a small executable that implements the host protocol.

## Maintainer workflow

For local plugin work:

```bash
wt plugin link /path/to/plugin
wt plugin validate /path/to/plugin
wt plugin emit <name> wt:worktree-created --id demo --path /tmp/demo --branch dev/demo
```

Run each plugin's own bats tests before release. Keep compatibility in `wt-plugin.json` via `api_versions`; bump the plugin's own `version` when behavior changes.
