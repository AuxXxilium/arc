#!/usr/bin/env bash
#
# Copyright (C) 2023 AuxXxilium <https://github.com/AuxXxilium> and Ing <https://github.com/wjz304>
# 
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Get Extractor
# $1 path
function getExtractor() {
  echo "Getting syno extractor begin"
  local DEST_PATH="${1:-extractor}"
  local CACHE_DIR="/tmp/pat"
  rm -rf "${CACHE_DIR}"
  mkdir -p "${CACHE_DIR}"
  # Download pat file
  # global.synologydownload.com, global.download.synology.com, cndl.synology.cn
  local PAT_URL="https://global.synologydownload.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
  local PAT_FILE="DSM_DS3622xs+_42218.pat"
  local STATUS=$(curl -# -w "%{http_code}" -L "${PAT_URL}" -o "${CACHE_DIR}/${PAT_FILE}")
  if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
    echo "[E] DSM_DS3622xs%2B_42218.pat download error!"
    rm -rf ${CACHE_DIR}
    exit 1
  fi

  mkdir -p "${CACHE_DIR}/ramdisk"
  tar -C "${CACHE_DIR}/ramdisk/" -xf "${CACHE_DIR}/${PAT_FILE}" rd.gz 2>&1
  if [ $? -ne 0 ]; then
    echo "[E] extractor rd.gz error!"
    rm -rf ${CACHE_DIR}
    exit 1
  fi
  (
    cd "${CACHE_DIR}/ramdisk"
    xz -dc <rd.gz | cpio -idm
  ) >/dev/null 2>&1 || true

  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"

  # Copy only necessary files
  for f in libcurl.so.4 libmbedcrypto.so.5 libmbedtls.so.13 libmbedx509.so.1 libmsgpackc.so.2 libsodium.so libsynocodesign-ng-virtual-junior-wins.so.7; do
    cp -f "${CACHE_DIR}/ramdisk/usr/lib/${f}" "${DEST_PATH}"
  done
  cp -f "${CACHE_DIR}/ramdisk/usr/syno/bin/scemd" "${DEST_PATH}/syno_extract_system_patch"

  # Clean up
  rm -rf ${CACHE_DIR}
  echo "Getting syno extractor end"
}

# Get latest LKMs
# $1 path
function getLKMs() {
  echo "Getting LKMs begin"
  local DEST_PATH="${1:-lkms}"
  local CACHE_FILE="/tmp/rp-lkms.zip"
  rm -f "${CACHE_FILE}"
  if [ -n "${LKMTAG}" ]; then
    TAG="${LKMTAG}"
  else
    TAG="$(curl -s "https://api.github.com/repos/AuxXxilium/redpill-lkm/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')"
  fi
  STATUS=$(curl -w "%{http_code}" -L "https://github.com/AuxXxilium/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o "${CACHE_FILE}")
  echo "TAG=${TAG}; Status=${STATUS}"
  [ ${STATUS} -ne 200 ] && exit 1
  # Unzip LKMs
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  unzip "${CACHE_FILE}" -d "${DEST_PATH}"
  rm -f "${CACHE_FILE}"
  echo "Getting LKMs end - ${TAG}"
}

# Get latest Addons
# $1 path
function getAddons() {
  echo "Getting Addons begin"
  local DEST_PATH="${1:-addons}"
  local CACHE_DIR="/tmp/addons"
  local CACHE_FILE="/tmp/addons.zip"
  if [ -n "${ADDONSTAG}" ]; then
    TAG="${ADDONSTAG}"
  else
    TAG="$(curl -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
  fi
  STATUS=$(curl -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o "${CACHE_FILE}")
  echo "TAG=${TAG}; Status=${STATUS}"
  [ ${STATUS} -ne 200 ] && exit 1
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  # Install Addons
  rm -rf "${CACHE_DIR}"
  mkdir -p "${CACHE_DIR}"
  unzip "${CACHE_FILE}" -d "${CACHE_DIR}"
  echo "Installing Addons to ${DEST_PATH}"
  [ -f /tmp/addons/VERSION ] && cp -f /tmp/addons/VERSION ${DEST_PATH}/
  for PKG in $(ls ${CACHE_DIR}/*.addon); do
    ADDON=$(basename "${PKG}" .addon)
    mkdir -p "${DEST_PATH}/${ADDON}"
    echo "Extracting ${PKG} to ${DEST_PATH}/${ADDON}"
    tar -xaf "${PKG}" -C "${DEST_PATH}/${ADDON}"
  done
  rm -f "${CACHE_FILE}"
  echo "Getting Addons end - ${TAG}"
}

# Get latest Modules
# $1 path
function getModules() {
  echo "Getting Modules begin"
  local DEST_PATH="${1:-modules}"
  local CACHE_FILE="/tmp/modules.zip"
  rm -f "${CACHE_FILE}"
  if [ -n "${MODULESTAG}" ]; then
    TAG="${MODULESTAG}"
  else
    TAG="$(curl -s https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
  fi
  STATUS=$(curl -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip" -o "${CACHE_FILE}")
  echo "TAG=${TAG}; Status=${STATUS}"
  [ ${STATUS} -ne 200 ] && exit 1
  # Unzip Modules
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  unzip "${CACHE_FILE}" -d "${DEST_PATH}"
  rm -f "${CACHE_FILE}"
  echo "Getting Modules end - ${TAG}"
}

# Get latest Configs
# $1 path
function getConfigs() {
  echo "Getting Configs begin"
  local DEST_PATH="${1:-configs}"
  local CACHE_FILE="/tmp/configs.zip"
  rm -f "${CACHE_FILE}"
  if [ -n "${CONFIGSTAG}" ]; then
    TAG="${CONFIGSTAG}"
  else
    TAG="$(curl -s https://api.github.com/repos/AuxXxilium/arc-configs/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
  fi
  STATUS=$(curl -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs.zip" -o "${CACHE_FILE}")
  echo "TAG=${TAG}; Status=${STATUS}"
  [ ${STATUS} -ne 200 ] && exit 1
  # Unzip Modules
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  unzip "${CACHE_FILE}" -d "${DEST_PATH}"
  rm -f "${CACHE_FILE}"
  echo "Getting Configs end - ${TAG}"
}

# Get latest Patches
# $1 path
function getPatches() {
  echo "Getting Patches begin"
  local DEST_PATH="${1:-patches}"
  local CACHE_FILE="/tmp/patches.zip"
  rm -f "${CACHE_FILE}"
  if [ -n "${PATCHESTAG}" ]; then
    TAG="${PATCHESTAG}"
  else
    TAG="$(curl -s https://api.github.com/repos/AuxXxilium/arc-patches/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
  fi
  STATUS=$(curl -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches.zip" -o "${CACHE_FILE}")
  echo "TAG=${TAG}; Status=${STATUS}"
  [ ${STATUS} -ne 200 ] && exit 1
  # Unzip Modules
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  unzip "${CACHE_FILE}" -d "${DEST_PATH}"
  rm -f "${CACHE_FILE}"
  echo "Getting Patches end - ${TAG}"
}

# Get latest Buildroot
# $1 TAG
# $2 path
function getBuildroot() {
  echo "Getting Buildroot begin"
  local TAG="${1:-latest}"
  local DEST_PATH="${2:-br}"

  if [ "${1}" = "latest" ]; then
    TAG=$(curl -s "https://api.github.com/repos/AuxXxilium/arc-buildroot/releases" | jq -r ".[0].tag_name")
  fi
  [ ! -d "${DEST_PATH}" ] && mkdir -p "${DEST_PATH}"
  rm -rf "${DEST_PATH}/bzImage-arc"
  STATUS=$(curl -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-buildroot/releases/download/${TAG}/bzImage" -o "${DEST_PATH}/bzImage-arc")
  echo "TAG=${TAG}; Status=${STATUS}"
  [ ${STATUS} -ne 200 ] && exit 1

  rm -rf "${DEST_PATH}/initrd-arc"
  STATUS=$(curl -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-buildroot/releases/download/${TAG}/rootfs.cpio.xz" -o "${DEST_PATH}/initrd-arc")
  echo "TAG=${TAG}; Status=${STATUS}"
  [ ${STATUS} -ne 200 ] && exit 1

  echo "Getting Buildroot end"
}

# repack initrd
# $1 initrd file  
# $2 plugin path
# $3 output file
function repackInitrd() {
  INITRD_FILE="${1}"
  PLUGIN_PATH="${2}"
  OUTPUT_PATH="${3:-${INITRD_FILE}}"

  [ -z "${INITRD_FILE}" ] || [ ! -f "${INITRD_FILE}" ] && exit 1
  [ -z "${PLUGIN_PATH}" ] || [ ! -d "${PLUGIN_PATH}" ] && exit 1
  
  INITRD_FILE="$(readlink -f "${INITRD_FILE}")"
  PLUGIN_PATH="$(readlink -f "${PLUGIN_PATH}")"
  OUTPUT_PATH="$(readlink -f "${OUTPUT_PATH}")"

  RDXZ_PATH="rdxz_tmp"
  mkdir -p "${RDXZ_PATH}"
  (
    cd "${RDXZ_PATH}"
    sudo xz -dc <"${INITRD_FILE}" | sudo cpio -idm
  ) || true
  sudo cp -Rf "${PLUGIN_PATH}/"* "${RDXZ_PATH}/"
  [ -f "${OUTPUT_PATH}" ] && rm -rf "${OUTPUT_PATH}"
  (
    cd "${RDXZ_PATH}"
    sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | xz --check=crc32 >"${OUTPUT_PATH}"
  ) || true
  sudo rm -rf "${RDXZ_PATH}"
}

# resizeimg
# $1 input file  
# $2 changsize MB eg: +50M -50M
# $3 output file
function resizeImg() {
  INPUT_FILE="${1}"
  CHANGE_SIZE="${2}"
  OUTPUT_FILE="${3:-${INPUT_FILE}}"

  [[ -z "${INPUT_FILE}" || ! -f "${INPUT_FILE}" ]] && exit 1
  [ -z "${CHANGE_SIZE}" ] && exit 1

  INPUT_FILE="$(readlink -f "${INPUT_FILE}")"
  OUTPUT_FILE="$(readlink -f "${OUTPUT_FILE}")"


  SIZE=$(($(du -m "${INPUT_FILE}" | awk '{print $1}')$(echo "${CHANGE_SIZE}" | sed 's/M//g; s/b//g')))
  [[ -z "${SIZE}" || "${SIZE}" -lt 0 ]] && exit 1

  if [ ! "${INPUT_FILE}" = "${OUTPUT_FILE}" ]; then
    sudo cp -f "${INPUT_FILE}" "${OUTPUT_FILE}"
  fi

  sudo truncate -s ${SIZE}M "${OUTPUT_FILE}"
  echo -e "d\n\nn\n\n\n\n\nn\nw" | sudo fdisk "${OUTPUT_FILE}"
  LOOPX=$(sudo losetup -f)
  sudo losetup -P ${LOOPX} "${OUTPUT_FILE}"
  sudo e2fsck -fp $(ls ${LOOPX}* | sort -n | tail -1)
  sudo resize2fs $(ls ${LOOPX}* | sort -n | tail -1)
  sudo losetup -d ${LOOPX}
}