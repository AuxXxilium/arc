#!/usr/bin/env bash

set -e

# Clean cached Files
sudo git clean -fdx

. scripts/func.sh

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
getBuildrootx "brx"

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

[[ ! -f "brx/bzImage-arc" || ! -f "brx/initrd-arc" ]] && return 1

VERSION=$(date +'%y.%m.dev')
echo "${VERSION}" >files/p1/ARC-VERSION
echo "${VERSION}" >VERSION
echo "dev" >files/p1/ARC-BRANCH

echo "Repack initrd"
cp -f "brx/bzImage-arc" "files/p3/bzImage-arc"
cp -f "brx/initrd-arc" "files/p3/initrd-arc"
repackInitrd "brx/initrd-arc" "files/initrd" "files/p3/initrd-arc"

echo "Copying files"
sudo cp -Rf "files/p1/"* "/tmp/p1"
sudo cp -Rf "files/p3/"* "/tmp/p3"
sync

echo "Unmount image file"
sudo umount "/tmp/p1"
sudo umount "/tmp/p3"
rmdir "/tmp/p1"
rmdir "/tmp/p3"

sudo losetup --detach ${LOOPX}

qemu-img convert ${IMAGE_FILE} -O vmdk -o adapter_type=lsilogic,subformat=monolithicFlat arc.vmdk