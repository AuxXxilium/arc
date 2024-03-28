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
  done <<<$(readConfigMap "addons" "${USER_CONFIG_FILE}")
  rm -f "${TMP_PATH}/opts"
  touch "${TMP_PATH}/opts"
  while read -r ADDON DESC; do
    arrayExistItem "${ADDON}" "${!ADDONS[@]}" && ACT="on" || ACT="off"
    echo -e "${ADDON} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
  done <<<$(availableAddons "${PLATFORM}" "${KVER}")
  dialog --backtitle "$(backtitle)" --title "Loader Addons" --aspect 18 \
    --checklist "Select Loader Addons to include.\nPlease read Wiki before choosing anything.\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
    --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(<"${TMP_PATH}/resp")"
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
  done <<<$(readConfigMap "modules" "${USER_CONFIG_FILE}")
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
        done <<<$(getAllModules "${PLATFORM}" "${KVER}")
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
        done <<<$(getAllModules "${PLATFORM}" "${KVER}")
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
  done <<<$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
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
        done <<<$(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
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
  done <<<$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "1 \"Add/edit Synoinfo item\""     >"${TMP_PATH}/menu"
  echo "2 \"Delete Synoinfo item(s)\""    >>"${TMP_PATH}/menu"
  echo "3 \"Show Synoinfo entries\""      >>"${TMP_PATH}/menu"
  echo "4 \"Add optimized Synoinfo\""     >>"${TMP_PATH}/menu"
  echo "5 \"Thermal Shutdown (DT only)\"" >>"${TMP_PATH}/menu"

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
        writeConfigKey "synoinfo.support_oob_ctl" "no" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_trim" "yes" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_disk_hibernation" "yes" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_bde_internal_10g" "no" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_btrfs_dedupe" "yes" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_tiny_btrfs_dedupe" "yes" "${USER_CONFIG_FILE}"
        dialog --backtitle "$(backtitle)" --title "Optimized Synoinfo entries" \
          --aspect 18 --msgbox "Optimized Synoinfo is written to Config." 0 0
        ;;
      5)
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
  done <<<$(cd /usr/share/keymaps/i386/${LAYOUT}; ls *.map.gz)
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
                done <<<$(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
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
                done <<<$(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
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
          tar xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
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
          done <<<$(getAllModules "${PLATFORM}" "${KVER}")
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
  if [[ "${DT}" = "false" && $(lspci -d ::106 | wc -l) -gt 0 ]]; then
    getmapSelection
  fi
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
  # Check if machine has EFI
  [ -d /sys/firmware/efi ] && BOOTSYS="UEFI" || BOOTSYS="Legacy"
  # Get System Informations
  CPU="$(echo $(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}'))"
  VENDOR="$(dmesg 2>/dev/null | grep -i "DMI:" | sed 's/\[.*\] DMI: //i')"
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
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
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  HARDDRIVES="$(readConfigKey "device.harddrives" "${USER_CONFIG_FILE}")"
  DRIVES="$(readConfigKey "device.drives" "${USER_CONFIG_FILE}")"
  MODULESINFO="$(lsmod | awk -F' ' '{print $1}' | grep -v 'Module')"
  MODULESVERSION="$(cat "${MODULES_PATH}/VERSION")"
  ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")"
  LKMVERSION="$(cat "${LKM_PATH}/VERSION")"
  CONFIGSVERSION="$(cat "${MODEL_CONFIG_PATH}/VERSION")"
  PATCHESVERSION="$(cat "${PATCH_PATH}/VERSION")"
  TEXT=""
  # Print System Informations
  TEXT+="\n\Z4> System: ${MACHINE} | ${BOOTSYS}\Zn"
  TEXT+="\n  Vendor: \Zb${VENDOR}\Zn"
  TEXT+="\n  CPU: \Zb${CPU}\Zn"
  TEXT+="\n  Memory: \Zb$((${RAMTOTAL} / 1024))GB\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4> Network: ${NIC} NIC\Zn"
  for ETH in ${ETHX}; do
    IP=""
    STATICIP="$(readConfigKey "static.${ETH}" "${USER_CONFIG_FILE}")"
    DRIVER="$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')"
    MAC="$(readConfigKey "mac.${ETH}" "${USER_CONFIG_FILE}")"
    MACR="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
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
        SPEED=$(ethtool ${ETH} 2>/dev/null | grep "Speed:" | awk '{print $2}')
        TEXT+="\n  ${DRIVER} (${SPEED} | ${MSG}) \ZbIP: ${IP} | Mac: ${MACR} (${MAC})\Zn"
        break
      fi
      if [ ${COUNT} -gt 3 ]; then
        TEXT+="\n  ${DRIVER} \ZbIP: TIMEOUT | MAC: ${MACR} (${MAC})\Zn"
        break
      fi
      sleep 3
      if ethtool ${ETH} 2>/dev/null | grep 'Link detected' | grep -q 'no'; then
        TEXT+="\n  ${DRIVER} \ZbIP: NOT CONNECTED | MAC: ${MACR} (${MAC})\Zn"
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
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS // 100=SCSI // c03=USB
  TEXT+="\n\Z4> Storage\Zn"
  TEXT+="\n  External Controller: \Zb${EXTERNALCONTROLLER}\Zn"
  TEXT+="\n  Drives | Harddrives: \Zb${DRIVES} | ${HARDDRIVES}\Zn"
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
    TEXT+="\n  Raid Controller:\n"
    for PCI in $(lspci -d ::104 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::100 | wc -l) -gt 0 ]; then
    TEXT+="\n  SCSI Controller:\n"
    for PCI in $(lspci -d ::100 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [[ -d "/sys/class/scsi_host" && $(ls -l /sys/class/scsi_host | grep usb | wc -l) -gt 0 ]]; then
    TEXT+="\n  USB Controller:\n"
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
  # Check if machine has EFI
  [ -d /sys/firmware/efi ] && BOOTSYS="UEFI" || BOOTSYS="Legacy"
  # Get System Informations
  CPU="$(echo $(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}'))"
  VENDOR="$(dmesg 2>/dev/null | grep -i "DMI:" | sed 's/\[.*\] DMI: //i')"
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
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
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  HARDDRIVES="$(readConfigKey "device.harddrives" "${USER_CONFIG_FILE}")"
  DRIVES="$(readConfigKey "device.drives" "${USER_CONFIG_FILE}")"
  MODULESINFO="$(lsmod | awk -F' ' '{print $1}' | grep -v 'Module')"
  MODULESVERSION="$(cat "${MODULES_PATH}/VERSION")"
  ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")"
  LKMVERSION="$(cat "${LKM_PATH}/VERSION")"
  CONFIGSVERSION="$(cat "${MODEL_CONFIG_PATH}/VERSION")"
  PATCHESVERSION="$(cat "${PATCH_PATH}/VERSION")"
  TEXT=""
  # Print System Informations
  TEXT+="\nSystem: ${MACHINE} | ${BOOTSYS}"
  TEXT+="\nVendor: ${VENDOR}"
  TEXT+="\nCPU: ${CPU}"
  TEXT+="\nMemory: $((${RAMTOTAL} / 1024))GB"
  TEXT+="\n"
  TEXT+="\nNetwork: ${NIC} NIC"
  for ETH in ${ETHX}; do
    IP=""
    STATICIP="$(readConfigKey "static.${ETH}" "${USER_CONFIG_FILE}")"
    DRIVER="$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')"
    MAC="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
    MACR="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
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
        SPEED=$(ethtool ${ETH} 2>/dev/null | grep "Speed:" | awk '{print $2}')
        TEXT+="\n${DRIVER} (${SPEED} | ${MSG}) IP: ${IP} | Mac: ${MACR} (${MAC})"
        break
      fi
      if [ ${COUNT} -gt 3 ]; then
        TEXT+="\n${DRIVER} IP: TIMEOUT | MAC: ${MACR} (${MAC})"
        break
      fi
      sleep 3
      if ethtool ${ETH} 2>/dev/null | grep 'Link detected' | grep -q 'no'; then
        TEXT+="\n${DRIVER} IP: NOT CONNECTED | MAC: ${MACR} (${MAC})"
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
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS // 100=SCSI // c03=USB
  TEXT+="\nStorage"
  TEXT+="\nExternal Controller: ${EXTERNALCONTROLLER}"
  TEXT+="\nDrives | Harddrives: ${DRIVES} | ${HARDDRIVES}"
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
    TEXT+="\nRaid Controller:\n"
    for PCI in $(lspci -d ::104 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="${NAME}\nDrives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::100 | wc -l) -gt 0 ]; then
    TEXT+="\nSCSI Controller:\n"
    for PCI in $(lspci -d ::100 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="${NAME}\n  Drives: ${PORTNUM}\n"
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
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
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
  TEXT+="\n   ARPL/RR: \Zbfbelavenuto / wjz304\Zn"
  TEXT+="\n   NVMe System: \Zbjim3ma\Zn"
  TEXT+="\n   System: \ZbBuildroot 2023.08.x\Zn"
  TEXT+="\n   DSM: \ZbSynology Inc.\Zn"
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
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
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
        --inputbox "Type a Static IP\nLike: 192.168.0.1" 0 0 "${IPADDR}" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      IPADDR="$(<"${TMP_PATH}/resp")"
      dialog --backtitle "$(backtitle)" --title "DHCP/StaticIP" \
        --inputbox "Type a Netmask\nLike: 24" 0 0 "${NETMASK}" \
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
    # for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
    for I in $(blkid 2>/dev/null | grep -i linux_raid_member | grep -E "/dev/.*1: " | awk -F ":" '{print $1}'); do
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
  for I in $(blkid 2>/dev/null | grep -i linux_raid_member | grep -E "/dev/.*1: " | awk -F ":" '{print $1}'); do
    mount ${I} "${TMP_PATH}/sdX1"
    if [ -f "${TMP_PATH}/sdX1/etc/shadow" ]; then
      while read -r L; do
        U=$(echo "${L}" | awk -F ':' '{if ($2 != "*" && $2 != "!!") print $1;}')
        [ -z "${U}" ] && continue
        E=$(echo "${L}" | awk -F ':' '{if ($8 == "1") print "disabled"; else print "        ";}')
        grep -q "status=on" "${TMP_PATH}/sdX1/usr/syno/etc/packages/SecureSignIn/preference/${U}/method.config" 2>/dev/null
        [ $? -eq 0 ] && S="SecureSignIn" || S="            "
        printf "\"%-36s %-10s %-14s\"\n" "${U}" "${E}" "${S}" >>"${TMP_PATH}/menu"
      done <<<$(cat "${TMP_PATH}/sdX1/etc/shadow")
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
    # for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
    for I in $(blkid 2>/dev/null | grep -i linux_raid_member | grep -E "/dev/.*1: " | awk -F ":" '{print $1}'); do
      mount "${I}" "${TMP_PATH}/sdX1"
      OLDPASSWD="$(cat "${TMP_PATH}/sdX1/etc/shadow" 2>/dev/null | grep "^${USER}:" | awk -F ':' '{print $2}')"
      if [ -n "${NEWPASSWD}" -a -n "${OLDPASSWD}" ]; then
        sed -i "s|${OLDPASSWD}|${NEWPASSWD}|g" "${TMP_PATH}/sdX1/etc/shadow"
        sed -i "/^${USER}:/ s/\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\)/\1:\2:\3:\4:\5:\6:\7::\9/" "${TMP_PATH}/sdX1/etc/shadow"
      fi
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
  while read -r KNAME KMODEL; do
    [ -z "${KNAME}" ] && continue
    [[ "${KNAME}" = /dev/md* ]] && continue
    [ -z "${KMODEL}" ] && KMODEL="${TYPE}"
    echo "${KNAME}" | grep -q "${LOADER_DISK}" && continue
    echo "\"${KNAME}\" \"${KMODEL}\" \"off\"" >>"${TMP_PATH}/opts"
  done <<<$(lsblk -pno KNAME,MODEL,TYPE)
  if [ ! -f "${TMP_PATH}/opts" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
      --msgbox "No disk found!" 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --checklist "Select Disk(s)" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  RESP=$(<"${TMP_PATH}/resp")
  [ -z "${RESP}" ] && return
  dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --yesno "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return
  if [ $(ls /dev/md* 2>/dev/null | wc -l) -gt 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
      --yesno "Warning:\nThe current HDD are in Raid, do you still want to format them?" 0 0
    [ $? -ne 0 ] && return
    for I in $(ls /dev/md* 2>/dev/null); do
      mdadm -S "${I}"
    done
  fi
  (
    for I in ${RESP}; do
      if [[ "${I}" = /dev/mmc* ]]; then
        echo y | mkfs.ext4 -T largefile4 -E nodiscard "${I}"
      else
        echo y | mkfs.ext4 -T largefile4 "${I}"
      fi
    done
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --progressbox "Formatting ..." 20 100
  dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --msgbox "Formatting is complete." 0 0
}

###############################################################################
# let user format disks from inside arc
function forcessh() {
  dialog --backtitle "$(backtitle)" --colors --title "Force SSH" \
    --yesno "Please insert all disks before continuing.\n" 0 0
  [ $? -ne 0 ] && return
  (
    ONBOOTUP=""
    ONBOOTUP="${ONBOOTUP}synowebapi --exec api=SYNO.Core.Terminal method=set version=3 enable_telnet=true enable_ssh=true ssh_port=22 forbid_console=false\n"
    ONBOOTUP="${ONBOOTUP}echo \"DELETE FROM task WHERE task_name LIKE ''ARCONBOOTUPARC'';\" | sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db\n"
    mkdir -p "${TMP_PATH}/sdX1"
    for I in $(blkid 2>/dev/null | grep -i linux_raid_member | grep -E "/dev/.*1: " | awk -F ":" '{print $1}'); do
      mount "${I}" "${TMP_PATH}/sdX1"
      if [ -f "${TMP_PATH}/sdX1/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        sqlite3 ${TMP_PATH}/sdX1/usr/syno/etc/esynoscheduler/esynoscheduler.db <<EOF
DELETE FROM task WHERE task_name LIKE 'ARCONBOOTUPARC';
INSERT INTO task VALUES('ARCONBOOTUPARC', '', 'bootup', '', 1, 0, 0, 0, '', 0, '$(echo -e ${ONBOOTUP})', 'script', '{}', '', '', '{}', '{}');
EOF
        sleep 1
        sync
        echo "true" >${TMP_PATH}/isEnable
      fi
      umount "${I}"
    done
    rm -rf "${TMP_PATH}/sdX1"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Force SSH" \
    --progressbox "Enabling ..." 20 100
  [ "$(cat ${TMP_PATH}/isEnable 2>/dev/null)" = "true" ] && MSG="Telnet&SSH is enabled." || MSG="Telnet&SSH is not enabled."
  dialog --backtitle "$(backtitle)" --colors --title "Force SSH" \
    --msgbox "${MSG}" 0 0
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
    dialog --backtitle "$(backtitle)" --title "Reset Loader" --aspect 18 \
    --yesno "Reset successful.\nReboot required!" 0 0
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
  tar cfz "${PART1_PATH}/log.tar.gz" "${PART1_PATH}/logs"
  mv -f "${PART1_PATH}/log.tar.gz" "${TMP_PATH}/log.tar.gz"
  dialog --backtitle "$(backtitle)" --colors --title "Grep Logs" \
    --msgbox "Logs can be found at /tmp/log.tar.gz" 5 40
}