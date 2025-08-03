#!/usr/bin/env bash
#
# Copyright (C) 2025 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

set -e

# Clean cached Files
sudo git clean -fdx

. scripts/functions.sh "${AUX_TOKEN}"

# Unmount Image File
sudo umount "/tmp/p1" 2>/dev/null || true
sudo umount "/tmp/p3" 2>/dev/null || true

# Get extractor, LKM, addons and Modules
echo "Get Dependencies"
getAddons "files/p3/addons"
getModules "files/p3/modules"
getConfigs "files/p3/configs"
getPatches "files/p3/patches"
getCustom "files/p3/custom"
getLKMs "files/p3/lkms"
getTheme "files/p1/boot/grub"
getOffline "files/p3/configs"
case "${1}" in
  evo) getBuildroot "${1}" "br" ;;
  essential) getBuildroot "${1}" "br" ;;
  *) echo "Invalid option specified" ;;
esac

# Sbase
IMAGE_FILE="arc.img"
gzip -dc "files/initrd/opt/arc/grub.img.gz" >"${IMAGE_FILE}"
fdisk -l "${IMAGE_FILE}"

LOOPX=$(sudo losetup -f)
sudo losetup -P "${LOOPX}" "${IMAGE_FILE}"

echo "Mounting Image File"
sudo rm -rf "/tmp/p1"
sudo rm -rf "/tmp/p3"
mkdir -p "/tmp/p1"
mkdir -p "/tmp/p3"
sudo mount ${LOOPX}p1 "/tmp/p1"
sudo mount ${LOOPX}p3 "/tmp/p3"

ARC_BUILD="$(date +'%y%m%d')"
ARC_VERSION="13.3.7"
echo "${ARC_VERSION}" >"files/p1/ARC-VERSION"
echo "${ARC_BUILD}" >"files/p1/ARC-BUILD"

echo "Repack initrd"
if [ -f "br/bzImage-arc" ] && [ -f "br/initrd-arc" ]; then
    cp -f "br/bzImage-arc" "files/p3/bzImage-arc"
    repackInitrd "br/initrd-arc" "files/initrd" "files/p3/initrd-arc"
else
    exit 1
fi

echo "Copying files"
sudo cp -rf "files/p1/"* "/tmp/p1"
sudo cp -rf "files/p3/"* "/tmp/p3"
sudo sync

echo "Unmount image file"
sudo umount "/tmp/p1"
sudo umount "/tmp/p3"
sudo rm -rf "/tmp/p1"
sudo rm -rf "/tmp/p3"

sudo losetup --detach ${LOOPX}

# echo "Resize Image File"
# mv -f "${IMAGE_FILE}" "${IMAGE_FILE}.tmp"
# resizeImg "${IMAGE_FILE}.tmp" "+1024M" "${IMAGE_FILE}"
# rm -f "${IMAGE_FILE}.tmp"

qemu-img convert -p -f raw -o subformat=monolithicFlat -O vmdk ${IMAGE_FILE} arc.vmdk
