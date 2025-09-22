#
# Copyright (C) 2025 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

###############################################################################
# Model Selection
function arcModel() {
  [ "${ARC_OFFLINE}" != "true" ] && checkHardwareID || true
  dialog --backtitle "$(backtitle)" --title "Model" \
    --infobox "Reading Models..." 3 25
  RESTRICT=1
  PS="$(readConfigEntriesArray "platforms" "${P_FILE}" | sort)"
  echo -n "" >"${TMP_PATH}/modellist"
  while read -r P; do
    PM="$(readConfigEntriesArray "${P}" "${D_FILE}" | sort)"
    while read -r M; do
      echo "${M} ${P}" >>"${TMP_PATH}/modellist"
    done < <(echo "${PM}")
  done < <(echo "${PS}")
  if [ "${ARC_MODE}" = "config" ]; then
    while true; do
      echo -n "" >"${TMP_PATH}/menu"
      while read -r M A; do
        COMPATIBLE=1
        DT="$(readConfigKey "platforms.${A}.dt" "${P_FILE}")"
        FLAGS="$(readConfigArray "platforms.${A}.flags" "${P_FILE}")"
        NOFLAGS="$(readConfigArray "platforms.${A}.noflags" "${P_FILE}")"
        BETA=""
        ARC_CONFM="$(generateSerial true "${M}")"
        [ "${#ARC_CONFM}" -eq 13 ] && ARC="x" || ARC=""
        [ "${DT}" = "true" ] && DTS="x" || DTS=""
        IGPU=""
        IGPUS=""
        IGPUID="$(lspci -nd ::300 2>/dev/null | grep "8086" | cut -d' ' -f3 | sed 's/://g')"
        if [ -n "${IGPUID}" ]; then grep -iq "${IGPUID}" ${ARC_PATH}/include/i915ids && IGPU="all" || IGPU="igpuv5"; else IGPU=""; fi
        if [[ " ${IGPU1L[@]} " =~ " ${A} " ]] && [ "${IGPU}" = "all" ]; then
          IGPUS="+"
        elif [[ " ${IGPU2L[@]} " =~ " ${A} " ]] && [[ "${IGPU}" = "igpuv5" || "${IGPU}" = "all" ]]; then
          IGPUS="x"
        else
          IGPUS=""
        fi
        [ "${DT}" = "true" ] && HBAS="" || HBAS="x"
        if echo "${KVER5L[@]}" | grep -wq "${A}"; then
          HBAS="x"
        fi
        [ "${DT}" = "false" ] && USBS="int/ext" || USBS="ext"
        is_in_array "${M}" "${NVMECACHE[@]}" && M_2_CACHE="+" || M_2_CACHE="x"
        [[ "${M}" = "DS220+" ||  "${M}" = "DS224+" || "${M}" = "DVA1622" ]] && M_2_CACHE=""
        [[ "${M}" = "DS220+" || "${M}" = "DS224+" || "${DT}" = "false" ]] && M_2_STORAGE="" || M_2_STORAGE="+"
        if [ "${RESTRICT}" -eq 1 ]; then
          for F in ${FLAGS}; do
            grep -q "^flags.*${F}.*" /proc/cpuinfo || COMPATIBLE=0
          done
          for NF in ${NOFLAGS}; do
            grep -q "^flags.*${NF}.*" /proc/cpuinfo && COMPATIBLE=0
          done
          if is_in_array "${A}" "${KVER5L[@]}"; then
            if { [ "${NVMEDRIVES}" -eq 0 ] && [ "${BUS}" = "usb" ] && [ "${SATADRIVES}" -eq 0 ] && [ "${EXTERNALCONTROLLER}" = "false" ]; } ||
               { [ "${NVMEDRIVES}" -eq 0 ] && [ "${BUS}" = "sata" ] && [ "${SATADRIVES}" -eq 1 ] && [ "${EXTERNALCONTROLLER}" = "false" ]; } ||
               [ "${SCSICONTROLLER}" -ge 1 ] || [ "${RAIDCONTROLLER}" -ge 1 ]; then
              COMPATIBLE=0
            fi
          else
            if { [ "${DT}" = "true" ] && [ "${EXTERNALCONTROLLER}" = "true" ]; } ||
               { [ "${SATACONTROLLER}" -eq 0 ] && [ "${EXTERNALCONTROLLER}" = "false" ]; } ||
               { [ "${NVMEDRIVES}" -gt 0 ] && [ "${BUS}" = "usb" ] && [ "${SATADRIVES}" -eq 0 ] && [ "${EXTERNALCONTROLLER}" = "false" ]; } ||
               { [ "${NVMEDRIVES}" -gt 0 ] && [ "${BUS}" = "sata" ] && [ "${SATADRIVES}" -eq 1 ] && [ "${EXTERNALCONTROLLER}" = "false" ]; }; then
              COMPATIBLE=0
            fi
          fi
          [ -z "$(grep -w "${M}" "${S_FILE}")" ] && COMPATIBLE=0
          [ -z "$(grep -w "${A}" "${P_FILE}")" ] && COMPATIBLE=0
        fi
        [ -n "$(grep -w "${M}" "${S_FILE}")" ] && BETA="Loader" || BETA="Syno"
        [ "${COMPATIBLE}" -eq 1 ] && echo -e "${M} \"\t$(printf "\Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "${A}" "${DTS}" "${ARC}" "${IGPUS}" "${HBAS}" "${M_2_CACHE}" "${M_2_STORAGE}" "${USBS}" "${BETA}")\" ">>"${TMP_PATH}/menu"
      done < <(cat "${TMP_PATH}/modellist")
      [ ! -s "${TMP_PATH}/menu" ] && echo "No supported models found." >"${TMP_PATH}/menu"
      [ "${RESTRICT}" -eq 1 ] && TITLEMSG="Supported Models for your Hardware" || TITLEMSG="Supported and unsupported Models for your Hardware"
      MSG="${TITLEMSG} (x = supported / + = need Addons)\n$(printf "\Zb%-16s\Zn \Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "Model" "Platform" "DT" "Arc" "iGPU" "HBA" "M.2 Cache" "M.2 Volume" "USB Mount" "Source")"
      dialog --backtitle "$(backtitle)" --title "DSM Model" --colors \
        --cancel-label "Show all" --help-button --help-label "Exit" \
        --menu "${MSG}" 0 115 0 \
        --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
      RET=$?
      case ${RET} in
        0)
          resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
          [ -z "${resp}" ] && return
          break
          ;;
        1)
          [ "${RESTRICT}" -eq 1 ] && RESTRICT=0 || RESTRICT=1
          ;;
        *)
          return 
          break
          ;;
      esac
    done
  fi
  if [ "${ARC_MODE}" = "config" ] && [ "${MODEL}" != "${resp}" ]; then
    MODEL="${resp}"
    writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "emmcboot" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "governor" "" "${USER_CONFIG_FILE}"
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
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
  fi
  PLATFORM="$(grep -w "${MODEL}" "${TMP_PATH}/modellist" | awk '{print $2}' | head -1)"
  writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"
  resetBuild
  writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  arcVersion
  return
}

###############################################################################
# Arc Version Section
function arcVersion() {
  init_default_addons() {
    initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
    initConfigKey "addons.arcdns" "" "${USER_CONFIG_FILE}"
    initConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
    initConfigKey "addons.hdddb" "" "${USER_CONFIG_FILE}"
    initConfigKey "addons.reducelogs" "" "${USER_CONFIG_FILE}"
    initConfigKey "addons.storagepanel" "" "${USER_CONFIG_FILE}"
    initConfigKey "addons.updatenotify" "" "${USER_CONFIG_FILE}"
    if [ "${NVMEDRIVES}" -gt 0 ]; then
      if is_in_array "${PLATFORM}" "${KVER5L[@]}" && [ "${SATADRIVES}" -eq 0 ] && [ "${SASDRIVES}" -eq 0 ] && [ "${BUS}" != "sata" ]; then
        initConfigKey "addons.nvmesystem" "" "${USER_CONFIG_FILE}"
      elif is_in_array "${PLATFORM}" "${KVER5L[@]}" && [ "${SATADRIVES}" -le 1 ] && [ "${SASDRIVES}" -eq 0 ] && [ "${BUS}" = "sata" ]; then
        initConfigKey "addons.nvmesystem" "" "${USER_CONFIG_FILE}"
      elif [ "${DT}" = "true" ]; then
        initConfigKey "addons.nvmevolume" "" "${USER_CONFIG_FILE}"
      elif is_in_array "${MODEL}" "${NVMECACHE[@]}"; then
        initConfigKey "addons.nvmecache" "" "${USER_CONFIG_FILE}"
      fi
    fi
    if [ "${MEV}" = "physical" ]; then
      initConfigKey "addons.cpufreqscaling" "" "${USER_CONFIG_FILE}"
      initConfigKey "addons.powersched" "" "${USER_CONFIG_FILE}"
      initConfigKey "addons.sensors" "" "${USER_CONFIG_FILE}"
      CORETEMP="$(find "/sys/devices/platform/" -name "temp1_input" | grep -E 'coretemp|k10temp' | head -1 | sed -n 's|.*/\(hwmon.*\/temp1_input\).*|\1|p')"
      if [ -n "${CORETEMP}" ]; then
        initConfigKey "addons.fancontrol" "" "${USER_CONFIG_FILE}"
      fi
      if is_in_array "${PLATFORM}" "${KVER5L[@]}"; then
        if command -v dmidecode >/dev/null 2>&1; then
            UGREEN_CHECK=$(dmidecode --string system-product-name 2>/dev/null)
            case "${UGREEN_CHECK}" in
              DXP6800*|DX4600*|DX4700*|DXP2800*|DXP4800*|DXP8800*)
                initConfigKey "addons.ledcontrol" "" "${USER_CONFIG_FILE}"
                ;;
            esac
        fi
      fi
    else
      initConfigKey "addons.vmtools" "" "${USER_CONFIG_FILE}"
    fi
    if is_in_array "${PLATFORM}" "${IGPU1L[@]}" && grep -iq "${IGPUID}" "${ARC_PATH}/include/i915ids"; then
      initConfigKey "addons.i915" "" "${USER_CONFIG_FILE}"
    fi
    if [ "${SASDRIVES}" -gt 0 ] && [ "${DT}" = "true" ]; then
      initConfigKey "addons.smartctl" "" "${USER_CONFIG_FILE}"
    fi
    WEBHOOKNOTIFY="$(readConfigKey "arc.webhooknotify" "${USER_CONFIG_FILE}")"
    DISCORDNOTIFY="$(readConfigKey "arc.discordnotify" "${USER_CONFIG_FILE}")"
    if [ "${WEBHOOKNOTIFY}" = "true" ] || [ "${DISCORDNOTIFY}" = "true" ]; then
      initConfigKey "addons.notification" "" "${USER_CONFIG_FILE}"
    fi
  }

  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  if [ "${ARC_MODE}" = "config" ] && [ "${ARCRESTORE}" != "true" ]; then
    CVS="$(readConfigEntriesArray "platforms.${PLATFORM}.productvers" "${P_FILE}")"
    PVS="$(readConfigEntriesArray "${PLATFORM}.\"${MODEL}\"" "${D_FILE}")"
    LVS=""
    for V in $(echo "${PVS}" | sort -r); do
      if echo "${CVS}" | grep -qx "${V:0:3}"; then
        LVS="${LVS}${V} "$'\n'
      fi
    done
    dialog --clear --no-items --nocancel --title "DSM Version" --backtitle "$(backtitle)" \
      --no-items --menu "Select DSM Version" 7 30 0 ${LVS} \
    2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    RESP="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
    [ -z "${RESP}" ] && return
     if [ "${PRODUCTVER}" != "${RESP:0:3}" ]; then
      PRODUCTVER="${RESP:0:3}"
      rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
    fi

    writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
    writeConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
    writeConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
    writeConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
    writeConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"

    PAT_URL_UPDATE="$(readConfigKey "${PLATFORM}.\"${MODEL}\".\"${RESP}\".url" "${D_FILE}")"
    PAT_HASH_UPDATE="$(readConfigKey "${PLATFORM}.\"${MODEL}\".\"${RESP}\".hash" "${D_FILE}")"

    while [ -z "${PAT_URL_UPDATE}" ] || [ -z "${PAT_HASH_UPDATE}" ]; do
      MSG="Failed to get PAT Data.\n"
      MSG+="Please manually fill in the URL and Hash of PAT.\n"
      MSG+="You will find these Data at: http://dsmdata.auxxxilium.tech/"
      dialog --backtitle "$(backtitle)" --colors --title "Arc Build" --default-button "OK" \
        --form "${MSG}" 11 120 2 "Url" 1 1 "${PAT_URL_UPDATE}" 1 8 110 0 "Hash" 2 1 "${PAT_HASH_UPDATE}" 2 8 110 0 \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      PAT_URL_UPDATE="$(sed -n '1p' "${TMP_PATH}/resp")"
      PAT_HASH_UPDATE="$(sed -n '2p' "${TMP_PATH}/resp")"
    done

    if [ "${PAT_URL}" != "${PAT_URL_UPDATE}" ] || [ "${PAT_HASH}" != "${PAT_HASH_UPDATE}" ]; then
      PAT_URL="${PAT_URL_UPDATE}"
      PAT_HASH="${PAT_HASH_UPDATE}"
      writeConfigKey "paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"
      writeConfigKey "pathash" "${PAT_HASH}" "${USER_CONFIG_FILE}"
      rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
      rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" >/dev/null 2>&1 || true
      rm -f "${USER_UP_PATH}/"*.tar >/dev/null 2>&1 || true
    fi
  fi

  if [ -n "${PAT_URL}" ] || [ -n "${PAT_HASH}" ]; then
    VALID="true"
  fi

  if [ "${ONLYVERSION}" != "true" ] && [ "${ARC_MODE}" = "config" ]; then
    if [ "${DT}" = "true" ]; then
      if [ "${SASCONTROLLER}" -ge 1 ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Warning" \
          --yesno "WARN: You use a HBA Controller and selected a DT Model.\nThis is an experimental feature.\n\nContinue anyway?" 8 70
        [ $? -ne 0 ] && return
      fi
      if [ "${SCSICONTROLLER}" -ge 1 ] || [ "${RAIDCONTROLLER}" -ge 1 ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Warning" \
          --yesno "WARN: You use a Raid/SCSI Controller and selected a DT Model.\nThis is not supported.\n\nContinue anyway?" 8 70
        [ $? -ne 0 ] && return
      fi
    fi
    USERID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
    ADDONS_LIST="$(readConfigMap "addons" "${USER_CONFIG_FILE}")"
    if [ -n "${USERID}" ] && ! echo "${ADDONS_LIST}" | grep -q "notification"; then
      MSG="Enable Discord Notification for Loader Mode and DSM Status?"
      dialog --backtitle "$(backtitle)" --colors --title "Notification" \
        --yesno "${MSG}" 5 65
      [ $? -eq 0 ] && writeConfigKey "arc.discordnotify" "true" "${USER_CONFIG_FILE}"
    fi
    MSG="Do you want to use Automated Mode?\nIf yes, Loader will configure, build and boot DSM."
    dialog --backtitle "$(backtitle)" --colors --title "Automated Mode" \
      --yesno "${MSG}" 6 55
    ARC_MODE=$([ $? -eq 0 ] && echo "automated" || echo "config")
  fi

  if [ "${VALID}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Config" \
      --infobox "Reconfiguring Cmdline, Modules and Synoinfo" 3 60
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"

    while IFS=': ' read -r KEY VALUE; do
      writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
    done < <(readConfigMap "platforms.${PLATFORM}.synoinfo" "${P_FILE}")

    KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
    is_in_array "${PLATFORM}" "${KVER5L[@]}" && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
    if [ -n "${PLATFORM}" ] && [ -n "${KVERP}" ]; then
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      mergeConfigModules "$(getAllModules "${PLATFORM}" "${KVERP}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
    fi

    ADDONS="$(readConfigKey "addons" "${USER_CONFIG_FILE}")"
    if [ "${ADDONS}" = "{}" ]; then
      init_default_addons
    fi

    while IFS=': ' read -r ADDON PARAM; do
      [ -z "${ADDON}" ] && continue
      if ! isAddonAvailable "${ADDON}" "${PLATFORM}"; then
        deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
      fi
    done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

    if [ "${ONLYVERSION}" = "true" ]; then
      resetBuild
      ONLYVERSION="false"
      return
    else
      arcPatch
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Arc Config" --aspect 18 \
      --infobox "Arc Config failed!\nExit." 4 40
    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
    sleep 5
    return
  fi
  return
}

###############################################################################
# Arc Patch Section
function arcPatch() {
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"

  if [ "${ARC_MODE}" = "automated" ] && [ "${ARC_PATCH}" != "user" ]; then
    if [ ! -f "${ORI_ZIMAGE_FILE}" ] || [ ! -f "${ORI_RDGZ_FILE}" ]; then
      SN="$(generateSerial "true" "${MODEL}")"
      ARC_PATCH="false"
      [ "${#SN}" -eq 13 ] && ARC_PATCH="true" || SN="$(generateSerial "false" "${MODEL}")"
    fi
  elif [ "${ARC_MODE}" = "config" ]; then
    SN="$(generateSerial "true" "${MODEL}")"
    OPTIONS=(
      2 "Use random SN/Mac (Reduced DSM Features)"
      3 "Use my own SN/Mac (Be sure your Data is valid)"
    )
    [ "${#SN}" -eq 13 ] && OPTIONS=(1 "Use Arc Patch (AME, QC, Push Notify and more)" "${OPTIONS[@]}")
    
    dialog --clear --backtitle "$(backtitle)" \
      --nocancel --title "SN/Mac Options" \
      --menu "Choose an Option" 7 60 0 \
      "${OPTIONS[@]}" \
      2>"${TMP_PATH}/resp"
    
    resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
    [ -z "${resp}" ] && return 1
    
    case ${resp} in
      1)
        ARC_PATCH="true"
        SN="$(generateSerial "${ARC_PATCH}" "${MODEL}")"
        ;;
      2)
        ARC_PATCH="false"
        SN="$(generateSerial "${ARC_PATCH}" "${MODEL}")"
        ;;
      3)
        while true; do
          dialog --backtitle "$(backtitle)" --colors --title "Serial" \
            --inputbox "Please enter a valid SN!" 7 50 "" \
            2>"${TMP_PATH}/resp"
          [ $? -ne 0 ] && break 2
          SN="$(cat "${TMP_PATH}/resp" | tr '[:lower:]' '[:upper:]')"
          [ -z "${SN}" ] && return
          [ "${#SN}" -eq 13 ] && break
        done
        ARC_PATCH="user"
        ;;
    esac
  fi
  writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.patch" "${ARC_PATCH}" "${USER_CONFIG_FILE}"
  resetBuild
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  arcSettings
  return
}

###############################################################################
# Arc Settings Section
function arcSettings() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  
  dialog --backtitle "$(backtitle)" --colors --title "Network Config" \
    --infobox "Generating Network Config..." 3 40
  sleep 2
  getnet
  
  if [ "${ONLYPATCH}" = "true" ]; then
    resetBuild
    ONLYPATCH="false"
    return 0
  fi
  
  dialog --backtitle "$(backtitle)" --colors --title "Storage Map" \
    --infobox "Generating Storage Map..." 3 40
  sleep 2
  getmap
  if [ "${DT}" = "false" ]; then
    getmapSelection
  fi
  
  if [ "${ARC_MODE}" = "config" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Addons" \
      --infobox "Loading Addons Table..." 3 40
    addonSelection
  fi
  
  if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "cpufreqscaling"; then
    if [ "${ARC_MODE}" = "config" ] && [ "${MEV}" = "physical" ]; then
      dialog --backtitle "$(backtitle)" --colors --title "CPU Frequency Scaling" \
        --infobox "Generating Governor Table..." 3 40
      governorSelection
    elif [ "${ARC_MODE}" = "automated" ] && [ "${MEV}" = "physical" ]; then
      if [ "${KVER:0:1}" = "5" ]; then
        writeConfigKey "governor" "schedutil" "${USER_CONFIG_FILE}"
      else
        writeConfigKey "governor" "conservative" "${USER_CONFIG_FILE}"
      fi
    fi
  fi

  if [ "${ARC_MODE}" = "config" ]; then
    DEVICENIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
    MODELNIC="$(readConfigKey "${MODEL}.ports" "${S_FILE}")"
    [ "${DEVICENIC}" -gt 8 ] && dialog --backtitle "$(backtitle)" --title "Arc Warning" --msgbox "WARN: You have more NIC (${DEVICENIC}) than 8 NIC.\nOnly 8 supported by DSM." 6 60
    [ "${DEVICENIC}" -gt "${MODELNIC}" ] && [ "${ARC_PATCH}" = "true" ] && dialog --backtitle "$(backtitle)" --title "Arc Warning" --msgbox "WARN: You have more NIC (${DEVICENIC}) than supported by Model (${MODELNIC}).\nOnly the first ${MODELNIC} are used by Arc Patch." 6 80
    [ "${AESSYS}" = "false" ] && dialog --backtitle "$(backtitle)" --title "Arc Warning" --msgbox "WARN: Your System doesn't support Hardware encryption in DSM. (AES)" 5 70
    [ "${CPUFREQ}" = "false" ] && readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "cpufreqscaling" && dialog --backtitle "$(backtitle)" --title "Arc Warning" --msgbox "WARN: It is possible that CPU Frequency Scaling is not working properly with your System." 6 80
  fi
  
  EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
  if [ "${EMMCBOOT}" = "true" ]; then
    writeConfigKey "modules.mmc_block" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modules.mmc_core" "" "${USER_CONFIG_FILE}"
  else
    deleteConfigKey "modules.mmc_block" "${USER_CONFIG_FILE}"
    deleteConfigKey "modules.mmc_core" "${USER_CONFIG_FILE}"
  fi
  
  if [ -n "${PLATFORM}" ] && [ -n "${MODEL}" ] && [ -n "${KVER}" ] && [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ]; then
    writeConfigKey "arc.confdone" "true" "${USER_CONFIG_FILE}"
    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
    if [ "${ARC_MODE}" = "config" ]; then
      dialog --clear --backtitle "$(backtitle)" --title "Config done" \
        --no-cancel --menu "Build now?" 7 40 0 \
        1 "Yes - Build Arc Loader now" \
        2 "No - I want to make changes" \
      2>"${TMP_PATH}/resp"
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && return
      [ "${resp}" -eq 1 ] && makearc || dialog --clear --no-items --backtitle "$(backtitle)"
    else
      makearc
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Config failed" --msgbox "ERROR: Config failed!\nExit." 6 40
    return 1
  fi
  return
}

###############################################################################
# Building Loader
function makearc() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  ARC_BACKUP="$(readConfigKey "arc.backup" "${USER_CONFIG_FILE}")"
  ARC_OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  while IFS=': ' read -r ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! isAddonAvailable "${ADDON}" "${PLATFORM}"; then
      deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  if [ ! -f "${ORI_ZIMAGE_FILE}" ] || [ ! -f "${ORI_RDGZ_FILE}" ]; then
    getpatfiles
  fi
  if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q fancontrol; then
    writeConfigKey "addons.sensors" "" "${USER_CONFIG_FILE}"
  fi
  if [ -f "${ORI_ZIMAGE_FILE}" ] && [ -f "${ORI_RDGZ_FILE}" ] && [ "${CONFDONE}" = "true" ] && [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ]; then
    (
      livepatch
      sleep 3
    ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Build Loader" \
      --progressbox "Patching DSM Files..." 20 70
  else
    dialog --backtitle "$(backtitle)" --title "Build Loader" --aspect 18 \
      --infobox "Configuration issue found.\nCould not build Loader!\nExit." 5 40
    rm -f "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
    resetBuild
    sleep 2
    return
  fi
  if [ -f "${MOD_ZIMAGE_FILE}" ] && [ -f "${MOD_RDGZ_FILE}" ]; then
    USERID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
    if [ "${ARC_OFFLINE}" = "false" ] && [ "${ARC_BACKUP}" = "true" ] && [ -n "${USERID}" ]; then
      HWID="$(genHWID)"
      curl -sk -X POST -F "file=@${USER_CONFIG_FILE}" "https://arc.auxxxilium.tech?cup=${HWID}&userid=${USERID}" 2>/dev/null
      if [ $? -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --title "Online Backup" --infobox "Config Online Backup successful!" 3 45
        sleep 2
      else
        dialog --backtitle "$(backtitle)" --title "Online Backup" --infobox "Config Online Backup failed!" 3 45
        sleep 2
      fi
    fi
    writeConfigKey "arc.builddone" "true" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    if [ "${ARC_MODE}" = "automated" ] || [ "${UPDATEMODE}" = "true" ]; then
      bootcheck
    else
      dialog --clear --backtitle "$(backtitle)" --title "Build done" \
        --no-cancel --menu "Boot now?" 7 40 0 \
        1 "Yes - Boot DSM now" \
        2 "No - I want to make changes" \
      2>"${TMP_PATH}/resp"
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ "${resp}" -eq 1 ] && bootcheck || return
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Build Loader" --aspect 18 \
      --infobox "Could not build Loader!\nExit." 4 40
    resetBuild
    sleep 2
    return
  fi
  return
}

###############################################################################
# Calls boot.sh to boot into DSM Reinstall Mode
function juniorboot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  if [ "${BUILDDONE}" = "false" ] && [ "${ARC_MODE}" != "automated" ]; then
    dialog --backtitle "$(backtitle)" --title "Alert" \
      --yesno "Config changed, you need to rebuild the Loader?" 0 0
    if [ $? -eq 0 ]; then
      makearc
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Booting DSM Reinstall Mode...\nPlease stay patient!" 4 30
    sleep 3
    rebootTo junior
  fi
  return
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function bootcheck() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  if [ "${ARC_MODE}" != "automated" ] && [ "${BUILDDONE}" = "false" ]; then
    dialog --backtitle "$(backtitle)" --title "Alert" \
      --yesno "Config changed, you need to rebuild the Loader?" 0 0
    if [ $? -eq 0 ]; then
      makearc
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Booting DSM...\nPlease stay patient!" 4 25
    sleep 2
    exec reboot
  fi
  return
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  PREHASH="$(sha256sum "${USER_CONFIG_FILE}" | awk '{print $1}')"
  while true; do
    dialog --backtitle "$(backtitle)" --title "Edit with caution" \
      --ok-label "Save" --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return 1
    mv -f "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=$(yq eval "${USER_CONFIG_FILE}" 2>&1)
    [ $? -eq 0 ] && break || continue
    dialog --backtitle "$(backtitle)" --title "Invalid YAML format" --msgbox "${ERRORS}" 0 0
  done
  POSTHASH="$(sha256sum "${USER_CONFIG_FILE}" | awk '{print $1}')"
  if [ "${POSTHASH}" != "${PREHASH}" ]; then
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null
    dialog --backtitle "$(backtitle)" --title "User Config" \
      --msgbox "User Config changed!\nYou need to rebuild the Loader." 6 40
    resetBuild
  fi
  return
}

###############################################################################
# Shows option to manage Addons
function addonMenu() {
  addonSelection
  resetBuild
  return
}

function addonSelection() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"

  declare -A ADDONS
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

  rm -f "${TMP_PATH}/opts"
  touch "${TMP_PATH}/opts"

  while read -r ADDON DESC; do
    arrayExistItem "${ADDON}" "${!ADDONS[@]}" && ACT="on" || ACT="off"
    echo -e "${ADDON} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
  done < <(availableAddons "${PLATFORM}")

  dialog --backtitle "$(backtitle)" --title "Addons" --colors --aspect 18 \
    --checklist "Select Addons to include.\nAddons: \Z1System Addon\Zn | \Z4App Addon\Zn\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
    --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"

  declare -A ADDONS
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  for ADDON in ${resp}; do
    ADDONS["${ADDON}"]=""
    writeConfigKey "addons.\"${ADDON}\"" "" "${USER_CONFIG_FILE}"
  done
  return
}

###############################################################################
# Permit user select the modules to include
function modulesMenu() {
  NEXT="1"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  is_in_array "${PLATFORM}" "${KVER5L[@]}" && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
  while true; do
    rm -f "${TMP_PATH}/menu"
    {
      echo "1 \"Show/Select Modules\""
      echo "2 \"Add from expanded Modules\""
      echo "3 \"Only select loaded Modules\""
      echo "4 \"Deselect i915 with dependencies\""
      echo "5 \"Edit Moduleslist for Modules copied to DSM\""
      echo "6 \"Blacklist Modules to prevent loading in DSM\""
    } >"${TMP_PATH}/menu"
    dialog --backtitle "$(backtitle)" --title "Modules" \
      --cancel-label "Exit" --menu "Choose an option (Only edit Modules if you know what you do)" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
    1)
      while true; do
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --infobox "Reading Modules ..." 3 25
        ALLMODULES=$(getAllModules "${PLATFORM}" "${KVERP}")
        unset USERMODULES
        declare -A USERMODULES
        while IFS=': ' read -r KEY VALUE; do
          [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
        done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
        rm -f "${TMP_PATH}/opts"
        while read -r ID DESC; do
          arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
          echo "${ID} ${DESC} ${ACT}" >>"${TMP_PATH}/opts"
        done <<<${ALLMODULES}
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --cancel-label "Exit" \
          --extra-button --extra-label "Select all" \
          --help-button --help-label "Deselect all" \
          --checklist "Select Modules to include" 0 0 0 --file "${TMP_PATH}/opts" \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0)
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          mergeConfigModules "$(cat "${TMP_PATH}/resp" 2>/dev/null)" "${USER_CONFIG_FILE}"
          resetBuild
          break
          ;;
        3)
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          mergeConfigModules "$(echo "${ALLMODULES}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
          resetBuild
          ;;
        2)
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          resetBuild
          ;;
        *)
          break
          ;;
        esac
      done
      ;;
    2)
      PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
      PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
      KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
      is_in_array "${PLATFORM}" "${KVER5L[@]}" && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
      MODULES_TMP_PATH="/tmp/arc-modules-ex"
      if [ -z "${KVERP}" ]; then
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --msgbox "No Kernel Version found, please select a Model and Version first." 0 0
        continue
      fi
      idx=0
      while (( idx <= 5 )); do
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-modules-ex/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
        if [ -n "${TAG}" ]; then
          break
        fi
        sleep 3
        idx=$((${idx} + 1))
      done
      if [ -n "${TAG}" ]; then
        mkdir -p "${MODULES_TMP_PATH}"
        export URL="https://github.com/AuxXxilium/arc-modules-ex/releases/download/${TAG}/${PLATFORM}-${KVERP}.tgz"
        export TAG="${TAG}"
        {
          {
            curl -kL "${URL}" -o "${MODULES_TMP_PATH}/${PLATFORM}-${KVERP}.tgz" 2>&3 3>&-
          } 3>&1 >&4 4>&- |
          perl -C -lane '
            BEGIN {$header = "Downloading $ENV{URL}...\n\n"; $| = 1}
            $pcent = $F[0];
            $_ = join "", unpack("x3 a7 x4 a9 x8 a9 x7 a*") if length > 20;
            s/ /\xa0/g; # replacing space with nbsp as dialog squashes spaces
            if ($. <= 3) {
              $header .= "$_\n";
              $/ = "\r" if $. == 2
            } else {
              print "XXX\n$pcent\n$header$_\nXXX"
            }' 4>&- |
          dialog --gauge "Download Modules: ${TAG}..." 14 72 4>&-
        } 4>&1
        TGZ1="${MODULES_PATH}/${PLATFORM}-${KVERP}.tgz"
        TGZ2="${MODULES_TMP_PATH}/${PLATFORM}-${KVERP}.tgz"
        TMP1="$(mktemp -d)"
        TMP2="$(mktemp -d)"
        TMPOUT="$(mktemp -d)"
        CHECKLIST="${TMP_PATH}/modcompare"
        rm -f "${CHECKLIST}"

        tar -xzf "$TGZ1" -C "${TMP1}"
        tar -xzf "$TGZ2" -C "${TMP2}"

        MODS1=($(find "${TMP1}" -type f -name '*.ko' -exec basename {} \; | sort -u))
        MODS2=($(find "${TMP2}" -type f -name '*.ko' -exec basename {} \; | sort -u))
        ALL_MODS=($(printf "%s\n%s\n" "${MODS1[@]}" "${MODS2[@]}" | sort -u))

        for MOD in "${ALL_MODS[@]}"; do
          DESC=""
          MODNAME="${MOD%.ko}"
          if [ -f "${TMP2}/${MOD}" ]; then
            DESC="$(modinfo -F description "${TMP2}/${MOD}" 2>/dev/null)"
            DESC="$(echo "${DESC}" | sed -E 's/[\n]/ /g' | sed -E 's/\(Compiled by RR for DSM\)//g')"
            [ -z "${DESC}" ] && DESC="No description"
          fi
        
          if [[ " ${MODS1[*]} " == *" $MOD "* && " ${MODS2[*]} " == *" $MOD "* ]]; then
            if ! cmp -s "${TMP1}/${MOD}" "${TMP2}/${MOD}"; then
              echo "\"${MODNAME}\" \"\Z1Different\Zn - $DESC\" off" >>"$CHECKLIST"
            fi
          elif [[ " ${MODS2[*]} " == *" $MOD "* ]]; then
            echo "\"${MODNAME}\" \"\Z1Only in Expanded\Zn - $DESC\" off" >>"$CHECKLIST"
          else
            echo "\"${MODNAME}\" \"\Z1Only in Loader\Zn\" off" >>"$CHECKLIST"
          fi
        done

        dialog --title "Expanded Modules" --colors \
          --checklist "Select modules to REPLACE in Loader with version from Expanded:" 0 0 0 \
          --file "${CHECKLIST}" 2>"${TMP_PATH}/modsel"

        [ $? -ne 0 ] && { rm -rf "${TMP1}" "${TMP2}" "${TMPOUT}"; return 1; }
        SELMODS=$(cat "${TMP_PATH}/modsel" | tr -d '"')

        cp -f "${TMP1}"/*.ko "${TMPOUT}/" 2>/dev/null

        REPLACED_LIST=""
        DEPS_TO_COPY=()
        for MOD in ${SELMODS}; do
          MODNAME="${MOD//[[:space:]]/}"
          DEPS_TO_COPY+=("${MODNAME}")
          for DEP in $(getdepends "${PLATFORM}" "${KVERP}" "${MODNAME}"); do
            DEPS_TO_COPY+=("${DEP}")
            REPLACED_LIST+="${DEP}\n"
          done
        done
        
        DEPS_TO_COPY=($(printf "%s\n" "${DEPS_TO_COPY[@]}" | sort -u))
        REPLACED_LIST="$(printf "%s\n" "${REPLACED_LIST}" | sort -u  | sed 's/^\s*//; s/\s*$//')"
        [ -z "${REPLACED_LIST}" ] && REPLACED_LIST="No modules replaced."

        for DEP in "${DEPS_TO_COPY[@]}"; do
          [ -f "${TMP2}/${DEP}" ] && cp -f "${TMP2}/${DEP}" "${TMPOUT}/${DEP}"
        done

        tar -czf "${TGZ1}" -C "${TMPOUT}" .

        if [ -n "${SELMODS}" ]; then
          FIRMWARE_URL="https://github.com/AuxXxilium/arc-modules-ex/releases/download/${TAG}/firmware.tgz"
          FIRMWARE_PATH="${MODULES_TMP_PATH}/firmware.tgz"
          FIRMWARE_TMP="$(mktemp -d)"
          curl -skL --http1.1 "${FIRMWARE_URL}" -o "${FIRMWARE_PATH}"
          if [ -f "${FIRMWARE_PATH}" ]; then
            tar -xzf "${FIRMWARE_PATH}" -C "${FIRMWARE_TMP}"
            tar -czf "${MODULES_PATH}/firmware.tgz" -C "${FIRMWARE_TMP}" .
            rm -rf "${FIRMWARE_TMP}"
          fi
        fi

        dialog --title "Expanded Modules" --msgbox "Replaced Modules:\n${REPLACED_LIST}" 20 60

        rm -rf "${TMP1}" "${TMP2}" "${TMPOUT}" "${CHECKLIST}" "${TMP_PATH}/modsel"
        resetBuild
      fi
      ;;
    3)
      dialog --backtitle "$(backtitle)" --title "Modules" \
        --infobox "Only select loaded modules" 0 0
      KOLIST=""
      for I in $(lsmod 2>/dev/null | awk -F' ' '{print $1}' | grep -v 'Module'); do
        KOLIST+="$(getdepends "${PLATFORM}" "${KVERP}" "${I}") ${I} "
      done
      KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      for ID in ${KOLIST[@]}; do
        writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
      done
      resetBuild
      ;;
    4)
      DEPS="$(getdepends "${PLATFORM}" "${KVERP}" i915) i915"
      DELS=()
      while IFS=': ' read -r KEY VALUE; do
        [ -z "${KEY}" ] && continue
        if echo "${DEPS}" | grep -wq "${KEY}"; then
          DELS+=("${KEY}")
        fi
      done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
      if [ "${#DELS[@]}" -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --msgbox "No i915 with dependencies module to deselect." 0 0
      else
        for ID in ${DELS[@]}; do
          deleteConfigKey "modules.\"${ID}\"" "${USER_CONFIG_FILE}"
        done
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --msgbox "$(printf "Module %s deselected." "${DELS[@]}")" 0 0
      fi
      resetBuild
      ;;
    5)
      if [ -f ${USER_UP_PATH}/modulelist ]; then
        cp -f "${USER_UP_PATH}/modulelist" "${TMP_PATH}/modulelist.tmp"
      else
        cp -f "${ARC_PATH}/include/modulelist" "${TMP_PATH}/modulelist.tmp"
      fi
      while true; do
        dialog --backtitle "$(backtitle)" --title "Edit with caution" \
          --ok-label "Save" --cancel-label "Exit" \
          --editbox "${TMP_PATH}/modulelist.tmp" 0 0 2>"${TMP_PATH}/modulelist.user"
        [ $? -ne 0 ] && break
        [ ! -d "${USER_UP_PATH}" ] && mkdir -p "${USER_UP_PATH}"
        mv -f "${TMP_PATH}/modulelist.user" "${USER_UP_PATH}/modulelist"
        dos2unix "${USER_UP_PATH}/modulelist" 2>/dev/null
        resetBuild
        break
      done
      ;;
    6)
      # modprobe.blacklist
      MSG=""
      MSG+="The blacklist is used to prevent the kernel from loading specific modules.\n"
      MSG+="The blacklist is a list of module names separated by ','.\n"
      MSG+="For example: \Z4evbug,cdc_ether\Zn\n"
      while true; do
        modblacklist="$(readConfigKey "modblacklist" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Modules" --colors \
          --inputbox "${MSG}" 12 70 "${modblacklist}" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        VALUE="$(cat "${TMP_PATH}/resp")"
        if echo "${VALUE}" | grep -q " "; then
          dialog --backtitle "$(backtitle)" --title "Modules/Cmdline" \
            --yesno "Invalid list, No spaces should appear, retry?" 0 0
          [ $? -eq 0 ] && continue || break
        fi
        writeConfigKey "modblacklist" "${VALUE}" "${USER_CONFIG_FILE}"
        break
      done
      ;;
    esac
  done
  return
}

###############################################################################
# Let user edit cmdline
function cmdlineMenu() {
  # Loop menu
  while true; do
    echo "1 \"Add a Cmdline item\""                               >"${TMP_PATH}/menu"
    echo "2 \"Delete Cmdline item(s)\""                           >>"${TMP_PATH}/menu"
    echo "3 \"CPU Fix\""                                          >>"${TMP_PATH}/menu"
    echo "4 \"RAM Fix\""                                          >>"${TMP_PATH}/menu"
    echo "5 \"PCI/IRQ Fix\""                                      >>"${TMP_PATH}/menu"
    echo "6 \"C-State Fix\""                                      >>"${TMP_PATH}/menu"
    echo "7 \"NVMe Optimization\""                                >>"${TMP_PATH}/menu"
    echo "8 \"CPU Performance Optimization\""                     >>"${TMP_PATH}/menu"
    echo "9 \"Kernelpanic Behavior\""                             >>"${TMP_PATH}/menu"
    dialog --backtitle "$(backtitle)" --title "Cmdline"  --cancel-label "Exit" --menu "Choose an Option (Only edit Cmdline if you know what you do)" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
      1)
        MSG=""
        MSG+="Commonly used Parameter (Format: Name=Value):\n"
        MSG+=" * \Z4SpectreAll_on=\Zn\n    Enable Spectre and Meltdown protection to mitigate the threat of speculative execution vulnerability.\n"
        MSG+=" * \Z4disable_mtrr_trim=\Zn\n    Disables kernel trim any uncacheable memory out.\n"
        MSG+=" * \Z4intel_idle.max_cstate=1\Zn\n    Set the maximum C-state depth allowed by the intel_idle driver.\n"
        MSG+=" * \Z4pcie_port_pm=off\Zn\n    Disable the power management of the PCIe port.\n"
        MSG+=" * \Z4pci=realloc=off\Zn\n    Disable reallocating PCI bridge resources.\n"
        MSG+=" * \Z4pci=nommconf\Zn\n    Disable the use of Memory-Mapped Configuration for PCI devices(use this parameter cautiously).\n"
        MSG+=" * \Z4pcie_port_pm=off\Zn\n    Turn off the power management of the PCIe port.\n"
        MSG+=" * \Z4scsi_mod.scan=sync\Zn\n    Synchronize scanning of devices on the SCSI bus during system startup(Resolve the disorderly order of HBA disks).\n"
        MSG+=" * \Z4libata.force=noncq\Zn\n    Disable NCQ for all SATA ports.\n"
        MSG+=" * \Z4i915.enable_guc=2\Zn\n    Enable the GuC firmware on Intel graphics hardware.(value: 1,2 or 3)\n"
        MSG+=" * \Z4i915.max_vfs=7\Zn\n     Set the maximum number of virtual functions (VFs) that can be created for Intel graphics hardware.\n"
        MSG+=" * \Z4i915.modeset=0\Zn\n    Disable the kernel mode setting (KMS) feature of the i915 driver.\n"
        MSG+=" * \Z4apparmor.mode=complain\Zn\n    Set the AppArmor security module to complain mode.\n"
        MSG+=" * \Z4acpi_enforce_resources=lax\Zn\n    Resolve the issue of some devices (such as fan controllers) not recognizing or using properly.\n"
        MSG+="\nEnter the Parameter Name and Value you want to add.\n"
        LINENUM=$(($(echo -e "${MSG}" | wc -l) + 10))
        RET=0
        while true; do
          [ "${RET}" -eq 255 ] && MSG+="Commonly used Parameter (Format: Name=Value):\n"
          dialog --clear --backtitle "$(backtitle)" \
            --colors --title "User Cmdline" \
            --form "${MSG}" ${LINENUM:-16} 80 2 "Name:" 1 1 "" 1 10 55 0 "Value:" 2 1 "" 2 10 55 0 \
            2>"${TMP_PATH}/resp"
          RET=$?
          case ${RET} in
            0)
              NAME="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
              VALUE="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
              [[ "${NAME}" = *= ]] && NAME="${NAME%?}"
              [[ "${VALUE}" = =* ]] && VALUE="${VALUE#*=}"
              if [ -z "${NAME//\"/}" ]; then
                dialog --clear --backtitle "$(backtitle)" --title "User Cmdline" \
                  --yesno "Invalid Parameter Name, retry?" 0 0
                [ $? -eq 0 ] && break
              fi
              writeConfigKey "cmdline.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
              break
              ;;
            1)
              break
              ;;
            255)
              break
              ;;
          esac
        done
        resetBuild
        ;;
      2)
        while true; do
          unset CMDLINE
          declare -A CMDLINE
          while IFS=': ' read -r KEY VALUE; do
            [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
          done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
          if [ "${#CMDLINE[@]}" -eq 0 ]; then
            dialog --backtitle "$(backtitle)" --msgbox "No user cmdline to remove" 0 0
            break
          fi
          ITEMS=""
          for I in "${!CMDLINE[@]}"; do
            [ -z "${CMDLINE[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${CMDLINE[${I}]} off "
          done
          dialog --backtitle "$(backtitle)" \
            --checklist "Select cmdline to remove" 0 0 0 ${ITEMS} \
            2>"${TMP_PATH}/resp"
          [ $? -ne 0 ] && break
          resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
          [ -z "${resp}" ] && break
          for I in ${resp}; do
            unset 'CMDLINE[${I}]'
            deleteConfigKey "cmdline.\"${I}\"" "${USER_CONFIG_FILE}"
          done
          resetBuild
        done
        ;;
      3)
        while true; do
          dialog --clear --backtitle "$(backtitle)" \
            --title "CPU Fix" --menu "Fix?" 0 0 0 \
            1 "Install" \
            2 "Uninstall" \
          2>"${TMP_PATH}/resp"
          resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
          [ -z "${resp}" ] && break
          if [ "${resp}" -eq 1 ]; then
            writeConfigKey "cmdline.nmi_watchdog" "0" "${USER_CONFIG_FILE}"
            writeConfigKey "cmdline.tsc" "reliable" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "CPU Fix" \
              --aspect 18 --msgbox "Fix added to Cmdline" 0 0
          elif [ "${resp}" -eq 2 ]; then
            deleteConfigKey "cmdline.nmi_watchdog" "${USER_CONFIG_FILE}"
            deleteConfigKey "cmdline.tsc" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "CPU Fix" \
              --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
          fi
        done
        resetBuild
        ;;
      4)
        while true; do
          dialog --clear --backtitle "$(backtitle)" \
            --title "RAM Fix" --menu "Fix?" 0 0 0 \
            1 "Install" \
            2 "Uninstall" \
          2>"${TMP_PATH}/resp"
          resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
          [ -z "${resp}" ] && break
          if [ "${resp}" -eq 1 ]; then
            writeConfigKey "cmdline.disable_mtrr_trim" "0" "${USER_CONFIG_FILE}"
            writeConfigKey "cmdline.crashkernel" "auto" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "RAM Fix" \
              --aspect 18 --msgbox "Fix added to Cmdline" 0 0
          elif [ "${resp}" -eq 2 ]; then
            deleteConfigKey "cmdline.disable_mtrr_trim" "${USER_CONFIG_FILE}"
            deleteConfigKey "cmdline.crashkernel" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "RAM Fix" \
              --aspect 18 --msgbox "Fix removed from Cmdline" 0 0
          fi
        done
        resetBuild
        ;;
      5)
        while true; do
          dialog --clear --backtitle "$(backtitle)" \
            --title "PCI/IRQ Fix" --menu "Fix?" 0 0 0 \
            1 "Install" \
            2 "Uninstall" \
          2>"${TMP_PATH}/resp"
          resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
          [ -z "${resp}" ] && break
          if [ "${resp}" -eq 1 ]; then
            writeConfigKey "cmdline.pci" "routeirq" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "PCI/IRQ Fix" \
              --aspect 18 --msgbox "Fix added to Cmdline" 0 0
          elif [ "${resp}" -eq 2 ]; then
            deleteConfigKey "cmdline.pci" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "PCI/IRQ Fix" \
              --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
          fi
        done
        resetBuild
        ;;
      6)
        while true; do
          dialog --clear --backtitle "$(backtitle)" \
            --title "C-State Fix" --menu "Fix?" 0 0 0 \
            1 "Install" \
            2 "Uninstall" \
          2>"${TMP_PATH}/resp"
          resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
          [ -z "${resp}" ] && break
          if [ "${resp}" -eq 1 ]; then
            writeConfigKey "cmdline.intel_idle.max_cstate" "1" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "C-State Fix" \
              --aspect 18 --msgbox "Fix added to Cmdline" 0 0
          elif [ "${resp}" -eq 2 ]; then
            deleteConfigKey "cmdline.intel_idle.max_cstate" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "C-State Fix" \
              --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
          fi
        done
        resetBuild
        ;;
      7)
        while true; do
          dialog --clear --backtitle "$(backtitle)" \
            --title "NVMe Optimization" --menu "Optimize?" 0 0 0 \
            1 "Install" \
            2 "Uninstall" \
          2>"${TMP_PATH}/resp"
          resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
          [ -z "${resp}" ] && break
          if [ "${resp}" -eq 1 ]; then
            writeConfigKey "cmdline.nvme.poll_queues" "24" "${USER_CONFIG_FILE}"
            writeConfigKey "cmdline.nvme.write_queues" "8" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "NVMe Optimization" \
              --aspect 18 --msgbox "Fix added to Cmdline" 0 0
          elif [ "${resp}" -eq 2 ]; then
            deleteConfigKey "cmdline.nvme.poll_queues" "${USER_CONFIG_FILE}"
            deleteConfigKey "cmdline.nvme.write_queues" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "NVMe Optimization" \
              --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
          fi
        done
        resetBuild
        ;;
      8)
        while true; do
          dialog --clear --backtitle "$(backtitle)" \
            --title "CPU Performance Optimization" --menu "Optimize?" 0 0 0 \
            1 "Install" \
            2 "Uninstall" \
          2>"${TMP_PATH}/resp"
          resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
          [ -z "${resp}" ] && break
          if [ "${resp}" -eq 1 ]; then
            writeConfigKey "cmdline.mitigations" "off" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "CPU Performance Optimization" \
              --aspect 18 --msgbox "Fix added to Cmdline" 0 0
          elif [ "${resp}" -eq 2 ]; then
            deleteConfigKey "cmdline.mitigations" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "CPU Performance Optimization" \
              --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
          fi
        done
        resetBuild
        ;;
      9)
        while true; do
          rm -f "${TMP_PATH}/opts" >/dev/null
          echo "5 \"Reboot after 5 seconds\"" >>"${TMP_PATH}/opts"
          echo "0 \"No reboot\"" >>"${TMP_PATH}/opts"
          echo "-1 \"Restart immediately\"" >>"${TMP_PATH}/opts"
          dialog --backtitle "$(backtitle)" --colors --title "Kernelpanic" \
            --default-item "${KERNELPANIC}" --menu "Choose a time(seconds)" 0 0 0 --file "${TMP_PATH}/opts" \
            2>"${TMP_PATH}/resp"
          [ $? -ne 0 ] && break
          resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
          [ -z "${resp}" ] && break
          KERNELPANIC=${resp}
          writeConfigKey "kernelpanic" "${KERNELPANIC}" "${USER_CONFIG_FILE}"
        done
        resetBuild
        ;;
      *)
        break
        ;;
    esac
  done
  return
}

###############################################################################
# let user configure synoinfo entries
function synoinfoMenu() {
  # menu loop
  while true; do
    echo "1 \"Add/edit Synoinfo item\""     >"${TMP_PATH}/menu"
    echo "2 \"Delete Synoinfo item(s)\""    >>"${TMP_PATH}/menu"
    dialog --backtitle "$(backtitle)" --title "Synoinfo" --cancel-label "Exit" --menu "Choose an Option (Only edit Synoinfo if you know what you do)" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
      1)
        MSG=""
        MSG+="Commonly used Synoinfo (Format: Name=Value):\n"
        MSG+=" * \Z4maxdisks=??\Zn\n    Maximum number of disks supported.\n"
        MSG+=" * \Z4internalportcfg=0x????\Zn\n    Internal(sata) disks mask.\n"
        MSG+=" * \Z4esataportcfg=0x????\Zn\n    Esata disks mask.\n"
        MSG+=" * \Z4usbportcfg=0x????\Zn\n    USB disks mask.\n"
        MSG+=" * \Z4SasIdxMap=0\Zn\n    Remove SAS reserved Ports.\n"
        MSG+=" * \Z4max_sys_raid_disks=??\Zn\n    Maximum number of system partition(md0) raid disks.\n"
        MSG+=" * \Z4support_glusterfs=yes\Zn\n    GlusterFS in DSM.\n"
        MSG+=" * \Z4support_sriov=yes\Zn\n    SR-IOV Support in DSM.\n"
        MSG+=" * \Z4support_disk_performance_test=yes\Zn\n    Disk Performance Test in DSM.\n"
        MSG+=" * \Z4support_ssd_cache=yes\Zn\n    Enable SSD Cache for unsupported Device.\n"
        #MSG+=" * \Z4support_diffraid=yes\Zn\n    TO-DO.\n"
        #MSG+=" * \Z4support_config_swap=yes\Zn\n    TO-DO.\n"
        MSG+="\nEnter the Parameter Name and Value you want to add.\n"
        LINENUM=$(($(echo -e "${MSG}" | wc -l) + 10))
        RET=0
        while true; do
          [ "${RET}" -eq 255 ] && MSG+="Commonly used Synoinfo (Format: Name=Value):\n"
          dialog --clear --backtitle "$(backtitle)" \
            --colors --title "Synoinfo Entries" \
            --form "${MSG}" ${LINENUM:-16} 80 2 "Name:" 1 1 "" 1 10 55 0 "Value:" 2 1 "" 2 10 55 0 \
            2>"${TMP_PATH}/resp"
          RET=$?
          case ${RET} in
            0)
              NAME="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
              VALUE="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
              [[ "${NAME}" = *= ]] && NAME="${NAME%?}"
              [[ "${VALUE}" = =* ]] && VALUE="${VALUE#*=}"
              if [ -z "${NAME//\"/}" ]; then
                dialog --clear --backtitle "$(backtitle)" --title "User Cmdline" \
                  --yesno "Invalid Parameter Name, retry?" 0 0
                [ $? -eq 0 ] && continue || break
              fi
              writeConfigKey "synoinfo.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
              break
              ;;
            *)
              break
              ;;
          esac
        done
        resetBuild
        ;;
      2)
        # Read synoinfo from user config
        unset SYNOINFO
        declare -A SYNOINFO
        while IFS=': ' read KEY VALUE; do
          [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
        done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")
        if [ "${#SYNOINFO[@]}" -eq 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Synoinfo" \
            --msgbox "No synoinfo entries to remove" 0 0
          continue
        fi
        rm -f "${TMP_PATH}/opts"
        for I in ${!SYNOINFO[@]}; do
          echo "\"${I}\" \"${SYNOINFO[${I}]}\" \"off\"" >>"${TMP_PATH}/opts"
        done
        dialog --backtitle "$(backtitle)" --title "Synoinfo" \
          --checklist "Select synoinfo entry to remove" 0 0 0 --file "${TMP_PATH}/opts" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
        [ -z "${resp}" ] && continue
        for I in ${resp}; do
          unset SYNOINFO[${I}]
          deleteConfigKey "synoinfo.\"${I}\"" "${USER_CONFIG_FILE}"
        done
        resetBuild
        ;;
      *)
        break
        ;;
    esac
  done
  return
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  dialog --backtitle "$(backtitle)" --title "Keymap" --default-item "${LAYOUT}" --no-items \
    --cancel-label "Exit" --menu "Choose a Layout" 0 0 0 \
    "azerty" "bepo" "carpalx" "colemak" \
    "dvorak" "fgGIod" "neo" "olpc" "qwerty" "qwertz" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  LAYOUT="$(cat "${TMP_PATH}/resp")"
  OPTIONS=""
  while read -r KM; do
    OPTIONS+="${KM::-7} "
  done < <(cd /usr/share/keymaps/i386/${LAYOUT}; ls *.map.gz)
  dialog --backtitle "$(backtitle)" --no-items --default-item "${KEYMAP}" \
    --menu "Choice a keymap" 0 0 0 ${OPTIONS} \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  KEYMAP=${resp}
  writeConfigKey "layout" "${LAYOUT}" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  loadkeys /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz
  return
}

###############################################################################
# Shows storagepanel menu to user
function storagepanelMenu() {
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    while true; do
      STORAGEPANELUSER="$(readConfigKey "addons.storagepanel" "${USER_CONFIG_FILE}")"
      [ -n "${STORAGEPANELUSER}" ] && DISKPANELUSER="$(echo ${STORAGEPANELUSER} | cut -d' ' -f1)" || DISKPANELUSER="RACK_24_Bay"
      [ -n "${STORAGEPANELUSER}" ] && M2PANELUSER="$(echo ${STORAGEPANELUSER} | cut -d' ' -f2)" || M2PANELUSER="1X4"
      ITEMS="$(echo -e "RACK_2_Bay \nRACK_4_Bay \nRACK_8_Bay \nRACK_12_Bay \nRACK_16_Bay \nRACK_24_Bay \nRACK_60_Bay \nTOWER_1_Bay \nTOWER_2_Bay \nTOWER_4_Bay \nTOWER_6_Bay \nTOWER_8_Bay \nTOWER_12_Bay \n")"
      dialog --backtitle "$(backtitle)" --title "StoragePanel" \
        --default-item "${DISKPANELUSER}" --no-items --menu "Choose a Disk Panel" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && break
      STORAGE=${resp}
      ITEMS="$(echo -e "1X2 \n1X4 \n1X8 \n")"
      dialog --backtitle "$(backtitle)" --title "StoragePanel" \
        --default-item "${M2PANELUSER}" --no-items --menu "Choose a M.2 Panel" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && break
      M2PANEL=${resp}
      STORAGEPANEL="${STORAGE} ${M2PANEL}"
      writeConfigKey "addons.storagepanel" "${STORAGEPANEL}" "${USER_CONFIG_FILE}"
      break
    done
    resetBuild
  fi
  return
}

###############################################################################
# Shows backup menu to user
function backupMenu() {
  NEXT="1"
  USERID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
  ARC_OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  while true; do
    if [ -n "${USERID}" ] && [ "${ARC_OFFLINE}" != "true" ] && [ "${CONFDONE}" = "true" ]; then
      dialog --backtitle "$(backtitle)" --title "Backup" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
        1 "Restore Arc Config (from DSM)" \
        2 "Restore Hardware Key (local)" \
        3 "Backup Hardware Key (local)" \
        4 "Restore Arc Config (from Online)" \
        5 "Backup Arc Config (to Online)" \
        2>"${TMP_PATH}/resp"
    elif [ -n "${USERID}" ] && [ "${ARC_OFFLINE}" != "true" ]; then
      dialog --backtitle "$(backtitle)" --title "Backup" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
        1 "Restore Arc Config (from DSM)" \
        2 "Restore Hardware Key (local)" \
        3 "Backup Hardware Key (local)" \
        4 "Restore Arc Config (from Online)" \
        2>"${TMP_PATH}/resp"
    else
      dialog --backtitle "$(backtitle)" --title "Backup" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
        1 "Restore Arc Config (from DSM)" \
        2 "Restore Hardware Key (local)" \
        3 "Backup Hardware Key (local)" \
        2>"${TMP_PATH}/resp"
    fi
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
      1)
        DSMROOTS="$(findDSMRoot)"
        if [ -z "${DSMROOTS}" ]; then
          dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
            --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
          return
        fi
        mkdir -p "${TMP_PATH}/mdX"
        for I in ${DSMROOTS}; do
          #fixDSMRootPart "${I}"
          T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
          mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
          [ $? -ne 0 ] && continue
          MODEL=""
          PRODUCTVER=""
          if [ -f "${TMP_PATH}/mdX/usr/arc/backup/p1/user-config.yml" ]; then
            cp -f "${TMP_PATH}/mdX/usr/arc/backup/p1/user-config.yml" "${USER_CONFIG_FILE}"
            sleep 2
            MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
            PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
            if [ -n "${MODEL}" ] && [ -n "${PRODUCTVER}" ]; then
              TEXT="Config found:\nModel: ${MODEL}\nVersion: ${PRODUCTVER}"
              SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
              TEXT+="\nSerial: ${SN}"
              ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
              TEXT+="\nArc Patch: ${ARC_PATCH}"
              dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
                --aspect 18 --msgbox "${TEXT}" 0 0
              PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
              DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
              CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
              resetBuild
              break
            fi
          fi
          umount "${TMP_PATH}/mdX"
        done
        rm -rf "${TMP_PATH}/mdX" 2>/dev/null
        if [ -f "${USER_CONFIG_FILE}" ]; then
          PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          if [ -n "${PRODUCTVER}" ]; then
            PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
            KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
            is_in_array "${PLATFORM}" "${KVER5L[@]}" && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
            if [ -n "${PLATFORM}" ] && [ -n "${KVERP}" ]; then
              writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
              mergeConfigModules "$(getAllModules "${PLATFORM}" "${KVERP}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
            fi
          fi
        fi
        dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
          --aspect 18 --infobox "Restore successful! -> Reload Arc Init now" 5 50
        sleep 2
        rm -f "${HOME}/.initialized" && exec init.sh
        ;;
      2)
        dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" \
          --msgbox "Upload the machine.key or machine.key.tar.gz file to ${PART3_PATH}/users\nand press OK after the upload is done." 0 0
        [ $? -ne 0 ] && return 1
        if [ -f "${PART3_PATH}/users/machine.key.tar.gz" ]; then
          tar -xzf "${PART3_PATH}/users/machine.key.tar.gz" -C "${PART2_PATH}" machine.key 2>/dev/null
          if [ -f "${PART2_PATH}/machine.key" ]; then
            dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
              --msgbox "Encryption Key restore successful!" 0 0
            rm -f "${PART3_PATH}/users/machine.key.tar.gz"
          else
            dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" \
              --msgbox "Extraction failed! machine.key not found in archive." 0 0
            return 1
          fi
        elif [ -f "${PART3_PATH}/users/machine.key" ]; then
          cp -f "${PART3_PATH}/users/machine.key" "${PART2_PATH}/machine.key"
          if [ -f "${PART2_PATH}/machine.key" ]; then
            dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
              --msgbox "Encryption Key restore successful!" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" \
              --msgbox "File not found!" 0 0
            return 1
          fi
        else
          dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" \
            --msgbox "File not found!" 0 0
          return 1
        fi
        return
        ;;
      3)
        dialog --backtitle "$(backtitle)" --title "Backup Encryption Key" \
          --msgbox "To backup the Encryption Key press OK." 0 0
        [ $? -ne 0 ] && return 1
        
        if [ -f "${PART2_PATH}/machine.key" ]; then
          mkdir -p /var/www/data
          tar -czf /var/www/data/machine.key.tar.gz -C "${PART2_PATH}" machine.key
          URL="http://${IPCON}:${HTTPPORT:-7080}/machine.key.tar.gz"
          MSG="Please use ${URL} to download the machine.key.tar.gz archive."
        else
          MSG="File not found!"
        fi
        dialog --backtitle "$(backtitle)" --colors --title "Backup Encryption Key" \
          --msgbox "${MSG}" 0 0
        if [ "${MSG}" = "File not found!" ]; then
          return 1
        fi
        return
        ;;
      4)
        [ -f "${USER_CONFIG_FILE}" ] && mv -f "${USER_CONFIG_FILE}" "${USER_CONFIG_FILE}.bak"
        HWID="$(genHWID)"
        if curl -skL --http1.1 "https://arc.auxxxilium.tech?cdown=${HWID}" -o "${USER_CONFIG_FILE}" 2>/dev/null; then
          dialog --backtitle "$(backtitle)" --title "Online Restore" --msgbox "Online Restore successful!" 5 40
        else
          dialog --backtitle "$(backtitle)" --title "Online Restore" --msgbox "Online Restore failed!" 5 40
          [ -f "${USER_CONFIG_FILE}.bak" ] && mv -f "${USER_CONFIG_FILE}.bak" "${USER_CONFIG_FILE}"
        fi
        MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
        PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
        if [ -n "${MODEL}" ] && [ -n "${PRODUCTVER}" ]; then
          TEXT="Config found:\nModel: ${MODEL}\nVersion: ${PRODUCTVER}"
          SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
          TEXT+="\nSerial: ${SN}"
          ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          TEXT+="\nArc Patch: ${ARC_PATCH}"
          dialog --backtitle "$(backtitle)" --title "Online Restore" \
            --aspect 18 --msgbox "${TEXT}" 0 0
          PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
          DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
          CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
          resetBuild
        fi
        dialog --backtitle "$(backtitle)" --title "Online Restore" \
          --aspect 18 --infobox "Restore successful! -> Reload Arc Init now" 5 50
        sleep 2
        rm -f "${HOME}/.initialized" && exec init.sh
        ;;
      5)
        HWID="$(genHWID)"
        curl -sk -X POST -F "file=@${USER_CONFIG_FILE}" "https://arc.auxxxilium.tech?cup=${HWID}&userid=${USERID}" 2>/dev/null
        if [ $? -eq 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Online Backup" --msgbox "Config Online Backup successful!" 5 45
        else
          dialog --backtitle "$(backtitle)" --title "Online Backup" --msgbox "Config Online Backup failed!" 5 45
          return 1
        fi
        return 0
        ;;
      *)
        break
        ;;
    esac
  done
  return
}

###############################################################################
# Shows update menu to user
function updateMenu() {
  NEXT="1"
  BETA="false"
  while true; do
    if [ "${ARC_OFFLINE}" = "false" ]; then
      dialog --backtitle "$(backtitle)" --title "Update" --colors --cancel-label "Exit" \
        --menu "Choose an Option" 0 0 0 \
        1 "Update Loader (incl. Dependencies) \Z1(no reflash)\Zn" \
        2 "Upgrade Loader (incl. Dependencies) \Z1(reflash!)\Zn" \
        3 "Update Dependencies \Z1(maybe not stable)\Zn" \
        2>"${TMP_PATH}/resp"
    else
      dialog --backtitle "$(backtitle)" --title "Update" --colors --cancel-label "Exit" \
        --menu "Choose an Option" 0 0 0 \
        1 "Update Loader (incl. Dependencies) \Z1(no reflash)\Zn" \
        2 "Upgrade Loader (incl. Dependencies) \Z1(reflash!)\Zn" \
        2>"${TMP_PATH}/resp"
    fi
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
      1)
        # Ask for Tag
        if [ "${ARC_OFFLINE}" = "false" ]; then
          TAG="$(curl -m 10 -skL "${API_URL}" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
          BETATAG="$(curl -m 10 -skL "${BETA_API_URL}" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
          dialog --clear --backtitle "$(backtitle)" --title "Update Loader" \
            --menu "Current: ${ARC_VERSION}" 7 50 0 \
            1 "Latest ${TAG}" \
            2 "Beta ${BETATAG}" \
            3 "Select Version" \
            4 "Upload .zip File" \
            2>"${TMP_PATH}/opts"
        else
          dialog --clear --backtitle "$(backtitle)" --title "Update Loader" \
            --menu "Current: ${ARC_VERSION}" 7 50 0 \
            4 "Upload .zip File" \
            2>"${TMP_PATH}/opts"
        fi
        [ $? -ne 0 ] && break
        opts="$(cat "${TMP_PATH}/opts")"
        if [ "${opts}" -eq 1 ]; then
          [ -z "${TAG}" ] && return 1
          updateLoader "${BETA}" "${TAG}"
        elif [ "${opts}" -eq 2 ]; then
          [ -z "${BETATAG}" ] && return 1
          BETA="true"
          updateLoader "${BETA}" "${BETATAG}"
        elif [ "${opts}" -eq 3 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Loader" \
          --inputbox "Which Version?" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
          updateLoader "${BETA}" "${TAG}"
        elif [ "${opts}" -eq 4 ]; then
          mkdir -p "/${TMP_PATH}/update"
          dialog --backtitle "$(backtitle)" --title "Update Loader" \
            --msgbox "Upload the update-*.zip File to /${TMP_PATH}/update\nand press OK after upload is done." 0 0
          [ $? -ne 0 ] && return 1
          UPDATEFOUND="false"
          for UPDATEFILE in /${TMP_PATH}/update/update-*.zip; do
            if [ -f "${UPDATEFILE}" ]; then
              mv -f "${UPDATEFILE}" "${TMP_PATH}/update.zip"
              TAG="zip"
              UPDATEFOUND="true"
              break
            fi
          done
          if [ "${UPDATEFOUND}" = "false" ]; then
            dialog --backtitle "$(backtitle)" --title "Update Loader" \
              --msgbox "File not found!" 0 0
            return 1
          fi
          updateLoader "${TAG}"
        fi
        ;;
      2)
        # Ask for Tag
        if [ "${ARC_OFFLINE}" = "false" ]; then
          TAG="$(curl -m 10 -skL "${API_URL}" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
          BETATAG="$(curl -m 10 -skL "${BETA_API_URL}" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
          dialog --clear --backtitle "$(backtitle)" --title "Upgrade Loader" --colors \
            --menu "\Z1Loader will be reset to defaults after upgrade!\nIf you use Hardware encryption, your key will be deleted!\Zn\nCurrent: ${ARC_VERSION}" 10 65 0 \
            1 "Latest ${TAG}" \
            2 "Select Version" \
            3 "Upload .zip File" \
            2>"${TMP_PATH}/opts"
        else
          dialog --clear --backtitle "$(backtitle)" --title "Upgrade Loader" --colors \
            --menu "\Z1Loader will be reset to default after upgrade!\nIf you use Hardware encryption, your key will be deleted!\Zn\nCurrent: ${ARC_VERSION}" 10 65 0 \
            3 "Upload .zip File" \
            2>"${TMP_PATH}/opts"
        fi
        [ $? -ne 0 ] && break
        opts="$(cat "${TMP_PATH}/opts")"
        if [ "${opts}" -eq 1 ]; then
          [ -z "${TAG}" ] && return 1
          upgradeLoader "${TAG}"
        elif [ "${opts}" -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --inputbox "Which Version?" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
          upgradeLoader "${TAG}"
        elif [ "${opts}" -eq 3 ]; then
          mkdir -p "/${TMP_PATH}/update"
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
            --msgbox "Upload the arc-*.zip File to /${TMP_PATH}/update\nand press OK after upload is done." 0 0
          [ $? -ne 0 ] && return 1
          UPDATEFOUND="false"
          for UPDATEFILE in /${TMP_PATH}/update/arc-*.zip; do
            if [ -f "${UPDATEFILE}" ]; then
              mv -f "${UPDATEFILE}" "${TMP_PATH}/arc.img.zip"
              TAG="zip"
              UPDATEFOUND="true"
              break
            fi
          done
          if [ "${UPDATEFOUND}" = "false" ]; then
            dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
              --msgbox "File not found!" 0 0
            return 1
          fi
          upgradeLoader "${TAG}"
        fi
        ;;
      3)
        dependenciesUpdate
        ;;
      *)
        break
        ;;
    esac
  done
  return
}

###############################################################################
# Show Storagemenu to user
function storageMenu() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  # Get Portmap for Loader
  getmap
  if [ "${DT}" = "false" ] && [ "${SATACONTROLLER}" -gt 0 ]; then
    getmapSelection
  fi
  resetBuild
  return
}

###############################################################################
# Show Storagemenu to user
function networkMenu() {
  # Get Network Config for Loader
  getnet
  resetBuild
  return
}

###############################################################################
# Shows Systeminfo to user
function sysinfo() {
  # Get System Informations
  [ -d /sys/firmware/efi ] && BOOTSYS="UEFI" || BOOTSYS="BIOS"
  USERID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
  CPU="$(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}')"
  BOARD="$(getBoardName)"
  RAMTOTAL="$(awk '/MemTotal:/ {printf "%.0f\n", $2 / 1024 / 1024 + 0.5}' /proc/meminfo 2>/dev/null)"
  [ -z "${RAMTOTAL}" ] && RAMTOTAL="N/A"
  GOVERNOR="$(readConfigKey "governor" "${USER_CONFIG_FILE}")"
  SECURE=$(dmesg 2>/dev/null | grep -i "Secure Boot" | awk -F'] ' '{print $2}')
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  ETHN=$(echo ${ETHX} | wc -w)
  HWID="$(genHWID)"
  ARC_BACKUP="$(readConfigKey "arc.backup" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
    DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
    KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
    ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
    ADDONS_RAW="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
    if [ -n "${ADDONS_RAW}" ]; then
      ADDONSINFO="$(echo "${ADDONS_RAW}" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')"
    else
      ADDONSINFO=""
    fi
    REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
    if [ "${REMAP}" = "acports" ] || [ "${REMAP}" = "maxports" ]; then
      PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
      DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" = "remap" ]; then
      PORTMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" = "ahci" ]; then
      AHCIPORTMAP="$(readConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}")"
    fi
    USERCMDLINEINFO_RAW="$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")"
    USERCMDLINEINFO="$(echo "${USERCMDLINEINFO_RAW}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')"
    USERSYNOINFO_RAW="$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")"
    USERSYNOINFO="$(echo "${USERSYNOINFO_RAW}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')"
    BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  fi
  DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
  CONFIGVER="$(readConfigKey "arc.version" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
  USBMOUNT="$(readConfigKey "usbmount" "${USER_CONFIG_FILE}")"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  HARDDRIVES="$(readConfigKey "device.harddrives" "${USER_CONFIG_FILE}")"
  DRIVES="$(readConfigKey "device.drives" "${USER_CONFIG_FILE}")"
  MODULESINFO="$(lsmod | awk -F' ' '{print $1}' | grep -v 'Module')"
  MODULESVERSION="$(cat "${MODULES_PATH}/VERSION")"
  ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")"
  LKMVERSION="$(cat "${LKMS_PATH}/VERSION")"
  CONFIGSVERSION="$(cat "${CONFIGS_PATH}/VERSION")"
  PATCHESVERSION="$(cat "${PATCH_PATH}/VERSION")"
  TIMEOUT=5
  # Print System Informations
  TEXT="\n\Z4> System: ${MEV} | ${BOOTSYS} | ${BUS}\Zn"
  TEXT+="\n"
  TEXT+="\n  Board: \Zb${BOARD}\Zn"
  TEXT+="\n  CPU: \Zb${CPU}\Zn"
  if [ $(lspci -d ::300 | wc -l) -gt 0 ]; then
    GPUNAME=""
    for PCI in $(lspci -d ::300 | awk '{print $1}'); do
      GPUNAME+="$(lspci -s ${PCI} | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')"
    done
    TEXT+="\n  GPU: \Zb${GPUNAME}\Zn"
  fi
  TEXT+="\n  Memory: \Zb$((${RAMTOTAL}))GB\Zn"
  TEXT+="\n  AES: \Zb${AESSYS}\Zn"
  TEXT+="\n  CPU Scaling | Governor: \Zb${CPUFREQ} | ${GOVERNOR}\Zn"
  TEXT+="\n  Secure Boot: \Zb${SECURE}\Zn"
  TEXT+="\n  Bootdisk: \Zb${LOADER_DISK}\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4> Network: ${ETHN} NIC\Zn"
  for N in ${ETHX}; do
    TEXT+="\n"
    COUNT=0
    DRIVER="$(basename "$(realpath "/sys/class/net/${N}/device/driver" 2>/dev/null)" 2>/dev/null)"
    MAC="$(cat "/sys/class/net/${N}/address" 2>/dev/null)"
    PCIDN="$(awk -F= '/PCI_SLOT_NAME/ {print $2}' "/sys/class/net/${N}/device/uevent" 2>/dev/null)"
    LNAME="$(lspci -s ${PCIDN} 2>/dev/null | sed "s/.*: //")"
    TEXT+="\n  ${N}: ${LNAME:-"unspecified"}"
    while true; do
      if [ -z "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
        TEXT+="\n  ${DRIVER} (${MAC}): \ZbDOWN\Zn"
        break
      fi
      if [ "0" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
        TEXT+="\n  ${DRIVER} (${MAC}): \ZbNOT CONNECTED\Zn"
        break
      fi
      if [ "${COUNT}" -ge "${TIMEOUT}" ]; then
        TEXT+="\n  ${DRIVER} (${MAC}): \ZbTIMEOUT\Zn"
        break
      fi
      COUNT=$((${COUNT} + 1))
      IP="$(getIP "${N}")"
      if [ -n "${IP}" ]; then
        SPEED="$(ethtool ${N} 2>/dev/null | grep "Speed:" | awk '{print $2}')"
        if [[ "${IP}" =~ ^169\.254\..* ]]; then
          TEXT+="\n  ${DRIVER} (${SPEED} | ${MAC}): \ZbLINK LOCAL (No DHCP server found.)\Zn"
        else
          TEXT+="\n  ${DRIVER} (${SPEED} | ${MAC}): \Zb${IP}\Zn"
        fi
        break
      fi
      sleep 1
    done
  done
  # Print Config Informations
  TEXT+="\n\n\Z4> Arc: ${ARC_VERSION} (${ARC_BUILD})\Zn"
  TEXT+="\n"
  TEXT+="\n  Subversion: \ZbAddons ${ADDONSVERSION} | Configs ${CONFIGSVERSION} | LKM ${LKMVERSION} | Modules ${MODULESVERSION} | Patches ${PATCHESVERSION}\Zn"
  TEXT+="\n  Config | Build: \Zb${CONFDONE} | ${BUILDDONE}\Zn"
  TEXT+="\n  Config Version: \Zb${CONFIGVER}\Zn"
  TEXT+="\n  HWID registered: \Zb$( [ -n "${USERID}" ] && echo "true" || echo "false" )\Zn"
  TEXT+="\n  Offline Mode: \Zb${ARC_OFFLINE}\Zn"
  TEXT+="\n"
  if [ "${CONFDONE}" = "true" ]; then
    TEXT+="\n\Z4> DSM ${PRODUCTVER} (${BUILDNUM}): ${MODEL}\Zn"
    TEXT+="\n"
    TEXT+="\n  Kernel | LKM: \Zb${KVER} | ${LKM}\Zn"
    TEXT+="\n  Platform | DeviceTree: \Zb${PLATFORM} | ${DT}\Zn"
    TEXT+="\n  Arc Patch: \Zb${ARC_PATCH}\Zn"
    TEXT+="\n  Arc Backup: \Zb${ARC_BACKUP}\Zn"
    TEXT+="\n  Kernelload: \Zb${KERNELLOAD}\Zn"
    TEXT+="\n  Directboot: \Zb${DIRECTBOOT}\Zn"
    TEXT+="\n  eMMC Boot: \Zb${EMMCBOOT}\Zn"
    TEXT+="\n  Addons selected: \Zb${ADDONSINFO}\Zn"
  else
    TEXT+="\n  Config not completed!"
    TEXT+="\n"
  fi
  TEXT+="\n  Modules loaded: \Zb${MODULESINFO}\Zn"
  if [ "${CONFDONE}" = "true" ]; then
    [ -n "${USERCMDLINEINFO}" ] && TEXT+="\n  User Cmdline: \Zb${USERCMDLINEINFO}\Zn"
    TEXT+="\n  User Synoinfo: \Zb${USERSYNOINFO}\Zn"
  fi
  TEXT+="\n"
  TEXT+="\n\Z4> Settings\Zn"
  TEXT+="\n"
  if [[ "${REMAP}" = "acports" || "${REMAP}" = "maxports" ]]; then
    TEXT+="\n  SataPortMap | DiskIdxMap: \Zb${PORTMAP} | ${DISKMAP}\Zn"
  elif [ "${REMAP}" = "remap" ]; then
    TEXT+="\n  SataRemap: \Zb${PORTMAP}\Zn"
  elif [ "${REMAP}" = "ahci" ]; then
    TEXT+="\n  AhciRemap: \Zb${AHCIPORTMAP}\Zn"
  elif [ "${REMAP}" = "user" ]; then
    TEXT+="\n  PortMap: \Zb"User"\Zn"
    [ -n "${PORTMAP}" ] && TEXT+="\n  SataPortmap: \Zb${PORTMAP}\Zn"
    [ -n "${DISKMAP}" ] && TEXT+="\n  DiskIdxMap: \Zb${DISKMAP}\Zn"
    [ -n "${PORTREMAP}" ] && TEXT+="\n  SataRemap: \Zb${PORTREMAP}\Zn"
    [ -n "${AHCIPORTREMAP}" ] && TEXT+="\n  AhciRemap: \Zb${AHCIPORTREMAP}\Zn"
  fi
  if [ "${DT}" = "true" ]; then
    TEXT+="\n  Hotplug: \Zb${HDDSORT}\Zn"
  else
    TEXT+="\n  USB Mount: \Zb${USBMOUNT}\Zn"
  fi
  TEXT+="\n"
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS // 100=SCSI // c03=USB
  TEXT+="\n\Z4> Storage\Zn"
  TEXT+="\n"
  TEXT+="\n  Additional Controller: \Zb${EXTERNALCONTROLLER}\Zn"
  TEXT+="\n  Disks | Internal: \Zb${DRIVES} | ${HARDDRIVES}\Zn"
  TEXT+="\n"
  # Get Information for Sata Controller
  NUMPORTS=0
  if [ $(lspci -d ::106 2>/dev/null | wc -l) -gt 0 ]; then
    TEXT+="\n  SATA Controller:\n"
    for PCI in $(lspci -d ::106 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      TEXT+="\Zb  ${NAME}\Zn\n  Ports: "
      PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      for P in ${PORTS}; do
        if lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep -q "\[${P}:"; then
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
      TEXT+="\n  Ports with color \Z1\Zbred\Zn as DUMMY, color \Z2\Zbgreen\Zn has a Disk connected.\n"
    done
  fi
  [ $(lspci -d ::104 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  RAID Controller:\n"
  for PCI in $(lspci -d ::104 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    TEXT+="\Zb   ${NAME}\Zn\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::107 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  HBA Controller:\n"
  for PCI in $(lspci -d ::107 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    TEXT+="\Zb   ${NAME}\Zn\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::100 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  SCSI Controller:\n"
  for PCI in $(lspci -d ::100 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/* 2>/dev/null | grep "${PCI}" | wc -l)
    [ "${PORTNUM}" -eq 0 ] && continue
    TEXT+="\Zb   ${NAME}\Zn\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(ls -l /sys/class/scsi_host 2>/dev/null | grep usb | wc -l) -gt 0 ] && TEXT+="\n  USB Controller:\n"
  for PCI in $(lspci -d ::c03 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    [ "${PORTNUM}" -eq 0 ] && continue
    TEXT+="\Zb   ${NAME}\Zn\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(ls -l /sys/block/mmc* 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  MMC Controller:\n"
  for PCI in $(lspci -d ::805 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/mmc* 2>/dev/null | grep "${PCI}" | wc -l)
    [ "${PORTNUM}" -eq 0 ] && continue
    TEXT+="\Zb   ${NAME}\Zn\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::108 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  NVME Controller:\n"
  for PCI in $(lspci -d ::108 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/nvme 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[N:${PORT}:" | wc -l)
    TEXT+="\Zb   ${NAME}\Zn\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  if [ $(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep 'vmbus:acpi' | wc -l) -gt 0 ]; then
    TEXT+="\n  VMBUS Controller:\n"
    NAME="vmbus:acpi"
    PORTNUM="$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep 'vmbus:acpi' | wc -l)"
    TEXT+="\Zb   ${NAME}\Zn\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  fi
  TEXT+="\n  Total Disks: \Zb${NUMPORTS}\Zn"
  if [ -n "${USERID}" ] && [ "${CONFDONE}" = "true" ]; then
    echo -e "${TEXT}" >"${TMP_PATH}/sysinfo.yml"
    while true; do
      dialog --backtitle "$(backtitle)" --colors --ok-label "Exit" --help-button --help-label "Show Cmdline" \
        --extra-button --extra-label "Upload" --title "Sysinfo" --msgbox "${TEXT}" 0 0
      RET=$?
      case ${RET} in
        2)
          getCMDline
          ;;
        3)
          uploadDiag
          ;;
        *)
          return 0
          break
          ;;
      esac
    done
  else
    while true; do
      dialog --backtitle "$(backtitle)" --colors --ok-label "Exit" --help-button --help-label "Show Cmdline" \
        --title "Sysinfo" --msgbox "${TEXT}" 0 0
      RET=$?
      case ${RET} in
        2)
          getCMDline
          ;;
        *)
          return 0
          break
          ;;
      esac
    done
  fi
  return
}

function getCMDline () {
  if [ -f "${PART1_PATH}/cmdline.yml" ]; then
    GETCMDLINE=$(cat "${PART1_PATH}/cmdline.yml")
    dialog --backtitle "$(backtitle)" --title "Sysinfo Cmdline" --msgbox "${GETCMDLINE}" 10 100
  else
    dialog --backtitle "$(backtitle)" --title "Sysinfo Cmdline" --msgbox "Cmdline File found!" 0 0
  fi
  return
}

function uploadDiag () {
  if [ -f "${TMP_PATH}/sysinfo.yml" ]; then
    HWID="$(genHWID)"
    curl -sk -m 20 -X POST -F "file=@${TMP_PATH}/sysinfo.yml" "https://arc.auxxxilium.tech?sysinfo=${HWID}&userid=${USERID}" 2>/dev/null
    if [ $? -eq 0 ]; then
      dialog --backtitle "$(backtitle)" --title "Sysinfo Upload" --msgbox "Your Code: ${HWID}" 5 40
    else
      dialog --backtitle "$(backtitle)" --title "Sysinfo Upload" --msgbox "Failed to upload diag file!" 0 0
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Sysinfo Upload" --msgbox "No Diag File found!" 0 0
  fi
  return
}

###############################################################################
# Shows Networkdiag to user
function networkdiag() {
  (
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  for N in ${ETHX}; do
    echo
    DRIVER="$(basename "$(realpath "/sys/class/net/${N}/device/driver" 2>/dev/null)" 2>/dev/null)"
    echo -e "Interface: ${N} (${DRIVER})"
    if [ "0" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
      echo -e "Link: NOT CONNECTED"
      continue
    fi
    if [ -z "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
      echo -e "Link: DOWN"
      continue
    fi
    echo -e "Link: CONNECTED"
    addr="$(getIP "${N}")"
    netmask=$(ifconfig "${N}" | grep inet | grep 255 | awk '{print $4}' | cut -f2 -d':')
    echo -e "IP Address: ${addr}"
    echo -e "Netmask: ${netmask}"
    echo
    gateway=$(route -n | grep 'UG[ \t]' | awk '{print $2}' | head -n 1)
    echo -e "Gateway: ${gateway}"
    dnsserver=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
    echo -e "DNS Server:\n${dnsserver}"
    echo
    if [ "${ARC_OFFLINE}" = "true" ]; then
      echo -e "Offline Mode: ${ARC_OFFLINE}"
    else
      websites=("github.com" "auxxxilium.tech")
      for website in "${websites[@]}"; do
        if ping -I "${N}" -c 1 "${website}" &> /dev/null; then
          echo -e "Connection to ${website} is successful."
        else
          echo -e "Connection to ${website} failed."
        fi
      done
      echo
      HWID="$(genHWID)"
      USERIDAPI="$(curl --interface "${N}" -skL -m 10 "https://arc.auxxxilium.tech?hwid=${HWID}" 2>/dev/null)"
      if [[ $? -ne 0 || -z "${USERIDAPI}" ]]; then
        echo -e "Arc UserID API not reachable!"
      else
        echo -e "Arc UserID API reachable!"
      fi
      GITHUBAPI=$(curl --interface "${N}" -skL -m 10 "${API_URL}" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1 2>/dev/null)
      if [[ $? -ne 0 || -z "${GITHUBAPI}" ]]; then
        echo -e "Github API not reachable!"
      else
        echo -e "Github API reachable!"
      fi
      if [ "${CONFDONE}" = "true" ]; then
        SYNOAPI=$(curl --interface "${N}" -skL -m 10 "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}" | jq -r '.info.system.detail[0].items[0].files[0].url' 2>/dev/null)
        if [[ $? -ne 0 || -z "${SYNOAPI}" ]]; then
          echo -e "Syno API not reachable!"
        else
          echo -e "Syno API reachable!"
        fi
      else
        echo -e "For Syno API Checks you need to configure Loader first!"
      fi
    fi
  done
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Networkdiag" \
    --programbox "Doing the some Diagnostics..." 50 120
  return
}

###############################################################################
# Shows Credits to user
function credits() {
  TEXT=""
  TEXT+="\n\Z4> Arc Loader:\Zn"
  TEXT+="\n  Github: \Zbhttps://github.com/AuxXxilium\Zn"
  TEXT+="\n  Web: \Zbhttps://auxxxilium.tech | https://xpenology.tech\Zn"
  TEXT+="\n  Wiki: \Zbhttps://xpenology.tech/wiki\Zn"
  TEXT+="\n  FAQ: \Zbhttps://xpenology.tech/faq\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Developer:\Zn"
  TEXT+="\n   Arc Loader: \ZbAuxXxilium / Fulcrum\Zn"
  TEXT+="\n   Arc Basesystem: \ZbVisionZ / AuxXxilium\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Based on:\Zn"
  TEXT+="\n   Redpill: \ZbTTG / Pocopico\Zn"
  TEXT+="\n   ARPL/RR: \Zbfbelavenuto / wjz304\Zn"
  TEXT+="\n   Others: \Zb007revad / PeterSuh-Q3 / more...\Zn"
  TEXT+="\n   DSM: \ZbSynology Inc.\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Note:\Zn"
  TEXT+="\n   DSM are licensed to Synology Inc."
  TEXT+="\n"
  TEXT+="\n   This Loader is FREE and it is forbidden"
  TEXT+="\n   to sell Arc or Parts of it."
  TEXT+="\n"
  TEXT+="\n   Commercial use is not permitted!"
  TEXT+="\n"
  dialog --backtitle "$(backtitle)" --colors --title "Credits" \
    --msgbox "${TEXT}" 0 0
  return
}

###############################################################################
# Setting Static IP for Loader
function staticIPMenu() {
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  IPCON=""
  for N in ${ETHX}; do
    MACR="$(cat "/sys/class/net/${N}/address" 2>/dev/null | sed 's/://g')"
    IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
    IFS='/' read -r -a IPRA <<<"${IPR}"

    MSG="Set to ${N}(${MACR}: (Delete if empty)"
    while true; do
      dialog --backtitle "$(backtitle)" --title "StaticIP" \
        --form "${MSG}" 10 60 4 "address" 1 1 "${IPRA[0]}" 1 9 36 16 "netmask" 2 1 "${IPRA[1]}" 2 9 36 16 "gateway" 3 1 "${IPRA[2]}" 3 9 36 16 "dns" 4 1 "${IPRA[3]}" 4 9 36 16 \
        2>"${TMP_PATH}/resp"
      RET=$?
      case ${RET} in
      0)
        address="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
        netmask="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
        gateway="$(sed -n '3p' "${TMP_PATH}/resp" 2>/dev/null)"
        dnsname="$(sed -n '4p' "${TMP_PATH}/resp" 2>/dev/null)"
        (
          if [ -z "${address}" ]; then
            if [ -n "$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")" ]; then
              echo "Deleting IP for ${N}(${MACR})"
              if [ "1" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
                ip addr flush dev ${N}
              fi
              deleteConfigKey "network.${MACR}" "${USER_CONFIG_FILE}"
              sleep 1
            fi
          else
            echo "Setting IP for ${N}(${MACR}) to ${address}/${netmask}/${gateway}/${dnsname}"
            writeConfigKey "network.${MACR}" "${address}/${netmask}/${gateway}/${dnsname}" "${USER_CONFIG_FILE}"
            if [ "1" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
              ip addr flush dev ${N}
              ip addr add ${address}/${netmask:-"255.255.255.0"} dev ${N}
              if [ -n "${gateway}" ]; then
                ip route add default via ${gateway} dev ${N}
              fi
              if [ -n "${dnsname:-${gateway}}" ]; then
                sed -i '/^nameserver /d' /etc/resolv.conf
                echo "nameserver ${dnsname:-${gateway}}" >>/etc/resolv.conf
              fi
            fi
            sleep 1
          fi
          resetBuild
        ) 2>&1 | dialog --backtitle "$(backtitle)" --title "StaticIP" \
          --progressbox "Set Network ..." 20 100
        break
        ;;
      1)
        break
        ;;
      *)
        break 2
        ;;
      esac
    done
  done
  IP="$(getIP)"
  [ -z "${IPCON}" ] && IPCON="${IP}"
  return
}

###############################################################################
# allow downgrade dsm version
function downgradeMenu() {
  TEXT=""
  TEXT+="This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n"
  TEXT+="Please insert all disks before continuing.\n"
  TEXT+="Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?"
  dialog --backtitle "$(backtitle)" --title "Allow Downgrade" \
      --yesno "${TEXT}" 0 0
  [ $? -ne 0 ] && return 1
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Allow Downgrade" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      #fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      [ -f "${TMP_PATH}/mdX/etc/VERSION" ] && rm -f "${TMP_PATH}/mdX/etc/VERSION" >/dev/null
      [ -f "${TMP_PATH}/mdX/etc.defaults/VERSION" ] && rm -f "${TMP_PATH}/mdX/etc.defaults/VERSION" >/dev/null
      sync
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX" >/dev/null
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Allow Downgrade" \
    --progressbox "Removing Version lock..." 20 70
  dialog --backtitle "$(backtitle)" --title "Allow Downgrade"  \
    --msgbox "Allow Downgrade Settings completed." 0 0
  return
}

###############################################################################
# Reset DSM password
function resetPassword() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Reset Password" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi
  rm -f "${TMP_PATH}/menu" >/dev/null
  mkdir -p "${TMP_PATH}/mdX"
  for I in ${DSMROOTS}; do
    #fixDSMRootPart "${I}"
    T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
    mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
    [ $? -ne 0 ] && continue
    if [ -f "${TMP_PATH}/mdX/etc/shadow" ]; then
      while read L; do
        U=$(echo "${L}" | awk -F ':' '{if ($2 != "*" && $2 != "!!") print $1;}')
        [ -z "${U}" ] && continue
        E=$(echo "${L}" | awk -F ':' '{if ($8 = "1") print "disabled"; else print "        ";}')
        grep -q "status=on" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${U}/method.config" 2>/dev/null
        [ $? -eq 0 ] && S="SecureSignIn" || S="            "
        printf "\"%-36s %-10s %-14s\"\n" "${U}" "${E}" "${S}" >>"${TMP_PATH}/menu"
      done < <(cat "${TMP_PATH}/mdX/etc/shadow" 2>/dev/null)
      break
    fi
    umount "${TMP_PATH}/mdX"
    [ -f "${TMP_PATH}/menu" ] && break
  done
  rm -rf "${TMP_PATH}/mdX" >/dev/null
  if [ ! -f "${TMP_PATH}/menu" ]; then
    dialog --backtitle "$(backtitle)" --title "Reset Password" \
      --msgbox "All existing users have been disabled. Please try adding new user." 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --title "Reset Password" \
    --no-items --menu  "Choose a User" 0 0 0 --file "${TMP_PATH}/menu" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  USER="$(cat "${TMP_PATH}/resp" 2>/dev/null | awk '{print $1}')"
  [ -z "${USER}" ] && return
  while true; do
    dialog --backtitle "$(backtitle)" --title "Reset Password" \
      --inputbox "Type a new password for user ${USER}" 0 70 \
    2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break 2
    STRPASSWD="$(cat "${TMP_PATH}/resp")"
    [ -n "${STRPASSWD}" ] && break
    dialog --backtitle "$(backtitle)" --title "Reset Password" \
      --msgbox "Invalid password" 0 0
  done
  #NEWPASSWD="$(python -c "from passlib.hash import sha512_crypt;pw=\"${VALUE}\";print(sha512_crypt.using(rounds=5000).hash(pw))")"
  NEWPASSWD="$(openssl passwd -6 -salt $(openssl rand -hex 8) "${STRPASSWD}")"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      #fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      sed -i "s|^${USER}:[^:]*|${USER}:${NEWPASSWD}|" "${TMP_PATH}/mdX/etc/shadow"
      sed -i "/^${USER}:/ s/^\(${USER}:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\)[^:]*:/\1:/" "${TMP_PATH}/mdX/etc/shadow"
      sed -i "s|status=on|status=off|g" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${USER}/method.config" 2>/dev/null
      sed -i "s|list=*$|list=|; s|type=*$|type=none|" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/secure_signin.conf" 2>/dev/null

      mkdir -p "${TMP_PATH}/mdX/usr/arc/once.d"
      {
        echo "#!/usr/bin/env bash"
        echo "synowebapi -s --exec api=SYNO.Core.OTP.EnforcePolicy method=set version=1 enable_otp_enforcement=false otp_enforce_option='\"none\"'"
        echo "synowebapi -s --exec api=SYNO.SecureSignIn.AMFA.Policy method=set version=1 type='\"none\"'"
				echo "synowebapi -s --exec api=SYNO.Core.SmartBlock method=set version=1 enabled=false untrust_try=5 untrust_minute=1 untrust_lock=30 trust_try=10 trust_minute=1 trust_lock=30"
				echo "synowebapi -s --exec api=SYNO.SecureSignIn.Method.Admin method=reset version=1 account='\"${USER}\"' keep_amfa_settings=true"
      } >"${TMP_PATH}/mdX/usr/arc/once.d/addNewDSMUser.sh"
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX" >/dev/null
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Reset Password" \
    --progressbox "Resetting ..." 20 100
  if [ -f "${TMP_PATH}/isOk" ]; then
    MSG="Reset password for user ${USER} completed."
  else
    MSG="Reset password for user ${USER} failed."
  fi
  dialog --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Add new DSM user
function addNewDSMUser() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Add DSM User" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi
  MSG="Add to administrators group by default"
  dialog --backtitle "$(backtitle)" --title "Add DSM User" \
    --form "${MSG}" 8 60 3 "username:" 1 1 "user" 1 10 50 0 "password:" 2 1 "passwd" 2 10 50 0 \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  username="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
  password="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      #fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      mkdir -p "${TMP_PATH}/mdX/usr/arc/once.d"
      {
        echo "#!/usr/bin/env bash"
        echo "if synouser --enum local | grep -q ^${username}\$; then synouser --setpw ${username} ${password}; else synouser --add ${username} ${password} rr 0 user@rr.com 1; fi"
        echo "synogroup --memberadd administrators ${username}"
      } >"${TMP_PATH}/mdX/usr/arc/once.d/addNewDSMUser.sh"
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX" >/dev/null
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Add DSM User" \
    --progressbox "Adding ..." 20 100
  [ "$(cat ${TMP_PATH}/isOk 2>/dev/null)" = "true" ] && MSG="Add DSM User successful." || MSG="Add DSM User failed."
  dialog --backtitle "$(backtitle)" --title "Add DSM User" \
    --msgbox "${MSG}" 0 0
  resetBuild
  return
}

###############################################################################
# Change Arc Loader Password
function loaderPassword() {
  dialog --backtitle "$(backtitle)" --title "Loader Password" \
    --inputbox "New password: (Empty value 'arc')" 0 70 \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && continue
  STRPASSWD="$(cat "${TMP_PATH}/resp")"
  NEWPASSWD="$(openssl passwd -6 -salt $(openssl rand -hex 8) "${STRPASSWD:-arc}")"
  cp -p /etc/shadow /etc/shadow-
  sed -i "s|^root:[^:]*|root:${NEWPASSWD}|" /etc/shadow
  RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
  rm -rf "${RDXZ_PATH}"
  mkdir -p "${RDXZ_PATH}"
  if [ -f "${ARC_RAMDISK_USER_FILE}" ]; then
    INITRD_FORMAT=$(file -b --mime-type "${ARC_RAMDISK_USER_FILE}")
    (
      cd "${RDXZ_PATH}"
      case "${INITRD_FORMAT}" in
      *'x-cpio'*) cpio -idm <"${ARC_RAMDISK_USER_FILE}" ;;
      *'x-xz'*) xz -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
      *'x-lz4'*) lz4 -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
      *'x-lzma'*) lzma -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
      *'x-bzip2'*) bzip2 -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
      *'gzip'*) gzip -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
      *'zstd'*) zstd -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
      *) ;;
      esac
    ) >/dev/null 2>&1 || true
  else
    INITRD_FORMAT="application/zstd"
  fi
  if [ "${STRPASSWD:-arc}" = "arc" ]; then
    rm -f ${RDXZ_PATH}/etc/shadow* 2>/dev/null
  else
    mkdir -p "${RDXZ_PATH}/etc"
    cp -p /etc/shadow* ${RDXZ_PATH}/etc && chown root:root ${RDXZ_PATH}/etc/shadow* && chmod 600 ${RDXZ_PATH}/etc/shadow*
  fi
  if [ -n "$(ls -A "${RDXZ_PATH}" 2>/dev/null)" ] && [ -n "$(ls -A "${RDXZ_PATH}/etc" 2>/dev/null)" ]; then
    (
      cd "${RDXZ_PATH}"
      local RDSIZE=$(du -sb ${RDXZ_PATH} 2>/dev/null | awk '{print $1}')
      case "${INITRD_FORMAT}" in
      *'x-cpio'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} >"${RR_RAMUSER_FILE}" ;;
      *'x-xz'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | xz -9 -C crc32 -c - >"${RR_RAMUSER_FILE}" ;;
      *'x-lz4'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | lz4 -9 -l -c - >"${RR_RAMUSER_FILE}" ;;
      *'x-lzma'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | lzma -9 -c - >"${RR_RAMUSER_FILE}" ;;
      *'x-bzip2'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | bzip2 -9 -c - >"${RR_RAMUSER_FILE}" ;;
      *'gzip'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | gzip -9 -c - >"${RR_RAMUSER_FILE}" ;;
      *'zstd'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | zstd -19 -T0 -f -c - >"${RR_RAMUSER_FILE}" ;;
      *) ;;
      esac
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Loader Password" \
      --progressbox "Changing Loader password..." 30 100
  else
    rm -f "${ARC_RAMDISK_USER_FILE}"
  fi
  rm -rf "${RDXZ_PATH}"
  [ "${STRPASSWD:-arc}" = "arc" ] && MSG="Loader Password for root restored." || MSG="Loader Password for root changed."
  dialog --backtitle "$(backtitle)" --title "Loader Password" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Change Arc Loader Ports
function loaderPorts() {
  MSG="Modify Ports (0-65535) (Leave empty for default):"
  unset HTTPPORT DUFSPORT TTYDPORT
  [ -f "/etc/arc.conf" ] && source "/etc/arc.conf" 2>/dev/null
  local HTTP=${HTTPPORT:-7080}
  local DUFS=${DUFSPORT:-7304}
  local TTYD=${TTYDPORT:-7681}
  while true; do
    dialog --backtitle "$(backtitle)" --title "Loader Ports" \
      --form "${MSG}" 11 70 3 "HTTP" 1 1 "${HTTPPORT:-7080}" 1 10 55 0 "DUFS" 2 1 "${DUFSPORT:-7304}" 2 10 55 0 "TTYD" 3 1 "${TTYDPORT:-7681}" 3 10 55 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
    0)
      HTTP="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
      DUFS="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
      TTYD="$(sed -n '3p' "${TMP_PATH}/resp" 2>/dev/null)"
      EP=""
      for P in "${HTTPPORT}" "${DUFSPORT}" "${TTYDPORT}"; do check_port "${P}" || EP="${EP} ${P}"; done
      if [ -n "${EP}" ]; then
        dialog --backtitle "$(backtitle)" --title "Loader Ports" \
          --yesno "Invalid ${EP} Port, retry?" 0 0
        [ $? -eq 0 ] && continue || break
      fi
      rm -f "/etc/arc.conf"
      [ "${HTTPPORT:-7080}" != "7080" ] && echo "HTTP_PORT=${HTTPPORT}" >>"/etc/arc.conf"
      [ "${DUFSPORT:-7304}" != "7304" ] && echo "DUFS_PORT=${DUFSPORT}" >>"/etc/arc.conf"
      [ "${TTYDPORT:-7681}" != "7681" ] && echo "TTYD_PORT=${TTYDPORT}" >>"/etc/arc.conf"
      RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
      rm -rf "${RDXZ_PATH}"
      mkdir -p "${RDXZ_PATH}"
      if [ -f "${ARC_RAMDISK_USER_FILE}" ]; then
        INITRD_FORMAT=$(file -b --mime-type "${ARC_RAMDISK_USER_FILE}")
        (
          cd "${RDXZ_PATH}"
          case "${INITRD_FORMAT}" in
          *'x-cpio'*) cpio -idm <"${ARC_RAMDISK_USER_FILE}" ;;
          *'x-xz'*) xz -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
          *'x-lz4'*) lz4 -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
          *'x-lzma'*) lzma -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
          *'x-bzip2'*) bzip2 -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
          *'gzip'*) gzip -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
          *'zstd'*) zstd -dc "${ARC_RAMDISK_USER_FILE}" | cpio -idm ;;
          *) ;;
          esac
        ) >/dev/null 2>&1 || true
      else
        INITRD_FORMAT="application/zstd"
      fi
      if [ ! -f "/etc/arc.conf" ]; then
        rm -f "${RDXZ_PATH}/etc/arc.conf" 2>/dev/null
      else
        mkdir -p "${RDXZ_PATH}/etc"
        cp -p /etc/arc.conf ${RDXZ_PATH}/etc
      fi
      if [ -n "$(ls -A "${RDXZ_PATH}" 2>/dev/null)" ] && [ -n "$(ls -A "${RDXZ_PATH}/etc" 2>/dev/null)" ]; then
        (
          cd "${RDXZ_PATH}"
          local RDSIZE=$(du -sb ${RDXZ_PATH} 2>/dev/null | awk '{print $1}')
          case "${INITRD_FORMAT}" in
          *'x-cpio'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} >"${ARC_RAMDISK_USER_FILE}" ;;
          *'x-xz'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | xz -9 -C crc32 -c - >"${ARC_RAMDISK_USER_FILE}" ;;
          *'x-lz4'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | lz4 -9 -l -c - >"${ARC_RAMDISK_USER_FILE}" ;;
          *'x-lzma'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | lzma -9 -c - >"${ARC_RAMDISK_USER_FILE}" ;;
          *'x-bzip2'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | bzip2 -9 -c - >"${ARC_RAMDISK_USER_FILE}" ;;
          *'gzip'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | gzip -9 -c - >"${ARC_RAMDISK_USER_FILE}" ;;
          *'zstd'*) find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s ${RDSIZE:-1} | zstd -19 -T0 -f -c - >"${ARC_RAMDISK_USER_FILE}" ;;
          *) ;;
          esac
        ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Loader Ports" \
          --progressbox "Changing Ports..." 30 100
      else
        rm -f "${ARC_RAMDISK_USER_FILE}"
      fi
      rm -rf "${RDXZ_PATH}"
      [ ! -f "/etc/arc.conf" ] && MSG="Ports for TTYD/DUFS/HTTP restored." || MSG="Ports for TTYD/DUFS/HTTP changed."
      dialog --backtitle "$(backtitle)" --title "Loader Ports" \
        --msgbox "${MSG}" 0 0
      rm -f "${TMP_PATH}/restartS.sh"
      {
        [ ! "${HTTP:-7080}" = "${HTTPPORT:-7080}" ] && echo "/etc/init.d/S90thttpd restart"
        [ ! "${DUFS:-7304}" = "${DUFSPORT:-7304}" ] && echo "/etc/init.d/S99dufs restart"
        [ ! "${TTYD:-7681}" = "${TTYDPORT:-7681}" ] && echo "/etc/init.d/S99ttyd restart"
      } >"${TMP_PATH}/restartS.sh"
      chmod +x "${TMP_PATH}/restartS.sh"
      nohup "${TMP_PATH}/restartS.sh" >/dev/null 2>&1
      break
      ;;
    *)
      break
      ;;
    esac
  done
  return
}

###############################################################################
# Force enable Telnet&SSH of DSM system
function forceEnableDSMTelnetSSH() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Force DSM SSH" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      #fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      mkdir -p "${TMP_PATH}/mdX/usr/arc/once.d"
      {
        echo "#!/usr/bin/env bash"
        echo "systemctl restart inetd"
        echo "synowebapi -s --exec api=SYNO.Core.Terminal method=set version=3 enable_telnet=true enable_ssh=true ssh_port=22 forbid_console=false"
      } >"${TMP_PATH}/mdX/usr/arc/once.d/enableTelnetSSH.sh"
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Force DSM SSH" \
    --progressbox "Enabling ..." 20 100
  [ -f "${TMP_PATH}/isOk" ] &&
    MSG="Force enable Telnet&SSH of DSM system completed." ||
    MSG="Force enable Telnet&SSH of DSM system failed."
  dialog --backtitle "$(backtitle)" --title "Force DSM SSH" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Removing the blocked ip database
function removeBlockIPDB {
  MSG=""
  MSG+="This feature will removing the blocked ip database from the first partition of all disks.\n"
  MSG+="Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?"
  dialog --backtitle "$(backtitle)" --title "Remove Blocked IP Database" \
    --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Remove Blocked IP Database" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      #fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      rm -f "${TMP_PATH}/mdX/etc/synoautoblock.db"
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Remove Blocked IP Database" \
    --progressbox "Removing ..." 20 100
  [ -f "${TMP_PATH}/isOk" ] &&
    MSG="Removing the blocked ip database completed." ||
    MSG="Removing the blocked ip database failed."
  dialog --backtitle "$(backtitle)" --title "Remove Blocked IP Database" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Disable all scheduled tasks of DSM
function disablescheduledTasks {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Scheduled Tasks" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      #fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        echo "UPDATE task SET enable = 0;" | sqlite3 "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db"
        sync
        echo "true" > "${TMP_PATH}/isOk"
      fi
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Scheduled Tasks" \
    --progressbox "Modifying..." 20 100
  if [ "$(cat ${TMP_PATH}/isOk 2>/dev/null)" = "true" ]; then
    MSG="Disable all scheduled tasks successful."
  else
    MSG="Disable all scheduled tasks failed."
  fi
  dialog --backtitle "$(backtitle)" --title "Scheduled Tasks" \
    --msgbox "${MSG}" 0 0
  resetBuild
  return
}

###############################################################################
# modify bootipwaittime
function bootipwaittime() {
  ITEMS="$(echo -e "0 \n5 \n10 \n20 \n30 \n60 \n")"
  dialog --backtitle "$(backtitle)" --colors --title "Boot IP Waittime" \
    --default-item "${BOOTIPWAIT}" --no-items --menu "Choose Waittime(seconds)\nto get an IP" 0 0 0 ${ITEMS} \
    2>"${TMP_PATH}/resp"
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  BOOTIPWAIT=${resp}
  writeConfigKey "bootipwait" "${BOOTIPWAIT}" "${USER_CONFIG_FILE}"
  return
}


###############################################################################
# let user format disks from inside arc
function formatDisks() {
  rm -f "${TMP_PATH}/opts"
  while read -r KNAME SIZE TYPE DMODEL PKNAME; do
    [ "${KNAME}" = "N/A" ] || [ "${SIZE:0:1}" = "0" ] && continue
    [ "${KNAME:0:7}" = "/dev/md" ] && continue
    [ "${KNAME}" = "${LOADER_DISK}" ] || [ "${PKNAME}" = "${LOADER_DISK}" ] && continue
    printf "\"%s\" \"%-6s %-4s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" "${DMODEL}" >>"${TMP_PATH}/opts"
  done < <(lsblk -Jpno KNAME,SIZE,TYPE,MODEL,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.size) \(.type) \(.model) \(.pkname)"' 2>/dev/null)
  if [ ! -f "${TMP_PATH}/opts" ]; then
    dialog --backtitle "$(backtitle)" --title "Format Disks" \
      --msgbox "No disk found!" 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --title "Format Disks" \
    --checklist "Select Disks" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return
  dialog --backtitle "$(backtitle)" --title "Format Disks" \
    --yesno "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return
  if [ $(ls /dev/md[0-9]* 2>/dev/null | wc -l) -gt 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Format Disks" \
      --yesno "Warning:\nThe current disks are in raid, do you still want to format them?" 0 0
    [ $? -ne 0 ] && return
    for I in $(ls /dev/md[0-9]* 2>/dev/null); do
      mdadm -S "${I}" >/dev/null 2>&1
    done
  fi
  for I in ${resp}; do
    umount -l "${I}" 2>/dev/null
    if [[ "${I}" = /dev/mmc* ]]; then
      echo y | mkfs.ext4 -T largefile4 -E nodiscard "${I}"
    else
      echo y | mkfs.ext4 -T largefile4 "${I}"
    fi
  done 2>&1 | dialog --backtitle "$(backtitle)" --title "Format Disks" \
    --progressbox "Formatting ..." 20 100
  rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
  resetBuild
  dialog --backtitle "$(backtitle)" --title "Format Disks" \
    --msgbox "Formatting is complete." 0 0
  return
}

###############################################################################
# Clone bootloader disk
function cloneLoader() {
  rm -f "${TMP_PATH}/opts" 2>/dev/null
  while read -r KNAME SIZE TYPE DMODEL PKNAME; do
    [ "${KNAME}" = "N/A" ] || [ "${SIZE:0:1}" = "0" ] && continue
    [ "${KNAME:0:7}" = "/dev/md" ] && continue
    [ "${KNAME}" = "${LOADER_DISK}" ] || [ "${PKNAME}" = "${LOADER_DISK}" ] && continue
    printf "\"%s\" \"%-6s %-4s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" "${DMODEL}" >>"${TMP_PATH}/opts"
  done < <(lsblk -Jpno KNAME,SIZE,TYPE,MODEL,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.size) \(.type) \(.model) \(.pkname)"' 2>/dev/null)

  if [ ! -f "${TMP_PATH}/opts" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
      --msgbox "No disk found!" 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
    --radiolist "Choose a Destination" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  if [ -z "${resp}" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
      --msgbox "No disk selected!" 0 0
    return
  else
    SIZE=$(df -m "${resp}" 2>/dev/null | awk 'NR=2 {print $2}')
    if [ "${SIZE:-0}" -lt 1024 ]; then
      dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
        --msgbox "Disk ${resp} size is less than 1GB and cannot be cloned!" 0 0
      return
    fi
    MSG=""
    MSG+="Warning:\nDisk ${resp} will be formatted and written to the bootloader. Please confirm that important data has been backed up. \nDo you want to continue?"
    dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
      --yesno "${MSG}" 0 0
    [ $? -ne 0 ] && return
  fi
  (
    CLEARCACHE=0

    gzip -dc "${ARC_PATH}/grub.img.gz" | dd of="${resp}" bs=1M conv=fsync status=progress
    hdparm -z "${resp}" # reset disk cache
    fdisk -l "${resp}"
    sleep 1

    NEW_BLDISK_P1="$(blkid | grep -v "${LOADER_DISK_PART1}:" | awk -F: '/LABEL="ARC1"/ {print $1}')"
    NEW_BLDISK_P2="$(blkid | grep -v "${LOADER_DISK_PART2}:" | awk -F: '/LABEL="ARC2"/ {print $1}')"
    NEW_BLDISK_P3="$(blkid | grep -v "${LOADER_DISK_PART3}:" | awk -F: '/LABEL="ARC3"/ {print $1}')"
    SIZEOFDISK=$(cat /sys/block/${resp/\/dev\//}/size)
    ENDSECTOR=$(($(fdisk -l ${resp} | grep "${NEW_BLDISK_P3}" | awk '{print $3}') + 1))

    if [ "${SIZEOFDISK}" -ne "${ENDSECTOR}" ]; then
      echo -e "\033[1;36mResizing ${NEW_BLDISK_P3}\033[0m"
      echo -e "d\n\nn\n\n\n\n\nn\nw" | fdisk "${resp}" >/dev/null 2>&1
      resize2fs "${NEW_BLDISK_P3}"
      fdisk -l "${resp}"
      sleep 1
    fi

    mkdir -p "${TMP_PATH}/sdX1" "${TMP_PATH}/sdX2" "${TMP_PATH}/sdX3"
    mount "${NEW_BLDISK_P1}" "${TMP_PATH}/sdX1" || {
      printf "Can't mount %s." "${NEW_BLDISK_P1}" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    }
    mount "${NEW_BLDISK_P2}" "${TMP_PATH}/sdX2" || {
      printf "Can't mount %s." "${NEW_BLDISK_P2}" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    }
    mount "${NEW_BLDISK_P3}" "${TMP_PATH}/sdX3" || {
      printf "Can't mount %s." "${NEW_BLDISK_P3}" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    }

    SIZEOLD1="$(du -sm "${PART1_PATH}" 2>/dev/null | awk '{print $1}')"
    SIZEOLD2="$(du -sm "${PART2_PATH}" 2>/dev/null | awk '{print $1}')"
    SIZEOLD3="$(du -sm "${PART3_PATH}" 2>/dev/null | awk '{print $1}')"
    SIZENEW1="$(df -m "${NEW_BLDISK_P1}" 2>/dev/null | awk 'NR==2 {print $4}')"
    SIZENEW2="$(df -m "${NEW_BLDISK_P2}" 2>/dev/null | awk 'NR==2 {print $4}')"
    SIZENEW3="$(df -m "${NEW_BLDISK_P3}" 2>/dev/null | awk 'NR==2 {print $4}')"

    if [ "${SIZEOLD1:-0}" -ge "${SIZENEW1:-0}" ] || [ "${SIZEOLD2:-0}" -ge "${SIZENEW2:-0}" ] || [ "${SIZEOLD3:-0}" -ge "${SIZENEW3:-0}" ]; then
      MSG="Cloning failed due to insufficient remaining disk space on the selected hard drive."
      echo "${MSG}" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    fi

    cp -vRf "${PART1_PATH}/". "${TMP_PATH}/sdX1/" || {
      printf "Can't copy to %s." "${NEW_BLDISK_P1}" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    }
    cp -vRf "${PART2_PATH}/". "${TMP_PATH}/sdX2/" || {
      printf "Can't copy to %s." "${NEW_BLDISK_P2}" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    }
    cp -vRf "${PART3_PATH}/". "${TMP_PATH}/sdX3/" || {
      printf "Can't copy to %s." "${NEW_BLDISK_P3}" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    }
    sync
    __umountNewBlDisk
    sleep 3
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
    --progressbox "Cloning ..." 20 100
  dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
    --msgbox "Bootloader has been cloned to Disk ${resp},\nremove the current Bootloader Disk!\nReboot?" 0 0
  rebootTo config
  return
}

###############################################################################
# let user delete Loader Boot Files
function resetLoader() {
  if [ -f "${ORI_ZIMAGE_FILE}" ] || [ -f "${ORI_RDGZ_FILE}" ] || [ -f "${MOD_ZIMAGE_FILE}" ] || [ -f "${MOD_RDGZ_FILE}" ]; then
    # Clean old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1
  fi
  [ -d "${UNTAR_PAT_PATH}" ] && rm -rf "${UNTAR_PAT_PATH}" >/dev/null 2>&1
  [ -f "${USER_CONFIG_FILE}" ] && rm -f "${USER_CONFIG_FILE}" >/dev/null 2>&1
  [ -f "${ARC_RAMDISK_USER_FILE}" ] && rm -f "${ARC_RAMDISK_USER_FILE}" >/dev/null 2>&1
  [ -f "${HOME}/.initialized" ] && rm -f "${HOME}/.initialized" >/dev/null 2>&1
  dialog --backtitle "$(backtitle)" --title "Reset Loader" --aspect 18 \
    --yesno "Reset successful.\nReloading...!" 0 0
  [ $? -ne 0 ] && return
  exec init.sh
}

###############################################################################
# let user edit the grub.cfg
function editGrubCfg() {
  while true; do
    dialog --backtitle "$(backtitle)" --title "Edit with caution" \
      --ok-label "Save" --editbox "${USER_GRUB_CONFIG}" 0 0 2>"${TMP_PATH}/usergrub.cfg"
    [ $? -ne 0 ] && return
    mv -f "${TMP_PATH}/usergrub.cfg" "${USER_GRUB_CONFIG}"
    break
  done
  return
}

###############################################################################
# Grep Logs from dbgutils
function greplogs() {
  rm -rf "${TMP_PATH}/logs" "${TMP_PATH}/logs.tar.gz"
  MSG=""
  SYSLOG=0
  DSMROOTS="$(findDSMRoot)"
  if [ -n "${DSMROOTS}" ]; then
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      #fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      mkdir -p "${TMP_PATH}/logs/md0/log"
      cp -rf ${TMP_PATH}/mdX/.log.junior "${TMP_PATH}/logs/md0"
      cp -rf ${TMP_PATH}/mdX/var/log/messages ${TMP_PATH}/mdX/var/log/*.log "${TMP_PATH}/logs/md0/log"
      SYSLOG=1
      umount "${TMP_PATH}/mdX"
      break
    done
    rm -rf "${TMP_PATH}/mdX" >/dev/null
  fi
  if [ "${SYSLOG}" -eq 1 ]; then
    MSG+="System logs found!\n"
  else
    MSG+="Can't find system logs!\n"
  fi

  ADDONS=0
  if [ -d "${PART1_PATH}/logs" ]; then
    mkdir -p "${TMP_PATH}/logs/addons"
    cp -rf "${PART1_PATH}/logs"/* "${TMP_PATH}/logs/addons" 2>/dev/null || true
    ADDONS=1
  fi
  if [ "${ADDONS}" -eq 1 ]; then
    MSG+="Addons logs found!\n"
  else
    MSG+="Can't find Addon logs!\n"
    MSG+="Please do as follows:\n"
    MSG+="1. Add dbgutils in addons and rebuild.\n"
    MSG+="2. Wait 10 minutes after booting.\n"
    MSG+="3. Reboot into Arc and go to this option.\n"
  fi

  if [ -n "$(ls -A ${TMP_PATH}/logs 2>/dev/null)" ]; then
    tar -czf "${TMP_PATH}/logs.tar.gz" -C "${TMP_PATH}" logs
    mv -f "${TMP_PATH}/logs.tar.gz" "/var/www/data/logs.tar.gz"
    if [ -f "/var/www/data/logs.tar.gz" ]; then
      chmod 644 "/var/www/data/logs.tar.gz"
      URL="http://${IPCON}:${HTTPPORT:-7080}/logs.tar.gz"
      MSG+="Please via ${URL} to download the logs,\nAnd go to Github or Discord to create an issue and upload the logs."
    else
      MSG+="Can't find logs!\n"
    fi
  fi
  dialog --backtitle "$(backtitle)" --colors --title "Grep Logs" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Get DSM Config File from dsmbackup
function getbackup() {
  if [ -d "${PART1_PATH}/dsmbackup" ]; then
    rm -f "${TMP_PATH}/dsmconfig.tar.gz" >/dev/null
    tar -czf "${TMP_PATH}/dsmconfig.tar.gz" -C "${PART1_PATH}" dsmbackup
    cp -f "${TMP_PATH}/dsmconfig.tar.gz" "/var/www/data/dsmconfig.tar.gz"
    chmod 644 "/var/www/data/dsmconfig.tar.gz"
    URL="http://${IPCON}:${HTTPPORT:-7080}/dsmconfig.tar.gz"
    dialog --backtitle "$(backtitle)" --colors --title "DSM Config" \
      --msgbox "Please via ${URL}\nto download the dsmconfig and unzip it and back it up in order by file name." 0 0
  else
    MSG=""
    MSG+="\Z1No dsmbackup found!\Zn\n\n"
    MSG+="Please do as follows:\n"
    MSG+=" 1. Add dsmconfigbackup in Addons and rebuild.\n"
    MSG+=" 2. Boot to DSM.\n"
    MSG+=" 3. Reboot to Config Mode and use this Option.\n"
    dialog --backtitle "$(backtitle)" --colors --title "DSM Config" \
      --msgbox "${MSG}" 0 0
  fi
  return
}

###############################################################################
# SataDOM Menu
function satadomMenu() {
  rm -f "${TMP_PATH}/opts" 2>/dev/null
  echo "0 \"Create SATA node (ARC)\"" >>"${TMP_PATH}/opts"
  echo "1 \"Native SATA Disk (SYNO)\"" >>"${TMP_PATH}/opts"
  echo "2 \"Fake SATA DOM (Redpill)\"" >>"${TMP_PATH}/opts"
  dialog --backtitle "$(backtitle)" --title "Switch SATA DOM" \
    --default-item "${SATADOM}" --menu  "Choose an Option" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return
  SATADOM=${resp}
  writeConfigKey "satadom" "${SATADOM}" "${USER_CONFIG_FILE}"
  resetBuild
  return
}

###############################################################################
# Reboot Menu
function rebootMenu() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  rm -f "${TMP_PATH}/opts" >/dev/null
  touch "${TMP_PATH}/opts"
  # Only show descriptions in the menu
  echo -e "\"Arc: Config Mode\" \"\"" >>"${TMP_PATH}/opts"
  echo -e "\"Arc: Automated Update Mode\" \"\"" >>"${TMP_PATH}/opts"
  echo -e "\"Arc: Restart Network Service\" \"\"" >>"${TMP_PATH}/opts"
  if [ "${BUILDDONE}" = "true" ]; then
    echo -e "\"DSM: Recovery Mode\" \"\"" >>"${TMP_PATH}/opts"
    echo -e "\"DSM: Reinstall Mode\" \"\"" >>"${TMP_PATH}/opts"
  fi
  echo -e "\"System: UEFI\" \"\"" >>"${TMP_PATH}/opts"
  echo -e "\"System: Shutdown\" \"\"" >>"${TMP_PATH}/opts"
  echo -e "\"System: Shell Cmdline\" \"\"" >>"${TMP_PATH}/opts"
  dialog --backtitle "$(backtitle)" --title "Power Menu" \
    --menu  "Choose a Destination" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return

  # Map the description back to the action
  case "${resp}" in
    "Arc: Config Mode") REDEST="config" ;;
    "Arc: Automated Update Mode") REDEST="update" ;;
    "Arc: Restart Network Service") REDEST="network" ;;
    "DSM: Recovery Mode") REDEST="recovery" ;;
    "DSM: Reinstall Mode") REDEST="junior" ;;
    "System: UEFI") REDEST="uefi" ;;
    "System: Shutdown") REDEST="poweroff" ;;
    "System: Shell Cmdline") REDEST="shell" ;;
    *) return ;;
  esac

  dialog --backtitle "$(backtitle)" --title "Power Menu" \
    --infobox "Option: ${resp} selected ...!" 3 50
  if [ "${REDEST}" = "poweroff" ]; then
    poweroff
    exit 0
  elif [ "${REDEST}" = "shell" ]; then
    clear
    exit 0
  elif [ "${REDEST}" = "network" ]; then
    clear
    /etc/init.d/S40network restart
    /etc/init.d/S41dhcpcd restart
    rm -f "${HOME}/.initialized" && exec init.sh
  else
    rebootTo ${REDEST}
    exit 0
  fi
  return
}

###############################################################################
# Reset DSM Network
function resetDSMNetwork {
  MSG=""
  MSG+="This option will clear all customized settings of the network card and restore them to the default state.\n"
  MSG+="Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?"
  dialog --backtitle "$(backtitle)" --title "Reset DSM Network" \
    --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Reset DSM Network" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      for F in ${TMP_PATH}/mdX/etc/sysconfig/network-scripts/ifcfg-* ${TMP_PATH}/mdX/etc.defaults/sysconfig/network-scripts/ifcfg-*; do
        [ ! -e "${F}" ] && continue
        ETHX=$(echo "${F}" | sed -E 's/.*ifcfg-(.*)$/\1/')
        case "${ETHX}" in
        ovs_bond*)
          rm -f "${F}"
          ;;
        ovs_eth*)
          ovs-vsctl del-br ${ETHX}
          sed -i "/${ETHX##ovs_}/"d ${TMP_PATH}/mdX/usr/syno/etc/synoovs/ovs_interface.conf
          rm -f "${F}"
          ;;
        eth*)
          echo -e "DEVICE=${ETHX}\nONBOOT=yes\nBOOTPROTO=dhcp\nIPV6INIT=auto_dhcp\nIPV6_ACCEPT_RA=1" >"${F}"
          ;;
        *) ;;
        esac
      done
      sed -i 's/_mtu=".*"$/_mtu="1500"/g' ${TMP_PATH}/mdX/etc/synoinfo.conf ${TMP_PATH}/mdX/etc.defaults/synoinfo.conf
      # systemctl restart rc-network.service
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Reset DSM Network" \
    --progressbox "Resetting ..." 20 100
  if [ -f "${TMP_PATH}/isOk" ]; then
    MSG="Reset DSM network settings completed."
  else
    MSG="Reset DSM network settings failed."
  fi
  dialog --backtitle "$(backtitle)" --title "Reset DSM Network" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# CPU Governor Menu
function governorMenu () {
  governorSelection
  resetBuild
  return
}

function governorSelection () {
  rm -f "${TMP_PATH}/opts" >/dev/null
  touch "${TMP_PATH}/opts"
  # Selectable CPU governors
  [ "${KVER:0:1}" = "5" ] && echo -e "schedutil \"use efficient frequency scaling *\"" >>"${TMP_PATH}/opts"
  [ "${KVER:0:1}" = "4" ] && echo -e "conservative \"use dynamic frequency scaling *\"" >>"${TMP_PATH}/opts"
  [ "${KVER:0:1}" = "4" ] && echo -e "ondemand \"use dynamic frequency boost\"" >>"${TMP_PATH}/opts"
  echo -e "performance \"always run at max frequency\"" >>"${TMP_PATH}/opts"
  echo -e "powersave \"always run at lowest frequency\"" >>"${TMP_PATH}/opts"
  dialog --backtitle "$(backtitle)" --title "CPU Frequency Scaling" \
    --menu  "Choose a Governor\n* Recommended Option" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return
  GOVERNOR=${resp}
  writeConfigKey "governor" "${GOVERNOR}" "${USER_CONFIG_FILE}"
  return
}

###############################################################################
# Where the magic happens!
function dtsMenu() {
  # Loop menu
  while true; do
    [ -f "${USER_UP_PATH}/${MODEL}.dts" ] && mv -f "${USER_UP_PATH}/${MODEL}.dts" "${USER_UP_PATH}/model.dts"
    [ -f "${USER_UP_PATH}/model.dts" ] && CUSTOMDTS="Yes" || CUSTOMDTS="No"
    dialog --backtitle "$(backtitle)" --title "Custom DTS" \
      --default-item ${NEXT} --menu "Choose an option" 0 0 0 \
      % "Custom dts: ${CUSTOMDTS}" \
      1 "Upload dts file" \
      2 "Delete dts file" \
      3 "Edit dts file" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
    1)
      if ! tty 2>/dev/null | grep -q "/dev/pts"; then
        MSG=""
        MSG+="This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol)\n"
        MSG+="or upload the dts file to ${USER_UP_PATH}/model.dts via Webfilemananger, will be automatically imported at building."
        dialog --backtitle "$(backtitle)" --title "Custom DTS" \
          --msgbox "${MSG}" 0 0
        return
      fi
      dialog --backtitle "$(backtitle)" --title "Custom DTS" \
        --msgbox "Currently, only dts format files are supported. Please prepare and click to confirm uploading.\n(located in /mnt/p3/users/)" 0 0
      TMP_UP_PATH="${TMP_PATH}/users"
      DTC_ERRLOG="/tmp/dtc.log"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      pushd "${TMP_UP_PATH}"
      RET=1
      rz -be
      for F in $(ls -A 2>/dev/null); do
        USER_FILE="${TMP_UP_PATH}/${F}"
        dtc -q -I dts -O dtb "${F}" >"test.dtb" 2>"${DTC_ERRLOG}"
        RET=$?
        break
      done
      popd
      if [ "${RET}" -ne 0 ] || [ -z "${USER_FILE}" ]; then
        dialog --backtitle "$(backtitle)" --title "Custom DTS" \
          --msgbox "Not a valid dts file, please try again!\n\n$(cat "${DTC_ERRLOG}")" 0 0
      else
        [ -d "${USER_UP_PATH}" ] || mkdir -p "${USER_UP_PATH}"
        cp -f "${USER_FILE}" "${USER_UP_PATH}/model.dts"
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Custom DTS")" \
          --msgbox "A valid dts file, Automatically import at compile time." 0 0
      fi
      rm -rf "${DTC_ERRLOG}"
      resetBuild
      ;;
    2)
      rm -f "${USER_UP_PATH}/model.dts"
      resetBuild
      ;;
    3)
      rm -rf "${TMP_PATH}/model.dts"
      if [ -f "${USER_UP_PATH}/model.dts" ]; then
        cp -f "${USER_UP_PATH}/model.dts" "${TMP_PATH}/model.dts"
      else
        ODTB="$(ls ${PART2_PATH}/*.dtb 2>/dev/null | head -1)"
        if [ -f "${ODTB}" ]; then
          dtc -q -I dtb -O dts "${ODTB}" >"${TMP_PATH}/model.dts"
        else
          dialog --backtitle "$(backtitle)" --title "Custom DTS" \
            --msgbox "No dts file to edit. Please upload first!" 0 0
          continue
        fi
      fi
      DTC_ERRLOG="/tmp/dtc.log"
      while true; do
        dialog --backtitle "$(backtitle)" --title "Edit with caution" \
          --editbox "${TMP_PATH}/model.dts" 0 0 2>"${TMP_PATH}/modelEdit.dts"
        [ $? -ne 0 ] && rm -f "${TMP_PATH}/model.dts" "${TMP_PATH}/modelEdit.dts" && return
        dtc -q -I dts -O dtb "${TMP_PATH}/modelEdit.dts}" >"test.dtb" 2>"${DTC_ERRLOG}"
        if [ $? -ne 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Custom DTS" \
            --msgbox "Not a valid dts file, please try again!\n\n$(cat "${DTC_ERRLOG}")" 0 0
        else
          mkdir -p "${USER_UP_PATH}"
          cp -f "${TMP_PATH}/modelEdit.dts" "${USER_UP_PATH}/model.dts"
          rm -r "${TMP_PATH}/model.dts" "${TMP_PATH}/modelEdit.dts"
          resetBuild
          break
        fi
      done
      ;;
    *)
      break
      ;;
    esac
  done
  return
}

###############################################################################
# Get PAT Files
function getpatfiles() {
  ARC_OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  mkdir -p "${USER_UP_PATH}"
  DSM_FILE="${USER_UP_PATH}/${PAT_HASH}.tar"
  VALID="false"
  if [ ! -f "${DSM_FILE}" ] && [ "${ARC_OFFLINE}" = "false" ]; then
    rm -f ${USER_UP_PATH}/*.tar
    dialog --backtitle "$(backtitle)" --colors --title "DSM Boot Files" \
      --infobox "Downloading DSM Boot Files..." 3 40
    # Get new Files
    DSM_URL="https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/files/${MODEL/+/%2B}/${PRODUCTVER}/${PAT_HASH}.tar"
    SPACELEFT=$(df --block-size=1 "${PART3_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
    FILESIZE=$(curl -skLI --http1.1 -m 10 "${DSM_URL}" | grep -i Content-Length | tail -n 1 | tr -d '\r\n' | awk '{print $2}')
    if [ ${FILESIZE:-0} -ge ${SPACELEFT:-0} ]; then
      DSM_FILE="${TMP_PATH}/${PAT_HASH}.tar"
    fi
    if curl -skL --http1.1 "${DSM_URL}" -o "${DSM_FILE}" 2>/dev/null; then
      VALID="true"
    fi
  elif [ ! -f "${DSM_FILE}" ] && [ "${ARC_OFFLINE}" = "true" ]; then
    rm -f ${USER_UP_PATH}/*.tar
    dialog --backtitle "$(backtitle)" --colors --title "DSM Boot Files" \
      --msgbox "Please upload the DSM Boot File to ${USER_UP_PATH}.\nUse ${IPCON}:7304 to upload and press OK after it's finished.\nLink: https://github.com/AuxXxilium/arc-dsm/blob/main/files/${MODEL}/${PRODUCTVER}/${PAT_HASH}.tar" 8 120
    [ $? -ne 0 ] && VALID="false"
    if [ -f "${DSM_FILE}" ]; then
      VALID="true"
    fi
  elif [ -f "${DSM_FILE}" ]; then
    VALID="true"
  fi
  mkdir -p "${UNTAR_PAT_PATH}"
  if [ "${VALID}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --title "DSM Boot Files" --aspect 18 \
      --infobox "Copying DSM Boot Files..." 3 40
    tar -xf "${DSM_FILE}" -C "${UNTAR_PAT_PATH}" 2>/dev/null
    copyDSMFiles "${UNTAR_PAT_PATH}" 2>/dev/null
  else
    dialog --backtitle "$(backtitle)" --title "DSM Boot Files" --aspect 18 \
      --infobox "DSM Boot Files extraction failed: Exit!" 4 45
    sleep 2
    return 1
  fi
  # Cleanup
  [ -d "${UNTAR_PAT_PATH}" ] && rm -rf "${UNTAR_PAT_PATH}"
  return 0
}

###############################################################################
# Generate HardwareID
function genHardwareID() {
  HWID="$(genHWID)"
  while true; do
    USERID="$(curl -skL --http1.1 -m 10 "https://arc.auxxxilium.tech?hwid=${HWID}" 2>/dev/null)"
    if echo "${USERID}" | grep -qE '^[0-9]+$'; then
      writeConfigKey "arc.hardwareid" "${HWID}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "${USERID}" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "true" "${USER_CONFIG_FILE}"
      dialog --backtitle "$(backtitle)" --title "HardwareID" \
        --msgbox "HardwareID: ${HWID}\nYour HardwareID is registered to UserID: ${USERID}!\nYou can use the Online Options now." 7 70
      break
    else
      USERID=""
      writeConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "false" "${USER_CONFIG_FILE}"
      dialog --backtitle "$(backtitle)" --title "HardwareID" \
        --yes-label "Retry" --no-label "Cancel" --yesno "HardwareID: ${HWID}\nRegister your HardwareID at\nhttps://arc.auxxxilium.tech (Discord Account needed).\nPress Retry after you registered it." 8 60
      [ $? -ne 0 ] && break
      continue
    fi
  done
  writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  return
}

###############################################################################
# Check HardwareID
function checkHardwareID() {
  HWID="$(genHWID)"
  USERID="$(curl -skL --http1.1 -m 10 "https://arc.auxxxilium.tech?hwid=${HWID}" 2>/dev/null)"
  if echo "${USERID}" | grep -qE '^[0-9]+$'; then
    writeConfigKey "arc.hardwareid" "${HWID}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.userid" "${USERID}" "${USER_CONFIG_FILE}"
    writeConfigKey "bootscreen.hwidinfo" "true" "${USER_CONFIG_FILE}"
  else
    USERID=""
    writeConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
    writeConfigKey "bootscreen.hwidinfo" "false" "${USER_CONFIG_FILE}"
  fi
  return
}

###############################################################################
# Bootsreen Menu
function bootScreen () {
  rm -f "${TMP_PATH}/bootscreen" "${TMP_PATH}/opts" "${TMP_PATH}/resp" >/dev/null
  unset BOOTSCREENS
  declare -A BOOTSCREENS
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && BOOTSCREENS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "bootscreen" "${USER_CONFIG_FILE}")
  cat <<EOL >"${TMP_PATH}/bootscreen"
dsminfo: DSM Information
systeminfo: System Information
diskinfo: Disk Information
hwidinfo: HardwareID Information
dsmlogo: DSM Logo
EOL
  while IFS=': ' read -r BOOTSCREEN BOOTDESCRIPTION; do
    if [ "${BOOTSCREENS[${BOOTSCREEN}]}" = "true" ]; then
      ACT="on"
    else
      ACT="off"
    fi
    echo -e "${BOOTSCREEN} \"${BOOTDESCRIPTION}\" ${ACT}" >>"${TMP_PATH}/opts"
  done < "${TMP_PATH}/bootscreen"
  dialog --backtitle "$(backtitle)" --title "Bootscreen" --colors --aspect 18 \
    --checklist "Select Bootscreen Informations\Zn\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
    --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  for BOOTSCREEN in dsminfo systeminfo diskinfo hwidinfo dsmlogo; do
    if echo "${resp}" | grep -q "${BOOTSCREEN}"; then
      writeConfigKey "bootscreen.${BOOTSCREEN}" "true" "${USER_CONFIG_FILE}"
    else
      writeConfigKey "bootscreen.${BOOTSCREEN}" "false" "${USER_CONFIG_FILE}"
    fi
  done
  return
}

###############################################################################
# Get Network Config for Loader
function getnet() {
  ETHX=($(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort))
  MODEL=$(readConfigKey "model" "${USER_CONFIG_FILE}")
  ARC_PATCH=$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")

  if [ "${ARC_PATCH}" = "user" ]; then
    for N in "${ETHX[@]}"; do
      while true; do
        dialog --backtitle "$(backtitle)" --title "Mac Setting" \
          --inputbox "Type a custom Mac for ${N} (Eq. 001132a1b2c3).\nThe Mac will not be applied to NIC!" 8 50 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        MAC="$(cat "${TMP_PATH}/resp")"
        [ -z "${MAC}" ] && MAC=$(cat "/sys/class/net/${N}/address" 2>/dev/null | sed 's/://g')
        MAC="$(echo "${MAC}" | tr '[:upper:]' '[:lower:]')"
        if [ "${#MAC}" -eq 12 ]; then
          dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Set Mac for ${N} to ${MAC}!" 5 50
          writeConfigKey "${N}" "${MAC}" "${USER_CONFIG_FILE}"
          break
        else
          dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Invalid MAC - Try again!" 5 50
        fi
      done
    done
  else
    macs=($(generateMacAddress "${ARC_PATCH}" "${MODEL}" "${#ETHX[@]}"))

    for N in "${!ETHX[@]}"; do
      mac="${macs[$N]}"
      writeConfigKey "${ETHX[$N]}" "${mac}" "${USER_CONFIG_FILE}"
    done
  fi
  return
}

###############################################################################
# Generate PortMap
function getmap() {
  SATADRIVES=0

  # Clean old files
  for file in drivesmax drivescon ports remap; do
    > "${TMP_PATH}/${file}"
  done

  # Process SATA Disks
  if [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
    let DISKIDXMAPIDX=0
    DISKIDXMAP=""
    let DISKIDXMAPIDXMAX=0
    DISKIDXMAPMAX=""
    for PCI in $(lspci -d ::106 | awk '{print $1}'); do
      NUMPORTS=0
      CONPORTS=0
      unset HOSTPORTS
      declare -A HOSTPORTS
      while read -r LINE; do
        ATAPORT="$(echo "${LINE}" | grep -o 'ata[0-9]*')"
        PORT=$(echo "${ATAPORT}" | sed 's/ata//')
        HOSTPORTS["${PORT}"]=$(echo "${LINE}" | grep -o 'host[0-9]*$')
      done < <(ls -l /sys/class/scsi_host | grep -F "${PCI}")
      while read -r PORT; do
        ls -l /sys/block | grep -F -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
        PCMD=$(cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd)
        [ "${PCMD}" = 0 ] && DUMMY=1 || DUMMY=0
        [[ "${ATTACH}" = 1 && "${DUMMY}" = 0 ]] && CONPORTS="$((${CONPORTS} + 1))" && echo "$((${PORT} - 1))" >>"${TMP_PATH}/ports"
        NUMPORTS=$((${NUMPORTS} + 1))
      done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
      [ "${NUMPORTS}" -gt 8 ] && NUMPORTS=8
      [ "${CONPORTS}" -gt 8 ] && CONPORTS=8
      echo -n "${NUMPORTS}" >>"${TMP_PATH}/drivesmax"
      echo -n "${CONPORTS}" >>"${TMP_PATH}/drivescon"
      DISKIDXMAP=$DISKIDXMAP$(printf "%02x" $DISKIDXMAPIDX)
      let DISKIDXMAPIDX=$DISKIDXMAPIDX+$CONPORTS
      DISKIDXMAPMAX=$DISKIDXMAPMAX$(printf "%02x" $DISKIDXMAPIDXMAX)
      let DISKIDXMAPIDXMAX=$DISKIDXMAPIDXMAX+$NUMPORTS
      SATADRIVES=$((${SATADRIVES} + ${CONPORTS}))
    done
  fi

  # Process NVMe Disks
  NVMEDRIVES=0
  if [ $(lspci -d ::108 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::108 2>/dev/null | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/nvme 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
      PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[N:${PORT}:" | wc -l)
      NVMEDRIVES=$((NVMEDRIVES + PORTNUM))
    done
    writeConfigKey "device.nvmedrives" "${NVMEDRIVES}" "${USER_CONFIG_FILE}"
  fi

  # Process MMC Disks
  MMCDRIVES=0
  if [ $(lspci -d ::805 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::805 2>/dev/null | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
      PORT=$(ls -l /sys/block/mmc* 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/mmcblk//' | sort -n)
      PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[M:${PORT}:" | wc -l)
      MMCDRIVES=$((MMCDRIVES + PORTNUM))
    done
    writeConfigKey "device.mmcdrives" "${MMCDRIVES}" "${USER_CONFIG_FILE}"
  fi

  # Process SAS Disks
  SASDRIVES=0
  if [ $(lspci -d ::107 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::107 2>/dev/null | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
      SASDRIVES=$((SASDRIVES + PORTNUM))
    done
    writeConfigKey "device.sasdrives" "${SASDRIVES}" "${USER_CONFIG_FILE}"
  fi

  # Process SCSI Disks
  SCSIDRIVES=0
  if [ $(lspci -d ::100 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::100 2>/dev/null | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
      SCSIDRIVES=$((SCSIDRIVES + PORTNUM))
    done
    writeConfigKey "device.scsidrives" "${SCSIDRIVES}" "${USER_CONFIG_FILE}"
  fi

  # Process RAID Disks
  RAIDDRIVES=0
  if [ $(lspci -d ::104 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::104 2>/dev/null | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
      RAIDDRIVES=$((RAIDDRIVES + PORTNUM))
    done
    writeConfigKey "device.raiddrives" "${RAIDDRIVES}" "${USER_CONFIG_FILE}"
  fi

  # Process USB Disks
  USBDRIVES=0
  if [ $(lspci -d ::c03 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::c03 2>/dev/null | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
      USBDRIVES=$((USBDRIVES + PORTNUM))
    done
    writeConfigKey "device.usbdrives" "${USBDRIVES}" "${USER_CONFIG_FILE}"
  fi

  # Write Disk Counts to Config
  DRIVES=$((SATADRIVES + SASDRIVES + SCSIDRIVES + RAIDDRIVES + USBDRIVES + MMCDRIVES + NVMEDRIVES))
  HARDDRIVES=$((SATADRIVES + SASDRIVES + SCSIDRIVES + RAIDDRIVES + NVMEDRIVES))
  writeConfigKey "device.satadrives" "${SATADRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.scsidrives" "${SCSIDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.raiddrives" "${RAIDDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.usbdrives" "${USBDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.mmcdrives" "${MMCDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.nvmedrives" "${NVMEDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.drives" "${DRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.harddrives" "${HARDDRIVES}" "${USER_CONFIG_FILE}"

  # Check for SATA Boot
  if [ $(lspci -d ::106 2>/dev/null | wc -l) -gt 0 ]; then
    LASTDRIVE=0
    while read -r D; do
      if [ "${BUS}" = "sata" ] && [ "${MEV}" != "physical" ] && [ "${D}" -eq 0 ]; then
        MAXDISKS=${DRIVES}
        echo -n "${D}>${MAXDISKS}:" >>"${TMP_PATH}/remap"
      elif [ "${D}" -ne "${LASTDRIVE}" ]; then
        echo -n "${D}>${LASTDRIVE}:" >>"${TMP_PATH}/remap"
        LASTDRIVE=$((LASTDRIVE + 1))
      else
        LASTDRIVE=$((D + 1))
      fi
    done < "${TMP_PATH}/ports"
  fi
  return
}

###############################################################################
# Select PortMap
function getmapSelection() {
  show_and_set_remap() {
    dialog --backtitle "$(backtitle)" --title "Sata Portmap" \
      --menu "Choose a Portmap for Sata!?\n* Recommended Option" 8 60 0 \
      1 "DiskIdxMap: Active Ports ${REMAP1}" \
      2 "DiskIdxMap: Max Ports ${REMAP2}" \
      3 "SataRemap: Remove empty Ports ${REMAP3}" \
      4 "AhciRemap: Remove empty Ports (new) ${REMAP4}" \
      5 "Set my own Portmap in Config" \
    2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
    [ -z "${resp}" ] && return 1

    case ${resp} in
      1) writeConfigKey "arc.remap" "acports" "${USER_CONFIG_FILE}" ;;
      2) writeConfigKey "arc.remap" "maxports" "${USER_CONFIG_FILE}" ;;
      3) writeConfigKey "arc.remap" "remap" "${USER_CONFIG_FILE}" ;;
      4) writeConfigKey "arc.remap" "ahci" "${USER_CONFIG_FILE}" ;;
      5) writeConfigKey "arc.remap" "user" "${USER_CONFIG_FILE}" ;;
    esac
  }
  # Compute PortMap Options
  SATAPORTMAPMAX="$(awk '{print $1}' "${TMP_PATH}/drivesmax")"
  SATAPORTMAP="$(awk '{print $1}' "${TMP_PATH}/drivescon")"
  SATAREMAP="$(awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//')"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  
  if [ "${ARC_MODE}" = "config" ]; then
    # Show recommended Option to user
    if [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "true" ] && [ "${MEV}" = "physical" ]; then
      REMAP2="*"
    elif [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "false" ]; then
      REMAP3="*"
    else
      REMAP1="*"
    fi
    show_and_set_remap
  else
    # Show recommended Option to user
    if [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "true" ] && [ "${MEV}" = "physical" ]; then
      writeConfigKey "arc.remap" "maxports" "${USER_CONFIG_FILE}"
    elif [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "false" ]; then
      writeConfigKey "arc.remap" "remap" "${USER_CONFIG_FILE}"
    else
      writeConfigKey "arc.remap" "acports" "${USER_CONFIG_FILE}"
    fi
  fi
  # Check Remap for correct config
  REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
  deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
  deleteConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}"
  
  case "${REMAP}" in
    "acports")
      writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
      writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAP}" "${USER_CONFIG_FILE}"
      ;;
    "maxports")
      writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAPMAX}" "${USER_CONFIG_FILE}"
      writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAPMAX}" "${USER_CONFIG_FILE}"
      ;;
    "remap")
      writeConfigKey "cmdline.sata_remap" "${SATAREMAP}" "${USER_CONFIG_FILE}"
      ;;
    "ahci")
      writeConfigKey "cmdline.ahci_remap" "${SATAREMAP}" "${USER_CONFIG_FILE}"
      ;;
  esac
  return
}

###############################################################################
# Get initial Disk Controller Info
function getdiskinfo() {
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS // 100=SCSI // c03=USB // 108=NVMe // 805=MMC
  declare -A controllers=(
    [satacontroller]=106
    [sascontroller]=107
    [scsicontroller]=100
    [raidcontroller]=104
    [nvmecontroller]=108
    [mmccontroller]=805
    [usbcontroller]=c03
  )
  external_controller="false"
  for controller in "${!controllers[@]}"; do
    count=$(lspci -d ::${controllers[$controller]} 2>/dev/null | wc -l)
    writeConfigKey "device.${controller}" "${count:-0}" "${USER_CONFIG_FILE}"
    # Only mark specific controllers as external
    if [[ "${controller}" == "sascontroller" || "${controller}" == "scsicontroller" || "${controller}" == "raidcontroller" ]] && [ "${count}" -gt 0 ]; then
      external_controller="true"
    fi
  done
  writeConfigKey "device.externalcontroller" "${external_controller}" "${USER_CONFIG_FILE}"
  return
}

###############################################################################
# Get Network Info
function getnetinfo() {
  BOOTIPWAIT=3
  IPCON=""
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  for N in ${ETHX}; do
    COUNT=0
    while true; do
      CARRIER=$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)
      if [ "${CARRIER}" = "0" ]; then
        break
      elif [ -z "${CARRIER}" ]; then
        break
      fi
      COUNT=$((COUNT + 1))
      IP="$(getIP "${N}")"
      if [ -n "${IP}" ]; then
        if ! echo "${IP}" | grep -q "^169\.254\."; then
          IPCON="${IP}"
        fi
        break
      fi
    done
  done
  IPCON="${IPCON:-noip}"
  return
}

###############################################################################
# Bootloader notifications
function notificationMenu() {
  WEBHOOKNOTIFY="$(readConfigKey "arc.webhooknotify" "${USER_CONFIG_FILE}")"
  DISCORDNOTIFY="$(readConfigKey "arc.discordnotify" "${USER_CONFIG_FILE}")"
  # Submenu for notification type
  dialog --backtitle "$(backtitle)" --title "Notification Type" \
    --menu "Choose notification type:" 10 60 2 \
    1 "Webhook Notification (${WEBHOOKNOTIFY})" \
    2 "Discord Notification (${DISCORDNOTIFY})" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return

  MSG=""
  if [ "${resp}" = "1" ]; then
    MSG+="Please enter the webhook url.\n"
    MSG+="The webhook url must be a valid URL (Reference https://webhook-test.com/).\n"
    WEBHOOKURL="$(readConfigKey "arc.webhookurl" "${USER_CONFIG_FILE}")"
    while true; do
      dialog --backtitle "$(backtitle)" --title "WebhookNotification Settings" \
        --extra-button --extra-label "Test" \
        --form "${MSG}" 10 110 2 "webhookurl" 1 1 "${WEBHOOKURL}" 1 12 93 0 \
        2>"${TMP_PATH}/resp"
      RET=$?
      WEBHOOKURL="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
      case ${RET} in
      0)
        # ok-button
        writeConfigKey "arc.webhooknotify" "true" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.webhookurl" "${WEBHOOKURL}" "${USER_CONFIG_FILE}"
        writeConfigKey "addons.notification" "" "${USER_CONFIG_FILE}"
        break
        ;;
      3)
        # extra-button
        sendWebhook "${WEBHOOKURL}"
        ;;
      1)
        # cancel-button
        writeConfigKey "arc.webhooknotify" "false" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.webhookurl" "" "${USER_CONFIG_FILE}"
        deleteConfigKey "addons.notification" "${USER_CONFIG_FILE}"
        break
        ;;
      *)
        # no-button
        break
        ;;
      esac
      WEBHOOKNOTIFY="$(readConfigKey "arc.webhooknotify" "${USER_CONFIG_FILE}")"
    done
  elif [ "${resp}" = "2" ]; then
    while true; do
      DISCORDUSER="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
      if [ -z "${DISCORDUSER}" ]; then
        dialog --backtitle "$(backtitle)" --title "Discord Notification" \
          --msgbox "Please register HardwareID first!\n" 6 60
        break
      fi
      dialog --backtitle "$(backtitle)" --title "Discord Notification Settings" \
        --yes-label "Enable" --no-label "Disable" --extra-button --extra-label "Test" \
        --yesno "If you enable this, it will send you a notification to your Discord account after Arc or DSM is booted.\nDiscord ID: ${DISCORDUSER}\nYou can disable this at any time." 8 60 \
        2>"${TMP_PATH}/resp"
      RET=$?
      resp2="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      case ${RET} in
      0)
        # ok-button
        writeConfigKey "arc.discordnotify" "true" "${USER_CONFIG_FILE}"
        writeConfigKey "addons.notification" "" "${USER_CONFIG_FILE}"
        break
        ;;
      3)
        # extra-button (Test)
        sendDiscord "${DISCORDUSER}"
        ;;
      1)
        # cancel-button
        writeConfigKey "arc.discordnotify" "false" "${USER_CONFIG_FILE}"
        deleteConfigKey "addons.notification" "${USER_CONFIG_FILE}"
        break
        ;;
      *)
        # no-button
        break
        ;;
      esac
      DISCORDNOTIFY="$(readConfigKey "arc.discordnotify" "${USER_CONFIG_FILE}")"
    done
  fi
  resetBuild
  return
}

###############################################################################
# Remote Assistance Menu
function remoteAssistance() {
  # lock
  exec 911>"${TMP_PATH}/remote.lock"
  flock -n 911 || {
    MSG="Another instance is already running."
    dialog --colors --aspect 50 --title "Arc Assistance" --msgbox "${MSG}" 0 0
    exit 1
  }
  trap 'flock -u 911; rm -f "${TMP_PATH}/remote.lock"; clear; echo "Reinitializing..."; exec "${ARC_PATH}/init.sh"' EXIT INT TERM HUP

  # Start the remote assistance mode
  {
    printf "Press 'ctrl + c' to exit the assistance mode.\n"
    printf "Please give the following link to the assistant. (Click to open and copy)\n\n"
    sshx -q --name "Arc Assistance" 2>&1 &
    SSHX_PID=$!

    # Wait for the sshx process to finish or handle Ctrl+C
    wait ${SSHX_PID}
    if [ $? -ne 0 ]; then
      echo "Failed to generate the remote assistance link."
      while true; do sleep 1; done
    fi
  } | dialog --backtitle "$(backtitle)" --colors --aspect 50 --title "Arc Assistance" \
    --progressbox "Notice: Please keep this window open." 20 100 2>&1

  clear
  echo -e "Reinitializing..."
  rm -f "${TMP_PATH}/remote.lock"
  exec "${ARC_PATH}/init.sh"
}

###############################################################################
# Remote Assistance Boot Menu
function remoteAssistanceBootMenu() {
  while true; do
    dialog --backtitle "$(backtitle)" --title "Arc Assistance" \
      --yesno "Do you want to enable remote assistance at boot?" 5 60
    case $? in
      0)
        writeConfigKey "arc.remoteassistance" "true" "${USER_CONFIG_FILE}"
        break
        ;;
      1)
        writeConfigKey "arc.remoteassistance" "false" "${USER_CONFIG_FILE}"
        break
        ;;
      *)
        break
        ;;
    esac
  done
  return
}

###############################################################################
# Online Menu
function onlineMenu() {
  while true; do
    ARC_UID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
    ARC_BACKUP="$(readConfigKey "arc.backup" "${USER_CONFIG_FILE}")"
    WEBHOOKNOTIFY="$(readConfigKey "arc.webhooknotify" "${USER_CONFIG_FILE}")"
    DISCORDNOTIFY="$(readConfigKey "arc.discordnotify" "${USER_CONFIG_FILE}")"

    # Check if the remote session is running
    if pgrep -f "sshx -q" 2>/dev/null; then
      REMOTE_SESSION_RUNNING=true
      REMOTE_SESSION_OPTION="Stop Remote Assistance Session"
    else
      REMOTE_SESSION_RUNNING=false
      REMOTE_SESSION_OPTION="Start Remote Assistance Session"
    fi

    rm -f "${TMP_PATH}/menu"
    write_menu_value 1 "HardwareID" "$( [ -n "${ARC_UID}" ] && echo "registered" || echo "register" )"
    write_menu_value 2 "Config Online Backup" "$( [ "${ARC_BACKUP}" = "true" ] && echo "enabled" || echo "disabled" )"
    write_menu_value 3 "Notify Webhook / Discord" "$( [ "${WEBHOOKNOTIFY}" = "true" ] && echo "enabled" || echo "disabled" ) / $( [ "${DISCORDNOTIFY}" = "true" ] && echo "enabled" || echo "disabled" )"
    write_menu 4 "${REMOTE_SESSION_OPTION}"
    write_menu_value 5 "Start Remote Assistance at Boot" "$( [ "${REMOTEASSISTANCE}" = "true" ] && echo "enabled" || echo "disabled" )"

    dialog --backtitle "$(backtitle)" --title "Online Settings" --colors \
      --menu "Online Settings require HardwareID registration" 20 55 2 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
    [ -z "${resp}" ] && break
    case ${resp} in
      1)
        if [ -n "${ARC_UID}" ]; then
          dialog --msgbox "HardwareID is already registered." 5 40
        else
          genHardwareID
        fi
        ;;
      2)
        [ "${ARC_BACKUP}" = "true" ] && ARC_BACKUP='false' || ARC_BACKUP='true'
        writeConfigKey "arc.backup" "${ARC_BACKUP}" "${USER_CONFIG_FILE}"
        ;;
      3)
        notificationMenu
        ;;
      4)
        if [ "${REMOTE_SESSION_RUNNING}" = true ]; then
          # Stop the remote session
          pkill -f "sshx -q"
          dialog --msgbox "Remote Assistance Session stopped." 5 40
        else
          # Start the remote session
          remoteAssistance
        fi
        ;;
      5)
        remoteAssistanceBootMenu
        ;;
    esac
  done
  return
}