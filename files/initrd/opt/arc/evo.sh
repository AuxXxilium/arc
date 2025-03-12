#!/usr/bin/env bash

###############################################################################
# Overlay Init Section
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/functions.sh"
. "${ARC_PATH}/arc-functions.sh"
. "${ARC_PATH}/include/addons.sh"
. "${ARC_PATH}/include/modules.sh"
. "${ARC_PATH}/include/update.sh"

# Get Keymap and Timezone and check System
onlineCheck
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
systemCheck
readData

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${ARC_TITLE}$([ -n "${NEWTAG}" ] && [ -n "${ARC_VERSION}" ] && [ ${ARC_VERSION//[!0-9]/} -lt ${NEWTAG//[!0-9]/} ] && echo " > ${NEWTAG}") | "
  BACKTITLE+="${MODEL:-(Model)} | "
  BACKTITLE+="${PRODUCTVER:-(Version)} | "
  BACKTITLE+="${IPCON:-(no IP)} | "
  BACKTITLE+="Patch: ${ARC_PATCH} | "
  BACKTITLE+="Config: ${CONFDONE} | "
  BACKTITLE+="Build: ${BUILDDONE} | "
  BACKTITLE+="${MACHINE}(${BUS}) | "
  [ -n "${KEYMAP}" ] && BACKTITLE+="KB: ${KEYMAP}"
  [ "${ARC_OFFLINE}" = "true" ] && BACKTITLE+=" | Offline"
  echo "${BACKTITLE}"
}

###############################################################################
# Advanced Menu
function advancedMenu() {
  NEXT="a"
  while true; do
    rm -f "${TMP_PATH}/menu" "${TMP_PATH}/resp" >/dev/null 2>&1 || true
    write_menu "=" "\Z4===== System ====\Zn"

    if [ "${CONFDONE}" = "true" ]; then
      if [ "${BOOTOPTS}" = "true" ]; then
        write_menu "6" "\Z1Hide Boot Options\Zn"
        write_menu_value "m" "Kernelload" "${KERNELLOAD}"
        write_menu_value "E" "eMMC Boot Support" "${EMMCBOOT}"
        if [ "${DIRECTBOOT}" = "false" ]; then
          write_menu_value "i" "Boot IP Waittime" "${BOOTIPWAIT}"
        fi
        write_menu_value "q" "Directboot" "${DIRECTBOOT}"
        write_menu_value "W" "RD Compression" "${RD_COMPRESSED}"
        write_menu_value "X" "Sata DOM" "${SATADOM}"
        write_menu_value "u" "LKM Version" "${LKM}"
      else
        write_menu "6" "\Z1Show Boot Options\Zn"
      fi

      if [ "${DSMOPTS}" = "true" ]; then
        write_menu "7" "\Z1Hide DSM Options\Zn"
        write_menu "j" "Cmdline"
        write_menu "k" "Synoinfo"
        write_menu "N" "Add new User"
        write_menu "t" "Change User Password"
        write_menu "J" "Reset Network Config"
        write_menu "T" "Disable all scheduled Tasks"
        write_menu "M" "Mount DSM Storage Pool"
        write_menu "l" "Edit User Config"
        write_menu "s" "Allow Downgrade Version"
      else
        write_menu "7" "\Z1Show DSM Options\Zn"
      fi
    fi

    if [ "${LOADEROPTS}" = "true" ]; then
      write_menu "8" "\Z1Hide Loader Options\Zn"
      write_menu "D" "StaticIP for Loader/DSM"
      write_menu "f" "Bootscreen Options"
      write_menu "U" "Change Loader Password"
      write_menu "Z" "Change Loader Ports"
      write_menu "w" "Reset Loader to Defaults"
      write_menu "L" "Grep Logs from dbgutils"
      write_menu "B" "Grep DSM Config from Backup"
      write_menu "=" "\Z1== Edit with caution! ==\Zn"
      write_menu "C" "Clone Loader to another Disk"
      write_menu "n" "Grub Bootloader Config"
      write_menu "y" "Choose a Keymap for Loader"
      write_menu "F" "\Z1Formate Disks\Zn"
    else
      write_menu "8" "\Z1Show Loader Options\Zn"
    fi

    dialog --clear --default-item ${NEXT} --backtitle "$(backtitle)" --title "Easy UI Advanced" --colors \
          --cancel-label "Back" \
          --menu "" 0 0 0 --file "${TMP_PATH}/menu" \
          2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
      0)
        resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
        [ -z "${resp}" ] && return
        case ${resp} in
          # DSM Section
          7) [ "${DSMOPTS}" = "true" ] && DSMOPTS='false' || DSMOPTS='true'
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
          T) disablescheduledTasks; NEXT="T" ;;
          B) getbackup; NEXT="B" ;;
          # Loader Section
          8) [ "${LOADEROPTS}" = "true" ] && LOADEROPTS='false' || LOADEROPTS='true'
            LOADEROPTS="${LOADEROPTS}"
            NEXT="8"
            ;;
          D) staticIPMenu; NEXT="D" ;;
          f) bootScreen; NEXT="f" ;;
          Z) loaderPorts; NEXT="Z" ;;
          U) loaderPassword; NEXT="U" ;;
          L) greplogs; NEXT="L" ;;
          w) resetLoader; NEXT="w" ;;
          C) cloneLoader; NEXT="C" ;;
          n) editGrubCfg; NEXT="n" ;;
          y) keymapMenu; NEXT="y" ;;
          F) formatDisks; NEXT="F" ;;
          6) [ "${BOOTOPTS}" = "true" ] && BOOTOPTS='false' || BOOTOPTS='true'
            BOOTOPTS="${BOOTOPTS}"
            NEXT="6"
            ;;
          m) [ "${KERNELLOAD}" = "kexec" ] && KERNELLOAD='power' || KERNELLOAD='kexec'
            writeConfigKey "kernelload" "${KERNELLOAD}" "${USER_CONFIG_FILE}"
            NEXT="m"
            ;;
          E) [ "${EMMCBOOT}" = "true" ] && EMMCBOOT='false' || EMMCBOOT='true'
            if [ "${EMMCBOOT}" = "false" ]; then
              writeConfigKey "emmcboot" "false" "${USER_CONFIG_FILE}"
              deleteConfigKey "synoinfo.disk_swap" "${USER_CONFIG_FILE}"
              deleteConfigKey "synoinfo.supportraid" "${USER_CONFIG_FILE}"
              deleteConfigKey "synoinfo.support_emmc_boot" "${USER_CONFIG_FILE}"
              deleteConfigKey "synoinfo.support_install_only_dev" "${USER_CONFIG_FILE}"
            elif [ "${EMMCBOOT}" = "true" ]; then
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
          W) RD_COMPRESSED=$([ "${RD_COMPRESSED}" = "true" ] && echo 'false' || echo 'true')
            writeConfigKey "rd-compressed" "${RD_COMPRESSED}" "${USER_CONFIG_FILE}"
            writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
            BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
            NEXT="W"
            ;;
          X) satadomMenu; NEXT="X" ;;
          u) [ "${LKM}" = "prod" ] && LKM='dev' || LKM='prod'
            writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
            writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
            BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
            NEXT="u"
            ;;
          i) bootipwaittime; NEXT="i" ;;
          q) [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
            grub-editenv ${USER_GRUBENVFILE} create
            writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
            NEXT="q"
            ;;
        esac
        ;;
      *)
        break
        ;;
    esac
  done
  return
}

###############################################################################
###############################################################################
# Main loop
if [ "${ARC_MODE}" = "update" ]; then
  if [ "${ARC_OFFLINE}" != "true" ]; then
    updateLoader
  else
    dialog --backtitle "$(backtitle)" --title "Arc Update" \
      --infobox "Update is not possible in Offline Mode!" 5 40
    sleep 3
    exec reboot
  fi
elif [ "${ARC_MODE}" = "automated" ]; then
  if [ "${BUILDDONE}" = "false" ] || [ "${MODEL}" != "${MODELID}" ]; then
    arcModel
  else
    make
  fi
elif [ "${ARC_MODE}" = "config" ]; then
  NEXT="1"
  while true; do
    rm -f "${TMP_PATH}/menu" "${TMP_PATH}/resp" >/dev/null 2>&1 || true
    write_menu "=" "\Z4===== Main =====\Zn"
    if [ -z "${USERID}" ] && [ "${ARC_OFFLINE}" = "false" ]; then
      write_menu_value "0" "HardwareID" "${HARDWAREID}"
    fi

    write_menu_value "1" "Model" "${MODEL}"

    if [ "${CONFDONE}" = "true" ]; then
      write_menu_value "e" "Version" "${PRODUCTVER}"
      write_menu_value "=" "DT" "${DT}"
      write_menu_value "=" "Platform" "${PLATFORM}"

      if [ -n "${USERID}" ] && [ "${ARC_OFFLINE}" = "false" ]; then
        write_menu_value "p" "Arc Patch" "${ARC_PATCH}"
      elif [ "${ARC_OFFLINE}" = "false" ]; then
        write_menu "p" "Arc Patch: \Z4Register HardwareID first\Zn"
      else
        write_menu "p" "SN/Mac Options"
      fi

      if [ "${PLATFORM}" = "epyc7002" ]; then
        CPUINFO="$(cat /proc/cpuinfo | grep MHz | wc -l)"
        if [ ${CPUINFO} -gt 24 ]; then
          write_menu "=" "Custom Kernel should be used for this CPU"
        fi
        write_menu_value "K" "Kernel" "${KERNEL}"
      fi

      write_menu "b" "Addons"

      for addon in "cpufreqscaling" "storagepanel" "sequentialio"; do
        if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "${addon}"; then
          case "${addon}" in
            "cpufreqscaling") write_menu_value "g" "Scaling Governor" "${GOVERNOR}" ;;
            "storagepanel") write_menu_value "P" "StoragePanel" "${STORAGEPANEL:-auto}" ;;
            "sequentialio") write_menu_value "Q" "SequentialIO" "${SEQUENTIALIO}" ;;
          esac
        fi
      done

      write_menu "d" "Modules"
      write_menu_value "O" "Official Driver Priority" "${ODP}"

      if [ "${DT}" = "false" ] && [ ${SATACONTROLLER} -gt 0 ]; then
        write_menu_value "S" "PortMap" "${REMAP}"
        write_menu_value "=" "Mapping" "${PORTMAP}"
      fi

      if [ "${DT}" = "true" ]; then
        write_menu_value "H" "Hotplug/SortDrives" "${HDDSORT}"
      else
        write_menu_value "h" "USB as Internal" "${USBMOUNT}"
      fi
    fi

    write_menu_value "c" "Offline Mode" "${ARC_OFFLINE}"
    write_menu "9" "Advanced Options"
    write_menu "=" "\Z4===== Diag =====\Zn"
    write_menu "a" "Sysinfo"
    write_menu "A" "Networkdiag"
    write_menu "=" "\Z4===== Misc =====\Zn"
    write_menu "x" "Backup/Restore/Recovery"
    [ "${ARC_OFFLINE}" = "false" ] && write_menu "z" "Update Menu"
    write_menu "I" "Power/Service Menu"
    write_menu "V" "Credits"

    if [ "${CONFDONE}" = "false" ]; then
      EXTRA_LABEL="Config"
    elif [ "${CONFDONE}" = "true" ]; then
      EXTRA_LABEL="Build"
    elif [ "${BUILDDONE}" = "true" ]; then
      EXTRA_LABEL="Boot"
    fi
    if [ "$TERM" != "xterm-256color" ]; then
      WEBCONFIG="Webconfig: http://${IPCON}${HTTPPORT:+:$HTTPPORT}"
    else
      WEBCONFIG=""
    fi
    dialog --clear --default-item ${NEXT} --backtitle "$(backtitle)" --title "Easy UI" --colors \
          --cancel-label "Advanced UI" --help-button --help-label "Exit" \
          --extra-button --extra-label "${EXTRA_LABEL}" \
          --menu "${WEBCONFIG}" 0 0 0 --file "${TMP_PATH}/menu" \
          2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
      0)
        resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
        [ -z "${resp}" ] && return
        case ${resp} in
          0) genHardwareID; NEXT="0" ;;
          1) arcModel; NEXT="2" ;;
          b) addonMenu; NEXT="b" ;;
          d) modulesMenu; NEXT="d" ;;
          e) ONLYVERSION="true" && arcVersion; NEXT="e" ;;
          p) ONLYPATCH="true" && checkHardwareID && arcPatch; NEXT="p" ;;
          S) storageMenu; NEXT="S" ;;
          g) governorMenu; NEXT="g" ;;
          P) storagepanelMenu; NEXT="P" ;;
          Q) sequentialIOMenu; NEXT="Q" ;;
          K) KERNEL=$([ "${KERNEL}" = "official" ] && echo 'custom' || echo 'official')
            writeConfigKey "kernel" "${KERNEL}" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --title "Kernel" \
              --infobox "Switching Kernel to ${KERNEL}! Stay patient..." 4 50
            if [ "${ODP}" = "true" ]; then
              ODP="false"
              writeConfigKey "odp" "${ODP}" "${USER_CONFIG_FILE}"
            fi
            PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
            PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
            KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
            [ "${PLATFORM}" = "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
            if [ -n "${PLATFORM}" ] && [ -n "${KVERP}" ]; then
              writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
              mergeConfigModules "$(getAllModules "${PLATFORM}" "${KVERP}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
            fi
            writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
            BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
            NEXT="K"
            ;;
          H) [ "${HDDSORT}" = "true" ] && HDDSORT='false' || HDDSORT='true'
            writeConfigKey "hddsort" "${HDDSORT}" "${USER_CONFIG_FILE}"
            writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
            BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
            NEXT="H"
            ;;
          h) [ "${USBMOUNT}" = "true" ] && USBMOUNT='false' || USBMOUNT='true'
            writeConfigKey "usbmount" "${USBMOUNT}" "${USER_CONFIG_FILE}"
            writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
            BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
            NEXT="h"
            ;;
          O) [ "${ODP}" = "false" ] && ODP='true' || ODP='false'
            writeConfigKey "odp" "${ODP}" "${USER_CONFIG_FILE}"
            writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
            BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
            NEXT="O"
            ;;
          c) ARC_OFFLINE=$([ "${ARC_OFFLINE}" = "true" ] && echo 'false' || echo 'true')
            writeConfigKey "arc.offline" "${ARC_OFFLINE}" "${USER_CONFIG_FILE}"
            [ "${ARC_OFFLINE}" = "false" ] && exec arc.sh
            NEXT="c"
            ;;
          # Diag Section
          a) sysinfo; NEXT="a" ;;
          A) networkdiag; NEXT="A" ;;
          # Misc Settings
          x) backupMenu; NEXT="x" ;;
          z) updateMenu; NEXT="z" ;;
          I) rebootMenu; NEXT="I" ;;
          V) credits; NEXT="V" ;;
          9) advancedMenu; NEXT="9" ;;
        esac
        ;;
      1)
        exec arc.sh
        ;;
      3)
        if [ "${CONFDONE}" = "false" ]; then
          arcModel
        elif [ "${CONFDONE}" = "true" ]; then
          arcSummary
        elif [ "${BUILDDONE}" = "true" ]; then
          boot
        fi
        ;;
      *)
        break
        ;;
    esac
  done
else
  echo "Unknown Mode: ${ARC_MODE} - Rebooting to Config Mode"
  sleep 3
  rebootTo config
fi

# Inform user
echo -e "Call \033[1;34marc.sh\033[0m to configure Loader"
echo
echo -e "Web Config: \033[1;34mhttp://${IPCON}${HTTPPORT:+:$HTTPPORT}\033[0m"
echo
echo -e "SSH Access:"
echo -e "IP: \033[1;34m${IPCON}\033[0m"
echo -e "User: \033[1;34mroot\033[0m"
echo -e "Password: \033[1;34marc\033[0m"
echo
