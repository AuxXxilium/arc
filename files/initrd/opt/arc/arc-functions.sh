###############################################################################
# Permits user edit the user config
function editUserConfig() {
  OLDMODEL="${MODEL}"
  OLDPRODUCTVER="${PRODUCTVER}"
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
  ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}")"
  # read addons from user config
  unset ADDONS
  declare -A ADDONS
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  rm -f "${TMP_PATH}/opts" >/dev/null
  touch "${TMP_PATH}/opts"
  while read -r ADDON DESC; do
    arrayExistItem "${ADDON}" "${!ADDONS[@]}" && ACT="on" || ACT="off"
    if [[ "${ADDON}" == "amepatch" || "${ADDON}" == "sspatch" || "${ADDON}" == "arcdns" ]] && [ -z "${ARCCONF}" ]; then
      continue
    elif [ "${ADDON}" == "codecpatch" ] && [ -n "${ARCCONF}" ]; then
      continue
    elif [ "${ADDON}" == "cpufreqscaling" ] && [[ "${CPUFREQ}" == "false" || "${ACPISYS}" == "false" ]] ; then
      continue
    else
      echo -e "${ADDON} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
    fi
  done < <(availableAddons "${PLATFORM}")
  dialog --backtitle "$(backtitle)" --title "DSM Addons" --colors --aspect 18 \
    --checklist "Select DSM Addons to include.\nAddons: \Z1System Addon\Zn | \Z4App Addon\Zn\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
    --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp=$(cat ${TMP_PATH}/resp)
  unset ADDONS
  declare -A ADDONS
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  for ADDON in ${resp}; do
    USERADDONS["${ADDON}"]=""
    writeConfigKey "addons.\"${ADDON}\"" "" "${USER_CONFIG_FILE}"
  done
  ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  dialog --backtitle "$(backtitle)" --title "DSM Addons" \
    --msgbox "DSM Addons selected:\n${ADDONSINFO}" 7 70
}

###############################################################################
# Permit user select the modules to include
function modulesMenu() {
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  # Modify KVER for Epyc7002
  [ "${PLATFORM}" == "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
      1 "Show selected Modules" \
      2 "Select loaded Modules" \
      3 "Select all Modules" \
      4 "Deselect all Modules" \
      5 "Choose Modules" \
      6 "Add external module" \
      7 "Edit Modules copied to DSM" \
      8 "Force-copy loaded Modules to DSM" \
      9 "Blacklist Modules to prevent loading in DSM" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
      1)
        dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
          --infobox "Reading modules" 0 0
        unset USERMODULES
        declare -A USERMODULES
        while IFS=': ' read -r KEY VALUE; do
          [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
        done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
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
          KOLIST+="$(getdepends "${PLATFORM}" "${KVERP}" "${I}") ${I} "
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
        done < <(getAllModules "${PLATFORM}" "${KVERP}")
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
        rm -f "${TMP_PATH}/opts" >/dev/null
        while read -r ID DESC; do
          arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
          echo "${ID} ${DESC} ${ACT}" >>"${TMP_PATH}/opts"
        done < <(getAllModules "${PLATFORM}" "${KVERP}")
        dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
          --checklist "Select Modules to include" 0 0 0 \
          --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && return 1
        resp=$(cat ${TMP_PATH}/resp)
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
        MSG=""
        MSG+="This function is experimental and dangerous. If you don't know much, please exit.\n"
        MSG+="The imported .ko of this function will be implanted into the corresponding arch's modules package, which will affect all models of the arch.\n"
        MSG+="This program will not determine the availability of imported modules or even make type judgments, as please double check if it is correct.\n"
        MSG+="If you want to remove it, please go to the \"Update\" -> \"Update Modules\" to forcibly update the modules. All imports will be reset.\n"
        MSG+="Do you want to continue?"
        dialog --backtitle "$(backtitle)" --title "External Modules" \
          --yesno "${MSG}" 0 0
        [ $? -ne 0 ] && return
        TMP_UP_PATH=${TMP_PATH}/users
        USER_FILE=""
        rm -rf "${TMP_UP_PATH}" >/dev/null
        mkdir -p "${TMP_UP_PATH}"
        dialog --backtitle "$(backtitle)" --title "External Modules" \
          --ok-label "Proceed" --msgbox "Please upload the *.ko file to /tmp/users.\n- Use SFTP at ${IPCON}:22 User: root PW: arc\n- Use Webclient at http://${IPCON}:7304" 7 50
        for F in $(ls "${TMP_UP_PATH}" 2>/dev/null); do
          USER_FILE="${F}"
          if [ -n "${USER_FILE}" ] && [ "${USER_FILE##*.}" == "ko" ]; then
            addToModules "${PLATFORM}" "${KVERP}" "${TMP_UP_PATH}/${USER_FILE}"
            dialog --backtitle "$(backtitle)" --title "External Modules" \
              --msgbox "Module: ${USER_FILE}\nadded to ${PLATFORM}-${KVERP}" 7 50
            rm -f "${TMP_UP_PATH}/${USER_FILE}" >/dev/null
          else
            dialog --backtitle "$(backtitle)" --title "External Modules" \
              --msgbox "Not a valid file, please try again!" 7 50
          fi
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      7)
        if [ -f "${USER_UP_PATH}/modulelist" ]; then
          cp -f "${USER_UP_PATH}/modulelist" "${TMP_PATH}/modulelist.tmp"
        else
          cp -f "${ARC_PATH}/include/modulelist" "${TMP_PATH}/modulelist.tmp"
        fi
        while true; do
          dialog --backtitle "$(backtitle)" --title "Edit Modules copied to DSM" \
            --editbox "${TMP_PATH}/modulelist.tmp" 0 0 2>"${TMP_PATH}/modulelist.user"
          [ $? -ne 0 ] && return
          [ ! -d "${USER_UP_PATH}" ] && mkdir -p "${USER_UP_PATH}"
          mv -f "${TMP_PATH}/modulelist.user" "${USER_UP_PATH}/modulelist"
          dos2unix "${USER_UP_PATH}/modulelist"
          break
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      8)
        if [ -f "${USER_UP_PATH}/modulelist" ]; then
          cp -f "${USER_UP_PATH}/modulelist" "${TMP_PATH}/modulelist.tmp"
        else
          cp -f "${ARC_PATH}/include/modulelist" "${TMP_PATH}/modulelist.tmp"
        fi
        echo -e "\n\n# Arc Modules" >>"${TMP_PATH}/modulelist.tmp"
        KOLIST=""
        for I in $(lsmod | awk -F' ' '{print $1}' | grep -v 'Module'); do
          KOLIST+="$(getdepends "${PLATFORM}" "${KVERP}" "${I}") ${I} "
        done
        KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
        while read -r ID DESC; do
          for MOD in ${KOLIST[@]}; do
            [ "${MOD}" == "${ID}" ] && echo "F ${ID}.ko" >>"${TMP_PATH}/modulelist.tmp"
          done
        done < <(getAllModules "${PLATFORM}" "${KVERP}")
        [ ! -d "${USER_UP_PATH}" ] && mkdir -p "${USER_UP_PATH}"
        mv -f "${TMP_PATH}/modulelist.tmp" "${USER_UP_PATH}/modulelist"
        dos2unix "${USER_UP_PATH}/modulelist"
        dialog --backtitle "$(backtitle)" --title "Loaded Modules Copy" \
            --msgbox "All loaded Modules will be copied to DSM!" 5 50
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      9)
        MSG=""
        MSG+="The blacklist is used to prevent the kernel from loading specific modules.\n"
        MSG+="The blacklist is a list of module names separated by ','.\n"
        MSG+="For example: \Z4evbug,cdc_ether\Zn\n"
        while true; do
          modblacklist="$(readConfigKey "modblacklist" "${USER_CONFIG_FILE}")"
          dialog --backtitle "$(backtitle)" --title "Blacklist Modules" \
            --inputbox "${MSG}" 12 70 "${modblacklist}" \
            2>${TMP_PATH}/resp
          [ $? -ne 0 ] && break
          VALUE="$(cat "${TMP_PATH}/resp")"
          if [[ ${VALUE} = *" "* ]]; then
            dialog --backtitle "$(backtitle)" --title  "Blacklist Module" \
              --yesno "Invalid list, No spaces should appear, retry?" 0 0
            [ $? -eq 0 ] && continue || break
          fi
          writeConfigKey "modblacklist" "${VALUE}" "${USER_CONFIG_FILE}"
          break
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
  echo "1 \"Add a Cmdline item\""                                >"${TMP_PATH}/menu"
  echo "2 \"Delete Cmdline item(s)\""                           >>"${TMP_PATH}/menu"
  echo "3 \"CPU Fix\""                                          >>"${TMP_PATH}/menu"
  echo "4 \"RAM Fix\""                                          >>"${TMP_PATH}/menu"
  echo "5 \"PCI/IRQ Fix\""                                      >>"${TMP_PATH}/menu"
  echo "6 \"C-State Fix\""                                      >>"${TMP_PATH}/menu"
  echo "7 \"Kernelpanic Behavior\""                             >>"${TMP_PATH}/menu"
    dialog --backtitle "$(backtitle)" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
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
            0) # ok-button
              NAME="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
              VALUE="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
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
            1) # cancel-button
              break
              ;;
            255) # ESC
              # break
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
            continue
          fi
          ITEMS=""
          for I in "${!CMDLINE[@]}"; do
            [ -z "${CMDLINE[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${CMDLINE[${I}]} off "
          done
          dialog --backtitle "$(backtitle)" \
            --checklist "Select cmdline to remove" 0 0 0 ${ITEMS} \
            2>"${TMP_PATH}/resp"
          [ $? -ne 0 ] && break
          resp=$(cat ${TMP_PATH}/resp)
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
          resp=$(cat ${TMP_PATH}/resp)
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
          resp=$(cat ${TMP_PATH}/resp)
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
          resp=$(cat ${TMP_PATH}/resp)
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
          resp=$(cat ${TMP_PATH}/resp)
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
            2>${TMP_PATH}/resp
          [ $? -ne 0 ] && break
          resp=$(cat ${TMP_PATH}/resp)
          [ -z "${resp}" ] && break
          KERNELPANIC=${resp}
          writeConfigKey "kernelpanic" "${KERNELPANIC}" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
    dialog --backtitle "$(backtitle)" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
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
            0) # ok-button
              NAME="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
              VALUE="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
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
            1) # cancel-button
              break
              ;;
            255) # ESC
              # break
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
        RESP=$(cat "${TMP_PATH}/resp")
        [ -z "${RESP}" ] && continue
        for I in ${RESP}; do
          unset SYNOINFO[${I}]
          deleteConfigKey "synoinfo.\"${I}\"" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
    esac
  done
  return
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  dialog --backtitle "$(backtitle)" --default-item "${LAYOUT}" --no-items \
    --cancel-label "Exit" --menu "Choose a Layout" 0 0 0 \
    "azerty" "bepo" "carpalx" "colemak" \
    "dvorak" "fgGIod" "neo" "olpc" "qwerty" "qwertz" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  LAYOUT=$(cat "${TMP_PATH}/resp")
  OPTIONS=""
  while read -r KM; do
    OPTIONS+="${KM::-7} "
  done < <(cd /usr/share/keymaps/i386/${LAYOUT}; ls *.map.gz)
  dialog --backtitle "$(backtitle)" --no-items --default-item "${KEYMAP}" \
    --menu "Choice a keymap" 0 0 0 ${OPTIONS} \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp=$(cat ${TMP_PATH}/resp)
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
  if [ "${CONFDONE}" == "true" ]; then
    while true; do
      STORAGEPANELUSER="$(readConfigKey "addons.storagepanel" "${USER_CONFIG_FILE}")"
      [ -n "${STORAGEPANELUSER}" ] && DISKPANELUSER="$(echo ${STORAGEPANELUSER} | cut -d' ' -f1)" || DISKPANELUSER="RACK_24_Bay"
      [ -n "${STORAGEPANELUSER}" ] && M2PANELUSER="$(echo ${STORAGEPANELUSER} | cut -d' ' -f2)" || M2PANELUSER="1X4"
      ITEMS="$(echo -e "RACK_2_Bay \nRACK_4_Bay \nRACK_8_Bay \nRACK_12_Bay \nRACK_16_Bay \nRACK_24_Bay \nRACK_60_Bay \nTOWER_1_Bay \nTOWER_2_Bay \nTOWER_4_Bay \nTOWER_6_Bay \nTOWER_8_Bay \nTOWER_12_Bay \n")"
      dialog --backtitle "$(backtitle)" --title "StoragePanel" \
        --default-item "${DISKPANELUSER}" --no-items --menu "Choose a Disk Panel" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      resp=$(cat ${TMP_PATH}/resp)
      [ -z "${resp}" ] && break
      STORAGE=${resp}
      ITEMS="$(echo -e "1X2 \n1X4 \n1X8 \n")"
      dialog --backtitle "$(backtitle)" --title "StoragePanel" \
        --default-item "${M2PANELUSER}" --no-items --menu "Choose a M.2 Panel" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      resp=$(cat ${TMP_PATH}/resp)
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
  if [ "${CONFDONE}" == "true" ]; then
    while true; do
        dialog --backtitle "$(backtitle)" --cancel-label "Exit" --menu "SequentialIO" 0 0 0 \
          1 "Enable for SSD Cache" \
          2 "Disable for SSD Cache" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        case "$(cat ${TMP_PATH}/resp)" in
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
  while true; do
    dialog --backtitle "$(backtitle)" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
      1 "Restore Arc Config from DSM" \
      2 "Restore HW Encryption Key from DSM" \
      3 "Backup HW Encryption Key to DSM" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
      1)
        DSMROOTS="$(findDSMRoot)"
        if [ -z "${DSMROOTS}" ]; then
          dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
            --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
          return
        fi
        mkdir -p "${TMP_PATH}/mdX"
        for I in ${DSMROOTS}; do
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
              TEXT="Installation found:\nModel: ${MODELID:-${MODEL}}\nVersion: ${PRODUCTVER}"
              SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
              TEXT+="\nSerial: ${SN}"
              ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
              TEXT+="\nArc Patch: ${ARCPATCH}"
              dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
                --aspect 18 --msgbox "${TEXT}" 0 0
              PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
              DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
              CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
              writeConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
              ARCKEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
              writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
              BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
              break
            fi
          fi
        done
        if [ -f "${USER_CONFIG_FILE}" ]; then
          PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          if [ -n "${PRODUCTVER}" ]; then
            PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
            KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
            # Modify KVER for Epyc7002
            [ "${PLATFORM}" == "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
          fi
          if [ -n "${PLATFORM}" ] && [ -n "${KVERP}" ]; then
            writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
            while read -r ID DESC; do
              writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
            done < <(getAllModules "${PLATFORM}" "${KVERP}")
          fi
          dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
            --aspect 18 --msgbox "Config restore successful!\nDownloading necessary files..." 0 0
          sleep 2
          ARCMODE="automated"
          ARCRESTORE="true"
          arcVersion
        fi
        ;;
      2)
        DSMROOTS="$(findDSMRoot)"
        if [ -z "${DSMROOTS}" ]; then
          dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" \
            --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
          return
        fi
        mkdir -p "${TMP_PATH}/mdX"
        for I in ${DSMROOTS}; do
          mount -t ext4 "${I}" "${TMP_PATH}/mdX"
          if [ -f "${TMP_PATH}/mdX/usr/arc/backup/p2/machine.key" ]; then
            cp -f "${TMP_PATH}/mdX/usr/arc/backup/p2/machine.key" "${PART2_PATH}/machine.key"
            dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
              --msgbox "Encryption Key restore successful!" 0 0
            break
          fi
        done
        if [ -f "${PART2_PATH}/machine.key" ]; then
          dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
            --msgbox "Encryption Key restore successful!" 0 0
        else
          dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
            --msgbox "No Encryption Key found!" 0 0
        fi
        ;;
      3)
        BACKUPKEY="false"
        DSMROOTS="$(findDSMRoot)"
        if [ -z "${DSMROOTS}" ]; then
          dialog --backtitle "$(backtitle)" --title "Backup Encrytion Key" \
            --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
          return
        fi
        (
          mkdir -p "${TMP_PATH}/mdX"
          for I in ${DSMROOTS}; do
            mount -t ext4 "${I}" "${TMP_PATH}/mdX"
            [ $? -ne 0 ] && continue
            if [ -f "${PART2_PATH}/machine.key" ]; then
              cp -f "${PART2_PATH}/machine.key" "${TMP_PATH}/mdX/usr/arc/backup/p2/machine.key"
              BACKUPKEY="true"
              sync
            fi
            umount "${TMP_PATH}/mdX"
          done
          rm -rf "${TMP_PATH}/mdX" >/dev/null
        ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Backup Encrytion Key" \
          --progressbox "Backup Encryption Key ..." 20 70
        if [ "${BACKUPKEY}" == "true" ]; then
          dialog --backtitle "$(backtitle)" --title "Backup Encrytion Key"  \
            --msgbox "Encryption Key backup successful!" 0 0
        else
          dialog --backtitle "$(backtitle)" --title "Backup Encrytion Key"  \
            --msgbox "No Encryption Key found!" 0 0
        fi
        ;;
    esac
  done
}

###############################################################################
# Shows update menu to user
function updateMenu() {
  ARCBRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
  NEXT="1"
  while true; do
    dialog --backtitle "$(backtitle)" --colors --cancel-label "Exit" \
      --menu "Choose an Option" 0 0 0 \
      0 "Buildroot Branch: \Z1${ARCBRANCH}\Zn" \
      1 "Automated Update Mode" \
      2 "Full-Update Loader \Z1(update)\Zn" \
      3 "Full-Upgrade Loader \Z1(reflash)\Zn" \
      4 "\Z4Advanced:\Zn Update Addons" \
      5 "\Z4Advanced:\Zn Update Configs" \
      6 "\Z4Advanced:\Zn Update LKMs" \
      7 "\Z4Advanced:\Zn Update Modules" \
      8 "\Z4Advanced:\Zn Update Patches" \
      9 "\Z4Advanced:\Zn Update Custom Kernel" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
      1)
        dialog --backtitle "$(backtitle)" --title "Automated Update" --aspect 18 \
          --msgbox "Loader will proceed Automated Update Mode.\nPlease wait until progress is finished!" 0 0
        arcUpdate
        ;;
      2)
        # Ask for Tag
        TAG=""
        NEWVER="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
        OLDVER="$(cat ${PART1_PATH}/ARC-VERSION)"
        dialog --clear --backtitle "$(backtitle)" --title "Full-Update Loader" \
          --menu "Current: ${OLDVER} -> Which Version?" 7 50 0 \
          1 "Latest ${NEWVER}" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Full-Update Loader" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        if updateLoader "${TAG}"; then
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          exec reboot && exit 0
        fi
        ;;
      3)
        # Ask for Tag
        TAG=""
        NEWVER="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
        OLDVER="$(cat ${PART1_PATH}/ARC-VERSION)"
        dialog --clear --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --menu "Current: ${OLDVER} -> Which Version?" 7 50 0 \
          1 "Latest ${NEWVER}" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        if upgradeLoader "${TAG}"; then
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          exec reboot && exit 0
        fi
        ;;
      4)
        # Ask for Tag
        TAG=""
        NEWVER="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-addons/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
        OLDVER="$(cat ${ADDONS_PATH}/VERSION)"
        dialog --clear --backtitle "$(backtitle)" --title "Update Addons" \
          --menu "Current: ${OLDVER} -> Which Version?" 7 50 0 \
          1 "Latest ${NEWVER}" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Addons" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        if updateAddons "${TAG}"; then
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        fi
        ;;
      5)
        # Ask for Tag
        TAG=""
        NEWVER="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-configs/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
        OLDVER="$(cat ${MODEL_CONFIG_PATH}/VERSION)"
        dialog --clear --backtitle "$(backtitle)" --title "Update Configs" \
          --menu "Current: ${OLDVER} -> Which Version?" 7 50 0 \
          1 "Latest ${NEWVER}" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Configs" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        if updateConfigs "${TAG}"; then
          writeConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
          ARCKEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
          writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
          ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        fi
        ;;
      6)
        # Ask for Tag
        TAG=""
        NEWVER="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-lkm/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
        OLDVER="$(cat ${LKMS_PATH}/VERSION)"
        dialog --clear --backtitle "$(backtitle)" --title "Update LKMs" \
          --menu "Current: ${OLDVER} -> Which Version?" 7 50 0 \
          1 "Latest ${NEWVER}" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update LKMs" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        if updateLKMs "${TAG}"; then
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        fi
        ;;
      7)
        # Ask for Tag
        TAG=""
        NEWVER="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-modules/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
        OLDVER="$(cat ${MODULES_PATH}/VERSION)"
        dialog --clear --backtitle "$(backtitle)" --title "Update Modules" \
          --menu "Current: ${OLDVER} -> Which Version?" 7 50 0 \
          1 "Latest ${NEWVER}" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Modules" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        if updateModules "${TAG}"; then
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        fi
        ;;
      8)
        # Ask for Tag
        TAG=""
        NEWVER="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-patches/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
        OLDVER="$(cat ${PATCH_PATH}/VERSION)"
        dialog --clear --backtitle "$(backtitle)" --title "Update Patches" \
          --menu "Current: ${OLDVER} -> Which Version?" 7 50 0 \
          1 "Latest ${NEWVER}" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Patches" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        if updatePatches "${TAG}"; then
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        fi
        ;;
      9)
        # Ask for Tag
        TAG=""
        NEWVER="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-custom/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
        OLDVER="$(cat ${CUSTOM_PATH}/VERSION)"
        dialog --clear --backtitle "$(backtitle)" --title "Update Custom" \
          --menu "Current: ${OLDVER} -> Which Version?" 7 50 0 \
          1 "Latest ${NEWVER}" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Custom Kernel" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        if updateCustom "${TAG}"; then
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        fi
        ;;
      0)
        # Ask for Arc Branch
        ARCBRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
        dialog --clear --backtitle "$(backtitle)" --title "Switch Buildroot" \
          --menu "Current: ${ARCBRANCH} -> Which Branch?" 7 50 0 \
          1 "Stable Buildroot" \
          2 "Next Buildroot (latest)" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          writeConfigKey "arc.branch" "stable" "${USER_CONFIG_FILE}"
        elif [ ${opts} -eq 2 ]; then
          writeConfigKey "arc.branch" "next" "${USER_CONFIG_FILE}"
        fi
        ARCBRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Switch Buildroot" --aspect 18 \
          --msgbox "Using ${ARCBRANCH} Buildroot, now.\nUpdate the Loader to apply the changes!" 7 50
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
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
  if [ "${DT}" == "false" ] && [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
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
  # Check if machine has EFI
  [ -d /sys/firmware/efi ] && BOOTSYS="UEFI" || BOOTSYS="BIOS"
  # Get System Informations
  CPU=$(echo $(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}'))
  SECURE=$(dmesg 2>/dev/null | grep -i "Secure Boot" | awk -F'] ' '{print $2}')
  VENDOR=$(dmesg 2>/dev/null | grep -i "DMI:" | sed 's/\[.*\] DMI: //i')
  ETHX="$(ls /sys/class/net 2>/dev/null | grep eth)"
  ETHN="$(echo ${ETHX} | wc -w)"
  ARCBRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" == "true" ]; then
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
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
      PORTMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" == "ahci" ]; then
      AHCIPORTMAP="$(readConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}")"
    fi
    USERCMDLINEINFO="$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")"
    USERSYNOINFO="$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")"
  fi
  [ "${BUILDDONE}" == "true" ] && BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
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
  TEXT=""
  # Print System Informations
  TEXT+="\n\Z4> System: ${MACHINE} | ${BOOTSYS} | ${BUS}\Zn"
  TEXT+="\n  Vendor: \Zb${VENDOR}\Zn"
  TEXT+="\n  CPU: \Zb${CPU}\Zn"
  if [ $(lspci -d ::300 | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::300 | awk '{print $1}'); do
      GPUNAME=$(sudo lspci -s ${PCI} | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      TEXT+="\n  iGPU: \Zb${GPUNAME}\Zn"
    done
  elif [ $(lspci -d ::380 | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::380 | awk '{print $1}'); do
      GPUNAME=$(sudo lspci -s ${PCI} | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      TEXT+="\n  GPU: \Zb${GPUNAME}\Zn"
    done
  fi
  TEXT+="\n  Memory: \Zb$((${RAMTOTAL}))GB\Zn"
  TEXT+="\n  AES | ACPI: \Zb${AESSYS} | ${ACPISYS}\Zn"
  TEXT+="\n  CPU Scaling: \Zb${CPUFREQ}\Zn"
  TEXT+="\n  Secure Boot: \Zb${SECURE}\Zn"
  TEXT+="\n  Bootdisk: \Zb${LOADER_DISK}\Zn"
  [ -n "${REGION}" ] && [ -n "${TIMEZONE}" ] && TEXT+="\n  Timezone: \Zb${REGION}/${TIMEZONE}\Zn"
  TEXT+="\n  Time: \Zb$(date "+%F %H:%M:%S")\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4> Network: ${ETHN} NIC\Zn\n"
  for ETH in ${ETHX}; do
    COUNT=0
    DRIVER=$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    NETBUS=$(ethtool -i ${ETH} 2>/dev/null | grep bus-info | cut -d' ' -f2)
    while true; do
      if ! ip link show ${ETH} 2>/dev/null | grep -q 'UP'; then
        TEXT+="\n${DRIVER}: \ZbDOWN\Zn"
        break
      fi
      if ethtool ${ETH} 2>/dev/null | grep 'Link detected' | grep -q 'no'; then
        TEXT+="\n${DRIVER}: \ZbNOT CONNECTED\Zn"
        break
      fi
      if [ ${COUNT} -ge ${TIMEOUT} ]; then
        TEXT+="\n${DRIVER}: \ZbTIMEOUT\Zn"
        break
      fi
      COUNT=$((${COUNT} + 1))
      IP="$(getIP ${ETH})"
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${ETH} 2>/dev/null | grep "Speed:" | awk '{print $2}')
        if [[ "${IP}" =~ ^169\.254\..* ]]; then
          TEXT+="${DRIVER} (${SPEED}): \ZbLINK LOCAL (No DHCP server found.)\Zn"
        else
          TEXT+="${DRIVER} (${SPEED}): \Zb${IP}\Zn"
        fi
        break
      fi
      sleep 1
    done
    TEXT+="\n\Zb$(lspci -s ${NETBUS} -nnk | awk '{$1=""}1' | awk '{$1=$1};1')\Zn\n"
  done
  # Print Config Informations
  TEXT+="\n\Z4> Arc: ${ARC_VERSION}\Zn"
  TEXT+="\n  Branch: \Zb${ARCBRANCH}\Zn"
  TEXT+="\n  Subversion: \ZbAddons ${ADDONSVERSION} | Configs ${CONFIGSVERSION} | LKM ${LKMVERSION} | Modules ${MODULESVERSION} | Patches ${PATCHESVERSION}\Zn"
  TEXT+="\n  Config | Build: \Zb${CONFDONE} | ${BUILDDONE}\Zn"
  TEXT+="\n  Config Version: \Zb${CONFIGVER}\Zn"
  if [ "${CONFDONE}" == "true" ]; then
    TEXT+="\n\Z4> DSM ${PRODUCTVER} (${BUILDNUM}): ${MODELID:-${MODEL}}\Zn"
    TEXT+="\n  Kernel | LKM: \Zb${KVER} | ${LKM}\Zn"
    TEXT+="\n  Platform | DeviceTree: \Zb${PLATFORM} | ${DT}\Zn"
    TEXT+="\n  Arc Patch: \Zb${ARCPATCH}\Zn"
    TEXT+="\n  Kernelload: \Zb${KERNELLOAD}\Zn"
    TEXT+="\n  Directboot: \Zb${DIRECTBOOT}\Zn"
    TEXT+="\n  Addons selected: \Zb${ADDONSINFO}\Zn"
  else
    TEXT+="\n"
    TEXT+="\n  Config not completed!\n"
  fi
  TEXT+="\n  Modules loaded: \Zb${MODULESINFO}\Zn"
  if [ "${CONFDONE}" == "true" ]; then
    [ -n "${USERCMDLINEINFO}" ] && TEXT+="\n  User Cmdline: \Zb${USERCMDLINEINFO}\Zn"
    TEXT+="\n  User Synoinfo: \Zb${USERSYNOINFO}\Zn"
  fi
  TEXT+="\n"
  TEXT+="\n\Z4> Settings\Zn"
  TEXT+="\n  Offline Mode: \Zb${OFFLINE}\Zn"
  if [[ "${REMAP}" == "acports" || "${REMAP}" == "maxports" ]]; then
    TEXT+="\n  SataPortMap | DiskIdxMap: \Zb${PORTMAP} | ${DISKMAP}\Zn"
  elif [ "${REMAP}" == "remap" ]; then
    TEXT+="\n  SataRemap: \Zb${PORTMAP}\Zn"
  elif [ "${REMAP}" == "ahci" ]; then
    TEXT+="\n  AhciRemap: \Zb${AHCIPORTMAP}\Zn"
  elif [ "${REMAP}" == "user" ]; then
    TEXT+="\n  PortMap: \Zb"User"\Zn"
    [ -n "${PORTMAP}" ] && TEXT+="\n  SataPortmap: \Zb${PORTMAP}\Zn"
    [ -n "${DISKMAP}" ] && TEXT+="\n  DiskIdxMap: \Zb${DISKMAP}\Zn"
    [ -n "${PORTREMAP}" ] && TEXT+="\n  SataRemap: \Zb${PORTREMAP}\Zn"
    [ -n "${AHCIPORTREMAP}" ] && TEXT+="\n  AhciRemap: \Zb${AHCIPORTREMAP}\Zn"
  fi
  if [ "${DT}" == "true" ]; then
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
  if [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
    TEXT+="\n  SATA Controller:\n"
    for PCI in $(lspci -d ::106 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      TEXT+="\Zb  ${NAME}\Zn\n  Ports: "
      PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      for P in ${PORTS}; do
        if lsscsi -b | grep -v - | grep -q "\[${P}:"; then
          DUMMY="$([ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" == "0" ] && echo 1 || echo 2)"
          if [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" == "0" ]; then
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
  if [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
    TEXT+="\n  SAS Controller:\n"
    for PCI in $(lspci -d ::107 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Disks: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::104 | wc -l) -gt 0 ]; then
    TEXT+="\n  Raid Controller:\n"
    for PCI in $(lspci -d ::104 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Disks: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::100 | wc -l) -gt 0 ]; then
    TEXT+="\n  SCSI Controller:\n"
    for PCI in $(lspci -d ::100 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Disks: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [[ -d "/sys/class/scsi_host" && $(ls -l /sys/class/scsi_host | grep usb | wc -l) -gt 0 ]]; then
    TEXT+="\n  USB Controller:\n"
    for PCI in $(lspci -d ::c03 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      TEXT+="\Zb  ${NAME}\Zn\n  Disks: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [[ -d "/sys/class/mmc_host" && $(ls -l /sys/class/mmc_host | grep mmc_host | wc -l) -gt 0 ]]; then
    TEXT+="\n  MMC Controller:\n"
    for PCI in $(lspci -d ::805 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORTNUM=$(ls -l /sys/class/mmc_host | grep "${PCI}" | wc -l)
      PORTNUM=$(ls -l /sys/block/mmc* | grep "${PCI}" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      TEXT+="\Zb  ${NAME}\Zn\n  Disks: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::108 | wc -l) -gt 0 ]; then
    TEXT+="\n  NVMe Controller:\n"
    for PCI in $(lspci -d ::108 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORT=$(ls -l /sys/class/nvme | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[N:${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Disks: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  TEXT+="\n  Total Disks: \Zb${NUMPORTS}\Zn"
  [ -f "${TMP_PATH}/diag" ] && rm -f "${TMP_PATH}/diag" >/dev/null
  echo -e "${TEXT}" >"${TMP_PATH}/diag"
  while true; do
    dialog --backtitle "$(backtitle)" --colors --ok-label "Exit" --help-button --help-label "Show Cmdline" \
      --extra-button --extra-label "Upload" --title "Sysinfo" --msgbox "${TEXT}" 0 0
    RET=$?
    case ${RET} in
      0) # ok-button
        return 0
        break
        ;;
      2) # help-button
        getCMDline
        ;;
      3) # extra-button
        uploadDiag
        ;;
      255) # ESC-button
        return 0
        break
        ;;
    esac
  done
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
  if [ -f "${TMP_PATH}/diag" ]; then
    GENHASH=$(cat "${TMP_PATH}/diag" | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-)
    dialog --backtitle "$(backtitle)" --title "Sysinfo Upload" --msgbox "Your Code: ${GENHASH}" 5 30
  else
    dialog --backtitle "$(backtitle)" --title "Sysinfo Upload" --msgbox "No Diag File found!" 0 0
  fi
  return
}

###############################################################################
# Shows Networkdiag to user
function networkdiag() {
  (
  ETHX="$(ls /sys/class/net 2>/dev/null | grep eth)"
  for ETH in ${ETHX}; do
    echo
    DRIVER=$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    echo -e "Interface: ${ETH} (${DRIVER})"
    if ethtool ${ETH} 2>/dev/null | grep 'Link detected' | grep -q 'no'; then
      echo -e "Link: NOT CONNECTED"
      continue
    fi
    if ! ip link show ${ETH} 2>/dev/null | grep -q 'UP'; then
      echo -e "Link: DOWN"
      continue
    fi
    echo -e "Link: CONNECTED"
    addr=$(getIP ${ETH})
    netmask=$(ifconfig ${ETH} | grep inet | grep 255 | awk '{print $4}' | cut -f2 -d':')
    echo -e "IP Address: ${addr}"
    echo -e "Netmask: ${netmask}"
    echo
    gateway=$(route -n | grep 'UG[ \t]' | awk '{print $2}' | head -n 1)
    echo -e "Gateway: ${gateway}"
    dnsserver=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
    echo -e "DNS Server:\n${dnsserver}"
    echo
    websites=("google.com" "github.com" "auxxxilium.tech")
    for website in "${websites[@]}"; do
      if ping -I ${ETH} -c 1 "${website}" &> /dev/null; then
        echo -e "Connection to ${website} is successful."
      else
        echo -e "Connection to ${website} failed."
      fi
    done
    echo
    GITHUBAPI=$(curl --interface ${ETH} -m 3 -skL https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
    if [[ $? -ne 0 || -z "${GITHUBAPI}" ]]; then
      echo -e "Github API not reachable!"
    else
      echo -e "Github API reachable!"
    fi
    if [ "${CONFDONE}" == "true" ]; then
      SYNOAPI=$(curl --interface ${ETH} -m 3 -skL "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}" | jq -r '.info.system.detail[0].items[0].files[0].url')
      if [[ $? -ne 0 || -z "${SYNOAPI}" ]]; then
        echo -e "Syno API not reachable!"
      else
        echo -e "Syno API reachable!"
      fi
    else
      echo -e "For Syno API Checks you need to configure Loader first!"
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
  TEXT+="\n"
  TEXT+="\n\Z4>> Based on:\Zn"
  TEXT+="\n   Redpill: \ZbTTG / Pocopico\Zn"
  TEXT+="\n   ARPL/RR: \Zbfbelavenuto / wjz304\Zn"
  TEXT+="\n   System: \ZbBuildroot 2024.02.x\Zn"
  TEXT+="\n   DSM: \ZbSynology Inc.\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Note:\Zn"
  TEXT+="\n   Arc and all Parts of it are OpenSource."
  TEXT+="\n   Commercial use is not permitted!"
  TEXT+="\n   This Loader is FREE and it is forbidden"
  TEXT+="\n   to sell Arc or Parts of it."
  TEXT+="\n"
  dialog --backtitle "$(backtitle)" --colors --title "Credits" \
    --msgbox "${TEXT}" 0 0
  return
}

###############################################################################
# allow setting Static IP for Loader
function staticIPMenu() {
  ETHX="$(ls /sys/class/net 2>/dev/null | grep eth)"
  for ETH in ${ETHX}; do
    MACR="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g' | tr '[:lower:]' '[:upper:]')"
    IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
    IFS='/' read -r -a IPRA <<<"${IPR}"

    MSG="$(printf "Set to %s: (Delete if empty)" "${ETH}(${MACR})")"
    while true; do
      dialog --backtitle "$(backtitle)" --title "StaticIP" \
        --form "${MSG}" 10 60 4 "address" 1 1 "${IPRA[0]}" 1 9 36 16 "netmask" 2 1 "${IPRA[1]}" 2 9 36 16 "gateway" 3 1 "${IPRA[2]}" 3 9 36 16 "dns" 4 1 "${IPRA[3]}" 4 9 36 16 \
        2>"${TMP_PATH}/resp"
      RET=$?
      case ${RET} in
      0) # ok-button
        dialog --backtitle "$(backtitle)" --title "StaticIP" \
          --infobox "Setting IP ..." 3 25
        address="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
        netmask="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
        gateway="$(cat "${TMP_PATH}/resp" | sed -n '3p')"
        dnsname="$(cat "${TMP_PATH}/resp" | sed -n '4p')"
        if [ -z "${address}" ]; then
          deleteConfigKey "network.${MACR}" "${USER_CONFIG_FILE}"
        else
          writeConfigKey "network.${MACR}" "${address}/${netmask}/${gateway}/${dnsname}" "${USER_CONFIG_FILE}"
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        break
        ;;
      1) # cancel-button
        break
        ;;
      255) # ESC
        break 2
        ;;
      esac
    done
    sleep 1
  done
  IPCON=""
  dialog --backtitle "$(backtitle)" --title "StaticIP" \
    --infobox "Restart Network ..." 3 25
  for ETH in ${ETHX}; do
    MACR="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g' | tr '[:lower:]' '[:upper:]')"
    IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
    if [ -n "${IPR}" ]; then
      IFS='/' read -r -a IPRA <<<"${IPR}"
      ip addr flush dev ${ETH}
      ip addr add ${IPRA[0]}/${IPRA[1]:-"255.255.255.0"} dev ${ETH}
      [ -z "${IPCON}" ] && IPCON="${IPRA[0]}"
      if [ -n "${IPRA[2]}" ]; then
        ip route add default via ${IPRA[2]} dev ${ETH}
      fi
      if [ -n "${IPRA[3]:-${IPRA[2]}}" ]; then
        sed -i "/nameserver ${IPRA[3]:-${IPRA[2]}}/d" /etc/resolv.conf
        echo "nameserver ${IPRA[3]:-${IPRA[2]}}" >>/etc/resolv.conf
      fi
      sleep 1
    fi
  done
}

###############################################################################
# allow downgrade dsm version
function downgradeMenu() {
  TEXT=""
  TEXT+="This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n"
  TEXT+="Therefore, please insert all disks before continuing.\n"
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
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      [ -f "${TMP_PATH}/mdX/etc/VERSION" ] && rm -f "${TMP_PATH}/mdX/etc/VERSION" >/dev/null
      [ -f "${TMP_PATH}/mdX/etc.defaults/VERSION" ] && rm -f "${TMP_PATH}/mdX/etc.defaults/VERSION" >/dev/null
      sync
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX" >/dev/null
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Allow Downgrade" \
    --progressbox "Removing ..." 20 70
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
    mount -t ext4 "${I}" "${TMP_PATH}/mdX"
    [ $? -ne 0 ] && continue
    if [ -f "${TMP_PATH}/mdX/etc/shadow" ]; then
      while read L; do
        U=$(echo "${L}" | awk -F ':' '{if ($2 != "*" && $2 != "!!") print $1;}')
        [ -z "${U}" ] && continue
        E=$(echo "${L}" | awk -F ':' '{if ($8 == "1") print "disabled"; else print "        ";}')
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
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  USER="$(cat "${TMP_PATH}/resp" 2>/dev/null | awk '{print $1}')"
  [ -z "${USER}" ] && return
  while true; do
    dialog --backtitle "$(backtitle)" --title "Reset Password" \
      --inputbox "Type a new password for user ${USER}" 0 70 \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break 2
    VALUE="$(cat "${TMP_PATH}/resp")"
    [ -n "${VALUE}" ] && break
    dialog --backtitle "$(backtitle)" --title "Reset Password" \
      --msgbox "Invalid password" 0 0
  done
  NEWPASSWD="$(python -c "from passlib.hash import sha512_crypt;pw=\"${VALUE}\";print(sha512_crypt.using(rounds=5000).hash(pw))")"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      OLDPASSWD="$(cat "${TMP_PATH}/mdX/etc/shadow" 2>/dev/null | grep "^${USER}:" | awk -F ':' '{print $2}')"
      if [ -n "${NEWPASSWD}" -a -n "${OLDPASSWD}" ]; then
        sed -i "s|${OLDPASSWD}|${NEWPASSWD}|g" "${TMP_PATH}/mdX/etc/shadow"
        sed -i "/^${USER}:/ s/\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\)/\1:\2:\3:\4:\5:\6:\7::\9/" "${TMP_PATH}/mdX/etc/shadow"
      fi
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
  username="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
  password="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
  (
    ONBOOTUP=""
    ONBOOTUP="${ONBOOTUP}if synouser --enum local | grep -q ^${username}\$; then synouser --setpw ${username} ${password}; else synouser --add ${username} ${password} arc 0 user@arc.arc 1; fi\n"
    ONBOOTUP="${ONBOOTUP}synogroup --memberadd administrators ${username}\n"
    ONBOOTUP="${ONBOOTUP}echo \"DELETE FROM task WHERE task_name LIKE ''ARCONBOOTUPARC_ADDUSER'';\" | sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db\n"

    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        sqlite3 ${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db <<EOF
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
  [ "$(cat ${TMP_PATH}/isEnable 2>/dev/null)" == "true" ] && MSG="Add DSM User successful." || MSG="Add DSM User failed."
  dialog --backtitle "$(backtitle)" --title "Add DSM User" \
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
  resp=$(cat ${TMP_PATH}/resp)
  [ -z "${resp}" ] && return 1
  BOOTIPWAIT=${resp}
  writeConfigKey "bootipwait" "${BOOTIPWAIT}" "${USER_CONFIG_FILE}"
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
  rm -rf "${RDXZ_PATH}/opt/arc" >/dev/null
  cp -Rf "$(dirname ${ARC_PATH})" "${RDXZ_PATH}"
  (cd "${RDXZ_PATH}"; find . 2>/dev/null | cpio -o -H newc -R root:root | xz --check=crc32 >"${PART3_PATH}/initrd-arc") || true
  rm -rf "${RDXZ_PATH}" >/dev/null
  dialog --backtitle "$(backtitle)" --colors --aspect 18 \
    --msgbox "Save to Disk is complete." 0 0
  return
}

###############################################################################
# let user format disks from inside arc
function formatDisks() {
  rm -f "${TMP_PATH}/opts"
  while read -r KNAME SIZE TYPE PKNAME; do
    [ -z "${KNAME}" ] && continue
    [ "${KNAME}" == "N/A" ] && continue
    [[ "${KNAME}" == /dev/md* ]] && continue
    [[ "${KNAME}" == "${LOADER_DISK}" || "${PKNAME}" == "${LOADER_DISK}" ]] && continue
    [ -z "${SIZE}" ] && SIZE="Unknown"
    printf "\"%s\" \"%-6s %-4s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" >>"${TMP_PATH}/opts"
  done < <(lsblk -Jpno KNAME,SIZE,TYPE,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.size) \(.type) \(.pkname)"' 2>/dev/null)
  if [ ! -f "${TMP_PATH}/opts" ]; then
    dialog --backtitle "$(backtitle)" --title "Format Disks" \
      --msgbox "No disk found!" 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --title "Format Disks" \
    --checklist "Select Disks" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  RESP=$(cat "${TMP_PATH}/resp")
  [ -z "${RESP}" ] && return
  dialog --backtitle "$(backtitle)" --title "Format Disks" \
    --yesno "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return
  if [ $(ls /dev/md[0-9]* 2>/dev/null | wc -l) -gt 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Format Disks" \
      --yesno "Warning:\nThe current hds is in raid, do you still want to format them?" 0 0
    [ $? -ne 0 ] && return
    for I in $(ls /dev/md[0-9]* 2>/dev/null); do
      mdadm -S "${I}" >/dev/null 2>&1
    done
  fi
  for I in ${RESP}; do
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
# install opkg package manager
function package() {
  dialog --backtitle "$(backtitle)" --colors --title "Package" \
    --yesno "This installs opkg Package Management,\nallowing you to install more Tools for use and debugging.\nDo you want to continue?" 0 0
  [ $? -ne 0 ] && return
  (
    wget -O - http://bin.entware.net/x64-k3.2/installer/generic.sh | /bin/sh
    opkg update
    #opkg install python3 python3-pip
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Package" \
    --progressbox "Installing opkg ..." 20 100
  dialog --backtitle "$(backtitle)" --colors --title "Package" \
    --msgbox "Installation is complete.\nPlease reconnect to ssh/web,\nor execute 'source ~/.bashrc'" 0 0
  return
}

###############################################################################
# let user format disks from inside arc
function forcessh() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --title "Force enable SSH"  \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi
  (
    ONBOOTUP=""
    ONBOOTUP="${ONBOOTUP}systemctl restart inetd\n"
    ONBOOTUP="${ONBOOTUP}synowebapi --exec api=SYNO.Core.Terminal method=set version=3 enable_telnet=true enable_ssh=true ssh_port=22 forbid_console=false\n"
    ONBOOTUP="${ONBOOTUP}echo \"DELETE FROM task WHERE task_name LIKE ''ARCONBOOTUPARC_SSH'';\" | sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db\n"
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        sqlite3 ${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db <<EOF
DELETE FROM task WHERE task_name LIKE 'ARCONBOOTUPARC_SSH';
INSERT INTO task VALUES('ARCONBOOTUPARC_SSH', '', 'bootup', '', 1, 0, 0, 0, '', 0, '$(echo -e ${ONBOOTUP})', 'script', '{}', '', '', '{}', '{}');
EOF
        sleep 1
        sync
        echo "true" >${TMP_PATH}/isEnable
      fi
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX" >/dev/null
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Force enable SSH"  \
    --progressbox "$(TEXT "Enabling ...")" 20 100
  [ "$(cat ${TMP_PATH}/isEnable 2>/dev/null)" == "true" ] && MSG="Enable Telnet&SSH successfully." || MSG="Enable Telnet&SSH failed."
  dialog --backtitle "$(backtitle)" --title "Force enable SSH"  \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Clone Loader Disk
function cloneLoader() {
  rm -f "${TMP_PATH}/opts" >/dev/null
  while read -r KNAME SIZE TYPE PKNAME; do
    [ -z "${KNAME}" ] && continue
    [ "${KNAME}" == "N/A" ] && continue
    [ "${TYPE}" != "disk" ] && continue
    [[ "${KNAME}" == /dev/md* ]] && continue
    [[ "${KNAME}" == "${LOADER_DISK}" || "${PKNAME}" == "${LOADER_DISK}" ]] && continue
    [ -z "${SIZE}" ] && SIZE="Unknown"
    printf "\"%s\" \"%-6s %-4s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" >>"${TMP_PATH}/opts"
  done < <(lsblk -Jpno KNAME,SIZE,TYPE,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.size) \(.type) \(.pkname)"' 2>/dev/null)
  if [ ! -f "${TMP_PATH}/opts" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
      --msgbox "No disk found!" 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
    --radiolist "Choose a Destination" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat ${TMP_PATH}/resp)
  if [ -z "${resp}" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
      --msgbox "No disk selected!" 0 0
    return
  else
    SIZE=$(df -m ${resp} 2>/dev/null | awk 'NR==2 {print $2}')
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
    rm -rf "${PART3_PATH}/dl" >/dev/null
    CLEARCACHE=0

    gzip -dc "${ARC_PATH}/grub.img.gz" | dd of="${resp}" bs=1M conv=fsync status=progress
    hdparm -z "${resp}" # reset disk cache
    fdisk -l "${resp}"
    sleep 3

    mkdir -p "${TMP_PATH}/sdX1"
    mount "$(lsblk "${resp}" -pno KNAME,LABEL 2>/dev/null | grep ARC1 | awk '{print $1}')" "${TMP_PATH}/sdX1"
    cp -vRf "${PART1_PATH}/". "${TMP_PATH}/sdX1/"
    sync
    umount "${TMP_PATH}/sdX1"

    mkdir -p "${TMP_PATH}/sdX2"
    mount "$(lsblk "${resp}" -pno KNAME,LABEL 2>/dev/null | grep ARC2 | awk '{print $1}')" "${TMP_PATH}/sdX2"
    cp -vRf "${PART2_PATH}/". "${TMP_PATH}/sdX2/"
    sync
    umount "${TMP_PATH}/sdX2"

    mkdir -p "${TMP_PATH}/sdX3"
    mount "$(lsblk "${resp}" -pno KNAME,LABEL 2>/dev/null | grep ARC3 | awk '{print $1}')" "${TMP_PATH}/sdX3"
    cp -vRf "${PART3_PATH}/". "${TMP_PATH}/sdX3/"
    sync
    umount "${TMP_PATH}/sdX3"
    sleep 3
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
    --progressbox "Cloning ..." 20 100
  dialog --backtitle "$(backtitle)" --colors --title "Clone Loader" \
    --msgbox "Bootloader has been cloned to disk ${resp},\nplease remove the current bootloader disk!\nReboot?" 0 0
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
    dialog --backtitle "$(backtitle)" --title "Reset Loader" --aspect 18 \
    --yesno "Reset successful.\nReinit required!" 0 0
  [ $? -ne 0 ] && return
  init.sh
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
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      mkdir -p "${TMP_PATH}/logs/md0/log"
      cp -rf ${TMP_PATH}/mdX/.log.junior "${TMP_PATH}/logs/md0"
      cp -rf ${TMP_PATH}/mdX/var/log/messages ${TMP_PATH}/mdX/var/log/*.log "${TMP_PATH}/logs/md0/log"
      SYSLOG=1
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  fi
  if [ ${SYSLOG} -eq 1 ]; then
    MSG+="System logs found!\n"
  else
    MSG+="Can't find system logs!\n"
  fi

  PSTORE=0
  if [ -n "$(ls /sys/fs/pstore 2>/dev/null)" ]; then
    mkdir -p "${TMP_PATH}/logs/pstore"
    cp -rf /sys/fs/pstore/* "${TMP_PATH}/logs/pstore"
    [ -n "$(ls /sys/fs/pstore/*.z 2>/dev/null)" ] && zlib-flate -uncompress </sys/fs/pstore/*.z >"${TMP_PATH}/logs/pstore/ps.log" 2>/dev/null
    PSTORE=1
  fi
  if [ ${PSTORE} -eq 1 ]; then
    MSG+="Pstore logs found!\n"
  else
    MSG+="Can't find pstore logs!\n"
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
    if [ -z "${SSH_TTY}" ]; then # web
      mv -f "${TMP_PATH}/logs.tar.gz" "/var/www/data/logs.tar.gz"
      URL="http://$(getIP)/logs.tar.gz"
      MSG+="Please via ${URL} to download the logs,\nAnd go to Github or Discord to create an issue and upload the logs."
    else
      sz -be -B 536870912 "${TMP_PATH}/logs.tar.gz"
      MSG+="Please go to Github or Discord to create an issue and upload the logs."
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
    if [ -z "${SSH_TTY}" ]; then # web
      mv -f "${TMP_PATH}/dsmconfig.tar.gz" "/var/www/data/dsmconfig.tar.gz"
      chmod 644 "/var/www/data/dsmconfig.tar.gz"
      URL="http://$(getIP)/dsmconfig.tar.gz"
      dialog --backtitle "$(backtitle)" --colors --title "DSM Config" \
        --msgbox "Please via ${URL}\nto download the dsmconfig and unzip it and back it up in order by file name." 0 0
    else
      sz -be -B 536870912 "${TMP_PATH}/dsmconfig.tar.gz"
      dialog --backtitle "$(backtitle)" --colors --title "DSM Config" \
        --msgbox "Please unzip it and back it up in order by file name." 0 0
    fi
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
  rm -f "${TMP_PATH}/opts" >/dev/null
  echo "0 \"Create SATA node(ARC)\"" >>"${TMP_PATH}/opts"
  echo "1 \"Native SATA Disk(SYNO)\"" >>"${TMP_PATH}/opts"
  echo "2 \"Fake SATA DOM(Redpill)\"" >>"${TMP_PATH}/opts"
  dialog --backtitle "$(backtitle)" --title "Switch SATA DOM" \
    --default-item "${SATADOM}" --menu  "Choose an Option" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat ${TMP_PATH}/resp)
  [ -z "${resp}" ] && return
  SATADOM=${resp}
  writeConfigKey "satadom" "${SATADOM}" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  return
}

###############################################################################
# Decrypt Menu
function decryptMenu() {
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  if [ "${OFFLINE}" == "false" ]; then
    local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-configs/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
    if [ -n "${TAG}" ]; then
      (
        # Download update file
        local URL="https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/arc-configs.zip"
        echo "Downloading ${TAG}"
        if [ "${ARCNIC}" == "auto" ]; then
          curl -#kL "${URL}" -o "${TMP_PATH}/configs.zip" 2>&1 | while IFS= read -r -n1 char; do
            [[ $char =~ [0-9] ]] && keep=1 ;
            [[ $char == % ]] && echo "Download: $progress%" && progress="" && keep=0 ;
            [[ $keep == 1 ]] && progress="$progress$char" ;
          done
        else
          curl --interface ${ARCNIC} -#kL "${URL}" -o "${TMP_PATH}/configs.zip" 2>&1 | while IFS= read -r -n1 char; do
            [[ $char =~ [0-9] ]] && keep=1 ;
            [[ $char == % ]] && echo "Download: $progress%" && progress="" && keep=0 ;
            [[ $keep == 1 ]] && progress="$progress$char" ;
          done
        fi
        if [ -f "${TMP_PATH}/configs.zip" ]; then
          echo "Download successful!"
          mkdir -p "${MODEL_CONFIG_PATH}"
          echo "Installing new Configs..."
          unzip -oq "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}"
          rm -f "${TMP_PATH}/configs.zip"
          echo "Installation done!"
          sleep 2
        else
          echo "Error extracting new Version!"
          sleep 5
        fi
      ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Arc Decrypt" \
        --progressbox "Installing Arc Patch Configs..." 20 50
    else
      dialog --backtitle "$(backtitle)" --colors --title "Arc Decrypt" \
        --msgbox "Can't connect to Github.\nCheck your Network!" 6 50
      return
    fi
    if [ -f "${S_FILE_ENC}" ]; then
      CONFIGSVERSION="$(cat "${MODEL_CONFIG_PATH}/VERSION")"
      cp -f "${S_FILE}" "${S_FILE}.bak"
      dialog --backtitle "$(backtitle)" --colors --title "Arc Decrypt" \
        --inputbox "Enter Decryption Key for ${CONFIGSVERSION}\nKey is available in my Discord." 8 50 2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      ARCKEY=$(cat "${TMP_PATH}/resp")
      if openssl enc -in "${S_FILE_ENC}" -out "${S_FILE_ARC}" -d -aes-256-cbc -k "${ARCKEY}" 2>/dev/null; then
        dialog --backtitle "$(backtitle)" --colors --title "Arc Decrypt" \
          --msgbox "Decrypt successful: You can use Arc Patch." 5 50
        cp -f "${S_FILE_ARC}" "${S_FILE}"
        writeConfigKey "arc.key" "${ARCKEY}" "${USER_CONFIG_FILE}"
      else
        cp -f "${S_FILE}.bak" "${S_FILE}"
        dialog --backtitle "$(backtitle)" --colors --title "Arc Decrypt" \
          --msgbox "Decrypt failed: Wrong Key for this Version." 5 50
        writeConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
      fi
    fi
    SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
    ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}")"
    if [ "${SN}" != "${ARCCONF}" ]; then
      writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
      CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
    fi
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    ARCKEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
  else
    dialog --backtitle "$(backtitle)" --colors --title "Arc Decrypt" \
      --msgbox "Not available in offline Mode!" 5 50
  fi
  return
}

###############################################################################
# ArcNIC Menu
function arcNIC () {
  ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  ETHX="$(ls /sys/class/net 2>/dev/null | grep eth)" # real network cards list
  rm -f "${TMP_PATH}/opts" >/dev/null
  touch "${TMP_PATH}/opts"
  echo -e "auto \"Automated\"" >>"${TMP_PATH}/opts"
  # Get NICs
  for ETH in ${ETHX}; do
    DRIVER="$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')"
    echo -e "${ETH} \"${DRIVER}\"" >>"${TMP_PATH}/opts"
  done
  dialog --backtitle "$(backtitle)" --title "Arc NIC" \
    --default-item "${ARCNIC}" --menu  "Choose a NIC" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat ${TMP_PATH}/resp)
  [ -z "${resp}" ] && return
  ARCNIC=${resp}
  writeConfigKey "arc.nic" "${ARCNIC}" "${USER_CONFIG_FILE}"
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
  echo -e "init \"Arc: Restart Loader Init\"" >>"${TMP_PATH}/opts"
  echo -e "network \"Arc: Restart Network Service\"" >>"${TMP_PATH}/opts"
  if [ "${BUILDDONE}" == "true" ]; then
    echo -e "recovery \"DSM: Recovery Mode\"" >>"${TMP_PATH}/opts"
    echo -e "junior \"DSM: Reinstall Mode\"" >>"${TMP_PATH}/opts"
  fi
  echo -e "bios \"System: BIOS/UEFI\"" >>"${TMP_PATH}/opts"
  echo -e "poweroff \"System: Shutdown\"" >>"${TMP_PATH}/opts"
  echo -e "shell \"System: Shell Cmdline\"" >>"${TMP_PATH}/opts"
  dialog --backtitle "$(backtitle)" --title "Power Menu" \
    --menu  "Choose a Destination" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat ${TMP_PATH}/resp)
  [ -z "${resp}" ] && return
  REDEST=${resp}
  dialog --backtitle "$(backtitle)" --title "Power Menu" \
    --infobox "Option: ${REDEST} selected ...!" 3 50
  if [ "${REDEST}" == "poweroff" ]; then
    poweroff
    exit 0
  elif [ "${REDEST}" == "shell" ]; then
    clear
    exit 0
  elif [ "${REDEST}" == "init" ]; then
    clear
    init.sh
  elif [ "${REDEST}" == "network" ]; then
    clear
    /etc/init.d/S41dhcpcd restart
    arc.sh
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
  if [ "${ARCMODE}" = "config" ]; then
    # Selectable CPU governors
    [ "${PLATFORM}" == "epyc7002" ] && echo -e "schedutil \"use schedutil to scale frequency *\"" >>"${TMP_PATH}/opts"
    [ "${PLATFORM}" != "epyc7002" ] && echo -e "ondemand \"use ondemand to scale frequency *\"" >>"${TMP_PATH}/opts"
    [ "${PLATFORM}" != "epyc7002" ] && echo -e "conservative \"use conservative to scale frequency\"" >>"${TMP_PATH}/opts"
    echo -e "performance \"always run at max frequency\"" >>"${TMP_PATH}/opts"
    echo -e "powersave \"always run at lowest frequency\"" >>"${TMP_PATH}/opts"
    dialog --backtitle "$(backtitle)" --title "CPU Frequency Scaling" \
      --menu  "Choose a Governor\n* Recommended Option" 0 0 0 --file "${TMP_PATH}/opts" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(cat ${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    CPUGOVERNOR=${resp}
  else
    [ "${PLATFORM}" == "epyc7002" ] && CPUGOVERNOR="schedutil"
    [ "${PLATFORM}" != "epyc7002" ] && CPUGOVERNOR="ondemand"
  fi
  writeConfigKey "addons.cpufreqscaling" "${CPUGOVERNOR}" "${USER_CONFIG_FILE}"
  CPUGOVERNOR="$(readConfigKey "addons.cpufreqscaling" "${USER_CONFIG_FILE}")"
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
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
    %) ;;
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
        dtc -q -I dts -O dtb "${TMP_PATH}/modelEdit.dts" >"test.dtb" 2>"${DTC_ERRLOG}"
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
    esac
  done
}

###############################################################################
# reset Arc Patch
function resetArcPatch() {
  writeConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
  ARCKEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
  writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  return
}
