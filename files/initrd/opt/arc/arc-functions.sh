###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "$(backtitle)" --title "Edit with caution" \
      --ok-label "Save" --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return 1
    mv -f "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=$(yq eval "${USER_CONFIG_FILE}" 2>&1)
    [ $? -eq 0 ] && break || continue
    dialog --backtitle "$(backtitle)" --title "Invalid YAML format" --msgbox "${ERRORS}" 0 0
  done
  OLDMODEL="${MODEL}"
  OLDPRODUCTVER="${PRODUCTVER}"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  SN="$(readConfigKey "arc.sn" "${USER_CONFIG_FILE}")"
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
  unset ADDONS
  declare -A ADDONS
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  rm -f "${TMP_PATH}/opts" >/dev/null
  touch "${TMP_PATH}/opts"
  while read -r ADDON DESC; do
    arrayExistItem "${ADDON}" "${!ADDONS[@]}" && ACT="on" || ACT="off"
    if [ "${ADDON}" == "amepatch" ] && [ "${OFFLINE}" == "true" ]; then
      continue
    else
      echo -e "${ADDON} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
    fi
  done < <(availableAddons "${PLATFORM}")
  dialog --backtitle "$(backtitle)" --title "DSM Addons" --aspect 18 \
    --checklist "Select DSM Addons to include.\nPlease read Wiki before choosing anything.\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
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
    --msgbox "DSM Addons selected:\n${ADDONSINFO}" 0 0
}

###############################################################################
# Permit user select the modules to include
function modulesMenu() {
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  # Modify KVER for Epyc7002
  if [ "${PLATFORM}" == "epyc7002" ]; then
    KVERP="${PRODUCTVER}-${KVER}"
  else
    KVERP="${KVER}"
  fi
  dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
    --infobox "Reading modules" 0 0
  unset USERMODULES
  declare -A USERMODULES
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
  done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
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
      8 "Copy i915 to DSM" \
      9 "Copy loaded Modules to DSM" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
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
        sed -i 's/#N /N /g' "${TMP_PATH}/modulelist.tmp"
        [ ! -d "${USER_UP_PATH}" ] && mkdir -p "${USER_UP_PATH}"
        mv -f "${TMP_PATH}/modulelist.tmp" "${USER_UP_PATH}/modulelist"
        dos2unix "${USER_UP_PATH}/modulelist"
        dialog --backtitle "$(backtitle)" --title "i915 Modules Copy" \
          --msgbox "i915 Modules will be copied to DSM!" 5 50
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      9)
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
            [ "${MOD}" == "${ID}" ] && echo "N ${ID}.ko" >>"${TMP_PATH}/modulelist.tmp"
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
    esac
  done
  return
}

###############################################################################
# Let user edit cmdline
function cmdlineMenu() {
  unset CMDLINE
  declare -A CMDLINE
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
  done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
  echo "1 \"Add a Cmdline item\""                                >"${TMP_PATH}/menu"
  echo "2 \"Delete Cmdline item(s)\""                           >>"${TMP_PATH}/menu"
  echo "3 \"CPU Fix\""                                          >>"${TMP_PATH}/menu"
  echo "4 \"RAM Fix\""                                          >>"${TMP_PATH}/menu"
  echo "5 \"PCI/IRQ Fix\""                                      >>"${TMP_PATH}/menu"
  echo "6 \"C-State Fix\""                                      >>"${TMP_PATH}/menu"
  echo "7 \"Show user Cmdline\""                                >>"${TMP_PATH}/menu"
  echo "9 \"Kernelpanic Behavior\""                             >>"${TMP_PATH}/menu"
  # Loop menu
  while true; do
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
        MSG+=" * \Z4intel_pstate=disable\Zn\n    Switch Intel P-State to ACPI.\n"
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
        [ $? -ne 0 ] && return 1
        resp=$(cat ${TMP_PATH}/resp)
        [ -z "${resp}" ] && return 1
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
          2 "Uninstall" \
        2>"${TMP_PATH}/resp"
        resp=$(cat ${TMP_PATH}/resp)
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
          2 "Uninstall" \
        2>"${TMP_PATH}/resp"
        resp=$(cat ${TMP_PATH}/resp)
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
          2 "Uninstall" \
        2>"${TMP_PATH}/resp"
        resp=$(cat ${TMP_PATH}/resp)
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
          2 "Uninstall" \
        2>"${TMP_PATH}/resp"
        resp=$(cat ${TMP_PATH}/resp)
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
        rm -f "${TMP_PATH}/opts" >/dev/null
        echo "5 \"Reboot after 5 seconds\"" >>"${TMP_PATH}/opts"
        echo "0 \"No reboot\"" >>"${TMP_PATH}/opts"
        echo "-1 \"Restart immediately\"" >>"${TMP_PATH}/opts"
        dialog --backtitle "$(backtitle)" --colors --title "Kernelpanic" \
          --default-item "${KERNELPANIC}" --menu "Choose a time(seconds)" 0 0 0 --file "${TMP_PATH}/opts" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && return 1
        resp=$(cat ${TMP_PATH}/resp)
        [ -z "${resp}" ] && return 1
        KERNELPANIC=${resp}
        writeConfigKey "arc.kernelpanic" "${KERNELPANIC}" "${USER_CONFIG_FILE}"
        ;;
    esac
  done
  return
}

###############################################################################
# let user configure synoinfo entries
function synoinfoMenu() {
  # read synoinfo from user config
  unset SYNOINFO
  declare -A SYNOINFO
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
  done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "1 \"Add/edit Synoinfo item\""     >"${TMP_PATH}/menu"
  echo "2 \"Delete Synoinfo item(s)\""    >>"${TMP_PATH}/menu"
  echo "3 \"Show Synoinfo entries\""      >>"${TMP_PATH}/menu"
  echo "4 \"Add Trim/Dedup to Synoinfo\"" >>"${TMP_PATH}/menu"

  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
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
        if [ ${#SYNOINFO[@]} -eq 0 ]; then
          dialog --backtitle "$(backtitle)" --msgbox "No Synoinfo Entries to remove" 0 0
          continue
        fi
        ITEMS=""
        for I in "${!SYNOINFO[@]}"; do
          [ -z "${SYNOINFO[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${SYNOINFO[${I}]} off "
        done
        dialog --backtitle "$(backtitle)" \
          --checklist "Select synoinfo entry to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && return 1
        resp=$(cat ${TMP_PATH}/resp)
        [ -z "${resp}" ] && return 1
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
        dialog --backtitle "$(backtitle)" --title "Synoinfo Entries" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      4)
        # Optimized Synoinfo
        writeConfigKey "synoinfo.support_trim" "yes" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_disk_hibernation" "yes" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_btrfs_dedupe" "yes" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_tiny_btrfs_dedupe" "yes" "${USER_CONFIG_FILE}"
        dialog --backtitle "$(backtitle)" --title "Add Trim/Dedup to Synoinfo" --aspect 18 \
          --msgbox "Synoinfo set successful!" 0 0
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
    dialog --backtitle "$(backtitle)" --title "StoragePanel" \
      --aspect 18 --msgbox "StoragePanel Addon enabled." 0 0
    ITEMS="$(echo -e "RACK_2_Bay \nRACK_4_Bay \nRACK_8_Bay \nRACK_12_Bay \nRACK_16_Bay \nRACK_24_Bay \nRACK_60_Bay \nTOWER_1_Bay \nTOWER_2_Bay \nTOWER_4_Bay \nTOWER_6_Bay \nTOWER_8_Bay \nTOWER_12_Bay \n")"
    dialog --backtitle "$(backtitle)" --title "StoragePanel" \
      --default-item "RACK_24_Bay" --no-items --menu "Choose a Disk Panel" 0 0 0 ${ITEMS} \
      2>"${TMP_PATH}/resp"
    resp=$(cat ${TMP_PATH}/resp)
    [ -z "${resp}" ] && return 1
    STORAGE=${resp}
    ITEMS="$(echo -e "1X2 \n1X4 \n1X8 \n")"
    dialog --backtitle "$(backtitle)" --title "StoragePanel" \
      --default-item "1X8" --no-items --menu "Choose a M.2 Panel" 0 0 0 ${ITEMS} \
      2>"${TMP_PATH}/resp"
    resp=$(cat ${TMP_PATH}/resp)
    [ -z "${resp}" ] && return 1
    M2PANEL=${resp}
    STORAGEPANEL="${STORAGE} ${M2PANEL}"
    writeConfigKey "addons.storagepanel" "${STORAGEPANEL}" "${USER_CONFIG_FILE}"
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
    dialog --backtitle "$(backtitle)" --title "SequentialIO" \
      --aspect 18 --msgbox "SequentialIO Addon enabled." 0 0
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
    done
    writeConfigKey "addons.sequentialio" "${SEQUENTIAL}" "${USER_CONFIG_FILE}"
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
      2 "Restore Encryption Key from DSM" \
      3 "Backup Encryption Key to DSM" \
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
              SN="$(readConfigKey "arc.sn" "${USER_CONFIG_FILE}")"
              TEXT+="\nSerial: ${SN}"
              ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
              TEXT+="\nArc Patch: ${ARCPATCH}"
              dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
                --aspect 18 --msgbox "${TEXT}" 0 0
              PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
              DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
              CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
              writeConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
              ARC_KEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
              writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
              BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
              break
            fi
          fi
        done
        if [ -f "${USER_CONFIG_FILE}" ]; then
          dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
            --aspect 18 --msgbox "Config restore successful!" 0 0
          # Ask for Build
          dialog --clear --backtitle "$(backtitle)" \
            --menu "Config done -> Build now?" 7 50 0 \
            1 "Yes - Build Arc Loader now" \
            2 "No - I want to make changes" \
          2>"${TMP_PATH}/resp"
          resp=$(cat ${TMP_PATH}/resp)
          [ -z "${resp}" ] && return 1
          # Check for compatibility
          compatboot
          if [ ${resp} -eq 1 ]; then
            arcSummary
          elif [ ${resp} -eq 2 ]; then
            dialog --clear --no-items --backtitle "$(backtitle)"
            return 1
          fi
        else
          dialog --backtitle "$(backtitle)" --title "Restore Arc Config" \
            --aspect 18 --msgbox "No Config found!" 0 0
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
  NEXT="1"
  while true; do
    dialog --backtitle "$(backtitle)" --cancel-label "Exit" \
      --menu "Choose an Option" 0 0 0 \
      1 "Automated Update Mode" \
      2 "Full-Upgrade Loader (reflash)" \
      3 "Update Loader" \
      4 "Update Addons" \
      5 "Update Configs" \
      6 "Update LKMs" \
      7 "Update Modules" \
      8 "Update Patches" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
      1)
        dialog --backtitle "$(backtitle)" --title "Automated Update" --aspect 18 \
          --msgbox "Loader will proceed Automated Update Mode.\nPlease wait until progress is finished!" 0 0
        . ${ARC_PATH}/update.sh
        ;;
      2)
        # Ask for Tag
        TAG=""
        dialog --clear --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && continue
        opts=$(cat ${TMP_PATH}/opts)
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        upgradeLoader "${TAG}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        exec reboot && exit 0
        ;;
      3)
        # Ask for Tag
        TAG=""
        dialog --clear --backtitle "$(backtitle)" --title "Update Loader" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && continue
        opts=$(cat ${TMP_PATH}/opts)
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Loader" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        updateLoader "${TAG}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      4)
        # Ask for Tag
        TAG=""
        dialog --clear --backtitle "$(backtitle)" --title "Update Addons" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && continue
        opts=$(cat ${TMP_PATH}/opts)
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Addons" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        updateAddons "${TAG}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      5)
        # Ask for Tag
        TAG=""
        dialog --clear --backtitle "$(backtitle)" --title "Update Configs" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts=$(cat ${TMP_PATH}/opts)
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Configs" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        updateConfigs "${TAG}"
        writeConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
        ARC_KEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      6)
        # Ask for Tag
        TAG=""
        dialog --clear --backtitle "$(backtitle)" --title "Update LKMs" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts=$(cat ${TMP_PATH}/opts)
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update LKMs" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        updateLKMs "${TAG}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      7)
        # Ask for Tag
        TAG=""
        dialog --clear --backtitle "$(backtitle)" --title "Update Modules" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts=$(cat ${TMP_PATH}/opts)
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Modules" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        updateModules "${TAG}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      8)
        # Ask for Tag
        TAG=""
        dialog --clear --backtitle "$(backtitle)" --title "Update Patches" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts=$(cat ${TMP_PATH}/opts)
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG=""
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Patches" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
        fi
        updatePatches "${TAG}"
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
  ETHX="$(ls /sys/class/net/ 2>/dev/null | grep eth)"
  ETHN="$(echo ${ETHX} | wc -w)"
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
      PORTMAP="$(readConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}")"
    fi
  fi
  DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
  OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  CONFIGVER="$(readConfigKey "arc.version" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
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
  TEXT+="\n\Z4> System: ${MACHINE} | ${BOOTSYS}\Zn"
  TEXT+="\n  Vendor: \Zb${VENDOR}\Zn"
  TEXT+="\n  CPU: \Zb${CPU}\Zn"
  if [ $(lspci -d ::300 | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::300 | awk '{print $1}'); do
      GPUNAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      TEXT+="\n  iGPU: \Zb${GPUNAME}\Zn"
    done
  elif [ $(lspci -d ::380 | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::380 | awk '{print $1}'); do
      GPUNAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      TEXT+="\n  GPU: \Zb${GPUNAME}\Zn"
    done
  fi
  TEXT+="\n  Memory: \Zb$((${RAMTOTAL}))GB\Zn"
  TEXT+="\n  AES | ACPI: \Zb${AESSYS} | ${ACPISYS}\Zn"
  TEXT+="\n  CPU Scaling: \Zb${CPUFREQ}\Zn"
  TEXT+="\n  Secure Boot: \Zb${SECURE}\Zn"
  TEXT+="\n  Date/Time: \Zb$(date)\Zn"
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
  TEXT+="\n  Subversion: \ZbAddons ${ADDONSVERSION} | Configs ${CONFIGSVERSION} | LKM ${LKMVERSION} | Modules ${MODULESVERSION} | Patches ${PATCHESVERSION}\Zn"
  TEXT+="\n\Z4> Loader\Zn"
  TEXT+="\n  Config | Build: \Zb${CONFDONE} | ${BUILDDONE}\Zn"
  TEXT+="\n  Config Version: \Zb${CONFIGVER}\Zn"
  if [ "${CONFDONE}" == "true" ]; then
    TEXT+="\n\Z4> DSM ${PRODUCTVER}: ${MODELID:-${MODEL}}\Zn"
    TEXT+="\n  Kernel | LKM: \Zb${KVER} | ${LKM}\Zn"
    TEXT+="\n  Platform | DeviceTree: \Zb${PLATFORM} | ${DT}\Zn"
    TEXT+="\n  Arc Patch | Kernelload: \Zb${ARCPATCH} | ${KERNELLOAD}\Zn"
    TEXT+="\n  Directboot: \Zb${DIRECTBOOT}\Zn"
    TEXT+="\n  Addons selected: \Zb${ADDONSINFO}\Zn"
  fi
  TEXT+="\n  Modules loaded: \Zb${MODULESINFO}\Zn"
  TEXT+="\n\Z4> Settings\Zn"
  TEXT+="\n  Offline Mode: \Zb${OFFLINE}\Zn"
  if [[ "${REMAP}" == "acports" || "${REMAP}" == "maxports" ]]; then
    TEXT+="\n  SataPortMap | DiskIdxMap: \Zb${PORTMAP} | ${DISKMAP}\Zn"
  elif [ "${REMAP}" == "remap" ]; then
    TEXT+="\n  SataRemap: \Zb${PORTMAP}\Zn"
  elif [ "${REMAP}" == "user" ]; then
    TEXT+="\n  PortMap: \Zb"User"\Zn"
  fi
  if [ "${DT}" == "true" ]; then
    TEXT+="\n  Hotplug: \Zb${HDDSORT}\Zn"
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
      TEXT+="\n  Ports with color \Z1\Zbred\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected.\n"
    done
  fi
  if [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
    TEXT+="\n  SAS Controller:\n"
    for PCI in $(lspci -d ::107 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::104 | wc -l) -gt 0 ]; then
    TEXT+="\n  Raid Controller:\n"
    for PCI in $(lspci -d ::104 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::100 | wc -l) -gt 0 ]; then
    TEXT+="\n  SCSI Controller:\n"
    for PCI in $(lspci -d ::100 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
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
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
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
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::108 | wc -l) -gt 0 ]; then
    TEXT+="\n  NVMe Controller:\n"
    for PCI in $(lspci -d ::108 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      PORT=$(ls -l /sys/class/nvme | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[N:${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  TEXT+="\n  Drives total: \Zb${NUMPORTS}\Zn"
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
  ETHX="$(ls /sys/class/net/ 2>/dev/null | grep eth)"
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
  ETHX="$(ls /sys/class/net/ 2>/dev/null | grep eth)"
  for ETH in ${ETHX}; do
    MACR="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g')"
    IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
    IFS='/' read -r -a IPRA <<<"$IPR"

    MSG="$(printf "Set to %s: (Delete if empty)" "${ETH}(${MACR})")"
    while true; do
      dialog --backtitle "$(backtitle)" --title "StaticIP" \
        --form "${MSG}" 10 60 4 "address" 1 1 "${IPRA[0]}" 1 9 36 16 "netmask" 2 1 "${IPRA[1]}" 2 9 36 16 "gateway" 3 1 "${IPRA[2]}" 3 9 36 16 "dns" 4 1 "${IPRA[3]}" 4 9 36 16 \
        2>"${TMP_PATH}/resp"
      RET=$?
      case ${RET} in
      0) # ok-button
        dialog --backtitle "$(backtitle)" --title "StaticIP" \
          --infobox "Setting IP ..." 0 0
        address="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
        netmask="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
        gateway="$(cat "${TMP_PATH}/resp" | sed -n '3p')"
        dnsname="$(cat "${TMP_PATH}/resp" | sed -n '4p')"
        if [ -z "${address}" ]; then
          deleteConfigKey "network.${MACR}" "${USER_CONFIG_FILE}"
        else
          ip addr flush dev $ETH
          ip addr add ${address}/${netmask:-"255.255.255.0"} dev $ETH
          if [ -n "${gateway}" ]; then
            ip route add default via ${gateway} dev $ETH
          fi
          if [ -n "${dnsname:-${gateway}}" ]; then
            sed -i "/nameserver ${dnsname:-${gateway}}/d" /etc/resolv.conf
            echo "nameserver ${dnsname:-${gateway}}" >>/etc/resolv.conf
          fi
          writeConfigKey "network.${MACR}" "${address}/${netmask}/${gateway}/${dnsname}" "${USER_CONFIG_FILE}"
          IP="$(getIP)"
          sleep 1
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
    dialog --backtitle "$(backtitle)" --title "Reset Password"  \
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
    dialog --backtitle "$(backtitle)" --title "Reset Password"  \
      --msgbox "All existing users have been disabled. Please try adding new user." 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --title "Reset Password"  \
    --no-items --menu  "Choose a User" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  USER="$(cat "${TMP_PATH}/resp" 2>/dev/null | awk '{print $1}')"
  [ -z "${USER}" ] && return
  while true; do
    dialog --backtitle "$(backtitle)" --title "Reset Password"  \
      --inputbox "$(printf "Type a new password for user '%s'")" "${USER}" 0 70 "${CMDLINE[${NAME}]}" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break 2
    VALUE="$(cat "${TMP_PATH}/resp")"
    [ -n "${VALUE}" ] && break
    dialog --backtitle "$(backtitle)" --title "Reset Password"  \
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
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Reset Password"  \
    --progressbox "Resetting ..." 20 100
  dialog --backtitle "$(backtitle)" --title "Reset Password"  \
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
    ONBOOTUP="${ONBOOTUP}echo \"DELETE FROM task WHERE task_name LIKE ''ARCONBOOTUPRR_ADDUSER'';\" | sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db\n"

    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        sqlite3 ${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db <<EOF
DELETE FROM task WHERE task_name LIKE 'ARCONBOOTUPRR_ADDUSER';
INSERT INTO task VALUES('ARCONBOOTUPRR_ADDUSER', '', 'bootup', '', 1, 0, 0, 0, '', 0, '$(echo -e ${ONBOOTUP})', 'script', '{}', '', '', '{}', '{}');
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
    [[ "${KNAME}" = /dev/md* ]] && continue
    [[ "${KNAME}" = "${LOADER_DISK}" || "${PKNAME}" = "${LOADER_DISK}" ]] && continue
    [ -z "${SIZE}" ] && SIZE="Unknown"
    printf "\"%s\" \"%-6s %-4s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" >>"${TMP_PATH}/opts"
  done < <(lsblk -pno KNAME,SIZE,TYPE,PKNAME)
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
  while read -r KNAME KMODEL PKNAME TYPE; do
    [ -z "${KNAME}" ] && continue
    [ -z "${KMODEL}" ] && KMODEL="${TYPE}"
    [ "${KNAME}" == "${LOADER_DISK}" ] || [ "${PKNAME}" == "${LOADER_DISK}" ] || [ "${KMODEL}" == "${LOADER_DISK}" ] && continue
    echo "\"${KNAME}\" \"${KMODEL}\" \"off\"" >>"${TMP_PATH}/opts"
  done < <(lsblk -dpno KNAME,MODEL,PKNAME,TYPE | sort)
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
  if [ -d "${PART1_PATH}/logs" ]; then
    rm -f "${TMP_PATH}/logs.tar.gz"
    tar -czf "${TMP_PATH}/logs.tar.gz" -C "${PART1_PATH}/logs"
    if [ -z "${SSH_TTY}" ]; then # web
      mv -f "${TMP_PATH}/logs.tar.gz" "/var/www/data/logs.tar.gz"
      URL="http://$(getIP)/logs.tar.gz"
      dialog --backtitle "$(backtitle)" --colors --title "Grep Logs" \
        --msgbox "Please visit ${URL}\nto download the logs and unzip it and back it up in order by file name." 0 0
    else
      sz -be -B 536870912 "${TMP_PATH}/log.tar.gz"
      dialog --backtitle "$(backtitle)" --colors --title "Grep Logs" \
        --msgbox "Please unzip it and back it up in order by file name." 0 0
    fi
  else
    MSG=""
    MSG+="\Z1No log found!\Zn\n\n"
    MSG+="Please do as follows:\n"
    MSG+=" 1. Add dbgutils in Addons and rebuild.\n"
    MSG+=" 2. Boot to DSM.\n"
    MSG+=" 3. Reboot to Config Mode and use this Option.\n"
    dialog --backtitle "$(backtitle)" --colors --title "Grep Logs" \
      --msgbox "${MSG}" 0 0
  fi
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
  if [ -f "${S_FILE_ENC}" ]; then
    CONFIGSVERSION="$(cat "${MODEL_CONFIG_PATH}/VERSION")"
    cp -f "${S_FILE}" "${S_FILE}.bak"
    dialog --backtitle "$(backtitle)" --colors --title "Arc Decrypt" \
      --inputbox "Enter Decryption Key for ${CONFIGSVERSION}" 7 40 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    ARC_KEY=$(cat "${TMP_PATH}/resp")
    if openssl enc -in "${S_FILE_ENC}" -out "${S_FILE_ARC}" -d -aes-256-cbc -k "${ARC_KEY}" 2>/dev/null; then
      dialog --backtitle "$(backtitle)" --colors --title "Arc Decrypt" \
        --msgbox "Decrypt successful: You can use Arc Patch." 5 50
      cp -f "${S_FILE_ARC}" "${S_FILE}"
      writeConfigKey "arc.key" "${ARC_KEY}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
      CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    else
      cp -f "${S_FILE}.bak" "${S_FILE}"
      dialog --backtitle "$(backtitle)" --colors --title "Arc Decrypt" \
        --msgbox "Decrypt failed: Wrong Key for this Version." 5 50
      writeConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
      CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    fi
  fi
  ARC_KEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
  return
}

###############################################################################
# ArcNIC Menu
function arcNIC () {
  ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  ETHX="$(ls /sys/class/net/ 2>/dev/null | grep eth)" # real network cards list
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
  rm -f "${TMP_PATH}/opts" >/dev/null
  touch "${TMP_PATH}/opts"
  # Selectable Reboot Options
  echo -e "config \"Config Mode\"" >>"${TMP_PATH}/opts"
  echo -e "update \"Automated Update Mode\"" >>"${TMP_PATH}/opts"
  echo -e "recovery \"Recovery Mode\"" >>"${TMP_PATH}/opts"
  echo -e "junior \"Reinstall Mode\"" >>"${TMP_PATH}/opts"
  if efibootmgr | grep -q "^Boot0000"; then
    echo -e "bios \"BIOS/UEFI\"" >>"${TMP_PATH}/opts"
  fi
  echo -e "poweroff \"Shutdown\"" >>"${TMP_PATH}/opts"
  echo -e "shell \"Exit to Shell Cmdline\"" >>"${TMP_PATH}/opts"
  echo -e "init \"Restart Loader Init\"" >>"${TMP_PATH}/opts"
  echo -e "network \"Restart Network Service\"" >>"${TMP_PATH}/opts"
  dialog --backtitle "$(backtitle)" --title "Reboot" \
    --menu  "Choose a Destination" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat ${TMP_PATH}/resp)
  [ -z "${resp}" ] && return
  REDEST=${resp}
  dialog --backtitle "$(backtitle)" --title "Reboot" \
    --infobox "Reboot to ${REDEST}!" 0 0
  if [ "${REDEST}" == "bios" ]; then
    efibootmgr -n 0000 >/dev/null 2>&1
    reboot
    exit 0
  elif [ "${REDEST}" == "poweroff" ]; then
    poweroff
    exit 0
  elif [ "${REDEST}" == "shell" ]; then
    clear
    exit 0
  elif [ "${REDEST}" == "init" ]; then
    init.sh
  elif [ "${REDEST}" == "network" ]; then
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
  if [ "${AUTOMATED}" == "false" ]; then
    # Selectable CPU governors
    [ "${PLATFORM}" == "epyc7002" ] && echo -e "schedutil \"use schedutil to scale frequency *\"" >>"${TMP_PATH}/opts"
    [ "${PLATFORM}" != "epyc7002" ] && echo -e "ondemand \"use ondemand to scale frequency *\"" >>"${TMP_PATH}/opts"
    [ "${PLATFORM}" != "epyc7002" ] && echo -e "conservative \"use conservative to scale frequency\"" >>"${TMP_PATH}/opts"
    echo -e "performance \"always run at max frequency\"" >>"${TMP_PATH}/opts"
    echo -e "powersave \"always run at lowest frequency\"" >>"${TMP_PATH}/opts"
    echo -e "userspace \"use userspace settings to scale frequency\"" >>"${TMP_PATH}/opts"
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
  writeConfigKey "arc.governor" "${CPUGOVERNOR}" "${USER_CONFIG_FILE}"
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
    [ $? -ne 0 ] && return
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