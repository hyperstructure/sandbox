#!/usr/bin/env bash
# Boots the kernel at $1 in Firecracker, as fctl's firecracker driver boots
# its sandboxes (an initramfs, a vsock), and checks that it reaches
# userspace with what fctl-agent's init needs: ext4, overlayfs, a vsock and
# TAP devices. Needs /dev/kvm; without it, says so and checks nothing.
set -euo pipefail

kernel=$(realpath "$1")
firecracker_version=1.17.0
arch=$(uname -m)
case "$arch" in
  x86_64) sum=06094a1108ae9e82aa4c23a775aa92758f53f1175d422270d9d6162cb9ade558 ;;
  aarch64) sum=e351ebe4f7a16b5873bbd51005d2e6767103cff4d5ebc829df2d3f95a93e2256 ;;
  *) echo "Firecracker runs on x86_64 and aarch64, not $arch" >&2; exit 1 ;;
esac
if ! [ -r /dev/kvm ] || ! [ -w /dev/kvm ]; then
  echo "No /dev/kvm to use here: the kernel isn't booted."
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

archive="firecracker-v$firecracker_version-$arch.tgz"
curl -fsSL --retry 3 -o "$archive" \
  "https://github.com/firecracker-microvm/firecracker/releases/download/v$firecracker_version/$archive"
echo "$sum  $archive" | sha256sum --check --quiet
tar -xzf "$archive" "release-v$firecracker_version-$arch/firecracker-v$firecracker_version-$arch"
firecracker="$work/release-v$firecracker_version-$arch/firecracker-v$firecracker_version-$arch"

# An initramfs of a static busybox whose init looks around, says what it
# found and resets the VM, which ends Firecracker.
mkdir -p root/bin root/dev root/proc root/sys
cp "$(command -v busybox)" root/bin/busybox
cat > root/init <<'INIT'
#!/bin/busybox sh
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t devtmpfs dev /dev
for fs in ext4 overlay; do
  /bin/busybox grep -qw "$fs" /proc/filesystems || echo "fctl-kernel: no $fs"
done
for dev in /dev/vsock /dev/net/tun; do
  [ -e "$dev" ] || echo "fctl-kernel: no $dev"
done
echo "fctl-kernel: booted $(/bin/busybox uname -r)"
/bin/busybox reboot -f
INIT
chmod 755 root/init
(cd root && find . | cpio --quiet -o -H newc) > initrd.cpio

args="console=ttyS0 panic=1 nomodule quiet rdinit=/init"
if [ "$arch" = x86_64 ]; then args="$args reboot=k i8042.noaux i8042.nomux i8042.dumbkbd pci=off"; fi
cat > vm.json <<JSON
{
  "boot-source": {"kernel_image_path": "$kernel", "initrd_path": "$work/initrd.cpio", "boot_args": "$args"},
  "drives": [],
  "machine-config": {"vcpu_count": 1, "mem_size_mib": 256},
  "vsock": {"guest_cid": 3, "uds_path": "$work/v.sock"}
}
JSON

timeout 120 "$firecracker" --no-api --config-file vm.json > console.log 2>&1 || true
grep "fctl-kernel:" console.log || true
if ! grep -q "fctl-kernel: booted" console.log; then
  echo "The kernel didn't boot to its init. Its console said:" >&2
  tail -40 console.log >&2
  exit 1
fi
if grep -q "fctl-kernel: no" console.log; then
  echo "The kernel lacks what fctl-agent's init needs." >&2
  exit 1
fi
echo "Booted in Firecracker $firecracker_version, with ext4, overlayfs, a vsock and TAP devices."
