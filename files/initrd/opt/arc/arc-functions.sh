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
    if [[ "${ADDON}" = "amepatch" || "${ADDON}" = "arcdns" ]] && [ -z "${ARCCONF}" ]; then
      continue
    elif [ "${ADDON}" = "codecpatch" ] && [ -n "${ARCCONF}" ]; then
      continue
    else
      echo -e "${ADDON} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
    fi
  done < <(availableAddons "${PLATFORM}")
  if [ "${STEP}" = "addons" ]; then
    dialog --backtitle "$(backtitlep)" --title "Addons" --colors --aspect 18 \
      --checklist "Select Addons to include.\nAddons: \Z1System Addon\Zn | \Z4App Addon\Zn\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
      --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    resp=$(cat ${TMP_PATH}/resp)
  else
    dialog --backtitle "$(backtitle)" --title "Addons" --colors --aspect 18 \
      --checklist "Select Addons to include.\nAddons: \Z1System Addon\Zn | \Z4App Addon\Zn\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
      --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    resp=$(cat ${TMP_PATH}/resp)
  fi
  unset ADDONS
  declare -A ADDONS
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  for ADDON in ${resp}; do
    ADDONS["${ADDON}"]=""
    writeConfigKey "addons.\"${ADDON}\"" "" "${USER_CONFIG_FILE}"
  done
  ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  if [ "${STEP}" = "addons" ]; then
    dialog --backtitle "$(backtitlep)" --title "Addons" \
      --msgbox "Addons selected:\n${ADDONSINFO}" 7 70
  else
    dialog --backtitle "$(backtitle)" --title "Addons" \
      --msgbox "Addons selected:\n${ADDONSINFO}" 7 70
  fi
  return
}

###############################################################################
# Permit user select the modules to include
function modulesMenu() {
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
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
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
          2>${TMP_PATH}/resp
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
      done <<<$(readConfigMap "modules" "${USER_CONFIG_FILE}")
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
          2>${TMP_PATH}/resp
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
        resp=$(cat "${TMP_PATH}/resp")
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
  if [ "${CONFDONE}" = "true" ]; then
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
  if [ "${CONFDONE}" = "true" ]; then
    while true; do
        dialog --backtitle "$(backtitle)" --title "SequentialIO" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
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
  ARCOFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  while true; do
    if [ -n "${USERID}" ] && [ "${ARCOFFLINE}" != "true" ] && [ "${CONFDONE}" = "true" ]; then
      dialog --backtitle "$(backtitle)" --title "Backup" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
        1 "Restore Arc Config from DSM" \
        2 "Restore HW Encryption Key from DSM" \
        3 "Backup HW Encryption Key to DSM" \
        4 "Restore Arc Config from Online" \
        5 "Backup Arc Config to Online" \
        2>"${TMP_PATH}/resp"
    elif [ -n "${USERID}" ] && [ "${ARCOFFLINE}" != "true" ]; then
      dialog --backtitle "$(backtitle)" --title "Backup" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
        1 "Restore Arc Config from DSM" \
        2 "Restore HW Encryption Key from DSM" \
        3 "Backup HW Encryption Key to DSM" \
        4 "Restore Arc Config from Online" \
        2>"${TMP_PATH}/resp"
    else
      dialog --backtitle "$(backtitle)" --title "Backup" --cancel-label "Exit" --menu "Choose an Option" 0 0 0 \
        1 "Restore Arc Config from DSM" \
        2 "Restore HW Encryption Key from DSM" \
        3 "Backup HW Encryption Key to DSM" \
        2>"${TMP_PATH}/resp"
    fi
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
              ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
              TEXT+="\nArc Patch: ${ARCPATCH}"
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
        ./init.sh
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
          # fixDSMRootPart "${I}"
          mount -t ext4 "${I}" "${TMP_PATH}/mdX"
          if [ -f "${TMP_PATH}/mdX/usr/arc/backup/p2/machine.key" ]; then
            cp -f "${TMP_PATH}/mdX/usr/arc/backup/p2/machine.key" "${PART2_PATH}/machine.key"
            dialog --backtitle "$(backtitle)" --title "Restore Encryption Key" --aspect 18 \
              --msgbox "Encryption Key restore successful!" 0 0
            break
          fi
        done
        umount "${TMP_PATH}/mdX"
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
            # fixDSMRootPart "${I}"
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
        if [ "${BACKUPKEY}" = "true" ]; then
          dialog --backtitle "$(backtitle)" --title "Backup Encrytion Key"  \
            --msgbox "Encryption Key backup successful!" 0 0
        else
          dialog --backtitle "$(backtitle)" --title "Backup Encrytion Key"  \
            --msgbox "No Encryption Key found!" 0 0
        fi
        ;;
      4)
        [ -f "${USER_CONFIG_FILE}" ] && mv -f "${USER_CONFIG_FILE}" "${USER_CONFIG_FILE}.bak"
        HWID="$(genHWID)"
        if curl -skL "https://arc.auxxxilium.tech?cdown=${HWID}" -o "${USER_CONFIG_FILE}" 2>/dev/null; then
          dialog --backtitle "$(backtitle)" --title "Online Restore" --msgbox "Online Restore successful!" 5 40
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
          ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          TEXT+="\nArc Patch: ${ARCPATCH}"
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
        ./init.sh
        ;;
      5)
        HWID="$(genHWID)"
        curl -sk -X POST -F "file=@${USER_CONFIG_FILE}" "https://arc.auxxxilium.tech?cup=${HWID}&userid=${USERID}" 2>/dev/null
        if [ $? -eq 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Online Backup" --msgbox "Online Backup successful!" 5 40
        else
          dialog --backtitle "$(backtitle)" --title "Online Backup" --msgbox "Online Backup failed!" 5 40
        fi
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
  ARC_BRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
  while true; do
    dialog --backtitle "$(backtitle)" --title "Update" --colors --cancel-label "Exit" \
      --menu "Choose an Option" 0 0 0 \
      1 "Update Loader \Z1(no reflash)\Zn" \
      2 "Update Dependencies" \
      3 "Update Configs and Arc Patch" \
      4 "Switch Arc Branch: \Z1${ARC_BRANCH}\Zn" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
      1)
        # Ask for Tag
        TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
        OLD="$(cat ${PART1_PATH}/ARC-VERSION)"
        dialog --clear --backtitle "$(backtitle)" --title "Update Loader" \
          --menu "Current: ${OLD} -> Which Version?" 7 50 0 \
          1 "Latest ${TAG}" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          [ -z "${TAG}" ] && return 1
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Loader" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG=$(cat "${TMP_PATH}/input")
          [ -z "${TAG}" ] && return 1
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
          1 "stable - Less Hardware support / faster Boot" \
          2 "next - More Hardware support / slower Boot" \
          3 "dev - Development only" \
          2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && break
        opts=$(cat ${TMP_PATH}/opts)
        if [ ${opts} -eq 1 ]; then
          ARC_BRANCH="stable"
        elif [ ${opts} -eq 2 ]; then
          ARC_BRANCH="next"
        elif [ ${opts} -eq 3 ]; then
          ARC_BRANCH="dev"
        fi
        writeConfigKey "arc.branch" "${ARC_BRANCH}" "${USER_CONFIG_FILE}"
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
  SECURE=$(dmesg 2>/dev/null | grep -i "Secure Boot" | awk -F'] ' '{print $2}')
  VENDOR=$(dmesg 2>/dev/null | grep -i "DMI:" | head -1 | sed 's/\[.*\] DMI: //i')
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
  ETHN=$(echo ${ETHX} | wc -w)
  ARC_BRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
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
    ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
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
  TEXT=""
  # Print System Informations
  TEXT+="\n\n\Z4> System: ${MACHINE} | ${BOOTSYS} | ${BUS}\Zn"
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
  TEXT+="\n  CPU Scaling: \Zb${CPUFREQ}\Zn"
  TEXT+="\n  Secure Boot: \Zb${SECURE}\Zn"
  TEXT+="\n  Bootdisk: \Zb${LOADER_DISK}\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4> Network: ${ETHN} NIC\Zn"
  for N in ${ETHX}; do
    COUNT=0
    DRIVER=$(ls -ld /sys/class/net/${N}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    while true; do
      if [ -z "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
        TEXT+="\n   ${DRIVER}: \ZbDOWN\Zn"
        break
      fi
      if [ "0" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
        TEXT+="\n   ${DRIVER}: \ZbNOT CONNECTED\Zn"
        break
      fi
      if [ ${COUNT} -ge ${TIMEOUT} ]; then
        TEXT+="\n   ${DRIVER}: \ZbTIMEOUT\Zn"
        break
      fi
      COUNT=$((${COUNT} + 1))
      IP="$(getIP "${N}")"
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${N} 2>/dev/null | grep "Speed:" | awk '{print $2}')
        if [[ "${IP}" =~ ^169\.254\..* ]]; then
          TEXT+="\n   ${DRIVER} (${SPEED}): \ZbLINK LOCAL (No DHCP server found.)\Zn"
        else
          TEXT+="\n   ${DRIVER} (${SPEED}): \Zb${IP}\Zn"
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
  TEXT+="\n  Offline Mode: \Zb${ARCOFFLINE}\Zn"
  [ "${ARCOFFLINE}" = "true" ] && TEXT+="\n  Offline Mode: \Zb${ARCOFFLINE}\Zn"
  if [ "${CONFDONE}" = "true" ]; then
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
    PORTNUM=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep 'vmbus:acpi' | wc -l)
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
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
  for N in ${ETHX}; do
    echo
    DRIVER=$(ls -ld /sys/class/net/${N}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    echo -e "Interface: ${N} (${DRIVER})"
    if [ "0" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
      echo -e "Link: NOT CONNECTED"
      continue
    fi
    if [ -z "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
      echo -e "Link: DOWN"
      continue
    fi
    echo -e "Link: CONNECTED"
    addr=$(getIP "${N}")
    netmask=$(ifconfig "${N}" | grep inet | grep 255 | awk '{print $4}' | cut -f2 -d':')
    echo -e "IP Address: ${addr}"
    echo -e "Netmask: ${netmask}"
    echo
    gateway=$(route -n | grep 'UG[ \t]' | awk '{print $2}' | head -n 1)
    echo -e "Gateway: ${gateway}"
    dnsserver=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
    echo -e "DNS Server:\n${dnsserver}"
    echo
    if [ "${ARCOFFLINE}" = "true" ]; then
      echo -e "Offline Mode: ${ARCOFFLINE}"
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
  TEXT+="\n"
  TEXT+="\n\Z4>> Based on:\Zn"
  TEXT+="\n   Redpill: \ZbTTG / Pocopico\Zn"
  TEXT+="\n   ARPL/RR: \Zbfbelavenuto / wjz304\Zn"
  TEXT+="\n   Others: \Zb007revad / more...\Zn"
  TEXT+="\n   System: \ZbBuildroot\Zn"
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
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
  IPCON=""
  for N in ${ETHX}; do
    MACR="$(cat /sys/class/net/${N}/address 2>/dev/null | sed 's/://g')"
    IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
    IFS='/' read -r -a IPRA <<<"${IPR}"

    MSG="Set ${N}(${MACR}) IP to: (Delete if empty)"
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
              if [ "1" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
                ip addr flush dev "${N}"
              fi
              deleteConfigKey "network.${MACR}" "${USER_CONFIG_FILE}"
              IP="$(getIP)"
              [ -z "${IPCON}" ] && IPCON="${IP}"
              sleep 1
            fi
          else
            if [ "1" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
              ip addr flush dev "${N}"
              ip addr add "${address}/${netmask:-"255.255.255.0"}" dev "${N}"
              if [ -n "${gateway}" ]; then
                ip route add default via "${gateway}" dev "${N}"
              fi
              if [ -n "${dnsname:-${gateway}}" ]; then
                sed -i "/nameserver ${dnsname:-${gateway}}/d" /etc/resolv.conf
                echo "nameserver ${dnsname:-${gateway}}" >>/etc/resolv.conf
              fi
            fi
            writeConfigKey "network.${MACR}" "${address}/${netmask}/${gateway}/${dnsname}" "${USER_CONFIG_FILE}"
            IP="$(getIP)"
            [ -z "${IPCON}" ] && IPCON="${IP}"
            sleep 1
          fi
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ) 2>&1 | dialog --backtitle "$(backtitle)" --title "StaticIP" \
          --progressbox "Setting IP ..." 20 100
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
    2>${TMP_PATH}/resp
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
  local HTTP=${HTTPPORT:-8080}
  local DUFS=${DUFSPORT:-7304}
  local TTYD=${TTYDPORT:-7681}
  while true; do
    dialog --backtitle "$(backtitle)" --title "Loader Ports" \
      --form "${MSG}" 11 70 3 "HTTP" 1 1 "${HTTPPORT}" 1 10 55 0 "DUFS" 2 1 "${DUFSPORT}" 2 10 55 0 "TTYD" 3 1 "${TTYDPORT}" 3 10 55 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
    0) # ok-button
      HTTP=$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)
      DUFS=$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)
      TTYD=$(sed -n '3p' "${TMP_PATH}/resp" 2>/dev/null)
      EP=""
      for P in "${HTTPPORT}" "${DUFSPORT}" "${TTYDPORT}"; do check_port "${P}" || EP="${EP} ${P}"; done
      if [ -n "${EP}" ]; then
        dialog --backtitle "$(backtitle)" --title "Loader Ports" \
          --yesno "Invalid ${EP} Port, retry?" 0 0
        [ $? -eq 0 ] && continue || break
      fi
      rm -f "/etc/arc.conf"
      [ "${HTTPPORT:-8080}" != "8080" ] && echo "HTTP_PORT=${HTTPPORT}" >>"/etc/arc.conf"
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
        [ ! "${HTTP:-8080}" = "${HTTPPORT:-8080}" ] && echo "/etc/init.d/S90thttpd restart"
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
      [ $? -ne 0 ] && continue
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        echo "UPDATE task SET enable = 0;" | sqlite3 ${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db
        sync
        echo "true" >${TMP_PATH}/isEnable
      fi
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Scheduled Tasks" \
    --progressbox "Modifying..." 20 100
  [ "$(cat ${TMP_PATH}/isEnable 2>/dev/null)" = "true" ] && MSG="Disable all scheduled tasks successful." || MSG="Disable all scheduled tasks failed."
  dialog --backtitle "$(backtitle)" --title Scheduled Tasks \
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
# let user format disks from inside arc
function formatDisks() {
  rm -f "${TMP_PATH}/opts"
  while read -r KNAME SIZE TYPE MODEL PKNAME; do
    [ "${KNAME}" = "N/A" ] || [ "${SIZE:0:1}" = "0" ] && continue
    [ "${KNAME:0:7}" = "/dev/md" ] && continue
    [ "${KNAME}" = "${LOADER_DISK}" ] || [ "${PKNAME}" = "${LOADER_DISK}" ] && continue
    printf "\"%s\" \"%-6s %-4s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" "${MODEL}" >>"${TMP_PATH}/opts"
  done < <(lsblk -Jpno KNAME,SIZE,TYPE,MODEL,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.size) \(.type) \(.model) \(.pkname)"' 2>/dev/null)
  if [ ! -f "${TMP_PATH}/opts" ]; then
    dialog --backtitle "$(backtitle)" --title "Format Disks" \
      --msgbox "No disk found!" 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --title "Format Disks" \
    --checklist "Select Disks" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat "${TMP_PATH}/resp")
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
  while read -r KNAME SIZE TYPE MODEL PKNAME; do
    [ "${KNAME}" = "N/A" ] || [ "${SIZE:0:1}" = "0" ] && continue
    [ "${KNAME:0:7}" = "/dev/md" ] && continue
    [ "${KNAME}" = "${LOADER_DISK}" ] || [ "${PKNAME}" = "${LOADER_DISK}" ] && continue
    printf "\"%s\" \"%-6s %-4s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" "${MODEL}" >>"${TMP_PATH}/opts"
  done < <(lsblk -Jpno KNAME,SIZE,TYPE,MODEL,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.size) \(.type) \(.model) \(.pkname)"' 2>/dev/null)

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
  dialog --backtitle "$(backtitle)" --title "Reset Loader" --aspect 18 \
    --yesno "Reset successful.\nReboot required!" 0 0
  [ $? -ne 0 ] && return
  rebootTo config
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
    if [ -z "${SSH_TTY}" ]; then # web
      mv -f "${TMP_PATH}/logs.tar.gz" "/var/www/data/logs.tar.gz"
      URL="http://${IPCON}:${HTTPPORT:-8080}/logs.tar.gz"
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
      cp -f "${TMP_PATH}/dsmconfig.tar.gz" "/var/www/data/dsmconfig.tar.gz"
      chmod 644 "/var/www/data/dsmconfig.tar.gz"
      URL="http://${IPCON}:${HTTPPORT:-8080}/dsmconfig.tar.gz"
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
  if [ "${REDEST}" = "poweroff" ]; then
    poweroff
    exit 0
  elif [ "${REDEST}" = "shell" ]; then
    clear
    exit 0
  elif [ "${REDEST}" = "network" ]; then
    clear
    /etc/init.d/S41dhcpcd restart
    ./init.sh
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
  if [ "${ARCMODE}" = "config" ]; then
    # Selectable CPU governors
    [ "${PLATFORM}" = "epyc7002" ] && echo -e "schedutil \"use schedutil to scale frequency *\"" >>"${TMP_PATH}/opts"
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
    [ "${PLATFORM}" = "epyc7002" ] && CPUGOVERNOR="schedutil"
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
  ARCOFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"
  mkdir -p "${USER_UP_PATH}"
  DSM_FILE="${USER_UP_PATH}/${PAT_HASH}.tar"
  VALID="false"
  if [ ! -f "${DSM_FILE}" ] && [ "${ARCOFFLINE}" = "false" ]; then
    rm -f ${USER_UP_PATH}/*.tar
    dialog --backtitle "$(backtitlep)" --colors --title "DSM Boot Files" \
      --infobox "Downloading DSM Boot Files..." 3 40
    # Get new Files
    DSM_URL="https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/files/${MODEL/+/%2B}/${PRODUCTVER}/${PAT_HASH}.tar"
    if curl -skL "${DSM_URL}" -o "${DSM_FILE}" 2>/dev/null; then
      VALID="true"
    fi
  elif [ ! -f "${DSM_FILE}" ] && [ "${ARCOFFLINE}" = "true" ]; then
    rm -f ${USER_UP_PATH}/*.tar
    dialog --backtitle "$(backtitlep)" --colors --title "DSM Boot Files" \
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
    dialog --backtitle "$(backtitlep)" --title "DSM Boot Files" --aspect 18 \
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
    if echo "${USERID}" | grep -vq "Hardware ID"; then
      dialog --backtitle "$(backtitle)" --title "HardwareID" \
        --msgbox "HardwareID: ${HWID}\nYour HardwareID is registered to UserID: ${USERID}!" 6 70
      writeConfigKey "arc.hardwareid" "${HWID}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "${USERID}" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "true" "${USER_CONFIG_FILE}"
      break
    else
      dialog --backtitle "$(backtitle)" --title "HardwareID" \
        --yes-label "Retry" --no-label "Cancel" --yesno "HardwareID: ${HWID}\nRegister your HardwareID on\nhttps://arc.auxxxilium.tech (Discord Account needed).\nPress Retry after you registered it." 8 60
      [ $? -ne 0 ] && break
      writeConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "false" "${USER_CONFIG_FILE}"
    fi
  done
  return
}

###############################################################################
# Check HardwareID
function checkHardwareID() {
  HWID="$(genHWID)"
  USERID="$(curl -skL -m 10 "https://arc.auxxxilium.tech?hwid=${HWID}" 2>/dev/null)"
  [ ! -f "${S_FILE}.bak" ] && cp -f "${S_FILE}" "${S_FILE}.bak" 2>/dev/null || true
  if echo "${USERID}" | grep -vq "Hardware ID"; then
    if curl -skL -m 10 "https://arc.auxxxilium.tech?hwid=${HWID}&userid=${USERID}" -o "${S_FILE}" 2>/dev/null; then
      writeConfigKey "arc.hardwareid" "${HWID}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "${USERID}" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "true" "${USER_CONFIG_FILE}"
    else
      writeConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
      writeConfigKey "bootscreen.hwidinfo" "false" "${USER_CONFIG_FILE}"
      [ -f "${S_FILE}.bak" ] && mv -f "${S_FILE}.bak" "${S_FILE}" 2>/dev/null
    fi
  else
    USERID=""
    writeConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
    writeConfigKey "bootscreen.hwidinfo" "false" "${USER_CONFIG_FILE}"
    [ -f "${S_FILE}.bak" ] && mv -f "${S_FILE}.bak" "${S_FILE}" 2>/dev/null
  fi
  return 0
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
  echo -e "dsminfo" >"${TMP_PATH}/bootscreen"
  echo -e "systeminfo" >>"${TMP_PATH}/bootscreen"
  echo -e "diskinfo" >>"${TMP_PATH}/bootscreen"
  echo -e "hwidinfo" >>"${TMP_PATH}/bootscreen"
  echo -e "dsmlogo" >>"${TMP_PATH}/bootscreen"
  while read -r BOOTSCREEN; do
    arrayExistItem "${BOOTSCREEN}" "${!BOOTSCREENS[@]}" && ACT="on" || ACT="off"
    echo -e "${BOOTSCREEN} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
  done < <(cat "${TMP_PATH}/bootscreen")
  dialog --backtitle "$(backtitle)" --title "Bootscreen" --colors --aspect 18 \
    --checklist "Select Bootscreen Informations\Zn\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
    --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp=$(cat ${TMP_PATH}/resp)
  unset BOOTSCREENS
  declare -A BOOTSCREENS
  writeConfigKey "bootscreen" "{}" "${USER_CONFIG_FILE}"
  for BOOTSCREEN in ${resp}; do
    BOOTSCREENS["${BOOTSCREEN}"]=""
    writeConfigKey "bootscreen.\"${BOOTSCREEN}\"" "true" "${USER_CONFIG_FILE}"
  done
}