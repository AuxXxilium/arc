#!/usr/bin/env bash
#
# Copyright (C) 2023 AuxXxilium <https://github.com/AuxXxilium> and Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

PROMPT=$(sudo -nv 2>&1)
if [ $? -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

function help() {
  echo "Usage: $0 <command> [args]"
  echo "Commands:"
  echo "  create [workspace] [arc.img] - Create the workspace"
  echo "  pack [arc.img] - Pack to arc.img"
  echo "  help - Show this help"
  exit 1
}

function create() {
  WORKSPACE="$(realpath ${1:-"workspace"})"
  ARCIMGPATH="$(realpath ${2:-"arc.img"})"

  if [ ! -f "${ARCIMGPATH}" ]; then
    echo "File not found: ${ARCIMGPATH}"
    exit 1
  fi

  sudo apt update
  sudo apt install -y busybox dialog curl xz-utils cpio sed qemu-utils

  YQ=$(command -v yq)
  if [ -z "${YQ}" ] || ! ${YQ} --version 2>/dev/null | grep -q "v4."; then
    wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O "${YQ:-"/usr/bin/yq"}" && chmod +x "${YQ:-"/usr/bin/yq"}"
  fi

  LOOPX=$(sudo losetup -f)
  sudo losetup -P "${LOOPX}" "${ARCIMGPATH}"

  echo "Mounting image file"
  rm -rf "/tmp/mnt/p1"
  rm -rf "/tmp/mnt/p2"
  rm -rf "/tmp/mnt/p3"
  mkdir -p "/tmp/mnt/p1"
  mkdir -p "/tmp/mnt/p2"
  mkdir -p "/tmp/mnt/p3"
  sudo mount ${LOOPX}p1 "/tmp/mnt/p1" || (
    echo -e "Can't mount ${LOOPX}p1."
    exit 1
  )

  sudo mount ${LOOPX}p2 "/tmp/mnt/p2" || (
    echo -e "Can't mount ${LOOPX}p2."
    exit 1
  )
  sudo mount ${LOOPX}p3 "/tmp/mnt/p3" || (
    echo -e "Can't mount ${LOOPX}p3."
    exit 1
  )

  echo "Create WORKSPACE"
  rm -rf "${WORKSPACE}"
  mkdir -p "${WORKSPACE}/mnt"
  mkdir -p "${WORKSPACE}/tmp"
  mkdir -p "${WORKSPACE}/initrd"
  cp -rf "/tmp/mnt/p1" "${WORKSPACE}/mnt/p1"
  cp -rf "/tmp/mnt/p2" "${WORKSPACE}/mnt/p2"
  cp -rf "/tmp/mnt/p3" "${WORKSPACE}/mnt/p3"
  sudo sync
  sudo umount "/tmp/mnt/p1"
  sudo umount "/tmp/mnt/p2"
  sudo umount "/tmp/mnt/p3"
  rm -rf "/tmp/mnt/p1"
  rm -rf "/tmp/mnt/p2"
  rm -rf "/tmp/mnt/p3"
  sudo losetup --detach ${LOOPX}

  rm -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/arc.env
  echo "OK."
}

function pack() {
  if [ ! -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/arc.env ]; then
    echo "Please run init first"
    exit 1
  fi
  . $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/arc.env

  ARCIMGPATH="$(realpath ${1:-"arc.img"})"
  if [ ! -f "${ARCIMGPATH}" ]; then
    gzip -dc "${CHROOT_PATH}/initrd/opt/arc/grub.img.gz" >"${ARCIMGPATH}"
  fi
  fdisk -l "${ARCIMGPATH}"

  LOOPX=$(sudo losetup -f)
  sudo losetup -P "${LOOPX}" "${ARCIMGPATH}"

  echo "Mounting image file"
  rm -rf "/tmp/mnt/p1"
  rm -rf "/tmp/mnt/p2"
  rm -rf "/tmp/mnt/p3"
  mkdir -p "/tmp/mnt/p1"
  mkdir -p "/tmp/mnt/p2"
  mkdir -p "/tmp/mnt/p3"
  sudo mount ${LOOPX}p1 "/tmp/mnt/p1" || (
    echo -e "Can't mount ${LOOPX}p1."
    exit 1
  )
  sudo mount ${LOOPX}p2 "/tmp/mnt/p2" || (
    echo -e "Can't mount ${LOOPX}p2."
    exit 1
  )
  sudo mount ${LOOPX}p3 "/tmp/mnt/p3" || (
    echo -e "Can't mount ${LOOPX}p3."
    exit 1
  )

  echo "Pack image file"
  sudo cp -rf "${CHROOT_PATH}/mnt/p1/"* "/tmp/mnt/p1" || (
    echo -e "Can't cp ${LOOPX}p1."
    exit 1
  )
  sudo cp -rf "${CHROOT_PATH}/mnt/p2/"* "/tmp/mnt/p2" || (
    echo -e "Can't cp ${LOOPX}p2."
    exit 1
  )
  sudo cp -rf "${CHROOT_PATH}/mnt/p3/"* "/tmp/mnt/p3" || (
    echo -e "Can't cp ${LOOPX}p3."
    exit 1
  )
  sudo sync
  sudo umount "/tmp/mnt/p1"
  sudo umount "/tmp/mnt/p2"
  sudo umount "/tmp/mnt/p3"
  rm -rf "/tmp/mnt/p1"
  rm -rf "/tmp/mnt/p2"
  rm -rf "/tmp/mnt/p3"
  sudo losetup --detach ${LOOPX}
  echo "OK."
}

$@
