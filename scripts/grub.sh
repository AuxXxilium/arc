#!/usr/bin/env bash
#
# Copyright (C) 2023 AuxXxilium <https://github.com/AuxXxilium> and Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

GRUB=${1:-"grub-2.06"}
BIOS=${2:-"i386-pc i386-efi x86_64-efi"}
NAME=${3:-"ARC"}

curl -#kLO https://ftp.gnu.org/gnu/grub/${GRUB}.tar.gz
tar -zxvf ${GRUB}.tar.gz

pushd ${GRUB}
for B in ${BIOS}; do
  b=${B}
  b=(${b//-/ })
  echo "Make ${b[@]} ..."

  mkdir -p ${B}
  pushd ${B}
  ../configure --prefix=$PWD/usr -sbindir=$PWD/sbin --sysconfdir=$PWD/etc --disable-werror --target=${b[0]} --with-platform=${b[1]}
  make
  make install
  popd
done
popd

rm -f grub.img
dd if=/dev/zero of=grub.img bs=1M seek=1024 count=0
echo -e "n\np\n1\n\n+50M\nn\np\n2\n\n+50M\nn\np\n3\n\n\na\n1\nw\nq\n" | fdisk grub.img
fdisk -l grub.img

LOOPX=$(sudo losetup -f)
sudo losetup -P ${LOOPX} grub.img
sudo mkdosfs -F32 -n ${NAME}1 ${LOOPX}p1
sudo mkfs.ext2 -F -L ${NAME}2 ${LOOPX}p2
sudo mkfs.ext4 -F -L ${NAME}3 ${LOOPX}p3

rm -rf ${NAME}1
mkdir -p ${NAME}1
sudo mount ${LOOPX}p1 ${NAME}1

sudo mkdir -p ${NAME}1/EFI
sudo mkdir -p ${NAME}1/boot/grub
cat >device.map <<EOF
(hd0)   ${LOOPX}
EOF
sudo mv device.map ${NAME}1/boot/grub/device.map

for B in ${BIOS}; do
  args=""
  args+=" ${LOOPX} --target=${B} --no-floppy --recheck --grub-mkdevicemap=${NAME}1/boot/grub/device.map --boot-directory=${NAME}1/boot"
  if [[ "${B}" == *"efi" ]]; then
    args+=" --efi-directory=${NAME}1 --removable --no-nvram"
  else
    args+=" --root-directory=${NAME}1"
  fi
  sudo ${GRUB}/${B}/grub-install ${args}
done

if [ -d ${NAME}1/boot/grub/fonts ] && [ -f /usr/share/grub/unicode.pf2 ]; then
  sudo cp /usr/share/grub/unicode.pf2 ${NAME}1/boot/grub/fonts
fi

sudo sync

sudo umount ${LOOPX}p1
sudo losetup -d ${LOOPX}
sudo rm -rf ${NAME}1

gzip grub.img