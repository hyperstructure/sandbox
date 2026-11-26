#!/usr/bin/env bash
# shellcheck disable=SC2016 # single-quoted scripts expand in the agent's shell
# Provisions an fctl agent sandbox: the tools agents need, Claude Code and
# fctl. Used by the Dockerfile (container sandboxes, Debian 13) and by `fctl
# host image build --driver lima`, which runs it in a Debian VM (fctl-base) as
# root with AGENT_USER set to the VM's user: Debian 13, or 12 with Lima before
# 2.0 and hosts of fctl 0.14 and earlier, so it works on both. Runs as root.
#
# FCTL_VERSION picks the fctl release and FCTL_DOWNLOAD where releases come
# from (`fctl host image build` passes its own version and download_base);
# empty means the latest, from https://fctl.sh/releases. CLAUDE_VERSION
# picks Claude Code's (empty: the latest); the image workflow passes the one
# it labels the image with, so that every architecture gets the same.
#
# It runs its steps (STEPS, below) in order, or only those named as its
# arguments: the Dockerfile runs each in a RUN of its own, so that no layer
# takes long to download (the Dockerfile says why).
#
#   bash provision.sh                # everything
#   bash provision.sh tools node     # two steps
set -euo pipefail

AGENT_USER="${AGENT_USER:-agent}"
# Toolchain versions; README.md lists them too. Rust is the release fctl
# builds with (rust-toolchain.toml in hyperstructure/fctl), so sessions
# working on fctl have nothing to download: bump the two together.
NODE_MAJOR="${NODE_MAJOR:-26}"
COREPACK_VERSION="${COREPACK_VERSION:-0.36.0}"
TYPESCRIPT_VERSION="${TYPESCRIPT_VERSION:-7.0.2}"
BUN_VERSION="${BUN_VERSION:-1.4.4}"
UV_VERSION="${UV_VERSION:-0.13.4}"
PYTHON_VERSION="${PYTHON_VERSION:-3.15.0}"
RUST_VERSION="${RUST_VERSION:-1.99.1}"
# Playwright's version picks its browsers' builds and the system libraries
# they need, which come with it.
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.64.1}"
FCTL_VERSION="${FCTL_VERSION:-}"
FCTL_DOWNLOAD="${FCTL_DOWNLOAD:-}"
CLAUDE_VERSION="${CLAUDE_VERSION:-}"
export DEBIAN_FRONTEND=noninteractive

# Installs Debian packages. apt's lists are fetched once per run of the
# script, which removes them as it ends, so that no layer keeps them.
apt_listed=
apt_install() {
  [ -n "$apt_listed" ] || apt-get update
  apt_listed=yes
  apt-get install -y --no-install-recommends "$@"
}

# Runs a script as the agent user in a login shell; it gets the arguments
# after the script as $1….
as_agent() {
  local script="$1"
  shift
  sudo -u "$AGENT_USER" -H bash -lc "set -euo pipefail; $script" bash "$@"
}

# The command-line tools.
step_tools() {
  apt_install \
    ca-certificates curl wget git gnupg less openssh-client procps psmisc lsof sudo \
    rsync unzip xz-utils zip zstd \
    jq ripgrep fd-find tree file shellcheck sqlite3
  # Debian calls fd `fdfind`.
  ln -sf /usr/bin/fdfind /usr/local/bin/fd
}

# What builds C and C++.
step_build_tools() {
  apt_install build-essential cmake pkg-config libssl-dev
}

# Recordings and images.
step_media_tools() {
  apt_install ffmpeg imagemagick pngquant
}

# GitHub CLI, Node.js, corepack, TypeScript and Playwright. Node.js stopped
# shipping corepack in 25, so it comes from npm, which also puts its yarn and
# pnpm shims on the PATH. npm leaves out its funding and audit notices and
# its update check, which only lengthen agents' output.
step_node() {
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  # It updates apt's lists, the GitHub CLI's included.
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt_listed=yes
  apt_install gh nodejs
  npm config set --location=global fund=false audit=false update-notifier=false
  npm install -g "corepack@$COREPACK_VERSION" "typescript@$TYPESCRIPT_VERSION" \
    "playwright@$PLAYWRIGHT_VERSION"
  npm cache clean --force
}

# The system libraries and fonts that Playwright's Chromium, Firefox and
# WebKit need, from its own list for this Debian release, and Xvfb for
# headed browsers. It updates apt's lists itself. The agent's browsers come
# later.
step_browser_libraries() {
  playwright install-deps chromium firefox webkit
}

# uv, and Python for everyone: uv's build of CPython in /opt/uv/python, as
# python3 and python in /usr/local/bin.
step_python() {
  curl -LsSf "https://astral.sh/uv/$UV_VERSION/install.sh" | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
  env UV_PYTHON_INSTALL_DIR=/opt/uv/python UV_PYTHON_BIN_DIR=/usr/local/bin UV_NO_CACHE=1 \
    uv python install --default --preview-features python-install-default "$PYTHON_VERSION"
}

# fctl, for everyone on the machine: agents name and describe their session
# with `fctl edit`. A version that is not published (a development build of
# the host) gets the latest release instead.
install_fctl() {
  curl -fsSL https://fctl.sh/install |
    env FCTL_VERSION="$1" FCTL_DOWNLOAD="$FCTL_DOWNLOAD" FCTL_INSTALL_DIR=/usr/local/bin \
      FCTL_NO_COMPLETIONS=1 sh
}

# The agent user, fctl's directories, fctl, and the agent's PATH.
step_user() {
  # The sandbox is the security boundary, so sudo needs no password.
  if ! id "$AGENT_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -u 1000 "$AGENT_USER"
  fi
  local home
  home="$(getent passwd "$AGENT_USER" | cut -d: -f6)"
  echo "$AGENT_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-fctl-$AGENT_USER"
  chmod 0440 "/etc/sudoers.d/90-fctl-$AGENT_USER"
  sudo -u "$AGENT_USER" -H mkdir -p "$home/workspace"
  # Root's: fctl runs its supervisor, fctl-agent, as root from there, so the
  # agent user must not put another in its place.
  mkdir -p /opt/fctl/bin
  chown -R root:root /opt/fctl
  chmod 755 /opt/fctl /opt/fctl/bin
  # The agent user's: fctl mounts a project's package caches here, and Docker
  # gives a new volume the owner of the directory it is mounted on, so a host
  # that runs nothing as root in its sandboxes needn't chown it.
  install -d -o "$AGENT_USER" -g "$(id -g "$AGENT_USER")" /var/cache/fctl

  if ! install_fctl "$FCTL_VERSION"; then
    [ -n "$FCTL_VERSION" ] || exit 1
    echo "fctl $FCTL_VERSION is not published; installing the latest release" >&2
    install_fctl ""
  fi
  # The host copies its own fctl-agent in at session start, so the one in
  # the archive goes.
  rm -f /usr/local/bin/fctl-agent-*-linux

  # The agent's PATH: Claude Code and uv's tools in ~/.local/bin, Rust's and
  # Bun's tools, then fctl's supervisor. The Dockerfile sets the same; login
  # shells (setup scripts, the Lima driver's, as_agent's) get it from here.
  cat > /etc/profile.d/fctl.sh <<'PROFILE'
PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:/opt/fctl/bin:$PATH"
PROFILE
}

# Claude Code, installed for the agent user (native build, ~/.local/bin/claude).
step_claude() {
  sudo -u "$AGENT_USER" -H env CLAUDE_VERSION="$CLAUDE_VERSION" \
    bash -c 'curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_VERSION:+"$CLAUDE_VERSION"}'
}

# Rust, with the components and targets that rust-toolchain.toml lists, and
# Bun, in the agent's home: they find their files through HOME alone
# (fctl-agent passes Claude no RUSTUP_HOME or the like), and agents add
# toolchains, targets and global tools without sudo.
#
# The compiler, cargo, rustfmt and Clippy first. The standard library for
# this machine goes, to come back in the next step with wasm32's: in one
# layer they are over 200 MB on amd64.
step_rust() {
  as_agent 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs |
    sh -s -- -y --no-modify-path --profile minimal --default-toolchain "$1" \
      --component rustfmt,clippy
    rustup target remove --toolchain "$1" "$(rustc -vV | sed -n "s/^host: //p")"' "$RUST_VERSION"
}

step_rust_std() {
  as_agent 'rustup target add --toolchain "$1" \
    "$(rustc -vV | sed -n "s/^host: //p")" wasm32-unknown-unknown' "$RUST_VERSION"
}

step_bun() {
  as_agent 'curl -fsSL https://bun.sh/install | bash -s "bun-v$1"' "$BUN_VERSION"
  as_agent 'ln -sf bun "$HOME/.bun/bin/bunx"'
}

# Playwright's headless Chromium and its WebKit, in ~/.cache/ms-playwright,
# where Playwright looks for them with HOME alone (fctl leaves
# PLAYWRIGHT_BROWSERS_PATH unset for an image that has them there): agents
# add the other browsers and other versions' builds without sudo. They stay
# when other versions install theirs, for as long as the global Playwright
# that installed them is there.
step_chromium() {
  as_agent 'playwright install --only-shell --no-progress chromium'
}

step_webkit() {
  as_agent 'playwright install --no-progress webkit'
}

# What sessions find on the PATH.
step_versions() {
  as_agent 'claude --version; fctl --version; python3 --version; uv --version
    rustc --version; cargo --version; node --version; corepack --version; tsc --version
    bun --version; playwright --version'
}

STEPS=(
  tools build-tools media-tools node browser-libraries python
  user claude rust rust-std bun chromium webkit versions
)
[ "$#" -gt 0 ] || set -- "${STEPS[@]}"
for step in "$@"; do
  case " ${STEPS[*]} " in
    *" $step "*) ;;
    *)
      echo "provision.sh: there is no step $step; the steps are ${STEPS[*]}" >&2
      exit 2
      ;;
  esac
  "step_${step//-/_}"
done
# No layer keeps apt's lists (apt_install), nor Node.js's compile cache,
# which npm turns on.
rm -rf /var/lib/apt/lists/* /tmp/node-compile-cache
