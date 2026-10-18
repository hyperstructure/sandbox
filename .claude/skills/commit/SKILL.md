---
name: commit
description: Commit and open pull requests in hyperstructure/sandbox. Covers Conventional Commit titles, breaking changes, what goes in the description, branch names, waiting for the checks, answering reviews, and what happens after the merge. Use when committing, naming a branch, writing a pull request title or description, or getting a change merged.
---

# Commits and pull requests

Every change reaches `main` as one squash-merged pull request. Its **title
becomes the commit subject** and its description the commit body. Merging a
change to the image publishes it (the `publish` skill), so `main` is always
what's published.

## The title

`type(scope): what changed`, at most 72 characters, no full stop, in the
imperative. The Commits workflow checks every title, and again when you
edit it.

| Type | For |
|---|---|
| `feat` | a tool the image didn't have, or a new major version of one |
| `fix` | something broken in the image or in publishing it |
| `perf` | a smaller or faster image with the same tools |
| `docs` | documentation only |
| `build` | other version upgrades |
| `refactor`, `test`, `ci`, `chore`, `revert` | restructuring; checks; workflows; upkeep; reverts |

The scope is optional: `image`, `ci`, `deps`, `docs`.

- `feat: add PostgreSQL's client`
- `build: upgrade Bun to 1.5.0`
- `fix: put Bun on login shells' PATH`
- `ci: rebuild the image when Claude Code moves on`

A **breaking change** changes what fctl or images built `FROM` this one rely
on (the layout in README.md, a tool removed, a file fctl downloads). It gets
a `!` and a `BREAKING CHANGE:` paragraph in the description that says what
people must do: `feat!: drop Node.js 20`. Check with AGENTS.md whether fctl
must change first.

## The description

Plain prose for someone reading `git log` in a year: what was missing or
wrong, what changed and why this way, what it adds to the image's size, and
how you verified it (the Image workflow's run, `check.sh`, a local build).
Link the issue: `Fixes #12` only when the pull request does everything it
asks, `Refs #12` otherwise.

The description ends with the content: no "Generated with …" footers. A link
to the fctl session that made the change is welcome.

## The flow

1. Branch from an up-to-date `main`: `<type>/<topic>` (`feat/postgres`), or
   `fctl/<number>-<topic>` when an fctl session makes the branch.
2. Commit as you go; the commits are squashed, so the title is what lasts.
3. Run `shellcheck provision.sh check.sh` and `actionlint` if you have them;
   the Lint workflow runs both anyway.
4. Open the pull request with a conventional title and a description. One
   change per pull request.
5. Wait for the checks in the same turn and fix failures (below).
6. A person merges it (squash) when the checks pass, unless they asked you
   to merge it yourself.

Never push to `main` directly, and never commit secrets: the repository and
the image are public.

## The checks

```sh
gh pr checks N --watch --fail-fast
```

- **Image** builds the pull request's image for amd64 and arm64 with the
  latest fctl and Claude Code and runs `check.sh` in each. It runs when the
  image's files or the workflow change, and takes a few minutes.
- **Lint** runs ShellCheck and actionlint.
- **Commits** checks the title. When only it fails, fix the title:
  `gh pr edit N --title "fix: …"`.

Read a failure with `gh run view ID --log-failed`. Something that looks like
infrastructure (a timeout, a registry or download error) gets one rerun
(`gh run rerun ID --failed`); if it fails again, treat it as real. Don't ask
anyone to merge a pull request with failing checks, and don't weaken a check
to make it pass.

## Reviews

Read the conversation and the comments on lines:

```sh
gh pr view N --comments
gh api repos/hyperstructure/sandbox/pulls/N/comments --jq '.[] | {id, path, line, user: .user.login, body}'
```

Answer every comment in its own thread: fix it, push, and reply with what
changed, or say plainly why not. Leave resolving threads to the reviewer.
After changes, update the description so it still says what the pull
request does: it becomes the commit message.

## After the merge

- Don't push to the merged branch; follow-ups go in a new pull request from
  the updated `main`.
- A change to the image starts the Image workflow on `main`. Check that it
  published (the `publish` skill), and say so where the change was asked
  for.
