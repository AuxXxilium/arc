#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh

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
  [ -f "${USER_CONFIG_FILE}" ] && cp -f "${USER_CONFIG_FILE}" "${TMP_PATH}/user-config.yml"
  [ -f "/mnt/p3/automated" ] && cp -f "/mnt/p3/automated" "${TMP_PATH}/automated"
  dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
    --infobox "Checking latest version..." 0 0
  ACTUALVERSION="${ARC_VERSION}"
  TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
  if [[ $? -ne 0 || -z "${TAG}" ]]; then
    dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
      --infobox "Error checking new Version!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
    --infobox "Downloading ${TAG}" 0 0
  # Download update file
  STATUS=$(curl --insecure -w "%{http_code}" -L "https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}.img.zip" -o "${TMP_PATH}/arc-${TAG}.img.zip")
  if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
    dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
      --infobox "Error downloading Updatefile!" 0 0
    return 1
  fi
  unzip -oq "${TMP_PATH}/arc-${TAG}.img.zip" -d "${TMP_PATH}"
  rm -f "${TMP_PATH}/arc-${TAG}.img.zip"
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
      --infobox "Error extracting Updatefile!" 0 0
    return 1
  fi
  # Process complete update
  umount "${PART1_PATH}" "${PART2_PATH}" "${PART3_PATH}"
  dd if="${TMP_PATH}/arc.img" of=$(blkid | grep 'LABEL="ARC3"' | cut -d3 -f1) bs=1M conv=fsync
  # Ask for Boot
  rm -f "${TMP_PATH}/arc.img"
  dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
    --infobox "Upgrade successfull!" 0 0
  mount ${LOADER_DISK_PART1} /mnt/p1 2>/dev/null || (
    break
  )
  mount ${LOADER_DISK_PART2} /mnt/p2 2>/dev/null || (
    break
  )
  mount ${LOADER_DISK_PART3} /mnt/p3 2>/dev/null || (
    break
  )
  [ -f "${TMP_PATH}/${USER_CONFIG_FILE}" ] && cp -f "${TMP_PATH}/user-config.yml" "${USER_CONFIG_FILE}"
  [ -f "${TMP_PATH}/automated" ] && cp -f "${TMP_PATH}/automated" "/mnt/p3/automated"
  boot
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  if [ "${CUSTOM}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Rebooting Automated Mode...\nPlease stay patient!" 4 25
    sleep 2
    rebootTo automated
  else
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Rebooting Config Mode...\nPlease stay patient!" 4 25
    sleep 2
    rebootTo config
  fi
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
fi

# Inform user
echo -e "Call \033[1;34marc.sh\033[0m to configure Loader"
echo
echo -e "SSH Access:"
echo -e "IP: \033[1;34m${IPCON}\033[0m"
echo -e "User: \033[1;34mroot\033[0m"
echo -e "Password: \033[1;34marc\033[0m"
echo
echo -e "Web Terminal:"
echo -e "Address: \033[1;34mhttp://${IPCON}:7681\033[0m"