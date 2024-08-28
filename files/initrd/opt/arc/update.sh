#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/modules.sh
. ${ARC_PATH}/include/network.sh
. ${ARC_PATH}/include/update.sh

# Check for System
systemCheck

# Offline Mode check
offlineCheck "false"
ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
AUTOMATED="$(readConfigKey "automated" "${USER_CONFIG_FILE}")"
ARCKEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"

# Get DSM Data from Config
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
if [ -n "${MODEL}" ]; then
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}" 2>/dev/null)"
fi

# Get Config Status
CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"

# Get Keymap and Timezone Config
ntpCheck

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${ARC_TITLE}$([ -n "${NEWTAG}" ] && [ "${NEWTAG}" != "${ARC_VERSION}" ] && echo " > ${NEWTAG}") | "
  BACKTITLE+="${MODEL:-(Model)} | "
  BACKTITLE+="${PRODUCTVER:-(Version)} | "
  BACKTITLE+="${IPCON:-(IP)}${OFF} | "
  BACKTITLE+="Patch: ${ARCPATCH} | "
  BACKTITLE+="Config: ${CONFDONE} | "
  BACKTITLE+="Build: ${BUILDDONE} | "
  BACKTITLE+="${MACHINE}(${BUS}) | "
  BACKTITLE+="KB: ${KEYMAP}"
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
  updateCustom
  # Ask for Boot
  dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
    --infobox "Update successful!" 0 0
  if [ "${CONFDONE}" == "true" ] && [ ! -f "${PART3_PATH}/automated" ]; then
    echo "${ARC_VERSION}-${MODEL}-${PRODUCTVER}-custom" >"${PART3_PATH}/automated"
  fi
  boot
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" == "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Rebooting to automated Build Mode...\nPlease stay patient!" 4 30
    sleep 3
    rebootTo automated
  else
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Rebooting to Config Mode...\nPlease stay patient!" 4 30
    sleep 3
    rebootTo config
  fi
}

###############################################################################
###############################################################################
# Main loop
if [ "${OFFLINE}" == "false" ]; then
  arcUpdate
else
  dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
    --infobox "Offline Mode enabled.\nCan't Update Loader!" 0 0
  sleep 5
  . ${ARC_PATH}/boot.sh
fi