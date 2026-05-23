# Security Policy

## Reporting a vulnerability

Email security reports to noam@noamsiegel.com.

Do not open public issues for security bugs. Include enough detail to reproduce the problem, the affected version or commit, and any known impact. You can expect a private response before public disclosure is coordinated.

## Supported versions

| Version | Supported |
|---|---|
| 0.x | Yes |

## Security boundaries

`wt` installs and chains git hooks that enforce the canonical-checkout discipline, branch validation, autopush behavior, and personal/repo-local hook handoff. Hook chain integrity is a security boundary.

Report any bypass that lets a repository silently skip, reorder, replace, or weaken the intended hook chain without an explicit user escape hatch.
