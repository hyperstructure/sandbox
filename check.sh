#!/bin/sh
# Checks an image built from this repository for what fctl and images built
# FROM it rely on (README.md's Layout): the agent user, sudo, the PATH and the
# tools. Runs inside the image as its user; the image workflow runs it on
# every build:
#
#   docker run --rm -i -e FCTL_VERSION=0.3.0 -e CLAUDE_VERSION=2.1.302 IMAGE sh -s < check.sh
#
# FCTL_VERSION and CLAUDE_VERSION, when set, are the versions it must have.
set -eu

fail() {
  echo "check.sh: $*" >&2
  exit 1
}

[ "$(id -un)" = agent ] || fail "runs as $(id -un), not agent"
[ "$(id -u)" = 1000 ] || fail "agent has uid $(id -u), not 1000"
[ "$HOME" = /home/agent ] || fail "HOME is $HOME, not /home/agent"
sudo -n true 2>/dev/null || fail "agent cannot use sudo without a password"
# The image's PATH, and login shells', which setup scripts run in and which get
# it from /etc/profile.d/fctl.sh.
login_path=$(bash -lc 'printf %s "$PATH"')
for dir in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin" /opt/fctl/bin; do
  for path in "$PATH" "$login_path"; do
    case ":$path:" in
      *":$dir:"*) ;;
      *) fail "$dir is not on the PATH ($path)" ;;
    esac
  done
done
[ -d /opt/fctl/bin ] || fail "/opt/fctl/bin is missing"
[ -d "$HOME/workspace" ] || fail "$HOME/workspace is missing"
[ -w "$HOME/workspace" ] || fail "$HOME/workspace is not writable"
for tool in sh tail git gh claude fctl python3 python uv rustup cargo rustc node npm corepack tsc bun \
  make cc cmake pkg-config rg fd jq shellcheck sqlite3 curl wget rsync zip tree \
  playwright xvfb-run ffmpeg magick pngquant; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on the PATH"
done
[ "$(command -v claude)" = "$HOME/.local/bin/claude" ] || fail "claude is $(command -v claude), not ~/.local/bin/claude"
# rustup's proxies are there even without a toolchain; these run from HOME
# and the PATH alone, as Claude's shell has them.
for tool in cargo rustc rustfmt cargo-clippy python3 tsc bun; do
  "$tool" --version >/dev/null 2>&1 || fail "$tool --version fails"
done
pkg-config --exists openssl || fail "OpenSSL's headers are missing"
# Playwright's browsers are agent's, where Playwright looks for them with HOME
# alone, and start with the libraries and fonts the image has.
[ -w "$HOME/.cache/ms-playwright" ] || fail "$HOME/.cache/ms-playwright is missing or not writable"
for browser in chromium webkit; do
  out=$(playwright screenshot --browser "$browser" 'data:text/html,<p>fctl</p>' "/tmp/check-$browser.png" 2>&1) ||
    fail "Playwright's $browser takes no screenshot: $out"
done

# `2.1.302 (Claude Code)` and `fctl 0.3.0`.
claude=$(claude --version)
claude=${claude%% *}
fctl=$(fctl --version)
fctl=${fctl#fctl }
[ -z "${CLAUDE_VERSION:-}" ] || [ "$claude" = "$CLAUDE_VERSION" ] ||
  fail "Claude Code is $claude, not $CLAUDE_VERSION"
[ -z "${FCTL_VERSION:-}" ] || [ "$fctl" = "$FCTL_VERSION" ] ||
  fail "fctl is $fctl, not $FCTL_VERSION"
echo "The image is as expected, with fctl $fctl and Claude Code $claude."
