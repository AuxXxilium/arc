#!/usr/bin/env bash

set -e

if [ ! -d .buildroot ]; then
  echo "Downloading buildroot"
  git clone --single-branch -b 2022.02 https://github.com/buildroot/buildroot.git .buildroot
fi
# Remove old files
rm -rf ".buildroot/output/target/opt/arpl"
rm -rf ".buildroot/board/arpl/overlayfs"
rm -rf ".buildroot/board/arpl/p1"
rm -rf ".buildroot/board/arpl/p3"

# Get extractor, LKM, Addons and Modules

. scripts/func.sh

getExtractor "files/board/arpl/p3/extractor"
getLKMs "files/board/arpl/p3/lkms"
getAddons "files/board/arpl/p3/addons"
getModules "files/board/arpl/p3/modules"

echo "Extractor, LKM, Addons and Modules loaded"

# Copy files
echo "Copying files"
VERSION=$(date +'%y.%m.%d')
rm -f files/board/arpl/p1/ARPL-VERSION
rm -f VERSION
echo "${VERSION}" > files/board/arpl/p1/ARPL-VERSION
echo "${VERSION}" > VERSION
sed 's/^ARPL_VERSION=.*/ARPL_VERSION="'${VERSION}'"/' -i files/board/arpl/overlayfs/opt/arpl/include/consts.sh
cp -rf files/* .buildroot/

cd .buildroot
echo "Generating default config"
make BR2_EXTERNAL=../external -j`nproc` arpl_defconfig
echo "Version: ${VERSION}"
echo "Building... Drink a coffee and wait!"
make BR2_EXTERNAL=../external -j`nproc`
cd -
rm -f arc.img
cp -f arpl.img arc.img
qemu-img convert -O vmdk arc.img arc-dyn.vmdk
qemu-img convert -O vmdk -o adapter_type=lsilogic arc.img -o subformat=monolithicFlat arc.vmdk
[ -x test.sh ] && ./test.sh
rm -f *.zip
zip -9 "arc.img.zip" arc.img
zip -9 "arc.vmdk-dyn.zip" arc-dyn.vmdk
zip -9 "arc.vmdk-flat.zip" arc.vmdk arc-flat.vmdk
sha256sum update-list.yml > sha256sum
zip -9j update.zip update-list.yml
while read F; do
  if [ -d "${F}" ]; then
    FTGZ="`basename "${F}"`.tgz"
    tar czf "${FTGZ}" -C "${F}" .
    sha256sum "${FTGZ}" >> sha256sum
    zip -9j update.zip "${FTGZ}"
    rm "${FTGZ}"
  else
    (cd `dirname ${F}` && sha256sum `basename ${F}`) >> sha256sum
    zip -9j update.zip "${F}"
  fi
done < <(yq '.replace | explode(.) | to_entries | map([.key])[] | .[]' update-list.yml)
zip -9j update.zip sha256sum 
rm -f sha256sum