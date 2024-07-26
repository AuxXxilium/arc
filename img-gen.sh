#!/usr/bin/env bash

set -e

# Clean cached Files
sudo git clean -fdx

. scripts/func.sh

# Get extractor, LKM, addons and Modules
getLKMs "files/p3/lkms"
getAddons "files/p3/addons"
getModules "files/p3/modules"
getConfigs "files/p3/configs"
getPatches "files/p3/patches"
getTheme "files/p1/boot/grub"
getOffline "files/p3/configs"
getBuildroot "latest" "brx"
getBuildroot "stable" "brs"

# Xbase
IMAGE_FILE="arc-x.img"
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

VERSION=$(date +'%y.%-m.dev')
echo "${VERSION}-x" >files/p1/ARC-VERSION
echo "${VERSION}-x" >VERSION
sed 's/^ARC_VERSION=.*/ARC_VERSION="'${VERSION}-x'"/' -i files/initrd/opt/arc/include/consts.sh

echo "Repack initrd"
cp -f "brx/bzImage-arc" "files/p3/bzImage-arc"
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

qemu-img convert ${IMAGE_FILE} -O vmdk -o adapter_type=lsilogic arc-x-dyn.vmdk
qemu-img convert ${IMAGE_FILE} -O vmdk -o adapter_type=lsilogic,subformat=monolithicFlat arc-x.vmdk
qemu-img convert ${IMAGE_FILE} -O vhdx -o subformat=dynamic arc-x.vhdx

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

[[ ! -f "brs/bzImage-arc" || ! -f "brs/initrd-arc" ]] && return 1

VERSION=$(date +'%y.%-m.dev')
echo "${VERSION}-s" >files/p1/ARC-VERSION
echo "${VERSION}-s" >VERSION
sed 's/^ARC_VERSION=.*/ARC_VERSION="'${VERSION}-s'"/' -i files/initrd/opt/arc/include/consts.sh

echo "Repack initrd"
cp -f "brs/bzImage-arc" "files/p3/bzImage-arc"
repackInitrd "brs/initrd-arc" "files/initrd" "files/p3/initrd-arc"

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

qemu-img convert ${IMAGE_FILE} -O vmdk -o adapter_type=lsilogic arc-s-dyn.vmdk
qemu-img convert ${IMAGE_FILE} -O vmdk -o adapter_type=lsilogic,subformat=monolithicFlat arc-s.vmdk
qemu-img convert ${IMAGE_FILE} -O vhdx -o subformat=dynamic arc-s.vhdx