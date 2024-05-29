#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/modules.sh
. ${ARC_PATH}/include/network.sh
. ${ARC_PATH}/include/update.sh

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
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
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
  # Automatic Update
  updateLoader
  updateAddons
  updateConfigs
  updateLKMs
  updateModules
  updatePatches
  # Ask for Boot
  dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
    --infobox "Update successfull!" 0 0
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${CUSTOM}" = "true" ] && [ ! -f "${PART3_PATH}/automated" ]; then
    echo "${ARC_VERSION}-${MODEL}-{PRODUCTVER}-custom" >"${PART3_PATH}/automated"
  fi
  boot
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  if [ "${CUSTOM}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Rebooting to automated Build Mode...\nPlease stay patient!" 4 30
  else
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Rebooting to Config Mode...\nPlease stay patient!" 4 30
  fi
  rm -f "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" 2>/dev/null
  sleep 3
  exec reboot
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