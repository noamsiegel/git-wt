# Contributing to wt

Thanks for improving `wt`. Keep changes small, boring, and worktree-safe.

## How to report a bug

Open a [bug report](./.github/ISSUE_TEMPLATE/bug.md) with reproduction steps, expected behavior, actual behavior, and your environment.

## How to propose a feature

Open a [feature request](./.github/ISSUE_TEMPLATE/feature.md) with the problem, proposed solution, and alternatives considered.

## Development setup

`wt` is a bash CLI for git worktree management.

Dependencies:

```bash
brew install bash git yq herdr bats-core actionlint gitleaks lefthook
```

Required runtime tools are bash >= 4, git, mikefarah/yq, and `realpath`. `herdr` is optional for tab integration but expected for full local testing.

Clone and work from a normal checkout or a `wt` worktree:

```bash
git clone https://github.com/noamsiegel/git-wt.git
cd git-wt
```

Do not test changes against real user repositories unless the sandboxed test suite already passes.

## Running tests

```bash
./tests/run.sh
```

The runner uses sandboxed fixtures and a herdr stub; it should not touch your real repos or herdr state.

## Commit message format

Conventional Commits are recommended but not strictly required:

```text
fix: repair hook chaining for repo-local hooks
feat: add doctor check for missing yq
```

## Pull request checklist

- [ ] Tests pass with `./tests/run.sh`.
- [ ] Lint/security checks are clean.
- [ ] Documentation is updated when behavior changes.
- [ ] `CHANGELOG.md` is updated for user-visible changes.
