# Sandbox

The image [fctl](https://fctl.sh) runs its agents in: Debian with Claude
Code, git, the GitHub CLI, Python, Rust, Node.js, TypeScript and Bun, for
arm64 and amd64.

```sh
docker pull ghcr.io/hyperstructure/sandbox
docker run --rm -it ghcr.io/hyperstructure/sandbox bash
```

fctl hosts pull it themselves: each session runs in a container made from
the tag of the host's own version (hosts of fctl 0.3.0 and earlier build
their own copy instead). It also works as a base for images with more tools
([Building on it](#building-on-it)).

## What's inside

- Debian 12 (bookworm), with `LANG=C.UTF-8` and `TZ=UTC`.
- Claude Code, the native build, in `~/.local/bin`: the newest release when
  the image was built.
- fctl, the release the tag names, in `/usr/local/bin`. Agents name and
  describe their session with `fctl edit`.
- Python 3.15.0 as `python3` and `python` for every user (uv's build of
  CPython, in `/opt/uv/python`), and uv 0.13.4.
- Rust 1.99.1 through rustup, with rustfmt, Clippy and the
  `wasm32-unknown-unknown` target.
- Node.js 26 with npm and corepack 0.36.0 (with its yarn and pnpm shims),
  TypeScript 7.0.2 (`tsc`) and Bun 1.4.3.
- build-essential (gcc, make), cmake, pkg-config and OpenSSL's headers.
- git, the GitHub CLI, ripgrep, fd, jq, ShellCheck, sqlite3, curl, wget,
  rsync, lsof, fuser, tree, file, unzip, zip, xz and zstd.

The versions are set at the top of [`provision.sh`](provision.sh), which
installs everything.

## Tags

| Tag | fctl inside |
|---|---|
| `0.4.0` | 0.4.0. Hosts of that version start their sessions from it. |
| `0.4` | The newest 0.4 release. |
| `latest` | The newest release. |

Each image is built from this repository's `main` with that release of
fctl and the newest Claude Code. A new fctl release gets its image within
the hour, and the newest release's image is rebuilt as things change:

- **A change merged to `main`**: right away.
- **A new Claude Code release**: in the daily run, at 05:41 UTC. fctl turns
  off Claude Code's auto-updater, so an image's Claude Code is as old as the
  image.
- **Debian's updates**: at least once a week.

Images of earlier releases stay as they were last built.

A rebuild moves the tag. To keep one build, pin its digest:
`ghcr.io/hyperstructure/sandbox:0.4.0@sha256:…`. Its labels say what's in
it:

| Label | Value |
|---|---|
| `org.opencontainers.image.version`, `sh.fctl.version` | fctl's version |
| `sh.fctl.claude-code.version` | Claude Code's version |
| `org.opencontainers.image.revision` | the commit of this repository it was built from; images built elsewhere have none |
| `org.opencontainers.image.created` | when it was built |

```sh
docker image inspect ghcr.io/hyperstructure/sandbox \
  --format '{{ index .Config.Labels "sh.fctl.claude-code.version" }}'
```

## Layout

fctl and images built `FROM` this one rely on its layout, which stays the
same from release to release. [`check.sh`](check.sh) checks every build for
it.

- **The user** is `agent`, uid 1000, with the home directory `/home/agent`
  and sudo without a password: the sandbox is the boundary. Sessions run as
  `agent`, in `~/workspace`.
- **The PATH** starts with `~/.local/bin` (Claude Code and uv's tools),
  `~/.cargo/bin` and `~/.bun/bin`, then `/opt/fctl/bin`, where fctl copies
  its supervisor, fctl-agent, when a session starts. The image sets it, and
  `/etc/profile.d/fctl.sh` sets it for login shells. fctl-agent passes
  Claude the PATH, HOME and the locale but none of the image's other
  environment variables, so every tool works from the PATH alone.
- **Rust and Bun** belong to `agent`, in `~/.rustup`, `~/.cargo` and
  `~/.bun`, so agents add toolchains, targets and global tools without sudo
  (`cargo install`, `bun add -g`, and for Python `uv tool install`). Run
  `cargo`, `rustup` and `bun` as `agent`.
- **Python** is marked externally managed: packages go into a virtual
  environment (`uv venv`, `python3 -m venv`) or come with `uv run --with`.
  Debian's Python 3.11, which Node.js depends on, stays in `/usr/bin`, after
  `/usr/local/bin` on the PATH.
- **npm** leaves out its funding and audit notices and its update check
  (`/usr/etc/npmrc`); `npm audit` still runs when asked.

## Building on it

An image that installs something as root switches back to `agent` at the
end:

```dockerfile
FROM ghcr.io/hyperstructure/sandbox:0.4
USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends postgresql-client \
  && rm -rf /var/lib/apt/lists/*
USER agent
```

To run it in fctl, name it in a project's Settings → Sandbox → Image, or as
`image` in a host's `host.toml`
([Sandbox images](https://fctl.sh/docs/sandbox-images/) in fctl's docs).
Apple silicon hosts need arm64 images.

## Building it

```sh
docker build -t sandbox .
docker run --rm -i sandbox sh -s < check.sh
```

`--build-arg FCTL_VERSION=0.4.0` picks the fctl release (default: the
latest) and `--build-arg CLAUDE_VERSION=…` Claude Code's (default: the
latest). On an fctl host, `fctl host image build` builds this repository's
`main` with the host's driver (Apple `container` or Docker) under the
host's image name, or prepares the Lima VM that sessions are cloned from
with `provision.sh`.

The Image workflow ([`.github/workflows/image.yml`](.github/workflows/image.yml))
publishes it: each architecture builds on a runner of its own and is
checked with `check.sh` before the two are tagged as one image. Pull
requests that change the image build and check both without publishing.

## Questions and changes

Open an issue for a tool the image lacks or something that doesn't work in
it, and report vulnerabilities privately: [SECURITY.md](SECURITY.md).
[AGENTS.md](AGENTS.md) describes how changes are made, for people and for
agents.

## License

The files in this repository are under the [MIT license](LICENSE). The image
contains software under its own licenses, among them Claude Code, which
[Anthropic's terms](https://code.claude.com/docs/en/legal-and-compliance)
govern.
