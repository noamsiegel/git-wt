# How git-wt compares

Short version: git-wt is not trying to be the biggest worktree UX. It is the policy/safety layer for parallel agentic Git worktrees: canonical checkout parking, per-repo branch gates, autopush, hook-chain composition, forbidden roots, and a language-neutral plugin boundary for tab/UI integrations.

## At a glance

| Tool | What it manages | Where state lives | When it acts |
|---|---|---|---|
| **git-wt** | Git worktree session safety: canonical parking, branch-pattern gates, autopush, plugin lifecycle | Per-user XDG config at `~/.config/wt/config.yaml`; Git worktrees under configured roots; plugins under `~/.local/share/git-wt/plugins/` | On `wt` commands plus git hook boundaries: pre-commit, post-commit, pre-push, post-checkout |
| Worktrunk | Broad worktree UX: picker, status, hooks, PR checkout, merge/dev-server/cache helpers | Tool config + worktree directories; exact state model belongs to Worktrunk | On CLI commands; hooks/automation when configured |
| wtp (Worktree Plus) | Worktree creation/navigation and environment bootstrap | Project-local `.wtp.yml` plus generated worktree paths | On CLI commands; post-create copy/symlink/command hooks |
| gwq | Global worktree discovery, dashboard, fuzzy navigation, tmux integration | Global gwq-managed worktree inventory and Git worktree state | On CLI commands; status watch for monitoring |
| git-spice | Stacked branches and PR/MR workflow | Git branches plus git-spice metadata/config; worktrees are compatibility surface | When creating/restacking/submitting/syncing stacks |
| Git Town | High-level Git branch workflow: lineage, sync, ship/propose, undo/runlog | Git branches plus Git Town config/lineage metadata | When running branch workflow commands such as sync/ship/propose |
| Graphite CLI (`gt`) | Stacked PR lifecycle and Graphite platform workflow | Git branches plus Graphite CLI metadata/platform state | When creating/modifying/submitting/syncing stacks |
| jj (Jujutsu) | Alternative Git-compatible VCS model: changes/working copies instead of branch-first workflow | jj repo metadata with Git compatibility | During everyday VCS operations; substitutes for some Git branch/worktree workflows rather than wrapping them |

## Direct worktree managers

### Worktrunk

Worktrunk is the strongest direct comparison. It has broader Rust-based worktree UX: interactive picker, status columns, PR checkout, merge flow, hooks, cache helpers, dev-server helpers, and agent-oriented positioning.

**Difference**: git-wt deliberately stays narrower. It cares less about picker/dashboard UX and more about invariants: canonical checkout as a read-only parking spot, every worktree commit auto-pushed, branch names checked at hook boundaries, forbidden roots, and tab/UI behavior behind a plugin contract.

**Coexistence**: possible only if one tool owns worktree creation roots and hook policy. Running both as active managers for the same repo risks confusing worktree layout and hook expectations.

### wtp (Worktree Plus)

wtp focuses on worktree creation/navigation and bootstrap. Project-local `.wtp.yml` can copy files, create symlinks, and run setup commands after worktree creation.

**Difference**: git-wt's config is per-user XDG policy, not a checked-in team bootstrap file. git-wt enforces agent-safety behavior after creation too: canonical commit refusal, branch-pattern checks, autopush, and explicit reaping safety.

**Coexistence**: treat wtp as environment-bootstrap oriented and git-wt as policy oriented. Do not let both create the same worktree directory tree.

### gwq

gwq is dashboard/navigation-first: global worktree inventory, fuzzy navigation, tmux integration, JSON output, and status watching.

**Difference**: git-wt does not auto-discover repos and does not ship a dashboard. It only manages configured repos and uses plugins for UI/tab behavior instead of baking tmux/herdr directly into core.

**Coexistence**: gwq can be useful for global visibility if it only observes worktrees. git-wt should remain owner of creation, hook policy, and cleanup for repos configured under it.

## Stack and branch workflow tools

### git-spice

git-spice manages stacked branches and PR/MR submission. Worktrees are compatibility surface, not core product.

**Difference**: git-wt owns workspace/session safety. It does not know stack lineage, restack branches, or submit PRs.

**Coexistence**: good. Use git-wt to create safe per-branch worktrees; use git-spice inside a worktree when you need stack workflow.

### Git Town

Git Town manages higher-level branch workflow: lineage, sync, ship/propose, undo/runlog, and forge integrations.

**Difference**: Git Town owns branch operations. git-wt owns worktree layout, canonical parking, hook safety, autopush, and plugin lifecycle.

**Coexistence**: plausible if commands are run from git-wt worktrees and hook order is understood. Avoid using Git Town as a worktree lifecycle layer for the same repo unless tested.

### Graphite CLI (`gt`)

Graphite manages stacked PR lifecycle and platform workflow. It is not a worktree lifecycle manager.

**Difference**: Graphite answers “how do I submit and sync stacks?” git-wt answers “where can parallel agents safely edit, commit, and persist work?”

**Coexistence**: good. Use git-wt as lower-level workspace/session layer; use Graphite for stack creation/modification/submission.

## Strategic substitutes

### jj (Jujutsu)

jj changes the VCS model. It can reduce branch/worktree friction by replacing branch-first Git workflow with changes and working-copy operations.

**Difference**: git-wt is intentionally native Git porcelain. It is for users who want safer worktrees without switching VCS models.

**Coexistence**: limited. jj is a workflow substitute more than an adjacent helper. If a repo moves to jj-first workflows, git-wt's branch-pattern and Git hook model becomes less central.

## Why git-wt exists despite overlap

Most adjacent tools optimize creation, navigation, dashboards, bootstrap, or PR stacks. git-wt optimizes for failure modes common in parallel agent sessions:

1. agent work happens in isolated worktrees, never canonical;
2. work reaches remote immediately after each commit;
3. local hooks catch branch-policy violations before push;
4. hook-chain composition preserves personal and repo-local hook systems;
5. plugins get lifecycle events without being sourced into core;
6. cleanup stays explicit and conservative.

This makes git-wt smaller than Worktrunk and less feature-rich than full stack tools by design. Its value is being boring, visible, and hard to accidentally violate.
