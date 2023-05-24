#!/usr/bin/env bash

. /opt/arpl/include/functions.sh
. /opt/arpl/include/addons.sh
. /opt/arpl/include/modules.sh
. /opt/arpl/include/checkmodules.sh
. /opt/arpl/include/storage.sh
. /opt/arpl/include/network.sh

# Check partition 3 space, if < 2GiB is necessary clean cache folder
CLEARCACHE=0
LOADER_DISK="`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`"
LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
if [ `cat /sys/block/${LOADER_DEVICE_NAME}/${LOADER_DEVICE_NAME}3/size` -lt 4194304 ]; then
  CLEARCACHE=1
fi

# Get actual IP
IP=`ip route 2>/dev/null | sed -n 's/.* via .* dev \(.*\)  src \(.*\)  metric .*/\1: \2 /p' | head -1`

# Get Number of Ethernet Ports
NETNUM=`lshw -class network -short | grep -ie "eth[0-9]" | wc -l`
[ ${NETNUM} -gt 8 ] && NETNUM=8 && WARNON=3

# Memory: Check Memory installed
RAMTOTAL=0
while read -r line; do
  RAMSIZE=$line
  RAMTOTAL=$((RAMTOTAL +RAMSIZE))
done <<< "`dmidecode -t memory | grep -i "Size" | cut -d" " -f2 | grep -i [1-9]`"
RAMTOTAL=$((RAMTOTAL *1024))

# Check for Hypervisor
if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
  MACHINE="VIRTUAL"
  # Check for Hypervisor
  HYPERVISOR="`lscpu | grep Hypervisor | awk '{print $3}'`"
else
  MACHINE="NATIVE"
fi

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1

# Dirty flag
DIRTY=0

MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
LAYOUT="`readConfigKey "layout" "${USER_CONFIG_FILE}"`"
KEYMAP="`readConfigKey "keymap" "${USER_CONFIG_FILE}"`"
LKM="`readConfigKey "lkm" "${USER_CONFIG_FILE}"`"
DIRECTBOOT="`readConfigKey "arc.directboot" "${USER_CONFIG_FILE}"`"
DIRECTDSM="`readConfigKey "arc.directdsm" "${USER_CONFIG_FILE}"`"
BACKUPBOOT="`readConfigKey "arc.backupboot" "${USER_CONFIG_FILE}"`"
SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"
CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
ARCPATCH="`readConfigKey "arc.patch" "${USER_CONFIG_FILE}"`"

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="Arc v${ARPL_VERSION} |"
  if [ -n "${MODEL}" ]; then
    BACKTITLE+=" ${MODEL}"
  else
    BACKTITLE+=" (no model)"
  fi
  BACKTITLE+=" |"
  if [ -n "${BUILD}" ]; then
    [ "${BUILD}" = "42962" ] && VER="7.1.1"
    [ "${BUILD}" = "64561" ] && VER="7.2.0"
    BACKTITLE+=" ${VER}"
  else
    BACKTITLE+=" (no build)"
  fi
  BACKTITLE+=" |"
  if [ -n "${SN}" ]; then
    BACKTITLE+=" ${SN}"
  else
    BACKTITLE+=" (no SN)"
  fi
  BACKTITLE+=" |"
  if [ -n "${IP}" ]; then
    BACKTITLE+=" ${IP}"
  else
    BACKTITLE+=" (no IP)"
  fi
  BACKTITLE+=" |"
  if [ "${ARCPATCH}" == "true" ]; then
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
  BACKTITLE+=" |"
  if [ -n "${EFI}" ]; then
    BACKTITLE+=" EFI: Y"
  else
    BACKTITLE+=" EFI: N"
  fi
  echo ${BACKTITLE}
}

###############################################################################
# Make Model Config
function arcMenu() {
  if [ -z "${1}" ]; then
    # Start ARC build process
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
  else
    if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
    resp="${1}"
  fi
  if [ -z "${1}" ]; then
  # Loop menu
  RESTRICT=1
  FLGBETA=0
  dialog --backtitle "`backtitle`" --title "Model" --aspect 18 \
    --infobox "Reading models" 0 0
  while true; do
    echo "" > "${TMP_PATH}/menu"
    FLGNEX=0
    while read M; do
      M="`basename ${M}`"
      M="${M::-4}"
      MID="`readModelKey "${M}" "id"`"
      PLATFORM="`readModelKey "${M}" "platform"`"
      DT="`readModelKey "${M}" "dt"`"
      BETA="`readModelKey "${M}" "beta"`"
      [ "${BETA}" = "true" -a ${FLGBETA} -eq 0 ] && continue
      DISKS="`readModelKey "${M}" "disks"`"
      if [ "${PLATFORM}" = "r1000" ] || [ "${PLATFORM}" = "v1000" ]; then
        CPU="AMD"
      else
        CPU="Intel"
      fi
      # Check id model is compatible with CPU
      COMPATIBLE=1
      if [ ${RESTRICT} -eq 1 ]; then
        for F in "`readModelArray "${M}" "flags"`"; do
          if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
            COMPATIBLE=0
            FLGNEX=1
            break
          fi
        done
        for F in "`readModelArray "${M}" "dt"`"; do
          if [ "${DT}" = "true" ] && [ "${SASCONTROLLER}" -gt 0 ]; then
            COMPATIBLE=0
            FLGNEX=1
            break
          fi
        done
      fi
      [ "${DT}" = "true" ] && DT="-DT" || DT=""
      [ ${COMPATIBLE} -eq 1 ] && echo -e "${MID} \"\Zb${DISKS}-Bay\Zn \t\Zb${CPU}\Zn \t\Zb${PLATFORM}${DT}\Zn\" " >> "${TMP_PATH}/menu"
    done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
    [ ${FLGBETA} -eq 0 ] && echo "b \"\Z1Show beta Models\Zn\"" >> "${TMP_PATH}/menu"
    [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1Show incompatible Models \Zn\"" >> "${TMP_PATH}/menu"
    dialog --backtitle "`backtitle`" --colors --menu "Choose Model for Arc" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
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
  # Read model config for buildconfig
  if [ "${MODEL}" != "${resp}" ]; then
    MODEL=${resp}
    DT="`readModelKey "${resp}" "dt"`"
    if [ "${DT}" = "true" ] && [ "${SASCONTROLLER}" -gt 0 ]; then
      # There is no Raid/SCSI Support for DT Models
      WARNON=2
    fi
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    deleteConfigKey "arc.confdone" "${USER_CONFIG_FILE}"
    deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
    # Delete old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
    rm -f "${TMP_PATH}/patdownloadurl"
    DIRTY=1
  fi
  arcbuild
}

###############################################################################
# Shows menu to user type one or generate randomly
function arcbuild() {
  # Select Build for DSM
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a DSM Version (Support)" 0 0 0 \
      1 "DSM 7.1.1 (Stable)" \
      2 "DSM 7.2.0 (Beta)" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "1" ]; then
      BUILD="42962"
      writeConfigKey "build" "${BUILD}" "${USER_CONFIG_FILE}"
      break
    elif [ "${resp}" = "2" ]; then
      BUILD="64561"
      writeConfigKey "build" "${BUILD}" "${USER_CONFIG_FILE}"
      break
    fi
  done
  # Read model values for buildconfig
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose an option" 0 0 0 \
      1 "Install with Arc Patch" \
      2 "Install without Arc Patch" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "1" ]; then
      #if [ "${EFI}" -eq 1 ]; then
        SN="`readModelKey "${MODEL}" "arc.serial"`"
        writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
        writeConfigKey "addons.powersched" "" "${USER_CONFIG_FILE}"
        writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
        dialog --backtitle "`backtitle`" --title "Arc Config" \
              --msgbox "Installing with Arc Patch\nSuccessfull!" 0 0
      #else
      #  dialog --backtitle "`backtitle`" --title "Arc Config" \
      #        --msgbox "Installing with Arc Patch\nFailed! Please select EFI as Bootmode.\nOtherwise Arc Patch will not work!" 0 0
      #  return 1
      #fi
      break
    elif [ "${resp}" = "2" ]; then
      # Generate random serial
      SN="`generateSerial "${MODEL}"`"
      writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
      dialog --backtitle "`backtitle`" --title "Arc Config" \
      --msgbox "Installing without Arc Patch!" 0 0
      break
    fi
  done
  ARCPATCH="`readConfigKey "arc.patch" "${USER_CONFIG_FILE}"`"
  dialog --backtitle "`backtitle`" --title "Arc Config" \
    --infobox "Reconfiguring Synoinfo, Addons and Modules" 0 0
  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read KEY VALUE; do
    writeConfigKey "synoinfo.${KEY}" "${VALUE}" "${USER_CONFIG_FILE}"
  done < <(readModelMap "${MODEL}" "builds.${BUILD}.synoinfo")
  # Memory: Set mem_max_mb to the amount of installed memory
  writeConfigKey "synoinfo.mem_max_mb" "${RAMTOTAL}" "${USER_CONFIG_FILE}"
  # Check addons
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      deleteConfigKey "addons.${ADDON}" "${USER_CONFIG_FILE}"
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Rebuild modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read ID DESC; do
    writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
  done < <(getAllModules "${PLATFORM}" "${KVER}")
  # Remove old files
  rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  rm -f "${TMP_PATH}/patdownloadurl"
  DIRTY=1
  dialog --backtitle "`backtitle`" --title "Arc Config" \
    --infobox "Model Configuration successfull!" 0 0
  sleep 1
  arcnetdisk
}


###############################################################################
# Make Network and Disk Config
function arcnetdisk() {
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  DT="`readModelKey "${MODEL}" "dt"`"
  # Get Network Config for Loader
  getnet
  # Only load getmap when Sata Controller are dedected and no DT Model is selected
  if [ "${SATACONTROLLER}" -gt 0 ] && [ "${DT}" != "true" ]; then
    # Config for Sata Controller with PortMap to get all drives
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --infobox "SATA Controller found. Need PortMap for Controller!" 0 0
    # Get Portmap for Loader
    getmap
  fi
  # Write Sasidxmap if SAS Controller are dedected
  #[ "${SASCONTROLLER}" -gt 0 ] && writeConfigKey "cmdline.SasIdxMap" "0" "${USER_CONFIG_FILE}"
  #[ "${SASCONTROLLER}" -eq 0 ] && deleteConfigKey "cmdline.SasIdxMap" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.SasIdxMap" "${USER_CONFIG_FILE}"
  # Config is done
  writeConfigKey "arc.confdone" "1" "${USER_CONFIG_FILE}"
  dialog --backtitle "`backtitle`" --title "Arc Config" \
    --infobox "Configuration successfull!" 0 0
  sleep 1
  DIRTY=1
  CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
  if [ "${WARNON}" = "1" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Warning" \
      --msgbox "WARN: Your Controller has more than 8 Disks connected. Max Disks per Controller: 8" 0 0
  fi
  if [ "${WARNON}" = "2" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Warning" \
      --msgbox "WARN: You have selected a DT Model. There is no support for Raid/SCSI Controller." 0 0
  fi
  if [ "${WARNON}" = "3" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Warning" \
      --msgbox "WARN: You have more than 8 Ethernet Ports. There are only 8 supported by Redpill." 0 0
  fi
  # Ask for Build
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Build now?" 0 0 0 \
      1 "Yes - Build Arc Loader now" \
      2 "No - I want to make changes" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "1" ]; then
      make
      break
    elif [ "${resp}" = "2" ]; then
      dialog --clear --no-items --backtitle "`backtitle`"
      break
    fi
  done
}

###############################################################################
# Building Loader
function make() {
  clear
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"

  # Check if all addon exists
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
        --msgbox "`printf "Addon %s not found!" "${ADDON}"`" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

  if [ ! -f "${ORI_ZIMAGE_FILE}" -o ! -f "${ORI_RDGZ_FILE}" ]; then
    extractDsmFiles
    [ $? -ne 0 ] && return 1
  fi

  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "zImage not patched:\n`<"${LOG_FILE}"`" 0 0
    return 1
  fi

  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "Ramdisk not patched:\n`<"${LOG_FILE}"`" 0 0
    return 1
  fi

  echo "Cleaning"
  rm -rf "${UNTAR_PAT_PATH}"

  echo "Ready!"
  sleep 3
  DIRTY=0
  # Set DirectDSM to false
  writeConfigKey "arc.directdsm" "false" "${USER_CONFIG_FILE}"
  grub-editenv ${GRUB_PATH}/grubenv create
  # Build is done
  writeConfigKey "arc.builddone" "1" "${USER_CONFIG_FILE}"
  BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
  # Ask for Boot
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Build done. Boot now?" 0 0 0 \
      1 "Yes - Boot Arc Loader now" \
      2 "No - I want to make changes" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
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
# Extracting DSM for building Loader
function extractDsmFiles() {
  PAT_URL="`readModelKey "${MODEL}" "builds.${BUILD}.pat.url"`"
  PAT_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.hash"`"
  RAMDISK_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.ramdisk-hash"`"
  ZIMAGE_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.zimage-hash"`"

  SPACELEFT=`df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print$4}'`  # Check disk space left

  PAT_FILE="${MODEL}-${BUILD}.pat"
  PAT_PATH="${CACHE_PATH}/dl/${PAT_FILE}"
  EXTRACTOR_PATH="${CACHE_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"
  OLDPAT_URL="https://global.download.synology.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"


  if [ -f "${PAT_PATH}" ]; then
    echo "${PAT_FILE} cached."
  else
    # If we have little disk space, clean cache folder
    if [ ${CLEARCACHE} -eq 1 ]; then
      echo "Cleaning cache"
      rm -rf "${CACHE_PATH}/dl"
    fi
    mkdir -p "${CACHE_PATH}/dl"

    speed_a=`ping -c 1 -W 5 global.synologydownload.com | awk '/time=/ {print $7}' | cut -d '=' -f 2`
    speed_b=`ping -c 1 -W 5 global.download.synology.com | awk '/time=/ {print $7}' | cut -d '=' -f 2`
    fastest="`echo -e "global.synologydownload.com ${speed_a:-999}\nglobal.download.synology.com ${speed_b:-999}" | sort -k2rn | head -1 | awk '{print $1}'`"

    mirror="`echo ${PAT_URL} | sed 's|^http[s]*://\([^/]*\).*|\1|'`"
    if [ "${mirror}" != "${fastest}" ]; then
      echo "`printf "Based on the current network situation, switch to %s mirror for download." "${fastest}"`"
      PAT_URL="`echo ${PAT_URL} | sed "s/${mirror}/${fastest}/"`"
      OLDPAT_URL="https://${fastest}/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
    fi
    echo ${PAT_URL} > "${TMP_PATH}/patdownloadurl"
    echo "Downloading ${PAT_FILE}"
    # Discover remote file size
    FILESIZE=`curl -k -sLI "${PAT_URL}" | grep -i Content-Length | awk '{print$2}'`
    if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
      # No disk space to download, change it to RAMDISK
      PAT_PATH="${TMP_PATH}/${PAT_FILE}"
    fi
    STATUS=`curl -k -w "%{http_code}" -L "${PAT_URL}" -o "${PAT_PATH}" --progress-bar`
    if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
      rm "${PAT_PATH}"
      dialog --backtitle "`backtitle`" --title "Error downloading" --aspect 18 \
        --msgbox "Check internet or cache disk space" 0 0
      return 1
    fi
  fi

  echo -n "Checking hash of ${PAT_FILE}: "
  if [ "`sha256sum ${PAT_PATH} | awk '{print$1}'`" != "${PAT_HASH}" ]; then
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "Hash of pat not match, try again!" 0 0
    rm -f ${PAT_PATH}
    return 1
  fi
  echo "OK"

  rm -rf "${UNTAR_PAT_PATH}"
  mkdir "${UNTAR_PAT_PATH}"
  echo -n "Disassembling ${PAT_FILE}: "

  header="$(od -bcN2 ${PAT_PATH} | head -1 | awk '{print $3}')"
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
      dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
        --msgbox "Could not determine if pat file is encrypted or not, maybe corrupted, try again!" \
        0 0
      return 1
      ;;
  esac

  SPACELEFT=`df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print $4}'`  # Check disk space left

  if [ "${isencrypted}" = "yes" ]; then
    # Check existance of extractor
    if [ -f "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" ]; then
      echo "Extractor cached."
    else
      # Extractor not exists, get it.
      mkdir -p "${EXTRACTOR_PATH}"
      # Check if old pat already downloaded
      OLDPAT_PATH="${CACHE_PATH}/dl/DS3622xs+-42218.pat"
      if [ ! -f "${OLDPAT_PATH}" ]; then
        echo "Downloading old pat to extract synology .pat extractor..."
        # Discover remote file size
        FILESIZE=`curl --insecure -sLI "${OLDPAT_URL}" | grep -i Content-Length | awk '{print$2}'`
        if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
          # No disk space to download, change it to RAMDISK
          OLDPAT_PATH="${TMP_PATH}/DS3622xs+-42218.pat"
        fi
        STATUS=`curl --insecure -w "%{http_code}" -L "${OLDPAT_URL}" -o "${OLDPAT_PATH}"  --progress-bar`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          rm "${OLDPAT_PATH}"
          dialog --backtitle "`backtitle`" --title "Error downloading" --aspect 18 \
            --msgbox "Check internet or cache disk space" 0 0
          return 1
        fi
      fi
      # Extract DSM ramdisk file from PAT
      rm -rf "${RAMDISK_PATH}"
      mkdir -p "${RAMDISK_PATH}"
      tar -xf "${OLDPAT_PATH}" -C "${RAMDISK_PATH}" rd.gz >"${LOG_FILE}" 2>&1
      if [ $? -ne 0 ]; then
        rm -f "${OLDPAT_PATH}"
        rm -rf "${RAMDISK_PATH}"
        dialog --backtitle "`backtitle`" --title "Error extracting" --textbox "${LOG_FILE}" 0 0
        return 1
      fi
      [ ${CLEARCACHE} -eq 1 ] && rm -f "${OLDPAT_PATH}"
      # Extract all files from rd.gz
      (cd "${RAMDISK_PATH}"; xz -dc < rd.gz | cpio -idm) >/dev/null 2>&1 || true
      # Copy only necessary files
      for f in libcurl.so.4 libmbedcrypto.so.5 libmbedtls.so.13 libmbedx509.so.1 libmsgpackc.so.2 libsodium.so libsynocodesign-ng-virtual-junior-wins.so.7; do
        cp "${RAMDISK_PATH}/usr/lib/${f}" "${EXTRACTOR_PATH}"
      done
      cp "${RAMDISK_PATH}/usr/syno/bin/scemd" "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}"
      rm -rf "${RAMDISK_PATH}"
    fi
    # Uses the extractor to untar pat file
    echo "Extracting..."
    LD_LIBRARY_PATH=${EXTRACTOR_PATH} "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" "${PAT_PATH}" "${UNTAR_PAT_PATH}" || true
  else
    echo "Extracting..."
    tar -xf "${PAT_PATH}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
    if [ $? -ne 0 ]; then
      dialog --backtitle "`backtitle`" --title "Error extracting" --textbox "${LOG_FILE}" 0 0
    fi
  fi

  echo -n "Checking hash of zImage: "
  HASH="`sha256sum ${UNTAR_PAT_PATH}/zImage | awk '{print$1}'`"
  if [ "${HASH}" != "${ZIMAGE_HASH}" ]; then
    sleep 1
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "Hash of zImage not match, try again!" 0 0
    return 1
  fi
  echo "OK"
  writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"

  echo -n "Checking hash of ramdisk: "
  HASH="`sha256sum ${UNTAR_PAT_PATH}/rd.gz | awk '{print$1}'`"
  if [ "${HASH}" != "${RAMDISK_HASH}" ]; then
    sleep 1
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "Hash of ramdisk not match, try again!" 0 0
    return 1
  fi
  echo "OK"
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"

  echo -n "Copying files: "
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER"        "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER"        "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/zImage"          "${ORI_ZIMAGE_FILE}"
  cp "${UNTAR_PAT_PATH}/rd.gz"           "${ORI_RDGZ_FILE}"
  rm -rf "${UNTAR_PAT_PATH}"
  echo "DSM extract complete" 
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "`backtitle`" --title "Edit with caution" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return
    mv "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=`yq eval "${USER_CONFIG_FILE}" 2>&1`
    [ $? -eq 0 ] && break
    dialog --backtitle "`backtitle`" --title "Invalid YAML format" --msgbox "${ERRORS}" 0 0
  done
  OLDMODEL=${MODEL}
  OLDBUILD=${BUILD}
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
  SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"
  if [ "${MODEL}" != "${OLDMODEL}" -o "${BUILD}" != "${OLDBUILD}" ]; then
    # Remove old files
    rm -f "${MOD_ZIMAGE_FILE}"
    rm -f "${MOD_RDGZ_FILE}"
  fi
  DIRTY=1
  deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
  BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
}

###############################################################################
# Shows option to manage addons
function addonMenu() {
  NEXT="1"
  # Read 'platform' and kernel version to check if addon exists
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  # Read addons from user config
  unset ADDONS
  declare -A ADDONS
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Loop menu
  while true; do
    dialog --backtitle "`backtitle`" --default-item ${NEXT} \
      --menu "Choose an option" 0 0 0 \
      1 "Add an Addon" \
      2 "Delete Addon(s)" \
      3 "Show user Addons" \
      4 "Show all available Addons" \
      0 "Exit" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      1)
        rm "${TMP_PATH}/menu"
        while read ADDON DESC; do
          arrayExistItem "${ADDON}" "${!ADDONS[@]}" && continue          # Check if addon has already been added
          echo "${ADDON} \"${DESC}\"" >> "${TMP_PATH}/menu"
        done < <(availableAddons "${PLATFORM}" "${KVER}")
        if [ ! -f "${TMP_PATH}/menu" ] ; then 
          dialog --backtitle "`backtitle`" --msgbox "No available Addons to add" 0 0 
          NEXT="0"
          continue
        fi
        dialog --backtitle "`backtitle`" --menu "Select an addon" 0 0 0 \
          --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        ADDON="`<"${TMP_PATH}/resp"`"
        [ -z "${ADDON}" ] && continue
        dialog --backtitle "`backtitle`" --title "params" \
          --inputbox "Type a optional params to Addon" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        ADDONS["${ADDON}"]="`<"${TMP_PATH}/resp"`"
        writeConfigKey "addons.${ADDON}" "${VALUE}" "${USER_CONFIG_FILE}"
        DIRTY=1
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        ;;
      2)
        if [ ${#ADDONS[@]} -eq 0 ]; then
          dialog --backtitle "`backtitle`" --msgbox "No user addons to remove" 0 0 
          continue
        fi
        ITEMS=""
        for I in "${!ADDONS[@]}"; do
          ITEMS+="${I} ${I} off "
        done
        dialog --backtitle "`backtitle`" --no-tags \
          --checklist "Select Addon to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        ADDON="`<"${TMP_PATH}/resp"`"
        [ -z "${ADDON}" ] && continue
        for I in ${ADDON}; do
          unset ADDONS[${I}]
          deleteConfigKey "addons.${I}" "${USER_CONFIG_FILE}"
        done
        DIRTY=1
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        ;;
      3)
        ITEMS=""
        for KEY in ${!ADDONS[@]}; do
          ITEMS+="${KEY}: ${ADDONS[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "User addons" \
          --msgbox "${ITEMS}" 0 0
        ;;
      4)
        MSG=""
        while read MODULE DESC; do
          if arrayExistItem "${MODULE}" "${!ADDONS[@]}"; then
            MSG+="\Z4${MODULE}\Zn"
          else
            MSG+="${MODULE}"
          fi
          MSG+=": \Z5${DESC}\Zn\n"
        done < <(availableAddons "${PLATFORM}" "${KVER}")
        dialog --backtitle "`backtitle`" --title "Available addons" \
          --colors --msgbox "${MSG}" 0 0
        ;;
      0) return ;;
    esac
  done
}

###############################################################################
# Permit user select the modules to include
function modulesMenu() {
  NEXT="1"
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  dialog --backtitle "`backtitle`" --title "Modules" --aspect 18 \
    --infobox "Reading modules" 0 0
  ALLMODULES=`getAllModules "${PLATFORM}" "${KVER}"`
  unset USERMODULES
  declare -A USERMODULES
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
  done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
  # menu loop
  while true; do
    dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
      1 "Show selected Modules" \
      2 "Select all Modules" \
      3 "Deselect all Modules" \
      4 "Choose Modules to include" \
      5 "Automated Module selection" \
      6 "Add external module" \
      0 "Exit" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case "`<${TMP_PATH}/resp`" in
      1)
        ITEMS=""
        for KEY in ${!USERMODULES[@]}; do
          ITEMS+="${KEY}: ${USERMODULES[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "User modules" \
          --msgbox "${ITEMS}" 0 0
        ;;
      2)
        dialog --backtitle "`backtitle`" --title "Modules" \
           --infobox "Selecting all modules" 0 0
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        while read ID DESC; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done <<<${ALLMODULES}
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        ;;
      3)
        dialog --backtitle "`backtitle`" --title "Modules" \
           --infobox "Deselecting all modules" 0 0
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        unset USERMODULES
        declare -A USERMODULES
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        ;;
      4)
        rm -f "${TMP_PATH}/opts"
        while read ID DESC; do
          arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
          echo "${ID} ${DESC} ${ACT}" >> "${TMP_PATH}/opts"
        done <<<${ALLMODULES}
        dialog --backtitle "`backtitle`" --title "Modules" --aspect 18 \
          --checklist "Select modules to include" 0 0 0 \
          --file "${TMP_PATH}/opts" 2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        resp=$(<${TMP_PATH}/resp)
        [ -z "${resp}" ] && continue
        dialog --backtitle "`backtitle`" --title "Modules" \
           --infobox "Writing to user config" 0 0
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        for ID in ${resp}; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        ;;
      5)
        dialog --backtitle "`backtitle`" --title "Modules" \
           --infobox "Automated selection" 0 0
        getModules
        LOADED="`readConfigMap "modules" "${USER_CONFIG_FILE}" | tr -d ':'`"
        dialog --backtitle "`backtitle`" --title "Modules" \
           --msgbox "Modules:\n${LOADED}" 0 0
        ;;
      6)
        MSG=""
        MSG+="This function is experimental and dangerous. If you don't know much, please exit.\n"
        MSG+="The imported .ko of this function will be implanted into the corresponding arch's modules package, which will affect all models of the arch.\n"
        MSG+="This program will not determine the availability of imported modules or even make type judgments, as please double check if it is correct.\n"
        MSG+="If you want to remove it, please go to the \"Update Menu\" -> \"Update modules\" to forcibly update the modules. All imports will be reset.\n"
        MSG+="Do you want to continue?"
        dialog --backtitle "`backtitle`" --title "Add external module" \
            --yesno "${MSG}" 0 0
        [ $? -ne 0 ] && return
        dialog --backtitle "`backtitle`" --aspect 18 --colors --inputbox "Please enter the complete URL to download.\n" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        URL="`<"${TMP_PATH}/resp"`"
        [ -z "${URL}" ] && continue
        clear
        echo "Downloading ${URL}"
        STATUS=`curl -kLJO -w "%{http_code}" "${URL}" --progress-bar`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "Add external module" --aspect 18 \
            --msgbox "ERROR: Check internet, URL or cache disk space" 0 0
          return 1
        fi
        KONAME=$(basename "$URL")
        if [ -n "${KONAME}" -a "${KONAME##*.}" = "ko" ]; then
          addToModules ${PLATFORM} ${KVER} ${KONAME}
          dialog --backtitle "`backtitle`" --title "Add external module" --aspect 18 \
            --msgbox "Module ${KONAME} added to ${PLATFORM}-${KVER}" 0 0
          rm -f ${KONAME}
        else
          dialog --backtitle "`backtitle`" --title "Add external module" --aspect 18 \
            --msgbox "File format not recognized!" 0 0
        fi
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
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
  done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
  echo "1 \"Add/edit a Cmdline item\""                          > "${TMP_PATH}/menu"
  echo "2 \"Delete Cmdline item(s)\""                           >> "${TMP_PATH}/menu"
  echo "3 \"Define a custom MAC\""                              >> "${TMP_PATH}/menu"
  echo "4 \"Show user Cmdline\""                                >> "${TMP_PATH}/menu"
  echo "5 \"Show Model/Build Cmdline\""                         >> "${TMP_PATH}/menu"
  echo "0 \"Exit\""                                             >> "${TMP_PATH}/menu"
  # Loop menu
  while true; do
    dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      1)
        dialog --backtitle "`backtitle`" --title "User cmdline" \
          --inputbox "Type a name of cmdline" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        NAME="`sed 's/://g' <"${TMP_PATH}/resp"`"
        [ -z "${NAME}" ] && continue
        dialog --backtitle "`backtitle`" --title "User cmdline" \
          --inputbox "Type a value of '${NAME}' cmdline" 0 0 "${CMDLINE[${NAME}]}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        VALUE="`<"${TMP_PATH}/resp"`"
        CMDLINE[${NAME}]="${VALUE}"
        writeConfigKey "cmdline.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        ;;
      2)
        if [ ${#CMDLINE[@]} -eq 0 ]; then
          dialog --backtitle "`backtitle`" --msgbox "No user cmdline to remove" 0 0 
          continue
        fi
        ITEMS=""
        for I in "${!CMDLINE[@]}"; do
          [ -z "${CMDLINE[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${CMDLINE[${I}]} off "
        done
        dialog --backtitle "`backtitle`" \
          --checklist "Select cmdline to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        RESP=`<"${TMP_PATH}/resp"`
        [ -z "${RESP}" ] && continue
        for I in ${RESP}; do
          unset CMDLINE[${I}]
          deleteConfigKey "cmdline.${I}" "${USER_CONFIG_FILE}"
        done
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        ;;
      3)
        for i in $(seq 1 ${NETNUM}); do
          RET=1
          while true; do
            dialog --backtitle "`backtitle`" --title "User cmdline" \
              --inputbox "`Type a custom MAC address of %s" "eth$(expr ${i} - 1)`" 0 0 "${CMDLINE["mac${i}"]}" \
              2>${TMP_PATH}/resp
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            MAC="`<"${TMP_PATH}/resp"`"
            [ -z "${MAC}" ] && MAC="`readConfigKey "original-mac${i}" "${USER_CONFIG_FILE}"`"
            MACF="`echo "${MAC}" | sed 's/://g'`"
            [ ${#MACF} -eq 12 ] && break
            dialog --backtitle "`backtitle`" --title "User cmdline" --msgbox "Invalid MAC" 0 0
          done
          if [ ${RET} -eq 0 ]; then
            CMDLINE["mac${i}"]="${MACF}"
            CMDLINE["netif_num"]="${NETNUM}"
            writeConfigKey "cmdline.mac${i}"      "${MACF}" "${USER_CONFIG_FILE}"
            writeConfigKey "cmdline.netif_num"    "${NETNUM}"  "${USER_CONFIG_FILE}"
            MAC="${MACF:0:2}:${MACF:2:2}:${MACF:4:2}:${MACF:6:2}:${MACF:8:2}:${MACF:10:2}"
            ip link set dev eth$(expr ${i} - 1) address ${MAC} 2>&1 | dialog --backtitle "`backtitle`" \
              --title "User cmdline" --progressbox "Changing MAC" 20 70
            /etc/init.d/S41dhcpcd restart 2>&1 | dialog --backtitle "`backtitle`" \
              --title "User cmdline" --progressbox "Renewing IP" 20 70
          fi
        done
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        IP=`ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1`
        ;;
      4)
        ITEMS=""
        for KEY in ${!CMDLINE[@]}; do
          ITEMS+="${KEY}: ${CMDLINE[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "User cmdline" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      5)
        ITEMS=""
        while IFS=': ' read KEY VALUE; do
          ITEMS+="${KEY}: ${VALUE}\n"
        done < <(readModelMap "${MODEL}" "builds.${BUILD}.cmdline")
        dialog --backtitle "`backtitle`" --title "Model/build cmdline" \
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
  # Read synoinfo from user config
  unset SYNOINFO
  declare -A SYNOINFO
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
  done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "1 \"Add/edit Synoinfo item\""     > "${TMP_PATH}/menu"
  echo "2 \"Delete Synoinfo item(s)\""    >> "${TMP_PATH}/menu"
  echo "3 \"Show Synoinfo entries\""      >> "${TMP_PATH}/menu"
  echo "0 \"Exit\""                       >> "${TMP_PATH}/menu"

  # menu loop
  while true; do
    dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      1)
        dialog --backtitle "`backtitle`" --title "Synoinfo entries" \
          --inputbox "Type a name of synoinfo entry" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        NAME="`<"${TMP_PATH}/resp"`"
        [ -z "${NAME}" ] && continue
        dialog --backtitle "`backtitle`" --title "Synoinfo entries" \
          --inputbox "Type a value of '${NAME}' entry" 0 0 "${SYNOINFO[${NAME}]}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        VALUE="`<"${TMP_PATH}/resp"`"
        SYNOINFO[${NAME}]="${VALUE}"
        writeConfigKey "synoinfo.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
        DIRTY=1
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        ;;
      2)
        if [ ${#SYNOINFO[@]} -eq 0 ]; then
          dialog --backtitle "`backtitle`" --msgbox "No synoinfo entries to remove" 0 0 
          continue
        fi
        ITEMS=""
        for I in "${!SYNOINFO[@]}"; do
          [ -z "${SYNOINFO[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${SYNOINFO[${I}]} off "
        done
        dialog --backtitle "`backtitle`" \
          --checklist "Select synoinfo entry to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        RESP=`<"${TMP_PATH}/resp"`
        [ -z "${RESP}" ] && continue
        for I in ${RESP}; do
          unset SYNOINFO[${I}]
          deleteConfigKey "synoinfo.${I}" "${USER_CONFIG_FILE}"
        done
        DIRTY=1
        deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
        BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
        ;;
      3)
        ITEMS=""
        for KEY in ${!SYNOINFO[@]}; do
          ITEMS+="${KEY}: ${SYNOINFO[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "Synoinfo entries" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      0) return ;;
    esac
  done
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  dialog --backtitle "`backtitle`" --default-item "${LAYOUT}" --no-items \
    --menu "Choose a Layout" 0 0 0 "azerty" "bepo" "carpalx" "colemak" \
    "dvorak" "fgGIod" "neo" "olpc" "qwerty" "qwertz" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  LAYOUT="`<${TMP_PATH}/resp`"
  OPTIONS=""
  while read KM; do
    OPTIONS+="${KM::-7} "
  done < <(cd /usr/share/keymaps/i386/${LAYOUT}; ls *.map.gz)
  dialog --backtitle "`backtitle`" --no-items --default-item "${KEYMAP}" \
    --menu "Choice a keymap" 0 0 0 ${OPTIONS} \
    2>/tmp/resp
  [ $? -ne 0 ] && return
  resp=`cat /tmp/resp 2>/dev/null`
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
  BUILDDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
  if [ -n "${CONFDONE}" ]; then
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Mount USB as Internal" \
        2 "Mount USB as Normal" \
        0 "Exit" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      case "`<${TMP_PATH}/resp`" in
        1)
          MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
          PLATFORM=`readModelKey "${MODEL}" "platform"`
          if [ "${PLATFORM}" = "broadwellnk" ]; then
            writeConfigKey "synoinfo.maxdisks" "24" "${USER_CONFIG_FILE}"
            writeConfigKey "synoinfo.usbportcfg" "0xff0000" "${USER_CONFIG_FILE}"
            writeConfigKey "synoinfo.internalportcfg" "0xffffff" "${USER_CONFIG_FILE}"
            writeConfigKey "arc.usbmount" "true" "${USER_CONFIG_FILE}"
            dialog --backtitle "`backtitle`" --title "Mount USB as Internal" \
            --aspect 18 --msgbox "Mount USB as Internal - successfull!" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Mount USB as Internal" \
            --aspect 18 --msgbox "You need to select a broadwellnk model!" 0 0
          fi
          ;;
        2)
          MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
          PLATFORM=`readModelKey "${MODEL}" "platform"`
          if [ "${PLATFORM}" = "broadwellnk" ]; then
            deleteConfigKey "synoinfo.maxdisks" "${USER_CONFIG_FILE}"
            deleteConfigKey "synoinfo.usbportcfg" "${USER_CONFIG_FILE}"
            deleteConfigKey "synoinfo.internalportcfg" "${USER_CONFIG_FILE}"
            writeConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
            dialog --backtitle "`backtitle`" --title "Mount USB as Normal" \
            --aspect 18 --msgbox "Mount USB as Normal - successfull!" 0 0
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
  BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
  if [ -n "${BUILDDONE}" ]; then
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Backup Config" \
        2 "Restore Config" \
        3 "Backup DSM Bootimage" \
        4 "Restore DSM Bootimage" \
        5 "Backup Config with Code" \
        6 "Restore Config with Code" \
        7 "Show Backup Path" \
        0 "Exit" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      case "`<${TMP_PATH}/resp`" in
        1)
          dialog --backtitle "`backtitle`" --title "Backup Config" --aspect 18 \
            --infobox "Backup Config to ${BACKUPDIR}" 0 0
          if [ ! -d "${BACKUPDIR}" ]; then
            # Make backup dir
            mkdir ${BACKUPDIR}
          else
            # Clean old backup
            rm -f ${BACKUPDIR}/user-config.yml
          fi
          # Copy config to backup
          cp -f ${USER_CONFIG_FILE} ${BACKUPDIR}/user-config.yml
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            dialog --backtitle "`backtitle`" --title "Backup Config" --aspect 18 \
              --msgbox "Backup complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Backup Config" --aspect 18 \
              --msgbox "Backup error" 0 0
          fi
          ;;
        2)
          dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
            --infobox "Restore Config from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            # Copy config back to location
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
              --msgbox "No Config Backup found" 0 0
          fi
          CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
          deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
          BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
          ;;
        3)
          dialog --backtitle "`backtitle`" --title "Backup DSM Bootimage" --aspect 18 \
            --infobox "Backup DSM Bootimage to ${BACKUPDIR}" 0 0
          if [ ! -d "${BACKUPDIR}" ]; then
            # Make backup dir
            mkdir ${BACKUPDIR}
          else
            # Clean old backup
            rm -f ${BACKUPDIR}/dsm-backup.tar
          fi
          # Copy files to backup
          cp -f ${USER_CONFIG_FILE} ${BACKUPDIR}/user-config.yml
          cp -f ${CACHE_PATH}/zImage-dsm ${BACKUPDIR}
          cp -f ${CACHE_PATH}/initrd-dsm ${BACKUPDIR}
          # Compress backup
          tar -cvf ${BACKUPDIR}/dsm-backup.tar ${BACKUPDIR}/
          # Clean temp files from backup dir
          rm -f ${BACKUPDIR}/user-config.yml
          rm -f ${BACKUPDIR}/zImage-dsm
          rm -f ${BACKUPDIR}/initrd-dsm
          if [ -f "${BACKUPDIR}/dsm-backup.tar" ]; then
            dialog --backtitle "`backtitle`" --title "Backup DSM Bootimage" --aspect 18 \
              --msgbox "Backup complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Backup DSM Bootimage" --aspect 18 \
              --msgbox "Backup error" 0 0
          fi
          ;;
        4)
          dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
            --infobox "Restore DSM Bootimage from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/dsm-backup.tar" ]; then
            # Uncompress backup
            tar -xvf ${BACKUPDIR}/dsm-backup.tar -C /
            # Copy files to locations
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            cp -f ${BACKUPDIR}/zImage-dsm ${CACHE_PATH}
            cp -f ${BACKUPDIR}/initrd-dsm ${CACHE_PATH}
            # Clean temp files from backup dir
            rm -f ${BACKUPDIR}/user-config.yml
            rm -f ${BACKUPDIR}/zImage-dsm
            rm -f ${BACKUPDIR}/initrd-dsm
            CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
            BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
            dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
              --msgbox "No DSM Bootimage Backup found" 0 0
          fi
          ;;
        5)
          dialog --backtitle "`backtitle`" --title "Backup Config with Code" \
              --infobox "Write down your Code for Restore!" 0 0
          if [ -f "${USER_CONFIG_FILE}" ]; then
            GENHASH=`cat /mnt/p1/user-config.yml | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-`
            dialog --backtitle "`backtitle`" --title "Backup Config with Code" --msgbox "Your Code: ${GENHASH}" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Backup Config with Code" --msgbox "No Config for Backup found!" 0 0
          fi
          ;;
        6)
          while true; do
            dialog --backtitle "`backtitle`" --title "Restore Config with Code" \
              --inputbox "Type your Code here!" 0 0 \
              2>${TMP_PATH}/resp
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            GENHASH="`<"${TMP_PATH}/resp"`"
            [ ${#GENHASH} -eq 9 ] && break
            dialog --backtitle "`backtitle`" --title "Restore with Code" --msgbox "Invalid Code" 0 0
          done
          curl -k https://dpaste.com/${GENHASH}.txt > /tmp/user-config.yml
          mv -f /tmp/user-config.yml /mnt/p1/user-config.yml
          ;;
        7)
          dialog --backtitle "`backtitle`" --title "Backup Path" --aspect 18 \
            --msgbox "Open in Explorer: \\\\${IP}\arpl\p3\backup" 0 0
          ;;
        0) return ;;
      esac
    done
  else
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Restore Config" \
        2 "Restore DSM Bootimage" \
        3 "Restore Config with Code" \
        4 "Show Backup Path" \
        0 "Exit" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      case "`<${TMP_PATH}/resp`" in
        1)
          dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
            --infobox "Restore Config from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            # Copy config back to location
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
              --msgbox "No Config Backup found" 0 0
          fi
          CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
          deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
          BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
          ;;
        2)
          dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
            --infobox "Restore DSM Bootimage from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/dsm-backup.tar" ]; then
            # Uncompress backup
            tar -xvf ${BACKUPDIR}/dsm-backup.tar -C /
            # Copy files to locations
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            cp -f ${BACKUPDIR}/zImage-dsm ${CACHE_PATH}
            cp -f ${BACKUPDIR}/initrd-dsm ${CACHE_PATH}
            # Clean temp files from backup dir
            rm -f ${BACKUPDIR}/user-config.yml
            rm -f ${BACKUPDIR}/zImage-dsm
            rm -f ${BACKUPDIR}/initrd-dsm
            CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
            BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
            dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
              --msgbox "No Loader Backup found" 0 0
          fi
          ;;
        3)
          while true; do
            dialog --backtitle "`backtitle`" --title "Restore with Code" \
              --inputbox "Type your Code here!" 0 0 \
              2>${TMP_PATH}/resp
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            GENHASH="`<"${TMP_PATH}/resp"`"
            [ ${#GENHASH} -eq 9 ] && break
            dialog --backtitle "`backtitle`" --title "Restore with Code" --msgbox "Invalid Code" 0 0
          done
          curl -k https://dpaste.com/${GENHASH}.txt > /tmp/user-config.yml
          mv -f /tmp/user-config.yml /mnt/p1/user-config.yml
          CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
          BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
          dialog --backtitle "`backtitle`" --title "Restore with Code" --aspect 18 \
              --msgbox "Restore complete" 0 0
          ;;
        4)
          dialog --backtitle "`backtitle`" --title "Backup Path" --aspect 18 \
            --msgbox "Open in Explorer: \\\\${IP}\arpl\p3\backup" 0 0
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
  CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
  if [ -n "${CONFDONE}" ]; then
    PLATFORM="`readModelKey "${MODEL}" "platform"`"
    KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Full upgrade Loader" \
        2 "Update Arc Loader" \
        3 "Update Addons" \
        4 "Update LKMs" \
        5 "Update Modules" \
        0 "Exit" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      case "`<${TMP_PATH}/resp`" in
        1)
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Checking latest version" 0 0
          ACTUALVERSION="v${ARPL_VERSION}"
          TAG="`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          if [ "${ACTUALVERSION}" = "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
            [ $? -ne 0 ] && continue
          fi
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Downloading latest version ${TAG}" 0 0
          # Download update file
          STATUS=`curl --insecure -w "%{http_code}" -L \
            "https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}.img.zip" -o /tmp/arc-${TAG}.img.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error downloading update file" 0 0
            continue
          fi
          unzip -o /tmp/arc-${TAG}.img.zip -d /tmp
          if [ $? -ne 0 ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error extracting update file" 0 0
            continue
          fi
          if [ -f "${USER_CONFIG_FILE}" ]; then
            GENHASH=`cat /mnt/p1/user-config.yml | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-`
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --msgbox "Backup config successfull!\nWrite down your Code: ${GENHASH}\n\nAfter Reboot use: Backup - Restore with Code." 0 0
          else
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "No config for Backup found!" 0 0
          fi
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Installing new Image" 0 0
          # Process complete update
          umount /mnt/p1 /mnt/p2 /mnt/p3
          dd if="/tmp/arc.img" of=`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1` bs=1M conv=fsync
          # Ask for Boot
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --yesno "Arc updated with success to ${TAG}!\nReboot?" 0 0
          [ $? -ne 0 ] && continue
          arpl-reboot.sh config
          exit
          ;;
        2)
          dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
            --infobox "Checking latest version" 0 0
          ACTUALVERSION="v${ARPL_VERSION}"
          TAG="`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          if [ "${ACTUALVERSION}" = "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
            [ $? -ne 0 ] && continue
          fi
          dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
            --infobox "Downloading latest version ${TAG}" 0 0
          # Download update file
          STATUS=`curl --insecure -w "%{http_code}" -L \
            "https://github.com/AuxXxilium/arc/releases/download/${TAG}/update.zip" -o /tmp/update.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --msgbox "Error downloading update file" 0 0
            continue
          fi
          unzip -oq /tmp/update.zip -d /tmp
          if [ $? -ne 0 ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --msgbox "Error extracting update file" 0 0
            continue
          fi
          # Check checksums
          (cd /tmp && sha256sum --status -c sha256sum)
          if [ $? -ne 0 ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --msgbox "Checksum do not match!" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
            --infobox "Installing new files" 0 0
          # Process update-list.yml
          while read F; do
            [ -f "${F}" ] && rm -f "${F}"
            [ -d "${F}" ] && rm -Rf "${F}"
          done < <(readConfigArray "remove" "/tmp/update-list.yml")
          while IFS=': ' read KEY VALUE; do
            if [ "${KEY: -1}" = "/" ]; then
              rm -Rf "${VALUE}"
              mkdir -p "${VALUE}"
              tar -zxf "/tmp/`basename "${KEY}"`.tgz" -C "${VALUE}"
            else
              mkdir -p "`dirname "${VALUE}"`"
              mv "/tmp/`basename "${KEY}"`" "${VALUE}"
            fi
          done < <(readConfigMap "replace" "/tmp/update-list.yml")
          dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
            --yesno "Arc updated with success to ${TAG}!\nReboot?" 0 0
          [ $? -ne 0 ] && continue
          arpl-reboot.sh config
          exit
          ;;
        3)
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --infobox "Checking latest version" 0 0
          TAG=`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --infobox "Downloading latest version: ${TAG}" 0 0
          STATUS=`curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o /tmp/addons.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
              --msgbox "Error downloading new version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --infobox "Extracting latest version" 0 0
          rm -rf /tmp/addons
          mkdir -p /tmp/addons
          unzip /tmp/addons.zip -d /tmp/addons >/dev/null 2>&1
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --infobox "Installing new addons" 0 0
          rm -Rf "${ADDONS_PATH}/"*
          [ -f /tmp/addons/VERSION ] && cp -f /tmp/addons/VERSION ${ADDONS_PATH}/
          for PKG in `ls /tmp/addons/*.addon`; do
            ADDON=`basename ${PKG} | sed 's|.addon||'`
            rm -rf "${ADDONS_PATH}/${ADDON}"
            mkdir -p "${ADDONS_PATH}/${ADDON}"
            tar -xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
          done
          DIRTY=1
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --msgbox "Addons updated with success! ${TAG}" 0 0
          ;;
        4)
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --infobox "Checking latest version" 0 0
          TAG=`curl --insecure -s https://api.github.com/repos/AuxXxilium/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --infobox "Downloading latest version: ${TAG}" 0 0
          STATUS=`curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o /tmp/rp-lkms.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
              --msgbox "Error downloading latest version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --infobox "Extracting latest version" 0 0
          rm -rf "${LKM_PATH}/"*
          unzip /tmp/rp-lkms.zip -d "${LKM_PATH}" >/dev/null 2>&1
          DIRTY=1
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --msgbox "LKMs updated with success! ${TAG}" 0 0
          ;;
        5)
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --infobox "Checking latest version" 0 0
          TAG="`curl -k -s "https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest" | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --infobox "Downloading latest version" 0 0
          STATUS="`curl -k -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip" -o "/tmp/modules.zip"`"
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
              --msgbox "Error downloading latest version" 0 0
            continue
          fi
          rm "${MODULES_PATH}/"*
          unzip /tmp/modules.zip -d "${MODULES_PATH}" >/dev/null 2>&1
          # Rebuild modules if model/buildnumber is selected
          if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
            writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
            while read ID DESC; do
              writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
            done < <(getAllModules "${PLATFORM}" "${KVER}")
          fi
          DIRTY=1
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --msgbox "Modules updated to ${TAG} with success!" 0 0
          ;;
        0) return ;;
      esac
    done
  else
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Full upgrade Loader" \
        0 "Exit" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      case "`<${TMP_PATH}/resp`" in
        1)
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Checking latest version" 0 0
          ACTUALVERSION="v${ARPL_VERSION}"
          TAG="`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          if [ "${ACTUALVERSION}" = "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
            [ $? -ne 0 ] && continue
          fi
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Downloading latest version ${TAG}" 0 0
          # Download update file
          STATUS=`curl --insecure -w "%{http_code}" -L \
            "https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}.img.zip" -o /tmp/arc-${TAG}.img.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error downloading update file" 0 0
            continue
          fi
          unzip -o /tmp/arc-${TAG}.img.zip -d /tmp
          if [ $? -ne 0 ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error extracting update file" 0 0
            continue
          fi
          if [ -f "${USER_CONFIG_FILE}" ]; then
            GENHASH=`cat /mnt/p1/user-config.yml | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-`
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --msgbox "Backup config successfull!\nWrite down your Code: ${GENHASH}\n\nAfter Reboot use: Backup - Restore with Code." 0 0
          else
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "No config for Backup found!" 0 0
          fi
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Installing new Image" 0 0
          # Process complete update
          umount /mnt/p1 /mnt/p2 /mnt/p3
          dd if="/tmp/arc.img" of=`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1` bs=1M conv=fsync
          # Ask for Boot
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --yesno "Arc updated with success to ${TAG}!\nReboot?" 0 0
          [ $? -ne 0 ] && continue
          arpl-reboot.sh config
          exit
          ;;
        0) return ;;
      esac
    done
  fi
}

###############################################################################
# Show Storagemenu to user
function storageMenu() {
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  DT="`readModelKey "${MODEL}" "dt"`"
  # Get Portmap for Loader
  getmap
  deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
  BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
}

###############################################################################
# Show Storagemenu to user
function networkMenu() {
  # Get Network Config for Loader
  getnet
  deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
  BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
}

###############################################################################
# Shows Systeminfo to user
function sysinfo() {
  # Delete old Sysinfo
  rm -f ${SYSINFO_PATH}
  # Checks for Systeminfo Menu
  CPUINFO=`awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//'`
  if [ -n "${EFI}" ]; then
    BOOTSYS="EFI"
  else
    BOOTSYS="Legacy"
  fi
  VENDOR=`dmidecode -s system-product-name`
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  IPLIST=`ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p'`
  REMAP="`readConfigKey "arc.remap" "${USER_CONFIG_FILE}"`"
  if [ "${REMAP}" == "1" ] || [ "${REMAP}" == "2" ]; then
    PORTMAP="`readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"`"
    DISKMAP="`readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"`"
  elif [ "${REMAP}" == "3" ]; then
    PORTMAP="`readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"`"
  fi
  CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
  BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
  ARCPATCH="`readConfigKey "arc.patch" "${USER_CONFIG_FILE}"`"
  USBMOUNT="`readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}"`"
  LKM="`readConfigKey "lkm" "${USER_CONFIG_FILE}"`"
  if [ -n "${CONFDONE}" ]; then
    ADDONSINFO="`readConfigEntriesArray "addons" "${USER_CONFIG_FILE}"`"
    getModulesInfo
    MODULESINFO=`cat "${TMP_PATH}/modulesinfo"`
  fi
  MODULESVERSION=`cat "${MODULES_PATH}/VERSION"`
  ADDONSVERSION=`cat "${ADDONS_PATH}/VERSION"`
  LKMVERSION=`cat "${LKM_PATH}/VERSION"`
  TEXT=""
  # Print System Informations
  TEXT+="\n\Z4System:\Zn"
  TEXT+="\nTyp | Boot: \Zb"${MACHINE}" | "${BOOTSYS}"\Zn"
  if [ "$MACHINE" = "VIRTUAL" ]; then
  TEXT+="\nHypervisor: \Zb"${HYPERVISOR}"\Zn"
  fi
  TEXT+="\nVendor: \Zb"${VENDOR}"\Zn"
  TEXT+="\nCPU: \Zb"${CPUINFO}"\Zn"
  TEXT+="\nRAM: \Zb"$((RAMTOTAL /1024))"GB\Zn\n"
  # Print Config Informations
  TEXT+="\n\Z4Config:\Zn"
  TEXT+="\nArc Version: \Zb"${ARPL_VERSION}"\Zn"
  TEXT+="\nSubversion: \ZbModules "${MODULESVERSION}"\Zn | \ZbAddons "${ADDONSVERSION}"\Zn | \ZbLKM "${LKMVERSION}"\Zn"
  TEXT+="\nModel | Build: \Zb"${MODEL}" | "${BUILD}"\Zn"
  if [ -n "${CONFDONE}" ]; then
    TEXT+="\nConfig: \ZbComplete\Zn"
  else
    TEXT+="\nConfig: \ZbIncomplete\Zn"
  fi
  if [ -n "${BUILDDONE}" ]; then
    TEXT+="\nBuild: \ZbComplete\Zn"
  else
    TEXT+="\nBuild: \ZbIncomplete\Zn"
  fi
  if [ -f "${BACKUPDIR}/arc-backup.img.gz" ]; then
    TEXT+="\nBackup: \ZbFull Loader\Zn"
  elif [ -f "${BACKUPDIR}/dsm-backup.tar" ]; then
    TEXT+="\nBackup: \ZbDSM Bootimage\Zn"
  elif [ -f "${BACKUPDIR}/user-config.yml" ]; then
    TEXT+="\nBackup: \ZbOnly Config\Zn"
  else
    TEXT+="\nBackup: \ZbNo Backup found\Zn"
  fi
  TEXT+="\nArcpatch: \Zb"${ARCPATCH}"\Zn"
  TEXT+="\nLKM: \Zb"${LKM}"\Zn"
  TEXT+="\nNetwork: \Zb"${NETNUM}" Adapter\Zn"
  TEXT+="\nIP(s): \Zb"${IPLIST}"\Zn"
  if [ "${REMAP}" == "1" ] || [ "${REMAP}" == "2" ]; then
    TEXT+="\nSataPortMap: \Zb"${PORTMAP}"\Zn | DiskIdxMap: \Zb"${DISKMAP}"\Zn"
  elif [ "${REMAP}" == "3" ]; then
    TEXT+="\nSataRemap: \Zb"${PORTMAP}"\Zn"
  elif [ "${REMAP}" == "0" ]; then
    TEXT+="\nPortMap: \Zb"Set by User"\Zn"
  fi
  TEXT+="\nUSB Mount: \Zb"${USBMOUNT}"\Zn"
  TEXT+="\nAddons loaded: \Zb"${ADDONSINFO}"\Zn"
  TEXT+="\nModules loaded: \Zb"${MODULESINFO}"\Zn\n"
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS
  TEXT+="\n\Z4Storage:\Zn"
  # Get Information for Sata Controller
  if [ "$SATACONTROLLER" -gt "0" ]; then
    NUMPORTS=0
    for PCI in `lspci -nnk | grep -ie "\[0106\]" | awk '{print$1}'`; do
      NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
      # Get Amount of Drives connected
      SATADRIVES=`ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l`
      TEXT+="\n\Z1SATA Controller\Zn detected:\n\Zb"${NAME}"\Zn\n"
      TEXT+="\Z1Drives\Zn detected:\n\Zb"${SATADRIVES}"\Zn\n"
      TEXT+="\n\ZbPorts: "
      unset HOSTPORTS
      declare -A HOSTPORTS
      while read LINE; do
        ATAPORT="`echo ${LINE} | grep -o 'ata[0-9]*'`"
        PORT=`echo ${ATAPORT} | sed 's/ata//'`
        HOSTPORTS[${PORT}]=`echo ${LINE} | grep -o 'host[0-9]*$'`
      done < <(ls -l /sys/class/scsi_host | fgrep "${PCI}")
      while read PORT; do
        ls -l /sys/block | fgrep -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
        PCMD=`cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd`
        [ "${PCMD}" = "0" ] && DUMMY=1 || DUMMY=0
        [ ${ATTACH} -eq 1 ] && TEXT+="\Z2\Zb"
        [ ${DUMMY} -eq 1 ] && TEXT+="\Z1"
        [ ${DUMMY} -eq 0 ] && [ ${ATTACH} -eq 0 ] && TEXT+="\Zb"
        TEXT+="${PORT}\Zn "
        NUMPORTS=$((${NUMPORTS}+1))
      done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
      TEXT+="\n "
    done
    TEXT+="\n\ZbTotal Ports: \Z2\Zb${NUMPORTS}\Zn\n"
  fi
  # Get Information for SAS Controller
  if [ "$SASCONTROLLER" -gt "0" ]; then
    for PCI in `lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print$1}'`; do
      # Get Name of Controller
      NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
      # Get Amount of Drives connected
      SASDRIVES=`ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l`
      TEXT+="\n\Z1SAS Controller\Zn detected:\n\Zb"${NAME}"\Zn\n"
      TEXT+="\Z1Drives\Zn detected:\n\Zb"${SASDRIVES}"\Zn\n"
    done
  fi
  echo -e ${TEXT} > "${SYSINFO_PATH}"
  TEXT+="\nSysinfo File: \Zb"\\\\${IP}\\arpl\\p1\\sysinfo.yml"\Zn"
  dialog --backtitle "`backtitle`" --title "Arc Sysinfo" --aspect 18 --colors --msgbox "${TEXT}" 0 0
}

###############################################################################
# Try to recovery a DSM already installed
function tryRecoveryDSM() {
  dialog --backtitle "`backtitle`" --title "Try to recover DSM" --aspect 18 \
    --infobox "Trying to recover a DSM installed system" 0 0
  if findAndMountDSMRoot; then
    MODEL=""
    BUILD=""
    if [ -f "${DSMROOT_PATH}/.syno/patch/VERSION" ]; then
      eval `cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep unique`
      eval `cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep base`
      if [ -n "${unique}" ] ; then
        while read F; do
          M="`basename ${F}`"
          M="${M::-4}"
          UNIQUE=`readModelKey "${M}" "unique"`
          [ "${unique}" = "${UNIQUE}" ] || continue
          # Found
          modelMenu "${M}"
        done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
        if [ -n "${MODEL}" ]; then
          buildMenu ${base}
          if [ -n "${BUILD}" ]; then
            cp "${DSMROOT_PATH}/.syno/patch/zImage" "${SLPART_PATH}"
            cp "${DSMROOT_PATH}/.syno/patch/rd.gz" "${SLPART_PATH}"
            MSG="Found a installation:\nModel: ${MODEL}\nBuildnumber: ${BUILD}"
            SN=`_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf"`
            if [ -n "${SN}" ]; then
              writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
              MSG+="\nSerial: ${SN}"
            fi
            dialog --backtitle "`backtitle`" --title "Try to recover DSM" \
              --aspect 18 --msgbox "${MSG}" 0 0
          fi
        fi
      fi
    fi
  else
    dialog --backtitle "`backtitle`" --title "Try recovery DSM" --aspect 18 \
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
  dialog --backtitle "`backtitle`" --title "Allow downgrade installation" \
      --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return
  (
    mkdir -p /tmp/sdX1
    for I in `ls /dev/sd*1 2>/dev/null | grep -v ${LOADER_DISK}1`; do
      mount ${I} /tmp/sdX1
      [ -f "/tmp/sdX1/etc/VERSION" ] && rm -f "/tmp/sdX1/etc/VERSION"
      [ -f "/tmp/sdX1/etc.defaults/VERSION" ] && rm -f "/tmp/sdX1/etc.defaults/VERSION"
      sync
      umount ${I}
    done
    rm -rf /tmp/sdX1
  ) | dialog --backtitle "`backtitle`" --title "Allow downgrade installation" \
      --progressbox "Removing ..." 20 70
  MSG="$(TEXT "Remove VERSION file for all disks completed.")"
  dialog --backtitle "`backtitle`" --colors --aspect 18 \
    --msgbox "${MSG}" 0 0
}

###############################################################################
# show .pat download url to user
function paturl() {
  # output pat download link
  if [ ! -f "${TMP_PATH}/patdownloadurl" ]; then
    echo "`readModelKey "${MODEL}" "builds.${BUILD}.pat.url"`" > "${TMP_PATH}/patdownloadurl"
  fi
  dialog --backtitle "`backtitle`" --title "*.pat download link" \
    --editbox "${TMP_PATH}/patdownloadurl" 0 0
}

###############################################################################
# allow user to save modifications to disk
function saveMenu() {
  dialog --backtitle "`backtitle`" --title "Save to Disk" \
      --yesno "Warning:\nDo not terminate midway, otherwise it may cause damage to the arc. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return
  dialog --backtitle "`backtitle`" --title "Save to Disk" \
      --infobox "Saving ..." 0 0 
  RDXZ_PATH=/tmp/rdxz_tmp
  mkdir -p "${RDXZ_PATH}"
  (cd "${RDXZ_PATH}"; xz -dc < "/mnt/p3/initrd-arpl" | cpio -idm) >/dev/null 2>&1 || true
  rm -rf "${RDXZ_PATH}/opt/arpl"
  cp -rf "/opt" "${RDXZ_PATH}"
  (cd "${RDXZ_PATH}"; find . 2>/dev/null | cpio -o -H newc -R root:root | xz --check=crc32 > "/mnt/p3/initrd-arpl") || true
  rm -rf "${RDXZ_PATH}"
  dialog --backtitle "`backtitle`" --colors --aspect 18 \
    --msgbox "Save to Disk is complete." 0 0
}

###############################################################################
# let user format disks from inside arc
function formatdisks() {
  ITEMS=""
  while read POSITION NAME; do
    [ -z "${POSITION}" -o -z "${NAME}" ] && continue
    echo "${POSITION}" | grep -q "${LOADER_DEVICE_NAME}" && continue
    ITEMS+="`printf "%s %s off " "${POSITION}" "${NAME}"`"
  done < <(ls -l /dev/disk/by-id/ | sed 's|../..|/dev|g' | grep -E "/dev/sd[a-z]$" | awk -F' ' '{print $11" "$9}' | sort -uk 1,1)
  dialog --backtitle "`backtitle`" --title "Format disk" \
    --checklist "Advanced" 0 0 0 ${ITEMS} 2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  RESP=`<"${TMP_PATH}/resp"`s
  if [ -z "${RESP}" ]; then
    dialog --backtitle "`backtitle`" --title "Format disk" \
      --msgbox "No Sata or NVMe Disks found." 0 0
    return
  fi
  dialog --backtitle "`backtitle`" --title "Format disk" \
      --yesno "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return
  if [ `ls /dev/md* | wc -l` -gt 0 ]; then
    dialog --backtitle "`backtitle`" --title "Format disk" \
        --yesno "Warning:\nThe current hds is in raid, do you still want to format them?" 0 0
    [ $? -ne 0 ] && return
    for I in `ls /dev/md*`; do
      mdadm -S ${I}
    done
  fi
  (
    for I in ${RESP}; do
      mkfs.ext4 -F -O ^metadata_csum ${I}
    done
  ) | dialog --backtitle "`backtitle`" --title "Format disk" \
      --progressbox "Formatting ..." 20 70
  dialog --backtitle "`backtitle`" --colors --aspect 18 \
    --msgbox "Formatting is complete." 0 0
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  DIRECTBOOT="`readConfigKey "arc.directboot" "${USER_CONFIG_FILE}"`"
  GRUBCONF=`grub-editenv ${GRUB_PATH}/grubenv list | wc -l`
  if [ ${DIRECTBOOT} = "false" ] && [ ${GRUBCONF} -gt 0 ]; then
  grub-editenv ${GRUB_PATH}/grubenv create
  dialog --backtitle "`backtitle`" --title "Arc Directboot" \
    --msgbox "Disable Directboot!" 0 0
  fi
  [ ${DIRTY} -eq 1 ] && dialog --backtitle "`backtitle`" --title "Alert" \
    --yesno "Config changed, would you like to rebuild the loader?" 0 0
  if [ $? -eq 0 ]; then
    make || return
  fi
  dialog --backtitle "`backtitle`" --title "Arc Boot" \
    --infobox "Booting to DSM - Please stay patient!" 0 0
  sleep 3
  exec reboot
}

###############################################################################
###############################################################################

if [ "x$1" = "xb" -a -n "${MODEL}" -a -n "${BUILD}" -a loaderIsConfigured ]; then
  install-addons.sh
  make
  boot && exit 0 || sleep 3
fi
# Main loop
NEXT="1"
while true; do
  echo "= \"\Z4========== Main ==========\Zn \" "                                            > "${TMP_PATH}/menu"
  echo "1 \"Choose Model for Loader \" "                                                    >> "${TMP_PATH}/menu"
  if [ -n "${CONFDONE}" ]; then
    echo "4 \"Build Loader \" "                                                             >> "${TMP_PATH}/menu"
  fi
  if [ -n "${BUILDDONE}" ]; then
    echo "5 \"Boot Loader \" "                                                              >> "${TMP_PATH}/menu"
  fi
  echo "= \"\Z4========== Info ==========\Zn \" "                                           >> "${TMP_PATH}/menu"
  echo "a \"Sysinfo \" "                                                                    >> "${TMP_PATH}/menu"
  if [ -n "${CONFDONE}" ]; then
    echo "= \"\Z4========= System =========\Zn \" "                                         >> "${TMP_PATH}/menu"
    echo "2 \"Addons \" "                                                                   >> "${TMP_PATH}/menu"
    echo "3 \"Modules \" "                                                                  >> "${TMP_PATH}/menu"
    if [ -n "${ARCOPTS}" ]; then
      echo "v \"\Z1Hide Arc Options\Zn \" "                                                 >> "${TMP_PATH}/menu"
    else
      echo "v \"\Z1Show Arc Options\Zn \" "                                                 >> "${TMP_PATH}/menu"
    fi
    if [ -n "${ARCOPTS}" ]; then
      if [ "${DT}" != "true" ] && [ "${SATACONTROLLER}" -gt 0 ]; then
        echo "s \"Change Storage Map \" "                                                   >> "${TMP_PATH}/menu"
      fi
      echo "n \"Change Network Config \" "                                                  >> "${TMP_PATH}/menu"
      echo "u \"Change USB Port Config \" "                                                 >> "${TMP_PATH}/menu"
      if [ -f "${BACKUPDIR}/dsm-backup.tar" ]; then
        echo "r \"Boot from Backup: \Z4${BACKUPBOOT}\Zn \" "                                >> "${TMP_PATH}/menu"
      fi
      if [ -n "${BUILDDONE}" ]; then
        echo "p \"Show .pat download link \" "                                              >> "${TMP_PATH}/menu"
      fi
      echo "w \"Allow DSM downgrade \" "                                                    >> "${TMP_PATH}/menu"
      echo "o \"Save Modifications to Disk \" "                                             >> "${TMP_PATH}/menu"
      echo "z \"\Z1Format Disk(s)\Zn \" "                                                   >> "${TMP_PATH}/menu"
    fi
    if [ -n "${ADVOPTS}" ]; then
      echo "x \"\Z1Hide Advanced Options\Zn \" "                                            >> "${TMP_PATH}/menu"
    else
      echo "x \"\Z1Show Advanced Options\Zn \" "                                            >> "${TMP_PATH}/menu"
    fi
    if [ -n "${ADVOPTS}" ]; then
      echo "f \"Cmdline \" "                                                                >> "${TMP_PATH}/menu"
      echo "g \"Synoinfo \" "                                                               >> "${TMP_PATH}/menu"
      echo "h \"Edit User Config \" "                                                       >> "${TMP_PATH}/menu"
      echo "i \"DSM Recovery \" "                                                           >> "${TMP_PATH}/menu"
      echo "j \"Switch LKM version: \Z4${LKM}\Zn \" "                                       >> "${TMP_PATH}/menu"
      echo "k \"Direct boot: \Z4${DIRECTBOOT}\Zn \" "                                       >> "${TMP_PATH}/menu"
      if [ "${DIRECTBOOT}" = "true" ]; then
        echo "l \"Reset Direct DSM \" "                                                     >> "${TMP_PATH}/menu"
      fi
    fi
  fi
  echo "= \"\Z4===== Loader Settings ====\Zn \" "                                           >> "${TMP_PATH}/menu"
  echo "c \"Choose a keymap \" "                                                            >> "${TMP_PATH}/menu"
  if [ ${CLEARCACHE} -eq 1 -a -d "${CACHE_PATH}/dl" ]; then
    echo "d \"Clean disk cache \""                                                          >> "${TMP_PATH}/menu"
  fi
  echo "t \"Backup \" "                                                                     >> "${TMP_PATH}/menu"
  echo "e \"Update \" "                                                                     >> "${TMP_PATH}/menu"
  echo "0 \"\Z1Exit\Zn \" "                                                                 >> "${TMP_PATH}/menu"
  dialog --clear --default-item ${NEXT} --backtitle "`backtitle`" --colors \
    --menu "Choose an Option" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && break
  case `<"${TMP_PATH}/resp"` in
    # Main
    1) arcMenu; NEXT="4" ;;
    4) make; NEXT="5" ;;
    5) boot && exit 0 ;;
    # Info
    a) sysinfo; NEXT="a" ;;
    # System
    2) addonMenu; NEXT="2" ;;
    3) modulesMenu; NEXT="3" ;;
    # Arc Section
    v) [ "${ARCOPTS}" = "" ] && ARCOPTS='1' || ARCOPTS=''
       ARCOPTS="${ARCOPTS}"
       NEXT="v"
       ;;
    s) storageMenu; NEXT="s" ;;
    n) networkMenu; NEXT="n" ;;
    u) usbMenu; NEXT="u" ;;
    t) backupMenu; NEXT="t" ;;
    r) [ "${BACKUPBOOT}" = "false" ] && BACKUPBOOT='true' || BACKUPBOOT='false'
      writeConfigKey "backupboot" "${BACKUPBOOT}" "${USER_CONFIG_FILE}"
      NEXT="5"
      ;;
    p) paturl; NEXT="p" ;;
    w) downgradeMenu; NEXT="w" ;;
    o) saveMenu; NEXT="o" ;;
    z) formatdisks; NEXT="z" ;;
    # Advanced Section
    x) [ "${ADVOPTS}" = "" ] && ADVOPTS='1' || ADVOPTS=''
       ADVOPTS="${ADVOPTS}"
       NEXT="x"
       ;;
    f) cmdlineMenu; NEXT="f" ;;
    g) synoinfoMenu; NEXT="g" ;;
    h) editUserConfig; NEXT="h" ;;
    i) tryRecoveryDSM; NEXT="i" ;;
    j) [ "${LKM}" = "dev" ] && LKM='prod' || LKM='dev'
      writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
      DIRTY=1
      NEXT="4"
      ;;
    k) [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
      writeConfigKey "arc.directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
      NEXT="4"
      ;;
    l) writeConfigKey "arc.directdsm" "false" "${USER_CONFIG_FILE}"
      grub-editenv ${GRUB_PATH}/grubenv create
      NEXT="4"
      ;;
    # Loader Settings
    c) keymapMenu; NEXT="c" ;;
    d) dialog --backtitle "`backtitle`" --title "Cleaning" --aspect 18 \
      --prgbox "rm -rfv \"${CACHE_PATH}/dl\"" 0 0 ;;
    e) updateMenu; NEXT="e" ;;
    0) break ;;
  esac
done
clear
# Inform user
echo
echo -e "Call \033[1;32marc.sh\033[0m to configure loader"
echo
echo -e "\033[1;31mSSH Access:\033[0m"
echo -e "IP: \033[1;31m${IP}\033[0m"
echo -e "User: \033[1;31mroot\033[0m"
echo -e "Password: \033[1;31mRedp1lL-1s-4weSomE\033[0m"
echo
echo -e "\033[1;31mWeb Terminal Access:\033[0m"
echo -e "Address: \033[1;31mhttp://${IP}:7681\033[0m"