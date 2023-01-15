#!/usr/bin/env bash

. /opt/arpl/include/functions.sh
. /opt/arpl/include/addons.sh
. /opt/arpl/include/modules.sh

# Check partition 3 space, if < 2GiB is necessary clean cache folder
CLEARCACHE=0
LOADER_DISK="`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`"
LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
if [ `cat /sys/block/${LOADER_DEVICE_NAME}/${LOADER_DEVICE_NAME}3/size` -lt 4194304 ]; then
  CLEARCACHE=1
fi

# Get actual IP
IP=`ip route get 1.1.1.1 2>/dev/null | awk '{print$7}'`

# Check for Hypervisor
if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
    MACHINE="VIRTUAL"
else
    MACHINE="NATIVE"
fi

# Check for RAID/SCSI
if [ $(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | wc -l) -gt 0 ]; then
    ADRAID="1"
else
    ADRAID="0"
fi

# Check for SATA
if [ $(lspci -nnk | grep -ie "\[0106\]" | wc -l) -gt 0 ]; then
    ADSATA="1"
else
    ADSATA="0"
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
    BACKTITLE+=" ${BUILD}"
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
      [ ${COMPATIBLE} -eq 1 ] && echo "${M} \"\Zb${PLATFORM}${DT}\Zn\" " >> "${TMP_PATH}/menu"
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
    MODEL=${resp}
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    # Delete old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
    DIRTY=1
  buildMenu
}

###############################################################################
# Shows available buildnumbers from a model to user choose one
function buildMenu() {
  ITEMS="`readConfigEntriesArray "builds" "${MODEL_CONFIG_PATH}/${MODEL}.yml" | sort -r`"
  if [ -z "${1}" ]; then
    dialog --clear --no-items --backtitle "`backtitle`" \
      --menu "Choose a build number" 0 0 0 ${ITEMS} 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
  else
    if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
    resp="${1}"
  fi
  if [ "${BUILD}" != "${resp}" ]; then
    dialog --backtitle "`backtitle`" --title "Arc DSM Build Number" \
      --infobox "Reconfiguring Synoinfo, Addons and Modules" 0 0
    BUILD=${resp}
    writeConfigKey "build" "${BUILD}" "${USER_CONFIG_FILE}"
  fi
  writeConfigKey "confdone" "0" "${USER_CONFIG_FILE}"
  arcpatch
}

###############################################################################
# Shows menu to user type one or generate randomly
function arcpatch() {
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
    if [ "${resp}" = "2" ]; then
	  ARCPATCH="0"
	  # Generate random serial
	  SN=`generateSerial "${MODEL}"`
  	writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
	  dialog --backtitle "`backtitle`" --title "Arc Config" \
	  --infobox "Installing without Arc Patch!" 0 0
      	break
    elif [ "${resp}" = "1" ]; then
	  ARCPATCH="1"
  	SN="`readModelKey "${MODEL}" "arcserial"`"
  	writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
	  dialog --backtitle "`backtitle`" --title "Arc Config" \
      	  --infobox "Installing with Arc Patch!" 0 0
      	break
    fi
  done
  writeConfigKey "confdone" "0" "${USER_CONFIG_FILE}"
  arcbuild
}

###############################################################################
# Adding Synoinfo and Addons
function arcbuild() {
  # Delete synoinfo and reload model/build synoinfo  
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS="=" read KEY VALUE; do
    writeConfigKey "synoinfo.${KEY}" "${VALUE}" "${USER_CONFIG_FILE}"
  done < <(readModelMap "${MODEL}" "builds.${BUILD}.synoinfo")
  # Check addons
  while IFS="=" read ADDON PARAM; do
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
  DIRTY=1
  dialog --backtitle "`backtitle`" --title "Arc Model Config" \
    --infobox "Model Configuration successfull!" 0 0
  sleep 3
  writeConfigKey "confdone" "0" "${USER_CONFIG_FILE}"
  arcdisk
}

###############################################################################
# Make Disk Config
function arcdisk() {
  # Check for diskconfig
  if [ "$DT" = "true" ] && [ "$ADRAID" -gt 0 ]; then
    # There is no Raid/SCSI Support for DT Models
    dialog --backtitle "`backtitle`" --title "Arc Disk Config" \
      --infobox "Device Tree Model selected - Raid/SCSI Controller not supported!" 0 0
    sleep 5
    return 1
  else
    dialog --backtitle "`backtitle`" --title "Arc Disk Config" \
      --infobox "Arc Disk configuration started!" 0 0
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    sleep 3
    # Get Number of Sata Drives
    if [ "$ADSATA" -gt 0 ]; then
      pcis=$(lspci -nnk | grep -ie "\[0106\]" | awk '{print $1}')
      [ ! -z "$pcis" ]
      # loop through non-SATA controllers
      for pci in $pcis; do
      # get attached block devices (exclude CD-ROMs)
      SATADRIVES=$(ls -la /sys/block | fgrep "$pci" | grep -v "sr.$" | wc -l)
      done
    fi
    # Get Number of Raid/SCSI Drives
    if [ "$ADRAID" -gt 0 ]; then
      pcis=$(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print $1}')
      [ ! -z "$pcis" ]
      # loop through non-SATA controllers
      for pci in $pcis; do
      # get attached block devices (exclude CD-ROMs)
      RAIDDRIVES=$(ls -la /sys/block | fgrep "$pci" | grep -v "sr.$" | wc -l)
      done
    fi
    # Maximum Number of Drives per Controller is 8 > So we have to limit it to 8
    if [ "$SATADRIVES" -gt 8 ]; then
    SATADRIVES=8
    fi
    if [ "$RAIDDRIVES" -gt 8 ]; then
    RAIDDRIVES=8
    fi
    # Set SataPortMap for Native and VMWare ESXi
    if [ "$ADSATA" -eq 1 ]; then
    writeConfigKey "cmdline.SataPortMap" "$SATADRIVES" "${USER_CONFIG_FILE}"
    fi
    if [ "$ADSATA" -eq 2 ]; then
    writeConfigKey "cmdline.SataPortMap" "$SATADRIVES$SATADRIVES" "${USER_CONFIG_FILE}"
    fi
    if [ "$ADSATA" -eq 1 ] && [ "$ADRAID" -eq 1 ]; then
    writeConfigKey "cmdline.SataPortMap" "$SATADRIVES$RAIDDRIVES" "${USER_CONFIG_FILE}"
    fi
    # Set SataPortMap for Proxmox/Unraid (only 1 Drive per Sata Controller)
    if [ "${MACHINE}" -eq "VIRTUAL" ]; then
      if [ "$ADSATA" -eq 3 ]; then
      writeConfigKey "cmdline.SataPortMap" "111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 4 ]; then
      writeConfigKey "cmdline.SataPortMap" "1111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 5 ]; then
      writeConfigKey "cmdline.SataPortMap" "11111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 6 ]; then
      writeConfigKey "cmdline.SataPortMap" "111111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 7 ]; then
      writeConfigKey "cmdline.SataPortMap" "1111111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 8 ]; then
      writeConfigKey "cmdline.SataPortMap" "11111111" "${USER_CONFIG_FILE}"
      fi
    fi
  dialog --backtitle "`backtitle`" --title "Arc Disk Config" \
    --infobox "Disk configuration successfull!\n\nSata: $SATADRIVES Drives\nRaid/SCSI: $RAIDDRIVES Drives\n" 0 0
  sleep 3
  writeConfigKey "confdone" "0" "${USER_CONFIG_FILE}"
  arcnet
  fi
}

###############################################################################
# Make Disk Config
function newarcdisk() {
  # Check for diskconfig
  if [ "$DT" = "true" ] && [ "$ADRAID" -gt 0 ]; then
    # There is no Raid/SCSI Support for DT Models
    dialog --backtitle "`backtitle`" --title "Arc Disk Config" \
      --infobox "Device Tree Model selected - Raid/SCSI Controller not supported!" 0 0
    sleep 5
    return 1
  else
    dialog --backtitle "`backtitle`" --title "Arc Disk Config" \
      --infobox "Arc Disk configuration started!" 0 0
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    sleep 3
    # Get Number of Sata Drives
    if [ "$ADSATA" -gt 0 ]; then
      pcis=$(lspci -nnk | grep -ie "\[0106\]" | awk '{print $1}')
      [ ! -z "$pcis" ]
      # loop through non-SATA controllers
      for pci in $pcis; do
      # get attached block devices (exclude CD-ROMs)
      SATADRIVES=$(ls -la /sys/block | fgrep "$pci" | grep -v "sr.$" | wc -l)
      done
    fi
    # Get Number of Raid/SCSI Drives
    if [ "$ADRAID" -gt 0 ]; then
      pcis=$(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print $1}')
      [ ! -z "$pcis" ]
      # loop through non-SATA controllers
      for pci in $pcis; do
      # get attached block devices (exclude CD-ROMs)
      RAIDDRIVES=$(ls -la /sys/block | fgrep "$pci" | grep -v "sr.$" | wc -l)
      done
    fi
    # Maximum Number of Drives per Controller is 8 > So we have to limit it to 8
    if [ "$SATADRIVES" -gt 8 ]; then
    SATADRIVES=8
    fi
    if [ "$RAIDDRIVES" -gt 8 ]; then
    RAIDDRIVES=8
    fi
    # Set SataPortMap for Native and VMWare ESXi
    if [ "$ADSATA" -eq 1 ]; then
    writeConfigKey "cmdline.SataPortMap" "$SATADRIVES" "${USER_CONFIG_FILE}"
    fi
    if [ "$ADSATA" -eq 2 ]; then
    writeConfigKey "cmdline.SataPortMap" "$SATADRIVES$SATADRIVES" "${USER_CONFIG_FILE}"
    fi
    if [ "$ADSATA" -eq 1 ] && [ "$ADRAID" -eq 1 ]; then
    writeConfigKey "cmdline.SataPortMap" "$SATADRIVES$RAIDDRIVES" "${USER_CONFIG_FILE}"
    fi
    # Set SataPortMap for Proxmox (only 1 Drive per Sata Controller)
    if [ "${MACHINE}" -eq "VIRTUAL" ]; then
      if [ "$ADSATA" -eq 3 ]; then
      writeConfigKey "cmdline.SataPortMap" "111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 4 ]; then
      writeConfigKey "cmdline.SataPortMap" "1111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 5 ]; then
      writeConfigKey "cmdline.SataPortMap" "11111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 6 ]; then
      writeConfigKey "cmdline.SataPortMap" "111111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 7 ]; then
      writeConfigKey "cmdline.SataPortMap" "1111111" "${USER_CONFIG_FILE}"
      fi
      if [ "$ADSATA" -eq 8 ]; then
      writeConfigKey "cmdline.SataPortMap" "11111111" "${USER_CONFIG_FILE}"
      fi
    fi
  dialog --backtitle "`backtitle`" --title "Arc Disk Config" \
    --infobox "Disk configuration successfull!\n\nSata: $SATADRIVES Drives\nRaid/SCSI: $RAIDDRIVES Drives\n" 0 0
  sleep 3
  fi
}

###############################################################################
# Make Network Config
function arcnet() {
  # Export Network Adapter Amount - DSM 
  NETNUM=$(lshw -class network -short | grep -ie "eth" | wc -l)
  # Hardlimit to 4 Mac because of Redpill doesn't more at this time
  if [ "$NETNUM" -gt 4 ]; then
  NETNUM="4"
  fi
  writeConfigKey "cmdline.netif_num" "${NETNUM}"            "${USER_CONFIG_FILE}"
  # Delete old Mac Address from Userconfig
  #deleteConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.mac2" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.mac3" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.mac4" "${USER_CONFIG_FILE}"
  if [ "$ARCPATCH" -eq 1 ]; then 
    # Install with Arc Patch - Check for model config and set custom Mac Address
    MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
    if [ "$NETNUM" -gt 0 ]; then
      MAC1="`readModelKey "${MODEL}" "mac1"`"
      writeConfigKey "cmdline.mac1"           "$MAC1" "${USER_CONFIG_FILE}"
      MACN1="${MAC1:0:2}:${MAC1:2:2}:${MAC1:4:2}:${MAC1:6:2}:${MAC1:8:2}:${MAC1:10:2}"
      ip link set dev eth0 address ${MACN1} 2>&1
    fi
    if [ "$NETNUM" -gt 1 ]; then
      MAC2="`readModelKey "${MODEL}" "mac2"`"
      writeConfigKey "cmdline.mac2"           "$MAC2" "${USER_CONFIG_FILE}"
      MACN2="${MAC2:0:2}:${MAC2:2:2}:${MAC2:4:2}:${MAC2:6:2}:${MAC2:8:2}:${MAC2:10:2}"
      ip link set dev eth1 address ${MACN2} 2>&1
    fi
    if [ "$NETNUM" -gt 2 ]; then
      MAC3="`readModelKey "${MODEL}" "mac3"`"
      writeConfigKey "cmdline.mac3"           "$MAC3" "${USER_CONFIG_FILE}"
      MACN3="${MAC3:0:2}:${MAC3:2:2}:${MAC3:4:2}:${MAC3:6:2}:${MAC3:8:2}:${MAC3:10:2}"
      ip link set dev eth2 address ${MACN3} 2>&1
    fi
    if [ "$NETNUM" -gt 3 ]; then
      MAC4="`readModelKey "${MODEL}" "mac4"`"
      writeConfigKey "cmdline.mac4"           "$MAC4" "${USER_CONFIG_FILE}"
      MACN4="${MAC4:0:2}:${MAC4:2:2}:${MAC4:4:2}:${MAC4:6:2}:${MAC4:8:2}:${MAC4:10:2}"
      ip link set dev eth3 address ${MACN4} 2>&1
    fi
    dialog --backtitle "`backtitle`" \
            --title "Loading Arc MAC Table" --infobox "Set new MAC for ${NETNUM} Adapter" 0 0
    sleep 3
  else
      # Install without Arc Patch - Set Hardware Mac Address
      if [ "$NETNUM" -gt 0 ]; then
      MACA1=`ip link show eth0 | awk '/ether/{print$2}'`
      MAC1=`echo ${MACA1} | sed 's/://g'`
      writeConfigKey "cmdline.mac1"           "$MAC1" "${USER_CONFIG_FILE}"
      MACN1="${MAC1:0:2}:${MAC1:2:2}:${MAC1:4:2}:${MAC1:6:2}:${MAC1:8:2}:${MAC1:10:2}"
      ip link set dev eth0 address ${MACN1} 2>&1
    fi
    if [ "$NETNUM" -gt 1 ]; then
      MACA2=`ip link show eth0 | awk '/ether/{print$2}'`
      MAC2=`echo ${MACA2} | sed 's/://g'`
      writeConfigKey "cmdline.mac2"           "$MAC2" "${USER_CONFIG_FILE}"
      MACN2="${MAC2:0:2}:${MAC2:2:2}:${MAC2:4:2}:${MAC2:6:2}:${MAC2:8:2}:${MAC2:10:2}"
      ip link set dev eth1 address ${MACN2} 2>&1
    fi
    if [ "$NETNUM" -gt 2 ]; then
      MACA3=`ip link show eth0 | awk '/ether/{print$2}'`
      MAC3=`echo ${MACA3} | sed 's/://g'`
      writeConfigKey "cmdline.mac3"           "$MAC3" "${USER_CONFIG_FILE}"
      MACN3="${MAC3:0:2}:${MAC3:2:2}:${MAC3:4:2}:${MAC3:6:2}:${MAC3:8:2}:${MAC3:10:2}"
      ip link set dev eth2 address ${MACN3} 2>&1
    fi
    if [ "$NETNUM" -gt 3 ]; then
      MACA4=`ip link show eth0 | awk '/ether/{print$2}'`
      MAC4=`echo ${MACA4} | sed 's/://g'`
      writeConfigKey "cmdline.mac4"           "$MAC4" "${USER_CONFIG_FILE}"
      MACN4="${MAC4:0:2}:${MAC4:2:2}:${MAC4:4:2}:${MAC4:6:2}:${MAC4:8:2}:${MAC4:10:2}"
      ip link set dev eth3 address ${MACN4} 2>&1
    fi
    dialog --backtitle "`backtitle`" \
            --title "Loading Hardware MAC Table" --infobox "Set MAC for ${NETNUM} Adapter" 0 0
    sleep 3
  fi
  /etc/init.d/S41dhcpcd restart 2>&1 | dialog --backtitle "`backtitle`" \
    --title "Restart DHCP" --progressbox "Renewing IP" 20 70
  sleep 5
  IP=`ip route get 1.1.1.1 2>/dev/null | awk '{print$7}'`
  dialog --backtitle "`backtitle`" --title "Arc Config" \
      --infobox "Network configuration successfull!" 0 0
  sleep 3
  writeConfigKey "confdone" "1" "${USER_CONFIG_FILE}"
  dialog --backtitle "`backtitle`" --title "Arc Config" \
      --infobox "Arc configuration successfull!" 0 0
  sleep 3
  CONFDONE="`readConfigKey "confdone" "${USER_CONFIG_FILE}"`"
  dialog --clear --no-items --backtitle "`backtitle`"
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
  deleteConfigKey "confdone" "${USER_CONFIG_FILE}"

  # Check if all addon exists
  while IFS="=" read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
        --msgbox "Addon ${ADDON} not found!" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

  [ ! -f "${ORI_ZIMAGE_FILE}" -o ! -f "${ORI_RDGZ_FILE}" ] && extractDsmFiles

  /opt/arc/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "zImage not patched:\n`<"${LOG_FILE}"`" 0 0
    return 1
  fi

  /opt/arc/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "Ramdisk not patched:\n`<"${LOG_FILE}"`" 0 0
    return 1
  fi

  echo "Cleaning"
  rm -rf "${UNTAR_PAT_PATH}"

  echo "Ready!"
  dialog --backtitle "`backtitle`" --title "Arc Build" \
    --infobox "Arc Build successfull! You can boot now." 0 0
  sleep 3
  DIRTY=0
  writeConfigKey "confdone" "1" "${USER_CONFIG_FILE}"
  return 0
}

###############################################################################
# Extracting DSM for building Loader
function extractDsmFiles() {
  PAT_URL="`readModelKey "${MODEL}" "builds.${BUILD}.pat.url"`"
  PAT_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.hash"`"
  RAMDISK_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.ramdisk-hash"`"
  ZIMAGE_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.zimage-hash"`"

  # If we have little disk space, clean cache folder
  if [ ${CLEARCACHE} -eq 1 ]; then
    echo "Cleaning cache"
    rm -rf "${CACHE_PATH}/dl"
  fi
  mkdir -p "${CACHE_PATH}/dl"

  SPACELEFT=`df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print$4}'`  # Check disk space left

  PAT_FILE="${MODEL}-${BUILD}.pat"
  PAT_PATH="${CACHE_PATH}/dl/${PAT_FILE}"
  EXTRACTOR_PATH="${CACHE_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"
  OLDPAT_URL="https://global.download.synology.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"

  if [ -f "${PAT_PATH}" ]; then
    echo "${PAT_FILE} cached."
  else
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
# Shows available Drives
function alldrives() {
        TEXT=""
        NUMPORTS=0
        if [ "$ADSATA" -eq "1" ]; then
        for PCI in `lspci -nnk | grep -ie "\[0106\]" | awk '{print$1}'`; do
          NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
          TEXT+="\Z1SATA Controller\Zn dedected:\n\Zb${NAME}\Zn\n\nPorts: "
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
        TEXT+="\nPorts with color \Z1red\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected."
        TEXT+="\n \n"
        fi
        if [ "$ADRAID" -eq "1" ]; then
        pcis=$(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print $1}')
        [ ! -z "$pcis" ]
        # loop through non-SATA controllers
        for pci in $pcis; do
        # get attached block devices (exclude CD-ROMs)
        DRIVES=$(ls -la /sys/block | fgrep "$pci" | grep -v "sr.$" | wc -l)
        done
        for PCI in `lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print$1}'`; do
          NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
          TEXT+="\Z1SCSI/RAID/SAS Controller\Zn dedected:\n\Zb${NAME}\Zn\n"
          TEXT+="\nDrives: \Z2\Zb${DRIVES}\Zn connected"
          TEXT+="\n\n"
        done
        fi
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
          --msgbox "${TEXT}" 0 0
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
  while IFS="=" read KEY VALUE; do
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
      5 "Download a external Addon" \
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
        ADDONS[${ADDON}]="`<"${TMP_PATH}/resp"`"
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
      5)
        TEXT="please enter the complete URL to download.\n"
        dialog --backtitle "`backtitle`" --aspect 18 --colors --inputbox "${TEXT}" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        URL="`<"${TMP_PATH}/resp"`"
        [ -z "${URL}" ] && continue
        clear
        echo "Downloading ${URL}"
        STATUS=`curl --insecure -w "%{http_code}" -L "${URL}" -o "${TMP_PATH}/addon.tgz" --progress-bar`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "Error downloading" --aspect 18 \
            --msgbox "Check internet, URL or cache disk space" 0 0
          return 1
        fi
        ADDON="`untarAddon "${TMP_PATH}/addon.tgz"`"
        if [ -n "${ADDON}" ]; then
          dialog --backtitle "`backtitle`" --title "Success" --aspect 18 \
            --msgbox "Addon '${ADDON}' added to loader" 0 0
        else
          dialog --backtitle "`backtitle`" --title "Invalid addon" --aspect 18 \
            --msgbox "File format not recognized!" 0 0
        fi
        ;;
      0) return ;;
    esac
  done
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
# Permit user select the modules to include
function selectModules() {
  NEXT="1"
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  dialog --backtitle "`backtitle`" --title "Modules" --aspect 18 \
    --infobox "Reading modules" 0 0
  ALLMODULES=`getAllModules "${PLATFORM}" "${KVER}"`
  unset USERMODULES
  declare -A USERMODULES
  while IFS="=" read KEY VALUE; do
    [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
  done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
  # menu loop
  while true; do
    dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
      1 "Show selected Modules" \
      2 "Select all Modules" \
      3 "Deselect all Modules" \
      4 "Automated Modules selection" \
      5 "Choose Modules to include" \
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
        dialog --backtitle "`backtitle`" --title "Modules" \
           --infobox "Automated modules selection" 0 0
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        unset USERMODULES
        declare -A USERMODULES
        # Rebuild modules
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        # Unzip modules for temporary folder
        rm -rf "${TMP_PATH}/modules"
        mkdir -p "${TMP_PATH}/modules"
        gzip -dc "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" | tar xf - -C "${TMP_PATH}/modules"
        # Write modules to userconfig
        while read ID DESC; do
        if [ -f "${TMP_PATH}/modules/${ID}.ko" ]; then
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        fi
        done < <(kmod list | awk '{print$1}' | awk 'NR>1')
        rm -rf "${TMP_PATH}/modules"
        ;;
      5)
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
  zcat /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz | loadkeys
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
          --infobox "Checking last version" 0 0
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
          --infobox "Downloading last version ${TAG}" 0 0
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
        while IFS="=" read KEY VALUE; do
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
         arc-reboot.sh config
        exit
        ;;

      2)
        dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
          --infobox "Checking last version" 0 0
        TAG=`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
        if [ $? -ne 0 -o -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
          --infobox "Downloading last version" 0 0
        STATUS=`curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o /tmp/addons.zip`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --msgbox "Error downloading new version" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
          --infobox "Extracting last version" 0 0
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
          --msgbox "Addons updated with success!" 0 0
        ;;

      3)
        dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
          --infobox "Checking last version" 0 0
        TAG=`curl --insecure -s https://api.github.com/repos/AuxXxilium/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
        if [ $? -ne 0 -o -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
          --infobox "Downloading last version" 0 0
        STATUS=`curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o /tmp/rp-lkms.zip`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --msgbox "Error downloading last version" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
          --infobox "Extracting last version" 0 0
        rm -rf "${LKM_PATH}/"*
        unzip /tmp/rp-lkms.zip -d "${LKM_PATH}" >/dev/null 2>&1
        DIRTY=1
        dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
          --msgbox "LKMs updated with success!" 0 0
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
          --infobox "Checking last version" 0 0
        TAG=`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
        if [ $? -ne 0 -o -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          continue
        fi
        for P in ${!PLATFORMS[@]}; do
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --infobox "Downloading ${P} modules" 0 0
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
          --msgbox "Modules updated with success!" 0 0
        ;;
      0) return ;;
    esac
  done
}

###############################################################################
# Shows Systeminfo to user
function sysinfo() {
        # Checks for Systeminfo Menu
        TYPEINFO=$(vserver=$(lscpu | grep Hypervisor | wc -l))
        CPUINFO=$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')
        MEMINFO=$(free -g | awk 'NR==2' | awk '{print $2}')
        VENDOR=$(dmidecode -s system-product-name)
        TEXT=""
        TEXT+="\nSystem: \Zb${MACHINE}\Zn"
        TEXT+="\nVendor: \Zb${VENDOR}\Zn"
        TEXT+="\nCPU: \Zb${CPUINFO}\Zn"
        TEXT+="\nRAM: \Zb${MEMINFO}GB\Zn\n\n"
        # Check for Raid/SCSI // 104=RAID // 106=SATA // 107=HBA/SCSI
        # Get Information for Sata Controller
        if [ "$ADSATA" -gt 0 ]; then
        for PCI in `lspci -nnk | grep -ie "\[0106\]" | awk '{print$1}'`; do
          # Get Name of Controller
          NAME=`lspci -s "$PCI" | sed "s/\ .*://"`
          # Get Amount of Drives connected
          SATADRIVES=$(ls -la /sys/block | fgrep "$PCI" | grep -v "sr.$" | wc -l)
          TEXT+="\Z1SATA Controller\Zn dedected:\n\Zb${NAME}\Zn\n"
          TEXT+="\Z1Drives\Zn dedected:\n\Zb${SATADRIVES}\Zn\n"
        done
        TEXT+="\n"
        fi
        # Get Information for Raid/SCSI Controller
        if [ "$ADRAID" -gt 0 ]; then
        for PCI in `lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print$1}'`; do
          # Get Name of Controller
          NAME=`lspci -s "$PCI" | sed "s/\ .*://"`
          # Get Amount of Drives connected
          RAIDDRIVES=$(ls -la /sys/block | fgrep "$PCI" | grep -v "sr.$" | wc -l)
          TEXT+="\Z1SCSI/RAID/SAS Controller\Zn dedected:\n\Zb${NAME}\Zn\n"
          TEXT+="\Z1Drives\Zn dedected:\n\Zb${RAIDDRIVES}\Zn\n"
        done
        fi
        # List loaded Modules
        MODULESINFO=$(kmod list | awk '{print$1}' | awk 'NR>1')
        TEXT+="\nModules loaded: \Zb${MODULESINFO}\n"
        TEXT+="\n"
        dialog --backtitle "`backtitle`" --title "Systeminformation" --aspect 18 --colors --msgbox "${TEXT}" 0 0 
}

###############################################################################
# Let user edit cmdline
function cmdlineMenu() {
  NEXT="1"
  unset CMDLINE
  declare -A CMDLINE
  while IFS="=" read KEY VALUE; do
    [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
  done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
  echo "1 \"Add/edit a Cmdline item\""                          > "${TMP_PATH}/menu"
  echo "2 \"Delete Cmdline item(s)\""                           >> "${TMP_PATH}/menu"
  echo "3 \"Define a custom SataPortMap\""                      >> "${TMP_PATH}/menu"
  echo "4 \"Define a custom MAC\""                              >> "${TMP_PATH}/menu"
  echo "5 \"Show user Cmdline\""                                >> "${TMP_PATH}/menu"
  echo "6 \"Show Model/Build Cmdline\""                         >> "${TMP_PATH}/menu"
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
          dialog --backtitle "`backtitle`" --title "Custom SataPortMap" \
            --inputbox "Type a custom SataPortMap" 0 0 "${CMDLINE['SataPortMap']}"\
            2>${TMP_PATH}/resp
          [ $? -ne 0 ] && break
          PORTMAP="`<"${TMP_PATH}/resp"`"
          [ -z "${PORTMAP}" ] && PORTMAP="`readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"`"
          writeConfigKey "cmdline.SataPortMap"      "${PORTMAP}" "${USER_CONFIG_FILE}"
        done
        ;;
      4)
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
      5)
        ITEMS=""
        for KEY in ${!CMDLINE[@]}; do
          ITEMS+="${KEY}: ${CMDLINE[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "User cmdline" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      6)
        ITEMS=""
        while IFS="=" read KEY VALUE; do
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
  # Get dt flag from model
  DT="`readModelKey "${MODEL}" "dt"`"
  # Read synoinfo from user config
  unset SYNOINFO
  declare -A SYNOINFO
  while IFS="=" read KEY VALUE; do
    [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
  done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "1 \"Add/edit Synoinfo item\""     > "${TMP_PATH}/menu"
  echo "2 \"Delete Synoinfo item(s)\""    >> "${TMP_PATH}/menu"
  if [ "${DT}" != "true" ]; then
    echo "3 \"Set maxdisks manually\""    >> "${TMP_PATH}/menu"
  fi
  echo "4 \"Map USB Drive to internal\""  >> "${TMP_PATH}/menu"
  echo "5 \"Show Synoinfo entries\""      >> "${TMP_PATH}/menu"
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
        MAXDISKS=`readConfigKey "maxdisks" "${USER_CONFIG_FILE}"`
        dialog --backtitle "`backtitle`" --title "Maxdisks" \
          --inputbox "Type a value for maxdisks" 0 0 "${MAXDISKS}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        VALUE="`<"${TMP_PATH}/resp"`"
        [ "${VALUE}" != "${MAXDISKS}" ] && writeConfigKey "maxdisks" "${VALUE}" "${USER_CONFIG_FILE}"
        ;;
      4)
        writeConfigKey "synoinfo.maxdisks" "24" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.esataportcfg" "0x00" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.usbportcfg" "0x00" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.internalportcfg" "0xffffffff" "${USER_CONFIG_FILE}"
        dialog --backtitle "`backtitle`" --msgbox "External USB Drives mapped" 0 0 
        ;;
      5)
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
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  [ ${DIRTY} -eq 1 ] && dialog --backtitle "`backtitle`" --title "Alert" \
    --yesno "Config changed, would you like to rebuild the loader?" 0 0
  if [ $? -eq 0 ]; then
    make || return
  fi
  dialog --backtitle "`backtitle`" --title "Arc Boot" \
    --infobox "Booting to DSM - Please stay patient!" 0 0
  boot.sh
}

###############################################################################
###############################################################################

if [ "x$1" = "xb" -a -n "${MODEL}" -a -n "${BUILD}" -a loaderIsConfigured ]; then
  make
  boot
fi
# Main loop
NEXT="1"
while true; do
  echo "= \"\Z4========== Main ========== \Zn\" "                                            > "${TMP_PATH}/menu"
  echo "1 \"Choose Model for Loader \" "                                                    >> "${TMP_PATH}/menu"
  if [ -n "${MODEL}" ] && [ -n "${BUILD}" ] && [ "${CONFDONE}" -eq "1" ]; then
      echo "4 \"Build the Loader \" "                                                       >> "${TMP_PATH}/menu"
  fi
  if loaderIsConfigured; then
  echo "5 \"Boot the Loader \" "                                                            >> "${TMP_PATH}/menu"
  fi
  echo "= \"\Z4========== Info ========== \Zn\" "                                           >> "${TMP_PATH}/menu"
  echo "a \"Show Controller/Drives \" "                                                     >> "${TMP_PATH}/menu"
  echo "b \"Systeminfo \" "                                                                 >> "${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
  echo "= \"\Z4========= System ========= \Zn\" "                                           >> "${TMP_PATH}/menu"
  echo "2 \"Addons \" "                                                                     >> "${TMP_PATH}/menu"
  echo "3 \"Modules \" "                                                                    >> "${TMP_PATH}/menu"
  echo "n \"New Disk Config \" "                                                            >> "${TMP_PATH}/menu"
  if [ -n "${ADV}" ]; then
  echo "x \"\Z1Hide Advanced Options \Zn\" "                                                >> "${TMP_PATH}/menu"
  else
  echo "x \"\Z1Show Advanced Options \Zn\" "                                                >> "${TMP_PATH}/menu"
  fi
  if [ -n "${ADV}" ]; then
  echo "f \"Cmdline \" "                                                                    >> "${TMP_PATH}/menu"
  echo "g \"Synoinfo \" "                                                                   >> "${TMP_PATH}/menu"
  echo "h \"Edit user config \" "                                                           >> "${TMP_PATH}/menu"
  echo "i \"DSM Recovery \" "                                                               >> "${TMP_PATH}/menu"
  echo "j \"Switch LKM version: \Z4${LKM}\Zn\" "                                            >> "${TMP_PATH}/menu"
  echo "k \"Switch direct boot: \Z4${DIRECTBOOT}\Zn \" "                                    >> "${TMP_PATH}/menu"
  fi
  fi
  echo "= \"\Z4===== Loader Settings ==== \Zn\" "                                           >> "${TMP_PATH}/menu"
  echo "c \"Choose a keymap \" "                                                            >> "${TMP_PATH}/menu"
  if [ ${CLEARCACHE} -eq 1 -a -d "${CACHE_PATH}/dl" ]; then
  echo "d \"Clean disk cache \""                                                            >> "${TMP_PATH}/menu"
  fi
  echo "e \"Update Menu \" "                                                                >> "${TMP_PATH}/menu"
  echo "0 \"\Z1Exit\Zn\" "                                                                  >> "${TMP_PATH}/menu"
  dialog --clear --default-item ${NEXT} --backtitle "`backtitle`" --colors \
    --menu "Choose an Option" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && break
  case `<"${TMP_PATH}/resp"` in
    1) arcMenu; NEXT="4" ;;
    4) make; NEXT="5" ;;
    5) boot ;;
    a) alldrives; NEXT="a" ;;
    b) sysinfo; NEXT="b" ;;
    2) addonMenu; NEXT="2" ;;
    3) selectModules; NEXT="3" ;;
    n) newarcdisk; NEXT="4" ;;
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
    e) updateMenu; NEXT="e" ;;
    0) break ;;
  esac
done
clear
echo -e "Call \033[1;32marc.sh\033[0m to return to menu"