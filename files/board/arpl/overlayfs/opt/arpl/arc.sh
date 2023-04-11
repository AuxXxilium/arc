#!/usr/bin/env bash

. /opt/arpl/include/functions.sh
. /opt/arpl/include/addons.sh
. /opt/arpl/include/modules.sh
. /opt/arpl/include/storage.sh

# Check partition 3 space, if < 2GiB is necessary clean cache folder
CLEARCACHE=0
LOADER_DISK="`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`"
LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
if [ `cat /sys/block/${LOADER_DEVICE_NAME}/${LOADER_DEVICE_NAME}3/size` -lt 4194304 ]; then
  CLEARCACHE=1
fi

# Get Number of Ethernet Ports
NETNUM=$(lshw -class network -short | grep -ie "eth[0-9]" | wc -l)
writeConfigKey "cmdline.netif_num" "${NETNUM}" "${USER_CONFIG_FILE}"

# Get actual IP
IP=`ip route get 1.1.1.1 2>/dev/null | awk '{print$7}'`

# Check for Hypervisor
if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
  MACHINE="VIRTUAL"
  # Check for Hypervisor
  HYPERVISOR=$(lscpu | grep Hypervisor | awk '{print $3}')
else
  MACHINE="NATIVE"
fi

# Dirty flag
DIRTY=0

MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
LAYOUT="`readConfigKey "layout" "${USER_CONFIG_FILE}"`"
KEYMAP="`readConfigKey "keymap" "${USER_CONFIG_FILE}"`"
LKM="`readConfigKey "lkm" "${USER_CONFIG_FILE}"`"
DIRECTBOOT="`readConfigKey "directboot" "${USER_CONFIG_FILE}"`"
SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"
CONFDONE="`readConfigKey "confdone" "${USER_CONFIG_FILE}"`"
BUILDDONE="`readConfigKey "builddone" "${USER_CONFIG_FILE}"`"
DT="`readModelKey "${MODEL}" "dt"`"

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
    [ "${BUILD}" = "64216" ] && VER="7.2 Beta"
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
      PLATFORM=`readModelKey "${M}" "platform"`
      DT="`readModelKey "${M}" "dt"`"
      DISKS="`readModelKey "${M}" "disks"`"
      if [ "${PLATFORM}" = "r1000" ] || [ "${PLATFORM}" = "v1000" ]; then
        CPU="AMD"
      else
        CPU="Intel"
      fi
      # Check id model is compatible with CPU
      COMPATIBLE=1
      if [ ${RESTRICT} -eq 1 ]; then
        for F in `readModelArray "${M}" "flags"`; do
          if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
            COMPATIBLE=0
            FLGNEX=1
            break
          fi
        done
      fi
      [ "${DT}" = "true" ] && DT="-DT" || DT=""
      [ ${COMPATIBLE} -eq 1 ] && echo -e "${M} \"\Zb${DISKS}-Bay\Zn \t\Zb${CPU}\Zn \t\Zb${PLATFORM}${DT}\Zn\" " >> "${TMP_PATH}/menu"
    done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
    [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1Show incompatible Models \Zn\"" >> "${TMP_PATH}/menu"
    dialog --backtitle "`backtitle`" --colors --menu "Choose Model for Arc" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "f" ]; then
      RESTRICT=0
      continue
    fi
      break
    done
  else
    resp="${1}"
  fi
  if [ "${DT}" = "true" ] && [ "$SCSICONTROLLER" -gt "0" ]; then
  # There is no Raid/SCSI Support for DT Models
  WARNON=2
  fi
  if [ "${WARNON}" = "1" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Warning" \
      --infobox "WARN: Your Controller has more than 8 Disks connected. Max Disks per Controller: 8" 0 0
    sleep 5
  fi
  if [ "${WARNON}" = "2" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Warning" \
      --infobox "WARN: You have selected a DT Model. There is no support for Raid/SCSI Controller." 0 0
    sleep 5
    exit 1
  fi
  if [ "${WARNON}" = "3" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Warning" \
      --infobox "WARN: No Diskcontroller found." 0 0
    sleep 5
    exit 1
  fi
  MODEL=${resp}
  writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
  deleteConfigKey "confdone" "${USER_CONFIG_FILE}"
  deleteConfigKey "builddone" "${USER_CONFIG_FILE}"
  deleteConfigKey "remap" "${USER_CONFIG_FILE}"
  # Delete old files
  rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  DIRTY=1
  arcbuild
}

###############################################################################
# Shows menu to user type one or generate randomly
function arcbuild() {
  # Select Build for DSM
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a DSM Version" 0 0 0 \
      1 "DSM 7.1.1 (stable)" \
      2 "DSM 7.2 Beta (experimental)" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "1" ]; then
      BUILD="42962"
      writeConfigKey "build" "${BUILD}" "${USER_CONFIG_FILE}"
      break
    elif [ "${resp}" = "2" ]; then
      BUILD="64216"
      writeConfigKey "build" "${BUILD}" "${USER_CONFIG_FILE}"
      break
    fi
  done
  # Read model config for buildconfig
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  DT="`readModelKey "${MODEL}" "dt"`"
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
      ARCPATCH=1
      SN="`readModelKey "${MODEL}" "arcserial"`"
      writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
      writeConfigKey "arcpatch" "yes" "${USER_CONFIG_FILE}"
      dialog --backtitle "`backtitle`" --title "Arc Config" \
            --infobox "Installing with Arc Patch!" 0 0
      break
    elif [ "${resp}" = "2" ]; then
      ARCPATCH=0
      # Generate random serial
      SN="`generateSerial "${MODEL}"`"
      writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
      writeConfigKey "arcpatch" "no" "${USER_CONFIG_FILE}"
      dialog --backtitle "`backtitle`" --title "Arc Config" \
      --infobox "Installing without Arc Patch!" 0 0
      break
    fi
  done
  dialog --backtitle "`backtitle`" --title "Arc Config" \
    --infobox "Reconfiguring Synoinfo, Addons and Modules" 0 0
  # Delete synoinfo and reload synoinfo from model and build
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read KEY VALUE; do
    writeConfigKey "synoinfo.${KEY}" "${VALUE}" "${USER_CONFIG_FILE}"
  done < <(readModelMap "${MODEL}" "builds.${BUILD}.synoinfo")
  # Check addons
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      deleteConfigKey "addons.${ADDON}" "${USER_CONFIG_FILE}"
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Delete modules and reload all modules for platform
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read ID DESC; do
    writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
  done < <(getAllModules "${PLATFORM}" "${KVER}")
  # Remove old files
  rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  DIRTY=1
  dialog --backtitle "`backtitle`" --title "Arc Config" \
    --infobox "Model Configuration successfull!" 0 0
  sleep 2
  arcnetdisk
}


###############################################################################
# Make Network and Disk Config
function arcnetdisk() {
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  DT="`readModelKey "${MODEL}" "dt"`"
  # Delete old Mac Address from Userconfig
  #deleteConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.mac2" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.mac3" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.mac4" "${USER_CONFIG_FILE}"
  MAC1="`readModelKey "${MODEL}" "mac1"`"
  MAC2="`readModelKey "${MODEL}" "mac2"`"
  MAC3="`readModelKey "${MODEL}" "mac3"`"
  MAC4="`readModelKey "${MODEL}" "mac4"`"
  dialog --backtitle "`backtitle`" \
    --title "Arc Network" --infobox " ${NETNUM} Adapter dedected" 0 0
  if [ "${ARCPATCH}" = "1" ]; then 
    # Install with Arc Patch - Check for model config and set custom Mac Address
    while true; do
      dialog --clear --backtitle "`backtitle`" \
        --menu "Network: MAC for 1. NIC" 0 0 0 \
        1 "Set MAC for all NIC" \
        2 "Use MAC1: ${MAC1}" \
        3 "Use MAC2: ${MAC2}" \
        4 "Use MAC3: ${MAC3}" \
        5 "Use MAC4: ${MAC4}" \
      2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(<${TMP_PATH}/resp)
      [ -z "${resp}" ] && return
      if [ "${resp}" != "1" ]; then
        if [ "${resp}" = "2" ]; then
            writeConfigKey "cmdline.mac1"           "${MAC1}" "${USER_CONFIG_FILE}"
        elif [ "${resp}" = "3" ]; then
            writeConfigKey "cmdline.mac1"           "${MAC2}" "${USER_CONFIG_FILE}"
        elif [ "${resp}" = "4" ]; then
            writeConfigKey "cmdline.mac1"           "${MAC3}" "${USER_CONFIG_FILE}"
        elif [ "${resp}" = "5" ]; then
            writeConfigKey "cmdline.mac1"           "${MAC4}" "${USER_CONFIG_FILE}"
        fi
        if [ "${NETNUM}" -gt 1 ]; then
          MAC2=`ip link show eth1 | awk '/ether/{print$2}' | sed 's/://g'`
          writeConfigKey "cmdline.mac2"           "${MAC2}" "${USER_CONFIG_FILE}"
        fi
        if [ "${NETNUM}" -gt 2 ]; then
          MAC3=`ip link show eth2 | awk '/ether/{print$2}' | sed 's/://g'`
          writeConfigKey "cmdline.mac3"           "${MAC3}" "${USER_CONFIG_FILE}"
        fi
        if [ "${NETNUM}" -gt 3 ]; then
          MAC4=`ip link show eth3 | awk '/ether/{print$2}' | sed 's/://g'`
          writeConfigKey "cmdline.mac4"           "${MAC4}" "${USER_CONFIG_FILE}"
        fi
        break
      fi
      if [ "${resp}" = "1" ]; then
          writeConfigKey "cmdline.mac1"           "${MAC1}" "${USER_CONFIG_FILE}"
        if [ "${NETNUM}" -gt 1 ]; then
          writeConfigKey "cmdline.mac2"           "${MAC2}" "${USER_CONFIG_FILE}"
        fi
        if [ "${NETNUM}" -gt 2 ]; then
          writeConfigKey "cmdline.mac3"           "${MAC3}" "${USER_CONFIG_FILE}"
        fi
        if [ "${NETNUM}" -gt 3 ]; then
          writeConfigKey "cmdline.mac4"           "${MAC4}" "${USER_CONFIG_FILE}"
        fi
        break
      fi
    done
    dialog --backtitle "`backtitle`" \
      --title "Arc Network" --infobox "Set MAC for first NIC" 0 0
    sleep 2
  elif [ "${ARCPATCH}" = "0" ]; then
    # Install without Arc Patch - Set Hardware Mac Address
      MAC1="`readConfigKey "original-mac" "${USER_CONFIG_FILE}"`"
      #MACA1=`ip link show eth0 | awk '/ether/{print$2}'`
      #MAC1=`echo ${MACA1} | sed 's/://g'`
      writeConfigKey "cmdline.mac1"           "${MAC1}" "${USER_CONFIG_FILE}"
    if [ "${NETNUM}" -gt 1 ]; then
      MAC2=`ip link show eth1 | awk '/ether/{print$2}' | sed 's/://g'`
      writeConfigKey "cmdline.mac2"           "${MAC2}" "${USER_CONFIG_FILE}"
    fi
    if [ "${NETNUM}" -gt 2 ]; then
      MAC3=`ip link show eth2 | awk '/ether/{print$2}' | sed 's/://g'`
      writeConfigKey "cmdline.mac3"           "${MAC3}" "${USER_CONFIG_FILE}"
    fi
    if [ "${NETNUM}" -gt 3 ]; then
      MAC4=`ip link show eth3 | awk '/ether/{print$2}' | sed 's/://g'`
      writeConfigKey "cmdline.mac4"           "${MAC4}" "${USER_CONFIG_FILE}"
    fi
    dialog --backtitle "`backtitle`" \
      --title "Arc Network" --infobox "Set MAC for all NIC" 0 0
    sleep 2
  fi
  # Ask for IP rebind
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Restart DHCP?" 0 0 0 \
      1 "No - Get new IP on Boot" \
      2 "Yes - Get new IP now" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "1" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Network" \
        --infobox "IP/MAC will be changed on first boot!" 0 0
      sleep 2
      break
    elif [ "${resp}" = "2" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Network" \
        --infobox "IP/MAC will be changed now!" 0 0
        MAC1="`readConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"`"
        MACN1="${MAC1:0:2}:${MAC1:2:2}:${MAC1:4:2}:${MAC1:6:2}:${MAC1:8:2}:${MAC1:10:2}"
        ip link set dev eth0 address ${MACN1} 2>&1
        /etc/init.d/S41dhcpcd restart 2>&1 | dialog --backtitle "`backtitle`" \
        --title "Restart DHCP" --progressbox "Renewing IP" 20 70
      sleep 5
      IP=`ip route get 1.1.1.1 2>/dev/eth0 | awk '{print$7}'`
      sleep 2
      break
    fi
  done
  # Only load getmap when Sata Controller are dedected and no DT Model is selected
  if [ "${SATACONTROLLER}" -gt 0 ] && [ "${DT}" != "true" ]; then
  # Config for Sata Controller with PortMap to get all drives
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --infobox "SATA Controller found. We have to use SataPortMap for Controller!" 0 0
    writeConfigKey "remap" "0" "${USER_CONFIG_FILE}"
    sleep 3
  elif [ "${SATACONTROLLER}" -eq 0 ] && [ "${DT}" != "true" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --infobox "No SATA Controller found. We can use SasIdxMap for Controller!" 0 0
      writeConfigKey "remap" "0" "${USER_CONFIG_FILE}"
      sleep 3
  elif [ "${DT}" = "true" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --infobox "Device Tree Model selected." 0 0
      writeConfigKey "remap" "3" "${USER_CONFIG_FILE}"
      sleep 3
  fi
  # Get Diskmap for DSM
  REMAP="`readConfigKey "remap" "${USER_CONFIG_FILE}"`"
  if [ -n "${REMAP}" ]; then
    getmap
  fi
  # Show Map to User
  if [ "${REMAP}" == "0" ] && [ "${SATAPORTMAP}" -gt 10 ]; then
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "SataPortMap: ${SATAPORTMAP} DiskIdxMap: ${DISKIDXMAP}" 0 0
  elif [ "${REMAP}" == "0" ] && [ "$HYPERVISOR" = "VMware" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "SataPortMap: ${SATAPORTMAP} DiskIdxMap: ${DISKIDXMAP}" 0 0
  elif [ "${REMAP}" == "3" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "Device Tree Model selected - We don't need this." 0 0
  fi
  # Config is done
  writeConfigKey "confdone" "1" "${USER_CONFIG_FILE}"
  dialog --backtitle "`backtitle`" --title "Arc Config" \
    --infobox "Configuration successfull!" 0 0
  sleep 1
  DIRTY=1
  CONFDONE="`readConfigKey "confdone" "${USER_CONFIG_FILE}"`"
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
  # Read modelconfig for build
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"

  # Check if all addon exists
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
        --msgbox "Addon ${ADDON} not found!" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

  [ ! -f "${ORI_ZIMAGE_FILE}" -o ! -f "${ORI_RDGZ_FILE}" ] && extractDsmFiles

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
  dialog --backtitle "`backtitle`" --title "Arc Build" \
    --infobox "Build successfull! You can boot now." 0 0
  sleep 2
  DIRTY=0
  # Build is done
  writeConfigKey "builddone" "1" "${USER_CONFIG_FILE}"
  BUILDDONE="`readConfigKey "builddone" "${USER_CONFIG_FILE}"`"
  # Ask for Boot
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Boot now?" 0 0 0 \
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
    echo "Downloading ${PAT_FILE}"
    # Discover remote file size
    FILESIZE=`curl --insecure -sLI "${PAT_URL}" | grep -i Content-Length | awk '{print$2}'`
    if [ 0${FILESIZE} -ge ${SPACELEFT} ]; then
      # No disk space to download, change it to RAMDISK
      PAT_PATH="${TMP_PATH}/${PAT_FILE}"
    fi
    STATUS=`curl --insecure -w "%{http_code}" -L "${PAT_URL}" -o "${PAT_PATH}" --progress-bar`
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

  SPACELEFT=`df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print$4}'`  # Check disk space left

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
        if [ 0${FILESIZE} -ge ${SPACELEFT} ]; then
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
function selectModules() {
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
        ;;
      3)
        dialog --backtitle "`backtitle`" --title "Modules" \
           --infobox "Deselecting all modules" 0 0
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        unset USERMODULES
        declare -A USERMODULES
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
        CMDLINE["${NAME}"]="${VALUE}"
        writeConfigKey "cmdline.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
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
        ;;
      3)
        while true; do
          dialog --backtitle "`backtitle`" --title "User cmdline" \
            --inputbox "Type a custom MAC address" 0 0 "${CMDLINE['mac1']}"\
            2>${TMP_PATH}/resp
          [ $? -ne 0 ] && break
          MAC="`<"${TMP_PATH}/resp"`"
          [ -z "${MAC}" ] && MAC="`readConfigKey "original-mac" "${USER_CONFIG_FILE}"`"
          MAC1="`echo "${MAC}" | sed 's/://g'`"
          [ ${#MAC1} -eq 12 ] && break
          dialog --backtitle "`backtitle`" --title "User cmdline" --msgbox "Invalid MAC" 0 0
        done
        CMDLINE["mac1"]="${MAC1}"
        CMDLINE["netif_num"]=1
        writeConfigKey "cmdline.mac1"      "${MAC1}" "${USER_CONFIG_FILE}"
        MAC="${MAC1:0:2}:${MAC1:2:2}:${MAC1:4:2}:${MAC1:6:2}:${MAC1:8:2}:${MAC1:10:2}"
        ip link set dev eth0 address ${MAC} 2>&1 | dialog --backtitle "`backtitle`" \
          --title "User cmdline" --progressbox "Changing mac" 20 70
        /etc/init.d/S41dhcpcd restart 2>&1 | dialog --backtitle "`backtitle`" \
          --title "User cmdline" --progressbox "Renewing IP" 20 70
        IP=`ip route get 1.1.1.1 2>/dev/null | awk '{print$7}'`
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
# let user edit synoinfo
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
        SYNOINFO["${NAME}"]="${VALUE}"
        writeConfigKey "synoinfo.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
        DIRTY=1
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
# Shows backup menu to user
function backupMenu() {
  NEXT="1"
  BUILDDONE="`readConfigKey "confdone" "${USER_CONFIG_FILE}"`"
  if [ -n "${BUILDDONE}" ]; then
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Backup Config" \
        2 "Restore Config" \
        3 "Backup Loader" \
        4 "Restore Loader" \
        5 "Show Backup Path" \
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
          ;;
        3)
          dialog --backtitle "`backtitle`" --title "Backup Loader" --aspect 18 \
            --infobox "Backup Loader to ${BACKUPDIR}" 0 0
          if [ ! -d "${BACKUPDIR}" ]; then
            # Make backup dir
            mkdir ${BACKUPDIR}
          else
            # Clean old backup
            rm -f ${BACKUPDIR}/arc-backup.tar
          fi
          # Copy files to backup
          cp -f ${USER_CONFIG_FILE} ${BACKUPDIR}/user-config.yml
          cp -f ${MOUNTP3}/zImage-dsm ${BACKUPDIR}/zImage-dsm
          cp -f ${MOUNTP3}/initrd-dsm ${BACKUPDIR}/initrd-dsm
          # Compress backup
          tar -cvf ${BACKUPDIR}/arc-backup.tar ${BACKUPDIR}/
          # Clean temp files from backup dir
          rm -f ${BACKUPDIR}/user-config.yml
          rm -f ${BACKUPDIR}/zImage-dsm
          rm -f ${BACKUPDIR}/initrd-dsm
          if [ -f "${BACKUPDIR}/arc-backup.tar" ]; then
            dialog --backtitle "`backtitle`" --title "Backup Loader" --aspect 18 \
              --msgbox "Backup complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Backup Loader" --aspect 18 \
              --msgbox "Backup error" 0 0
          fi
          ;;
        4)
          dialog --backtitle "`backtitle`" --title "Restore Loader" --aspect 18 \
            --infobox "Restore Loader from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/arc-backup.tar" ]; then
            # Uncompress backup
            tar -xvf ${BACKUPDIR}/arc-backup.tar -C /
            # Copy files to locations
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            cp -f ${BACKUPDIR}/zImage-dsm ${MOUNTP3}/zImage-dsm
            cp -f ${BACKUPDIR}/initrd-dsm ${MOUNTP3}/initrd-dsm
            # Clean temp files from backup dir
            rm -f ${BACKUPDIR}/user-config.yml
            rm -f ${BACKUPDIR}/zImage-dsm
            rm -f ${BACKUPDIR}/initrd-dsm
            dialog --backtitle "`backtitle`" --title "Restore Loader" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore Loader" --aspect 18 \
              --msgbox "No Loader Backup found" 0 0
          fi
          ;;
        5)
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
        2 "Restore Loader" \
        3 "Show Backup Path" \
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
          ;;
        2)
          dialog --backtitle "`backtitle`" --title "Restore Loader" --aspect 18 \
            --infobox "Restore Loader from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/arc-backup.tar" ]; then
            # Uncompress backup
            tar -xvf ${BACKUPDIR}/arc-backup.tar -C /
            # Copy files to locations
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            cp -f ${BACKUPDIR}/zImage-dsm ${MOUNTP3}/zImage-dsm
            cp -f ${BACKUPDIR}/initrd-dsm ${MOUNTP3}/initrd-dsm
            # Clean temp files from backup dir
            rm -f ${BACKUPDIR}/user-config.yml
            rm -f ${BACKUPDIR}/zImage-dsm
            rm -f ${BACKUPDIR}/initrd-dsm
            sleep 3
            dialog --backtitle "`backtitle`" --title "Restore Loader" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore Loader" --aspect 18 \
              --msgbox "No Loader Backup found" 0 0
          fi
          ;;
        3)
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
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  while true; do
    dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
      1 "Update Arc Loader" \
      2 "Update Addons" \
      3 "Update LKMs" \
      4 "Update Modules" \
      0 "Exit" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      1)
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
            gzip -dc "/tmp/`basename "${KEY}"`.tgz" | tar xf - -C "${VALUE}"
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

      2)
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
        for PKG in `ls /tmp/addons/*.addon`; do
          ADDON=`basename ${PKG} | sed 's|.addon||'`
          rm -rf "${ADDONS_PATH}/${ADDON}"
          mkdir -p "${ADDONS_PATH}/${ADDON}"
          tar xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
        done
        DIRTY=1
        dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
          --msgbox "Addons updated with success! ${TAG}" 0 0
        ;;

      3)
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
      4)
        unset PLATFORMS
        declare -A PLATFORMS
        while read M; do
          M="`basename ${M}`"
          M="${M::-4}"
          P=`readModelKey "${M}" "platform"`
          ITEMS="`readConfigEntriesArray "builds" "${MODEL_CONFIG_PATH}/${M}.yml"`"
          for B in ${ITEMS}; do
            KVER=`readModelKey "${M}" "builds.${B}.kver"`
            PLATFORMS["${P}-${KVER}"]=""
          done
        done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
        dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
          --infobox "Checking latest version" 0 0
        TAG=`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
        if [ $? -ne 0 -o -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          continue
        fi
        for P in ${!PLATFORMS[@]}; do
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --infobox "Downloading ${P} modules: ${TAG}" 0 0
          STATUS=`curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/${P}.tgz" -o "/tmp/${P}.tgz"`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
              --msgbox "Error downloading ${P}.tgz" 0 0
            continue
          fi
          rm "${MODULES_PATH}/${P}.tgz"
          mv "/tmp/${P}.tgz" "${MODULES_PATH}/${P}.tgz"
        done
        # Rebuild modules if model/buildnumber is selected
        if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          while read ID DESC; do
            writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
          done < <(getAllModules "${PLATFORM}" "${KVER}")
        fi
        DIRTY=1
        dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
          --msgbox "Modules updated with success! ${TAG}" 0 0
        ;;
      0) return ;;
    esac
  done
}

###############################################################################
# Show Storagemenu to user
function storageMenu() {
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  DT="`readModelKey "${MODEL}" "dt"`"
  # Ask for Storage Map
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Storageconfig" 0 0 0 \
      1 "Use Portmap for Disks" \
      2 "Use Remap for Disks" \
      3 "Set own Map in Userconfig" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "1" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --infobox "Use Portmap for Sata Controller" 0 0
      writeConfigKey "remap" "0" "${USER_CONFIG_FILE}"
      sleep 2
      break
    elif [ "${resp}" = "2" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --infobox "Use Remap for Sata Controller" 0 0
      writeConfigKey "remap" "1" "${USER_CONFIG_FILE}"
      sleep 2
      break
    elif [ "${resp}" = "4" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --infobox "Set own Map for Controller" 0 0
      writeConfigKey "remap" "3" "${USER_CONFIG_FILE}"
      sleep 2
      break
    fi
  done
  # Get Diskmap for DSM
  REMAP="`readConfigKey "remap" "${USER_CONFIG_FILE}"`"
  if [ -n "${REMAP}" ]; then
  getmap
  fi
  # Show Map to User
  if [ "${REMAP}" == "0" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "SataPortMap: ${SATAPORTMAP} DiskIdxMap: ${DISKIDXMAP}" 0 0
  elif [ "${REMAP}" == "1" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "Sata_Remap: ${SATAREMAP}" 0 0
  elif [ "${REMAP}" == "2" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "SasIdxMap: ${SASIDXMAP}" 0 0
  elif [ "${REMAP}" == "3" ]; then
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "Set your own Map in Userconfig" 0 0
  fi
  writeConfigKey "builddone" "0" "${USER_CONFIG_FILE}"
  BUILDDONE="`readConfigKey "builddone" "${USER_CONFIG_FILE}"`"
}

###############################################################################
# Shows Systeminfo to user
function sysinfo() {
  # Delete old Sysinfo
  rm -f ${SYSINFO_PATH}
  # Checks for Systeminfo Menu
  CPUINFO=$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')
  MEMINFO=$(free -g | awk 'NR==2' | awk '{print $2}')
  VENDOR=$(dmidecode -s system-product-name)
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  NETNUM=$(lshw -class network -short | grep -ie "eth" | wc -l)
  REMAP="`readConfigKey "remap" "${USER_CONFIG_FILE}"`"
  if [ "${REMAP}" == "0" ]; then
  PORTMAP="`readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"`"
  elif [ "${REMAP}" == "1" ]; then
  PORTMAP="`readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"`"
  fi
  CONFDONE="`readConfigKey "confdone" "${USER_CONFIG_FILE}"`"
  BUILDDONE="`readConfigKey "builddone" "${USER_CONFIG_FILE}"`"
  ARCPATCH="`readConfigKey "arcpatch" "${USER_CONFIG_FILE}"`"
  LKM="`readConfigKey "lkm" "${USER_CONFIG_FILE}"`"
  ADDONSINFO="`readConfigEntriesArray "addons" "${USER_CONFIG_FILE}"`"
  MODULESINFO=$(kmod list | awk '{print$1}' | awk 'NR>1')
  TEXT=""
  # Print System Informations
  TEXT+="\n\Z4System:\Zn"
  TEXT+="\nTyp: \Zb"${MACHINE}"\Zn"
  if [ "$MACHINE" = "VIRTUAL" ]; then
  TEXT+="\nHypervisor: \Zb"${HYPERVISOR}"\Zn"
  fi
  TEXT+="\nVendor: \Zb"${VENDOR}"\Zn"
  TEXT+="\nCPU: \Zb"${CPUINFO}"\Zn"
  TEXT+="\nRAM: \Zb"${MEMINFO}"GB\Zn\n"
  # Print Config Informations
  TEXT+="\n\Z4Config:\Zn"
  TEXT+="\nArc: \Zb"${ARPL_VERSION}"\Zn"
  TEXT+="\nModel: \Zb"${MODEL}"\Zn"
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
  if [ -f "${BACKUPDIR}/arc-backup.tar" ]; then
    TEXT+="\nBackup: \ZbComplete\Zn"
  elif [ -f "${BACKUPDIR}/user-config.yml" ]; then
    TEXT+="\nBackup: \ZbOnly Config\Zn"
  else
    TEXT+="\nBackup: \ZbNo Backup found\Zn"
  fi
  TEXT+="\nArcpatch: \Zb"${ARCPATCH}"\Zn"
  TEXT+="\nLKM: \Zb"${LKM}"\Zn"
  TEXT+="\nNetwork: \Zb"${NETNUM}" Adapter\Zn"
  TEXT+="\nIP: \Zb"${IP}"\Zn"
  if [ "${REMAP}" == "0" ]; then
    TEXT+="\nSataPortMap: \Zb"${PORTMAP}"\Zn"
  elif [ "${REMAP}" == "1" ]; then
    TEXT+="\nSataRemap: \Zb"${PORTMAP}"\Zn"
  elif [ "${REMAP}" == "2" ]; then
    TEXT+="\nPortMap: \Zb"Set by User"\Zn"
  fi
  TEXT+="\nAddons loaded: \Zb"${ADDONSINFO}"\Zn"
  TEXT+="\nModules loaded: \Zb"${MODULESINFO}"\Zn\n"
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS
  TEXT+="\n\Z4Storage:\Zn"
  # Get Information for Sata Controller
  if [ "$SATACONTROLLER" -gt "0" ]; then
  for PCI in `lspci -nnk | grep -ie "\[0106\]" | awk '{print$1}'`; do
    # Get Name of Controller
    NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
    # Get Amount of Drives connected
    SATADRIVES=$(ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l)
    TEXT+="\n\Z1SATA Controller\Zn detected:\n\Zb"${NAME}"\Zn\n"
    TEXT+="\Z1Drives\Zn detected:\n\Zb"${SATADRIVES}"\Zn\n"
  done
  fi
  # Get Information for SCSI Controller
  if [ "$SCSICONTROLLER" -gt "0" ]; then
  for PCI in `lspci -nnk | grep -ie "\[0104\]" | awk '{print$1}'`; do
    # Get Name of Controller
    NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
    # Get Amount of Drives connected
    SCSIDRIVES=$(ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l)
    TEXT+="\n\Z1SCSI/RAID Controller\Zn detected:\n\Zb"${NAME}"\Zn\n"
    TEXT+="\Z1Drives\Zn detected:\n\Zb"${SCSIDRIVES}"\Zn\n"
  done
  fi
  # Get Information for SAS Controller
  if [ "$SASCONTROLLER" -gt "0" ]; then
  for PCI in `lspci -nnk | grep -ie "\[0107\]" | awk '{print$1}'`; do
    # Get Name of Controller
    NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
    # Get Amount of Drives connected
    SASDRIVES=$(ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l)
    TEXT+="\n\Z1SAS Controller\Zn detected:\n\Zb"${NAME}"\Zn\n"
    TEXT+="\Z1Drives\Zn detected:\n\Zb"${SASDRIVES}"\Zn\n"
  done
  fi
  if [ "$SATACONTROLLER" -gt "0" ]; then
    TEXT+="\n\Z4Controller Ports:\Zn\n"
    NUMPORTS=0
    for PCI in `lspci -d ::106 | awk '{print$1}'`; do
      NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
      TEXT+="\Zb${NAME}\Zn\nPorts: "
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
        TEXT+="${PORT}\Zn "
        NUMPORTS=$((${NUMPORTS}+1))
      done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
      TEXT+="\n"
    done
    TEXT+="\nTotal of ports: ${NUMPORTS}\n"
    TEXT+="\nPorts with color \Z1red\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected.\n"
  fi
  echo -e ${TEXT} > "${SYSINFO_PATH}"
  TEXT+="\nSysinfo File: \Zb"\\\\${IP}\\arpl\\p1\\sysinfo.yml"\Zn"
  dialog --backtitle "`backtitle`" --title "Arc Sysinfo" --aspect 18 --colors --msgbox "${TEXT}" 0 0
}

###############################################################################
# let user reset config
function reset() {
  # Reset full userconfig
  writeConfigKey "lkm" "dev" "${USER_CONFIG_FILE}"
  writeConfigKey "directboot" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "model" "" "${USER_CONFIG_FILE}"
  writeConfigKey "build" "" "${USER_CONFIG_FILE}"
  writeConfigKey "sn" "" "${USER_CONFIG_FILE}"
  #writeConfigKey "maxdisks" "" "${USER_CONFIG_FILE}"
  writeConfigKey "layout" "qwertz" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "de" "${USER_CONFIG_FILE}"
  writeConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
  writeConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
  writeConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.misc" "" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.powersched" "" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.SasIdxMap" "${USER_CONFIG_FILE}"
  writeConfigKey "cmdline.netif_num" "1" "${USER_CONFIG_FILE}"
  writeConfigKey "cmdline.mac1" "${MACF}" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.mac2" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.mac3" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.mac4" "${USER_CONFIG_FILE}"
  deleteConfigKey "confdone" "${USER_CONFIG_FILE}"
  deleteConfigKey "builddone" "${USER_CONFIG_FILE}"
  CONFDONE="`readConfigKey "confdone" "${USER_CONFIG_FILE}"`"
  BUILDDONE="`readConfigKey "builddone" "${USER_CONFIG_FILE}"`"
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
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
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
  boot && exit 0
fi
# Main loop
NEXT="1"
while true; do
  echo "= \"\Z4========== Main ========== \Zn\" "                                            > "${TMP_PATH}/menu"
  echo "1 \"Choose Model for Arc Loader \" "                                                >> "${TMP_PATH}/menu"
  if [ -n "${CONFDONE}" ]; then
    echo "4 \"Build Arc Loader \" "                                                         >> "${TMP_PATH}/menu"
  fi
  if [ -n "${BUILDDONE}" ]; then
    echo "5 \"Boot Arc Loader \" "                                                          >> "${TMP_PATH}/menu"
  fi
  echo "= \"\Z4========== Info ========== \Zn\" "                                           >> "${TMP_PATH}/menu"
  echo "a \"Sysinfo \" "                                                                    >> "${TMP_PATH}/menu"
  if [ -n "${CONFDONE}" ]; then
    echo "= \"\Z4========= System ========= \Zn\" "                                         >> "${TMP_PATH}/menu"
    echo "2 \"Addons \" "                                                                   >> "${TMP_PATH}/menu"
    echo "3 \"Modules \" "                                                                  >> "${TMP_PATH}/menu"
    if [ "${DT}" != "true" ]; then
      echo "s \"Change Storage Map \" "                                                     >> "${TMP_PATH}/menu"
    fi
    if [ -n "${ADV}" ]; then
      echo "x \"\Z1Hide Advanced Options \Zn\" "                                            >> "${TMP_PATH}/menu"
    else
      echo "x \"\Z1Show Advanced Options \Zn\" "                                            >> "${TMP_PATH}/menu"
    fi
    if [ -n "${ADV}" ]; then
      echo "f \"Cmdline \" "                                                                >> "${TMP_PATH}/menu"
      echo "g \"Synoinfo \" "                                                               >> "${TMP_PATH}/menu"
      echo "h \"Edit User Config \" "                                                       >> "${TMP_PATH}/menu"
      echo "r \"Reset User Config \" "                                                      >> "${TMP_PATH}/menu"
      echo "i \"DSM Recovery \" "                                                           >> "${TMP_PATH}/menu"
      echo "j \"Switch LKM version: \Z4${LKM}\Zn\" "                                        >> "${TMP_PATH}/menu"
      echo "k \"Switch direct boot: \Z4${DIRECTBOOT}\Zn \" "                                >> "${TMP_PATH}/menu"
    fi
  fi
  echo "= \"\Z4===== Loader Settings ==== \Zn\" "                                           >> "${TMP_PATH}/menu"
  echo "c \"Choose a keymap \" "                                                            >> "${TMP_PATH}/menu"
  if [ ${CLEARCACHE} -eq 1 -a -d "${CACHE_PATH}/dl" ]; then
    echo "d \"Clean disk cache \""                                                          >> "${TMP_PATH}/menu"
  fi
  echo "t \"Backup Menu \" "                                                                >> "${TMP_PATH}/menu"
  echo "e \"Update Menu \" "                                                                >> "${TMP_PATH}/menu"
  echo "0 \"\Z1Exit\Zn\" "                                                                  >> "${TMP_PATH}/menu"
  dialog --clear --default-item ${NEXT} --backtitle "`backtitle`" --colors \
    --menu "Choose an Option" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && break
  case `<"${TMP_PATH}/resp"` in
    1) arcMenu; NEXT="4" ;;
    4) make; NEXT="5" ;;
    5) boot && exit 0 ;;
    a) sysinfo; NEXT="a" ;;
    2) addonMenu; NEXT="2" ;;
    3) selectModules; NEXT="3" ;;
    s) storageMenu; NEXT="s" ;;
    n) reset; NEXT="1" ;;
    x) [ "${ADV}" = "" ] && ADV='1' || ADV=''
       ARV="${ADV}"
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
    writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
    NEXT="4"
    ;;
    c) keymapMenu; NEXT="c" ;;
    d) dialog --backtitle "`backtitle`" --title "Cleaning" --aspect 18 \
      --prgbox "rm -rfv \"${CACHE_PATH}/dl\"" 0 0 ;;
    t) backupMenu; NEXT="t" ;;
    e) updateMenu; NEXT="e" ;;
    0) break ;;
  esac
done
clear
# Inform user
echo
echo -e "Call \033[1;32marc.sh\033[0m to configure loader"
echo
echo -e "User config is on \033[1;32m${USER_CONFIG_FILE}\033[0m"
echo -e "Default SSH Root password is \033[1;31mRedp1lL-1s-4weSomE\033[0m"
echo
echo -e "IP: \033[1;31m${IP}\033[0m"