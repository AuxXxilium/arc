#!/usr/bin/env bash
#
# Copyright (C) 2026 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

[ -n "${1}" ] && export TOKEN="${1}"

function githubApiGet() {
  local URL="${1}"
  local TMP_FILE=""

  TMP_FILE=$(mktemp)
  if [ -n "${TOKEN}" ]; then
    if ! curl -fsSL --retry 3 --retry-delay 1 --retry-all-errors -H "Accept: application/vnd.github+json" -H "Authorization: token ${TOKEN}" "${URL}" -o "${TMP_FILE}"; then
      rm -f "${TMP_FILE}"
      echo "GitHub API request failed: ${URL}" >&2
      return 1
    fi
  else
    if ! curl -fsSL --retry 3 --retry-delay 1 --retry-all-errors -H "Accept: application/vnd.github+json" "${URL}" -o "${TMP_FILE}"; then
      rm -f "${TMP_FILE}"
      echo "GitHub API request failed: ${URL}" >&2
      return 1
    fi
  fi

  if ! jq -e . >/dev/null 2>&1 <"${TMP_FILE}"; then
    rm -f "${TMP_FILE}"
    echo "GitHub API returned invalid JSON: ${URL}" >&2
    return 1
  fi

  cat "${TMP_FILE}"
  rm -f "${TMP_FILE}"
}

function githubLatestReleaseTag() {
  local REPO="${1}"
  local JSON=""
  local TAG=""

  JSON=$(githubApiGet "https://api.github.com/repos/AuxXxilium/${REPO}/releases") || return 1
  TAG=$(jq -er '.[].tag_name // empty' <<<"${JSON}" | sort -rV | head -1) || return 1

  if [ -z "${TAG}" ]; then
    echo "No releases found for ${REPO}" >&2
    return 1
  fi

  printf '%s\n' "${TAG}"
}

function githubReleaseAssets() {
  local REPO="${1}"
  local TAG="${2}"
  local JSON=""

  JSON=$(githubApiGet "https://api.github.com/repos/AuxXxilium/${REPO}/releases/tags/${TAG}") || return 1
  jq -er '.assets[]? | [.id, .name] | @tsv' <<<"${JSON}"
}

function githubDownloadReleaseAsset() {
  local REPO="${1}"
  local TAG="${2}"
  local ASSET_NAME="${3}"
  local OUTPUT_FILE="${4}"
  local ASSETS=""
  local FOUND=0

  ASSETS=$(githubReleaseAssets "${REPO}" "${TAG}") || return 1
  while IFS=$'\t' read -r ID NAME; do
    if [ "${NAME}" = "${ASSET_NAME}" ]; then
      FOUND=1
      if [ -n "${TOKEN}" ]; then
        curl -fkL --retry 3 --retry-delay 1 --retry-all-errors -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/${REPO}/releases/assets/${ID}" -o "${OUTPUT_FILE}" || return 1
      else
        curl -fkL --retry 3 --retry-delay 1 --retry-all-errors -H "Accept: application/octet-stream" "https://api.github.com/repos/AuxXxilium/${REPO}/releases/assets/${ID}" -o "${OUTPUT_FILE}" || return 1
      fi
      break
    fi
  done <<< "${ASSETS}"

  if [ "${FOUND}" -eq 0 ]; then
    echo "No asset named ${ASSET_NAME} found for ${REPO} ${TAG}" >&2
    return 1
  fi
}

# Get latest LKMs
# $1 path
function getLKMs() {
  echo "Getting LKMs begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/rp-lkms.zip"
  local TAG=""
  rm -f "${CACHE_FILE}"
  TAG=$(githubLatestReleaseTag "arc-lkm") || return 1
  export LKMTAG="${TAG}"
  githubDownloadReleaseAsset "arc-lkm" "${TAG}" "rp-lkms.zip" "${CACHE_FILE}" || return 1
  # Unzip LKMs
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
    rm -f "${CACHE_FILE}"
    echo "Getting LKMs end - ${TAG}"
  else
    return 1
  fi
}

# Get latest Addons
# $1 path
function getAddons() {
  echo "Getting Addons begin"
  local DEST_PATH="${1}"
  local CACHE_DIR="/tmp/addons"
  local CACHE_FILE="/tmp/addons.zip"
  local TAG=""
  rm -f "${CACHE_FILE}"
  TAG=$(githubLatestReleaseTag "arc-addons") || return 1
  export ADDONTAG="${TAG}"
  githubDownloadReleaseAsset "arc-addons" "${TAG}" "addons-${TAG}.zip" "${CACHE_FILE}" || return 1
  # Unzip Addons
  rm -rf "${CACHE_DIR}"
  mkdir -p "${CACHE_DIR}"
  mkdir -p "${DEST_PATH}"
  if unzip -o "${CACHE_FILE}" -d "${CACHE_DIR}"; then
    echo "Installing Addons to ${DEST_PATH}"
    [ -f /tmp/addons/VERSION ] && cp -f /tmp/addons/VERSION ${DEST_PATH}/
    for PKG in $(LC_ALL=C printf '%s\n' ${CACHE_DIR}/*.addon | sort -V); do
      ADDON=$(basename "${PKG}" .addon)
      mkdir -p "${DEST_PATH}/${ADDON}"
      echo "Extracting ${PKG} to ${DEST_PATH}/${ADDON}"
      tar -xaf "${PKG}" -C "${DEST_PATH}/${ADDON}"
    done
    rm -f "${CACHE_FILE}"
    echo "Getting Addons end - ${TAG}"
  else
    return 1
  fi
}

# Get latest Modules
# $1 path
function getModules() {
  echo "Getting Modules begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/modules.zip"
  local TAG=""
  rm -f "${CACHE_FILE}"
  TAG=$(githubLatestReleaseTag "arc-modules") || return 1
  export MODULETAG="${TAG}"
  githubDownloadReleaseAsset "arc-modules" "${TAG}" "modules-${TAG}.zip" "${CACHE_FILE}" || return 1
  # Unzip Modules
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
    rm -f "${CACHE_FILE}"
    echo "Getting Modules end - ${TAG}"
  else
    return 1
  fi
}

# Get latest Configs
# $1 path
function getConfigs() {
  echo "Getting Configs begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/configs.zip"
  local TAG=""
  rm -f "${CACHE_FILE}"
  TAG=$(githubLatestReleaseTag "arc-configs") || return 1
  export CONFIGTAG="${TAG}"
  githubDownloadReleaseAsset "arc-configs" "${TAG}" "configs-${TAG}.zip" "${CACHE_FILE}" || return 1
  # Unzip Configs
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
    rm -f "${CACHE_FILE}"
    echo "Getting Configs end - ${TAG}"
  else
    return 1
  fi
}

# Get latest Patches
# $1 path
function getPatches() {
  echo "Getting Patches begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/patches.zip"
  local TAG=""
  rm -f "${CACHE_FILE}"
  TAG=$(githubLatestReleaseTag "arc-patches") || return 1
  export PATCHTAG="${TAG}"
  githubDownloadReleaseAsset "arc-patches" "${TAG}" "patches-${TAG}.zip" "${CACHE_FILE}" || return 1
  # Unzip Patches
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
    rm -f "${CACHE_FILE}"
    echo "Getting Patches end - ${TAG}"
  else
    return 1
  fi
}

# Get latest Custom
# $1 path
function getCustom() {
  echo "Getting Custom begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/custom.zip"
  local TAG=""
  rm -f "${CACHE_FILE}"
  TAG=$(githubLatestReleaseTag "arc-custom") || return 1
  export CUSTOMTAG="${TAG}"
  githubDownloadReleaseAsset "arc-custom" "${TAG}" "custom-${TAG}.zip" "${CACHE_FILE}" || return 1
  # Unzip Custom
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
    rm -f "${CACHE_FILE}"
    echo "Getting Custom end - ${TAG}"
  else
    return 1
  fi
}

# Get latest Theme
# $1 path
function getTheme() {
  echo "Getting Theme begin"
  local DEST_PATH="${1}"
  local CACHE_FILE="/tmp/theme.zip"
  local TAG=""
  rm -f "${CACHE_FILE}"
  TAG=$(githubLatestReleaseTag "arc-theme") || return 1
  export THEMETAG="${TAG}"
  githubDownloadReleaseAsset "arc-theme" "${TAG}" "arc-theme-${TAG}.zip" "${CACHE_FILE}" || return 1
  # Unzip Theme
  mkdir -p "${DEST_PATH}"
  if unzip -o "${CACHE_FILE}" -d "${DEST_PATH}"; then
    rm -f "${CACHE_FILE}"
    echo "Getting Theme end - ${TAG}"
  else
    return 1
  fi
}

# Get latest Buildroot
# $1 type
# $2 path
function getBuildroot() {
  local TYPE="${1}"
  local DEST_PATH="br"
  local REPO=""
  local TAG=""
  [ "${TYPE}" = "apex" ] && REPO="arc-buildroot-essential"
  [ "${TYPE}" = "evo" ] && REPO="arc-buildroot-evo"

  echo "Getting Buildroot-${TYPE} begin"
  TAG=$(githubLatestReleaseTag "${REPO}") || return 1
  export "${TYPE}"="${TAG}"
  [ ! -d "${DEST_PATH}" ] && mkdir -p "${DEST_PATH}"
  githubDownloadReleaseAsset "${REPO}" "${TAG}" "buildroot-${TAG}.zip" "${DEST_PATH}/br-${TYPE}.zip" || return 1
  echo "Buildroot: ${TAG}"
  unzip -o "${DEST_PATH}/br-${TYPE}.zip" -d "${DEST_PATH}" || return 1
  mv -f "${DEST_PATH}/bzImage" "${DEST_PATH}/bzImage-${TYPE}"
  mv -f "${DEST_PATH}/rootfs.cpio.zst" "${DEST_PATH}/initrd-${TYPE}"
  rm -f "${DEST_PATH}/br-${TYPE}.zip"
  [ -f "${DEST_PATH}/bzImage-${TYPE}" ] && [ -f "${DEST_PATH}/initrd-${TYPE}" ] || return 1
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
  
  # Remove ttyd and dufs autostart scripts (services now start via web login)
  sudo rm -f "${RDXZ_PATH}/etc/init.d/S99ttyd"
  sudo rm -f "${RDXZ_PATH}/etc/init.d/S99dufs"
  
  # Update S90thttpd to run as root with CGI support for web authentication
  sudo tee "${RDXZ_PATH}/etc/init.d/S90thttpd" >/dev/null <<'EOF'
#!/bin/sh

DAEMON="thttpd"
PIDFILE="/var/run/$DAEMON.pid"
HTTPPORT=$(grep -i '^HTTP_PORT=' /etc/arc.conf 2>/dev/null | cut -d'=' -f2)
HTTPPORT=${HTTPPORT:-7080}

start() {
  printf 'Starting %s: ' "$DAEMON"
  # Run as root with CGI support for authentication
  /usr/sbin/thttpd -h 0.0.0.0 -p ${HTTPPORT} -d /var/www/data -u root -c '**.cgi' -i "$PIDFILE" 2>/dev/null
  status=$?
  if [ "$status" -eq 0 ]; then
    echo "OK"
  else
    echo "FAIL"
  fi
  return "$status"
}

stop() {
  printf 'Stopping %s: ' "$DAEMON"
  if [ -f "$PIDFILE" ]; then
    kill $(cat "$PIDFILE") 2>/dev/null
    rm -f "$PIDFILE"
    echo "OK"
  else
    echo "FAIL"
  fi
}

restart() {
  stop
  sleep 1
  start
}

case "$1" in
start | stop | restart)
  "$1"
  ;;
reload)
  restart
  ;;
*)
  echo "Usage: $0 {start|stop|restart|reload}"
  exit 1
  ;;
esac
EOF
  sudo chmod +x "${RDXZ_PATH}/etc/init.d/S90thttpd"
  
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
  qemu-img convert -O vmdk -o 'adapter_type=lsilogic,subformat=monolithicSparse,compat6' "${BLIMAGE}" "VMX_${VMNAME}/${VMNAME}-disk1.vmdk"
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
    curl -skL https://github.com/rgl/ovftool-binaries/raw/main/archive/VMware-ovftool-4.6.3-24031167-lin.x86_64.zip -o ovftool.zip
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