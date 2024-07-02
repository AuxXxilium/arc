#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/compat.sh
. ${ARC_PATH}/include/modules.sh
. ${ARC_PATH}/include/storage.sh
. ${ARC_PATH}/include/network.sh
. ${ARC_PATH}/include/update.sh
. ${ARC_PATH}/arc-functions.sh
. ${ARC_PATH}/boot.sh

[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"

# Check for System
systemCheck

# Offline Mode check
ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
AUTOMATED="$(readConfigKey "arc.automated" "${USER_CONFIG_FILE}")"
offlineCheck

# Get DSM Data from Config
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
if [ -n "${MODEL}" ]; then
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}" 2>/dev/null)"
fi

# Get Arc Data from Config
ARC_KEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
EMMCBOOT="$(readConfigKey "arc.emmcboot" "${USER_CONFIG_FILE}")"
CPUGOVERNOR="$(readConfigKey "arc.governor" "${USER_CONFIG_FILE}")"
HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "arc.kernel" "${USER_CONFIG_FILE}")"
KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "arc.kernelpanic" "${USER_CONFIG_FILE}")"
ODP="$(readConfigKey "arc.odp" "${USER_CONFIG_FILE}")"
OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
RD_COMPRESSED="$(readConfigKey "rd-compressed" "${USER_CONFIG_FILE}")"
SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
SATACONTROLLER="$(readConfigKey "device.satacontroller" "${USER_CONFIG_FILE}")"
SCSICONTROLLER="$(readConfigKey "device.scsicontroller" "${USER_CONFIG_FILE}")"
RAIDCONTROLLER="$(readConfigKey "device.raidcontroller" "${USER_CONFIG_FILE}")"
SASCONTROLLER="$(readConfigKey "device.sascontroller" "${USER_CONFIG_FILE}")"

# Get Config/Build Status
CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"

# Get Keymap and Timezone Config
ntpCheck

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  if [ -n "${NEWTAG}" ] && [ "${NEWTAG}" != "${ARC_VERSION}" ] && [ "${OFFLINE}" == "false" ]; then
    ARC_TITLE="${ARC_TITLE} -> ${NEWTAG}"
  fi
  if [ -z "${MODEL}" ]; then
    MODEL="(Model)"
  fi
  if [ -z "${PRODUCTVER}" ]; then
    PRODUCTVER="(Version)"
  fi
  if [ -z "${IPCON}" ]; then
    IPCON="(IP)"
  fi
  if [ "${OFFLINE}" == "true" ]; then
    OFF=" (Offline)"
  fi
  BACKTITLE="${ARC_TITLE} | "
  BACKTITLE+="${MODEL} | "
  BACKTITLE+="${PRODUCTVER} | "
  BACKTITLE+="${IPCON}${OFF} | "
  BACKTITLE+="Patch: ${ARCPATCH} | "
  BACKTITLE+="Config: ${CONFDONE} | "
  BACKTITLE+="Build: ${BUILDDONE} | "
  BACKTITLE+="${MACHINE}(${BUS}) | "
  BACKTITLE+="KB: ${KEYMAP}"
  echo "${BACKTITLE}"
}

###############################################################################
# Model Selection
function arcModel() {
  dialog --backtitle "$(backtitle)" --title "DSM Model" \
    --infobox "Reading Models..." 3 25
  # Loop menu
  RESTRICT=1
  PS="$(readConfigEntriesArray "platforms" "${P_FILE}" | sort)"
  if [ "${OFFLINE}" == "true" ]; then
    MJ="$(python ${ARC_PATH}/include/functions.py getmodelsoffline -p "${PS[*]}")"
  else
    MJ="$(python ${ARC_PATH}/include/functions.py getmodels -p "${PS[*]}")"
  fi
  if [[ -z "${MJ}" || "${MJ}" == "[]" ]]; then
    dialog --backtitle "$(backtitle)" --title "Model" --title "Model" \
      --msgbox "Failed to get models, please try again!" 0 0
    return 1
  fi
  echo -n "" >"${TMP_PATH}/modellist"
  echo "${MJ}" | jq -c '.[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    arch=$(echo "$item" | jq -r '.arch')
    echo "${name} ${arch}" >>"${TMP_PATH}/modellist"
  done
  if [ "${AUTOMATED}" == "false" ]; then
    while true; do
      echo -n "" >"${TMP_PATH}/menu"
      while read -r M A; do
        COMPATIBLE=1
        DT="$(readConfigKey "platforms.${A}.dt" "${P_FILE}")"
        FLAGS="$(readConfigArray "platforms.${A}.flags" "${P_FILE}")"
        ARCCONF="$(readConfigKey "${M}.serial" "${S_FILE}" 2>/dev/null)"
        ARC=""
        BETA=""
        [ -n "${ARCCONF}" ] && ARC="x" || ARC=""
        [ "${DT}" == "true" ] && DTS="x" || DTS=""
        IGPUS=""
        [[ "${A}" == "apollolake" || "${A}" == "geminilake" ]] && IGPUS="up to 10th"
        [ "${A}" == "epyc7002" ] && IGPUS="up to 14th" 
        [ "${DT}" == "true" ] && HBAS="" || HBAS="x"
        [ "${M}" == "SA6400" ] && HBAS="x"
        [ "${DT}" == "false" ] && USBS="x" || USBS=""
        [[ "${M}" == "DS918+" || "${M}" == "DS1019+" || "${M}" == "DS1621xs+" || "${M}" == "RS1619xs+" ]] && M_2_CACHE="+" || M_2_CACHE="x"
        [[ "${M}" == "DS220+" ||  "${M}" == "DS224+" ]] && M_2_CACHE=""
        [ "${DT}" == "false" ] && M_2_STORAGE="" || M_2_STORAGE="+"
        [[ "${M}" == "DS220+" || "${M}" == "DS224+" ]] && M_2_STORAGE=""
        # Check id model is compatible with CPU
        if [ ${RESTRICT} -eq 1 ]; then
          for F in "${FLAGS}"; do
            if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
              COMPATIBLE=0
              break
            fi
          done
          if [ "${A}" != "epyc7002" ] && [ "${DT}" == "true" ] && [ "${EXTERNALCONTROLLER}" == "true" ]; then
            COMPATIBLE=0
          fi
          if [ "${A}" != "epyc7002" ] && [ ${SATACONTROLLER} -eq 0 ] && [ "${EXTERNALCONTROLLER}" == "false" ]; then
            COMPATIBLE=0
          fi
          if [ "${A}" = "epyc7002" ] && [ ${SCSICONTROLLER} -ne 0 ]; then
            COMPATIBLE=0
          fi
          [ -z "$(grep -w "${M}" "${S_FILE}")" ] && COMPATIBLE=0
        fi
        [ -n "$(grep -w "${M}" "${S_FILE}")" ] && BETA="Arc" || BETA="Syno"
        [ -z "$(grep -w "${A}" "${P_FILE}")" ] && COMPATIBLE=0
        if [ -n "${ARC_KEY}" ]; then
          [ ${COMPATIBLE} -eq 1 ] && echo -e "${M} \"\t$(printf "\Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-12s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "${A}" "${DTS}" "${ARC}" "${IGPUS}" "${HBAS}" "${M_2_CACHE}" "${M_2_STORAGE}" "${USBS}" "${BETA}")\" ">>"${TMP_PATH}/menu"
        else
          [ ${COMPATIBLE} -eq 1 ] && echo -e "${M} \"\t$(printf "\Zb%-15s\Zn \Zb%-5s\Zn \Zb%-12s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "${A}" "${DTS}" "${IGPUS}" "${HBAS}" "${M_2_CACHE}" "${M_2_STORAGE}" "${USBS}" "${BETA}")\" ">>"${TMP_PATH}/menu"
        fi
      done < <(cat "${TMP_PATH}/modellist")
      if [ -n "${ARC_KEY}" ]; then
        dialog --backtitle "$(backtitle)" --title "Arc DSM Model" --colors \
          --cancel-label "Show all" --help-button --help-label "Exit" \
          --extra-button --extra-label "Info" \
          --menu "Supported Models for your Hardware (x = supported / + = need Addons)\n$(printf "\Zb%-16s\Zn \Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-12s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "Model" "Platform" "DT" "Arc" "iGPU/i915" "HBA" "M.2 Cache" "M.2 Volume" "USB Mount" "Source")" 0 112 0 \
          --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
      else
        dialog --backtitle "$(backtitle)" --title "DSM Model" --colors \
          --cancel-label "Show all" --help-button --help-label "Exit" \
          --extra-button --extra-label "Info" \
          --menu "Supported Models for your Hardware (x = supported / + = need Addons) | Syno Models can have faulty Values.\n$(printf "\Zb%-16s\Zn \Zb%-15s\Zn \Zb%-5s\Zn \Zb%-12s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "Model" "Platform" "DT" "iGPU/i915" "HBA" "M.2 Cache" "M.2 Volume" "USB Mount" "Source")" 0 112 0 \
          --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
      fi
      RET=$?
      case ${RET} in
        0) # ok-button
          resp=$(cat ${TMP_PATH}/resp)
          [ -z "${resp}" ] && return 1
          break
          ;;
        1) # cancel-button -> Show all Models
          [ ${RESTRICT} -eq 1 ] && RESTRICT=0 || RESTRICT=1
          ;;
        2) # help-button -> Exit
          return 1
          break
          ;;
        3) # extra-button -> Platform Info
          resp=$(cat ${TMP_PATH}/resp)
          PLATFORM="$(grep -w "${resp}" "${TMP_PATH}/modellist" | awk '{print $2}' | head -n 1)"
          dialog --backtitle "$(backtitle)" --colors \
            --title "Platform Info" --textbox "./informations/${PLATFORM}.yml" 15 80
          ;;
        255) # ESC -> Exit
          return 1
          break
          ;;
      esac
    done
  fi
  # Reset Model Config if changed
  if [ "${MODEL}" != "${resp}" ]; then
    PRODUCTVER=""
    MODEL="${resp}"
    PLATFORM="$(grep -w "${MODEL}" "${TMP_PATH}/modellist" | awk '{print $2}' | head -n 1)"
    MODELID=$(echo ${MODEL} | sed 's/d$/D/; s/rp$/RP/; s/rp+/RP+/')
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    writeConfigKey "productver" "" "${USER_CONFIG_FILE}"
    writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.emmcboot" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.hddsort" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.kernel" "official" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.odp" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.sn" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modelid" "${MODELID}" "${USER_CONFIG_FILE}"
    writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"
    writeConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
  elif [ -z "${resp}" ]; then
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    PLATFORM="$(grep -w "${MODEL}" "${TMP_PATH}/modellist" | awk '{print $2}' | head -n 1)"
    MODELID=$(echo ${MODEL} | sed 's/d$/D/; s/rp$/RP/; s/rp+/RP+/')
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modelid" "${MODELID}" "${USER_CONFIG_FILE}"
    writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"
    writeConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
    writeConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
  fi
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "arc.emmcboot" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
  KERNEL="$(readConfigKey "arc.kernel" "${USER_CONFIG_FILE}")"
  ODP="$(readConfigKey "arc.odp" "${USER_CONFIG_FILE}")"
  if [ -f "${ORI_ZIMAGE_FILE}" ] || [ -f "${ORI_RDGZ_FILE}" ] || [ -f "${MOD_ZIMAGE_FILE}" ] || [ -f "${MOD_RDGZ_FILE}" ]; then
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" 2>/dev/null || true
  fi
  arcVersion
}

###############################################################################
# Arc Version Section
function arcVersion() {
  # read model values for arcbuild
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  AUTOMATED="$(readConfigKey "arc.automated" "${USER_CONFIG_FILE}")"
  # Check for Custom Build
  if [ "${AUTOMATED}" == "false" ]; then
    # Select Build for DSM
    ITEMS="$(readConfigEntriesArray "platforms.${PLATFORM}.productvers" "${P_FILE}" | sort -r)"
    dialog --clear --no-items --nocancel --title "DSM Version" --backtitle "$(backtitle)" \
      --no-items --menu "Choose DSM Version" 7 30 0 ${ITEMS} \
    2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 0
    resp=$(cat ${TMP_PATH}/resp)
    [ -z "${resp}" ] && return 1
    if [ "${PRODUCTVER}" != "${resp}" ]; then
      PRODUCTVER="${resp}"
      writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
      # Delete old files
      rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" 2>/dev/null || true
    fi
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Config" \
    --infobox "Reconfiguring Addons, Modules and Synoinfo" 3 50
  # Reset Synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read -r KEY VALUE; do
    writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
  done < <(readConfigMap "platforms.${PLATFORM}.synoinfo" "${P_FILE}")
  # Check Addons for Platform
  while IFS=': ' read -r ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}"; then
      deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Reset Modules
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  # Modify KVER for Epyc7002
  if [ "${PLATFORM}" == "epyc7002" ]; then
    KVERP="${PRODUCTVER}-${KVER}"
  else
    KVERP="${KVER}"
  fi
  # Rewrite modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  cp -f "${ARC_PATH}/include/modulelist" "${USER_UP_PATH}/modulelist"
  echo -e "\n\n# Arc Modules" >>"${USER_UP_PATH}/modulelist"
  KOLIST=""
  for I in $(lsmod | awk -F' ' '{print $1}' | grep -v 'Module'); do
    KOLIST+="$(getdepends "${PLATFORM}" "${KVERP}" "${I}") ${I} "
  done
  KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
  while read -r ID DESC; do
    writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
    for MOD in ${KOLIST[@]}; do
      [ "${MOD}" == "${ID}" ] && echo "N ${ID}.ko" >>"${USER_UP_PATH}/modulelist"
    done
  done < <(getAllModules "${PLATFORM}" "${KVERP}")
  # Check for Only Version
  if [ "${ONLYVERSION}" == "true" ]; then
    # Build isn't done
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    ONLYVERSION="false"
    return 0
  else
    arcPatch
  fi
}

###############################################################################
# Arc Patch Section
function arcPatch() {
  # Read Model Values
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  AUTOMATED="$(readConfigKey "arc.automated" "${USER_CONFIG_FILE}")"
  ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}" 2>/dev/null)"
  # Check for Custom Build
  SN="$(readConfigKey "arc.sn" "${USER_CONFIG_FILE}")"
  if [ "${AUTOMATED}" == "true" ] && [ -z "${SN}" ]; then
    SN=$(generateSerial "${MODEL}" false)
    writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
  elif [ "${AUTOMATED}" == "false" ]; then
    if [ -n "${ARCCONF}" ]; then
      dialog --clear --backtitle "$(backtitle)" \
        --nocancel --title "Arc Patch"\
        --menu "Please choose an Option." 7 50 0 \
        1 "Use Arc Patch (only for QC)" \
        2 "Use random SN/Mac" \
        3 "Use my own SN/Mac" \
      2>"${TMP_PATH}/resp"
      resp=$(cat ${TMP_PATH}/resp)
      [ -z "${resp}" ] && return 1
      if [ ${resp} -eq 1 ]; then
        # Read Arc Patch from File
        SN=$(generateSerial "${MODEL}" true)
        writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
      elif [ ${resp} -eq 2 ]; then
        # Generate random Serial
        SN=$(generateSerial "${MODEL}" false)
        writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
      elif [ ${resp} -eq 3 ]; then
        while true; do
          dialog --backtitle "$(backtitle)" --colors --title "DSM SN" \
            --inputbox "Please enter a valid SN!" 7 50 "" \
            2>"${TMP_PATH}/resp"
          [ $? -ne 0 ] && break 2
          SN="$(cat ${TMP_PATH}/resp)"
          if [ -z "${SN}" ]; then
            return
          elif [ $(validateSerial ${MODEL} ${SN}) -eq 1 ]; then
            break
          fi
          # At present, the SN rules are not complete, and many SNs are not truly invalid, so not provide tips now.
          dialog --backtitle "$(backtitle)" --colors --title "DSM SN" \
            --yesno "SN looks invalid, continue?" 5 50
          [ $? -eq 0 ] && break
        done
        writeConfigKey "arc.patch" "user" "${USER_CONFIG_FILE}"
      fi
    elif [ -z "${ARCCONF}" ]; then
      dialog --clear --backtitle "$(backtitle)" \
        --nocancel --title "Non Arc Patch Model" \
        --menu "Please choose an Option." 8 50 0 \
        1 "Use random SN/Mac" \
        2 "Use my SN/Mac" \
      2>"${TMP_PATH}/resp"
      resp=$(cat ${TMP_PATH}/resp)
      [ -z "${resp}" ] && return 1
      if [ ${resp} -eq 1 ]; then
        # Generate random Serial
        SN=$(generateSerial "${MODEL}" false)
        writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
      elif [ ${resp} -eq 2 ]; then
        while true; do
          dialog --backtitle "$(backtitle)" --colors --title "DSM SN" \
            --inputbox "Please enter a SN " 7 50 "" \
            2>"${TMP_PATH}/resp"
          [ $? -ne 0 ] && break 2
          SN="$(cat ${TMP_PATH}/resp)"
          if [ -z "${SN}" ]; then
            return
          elif [ $(validateSerial ${MODEL} ${SN}) -eq 1 ]; then
            break
          fi
          # At present, the SN rules are not complete, and many SNs are not truly invalid, so not provide tips now.
          dialog --backtitle "$(backtitle)" --colors --title "DSM SN" \
            --yesno "SN looks invalid, continue?" 5 50
          [ $? -eq 0 ] && break
        done
        writeConfigKey "arc.patch" "user" "${USER_CONFIG_FILE}"
      fi
    fi
  fi
  writeConfigKey "arc.sn" "${SN}" "${USER_CONFIG_FILE}"
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  arcSettings
}

###############################################################################
# Arc Settings Section
function arcSettings() {
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  AUTOMATED="$(readConfigKey "arc.automated" "${USER_CONFIG_FILE}")"
  # Get Network Config for Loader
  dialog --backtitle "$(backtitle)" --colors --title "Network Config" \
    --infobox "Generating Network Config..." 3 40
  sleep 2
  getnet
  if [ "${ONLYPATCH}" == "true" ]; then
    # Build isn't done
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    ONLYPATCH="false"
    return 0
  fi
  # Select Portmap for Loader
  if [ "${DT}" == "false" ] && [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Storage Map" \
      --infobox "Generating Storage Map..." 3 40
    sleep 2
    getmapSelection
  fi
  # Check for CPU Frequency Scaling
  if [ "${CPUFREQ}" == "true" ]; then
    # Select Governor for DSM
    dialog --backtitle "$(backtitle)" --colors --title "CPU Frequency Scaling" \
      --infobox "Generating Governor Table..." 3 40
    governorSelection
  fi
  # Check for Custom Build
  if [ "${AUTOMATED}" == "false" ]; then
    # Select Addons
    dialog --backtitle "$(backtitle)" --colors --title "DSM Addons" \
      --infobox "Loading Addons Table..." 3 40
    writeConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
    writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
    writeConfigKey "addons.storagepanel" "" "${USER_CONFIG_FILE}"
    addonSelection
    # Check for DT and HBA/Raid Controller
    if [ "${PLATFORM}" != "epyc7002" ]; then
      if [ "${DT}" == "true" ] && [ "${EXTERNALCONTROLLER}" == "true" ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Warning" \
          --msgbox "WARN: You use a HBA/Raid Controller and selected a DT Model. This is still an experimental." 5 90
      fi
    fi
    # Check for more then 8 Ethernet Ports
    DEVICENIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
    if [ ${DEVICENIC} -gt 8 ]; then
      dialog --backtitle "$(backtitle)" --title "Arc Warning" \
        --msgbox "WARN: You have more then 8 Ethernet Ports. Only 8 supported by DSM." 5 80
    fi
    # Check for AES
    if [ "${AESSYS}" == "false" ]; then
      dialog --backtitle "$(backtitle)" --title "Arc Warning" \
        --msgbox "WARN: Your System doesn't support Hardwareencryption in DSM. (AES)" 5 80
    fi
    # Check for CPUFREQ
    if [ "${CPUFREQ}" == "false" ]; then
      dialog --backtitle "$(backtitle)" --title "Arc Warning" \
        --msgbox "WARN: Your System doesn't support CPU Frequency Scaling in DSM." 5 80
    fi
  fi
  EMMCBOOT="$(readConfigKey "arc.emmcboot" "${USER_CONFIG_FILE}")"
  # eMMC Boot Support
  if [ "${EMMCBOOT}" == "true" ]; then
    writeConfigKey "modules.mmc_block" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modules.mmc_core" "" "${USER_CONFIG_FILE}"
  else
    deleteConfigKey "modules.mmc_block" "${USER_CONFIG_FILE}"
    deleteConfigKey "modules.mmc_core" "${USER_CONFIG_FILE}"
  fi
  # Max Memory for DSM
  RAMCONFIG="$((${RAMTOTAL} * 1024))"
  writeConfigKey "synoinfo.mem_max_mb" "${RAMCONFIG}" "${USER_CONFIG_FILE}"
  # Config is done
  writeConfigKey "arc.confdone" "true" "${USER_CONFIG_FILE}"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  # Check for Custom Build
  if [ "${AUTOMATED}" == "false" ]; then
    # Ask for Build
    dialog --clear --backtitle "$(backtitle)" --title "Config done" \
      --no-cancel --menu "Build now?" 7 40 0 \
      1 "Yes - Build Arc Loader now" \
      2 "No - I want to make changes" \
    2>"${TMP_PATH}/resp"
    resp=$(cat ${TMP_PATH}/resp)
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      arcSummary
    elif [ ${resp} -eq 2 ]; then
      dialog --clear --no-items --backtitle "$(backtitle)"
      return 1
    fi
  else
    # Build Loader
    make
  fi
}

###############################################################################
# Calls boot.sh to boot into DSM Recovery
function arcSummary() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
  if [ "${REMAP}" == "acports" ] || [ "${REMAP}" == "maxports" ]; then
    PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
    DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
  elif [ "${REMAP}" == "remap" ]; then
    PORTREMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
  fi
  DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
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
  [ "${MODEL}" == "SA6400" ] && SUMMARY+="\n>> Kernel: \Zb${KERNEL}\Zn"
  SUMMARY+="\n>> Kernel Version: \Zb${KVER}\Zn"
  SUMMARY+="\n"
  SUMMARY+="\n\Z4> Arc Information\Zn"
  SUMMARY+="\n>> Arc Patch: \Zb${ARCPATCH}\Zn"
  [ -n "${PORTMAP}" ] && SUMMARY+="\n>> SataPortmap: \Zb${PORTMAP}\Zn"
  [ -n "${DISKMAP}" ] && SUMMARY+="\n>> DiskIdxMap: \Zb${DISKMAP}\Zn"
  [ -n "${PORTREMAP}" ] && SUMMARY+="\n>> SataRemap: \Zb${PORTREMAP}\Zn"
  [ "${DT}" == "true" ] && SUMMARY+="\n>> Sort Drives: \Zb${HDDSORT}\Zn"
  SUMMARY+="\n>> Offline Mode: \Zb${OFFLINE}\Zn"
  SUMMARY+="\n>> Directboot: \Zb${DIRECTBOOT}\Zn"
  SUMMARY+="\n>> eMMC Boot: \Zb${EMMCBOOT}\Zn"
  SUMMARY+="\n>> Kernelload: \Zb${KERNELLOAD}\Zn"
  SUMMARY+="\n>> Addons: \Zb${ADDONSINFO}\Zn"
  SUMMARY+="\n"
  SUMMARY+="\n\Z4> Device Information\Zn"
  SUMMARY+="\n>> AES | ACPI: \Zb${AESSYS} | ${ACPISYS}\Zn"
  SUMMARY+="\n>> CPU Scaling: \Zb${CPUFREQ}\Zn"
  SUMMARY+="\n>> NIC: \Zb${NIC}\Zn"
  SUMMARY+="\n>> Disks (incl. USB): \Zb${DRIVES}\Zn"
  SUMMARY+="\n>> Disks (internal): \Zb${HARDDRIVES}\Zn"
  SUMMARY+="\n>> External Controller: \Zb${EXTERNALCONTROLLER}\Zn"
  SUMMARY+="\n>> Memory: \Zb${RAMTOTAL}GB\Zn"
  dialog --backtitle "$(backtitle)" --colors --title "DSM Config Summary" \
    --extra-button --extra-label "Cancel" --msgbox "${SUMMARY}" 0 0
  RET=$?
  case ${RET} in
    0) # ok-button
      make
      ;;
    3) # extra-button
      return 0
      ;;
    255) # ESC
      return 0
      ;;
  esac
}

###############################################################################
# Building Loader Online
function make() {
  # Read Model Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  AUTOMATED="$(readConfigKey "arc.automated" "${USER_CONFIG_FILE}")"
  PAT_URL=""
  PAT_HASH=""
  VALID="false"
  # Cleanup
  [ -d "${UNTAR_PAT_PATH}" ] && rm -rf "${UNTAR_PAT_PATH}"
  mkdir -p "${UNTAR_PAT_PATH}"
  if [ "${OFFLINE}" == "false" ]; then
    # Get PAT Data
    dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
      --infobox "Get PAT Data from Syno..." 3 30
    idx=0
    while [ ${idx} -le 3 ]; do # Loop 3 times, if successful, break
      if [ "${ARCNIC}" == "auto" ]; then
        PAT_DATA="$(curl -skL -m 10 "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}")"
      else
        PAT_DATA="$(curl --interface ${ARCNIC} -skL -m 10 "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}")"
      fi
      if [ "$(echo ${PAT_DATA} | jq -r '.success' 2>/dev/null)" == "true" ]; then
        if echo ${PAT_DATA} | jq -r '.info.system.detail[0].items[0].files[0].label_ext' 2>/dev/null | grep -q 'pat'; then
          PAT_URL=$(echo ${PAT_DATA} | jq -r '.info.system.detail[0].items[0].files[0].url')
          PAT_HASH=$(echo ${PAT_DATA} | jq -r '.info.system.detail[0].items[0].files[0].checksum')
          PAT_URL=${PAT_URL%%\?*}
          if [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ]; then
            if echo "${PAT_URL}" | grep -q "https://"; then
              VALID=true
              break
            fi
          fi
        fi
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
    if [ "${VALID}" == "false" ]; then
      dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
        --infobox "Get PAT Data from Github..." 3 30
      idx=0
      while [ ${idx} -le 3 ]; do # Loop 3 times, if successful, break
        if [ "${ARCNIC}" == "auto" ]; then
          PAT_URL="$(curl -skL -m 10 "https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/dsm/${MODEL/+/%2B}/${PRODUCTVER}/pat_url")"
          PAT_HASH="$(curl -skL -m 10 "https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/dsm/${MODEL/+/%2B}/${PRODUCTVER}/pat_hash")"
        else
          PAT_URL="$(curl --interface ${ARCNIC} -m 10 -skL "https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/dsm/${MODEL/+/%2B}/${PRODUCTVER}/pat_url")"
          PAT_HASH="$(curl --interface ${ARCNIC} -m 10 -skL "https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/dsm/${MODEL/+/%2B}/${PRODUCTVER}/pat_hash")"
        fi
        PAT_URL=${PAT_URL%%\?*}
        if [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ]; then
          if echo "${PAT_URL}" | grep -q "https://"; then
            VALID="true"
            break
          fi
        fi
        sleep 3
        idx=$((${idx} + 1))
      done
    fi
    if [ "${AUTOMATED}" == "false" ] && [ "${VALID}" == "false" ]; then
        MSG="Failed to get PAT Data.\nPlease manually fill in the URL and Hash of PAT."
        MSG+="You will find these Data at:\nhttps://download.synology.com"
        dialog --backtitle "$(backtitle)" --colors --title "Arc Build" --default-button "OK" \
          --form "${MSG}" 10 110 2 "URL" 1 1 "${PAT_URL}" 1 7 100 0 "HASH" 2 1 "${PAT_HASH}" 2 7 100 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        [ ${RET} -eq 0 ]             # ok-button
        return 1                     # 1 or 255  # cancel-button or ESC
        PAT_URL="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
        PAT_HASH="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
    elif [ "${VALID}" == "false" ]; then
        dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
          --infobox "Could not get PAT Data..." 4 30
        PAT_URL="#"
        PAT_HASH="#"
        sleep 5
    elif [ "${VALID}" == "true" ]; then
      # Get PAT Data from Config
      PAT_URL_CONF="$(readConfigKey "arc.paturl" "${USER_CONFIG_FILE}")"
      PAT_HASH_CONF="$(readConfigKey "arc.pathash" "${USER_CONFIG_FILE}")"
      if [ "${PAT_HASH}" != "${PAT_HASH_CONF}" ] || [ ! -f "${ORI_ZIMAGE_FILE}" ] || [ ! -f "${ORI_RDGZ_FILE}" ]; then
        # Write new PAT Data to Config
        writeConfigKey "arc.paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.pathash" "${PAT_HASH}" "${USER_CONFIG_FILE}"
        # Get new Files
        DSM_FILE="${UNTAR_PAT_PATH}/${PAT_HASH}.tar"
        DSM_URL="https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/files/${MODEL/+/%2B}/${PRODUCTVER}/${PAT_HASH}.tar"
        if curl -skL "${DSM_URL}" -o "${DSM_FILE}"; then
          VALID="true"
        elif curl --interface ${ARCNIC} -skL "${DSM_URL}" -o "${DSM_FILE}"; then
          VALID="true"
        else
          dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
            --infobox "No DSM Image found!\nTry to get .pat from Syno." 4 40
          sleep 5
          # Grep PAT_URL
          PAT_FILE="${TMP_PATH}/${PAT_HASH}.pat"
          if curl -skL "${DSM_URL}" -o "${DSM_FILE}"; then
            VALID="true"
          elif curl --interface ${ARCNIC} -skL "${DSM_URL}" -o "${DSM_FILE}"; then
            VALID="true"
          else
            dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
              --infobox "No DSM Image found!\nExit." 4 40
            VALID="false"
            sleep 5
          fi
        fi
        if [ -f "${DSM_FILE}" ] && [ "${VALID}" == "true" ]; then
          tar -xf "${DSM_FILE}" -C "${UNTAR_PAT_PATH}" 2>/dev/null
          VALID="true"
        elif [ -f "${PAT_FILE}" ] && [ "${VALID}" == "true" ]; then
          extractDSMFiles "${PAT_FILE}" "${UNTAR_PAT_PATH}" 2>/dev/null
          VALID="true"
        else
          dialog --backtitle "$(backtitle)" --title "DSM Extraction" --aspect 18 \
            --infobox "DSM Extraction failed!\nExit." 4 40
          VALID="false"
          sleep 5
        fi
      fi
    fi
  elif [ "${OFFLINE}" == "true" ] && [ "${AUTOMATED}" ==  "false" ]; then
    if [ -f "${ORI_ZIMAGE_FILE}" ] && [ -f "${ORI_RDGZ_FILE}" ]; then
      rm -f "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" 2>/dev/null || true
      VALID="true"
    else
      # Check for existing Files
      mkdir -p "${TMP_UP_PATH}"
      # Get new Files
      dialog --backtitle "$(backtitle)" --title "DSM Upload" --aspect 18 \
      --msgbox "Upload your DSM .pat File now to /tmp/upload.\nUse Webfilebrowser: ${IPCON}:7304\nor SSH/SFTP to connect to ${IPCON}.\nUser: root | Password: arc\nPress OK to continue!" 0 0
      # Grep PAT_FILE
      PAT_FILE=$(ls ${TMP_UP_PATH}/*.pat | head -n 1)
      if [ -f "${PAT_FILE}" ] && [ $(wc -c "${PAT_FILE}" | awk '{print $1}') -gt 300000000 ]; then
        dialog --backtitle "$(backtitle)" --title "DSM Upload" --aspect 18 \
          --infobox "DSM Image found!" 3 40
        # Remove PAT Data for Offline
        writeConfigKey "arc.paturl" "#" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.pathash" "#" "${USER_CONFIG_FILE}"
        # Extract Files
        if [ -f "${PAT_FILE}" ]; then
          extractDSMFiles "${PAT_FILE}" "${UNTAR_PAT_PATH}"
          VALID="true"
        else
          dialog --backtitle "$(backtitle)" --title "DSM Extraction" --aspect 18 \
            --infobox "DSM Extraction failed!\nExit." 4 40
          VALID="false"
          sleep 5
        fi
      elif [ ! -f "${PAT_FILE}" ]; then
        dialog --backtitle "$(backtitle)" --title "DSM Extraction" --aspect 18 \
          --infobox "No DSM Image found!\nExit." 4 40
        VALID="false"
        sleep 5
      else
        dialog --backtitle "$(backtitle)" --title "DSM Upload" --aspect 18 \
          --infobox "Incorrect DSM Image (.pat) found!\nExit." 4 40
        VALID="false"
        sleep 5
      fi
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Arc Build" --aspect 18 \
      --infobox "Can't build Custom Loader while Offline!\nExit." 4 40
    VALID="false"
    sleep 5
  fi
  # Copy DSM Files to Locations if DSM Files not found
  if [ "${VALID}" == "true" ]; then
    if [ ! -f "${ORI_ZIMAGE_FILE}" ] || [ ! -f "${ORI_RDGZ_FILE}" ]; then
      if copyDSMFiles "${UNTAR_PAT_PATH}" 2>/dev/null; then
        VALID="true"
      else
        VALID="false"
      fi
    fi
  fi
  if [ -f "${ORI_ZIMAGE_FILE}" ] && [ -f "${ORI_RDGZ_FILE}" ] && [ "${VALID}" == "true" ]; then
    (
      livepatch
      sleep 3
    ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Build Loader" \
      --progressbox "Doing the Magic..." 20 70
  fi
  if [ -f "${ORI_ZIMAGE_FILE}" ] && [ -f "${ORI_RDGZ_FILE}" ] && [ -f "${MOD_ZIMAGE_FILE}" ] && [ -f "${MOD_RDGZ_FILE}" ]; then
    writeConfigKey "arc.builddone" "true" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    arcFinish
  else
    dialog --backtitle "$(backtitle)" --title "Build Loader" --aspect 18 \
      --infobox "Could not build Loader!\nExit." 4 40
    # Set Build to false
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    sleep 5
    return 1
  fi
}

###############################################################################
# Finish Building Loader
function arcFinish() {
  # Verify Files exist
  AUTOMATED="$(readConfigKey "arc.automated" "${USER_CONFIG_FILE}")"
  rm -f "${LOG_FILE}" >/dev/null
  # Check for Automated Mode
  if grep -q "automated_arc" /proc/cmdline; then
    boot
  elif [ "${AUTOMATED}" == "true" ]; then
    [ ! -f "${PART3_PATH}/automated" ] && echo "${ARC_VERSION}-${MODEL}-${PRODUCTVER}-custom" >"${PART3_PATH}/automated"
    boot
  elif [ "${AUTOMATED}" == "false" ]; then
    [ -f "${PART3_PATH}/automated" ] && rm -f "${PART3_PATH}/automated" >/dev/null
    # Ask for Boot
    dialog --clear --backtitle "$(backtitle)" --title "Build done"\
      --no-cancel --menu "Boot now?" 7 40 0 \
      1 "Yes - Boot Arc Loader now" \
      2 "No - I want to make changes" \
    2>"${TMP_PATH}/resp"
    resp=$(cat ${TMP_PATH}/resp)
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      boot
    elif [ ${resp} -eq 2 ]; then
      return 0
    fi
  fi
}

###############################################################################
# Calls boot.sh to boot into DSM Reinstall Mode
function juniorboot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  [ "${BUILDDONE}" == "false" ] && dialog --backtitle "$(backtitle)" --title "Alert" \
    --yesno "Config changed, please build Loader first." 0 0
  if [ $? -eq 0 ]; then
    make
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Booting DSM Reinstall Mode...\nPlease stay patient!" 4 30
  sleep 2
  rebootTo "junior"
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  [ "${BUILDDONE}" == "false" ] && dialog --backtitle "$(backtitle)" --title "Alert" \
    --yesno "Config changed, you need to rebuild the Loader?" 0 0
  if [ $? -eq 0 ]; then
    arcSummary
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Booting DSM...\nPlease stay patient!" 4 25
  sleep 2
  bootDSM
}

###############################################################################
###############################################################################
# Main loop
# Check for Automated Mode
if grep -q "automated_arc" /proc/cmdline; then
  # Check for Custom Build
  if [ "${AUTOMATED}" == "true" ]; then
    arcModel
  else
    make
  fi
else
  [ "${BUILDDONE}" == "true" ] && NEXT="3" || NEXT="1"
  while true; do
    echo "= \"\Z4========== Main ==========\Zn \" "                                            >"${TMP_PATH}/menu"
    if [ "${ARCPATCH}" == "true" ] && [ -z "ARC_KEY" ]; then
      echo "0 \"Decrypt Arc Patch \" "                                                        >>"${TMP_PATH}/menu"
    else
      if [ -z "${ARC_KEY}" ]; then
        echo "0 \"Decrypt Arc Patch \" "                                                      >>"${TMP_PATH}/menu"
      fi
      echo "1 \"Choose Model \" "                                                             >>"${TMP_PATH}/menu"
      if [ "${CONFDONE}" == "true" ]; then
        echo "2 \"Build Loader \" "                                                           >>"${TMP_PATH}/menu"
      fi
      if [ "${BUILDDONE}" == "true" ]; then
        echo "3 \"Boot Loader \" "                                                            >>"${TMP_PATH}/menu"
      fi
    fi
    echo "= \"\Z4========== Info ==========\Zn \" "                                           >>"${TMP_PATH}/menu"
    echo "a \"Sysinfo \" "                                                                    >>"${TMP_PATH}/menu"
    echo "A \"Networkdiag \" "                                                                >>"${TMP_PATH}/menu"
    echo "= \"\Z4========== System ========\Zn \" "                                           >>"${TMP_PATH}/menu"
    if [ "${CONFDONE}" == "true" ]; then
      if [ "${ARCOPTS}" == "true" ]; then
        echo "4 \"\Z1Hide Arc DSM Options\Zn \" "                                             >>"${TMP_PATH}/menu"
      else
        echo "4 \"\Z1Show Arc DSM Options\Zn \" "                                             >>"${TMP_PATH}/menu"
      fi
      if [ "${ARCOPTS}" == "true" ]; then
        echo "= \"\Z4======== Arc DSM ========\Zn \" "                                        >>"${TMP_PATH}/menu"
        echo "b \"Addons \" "                                                                 >>"${TMP_PATH}/menu"
        echo "d \"Modules \" "                                                                >>"${TMP_PATH}/menu"
        echo "e \"Version \" "                                                                >>"${TMP_PATH}/menu"
        if [ "${CPUFREQ}" == "true" ]; then
          echo "g \"Frequency Scaling \" "                                                    >>"${TMP_PATH}/menu"
        fi
        if [ "${DT}" == "false" ] && [ ${SATACONTROLLER} -gt 0 ]; then
          echo "S \"Sata PortMap \" "                                                         >>"${TMP_PATH}/menu"
        fi
        if [ "${DT}" == "true" ]; then
          echo "o \"DTS Map Options \" "                                                      >>"${TMP_PATH}/menu"
        fi
        echo "P \"StoragePanel Options \" "                                                   >>"${TMP_PATH}/menu"
        echo "Q \"SequentialIO Options \" "                                                   >>"${TMP_PATH}/menu"
        echo "p \"Patch Options (SN/Mac) \" "                                                 >>"${TMP_PATH}/menu"
      fi
      if [ "${BOOTOPTS}" == "true" ]; then
        echo "6 \"\Z1Hide Boot Options\Zn \" "                                                >>"${TMP_PATH}/menu"
      else
        echo "6 \"\Z1Show Boot Options\Zn \" "                                                >>"${TMP_PATH}/menu"
      fi
      if [ "${BOOTOPTS}" == "true" ]; then
        echo "= \"\Z4========== Boot =========\Zn \" "                                        >>"${TMP_PATH}/menu"
        echo "m \"DSM Kernelload: \Z4${KERNELLOAD}\Zn \" "                                    >>"${TMP_PATH}/menu"
        echo "E \"eMMC Boot Support: \Z4${EMMCBOOT}\Zn \" "                                   >>"${TMP_PATH}/menu"
        if [ "${DIRECTBOOT}" == "false" ]; then
          echo "i \"Boot IP Waittime: \Z4${BOOTIPWAIT}\Zn \" "                                >>"${TMP_PATH}/menu"
        fi
        echo "q \"Directboot: \Z4${DIRECTBOOT}\Zn \" "                                        >>"${TMP_PATH}/menu"
      fi
      if [ "${DSMOPTS}" == "true" ]; then
        echo "7 \"\Z1Hide DSM Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
      else
        echo "7 \"\Z1Show DSM Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
      fi
      if [ "${DSMOPTS}" == "true" ]; then
        echo "= \"\Z4========== DSM ==========\Zn \" "                                        >>"${TMP_PATH}/menu"
        echo "j \"Cmdline \" "                                                                >>"${TMP_PATH}/menu"
        echo "k \"Synoinfo \" "                                                               >>"${TMP_PATH}/menu"
        echo "l \"Edit Config \" "                                                            >>"${TMP_PATH}/menu"
        echo "s \"Allow Downgrade \" "                                                        >>"${TMP_PATH}/menu"
        echo "t \"Change User Password \" "                                                   >>"${TMP_PATH}/menu"
        echo "N \"Add new User\" "                                                            >>"${TMP_PATH}/menu"
        echo "D \"StaticIP \" "                                                               >>"${TMP_PATH}/menu"
        echo "J \"Reset DSM Network Config \" "                                               >>"${TMP_PATH}/menu"
        if [ "${PLATFORM}" == "epyc7002" ]; then
          echo "K \"Kernel: \Z4${KERNEL}\Zn \" "                                              >>"${TMP_PATH}/menu"
        fi
        if [ "${DT}" == "true" ]; then
          echo "H \"Hotplug/SortDrives: \Z4${HDDSORT}\Zn \" "                                 >>"${TMP_PATH}/menu"
        fi
        echo "O \"Official Driver Priority: \Z4${ODP}\Zn \" "                                 >>"${TMP_PATH}/menu"
        echo "T \"Force enable SSH in DSM \" "                                                >>"${TMP_PATH}/menu"
      fi
    fi
    if [ "${DEVOPTS}" == "true" ]; then
      echo "8 \"\Z1Hide Loader Options\Zn \" "                                                >>"${TMP_PATH}/menu"
    else
      echo "8 \"\Z1Show Loader Options\Zn \" "                                                >>"${TMP_PATH}/menu"
    fi
    if [ "${DEVOPTS}" == "true" ]; then
      echo "= \"\Z4========= Loader =========\Zn \" "                                         >>"${TMP_PATH}/menu"
      echo "= \"\Z4=== Edit with caution! ===\Zn \" "                                         >>"${TMP_PATH}/menu"
      echo "R \"Automated Mode: \Z4${AUTOMATED}\Zn \" "                                          >>"${TMP_PATH}/menu"
      echo "W \"RD Compression: \Z4${RD_COMPRESSED}\Zn \" "                                   >>"${TMP_PATH}/menu"
      echo "X \"Sata DOM: \Z4${SATADOM}\Zn \" "                                               >>"${TMP_PATH}/menu"
      echo "u \"Switch LKM version: \Z4${LKM}\Zn \" "                                         >>"${TMP_PATH}/menu"
      echo "B \"Grep DSM Config from Backup \" "                                              >>"${TMP_PATH}/menu"
      echo "L \"Grep Logs from dbgutils \" "                                                  >>"${TMP_PATH}/menu"
      echo "w \"Reset Loader to Defaults \" "                                                 >>"${TMP_PATH}/menu"
      echo "C \"Clone Loader to Disk \" "                                                     >>"${TMP_PATH}/menu"
      echo "F \"\Z1Formate Disks \Zn \" "                                                     >>"${TMP_PATH}/menu"
      echo "n \"Grub Bootloader Config \" "                                                   >>"${TMP_PATH}/menu"
      echo "v \"Write Loader Modifications to Disk \" "                                       >>"${TMP_PATH}/menu"
      if [ "${OFFLINE}" == "false" ]; then
        echo "G \"Install opkg Package Manager \" "                                           >>"${TMP_PATH}/menu"
      fi
    fi
    echo "= \"\Z4========== Misc ==========\Zn \" "                                           >>"${TMP_PATH}/menu"
    echo "x \"Backup/Restore/Recovery \" "                                                    >>"${TMP_PATH}/menu"
    echo "M \"Primary NIC: \Z4${ARCNIC}\Zn \" "                                               >>"${TMP_PATH}/menu"
    echo "9 \"Offline Mode: \Z4${OFFLINE}\Zn \" "                                             >>"${TMP_PATH}/menu"
    echo "y \"Choose a Keymap \" "                                                            >>"${TMP_PATH}/menu"
    if [ "${OFFLINE}" == "false" ]; then
      echo "z \"Update Loader \" "                                                            >>"${TMP_PATH}/menu"
    fi
    echo "I \"Restart/Shutdown \" "                                                           >>"${TMP_PATH}/menu"
    echo "V \"Credits \" "                                                                    >>"${TMP_PATH}/menu"

    dialog --clear --default-item ${NEXT} --backtitle "$(backtitle)" --colors \
      --cancel-label "Exit" --title "Arc Menu" --menu "" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
      # Main Section
      0) decryptMenu; NEXT="0" ;;
      1) arcModel; NEXT="2" ;;
      2) make; NEXT="3" ;;
      3) boot; NEXT="3" ;;
      # Info Section
      a) sysinfo; NEXT="a" ;;
      A) networkdiag; NEXT="A" ;;
      # System Section
      # Arc Section
      4) [ "${ARCOPTS}" == "true" ] && ARCOPTS='false' || ARCOPTS='true'
        ARCOPTS="${ARCOPTS}"
        NEXT="4"
        ;;
      b) addonMenu; NEXT="b" ;;
      d) modulesMenu; NEXT="d" ;;
      g) governorMenu; NEXT="g" ;;
      e) ONLYVERSION="true" && arcVersion; NEXT="e" ;;
      S) storageMenu; NEXT="S" ;;
      o) dtsMenu; NEXT="o" ;;
      P) storagepanelMenu; NEXT="P" ;;
      Q) sequentialIOMenu; NEXT="Q" ;;
      p) ONLYPATCH="true" && arcPatch; NEXT="p" ;;
      D) staticIPMenu; NEXT="D" ;;
      R) [ "${AUTOMATED}" == "false" ] && AUTOMATED='true' || AUTOMATED='false'
        writeConfigKey "arc.custom" "${AUTOMATED}" "${USER_CONFIG_FILE}"
        if [ "${AUTOMATED}" == "true" ]; then
          [ ! -f "${PART3_PATH}/automated" ] && echo "${ARC_VERSION}-${MODEL}-${PRODUCTVER}-custom" >"${PART3_PATH}/automated"
        elif [ "${AUTOMATED}" == "false" ]; then
          [ -f "${PART3_PATH}/automated" ] && rm -f "${PART3_PATH}/automated" >/dev/null
        fi
        NEXT="R"
        ;;
      # Boot Section
      6) [ "${BOOTOPTS}" == "true" ] && BOOTOPTS='false' || BOOTOPTS='true'
        BOOTOPTS="${BOOTOPTS}"
        NEXT="6"
        ;;
      m) [ "${KERNELLOAD}" == "kexec" ] && KERNELLOAD='power' || KERNELLOAD='kexec'
        writeConfigKey "arc.kernelload" "${KERNELLOAD}" "${USER_CONFIG_FILE}"
        NEXT="m"
        ;;
      i) bootipwaittime; NEXT="i" ;;
      q) [ "${DIRECTBOOT}" == "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
        grub-editenv ${USER_GRUBENVFILE} create
        writeConfigKey "arc.directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
        NEXT="q"
        ;;
      # DSM Section
      7) [ "${DSMOPTS}" == "true" ] && DSMOPTS='false' || DSMOPTS='true'
        DSMOPTS="${DSMOPTS}"
        NEXT="7"
        ;;
      j) cmdlineMenu; NEXT="j" ;;
      k) synoinfoMenu; NEXT="k" ;;
      s) downgradeMenu; NEXT="s" ;;
      t) resetPassword; NEXT="t" ;;
      N) addNewDSMUser; NEXT="N" ;;
      J) resetDSMNetwork; NEXT="J" ;;
      K) [ "${KERNEL}" == "official" ] && KERNEL='custom' || KERNEL='official'
        writeConfigKey "arc.kernel" "${KERNEL}" "${USER_CONFIG_FILE}"
        if [ "${ODP}" == "true" ]; then
          ODP="false"
          writeConfigKey "arc.odp" "${ODP}" "${USER_CONFIG_FILE}"
        fi
        PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
        PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
        KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
        if [ -n "${PLATFORM}" ] && [ -n "${KVER}" ]; then
          if [ "${PLATFORM}" == "epyc7002" ]; then
            KVERP="${PRODUCTVER}-${KVER}"
          else
            KVERP="${KVER}"
          fi
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          while read -r ID DESC; do
            writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
          done < <(getAllModules "${PLATFORM}" "${KVERP}")
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="K"
        ;;
      H) [ "${HDDSORT}" == "true" ] && HDDSORT='false' || HDDSORT='true'
        writeConfigKey "arc.hddsort" "${HDDSORT}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="H"
        ;;
      O) [ "${ODP}" == "false" ] && ODP='true' || ODP='false'
        writeConfigKey "arc.odp" "${ODP}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="O"
        ;;
      E) [ "${EMMCBOOT}" == "true" ] && EMMCBOOT='false' || EMMCBOOT='true'
        if [ "${EMMCBOOT}" == "false" ]; then
          writeConfigKey "arc.emmcboot" "false" "${USER_CONFIG_FILE}"
          deleteConfigKey "synoinfo.disk_swap" "${USER_CONFIG_FILE}"
          deleteConfigKey "synoinfo.supportraid" "${USER_CONFIG_FILE}"
          deleteConfigKey "synoinfo.support_emmc_boot" "${USER_CONFIG_FILE}"
          deleteConfigKey "synoinfo.support_install_only_dev" "${USER_CONFIG_FILE}"
        elif [ "${EMMCBOOT}" == "true" ]; then
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
      W) [ "${RD_COMPRESSED}" == "true" ] && RD_COMPRESSED='false' || RD_COMPRESSED='true'
        writeConfigKey "rd-compressed" "${RD_COMPRESSED}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="W"
        ;;
      X) satadomMenu; NEXT="X" ;;
      u) [ "${LKM}" == "prod" ] && LKM='dev' || LKM='prod'
        writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="u"
        ;;
      # Loader Section
      8) [ "${DEVOPTS}" == "true" ] && DEVOPTS='false' || DEVOPTS='true'
        DEVOPTS="${DEVOPTS}"
        NEXT="8"
        ;;
      l) editUserConfig; NEXT="l" ;;
      w) resetLoader; NEXT="w" ;;
      v) saveMenu; NEXT="v" ;;
      n) editGrubCfg; NEXT="n" ;;
      B) getbackup; NEXT="B" ;;
      L) greplogs; NEXT="L" ;;
      T) forcessh; NEXT="T" ;;
      C) cloneLoader; NEXT="C" ;;
      F) formatDisks; NEXT="F" ;;
      G) package; NEXT="G" ;;
      # Misc Settings
      x) backupMenu; NEXT="x" ;;
      M) arcNIC; NEXT="M" ;;
      9) [ "${OFFLINE}" == "true" ] && OFFLINE='false' || OFFLINE='true'
        [ "${OFFLINE}" == "false" ] && offlineCheck
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="9"
        ;;
      y) keymapMenu; NEXT="y" ;;
      z) updateMenu; NEXT="z" ;;
      I) rebootMenu; NEXT="I" ;;
      V) credits; NEXT="V" ;;
    esac
  done
  clear
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
