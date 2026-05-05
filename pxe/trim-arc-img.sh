#!/bin/bash
set -e
#
# Trim arc.img for PXE boot (conservative: keep geminilake only)
# Removes: non-geminilake modules, evo kernel/initrd, custom/, non-geminilake lkms
# Expected savings: ~560MB
#

ARC_IMG="/mnt/d/software/Synology_Arc/arc-configured.img"
if [ ! -f "${ARC_IMG}" ]; then
  echo "ERROR: ${ARC_IMG} not found!"
  echo "Please extract arc-configured.img from USB first."
  exit 1
fi

echo "=== Trimming arc-configured.img for geminilake ==="
echo "Original size: $(du -sh ${ARC_IMG} | cut -f1)"

WORK="/root/arc-trim"
rm -rf "${WORK}"
mkdir -p "${WORK}" && cd "${WORK}"

echo '=== [1] Mount arc.img partitions ==='
losetup -P /dev/loop0 "${ARC_IMG}"
mkdir -p p1 p2 p3
mount /dev/loop0p1 p1
mount /dev/loop0p2 p2
mount /dev/loop0p3 p3

echo '=== [2] Remove non-geminilake modules ==='
echo "  Before: $(du -sh p3/modules | cut -f1)"
cd p3/modules
for f in *.tgz; do
  case "${f}" in
    geminilake-4.4.302.tgz|firmware.tgz)
      echo "  KEEP: ${f}"
      ;;
    *)
      echo "  DEL:  ${f} ($(du -sh "${f}" | cut -f1))"
      rm -f "${f}"
      ;;
  esac
done
cd "${WORK}"
echo "  After:  $(du -sh p3/modules | cut -f1)"

echo '=== [3] Remove evo kernel + initrd ==='
for f in p3/bzImage-evo p3/initrd-evo; do
  if [ -f "${f}" ]; then
    echo "  DEL:  $(basename ${f}) ($(du -sh "${f}" | cut -f1))"
    rm -f "${f}"
  fi
done

echo '=== [4] Remove custom/ (epyc7002 only) ==='
if [ -d "p3/custom" ]; then
  echo "  DEL:  custom/ ($(du -sh p3/custom | cut -f1))"
  rm -rf p3/custom/*
  # Keep .gitkeep if exists
  touch p3/custom/.gitkeep
fi

echo '=== [5] Remove non-geminilake lkms ==='
echo "  Before: $(du -sh p3/lkms | cut -f1)"
cd p3/lkms
for f in rp-*.ko.gz; do
  case "${f}" in
    rp-geminilake-4.4.302-*)
      echo "  KEEP: ${f}"
      ;;
    *)
      echo "  DEL:  ${f}"
      rm -f "${f}"
      ;;
  esac
done
cd "${WORK}"
echo "  After:  $(du -sh p3/lkms | cut -f1)"

echo '=== [6] Summary ==='
echo "  p3/modules: $(du -sh p3/modules | cut -f1)"
echo "  p3/lkms:    $(du -sh p3/lkms | cut -f1)"
echo "  p3 total:   $(du -sh p3 | cut -f1)"
echo "  Remaining files in p3 root:"
ls -lh p3/ | grep -v '^total' | grep -v '^d'

echo '=== [7] Unmount and detach ==='
sync
umount p1 p2 p3
losetup -d /dev/loop0

echo "=== Done! ==="
echo "Trimmed size: $(du -sh ${ARC_IMG} | cut -f1)"
echo ""
echo "Next: rebuild PXE initrd with:"
echo "  wsl -d Ubuntu -u root -- bash /mnt/d/software/Synology_Arc/pxe/rebuild-embedded.sh"
rm -rf "${WORK}"
