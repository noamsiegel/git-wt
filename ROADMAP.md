# git-wt Roadmap

> Target architecture and quarterly milestones, derived from the
> `improve-codebase-architecture` audit on 2026-05-23.

## Current state (v0.4.0)

~1770-line single-file bash CLI. The 2026-05 audit found these structural issues
(ordered by leverage):

1. **Worktree identity reparsed** from `git worktree list --porcelain` in `cmd_list`, `cmd_status`, `cmd_audit`, `cmd_reap`, `cmd_tidy`, `cmd_repair` — six places that each decide independently how to skip canonical, derive id, handle realpath.
2. **Branch policy scattered** across `validate_branch_shape`, `cmd_new` repo inference, and `generate_path_cache` (hook-cache emission). Three call sites, three different semantics.
3. **Plugin event JSON built by heredoc** with unescaped `id` / `path` / `branch`. Comment says "callers pre-escape"; call sites pass raw values.
4. **Config snapshot leaky** — callers fetch individual fields repeatedly via `cfg_repo_get`; hook-cache serializes through a parallel path; `cmd_onboard` writes raw yq then manually invalidates the cache.
5. **No sourceable boundary** — `main "$@"` runs unconditionally, so bats can't unit-test helpers without full fixture repos.
6. **Herdr still partially embedded** (extraction begun in v0.4.0; finish in v0.5.0).

## Target architecture

### Domain layer (sourceable, pure helpers, unit-testable)

```
wt_each_worktree <repo>           → TSV stream: repo id path rp_path branch sha is_canonical
wt_resolve_id <id>                → one record

branch_policy_match_repo <branch> → repo name or empty
branch_policy_validate <repo> <branch>
branch_policy_emit_cache <repo>

cfg_repo_record <repo>            → all canonical fields after defaults + {repo} expansion
cfg_each_repo_record              → all repos
cfg_reload

wt_plugin_emit_lifecycle <event> <record> [reason]
                                  → owns JSON escaping, timestamp, routing
```

### Adapter layer

- `git worktree list --porcelain` parsing → only `wt_each_worktree` touches it
- Plugin protocol → only `wt_plugin_emit_lifecycle` touches it
- Hook-cache generation → consumes `cfg_each_repo_record`

### CLI layer

- Each `cmd_*` is 5–20 lines: parse args → call domain → render
- `main "$@"` guarded by `[[ ${BASH_SOURCE[0]} == "$0" ]]` so tests can source helpers

## Milestones

### v0.5.0 — Sourceable + plugin JSON safety + finish herdr (Q1)

**Goals**
- Add `[[ ${BASH_SOURCE[0]} == "$0" ]]` guard around `main "$@"` so the file is sourceable.
- Replace plugin event JSON heredocs with a single safe emitter that owns escaping.
- Delete bundled herdr code (~300 LOC). `wt-herdr` plugin becomes the only path.
- Update README, CHANGELOG; bump tap; brew upgrade.

**Files**
- `git-wt` (the binary)
- `tests/test_plugin.bats` — add JSON-escaping tests for branches with `"`, ` `, `\\`
- `tests/lib/setup.bash`

**Acceptance**
- All 6 bats tests pass + 3 new JSON-escaping tests.
- `wt new` without wt-herdr installed: succeeds with informational "no plugin handling wt:worktree-created" line, no tab created.
- `wt new` with wt-herdr installed: tab created exactly once.
- `wt --version` reports 0.5.0.

### v0.6.0 — Worktree record stream (Q2)

**Goals**
- Introduce `wt_each_worktree` / `wt_resolve_id` TSV record stream.
- Migrate `cmd_list`, `cmd_status`, `cmd_audit`, `cmd_reap`, `cmd_tidy`, `cmd_repair` one at a time to consume records.
- Each migration is one commit; revertable independently.

**Acceptance**
- `git worktree list --porcelain` referenced in exactly one place.
- 10+ new bats covering record parser edge cases (detached, symlinks, canonical-skip, duplicate ids).

### v0.7.0 — Branch policy module (Q3)

**Goals**
- Extract `branch_policy_*` from `validate_branch_shape` + `cmd_new` + `generate_path_cache`.
- `cmd_new`: call match-repo → validate → create.
- Hook-cache emits from the same policy interface.

**Acceptance**
- Branch-pattern config changes require editing one function.
- Hook cache and runtime validation provably consistent (one shared test fixture).

### v0.8.0 — Config snapshot (Q4)

**Goals**
- Replace field-by-field `cfg_repo_get` with `cfg_repo_record`.
- `cmd_onboard` writes config then calls `cfg_reload` through the same interface.

**Acceptance**
- yq referenced in one section of the file.
- Config schema changes touch one function.

## Non-goals

- **No rewrite in another language.** Stays bash.
- **No object model.** Records stay TSV.
- **No DSL.** Plugin contract stays JSON, escaping handled at the emitter.
- **No micro-libraries.** This file is one shell script with a sourceable boundary, not a multi-file project.

## Open questions

- **Plugin query events** (`wt:list`, `wt:query-tab-state`) for v0.6+: needed so list/status/tidy can show plugin-provided tab state without depending on the herdr binary on PATH. Deferred until at least one plugin besides wt-herdr exists.
- **Homebrew-core graduation**: candidate after v0.6.0 if adoption signal exists (30+ stars or external contributors).
