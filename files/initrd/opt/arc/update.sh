#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/modules.sh
. ${ARC_PATH}/include/network.sh
. ${ARC_PATH}/include/update.sh

[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"

# Check for Hypervisor
if grep -q "^flags.*hypervisor.*" /proc/cpuinfo; then
  MACHINE="$(lscpu | grep Hypervisor | awk '{print $3}')"
else
  MACHINE="NATIVE"
fi

# Get Loader Disk Bus
BUS=$(getBus "${LOADER_DISK}")

# Offline Mode check
ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
CUSTOM="$(readConfigKey "arc.custom" "${USER_CONFIG_FILE}")"
NEWTAG=$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
if [ -n "${NEWTAG}" ]; then
  [ -z "${ARCNIC}" ] && ARCNIC="auto"
elif [ -z "${NEWTAG}" ]; then
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) # real network cards list
  for ETH in ${ETHX}; do
    # Update Check
    NEWTAG=$(curl --interface ${ETH} -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
    if [ -n "${NEWTAG}" ]; then
      [ -z "${ARCNIC}" ] && ARCNIC="${ETH}"
      break
    fi
  done
  if [ -n "${ARCNIC}" ]; then
    writeConfigKey "arc.offline" "false" "${USER_CONFIG_FILE}"
  elif [ -z "${ARCNIC}" ] && [ "${CUSTOM}" == "false" ]; then
    writeConfigKey "arc.offline" "true" "${USER_CONFIG_FILE}"
    cp -f "${PART3_PATH}/configs/offline.json" "${ARC_PATH}/include/offline.json"
    [ -z "${ARCNIC}" ] && ARCNIC="auto"
    dialog --backtitle "$(backtitle)" --title "Online Check" \
        --msgbox "Could not connect to Github.\nSwitch to Offline Mode!" 0 0
  elif [ -z "${ARCNIC}" ] && [ "${CUSTOM}" == "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Online Check" \
      --infobox "Could not connect to Github.\nReboot to try again!" 0 0
    sleep 10
    exec reboot
  fi
fi
writeConfigKey "arc.nic" "${ARCNIC}" "${USER_CONFIG_FILE}"
ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"

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

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  if [ -z "${MODEL}" ]; then
    MODEL="(Model)"
  fi
  if [ -z "${PRODUCTVER}" ]; then
    PRODUCTVER="(Version)"
  fi
  if [ -z "${IPCON}" ]; then
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
    --infobox "Update successful!" 0 0
  writeConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ ! -f "${PART3_PATH}/automated" ]; then
    echo "${ARC_VERSION}-${MODEL}-${PRODUCTVER}-custom" >"${PART3_PATH}/automated"
  fi
  boot
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
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
  if [ "${CUSTOM}" == "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
      --infobox "Offline Mode enabled.\nCan't Update Loader!" 0 0
    sleep 5
    exec reboot
  else
    dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
      --msgbox "Offline Mode enabled.\nCan't Update Loader!" 0 0
    exit 1
  fi
fi