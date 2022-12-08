#!/usr/bin/env bash

set -e

if [ ! -d .buildroot ]; then
  echo "Downloading buildroot"
  git clone --single-branch -b 2022.02 https://github.com/buildroot/buildroot.git .buildroot
fi
# Remove old files
rm -rf ".buildroot/output/target/opt/arc"
rm -rf ".buildroot/board/arc/overlayfs"
rm -rf ".buildroot/board/arc/p1"
rm -rf ".buildroot/board/arc/p3"

# Get latest LKMs
echo "Getting latest LKMs"
if [ `ls ../redpill-lkm/output | wc -l` -eq 0 ]; then
  echo "  Downloading from github"
  TAG=`curl -s https://api.github.com/repos/AuxXxilium/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
  curl -L "https://github.com/AuxXxilium/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o /tmp/rp-lkms.zip
  rm -rf files/board/arc/p3/lkms/*
  unzip /tmp/rp-lkms.zip -d files/board/arc/p3/lkms
else
  echo "  Copying from ../redpill-lkm/output"
  rm -rf files/board/arc/p3/lkms/*
  cp -f ../redpill-lkm/output/* files/board/arc/p3/lkms
fi

# Get latest addons and install its
echo "Getting latest Addons"
rm -Rf /tmp/addons
mkdir -p /tmp/addons
  TAG=`curl -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
  curl -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o /tmp/addons.zip
  rm -rf /tmp/addons
  unzip /tmp/addons.zip -d /tmp/addons
DEST_PATH="files/board/arc/p3/addons"
echo "Installing addons to ${DEST_PATH}"
for PKG in `ls /tmp/addons/*.addon`; do
  ADDON=`basename ${PKG} | sed 's|.addon||'`
  mkdir -p "${DEST_PATH}/${ADDON}"
  echo "Extracting ${PKG} to ${DEST_PATH}/${ADDON}"
  tar xaf "${PKG}" -C "${DEST_PATH}/${ADDON}"
done

# Get latest modules
echo "Getting latest modules"
mkdir -p "${PWD}/files/board/arc/p3/modules"
MODULES_DIR="${PWD}/files/board/arc/p3/modules"
  TAG=`curl -s https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
  while read PLATFORM KVER; do
    FILE="${PLATFORM}-${KVER}"
    curl -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/${FILE}.tgz" -o "${MODULES_DIR}/${FILE}.tgz"
  done < PLATFORMS
  curl -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/firmware.tgz" -o "${MODULES_DIR}/firmware.tgz"

# Copy files
echo "Copying files"
VERSION=`cat VERSION`
sed 's/^arc_VERSION=.*/arc_VERSION="'${VERSION}'"/' -i files/board/arc/overlayfs/opt/arc/include/consts.sh
echo "${VERSION}" > files/board/arc/p1/ARC-VERSION
cp -Ru files/* .buildroot/

cd .buildroot
echo "Generating default config"
make BR2_EXTERNAL=../external -j`nproc` arc_defconfig
echo "Version: ${VERSION}"
echo "Building... Drink a coffee and wait!"
make BR2_EXTERNAL=../external -j`nproc`
cd -
qemu-img convert -O vmdk arc.img arc-dyn.vmdk
qemu-img convert -O vmdk -o adapter_type=lsilogic arc.img -o subformat=monolithicFlat arc.vmdk
[ -x test.sh ] && ./test.sh
rm -f *.zip
zip -9 "arc-${VERSION}.img.zip" arc.img
zip -9 "arc-${VERSION}.vmdk-dyn.zip" arc-dyn.vmdk
zip -9 "arc-${VERSION}.vmdk-flat.zip" arc.vmdk arc-flat.vmdk
sha256sum update-list.yml > sha256sum
yq '.replace | explode(.) | to_entries | map([.key])[] | .[]' update-list.yml | while read F; do
  (cd `dirname ${F}` && sha256sum `basename ${F}`) >> sha256sum
done
yq '.replace | explode(.) | to_entries | map([.key])[] | .[]' update-list.yml | xargs zip -9j "update.zip" sha256sum update-list.yml
rm -f sha256sum
