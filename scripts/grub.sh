#!/usr/bin/env bash
#
# Copyright (C) 2025 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Variables
GRUB=${1:-"grub-2.12"}
BIOS=${2:-"i386-pc i386-efi x86_64-efi"}
NAME=${3:-"ARC"}
GRUB_URL="https://ftp.gnu.org/gnu/grub/${GRUB}.tar.gz"

# Download and extract GRUB
curl -#kLO "${GRUB_URL}"
tar -zxf "${GRUB}.tar.gz"

# Build GRUB for each platform
pushd "${GRUB}" > /dev/null
# Restore the modification to extra_deps.lst
echo "depends bli part_gpt lvm" > grub-core/extra_deps.lst
for B in ${BIOS}; do
  b=${B}
  b=(${b//-/ }) # Split target and platform
  echo "Building for ${b[@]}..."
  mkdir -p "${B}"
  pushd "${B}" > /dev/null
  ../configure --prefix="$PWD/usr" --sbindir="$PWD/sbin" --sysconfdir="$PWD/etc" \
    --disable-werror --target="${b[0]}" --with-platform="${b[1]}"
  make -j$(nproc)
  make install

  # Remove locale files if generated
  LOCALE_DIR="$PWD/usr/share/locale"
  if [[ -d "${LOCALE_DIR}" ]]; then
    echo "Removing locale files..."
    rm -rf "${LOCALE_DIR}"
  fi

  popd > /dev/null
done
popd > /dev/null

# Create GRUB disk image
rm -f grub.img
dd if=/dev/zero of=grub.img bs=1M seek=1850 count=0
echo -e "n\np\n1\n\n+50M\nn\np\n2\n\n+50M\nn\np\n3\n\n\na\n1\nw\nq\n" | fdisk grub.img
fdisk -l grub.img

# Setup loop device
LOOPX=$(sudo losetup -f)
sudo losetup -P "${LOOPX}" grub.img

# Format partitions
sudo mkdosfs -F32 -n "${NAME}1" "${LOOPX}p1"
sudo mkfs.ext2 -F -L "${NAME}2" "${LOOPX}p2"
sudo mkfs.ext4 -F -L "${NAME}3" "${LOOPX}p3"

# Mount and prepare GRUB installation
MOUNT_DIR="${NAME}1"
rm -rf "${MOUNT_DIR}"
mkdir -p "${MOUNT_DIR}"
sudo mount "${LOOPX}p1" "${MOUNT_DIR}"

sudo mkdir -p "${MOUNT_DIR}/EFI" "${MOUNT_DIR}/boot/grub"
cat > device.map <<EOF
(hd0)   ${LOOPX}
EOF
sudo mv device.map "${MOUNT_DIR}/boot/grub/device.map"

# Install GRUB for each platform
for B in ${BIOS}; do
  args=("${LOOPX}" "--target=${B}" "--no-floppy" "--recheck" "--grub-mkdevicemap=${MOUNT_DIR}/boot/grub/device.map" "--boot-directory=${MOUNT_DIR}/boot")
  if [[ "${B}" == *"efi" ]]; then
    args+=("--efi-directory=${MOUNT_DIR}" "--removable" "--no-nvram")
  else
    args+=("--root-directory=${MOUNT_DIR}")
  fi
  sudo "${GRUB}/${B}/grub-install" "${args[@]}"
done

# Copy GRUB font if available
if [[ -d "${MOUNT_DIR}/boot/grub/fonts" && -f /usr/share/grub/unicode.pf2 ]]; then
  sudo cp /usr/share/grub/unicode.pf2 "${MOUNT_DIR}/boot/grub/fonts"
fi

# Finalize and cleanup
sudo sync
sudo umount "${LOOPX}p1"
sudo losetup -d "${LOOPX}"
sudo rm -rf "${MOUNT_DIR}"

gzip grub.img