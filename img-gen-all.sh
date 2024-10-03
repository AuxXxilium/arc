#!/usr/bin/env bash

set -e

# Clean cached Files
sudo git clean -fdx

. scripts/func.sh

# Get extractor, LKM, addons and Modules
getTheme "files/p1/boot/grub"
getBuildroots "latest" "brs"
getBuildrootx "latest" "brx"

# Sbase
IMAGE_FILE="arc.img"
gzip -dc "grub.img.gz" >"${IMAGE_FILE}"
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

VERSION=$(date +'%y.%m.dev')
echo "${VERSION}" >files/p1/ARC-BASE-VERSION
echo "${VERSION}" >VERSION
echo "stable" >files/p1/ARC-BRANCH
sed 's/^ARC_BASE_VERSION=.*/ARC_BASE_VERSION="'${VERSION}'"/' -i files/initrd/opt/arc/include/base_consts.sh

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

qemu-img convert ${IMAGE_FILE} -O vmdk -o adapter_type=lsilogic arc-dyn.vmdk
qemu-img convert ${IMAGE_FILE} -O vmdk -o adapter_type=lsilogic,subformat=monolithicFlat arc.vmdk
qemu-img convert ${IMAGE_FILE} -O vhdx -o subformat=dynamic arc.vhdx

# Xbase
IMAGE_FILE="arc-next.img"
gzip -dc "grub.img.gz" >"${IMAGE_FILE}"
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
echo "${VERSION}" >files/p1/ARC-BASE-VERSION
echo "${VERSION}" >VERSION
echo "next" >files/p1/ARC-BRANCH
sed 's/^ARC_VERSION=.*/ARC_VERSION="'${VERSION}'"/' -i files/initrd/opt/arc/include/base_consts.sh

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

qemu-img convert ${IMAGE_FILE} -O vmdk -o adapter_type=lsilogic arc-next-dyn.vmdk
qemu-img convert ${IMAGE_FILE} -O vmdk -o adapter_type=lsilogic,subformat=monolithicFlat arc-next.vmdk
qemu-img convert ${IMAGE_FILE} -O vhdx -o subformat=dynamic arc-next.vhdx