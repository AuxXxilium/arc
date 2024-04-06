#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/modules.sh
. ${ARC_PATH}/include/storage_automated.sh
. ${ARC_PATH}/include/network_automated.sh
. ${ARC_PATH}/arc-functions.sh

[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"

# Memory: Check Memory installed
RAMFREE=$(($(free -m | grep -i mem | awk '{print$2}') / 1024 + 1))
RAMTOTAL=$((${RAMFREE} * 1024))
[ -z "${RAMTOTAL}" ] || [ ${RAMTOTAL} -le 0 ] && RAMTOTAL=8192
RAMMAX=$((${RAMTOTAL} * 2))
RAMMIN=$((${RAMTOTAL} / 2))

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
DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "arc.kernelpanic" "${USER_CONFIG_FILE}")"
KVMSUPPORT="$(readConfigKey "arc.kvm" "${USER_CONFIG_FILE}")"
MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
ODP="$(readConfigKey "arc.odp" "${USER_CONFIG_FILE}")"
MODULESCOPY="$(readConfigKey "arc.modulescopy" "${USER_CONFIG_FILE}")"
HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "arc.kernel" "${USER_CONFIG_FILE}")"
USBMOUNT="$(readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}")"
ARCIPV6="$(readConfigKey "arc.ipv6" "${USER_CONFIG_FILE}")"
EMMCBOOT="$(readConfigKey "arc.emmcboot" "${USER_CONFIG_FILE}")"
OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"

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
# Make Model Config
function arcAutomated() {
  # read model config for dt and aes
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  DT="$(readModelKey "${MODEL}" "dt")"
  ARCCONF="$(readModelKey "${M}" "arc.serial")"
  [ -n "${ARCCONF}" ] && ARCPATCH="true" || ARCPATCH="false"
  if [ "${ARCPATCH}" = "true" ]; then
    SN="$(readModelKey "${MODEL}" "arc.serial")"
    writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
  elif [ "${ARCPATCH}" = "false" ]; then
    SN="$(generateSerial "${MODEL}")"
    writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
  fi
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
  fi
  writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [[ -f "${ORI_ZIMAGE_FILE}" || -f "${ORI_RDGZ_FILE}" || -f "${MOD_ZIMAGE_FILE}" || -f "${MOD_RDGZ_FILE}" ]]; then
    # Delete old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Config" \
    --infobox "Reconfiguring Synoinfo and Modules" 3 40
  # Reset synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read -r KEY VALUE; do
    writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
  done <<<$(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].synoinfo")
  # Reset modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read -r ID DESC; do
    writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
  done <<<$(getAllModules "${PLATFORM}" "${KVER}")
  # Check for ACPI Support
  if ! grep -q "^flags.*acpi.*" /proc/cpuinfo; then
    deleteConfigKey "addons.acpid" "${USER_CONFIG_FILE}"
  fi
  arcSettings
}

###############################################################################
# Arc Settings Section
function arcSettings() {
  # Get Network Config for Loader
  dialog --backtitle "$(backtitle)" --colors --title "Network Config" \
    --infobox "Network Config..." 3 30
  getnet
  # Select Portmap for Loader (nonDT)
  getmap
  if [[ "${DT}" = "false" && $(lspci -d ::106 | wc -l) -gt 0 ]]; then
    dialog --backtitle "$(backtitle)" --colors --title "Storage Map" \
      --infobox "Storage Map..." 3 30
    getmapSelection
  fi
  # Config is done
  writeConfigKey "arc.confdone" "true" "${USER_CONFIG_FILE}"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  premake
}

###############################################################################
# Building Loader Online
function premake() {
  # Read Model Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  DT="$(readModelKey "${MODEL}" "dt")"
  # Read Config for Arc Settings
  USBMOUNT="$(readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}")"
  KVMSUPPORT="$(readConfigKey "arc.kvm" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "arc.emmcboot" "${USER_CONFIG_FILE}")"
  # Memory: Set mem_max_mb to the amount of installed memory to bypass Limitation
  writeConfigKey "synoinfo.mem_max_mb" "${RAMMAX}" "${USER_CONFIG_FILE}"
  writeConfigKey "synoinfo.mem_min_mb" "${RAMMIN}" "${USER_CONFIG_FILE}"
  # KVM Support
  if [ "${KVMSUPPORT}" = "true" ]; then
    writeConfigKey "modules.kvm_intel" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modules.kvm_amd" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modules.kvm" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modules.irgbypass" "" "${USER_CONFIG_FILE}"
  else
    deleteConfigKey "modules.kvm_intel" "${USER_CONFIG_FILE}"
    deleteConfigKey "modules.kvm_amd" "${USER_CONFIG_FILE}"
    deleteConfigKey "modules.kvm" "${USER_CONFIG_FILE}"
    deleteConfigKey "modules.irgbypass" "${USER_CONFIG_FILE}"
  fi
  # eMMC Boot Support
  if [ "${EMMCBOOT}" = "true" ]; then
    writeConfigKey "modules.mmc_block" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modules.mmc_core" "" "${USER_CONFIG_FILE}"
  else
    deleteConfigKey "modules.mmc_block" "${USER_CONFIG_FILE}"
    deleteConfigKey "modules.mmc_core" "${USER_CONFIG_FILE}"
  fi
  # Fixes for SA6400
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
    MODULESCOPY="false"
    writeConfigKey "arc.modulescopy" "${MODULESCOPY}" "${USER_CONFIG_FILE}"
  fi
  # Build Loader
  make
}

###############################################################################
# Building Loader Online
function make() {
  # Read Model Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  DT="$(readModelKey "${MODEL}" "dt")"
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
  fi
  # Cleanup
  if [ -d "${UNTAR_PAT_PATH}" ]; then
    rm -rf "${UNTAR_PAT_PATH}"
  fi
  mkdir -p "${UNTAR_PAT_PATH}"
  # Check if all addon exists
  while IFS=': ' read -r ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      deleteConfigKey "addons.${ADDON}" "${USER_CONFIG_FILE}"
      continue
    fi
  done <<<$(readConfigMap "addons" "${USER_CONFIG_FILE}")
  dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
    --infobox "Get PAT Data from Syno..." 3 30
  # Get PAT Data from Syno
  idx=0
  while [ ${idx} -le 3 ]; do # Loop 3 times, if successful, break
    PAT_URL="$(curl -m 5 -skL "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}" | jq -r '.info.system.detail[0].items[0].files[0].url')"
    PAT_HASH="$(curl -m 5 -skL "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}" | jq -r '.info.system.detail[0].items[0].files[0].checksum')"
    PAT_URL=${PAT_URL%%\?*}
    if [[ -n "${PAT_URL}" && -n "${PAT_HASH}" ]]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [[ -z "${PAT_URL}" || -z "${PAT_HASH}" ]]; then
    dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
      --infobox "Syno Connection failed,\ntry to get from Github..." 4 30
    idx=0
    while [ ${idx} -le 3 ]; do # Loop 3 times, if successful, break
      PAT_URL="$(curl -m 5 -skL "https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/dsm/${MODEL/+/%2B}/${PRODUCTVER%%.*}.${PRODUCTVER##*.}/pat_url")"
      PAT_HASH="$(curl -m 5 -skL "https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/dsm/${MODEL/+/%2B}/${PRODUCTVER%%.*}.${PRODUCTVER##*.}/pat_hash")"
      PAT_URL=${PAT_URL%%\?*}
      if [[ -n "${PAT_URL}" && -n "${PAT_HASH}" ]]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  fi
  if [[ -z "${PAT_URL}" || -z "${PAT_HASH}" ]]; then
    dialog --backtitle "$(backtitle)" --title "DSM Data" --aspect 18 \
      --infobox "No DSM Data found!\nExit." 0 0
    sleep 5
    return 1
  else
    dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
      --infobox "Get PAT Data sucessfull..." 3 30
  fi
  if [[ "${PAT_HASH}" != "${PAT_HASH_CONF}" || ! -f "${ORI_ZIMAGE_FILE}" || ! -f "${ORI_RDGZ_FILE}" ]]; then
    writeConfigKey "arc.paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.pathash" "${PAT_HASH}" "${USER_CONFIG_FILE}"
    # Check for existing Files
    DSM_FILE="${UNTAR_PAT_PATH}/${PAT_HASH}.tar"
    # Get new Files
    DSM_URL="https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/files/${MODEL/+/%2B}/${PRODUCTVER}/${PAT_HASH}.tar"
    STATUS=$(curl --insecure -s -w "%{http_code}" -L "${DSM_URL}" -o "${DSM_FILE}")
    if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
      dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
      --infobox "No DSM Image found!\nTry Syno Link." 0 0
      # Grep PAT_URL
      PAT_FILE="${TMP_PATH}/${PAT_HASH}.pat"
      STATUS=$(curl -k -w "%{http_code}" -L "${PAT_URL}" -o "${PAT_FILE}" --progress-bar)
      if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
        dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
          --infobox "No DSM Image found!\ Exit." 0 0
        sleep 5
        return 1
      fi
      # Extract Files
      header=$(od -bcN2 ${PAT_FILE} | head -1 | awk '{print $3}')
      case ${header} in
          105)
          isencrypted="no"
          ;;
          213)
          isencrypted="no"
          ;;
          255)
          isencrypted="yes"
          ;;
          *)
          echo -e "Could not determine if pat file is encrypted or not, maybe corrupted, try again!"
          ;;
      esac
      if [ "${isencrypted}" = "yes" ]; then
        # Uses the extractor to untar PAT file
        LD_LIBRARY_PATH="${EXTRACTOR_PATH}" "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" "${PAT_FILE}" "${UNTAR_PAT_PATH}"
      else
        # Untar PAT file
        tar -xf "${PAT_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
      fi
      # Cleanup PAT Download
      rm -f "${PAT_FILE}"
    elif [ -f "${DSM_FILE}" ]; then
      tar -xf "${DSM_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
    elif [ ! -f "${UNTAR_PAT_PATH}/zImage" ]; then
      dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
        --infobox "ERROR: No DSM Image found!" 0 0
      sleep 5
      return 1
    fi
    dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
      --infobox "Image unpack sucessfull..." 3 30
    # Copy DSM Files to Locations if DSM Files not found
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART1_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART1_PATH}"
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART2_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART2_PATH}"
    cp -f "${UNTAR_PAT_PATH}/zImage" "${ORI_ZIMAGE_FILE}"
    cp -f "${UNTAR_PAT_PATH}/rd.gz" "${ORI_RDGZ_FILE}"
    rm -rf "${UNTAR_PAT_PATH}"
  fi
  # Reset Bootcount if User rebuild DSM
  if [[ -z "${BOOTCOUNT}" || ${BOOTCOUNT} -gt 0 ]]; then
    writeConfigKey "arc.bootcount" "0" "${USER_CONFIG_FILE}"
  fi
  (
    livepatch
    sleep 3
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Build Loader" \
    --progressbox "Doing the Magic..." 20 70
  if [[ -f "${ORI_ZIMAGE_FILE}" && -f "${ORI_RDGZ_FILE}" && -f "${MOD_ZIMAGE_FILE}" && -f "${MOD_RDGZ_FILE}" ]]; then
    # Build is done
    writeConfigKey "arc.builddone" "true" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    boot && exit 0
  fi
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  [ "${BUILDDONE}" = "false" ] && dialog --backtitle "$(backtitle)" --title "Alert" \
    --yesno "Config changed, you need to rebuild the Loader?" 0 0
  if [ $? -eq 0 ]; then
    premake
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Booting DSM...\nPlease stay patient!" 4 25
  sleep 2
  exec reboot
}

###############################################################################
###############################################################################
# Main loop
arcAutomated

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