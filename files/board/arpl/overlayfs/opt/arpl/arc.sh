#!/usr/bin/env bash

. /opt/arpl/include/functions.sh
. /opt/arpl/include/addons.sh
. /opt/arpl/include/modules.sh
. /opt/arpl/include/storage.sh
. /opt/arpl/include/network.sh

LOADER_DISK="$(blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1)"
LOADER_DEVICE_NAME=$(echo ${LOADER_DISK} | sed 's|/dev/||')

# Memory: Check Memory installed
RAMTOTAL=0
while read -r -r LINE; do
  RAMSIZE=${LINE}
  RAMTOTAL=$((${RAMTOTAL}+${RAMSIZE}))
done < <(dmidecode -t memory | grep -i "Size" | cut -d" " -f2 | grep -i "[1-9]")
RAMTOTAL=$((${RAMTOTAL}*1024))
RAMMIN=$((${RAMTOTAL}/2))

# Check for Hypervisor
if grep -q "^flags.*hypervisor.*" /proc/cpuinfo; then
  # Check for Hypervisor
  MACHINE="$(lscpu | grep Hypervisor | awk '{print $3}')"
else
  MACHINE="NATIVE"
fi

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

# Get DSM Data from Config
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
if [ -n "${MODEL}" ]; then
  DT="$(readModelKey "${MODEL}" "dt")"
fi

# Get Arc Data from Config
DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
DIRECTDSM="$(readConfigKey "arc.directdsm" "${USER_CONFIG_FILE}")"
CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
ONLINEMODE="$(readConfigKey "arc.onlinemode" "${USER_CONFIG_FILE}")"
BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
NOTSETMAC="$(readConfigKey "arc.notsetmac" "${USER_CONFIG_FILE}")"
KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"

# Add Kernelload to old configs
if [ -z "${KERNELLOAD}" ]; then
  writeConfigKey "arc.kernelload" "power" "${USER_CONFIG_FILE}"
fi

# Reset DirectDSM if User boot to Config
if [ "${DIRECTDSM}" = "true" ]; then
  writeConfigKey "arc.directdsm" "false" "${USER_CONFIG_FILE}"
fi

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${ARPL_TITLE} |"
  if [ -n "${MODEL}" ]; then
    BACKTITLE+=" ${MODEL}"
  else
    BACKTITLE+=" (no model)"
  fi
  BACKTITLE+=" |"
  if [ -n "${PRODUCTVER}" ]; then
    BACKTITLE+=" ${PRODUCTVER}"
  else
    BACKTITLE+=" (no version)"
  fi
  BACKTITLE+=" |"
  if [ -n "${IP}" ]; then
    BACKTITLE+=" ${IP}"
  else
    BACKTITLE+=" (no IP)"
  fi
  BACKTITLE+=" |"
  if [ "${ARCPATCH}" = "true" ]; then
    BACKTITLE+=" Patch: Y"
  else
    BACKTITLE+=" Patch: N"
  fi
  BACKTITLE+=" |"
  if [ -n "${CONFDONE}" ]; then
    BACKTITLE+=" Config: Y"
  else
    BACKTITLE+=" Config: N"
  fi
  BACKTITLE+=" |"
  if [ -n "${BUILDDONE}" ]; then
    BACKTITLE+=" Build: Y"
  else
    BACKTITLE+=" Build: N"
  fi
  BACKTITLE+=" |"
  BACKTITLE+=" ${MACHINE}"
  echo "${BACKTITLE}"
}

###############################################################################
# Make Model Config
function arcMenu() {
  if [ -z "${1}" ]; then
    # Start ARC build process
    resp=$(<"${TMP_PATH}/resp")
    [ -z "${resp}" ] && return
  else
    if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
    resp="${1}"
  fi
  if [ -z "${1}" ]; then
  # Loop menu
  RESTRICT=1
  FLGBETA=0
  dialog --backtitle "$(backtitle)" --title "Model" --aspect 18 \
    --infobox "Reading models" 3 20
  while true; do
    echo "" >"${TMP_PATH}/menu"
    FLGNEX=0
    while read -r M; do
      M="$(basename ${M})"
      M="${M::-4}"
      PLATFORM="$(readModelKey "${M}" "platform")"
      DT="$(readModelKey "${M}" "dt")"
      BETA="$(readModelKey "${M}" "beta")"
      [ "${BETA}" = "true" ] && [ "${FLGBETA}" -eq "0" ] && continue
      DISKS="$(readModelKey "${M}" "disks")-Bay"
      ARCCONF="$(readModelKey "${M}" "arc.serial")"
      if [ -n "${ARCCONF}" ]; then
        ARCAV="Arc"
      else
        ARCAV="NonArc"
      fi
      if [ "${PLATFORM}" = "r1000" ] || [ "${PLATFORM}" = "v1000" ] || [ "${PLATFORM}" = "epyc7002" ]; then
        CPU="AMD"
      else
        CPU="Intel"
      fi
      # Check id model is compatible with CPU
      COMPATIBLE=1
      if [ "${RESTRICT}" -eq "1" ]; then
        for F in "$(readModelArray "${M}" "flags")"; do
          if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
            COMPATIBLE=0
            FLGNEX=1
            break
          fi
        done
        for F in "$(readModelArray "${M}" "dt")"; do
          if [ "${DT}" = "true" ] && [ "${SASCONTROLLER}" -gt "0" ]; then
            COMPATIBLE=0
            FLGNEX=1
            break
          fi
        done
      fi
      [ "${DT}" = "true" ] && DT="DT" || DT=""
      [ "${BETA}" = "true" ] && BETA="Beta" || BETA=""
      [ "${COMPATIBLE}" -eq "1" ] && echo "${M} \"$(printf "\Zb%-7s\Zn \Zb%-6s\Zn \Zb%-13s\Zn \Zb%-3s\Zn \Zb%-7s\Zn \Zb%-4s\Zn" "${DISKS}" "${CPU}" "${PLATFORM}" "${DT}" "${ARCAV}" "${BETA}")\" ">>"${TMP_PATH}/menu"
    done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
    [ "${FLGBETA}" -eq "0" ] && echo "b \"\Z1Show beta Models\Zn\"" >>"${TMP_PATH}/menu"
    [ "${FLGNEX}" -eq "1" ] && echo "f \"\Z1Show incompatible Models \Zn\"" >>"${TMP_PATH}/menu"
    dialog --backtitle "$(backtitle)" --colors --menu "Choose Model for Loader" 0 62 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    resp=$(<"${TMP_PATH}/resp")
    [ -z "${resp}" ] && return
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
  else
    resp="${1}"
  fi
  # read model config for dt and aes
  if [ "${MODEL}" != "${resp}" ]; then
    MODEL="${resp}"
    # Check for DT and SAS Controller
    DT="$(readModelKey "${resp}" "dt")"
    if [ "${DT}" = "true" ] && [ "${SASCONTROLLER}" -gt "0" ]; then
      # There is no Raid/SCSI Support for DT Models
      WARNON=2
    fi
    # Check for AES
    if ! grep -q "^flags.*aes.*" /proc/cpuinfo; then
      WARNON=4
    fi
    PRODUCTVER=""
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    writeConfigKey "productver" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
    deleteConfigKey "arc.confdone" "${USER_CONFIG_FILE}"
    deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
    if [ -f "${ORI_ZIMAGE_FILE}" ] || [ -f "${ORI_RDGZ_FILE}" ] || [ -f "${MOD_ZIMAGE_FILE}" ] || [ -f "${MOD_RDGZ_FILE}" ]; then
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
  if [ "${ARCRECOVERY}" != "true" ]; then
    # Select Build for DSM
    ITEMS="$(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml" | sort -r)"
    if [ -z "${1}" ]; then
      dialog --clear --no-items --backtitle "$(backtitle)" \
        --menu "Choose a Version" 0 0 0 ${ITEMS} 2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      resp=$(<"${TMP_PATH}/resp")
      [ -z "${resp}" ] && return
    else
      if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
      resp="${1}"
    fi
    if [ "${PRODUCTVER}" != "${resp}" ]; then
      PRODUCTVER="${resp}"
      writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
      if [ -f "${ORI_ZIMAGE_FILE}" ] || [ -f "${ORI_RDGZ_FILE}" ] || [ -f "${MOD_ZIMAGE_FILE}" ] || [ -f "${MOD_RDGZ_FILE}" ]; then
        # Delete old files
        rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
      fi
    fi
  fi
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  dialog --backtitle "$(backtitle)" --title "Arc Config" \
    --infobox "Reconfiguring Synoinfo, Addons and Modules" 0 0
  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read -r KEY VALUE; do
    writeConfigKey "synoinfo.${KEY}" "${VALUE}" "${USER_CONFIG_FILE}"
  done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].synoinfo")
  # Memory: Set mem_max_mb to the amount of installed memory
  writeConfigKey "synoinfo.mem_max_mb" "${RAMTOTAL}" "${USER_CONFIG_FILE}"
  writeConfigKey "synoinfo.mem_min_mb" "${RAMMIN}" "${USER_CONFIG_FILE}"
  # Check addons
  while IFS=': ' read -r ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      deleteConfigKey "addons.${ADDON}" "${USER_CONFIG_FILE}"
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Rebuild modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read -r ID DESC; do
    writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
  done < <(getAllModules "${PLATFORM}" "${KVER}")
  if [ "${ONLYVERSION}" != "true" ]; then
    arcsettings
  else
    deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  fi
}

###############################################################################
# Make Arc Settings
function arcsettings() {
  # read model values for arcsettings
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  if [ "${ARCRECOVERY}" != "true" ] && [ "${ARCAV}" = "Arc" ]; then
    while true; do
      dialog --clear --backtitle "$(backtitle)" \
        --menu "Arc Patch\nDo you want to use Syno Services?" 0 0 0 \
        1 "Yes - Install with Arc Patch" \
        2 "No - Install without Arc Patch" \
      2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      resp=$(<"${TMP_PATH}/resp")
      [ -z "${resp}" ] && return
      if [ "${resp}" = "1" ]; then
        # read valid serial from file
        SN="$(readModelKey "${MODEL}" "arc.serial")"
        writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
        writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
        break
      elif [ "${resp}" = "2" ]; then
        # Generate random serial
        SN="$(generateSerial "${MODEL}")"
        writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
        break
      fi
    done
  elif [ "${ARCRECOVERY}" = "true" ] && [ "${ARCAV}" = "Arc" ]; then
    writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
  else
    # Generate random serial
    SN="$(generateSerial "${MODEL}")"
    writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
  fi
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  dialog --backtitle "$(backtitle)" --title "Arc Config" \
    --infobox "Model Configuration successful!" 0 0
  sleep 1
  arcnetdisk
}

###############################################################################
# Make Network and Disk Config
function arcnetdisk() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  DT="$(readModelKey "${MODEL}" "dt")"
  # Get Network Config for Loader
  getnet
  # Only load getmap when Sata Controller are dedected and no DT Model is selected
  if [ "${SATACONTROLLER}" -gt "0" ] && [ "${DT}" != "true" ]; then
    # Config for Sata Controller with PortMap to get all drives
      dialog --backtitle "$(backtitle)" --title "Arc Disks" \
        --infobox "SATA Controller found. Need PortMap for Controller!" 0 0
    # Get Portmap for Loader
    getmap
  fi
  # Config is done
  writeConfigKey "arc.confdone" "1" "${USER_CONFIG_FILE}"
  dialog --backtitle "$(backtitle)" --title "Arc Config" \
    --infobox "Configuration successful!" 0 0
  sleep 1
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ "${WARNON}" = "1" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: Your Controller has more than 8 Disks connected. Max Disks per Controller: 8" 0 0
  fi
  if [ "${WARNON}" = "2" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: You have selected a DT Model. There is no support for Raid/SCSI Controller." 0 0
  fi
  if [ "${WARNON}" = "3" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: You have more than 8 Ethernet Ports. There are only 8 supported by Redpill." 0 0
  fi
  if [ "${WARNON}" = "4" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: Your CPU does not have AES Support for Hardwareencryption in DSM." 0 0
  fi
  # Ask for Build
  while true; do
    dialog --clear --backtitle "$(backtitle)" \
      --menu "Build now?" 0 0 0 \
      1 "Yes - Build Arc Loader now" \
      2 "No - I want to make changes" \
    2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    resp=$(<"${TMP_PATH}/resp")
    [ -z "${resp}" ] && return
    if [ "${resp}" = "1" ]; then
      make
      break
    elif [ "${resp}" = "2" ]; then
      dialog --clear --no-items --backtitle "$(backtitle)"
      break
    fi
  done
}

###############################################################################
# Building Loader
function make() {
  clear
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  # Check if all addon exists
  while IFS=': ' read -r ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
        --msgbox "$(printf "Addon %s not found!" "${ADDON}")" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Check for old DSM Kernel
  if [ -f "${MOD_ZIMAGE_FILE}" ] && [ -f "${MOD_RDGZ_FILE}" ]; then
    # Check zImage Hash
    ZIMAGE_HASH="$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print$1}')"
    OLD_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
    if [ "${ZIMAGE_HASH}" = "${OLD_HASH}" ]; then
      NEWIMAGE="false"
    fi
    # Check Ramdisk Hash
    RAMDISK_HASH="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print$1}')"
    OLD_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
    if [ "${RAMDISK_HASH}" = "${OLD_HASH}" ]; then
      NEWIMAGE="false"
    fi
  fi
  # Build if NEWIMAGE is not falses
  if [ "${NEWIMAGE}" != "false" ]; then
    # Clean old files
    rm -rf "${UNTAR_PAT_PATH}"
    rm -rf "${CACHE_PATH}/${MODEL}/${PRODUCTVER}"
    # Check for existing files
    mkdir -p "${CACHE_PATH}/${MODEL}/${PRODUCTVER}"
    DSM_FILE="${CACHE_PATH}/${MODEL}/${PRODUCTVER}/dsm.tar"
    DSM_MODEL="$(echo "${MODEL}" | sed -e 's/+/%2B/g')"
    # Get new files
    DSM_LINK="${DSM_MODEL}/${PRODUCTVER}/dsm.tar"
    DSM_URL="https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/files/${DSM_LINK}"
    STATUS=$(curl --insecure -s -w "%{http_code}" -L "${DSM_URL}" -o "${DSM_FILE}")
    if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
      dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
        --msgbox "No DSM Image found!\nTry alternate Link." 0 0
      DSM_LINK="${MODEL}/${PRODUCTVER}/dsm.tar"
      DSM_URL="https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/files/${DSM_LINK}"
      STATUS=$(curl --insecure -s -w "%{http_code}" -L "${DSM_URL}" -o "${DSM_FILE}")
      if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
        dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
        --msgbox "No DSM Image found!\nTry Syno Link." 0 0
        # Grep Values
        PAT_MODEL="$(echo "${MODEL}" | sed -e 's/+/%2B/g')"
        PAT_MAJOR="$(echo "${PRODUCTVER}" | cut -b 1)"
        PAT_MINOR="$(echo "${PRODUCTVER}" | cut -b 3)"
        # Grep PAT_URL
        PAT_URL="$(curl -skL "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${PAT_MODEL}&major=${PAT_MAJOR}&minor=${PAT_MINOR}" | jq -r '.info.system.detail[0].items[0].files[0].url')"
        PAT_URL="${PAT_URL%%\?*}"
        PAT_FILE="${MODEL}_${PRODUCTVER}.pat"
        PAT_PATH="${CACHE_PATH}/dl/${PAT_FILE}"
        mkdir -p "${CACHE_PATH}/dl"
        STATUS=$(curl -k -w "%{http_code}" -L "${PAT_URL}" -o "${PAT_PATH}" --progress-bar)
        if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
          dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
            --msgbox "No DSM Image found!\ Exit." 0 0
          rm -f "${PAT_PATH}"
          return 1
        fi
        # Extract Files
        rm -rf "${UNTAR_PAT_PATH}"
        mkdir -p "${UNTAR_PAT_PATH}"
        header=$(od -bcN2 ${PAT_PATH} | head -1 | awk '{print $3}')
        case ${header} in
            105)
            echo "Uncompressed tar"
            isencrypted="no"
            ;;
            213)
            echo "Compressed tar"
            isencrypted="no"
            ;;
            255)
            echo "Encrypted"
            isencrypted="yes"
            ;;
            *)
            echo -e "Could not determine if pat file is encrypted or not, maybe corrupted, try again!"
            ;;
        esac
        if [ "${isencrypted}" = "yes" ]; then
            # Uses the extractor to untar PAT file
            LD_LIBRARY_PATH="${EXTRACTOR_PATH}" "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" "${PAT_PATH}" "${UNTAR_PAT_PATH}"
        else
            # Untar PAT file
            tar -xf "${PAT_PATH}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
        fi
        # Cleanup PAT Download
        rm -rf "${CACHE_PATH}/dl"
      fi
      dialog --backtitle "$(backtitle)" --title "DSM Extraction" --aspect 18 \
        --msgbox "DSM Extraction successful!" 0 0
    fi
    if [ -f "${DSM_FILE}" ]; then
      mkdir -p "${UNTAR_PAT_PATH}"
      tar -xf "${DSM_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
    fi
    # Copy DSM Files to locations
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${BOOTLOADER_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER"        "${BOOTLOADER_PATH}"
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${SLPART_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER"        "${SLPART_PATH}"
    if [ ! -f "${ORI_ZIMAGE_FILE}" ] || [ ! -f "${ORI_RDGZ_FILE}" ]; then
      cp -f "${UNTAR_PAT_PATH}/zImage"          "${ORI_ZIMAGE_FILE}"
      cp -f "${UNTAR_PAT_PATH}/rd.gz"           "${ORI_RDGZ_FILE}"
    fi
  fi
  # Patch Ramdisk
  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
      --msgbox "Ramdisk not patched:\n$(<"${LOG_FILE}")" 0 0
    return 1
  fi
  # Patch zImage
  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
      --msgbox "zImage not patched:\n$(<"${LOG_FILE}")" 0 0
    return 1
  fi
  echo "Ready!"
  sleep 3
  # Build is done
  writeConfigKey "arc.directdsm" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.builddone" "1" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  # Ask for Boot
  while true; do
    dialog --clear --backtitle "$(backtitle)" \
      --menu "Build done. Boot now?" 0 0 0 \
      1 "Yes - Boot Arc Loader now" \
      2 "No - I want to make changes" \
    2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    resp=$(<"${TMP_PATH}/resp")
    [ -z "${resp}" ] && return
    if [ "${resp}" = "1" ]; then
      boot && exit 0
      break
    elif [ "${resp}" = "2" ]; then
      return 0
      break
    fi
  done
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "$(backtitle)" --title "Edit with caution" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return
    mv "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=$(yq eval "${USER_CONFIG_FILE}" 2>&1)
    [ $? -eq 0 ] && break
    dialog --backtitle "$(backtitle)" --title "Invalid YAML format" --msgbox "${ERRORS}" 0 0
  done
  OLDMODEL="${MODEL}"
  OLDPRODUCTVER="${PRODUCTVER}"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
  if [ "${MODEL}" != "${OLDMODEL}" ] || [ "${PRODUCTVER}" != "${OLDPRODUCTVER}" ]; then
    # Remove old files
    rm -f "${MOD_ZIMAGE_FILE}"
    rm -f "${MOD_RDGZ_FILE}"
  fi
  deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Shows option to manage addons
function addonMenu() {
  # read platform and kernel version to check if addon exists
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  ALLADDONS="$(availableAddons "${PLATFORM}" "${KVER}")"
  # read addons from user config
  unset ADDONS
  declare -A ADDONS
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  rm "${TMP_PATH}/opts"
  touch "${TMP_PATH}/opts"
  while read -r ADDON DESC; do
    arrayExistItem "${ADDON}" "${!ADDONS[@]}" && ACT="on" || ACT="off"         # Check if addon has already been added
    echo -e "${ADDON} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
  done <<<${ALLADDONS}
  dialog --backtitle "$(backtitle)" --title "Addons" --aspect 18 \
    --checklist "Select Addons to include or remove\nSelect with SPACE" 0 0 0 \
    --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp=$(<"${TMP_PATH}/resp")
  [ -z "${resp}" ] && continue
  dialog --backtitle "$(backtitle)" --title "Addons" \
      --infobox "Writing to user config" 0 0
  unset ADDONS
  declare -A ADDONS
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  for ADDON in ${resp}; do
    USERADDONS["${ADDON}"]=""
    writeConfigKey "addons.${ADDON}" "" "${USER_CONFIG_FILE}"
  done
  ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  dialog --backtitle "$(backtitle)" --title "Addons" \
    --msgbox "Addons selected:\n${ADDONSINFO}" 0 0
  deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Permit user select the modules to include
function modulesMenu() {
  NEXT="1"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
    --infobox "Reading modules" 0 0
  ALLMODULES=$(getAllModules "${PLATFORM}" "${KVER}")
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
      0 "Exit" \
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
          --infobox "Selecting loaded modules" 0 0
        KOLIST=""
        for I in $(lsmod | awk -F' ' '{print $1}' | grep -v 'Module'); do
          KOLIST+="$(getdepends ${PLATFORM} ${KVER} ${I}) ${I} "
        done
        KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        for ID in ${KOLIST[@]}; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      3)
        dialog --backtitle "$(backtitle)" --title "Modules" \
           --infobox "Selecting all modules" 0 0
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        while read -r ID DESC; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done <<<${ALLMODULES}
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      4)
        dialog --backtitle "$(backtitle)" --title "Modules" \
           --infobox "Deselecting all modules" 0 0
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        unset USERMODULES
        declare -A USERMODULES
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      5)
        rm -f "${TMP_PATH}/opts"
        while read -r ID DESC; do
          arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
          echo "${ID} ${DESC} ${ACT}" >>"${TMP_PATH}/opts"
        done <<<${ALLMODULES}
        dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
          --checklist "Select modules to include" 0 0 0 \
          --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        resp=$(<"${TMP_PATH}/resp")
        [ -z "${resp}" ] && continue
        dialog --backtitle "$(backtitle)" --title "Modules" \
           --infobox "Writing to user config" 0 0
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        for ID in ${resp}; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      6)
        MSG=""
        MSG+="This function is experimental and dangerous. If you don't know much, please exit.\n"
        MSG+="The imported .ko of this function will be implanted into the corresponding arch's modules package, which will affect all models of the arch.\n"
        MSG+="This program will not determine the availability of imported modules or even make type judgments, as please double check if it is correct.\n"
        MSG+="If you want to remove it, please go to the \"Update Menu\" -> \"Update modules\" to forcibly update the modules. All imports will be reset.\n"
        MSG+="Do you want to continue?"
        dialog --backtitle "$(backtitle)" --title "Add external module" \
            --yesno "${MSG}" 0 0
        [ $? -ne 0 ] && return
        dialog --backtitle "$(backtitle)" --aspect 18 --colors --inputbox "Please enter the complete URL to download.\n" 0 0 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        URL="$(<"${TMP_PATH}/resp")"
        [ -z "${URL}" ] && continue
        clear
        echo "Downloading ${URL}"
        STATUS=$(curl -kLJO -w "%{http_code}" "${URL}" --progress-bar)
        if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
          dialog --backtitle "$(backtitle)" --title "Add external module" --aspect 18 \
            --msgbox "ERROR: Check internet, URL or cache disk space" 0 0
          return 1
        fi
        KONAME=$(basename "$URL")
        if [ -n "${KONAME}" -a "${KONAME##*.}" = "ko" ]; then
          addToModules "${PLATFORM}" "${KVER}" "${KONAME}"
          dialog --backtitle "$(backtitle)" --title "Add external module" --aspect 18 \
            --msgbox "Module ${KONAME} added to ${PLATFORM}-${KVER}" 0 0
          rm -f "${KONAME}"
        else
          dialog --backtitle "$(backtitle)" --title "Add external module" --aspect 18 \
            --msgbox "File format not recognized!" 0 0
        fi
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      0)
        break
        ;;
    esac
  done
}

###############################################################################
# Let user edit cmdline
function cmdlineMenu() {
  NEXT="1"
  unset CMDLINE
  declare -A CMDLINE
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
  done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
  echo "1 \"Add/edit a Cmdline item\""                          >"${TMP_PATH}/menu"
  echo "2 \"Delete Cmdline item(s)\""                           >>"${TMP_PATH}/menu"
  echo "3 \"Define a serial number\""                           >>"${TMP_PATH}/menu"
  echo "4 \"Define a custom MAC\""                              >>"${TMP_PATH}/menu"
  echo "5 \"Add experimental CPU Fix\""                         >>"${TMP_PATH}/menu"
  echo "6 \"Add experimental RAM Fix\""                         >>"${TMP_PATH}/menu"
  echo "7 \"Show user Cmdline\""                                >>"${TMP_PATH}/menu"
  echo "8 \"Show Model/Build Cmdline\""                         >>"${TMP_PATH}/menu"
  echo "0 \"Exit\""                                             >>"${TMP_PATH}/menu"
  # Loop menu
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    case "$(<"${TMP_PATH}/resp")" in
      1)
        dialog --backtitle "$(backtitle)" --title "User cmdline" \
          --inputbox "Type a name of cmdline" 0 0 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        NAME="$(sed 's/://g' <"${TMP_PATH}/resp")"
        [ -z "${NAME}" ] && continue
        dialog --backtitle "$(backtitle)" --title "User cmdline" \
          --inputbox "Type a value of '${NAME}' cmdline" 0 0 "${CMDLINE[${NAME}]}" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        VALUE="$(<"${TMP_PATH}/resp")"
        CMDLINE[${NAME}]="${VALUE}"
        writeConfigKey "cmdline.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
        resp=$(<"${TMP_PATH}/resp")
        [ -z "${RESP}" ] && continue
        for I in ${RESP}; do
          unset 'CMDLINE[${I}]'
          deleteConfigKey "cmdline.${I}" "${USER_CONFIG_FILE}"
        done
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      3)
        while true; do
          dialog --backtitle "$(backtitle)" --colors --title "Cmdline" \
            --inputbox "Please enter a serial number " 0 0 "" \
            2>"${TMP_PATH}/resp"
          [ $? -ne 0 ] && break 2
          SERIAL=$(cat ${TMP_PATH}/resp)
          if [ -z "${SERIAL}" ]; then
            return
          elif [ $(validateSerial ${MODEL} ${SERIAL}) -eq 1 ]; then
            break
          fi
          # At present, the SN rules are not complete, and many SNs are not truly invalid, so not provide tips now.
          break
          dialog --backtitle "$(backtitle)" --colors --title "Cmdline" \
            --yesno "Invalid serial, continue?" 0 0
          [ $? -eq 0 ] && break
        done
        SN="${SERIAL}"
        writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      4)
        ETHX=($(ls /sys/class/net/ | grep eth))  # real network cards list
        for N in $(seq 1 8); do # Currently, only up to 8 are supported.  (<==> boot.sh L96, <==> lkm: MAX_NET_IFACES)
          MACR="$(cat /sys/class/net/${ETHX[$((${N}-1))]}/address | sed 's/://g')"
          MACF=${CMDLINE["mac${N}"]}
          [ -n "${MACF}" ] && MAC=${MACF} || MAC=${MACR}
          RET=1
          while true; do
            dialog --backtitle "$(backtitle)" --title "User cmdline" \
              --inputbox "Type a custom MAC address of mac${N}" 0 0 "${MAC}"\
              2>"${TMP_PATH}/resp"
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            MAC="$(<"${TMP_PATH}/resp")"
            [ -z "${MAC}" ] && MAC="$(readConfigKey "device.mac${i}" "${USER_CONFIG_FILE}")"
            [ -z "${MAC}" ] && MAC="${MACFS[$((${i}-1))]}"
            MACF="$(echo "${MAC}" | sed 's/://g')"
            [ ${#MACF} -eq 12 ] && break
            dialog --backtitle "$(backtitle)" --title "User cmdline" --msgbox "Invalid MAC" 0 0
          done
          if [ ${RET} -eq 0 ]; then
            CMDLINE["mac${N}"]="${MACF}"
            CMDLINE["netif_num"]=${N}
            writeConfigKey "cmdline.mac${N}"      "${MACF}" "${USER_CONFIG_FILE}"
            writeConfigKey "cmdline.netif_num"    "${N}"    "${USER_CONFIG_FILE}"
            MAC="${MACF:0:2}:${MACF:2:2}:${MACF:4:2}:${MACF:6:2}:${MACF:8:2}:${MACF:10:2}"
            ip link set dev ${ETHX[$((${N}-1))]} address ${MAC} 2>&1 | dialog --backtitle "$(backtitle)" \
              --title "User cmdline" --progressbox "Changing MAC" 20 70
            /etc/init.d/S41dhcpcd restart 2>&1 | dialog --backtitle "$(backtitle)" \
              --title "User cmdline" --progressbox "Renewing IP" 20 70
            IP=$(ip route 2>/dev/null | sed -n 's/.* via .* dev \(.*\)  src \(.*\)  metric .*/\1: \2 /p' | head -1)
            dialog --backtitle "$(backtitle)" --title "Alert" \
              --yesno "Continue to custom MAC?" 0 0
            [ $? -ne 0 ] && break
          fi
        done
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      5)
        writeConfigKey "cmdline.nmi_watchdog" "0" "${USER_CONFIG_FILE}"
        writeConfigKey "cmdline.tsc" "reliable" "${USER_CONFIG_FILE}"
        dialog --backtitle "$(backtitle)" --title "CPU Fix" \
          --aspect 18 --msgbox "Fix added to Cmdline" 0 0
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      6)
        writeConfigKey "cmdline.disable_mtrr_trim" "0" "${USER_CONFIG_FILE}"
        writeConfigKey "cmdline.crashkernel" "192M" "${USER_CONFIG_FILE}"
        dialog --backtitle "$(backtitle)" --title "RAM Fix" \
          --aspect 18 --msgbox "Fix added to Cmdline" 0 0
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
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
      0) return ;;
    esac
  done
}

###############################################################################
# let user configure synoinfo entries
function synoinfoMenu() {
  NEXT="1"
  # read synoinfo from user config
  unset SYNOINFO
  declare -A SYNOINFO
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
  done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "1 \"Add/edit Synoinfo item\""     >"${TMP_PATH}/menu"
  echo "2 \"Delete Synoinfo item(s)\""    >>"${TMP_PATH}/menu"
  echo "3 \"Show Synoinfo entries\""      >>"${TMP_PATH}/menu"
  echo "0 \"Exit\""                       >>"${TMP_PATH}/menu"

  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    case "$(<"${TMP_PATH}/resp")" in
      1)
        dialog --backtitle "$(backtitle)" --title "Synoinfo entries" \
          --inputbox "Type a name of synoinfo entry" 0 0 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        NAME="$(<"${TMP_PATH}/resp")"
        [ -z "${NAME}" ] && continue
        dialog --backtitle "$(backtitle)" --title "Synoinfo entries" \
          --inputbox "Type a value of '${NAME}' entry" 0 0 "${SYNOINFO[${NAME}]}" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        VALUE="$(<"${TMP_PATH}/resp")"
        SYNOINFO[${NAME}]="${VALUE}"
        writeConfigKey "synoinfo.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
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
        resp=$(<"${TMP_PATH}/resp")
        [ -z "${resp}" ] && continue
        for I in ${resp}; do
          unset 'SYNOINFO[${I}]'
          deleteConfigKey "synoinfo.${I}" "${USER_CONFIG_FILE}"
        done
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
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
      0) return ;;
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
  [ $? -ne 0 ] && return
  LAYOUT="$(<"${TMP_PATH}/resp")"
  OPTIONS=""
  while read -r KM; do
    OPTIONS+="${KM::-7} "
  done < <(cd /usr/share/keymaps/i386/${LAYOUT}; ls *.map.gz)
  dialog --backtitle "$(backtitle)" --no-items --default-item "${KEYMAP}" \
    --menu "Choice a keymap" 0 0 0 ${OPTIONS} \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp=$(<"${TMP_PATH}/resp")
  [ -z "${resp}" ] && return
  KEYMAP=${resp}
  writeConfigKey "layout" "${LAYOUT}" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  loadkeys /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz
}

###############################################################################
# Shows usb menu to user
function usbMenu() {
  NEXT="1"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ -n "${CONFDONE}" ]; then
    while true; do
      dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
        1 "Mount USB as Internal" \
        2 "Mount USB as Normal" \
        0 "Exit" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      case "$(<"${TMP_PATH}/resp")" in
        1)
          MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
          PLATFORM=$(readModelKey "${MODEL}" "platform")
          if [ "${PLATFORM}" = "broadwellnk" ]; then
            writeConfigKey "synoinfo.maxdisks" "24" "${USER_CONFIG_FILE}"
            writeConfigKey "synoinfo.usbportcfg" "0xff0000" "${USER_CONFIG_FILE}"
            writeConfigKey "synoinfo.internalportcfg" "0xffffff" "${USER_CONFIG_FILE}"
            writeConfigKey "arc.usbmount" "true" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "Mount USB as Internal" \
            --aspect 18 --msgbox "Mount USB as Internal - successful!" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Mount USB as Internal" \
            --aspect 18 --msgbox "You need to select a broadwellnk model!" 0 0
          fi
          ;;
        2)
          MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
          PLATFORM=$(readModelKey "${MODEL}" "platform")
          if [ "${PLATFORM}" = "broadwellnk" ]; then
            deleteConfigKey "synoinfo.maxdisks" "${USER_CONFIG_FILE}"
            deleteConfigKey "synoinfo.usbportcfg" "${USER_CONFIG_FILE}"
            deleteConfigKey "synoinfo.internalportcfg" "${USER_CONFIG_FILE}"
            writeConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "Mount USB as Normal" \
            --aspect 18 --msgbox "Mount USB as Normal - successful!" 0 0
          fi
          ;;
        0) return ;;
      esac
    done
  fi
}

###############################################################################
# Shows backup menu to user
function backupMenu() {
  NEXT="1"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ -n "${BUILDDONE}" ]; then
    while true; do
      dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
        1 "Backup Config" \
        2 "Restore Config" \
        3 "Backup Loader Disk" \
        4 "Restore Loader Disk" \
        5 "Backup Config with Code" \
        6 "Restore Config with Code" \
        0 "Exit" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      case "$(<"${TMP_PATH}/resp")" in
        1)
          dialog --backtitle "$(backtitle)" --title "Backup Config" --aspect 18 \
            --infobox "Backup Config to ${BACKUPDIR}" 0 0
          if [ ! -d "${BACKUPDIR}" ]; then
            # Make backup dir
            mkdir "${BACKUPDIR}"
          else
            # Clean old backup
            rm -f "${BACKUPDIR}/user-config.yml"
          fi
          # Copy config to backup
          cp -f "${USER_CONFIG_FILE}" "${BACKUPDIR}/user-config.yml"
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            dialog --backtitle "$(backtitle)" --title "Backup Config" --aspect 18 \
              --msgbox "Backup complete" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Backup Config" --aspect 18 \
              --msgbox "Backup error" 0 0
          fi
          ;;
        2)
          dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
            --infobox "Restore Config from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            # Copy config back to location
            cp -f "${BACKUPDIR}/user-config.yml" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
              --msgbox "No Config Backup found" 0 0
          fi
          MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
          OLDPRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          while read -r LINE; do
            if [ "${LINE}" = "${OLDPRODUCTVER}" ]; then
              writeConfigKey "productver" "${OLDPRODUCTVER}" "${USER_CONFIG_FILE}"
              PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
              break
            elif [ "${LINE}" != "${OLDPRODUCTVER}" ]; then
              writeConfigKey "productver" "${LINE}" "${USER_CONFIG_FILE}"
              PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
            fi
          done < <(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml")
          ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          ARCRECOVERY="true"
          ONLYVERSION="true"
          arcbuild
          CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
          deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          ;;
        3)
          if ! tty | grep -q "/dev/pts"; then
            dialog --backtitle "$(backtitle)" --colors --aspect 18 \
              --msgbox "This feature is only available when accessed via web/ssh." 0 0
            return
          fi 
          dialog --backtitle "$(backtitle)" --title "Backup Loader Disk" \
              --yesno "Warning:\nDo not terminate midway, otherwise it may cause damage to the Loader. Do you want to continue?" 0 0
          [ $? -ne 0 ] && return
          dialog --backtitle "$(backtitle)" --title "Backup Loader Disk" \
            --infobox "Backup in progress..." 0 0
          rm -f /var/www/data/arc-backup.img.gz  # thttpd root path
          dd if="${LOADER_DISK}" bs=1M conv=fsync | gzip > /var/www/data/arc-backup.img.gz
          if [ $? -ne 0 ]; then
            dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
              --msgbox "Failed to generate Backup. There may be insufficient memory. Please clear the cache and try again!" 0 0
            return
          fi
          if [ -z "${SSH_TTY}" ]; then  # web
            IP_HEAD="$(ip route show 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1)"
            echo "http://${IP_HEAD}/arc-backup.img.gz"  > "${TMP_PATH}/resp"
            echo "            ↑                  " >> "${TMP_PATH}/resp"
            echo "Click on the address above to download." >> "${TMP_PATH}/resp"
            echo "Please confirm the completion of the download before closing this window." >> "${TMP_PATH}/resp"
            dialog --backtitle "$(backtitle)" --title "Download link" --aspect 18 \
            --editbox "${TMP_PATH}/resp" 10 100
          else                          # ssh
            sz -be /var/www/data/arc-backup.img.gz
          fi
          dialog --backtitle "$(backtitle)" --colors --aspect 18 \
              --msgbox "Backup is complete." 0 0
          rm -f /var/www/data/arc-backup.img.gz
          ;;
        4)
          if ! tty | grep -q "/dev/pts"; then
            dialog --backtitle "$(backtitle)" --colors --aspect 18 \
              --msgbox "This feature is only available when accessed via web/ssh." 0 0
            return
          fi 
          dialog --backtitle "$(backtitle)" --title "Restore bootloader disk" --aspect 18 \
              --yesno "Please upload the Backup file.\nCurrently, arc-x.zip(github) and arc-backup.img.gz(Backup) files are supported." 0 0
          [ $? -ne 0 ] && return
          IFTOOL=""
          TMP_PATH="${TMP_PATH}/users"
          rm -rf "${TMP_PATH}"
          mkdir -p "${TMP_PATH}"
          pushd "${TMP_PATH}"
          rz -be
          for F in $(ls -A); do
            USER_FILE="${F}"
            [ "${F##*.}" = "zip" -a $(unzip -l "${TMP_PATH}/${USER_FILE}" | grep -c "\.img$") -eq 1 ] && IFTOOL="zip"
            [ "${F##*.}" = "gz" -a "${F#*.}" = "img.gz" ] && IFTOOL="gzip"
            break 
          done
          popd
          if [ -z "${IFTOOL}" ] || [ -z "${TMP_PATH}/${USER_FILE}" ]; then
            dialog --backtitle "$(backtitle)" --title "Restore Loader disk" --aspect 18 \
              --msgbox "Not a valid .zip/.img.gz file, please try again!\n${USER_FILE}" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Restore Loader disk" \
                --yesno "Warning:\nDo not terminate midway, otherwise it may cause damage to the Loader. Do you want to continue?" 0 0
            [ $? -ne 0 ] && ( rm -f ${LOADER_DISK}; return )
            dialog --backtitle "$(backtitle)" --title "Restore Loader disk" --aspect 18 \
              --infobox "Restore in progress..." 0 0
            umount /mnt/p1 /mnt/p2 /mnt/p3
            if [ "${IFTOOL}" = "zip" ]; then
              unzip -p "${TMP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
            elif [ "${IFTOOL}" = "gzip" ]; then
              gzip -dc "${TMP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
            fi
            dialog --backtitle "$(backtitle)" --title "Restore Loader disk" --aspect 18 \
              --yesno "Restore Loader Disk successful!\nReboot?" 0 0
            [ $? -ne 0 ] && continue
            exec reboot
            exit
          fi
          ;;
        5)
          dialog --backtitle "$(backtitle)" --title "Backup Config with Code" \
              --infobox "Write down your Code for Restore!" 0 0
          if [ -f "${USER_CONFIG_FILE}" ]; then
            GENHASH=$(cat ${USER_CONFIG_FILE} | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-)
            dialog --backtitle "$(backtitle)" --title "Backup Config with Code" --msgbox "Your Code: ${GENHASH}" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Backup Config with Code" --msgbox "No Config for Backup found!" 0 0
          fi
          ;;
        6)
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
          rm -f "${TMP_PATH}/user-config.yml"
          curl -k https://dpaste.com/${GENHASH}.txt >"${TMP_PATH}/user-config.yml"
          cp -f "${TMP_PATH}/user-config.yml" "${USER_CONFIG_FILE}"
          MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
          OLDPRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          while read -r LINE; do
            if [ "${LINE}" = "${OLDPRODUCTVER}" ]; then
              writeConfigKey "productver" "${OLDPRODUCTVER}" "${USER_CONFIG_FILE}"
              PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
              break
            elif [ "${LINE}" != "${OLDPRODUCTVER}" ]; then
              writeConfigKey "productver" "${LINE}" "${USER_CONFIG_FILE}"
              PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
            fi
          done < <(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml")
          ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          ARCRECOVERY="true"
          ONLYVERSION="true"
          arcbuild
          CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          dialog --backtitle "$(backtitle)" --title "Restore with Code" --aspect 18 \
              --msgbox "Restore complete" 0 0
          ;;
        0) return ;;
      esac
    done
  else
    while true; do
      dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
        1 "Restore Config" \
        2 "Restore Loader Disk" \
        3 "Restore Config with Code" \
        0 "Exit" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      case "$(<"${TMP_PATH}/resp")" in
        1)
          dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
            --infobox "Restore Config from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            # Copy config back to location
            cp -f "${BACKUPDIR}/user-config.yml" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
              --msgbox "No Config Backup found" 0 0
          fi
          MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
          OLDPRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          while read -r LINE; do
            if [ "${LINE}" = "${OLDPRODUCTVER}" ]; then
              writeConfigKey "productver" "${OLDPRODUCTVER}" "${USER_CONFIG_FILE}"
              PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
              break
            elif [ "${LINE}" != "${OLDPRODUCTVER}" ]; then
              writeConfigKey "productver" "${LINE}" "${USER_CONFIG_FILE}"
              PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
            fi
          done < <(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml")
          ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          ARCRECOVERY="true"
          ONLYVERSION="true"
          arcbuild
          CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
          deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          ;;
        2)
          if ! tty | grep -q "/dev/pts"; then
            dialog --backtitle "$(backtitle)" --colors --aspect 18 \
              --msgbox "This feature is only available when accessed via web/ssh." 0 0
            return
          fi 
          dialog --backtitle "$(backtitle)" --title "Restore bootloader disk" --aspect 18 \
              --yesno "Please upload the Backup file.\nCurrently, arc-x.zip(github) and arc-backup.img.gz(Backup) files are supported." 0 0
          [ $? -ne 0 ] && return
          IFTOOL=""
          TMP_PATH="${TMP_PATH}/users"
          rm -rf "${TMP_PATH}"
          mkdir -p "${TMP_PATH}"
          pushd "${TMP_PATH}"
          rz -be
          for F in $(ls -A); do
            USER_FILE="${F}"
            [ "${F##*.}" = "zip" -a $(unzip -l "${TMP_PATH}/${USER_FILE}" | grep -c "\.img$") -eq 1 ] && IFTOOL="zip"
            [ "${F##*.}" = "gz" -a "${F#*.}" = "img.gz" ] && IFTOOL="gzip"
            break 
          done
          popd
          if [ -z "${IFTOOL}" ] || [ -z "${TMP_PATH}/${USER_FILE}" ]; then
            dialog --backtitle "$(backtitle)" --title "Restore Loader disk" --aspect 18 \
              --msgbox "Not a valid .zip/.img.gz file, please try again!\n${USER_FILE}" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Restore Loader disk" \
                --yesno "Warning:\nDo not terminate midway, otherwise it may cause damage to the Loader. Do you want to continue?" 0 0
            [ $? -ne 0 ] && ( rm -f ${LOADER_DISK}; return )
            dialog --backtitle "$(backtitle)" --title "Restore Loader disk" --aspect 18 \
              --infobox "Restore in progress..." 0 0
            umount /mnt/p1 /mnt/p2 /mnt/p3
            if [ "${IFTOOL}" = "zip" ]; then
              unzip -p "${TMP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
            elif [ "${IFTOOL}" = "gzip" ]; then
              gzip -dc "${TMP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
            fi
            dialog --backtitle "$(backtitle)" --title "Restore Loader disk" --aspect 18 \
              --yesno "Restore Loader Disk successful!\nReboot?" 0 0
            [ $? -ne 0 ] && continue
            reboot
            exit
          fi
          ;;
        3)
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
          rm -f "${TMP_PATH}/user-config.yml"
          curl -k https://dpaste.com/${GENHASH}.txt >${TMP_PATH}/user-config.yml
          cp -f "${TMP_PATH}/user-config.yml" "${USER_CONFIG_FILE}"
          MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
          OLDPRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          while read -r LINE; do
            if [ "${LINE}" = "${OLDPRODUCTVER}" ]; then
              writeConfigKey "productver" "${OLDPRODUCTVER}" "${USER_CONFIG_FILE}"
              PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
              break
            elif [ "${LINE}" != "${OLDPRODUCTVER}" ]; then
              writeConfigKey "productver" "${LINE}" "${USER_CONFIG_FILE}"
              PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
            fi
          done < <(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml")
          ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          ARCRECOVERY="true"
          ONLYVERSION="true"
          arcbuild
          CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          dialog --backtitle "$(backtitle)" --title "Restore with Code" --aspect 18 \
              --msgbox "Restore complete" 0 0
          ;;
        0) return ;;
      esac
    done
  fi
}

###############################################################################
# Shows update menu to user
function updateMenu() {
  NEXT="1"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      1 "Full upgrade Loader" \
      2 "Update Arc Loader" \
      3 "Update Addons" \
      4 "Update Modules" \
      5 "Update Configs" \
      6 "Update LKMs" \
      0 "Exit" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    case "$(<"${TMP_PATH}/resp")" in
      1)
        dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
          --infobox "Checking latest version" 0 0
        ACTUALVERSION="${ARPL_VERSION}"
        TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ $? -ne 0 ] || [ -z "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          return 1
        fi
        if [ "${ACTUALVERSION}" = "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
            --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
          [ $? -ne 0 ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
          --infobox "Downloading latest version ${TAG}" 0 0
        # Download update file
        STATUS=$(curl --insecure -w "%{http_code}" -L \
          "https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}.img.zip" -o "${TMP_PATH}/arc-${TAG}.img.zip")
        if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
          dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
            --msgbox "Error downloading update file" 0 0
          return 1
        fi
        unzip -o "${TMP_PATH}/arc-${TAG}.img.zip" -d "${TMP_PATH}"
        rm -f "${TMP_PATH}/arc-${TAG}.img.zip"
        if [ $? -ne 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
            --msgbox "Error extracting update file" 0 0
          return 1
        fi
        if [ -f "${USER_CONFIG_FILE}" ]; then
          GENHASH=$(cat ${USER_CONFIG_FILE} | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-)
          dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
          --msgbox "Backup config successful!\nWrite down your Code: ${GENHASH}\n\nAfter Reboot use: Backup - Restore with Code." 0 0
        else
          dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
          --infobox "No config for Backup found!" 0 0
        fi
        dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
          --infobox "Installing new Image" 0 0
        # Process complete update
        umount /mnt/p1 /mnt/p2 /mnt/p3
        dd if="${TMP_PATH}/arc.img" of=$(blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1) bs=1M conv=fsync
        # Ask for Boot
        rm -f "${TMP_PATH}/arc.img"
        dialog --backtitle "$(backtitle)" --title "Full upgrade Loader" --aspect 18 \
          --yesno "Arc updated with success to ${TAG}!\nReboot?" 0 0
        [ $? -ne 0 ] && continue
        exec reboot
        exit
        ;;
      2)
        dialog --backtitle "$(backtitle)" --title "Update Arc" --aspect 18 \
          --infobox "Checking latest version" 0 0
        ACTUALVERSION="${ARPL_VERSION}"
        TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ $? -ne 0 ] || [ -z "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Update Arc" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          return 1
        fi
        if [ "${ACTUALVERSION}" = "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Update Arc" --aspect 18 \
            --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
          [ $? -ne 0 ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Arc" --aspect 18 \
          --infobox "Downloading latest version ${TAG}" 0 0
        # Download update file
        STATUS=$(curl --insecure -w "%{http_code}" -L \
          "https://github.com/AuxXxilium/arc/releases/download/${TAG}/update.zip" -o "${TMP_PATH}/update.zip")
        if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Arc" --aspect 18 \
            --msgbox "Error downloading update file" 0 0
          return 1
        fi
        unzip -o "${TMP_PATH}/update.zip" -d "${TMP_PATH}"
        rm -f "${TMP_PATH}/update.zip"
        if [ $? -ne 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Arc" --aspect 18 \
            --msgbox "Error extracting update file" 0 0
          return 1
        fi
        # Check checksums
        (cd "${TMP_PATH}" && sha256sum --status -c sha256sum)
        if [ $? -ne 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Arc" --aspect 18 \
            --msgbox "Checksum do not match!" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Arc" --aspect 18 \
          --infobox "Installing new files" 0 0
        # Process update-list.yml
        while read -r F; do
          [ -f "${F}" ] && rm -f "${F}"
          [ -d "${F}" ] && rm -Rf "${F}"
        done < <(readConfigArray "remove" "${TMP_PATH}/update-list.yml")
        while IFS=': ' read -r KEY VALUE; do
          if [ "${KEY: -1}" = "/" ]; then
            rm -rf "${VALUE}"
            mkdir -p "${VALUE}"
            tar -zxf "${TMP_PATH}/$(basename "${KEY}").tgz" -C "${VALUE}"
          else
            mkdir -p "$(dirname "${VALUE}")"
            mv "${TMP_PATH}/$(basename "${KEY}")" "${VALUE}"
          fi
        done < <(readConfigMap "replace" "${TMP_PATH}/update-list.yml")
        dialog --backtitle "$(backtitle)" --title "Update Arc" --aspect 18 \
          --yesno "Arc updated with success to ${TAG}!\nReboot?" 0 0
        [ $? -ne 0 ] && continue
        arpl-reboot.sh config
        exit
        ;;
      3)
        dialog --backtitle "$(backtitle)" --title "Update addons" --aspect 18 \
          --infobox "Checking latest version" 0 0
        TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ $? -ne 0 ] || [ -z "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Update addons" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update addons" --aspect 18 \
          --infobox "Downloading latest version: ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o "${TMP_PATH}/addons.zip")
        if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
          dialog --backtitle "$(backtitle)" --title "Update addons" --aspect 18 \
            --msgbox "Error downloading new version" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update addons" --aspect 18 \
          --infobox "Extracting latest version" 0 0
        rm -rf "${ADDONS_PATH}"
        mkdir -p "${ADDONS_PATH}"
        unzip -o "${TMP_PATH}/addons.zip" -d "${ADDONS_PATH}" >/dev/null 2>&1
        dialog --backtitle "$(backtitle)" --title "Update addons" --aspect 18 \
          --infobox "Installing new addons" 0 0
        for PKG in $(ls ${ADDONS_PATH}/*.addon); do
          ADDON=$(basename ${PKG} | sed 's|.addon||')
          rm -rf "${ADDONS_PATH}/${ADDON}"
          mkdir -p "${ADDONS_PATH}/${ADDON}"
          tar -xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
          rm -f "${ADDONS_PATH}/${ADDON}.addon"
        done
        rm -f "${TMP_PATH}/addons.zip"
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update addons" --aspect 18 \
          --msgbox "Addons updated with success! ${TAG}" 0 0
        ;;
      4)
        dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
          --infobox "Checking latest version" 0 0
        TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ $? -ne 0 ] || [ -z "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
          --infobox "Downloading latest version" 0 0
        STATUS=$(curl -k -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip" -o "${TMP_PATH}/modules.zip")
        if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
            --msgbox "Error downloading latest version" 0 0
          return 1
        fi
        rm -rf "${MODULES_PATH}"
        mkdir -p "${MODULES_PATH}"
        unzip -o "${TMP_PATH}/modules.zip" -d "${MODULES_PATH}" >/dev/null 2>&1
        # Rebuild modules if model/build is selected
        if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          while read -r ID DESC; do
            writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
          done < <(getAllModules "${PLATFORM}" "${KVER}")
        fi
        rm -f "${TMP_PATH}/modules.zip"
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
          --msgbox "Modules updated to ${TAG} with success!" 0 0
        ;;
      5)
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --infobox "Checking latest version" 0 0
        TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-configs/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ $? -ne 0 ] || [ -z "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --infobox "Downloading latest version: ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs.zip" -o "${TMP_PATH}/configs.zip")
        if [ $? -ne 0 ] || [] ${STATUS} -ne 200 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
            --msgbox "Error downloading latest version" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --infobox "Extracting latest version" 0 0
        rm -rf "${MODEL_CONFIG_PATH}"
        mkdir -p "${MODEL_CONFIG_PATH}"
        unzip -o "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}" >/dev/null 2>&1
        rm -f "${TMP_PATH}/configs.zip"
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --msgbox "Configs updated with success! ${TAG}" 0 0
        ;;
      6)
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --infobox "Checking latest version" 0 0
        TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ $? -ne 0 ] || [ -z "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --infobox "Downloading latest version: ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o "${TMP_PATH}/rp-lkms.zip")
        if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
          dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
            --msgbox "Error downloading latest version" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --infobox "Extracting latest version" 0 0
        rm -rf "${LKM_PATH}"
        mkdir -p "${LKM_PATH}"
        unzip -o "${TMP_PATH}/rp-lkms.zip" -d "${LKM_PATH}" >/dev/null 2>&1
        rm -f "${TMP_PATH}/rp-lkms.zip"
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --msgbox "LKMs updated with success! ${TAG}" 0 0
        ;;
      0) return ;;
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
  deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Show Storagemenu to user
function networkMenu() {
  # Get Network Config for Loader
  getnet
  deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Shows Systeminfo to user
function sysinfo() {
  # Checks for Systeminfo Menu
  CPUINFO="$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')"
  CPUCORES="$(awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo)"
  if [ "${EFI}" -eq "1" ]; then
    BOOTSYS="EFI"
  elif [ "${EFI}" -eq "0" ]; then
    BOOTSYS="Legacy"
  fi
  VENDOR=$(dmidecode -s system-product-name)
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ -n "${CONFDONE}" ]; then
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
    REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
    ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
    DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
    DIRECTDSM="$(readConfigKey "arc.directdsm" "${USER_CONFIG_FILE}")"
    ONLINEMODE="$(readConfigKey "arc.onlinemode" "${USER_CONFIG_FILE}")"
    USBMOUNT="$(readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}")"
    LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
    MODULESINFO=""
    KOLIST=""
    for I in $(lsmod | awk -F' ' '{print $1}' | grep -v 'Module'); do
      KOLIST+="$(getdepends ${PLATFORM} ${KVER} ${I}) ${I} "
    done
    KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
    for ID in ${KOLIST[@]}; do
      MODULESINFO+="${ID} "
    done
  fi
  NETRL_NUM="$(ls /sys/class/net/ | grep eth | wc -l)"
  IPLIST="$(ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p')"
  if [ "${REMAP}" = "1" ] || [ "${REMAP}" = "2" ]; then
    PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
    DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
  elif [ "${REMAP}" = "3" ]; then
    PORTMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
  fi
  if [ -n "${CONFDONE}" ]; then
    ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  fi
  MODULESVERSION=$(cat "${MODULES_PATH}/VERSION")
  ADDONSVERSION=$(cat "${ADDONS_PATH}/VERSION")
  LKMVERSION=$(cat "${LKM_PATH}/VERSION")
  CONFIGSVERSION=$(cat "${MODEL_CONFIG_PATH}/VERSION")
  TEXT=""
  # Print System Informations
  TEXT+="\n\Z4> System\Zn"
  TEXT+="\nTyp | Boot: \Zb${MACHINE} | ${BOOTSYS}\Zn"
  TEXT+="\nVendor: \Zb${VENDOR}\Zn"
  TEXT+="\nCPU | Cores: \Zb${CPUINFO} | ${CPUCORES}\Zn"
  TEXT+="\nMemory: \Zb$((${RAMTOTAL}/1024))GB\Zn"
  TEXT+="\nNetwork: \Zb${NETRL_NUM} Adapter\Zn"
  TEXT+="\nIP(s): \Zb${IPLIST}\Zn\n"
  # Print Config Informations
  TEXT+="\n\Z4> Arc\Zn"
  TEXT+="\nArc Version: \Zb${ARPL_VERSION}\Zn"
  TEXT+="\nSubversion: \ZbModules ${MODULESVERSION} | Addons ${ADDONSVERSION} | LKM ${LKMVERSION} | Configs ${CONFIGSVERSION}\Zn"
  TEXT+="\n\Z4>> DSM\Zn"
  TEXT+="\nModel | Platform: \Zb${MODEL} | ${PLATFORM}\Zn"
  TEXT+="\nDSM | Kernel | LKM: \Zb${PRODUCTVER} | ${KVER} | ${LKM}\Zn"
  TEXT+="\n\Z4>> Loader\Zn"
  if [ -n "${CONFDONE}" ]; then
    TEXT+="\nConfig | Build: \ZbComplete | "
  else
    TEXT+="\nConfig | Build: \ZbIncomplete | "
  fi
  if [ -n "${BUILDDONE}" ]; then
    TEXT+="Complete\Zn"
  else
    TEXT+="Incomplete\Zn"
  fi
  TEXT+="\nArcpatch | Onlinemode: \Zb${ARCPATCH} | ${ONLINEMODE}\Zn"
  TEXT+="\nDirectboot | DirectDSM: \Zb${DIRECTBOOT} | ${DIRECTDSM}\Zn"
  TEXT+="\nLoad Kernel: \Zb${KERNELLOAD}\Zn"
  TEXT+="\n\Z4>> Extensions\Zn"
  TEXT+="\nAddons loaded: \Zb${ADDONSINFO}\Zn"
  TEXT+="\nModules loaded: \Zb${MODULESINFO}\Zn"
  TEXT+="\n\Z4>> Settings\Zn"
  if [ "${REMAP}" = "1" ] || [ "${REMAP}" == "2" ]; then
    TEXT+="\nSataPortMap | DiskIdxMap: \Zb${PORTMAP} | ${DISKMAP}\Zn"
  elif [ "${REMAP}" = "3" ]; then
    TEXT+="\nSataRemap: \Zb${PORTMAP}\Zn"
  elif [ "${REMAP}" = "0" ]; then
    TEXT+="\nPortMap: \Zb"User"\Zn"
  fi
  TEXT+="\nUSB Mount: \Zb${USBMOUNT}\Zn\n"
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS
  TEXT+="\n\Z4> Storage\Zn"
  # Get Information for Sata Controller
  if [ "${SATACONTROLLER}" -gt "0" ]; then
    NUMPORTS=0
    for PCI in $(lspci -nnk | grep -ie "\[0106\]" | awk '{print$1}'); do
      NAME="$(lspci -s "${PCI}" | sed "s/\ .*://")"
      # Get Amount of Drives connected
      SATADRIVES="$(ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l)"
      TEXT+="\n\Z1SATA Controller\Zn detected:\n\Zb"${NAME}"\Zn\n"
      TEXT+="\Z1Drives\Zn detected:\n\Zb"${SATADRIVES}"\Zn\n"
      TEXT+="\n\ZbPorts: "
      unset HOSTPORTS
      declare -A HOSTPORTS
      while read -r LINE; do
        ATAPORT="$(echo ${LINE} | grep -o 'ata[0-9]*')"
        PORT=$(echo ${ATAPORT} | sed 's/ata//')
        HOSTPORTS[${PORT}]=$(echo ${LINE} | grep -o 'host[0-9]*$')
      done < <(ls -l /sys/class/scsi_host | fgrep "${PCI}")
      while read -r PORT; do
        ls -l /sys/block | fgrep -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
        PCMD=$(cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd)
        [ "${PCMD}" = "0" ] && DUMMY=1 || DUMMY=0
        [ "${ATTACH}" = "1" ] && TEXT+="\Z2\Zb"
        [ "${DUMMY}" = "1" ] && TEXT+="\Z1"
        [ "${DUMMY}" = "0" ] && [ "${ATTACH}" = "0" ] && TEXT+="\Zb"
        TEXT+="${PORT}\Zn "
        NUMPORTS=$((${NUMPORTS}+1))
      done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
      TEXT+="\n "
    done
    TEXT+="\n\ZbTotal Ports: \Z2\Zb${NUMPORTS}\Zn\n"
  fi
  # Get Information for SAS Controller
  if [ "${SASCONTROLLER}" -gt "0" ]; then
    for PCI in $(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print$1}'); do
      # Get Name of Controller
      NAME="$(lspci -s "${PCI}" | sed "s/\ .*://")"
      # Get Amount of Drives connected
      SASDRIVES="$(ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l)"
      TEXT+="\n\Z1SAS/SCSI Controller\Zn detected:\n\Zb${NAME}\Zn\n"
      TEXT+="\Z1Drives\Zn detected:\n\Zb${SASDRIVES}\Zn\n"
    done
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Sysinfo" --aspect 18 --colors --msgbox "${TEXT}" 0 0
}

###############################################################################
# Try to recovery a DSM already installed
function tryRecoveryDSM() {
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
            cp "${DSMROOT_PATH}/.syno/patch/zImage" "${SLPART_PATH}"
            cp "${DSMROOT_PATH}/.syno/patch/rd.gz" "${SLPART_PATH}"
            MSG="Installation found:\nModel: ${MODEL}\nVersion: ${PRODUCTVER}"
            SN=$(_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf")
            if [ -n "${SN}" ]; then
              deleteConfigKey "arc.patch" "${USER_CONFIG_FILE}"
              SNARC="$(readModelKey "${MODEL}" "arc.serial")"
              writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
              MSG+="\nSerial: ${SN}"
              if [ "${SN}" = "${SNARC}" ]; then
                writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
                ARCAV="Arc"
              else
                writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
                ARCAV="nonArc"
              fi
              ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
              MSG+="\nArc Patch: ${ARCPATCH}"
            fi
            dialog --backtitle "$(backtitle)" --title "Try to recover DSM" \
              --aspect 18 --msgbox "${MSG}" 0 0
            ARCRECOVERY="true"
            arcbuild
          fi
        fi
      fi
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Try recovery DSM" --aspect 18 \
      --msgbox "Unfortunately I couldn't mount the DSM partition!" 0 0
  fi
}


 ###############################################################################
# allow downgrade dsm version
function downgradeMenu() {
  MSG=""
  MSG+="This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n"
  MSG+="Therefore, please insert all disks before continuing.\n"
  MSG+="Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?"
  dialog --backtitle "$(backtitle)" --title "Allow downgrade installation" \
      --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return
  (
    mkdir -p "${TMP_PATH}/sdX1"
    for I in $(ls /dev/sd*1 2>/dev/null | grep -v ${LOADER_DISK}1); do
      mount "${I}" "${TMP_PATH}/sdX1"
      [ -f "${TMP_PATH}/sdX1/etc/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc/VERSION"
      [ -f "${TMP_PATH}/sdX1/etc.defaults/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc.defaults/VERSION"
      sync
      umount "${I}"
    done
    rm -rf "${TMP_PATH}/sdX1"
  ) | dialog --backtitle "$(backtitle)" --title "Allow downgrade installation" \
      --progressbox "Removing ..." 20 70
  MSG="Remove VERSION file for all disks completed."
  dialog --backtitle "$(backtitle)" --colors --aspect 18 \
    --msgbox "${MSG}" 0 0
}

###############################################################################
# Reset DSM password
function resetPassword() {
  SHADOW_FILE=""
  mkdir -p "${TMP_PATH}/sdX1"
  for I in $(ls /dev/sd*1 2>/dev/null | grep -v ${LOADER_DISK}1); do
    mount "${I}" "${TMP_PATH}/sdX1"
    if [ -f "${TMP_PATH}/sdX1/etc/shadow" ]; then
      cp "${TMP_PATH}/sdX1/etc/shadow" "${TMP_PATH}/shadow_bak"
      SHADOW_FILE="${TMP_PATH}/shadow_bak"
    fi
    umount ${I}
    [ -n "${SHADOW_FILE}" ] && break
  done
  rm -rf "${TMP_PATH}/sdX1"
  if [ -z "${SHADOW_FILE}" ]; then
    dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
      --msgbox "No DSM found in the currently inserted disks!" 0 0
    return
  fi
  ITEMS="$(cat ${SHADOW_FILE} | awk -F ':' '{if ($2 != "*" && $2 != "!!") {print $1;}}')"
  dialog --clear --no-items --backtitle "$(backtitle)" --title "Reset DSM Password" \
        --menu "Choose a user name" 0 0 0 ${ITEMS} 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  USER=$(<"${TMP_PATH}/resp")
  [ -z "${USER}" ] && return
  OLDPASSWD=$(cat ${SHADOW_FILE} | grep "^${USER}:" | awk -F ':' '{print $2}')

  while true; do
    dialog --backtitle "$(backtitle)" --title "Reset DSM Password" \
      --inputbox "Type a new password for user ${USER}" 0 0 "${CMDLINE[${NAME}]}" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break 2
    VALUE="$(<"${TMP_PATH}/resp")"
    [ -n "${VALUE}" ] && break
    dialog --backtitle "$(backtitle)" --title "Reset syno system password" --msgbox "Invalid password" 0 0
  done
  NEWPASSWD=$(python -c "import crypt,getpass;pw=\"${VALUE}\";print(crypt.crypt(pw))")
  (
    mkdir -p "${TMP_PATH}/sdX1"
    for I in $(ls /dev/sd*1 2>/dev/null | grep -v ${LOADER_DISK}1); do
      mount "${I}" "${TMP_PATH}/sdX1"
      sed -i "s|${OLDPASSWD}|${NEWPASSWD}|g" "${TMP_PATH}/sdX1/etc/shadow"
      sync
      umount ${I}
    done
    rm -rf "${TMP_PATH}/sdX1"
  ) | dialog --backtitle "$(backtitle)" --title "Reset DSM Password" \
      --progressbox "Resetting ..." 20 70
  [ -f "${SHADOW_FILE}" ] && rm -rf "${SHADOW_FILE}"
  dialog --backtitle "$(backtitle)" --colors --aspect 18 \
    --msgbox "Password reset completed." 0 0
}

###############################################################################
# modify modules to fix mpt3sas module
function mptFix() {
  dialog --backtitle "$(backtitle)" --title "LSI HBA Fix" \
      --yesno "Warning:\nDo you want to modify your Config to fix LSI HBA's. Continue?" 0 0
  [ $? -ne 0 ] && return
  deleteConfigKey "modules.scsi_transport_sas" "${USER_CONFIG_FILE}"
  deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# modify bootipwaittime
function bootipwaittime() {
      ITEMS="$(echo -e "5 \n10 \n20 \n30 \n60 \n")"
      dialog --backtitle "$(backtitle)" --colors --title "Boot IP Waittime" \
        --default-item "${BOOTIPWAIT}" --no-items --menu "Choose a Waitingtime(seconds)" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
      [ -z "${resp}" ] && return
      BOOTIPWAIT=${resp}
      writeConfigKey "bootipwait" "${BOOTIPWAIT}" "${USER_CONFIG_FILE}"
}

###############################################################################
# allow user to save modifications to disk
function saveMenu() {
  dialog --backtitle "$(backtitle)" --title "Save to Disk" \
      --yesno "Warning:\nDo not terminate midway, otherwise it may cause damage to the arc. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return
  dialog --backtitle "$(backtitle)" --title "Save to Disk" \
      --infobox "Saving ..." 0 0 
  RDXZ_PATH=${TMP_PATH}/rdxz_tmp
  mkdir -p "${RDXZ_PATH}"
  (cd "${RDXZ_PATH}"; xz -dc < "/mnt/p3/initrd-arpl" | cpio -idm) >/dev/null 2>&1 || true
  rm -rf "${RDXZ_PATH}/opt/arpl"
  cp -rf "/opt" "${RDXZ_PATH}"
  (cd "${RDXZ_PATH}"; find . 2>/dev/null | cpio -o -H newc -R root:root | xz --check=crc32 >"/mnt/p3/initrd-arpl") || true
  rm -rf "${RDXZ_PATH}"
  dialog --backtitle "$(backtitle)" --colors --aspect 18 \
    --msgbox "Save to Disk is complete." 0 0
}

###############################################################################
# let user format disks from inside arc
function formatdisks() {
  ITEMS=""
  while read -r POSITION NAME; do
    [ -z "${POSITION}" ] || [ -z "${NAME}" ] && continue
    echo "${POSITION}" | grep -q "${LOADER_DEVICE_NAME}" && continue
    ITEMS+="$(printf "%s %s off " "${POSITION}" "${NAME}")"
  done < <(ls -l /dev/disk/by-id/ | sed 's|../..|/dev|g' | grep -E "/dev/sd*" | awk -F' ' '{print $NF" "$(NF-2)}' | sort -uk 1,1)
  dialog --backtitle "$(backtitle)" --title "Format disk" \
    --checklist "Advanced" 0 0 0 ${ITEMS} 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp=$(<"${TMP_PATH}/resp")
  if [ -z "${resp}" ]; then
    dialog --backtitle "$(backtitle)" --title "Format disk" \
      --msgbox "No Sata or NVMe Disks found." 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --title "Format disk" \
      --yesno "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return
  if [ $(ls /dev/md* | wc -l) -gt 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Format disk" \
        --yesno "Warning:\nThe current hds is in raid, do you still want to format them?" 0 0
    [ $? -ne 0 ] && return
    for I in $(ls /dev/md*); do
      mdadm -S ${I}
    done
  fi
  (
    for I in ${resp}; do
      mkfs.ext4 -T largefile4 ${I}
    done
  ) | dialog --backtitle "$(backtitle)" --title "Format disk" \
      --progressbox "Formatting ..." 20 70
  dialog --backtitle "$(backtitle)" --colors --aspect 18 \
    --msgbox "Formatting is complete." 0 0
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  [ "${BUILDDONE}" -ne "1" ] && dialog --backtitle "$(backtitle)" --title "Alert" \
    --yesno "Config changed, would you like to rebuild the loader?" 0 0
  if [ $? -eq 0 ]; then
    make || return
  fi
  if [ "${DIRECTBOOT}" = "false" ]; then
    grub-editenv "${GRUB_PATH}/grubenv" create
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Booting to DSM - Please stay patient!" 0 0
  sleep 2
  exec reboot
}

###############################################################################
###############################################################################

if [ "x$1" = "xb" -a -n "${MODEL}" -a -n "${PRODUCTVER}" ]; then
  install-addons.sh
  make
  boot && exit 0 || sleep 3
fi

# Main loop
[ -n "${MODEL}" ] && NEXT="4" || NEXT="1"
while true; do
  echo "= \"\Z4========== Main ==========\Zn \" "                                            >"${TMP_PATH}/menu"
  echo "1 \"Choose Model for Loader \" "                                                    >>"${TMP_PATH}/menu"
  if [ -n "${CONFDONE}" ]; then
    echo "4 \"Build Loader \" "                                                             >>"${TMP_PATH}/menu"
  fi
  if [ -n "${BUILDDONE}" ]; then
    echo "5 \"Boot Loader \" "                                                              >>"${TMP_PATH}/menu"
  fi
  echo "= \"\Z4========== Info ==========\Zn \" "                                           >>"${TMP_PATH}/menu"
  echo "a \"Sysinfo \" "                                                                    >>"${TMP_PATH}/menu"
  echo "= \"\Z4========= System =========\Zn \" "                                           >>"${TMP_PATH}/menu"
  if [ -n "${CONFDONE}" ]; then
    echo "2 \"Addons \" "                                                                   >>"${TMP_PATH}/menu"
    echo "3 \"Modules \" "                                                                  >>"${TMP_PATH}/menu"
    if [ -n "${ARCOPTS}" ]; then
      echo "7 \"\Z1Hide Arc Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    else
      echo "7 \"\Z1Show Arc Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    fi
    if [ -n "${ARCOPTS}" ]; then
      echo "= \"\Z4========== Arc ==========\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "v \"Change DSM Version \" "                                                     >>"${TMP_PATH}/menu"
      if [ "${DT}" != "true" ] && [ "${SATACONTROLLER}" -gt 0 ]; then
        echo "s \"Change Storage Map \" "                                                   >>"${TMP_PATH}/menu"
      fi
      echo "n \"Change Network Config \" "                                                  >>"${TMP_PATH}/menu"
      echo "u \"Change USB Port Config \" "                                                 >>"${TMP_PATH}/menu"
      echo "w \"Allow DSM Downgrade \" "                                                    >>"${TMP_PATH}/menu"
      echo "x \"Reset DSM Password \" "                                                     >>"${TMP_PATH}/menu"
      echo "k \"Load Kernel: \Z4${KERNELLOAD}\Zn \" "                                       >>"${TMP_PATH}/menu"
      if [ "${DIRECTBOOT}" = "false" ]; then
        echo "b \"Boot IP Waittime: \Z4${BOOTIPWAIT}\Zn \" "                                >>"${TMP_PATH}/menu"
      fi
      echo "+ \"\Z1Format Disk(s)\Zn \" "                                                   >>"${TMP_PATH}/menu"
      echo "= \"\Z4=========================\Zn \" "                                        >>"${TMP_PATH}/menu"
    fi
    if [ -n "${ADVOPTS}" ]; then
      echo "8 \"\Z1Hide Advanced Options\Zn \" "                                            >>"${TMP_PATH}/menu"
    else
      echo "8 \"\Z1Show Advanced Options\Zn \" "                                            >>"${TMP_PATH}/menu"
    fi
    if [ -n "${ADVOPTS}" ]; then
      echo "= \"\Z4======== Advanced =======\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "f \"Cmdline \" "                                                                >>"${TMP_PATH}/menu"
      echo "g \"Synoinfo \" "                                                               >>"${TMP_PATH}/menu"
      echo "h \"Edit User Config \" "                                                       >>"${TMP_PATH}/menu"
      echo "m \"Not set Boot MAC: \Z4${NOTSETMAC}\Zn \" "                                   >>"${TMP_PATH}/menu"
      echo "d \"Directboot: \Z4${DIRECTBOOT}\Zn \" "                                        >>"${TMP_PATH}/menu"
      if [ "${DIRECTBOOT}" = "true" ]; then
        echo "l \"Reset DirectDSM: \Z4${DIRECTDSM}\Zn \" "                                  >>"${TMP_PATH}/menu"
      fi
      echo "= \"\Z4=========================\Zn \" "                                        >>"${TMP_PATH}/menu"
    fi
    if [ -n "${DEVOPTS}" ]; then
      echo "9 \"\Z1Hide Dev Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    else
      echo "9 \"\Z1Show Dev Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    fi
    if [ -n "${DEVOPTS}" ]; then
      echo "= \"\Z4========== Dev ==========\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "j \"Switch LKM version: \Z4${LKM}\Zn \" "                                       >>"${TMP_PATH}/menu"
      echo "z \"Save Modifications to Disk \" "                                             >>"${TMP_PATH}/menu"
      echo "= \"\Z4=========================\Zn \" "                                        >>"${TMP_PATH}/menu"
    fi
  fi
  echo "t \"Backup/Restore \" "                                                             >>"${TMP_PATH}/menu"
  echo "i \"Recover from DSM \" "                                                           >>"${TMP_PATH}/menu"
  echo "= \"\Z4===== Loader Settings ====\Zn \" "                                           >>"${TMP_PATH}/menu"
  echo "c \"Choose a keymap \" "                                                            >>"${TMP_PATH}/menu"
  echo "e \"Update \" "                                                                     >>"${TMP_PATH}/menu"
  echo "0 \"\Z1Exit\Zn \" "                                                                 >>"${TMP_PATH}/menu"

  dialog --clear --default-item ${NEXT} --backtitle "$(backtitle)" --colors \
    --menu "Choose an Option" 0 0 0 --file "${TMP_PATH}/menu" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && break
  case $(<"${TMP_PATH}/resp") in
    # Main Section
    1) arcMenu; NEXT="4" ;;
    4) make; NEXT="5" ;;
    5) boot && exit 0 ;;
    # Info Section
    a) sysinfo; NEXT="a" ;;
    # System Section
    2) addonMenu; NEXT="2" ;;
    3) modulesMenu; NEXT="3" ;;
    # Arc Section
    7) [ "${ARCOPTS}" = "" ] && ARCOPTS='1' || ARCOPTS=''
       ARCOPTS="${ARCOPTS}"
       NEXT="7"
       ;;
    v) ONLYVERSION="true" && arcbuild; NEXT="v" ;;
    s) storageMenu; NEXT="s" ;;
    n) networkMenu; NEXT="n" ;;
    u) usbMenu; NEXT="u" ;;
    p) paturl; NEXT="p" ;;
    w) downgradeMenu; NEXT="w" ;;
    x) resetPassword; NEXT="x" ;;
    k)
      [ "${KERNELLOAD}" = "kexec" ] && KERNELLOAD='power' || KERNELLOAD='kexec'
      writeConfigKey "arc.kernelload" "${KERNELLOAD}" "${USER_CONFIG_FILE}"
      NEXT="k"
      ;;
    b) bootipwaittime; NEXT="b" ;;
    +) formatdisks; NEXT="+" ;;
    # Advanced Section
    8) [ "${ADVOPTS}" = "" ] && ADVOPTS='1' || ADVOPTS=''
       ADVOPTS="${ADVOPTS}"
       NEXT="8"
       ;;
    f) cmdlineMenu; NEXT="f" ;;
    g) synoinfoMenu; NEXT="g" ;;
    h) editUserConfig; NEXT="h" ;;
    m) [ "${NOTSETMAC}" = "false" ] && NOTSETMAC='true' || NOTSETMAC='false'
      writeConfigKey "arc.notsetmac" "${NOTSETMAC}" "${USER_CONFIG_FILE}"
      NEXT="m"
      ;;
    d) [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
      writeConfigKey "arc.directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
      NEXT="d"
      ;;
    l)
      writeConfigKey "arc.directdsm" "false" "${USER_CONFIG_FILE}"
      DIRECTDSM="$(readConfigKey "arc.directdsm" "${USER_CONFIG_FILE}")"
      NEXT="l"
      ;;
    # Dev Section
    9) [ "${DEVOPTS}" = "" ] && DEVOPTS='1' || DEVOPTS=''
      DEVOPTS="${DEVOPTS}"
      NEXT="9"
      ;;
    j) [ "${LKM}" = "prod" ] && LKM='dev' || LKM='prod'
      writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
      NEXT="j"
      ;;
    z) saveMenu; NEXT="z" ;;
    # System Section 2
    t) backupMenu; NEXT="t" ;;
    i) tryRecoveryDSM; NEXT="i" ;;
    # Loader Settings
    c) keymapMenu; NEXT="c" ;;
    e) updateMenu; NEXT="e" ;;
    0) break ;;
  esac
done
clear

# Inform user
echo -e "Call \033[1;31marc.sh\033[0m to configure loader"
echo
echo -e "Access:"
echo -e "IP: \033[1;31m${IP}\033[0m"
echo -e "User: \033[1;31mroot\033[0m"
echo -e "Password: \033[1;31marc\033[0m"
echo
echo -e "Web Terminal Access:"
echo -e "Address: \033[1;31mhttp://${IP}:5000\033[0m"
