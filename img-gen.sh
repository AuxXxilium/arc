#!/usr/bin/env bash

set -e

. scripts/func.sh

IMAGE_FILE="arc.img"
gzip -dc "files/grub.img.gz" >"${IMAGE_FILE}"
fdisk -l "${IMAGE_FILE}"

LOOPX=$(sudo losetup -f)
sudo losetup -P "${LOOPX}" "${IMAGE_FILE}"

echo "Mounting image file"
mkdir -p "/tmp/p1"
mkdir -p "/tmp/p3"
sudo mount ${LOOPX}p1 "/tmp/p1"
sudo mount ${LOOPX}p3 "/tmp/p3"

echo "Get Buildroot"
read -rp 'Version (2023.02.x): ' br_version
[ -z "${br_version}" ] && br_version="2023.02.x"
getBuildroot "${br_version}" "br"
[ ! -f "br/bzImage-arc" ] || [ ! -f "br/initrd-arc" ] && return 1

VERSION=$(date +'%y.%-m.dev')
echo "${VERSION}" >files/p1/ARC-VERSION
echo "${VERSION}" >VERSION
sed 's/^ARC_VERSION=.*/ARC_VERSION="'${VERSION}'"/' -i files/initrd/opt/arc/include/consts.sh

echo "Repack initrd"
cp -f "br/bzImage-arc" "/tmp/p3/bzImage-arc"
repackInitrd "br/initrd-arc" "files/initrd" "/tmp/p3/initrd-arc"

# Get extractor, LKM, addons and Modules
getExtractor "files/p3/extractor"
getLKMs "files/p3/lkms" true
getAddons "files/p3/addons" true
getExtensions "files/p3/extensions" true
getModules "files/p3/modules" true
getConfigs "files/p3/configs" true
getPatches "files/p3/patches" true

echo "Copying files"
sudo cp -Rf "files/p1/"* "/tmp/p1"
sudo cp -Rf "files/p3/"* "/tmp/p3"

read -r -p "Subrepos loaded. Press ENTER to continue"

sync

echo "Unmount image file"
sudo umount "/tmp/p1"
sudo umount "/tmp/p3"
rmdir "/tmp/p1"
rmdir "/tmp/p3"

sudo losetup --detach ${LOOPX}

qemu-img convert -O vmdk arc.img arc-dyn.vmdk
qemu-img convert -O vmdk -o adapter_type=lsilogic arc.img -o subformat=monolithicFlat arc.vmdk