#!/usr/bin/env bash
# Boots the kernel at $1 in Firecracker, as fctl's firecracker driver boots
# its sandboxes (an initramfs, a drive, a vsock), and checks that it reaches
# userspace with what fctl-agent's init needs: virtio's MMIO devices, its
# drive mounted as ext4 with an overlay on it, vsock's transport and TAP
# devices. Needs /dev/kvm and mkfs.ext4; without KVM, says so and checks
# nothing.
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

# A drive, as an image's filesystem is: ext4 with a file on it.
mkdir drive
echo hello > drive/hello
truncate -s 16M drive.ext4
"$(command -v mkfs.ext4 || echo /usr/sbin/mkfs.ext4)" -q -F -d drive drive.ext4

# An initramfs of a static busybox whose init tries what fctl-agent's init
# does, says what fails and resets the VM, which ends Firecracker.
mkdir -p root/bin root/dev root/proc root/sys
cp "$(command -v busybox)" root/bin/busybox
cat > root/init <<'INIT'
#!/bin/busybox sh
export PATH=/bin
/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t devtmpfs dev /dev
mount -t sysfs sys /sys
missing() { echo "fctl-kernel: no $1"; }
# The drive: virtio's MMIO transport and its block driver, and ext4.
mkdir -p /image /upper /merged
mount -t ext4 -o ro /dev/vda /image || missing "ext4 on /dev/vda"
# overlayfs, which lays a sandbox's disk over its image.
mount -t tmpfs tmpfs /upper && mkdir -p /upper/root /upper/work
mount -t overlay overlay -o lowerdir=/image,upperdir=/upper/root,workdir=/upper/work /merged ||
  missing overlayfs
grep -q hello /merged/hello 2>/dev/null || missing "the drive's file through the overlay"
# vsock's virtio transport, bound to the VM's device, and TAP devices.
ls /sys/bus/virtio/drivers/vmw_vsock_virtio_transport 2>/dev/null | grep -q virtio ||
  missing "vsock's virtio transport"
[ -e /dev/net/tun ] || missing /dev/net/tun
echo "fctl-kernel: booted $(uname -r)"
reboot -f
INIT
chmod 755 root/init
(cd root && find . | cpio --quiet -o -H newc) > initrd.cpio

args="console=ttyS0 panic=1 nomodule quiet rdinit=/init"
if [ "$arch" = x86_64 ]; then args="$args reboot=k i8042.noaux i8042.nomux i8042.dumbkbd pci=off"; fi
cat > vm.json <<JSON
{
  "boot-source": {"kernel_image_path": "$kernel", "initrd_path": "$work/initrd.cpio", "boot_args": "$args"},
  "drives": [{"drive_id": "vda", "path_on_host": "$work/drive.ext4", "is_root_device": false, "is_read_only": true}],
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
echo "Booted in Firecracker $firecracker_version: a drive with ext4 and an overlay on it, vsock's transport and TAP devices work."
