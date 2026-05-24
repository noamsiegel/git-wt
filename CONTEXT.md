# git-wt CONTEXT

Architecture context for agents and humans working on git-wt itself. For user documentation see `README.md` and `docs/*`.

## Load-bearing invariants

These do not change without a deliberate compatibility break.

1. **Canonical checkout is a parking spot**: configured `repos.<name>.path` checkouts are not where work happens. Runtime command guards and installed hooks both protect this discipline: `guard_not_canonical` refuses user commands from canonical paths (`git-wt` lines 175-186), `repo_for_cwd` classifies canonical versus worktree context (`git-wt` lines 196-213), and the generated hook path cache records canonical paths for hook-time refusal (`generate_path_cache`, lines 816-859).
2. **Every worktree identity flows through one record stream**: `wt_each_worktree` is the only adapter over `git worktree list --porcelain`, and it emits `repo`, `id`, `path`, `rp_path`, `branch`, `sha`, `is_canonical` fields (`git-wt` lines 215-262). `wt_resolve_id` and CLI commands consume those records instead of reparsing porcelain output (`git-wt` lines 270-294). This exists because duplicate record parsing already caused drift.
3. **Branch policy has one runtime surface**: repo inference, branch validation, and hook-cache emission go through `branch_policy_match_repo`, `branch_policy_validate`, and `branch_policy_emit_cache` (`git-wt` lines 296-343). `wt new` validates through that surface before creating a worktree (`git-wt` lines 872-887). Hook enforcement is opt-in via `hooks.enforce_branch_names` and serializes the same patterns into `WT_CACHE`.
4. **Config is a snapshot, not scattered yq reads**: `_cfg_load` performs one props dump and fills bash arrays (`git-wt` lines 46-98). `cfg_repo_record` / `cfg_each_repo_record` are the stable internal record interface for repo config after defaults and `{repo}` expansion (`git-wt` lines 115-137). Config writes must call `cfg_reload` before reading updated values (`cmd_onboard`, lines 1412-1424).
5. **Plugin failures warn, never fail core worktree operations**: plugins are out-of-process executables; core never sources plugin code (`git-wt` lines 370-388). `wt_plugin_emit` routes lifecycle events only to enabled subscribers and downgrades plugin failure to a warning (`git-wt` lines 557-582). `wt_plugin_emit_lifecycle` owns JSON payload construction and handler discovery (`git-wt` lines 584-624).
6. **Bare plugin names are curated; explicit plugin sources are user-trust**: bare names resolve only through `plugins-registry.json` via `wt_plugin_registry_repo_for`; unknown bare names fail with known entries and explicit-install instructions (`git-wt` lines 507-534, 1485-1503). `docs/plugin-contract.md` is the source of truth for trust model and manifest rules.
7. **Hook chain composes instead of owning the repo**: wt-managed global hooks do wt's safety checks, then delegate to `~/.git-hooks-personal/<hook>`, then to repo-local `.git/hooks/<name>` as described in `README.md`. This allows guardrails, Husky, lefthook, pre-commit, and custom repo hooks to coexist without git-wt knowing their internals.
8. **Reaping is explicit and conservative**: `cmd_reap` refuses clean-up unless worktree state is clean, pushed, reachable from `origin/<default_branch>`, and no open files are detected, unless `--force` is supplied (`git-wt` lines 1136-1211). There is no background auto-cleanup.

## TSV record convention

Multiple helpers emit or consume TSV-shaped records (`wt_each_worktree`, `wt_resolve_id`, `cfg_repo_record`, `cfg_each_repo_record`). **Use a non-whitespace separator, never plain `\t`** — bash `read -d $'\t'` collapses adjacent empty fields, shifting column meaning.

The canonical helper `wt_record_fields` handles this by emitting `\x1f` (unit separator), preserving empty fields. v0.6.0 and v0.8.0 both hit bugs from this: detached worktrees with empty branch fields, and snapshot records with 6 fields versus worktree records with 7.

Consumers MUST use `wt_record_fields`, not raw bash `read`. Adding a new record type requires one helper edit, not all call sites.

## Module map

```
git-wt                         single sourceable bash binary
├─ constants / env              WT_CONFIG, WT_CACHE, WT_VERSION, plugin paths
├─ terminal output              red/yellow/green/dim, die/warn/info
├─ dep checks                   bash/yq/git/realpath/config readability
├─ config snapshot              _cfg_load, cfg_repo_record, cfg_each_repo_record
├─ safety guards                guard_forbidden, guard_not_canonical
├─ repo/worktree records         repo_for_cwd, wt_each_worktree, wt_resolve_id
├─ branch policy                branch_policy_match_repo / validate / emit_cache
├─ locking                      per-worktree-root .wt.lock
├─ plugin system                registry, manifest validation, lifecycle emit, commands
├─ git adapters                 git_in, branch existence, worktree registration
├─ file copying                 .worktreeinclude ignored-file copy
├─ status predicates            is_clean, is_pushed, reachable_from
├─ CLI commands                 cmd_new/adopt/pr/list/status/audit/reap/.../plugin
├─ release helpers              cmd_version, cmd_upgrade
└─ dispatch                     main guarded by BASH_SOURCE for sourceable tests

tests/*.bats                    bats integration and helper tests
examples/config.example.yaml    user config example
docs/plugin-contract.md         stable v0 plugin contract
plugins-registry.json           curated bare-name plugin registry
```

## Real seams

- **Plugin executables**: this is a real seam. `wt-herdr` exists outside core, registry installs are curated, explicit third-party installs are supported, and the host/plugin boundary is JSON on stdin plus manifest files. It justifies `docs/plugin-contract.md` and the validation code.
- **Hook chain**: global wt hooks, personal hooks, and repo-local hooks are distinct adapters over Git hook boundaries. git-wt must keep composing rather than replacing them.
- **Worktree record stream**: many commands consume worktree identity. Centralizing the porcelain adapter in `wt_each_worktree` buys locality and avoids the empty-field/TSV bugs that come from ad hoc bash reads.
- **Config snapshot**: command code, hook-cache generation, and onboarding all consume the same repo config shape. `cfg_repo_record` earns its keep because schema/default changes otherwise spread across many yq calls.
- **Branch policy**: runtime branch creation and hook-time validation need identical semantics. `branch_policy_*` is a real seam because two enforcement paths consume it.

## Hypothetical seams to avoid for now

- **Multi-file bash library split**: splitting `git-wt` into `lib/config.sh`, `lib/worktree.sh`, `lib/plugin.sh`, etc. would improve navigation, but it complicates clone+symlink installs, Homebrew formula packaging, sourceability, and support for `WT_PLUGIN_REGISTRY` relative to the binary. Reconsider when a concrete release/install plan exists, not as a readability-only refactor.
- **Go rewrite**: Go would give typed structs, better unit tests, ldflags-stamped versions, and single binaries, and the plugin contract would survive because it is already language-neutral JSON. But a rewrite carries real migration cost and must re-prove hook behavior, path handling, yq-compatible config semantics, plugin installs, and 121 bats cases. Do not start until bash changes are materially slower or riskier than equivalent Go changes.
- **Plugin marketplace abstraction**: one local curated registry plus explicit user-trust installs is enough. A remote marketplace, auto-update layer, signing service, or plugin SDK would be a hypothetical seam.
- **Generic record framework**: worktree records, config records, hook cache, and plugin payloads all look like structured data, but one shared encoder/decoder abstraction in bash could make call sites harder to read. Prefer small helper functions per record type unless another empty-field bug appears.
- **Stacked-PR integration layer**: git-spice, Git Town, and Graphite already own stack semantics. git-wt should document coexistence, not wrap them.

## Public API stability

The public contract is the `git-wt`/`wt` binary, the XDG config file at `~/.config/wt/config.yaml`, installed hook behavior under `~/.config/git/hooks/`, `.worktreeinclude` copying semantics, and `git-wt.plugin.v0` in `docs/plugin-contract.md`.

Helper functions inside `git-wt` are internal even though the file is sourceable for tests. External scripts should call the binary, not source private helpers.

Config fields may gain optional keys with safe defaults. Existing fields that change meaning, validation, or safety behavior require documentation updates in `docs/CONFIG.md` and a changelog entry. Plugin API breaking changes require a new API string, not silent mutation of `git-wt.plugin.v0`.

## ADRs

ADR-001 — canonical checkout as parking spot. Decision: canonical checkouts stay clean and parked on the default branch; active work happens only in worktrees. Source: README mental model and v0.1.0 hook behavior in `CHANGELOG.md`.

ADR-002 — bash first, no rewrite yet. Decision: keep a single bash CLI while helper seams (`wt_each_worktree`, `branch_policy_*`, `cfg_repo_record`, plugin lifecycle emitter) are still buying enough locality. Source: `ROADMAP.md` v0.4 target architecture and non-goals.

ADR-003 — plugin-only tab/UI integrations. Decision: herdr-specific tab code left core; UI/tab behavior lives in plugins behind `git-wt.plugin.v0`. Source: `CHANGELOG.md` v0.5.0 and `docs/plugin-contract.md`.

ADR-004 — curated bare-name plugins. Decision: `wt plugin install herdr` resolves through repo-local `plugins-registry.json`; unknown bare names fail. Third-party plugins require explicit `owner/repo` or URL. Source: `CHANGELOG.md` v0.9.0 and `docs/plugin-contract.md` trust model.

ADR-005 — explicit cleanup. Decision: no auto-reaping. Worktree deletion requires `wt reap` and passes safety checks unless forced. Source: README `What it doesn't do` and `cmd_reap` refusal logic.
