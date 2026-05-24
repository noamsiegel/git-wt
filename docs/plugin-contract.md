# git-wt plugin contract

`docs/plugin-contract.md` is source of truth for `git-wt.plugin.v0`.

## Goals

- Keep git-wt core small: worktree policy stays in `wt`; UI/tab integrations live out of process.
- Let plugins be written in any language.
- Make plugin install/enable deterministic and safe enough for agent workflows.
- Support curated bare-name installs while preserving explicit user-trust installs.

## Non-goals

- Hosted marketplace or remote registry service.
- Plugin auto-update.
- New lifecycle events beyond v0's current four until plugin examples require them.
- In-process shell sourcing or shared-library plugins.

## Trust model

Bare-name installs are curated:

```bash
wt plugin install herdr
```

Bare names resolve only through `plugins-registry.json` in the git-wt repo. Unknown bare names fail and list known plugins.

Explicit installs are user-trust:

```bash
wt plugin install noamsiegel/wt-herdr
wt plugin install https://github.com/noamsiegel/wt-herdr.git
```

For explicit `owner/repo` and URL installs, git-wt validates manifest shape and API compatibility, but the user is choosing to trust that source.

## Manifest schema

Each plugin root contains `wt-plugin.json` and an executable named `wt-<name>`.

```json
{
  "api_versions": ["git-wt.plugin.v0"],
  "name": "hello",
  "executable": "wt-hello",
  "events": ["wt:worktree-created"],
  "capabilities": [],
  "version": "0.1.0",
  "description": "example plugin"
}
```

Required fields:

| Field | Type | Meaning |
|---|---|---|
| `api_versions` | string array | Plugin API versions supported by plugin. Must intersect host supported APIs. |
| `name` | string | Plugin name without `wt-` prefix. |
| `executable` | string | Must equal `wt-<name>` and be executable at plugin root. |
| `events` | string array | Lifecycle events plugin subscribes to. |

Optional fields:

| Field | Type | Meaning |
|---|---|---|
| `capabilities` | string array | Actions plugin can perform. Defaults to `[]` if absent. |
| `version` | string | Plugin release version. |
| `description` | string | Human description. |

Backward compatibility: old manifests with singular `api_version: "git-wt.plugin.v0"` are treated as one-element `api_versions` and emit deprecation warning. New plugins must use `api_versions`.

## Events

Plugins receive JSON on stdin and are invoked as:

```bash
wt-<name> event <event-name>
```

Common payload fields:

```json
{
  "api_version": "git-wt.plugin.v0",
  "event": "wt:worktree-created",
  "repo": "repo-name",
  "worktree": {
    "id": "ABC-123-example",
    "path": "/absolute/path/to/worktree",
    "branch": "dev/ABC-123-example"
  },
  "timestamp": "2026-05-24T00:00:00Z"
}
```

Current v0 events:

| Event | Direction | Meaning | Extra fields |
|---|---|---|---|
| `wt:worktree-created` | wt -> plugin | Worktree was created/adopted and plugin may create/bind UI. | none |
| `wt:worktree-removed` | wt -> plugin | Worktree was reaped and plugin may close UI. | `reason` when available |
| `wt:focus` | wt -> plugin | Plugin should focus existing UI for worktree. | none |
| `wt:list` | reserved query event | Future list/status tab query. No new behavior in v0.9.0. | TBD |

Plugin stdout for lifecycle events is ignored unless future query events define response semantics. Plugin failure warns but does not fail the originating git operation.

## JSON parsing in plugins (normative)

Plugins receive event payloads on stdin as JSON. The recommended parser is **[`yq`](https://github.com/mikefarah/yq)**, because:

- git-wt already requires yq for its own config parsing; no new dependency.
- Consistent across the ecosystem.
- Stable expression syntax. Python's `yq` package is incompatible — do NOT use `pip install yq`; install the Go yq from `mikefarah/yq`.

Example plugin event handler:

```bash
payload=$(cat)
worktree_path=$(echo "$payload" | yq -p json '.worktree.path')
```

Existing plugins (`wt-zed`, `wt-cmux`, `wt-herdr`) target yq. `wt-zed` has a python3 fallback for historical reasons; new plugins should not replicate this.

## Capabilities

`events` are subscriptions: what plugin wants to hear.

`capabilities` are actions: what plugin can do.

Current reserved vocabulary:

| Capability | Meaning |
|---|---|
| `tab.focus` | Plugin can focus worktree tab/window/session. |
| `tab.close` | Plugin can close worktree tab/window/session. |
| `tab.query` | Plugin can answer tab status/query events. |

Unknown capabilities are allowed but ignored by git-wt v0.

## Health protocol

Plugins should implement:

```bash
wt-<name> health
```

It returns JSON:

```json
{"ok": true, "version": "0.1.0", "errors": []}
```

If unhealthy:

```json
{"ok": false, "version": "0.1.0", "errors": ["missing herdr binary"]}
```

`wt plugin validate <path>` runs health when executable exists. Non-JSON output, non-zero exit, or `ok: false` makes validation fail with detail.

## Versioning policy

`git-wt.plugin.v0` becomes `git-wt.plugin.v1` when all criteria are true:

1. At least two non-trivial plugins exist outside git-wt core.
2. `events` vs `capabilities` vocabulary has survived real use without breaking change.
3. Query event response shape for `wt:list`/tab status is specified and exercised.
4. Manifest compatibility rules are stable across one release after deprecation of singular `api_version`.
5. Plugin validation covers required v1 invariants.

Before v1, v0 may still evolve with backward compatibility where practical. After v1, breaking changes require a new API string and host/plugin intersection check.

## Reference plugin

Reference implementation: [wt-herdr](https://github.com/noamsiegel/wt-herdr).

## From-scratch hello-world plugin

Create directory:

```bash
mkdir wt-hello
cd wt-hello
```

Write manifest:

```json
{
  "api_versions": ["git-wt.plugin.v0"],
  "name": "hello",
  "executable": "wt-hello",
  "events": ["wt:worktree-created", "wt:focus"],
  "capabilities": [],
  "version": "0.1.0",
  "description": "hello-world git-wt plugin"
}
```

Write executable:

```bash
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  manifest)
    cat "$(dirname "$0")/wt-plugin.json"
    ;;
  health)
    printf '{"ok":true,"version":"0.1.0","errors":[]}\n'
    ;;
  event)
    event="${2:-}"
    payload=$(cat)
    printf 'hello plugin saw %s: %s\n' "$event" "$payload" >> "${WT_HELLO_LOG:-/tmp/wt-hello.log}"
    ;;
  *)
    printf 'usage: wt-hello manifest|health|event <event>\n' >&2
    exit 10
    ;;
esac
```

Make executable and validate:

```bash
chmod +x wt-hello
wt plugin validate .
```

Install for local development:

```bash
wt plugin link "$PWD"
wt plugin emit hello wt:worktree-created --id demo --path /tmp/demo --branch dev/demo
```
