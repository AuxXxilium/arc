#!/usr/bin/env bash

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/modules.sh
. ${ARC_PATH}/include/storage.sh
. ${ARC_PATH}/include/network.sh

[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"

# Memory: Check Memory installed
RAMTOTAL=0
while read -r LINE; do
  RAMSIZE=${LINE}
  RAMTOTAL=$((${RAMTOTAL} + ${RAMSIZE}))
done < <(dmidecode -t memory | grep -i "Size" | cut -d" " -f2 | grep -i "[1-9]")
RAMTOTAL=$((${RAMTOTAL} * 1024))
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

# Set Warning to 0
WARNON=0

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

if [ "${OFFLINE}" = "false" ]; then
  # Update Check
  NEWTAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
  if [ -z "${NEWTAG}" ]; then
    NEWTAG="${ARC_VERSION}"
  fi
fi

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  if [ ! "${NEWTAG}" = "${ARC_VERSION}" ] && [ "${OFFLINE}" = "false" ]; then
    ARC_TITLE="${ARC_TITLE} -> ${NEWTAG}"
  fi
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
  BACKTITLE+="${MACHINE}(${BUS^^})"
  echo "${BACKTITLE}"
}

###############################################################################
# Make Model Config
function arcMenu() {
  # Loop menu
  RESTRICT=1
  FLGBETA=0
  dialog --backtitle "$(backtitle)" --title "Model" --aspect 18 \
    --infobox "Reading Models" 3 20
    echo -n "" >"${TMP_PATH}/modellist"
    while read -r M; do
      Y="$(readModelKey "${M}" "disks")"
      echo "${M} ${Y}" >>"${TMP_PATH}/modellist"
    done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sed 's/.*\///; s/\.yml//')

    while true; do
      echo -n "" >"${TMP_PATH}/menu"
      FLGNEX=0
      while read -r M Y; do
        PLATFORM=$(readModelKey "${M}" "platform")
        DT="$(readModelKey "${M}" "dt")"
        BETA="$(readModelKey "${M}" "beta")"
        [[ "${BETA}" = "true" && ${FLGBETA} -eq 0 ]] && continue
        DISKS="$(readModelKey "${M}" "disks")-Bay"
        ARCCONF="$(readModelKey "${M}" "arc.serial")"
        if [ -n "${ARCCONF}" ]; then
          ARCAV="Arc"
        else
          ARCAV="NonArc"
        fi
        if [[ "${PLATFORM}" = "r1000" || "${PLATFORM}" = "v1000" || "${PLATFORM}" = "epyc7002" ]]; then
          CPU="AMD"
        else
          CPU="Intel"
        fi
        # Check id model is compatible with CPU
        COMPATIBLE=1
        if [ ${RESTRICT} -eq 1 ]; then
          for F in "$(readModelArray "${M}" "flags")"; do
            if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
              COMPATIBLE=0
              FLGNEX=1
              break
            fi
          done
          for F in "$(readModelArray "${M}" "dt")"; do
            if [ "${DT}" = "true" ] && [[ ${SASCONTROLLER} -gt 0 || ${SCSICONTROLLER} -gt 0 ]]; then
              COMPATIBLE=0
              FLGNEX=1
              break
            fi
          done
        fi
        [ "${DT}" = "true" ] && DTO="DT" || DTO=""
        [ "${BETA}" = "true" ] && BETA="Beta" || BETA=""
        [ ${COMPATIBLE} -eq 1 ] && echo "${M} \"$(printf "\Zb%-7s\Zn \Zb%-6s\Zn \Zb%-13s\Zn \Zb%-3s\Zn \Zb%-7s\Zn \Zb%-4s\Zn" "${DISKS}" "${CPU}" "${PLATFORM}" "${DTO}" "${ARCAV}" "${BETA}")\" ">>"${TMP_PATH}/menu"
      done < <(cat "${TMP_PATH}/modellist" | sort -n -k 2)
    [ ${FLGBETA} -eq 0 ] && echo "b \"\Z1Show beta Models\Zn\"" >>"${TMP_PATH}/menu"
    [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1Show incompatible Models \Zn\"" >>"${TMP_PATH}/menu"
    dialog --backtitle "$(backtitle)" --colors --menu "Choose Model for Loader" 0 62 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ "${resp}" = "b" ]; then
      FLGBETA=1
      continue
    fi
    if [ "${resp}" = "f" ]; then
      RESTRICT=0
      continue
    fi
    break
  done
  # read model config for dt and aes
  if [ "${MODEL}" != "${resp}" ]; then
    MODEL="${resp}"
    DT="$(readModelKey "${MODEL}" "dt")"
    # Check for AES
    if ! grep -q "^flags.*aes.*" /proc/cpuinfo; then
      WARNON=4
    fi
    PRODUCTVER=""
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    writeConfigKey "productver" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.sn" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.kernel" "official" "${USER_CONFIG_FILE}"
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    if [ "${DT}" = "true" ]; then
      deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    fi
    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    if [[ -f "${ORI_ZIMAGE_FILE}" || -f "${ORI_RDGZ_FILE}" || -f "${MOD_ZIMAGE_FILE}" || -f "${MOD_RDGZ_FILE}" ]]; then
      # Delete old files
      rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
    fi
  fi
  arcbuild
}

###############################################################################
# Shows menu to user type one or generate randomly
function arcbuild() {
  # read model values for arcbuild
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  if [ "${ARCRECOVERY}" != "true" ]; then
    # Select Build for DSM
    ITEMS="$(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml" | sort -r)"
    if [ -z "${1}" ]; then
      dialog --clear --no-items --nocancel --backtitle "$(backtitle)" \
        --menu "Choose a Version" 0 0 0 ${ITEMS} 2>"${TMP_PATH}/resp"
      resp="$(<"${TMP_PATH}/resp")"
      [ -z "${resp}" ] && return 1
    else
      if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
      resp="${1}"
    fi
    if [ "${PRODUCTVER}" != "${resp}" ]; then
      PRODUCTVER="${resp}"
      writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
      if [[ -f "${ORI_ZIMAGE_FILE}" || -f "${ORI_RDGZ_FILE}" || -f "${MOD_ZIMAGE_FILE}" || -f "${MOD_RDGZ_FILE}" ]]; then
        # Delete old files
        rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
      fi
    fi
  fi
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Config" \
    --infobox "Reconfiguring Synoinfo, Addons and Modules" 3 46
  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read -r KEY VALUE; do
    writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
  done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].synoinfo")
  # Rebuild modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read -r ID DESC; do
    writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
  done < <(getAllModules "${PLATFORM}" "${KVER}")
  if [ "${ONLYVERSION}" != "true" ]; then
    arcsettings
  else
    # Build isn't done
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    # Ask for Build
    dialog --clear --backtitle "$(backtitle)" \
      --menu "Build now?" 0 0 0 \
      1 "Yes - Build Arc Loader now" \
      2 "No - I want to make changes" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      make
    elif [ ${resp} -eq 2 ]; then
      dialog --clear --no-items --backtitle "$(backtitle)"
      return 1
    fi
  fi
}

###############################################################################
# Make Arc Settings
function arcsettings() {
  # Read Model Values
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  DT="$(readModelKey "${MODEL}" "dt")"
  ARCCONF="$(readConfigKey "arc.serial" "${MODEL_CONFIG_PATH}/${MODEL}.yml")"
  if [[ "${ARCRECOVERY}" != "true" && -n "${ARCCONF}" ]]; then
    dialog --clear --backtitle "$(backtitle)" \
      --nocancel --title "Arc Patch"\
      --menu "Do you want to use Syno Services?" 7 50 0 \
      1 "Yes - Install with Arc Patch" \
      2 "No - Install with random Serial/Mac" \
      3 "No - Install with my Serial/Mac" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      # Read Arc Patch from File
      SN="$(readModelKey "${MODEL}" "arc.serial")"
      writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 2 ]; then
      # Generate random Serial
      SN="$(generateSerial "${MODEL}")"
      writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 3 ]; then
      while true; do
        dialog --backtitle "$(backtitle)" --colors --title "Serial" \
          --inputbox "Please enter a valid Serial " 0 0 "" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break 2
        SN="$(cat ${TMP_PATH}/resp)"
        if [ -z "${SN}" ]; then
          return
        elif [ $(validateSerial ${MODEL} ${SN}) -eq 1 ]; then
          break
        fi
        # At present, the SN rules are not complete, and many SNs are not truly invalid, so not provide tips now.
        break
        dialog --backtitle "$(backtitle)" --colors --title "Serial" \
          --yesno "Invalid Serial, continue?" 0 0
        [ $? -eq 0 ] && break
      done
      writeConfigKey "arc.patch" "user" "${USER_CONFIG_FILE}"
    fi
    writeConfigKey "arc.sn" "${SN}" "${USER_CONFIG_FILE}"
  elif [[ "${ARCRECOVERY}" != "true" && -z "${ARCCONF}" ]]; then
    dialog --clear --backtitle "$(backtitle)" \
      --nocancel --title "Non Arc Patch Model" \
      --menu "Please select an Option?" 7 50 0 \
      1 "Install with random Serial/Mac" \
      2 "Install with my Serial/Mac" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      # Generate random Serial
      SN="$(generateSerial "${MODEL}")"
      writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 2 ]; then
      while true; do
        dialog --backtitle "$(backtitle)" --colors --title "Serial" \
          --inputbox "Please enter a Serial Number " 0 0 "" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break 2
        SN="$(cat ${TMP_PATH}/resp)"
        if [ -z "${SN}" ]; then
          return
        elif [ $(validateSerial ${MODEL} ${SN}) -eq 1 ]; then
          break
        fi
        # At present, the SN rules are not complete, and many SNs are not truly invalid, so not provide tips now.
        break
        dialog --backtitle "$(backtitle)" --colors --title "Serial" \
          --yesno "Invalid Serial, continue?" 0 0
        [ $? -eq 0 ] && break
      done
      writeConfigKey "arc.patch" "user" "${USER_CONFIG_FILE}"
    fi
    writeConfigKey "arc.sn" "${SN}" "${USER_CONFIG_FILE}"
  fi
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  # Get Network Config for Loader
  getnet
  if [ "${ONLYPATCH}" = "true" ]; then
    return 1
  fi
  # Get Portmap for Loader
  getmap
  # Select Addons
  addonSelection
  # Check Warnings
  if [ ${WARNON} -eq 1 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: Your Controller has more then 8 Disks connected. Max Disks per Controller: 8" 0 0
  fi
  if [ ${WARNON} -eq 3 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: You have more then 8 Ethernet Ports. There are only 8 supported by DSM." 0 0
  fi
  if [ ${WARNON} -eq 4 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: Your CPU does not have AES Support for Hardwareencryption in DSM." 0 0
  fi
  KVMSUPPORT="$(readConfigKey "arc.kvm" "${USER_CONFIG_FILE}")"
  if [ "${KVMSUPPORT}" = "true" ]; then
    if ! grep -q "^flags.*vmx.*" /proc/cpuinfo | grep -q "^flags.*svm.*" /proc/cpuinfo; then
      dialog --backtitle "$(backtitle)" --title "Arc Warning" \
        --msgbox "WARN: Your CPU does not support VMM/KVM in DSM.\nCheck CPU/Bios for VMX or SVM Support." 0 0
    fi
  fi
  # Config is done
  writeConfigKey "arc.confdone" "true" "${USER_CONFIG_FILE}"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  # Ask for Build
  dialog --clear --backtitle "$(backtitle)" \
    --menu "Config done -> Build now?" 0 0 0 \
    1 "Yes - Build Arc Loader now" \
    2 "No - I want to make changes" \
  2>"${TMP_PATH}/resp"
  resp="$(<"${TMP_PATH}/resp")"
  [ -z "${resp}" ] && return 1
  if [ ${resp} -eq 1 ]; then
    make
  elif [ ${resp} -eq 2 ]; then
    dialog --clear --no-items --backtitle "$(backtitle)"
    return 1
  fi
}

###############################################################################
# Building Loader Online
function make() {
  # Read Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  USBMOUNT="$(readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "arc.emmcboot" "${USER_CONFIG_FILE}")"
  # Changes for SA6400
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
    MODULESCOPY="false"
    writeConfigKey "arc.modulescopy" "${MODULESCOPY}" "${USER_CONFIG_FILE}"
  fi
  if [ -d "${UNTAR_PAT_PATH}" ]; then
    rm -rf "${UNTAR_PAT_PATH}"
  fi
  mkdir -p "${UNTAR_PAT_PATH}"
  # Memory: Set mem_max_mb to the amount of installed memory to bypass Limitation
  writeConfigKey "synoinfo.mem_max_mb" "${RAMMAX}" "${USER_CONFIG_FILE}"
  writeConfigKey "synoinfo.mem_min_mb" "${RAMMIN}" "${USER_CONFIG_FILE}"
  # USBMount: If set to force
  if [ "${USBMOUNT}" = "force" ]; then
    writeConfigKey "synoinfo.maxdisks" "26" "${USER_CONFIG_FILE}"
    writeConfigKey "synoinfo.usbportcfg" "0x00" "${USER_CONFIG_FILE}"
    writeConfigKey "synoinfo.esataportcfg" "0x00" "${USER_CONFIG_FILE}"
    writeConfigKey "synoinfo.internalportcfg" "0x3ffffff" "${USER_CONFIG_FILE}"
  else
    deleteConfigKey "synoinfo.maxdisks" "${USER_CONFIG_FILE}"
    deleteConfigKey "synoinfo.usbportcfg" "${USER_CONFIG_FILE}"
    deleteConfigKey "synoinfo.esataportcfg" "${USER_CONFIG_FILE}"
    deleteConfigKey "synoinfo.internalportcfg" "${USER_CONFIG_FILE}"
  fi
  # Check if all addon exists
  while IFS=': ' read -r ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
        --msgbox "Addon ${ADDON} not found!" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Check for eMMC Boot
  if [ "${EMMCBOOT}" = "false" ]; then
    deleteConfigKey "modules.mmc_block" "${USER_CONFIG_FILE}"
    deleteConfigKey "modules.mmc_core" "${USER_CONFIG_FILE}"
  elif [ "${EMMCBOOT}" = "true" ]; then
    writeConfigKey "modules.mmc_block" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modules.mmc_core" "" "${USER_CONFIG_FILE}"
  fi
  # Check for offline Mode
  if [ "${OFFLINE}" = "true" ]; then
    offlinemake
    return
  else
    # Get PAT Data from Config
    PAT_URL_CONF="$(readConfigKey "arc.paturl" "${USER_CONFIG_FILE}")"
    PAT_HASH_CONF="$(readConfigKey "arc.pathash" "${USER_CONFIG_FILE}")"
    if [[ -z "${PAT_URL_CONF}" || -z "${PAT_HASH_CONF}" ]]; then
      PAT_URL_CONF="0"
      PAT_HASH_CONF="0"
    fi
    # Get PAT Data from Syno
    while true; do
      dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
        --infobox "Get PAT Data from Syno..." 3 30
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
          PAT_URL="$(curl -m 5-skL "https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/dsm/${MODEL/+/%2B}/${PRODUCTVER%%.*}.${PRODUCTVER##*.}/pat_url")"
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
        MSG="Failed to get PAT Data.\nPlease manually fill in the URL and Hash of PAT."
        PAT_URL=""
        PAT_HASH=""
      else
        MSG="Successfully got PAT Data.\nPlease confirm or modify if needed."
      fi
      dialog --backtitle "$(backtitle)" --colors --title "Arc Build" --default-button "OK" \
        --form "${MSG}" 10 110 2 "URL" 1 1 "${PAT_URL}" 1 7 100 0 "HASH" 2 1 "${PAT_HASH}" 2 7 100 0 \
        2>"${TMP_PATH}/resp"
      RET=$?
      [ ${RET} -eq 0 ] && break    # ok-button
      return                       # 1 or 255  # cancel-button or ESC
    done
    PAT_URL="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
    PAT_HASH="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
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
        --msgbox "No DSM Image found!\nTry Syno Link." 0 0
        # Grep PAT_URL
        PAT_FILE="${TMP_PATH}/${PAT_HASH}.pat"
        STATUS=$(curl -k -w "%{http_code}" -L "${PAT_URL}" -o "${PAT_FILE}" --progress-bar)
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
            --msgbox "No DSM Image found!\nExit." 0 0
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
          --msgbox "ERROR: No DSM Image found!" 0 0
        return 1
      fi
      # Copy DSM Files to Locations if DSM Files not found
      cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART1_PATH}"
      cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART1_PATH}"
      cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART2_PATH}"
      cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART2_PATH}"
      cp -f "${UNTAR_PAT_PATH}/zImage" "${ORI_ZIMAGE_FILE}"
      cp -f "${UNTAR_PAT_PATH}/rd.gz" "${ORI_RDGZ_FILE}"
      rm -rf "${UNTAR_PAT_PATH}"
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
      # Ask for Boot
      dialog --clear --backtitle "$(backtitle)" \
        --menu "Build done -> Boot now?" 0 0 0 \
        1 "Yes - Boot Arc Loader now" \
        2 "No - I want to make changes" \
      2>"${TMP_PATH}/resp"
      resp="$(<"${TMP_PATH}/resp")"
      [ -z "${resp}" ] && return 1
      if [ ${resp} -eq 1 ]; then
        boot && exit 0
      elif [ ${resp} -eq 2 ]; then
        dialog --clear --no-items --backtitle "$(backtitle)"
        return 1
      fi
    else
      dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
        --msgbox "Build failed!\nPlease check your Connection and Diskspace!" 0 0
      return 1
    fi
  fi
}

###############################################################################
# Building Loader Offline
function offlinemake() {
  # Check for existing Files
  mkdir -p "${UPLOAD_PATH}"
  # Get new Files
  dialog --backtitle "$(backtitle)" --title "DSM Upload" --aspect 18 \
  --msgbox "Upload your DSM .pat File to /tmp/upload.\nUse SSH/SFTP to connect to ${IP}.\nUser: root | Password: arc\nPress OK to continue!" 0 0
  # Grep PAT_FILE
  PAT_FILE=$(ls ${UPLOAD_PATH}/*.pat)
  if [ ! -f "${PAT_FILE}" ]; then
    dialog --backtitle "$(backtitle)" --title "DSM Extraction" --aspect 18 \
      --msgbox "No DSM Image found!\nExit." 0 0
    return 1
  else
    # Remove PAT Data for Offline
    PAT_URL=""
    PAT_HASH=""
    writeConfigKey "arc.paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.pathash" "${PAT_HASH}" "${USER_CONFIG_FILE}"
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
    # Cleanup old PAT
    rm -f "${PAT_FILE}"
    dialog --backtitle "$(backtitle)" --title "DSM Extraction" --aspect 18 \
      --msgbox "DSM Extraction successful!" 0 0
    # Copy DSM Files to Locations if DSM Files not found
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART1_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART1_PATH}"
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART2_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART2_PATH}"
    cp -f "${UNTAR_PAT_PATH}/zImage" "${ORI_ZIMAGE_FILE}"
    cp -f "${UNTAR_PAT_PATH}/rd.gz" "${ORI_RDGZ_FILE}"
    rm -rf "${UNTAR_PAT_PATH}"
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
    # Ask for Boot
    dialog --clear --backtitle "$(backtitle)" \
      --menu "Build done. Boot now?" 0 0 0 \
      1 "Yes - Boot Arc Loader now" \
      2 "No - I want to make changes" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      boot && exit 0
    elif [ ${resp} -eq 2 ]; then
      dialog --clear --no-items --backtitle "$(backtitle)"
      return 1
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
      --msgbox "Build failed!\nPlease check your Diskspace!" 0 0
    return 1
  fi
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "$(backtitle)" --title "Edit with caution" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return 1
    mv -f "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=$(yq eval "${USER_CONFIG_FILE}" 2>&1)
    [ $? -eq 0 ] && break
    dialog --backtitle "$(backtitle)" --title "Invalid YAML format" --msgbox "${ERRORS}" 0 0
  done
  OLDMODEL="${MODEL}"
  OLDPRODUCTVER="${PRODUCTVER}"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  SN="$(readConfigKey "arc.sn" "${USER_CONFIG_FILE}")"
  if [[ "${MODEL}" != "${OLDMODEL}" || "${PRODUCTVER}" != "${OLDPRODUCTVER}" ]]; then
    # Delete old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  fi
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Shows option to manage Addons
function addonMenu() {
  addonSelection
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

function addonSelection() {
  # read platform and kernel version to check if addon exists
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
  fi
  # Check for ACPI Support
  if ! grep -q "^flags.*acpi.*" /proc/cpuinfo; then
    deleteConfigKey "addons.acpid" "${USER_CONFIG_FILE}"
  fi
  # read addons from user config
  unset ADDONS
  declare -A ADDONS
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  rm -f "${TMP_PATH}/opts"
  touch "${TMP_PATH}/opts"
  while read -r ADDON DESC; do
    arrayExistItem "${ADDON}" "${!ADDONS[@]}" && ACT="on" || ACT="off"
    echo -e "${ADDON} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
  done < <(availableAddons "${PLATFORM}" "${KVER}")
  dialog --backtitle "$(backtitle)" --title "Loader Addons" --aspect 18 \
    --checklist "Select Loader Addons to include.\nPlease read Wiki before choosing anything.\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
    --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(<"${TMP_PATH}/resp")"
  dialog --backtitle "$(backtitle)" --title "Addons" \
      --infobox "Writing to user config" 5 30
  unset ADDONS
  declare -A ADDONS
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  for ADDON in ${resp}; do
    USERADDONS["${ADDON}"]=""
    writeConfigKey "addons.\"${ADDON}\"" "" "${USER_CONFIG_FILE}"
  done
  ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  dialog --backtitle "$(backtitle)" --title "Addons" \
    --msgbox "Loader Addons selected:\n${ADDONSINFO}" 0 0
}

###############################################################################
# Permit user select the modules to include
function modulesMenu() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
  fi
  dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
    --infobox "Reading modules" 0 0
  unset USERMODULES
  declare -A USERMODULES
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
  done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      1 "Show selected Modules" \
      2 "Select loaded Modules" \
      3 "Select all Modules" \
      4 "Deselect all Modules" \
      5 "Choose Modules to include" \
      6 "Add external module" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(<"${TMP_PATH}/resp")" in
      1)
        ITEMS=""
        for KEY in ${!USERMODULES[@]}; do
          ITEMS+="${KEY}: ${USERMODULES[$KEY]}\n"
        done
        dialog --backtitle "$(backtitle)" --title "User modules" \
          --msgbox "${ITEMS}" 0 0
        ;;
      2)
        dialog --backtitle "$(backtitle)" --colors --title "Modules" \
          --infobox "Selecting loaded Modules" 0 0
        KOLIST=""
        for I in $(lsmod | awk -F' ' '{print $1}' | grep -v 'Module'); do
          KOLIST+="$(getdepends "${PLATFORM}" "${KVER}" "${I}") ${I} "
        done
        KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        for ID in ${KOLIST[@]}; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      3)
        dialog --backtitle "$(backtitle)" --title "Modules" \
           --infobox "Selecting all Modules" 0 0
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        while read -r ID DESC; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
        done < <(getAllModules "${PLATFORM}" "${KVER}")
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      4)
        dialog --backtitle "$(backtitle)" --title "Modules" \
           --infobox "Deselecting all Modules" 0 0
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      5)
        rm -f "${TMP_PATH}/opts"
        while read -r ID DESC; do
          arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
          echo "${ID} ${DESC} ${ACT}" >>"${TMP_PATH}/opts"
        done < <(getAllModules "${PLATFORM}" "${KVER}")
        dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
          --checklist "Select Modules to include" 0 0 0 \
          --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        resp="$(<"${TMP_PATH}/resp")"
        dialog --backtitle "$(backtitle)" --title "Modules" \
           --infobox "Writing to user config" 20 5
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        for ID in ${resp}; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      6)
        TEXT=""
        TEXT+="This function is experimental and dangerous. If you don't know much, please exit.\n"
        TEXT+="The imported .ko of this function will be implanted into the corresponding arch's modules package, which will affect all models of the arch.\n"
        TEXT+="This program will not determine the availability of imported modules or even make type judgments, as please double check if it is correct.\n"
        TEXT+="If you want to remove it, please go to the \"Update Menu\" -> \"Update Modules\" to forcibly update the modules. All imports will be reset.\n"
        TEXT+="Do you want to continue?"
        dialog --backtitle "$(backtitle)" --title "Add external Module" \
            --yesno "${TEXT}" 0 0
        [ $? -ne 0 ] && continue
        dialog --backtitle "$(backtitle)" --aspect 18 --colors --inputbox "Please enter the complete URL to download.\n" 0 0 \
          2>"${TMP_PATH}/resp"
        URL="$(<"${TMP_PATH}/resp")"
        [ -z "${URL}" ] && continue
        clear
        echo "Downloading ${URL}"
        STATUS=$(curl -kLJO -w "%{http_code}" "${URL}" --progress-bar)
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Add external Module" --aspect 18 \
            --msgbox "ERROR: Check internet, URL or cache disk space" 0 0
          continue
        fi
        KONAME=$(basename "$URL")
        if [[ -n "${KONAME}" && "${KONAME##*.}" = "ko" ]]; then
          addToModules "${PLATFORM}" "${KVER}" "${TMP_UP_PATH}/${USER_FILE}"
          dialog --backtitle "$(backtitle)" --title "Add external Module" --aspect 18 \
            --msgbox "Module ${KONAME} added to ${PLATFORM}-${KVER}" 0 0
          rm -f "${KONAME}"
        else
          dialog --backtitle "$(backtitle)" --title "Add external Module" --aspect 18 \
            --msgbox "File format not recognized!" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
    esac
  done
}

###############################################################################
# Let user edit cmdline
function cmdlineMenu() {
  unset CMDLINE
  declare -A CMDLINE
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
  done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
  echo "1 \"Add a Cmdline item\""                                >"${TMP_PATH}/menu"
  echo "2 \"Delete Cmdline item(s)\""                           >>"${TMP_PATH}/menu"
  echo "3 \"CPU Fix\""                                          >>"${TMP_PATH}/menu"
  echo "4 \"RAM Fix\""                                          >>"${TMP_PATH}/menu"
  echo "5 \"PCI/IRQ Fix\""                                      >>"${TMP_PATH}/menu"
  echo "6 \"C-State Fix\""                                      >>"${TMP_PATH}/menu"
  echo "7 \"Show user Cmdline\""                                >>"${TMP_PATH}/menu"
  echo "8 \"Show Model/Build Cmdline\""                         >>"${TMP_PATH}/menu"
  echo "9 \"Kernelpanic Behavior\""                             >>"${TMP_PATH}/menu"
  # Loop menu
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(<"${TMP_PATH}/resp")" in
      1)
        MSG=""
        MSG+="Commonly used Parameter:\n"
        MSG+=" * \Z4disable_mtrr_trim=\Zn\n    disables kernel trim any uncacheable memory out.\n"
        MSG+=" * \Z4intel_idle.max_cstate=1\Zn\n    Set the maximum C-state depth allowed by the intel_idle driver.\n"
        MSG+=" * \Z4pcie_port_pm=off\Zn\n    Turn off the power management of the PCIe port.\n"
        MSG+=" * \Z4libata.force=noncq\Zn\n    Disable NCQ for all SATA ports.\n"
        MSG+=" * \Z4i915.enable_guc=2\Zn\n    Enable the GuC firmware on Intel graphics hardware.(value: 1,2 or 3)\n"
        MSG+=" * \Z4i915.max_vfs=7\Zn\n     Set the maximum number of virtual functions (VFs) that can be created for Intel graphics hardware.\n"
        MSG+="\nEnter the Parameter Name and Value you want to add.\n"
        LINENUM=$(($(echo -e "${MSG}" | wc -l) + 10))
        while true; do
          dialog --clear --backtitle "$(backtitle)" \
            --colors --title "User Cmdline" \
            --form "${MSG}" ${LINENUM:-16} 70 2 "Name:" 1 1 "" 1 10 55 0 "Value:" 2 1 "" 2 10 55 0 \
            2>"${TMP_PATH}/resp"
          RET=$?
          case ${RET} in
          0) # ok-button
            NAME="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
            VALUE="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
            if [ -z "${NAME//\"/}" ]; then
                        dialog --clear --backtitle "$(backtitle)" --title "User Cmdline" \
                --yesno "Invalid Parameter Name, retry?" 0 0
              [ $? -eq 0 ] && break
            fi
            writeConfigKey "cmdline.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
            break
            ;;
          1) # cancel-button
            break
            ;;
          255) # ESC
            break
            ;;
          esac
        done
        ;;
      2)
        if [ ${#CMDLINE[@]} -eq 0 ]; then
          dialog --backtitle "$(backtitle)" --msgbox "No user cmdline to remove" 0 0
          continue
        fi
        ITEMS=""
        for I in "${!CMDLINE[@]}"; do
          [ -z "${CMDLINE[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${CMDLINE[${I}]} off "
        done
        dialog --backtitle "$(backtitle)" \
          --checklist "Select cmdline to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && continue
        for I in ${resp}; do
          unset 'CMDLINE[${I}]'
          deleteConfigKey "cmdline.\"${I}\"" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      3)
        dialog --clear --backtitle "$(backtitle)" \
          --title "CPU Fix" --menu "Fix?" 0 0 0 \
          1 "Install" \
          2 "Uninnstall" \
        2>"${TMP_PATH}/resp"
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        if [ ${resp} -eq 1 ]; then
          writeConfigKey "cmdline.nmi_watchdog" "0" "${USER_CONFIG_FILE}"
          writeConfigKey "cmdline.tsc" "reliable" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "CPU Fix" \
            --aspect 18 --msgbox "Fix added to Cmdline" 0 0
        elif [ ${resp} -eq 2 ]; then
          deleteConfigKey "cmdline.nmi_watchdog" "${USER_CONFIG_FILE}"
          deleteConfigKey "cmdline.tsc" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "CPU Fix" \
            --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      4)
        dialog --clear --backtitle "$(backtitle)" \
          --title "RAM Fix" --menu "Fix?" 0 0 0 \
          1 "Install" \
          2 "Uninnstall" \
        2>"${TMP_PATH}/resp"
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        if [ ${resp} -eq 1 ]; then
          writeConfigKey "cmdline.disable_mtrr_trim" "0" "${USER_CONFIG_FILE}"
          writeConfigKey "cmdline.crashkernel" "auto" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "RAM Fix" \
            --aspect 18 --msgbox "Fix added to Cmdline" 0 0
        elif [ ${resp} -eq 2 ]; then
          deleteConfigKey "cmdline.disable_mtrr_trim" "${USER_CONFIG_FILE}"
          deleteConfigKey "cmdline.crashkernel" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "RAM Fix" \
            --aspect 18 --msgbox "Fix removed from Cmdline" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      5)
        dialog --clear --backtitle "$(backtitle)" \
          --title "PCI/IRQ Fix" --menu "Fix?" 0 0 0 \
          1 "Install" \
          2 "Uninnstall" \
        2>"${TMP_PATH}/resp"
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        if [ ${resp} -eq 1 ]; then
          writeConfigKey "cmdline.pci" "routeirq" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "PCI/IRQ Fix" \
            --aspect 18 --msgbox "Fix added to Cmdline" 0 0
        elif [ ${resp} -eq 2 ]; then
          deleteConfigKey "cmdline.pci" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "PCI/IRQ Fix" \
            --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      6)
        dialog --clear --backtitle "$(backtitle)" \
          --title "C-State Fix" --menu "Fix?" 0 0 0 \
          1 "Install" \
          2 "Uninnstall" \
        2>"${TMP_PATH}/resp"
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        if [ ${resp} -eq 1 ]; then
          writeConfigKey "cmdline.intel_idle.max_cstate" "1" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "C-State Fix" \
            --aspect 18 --msgbox "Fix added to Cmdline" 0 0
        elif [ ${resp} -eq 2 ]; then
          deleteConfigKey "cmdline.intel_idle.max_cstate" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "C-State Fix" \
            --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      7)
        ITEMS=""
        for KEY in ${!CMDLINE[@]}; do
          ITEMS+="${KEY}: ${CMDLINE[$KEY]}\n"
        done
        dialog --backtitle "$(backtitle)" --title "User cmdline" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      8)
        ITEMS=""
        while IFS=': ' read -r KEY VALUE; do
          ITEMS+="${KEY}: ${VALUE}\n"
        done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
        dialog --backtitle "$(backtitle)" --title "Model/Version cmdline" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      9)
        rm -f "${TMP_PATH}/opts"
        echo "5 \"Reboot after 5 seconds\"" >>"${TMP_PATH}/opts"
        echo "0 \"No reboot\"" >>"${TMP_PATH}/opts"
        echo "-1 \"Restart immediately\"" >>"${TMP_PATH}/opts"
        dialog --backtitle "$(backtitle)" --colors --title "Kernelpanic" \
          --default-item "${KERNELPANIC}" --menu "Choose a time(seconds)" 0 0 0 --file "${TMP_PATH}/opts" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && return
        resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
        [ -z "${resp}" ] && return
        KERNELPANIC=${resp}
        writeConfigKey "arc.kernelpanic" "${KERNELPANIC}" "${USER_CONFIG_FILE}"
        ;;
    esac
  done
}

###############################################################################
# let user configure synoinfo entries
function synoinfoMenu() {
  # read synoinfo from user config
  unset SYNOINFO
  declare -A SYNOINFO
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
  done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "1 \"Add/edit Synoinfo item\""     >"${TMP_PATH}/menu"
  echo "2 \"Delete Synoinfo item(s)\""    >>"${TMP_PATH}/menu"
  echo "3 \"Show Synoinfo entries\""      >>"${TMP_PATH}/menu"
  echo "4 \"Thermal Shutdown (DT only)\"" >>"${TMP_PATH}/menu"

  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(<"${TMP_PATH}/resp")" in
      1)
        dialog --backtitle "$(backtitle)" --title "Synoinfo entries" \
          --inputbox "Type a name of synoinfo entry" 0 0 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        NAME="$(<"${TMP_PATH}/resp")"
        [ -z "${NAME//\"/}" ] && continue
        dialog --backtitle "$(backtitle)" --title "Synoinfo entries" \
          --inputbox "Type a value of '${NAME}' entry" 0 0 "${SYNOINFO[${NAME}]}" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        VALUE="$(<"${TMP_PATH}/resp")"
        SYNOINFO[${NAME}]="${VALUE}"
        writeConfigKey "synoinfo.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      2)
        if [ ${#SYNOINFO[@]} -eq 0 ]; then
          dialog --backtitle "$(backtitle)" --msgbox "No synoinfo entries to remove" 0 0
          continue
        fi
        ITEMS=""
        for I in "${!SYNOINFO[@]}"; do
          [ -z "${SYNOINFO[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${SYNOINFO[${I}]} off "
        done
        dialog --backtitle "$(backtitle)" \
          --checklist "Select synoinfo entry to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && continue
        for I in ${resp}; do
          unset 'SYNOINFO[${I}]'
          deleteConfigKey "synoinfo.\"${I}\"" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      3)
        ITEMS=""
        for KEY in ${!SYNOINFO[@]}; do
          ITEMS+="${KEY}: ${SYNOINFO[$KEY]}\n"
        done
        dialog --backtitle "$(backtitle)" --title "Synoinfo entries" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      4)
        MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
        CONFDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        PLATFORM="$(readModelKey "${MODEL}" "platform")"
        DT="$(readModelKey "${MODEL}" "dt")"
        if [[ "${CONFDONE}" = "true" && "${DT}" = "true" ]]; then
          if findAndMountDSMRoot; then
            if [ -f "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml" ]; then
              if [ -f "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml.bak" ]; then
                cp -f "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml.bak" "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml"
              fi
              cp -f "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml" "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml.bak"
              dialog --backtitle "$(backtitle)" --title "Thermal Shutdown" \
              --inputbox "CPU Temperature: (Default 90 °C)" 0 0 \
              2>"${TMP_PATH}/resp"
              RET=$?
              [ ${RET} -ne 0 ] && break 2
              CPUTEMP="$(<"${TMP_PATH}/resp")"
              if [ "${PLATFORM}" = "geminilake" ]; then
                sed -i 's|<cpu_temperature fan_speed="99%40hz" action="SHUTDOWN">90</cpu_temperature>|<cpu_temperature fan_speed="99%40hz" action="SHUTDOWN">'"${CPUTEMP}"'</cpu_temperature>|g' "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml"
              elif [[ "${PLATFORM}" = "r1000" || "${PLATFORM}" = "v1000" || "${PLATFORM}" = "epyc7002" ]]; then
                sed -i 's|<alert_config threshold="2" period="30" alert_temp="85" shutdown_temp="95" name="cpu"/>|<alert_config threshold="2" period="30" alert_temp="85" shutdown_temp="'"${CPUTEMP}"'" name="cpu"/>|g' "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml"
              fi
              dialog --backtitle "$(backtitle)" --title "Thermal Shutdown" \
              --inputbox "Disk Temperature: (Default 61 °C)" 0 0 \
              2>"${TMP_PATH}/resp"
              RET=$?
              [ ${RET} -ne 0 ] && break 2
              DISKTEMP="$(<"${TMP_PATH}/resp")"
              if [ "${PLATFORM}" = "geminilake" ]; then
                sed -i 's|<disk_temperature fan_speed="99%40hz" action="SHUTDOWN">61</disk_temperature>|<disk_temperature fan_speed="99%40hz" action="SHUTDOWN">'"${DISKTEMP}"'</disk_temperature>|g' "/mnt/dsmroot/usr/syno/etc.defaults/scemd.xml"
              elif [[ "${PLATFORM}" = "r1000" || "${PLATFORM}" = "v1000" || "${PLATFORM}" = "epyc7002" ]]; then
                sed -i 's|<alert_config threshold="2" period="300" alert_temp="58" shutdown_temp="61" name="disk"/>|<alert_config threshold="2" period="300" alert_temp="58" shutdown_temp="'"${DISKTEMP}"'" name="disk"/>|g' "/mnt/dsmroot/usr/syno/etc.defaults/scemd.xml"
              fi
              dialog --backtitle "$(backtitle)" --title "Thermal Shutdown" \
              --inputbox "M.2 Temperature: (Default 70 °C)" 0 0 \
              2>"${TMP_PATH}/resp"
              RET=$?
              [ ${RET} -ne 0 ] && break 2
              M2TEMP="$(<"${TMP_PATH}/resp")"
              if [ "${PLATFORM}" = "geminilake" ]; then
                sed -i 's|<m2_temperature fan_speed="99%40hz" action="SHUTDOWN">70</m2_temperature>|<m2_temperature fan_speed="99%40hz" action="SHUTDOWN">'"${M2TEMP}"'</m2_temperature>|g' "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml"
              elif [[ "${PLATFORM}" = "r1000" || "${PLATFORM}" = "v1000" || "${PLATFORM}" = "epyc7002" ]]; then
                sed -i 's|<alert_config threshold="2" period="30" alert_temp="68" shutdown_temp="71" name="m2"/>|<alert_config threshold="2" period="30" alert_temp="68" shutdown_temp="'"${M2TEMP}"'" name="m2"/>|g' "${DSMROOT_PATH}/usr/syno/etc.defaults/scemd.xml"
              fi
              dialog --backtitle "$(backtitle)" --title "Thermal Shutdown" --aspect 18 \
                --msgbox "Change Thermal Shutdown Settings successful!\nCPU: ${CPUTEMP}\nDisk: ${DISKTEMP}\nM.2: ${M2TEMP}" 0 0
            else
              dialog --backtitle "$(backtitle)" --title "Thermal Shutdown" --aspect 18 \
                --msgbox "Change Thermal Shutdown Settings not possible!" 0 0
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Thermal Shutdown" --aspect 18 \
                --msgbox "Unfortunately Arc couldn't mount the DSM Partition!" 0 0
          fi
        else
          dialog --backtitle "$(backtitle)" --title "Thermal Shutdown" --aspect 18 \
            --msgbox "Please build and install DSM first!" 0 0
        fi
        ;;
    esac
  done
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  dialog --backtitle "$(backtitle)" --default-item "${LAYOUT}" --no-items \
    --menu "Choose a Layout" 0 0 0 "azerty" "bepo" "carpalx" "colemak" \
    "dvorak" "fgGIod" "neo" "olpc" "qwerty" "qwertz" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  LAYOUT="$(<"${TMP_PATH}/resp")"
  OPTIONS=""
  while read -r KM; do
    OPTIONS+="${KM::-7} "
  done < <(cd /usr/share/keymaps/i386/${LAYOUT}; ls *.map.gz)
  dialog --backtitle "$(backtitle)" --no-items --default-item "${KEYMAP}" \
    --menu "Choice a keymap" 0 0 0 ${OPTIONS} \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && continue
  resp="$(<"${TMP_PATH}/resp")"
  [ -z "${resp}" ] && continue
  KEYMAP=${resp}
  writeConfigKey "layout" "${LAYOUT}" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  loadkeys /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz
}

###############################################################################
# Shows usb menu to user
function usbMenu() {
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      1 "Mount USB as Internal (force)" \
      2 "Mount USB as Device" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(<"${TMP_PATH}/resp")" in
      1)
        MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
        writeConfigKey "synoinfo.maxdisks" "26" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.usbportcfg" "0x00" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.esataportcfg" "0x00" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.internalportcfg" "0x3ffffff" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.usbmount" "true" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Mount USB as Internal" \
          --aspect 18 --msgbox "Mount USB as Internal - successful!" 0 0
        ;;
      2)
        MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
        deleteConfigKey "synoinfo.maxdisks" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.usbportcfg" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.esataportcfg" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.internalportcfg" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Mount USB as Device" \
          --aspect 18 --msgbox "Mount USB as Device - successful!" 0 0
        ;;
    esac
  else
    dialog --backtitle "$(backtitle)" --title "Mount USB Options" \
      --aspect 18 --msgbox "Please configure your System first." 0 0
    return 1
  fi
}

###############################################################################
# Shows storagepanel menu to user
function storagepanelMenu() {
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --title "StoragePanel" \
      --aspect 18 --msgbox "Enable custom StoragePanel Addon." 0 0
    ITEMS="$(echo -e "2_Bay \n4_Bay \n8_Bay \n12_Bay \n16_Bay \n24_Bay \n")"
    dialog --backtitle "$(backtitle)" --title "StoragePanel" \
      --default-item "24_Bay" --no-items --menu "Choose a Disk Panel" 0 0 0 ${ITEMS} \
      2>"${TMP_PATH}/resp"
    resp="$(cat ${TMP_PATH}/resp 2>/dev/null)"
    [ -z "${resp}" ] && return 1
    STORAGE=${resp}
    ITEMS="$(echo -e "1X2 \n1X4 \n1X8 \n")"
    dialog --backtitle "$(backtitle)" --title "StoragePanel" \
      --default-item "1X8" --no-items --menu "Choose a M.2 Panel" 0 0 0 ${ITEMS} \
      2>"${TMP_PATH}/resp"
    resp="$(cat ${TMP_PATH}/resp 2>/dev/null)"
    [ -z "${resp}" ] && return 1
    M2PANEL=${resp}
    STORAGEPANEL="RACK_${STORAGE} ${M2PANEL}"
    writeConfigKey "addons.storagepanel" "${STORAGEPANEL}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  fi
}

###############################################################################
# Shows backup menu to user
function backupMenu() {
  NEXT="1"
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  if [ "${OFFLINE}" = "false" ]; then
    while true; do
      dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
        1 "Backup Config with Code" \
        2 "Restore Config with Code" \
        3 "Recover from DSM" \
        4 "Backup Encryption Key" \
        5 "Restore Encryption Key" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return 1
      case "$(<"${TMP_PATH}/resp")" in
        1)
          dialog --backtitle "$(backtitle)" --title "Backup Config with Code" \
              --infobox "Write down your Code for Restore!" 0 0
          if [ -f "${USER_CONFIG_FILE}" ]; then
            GENHASH="$(cat "${USER_CONFIG_FILE}" | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-)"
            dialog --backtitle "$(backtitle)" --title "Backup Config with Code" --msgbox "Your Code: ${GENHASH}" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Backup Config with Code" --msgbox "No Config for Backup found!" 0 0
          fi
          ;;
        2)
          while true; do
            dialog --backtitle "$(backtitle)" --title "Restore with Code" \
              --inputbox "Type your Code here!" 0 0 \
              2>"${TMP_PATH}/resp"
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            GENHASH="$(<"${TMP_PATH}/resp")"
            [ ${#GENHASH} -eq 9 ] && break
            dialog --backtitle "$(backtitle)" --title "Restore with Code" --msgbox "Invalid Code" 0 0
          done
          rm -f "${BACKUPDIR}/user-config.yml"
          curl -k https://dpaste.com/${GENHASH}.txt >"${BACKUPDIR}/user-config.yml"
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            CONFIG_VERSION="$(readConfigKey "arc.version" "${BACKUPDIR}/user-config.yml")"
            if [ "${ARC_VERSION}" = "${CONFIG_VERSION}" ]; then
              # Copy config back to location
              cp -f "${BACKUPDIR}/user-config.yml" "${USER_CONFIG_FILE}"
              dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
                --msgbox "Restore complete!" 0 0
            else
              cp -f "${BACKUPDIR}/user-config.yml" "${USER_CONFIG_FILE}"
              dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
                --msgbox "Version mismatch!\nIt is possible that your Config will not work!" 0 0
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
              --msgbox "No Config Backup found" 0 0
            return 1
          fi
          MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
          PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          ARCRECOVERY="true"
          ONLYVERSION="true"
          CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          arcbuild
          ;;
        3)
          dialog --backtitle "$(backtitle)" --title "Try to recover DSM" --aspect 18 \
            --infobox "Trying to recover a DSM installed system" 0 0
          if findAndMountDSMRoot; then
            MODEL=""
            PRODUCTVER=""
            if [ -f "${DSMROOT_PATH}/.syno/patch/VERSION" ]; then
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep unique)
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep majorversion)
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep minorversion)
              if [ -n "${unique}" ] ; then
                while read -r F; do
                  M="$(basename ${F})"
                  M="${M::-4}"
                  UNIQUE="$(readModelKey "${M}" "unique")"
                  [ "${unique}" = "${UNIQUE}" ] || continue
                  # Found
                  writeConfigKey "model" "${M}" "${USER_CONFIG_FILE}"
                done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
                MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
                if [ -n "${MODEL}" ]; then
                  writeConfigKey "productver" "${majorversion}.${minorversion}" "${USER_CONFIG_FILE}"
                  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
                  if [ -n "${PRODUCTVER}" ]; then
                    cp -f "${DSMROOT_PATH}/.syno/patch/zImage" "${PART2_PATH}"
                    cp -f "${DSMROOT_PATH}/.syno/patch/rd.gz" "${PART2_PATH}"
                    TEXT="Installation found:\nModel: ${MODEL}\nVersion: ${PRODUCTVER}"
                    SN=$(_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf")
                    if [ -n "${SN}" ]; then
                      deleteConfigKey "arc.patch" "${USER_CONFIG_FILE}"
                      SNARC="$(readConfigKey "arc.serial" "${MODEL_CONFIG_PATH}/${MODEL}.yml")"
                      writeConfigKey "arc.sn" "${SN}" "${USER_CONFIG_FILE}"
                      TEXT+="\nSerial: ${SN}"
                      if [ "${SN}" = "${SNARC}" ]; then
                        writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
                      else
                        writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
                      fi
                      ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
                      TEXT+="\nArc Patch: ${ARCPATCH}"
                    fi
                    dialog --backtitle "$(backtitle)" --title "Try to recover DSM" \
                      --aspect 18 --msgbox "${TEXT}" 0 0
                    ARCRECOVERY="true"
                    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
                    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
                    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
                    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
                    arcbuild
                  fi
                fi
              fi
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Try recovery DSM" --aspect 18 \
              --msgbox "Unfortunately Arc couldn't mount the DSM partition!" 0 0
          fi
          ;;
        4)
          dialog --backtitle "$(backtitle)" --title "Backup Encryption Key" --aspect 18 \
            --infobox "Backup Encryption Key..." 0 0
          if [ -f "${PART2_PATH}/machine.key" ]; then
            if findAndMountDSMRoot; then
              mkdir -p "${DSMROOT_PATH}/root/Xpenology_backup"
              cp -f "${PART2_PATH}/machine.key" "${DSMROOT_PATH}/root/Xpenology_backup/machine.key"
              dialog --backtitle "$(backtitle)" --title "Backup Encryption Key" --aspect 18 \
                --msgbox "Encryption Key backup successful!" 0 0
            else
              dialog --backtitle "$(backtitle)" --title "Backup Encryption Key" --aspect 18 \
                --msgbox "Unfortunately Arc couldn't mount the DSM Partition for Backup!" 0 0
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Backup Encryption Key" --aspect 18 \
              --msgbox "No Encryption Key found!" 0 0
          fi
          ;;
        5)
          dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
            --infobox "Restore Encryption Key..." 0 0
          if findAndMountDSMRoot; then
            if [ -f "${DSMROOT_PATH}/root/Xpenology_backup/machine.key" ]; then
              cp -f "${DSMROOT_PATH}/root/Xpenology_backup/machine.key" "${PART2_PATH}/machine.key"
              dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
                --msgbox "Encryption Key restore successful!" 0 0
            else
              dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
              --msgbox "No Encryption Key found!" 0 0
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
                --msgbox "Unfortunately Arc couldn't mount the DSM Partition for Restore!" 0 0
          fi
          ;;
      esac
    done
  else
    while true; do
      dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
        1 "Recover from DSM" \
        2 "Restore Encryption Key" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return 1
      case "$(<"${TMP_PATH}/resp")" in
        1)
          dialog --backtitle "$(backtitle)" --title "Try to recover DSM" --aspect 18 \
            --infobox "Trying to recover a DSM installed system" 0 0
          if findAndMountDSMRoot; then
            MODEL=""
            PRODUCTVER=""
            if [ -f "${DSMROOT_PATH}/.syno/patch/VERSION" ]; then
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep unique)
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep majorversion)
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep minorversion)
              if [ -n "${unique}" ] ; then
                while read -r F; do
                  M="$(basename ${F})"
                  M="${M::-4}"
                  UNIQUE="$(readModelKey "${M}" "unique")"
                  [ "${unique}" = "${UNIQUE}" ] || continue
                  # Found
                  writeConfigKey "model" "${M}" "${USER_CONFIG_FILE}"
                done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
                MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
                if [ -n "${MODEL}" ]; then
                  writeConfigKey "productver" "${majorversion}.${minorversion}" "${USER_CONFIG_FILE}"
                  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
                  if [ -n "${PRODUCTVER}" ]; then
                    cp -f "${DSMROOT_PATH}/.syno/patch/zImage" "${PART2_PATH}"
                    cp -f "${DSMROOT_PATH}/.syno/patch/rd.gz" "${PART2_PATH}"
                    TEXT="Installation found:\nModel: ${MODEL}\nVersion: ${PRODUCTVER}"
                    SN=$(_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf")
                    if [ -n "${SN}" ]; then
                      deleteConfigKey "arc.patch" "${USER_CONFIG_FILE}"
                      SNARC="$(readConfigKey "arc.serial" "${MODEL_CONFIG_PATH}/${MODEL}.yml")"
                      writeConfigKey "arc.sn" "${SN}" "${USER_CONFIG_FILE}"
                      TEXT+="\nSerial: ${SN}"
                      if [ "${SN}" = "${SNARC}" ]; then
                        writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
                      else
                        writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
                      fi
                      ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
                      TEXT+="\nArc Patch: ${ARCPATCH}"
                    fi
                    dialog --backtitle "$(backtitle)" --title "Try to recover DSM" \
                      --aspect 18 --msgbox "${TEXT}" 0 0
                    ARCRECOVERY="true"
                    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
                    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
                    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
                    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
                    arcbuild
                  fi
                fi
              fi
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Try recovery DSM" --aspect 18 \
              --msgbox "Unfortunately Arc couldn't mount the DSM partition!" 0 0
          fi
          ;;
        2)
          dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
            --infobox "Restore Encryption Key..." 0 0
          if findAndMountDSMRoot; then
            if [ -f "${DSMROOT_PATH}/root/Xpenology_backup/machine.key" ]; then
              cp -f "${DSMROOT_PATH}/root/Xpenology_backup/machine.key" "${PART2_PATH}/machine.key"
              dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
                --msgbox "Encryption Key restore successful!" 0 0
            else
              dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
              --msgbox "No Encryption Key found!" 0 0
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
                --msgbox "Unfortunately Arc couldn't mount the DSM Partition for Restore!" 0 0
          fi
          ;;
      esac
    done
  fi
}

###############################################################################
# Shows update menu to user
function updateMenu() {
  NEXT="1"
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      1 "Full-Upgrade Loader" \
      2 "Update Addons" \
      3 "Update Patches" \
      4 "Update Modules" \
      5 "Update Configs" \
      6 "Update LKMs" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(<"${TMP_PATH}/resp")" in
      1)
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --infobox "Checking latest version..." 0 0
        ACTUALVERSION="${ARC_VERSION}"
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        if [ "${ACTUALVERSION}" = "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
            --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
          [ $? -ne 0 ] && continue
        fi
        # Download update file
        STATUS=$(curl --insecure -w "%{http_code}" -L "https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}.img.zip" -o "${TMP_PATH}/arc-${TAG}.img.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
            --msgbox "Error downloading Updatefile!" 0 0
          return 1
        fi
        unzip -oq "${TMP_PATH}/arc-${TAG}.img.zip" -d "${TMP_PATH}"
        rm -f "${TMP_PATH}/arc-${TAG}.img.zip"
        if [ $? -ne 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
            --msgbox "Error extracting Updatefile" 0 0
          return 1
        fi
        if [[ -f "${USER_CONFIG_FILE}" && "${CONFDONE}" = "true" ]]; then
          GENHASH="$(cat "${USER_CONFIG_FILE}" | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-)"
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --msgbox "Backup config successful!\nWrite down your Code: ${GENHASH}\n\nAfter Reboot use: Restore with Code." 0 0
        else
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --msgbox "No config for Backup found!" 0 0
        fi
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --infobox "Installing new Loader Image" 0 0
        # Process complete update
        umount "${PART1_PATH}" "${PART2_PATH}" "${PART3_PATH}"
        dd if="${TMP_PATH}/arc.img" of=$(blkid | grep 'LABEL="ARC3"' | cut -d3 -f1) bs=1M conv=fsync
        # Ask for Boot
        rm -f "${TMP_PATH}/arc.img"
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --yesno "Arc Upgrade successful. New Version: ${TAG}\nReboot?" 0 0
        [ $? -ne 0 ] && continue
        exec reboot
        exit 0
        ;;
      2)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update Addons" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && continue
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Addons" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o "${TMP_PATH}/addons.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
            --msgbox "Error downloading Updatefile!" 0 0
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
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
          --msgbox "Addons updated successful! New Version: ${TAG}" 0 0
        ;;
      3)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update Patches" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-patches/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Patches" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches.zip" -o "${TMP_PATH}/patches.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
            --msgbox "Error downloading Updatefile!" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
          --infobox "Extracting" 0 0
        rm -rf "${PATCH_PATH}"
        mkdir -p "${PATCH_PATH}"
        unzip -oq "${TMP_PATH}/patches.zip" -d "${PATCH_PATH}" >/dev/null 2>&1
        rm -f "${TMP_PATH}/patches.zip"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
          --msgbox "Patches updated successful! New Version: ${TAG}" 0 0
        ;;
      4)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update Modules" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Modules" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl -k -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip" -o "${TMP_PATH}/modules.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
            --msgbox "Error downloading Updatefile!" 0 0
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
          done < <(getAllModules "${PLATFORM}" "${KVER}")
        fi
        rm -f "${TMP_PATH}/modules.zip"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
          --msgbox "Modules updated successful. New Version: ${TAG}" 0 0
        ;;
      5)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update Configs" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-configs/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Configs" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs.zip" -o "${TMP_PATH}/configs.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
            --msgbox "Error downloading Updatefile!" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --infobox "Extracting" 0 0
        rm -rf "${MODEL_CONFIG_PATH}"
        mkdir -p "${MODEL_CONFIG_PATH}"
        unzip -oq "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}" >/dev/null 2>&1
        rm -f "${TMP_PATH}/configs.zip"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --msgbox "Configs updated successful! New Version: ${TAG}" 0 0
        ;;
      6)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update LKMs" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update LKMs" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o "${TMP_PATH}/rp-lkms.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
            --msgbox "Error downloading Updatefile" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --infobox "Extracting" 0 0
        rm -rf "${LKM_PATH}"
        mkdir -p "${LKM_PATH}"
        unzip -oq "${TMP_PATH}/rp-lkms.zip" -d "${LKM_PATH}" >/dev/null 2>&1
        rm -f "${TMP_PATH}/rp-lkms.zip"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --msgbox "LKMs updated successful! New Version: ${TAG}" 0 0
        ;;
    esac
  done
}

###############################################################################
# Show Storagemenu to user
function storageMenu() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  DT="$(readModelKey "${MODEL}" "dt")"
  # Get Portmap for Loader
  getmap
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Show Storagemenu to user
function networkMenu() {
  # Get Network Config for Loader
  getnet
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Shows Systeminfo to user
function sysinfo() {
  # Checks for Systeminfo Menu
  CPUINFO="$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')"
  # Check if machine has EFI
  [ -d /sys/firmware/efi ] && BOOTSYS="UEFI" || BOOTSYS="Legacy"
  VENDOR="$(dmidecode -s system-product-name)"
  BOARD="$(dmidecode -s baseboard-product-name)"
  ETHX=$(ls /sys/class/net/ | grep -v lo) || true
  NIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    DT="$(readModelKey "${MODEL}" "dt")"
    KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
    ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
    ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
    REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
    if [[ "${REMAP}" = "acports" || "${REMAP}" = "maxports" ]]; then
      PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
      DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" = "remap" ]; then
      PORTMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
    fi
  fi
  DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
  USBMOUNT="$(readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
  MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  ARCIPV6="$(readConfigKey "arc.ipv6" "${USER_CONFIG_FILE}")"
  CONFIGVER="$(readConfigKey "arc.version" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
  KVMSUPPORT="$(readConfigKey "arc.kvm" "${USER_CONFIG_FILE}")"
  MODULESINFO="$(lsmod | awk -F' ' '{print $1}' | grep -v 'Module')"
  MODULESVERSION="$(cat "${MODULES_PATH}/VERSION")"
  ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")"
  LKMVERSION="$(cat "${LKM_PATH}/VERSION")"
  CONFIGSVERSION="$(cat "${MODEL_CONFIG_PATH}/VERSION")"
  PATCHESVERSION="$(cat "${PATCH_PATH}/VERSION")"
  TEXT=""
  # Print System Informations
  TEXT+="\n\Z4> System: ${MACHINE} | ${BOOTSYS}\Zn"
  TEXT+="\n  Vendor | Board: \Zb${VENDOR} | ${BOARD}\Zn"
  TEXT+="\n  CPU: \Zb${CPUINFO}\Zn"
  TEXT+="\n  Memory: \Zb$((${RAMTOTAL} / 1024))GB\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4> Network: ${NIC} NIC\Zn"
  for ETH in ${ETHX}; do
    IP=""
    STATICIP="$(readConfigKey "static.${ETH}" "${USER_CONFIG_FILE}")"
    DRIVER=$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    MAC="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
    COUNT=0
    while true; do
      if [ "${STATICIP}" = "true" ]; then
        IP="$(readConfigKey "ip.${ETH}" "${USER_CONFIG_FILE}")"
        MSG="STATIC"
      else
        IP="$(getIP ${ETH})"
        MSG="DHCP"
      fi
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${ETH} | grep "Speed:" | awk '{print $2}')
        TEXT+="\n  ${DRIVER} (${SPEED} | ${MSG}) \ZbIP: ${IP} | Mac: ${MAC}\Zn"
        break
      fi
      if [ ${COUNT} -gt 3 ]; then
        TEXT+="\n  ${DRIVER} \ZbIP: TIMEOUT | MAC: ${MAC}\Zn"
        break
      fi
      sleep 3
      if ethtool ${ETH} | grep 'Link detected' | grep -q 'no'; then
        TEXT+="\n  ${DRIVER} \ZbIP: NOT CONNECTED | MAC: ${MAC}\Zn"
        break
      fi
      COUNT=$((${COUNT} + 3))
    done
  done
  # Print Config Informations
  TEXT+="\n"
  TEXT+="\n\Z4> Arc: ${ARC_VERSION}\Zn"
  TEXT+="\n  Subversion Loader: \ZbAddons ${ADDONSVERSION} | Configs ${CONFIGSVERSION} | Patches ${PATCHESVERSION}\Zn"
  TEXT+="\n  Subversion DSM: \ZbModules ${MODULESVERSION} | LKM ${LKMVERSION}\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Loader\Zn"
  TEXT+="\n   Config | Build: \Zb${CONFDONE} | ${BUILDDONE}\Zn"
  TEXT+="\n   Config Version: \Zb${CONFIGVER}\Zn"
  TEXT+="\n\Z4>> DSM ${PRODUCTVER}: ${MODEL}\Zn"
  TEXT+="\n   Kernel | LKM: \Zb${KVER} | ${LKM}\Zn"
  TEXT+="\n   Platform | DeviceTree: \Zb${PLATFORM} | ${DT}\Zn"
  TEXT+="\n   Arc Patch | Kernelload: \Zb${ARCPATCH} | ${KERNELLOAD}\Zn"
  TEXT+="\n   Directboot: \Zb${DIRECTBOOT}\Zn"
  TEXT+="\n\Z4>> Addons | Modules\Zn"
  TEXT+="\n   Addons selected: \Zb${ADDONSINFO}\Zn"
  TEXT+="\n   Modules loaded: \Zb${MODULESINFO}\Zn"
  TEXT+="\n\Z4>> Settings\Zn"
  TEXT+="\n   MacSys: \Zb${MACSYS}\Zn"
  TEXT+="\n   IPv6: \Zb${ARCIPV6}\Zn"
  TEXT+="\n   Offline Mode: \Zb${OFFLINE}\Zn"
  TEXT+="\n   Sort Drives: \Zb${HDDSORT}\Zn"
  TEXT+="\n   VMM/KVM Support: \Zb${KVMSUPPORT}\Zn"
  if [[ "${REMAP}" = "acports" || "${REMAP}" = "maxports" ]]; then
    TEXT+="\n   SataPortMap | DiskIdxMap: \Zb${PORTMAP} | ${DISKMAP}\Zn"
  elif [ "${REMAP}" = "remap" ]; then
    TEXT+="\n   SataRemap: \Zb${PORTMAP}\Zn"
  elif [ "${REMAP}" = "user" ]; then
    TEXT+="\n   PortMap: \Zb"User"\Zn"
  fi
  if [ ! "${DT}" = "true" ]; then
    TEXT+="\n   USB Mount: \Zb${USBMOUNT}\Zn"
  fi
  TEXT+="\n"
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS
  TEXT+="\n\Z4> Storage\Zn"
  # Get Information for Sata Controller
  NUMPORTS=0
  if [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
    TEXT+="\n  SATA Controller:\n"
    for PCI in $(lspci -d ::106 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      TEXT+="\Zb  ${NAME}\Zn\n  Ports: "
      PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      for P in ${PORTS}; do
        if lsscsi -b | grep -v - | grep -q "\[${P}:"; then
          DUMMY="$([ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ] && echo 1 || echo 2)"
          if [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ]; then
            TEXT+="\Z1\Zb$(printf "%02d" ${P})\Zn "
          else
            TEXT+="\Z2\Zb$(printf "%02d" ${P})\Zn "
            NUMPORTS=$((${NUMPORTS} + 1))
          fi
        else
          TEXT+="\Zb$(printf "%02d" ${P})\Zn "
        fi
      done
      TEXT+="\n  Ports with color \Z1\Zbred\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected.\n"
    done
  fi
  if [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
    TEXT+="\n  SAS Controller:\n"
    for PCI in $(lspci -d ::107 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::104 | wc -l) -gt 0 ]; then
    TEXT+="\n  Raid/SCSI Controller:\n"
    for PCI in $(lspci -d ::104 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [[ -d "/sys/class/scsi_host" && $(ls -l /sys/class/scsi_host | grep usb | wc -l) -gt 0 ]]; then
    TEXT+="\n USB Controller:\n"
    for PCI in $(lspci -d ::c03 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [[ -d "/sys/class/mmc_host" && $(ls -l /sys/class/mmc_host | grep mmc_host | wc -l) -gt 0 ]]; then
    TEXT+="\n MMC Controller:\n"
    for PCI in $(lspci -d ::805 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORTNUM=$(ls -l /sys/class/mmc_host | grep "${PCI}" | wc -l)
      PORTNUM=$(ls -l /sys/block/mmc* | grep "${PCI}" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::108 | wc -l) -gt 0 ]; then
    TEXT+="\n NVMe Controller:\n"
    for PCI in $(lspci -d ::108 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/nvme | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[N:${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  TEXT+="\n  Drives total: \Zb${NUMPORTS}\Zn"
  dialog --backtitle "$(backtitle)" --colors --title "Sysinfo" \
    --help-button --help-label "Networkdiag" --extra-button --extra-label "Full Sysinfo" \
    --msgbox "${TEXT}" 0 0
  RET=$?
  case ${RET} in
  0) # ok-button
    return 0
    ;;
  2) # help-button
    networkdiag
    ;;
  3) # extra-button
    fullsysinfo
    ;;
  255) # ESC
    return 0
    ;;
  esac
}

function fullsysinfo() {
  # Checks for Systeminfo Menu
  CPUINFO="$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')"
  # Check if machine has EFI
  [ -d /sys/firmware/efi ] && BOOTSYS="UEFI" || BOOTSYS="Legacy"
  VENDOR="$(dmidecode -s system-product-name)"
  BOARD="$(dmidecode -s baseboard-product-name)"
  ETHX=$(ls /sys/class/net/ | grep -v lo || true)
  NIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    DT="$(readModelKey "${MODEL}" "dt")"
    KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
    ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
    ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
    REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
    if [[ "${REMAP}" = "acports" || "${REMAP}" = "maxports" ]]; then
      PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
      DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" = "remap" ]; then
      PORTMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
    fi
  fi
  DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
  USBMOUNT="$(readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
  MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  ARCIPV6="$(readConfigKey "arc.ipv6" "${USER_CONFIG_FILE}")"
  CONFIGVER="$(readConfigKey "arc.version" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
  KVMSUPPORT="$(readConfigKey "arc.kvm" "${USER_CONFIG_FILE}")"
  MODULESINFO="$(lsmod | awk -F' ' '{print $1}' | grep -v 'Module')"
  MODULESVERSION="$(cat "${MODULES_PATH}/VERSION")"
  ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")"
  LKMVERSION="$(cat "${LKM_PATH}/VERSION")"
  CONFIGSVERSION="$(cat "${MODEL_CONFIG_PATH}/VERSION")"
  PATCHESVERSION="$(cat "${PATCH_PATH}/VERSION")"
  TEXT=""
  # Print System Informations
  TEXT+="\nSystem: ${MACHINE} | ${BOOTSYS}"
  TEXT+="\nVendor | Board: ${VENDOR} | ${BOARD}"
  TEXT+="\nCPU: ${CPUINFO}"
  TEXT+="\nMemory: $((${RAMTOTAL} / 1024))GB"
  TEXT+="\n"
  TEXT+="\nNetwork: ${NIC} NIC"
  for ETH in ${ETHX}; do
    IP=""
    STATICIP="$(readConfigKey "static.${ETH}" "${USER_CONFIG_FILE}")"
    DRIVER=$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    MAC="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
    COUNT=0
    while true; do
      if [ "${STATICIP}" = "true" ]; then
        IP="$(readConfigKey "ip.${ETH}" "${USER_CONFIG_FILE}")"
        MSG="STATIC"
      else
        IP="$(getIP ${ETH})"
        MSG="DHCP"
      fi
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${ETH} | grep "Speed:" | awk '{print $2}')
        TEXT+="\n${DRIVER} (${SPEED} | ${MSG}) IP: ${IP} | Mac: ${MAC}"
        break
      fi
      if [ ${COUNT} -gt 3 ]; then
        TEXT+="\n${DRIVER} IP: TIMEOUT | MAC: ${MAC}"
        break
      fi
      sleep 3
      if ethtool ${ETH} | grep 'Link detected' | grep -q 'no'; then
        TEXT+="\n${DRIVER} IP: NOT CONNECTED | MAC: ${MAC}"
        break
      fi
      COUNT=$((${COUNT} + 3))
    done
  done
  TEXT+="\n"
  TEXT+="\nNIC:\n"
  TEXT+="$(lspci -d ::200 -nnk)"
  # Print Config Informations
  TEXT+="\n"
  TEXT+="\nArc: ${ARC_VERSION}"
  TEXT+="\nSubversion Loader: Addons ${ADDONSVERSION} | Configs ${CONFIGSVERSION} | Patches ${PATCHESVERSION}"
  TEXT+="\nSubversion DSM: Modules ${MODULESVERSION} | LKM ${LKMVERSION}"
  TEXT+="\n"
  TEXT+="\nLoader"
  TEXT+="\nConfig | Build: ${CONFDONE} | ${BUILDDONE}"
  TEXT+="\nConfig Version: ${CONFIGVER}"
  TEXT+="\n"
  TEXT+="\nDSM ${PRODUCTVER}: ${MODEL}"
  TEXT+="\nKernel | LKM: ${KVER} | ${LKM}"
  TEXT+="\nPlatform | DeviceTree: ${PLATFORM} | ${DT}"
  TEXT+="\nArc Patch | Kernelload: ${ARCPATCH} | ${KERNELLOAD}"
  TEXT+="\nDirectboot: ${DIRECTBOOT}"
  TEXT+="\n"
  TEXT+="\nAddons selected:"
  TEXT+="\n${ADDONSINFO}"
  TEXT+="\n"
  TEXT+="\nModules loaded:"
  TEXT+="\n${MODULESINFO}"
  TEXT+="\n"
  TEXT+="\nSettings"
  TEXT+="\nMacSys: ${MACSYS}"
  TEXT+="\nIPv6: ${ARCIPV6}"
  TEXT+="\nOffline Mode: ${OFFLINE}"
  TEXT+="\nSort Drives: ${HDDSORT}"
  TEXT+="\nVMM/KVM Support: ${KVMSUPPORT}"
  if [[ "${REMAP}" = "acports" || "${REMAP}" = "maxports" ]]; then
    TEXT+="\nSataPortMap | DiskIdxMap: ${PORTMAP} | ${DISKMAP}"
  elif [ "${REMAP}" = "remap" ]; then
    TEXT+="\nSataRemap: ${PORTMAP}"
  elif [ "${REMAP}" = "user" ]; then
    TEXT+="\nPortMap: "User""
  fi
  if [ ! "${DT}" = "true" ]; then
    TEXT+="\nUSB Mount: ${USBMOUNT}"
  fi
  TEXT+="\n"
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS
  TEXT+="\nStorage"
  # Get Information for Sata Controller
  NUMPORTS=0
  if [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
    TEXT+="\nSATA Controller:\n"
    for PCI in $(lspci -d ::106 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      TEXT+="${NAME}\nPorts in Use: "
      PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      for P in ${PORTS}; do
        if lsscsi -b | grep -v - | grep -q "\[${P}:"; then
          DUMMY="$([ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ] && echo 1 || echo 2)"
          if [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ]; then
            TEXT+=""
          else
            TEXT+="$(printf "%02d" ${P}) "
            NUMPORTS=$((${NUMPORTS} + 1))
          fi
        fi
      done
      TEXT+="\n"
    done
  fi
  if [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
    TEXT+="\nSAS Controller:\n"
    for PCI in $(lspci -d ::107 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="${NAME}\nDrives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::104 | wc -l) -gt 0 ]; then
    TEXT+="\nRaid/SCSI Controller:\n"
    for PCI in $(lspci -d ::104 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="${NAME}\nDrives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [[ -d "/sys/class/scsi_host" && $(ls -l /sys/class/scsi_host | grep usb | wc -l) -gt 0 ]]; then
    TEXT+="\nUSB Controller:\n"
    for PCI in $(lspci -d ::c03 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      TEXT+="${NAME}\nDrives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [[ -d "/sys/class/mmc_host" && $(ls -l /sys/class/mmc_host | grep mmc_host | wc -l) -gt 0 ]]; then
    TEXT+="\nMMC Controller:\n"
    for PCI in $(lspci -d ::805 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORTNUM=$(ls -l /sys/class/mmc_host | grep "${PCI}" | wc -l)
      PORTNUM=$(ls -l /sys/block/mmc* | grep "${PCI}" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      TEXT+="${NAME}\nDrives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::108 | wc -l) -gt 0 ]; then
    TEXT+="\nNVMe Controller:\n"
    for PCI in $(lspci -d ::108 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/nvme | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[N:${PORT}:" | wc -l)
      TEXT+="${NAME}\nDrives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  TEXT+="\nDrives total: ${NUMPORTS}"
  [ -f "${TMP_PATH}/diag" ] && rm -f "${TMP_PATH}/diag"
  echo -e "${TEXT}" >"${TMP_PATH}/diag"
  dialog --backtitle "$(backtitle)" --colors --title "Full Sysinfo" \
    --extra-button --extra-label "Upload" --no-cancel --textbox "${TMP_PATH}/diag" 0 0
  RET=$?
  case ${RET} in
  0) # ok-button
    return 0
    ;;
  3) # extra-button
    if [ -f "${TMP_PATH}/diag" ]; then
      GENHASH="$(cat "${TMP_PATH}/diag" | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-)"
      dialog --backtitle "$(backtitle)" --title "Sysinfo Upload" --msgbox "Your Code: ${GENHASH}" 0 0
    else
      dialog --backtitle "$(backtitle)" --title "Sysinfo Upload" --msgbox "No Diag File found!" 0 0
    fi
    ;;
  255) # ESC
    return 0
    ;;
  esac
}

###############################################################################
# Shows Networkdiag to user
function networkdiag() {
  MSG=""
  ETHX=$(ls /sys/class/net/ | grep -v lo) || true
  for ETH in ${ETHX}; do
    MSG+="Interface: ${ETH}\n"
    addr=$(getIP ${ETH})
    netmask=$(ifconfig ${ETH} | grep inet | grep 255 | awk '{print $4}' | cut -f2 -d':')
    MSG+="IP Address: ${addr}\n"
    MSG+="Netmask: ${netmask}\n"
    MSG+="\n"
  done
  gateway=$(route -n | grep 'UG[ \t]' | awk '{print $2}' | head -n 1)
  MSG+="Gateway: ${gateway}\n"
  dnsserver="$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')"
  MSG+="DNS Server: ${dnsserver}\n"
  MSG+="\n"
  websites=("google.com" "github.com" "auxxxilium.tech")
  for website in "${websites[@]}"; do
    if ping -c 1 "${website}" &> /dev/null; then
      MSG+="Connection to ${website} is successful.\n"
    else
      MSG+="Connection to ${website} failed.\n"
    fi
  done
  if [ "${CONFDONE}" = "true" ]; then
    GITHUBAPI="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
    if [[ $? -ne 0 || -z "${GITHUBAPI}" ]]; then
      MSG+="\nGithub API not reachable!"
    else
      MSG+="\nGithub API reachable!"
    fi
    SYNOAPI="$(curl -skL "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}" | jq -r '.info.system.detail[0].items[0].files[0].url')"
    if [[ $? -ne 0 || -z "${SYNOAPI}" ]]; then
      MSG+="\nSyno API not reachable!"
    else
      MSG+="\nSyno API reachable!"
    fi
  else
    MSG+="\nFor API Checks you need to configure Loader first!"
  fi
  dialog --backtitle "$(backtitle)" --colors --title "Networkdiag" \
    --msgbox "${MSG}" 0 0
}

###############################################################################
# Shows Systeminfo to user
function credits() {
  # Print Credits Informations
  TEXT=""
  TEXT+="\n\Z4> Arc Loader:\Zn"
  TEXT+="\n  Github: \Zbhttps://github.com/AuxXxilium\Zn"
  TEXT+="\n  Website: \Zbhttps://auxxxilium.tech\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Developer:\Zn"
  TEXT+="\n   Arc Loader: \ZbAuxXxilium\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Based on:\Zn"
  TEXT+="\n   Redpill: \ZbTTG / Pocopico\Zn"
  TEXT+="\n   ARPL: \Zbfbelavenuto / wjz304\Zn"
  TEXT+="\n   NVMe Scripts: \Zb007revad\Zn"
  TEXT+="\n   NVMe Install: \ZbKodeCR\Zn"
  TEXT+="\n   System: \ZbBuildroot 2023.02.x\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Note:\Zn"
  TEXT+="\n   Arc and all Parts are OpenSource."
  TEXT+="\n   Commercial use is not permitted!"
  TEXT+="\n   This Loader is FREE and it is forbidden"
  TEXT+="\n   to sell Arc or Parts of this."
  TEXT+="\n"
  dialog --backtitle "$(backtitle)" --colors --title "Credits" \
    --msgbox "${TEXT}" 0 0
}

###############################################################################
# allow setting Static IP for Loader
function staticIPMenu() {
  # Get Amount of NIC
  ETHX=$(ls /sys/class/net/ | grep -v lo) || true
  for ETH in ${ETHX}; do
    STATIC="$(readConfigKey "static.${ETH}" "${USER_CONFIG_FILE}")"
    DRIVER=$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    TEXT=""
    TEXT+="This Feature allow you to set a StaticIP for the Loader.\n"
    TEXT+="Actual Settings are:\n"
    TEXT+="\nNIC: ${ETH} (${DRIVER})\n"
    TEXT+="StaticIP: ${STATIC}\n"
    if [ "${STATIC}" = "true" ]; then
      IPADDR="$(readConfigKey "ip.${ETH}" "${USER_CONFIG_FILE}")"
      NETMASK="$(readConfigKey "netmask.${ETH}" "${USER_CONFIG_FILE}")"
      TEXT+="IP: ${IPADDR}\n"
      TEXT+="NETMASK: ${NETMASK}\n"
    else
      IPADDR=""
      NETMASK=""
    fi
    TEXT+=""
    TEXT+="Do you want to change Config?"
    dialog --backtitle "$(backtitle)" --title "DHCP/StaticIP" \
        --yesno "${TEXT}" 0 0
    [ $? -ne 0 ] && continue
    dialog --clear --backtitle "$(backtitle)" --title "DHCP/StaticIP" \
      --menu "DHCP or STATIC?" 0 0 0 \
        1 "DHCP" \
        2 "STATIC" \
      2>"${TMP_PATH}/opts"
    opts="$(<"${TMP_PATH}/opts")"
    [ -z "${opts}" ] && continue
    if [ ${opts} -eq 1 ]; then
      writeConfigKey "static.${ETH}" "false" "${USER_CONFIG_FILE}"
    elif [ ${opts} -eq 2 ]; then
      dialog --backtitle "$(backtitle)" --title "DHCP/StaticIP" \
        --inputbox "Type a Static IP\nEq: 192.168.0.1" 0 0 "${IPADDR}" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      IPADDR="$(<"${TMP_PATH}/resp")"
      dialog --backtitle "$(backtitle)" --title "DHCP/StaticIP" \
        --inputbox "Type a Netmask\nEq: 24" 0 0 "${NETMASK}" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      NETMASK="$(<"${TMP_PATH}/resp")"
      writeConfigKey "ip.${ETH}" "${IPADDR}" "${USER_CONFIG_FILE}"
      writeConfigKey "netmask.${ETH}" "${NETMASK}" "${USER_CONFIG_FILE}"
      writeConfigKey "static.${ETH}" "true" "${USER_CONFIG_FILE}"
      #NETMASK=$(convert_netmask "${NETMASK}")
      ip addr add ${IPADDR}/${NETMASK} dev ${ETH}
    fi
  done
  dialog --backtitle "$(backtitle)" --title "DHCP/StaticIP" \
  --msgbox "Settings written and enabled.\nThis will be not applied to DSM." 5 50
}

###############################################################################
# allow downgrade dsm version
function downgradeMenu() {
  TEXT=""
  TEXT+="This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n"
  TEXT+="Therefore, please insert all disks before continuing.\n"
  TEXT+="Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?"
  dialog --backtitle "$(backtitle)" --title "Allow downgrade installation" \
      --yesno "${TEXT}" 0 0
  [ $? -ne 0 ] && return 1
  (
    mkdir -p "${TMP_PATH}/sdX1"
    for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
      mount "${I}" "${TMP_PATH}/sdX1"
      [ -f "${TMP_PATH}/sdX1/etc/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc/VERSION"
      [ -f "${TMP_PATH}/sdX1/etc.defaults/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc.defaults/VERSION"
      sync
      umount "${I}"
    done
    rm -rf "${TMP_PATH}/sdX1"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Allow downgrade installation" \
      --progressbox "Removing ..." 20 70
  TEXT="Remove VERSION file for all disks completed."
  dialog --backtitle "$(backtitle)" --colors --aspect 18 \
    --msgbox "${TEXT}" 0 0
}

###############################################################################
# Reset DSM password
function resetPassword() {
  rm -f "${TMP_PATH}/menu"
  mkdir -p "${TMP_PATH}/sdX1"
  for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
    mount ${I} "${TMP_PATH}/sdX1"
    if [ -f "${TMP_PATH}/sdX1/etc/shadow" ]; then
      for U in $(cat "${TMP_PATH}/sdX1/etc/shadow" | awk -F ':' '{if ($2 != "*" && $2 != "!!") {print $1;}}'); do
        grep -q "status=on" "${TMP_PATH}/sdX1/usr/syno/etc/packages/SecureSignIn/preference/${U}/method.config" 2>/dev/nulll
        [ $? -eq 0 ] && SS="SecureSignIn" || SS="            "
        printf "\"%-36s %-16s\"\n" "${U}" "${SS}" >>"${TMP_PATH}/menu"
      done
    fi
    umount "${I}"
    [ -f "${TMP_PATH}/menu" ] && break
  done
  rm -rf "${TMP_PATH}/sdX1"
  if [ ! -f "${TMP_PATH}/menu" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
      --msgbox "The installed Syno system not found in the currently inserted disks!" 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
    --no-items --menu "Choose a User" 0 0 0  --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  USER="$(cat "${TMP_PATH}/resp" | awk '{print $1}')"
  [ -z "${USER}" ] && return
  while true; do
    dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
      --inputbox "Type a new Password for User ${USER}" 0 70 "${CMDLINE[${NAME}]}" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break 2
    VALUE="$(<"${TMP_PATH}/resp")"
    [ -n "${VALUE}" ] && break
    dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
      --msgbox "Invalid Password" 0 0
  done
  NEWPASSWD="$(python -c "from passlib.hash import sha512_crypt;pw=\"${VALUE}\";print(sha512_crypt.using(rounds=5000).hash(pw))")"
  (
    mkdir -p "${TMP_PATH}/sdX1"
    for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
      mount "${I}" "${TMP_PATH}/sdX1"
      OLDPASSWD="$(cat "${TMP_PATH}/sdX1/etc/shadow" | grep "^${USER}:" | awk -F ':' '{print $2}')"
      [[ -n "${NEWPASSWD}" && -n "${OLDPASSWD}" ]] && sed -i "s|${OLDPASSWD}|${NEWPASSWD}|g" "${TMP_PATH}/sdX1/etc/shadow"
      sed -i "s|status=on|status=off|g" "${TMP_PATH}/sdX1/usr/syno/etc/packages/SecureSignIn/preference/${USER}/method.config" 2>/dev/null
      sync
      umount "${I}"
    done
    rm -rf "${TMP_PATH}/sdX1"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
    --progressbox "Resetting ..." 20 100
  dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" --aspect 18 \
    --msgbox "Password reset completed." 0 0
}

###############################################################################
# modify bootipwaittime
function bootipwaittime() {
  ITEMS="$(echo -e "0 \n5 \n10 \n20 \n30 \n60 \n")"
  dialog --backtitle "$(backtitle)" --colors --title "Boot IP Waittime" \
    --default-item "${BOOTIPWAIT}" --no-items --menu "Choose Waittime(seconds)\nto get an IP" 0 0 0 ${ITEMS} \
    2>"${TMP_PATH}/resp"
  resp="$(cat ${TMP_PATH}/resp 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  BOOTIPWAIT=${resp}
  writeConfigKey "arc.bootipwait" "${BOOTIPWAIT}" "${USER_CONFIG_FILE}"
}

###############################################################################
# allow user to save modifications to disk
function saveMenu() {
  dialog --backtitle "$(backtitle)" --title "Save to Disk" \
      --yesno "Warning:\nDo not terminate midway, otherwise it may cause damage to the arc. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return 1
  dialog --backtitle "$(backtitle)" --title "Save to Disk" \
      --infobox "Saving ..." 0 0
  RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
  mkdir -p "${RDXZ_PATH}"
  (cd "${RDXZ_PATH}"; xz -dc <"${PART3_PATH}/initrd-arc" | cpio -idm) >/dev/null 2>&1 || true
  rm -rf "${RDXZ_PATH}/opt/arc"
  cp -Rf "/opt" "${RDXZ_PATH}"
  (cd "${RDXZ_PATH}"; find . 2>/dev/null | cpio -o -H newc -R root:root | xz --check=crc32 >"${PART3_PATH}/initrd-arc") || true
  rm -rf "${RDXZ_PATH}"
  dialog --backtitle "$(backtitle)" --colors --aspect 18 \
    --msgbox "Save to Disk is complete." 0 0
}

###############################################################################
# let user format disks from inside arc
function formatdisks() {
  rm -f "${TMP_PATH}/opts"
  while read -r POSITION NAME; do
    [[ -z "${POSITION}" || -z "${NAME}" ]] && continue
    echo "${POSITION}" | grep -q "${LOADER_DISK}" && continue
    echo "\"${POSITION}\" \"${NAME}\" \"off\"" >>"${TMP_PATH}/opts"
  done < <(ls -l /dev/disk/by-id/ | sed 's|../..|/dev|g' | grep -E "/dev/sd|/dev/mmc|/dev/nvme" | awk -F' ' '{print $NF" "$(NF-2)}' | sort -uk 1,1)
  if [ ! -f "${TMP_PATH}/opts" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
      --msgbox "No Disk found!" 0 0
    return 1
  fi
  dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --checklist "" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  RESP="$(<"${TMP_PATH}/resp")"
  [ -z "${RESP}" ] && return 1
  dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --yesno "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return 1
  RAID=$(ls /dev/md* | wc -l)
  if [ ${RAID} -gt 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
      --yesno "Warning:\nThe current hds is in raid, do you still want to format them?" 0 0
    [ $? -ne 0 ] && return 1
    for I in $(ls /dev/md*); do
      mdadm -S "${I}"
    done
  fi
  (
    for I in ${RESP}; do
      echo -e ">>> Formatting: ${I}"
      echo y | mkfs.ext4 -T largefile4 "${I}" &>/dev/null
      echo -e ">>> Done\n"
    done
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --progressbox "Doing the Magic..." 20 70
  dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --msgbox "Formatting is complete." 0 0
}

###############################################################################
# let user delete Loader Boot Files
function resetLoader() {
  if [[ -f "${ORI_ZIMAGE_FILE}" || -f "${ORI_RDGZ_FILE}" || -f "${MOD_ZIMAGE_FILE}" || -f "${MOD_RDGZ_FILE}" ]]; then
    # Clean old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  fi
  [ -d "${UNTAR_PAT_PATH}" ] && rm -rf "${UNTAR_PAT_PATH}"
  [ -f "${USER_CONFIG_FILE}" ] && rm -f "${USER_CONFIG_FILE}"
  [ ! -f "${USER_CONFIG_FILE}" ] && touch "${USER_CONFIG_FILE}"
  initConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
  initConfigKey "model" "" "${USER_CONFIG_FILE}"
  initConfigKey "productver" "" "${USER_CONFIG_FILE}"
  initConfigKey "layout" "qwertz" "${USER_CONFIG_FILE}"
  initConfigKey "keymap" "de" "${USER_CONFIG_FILE}"
  initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
  initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
  initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
  initConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
  initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "arc" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.sn" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.ipv6" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.emmcboot" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.offline" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.directboot" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.bootipwait" "20" "${USER_CONFIG_FILE}"
  initConfigKey "arc.kernelload" "power" "${USER_CONFIG_FILE}"
  initConfigKey "arc.kernelpanic" "5" "${USER_CONFIG_FILE}"
  initConfigKey "arc.macsys" "hardware" "${USER_CONFIG_FILE}"
  initConfigKey "arc.odp" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.modulescopy" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.hddsort" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.kernel" "official" "${USER_CONFIG_FILE}"
  initConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
  initConfigKey "ip" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "netmask" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "mac" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "static" "{}" "${USER_CONFIG_FILE}"
  # KVM Check
  if grep -q -E "(vmx|svm)" /proc/cpuinfo; then
    writeConfigKey "arc.kvm" "true" "${USER_CONFIG_FILE}"
  else
    writeConfigKey "arc.kvm" "false" "${USER_CONFIG_FILE}"
  fi
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    dialog --backtitle "$(backtitle)" --title "Reset Loader" --aspect 18 \
    --yesno "Reset successful.\nReboot?" 0 0
  [ $? -ne 0 ] && return
  exec reboot
}

###############################################################################
# let user edit the grub.cfg
function editGrubCfg() {
  while true; do
    dialog --backtitle "$(backtitle)" --colors --title "Edit grub.cfg with caution" \
      --editbox "${GRUB_PATH}/grub.cfg" 0 0 2>"${TMP_PATH}/usergrub.cfg"
    [ $? -ne 0 ] && return
    mv -f "${TMP_PATH}/usergrub.cfg" "${GRUB_PATH}/grub.cfg"
    break
  done
}

###############################################################################
# Grep Logs from dbgutils
function greplogs() {
  dialog --backtitle "$(backtitle)" --colors --title "Grep Logs" \
    --infobox "Copy Log Files." 3 20
  sleep 2
  tar -cfz "${TMP_PATH}/log.tar.gz" "${PART1_PATH}/logs" >/dev/null 2>&1
  dialog --backtitle "$(backtitle)" --colors --title "Grep Logs" \
    --msgbox "Logs can be found at /tmp/log.tar.gz" 5 40
}

###############################################################################
# Calls boot.sh to boot into DSM Recovery
function juniorboot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  [ "${BUILDDONE}" = "false" ] && dialog --backtitle "$(backtitle)" --title "Alert" \
    --yesno "Config changed, please build Loader first." 0 0
  if [ $? -eq 0 ]; then
    make
  fi
  grub-editenv ${GRUB_PATH}/grubenv set next_entry="junior"
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Booting DSM Recovery...\nPlease stay patient!" 4 30
  sleep 2
  exec reboot
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  [ "${BUILDDONE}" = "false" ] && dialog --backtitle "$(backtitle)" --title "Alert" \
    --yesno "Config changed, you need to rebuild the Loader?" 0 0
  if [ $? -eq 0 ]; then
    make
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Booting DSM...\nPlease stay patient!" 4 25
  sleep 2
  exec reboot
}

###############################################################################
###############################################################################
# Main loop
[ "${BUILDDONE}" = "true" ] && NEXT="3" || NEXT="1"
while true; do
  echo "= \"\Z4========== Main ==========\Zn \" "                                            >"${TMP_PATH}/menu"
  echo "1 \"Choose Model \" "                                                               >>"${TMP_PATH}/menu"
  if [ "${CONFDONE}" = "true" ]; then
    echo "2 \"Build Loader \" "                                                             >>"${TMP_PATH}/menu"
  fi
  if [ "${BUILDDONE}" = "true" ]; then
    echo "3 \"Boot Loader \" "                                                              >>"${TMP_PATH}/menu"
  fi
  echo "= \"\Z4========== Info ==========\Zn \" "                                           >>"${TMP_PATH}/menu"
  echo "a \"Sysinfo \" "                                                                    >>"${TMP_PATH}/menu"
  echo "= \"\Z4========= System =========\Zn \" "                                           >>"${TMP_PATH}/menu"
  if [ "${CONFDONE}" = "true" ]; then
    if [ "${ARCOPTS}" = "true" ]; then
      echo "4 \"\Z1Hide Arc Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    else
      echo "4 \"\Z1Show Arc Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    fi
    if [ "${ARCOPTS}" = "true" ]; then
      echo "= \"\Z4========== Arc ==========\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "b \"Addons \" "                                                                 >>"${TMP_PATH}/menu"
      echo "d \"Modules \" "                                                                >>"${TMP_PATH}/menu"
      echo "e \"DSM Version \" "                                                            >>"${TMP_PATH}/menu"
      echo "p \"Arc Patch Settings \" "                                                     >>"${TMP_PATH}/menu"
      echo "N \"Network Config \" "                                                         >>"${TMP_PATH}/menu"
      if [ "${DT}" = "false" ]; then
        echo "S \"Storage Map \" "                                                          >>"${TMP_PATH}/menu"
        echo "U \"USB Mount: \Z4${USBMOUNT}\Zn \" "                                         >>"${TMP_PATH}/menu"
        echo "W \"Force USB Mount \" "                                                      >>"${TMP_PATH}/menu"
      fi
      echo "P \"Custom StoragePanel \" "                                                    >>"${TMP_PATH}/menu"
      echo "D \"Loader DHCP/StaticIP \" "                                                   >>"${TMP_PATH}/menu"
    fi
    if [ "${ADVOPTS}" = "true" ]; then
      echo "5 \"\Z1Hide Advanced Options\Zn \" "                                            >>"${TMP_PATH}/menu"
    else
      echo "5 \"\Z1Show Advanced Options\Zn \" "                                            >>"${TMP_PATH}/menu"
    fi
    if [ "${ADVOPTS}" = "true" ]; then
      echo "= \"\Z4======== Advanced =======\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "j \"Cmdline \" "                                                                >>"${TMP_PATH}/menu"
      echo "k \"Synoinfo \" "                                                               >>"${TMP_PATH}/menu"
      echo "l \"Edit User Config \" "                                                       >>"${TMP_PATH}/menu"
    fi
    if [ "${BOOTOPTS}" = "true" ]; then
      echo "6 \"\Z1Hide Boot Options\Zn \" "                                                >>"${TMP_PATH}/menu"
    else
      echo "6 \"\Z1Show Boot Options\Zn \" "                                                >>"${TMP_PATH}/menu"
    fi
    if [ "${BOOTOPTS}" = "true" ]; then
      echo "= \"\Z4========== Boot =========\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "m \"DSM Kernelload: \Z4${KERNELLOAD}\Zn \" "                                    >>"${TMP_PATH}/menu"
      if [ "${DIRECTBOOT}" = "false" ]; then
        echo "i \"Boot IP Waittime: \Z4${BOOTIPWAIT}\Zn \" "                                >>"${TMP_PATH}/menu"
      fi
      echo "q \"Directboot: \Z4${DIRECTBOOT}\Zn \" "                                        >>"${TMP_PATH}/menu"
    fi
    if [ "${DSMOPTS}" = "true" ]; then
      echo "7 \"\Z1Hide DSM Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    else
      echo "7 \"\Z1Show DSM Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    fi
    if [ "${DSMOPTS}" = "true" ]; then
      echo "= \"\Z4========== DSM ==========\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "s \"Allow DSM Downgrade \" "                                                    >>"${TMP_PATH}/menu"
      echo "t \"Change DSM Password \" "                                                    >>"${TMP_PATH}/menu"
      if [ "${MODEL}" = "SA6400" ]; then
        echo "K \"Kernel: \Z4${KERNEL}\Zn \" "                                              >>"${TMP_PATH}/menu"
      fi
      if [ ! "${MODEL}" = "SA6400" ]; then
        echo "M \"Copy Modules to DSM: \Z4${MODULESCOPY}\Zn \" "                            >>"${TMP_PATH}/menu"
      fi
      echo "O \"Official Driver Priority: \Z4${ODP}\Zn \" "                                 >>"${TMP_PATH}/menu"
      echo "H \"Sort Drives: \Z4${HDDSORT}\Zn \" "                                          >>"${TMP_PATH}/menu"
      echo "V \"VMM/KVM Support: \Z4${KVMSUPPORT}\Zn \" "                                   >>"${TMP_PATH}/menu"
      echo "c \"IPv6 Support: \Z4${ARCIPV6}\Zn \" "                                         >>"${TMP_PATH}/menu"
      echo "E \"eMMC Boot Support: \Z4${EMMCBOOT}\Zn \" "                                   >>"${TMP_PATH}/menu"
      echo "o \"Switch MacSys: \Z4${MACSYS}\Zn \" "                                         >>"${TMP_PATH}/menu"
      echo "u \"Switch LKM version: \Z4${LKM}\Zn \" "                                       >>"${TMP_PATH}/menu"
    fi
  fi
  if [ "${DEVOPTS}" = "true" ]; then
    echo "8 \"\Z1Hide Dev Options\Zn \" "                                                   >>"${TMP_PATH}/menu"
  else
    echo "8 \"\Z1Show Dev Options\Zn \" "                                                   >>"${TMP_PATH}/menu"
  fi
  if [ "${DEVOPTS}" = "true" ]; then
    echo "= \"\Z4========== Dev ===========\Zn \" "                                         >>"${TMP_PATH}/menu"
    echo "v \"Save Modifications to Disk \" "                                               >>"${TMP_PATH}/menu"
    echo "n \"Edit Grub Config \" "                                                         >>"${TMP_PATH}/menu"
    echo "w \"Reset Loader \" "                                                             >>"${TMP_PATH}/menu"
    echo "J \"DSM force Reinstall \" "                                                      >>"${TMP_PATH}/menu"
    echo "F \"\Z1Format Sata/NVMe Disk\Zn \" "                                              >>"${TMP_PATH}/menu"
    echo "L \"Grep Logs from dbgutils \" "                                                  >>"${TMP_PATH}/menu"
  fi
  echo "= \"\Z4====== Misc Settings =====\Zn \" "                                           >>"${TMP_PATH}/menu"
  echo "x \"Backup/Restore/Recovery \" "                                                    >>"${TMP_PATH}/menu"
  echo "9 \"Offline Mode: \Z4${OFFLINE}\Zn \" "                                             >>"${TMP_PATH}/menu"
  echo "y \"Choose a Keymap \" "                                                            >>"${TMP_PATH}/menu"
  if [ "${OFFLINE}" = "false" ]; then
    echo "z \"Update \" "                                                                   >>"${TMP_PATH}/menu"
  fi
  echo "0 \"Credits \" "                                                                    >>"${TMP_PATH}/menu"

  dialog --clear --default-item ${NEXT} --backtitle "$(backtitle)" --colors \
    --cancel-label "Exit" --title "Arc Menu" --menu "" 0 0 0 --file "${TMP_PATH}/menu" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && break
  case $(<"${TMP_PATH}/resp") in
    # Main Section
    1) arcMenu; NEXT="2" ;;
    2) make; NEXT="3" ;;
    3) boot && exit 0 || sleep 3 ;;
    # Info Section
    a) sysinfo; NEXT="a" ;;
    # System Section
    # Arc Section
    4) [ "${ARCOPTS}" = "true" ] && ARCOPTS='false' || ARCOPTS='true'
      ARCOPTS="${ARCOPTS}"
      NEXT="4"
      ;;
    b) addonMenu; NEXT="b" ;;
    d) modulesMenu; NEXT="d" ;;
    e) ONLYVERSION="true" && arcbuild; NEXT="e" ;;
    N) networkMenu; NEXT="N" ;;
    S) storageMenu; NEXT="S" ;;
    p) ONLYPATCH="true" && arcsettings; NEXT="p" ;;
    U) [ "${USBMOUNT}" = "true" ] && USBMOUNT='false' || USBMOUNT='true'
      writeConfigKey "arc.usbmount" "${USBMOUNT}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="U"
      ;;
    W) USBMOUNT='force'
      writeConfigKey "arc.usbmount" "force" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="W"
      ;;
    P) storagepanelMenu; NEXT="S" ;;
    # Advanced Section
    5) [ "${ADVOPTS}" = "true" ] && ADVOPTS='false' || ADVOPTS='true'
       ADVOPTS="${ADVOPTS}"
       NEXT="5"
       ;;
    j) cmdlineMenu; NEXT="j" ;;
    k) synoinfoMenu; NEXT="k" ;;
    l) editUserConfig; NEXT="l" ;;
    # Boot Section
    6) [ "${BOOTOPTS}" = "true" ] && BOOTOPTS='false' || BOOTOPTS='true'
      ARCOPTS="${BOOTOPTS}"
      NEXT="6"
      ;;
    m) [ "${KERNELLOAD}" = "kexec" ] && KERNELLOAD='power' || KERNELLOAD='kexec'
      writeConfigKey "arc.kernelload" "${KERNELLOAD}" "${USER_CONFIG_FILE}"
      NEXT="m"
      ;;
    i) bootipwaittime; NEXT="i" ;;
    q) [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
      grub-editenv "${GRUB_PATH}/grubenv" create
      writeConfigKey "arc.directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
      NEXT="q"
      ;;
    # DSM Section
    7) [ "${DSMOPTS}" = "true" ] && DSMOPTS='false' || DSMOPTS='true'
      DSMOPTS="${DSMOPTS}"
      NEXT="7"
      ;;
    s) downgradeMenu; NEXT="s" ;;
    t) resetPassword; NEXT="t" ;;
    K) [ "${KERNEL}" = "official" ] && KERNEL='custom' || KERNEL='official'
      writeConfigKey "arc.kernel" "${KERNEL}" "${USER_CONFIG_FILE}"
      if [ "${ODP}" = "true" ]; then
        ODP="false"
        writeConfigKey "arc.odp" "${ODP}" "${USER_CONFIG_FILE}"
      fi
      if [ "${MODULESCOPY}" = "true" ]; then
        MODULESCOPY="false"
        writeConfigKey "arc.modulescopy" "${MODULESCOPY}" "${USER_CONFIG_FILE}"
      fi
      PLATFORM="$(readModelKey "${MODEL}" "platform")"
      PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
      KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
      if [ "${PLATFORM}" = "epyc7002" ]; then
        KVER="${PRODUCTVER}-${KVER}"
      fi
      if [[ -n "${PLATFORM}" && -n "${KVER}" ]]; then
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        while read -r ID DESC; do
          writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
        done < <(getAllModules "${PLATFORM}" "${KVER}")
      fi
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="K"
      ;;
    O) [ "${ODP}" = "false" ] && ODP='true' || ODP='false'
      writeConfigKey "arc.odp" "${ODP}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="O"
      ;;
    M) [ "${MODULESCOPY}" = "false" ] && MODULESCOPY='true' || MODULESCOPY='false'
      writeConfigKey "arc.modulescopy" "${MODULESCOPY}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="M"
      ;;
    H) [ "${HDDSORT}" = "true" ] && HDDSORT='false' || HDDSORT='true'
      writeConfigKey "arc.hddsort" "${HDDSORT}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="H"
      ;;
    V) [ "${KVMSUPPORT}" = "true" ] && KVMSUPPORT='false' || KVMSUPPORT='true'
      writeConfigKey "arc.kvm" "${KVMSUPPORT}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="V"
      ;;
    c) [ "${ARCIPV6}" = "true" ] && ARCIPV6='false' || ARCIPV6='true'
      writeConfigKey "arc.ipv6" "${ARCIPV6}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="c"
      ;;
    E) [ "${EMMCBOOT}" = "true" ] && EMMCBOOT='false' || EMMCBOOT='true'
      if [ "${EMMCBOOT}" = "false" ]; then
        writeConfigKey "arc.emmcboot" "false" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.disk_swap" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.supportraid" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.support_emmc_boot" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.support_install_only_dev" "${USER_CONFIG_FILE}"
      elif [ "${EMMCBOOT}" = "true" ]; then
        writeConfigKey "arc.emmcboot" "true" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.disk_swap" "no" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.supportraid" "no" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_emmc_boot" "yes" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_install_only_dev" "yes" "${USER_CONFIG_FILE}"
      fi
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="E"
      ;;
    o) [ "${MACSYS}" = "hardware" ] && MACSYS='custom' || MACSYS='hardware'
      writeConfigKey "arc.macsys" "${MACSYS}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="o"
      ;;
    u) [ "${LKM}" = "prod" ] && LKM='dev' || LKM='prod'
      writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="u"
      ;;
    # Dev Section
    8) [ "${DEVOPTS}" = "true" ] && DEVOPTS='false' || DEVOPTS='true'
      DEVOPTS="${DEVOPTS}"
      NEXT="8"
      ;;
    v) saveMenu; NEXT="v" ;;
    n) editGrubCfg; NEXT="n" ;;
    w) resetLoader; NEXT="w" ;;
    J) juniorboot; NEXT="J" ;;
    F) formatdisks; NEXT="F" ;;
    L) greplogs; NEXT="L" ;;
    # Loader Settings
    x) backupMenu; NEXT="x" ;;
    9) [ "${OFFLINE}" = "true" ] && OFFLINE='false' || OFFLINE='true'
      OFFLINE="${OFFLINE}"
      writeConfigKey "arc.offline" "${OFFLINE}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="9"
      ;;
    y) keymapMenu; NEXT="y" ;;
    z) updateMenu; NEXT="z" ;;
    0) credits; NEXT="0" ;;
  esac
done
clear

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