#!/usr/bin/env bash

set -e

if [ ! -d .buildroot ]; then
  echo "Downloading buildroot"
  git clone --single-branch -b 2023.02.x https://github.com/buildroot/buildroot.git .buildroot
fi
# Remove old files
rm -rf ".buildroot/output/target/opt/arc"
rm -rf ".buildroot/board/arc/overlayfs"
rm -rf ".buildroot/board/arc/p1"
rm -rf ".buildroot/board/arc/p3"

# Get Additions

. ./scripts/func.sh

getLKMs "files/board/arc/p3/lkms" true
getAddons "files/board/arc/p3/addons" true
getExtensions "files/board/arc/p3/extensions" true
getModules "files/board/arc/p3/modules" true
getConfigs "files/board/arc/p3/configs" true
getPatches "files/board/arc/p3/patches" true

echo "Subrepos loaded"

# Copy files
echo "Copying files"
VERSION=$(date +'%y.%-m.dev')
rm -f files/board/arc/p1/ARC-VERSION
rm -f VERSION
echo "${VERSION}" >files/board/arc/p1/ARC-VERSION
echo "${VERSION}" >VERSION
sed 's/^ARC_VERSION=.*/ARC_VERSION="'${VERSION}'"/' -i files/board/arc/overlayfs/opt/arc/include/consts.sh
cp -rf files/* .buildroot/

cd .buildroot
echo "Generating default config"
make BR2_EXTERNAL=./external arc_defconfig -j$(nproc)
echo "Version: ${VERSION}"
echo "Building... Drink a coffee and wait!"
make BR2_EXTERNAL=./external -j$(nproc)
cd -
qemu-img convert -O vmdk arc.img arc-dyn.vmdk
qemu-img convert -O vmdk -o adapter_type=lsilogic arc.img -o subformat=monolithicFlat arc.vmdk