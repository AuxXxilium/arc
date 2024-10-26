#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/modules.sh
. ${ARC_PATH}/include/update.sh
. ${ARC_PATH}/include/storage.sh
. ${ARC_PATH}/include/network.sh
. ${ARC_PATH}/include/compat.sh
. ${ARC_PATH}/arc-functions.sh

# Get Keymap and Timezone Config
ntpCheck
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
# Check for System
systemCheck
ARCMODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"

# Get DSM Data from Config
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
if [ -n "${MODEL}" ]; then
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
fi

# Get Arc Data from Config
ARCKEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
ARCCONF="$(readConfigKey "${MODEL:-SA6400}.serial" "${S_FILE}")"
BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
USBMOUNT="$(readConfigKey "usbmount" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "kernelpanic" "${USER_CONFIG_FILE}")"
ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
RD_COMPRESSED="$(readConfigKey "rd-compressed" "${USER_CONFIG_FILE}")"
SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
SATACONTROLLER="$(readConfigKey "device.satacontroller" "${USER_CONFIG_FILE}")"
SCSICONTROLLER="$(readConfigKey "device.scsicontroller" "${USER_CONFIG_FILE}")"
RAIDCONTROLLER="$(readConfigKey "device.raidcontroller" "${USER_CONFIG_FILE}")"
SASCONTROLLER="$(readConfigKey "device.sascontroller" "${USER_CONFIG_FILE}")"

# Get Config/Build Status
ARC_BRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
ARCOFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${ARC_TITLE}$([ -n "${NEWTAG}" ] && [[ "$(echo ${ARC_VERSION} | tr -d '.')" -lt "$(echo ${NEWTAG} | tr -d '.')" ]] && echo " > ${NEWTAG}") | "
  BACKTITLE+="${MODEL:-(Model)} | "
  BACKTITLE+="${PRODUCTVER:-(Version)} | "
  BACKTITLE+="${IPCON:-(IP)} | "
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
  if [ ! -f "${S_FILE}" ]; then
    updateConfigs
  fi
  # Loop menu
  RESTRICT=1
  PS="$(readConfigEntriesArray "platforms" "${P_FILE}" | sort)"
  [[ "${ARCMODE}" == "automated" || "${ARCOFFLINE}" == "true" ]] && MJ="$(python ${ARC_PATH}/include/functions.py getmodelsoffline -p "${PS[*]}")" || MJ="$(python ${ARC_PATH}/include/functions.py getmodels -p "${PS[*]}")"
  if [[ -z "${MJ}" || "${MJ}" == "[]" ]]; then
    dialog --backtitle "$(backtitle)" --title "Model" --title "Model" \
      --msgbox "Failed to get models, please try again!" 3 50
    return 1
  fi
  echo -n "" >"${TMP_PATH}/modellist"
  echo "${MJ}" | jq -c '.[]' | while read -r item; do
    name=$(echo "${item}" | jq -r '.name')
    arch=$(echo "${item}" | jq -r '.arch')
    echo "${name} ${arch}" >>"${TMP_PATH}/modellist"
  done
  if [ "${ARCMODE}" == "config" ]; then
    while true; do
      echo -n "" >"${TMP_PATH}/menu"
      while read -r M A; do
        COMPATIBLE=1
        DT="$(readConfigKey "platforms.${A}.dt" "${P_FILE}")"
        FLAGS="$(readConfigArray "platforms.${A}.flags" "${P_FILE}")"
        ARCCONFM="$(readConfigKey "${M}.serial" "${S_FILE}")"
        ARC=""
        BETA=""
        [ -n "${ARCCONFM}" ] && ARC="x" || ARC=""
        [ "${DT}" == "true" ] && DTS="x" || DTS=""
        IGPUS=""
        [[ "${A}" == "apollolake" || "${A}" == "geminilake" ]] && IGPUS="up to 9th"
        [ "${A}" == "epyc7002" ] && IGPUS="up to 14th" 
        [ "${DT}" == "true" ] && HBAS="" || HBAS="x"
        [ "${M}" == "SA6400" ] && HBAS="x"
        [ "${DT}" == "false" ] && USBS="int/ext" || USBS="ext"
        [[ "${M}" == "DS918+" || "${M}" == "DS1019+" || "${M}" == "DS1621xs+" || "${M}" == "RS1619xs+" ]] && M_2_CACHE="+" || M_2_CACHE="x"
        [[ "${M}" == "DS220+" ||  "${M}" == "DS224+" ]] && M_2_CACHE=""
        [[ "${M}" == "DS220+" || "${M}" == "DS224+" || "${M}" == "DS918+" || "${M}" == "DS1019+" || "${M}" == "DS1621xs+" || "${M}" == "RS1619xs+" ]] && M_2_STORAGE="" || M_2_STORAGE="+"
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
          if [ "${A}" == "epyc7002" ] && [[ ${SCSICONTROLLER} -ne 0 || ${RAIDCONTROLLER} -ne 0 ]]; then
            COMPATIBLE=0
          fi
          if [ "${A}" != "epyc7002" ] && [ ${NVMEDRIVES} -gt 0 ] && [ "${BUS}" == "usb" ] && [ ${SATADRIVES} -eq 0 ] && [ "${EXTERNALCONTROLLER}" == "false" ]; then
            COMPATIBLE=0
          elif [ "${A}" != "epyc7002" ] && [ ${NVMEDRIVES} -gt 0 ] && [ "${BUS}" == "sata" ] && [ ${SATADRIVES} -eq 1 ] && [ "${EXTERNALCONTROLLER}" == "false" ]; then
            COMPATIBLE=0
          fi
          [ -z "$(grep -w "${M}" "${S_FILE}")" ] && COMPATIBLE=0
        fi
        [ -n "$(grep -w "${M}" "${S_FILE}")" ] && BETA="Arc" || BETA="Syno"
        [ -z "$(grep -w "${A}" "${P_FILE}")" ] && COMPATIBLE=0
        if [ -n "${ARCKEY}" ]; then
          [ ${COMPATIBLE} -eq 1 ] && echo -e "${M} \"\t$(printf "\Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-12s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "${A}" "${DTS}" "${ARC}" "${IGPUS}" "${HBAS}" "${M_2_CACHE}" "${M_2_STORAGE}" "${USBS}" "${BETA}")\" ">>"${TMP_PATH}/menu"
        else
          [ ${COMPATIBLE} -eq 1 ] && echo -e "${M} \"\t$(printf "\Zb%-15s\Zn \Zb%-5s\Zn \Zb%-12s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "${A}" "${DTS}" "${IGPUS}" "${HBAS}" "${M_2_CACHE}" "${M_2_STORAGE}" "${USBS}" "${BETA}")\" ">>"${TMP_PATH}/menu"
        fi
      done < <(cat "${TMP_PATH}/modellist")
      if [ -n "${ARCKEY}" ]; then
        dialog --backtitle "$(backtitle)" --title "Arc DSM Model" --colors \
          --cancel-label "Show all" --help-button --help-label "Exit" \
          --extra-button --extra-label "Info" \
          --menu "Supported Models for your Hardware (x = supported / + = need Addons)\n$(printf "\Zb%-16s\Zn \Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-12s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "Model" "Platform" "DT" "Arc" "Intel iGPU" "HBA" "M.2 Cache" "M.2 Volume" "USB Mount" "Source")" 0 115 0 \
          --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
      else
        dialog --backtitle "$(backtitle)" --title "DSM Model" --colors \
          --cancel-label "Show all" --help-button --help-label "Exit" \
          --extra-button --extra-label "Info" \
          --menu "Supported Models for your Hardware (x = supported / + = need Addons) | Syno Models can have faulty Values.\n$(printf "\Zb%-16s\Zn \Zb%-15s\Zn \Zb%-5s\Zn \Zb%-12s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "Model" "Platform" "DT" "Intel iGPU" "HBA" "M.2 Cache" "M.2 Volume" "USB Mount" "Source")" 0 115 0 \
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
            --title "Platform Info" --textbox "./informations/${PLATFORM}.yml" 70 80
          ;;
        255) # ESC -> Exit
          return 1
          break
          ;;
      esac
    done
  fi
  # Reset Model Config if changed
  if [ "${ARCMODE}" == "config" ] && [ "${MODEL}" != "${resp}" ]; then
    MODEL="${resp}"
    writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
    writeConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "emmcboot" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "hddsort" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "kernel" "official" "${USER_CONFIG_FILE}"
    writeConfigKey "odp" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    writeConfigKey "paturl" "" "${USER_CONFIG_FILE}"
    writeConfigKey "pathash" "" "${USER_CONFIG_FILE}"
    writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"
    writeConfigKey "productver" "" "${USER_CONFIG_FILE}"
    writeConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
    writeConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
    writeConfigKey "sn" "" "${USER_CONFIG_FILE}"
    writeConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
  fi
  PLATFORM="$(grep -w "${MODEL}" "${TMP_PATH}/modellist" | awk '{print $2}' | head -1)"
  writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
  # Read Platform Data
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  arcVersion
}

###############################################################################
# Arc Version Section
function arcVersion() {
  # Read Model Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  # Get PAT Data from Config
  PAT_URL_CONF="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH_CONF="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  # Check for Custom Build
  if [ "${ARCMODE}" == "config" ] && [ "${ARCRESTORE}" != "true" ]; then
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
      # Reset Config if changed
      writeConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
      writeConfigKey "paturl" "" "${USER_CONFIG_FILE}"
      writeConfigKey "pathash" "" "${USER_CONFIG_FILE}"
      writeConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
      writeConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
      writeConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
    fi
    dialog --backtitle "$(backtitle)" --title "DSM Version" \
    --infobox "Reading DSM Build..." 3 25
    PAT_URL=""
    PAT_HASH=""
    URLVER=""
    while true; do
      PJ="$(python ${ARC_PATH}/include/functions.py getpats4mv -m "${MODEL}" -v "${PRODUCTVER}")"
      if [[ -z "${PJ}" || "${PJ}" == "{}" ]]; then
        MSG="Unable to connect to Synology API, Please check the network and try again!"
        dialog --backtitle "$(backtitle)" --colors --title "DSM Version" \
          --yes-label "Retry" \
          --yesno "${MSG}" 0 0
        [ $? -eq 0 ] && continue # yes-button
        return 1
      else
        PVS="$(echo "${PJ}" | jq -r 'keys | sort | reverse | join("\n")')"
        [ -f "${TMP_PATH}/versions" ] && rm -f "${TMP_PATH}/versions" >/dev/null 2>&1 && touch "${TMP_PATH}/versions"
        while IFS= read -r line; do
          VERSION="${line}"
          CHECK_URL=$(echo "${PJ}" | jq -r ".\"${VERSION}\".url")
          if curl --head -skL -m 5 "${CHECK_URL}" | head -n 1 | grep -q "404\|403"; then
            continue
          else
            echo "${VERSION}" >>"${TMP_PATH}/versions"
          fi
        done < <(echo "${PVS}")
        DSMPVS="$(cat ${TMP_PATH}/versions)"
        dialog --backtitle "$(backtitle)" --colors --title "DSM Version" \
          --no-items --menu "Choose a DSM Build" 0 0 0 ${DSMPVS} \
        2>${TMP_PATH}/resp
        RET=$?
        [ ${RET} -ne 0 ] && return
        PV=$(cat ${TMP_PATH}/resp)
        PAT_URL=$(echo "${PJ}" | jq -r ".\"${PV}\".url")
        PAT_HASH=$(echo "${PJ}" | jq -r ".\"${PV}\".sum")
        URLVER="$(echo "${PV}" | cut -d'.' -f1,2)"
        [ "${PRODUCTVER}" != "${URLVER}" ] && PRODUCTVER="${URLVER}"
        writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
        [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ] && VALID="true" && break
      fi
    done
    if [ -z "${PAT_URL}" ] || [ -z "${PAT_HASH}" ]; then
      MSG="Failed to get PAT Data.\n"
      MSG+="Please manually fill in the URL and Hash of PAT.\n"
      MSG+="You will find these Data at: https://auxxxilium.tech/wiki/arc-loader-arc-loader/url-hash-liste"
      dialog --backtitle "$(backtitle)" --colors --title "Arc Build" --default-button "OK" \
        --form "${MSG}" 11 120 2 "Url" 1 1 "${PAT_URL}" 1 8 110 0 "Hash" 2 1 "${PAT_HASH}" 2 8 110 0 \
        2>"${TMP_PATH}/resp"
      RET=$?
      [ ${RET} -eq 0 ]             # ok-button
      return 1                     # 1 or 255  # cancel-button or ESC
      PAT_URL="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
      PAT_HASH="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
      [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ] && VALID="true"
    fi
    MSG="Do you want to try Automated Mode?\nIf yes, Loader will configure, build and boot DSM."
    dialog --backtitle "$(backtitle)" --colors --title "Automated Mode" \
      --yesno "${MSG}" 6 55
    if [ $? -eq 0 ]; then
      ARCMODE="automated"
    else
      ARCMODE="config"
    fi
    if [ "${ARCOFFLINE}" == "false" ]; then
      # Check PAT URL
      dialog --backtitle "$(backtitle)" --colors --title "DSM Version" \
        --infobox "Check PAT Data..." 3 40
      if curl --head -skL -m 10 "${PAT_URL}" | head -n 1 | grep -q 404; then
        VALID="false"
        writeConfigKey "paturl" "" "${USER_CONFIG_FILE}"
        writeConfigKey "pathash" "" "${USER_CONFIG_FILE}"
      else
        VALID="true"
        writeConfigKey "paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"
        writeConfigKey "pathash" "${PAT_HASH}" "${USER_CONFIG_FILE}"
      fi
    fi
  elif [ "${ARCMODE}" == "automated" ] || [ "${ARCRESTORE}" == "true" ]; then
    VALID="true"
  fi
  # Check PAT Hash
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  if [ "${PAT_HASH}" != "${PAT_HASH_CONF}" ] || [ "${PAT_URL}" != "${PAT_URL_CONF}" ]; then
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
    rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" "${PART2_PATH}/"* >/dev/null 2>&1 || true
    rm -f "${USER_UP_PATH}/"*.tar >/dev/null 2>&1 || true
  fi
  getpatfiles
  # Change Config if Files are valid
  if [ "${VALID}" == "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Config" \
      --infobox "Reconfiguring Addons, Cmdline, Modules and Synoinfo" 3 60
    # Reset Synoinfo
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
    while IFS=': ' read -r KEY VALUE; do
      writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
    done < <(readConfigMap "platforms.${PLATFORM}.synoinfo" "${P_FILE}")
    # Check Addons for Platform
    ADDONS="$(readConfigKey "addons" "${USER_CONFIG_FILE}")"
    DEVICENIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
    ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}")"
    if [ "${ADDONS}" == "{}" ]; then
      initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
      initConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
      initConfigKey "addons.storagepanel" "" "${USER_CONFIG_FILE}"
      initConfigKey "addons.updatenotify" "" "${USER_CONFIG_FILE}"
      if [ ${NVMEDRIVES} -gt 0 ]; then
        if [ "${PLATFORM}" == "epyc7002" ] && [ ${SATADRIVES} -eq 0 ] && [ ${SASDRIVES} -eq 0 ]; then
          initConfigKey "addons.nvmesystem" "" "${USER_CONFIG_FILE}"
        elif [ "${MODEL}" == "DS918+" ] || [ "${MODEL}" == "DS1019+" ] || [ "${MODEL}" == "DS1621xs+" ] || [ "${MODEL}" == "RS1619xs+" ]; then
          initConfigKey "addons.nvmecache" "" "${USER_CONFIG_FILE}"
        fi
        initConfigKey "addons.nvmevolume" "" "${USER_CONFIG_FILE}"
      fi
      if [ "${CPUFREQ}" == "true" ] && [ "${ACPISYS}" == "true" ]; then
        initConfigKey "addons.cpufreqscaling" "" "${USER_CONFIG_FILE}"
      fi
      if [ "${MACHINE}" == "Native" ]; then
        initConfigKey "addons.powersched" "" "${USER_CONFIG_FILE}"
        initConfigKey "addons.sensors" "" "${USER_CONFIG_FILE}"
      fi
      if [ "${PLATFORM}" == "apollolake" ] || [ "${PLATFORM}" == "geminilake" ]; then
        initConfigKey "addons.i915" "" "${USER_CONFIG_FILE}"
      fi
      if echo "${PAT_URL}" 2>/dev/null | grep -q "7.2.2"; then
        initConfigKey "addons.allowdowngrade" "" "${USER_CONFIG_FILE}"
      fi
      if [ -n "${ARCCONF}" ]; then
        initConfigKey "addons.arcdns" "" "${USER_CONFIG_FILE}"
      fi
    fi
    while IFS=': ' read -r ADDON PARAM; do
      [ -z "${ADDON}" ] && continue
      if ! checkAddonExist "${ADDON}" "${PLATFORM}"; then
        deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
      fi
    done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
    KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
    [ "${PLATFORM}" == "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
    if [ -n "${PLATFORM}" ] && [ -n "${KVERP}" ]; then
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read -r ID DESC; do
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
      done < <(getAllModules "${PLATFORM}" "${KVERP}")
    fi
    # Check for Only Version
    if [ "${ONLYVERSION}" == "true" ]; then
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      ONLYVERSION="false"
      return 0
    else
      arcPatch
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Arc Config" --aspect 18 \
      --infobox "Arc Config failed!\nExit." 4 40
    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
    sleep 5
    return 1
  fi
}

###############################################################################
# Arc Patch Section
function arcPatch() {
  # Read Model Values
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}")"
  # Check for Custom Build
  if [ "${ARCMODE}" == "automated" ]; then
    if [ -n "${ARCCONF}" ]; then
      SN=$(generateSerial "${MODEL}" "true")
      writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
    else
      SN=$(generateSerial "${MODEL}" "false")
      writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
    fi
  elif [ "${ARCMODE}" == "config" ]; then
    dialog --clear --backtitle "$(backtitle)" \
      --nocancel --title "SN/Mac Options"\
      --menu "Choose an Option." 7 60 0 \
      1 "Use Arc Patch (AME, QC, Push Notify and more)" \
      2 "Use random SN/Mac (Reduced DSM Features)" \
      3 "Use my own SN/Mac (Be sure your Data is valid)" \
    2>"${TMP_PATH}/resp"
    resp=$(cat ${TMP_PATH}/resp)
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      [ -z "${ARCCONF}" ] && decryptMenu || true
      if [ -n "${ARCCONF}" ]; then
        # Read Arc Patch from File
        SN="$(generateSerial "${MODEL}" "true")"
        writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
      else
        # Read Arc Patch from File
        SN="$(generateSerial "${MODEL}" "false")"
        writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
      fi
    elif [ ${resp} -eq 2 ]; then
      # Generate random Serial
      SN="$(generateSerial "${MODEL}" "false")"
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
        else
          break
        fi
      done
      writeConfigKey "arc.patch" "user" "${USER_CONFIG_FILE}"
    fi
  fi
  writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  arcSettings
}

###############################################################################
# Arc Settings Section
function arcSettings() {
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  # Get Network Config for Loader
  dialog --backtitle "$(backtitle)" --colors --title "Network Config" \
    --infobox "Generating Network Config..." 3 40
  sleep 2
  getnet
  [ $? -ne 0 ] && return 1
  if [ "${ONLYPATCH}" == "true" ]; then
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
    [ $? -ne 0 ] && return 1
  fi
  # Check for Custom Build
  if [ "${ARCMODE}" == "config" ]; then
    # Select Addons
    dialog --backtitle "$(backtitle)" --colors --title "DSM Addons" \
      --infobox "Loading Addons Table..." 3 40
    addonSelection
    [ $? -ne 0 ] && return 1
  fi
  # Check for CPU Frequency Scaling & Governor
  if [ "${ARCMODE}" == "config" ] && [ "${CPUFREQ}" == "true" ] && [ "${ACPISYS}" == "true" ] && readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "cpufreqscaling"; then
    dialog --backtitle "$(backtitle)" --colors --title "CPU Frequency Scaling" \
      --infobox "Generating Governor Table..." 3 40
    governorSelection
    [ $? -ne 0 ] && return 1
  elif [ "${ARCMODE}" == "automated" ] && [ "${CPUFREQ}" == "true" ] && [ "${ACPISYS}" == "true" ] && readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "cpufreqscaling"; then
    if [ "${PLATFORM}" == "epyc7002" ]; then
      writeConfigKey "addons.cpufreqscaling" "schedutil" "${USER_CONFIG_FILE}"
    else
      writeConfigKey "addons.cpufreqscaling" "conservative" "${USER_CONFIG_FILE}"
    fi
  else
    deleteConfigKey "addons.cpufreqscaling" "${USER_CONFIG_FILE}"
  fi
  if [ "${ARCMODE}" == "config" ]; then
    # Check for DT and HBA/Raid Controller
    if [ "${PLATFORM}" != "epyc7002" ]; then
      if [ "${DT}" == "true" ] && [ "${EXTERNALCONTROLLER}" == "true" ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Warning" \
          --msgbox "WARN: You use a HBA/Raid Controller and selected a DT Model.\nThis is still an experimental." 6 70
      fi
    fi
    # Check for more then 8 Ethernet Ports
    DEVICENIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
    MODELNIC="$(readConfigKey "${MODEL}.ports" "${S_FILE}" 2>/dev/null)"
    if [ ${DEVICENIC} -gt 8 ]; then
      dialog --backtitle "$(backtitle)" --title "Arc Warning" \
        --msgbox "WARN: You have more NIC (${DEVICENIC}) then 8 NIC.\nOnly 8 supported by DSM." 6 60
    fi
    if [ ${DEVICENIC} -gt ${MODELNIC} ] && [ "${ARCPATCH}" == "true" ]; then
      dialog --backtitle "$(backtitle)" --title "Arc Warning" \
        --msgbox "WARN: You have more NIC (${DEVICENIC}) than supported by Model (${MODELNIC}).\nOnly ${MODELNIC} are used by Arc Patch." 6 80
    fi
    # Check for AES
    if [ "${AESSYS}" == "false" ]; then
      dialog --backtitle "$(backtitle)" --title "Arc Warning" \
        --msgbox "WARN: Your System doesn't support Hardwareencryption in DSM. (AES)" 5 70
    fi
    # Check for CPUFREQ
    if [[ "${CPUFREQ}" == "false" || "${ACPISYS}" == "false" ]]; then
      dialog --backtitle "$(backtitle)" --title "Arc Warning" \
        --msgbox "WARN: Your System doesn't support CPU Frequency Scaling in DSM." 5 70
    fi
  fi
  EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
  # eMMC Boot Support
  if [ "${EMMCBOOT}" == "true" ]; then
    writeConfigKey "modules.mmc_block" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modules.mmc_core" "" "${USER_CONFIG_FILE}"
  else
    deleteConfigKey "modules.mmc_block" "${USER_CONFIG_FILE}"
    deleteConfigKey "modules.mmc_core" "${USER_CONFIG_FILE}"
  fi
  if [ -n "${PLATFORM}" ] && [ -n "${MODEL}" ] && [ -n "${KVER}" ] && [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ]; then
    # Config is done
    writeConfigKey "arc.confdone" "true" "${USER_CONFIG_FILE}"
    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
    # Check for Custom Build
    if [ "${ARCMODE}" == "config" ]; then
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
  else
    dialog --backtitle "$(backtitle)" --title "Config failed" \
      --msgbox "ERROR: Config failed!\nExit." 6 40
    return 1
  fi
}

###############################################################################
# Show Summary of Config
function arcSummary() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
  if [ "${REMAP}" == "acports" ] || [ "${REMAP}" == "maxports" ]; then
    PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
    DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
  elif [ "${REMAP}" == "remap" ]; then
    PORTREMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
  elif [ "${REMAP}" == "ahci" ]; then
    AHCIPORTREMAP="$(readConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}")"
  else
    PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
    DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
    PORTREMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
    AHCIPORTREMAP="$(readConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}")"
  fi
  DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
  NIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  HARDDRIVES="$(readConfigKey "device.harddrives" "${USER_CONFIG_FILE}")"
  DRIVES="$(readConfigKey "device.drives" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  if [ "${DT}" == "false" ] && [ "${REMAP}" == "user" ]; then
    if [ -z "${PORTMAP}" ] && [ -z "${DISKMAP}"] && [ -z "${PORTREMAP}" ] && [ -z "${AHCIPORTREMAP}" ]; then
      dialog --backtitle "$(backtitle)" --title "Arc Error" \
        --msgbox "ERROR: You selected Portmap: User and not set any values. -> Can't build Loader!\nGo need to go Cmdline Options and add your Values." 6 80
      return 1
    fi
  fi
  # Print Summary
  SUMMARY="\Z4> DSM Information\Zn"
  SUMMARY+="\n>> DSM Model: \Zb${MODEL}\Zn"
  SUMMARY+="\n>> DSM Version: \Zb${PRODUCTVER}\Zn"
  SUMMARY+="\n>> DSM Platform: \Zb${PLATFORM}\Zn"
  SUMMARY+="\n>> DSM DT: \Zb${DT}\Zn"
  SUMMARY+="\n>> DSM PAT URL: \Zb${PAT_URL}\Zn"
  SUMMARY+="\n>> DSM PAT Hash: \Zb${PAT_HASH}\Zn"
  SUMMARY+="\n>> DeviceTree: \Zb${DT}\Zn"
  [ "${MODEL}" == "SA6400" ] && SUMMARY+="\n>> Kernel: \Zb${KERNEL}\Zn"
  SUMMARY+="\n>> Kernel Version: \Zb${KVER}\Zn"
  SUMMARY+="\n"
  SUMMARY+="\n\Z4> Arc Information\Zn"
  SUMMARY+="\n>> Arc Patch: \Zb${ARCPATCH}\Zn"
  [ -n "${PORTMAP}" ] && SUMMARY+="\n>> SataPortmap: \Zb${PORTMAP}\Zn"
  [ -n "${DISKMAP}" ] && SUMMARY+="\n>> DiskIdxMap: \Zb${DISKMAP}\Zn"
  [ -n "${PORTREMAP}" ] && SUMMARY+="\n>> SataRemap: \Zb${PORTREMAP}\Zn"
  [ -n "${AHCIPORTREMAP}" ] && SUMMARY+="\n>> AhciRemap: \Zb${AHCIPORTREMAP}\Zn"
  [ "${DT}" == "true" ] && SUMMARY+="\n>> Sort Drives: \Zb${HDDSORT}\Zn"
  SUMMARY+="\n>> Directboot: \Zb${DIRECTBOOT}\Zn"
  SUMMARY+="\n>> eMMC Boot: \Zb${EMMCBOOT}\Zn"
  SUMMARY+="\n>> Kernelload: \Zb${KERNELLOAD}\Zn"
  SUMMARY+="\n>> Addons: \Zb${ADDONSINFO}\Zn"
  SUMMARY+="\n"
  SUMMARY+="\n\Z4> Device Information\Zn"
  SUMMARY+="\n>> AES: \Zb${AESSYS}\Zn"
  SUMMARY+="\n>> CPU FreqScaling | ACPI: \Zb${CPUFREQ} | ${ACPISYS}\Zn"
  SUMMARY+="\n>> NIC: \Zb${NIC}\Zn"
  SUMMARY+="\n>> Total Disks: \Zb${DRIVES}\Zn"
  SUMMARY+="\n>> Internal Disks: \Zb${HARDDRIVES}\Zn"
  SUMMARY+="\n>> Additional Controller: \Zb${EXTERNALCONTROLLER}\Zn"
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
  ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}" 2>/dev/null)"
  SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
  BOOTMODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"
  if [ "${BOOTMODE}" != "automated" ] && [[ "${ARCPATCH}" != "true" || -z "${ARCCONF}" ]]; then
    if ! curl -skL "https://auxxxilium.tech/check.yml" -o "${TMP_PATH}/check.yml" 2>/dev/null; then
      SN=$(generateSerial "${MODEL}" "false")
    else
      if grep -q "${SN}" "${TMP_PATH}/check.yml"; then
        SN=$(generateSerial "${MODEL}" "false")
      fi
    fi
    writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
  fi
  # Read Model Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  # Check for Arc Patch
  ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}")"
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  if [ -n "${ARCCONF}" ] && [ "${ARCPATCH}" == "true" ]; then
    if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "sspatch"; then
      writeConfigKey "addons.sspatch" "true" "${USER_CONFIG_FILE}"
    fi
  elif [ -z "${ARCCONF}" ] || [ "${ARCPATCH}" == "false" ]; then
    deleteConfigKey "addons.amepatch" "${USER_CONFIG_FILE}"
    deleteConfigKey "addons.arcdns" "${USER_CONFIG_FILE}"
    if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "sspatch"; then
      writeConfigKey "addons.sspatch" "false" "${USER_CONFIG_FILE}"
    fi
  fi
  # Max Memory for DSM
  RAMCONFIG="$((${RAMTOTAL} * 1024 * 2))"
  writeConfigKey "synoinfo.mem_max_mb" "${RAMCONFIG}" "${USER_CONFIG_FILE}"
  getpatfiles    
  if [ -f "${ORI_ZIMAGE_FILE}" ] && [ -f "${ORI_RDGZ_FILE}" ] && [ "${CONFDONE}" == "true" ] && [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ]; then
    (
      livepatch
      sleep 3
    ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Build Loader" \
      --progressbox "Welcome at the Dark Side..." 20 70
  else
    dialog --backtitle "$(backtitle)" --title "Build Loader" --aspect 18 \
      --infobox "Configuration issue found.\nCould not build Loader!\nExit." 5 40
    # Set Build to false
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    sleep 5
    return 1
  fi
  if [ -f "${ORI_ZIMAGE_FILE}" ] && [ -f "${ORI_RDGZ_FILE}" ] && [ -f "${MOD_ZIMAGE_FILE}" ] && [ -f "${MOD_RDGZ_FILE}" ]; then
    MODELID=$(echo ${MODEL} | sed 's/d$/D/; s/rp$/RP/; s/rp+/RP+/')
    writeConfigKey "modelid" "${MODELID}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
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
  rm -f "${LOG_FILE}" >/dev/null 2>&1 || true
  MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
  if [ -n "${MODELID}" ]; then
    writeConfigKey "arc.builddone" "true" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    if [ "${ARCMODE}" == "automated" ] || [ "${UPDATEMODE}" == "true" ]; then
      boot
    else
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
  fi
}

###############################################################################
# Calls boot.sh to boot into DSM Reinstall Mode
function juniorboot() {
  if [ "${BUILDDONE}" == "false" ] && [ "${ARCMODE}" != "automated" ]; then
    dialog --backtitle "$(backtitle)" --title "Alert" \
      --yesno "Config changed, you need to rebuild the Loader?" 0 0
    if [ $? -eq 0 ]; then
      arcSummary
    fi
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Booting DSM Reinstall Mode...\nPlease stay patient!" 4 30
  sleep 3
  rebootTo junior
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${BUILDDONE}" == "false" ] && [ "${ARCMODE}" != "automated" ]; then
    dialog --backtitle "$(backtitle)" --title "Alert" \
      --yesno "Config changed, you need to rebuild the Loader?" 0 0
    if [ $? -eq 0 ]; then
      arcSummary
    fi
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Booting DSM...\nPlease stay patient!" 4 25
  sleep 2
  clear 
  exec boot.sh
}

###############################################################################
###############################################################################
# Main loop
# Check for Arc Mode
if [ "${ARCMODE}" == "update" ]; then
  UPDATEMODE="true"
  arcUpdate
elif [ "${ARCMODE}" == "automated" ]; then
  # Check for Custom Build
  if [ "${BUILDDONE}" == "false" ] || [ "${MODEL}" != "${MODELID}" ]; then
    arcModel
  else
    make
  fi
else
  if [ "${BUILDDONE}" == "true" ]; then
    NEXT="3"
  elif [ "${CONFDONE}" == "true" ]; then
    NEXT="2"
  else
    NEXT="1"
  fi
  while true; do
    echo "= \"\Z4========== Main ==========\Zn \" "                                            >"${TMP_PATH}/menu"
    if [ -z "${ARCCONF}" ]; then
      echo "0 \"Enable Arc Patch\" "                                                          >>"${TMP_PATH}/menu"
    fi
    echo "1 \"Choose Model \" "                                                               >>"${TMP_PATH}/menu"
    if [ "${CONFDONE}" == "true" ]; then
      echo "2 \"Build Loader \" "                                                             >>"${TMP_PATH}/menu"
    fi
    if [ "${BUILDDONE}" == "true" ]; then
      echo "3 \"Boot Loader \" "                                                              >>"${TMP_PATH}/menu"
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
        echo "p \"SN/Mac Options \" "                                                         >>"${TMP_PATH}/menu"
        if [ "${DT}" == "false" ] && [ ${SATACONTROLLER} -gt 0 ]; then
          echo "S \"Sata PortMap \" "                                                         >>"${TMP_PATH}/menu"
        fi
        if [ "${DT}" == "true" ]; then
          echo "o \"DTS Map Options \" "                                                      >>"${TMP_PATH}/menu"
        fi
        if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "cpufreqscaling"; then
          echo "g \"Frequency Scaling Governor\" "                                            >>"${TMP_PATH}/menu"
        fi
        if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "storagepanel"; then
          echo "P \"StoragePanel Options \" "                                                 >>"${TMP_PATH}/menu"
        fi
        if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "sequentialio"; then
          echo "Q \"SequentialIO Options \" "                                                 >>"${TMP_PATH}/menu"
        fi
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
        echo "l \"Edit User Config \" "                                                       >>"${TMP_PATH}/menu"
        echo "s \"Allow Downgrade \" "                                                        >>"${TMP_PATH}/menu"
        echo "t \"Change User Password \" "                                                   >>"${TMP_PATH}/menu"
        echo "N \"Add new User\" "                                                            >>"${TMP_PATH}/menu"
        echo "J \"Reset Network Config \" "                                                   >>"${TMP_PATH}/menu"
        echo "M \"Mount DSM Storage Pool\" "                                                  >>"${TMP_PATH}/menu"
        if [ "${PLATFORM}" == "epyc7002" ]; then
          echo "K \"Kernel: \Z4${KERNEL}\Zn \" "                                              >>"${TMP_PATH}/menu"
        fi
        if [ "${DT}" == "true" ]; then
          echo "H \"Hotplug/SortDrives: \Z4${HDDSORT}\Zn \" "                                 >>"${TMP_PATH}/menu"
        else
          echo "h \"USB Mount: \Z4${USBMOUNT}\Zn \" "                                         >>"${TMP_PATH}/menu"
        fi
        echo "O \"Official Driver Priority: \Z4${ODP}\Zn \" "                                 >>"${TMP_PATH}/menu"
        echo "B \"Grep DSM Config from Backup \" "                                            >>"${TMP_PATH}/menu"
      fi
    fi
    if [ "${LOADEROPTS}" == "true" ]; then
      echo "8 \"\Z1Hide Loader Options\Zn \" "                                                >>"${TMP_PATH}/menu"
    else
      echo "8 \"\Z1Show Loader Options\Zn \" "                                                >>"${TMP_PATH}/menu"
    fi
    if [ "${LOADEROPTS}" == "true" ]; then
      echo "= \"\Z4========= Loader =========\Zn \" "                                         >>"${TMP_PATH}/menu"
      echo "= \"\Z1=== Edit with caution! ===\Zn \" "                                         >>"${TMP_PATH}/menu"
      echo "D \"StaticIP for Loader/DSM \" "                                                  >>"${TMP_PATH}/menu"
      echo "f \"Bootscreen Options \" "                                                       >>"${TMP_PATH}/menu"
      echo "W \"RD Compression: \Z4${RD_COMPRESSED}\Zn \" "                                   >>"${TMP_PATH}/menu"
      echo "X \"Sata DOM: \Z4${SATADOM}\Zn \" "                                               >>"${TMP_PATH}/menu"
      echo "u \"LKM Version: \Z4${LKM}\Zn \" "                                                >>"${TMP_PATH}/menu"
      echo "L \"Grep Logs from dbgutils \" "                                                  >>"${TMP_PATH}/menu"
      echo "w \"Reset Loader to Defaults \" "                                                 >>"${TMP_PATH}/menu"
      echo "C \"Clone Loader to another Disk \" "                                             >>"${TMP_PATH}/menu"
      echo "n \"Grub Bootloader Config \" "                                                   >>"${TMP_PATH}/menu"
      echo "y \"Choose a Keymap for Loader\" "                                                >>"${TMP_PATH}/menu"
      echo "F \"\Z1Formate Disks \Zn \" "                                                     >>"${TMP_PATH}/menu"
    fi
    echo "= \"\Z4========== Misc ==========\Zn \" "                                           >>"${TMP_PATH}/menu"
    echo "x \"Backup/Restore/Recovery \" "                                                    >>"${TMP_PATH}/menu"
    echo "z \"Update Menu \" "                                                                >>"${TMP_PATH}/menu"
    echo "I \"Power/Service Menu \" "                                                         >>"${TMP_PATH}/menu"
    echo "V \"Credits \" "                                                                    >>"${TMP_PATH}/menu"

    dialog --clear --default-item ${NEXT} --backtitle "$(backtitle)" --colors \
      --cancel-label "Exit" --title "Arc Menu" --menu "" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
      # Main Section
      0) decryptMenu; NEXT="0" ;;
      1) arcModel; NEXT="2" ;;
      2) arcSummary; NEXT="3" ;;
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
      e) ONLYVERSION="true" && arcVersion; NEXT="e" ;;
      p) ONLYPATCH="true" && arcPatch; NEXT="p" ;;
      S) storageMenu; NEXT="S" ;;
      o) dtsMenu; NEXT="o" ;;
      g) governorMenu; NEXT="g" ;;
      P) storagepanelMenu; NEXT="P" ;;
      Q) sequentialIOMenu; NEXT="Q" ;;
      # Boot Section
      6) [ "${BOOTOPTS}" == "true" ] && BOOTOPTS='false' || BOOTOPTS='true'
        BOOTOPTS="${BOOTOPTS}"
        NEXT="6"
        ;;
      m) [ "${KERNELLOAD}" == "kexec" ] && KERNELLOAD='power' || KERNELLOAD='kexec'
        writeConfigKey "kernelload" "${KERNELLOAD}" "${USER_CONFIG_FILE}"
        NEXT="m"
        ;;
      E) [ "${EMMCBOOT}" == "true" ] && EMMCBOOT='false' || EMMCBOOT='true'
        if [ "${EMMCBOOT}" == "false" ]; then
          writeConfigKey "emmcboot" "false" "${USER_CONFIG_FILE}"
          deleteConfigKey "synoinfo.disk_swap" "${USER_CONFIG_FILE}"
          deleteConfigKey "synoinfo.supportraid" "${USER_CONFIG_FILE}"
          deleteConfigKey "synoinfo.support_emmc_boot" "${USER_CONFIG_FILE}"
          deleteConfigKey "synoinfo.support_install_only_dev" "${USER_CONFIG_FILE}"
        elif [ "${EMMCBOOT}" == "true" ]; then
          writeConfigKey "emmcboot" "true" "${USER_CONFIG_FILE}"
          writeConfigKey "synoinfo.disk_swap" "no" "${USER_CONFIG_FILE}"
          writeConfigKey "synoinfo.supportraid" "no" "${USER_CONFIG_FILE}"
          writeConfigKey "synoinfo.support_emmc_boot" "yes" "${USER_CONFIG_FILE}"
          writeConfigKey "synoinfo.support_install_only_dev" "yes" "${USER_CONFIG_FILE}"
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="E"
        ;;
      i) bootipwaittime; NEXT="i" ;;
      q) [ "${DIRECTBOOT}" == "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
        grub-editenv ${USER_GRUBENVFILE} create
        writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
        NEXT="q"
        ;;
      # DSM Section
      7) [ "${DSMOPTS}" == "true" ] && DSMOPTS='false' || DSMOPTS='true'
        DSMOPTS="${DSMOPTS}"
        NEXT="7"
        ;;
      j) cmdlineMenu; NEXT="j" ;;
      k) synoinfoMenu; NEXT="k" ;;
      l) editUserConfig; NEXT="l" ;;
      s) downgradeMenu; NEXT="s" ;;
      t) resetPassword; NEXT="t" ;;
      N) addNewDSMUser; NEXT="N" ;;
      J) resetDSMNetwork; NEXT="J" ;;
      M) mountDSM; NEXT="M" ;;
      K) [ "${KERNEL}" == "official" ] && KERNEL='custom' || KERNEL='official'
        writeConfigKey "kernel" "${KERNEL}" "${USER_CONFIG_FILE}"
        dialog --backtitle "$(backtitle)" --title "DSM Kernel" \
          --infobox "Switching to Custom Kernel! Stay patient..." 4 50
        if [ "${ODP}" == "true" ]; then
          ODP="false"
          writeConfigKey "odp" "${ODP}" "${USER_CONFIG_FILE}"
        fi
        PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
        PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
        KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
        if [ -n "${PLATFORM}" ] && [ -n "${KVER}" ]; then
          [ "${PLATFORM}" == "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
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
        writeConfigKey "hddsort" "${HDDSORT}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="H"
        ;;
      h) if [ "${USBMOUNT}" == "auto" ]; then
          USBMOUNT='internal'
        elif [ "${USBMOUNT}" == "internal" ]; then
          USBMOUNT='external'
        elif [ "${USBMOUNT}" == "external" ]; then
          USBMOUNT='auto'
        fi
        writeConfigKey "usbmount" "${USBMOUNT}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="h"
        ;;
      O) [ "${ODP}" == "false" ] && ODP='true' || ODP='false'
        writeConfigKey "odp" "${ODP}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        NEXT="O"
        ;;
      B) getbackup; NEXT="B" ;;
      # Loader Section
      8) [ "${LOADEROPTS}" == "true" ] && LOADEROPTS='false' || LOADEROPTS='true'
        LOADEROPTS="${LOADEROPTS}"
        NEXT="8"
        ;;
      D) staticIPMenu; NEXT="D" ;;
      f) bootScreen; NEXT="f" ;;
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
      L) greplogs; NEXT="L" ;;
      w) resetLoader; NEXT="w" ;;
      C) cloneLoader; NEXT="C" ;;
      n) editGrubCfg; NEXT="n" ;;
      y) keymapMenu; NEXT="y" ;;
      F) formatDisks; NEXT="F" ;;
      # Misc Settings
      x) backupMenu; NEXT="x" ;;
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
