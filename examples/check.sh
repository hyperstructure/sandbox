#!/bin/sh
# Checks an image that doesn't start from this one for what fctl needs of
# it (fctl's docs: https://fctl.sh/docs/sandbox-images/#what-an-image-needs).
# Runs inside the image as its user, in place of its ENTRYPOINT, as sessions
# do:
#
#   docker run --rm -i --entrypoint sh IMAGE -s < examples/check.sh
#
# It fails on what sessions can't do without, warns about the rest, and needs
# the network, to reach GitHub as git does.
set -u

failed=0 claude='' fctl_version=''
fail() {
  echo "check.sh: $*" >&2
  failed=1
}
warn() { echo "check.sh: warning: $*" >&2; }

# Whether version $1 (2.1.101) is older than $2.
older() {
  # shellcheck disable=SC2046 # split at the dots
  set -- $(echo "$1 $2" | tr . ' ')
  [ "$1" -lt "$4" ] || { [ "$1" -eq "$4" ] && { [ "$2" -lt "$5" ] || { [ "$2" -eq "$5" ] && [ "$3" -lt "$6" ]; }; }; }
}

# What the host runs in the sandbox itself, by the system's own directories.
[ -x /bin/sh ] || fail "/bin/sh is missing"
for tool in tail id cat mkdir chown chmod mv rm stat; do
  found=
  for dir in /usr/sbin /usr/bin /sbin /bin; do
    [ ! -x "$dir/$tool" ] || found=yes
  done
  [ -n "$found" ] || fail "$tool is not in /usr/bin or /bin"
done

# The user Claude and its commands run as, and its home, from /etc/passwd as
# fctl-agent reads it.
uid=$(id -u)
[ "$uid" != 0 ] ||
  warn "the image runs as root, so Claude does, and its commands can stop fctl-agent: end the Dockerfile with USER and a user of its own"
home=
while IFS=: read -r _ _ id _ _ dir _; do
  if [ "$id" = "$uid" ]; then
    home=$dir
    break
  fi
done </etc/passwd
if [ -z "$home" ]; then
  fail "uid $uid has no line in /etc/passwd, so sessions would have / as their home"
elif [ ! -d "$home" ] || [ ! -w "$home" ]; then
  fail "$home, the home of uid $uid, is missing or not writable"
fi

# What Claude and the setup script find: the image's PATH, and a login
# shell's, which the setup script runs in.
for tool in bash git claude fctl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on the PATH ($PATH)"
done
command -v gh >/dev/null 2>&1 || warn "gh is not on the PATH, so sessions show no pull request"
if command -v bash >/dev/null 2>&1; then
  for tool in git claude fctl; do
    if command -v "$tool" >/dev/null 2>&1 && ! bash -lc "command -v $tool" >/dev/null 2>&1; then
      fail "$tool is not on a login shell's PATH ($(bash -lc 'printf %s "$PATH"'))"
    fi
  done
fi

if command -v claude >/dev/null 2>&1; then
  # `2.1.302 (Claude Code)`
  claude=$(claude --version 2>/dev/null)
  claude=${claude%% *}
  case $claude in
    [0-9]*.[0-9]*.[0-9]*)
      ! older "$claude" 2.1.101 || fail "Claude Code is $claude: fctl needs 2.1.101 or later"
      ;;
    *) fail "claude --version says '$claude'" ;;
  esac
fi
if command -v fctl >/dev/null 2>&1; then
  fctl_version=$(fctl --version 2>/dev/null) || fail "fctl --version fails: is it the build for this architecture?"
fi

[ -w /var/cache/fctl ] ||
  warn "the user can't write to /var/cache/fctl, where fctl mounts the project's package caches, so on hosts that run nothing as root its package managers keep their own"
if command -v git >/dev/null 2>&1 && ! git ls-remote https://github.com/hyperstructure/sandbox HEAD >/dev/null 2>&1; then
  fail "git can't reach GitHub over HTTPS: are CA certificates installed?"
fi

[ "$failed" = 0 ] || exit 1
echo "The image has what fctl needs, with ${fctl_version:-fctl} and Claude Code $claude, as uid $uid in $home."
