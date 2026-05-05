#!/bin/bash
set -e
#
# Shrink arc-configured.img by zeroing freed blocks
# This makes gzip compression much more effective
#

ARC_IMG="/mnt/d/software/Synology_Arc/arc-configured.img"
if [ ! -f "${ARC_IMG}" ]; then
  echo "ERROR: ${ARC_IMG} not found!"
  exit 1
fi

echo "=== Shrink arc-configured.img ==="
echo "Before: $(du -sh ${ARC_IMG} | cut -f1)"

echo '=== [1] Mount partitions ==='
losetup -P /dev/loop0 "${ARC_IMG}"
mkdir -p /tmp/p1 /tmp/p2 /tmp/p3
mount /dev/loop0p1 /tmp/p1
mount /dev/loop0p2 /tmp/p2
mount -o discard /dev/loop0p3 /tmp/p3

echo '=== [2] Try fstrim on p3 ==='
fstrim -v /tmp/p3 2>/dev/null || echo "  fstrim not supported, using zero-fill instead"

echo '=== [3] Zero-fill free space on all partitions ==='
for mnt in /tmp/p1 /tmp/p2 /tmp/p3; do
  echo "  Zero-filling ${mnt}..."
  dd if=/dev/zero of="${mnt}/.zero" bs=1M status=progress 2>&1 | tail -1 || true
  rm -f "${mnt}/.zero"
  echo "  Done: ${mnt} free space zeroed"
done

echo '=== [4] Sync and unmount ==='
sync
umount /tmp/p1 /tmp/p2 /tmp/p3
losetup -d /dev/loop0
rmdir /tmp/p1 /tmp/p2 /tmp/p3

echo "=== Done! ==="
echo "After:  $(du -sh ${ARC_IMG} | cut -f1)"
echo ""
echo "Now rebuild PXE initrd with:"
echo "  wsl -d Ubuntu -u root -- bash /mnt/d/software/Synology_Arc/pxe/rebuild-embedded.sh"
