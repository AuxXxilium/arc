#!/usr/bin/env bash
#
# Copyright (C) 2025 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

[ -n "${1}" ] && export TOKEN="${1}"

# Get latest LKMs
# $1 path
function getLKMs() {
  echo "Getting LKMs begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/rp-lkms.zip"
  rm -f "${CACHE_FILE}"
  TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-lkm/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  export LKMTAG="${TAG}"
  while read -r ID NAME; do
    if [ "${NAME}" = "rp-lkms.zip" ]; then
      curl -kL -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/arc-lkm/releases/assets/${ID}" -o "${CACHE_FILE}"
      # Unzip LKMs
      rm -rf "${DEST_PATH}"
      mkdir -p "${DEST_PATH}"
      if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
        rm -f "${CACHE_FILE}"
        echo "Getting LKMs end - ${TAG}"
        break
      fi
    fi
  done < <(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-lkm/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
}

# Get latest Addons
# $1 path
function getAddons() {
  echo "Getting Addons begin"
  local DEST_PATH="${1}"
  local CACHE_DIR="/tmp/addons"
  local CACHE_FILE="/tmp/addons.zip"
  rm -f "${CACHE_FILE}"
  TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-addons/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  export ADDONTAG="${TAG}"
  while read -r ID NAME; do
    if [ "${NAME}" = "addons-${TAG}.zip" ]; then
      curl -kL -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/arc-addons/releases/assets/${ID}" -o "${CACHE_FILE}"
      # Unzip Addons
      rm -rf "${CACHE_DIR}"
      mkdir -p "${CACHE_DIR}"
      mkdir -p "${DEST_PATH}"
      if unzip -o "${CACHE_FILE}" -d "${CACHE_DIR}"; then
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
        break
      fi
    fi
  done < <(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-addons/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
}

# Get latest Modules
# $1 path
function getModules() {
  echo "Getting Modules begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/modules.zip"
  rm -f "${CACHE_FILE}"
  TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-modules/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  export MODULETAG="${TAG}"
  while read -r ID NAME; do
    if [ "${NAME}" = "modules-${TAG}.zip" ]; then
      curl -kL -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/arc-modules/releases/assets/${ID}" -o "${CACHE_FILE}"
      # Unzip Modules
      rm -rf "${DEST_PATH}"
      mkdir -p "${DEST_PATH}"
      if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
        rm -f "${CACHE_FILE}"
        echo "Getting Modules end - ${TAG}"
        break
      fi
    fi
  done < <(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-modules/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
}

# Get latest Configs
# $1 path
function getConfigs() {
  echo "Getting Configs begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/configs.zip"
  rm -f "${CACHE_FILE}"
  TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-configs/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  export CONFIGTAG="${TAG}"
  while read -r ID NAME; do
    if [ "${NAME}" = "configs-${TAG}.zip" ]; then
      curl -kL -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/arc-configs/releases/assets/${ID}" -o "${CACHE_FILE}"
      # Unzip Configs
      rm -rf "${DEST_PATH}"
      mkdir -p "${DEST_PATH}"
      if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
        rm -f "${CACHE_FILE}"
        echo "Getting Configs end - ${TAG}"
        break
      fi
    fi
  done < <(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-configs/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
}

# Get latest Patches
# $1 path
function getPatches() {
  echo "Getting Patches begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/patches.zip"
  rm -f "${CACHE_FILE}"
  TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-patches/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  export PATCHTAG="${TAG}"
  while read -r ID NAME; do
    if [ "${NAME}" = "patches-${TAG}.zip" ]; then
      curl -kL -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/arc-patches/releases/assets/${ID}" -o "${CACHE_FILE}"
      # Unzip Patches
      rm -rf "${DEST_PATH}"
      mkdir -p "${DEST_PATH}"
      if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
        rm -f "${CACHE_FILE}"
        echo "Getting Patches end - ${TAG}"
        break
      fi
    fi
  done < <(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-patches/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
}

# Get latest Custom
# $1 path
function getCustom() {
  echo "Getting Custom begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/custom.zip"
  rm -f "${CACHE_FILE}"
  TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-custom/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  export CUSTOMTAG="${TAG}"
  while read -r ID NAME; do
    if [ "${NAME}" = "custom-${TAG}.zip" ]; then
      curl -kL -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/arc-custom/releases/assets/${ID}" -o "${CACHE_FILE}"
      # Unzip Custom
      rm -rf "${DEST_PATH}"
      mkdir -p "${DEST_PATH}"
      if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
        rm -f "${CACHE_FILE}"
        echo "Getting Custom end - ${TAG}"
        break
      fi
    fi
  done < <(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-custom/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
}

# Get latest Theme
# $1 path
function getTheme() {
  echo "Getting Theme begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/theme.zip"
  rm -f "${CACHE_FILE}"
  TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-theme/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  export THEMETAG="${TAG}"
  while read -r ID NAME; do
    if [ "${NAME}" = "arc-theme-${TAG}.zip" ]; then
      curl -kL -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/arc-theme/releases/assets/${ID}" -o "${CACHE_FILE}"
      # Unzip Theme
      mkdir -p "${DEST_PATH}"
      if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
        rm -f "${CACHE_FILE}"
        echo "Getting Theme end - ${TAG}"
        break
      fi
    fi
  done < <(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/arc-theme/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
}

# Get latest Buildroot
# $1 type
# $2 path
function getBuildroot() {
  local TYPE="${1}"
  local DEST_PATH="${2}"
  local REPO=""
  local ZIP_NAME=""
  local TAG_VAR=""
  local REPO="arc-buildroot-${TYPE}"

  echo "Getting Buildroot-${TYPE} begin"
  TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/${REPO}/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  export BRTAG="${TAG}-${TYPE}"
  [ ! -d "${DEST_PATH}" ] && mkdir -p "${DEST_PATH}"
  rm -f "${DEST_PATH}/bzImage-arc"
  rm -f "${DEST_PATH}/initrd-arc"
  while read -r ID NAME; do
    if [ "${NAME}" = "buildroot-${TAG}.zip" ]; then
      curl -kL -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/${REPO}/releases/assets/${ID}" -o "${DEST_PATH}/br.zip"
      echo "Buildroot: ${TAG}-${TYPE}"
      unzip -o "${DEST_PATH}/br.zip" -d "${DEST_PATH}"
      mv -f "${DEST_PATH}/bzImage" "${DEST_PATH}/bzImage-arc"
      mv -f "${DEST_PATH}/rootfs.cpio.zst" "${DEST_PATH}/initrd-arc"
      [ -f "${DEST_PATH}/bzImage-arc" ] && [ -f "${DEST_PATH}/initrd-arc" ] && break
    fi
  done < <(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/AuxXxilium/${REPO}/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
}

# Get latest Offline
# $1 path
function getOffline() {
  echo "Getting Offline begin"
  local DEST_PATH="${1}"

  [ ! -d "${DEST_PATH}" ] && mkdir -p "${DEST_PATH}"
  rm -f "${DEST_PATH}/data.yml"
  if curl -skL "https://raw.githubusercontent.com/AuxXxilium/arc-dsm/refs/heads/main/data.yml" -o "${DEST_PATH}/data.yml"; then
    echo "Getting Offline end"
  else
    echo "Failed to get Offline"
    exit 1
  fi
}

# repack initrd
# $1 initrd file
# $2 plugin path
# $3 output file
function repackInitrd() {
  local INITRD_FILE="${1}"
  local PLUGIN_PATH="${2}"
  local OUTPUT_PATH="${3:-${INITRD_FILE}}"

  [ -z "${INITRD_FILE}" ] || [ ! -f "${INITRD_FILE}" ] && exit 1
  [ -z "${PLUGIN_PATH}" ] || [ ! -d "${PLUGIN_PATH}" ] && exit 1

  INITRD_FILE="$(realpath "${INITRD_FILE}")"
  PLUGIN_PATH="$(realpath "${PLUGIN_PATH}")"
  OUTPUT_PATH="$(realpath "${OUTPUT_PATH}")"

  local RDXZ_PATH="rdxz_tmp"
  mkdir -p "${RDXZ_PATH}"
  local INITRD_FORMAT=$(file -b --mime-type "${INITRD_FILE}")

  case "${INITRD_FORMAT}" in
  *'x-cpio'*) (cd "${RDXZ_PATH}" && sudo cpio -idm <"${INITRD_FILE}") >/dev/null 2>&1 ;;
  *'x-xz'*) (cd "${RDXZ_PATH}" && xz -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'x-lz4'*) (cd "${RDXZ_PATH}" && lz4 -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'x-lzma'*) (cd "${RDXZ_PATH}" && lzma -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'x-bzip2'*) (cd "${RDXZ_PATH}" && bzip2 -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'gzip'*) (cd "${RDXZ_PATH}" && gzip -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'zstd'*) (cd "${RDXZ_PATH}" && zstd -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *) ;;
  esac

  sudo cp -rf "${PLUGIN_PATH}/"* "${RDXZ_PATH}/"
  [ -f "${OUTPUT_PATH}" ] && rm -rf "${OUTPUT_PATH}"

  case "${INITRD_FORMAT}" in
  *'x-cpio'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'x-xz'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | xz -9 -C crc32 -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'x-lz4'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | lz4 -9 -l -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'x-lzma'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | lzma -9 -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'x-bzip2'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | bzip2 -9 -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'gzip'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | gzip -9 -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'zstd'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | zstd -19 -T0 -f -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *) ;;
  esac
  sudo rm -rf "${RDXZ_PATH}"
}

# resizeimg
# $1 input file
# $2 changsize MB eg: +50M -50M
# $3 output file
function resizeImg() {
  local INPUT_FILE="${1}"
  local CHANGE_SIZE="${2}"
  local OUTPUT_FILE="${3:-${INPUT_FILE}}"

  [ -z "${INPUT_FILE}" ] || [ ! -f "${INPUT_FILE}" ] && exit 1
  [ -z "${CHANGE_SIZE}" ] && exit 1

  INPUT_FILE="$(realpath "${INPUT_FILE}")"
  OUTPUT_FILE="$(realpath "${OUTPUT_FILE}")"

  local SIZE=$(($(du -sm "${INPUT_FILE}" 2>/dev/null | awk '{print $1}')$(echo "${CHANGE_SIZE}" | sed 's/M//g; s/b//g')))
  [ "${SIZE:-0}" -lt 0 ] && exit 1

  if [ ! "${INPUT_FILE}" = "${OUTPUT_FILE}" ]; then
    sudo cp -f "${INPUT_FILE}" "${OUTPUT_FILE}"
  fi

  sudo truncate -s ${SIZE}M "${OUTPUT_FILE}"
  echo -e "d\n\nn\n\n\n\n\nn\nw" | sudo fdisk "${OUTPUT_FILE}" >/dev/null 2>&1
  local LOOPX LOOPXPY
  LOOPX=$(sudo losetup -f)
  sudo losetup -P "${LOOPX}" "${OUTPUT_FILE}"
  LOOPXPY="$(find "${LOOPX}p"* -maxdepth 0 2>/dev/null | sort -n | tail -1)"
  sudo e2fsck -fp "${LOOPXPY:-${LOOPX}p3}"
  sudo resize2fs "${LOOPXPY:-${LOOPX}p3}"
  sudo losetup -d "${LOOPX}"
}

# createvmx
# $1 bootloader file
# $2 vmx name
function createvmx() {
  BLIMAGE=${1}
  VMNAME=${2}

  if ! type -p qemu-img >/dev/null 2>&1; then
    sudo apt install -y qemu-utils
  fi

  # Convert raw image to VMDK
  rm -rf "VMX_${VMNAME}"
  mkdir -p "VMX_${VMNAME}"
  qemu-img convert -O vmdk -o 'adapter_type=lsilogic,subformat=streamOptimized,compat6' "${BLIMAGE}" "VMX_${VMNAME}/${VMNAME}-disk1.vmdk"
  qemu-img create -f vmdk "VMX_${VMNAME}/${VMNAME}-disk2.vmdk" "32G"

  # Create VM configuration
  cat <<_EOF_ >"VMX_${VMNAME}/${VMNAME}.vmx"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "17"
displayName = "${VMNAME}"
annotation = "https://github.com/AuxXxilium/arc"
guestOS = "ubuntu-64"
firmware = "efi"
mks.enable3d = "TRUE"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
nvram = "${VMNAME}.nvram"
virtualHW.productCompatibility = "hosted"
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"
tools.syncTime = "FALSE"
sound.autoDetect = "TRUE"
sound.fileName = "-1"
sound.present = "TRUE"
numvcpus = "2"
cpuid.coresPerSocket = "1"
vcpu.hotadd = "TRUE"
memsize = "4096"
mem.hotadd = "TRUE"
usb.present = "TRUE"
ehci.present = "TRUE"
usb_xhci.present = "TRUE"
svga.graphicsMemoryKB = "8388608"
usb.vbluetooth.startConnected = "TRUE"
extendedConfigFile = "${VMNAME}.vmxf"
floppy0.present = "FALSE"
ethernet0.addressType = "generated"
ethernet0.virtualDev = "vmxnet3"
ethernet0.connectionType = "nat"
ethernet0.allowguestconnectioncontrol = "true"
ethernet0.present = "TRUE"
serial0.fileType = "file"
serial0.fileName = "serial0.log"
serial0.present = "TRUE"
sata0.present = "TRUE"
sata0:0.fileName = "${VMNAME}-disk1.vmdk"
sata0:0.present = "TRUE"
sata0:1.fileName = "${VMNAME}-disk2.vmdk"
sata0:1.present = "TRUE"
_EOF_
}

# convertvmx
# $1 bootloader file
# $2 vmx file
function convertvmx() {
  local BLIMAGE=${1}
  local VMXPATH=${2}

  BLIMAGE="$(realpath "${BLIMAGE}")"
  VMXPATH="$(realpath "${VMXPATH}")"
  local VMNAME="$(basename "${VMXPATH}" .vmx)"

  createvmx "${BLIMAGE}" "${VMNAME}"

  rm -rf "${VMXPATH}"
  mv -f "VMX_${VMNAME}" "${VMXPATH}"
}

# convertova
# $1 bootloader file
# $2 ova file
function convertova() {
  local BLIMAGE=${1}
  local OVAPATH=${2}

  BLIMAGE="$(realpath "${BLIMAGE}")"
  OVAPATH="$(realpath "${OVAPATH}")"
  local VMNAME="$(basename "${OVAPATH}" .ova)"

  createvmx "${BLIMAGE}" "${VMNAME}"

  # Download and install ovftool if it doesn't exist
  if [ ! -x ovftool/ovftool ]; then
    rm -rf ovftool ovftool.zip
    curl -skL https://github.com/rgl/ovftool-binaries/raw/main/archive/VMware-ovftool-4.6.0-21452615-lin.x86_64.zip -o ovftool.zip
    if [ $? -ne 0 ]; then
      echo "Failed to download ovftool"
      exit 1
    fi
    unzip ovftool.zip -d . >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "Failed to extract ovftool"
      exit 1
    fi
    chmod +x ovftool/ovftool
  fi

  rm -f "${OVAPATH}"
  ovftool/ovftool "VMX_${VMNAME}/${VMNAME}.vmx" "${OVAPATH}"
  rm -rf "VMX_${VMNAME}"
}

# createvmc
# $1 vhd file
# $2 vmc file
function createvmc() {
  local BLIMAGE=${1:-arc.vhd}
  local VMCPATH=${2:-arc.vmc}

  BLIMAGE="$(basename "${BLIMAGE}")"
  VMCPATH="$(realpath "${VMCPATH}")"

  cat <<_EOF_ >"${VMCPATH}"
<?xml version="1.0" encoding="UTF-8"?>
<preferences>
    <version type="string">2.0</version>
    <hardware>
        <memory>
          <ram_size type="integer">4096</ram_size>
        </memory>
        <pci_bus>
            <ide_adapter>
                <ide_controller id="0">
                    <location id="0">
                        <drive_type type="integer">1</drive_type>
                        <pathname>
                            <relative type="string">${BLIMAGE}</relative>
                        </pathname>
                    </location>
                </ide_controller>
            </ide_adapter>
        </pci_bus>
    </hardware>
</preferences>
_EOF_
}