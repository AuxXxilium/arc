#!/bin/sh
#
# PXE init wrapper for Arc Loader
# Supports embedded arc.img or HTTP download via pxe_server= param

# Mount essential filesystems
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null

# Skip if physical ARC disk exists
if blkid 2>/dev/null | grep -q 'LABEL="ARC1"'; then
  exec /init.buildroot "$@"
fi

ARC_IMG="/opt/arc/arc.img"
ARC_IMG_GZ="/opt/arc/arc.img.gz"
PXE_SERVER=$(cat /proc/cmdline 2>/dev/null | sed 's/.*pxe_server=\([^ ]*\).*/\1/')

if [ -z "${PXE_SERVER}" ] && [ ! -f "${ARC_IMG}" ] && [ ! -f "${ARC_IMG_GZ}" ]; then
  exec /init.buildroot "$@"
fi

echo "========================================"
echo " PXE Mode: Setting up loopback disk"
echo "========================================"

mkdir -p /tmp/ramdisk
mount -t tmpfs -o size=2G,mode=0755 tmpfs /tmp/ramdisk

if [ -f "${ARC_IMG_GZ}" ]; then
  echo "PXE: Decompressing embedded arc.img.gz..."
  gzip -dc "${ARC_IMG_GZ}" > /tmp/ramdisk/arc.img
elif [ -f "${ARC_IMG}" ]; then
  echo "PXE: Copying embedded arc.img..."
  cp "${ARC_IMG}" /tmp/ramdisk/arc.img
elif [ -n "${PXE_SERVER}" ]; then
  echo "PXE: Target: http://${PXE_SERVER}/arc.img"

  # Bring up all interfaces
  echo "PXE: Bringing up network..."
  for IF in $(ls /sys/class/net/ 2>/dev/null); do
    echo "  ${IF}: up"
    ip link set "${IF}" up
  done
  sleep 3

  # DHCP
  echo "PXE: Running DHCP..."
  if command -v dhcpcd >/dev/null 2>&1; then
    dhcpcd -n 2>&1
  elif command -v udhcpc >/dev/null 2>&1; then
    udhcpc -n -T 5 -t 3 2>&1
  fi

  # Show IPs for debug
  echo "PXE: IP status:"
  ip addr show 2>/dev/null | grep "inet " || echo "  NO IP ADDRESS!"

  # Download
  echo "PXE: Downloading arc.img..."
  if command -v curl >/dev/null 2>&1; then
    curl -L --connect-timeout 10 --max-time 600 "http://${PXE_SERVER}/arc.img" -o /tmp/ramdisk/arc.img 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget --timeout=600 "http://${PXE_SERVER}/arc.img" -O /tmp/ramdisk/arc.img 2>&1
  fi

  if [ ! -s /tmp/ramdisk/arc.img ]; then
    echo "PXE: ERROR - Failed to download arc.img!"
    echo "PXE: Falling back to normal boot..."
    exec /init.buildroot "$@"
  fi
  echo "PXE: Download OK ($(du -sh /tmp/ramdisk/arc.img | cut -f1))"
fi

# Create loop device
echo "PXE: Creating loop device..."
losetup -P /dev/loop0 /tmp/ramdisk/arc.img

RETRY=0
while [ ! -b /dev/loop0p1 ] && [ ${RETRY} -lt 10 ]; do
  sleep 1
  RETRY=$((RETRY + 1))
done

if [ -b /dev/loop0p1 ]; then
  echo "PXE: Loop device ready /dev/loop0"
else
  echo "PXE: ERROR - loop partitions not created!"
fi

echo "========================================"
echo " PXE setup complete, starting Arc..."
echo "========================================"

exec /init.buildroot "$@"
