---
name: change-the-image
description: Add, upgrade or remove a tool in the sandbox image, or change its layout. Covers where versions live, both architectures, the Lima VM that provision.sh also provisions, what fctl and derived images rely on, the image's size, and verifying a change with a local build or the pull request's Image and Develop fctl workflows. Use for any change to Dockerfile, provision.sh, check.sh or check-fctl.sh.
---

# Changing the image

- `provision.sh` installs everything, as root; the Dockerfile only runs it
  and sets the user and the PATH. The versions are at the top, as
  `NAME="${NAME:-default}"`, so a build can override one.
- `check.sh` is the layout fctl and images built `FROM` this one rely on,
  checked in every build.
- README.md lists the tools with their versions, and the layout.

## Adding or upgrading a tool

1. **Install it in `provision.sh`.** Prefer Debian's package: add it to the
   `apt-get install` list. Otherwise use the project's own installer or
   release archive, with the version pinned at the top of the script, and
   check the download against the checksum the project publishes, when it
   publishes one. A toolchain agents extend (more versions, targets, global
   tools) goes in the agent's home through `as_agent`, like rustup and Bun;
   anything else system-wide.
2. **Make it work from the PATH alone.** fctl-agent passes Claude the PATH,
   HOME and the locale, nothing else from the image. A tool that needs an
   environment variable gets a wrapper or a config file instead. A new PATH
   entry is a layout change (below).
3. **Check for it.** Add the command to `check.sh`'s list of tools, and to
   the `--version` runs when it could be there but broken (a proxy without
   its toolchain).
4. **List it** in README.md's "What's inside", with its version.
5. **Say what it costs.** The Image workflow's summary lists each
   architecture's size; put the difference in the pull request.

An upgrade changes the version at the top of `provision.sh` and in README.md.
Rust follows fctl's `rust-toolchain.toml`; Claude Code and fctl aren't pinned
here (the workflow passes the versions it builds with).

Removing a tool breaks images and sessions that use it: a breaking change
(the `commit` skill) with a reason.

## What bites

- **Two architectures.** Every download works on amd64 and arm64: pick the
  file with `dpkg --print-architecture` (`amd64`, `arm64`) or `uname -m`
  (`x86_64`, `aarch64`).
- **The Lima VM.** fctl's Lima driver runs `provision.sh` in a Debian 13 VM
  (Lima's cloud image, not `trixie-slim`), or a Debian 12 one with Lima
  before 2.0 and on hosts of fctl 0.14 and earlier, so keep it working on
  both. It runs as root, with `AGENT_USER` set to the VM's user, who
  already exists and may not be uid 1000. Use `$AGENT_USER` and
  `$AGENT_HOME`, never `agent` or `/home/agent`, and don't rely on what
  only the Dockerfile sets.
- **Login shells.** Setup scripts and the Lima driver run `bash -l`, which
  reads `/etc/profile.d/fctl.sh`. Keep its PATH and the Dockerfile's
  `ENV PATH` the same.
- **apt's lists** are removed after the first installs; a later
  `apt-get install` needs its own `apt-get update` and cleanup.
- **Python is externally managed.** No `pip install` into the system: use
  `uv tool install` (as the agent) or a Debian package.
- **Playwright's version is its browsers' and their libraries'.** Bumping
  `PLAYWRIGHT_VERSION` moves all three: `playwright install-deps` takes the
  libraries from Playwright's own list for the Debian release it runs on
  (Lima's Debian 12 included), and the global `playwright` installs the
  browsers into the agent's `~/.cache/ms-playwright`. Playwright removes
  browsers that no installed copy of it uses whenever it installs others,
  so the copy that installs them must stay in the image.
- **No auto-updates and no daemons.** fctl turns off Claude Code's
  auto-updater, and sessions start only fctl-agent; a tool that expects a
  service running won't find one.

## Changing the layout

The user, its home, `~/workspace`, `/opt/fctl/bin` and the PATH are an
interface: installed fctl hosts and images built `FROM` this one rely on
them. Look for a way that keeps them first. If there is none:

1. Make it a breaking change (`feat!:` with a `BREAKING CHANGE:` paragraph).
2. Change `check.sh` and README.md's Layout with it.
3. Change fctl's Sandbox images page (`docs/sandbox-images.md` in
   hyperstructure/fctl) to match, and fctl itself when hosts must adapt,
   released before this merges. An fctl session's token covers only its own
   repository: name what hyperstructure/fctl needs, and tell the person.

The newest fctl release's tag is rebuilt from `main`, so its hosts get the
change the next time they pull the image.

## Verifying

- **With Docker:** `docker build -t sandbox:dev .`, then
  `docker run --rm -i sandbox:dev sh -s < check.sh`, and try the tool:
  `docker run --rm sandbox:dev bash -lc 'psql --version'`. Add
  `--platform linux/amd64` (or `arm64`) to try the other architecture under
  emulation, slowly.
- **In an fctl session** (no Docker): open the pull request. The Image
  workflow builds both architectures with the latest fctl and Claude Code
  and runs `check.sh` in each: `gh pr checks N --watch --fail-fast`, then
  the run's summary for the sizes. The Develop fctl workflow runs
  `check-fctl.sh` in each too: fctl's own checks, sessions and screenshots,
  as sessions working on fctl do them, with fctl's branch of the same name
  when there is one.
- **With fctl:** on a host, `docker build -t sandbox:dev .` and set it as a
  project's image (Settings → Sandbox → Image), or
  `fctl host image build --source .` from a checkout, which builds it under
  the host's image name (with Lima: provisions the base VM). Then start a
  session and use the tool.
