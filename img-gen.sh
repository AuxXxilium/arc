#!/usr/bin/env bash

set -e

if [ ! -d .buildroot ]; then
  echo "Downloading buildroot"
  git clone --single-branch -b 2023.02.x https://github.com/buildroot/buildroot.git .buildroot
fi
# Remove old files
rm -rf ".buildroot/output/target/opt/arpl"
rm -rf ".buildroot/board/arpl/overlayfs"
rm -rf ".buildroot/board/arpl/p1"
rm -rf ".buildroot/board/arpl/p3"

# Get extractor, LKM, Addons and Modules

. ./scripts/func.sh

getExtractor "files/board/arpl/p3/extractor"
getLKMs "files/board/arpl/p3/lkms"
getAddons "files/board/arpl/p3/addons"
getExtensions "files/board/arpl/p3/extensions"
getModules "files/board/arpl/p3/modules"
getConfigs "files/board/arpl/p3/configs"

echo "Extractor, LKM, Addons and Modules loaded"

# Copy files
echo "Copying files"
VERSION=$(date +'%y.%-m.dev')
rm -f files/board/arpl/p1/ARPL-VERSION
rm -f VERSION
echo "${VERSION}" >files/board/arpl/p1/ARPL-VERSION
echo "${VERSION}" >VERSION
sed 's/^ARPL_VERSION=.*/ARPL_VERSION="'${VERSION}'"/' -i files/board/arpl/overlayfs/opt/arpl/include/consts.sh
cp -rf files/* .buildroot/

cd .buildroot
echo "Generating default config"
make BR2_EXTERNAL=../external -j$(nproc) arpl_defconfig
echo "Version: ${VERSION}"
echo "Building... Drink a coffee and wait!"
make BR2_EXTERNAL=../external -j$(nproc)
cd -
rm -f arc.img
cp -f arpl.img arc.img
rm -f arpl.img
qemu-img convert -O vmdk arc.img arc-dyn.vmdk
qemu-img convert -O vmdk -o adapter_type=lsilogic arc.img -o subformat=monolithicFlat arc.vmdk