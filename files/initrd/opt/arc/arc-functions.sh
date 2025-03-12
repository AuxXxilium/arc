###############################################################################
# Model Selection
function arcModel() {
  [ "${ARC_OFFLINE}" != "true" ] && checkHardwareID || true
  dialog --backtitle "$(backtitle)" --title "Model" \
    --infobox "Reading Models..." 3 25
  # Loop menu
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
        ARC_CONFM="$(readConfigKey "${M}.serial" "${S_FILE}")"
        ARC=""
        BETA=""
        [ -n "${ARC_CONFM}" ] && ARC="x" || ARC=""
        [ "${DT}" = "true" ] && DTS="x" || DTS=""
        IGPU=""
        IGPUS=""
        IGPUID="$(lspci -nd ::300 2>/dev/null | grep "8086" | cut -d' ' -f3 | sed 's/://g')"
        if [ -n "${IGPUID}" ]; then grep -iq "${IGPUID}" ${ARC_PATH}/include/i915ids && IGPU="all" || IGPU="epyc7002"; else IGPU=""; fi
        if [[ "${A}" = "apollolake" || "${A}" = "geminilake" ]] && [ "${IGPU}" = "all" ]; then
          IGPUS="+"
        elif [ "${A}" = "epyc7002" ] && [[ "${IGPU}" = "epyc7002" || "${IGPU}" = "all" ]]; then
          IGPUS="x"
        else
          IGPUS=""
        fi
        [ "${DT}" = "true" ] && HBAS="" || HBAS="x"
        [ "${M}" = "SA6400" ] && HBAS="x"
        [ "${DT}" = "false" ] && USBS="int/ext" || USBS="ext"
        [[ "${M}" = "DS719+" || "${M}" = "DS918+" || "${M}" = "DS1019+" || "${M}" = "DS1621xs+" || "${M}" = "RS1619xs+" ]] && M_2_CACHE="+" || M_2_CACHE="x"
        [[ "${M}" = "DS220+" ||  "${M}" = "DS224+" || "${M}" = "DVA1622" ]] && M_2_CACHE=""
        [[ "${M}" = "DS220+" || "${M}" = "DS224+" || "${DT}" = "false" ]] && M_2_STORAGE="" || M_2_STORAGE="+"
        # Check id model is compatible with CPU
        if [ ${RESTRICT} -eq 1 ]; then
          for F in ${FLAGS}; do
            if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
              COMPATIBLE=0
            fi
          done
          if [ "${A}" != "epyc7002" ] && [ "${DT}" = "true" ] && [ "${EXTERNALCONTROLLER}" = "true" ]; then
            COMPATIBLE=0
          fi
          if [ "${A}" != "epyc7002" ] && [ ${SATACONTROLLER} -eq 0 ] && [ "${EXTERNALCONTROLLER}" = "false" ]; then
            COMPATIBLE=0
          fi
          if [ "${A}" = "epyc7002" ] && [[ ${SCSICONTROLLER} -ne 0 || ${RAIDCONTROLLER} -ne 0 ]]; then
            COMPATIBLE=0
          fi
          if [ "${A}" != "epyc7002" ] && [ ${NVMEDRIVES} -gt 0 ] && [ "${BUS}" = "usb" ] && [ ${SATADRIVES} -eq 0 ] && [ "${EXTERNALCONTROLLER}" = "false" ]; then
            COMPATIBLE=0
          elif [ "${A}" != "epyc7002" ] && [ ${NVMEDRIVES} -gt 0 ] && [ "${BUS}" = "sata" ] && [ ${SATADRIVES} -eq 1 ] && [ "${EXTERNALCONTROLLER}" = "false" ]; then
            COMPATIBLE=0
          fi
          [ -z "$(grep -w "${M}" "${S_FILE}")" ] && COMPATIBLE=0
        fi
        [ -n "$(grep -w "${M}" "${S_FILE}")" ] && BETA="Arc" || BETA="Syno"
        [ -z "$(grep -w "${A}" "${P_FILE}")" ] && COMPATIBLE=0
        if [ -n "${ARC_CONF}" ]; then
          [ ${COMPATIBLE} -eq 1 ] && echo -e "${M} \"\t$(printf "\Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "${A}" "${DTS}" "${ARC}" "${IGPUS}" "${HBAS}" "${M_2_CACHE}" "${M_2_STORAGE}" "${USBS}" "${BETA}")\" ">>"${TMP_PATH}/menu"
        else
          [ ${COMPATIBLE} -eq 1 ] && echo -e "${M} \"\t$(printf "\Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "${A}" "${DTS}" "${IGPUS}" "${HBAS}" "${M_2_CACHE}" "${M_2_STORAGE}" "${USBS}" "${BETA}")\" ">>"${TMP_PATH}/menu"
        fi
      done < <(cat "${TMP_PATH}/modellist")
      [ -n "${ARC_CONF}" ] && MSG="Supported Models for your Hardware (x = supported / + = need Addons)\n$(printf "\Zb%-16s\Zn \Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "Model" "Platform" "DT" "Arc" "iGPU" "HBA" "M.2 Cache" "M.2 Volume" "USB Mount" "Source")" || MSG="Supported Models for your Hardware (x = supported / + = need Addons) | Syno Models can have faulty Values.\n$(printf "\Zb%-16s\Zn \Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn \Zb%-10s\Zn \Zb%-10s\Zn" "Model" "Platform" "DT" "iGPU" "HBA" "M.2 Cache" "M.2 Volume" "USB Mount" "Source")"
      [ -n "${ARC_CONF}" ] && TITLEMSG="Arc Model" || TITLEMSG="Model"
      dialog --backtitle "$(backtitle)" --title "${TITLEMSG}" --colors \
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
          [ ${RESTRICT} -eq 1 ] && RESTRICT=0 || RESTRICT=1
          ;;
        *)
          return 
          break
          ;;
      esac
    done
  fi
  # Reset Model Config if changed
  if [ "${ARC_MODE}" = "config" ] && [ "${MODEL}" != "${resp}" ]; then
    MODEL="${resp}"
    writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
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
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
  fi
  PLATFORM="$(grep -w "${MODEL}" "${TMP_PATH}/modellist" | awk '{print $2}' | head -1)"
  writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
  # Read Platform Data
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
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
  if [ "${ARC_MODE}" = "config" ] && [ "${ARCRESTORE}" != "true" ]; then
    # Select Build for DSM
    ITEMS="$(readConfigEntriesArray "platforms.${PLATFORM}.productvers" "${P_FILE}" | sort -r)"
    dialog --clear --no-items --nocancel --title "DSM Version" --backtitle "$(backtitle)" \
      --no-items --menu "Select DSM Version" 7 30 0 ${ITEMS} \
    2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
    [ -z "${resp}" ] && return
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
      rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
    fi
    dialog --backtitle "$(backtitle)" --title "Version" \
    --infobox "Reading DSM Build..." 3 25
    PAT_URL=""
    PAT_HASH=""
    URLVER=""
    while true; do
      PVS="$(readConfigEntriesArray "${PLATFORM}.\"${MODEL}\"" "${D_FILE}" | sort -r)"
      echo -n "" >"${TMP_PATH}/versions"
      while read -r V; do
        if [ "${V:0:3}" != "${PRODUCTVER}" ] || [ "${V}" = "${PREV}" ]; then
          continue
        else
          echo "${V}" >>"${TMP_PATH}/versions"
        fi
        PREV="${V}"
      done < <(echo "${PVS}")
      DSMPVS="$(cat ${TMP_PATH}/versions)"
      dialog --backtitle "$(backtitle)" --colors --title "DSM Build" \
      --no-items --menu "Select DSM Build" 0 0 0 ${DSMPVS} \
      2>"${TMP_PATH}/resp"
      RET=$?
      [ ${RET} -ne 0 ] && return
      PV="$(cat ${TMP_PATH}/resp)"
      PAT_URL="$(readConfigKey "${PLATFORM}.\"${MODEL}\".\"${PV}\".url" "${D_FILE}")"
      PAT_HASH="$(readConfigKey "${PLATFORM}.\"${MODEL}\".\"${PV}\".hash" "${D_FILE}")"
      writeConfigKey "productver" "${PV:0:3}" "${USER_CONFIG_FILE}"
      if [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ]; then
        VALID="true"
        break
      fi
    done
    if [ -z "${PAT_URL}" ] || [ -z "${PAT_HASH}" ]; then
      while true; do
        MSG="Failed to get PAT Data.\n"
        MSG+="Please manually fill in the URL and Hash of PAT.\n"
        MSG+="You will find these Data at: https://github.com/AuxXxilium/arc-dsm/blob/main/webdata.txt"
        dialog --backtitle "$(backtitle)" --colors --title "Arc Build" --default-button "OK" \
          --form "${MSG}" 11 120 2 "Url" 1 1 "${PAT_URL}" 1 8 110 0 "Hash" 2 1 "${PAT_HASH}" 2 8 110 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        [ ${RET} -ne 0 ] && return
        PAT_URL="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
        PAT_HASH="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
        [ -n "${PAT_URL}" ] && [ -n "${PAT_HASH}" ] && VALID="true" && break
      done
    fi
    if [ "${PAT_URL}" != "${PAT_URL_CONF}" ] || [ "${PAT_HASH}" != "${PAT_HASH_CONF}" ]; then
      writeConfigKey "paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"
      writeConfigKey "pathash" "${PAT_HASH}" "${USER_CONFIG_FILE}"
      rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
      rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" >/dev/null 2>&1 || true
      rm -f "${USER_UP_PATH}/"*.tar >/dev/null 2>&1 || true
    fi
    if [ "${ONLYVERSION}" != "true" ]; then
      MSG="Do you want to try Automated Mode?\nIf yes, Loader will configure, build and boot DSM."
      dialog --backtitle "$(backtitle)" --colors --title "Automated Mode" \
        --yesno "${MSG}" 6 55
      if [ $? -eq 0 ]; then
        export ARC_MODE="automated"
      else
        export ARC_MODE="config"
      fi
    fi
  elif [ "${ARC_MODE}" = "automated" ] || [ "${ARCRESTORE}" = "true" ]; then
    VALID="true"
  fi
  # Change Config if Files are valid
  if [ "${VALID}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Config" \
      --infobox "Reconfiguring Cmdline, Modules and Synoinfo" 3 60
    # Reset Synoinfo
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
    while IFS=': ' read -r KEY VALUE; do
      writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
    done < <(readConfigMap "platforms.${PLATFORM}.synoinfo" "${P_FILE}")
    # Reset Modules
    KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
    [ "${PLATFORM}" = "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
    if [ -n "${PLATFORM}" ] && [ -n "${KVERP}" ]; then
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      mergeConfigModules "$(getAllModules "${PLATFORM}" "${KVERP}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
    fi
    # Check Addons for Platform
    ADDONS="$(readConfigKey "addons" "${USER_CONFIG_FILE}")"
    DEVICENIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
    if [ "${ADDONS}" = "{}" ]; then
      initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
      initConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
      initConfigKey "addons.hdddb" "" "${USER_CONFIG_FILE}"
      initConfigKey "addons.storagepanel" "" "${USER_CONFIG_FILE}"
      initConfigKey "addons.updatenotify" "" "${USER_CONFIG_FILE}"
      if [ ${NVMEDRIVES} -gt 0 ]; then
        if [ "${PLATFORM}" = "epyc7002" ] && [ ${SATADRIVES} -eq 0 ] && [ ${SASDRIVES} -eq 0 ]; then
          initConfigKey "addons.nvmesystem" "" "${USER_CONFIG_FILE}"
        elif [ "${DT}" = "true" ]; then
          initConfigKey "addons.nvmevolume" "" "${USER_CONFIG_FILE}"
        fi
      fi
      if [ "${MACHINE}" = "physical" ]; then
        initConfigKey "addons.cpufreqscaling" "" "${USER_CONFIG_FILE}"
        initConfigKey "addons.powersched" "" "${USER_CONFIG_FILE}"
        initConfigKey "addons.sensors" "" "${USER_CONFIG_FILE}"
      else
        initConfigKey "addons.vmtools" "" "${USER_CONFIG_FILE}"
      fi
      if [ "${PLATFORM}" = "apollolake" ] || [ "${PLATFORM}" = "geminilake" ]; then
        if [ -n "${IGPUID}" ]; then grep -iq "${IGPUID}" ${ARC_PATH}/include/i915ids && IGPU="all" || IGPU="epyc7002"; else IGPU=""; fi
        [ "${IGPU}"="all" ] && initConfigKey "addons.i915" "" "${USER_CONFIG_FILE}" || true
      fi
      if echo "${PAT_URL}" 2>/dev/null | grep -q "7.2.2"; then
        initConfigKey "addons.allowdowngrade" "" "${USER_CONFIG_FILE}"
      fi
      if [ -n "${ARC_CONF}" ]; then
        initConfigKey "addons.arcdns" "" "${USER_CONFIG_FILE}"
      fi
      if [ ${SASDRIVES} -gt 0 ]; then
        initConfigKey "addons.smartctl" "" "${USER_CONFIG_FILE}"
      fi
    fi
    while IFS=': ' read -r ADDON PARAM; do
      [ -z "${ADDON}" ] && continue
      if ! checkAddonExist "${ADDON}" "${PLATFORM}"; then
        deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
      fi
    done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
    # Check for Only Version
    if [ "${ONLYVERSION}" = "true" ]; then
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
}

###############################################################################
# Arc Patch Section
function arcPatch() {
  # Read Model Values
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  if [ "${ARC_MODE}" = "automated" ] && [ "${ARC_PATCH}" != "user" ]; then
    if [ -n "${ARC_CONF}" ]; then
      generate_and_write_serial "true"
    else
      generate_and_write_serial "false"
    fi
  elif [ "${ARC_MODE}" = "config" ]; then
   if [ -n "${ARC_CONF}" ]; then
    dialog --clear --backtitle "$(backtitle)" \
      --nocancel --title "SN/Mac Options" \
      --menu "Choose an Option" 7 60 0 \
      1 "Use Arc Patch (AME, QC, Push Notify and more)" \
      2 "Use random SN/Mac (Reduced DSM Features)" \
      3 "Use my own SN/Mac (Be sure your Data is valid)" \
      2>"${TMP_PATH}/resp"
    else
      dialog --clear --backtitle "$(backtitle)" \
        --nocancel --title "SN/Mac Options" \
        --menu "Choose an Option" 7 60 0 \
        2 "Use random SN/Mac (Reduced DSM Features)" \
        3 "Use my own SN/Mac (Be sure your Data is valid)" \
        2>"${TMP_PATH}/resp"
    fi
    
    resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
    [ -z "${resp}" ] && return 1
    
    case ${resp} in
      1)
        generate_and_write_serial "true"
        ;;
      2)
        generate_and_write_serial "false"
        ;;
      3)
        while true; do
          dialog --backtitle "$(backtitle)" --colors --title "Serial" \
            --inputbox "Please enter a valid SN!" 7 50 "" \
            2>"${TMP_PATH}/resp"
          [ $? -ne 0 ] && break 2
          SN="$(cat "${TMP_PATH}/resp" | tr '[:lower:]' '[:upper:]')"
          [ -z "${SN}" ] && return
          break
        done
        writeConfigKey "arc.patch" "user" "${USER_CONFIG_FILE}"
        writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
        ;;
    esac
  fi

  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  arcSettings
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
  
  # Network Config for Loader
  dialog --backtitle "$(backtitle)" --colors --title "Network Config" \
    --infobox "Generating Network Config..." 3 40
  sleep 2
  getnet || return
  
  if [ "${ONLYPATCH}" = "true" ]; then
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    ONLYPATCH="false"
    return 0
  fi
  
  # Select Portmap for Loader
  dialog --backtitle "$(backtitle)" --colors --title "Storage Map" \
    --infobox "Generating Storage Map..." 3 40
  sleep 2
  getmap || return
  if [ "${DT}" = "false" ] && [ ${SATADRIVES} -gt 0 ]; then
    getmapSelection || return
  fi
  
  # Select Addons
  if [ "${ARC_MODE}" = "config" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Addons" \
      --infobox "Loading Addons Table..." 3 40
    addonSelection || return
  fi
  
  # CPU Frequency Scaling & Governor
  if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "cpufreqscaling"; then
    if [ "${ARC_MODE}" = "config" ] && [ "${MACHINE}" = "pysical" ]; then
      dialog --backtitle "$(backtitle)" --colors --title "CPU Frequency Scaling" \
        --infobox "Generating Governor Table..." 3 40
      governorSelection || return
    elif [ "${ARC_MODE}" = "automated" ] && [ "${MACHINE}" = "physical" ]; then
      if [ "${PLATFORM}" = "epyc7002" ]; then
        writeConfigKey "governor" "schedutil" "${USER_CONFIG_FILE}"
      else
        writeConfigKey "governor" "conservative" "${USER_CONFIG_FILE}"
      fi
    fi
  fi
  
  # Warnings and Checks
  if [ "${ARC_MODE}" = "config" ]; then
    [ "${DT}" = "true" ] && [ "${EXTERNALCONTROLLER}" = "true" ] && dialog --backtitle "$(backtitle)" --title "Arc Warning" --msgbox "WARN: You use a HBA/Raid Controller and selected a DT Model.\nThis is still an experimental." 6 70
    DEVICENIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
    MODELNIC="$(readConfigKey "${MODEL}.ports" "${S_FILE}" 2>/dev/null)"
    [ ${DEVICENIC} -gt 8 ] && dialog --backtitle "$(backtitle)" --title "Arc Warning" --msgbox "WARN: You have more NIC (${DEVICENIC}) than 8 NIC.\nOnly 8 supported by DSM." 6 60
    [ ${DEVICENIC} -gt ${MODELNIC} ] && [ "${ARC_PATCH}" = "true" ] && dialog --backtitle "$(backtitle)" --title "Arc Warning" --msgbox "WARN: You have more NIC (${DEVICENIC}) than supported by Model (${MODELNIC}).\nOnly the first ${MODELNIC} are used by Arc Patch." 6 80
    [ "${AESSYS}" = "false" ] && dialog --backtitle "$(backtitle)" --title "Arc Warning" --msgbox "WARN: Your System doesn't support Hardware encryption in DSM. (AES)" 5 70
    [[ "${CPUFREQ}" = "false" || "${ACPISYS}" = "false" ]] && readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "cpufreqscaling" && dialog --backtitle "$(backtitle)" --title "Arc Warning" --msgbox "WARN: It is possible that CPU Frequency Scaling is not working properly with your System." 6 80
  fi
  
  # eMMC Boot Support
  EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
  if [ "${EMMCBOOT}" = "true" ]; then
    writeConfigKey "modules.mmc_block" "" "${USER_CONFIG_FILE}"
    writeConfigKey "modules.mmc_core" "" "${USER_CONFIG_FILE}"
  else
    deleteConfigKey "modules.mmc_block" "${USER_CONFIG_FILE}"
    deleteConfigKey "modules.mmc_core" "${USER_CONFIG_FILE}"
  fi
  
  # Final Config Check
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
      [ ${resp} -eq 1 ] && arcSummary || dialog --clear --no-items --backtitle "$(backtitle)"
    else
      make
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Config failed" --msgbox "ERROR: Config failed!\nExit." 6 40
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
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
  
  # Read remap configurations
  PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
  DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
  PORTREMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
  AHCIPORTREMAP="$(readConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}")"
  
  DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
  NIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  HARDDRIVES="$(readConfigKey "device.harddrives" "${USER_CONFIG_FILE}")"
  DRIVES="$(readConfigKey "device.drives" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  
  # Check for user-defined remap values
  if [ "${DT}" = "false" ] && [ "${REMAP}" = "user" ] && [ -z "${PORTMAP}${DISKMAP}${PORTREMAP}${AHCIPORTREMAP}" ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Error" \
      --msgbox "ERROR: You selected Portmap: User and not set any values. -> Can't build Loader!\nGo need to go Cmdline Options and add your Values." 6 80
    return 1
  fi
  
  # Print Summary
  SUMMARY="\Z4> DSM Information\Zn"
  SUMMARY+="\n>> Model: \Zb${MODEL}\Zn"
  SUMMARY+="\n>> Version: \Zb${PRODUCTVER}\Zn"
  SUMMARY+="\n>> Platform: \Zb${PLATFORM}\Zn"
  SUMMARY+="\n>> DT: \Zb${DT}\Zn"
  SUMMARY+="\n>> PAT URL: \Zb${PAT_URL}\Zn"
  SUMMARY+="\n>> PAT Hash: \Zb${PAT_HASH}\Zn"
  [ "${MODEL}" = "SA6400" ] && SUMMARY+="\n>> Kernel: \Zb${KERNEL}\Zn"
  SUMMARY+="\n>> Kernel Version: \Zb${KVER}\Zn"
  SUMMARY+="\n"
  SUMMARY+="\n\Z4> Arc Information\Zn"
  SUMMARY+="\n>> Arc Patch: \Zb${ARC_PATCH}\Zn"
  [ -n "${PORTMAP}" ] && SUMMARY+="\n>> SataPortmap: \Zb${PORTMAP}\Zn"
  [ -n "${DISKMAP}" ] && SUMMARY+="\n>> DiskIdxMap: \Zb${DISKMAP}\Zn"
  [ -n "${PORTREMAP}" ] && SUMMARY+="\n>> SataRemap: \Zb${PORTREMAP}\Zn"
  [ -n "${AHCIPORTREMAP}" ] && SUMMARY+="\n>> AhciRemap: \Zb${AHCIPORTREMAP}\Zn"
  [ "${DT}" = "true" ] && SUMMARY+="\n>> Sort Drives: \Zb${HDDSORT}\Zn"
  SUMMARY+="\n>> Directboot: \Zb${DIRECTBOOT}\Zn"
  SUMMARY+="\n>> eMMC Boot: \Zb${EMMCBOOT}\Zn"
  SUMMARY+="\n>> Kernelload: \Zb${KERNELLOAD}\Zn"
  SUMMARY+="\n>> Addons: \Zb${ADDONSINFO}\Zn"
  SUMMARY+="\n"
  SUMMARY+="\n\Z4> Device Information\Zn"
  SUMMARY+="\n>> NIC: \Zb${NIC}\Zn"
  SUMMARY+="\n>> Total Disks: \Zb${DRIVES}\Zn"
  SUMMARY+="\n>> Internal Disks: \Zb${HARDDRIVES}\Zn"
  SUMMARY+="\n>> Additional Controller: \Zb${EXTERNALCONTROLLER}\Zn"
  SUMMARY+="\n"
  
  dialog --backtitle "$(backtitle)" --colors --title "Config Summary" \
    --extra-button --extra-label "Cancel" --msgbox "${SUMMARY}" 0 0
  
  RET=$?
  case ${RET} in
    0)
      make
      ;;
    *)
      return 0
      ;;
  esac
}

###############################################################################
# Building Loader
function make() {
  # Read Model Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  # Check for Arc Patch
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  if [ -z "${ARC_CONF}" ] || [ "${ARC_PATCH}" = "false" ]; then
    deleteConfigKey "addons.amepatch" "${USER_CONFIG_FILE}"
    deleteConfigKey "addons.arcdns" "${USER_CONFIG_FILE}"
  fi
  # Max Memory for DSM
  RAMCONFIG="$((${RAMTOTAL} * 1024 * 2))"
  writeConfigKey "synoinfo.mem_max_mb" "${RAMCONFIG}" "${USER_CONFIG_FILE}"
  if [ -n "${IPCON}" ]; then
    getpatfiles
  else
    dialog --backtitle "$(backtitle)" --title "Build Loader" --aspect 18 \
      --infobox "Could not build Loader!\nNetwork Connection needed." 4 40
    # Set Build to false
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    sleep 2
    return
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
    # Set Build to false
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    sleep 2
    return
  fi
  if [ -f "${ORI_ZIMAGE_FILE}" ] && [ -f "${ORI_RDGZ_FILE}" ] && [ -f "${MOD_ZIMAGE_FILE}" ] && [ -f "${MOD_RDGZ_FILE}" ]; then
    MODELID="$(echo ${MODEL} | sed 's/d$/D/; s/rp$/RP/; s/rp+/RP+/')"
    writeConfigKey "modelid" "${MODELID}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
    arcFinish
  else
    dialog --backtitle "$(backtitle)" --title "Build Loader" --aspect 18 \
      --infobox "Could not build Loader!\nExit." 4 40
    # Set Build to false
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    sleep 2
    return
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
  
    if [ "${ARC_MODE}" = "automated" ] || [ "${UPDATEMODE}" = "true" ]; then
      boot
    else
      # Ask for Boot
      dialog --clear --backtitle "$(backtitle)" --title "Build done" \
        --no-cancel --menu "Boot now?" 7 40 0 \
        1 "Yes - Boot DSM now" \
        2 "No - I want to make changes" \
      2>"${TMP_PATH}/resp"
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ "${resp}" -eq 1 ] && boot || return
    fi
  fi
}

###############################################################################
# Calls boot.sh to boot into DSM Reinstall Mode
function juniorboot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
  if [[ "${BUILDDONE}" = "false" && "${ARC_MODE}" != "automated" ]] || [ "${MODEL}" != "${MODELID}" ]; then
    dialog --backtitle "$(backtitle)" --title "Alert" \
      --yesno "Config changed, you need to rebuild the Loader?" 0 0
    if [ $? -eq 0 ]; then
      arcSummary
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Booting DSM Reinstall Mode...\nPlease stay patient!" 4 30
    sleep 3
    rebootTo junior
  fi
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
  if [[ "${BUILDDONE}" = "false" && "${ARC_MODE}" != "automated" ]] || [ "${MODEL}" != "${MODELID}" ]; then
    dialog --backtitle "$(backtitle)" --title "Alert" \
      --yesno "Config changed, you need to rebuild the Loader?" 0 0
    if [ $? -eq 0 ]; then
      arcSummary
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Arc Boot" \
      --infobox "Booting DSM...\nPlease stay patient!" 4 25
    sleep 2
    exec reboot
  fi
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  OLDMODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  OLDPRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  while true; do
    dialog --backtitle "$(backtitle)" --title "Edit with caution" \
      --ok-label "Save" --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return 1
    mv -f "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=$(yq eval "${USER_CONFIG_FILE}" 2>&1)
    [ $? -eq 0 ] && break || continue
    dialog --backtitle "$(backtitle)" --title "Invalid YAML format" --msgbox "${ERRORS}" 0 0
  done
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
  if [ "${MODEL}" != "${OLDMODEL}" ] || [ "${PRODUCTVER}" != "${OLDPRODUCTVER}" ]; then
    # Delete old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null
  fi
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  return
}

###############################################################################
# Shows option to manage Addons
function addonMenu() {
  addonSelection
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  return
}

function addonSelection() {
  # read platform and kernel version to check if addon exists
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"

  # read addons from user config
  declare -A ADDONS
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

  rm -f "${TMP_PATH}/opts"
  touch "${TMP_PATH}/opts"

  while read -r ADDON DESC; do
    arrayExistItem "${ADDON}" "${!ADDONS[@]}" && ACT="on" || ACT="off"
    if { [[ "${ADDON}" = "amepatch" || "${ADDON}" = "arcdns" ]] && [ -z "${ARC_CONF}" ]; } || { [ "${ADDON}" = "codecpatch" ] && [ -n "${ARC_CONF}" ]; }; then
      continue
    else
      echo -e "${ADDON} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
    fi
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

  ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  dialog --backtitle "$(backtitle)" --title "Addons" \
    --msgbox "Addons selected:\n${ADDONSINFO}" 7 70
}

###############################################################################
# Permit user select the modules to include
function modulesMenu() {
  NEXT="1"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  [ "${PLATFORM}" = "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
  # loop menu
  while true; do
    rm -f "${TMP_PATH}/menu"
    {
      echo "1 \"Show/Select Modules\""
      echo "2 \"Select loaded Modules\""
      echo "3 \"Upload a external Module\""
      echo "4 \"Deselect i915 with dependencies\""
      echo "5 \"Edit Modules that need to be copied to DSM\""
      echo "6 \"Blacklist Modules to prevent loading\""
    } >"${TMP_PATH}/menu"
    dialog --backtitle "$(backtitle)" --title "Modules" \
      --cancel-label "Exit" --menu "Choose an option" 0 0 0 --file "${TMP_PATH}/menu" \
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
          # ok-button
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          mergeConfigModules "$(cat "${TMP_PATH}/resp" 2>/dev/null)" "${USER_CONFIG_FILE}"
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          break
          ;;
        3)
          # extra-button
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          mergeConfigModules "$(echo "${ALLMODULES}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          ;;
        2)
          # help-button
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          ;;
        1)
          # cancel-button
          break
          ;;
        255)
          # ESC
          break
          ;;
        esac
      done
      ;;
    2)
      dialog --backtitle "$(backtitle)" --title "Modules" \
        --infobox "Select loaded modules" 0 0
      KOLIST=""
      for I in $(lsmod 2>/dev/null | awk -F' ' '{print $1}' | grep -v 'Module'); do
        KOLIST+="$(getdepends "${PLATFORM}" "${KVERP}" "${I}") ${I} "
      done
      KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      for ID in ${KOLIST[@]}; do
        writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
      done
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      ;;
    3)
      if ! tty 2>/dev/null | grep -q "/dev/pts"; then #if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG=""
        MSG+="This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol)."
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --msgbox "${MSG}" 0 0
        return
      fi
      MSG=""
      MSG+="This function is experimental and dangerous. If you don't know much, please exit.\n"
      MSG+="The imported .ko of this function will be implanted into the corresponding arch's modules package, which will affect all models of the arch.\n"
      MSG+="This program will not determine the availability of imported modules or even make type judgments, as please double check if it is correct.\n"
      MSG+="If you want to remove it, please go to the \"Update Menu\" -> \"Update Dependencies\" to forcibly update the modules. All imports will be reset.\n"
      MSG+="Do you want to continue?"
      dialog --backtitle "$(backtitle)" --title "Modules" \
        --yesno "${MSG}" 0 0
      [ $? -ne 0 ] && continue
      dialog --backtitle "$(backtitle)" --title "Modules" \
        --msgbox "Please upload the *.ko file." 0 0
      TMP_UP_PATH=${TMP_PATH}/users
      USER_FILE=""
      rm -rf ${TMP_UP_PATH}
      mkdir -p ${TMP_UP_PATH}
      pushd ${TMP_UP_PATH}
      rz -be
      for F in $(ls -A 2>/dev/null); do
        USER_FILE=${F}
        break
      done
      popd
      if [ -n "${USER_FILE}" ] && [ "${USER_FILE##*.}" = "ko" ]; then
        addToModules ${PLATFORM} "${KVERP}" "${TMP_UP_PATH}/${USER_FILE}"
        [ -f "${MODULES_PATH}/VERSION" ] && rm -f "${MODULES_PATH}/VERSION"
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --msgbox "$(printf "Module '%s' added to %s-%s" "${USER_FILE}" "${PLATFORM}" "${KVERP}")" 0 0
        rm -f "${TMP_UP_PATH}/${USER_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      else
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --msgbox "Not a valid file, please try again!" 0 0
      fi
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
      if [ ${#DELS[@]} -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --msgbox "No i915 with dependencies module to deselect." 0 0
      else
        for ID in ${DELS[@]}; do
          deleteConfigKey "modules.\"${ID}\"" "${USER_CONFIG_FILE}"
        done
        dialog --backtitle "$(backtitle)" --title "Modules" \
          --msgbox "$(printf "Module %s deselected." "${DELS[@]}")" 0 0
      fi
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
        dos2unix "${USER_UP_PATH}/modulelist"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
        dialog --backtitle "$(backtitle)" --title "Modules" \
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
}

###############################################################################
# Let user edit cmdline
function cmdlineMenu() {
  # Loop menu
  while true; do
  echo "1 \"Add a Cmdline item\""                                >"${TMP_PATH}/menu"
  echo "2 \"Delete Cmdline item(s)\""                           >>"${TMP_PATH}/menu"
  echo "3 \"CPU Fix\""                                          >>"${TMP_PATH}/menu"
  echo "4 \"RAM Fix\""                                          >>"${TMP_PATH}/menu"
  echo "5 \"PCI/IRQ Fix\""                                      >>"${TMP_PATH}/menu"
  echo "6 \"C-State Fix\""                                      >>"${TMP_PATH}/menu"
  echo "7 \"Kernelpanic Behavior\""                             >>"${TMP_PATH}/menu"
    dialog --backtitle "$(backtitle)" --title "Cmdline"  --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
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
        MSG+=" * \Z4libata.force=noncq\Zn\n    Disable NCQ for all SATA ports.\n"
        MSG+=" * \Z4acpi=force\Zn\n    Force enables ACPI.\n"
        MSG+=" * \Z4i915.enable_guc=2\Zn\n    Enable the GuC firmware on Intel graphics hardware.(value: 1,2 or 3)\n"
        MSG+=" * \Z4i915.max_vfs=7\Zn\n     Set the maximum number of virtual functions (VFs) that can be created for Intel graphics hardware.\n"
        MSG+=" * \Z4i915.modeset=0\Zn\n    Disable the kernel mode setting (KMS) feature of the i915 driver.\n"
        MSG+=" * \Z4apparmor.mode=complain\Zn\n    Set the AppArmor security module to complain mode.\n"
        MSG+=" * \Z4pci=nommconf\Zn\n    Disable the use of Memory-Mapped Configuration for PCI devices(use this parameter cautiously).\n"
        MSG+="\nEnter the Parameter Name and Value you want to add.\n"
        LINENUM=$(($(echo -e "${MSG}" | wc -l) + 10))
        RET=0
        while true; do
          [ ${RET} -eq 255 ] && MSG+="Commonly used Parameter (Format: Name=Value):\n"
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
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      2)
        while true; do
          unset CMDLINE
          declare -A CMDLINE
          while IFS=': ' read -r KEY VALUE; do
            [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
          done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
          if [ ${#CMDLINE[@]} -eq 0 ]; then
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
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
          if [ ${resp} -eq 1 ]; then
            writeConfigKey "cmdline.pci" "routeirq" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "PCI/IRQ Fix" \
              --aspect 18 --msgbox "Fix added to Cmdline" 0 0
          elif [ ${resp} -eq 2 ]; then
            deleteConfigKey "cmdline.pci" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "PCI/IRQ Fix" \
              --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
          fi
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
          if [ ${resp} -eq 1 ]; then
            writeConfigKey "cmdline.intel_idle.max_cstate" "1" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "C-State Fix" \
              --aspect 18 --msgbox "Fix added to Cmdline" 0 0
          elif [ ${resp} -eq 2 ]; then
            deleteConfigKey "cmdline.intel_idle.max_cstate" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "C-State Fix" \
              --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
          fi
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      7)
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
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
    dialog --backtitle "$(backtitle)" --title "Synoinfo" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
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
          [ ${RET} -eq 255 ] && MSG+="Commonly used Synoinfo (Format: Name=Value):\n"
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
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      2)
        # Read synoinfo from user config
        unset SYNOINFO
        declare -A SYNOINFO
        while IFS=': ' read KEY VALUE; do
          [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
        done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")
        if [ ${#SYNOINFO[@]} -eq 0 ]; then
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
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  fi
  return
}

###############################################################################
# Shows sequentialIO menu to user
function sequentialIOMenu() {
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    while true; do
        dialog --backtitle "$(backtitle)" --title "SequentialIO" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
          1 "Enable for SSD Cache" \
          2 "Disable for SSD Cache" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
          1)
            dialog --backtitle "$(backtitle)" --colors --title "SequentialIO" \
              --msgbox "SequentialIO enabled" 0 0
            SEQUENTIAL="true"
            ;;
          2)
            dialog --backtitle "$(backtitle)" --colors --title "SequentialIO" \
              --msgbox "SequentialIO disabled" 0 0
            SEQUENTIAL="false"
            ;;
          *)
            break
            ;;
        esac
        writeConfigKey "addons.sequentialio" "${SEQUENTIAL}" "${USER_CONFIG_FILE}"
        break
    done
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
          # fixDSMRootPart "${I}"
          mount -t ext4 "${I}" "${TMP_PATH}/mdX"
          MODEL=""
          PRODUCTVER=""
          if [ -f "${TMP_PATH}/mdX/usr/arc/backup/p1/user-config.yml" ]; then
            cp -f "${TMP_PATH}/mdX/usr/arc/backup/p1/user-config.yml" "${USER_CONFIG_FILE}"
            sleep 2
            MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
            MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
            PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
            if [ -n "${MODEL}" ] && [ -n "${PRODUCTVER}" ]; then
              TEXT="Config found:\nModel: ${MODELID:-${MODEL}}\nVersion: ${PRODUCTVER}"
              SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
              TEXT+="\nSerial: ${SN}"
              ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
              TEXT+="\nArc Patch: ${ARC_PATCH}"
              dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
                --aspect 18 --msgbox "${TEXT}" 0 0
              PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
              DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
              CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
              writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
              BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
              break
            fi
          fi
          umount "${TMP_PATH}/mdX"
        done
        if [ -f "${USER_CONFIG_FILE}" ]; then
          PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          if [ -n "${PRODUCTVER}" ]; then
            PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
            KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
            [ "${PLATFORM}" = "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
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
          --msgbox "Upload the machine.key file to ${PART3_PATH}/users\nand press OK after the upload is done." 0 0
        [ $? -ne 0 ] && return 1
        if [ -f "${PART3_PATH}/users/machine.key" ]; then
          mv -f "${PART3_PATH}/users/machine.key" "${PART2_PATH}/machine.key"
          dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
            --msgbox "Encryption Key restore successful!" 0 0
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
          cp -f "${PART2_PATH}/machine.key" "/var/www/data/machine.key"
          URL="http://${IPCON}${HTTPPORT:+:$HTTPPORT}/machine.key"
          MSG="Please use ${URL} to download the machine.key file."
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
        if curl -skL "https://arc.auxxxilium.tech?cdown=${HWID}" -o "${USER_CONFIG_FILE}" 2>/dev/null; then
          dialog --backtitle "$(backtitle)" --title "Online Restore" --msgbox "Online Restore successful!" 5 40
          export ARC_CONF="true"
        else
          dialog --backtitle "$(backtitle)" --title "Online Restore" --msgbox "Online Restore failed!" 5 40
          [ -f "${USER_CONFIG_FILE}.bak" ] && mv -f "${USER_CONFIG_FILE}.bak" "${USER_CONFIG_FILE}"
        fi
        MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
        MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
        PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
        if [ -n "${MODEL}" ] && [ -n "${PRODUCTVER}" ]; then
          TEXT="Config found:\nModel: ${MODELID:-${MODEL}}\nVersion: ${PRODUCTVER}"
          SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
          TEXT+="\nSerial: ${SN}"
          ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          TEXT+="\nArc Patch: ${ARC_PATCH}"
          dialog --backtitle "$(backtitle)" --title "Online Restore" \
            --aspect 18 --msgbox "${TEXT}" 0 0
          PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
          DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
          CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
          dialog --backtitle "$(backtitle)" --title "Online Backup" --msgbox "Online Backup successful!" 5 40
        else
          dialog --backtitle "$(backtitle)" --title "Online Backup" --msgbox "Online Backup failed!" 5 40
          return 1
        fi
        return
        ;;
      *)
        break
        ;;
    esac
  done
}

###############################################################################
# Shows update menu to user
function updateMenu() {
  NEXT="1"
  while true; do
    dialog --backtitle "$(backtitle)" --title "Update" --colors --cancel-label "Exit" \
      --menu "Choose an Option" 0 0 0 \
      1 "Update Full Loader \Z1(no reflash)\Zn" \
      2 "Update Dependencies (only integrated Parts)" \
      3 "Update Configs and Arc Patch" \
      4 "Switch Arc Branch: \Z1${ARC_BRANCH}\Zn" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
      1)
        # Ask for Tag
        TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
        OLD="${ARC_VERSION}"
        dialog --clear --backtitle "$(backtitle)" --title "Update Loader" \
          --menu "Current: ${OLD} -> Which Version?" 7 50 0 \
          1 "Latest ${TAG}" \
          2 "Select Version" \
          3 "Upload .zip File" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts="$(cat "${TMP_PATH}/opts")"
        if [ ${opts} -eq 1 ]; then
          [ -z "${TAG}" ] && return 1
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Loader" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        elif [ ${opts} -eq 3 ]; then
          mkdir -p "${PART3_PATH}/users"
          dialog --backtitle "$(backtitle)" --title "Update Loader" \
            --msgbox "Upload the update-*.zip File to ${PART3_PATH}/users\nand press OK after upload is done." 0 0
          [ $? -ne 0 ] && return 1
          UPDATEFOUND="false"
          for UPDATEFILE in "${PART3_PATH}/users/update-*.zip"; do
            if [ -e "${UPDATEFILE}" ]; then
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
        fi
        updateLoader "${TAG}"
        ;;
      2)
        dependenciesUpdate
        ;;
      3)
        updateConfigs
        checkHardwareID
        ;;
      4)
        dialog --backtitle "$(backtitle)" --title "Switch Arc Branch" \
          --menu "Choose a Branch" 0 0 0 \
          1 "evo - New Evolution System" \
          2 "minimal - Minimal System" \
          3 "dev - Development System" \
          2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts="$(cat "${TMP_PATH}/opts")"
        if [ ${opts} -eq 1 ]; then
          export ARC_BRANCH="evo"
        elif [ ${opts} -eq 2 ]; then
          export ARC_BRANCH="minimal"
        elif [ ${opts} -eq 3 ]; then
          export ARC_BRANCH="dev"
        fi
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
  if [ "${DT}" = "false" ] && [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
    getmapSelection
  fi
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  return
}

###############################################################################
# Show Storagemenu to user
function networkMenu() {
  # Get Network Config for Loader
  getnet
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  return
}

###############################################################################
# Shows Systeminfo to user
function sysinfo() {
  # Get System Informations
  [ -d /sys/firmware/efi ] && BOOTSYS="UEFI" || BOOTSYS="BIOS"
  USERID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
  CPU="$(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}')"
  GOVERNOR="$(readConfigKey "governor" "${USER_CONFIG_FILE}")"
  SECURE=$(dmesg 2>/dev/null | grep -i "Secure Boot" | awk -F'] ' '{print $2}')
  VENDOR=$(dmesg 2>/dev/null | grep -i "DMI:" | head -1 | sed 's/\[.*\] DMI: //i')
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  ETHN=$(echo ${ETHX} | wc -w)
  HWID="$(genHWID)"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
    DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
    KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
    ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
    ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
    REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
    if [ "${REMAP}" = "acports" ] || [ "${REMAP}" = "maxports" ]; then
      PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
      DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" = "remap" ]; then
      PORTMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" = "ahci" ]; then
      AHCIPORTMAP="$(readConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}")"
    fi
    USERCMDLINEINFO="$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")"
    USERSYNOINFO="$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")"
  fi
  [ "${CONFDONE}" = "true" ] && BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
  CONFIGVER="$(readConfigKey "arc.version" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
  USBMOUNT="$(readConfigKey "usbmount" "${USER_CONFIG_FILE}")"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  HARDDRIVES="$(readConfigKey "device.harddrives" "${USER_CONFIG_FILE}")"
  DRIVES="$(readConfigKey "device.drives" "${USER_CONFIG_FILE}")"
  MODULESINFO="$(lsmod | awk -F' ' '{print $1}' | grep -v 'Module')"
  MODULESVERSION="$(cat "${MODULES_PATH}/VERSION")"
  ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")"
  LKMVERSION="$(cat "${LKMS_PATH}/VERSION")"
  CONFIGSVERSION="$(cat "${MODEL_CONFIG_PATH}/VERSION")"
  PATCHESVERSION="$(cat "${PATCH_PATH}/VERSION")"
  TIMEOUT=5
  # Print System Informations
  TEXT="\n\Z4> System: ${MACHINE} | ${BOOTSYS} | ${BUS}\Zn"
  TEXT+="\n  Vendor: \Zb${VENDOR}\Zn"
  TEXT+="\n  CPU: \Zb${CPU}\Zn"
  if [ $(lspci -d ::300 | wc -l) -gt 0 ]; then
    GPUNAME=""
    for PCI in $(lspci -d ::300 | awk '{print $1}'); do
      GPUNAME+="$(lspci -s ${PCI} | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')"
    done
    TEXT+="\n  GPU: \Zb${GPUNAME}\Zn"
  fi
  TEXT+="\n  Memory: \Zb$((${RAMTOTAL}))GB\Zn"
  TEXT+="\n  AES | ACPI: \Zb${AESSYS} | ${ACPISYS}\Zn"
  TEXT+="\n  CPU Scaling | Governor: \Zb${CPUFREQ} | ${GOVERNOR}\Zn"
  TEXT+="\n  Secure Boot: \Zb${SECURE}\Zn"
  TEXT+="\n  Bootdisk: \Zb${LOADER_DISK}\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4> Network: ${ETHN} NIC\Zn"
  for N in ${ETHX}; do
    COUNT=0
    DRIVER="$(basename "$(realpath "/sys/class/net/${N}/device/driver" 2>/dev/null)" 2>/dev/null)"
    MAC="$(cat "/sys/class/net/${N}/address" 2>/dev/null)"
    while true; do
      if [ -z "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
        TEXT+="\n   ${DRIVER} (${MAC}): \ZbDOWN\Zn"
        break
      fi
      if [ "0" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
        TEXT+="\n   ${DRIVER} (${MAC}): \ZbNOT CONNECTED\Zn"
        break
      fi
      if [ ${COUNT} -ge ${TIMEOUT} ]; then
        TEXT+="\n   ${DRIVER} (${MAC}): \ZbTIMEOUT\Zn"
        break
      fi
      COUNT=$((${COUNT} + 1))
      IP="$(getIP "${N}")"
      if [ -n "${IP}" ]; then
        SPEED="$(ethtool ${N} 2>/dev/null | grep "Speed:" | awk '{print $2}')"
        if [[ "${IP}" =~ ^169\.254\..* ]]; then
          TEXT+="\n   ${DRIVER} (${SPEED} | ${MAC}): \ZbLINK LOCAL (No DHCP server found.)\Zn"
        else
          TEXT+="\n   ${DRIVER} (${SPEED} | ${MAC}): \Zb${IP}\Zn"
        fi
        break
      fi
      sleep 1
    done
  done
  # Print Config Informations
  TEXT+="\n\n\Z4> Arc: ${ARC_VERSION} (${ARC_BUILD}) ${ARC_BRANCH}\Zn"
  TEXT+="\n  Subversion: \ZbAddons ${ADDONSVERSION} | Configs ${CONFIGSVERSION} | LKM ${LKMVERSION} | Modules ${MODULESVERSION} | Patches ${PATCHESVERSION}\Zn"
  TEXT+="\n  Config | Build: \Zb${CONFDONE} | ${BUILDDONE}\Zn"
  TEXT+="\n  Config Version: \Zb${CONFIGVER}\Zn"
  TEXT+="\n  HardwareID: \Zb${HWID}\Zn"
  TEXT+="\n  Offline Mode: \Zb${ARC_OFFLINE}\Zn"
  if [ "${CONFDONE}" = "true" ]; then
    TEXT+="\n\Z4> DSM ${PRODUCTVER} (${BUILDNUM}): ${MODELID:-${MODEL}}\Zn"
    TEXT+="\n  Kernel | LKM: \Zb${KVER} | ${LKM}\Zn"
    TEXT+="\n  Platform | DeviceTree: \Zb${PLATFORM} | ${DT}\Zn"
    TEXT+="\n  Arc Patch: \Zb${ARC_PATCH}\Zn"
    TEXT+="\n  Kernelload: \Zb${KERNELLOAD}\Zn"
    TEXT+="\n  Directboot: \Zb${DIRECTBOOT}\Zn"
    TEXT+="\n  Addons selected: \Zb${ADDONSINFO}\Zn"
  else
    TEXT+="\n"
    TEXT+="\n  Config not completed!\n"
  fi
  TEXT+="\n  Modules loaded: \Zb${MODULESINFO}\Zn"
  if [ "${CONFDONE}" = "true" ]; then
    [ -n "${USERCMDLINEINFO}" ] && TEXT+="\n  User Cmdline: \Zb${USERCMDLINEINFO}\Zn"
    TEXT+="\n  User Synoinfo: \Zb${USERSYNOINFO}\Zn"
  fi
  TEXT+="\n"
  TEXT+="\n\Z4> Settings\Zn"
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
    [ ${PORTNUM} -eq 0 ] && continue
    TEXT+="\Zb   ${NAME}\Zn\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(ls -l /sys/class/scsi_host 2>/dev/null | grep usb | wc -l) -gt 0 ] && TEXT+="\n  USB Controller:\n"
  for PCI in $(lspci -d ::c03 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    TEXT+="\Zb   ${NAME}\Zn\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(ls -l /sys/block/mmc* 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  MMC Controller:\n"
  for PCI in $(lspci -d ::805 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/mmc* 2>/dev/null | grep "${PCI}" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
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
      websites=("google.com" "github.com" "auxxxilium.tech")
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
        echo -e "Arc UserID API reachable! (${USERIDAPI})"
      fi
      GITHUBAPI=$(curl --interface "${N}" -skL -m 10 "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1 2>/dev/null)
      if [[ $? -ne 0 || -z "${GITHUBAPI}" ]]; then
        echo -e "Github API not reachable!"
      else
        echo -e "Github API reachable!"
      fi
      if [ "${CONFDONE}" = "true" ]; then
        SYNOAPI=$(curl --interface "${N}" -skL -m 10 "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}" | jq -r '.info.system.detail[0].items[0].files[0].url')
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
  # Print Credits Informations
  TEXT=""
  TEXT+="\n\Z4> Arc Loader:\Zn"
  TEXT+="\n  Github: \Zbhttps://github.com/AuxXxilium\Zn"
  TEXT+="\n  Website: \Zbhttps://auxxxilium.tech\Zn"
  TEXT+="\n  Wiki: \Zbhttps://auxxxilium.tech/wiki\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Developer:\Zn"
  TEXT+="\n   Arc Loader: \ZbAuxXxilium / Fulcrum\Zn"
  TEXT+="\n   Arc Evo Base: \ZbVisionZ\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Based on:\Zn"
  TEXT+="\n   Redpill: \ZbTTG / Pocopico\Zn"
  TEXT+="\n   ARPL/RR: \Zbfbelavenuto / wjz304\Zn"
  TEXT+="\n   Others: \Zb007revad / PeterSuh-Q3 / more...\Zn"
  TEXT+="\n   DSM: \ZbSynology Inc.\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Note:\Zn"
  TEXT+="\n   Arc and all not encrypted Parts are OpenSource."
  TEXT+="\n   The encrypted Parts and DSM are licensed to"
  TEXT+="\n   Synology Inc. and are not under GPL!"
  TEXT+="\n"
  TEXT+="\n   Commercial use is not permitted!"
  TEXT+="\n"
  TEXT+="\n   This Loader is FREE and it is forbidden"
  TEXT+="\n   to sell Arc or Parts of it."
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
            if [ "1" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
              ip addr flush dev ${N}
              ip addr add ${address}/${netmask:-"255.255.255.0"} dev ${N}
              if [ -n "${gateway}" ]; then
                ip route add default via ${gateway} dev ${N}
              fi
              if [ -n "${dnsname:-${gateway}}" ]; then
                sed -i "/nameserver ${dnsname:-${gateway}}/d" /etc/resolv.conf
                echo "nameserver ${dnsname:-${gateway}}" >>/etc/resolv.conf
              fi
            fi
            writeConfigKey "network.${MACR}" "${address}/${netmask}/${gateway}/${dnsname}" "${USER_CONFIG_FILE}"
            sleep 1
          fi
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
      # fixDSMRootPart "${I}"
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
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
    # fixDSMRootPart "${I}"
    mount -t ext4 "${I}" "${TMP_PATH}/mdX"
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
    VALUE="$(cat "${TMP_PATH}/resp")"
    [ -n "${VALUE}" ] && break
    dialog --backtitle "$(backtitle)" --title "Reset Password" \
      --msgbox "Invalid password" 0 0
  done
  #NEWPASSWD="$(python -c "from passlib.hash import sha512_crypt;pw=\"${VALUE}\";print(sha512_crypt.using(rounds=5000).hash(pw))")"
  NEWPASSWD="$(openssl passwd -6 -salt $(openssl rand -hex 8) "${VALUE}")"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      # fixDSMRootPart "${I}"
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      sed -i "s|^${USER}:[^:]*|${USER}:${NEWPASSWD}|" "${TMP_PATH}/mdX/etc/shadow"
      sed -i "/^${USER}:/ s/^\(${USER}:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\)[^:]*:/\1:/" "${TMP_PATH}/mdX/etc/shadow"
      sed -i "s|status=on|status=off|g" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${USER}/method.config" 2>/dev/null
      sync
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX" >/dev/null
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Reset Password" \
    --progressbox "Resetting ..." 20 100
  dialog --backtitle "$(backtitle)" --title "Reset Password" \
    --msgbox "Password Reset completed." 0 0
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
    ONBOOTUP=""
    ONBOOTUP="${ONBOOTUP}if synouser --enum local | grep -q ^${username}\$; then synouser --setpw ${username} ${password}; else synouser --add ${username} ${password} arc 0 user@arc.arc 1; fi\n"
    ONBOOTUP="${ONBOOTUP}synogroup --memberadd administrators ${username}\n"
    ONBOOTUP="${ONBOOTUP}echo \"DELETE FROM task WHERE task_name LIKE ''ARCONBOOTUPARC_ADDUSER'';\" | sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db\n"

    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      # fixDSMRootPart "${I}"
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        sqlite3 "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" <<EOF
DELETE FROM task WHERE task_name LIKE 'ARCONBOOTUPARC_ADDUSER';
INSERT INTO task VALUES('ARCONBOOTUPARC_ADDUSER', '', 'bootup', '', 1, 0, 0, 0, '', 0, '$(echo -e ${ONBOOTUP})', 'script', '{}', '', '', '{}', '{}');
EOF
        sleep 1
        sync
        echo "true" >${TMP_PATH}/isEnable
      fi
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX" >/dev/null
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Add DSM User" \
    --progressbox "Adding ..." 20 100
  [ "$(cat ${TMP_PATH}/isEnable 2>/dev/null)" = "true" ] && MSG="Add DSM User successful." || MSG="Add DSM User failed."
  dialog --backtitle "$(backtitle)" --title "Add DSM User" \
    --msgbox "${MSG}" 0 0
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
# Change Arc Loader Password
function loaderPorts() {
  MSG="Modify Ports (0-65535) (Leave empty for default):"
  unset HTTPPORT DUFSPORT TTYDPORT
  [ -f "/etc/arc.conf" ] && source "/etc/arc.conf" 2>/dev/null
  local HTTP=${HTTPPORT:-80}
  local DUFS=${DUFSPORT:-7304}
  local TTYD=${TTYDPORT:-7681}
  while true; do
    dialog --backtitle "$(backtitle)" --title "Loader Ports" \
      --form "${MSG}" 11 70 3 "HTTP" 1 1 "${HTTPPORT:-80}" 1 10 55 0 "DUFS" 2 1 "${DUFSPORT:-7304}" 2 10 55 0 "TTYD" 3 1 "${TTYDPORT:-7681}" 3 10 55 0 \
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
      [ "${HTTPPORT:-80}" != "80" ] && echo "HTTP_PORT=${HTTPPORT}" >>"/etc/arc.conf"
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
        [ ! "${HTTP:-80}" = "${HTTPPORT:-80}" ] && echo "/etc/init.d/S90thttpd restart"
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
      # fixDSMRootPart "${I}"
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      if [ $? -ne 0 ]; then
        continue
      fi
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        echo "UPDATE task SET enable = 0;" | sqlite3 "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db"
        sync
        echo "true" > "${TMP_PATH}/isEnable"
      fi
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Scheduled Tasks" \
    --progressbox "Modifying..." 20 100
  if [ "$(cat ${TMP_PATH}/isEnable 2>/dev/null)" = "true" ]; then
    MSG="Disable all scheduled tasks successful."
  else
    MSG="Disable all scheduled tasks failed."
  fi
  dialog --backtitle "$(backtitle)" --title "Scheduled Tasks" \
    --msgbox "${MSG}" 0 0
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
    if [[ "${I}" = /dev/mmc* ]]; then
      echo y | mkfs.ext4 -T largefile4 -E nodiscard "${I}"
    else
      echo y | mkfs.ext4 -T largefile4 "${I}"
    fi
  done 2>&1 | dialog --backtitle "$(backtitle)" --title "Format Disks" \
    --progressbox "Formatting ..." 20 100
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
    SIZE=$(df -m ${resp} 2>/dev/null | awk 'NR=2 {print $2}')
    if [ ${SIZE:-0} -lt 1024 ]; then
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

    NEW_BLDISK_P1="$(lsblk "${resp}" -pno KNAME,LABEL 2>/dev/null | grep 'ARC1' | awk '{print $1}')"
    NEW_BLDISK_P2="$(lsblk "${resp}" -pno KNAME,LABEL 2>/dev/null | grep 'ARC2' | awk '{print $1}')"
    NEW_BLDISK_P3="$(lsblk "${resp}" -pno KNAME,LABEL 2>/dev/null | grep 'ARC3' | awk '{print $1}')"
    SIZEOFDISK=$(cat /sys/block/${resp/\/dev\//}/size)
    ENDSECTOR=$(($(fdisk -l ${resp} | grep "${NEW_BLDISK_P3}" | awk '{print $3}') + 1))

    if [ ${SIZEOFDISK}0 -ne ${ENDSECTOR}0 ]; then
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

    if [ ${SIZEOLD1:-0} -ge ${SIZENEW1:-0} ] || [ ${SIZEOLD2:-0} -ge ${SIZENEW2:-0} ] || [ ${SIZEOLD3:-0} -ge ${SIZENEW3:-0} ]; then
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
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null
  fi
  [ -d "${UNTAR_PAT_PATH}" ] && rm -rf "${UNTAR_PAT_PATH}" >/dev/null
  [ -f "${USER_CONFIG_FILE}" ] && rm -f "${USER_CONFIG_FILE}" >/dev/null
  [ -f "${ARC_RAMDISK_USER_FILE}" ] && rm -f "${ARC_RAMDISK_USER_FILE}" >/dev/null
  [ -f "${HOME}/.initialized" ] && rm -f "${HOME}/.initialized" >/dev/null
  dialog --backtitle "$(backtitle)" --title "Reset Loader" --aspect 18 \
    --yesno "Reset successful.\nReboot required!" 0 0
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
      # fixDSMRootPart "${I}"
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      mkdir -p "${TMP_PATH}/logs/md0/log"
      cp -rf ${TMP_PATH}/mdX/.log.junior "${TMP_PATH}/logs/md0"
      cp -rf ${TMP_PATH}/mdX/var/log/messages ${TMP_PATH}/mdX/var/log/*.log "${TMP_PATH}/logs/md0/log"
      SYSLOG=1
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX" >/dev/null
  fi
  if [ ${SYSLOG} -eq 1 ]; then
    MSG+="System logs found!\n"
  else
    MSG+="Can't find system logs!\n"
  fi

  ADDONS=0
  if [ -d "${PART1_PATH}/logs" ]; then
    mkdir -p "${TMP_PATH}/logs/addons"
    cp -rf "${PART1_PATH}/logs"/* "${TMP_PATH}/logs/addons"
    ADDONS=1
  fi
  if [ ${ADDONS} -eq 1 ]; then
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
    URL="http://${IPCON}${HTTPPORT:+:$HTTPPORT}/logs.tar.gz"
    MSG+="Please via ${URL} to download the logs,\nAnd go to Github or Discord to create an issue and upload the logs."
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
    URL="http://${IPCON}${HTTPPORT:+:$HTTPPORT}/dsmconfig.tar.gz"
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
  echo "0 \"Create SATA node(ARC)\"" >>"${TMP_PATH}/opts"
  echo "1 \"Native SATA Disk(SYNO)\"" >>"${TMP_PATH}/opts"
  echo "2 \"Fake SATA DOM(Redpill)\"" >>"${TMP_PATH}/opts"
  dialog --backtitle "$(backtitle)" --title "Switch SATA DOM" \
    --default-item "${SATADOM}" --menu  "Choose an Option" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return
  SATADOM=${resp}
  writeConfigKey "satadom" "${SATADOM}" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  return
}

###############################################################################
# Reboot Menu
function rebootMenu() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  rm -f "${TMP_PATH}/opts" >/dev/null
  touch "${TMP_PATH}/opts"
  # Selectable Reboot Options
  echo -e "config \"Arc: Config Mode\"" >>"${TMP_PATH}/opts"
  echo -e "update \"Arc: Automated Update Mode\"" >>"${TMP_PATH}/opts"
  echo -e "network \"Arc: Restart Network Service\"" >>"${TMP_PATH}/opts"
  if [ "${BUILDDONE}" = "true" ]; then
    echo -e "recovery \"DSM: Recovery Mode\"" >>"${TMP_PATH}/opts"
    echo -e "junior \"DSM: Reinstall Mode\"" >>"${TMP_PATH}/opts"
  fi
  echo -e "uefi \"System: UEFI\"" >>"${TMP_PATH}/opts"
  echo -e "poweroff \"System: Shutdown\"" >>"${TMP_PATH}/opts"
  echo -e "shell \"System: Shell Cmdline\"" >>"${TMP_PATH}/opts"
  dialog --backtitle "$(backtitle)" --title "Power Menu" \
    --menu  "Choose a Destination" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return
  REDEST=${resp}
  dialog --backtitle "$(backtitle)" --title "Power Menu" \
    --infobox "Option: ${REDEST} selected ...!" 3 50
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
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      # fixDSMRootPart "${I}"
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      rm -f "${TMP_PATH}/mdX/etc.defaults/sysconfig/network-scripts/ifcfg-bond"* "${TMP_PATH}/mdX/etc.defaults/sysconfig/network-scripts/ifcfg-eth"*
      sync
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Reset DSM Network" \
    --progressbox "Resetting ..." 20 100
  MSG="The network settings have been resetted."
  dialog --backtitle "$(backtitle)" --title "Reset DSM Network" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Mount DSM Storage Pools
function mountDSM() {
  vgscan >/dev/null 2>&1
  vgchange -ay >/dev/null 2>&1
  VOLS="$(lvdisplay 2>/dev/null | grep 'LV Path' | grep -v 'syno_vg_reserved_area' | awk '{print $3}')"
  if [ -z "${VOLS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Mount DSM Pool" \
      --msgbox "No storage pool found!" 0 0
    return
  fi
  for I in ${VOLS}; do
    NAME="$(echo "${I}" | awk -F'/' '{print $3"_"$4}')"
    mkdir -p "/mnt/DSM/${NAME}"
    umount "${I}" 2>/dev/null
    mount ${I} "/mnt/DSM/${NAME}" -o ro
  done
  MSG="Storage pools are mounted at /mnt/DSM.\nPlease check them via ${IPCON}:7304."
  dialog --backtitle "$(backtitle)" --title "Mount DSM Pool" \
    --msgbox "${MSG}" 6 50
  if [ -n "${VOLS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Mount DSM Pool" \
      --yesno "Unmount all storage pools?" 5 30
    [ $? -ne 0 ] && return
    for I in ${VOLS}; do
      umount "${I}" 2>/dev/null
    done
    rm -rf /mnt/DSM
  fi
  return
}

###############################################################################
# CPU Governor Menu
function governorMenu () {
  governorSelection
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  return
}

function governorSelection () {
  rm -f "${TMP_PATH}/opts" >/dev/null
  touch "${TMP_PATH}/opts"
  # Selectable CPU governors
  [ "${PLATFORM}" = "epyc7002" ] && echo -e "schedutil \"use schedutil to scale frequency *\"" >>"${TMP_PATH}/opts"
  [ "${PLATFORM}" != "epyc7002" ] && echo -e "conservative \"use conservative to scale frequency *\"" >>"${TMP_PATH}/opts"
  [ "${PLATFORM}" != "epyc7002" ] && echo -e "ondemand \"use ondemand to scale frequency\"" >>"${TMP_PATH}/opts"
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
}

###############################################################################
# Where the magic happens!
function dtsMenu() {
  # Loop menu
  while true; do
    [ -f "${USER_UP_PATH}/${MODEL}.dts" ] && CUSTOMDTS="Yes" || CUSTOMDTS="No"
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
      if ! tty 2>/dev/null | grep -q "/dev/pts"; then #if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG=""
        MSG+="This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol).\n"
        MSG+="$(printf "Or upload the dts file to %s via DUFS, Will be automatically imported when building." "${USER_UP_PATH}/${MODEL}.dts")"
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
      if [ ${RET} -ne 0 ] || [ -z "${USER_FILE}" ]; then
        dialog --backtitle "$(backtitle)" --title "Custom DTS" \
          --msgbox "Not a valid dts file, please try again!\n\n$(cat "${DTC_ERRLOG}")" 0 0
      else
        [ -d "{USER_UP_PATH}" ] || mkdir -p "${USER_UP_PATH}"
        cp -f "${USER_FILE}" "${USER_UP_PATH}/${MODEL}.dts"
        dialog --backtitle "$(backtitle)" --title "$(TEXT "Custom DTS")" \
          --msgbox "A valid dts file, Automatically import at compile time." 0 0
      fi
      rm -rf "${DTC_ERRLOG}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      ;;
    2)
      rm -f "${USER_UP_PATH}/${MODEL}.dts"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      ;;
    3)
      rm -rf "${TMP_PATH}/model.dts"
      if [ -f "${USER_UP_PATH}/${MODEL}.dts" ]; then
        cp -f "${USER_UP_PATH}/${MODEL}.dts" "${TMP_PATH}/model.dts"
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
          cp -f "${TMP_PATH}/modelEdit.dts" "${USER_UP_PATH}/${MODEL}.dts"
          rm -r "${TMP_PATH}/model.dts" "${TMP_PATH}/modelEdit.dts"
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          break
        fi
      done
      ;;
    *)
      break
      ;;
    esac
  done
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
    if curl -skL "${DSM_URL}" -o "${DSM_FILE}" 2>/dev/null; then
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
    USERID="$(curl -skL -m 10 "https://arc.auxxxilium.tech?hwid=${HWID}" 2>/dev/null)"
    if echo "${USERID}" | grep -qE '^[0-9]+$'; then
      writeConfigKey "arc.hardwareid" "${HWID}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "${USERID}" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "true" "${USER_CONFIG_FILE}"
      export ARC_CONF="true"
      dialog --backtitle "$(backtitle)" --title "HardwareID" \
        --msgbox "HardwareID: ${HWID}\nYour HardwareID is registered to UserID: ${USERID}!\nMake sure you select Arc Patch while configure." 7 70
      break
    else
      USERID=""
      writeConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "false" "${USER_CONFIG_FILE}"
      export ARC_CONF=""
      dialog --backtitle "$(backtitle)" --title "HardwareID" \
        --yes-label "Retry" --no-label "Cancel" --yesno "HardwareID: ${HWID}\nRegister your HardwareID at\nhttps://arc.auxxxilium.tech (Discord Account needed).\nPress Retry after you registered it." 8 60
      [ $? -ne 0 ] && break
      continue
    fi
  done
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ -n "${USERID}" ] && [ "${CONFDONE}" = "true"]; then
    ONLYPATCH="true" && arcPatch
  fi
  return
}

###############################################################################
# Check HardwareID
function checkHardwareID() {
  HWID="$(genHWID)"
  USERID="$(curl -skL -m 10 "https://arc.auxxxilium.tech?hwid=${HWID}" 2>/dev/null)"
  [ ! -f "${S_FILE}.bak" ] && cp -f "${S_FILE}" "${S_FILE}.bak" 2>/dev/null || true
  if echo "${USERID}" | grep -qE '^[0-9]+$'; then
    if curl -skL -m 10 "https://arc.auxxxilium.tech?hwid=${HWID}&userid=${USERID}" -o "${S_FILE}" 2>/dev/null; then
      writeConfigKey "arc.hardwareid" "${HWID}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "${USERID}" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "true" "${USER_CONFIG_FILE}"
      export ARC_CONF="true"
    else
      USERID=""
      writeConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "false" "${USER_CONFIG_FILE}"
      export ARC_CONF=""
      [ -f "${S_FILE}.bak" ] && mv -f "${S_FILE}.bak" "${S_FILE}" 2>/dev/null
    fi
  else
    USERID=""
    writeConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
    writeConfigKey "bootscreen.hwidinfo" "false" "${USER_CONFIG_FILE}"
    export ARC_CONF=""
    [ -f "${S_FILE}.bak" ] && mv -f "${S_FILE}.bak" "${S_FILE}" 2>/dev/null
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
}

###############################################################################
# Get Network Config for Loader
function getnet() {
  generate_and_write_macs() {
    local patch=$1
    local macs="$(generateMacAddress "${MODEL}" "${ETHN}" "${patch}")"

    for i in $(seq 1 "${ETHN}"); do
      local mac="${macs[$((i - 1))]}"
      writeConfigKey "eth$((i - 1))" "${mac}" "${USER_CONFIG_FILE}"
    done
  }

  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  MODEL=$(readConfigKey "model" "${USER_CONFIG_FILE}")
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  ETHN=$(echo "${ETHX}" | wc -w)

  if [ "${ARC_PATCH}" = "user" ]; then
    for N in ${ETHX}; do
      while true; do
        dialog --backtitle "$(backtitle)" --title "Mac Setting" \
          --inputbox "Type a custom Mac for ${N} (Eq. 001132a1b2c3).\nA custom Mac will not be applied to NIC!" 8 50 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        MAC="$(cat "${TMP_PATH}/resp")"
        [ -z "${MAC}" ] && MAC=$(readConfigKey "${N}" "${USER_CONFIG_FILE}")
        [ -z "${MAC}" ] && MAC="$(cat "/sys/class/net/${N}/address" 2>/dev/null)"
        MAC=$(echo "${MAC}" | tr '[:upper:]' '[:lower:]')
        if [ ${#MAC} -eq 12 ]; then
          dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Set Mac for ${N} to ${MAC}!" 5 50
          writeConfigKey "${N}" "${MAC}" "${USER_CONFIG_FILE}"
          break
        else
          dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Invalid MAC - Try again!" 5 50
        fi
      done
    done
  elif [ "${ARC_PATCH}" != "user" ] && [ -n "${ARC_CONF}" ]; then
    generate_and_write_macs "${ARC_PATCH}"
  else
    generate_and_write_macs "false"
  fi
}

###############################################################################
# Generate PortMap
function getmap() {
  # Sata Disks
  SATADRIVES=0
  if [ $(lspci -d ::106 2>/dev/null | wc -l) -gt 0 ]; then
    # Clean old files
    for file in drivesmax drivescon ports remap; do
      > "${TMP_PATH}/${file}"
    done

    DISKIDXMAPIDX=0
    DISKIDXMAP=""
    DISKIDXMAPIDXMAX=0
    DISKIDXMAPMAX=""

    for PCI in $(lspci -d ::106 2>/dev/null | awk '{print $1}'); do
      NUMPORTS=0
      CONPORTS=0
      declare -A HOSTPORTS

      while read -r LINE; do
        PORT=$(echo ${LINE} | grep -o 'ata[0-9]*' | sed 's/ata//')
        HOSTPORTS[${PORT}]=$(echo ${LINE} | grep -o 'host[0-9]*$')
      done < <(ls -l /sys/class/scsi_host | grep -F "${PCI}")

      for PORT in $(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n); do
        ATTACH=$(ls -l /sys/block | grep -F -q "${PCI}/ata${PORT}" && echo 1 || echo 0)
        PCMD=$(cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd)
        DUMMY=$([ ${PCMD} = 0 ] && echo 1 || echo 0)

        [ ${ATTACH} = 1 ] && CONPORTS=$((CONPORTS + 1)) && echo $((PORT - 1)) >>"${TMP_PATH}/ports"
        NUMPORTS=$((NUMPORTS + 1))
      done

      NUMPORTS=$((NUMPORTS > 8 ? 8 : NUMPORTS))
      CONPORTS=$((CONPORTS > 8 ? 8 : CONPORTS))

      echo -n "${NUMPORTS}" >>"${TMP_PATH}/drivesmax"
      echo -n "${CONPORTS}" >>"${TMP_PATH}/drivescon"
      DISKIDXMAP+=$(printf "%02x" $DISKIDXMAPIDX)
      DISKIDXMAPIDX=$((DISKIDXMAPIDX + CONPORTS))
      DISKIDXMAPMAX+=$(printf "%02x" $DISKIDXMAPIDXMAX)
      DISKIDXMAPIDXMAX=$((DISKIDXMAPIDXMAX + NUMPORTS))
      SATADRIVES=$((SATADRIVES + CONPORTS))
    done
  fi

  # SAS Disks
  SASDRIVES=0
  if [ $(lspci -d ::107 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::107 2>/dev/null | awk '{print $1}'); do
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n 2>/dev/null)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      SASDRIVES=$((SASDRIVES + PORTNUM))
    done
  fi

  # SCSI Disks
  SCSIDRIVES=0
  if [ $(lspci -d ::100 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::100 2>/dev/null | awk '{print $1}'); do
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n 2>/dev/null)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      SCSIDRIVES=$((SCSIDRIVES + PORTNUM))
    done
  fi

  # Raid Disks
  RAIDDRIVES=0
  if [ $(lspci -d ::104 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::104 2>/dev/null | awk '{print $1}'); do
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n 2>/dev/null)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      RAIDDRIVES=$((RAIDDRIVES + PORTNUM))
    done
  fi

  # NVMe Disks
  NVMEDRIVES=0
  if [ $(ls -l /sys/class/nvme 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::108 2>/dev/null | awk '{print $1}'); do
      PORTNUM=$(ls -l /sys/class/nvme | grep "${PCI}" | wc -l 2>/dev/null)
      [ ${PORTNUM} -eq 0 ] && continue
      NVMEDRIVES=$((NVMEDRIVES + PORTNUM))
    done
  fi

  # USB Disks
  USBDRIVES=0
  if [ $(ls -l /sys/class/scsi_host 2>/dev/null | grep usb | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::c03 2>/dev/null | awk '{print $1}'); do
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n 2>/dev/null)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      USBDRIVES=$((USBDRIVES + PORTNUM))
    done
  fi

  # MMC Disks
  MMCDRIVES=0
  if [ $(ls -l /sys/block/mmc* 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::805 | awk '{print $1}'); do
      PORTNUM=$(ls -l /sys/block/mmc* | grep "${PCI}" | wc -l 2>/dev/null)
      [ ${PORTNUM} -eq 0 ] && continue
      MMCDRIVES=$((MMCDRIVES + PORTNUM))
    done
  fi

  # Disk Count for MaxDisks
  DRIVES=$((${SATADRIVES} + ${SASDRIVES} + ${SCSIDRIVES} + ${RAIDDRIVES} + ${USBDRIVES} + ${MMCDRIVES} + ${NVMEDRIVES}))
  HARDDRIVES=$((${SATADRIVES} + ${SASDRIVES} + ${SCSIDRIVES} + ${RAIDDRIVES} + ${NVMEDRIVES}))
  writeConfigKey "device.satadrives" "${SATADRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.sasdrives" "${SASDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.scsidrives" "${SCSIDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.raiddrives" "${RAIDDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.usbdrives" "${USBDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.mmcdrives" "${MMCDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.nvmedrives" "${NVMEDRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.drives" "${DRIVES}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.harddrives" "${HARDDRIVES}" "${USER_CONFIG_FILE}"

  # Check for Sata Boot
  if [ $(lspci -d ::106 2>/dev/null | wc -l) -gt 0 ]; then
    LASTDRIVE=0
    while read -r D; do
      if [ "${BUS}" = "sata" ] && [ "${MACHINE}" != "physical" ] && [ ${D} -eq 0 ]; then
        MAXDISKS=${DRIVES}
        echo -n "${D}>${MAXDISKS}:" >>"${TMP_PATH}/remap"
      elif [ ${D} -ne ${LASTDRIVE} ]; then
        echo -n "${D}>${LASTDRIVE}:" >>"${TMP_PATH}/remap"
        LASTDRIVE=$((LASTDRIVE + 1))
      else
        LASTDRIVE=$((D + 1))
      fi
    done < "${TMP_PATH}/ports"
  fi
}

###############################################################################
# Select PortMap
function getmapSelection() {
  # Compute PortMap Options
  SATAPORTMAPMAX=$(awk '{print $1}' "${TMP_PATH}/drivesmax")
  SATAPORTMAP=$(awk '{print $1}' "${TMP_PATH}/drivescon")
  SATAREMAP=$(awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//')
  EXTERNALCONTROLLER=$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")
  
  if [ "${ARC_MODE}" = "config" ]; then
    # Show recommended Option to user
    if [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "true" ] && [ "${MACHINE}" = "physical" ]; then
      REMAP2="*"
    elif [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "false" ]; then
      REMAP3="*"
    else
      REMAP1="*"
    fi
    show_and_set_remap
  else
    # Show recommended Option to user
    if [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "true" ] && [ "${MACHINE}" = "physical" ]; then
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
# Choose PortMap
function show_and_set_remap() {
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

###############################################################################
# Get initial Disk Controller Info
function getdiskinfo() {
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS // 100=SCSI // c03=USB
  declare -A controllers=(
    [satacontroller]=106
    [sascontroller]=107
    [scsicontroller]=100
    [raidcontroller]=104
  )
  external_controller=false
  for controller in "${!controllers[@]}"; do
    count=$(lspci -d ::${controllers[$controller]} 2>/dev/null | wc -l)
    writeConfigKey "device.${controller}" "${count}" "${USER_CONFIG_FILE}"
    if [ "${controller}" != "satacontroller" ] && [ ${count} -gt 0 ]; then
      external_controller=true
    fi
  done
  writeConfigKey "device.externalcontroller" "${external_controller}" "${USER_CONFIG_FILE}"
}

###############################################################################
# Get Network Info
function getnetinfo() {
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  for N in ${ETHX}; do
    IPCON="$(getIP "${N}")"
    [ -n "${IPCON}" ] && break
  done
  IPCON="${IPCON:-noip}"
}

###############################################################################
# Create Microcode for Kernel
function createMicrocode() {
  rm -rf ${TMP_PATH}/kernel
  if [ -d /usr/lib/firmware/amd-ucode ]; then
    mkdir -p ${TMP_PATH}/kernel/x86/microcode
    cat /usr/lib/firmware/amd-ucode/microcode_amd*.bin >${TMP_PATH}/kernel/x86/microcode/AuthenticAMD.bin
  fi
  if [ -d /usr/lib/firmware/intel-ucode ]; then
    mkdir -p ${TMP_PATH}/kernel/x86/microcode
    cat /usr/lib/firmware/intel-ucode/* >${TMP_PATH}/kernel/x86/microcode/GenuineIntel.bin
  fi
  if [ -d ${TMP_PATH}/kernel/x86/microcode ]; then
    (cd ${TMP_PATH} && find kernel 2>/dev/null | cpio -o -H newc -R root:root >"${MC_RAMDISK_FILE}") >/dev/null 2>&1
  fi
}