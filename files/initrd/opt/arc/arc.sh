#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/modules.sh
. ${ARC_PATH}/include/storage.sh
. ${ARC_PATH}/include/network.sh
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

# Offline Mode check
OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
if [ "${OFFLINE}" = "false" ]; then
  if ping -c 1 "github.com" &> /dev/null; then
    writeConfigKey "arc.offline" "false" "${USER_CONFIG_FILE}"
  else
    writeConfigKey "arc.offline" "true" "${USER_CONFIG_FILE}"
  fi
fi

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
  BACKTITLE+="${MACHINE}(${BUS})"
  echo "${BACKTITLE}"
}

###############################################################################
# Model Selection
function arcModel() {
  # Loop menu
  RESTRICT=1
  FLGBETA=0
  dialog --backtitle "$(backtitle)" --title "Model" --aspect 18 \
    --infobox "Reading Models" 3 20
    echo -n "" >"${TMP_PATH}/modellist"
    while read -r M; do
      Y="$(readModelKey "${M}" "disks")"
      echo "${M} ${Y}" >>"${TMP_PATH}/modellist"
    done <<<$(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sed 's/.*\///; s/\.yml//')

    while true; do
      echo -n "" >"${TMP_PATH}/menu"
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
              break
            fi
          done
          if [ "${DT}" = "true" ] && [ "${EXTERNALCONTROLLER}" = "true" ]; then
            COMPATIBLE=0
          fi
          if [[ ${SATACONTROLLER} -eq 0 && "${EXTERNALCONTROLLER}" = "false" && "${M}" != "SA6400" ]]; then
            COMPATIBLE=0
          fi
        fi
        [ "${DT}" = "true" ] && DTO="DT" || DTO=""
        [ "${BETA}" = "true" ] && BETA="Beta" || BETA=""
        [ ${COMPATIBLE} -eq 1 ] && echo "${M} \"$(printf "\Zb%-7s\Zn \Zb%-6s\Zn \Zb%-13s\Zn \Zb%-3s\Zn \Zb%-7s\Zn \Zb%-4s\Zn" "${DISKS}" "${CPU}" "${PLATFORM}" "${DTO}" "${ARCAV}" "${BETA}")\" ">>"${TMP_PATH}/menu"
      done <<<$(cat "${TMP_PATH}/modellist" | sort -n -k 2)
      dialog --backtitle "$(backtitle)" --colors \
        --cancel-label "Show all" --help-button --help-label "Exit" \
        --extra-button --extra-label "Info" \
        --menu "Choose Model for Loader" 0 70 0 \
        --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
      RET=$?
      case ${RET} in
      0) # ok-button
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        break
        ;;
      1) # cancel-button -> Show all Models
        FLGBETA=1
        RESTRICT=0
        ;;
      2) # help-button -> Exit
        return 1
        break
        ;;
      3) # extra-button -> Platform Info
        resp="$(<"${TMP_PATH}/resp")"
        PLATFORM="$(readModelKey "${resp}" "platform")"
        dialog --textbox "./informations/${PLATFORM}.yml" 15 80
        ;;
      255) # ESC -> Exit
        return 1
        break
        ;;
      esac
    done
  # read model config for dt and aes
  if [ "${MODEL}" != "${resp}" ]; then
    MODEL="${resp}"
    DT="$(readModelKey "${MODEL}" "dt")"
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
    writeConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    if [[ -f "${ORI_ZIMAGE_FILE}" || -f "${ORI_RDGZ_FILE}" || -f "${MOD_ZIMAGE_FILE}" || -f "${MOD_RDGZ_FILE}" ]]; then
      # Delete old files
      rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
    fi
  fi
  arcVersion
}

###############################################################################
# Arc Version Section
function arcVersion() {
  # read model values for arcbuild
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  if [ "${ARCRECOVERY}" != "true" ]; then
    # Select Build for DSM
    ITEMS="$(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml" | sort -r)"
    if [ -z "${1}" ]; then
      dialog --clear --no-items --nocancel --backtitle "$(backtitle)" \
        --menu "Choose a Version" 7 30 0 ${ITEMS} 2>"${TMP_PATH}/resp"
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
  if [ "${ONLYVERSION}" != "true" ]; then
    arcPatch
  else
    # Build isn't done
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  fi
}

###############################################################################
# Arc Patch Section
function arcPatch() {
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
      --menu "Please select an Option?" 8 50 0 \
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
  if [ "${ONLYPATCH}" = "true" ]; then
    return 1
  else
    arcSettings
  fi
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
  # Select Addons
  addonSelection
  # Check for DT and HBA/Raid Controller
  if [[ "${DT}" = "true" && "${EXTERNALCONTROLLER}" = "true" ]]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: You use a HBA/Raid Controller and selected a DT Model.\nThis is still an experimental Feature." 0 0
  fi
  # Check for more then 8 Ethernet Ports
  DEVICENIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
  if [ ${DEVICENIC} -gt 8 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: You have more then 8 Ethernet Ports.\nThere are only 8 supported by DSM." 0 0
  fi
  # Check for AES
  if ! grep -q "^flags.*aes.*" /proc/cpuinfo; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: Your CPU does not have AES Support for Hardwareencryption in DSM." 0 0
  fi
  # Check for KVM
  KVMSUPPORT="$(readConfigKey "arc.kvm" "${USER_CONFIG_FILE}")"
  if [ "${KVMSUPPORT}" = "true" ]; then
    if ! grep -q -E '(vmx|svm)' /proc/cpuinfo; then
      dialog --backtitle "$(backtitle)" --title "Arc Warning" \
        --msgbox "WARN: Your CPU does not support KVM in DSM.\nCheck CPU/Bios for VMX or SVM Support." 0 0
    fi
  fi
  # Config is done
  writeConfigKey "arc.confdone" "true" "${USER_CONFIG_FILE}"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  # Ask for Build
  dialog --clear --backtitle "$(backtitle)" \
    --menu "Config done -> Build now?" 7 50 0 \
    1 "Yes - Build Arc Loader now" \
    2 "No - I want to make changes" \
  2>"${TMP_PATH}/resp"
  resp="$(<"${TMP_PATH}/resp")"
  [ -z "${resp}" ] && return 1
  if [ ${resp} -eq 1 ]; then
    premake
  elif [ ${resp} -eq 2 ]; then
    dialog --clear --no-items --backtitle "$(backtitle)"
    return 1
  fi
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
  # Show Config Summary
  arcSummary
}

###############################################################################
# Calls boot.sh to boot into DSM Recovery
function arcSummary() {
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
  DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
  USBMOUNT="$(readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
  MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  ARCIPV6="$(readConfigKey "arc.ipv6" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
  KVMSUPPORT="$(readConfigKey "arc.kvm" "${USER_CONFIG_FILE}")"
  NIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  HARDDRIVES="$(readConfigKey "device.harddrives" "${USER_CONFIG_FILE}")"
  DRIVES="$(readConfigKey "device.drives" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "arc.emmcboot" "${USER_CONFIG_FILE}")"
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  KERNEL="$(readConfigKey "arc.kernel" "${USER_CONFIG_FILE}")"
  # Print Summary
  SUMMARY="\Z4> DSM Information\Zn"
  SUMMARY+="\n>> DSM Model: \Zb${MODEL}\Zn"
  SUMMARY+="\n>> DSM Version: \Zb${PRODUCTVER}\Zn"
  SUMMARY+="\n>> DSM Platform: \Zb${PLATFORM}\Zn"
  SUMMARY+="\n>> DeviceTree: \Zb${DT}\Zn"
  SUMMARY+="\n>> Kernel: \Zb${KERNEL}\Zn"
  SUMMARY+="\n>> Kernel Version: \Zb${KVER}\Zn"
  SUMMARY+="\n"
  SUMMARY+="\n\Z4> Arc Information\Zn"
  SUMMARY+="\n>> Arc Patch: \Zb${ARCPATCH}\Zn"
  SUMMARY+="\n>> MacSys: \Zb${MACSYS}\Zn"
  [ -n "${PORTMAP}" ] && SUMMARY+="\n>> Portmap: \Zb${PORTMAP}\Zn"
  [ -n "${DISKMAP}" ] && SUMMARY+="\n>> Diskmap: \Zb${DISKMAP}\Zn"
  SUMMARY+="\n>> USB Mount: \Zb${USBMOUNT}\Zn"
  SUMMARY+="\n>> IPv6: \Zb${ARCIPV6}\Zn"
  SUMMARY+="\n>> KVM Support: \Zb${KVMSUPPORT}\Zn"
  SUMMARY+="\n>> Offline Mode: \Zb${OFFLINE}\Zn"
  SUMMARY+="\n>> Sort Drives: \Zb${HDDSORT}\Zn"
  SUMMARY+="\n>> Directboot: \Zb${DIRECTBOOT}\Zn"
  SUMMARY+="\n>> eMMC Boot: \Zb${EMMCBOOT}\Zn"
  SUMMARY+="\n>> Kernelload: \Zb${KERNELLOAD}\Zn"
  SUMMARY+="\n>> Addons: \Zb${ADDONSINFO}\Zn"
  SUMMARY+="\n"
  SUMMARY+="\n\Z4> Device Information\Zn"
  SUMMARY+="\n>> NIC Count: \Zb${NIC}\Zn"
  SUMMARY+="\n>> Disks Count (incl. USB): \Zb${DRIVES}\Zn"
  SUMMARY+="\n>> External Controller: \Zb${EXTERNALCONTROLLER}\Zn"
  SUMMARY+="\n>> Memory Min/Max MB: \Zb${RAMMIN}/${RAMMAX}\Zn"
  dialog --backtitle "$(backtitle)" --colors --title "Config Summary" \
    --extra-button --extra-label "Cancel" --msgbox "${SUMMARY}" 0 0
  RET=$?
  case ${RET} in
  0) # ok-button
    make
    ;;
  3) # extra-button
    return 1
    ;;
  255) # ESC
    return 1
    ;;
  esac
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
      dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
        --msgbox "Addon ${ADDON} not found!" 0 0
      return 1
    fi
  done <<<$(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Check for offline Mode
  if [ "${OFFLINE}" = "true" ]; then
    offlinemake
    return 0
  else
    # Get PAT Data from Config
    PAT_URL_CONF="$(readConfigKey "arc.paturl" "${USER_CONFIG_FILE}")"
    PAT_HASH_CONF="$(readConfigKey "arc.pathash" "${USER_CONFIG_FILE}")"
    if [[ -z "${PAT_URL_CONF}" || -z "${PAT_HASH_CONF}" ]]; then
      PAT_URL_CONF=""
      PAT_HASH_CONF=""
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
      return 1                     # 1 or 255  # cancel-button or ESC
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
          tar xf "${PAT_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
        fi
        # Cleanup PAT Download
        rm -f "${PAT_FILE}"
      elif [ -f "${DSM_FILE}" ]; then
        tar xf "${DSM_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
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
        --menu "Build done -> Boot now?" 8 50 0 \
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
      tar xf "${PAT_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
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
# Calls boot.sh to boot into DSM Recovery
function juniorboot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  [ "${BUILDDONE}" = "false" ] && dialog --backtitle "$(backtitle)" --title "Alert" \
    --yesno "Config changed, please build Loader first." 0 0
  if [ $? -eq 0 ]; then
    premake
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
  echo "A \"Networkdiag \" "                                                                >>"${TMP_PATH}/menu"
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
      echo "S \"Update Storage Map \" "                                                     >>"${TMP_PATH}/menu"
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
      echo "U \"USB Mount: \Z4${USBMOUNT}\Zn \" "                                           >>"${TMP_PATH}/menu"
      echo "V \"KVM Support: \Z4${KVMSUPPORT}\Zn \" "                                       >>"${TMP_PATH}/menu"
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
    echo "T \"Force enable SSH in DSM \" "                                                  >>"${TMP_PATH}/menu"
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
    1) arcModel; NEXT="2" ;;
    2) premake; NEXT="3" ;;
    3) boot && exit 0 ;;
    # Info Section
    a) sysinfo; NEXT="a" ;;
    A) networkdiag; NEXT="A" ;;
    # System Section
    # Arc Section
    4) [ "${ARCOPTS}" = "true" ] && ARCOPTS='false' || ARCOPTS='true'
      ARCOPTS="${ARCOPTS}"
      NEXT="4"
      ;;
    b) addonMenu; NEXT="b" ;;
    d) modulesMenu; NEXT="d" ;;
    e) ONLYVERSION="true" && arcVersion; NEXT="e" ;;
    N) networkMenu; NEXT="N" ;;
    S) storageMenu; NEXT="S" ;;
    p) ONLYPATCH="true" && arcPatch; NEXT="p" ;;
    P) storagepanelMenu; NEXT="P" ;;
    D) staticIPMenu; NEXT="D" ;;
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
        done <<<$(getAllModules "${PLATFORM}" "${KVER}")
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
    U)
      if [ "${USBMOUNT}" = "true" ]; then
        USBMOUNT="false"
      elif [[ "${USBMOUNT}" = "false" && "${DT}" = "false" ]]; then
        USBMOUNT="force"
      elif [[ "${USBMOUNT}" = "force" || "${USBMOUNT}" = "false" ]]; then
        USBMOUNT="true"
      fi
      writeConfigKey "arc.usbmount" "${USBMOUNT}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="U"
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
    T) forcessh; NEXT="T" ;;
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
