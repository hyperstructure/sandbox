#!/usr/bin/env bash
# Builds the kernel that fctl's firecracker driver boots sandboxes with, for
# this machine's architecture: the Linux release in VERSION (whose build
# number, after a dash, changes nothing here), configured as
# Firecracker configures its CI's guests (microvm-<arch>.config, from
# Firecracker's resources/guest_configs), with fctl.config on top. Writes
# the kernel to $OUT/vmlinux (./out unless OUT says otherwise), and its
# configuration next to it.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out=${OUT:-$PWD/out}
version=$(tr -d '[:space:]' < "$here/VERSION")
version=${version%%-*}

case "$(uname -m)" in
  x86_64) config=microvm-x86_64.config target=vmlinux built=vmlinux ;;
  aarch64) config=microvm-aarch64.config target=Image built=arch/arm64/boot/Image ;;
  *) echo "Firecracker runs on x86_64 and aarch64, not $(uname -m)" >&2; exit 1 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
curl -fsSL --retry 3 -o "linux-$version.tar.xz" \
  "https://cdn.kernel.org/pub/linux/kernel/v${version%%.*}.x/linux-$version.tar.xz"
sha256sum --check --quiet "$here/SHA256SUMS"
tar -xf "linux-$version.tar.xz"
cd "linux-$version"

# Later lines win, and olddefconfig settles what this release has that the
# configuration doesn't say.
awk 1 "$here/$config" "$here/fctl.config" > .config
make olddefconfig
make -j"$(nproc)" "$target"

mkdir -p "$out"
cp "$built" "$out/vmlinux"
cp .config "$out/vmlinux.config"
echo "Built Linux $version for $(uname -m): $out/vmlinux"
