#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/modules.sh

[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"

# Check for Hypervisor
if grep -q "^flags.*hypervisor.*" /proc/cpuinfo; then
  # Check for Hypervisor
  MACHINE="$(lscpu | grep Hypervisor | awk '{print $3}')"
else
  MACHINE="NATIVE"
fi

# Get Loader Disk Bus
BUS=$(getBus "${LOADER_DISK}")

# Get DSM Data from Config
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
if [ -n "${MODEL}" ]; then
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  DT="$(readModelKey "${MODEL}" "dt")"
fi

# Get Arc Data from Config
CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
CUSTOM="${readConfigKey "arc.custom" "${USER_CONFIG_FILE}"}"

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  if [ ! -n "${MODEL}" ]; then
    MODEL="(Model)"
  fi
  if [ ! -n "${PRODUCTVER}" ]; then
    PRODUCTVER="(Version)"
  fi
  if [ ! -n "${IPCON}" ]; then
    IPCON="(IP)"
  fi
  BACKTITLE="${ARC_TITLE} | "
  BACKTITLE+="${MODEL} | "
  BACKTITLE+="${PRODUCTVER} | "
  BACKTITLE+="${IPCON} | "
  BACKTITLE+="Patch: ${ARCPATCH} | "
  BACKTITLE+="Config: ${CONFDONE} | "
  BACKTITLE+="Build: ${BUILDDONE} | "
  BACKTITLE+="${MACHINE}(${BUS})"
  echo "${BACKTITLE}"
}

###############################################################################
# Auto Update Loader
function arcUpdate() {
  # Update Loader
  dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
    --infobox "Checking latest version..." 0 0
  ACTUALVERSION="${ARC_VERSION}"
  TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
  if [[ $? -ne 0 || -z "${TAG}" ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
      --infobox "Error checking new Version!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
    --infobox "Downloading ${TAG}" 0 0
  # Download update file
  STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc/releases/download/${TAG}/update.zip" -o "${TMP_PATH}/update.zip")
  if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
      --infobox "Error downloading Updatefile!" 0 0
    return 1
  fi
  unzip -oq "${TMP_PATH}/update.zip" -d "${TMP_PATH}"
  rm -f "${TMP_PATH}/update.zip"
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
      --infobox "Error extracting Updatefile!" 0 0
    return 1
  fi
  # Process complete update
  cp -f "${TMP_PATH}/grub.cfg" "${GRUB_PATH}/grub.cfg"
  cp -f "${TMP_PATH}/bzImage-arc" "${ARC_BZIMAGE_FILE}"
  cp -f "${TMP_PATH}/initrd-arc" "${ARC_RAMDISK_FILE}"
  rm -f "${TMP_PATH}/update.zip"
  # Update Addons
  TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
  if [[ $? -ne 0 || -z "${TAG}" ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
      --infobox "Error checking new Version!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
    --infobox "Downloading ${TAG}" 0 0
  STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o "${TMP_PATH}/addons.zip")
  if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
      --infobox "Error downloading Updatefile!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
    --infobox "Extracting" 0 0
  rm -rf "${ADDONS_PATH}"
  mkdir -p "${ADDONS_PATH}"
  unzip -oq "${TMP_PATH}/addons.zip" -d "${ADDONS_PATH}" >/dev/null 2>&1
  dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
    --infobox "Installing new Addons" 0 0
  for PKG in $(ls ${ADDONS_PATH}/*.addon); do
    ADDON=$(basename ${PKG} | sed 's|.addon||')
    rm -rf "${ADDONS_PATH}/${ADDON:?}"
    mkdir -p "${ADDONS_PATH}/${ADDON}"
    tar -xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
    rm -f "${ADDONS_PATH}/${ADDON}.addon"
  done
  rm -f "${TMP_PATH}/addons.zip"
  # Update Patches
  TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc-patches/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
  if [[ $? -ne 0 || -z "${TAG}" ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
      --infobox "Error checking new Version!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
    --infobox "Downloading ${TAG}" 0 0
  STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches.zip" -o "${TMP_PATH}/patches.zip")
  if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
      --infobox "Error downloading Updatefile!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
    --infobox "Extracting" 0 0
  rm -rf "${PATCH_PATH}"
  mkdir -p "${PATCH_PATH}"
  unzip -oq "${TMP_PATH}/patches.zip" -d "${PATCH_PATH}" >/dev/null 2>&1
  rm -f "${TMP_PATH}/patches.zip"
  # Update Modules
  TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
  if [[ $? -ne 0 || -z "${TAG}" ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
      --infobox "Error checking new Version!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
    --infobox "Downloading ${TAG}" 0 0
  STATUS=$(curl -k -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip" -o "${TMP_PATH}/modules.zip")
  if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
      --infobox "Error downloading Updatefile!" 0 0
    return 1
  fi
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  if [[ -n "${MODEL}" && -n "${PRODUCTVER}" ]]; then
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
    if [ "${PLATFORM}" = "epyc7002" ]; then
      KVER="${PRODUCTVER}-${KVER}"
    fi
  fi
  rm -rf "${MODULES_PATH}"
  mkdir -p "${MODULES_PATH}"
  unzip -oq "${TMP_PATH}/modules.zip" -d "${MODULES_PATH}" >/dev/null 2>&1
  # Rebuild modules if model/build is selected
  if [[ -n "${PLATFORM}" && -n "${KVER}" ]]; then
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    while read -r ID DESC; do
      writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
    done <<<$(getAllModules "${PLATFORM}" "${KVER}")
  fi
  rm -f "${TMP_PATH}/modules.zip"
  # Update Configs
  TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc-configs/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
  if [[ $? -ne 0 || -z "${TAG}" ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
      --infobox "Error checking new Version!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
    --infobox "Downloading ${TAG}" 0 0
  STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs.zip" -o "${TMP_PATH}/configs.zip")
  if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
    dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
      --infobox "Error downloading Updatefile!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
    --infobox "Extracting" 0 0
  rm -rf "${MODEL_CONFIG_PATH}"
  mkdir -p "${MODEL_CONFIG_PATH}"
  unzip -oq "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}" >/dev/null 2>&1
  rm -f "${TMP_PATH}/configs.zip"
  # Update LKMs
  TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
  if [[ $? -ne 0 || -z "${TAG}" ]]; then
    dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
      --infobox "Error checking new Version!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
    --infobox "Downloading ${TAG}" 0 0
  STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/redpill-lkm/releases/download/${TAG}/rp-lkms-${TAG}.zip" -o "${TMP_PATH}/rp-lkms.zip")
  if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
    dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
      --infobox "Error downloading Updatefile" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
    --infobox "Extracting" 0 0
  rm -rf "${LKM_PATH}"
  mkdir -p "${LKM_PATH}"
  unzip -oq "${TMP_PATH}/rp-lkms.zip" -d "${LKM_PATH}" >/dev/null 2>&1
  rm -f "${TMP_PATH}/rp-lkms.zip"
  # Ask for Boot
  dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
    --infobox "Update successfull!" 0 0
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  [ ! -f "${PART3_PATH}/automated" ] && echo "${ARC_VERSION}-${MODEL}-{PRODUCTVER}-custom" >"${PART3_PATH}/automated"
  boot
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Rebooting automated Build Mode...\nPlease stay patient!" 4 25
  sleep 2
  rebootTo automated
}

###############################################################################
###############################################################################
# Main loop
if [ "${OFFLINE}" = "false" ]; then
  arcUpdate
else
  dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
    --infobox "Offline Mode enabled.\nCan't Update Loader!" 0 0
  sleep 5
  exec reboot
fi