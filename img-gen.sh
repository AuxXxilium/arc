#!/usr/bin/env bash

set -e

. scripts/func.sh

IMAGE_FILE="arc.img"
gzip -dc "files/grub.img.gz" >"${IMAGE_FILE}"
fdisk -l "${IMAGE_FILE}"

LOOPX=$(sudo losetup -f)
sudo losetup -P "${LOOPX}" "${IMAGE_FILE}"

echo "Mounting Image File"
sudo rm -rf "/tmp/files/p1"
sudo rm -rf "/tmp/files/p3"
sudo mkdir -p "/tmp/files/p1"
sudo mkdir -p "/tmp/files/p3"
sudo mount ${LOOPX}p1 "/tmp/files/p1"
sudo mount ${LOOPX}p3 "/tmp/files/p3"

echo "Get Buildroot"
read -rp 'Version (2023.02.x): ' br_version
[ -z "${br_version}" ] && br_version="2023.02.x"
[[ ! -f "br/bzImage-arc" || ! -f "br/initrd-arc" ]] && getBuildroot "${br_version}" "br"
[[ ! -f "br/bzImage-arc" || ! -f "br/initrd-arc" ]] && return 1

VERSION=$(date +'%y.%-m.dev')
echo "${VERSION}" >files/p1/ARC-VERSION
echo "${VERSION}" >VERSION
sed 's/^ARC_VERSION=.*/ARC_VERSION="'${VERSION}'"/' -i files/initrd/opt/arc/include/consts.sh

read -rp "Build: ${VERSION}? Press ENTER to continue"

echo "Repack initrd"
sudo cp -f "br/bzImage-arc" "/tmp/files/p3/bzImage-arc"
repackInitrd "br/initrd-arc" "files/initrd" "/tmp/files/p3/initrd-arc"

echo "Copying files"
sudo cp -Rf "files/p1/"* "/tmp/files/p1"
sudo cp -Rf "files/p3/"* "/tmp/files/p3"
# Get extractor, LKM, addons and Modules
getExtractor "/tmp/files/p3/extractor"
getLKMs "/tmp/files/p3/lkms" true
getAddons "/tmp/files/p3/addons" true
getModules "/tmp/files/p3/modules" true
getConfigs "/tmp/files/p3/configs" true
getPatches "/tmp/files/p3/patches" true

sync

echo "Unmount Image File"
sudo umount "/tmp/files/p1"
sudo umount "/tmp/files/p3"

sudo losetup --detach ${LOOPX}

qemu-img convert -O vmdk arc.img arc-dyn.vmdk
qemu-img convert -O vmdk -o adapter_type=lsilogic arc.img -o subformat=monolithicFlat arc.vmdk