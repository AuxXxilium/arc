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
ARCOFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
systemCheck
readData

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${ARC_TITLE}$([ -n "${NEWTAG}" ] && [ -n "${ARC_VERSION}" ] && [ ${ARC_VERSION//[!0-9]/} -lt ${NEWTAG//[!0-9]/} ] && echo " > ${NEWTAG}") | "
  BACKTITLE+="${MODEL:-(Model)} | "
  BACKTITLE+="${PRODUCTVER:-(Version)} | "
  BACKTITLE+="${IPCON:-(IP)} | "
  BACKTITLE+="Patch: ${ARCPATCH} | "
  BACKTITLE+="Config: ${CONFDONE} | "
  BACKTITLE+="Build: ${BUILDDONE} | "
  BACKTITLE+="${MACHINE}(${BUS}) | "
  [ -n "${KEYMAP}" ] && BACKTITLE+="KB: ${KEYMAP}"
  [ "${ARCOFFLINE}" = "true" ] && BACKTITLE+=" | Offline"
  echo "${BACKTITLE}"
}

###############################################################################
###############################################################################
# Main loop
if [ "${ARCMODE}" = "update" ]; then
  if [ "${ARCOFFLINE}" != "true" ]; then
    updateLoader
  else
    dialog --backtitle "$(backtitle)" --title "Arc Update" \
      --infobox "Update is not possible in Offline Mode!" 5 40
    sleep 3
    exec reboot
  fi
elif [ "${ARCMODE}" = "automated" ]; then
  if [ "${BUILDDONE}" = "false" ] || [ "${MODEL}" != "${MODELID}" ]; then
    arcModel
  else
    make
  fi
elif [ "${ARCMODE}" = "config" ]; then
  [ "${CONFDONE}" = "true" ] && NEXT="2" || NEXT="1"
  [ "${BUILDDONE}" = "true" ] && NEXT="3" || NEXT="1"
  while true; do
    rm -f "${TMP_PATH}/menu" "${TMP_PATH}/resp" >/dev/null 2>&1 || true

    write_menu "=" "\Z4===== Main =====\Zn"

    if [ -z "${USERID}" ] && [ "${ARCOFFLINE}" = "false" ]; then
      write_menu "0" "HardwareID for Arc Patch"
    fi

    write_menu "1" "Choose Model"

    if [ "${CONFDONE}" = "true" ]; then
      if [ -f "${MOD_ZIMAGE_FILE}" ] && [ -f "${MOD_RDGZ_FILE}" ]; then
        write_menu "2" "Rebuild Loader"
      else
        write_menu "2" "Build Loader"
      fi
    fi

    if [ "${BUILDDONE}" = "true" ]; then
      write_menu "3" "Boot Loader"
    fi

    write_menu "=" "\Z4===== Info =====\Zn"
    write_menu "a" "Sysinfo"
    write_menu "A" "Networkdiag"
    
    if [ "${CONFDONE}" = "true" ]; then
      if [ "${ARCOPTS}" = "true" ]; then
        write_menu "4" "\Z1Hide Arc DSM Options\Zn"
      else
        write_menu "4" "\Z1Show Arc DSM Options\Zn"
      fi

      if [ "${ARCOPTS}" = "true" ]; then
        write_menu "=" "\Z4==== Arc DSM ====\Zn"
        write_menu "b" "Addons"
        write_menu "d" "Modules"
        write_menu "e" "Version"
        write_menu "p" "SN/Mac Options"
    
        if [ "${DT}" = "false" ] && [ ${SATACONTROLLER} -gt 0 ]; then
          write_menu "S" "Sata PortMap"
        fi

        if [ "${DT}" = "true" ]; then
          write_menu "o" "DTS Map Options"
        fi

        for addon in "cpufreqscaling" "storagepanel" "sequentialio"; do
          if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "${addon}"; then
            case "${addon}" in
              "cpufreqscaling") write_menu "g" "Scaling Governor" ;;
              "storagepanel") write_menu "P" "StoragePanel" ;;
              "sequentialio") write_menu "Q" "SequentialIO" ;;
            esac
          fi
        done

        if [ "${PLATFORM}" = "epyc7002" ]; then
          write_menu_with_color "K" "Kernel" "${KERNEL}"
        fi

        if [ "${DT}" = "true" ]; then
          write_menu_with_color "H" "Hotplug/SortDrives" "${HDDSORT}"
        else
          write_menu_with_color "h" "USB as Internal" "${USBMOUNT}"
        fi
      fi

      if [ "${BOOTOPTS}" = "true" ]; then
        write_menu "6" "\Z1Hide Boot Options\Zn"
      else
        write_menu "6" "\Z1Show Boot Options\Zn"
      fi

      if [ "${BOOTOPTS}" = "true" ]; then
        write_menu "=" "\Z4===== Boot =====\Zn"
        write_menu_with_color "m" "Boot Kernelload" "${KERNELLOAD}"
        write_menu_with_color "E" "eMMC Boot Support" "${EMMCBOOT}"
        if [ "${DIRECTBOOT}" = "false" ]; then
          write_menu_with_color "i" "Boot IP Waittime" "${BOOTIPWAIT}"
        fi
        write_menu_with_color "q" "Directboot" "${DIRECTBOOT}"
      fi

      if [ "${DSMOPTS}" = "true" ]; then
        write_menu "7" "\Z1Hide DSM Options\Zn"
      else
        write_menu "7" "\Z1Show DSM Options\Zn"
      fi

      if [ "${DSMOPTS}" = "true" ]; then
        write_menu "=" "\Z4===== DSM =====\Zn"
        write_menu "j" "Cmdline"
        write_menu "k" "Synoinfo"
        write_menu "N" "Add new User"
        write_menu "t" "Change User Password"
        write_menu "J" "Reset Network Config"
        write_menu "T" "Disable all scheduled Tasks"
        write_menu "M" "Mount DSM Storage Pool"
        write_menu "l" "Edit User Config"
        write_menu "s" "Allow Downgrade Version"
        write_menu_with_color "O" "Official Driver Priority" "${ODP}"
      fi
    fi

    if [ "${LOADEROPTS}" = "true" ]; then
      write_menu "8" "\Z1Hide Loader Options\Zn"
    else
      write_menu "8" "\Z1Show Loader Options\Zn"
    fi

    if [ "${LOADEROPTS}" = "true" ]; then
      write_menu "=" "\Z4===== Loader =====\Zn"
      write_menu_with_color "c" "Offline Mode" "${ARCOFFLINE}"
      write_menu "D" "StaticIP for Loader/DSM"
      write_menu "f" "Bootscreen Options"
      write_menu "U" "Change Loader Password"
      write_menu "Z" "Change Loader Ports"
      write_menu "w" "Reset Loader to Defaults"
      write_menu "L" "Grep Logs from dbgutils"
      write_menu "B" "Grep DSM Config from Backup"
      write_menu "=" "\Z1== Edit with caution! ==\Zn"
      write_menu_with_color "W" "RD Compression" "${RD_COMPRESSED}"
      write_menu_with_color "X" "Sata DOM" "${SATADOM}"
      write_menu_with_color "u" "LKM Version" "${LKM}"
      write_menu "C" "Clone Loader to another Disk"
      write_menu "n" "Grub Bootloader Config"
      write_menu "y" "Choose a Keymap for Loader"
      write_menu "F" "\Z1Formate Disks\Zn"
    fi

    write_menu_with_color "=" "\Z4===== Misc =====\Zn"
    write_menu "x" "Backup/Restore/Recovery"
    [ "${ARCOFFLINE}" = "false" ] && write_menu "z" "Update Menu"
    write_menu "I" "Power/Service Menu"
    write_menu "V" "Credits"
    if [ "$TERM" != "xterm-256color" ]; then
      WEBCONFIG="Webconfig: http://${IPCON}${HTTPPORT:+:$HTTPPORT}"
    else
      WEBCONFIG=""
    fi
    dialog --clear --default-item ${NEXT} --backtitle "$(backtitle)" --title "Classic UI" --colors \
          --cancel-label "Evo" --help-button --help-label "Exit" \
          --menu "${WEBCONFIG}" 0 0 0 --file "${TMP_PATH}/menu" \
          2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
      0)
        resp=$(cat ${TMP_PATH}/resp)
        [ -z "${resp}" ] && return
        case ${resp} in
          # Main Section
          0) genHardwareID; NEXT="0" ;;
          1) arcModel; NEXT="2" ;;
          2) arcSummary; NEXT="3" ;;
          3) boot; NEXT="3" ;;
          # Info Section
          a) sysinfo; NEXT="a" ;;
          A) networkdiag; NEXT="A" ;;
          # System Section
          # Arc Section
          4) [ "${ARCOPTS}" = "true" ] && ARCOPTS='false' || ARCOPTS='true'
            ARCOPTS="${ARCOPTS}"
            NEXT="4"
            ;;
          b) addonMenu; NEXT="b" ;;
          d) modulesMenu; NEXT="d" ;;
          e) ONLYVERSION="true" && arcVersion; NEXT="e" ;;
          p) ONLYPATCH="true" && checkHardwareID && arcPatch; NEXT="p" ;;
          S) storageMenu; NEXT="S" ;;
          o) dtsMenu; NEXT="o" ;;
          g) governorMenu; NEXT="g" ;;
          P) storagepanelMenu; NEXT="P" ;;
          Q) sequentialIOMenu; NEXT="Q" ;;
          # Boot Section
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
          i) bootipwaittime; NEXT="i" ;;
          q) [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
            grub-editenv ${USER_GRUBENVFILE} create
            writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
            NEXT="q"
            ;;
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
          B) getbackup; NEXT="B" ;;
          # Loader Section
          8) [ "${LOADEROPTS}" = "true" ] && LOADEROPTS='false' || LOADEROPTS='true'
            LOADEROPTS="${LOADEROPTS}"
            NEXT="8"
            ;;
          c) ARCOFFLINE=$([ "${ARCOFFLINE}" = "true" ] && echo 'false' || echo 'true')
            writeConfigKey "arc.offline" "${ARCOFFLINE}" "${USER_CONFIG_FILE}"
            [ "${ARCOFFLINE}" = "false" ] && exec arc.sh
            NEXT="c"
            ;;
          D) staticIPMenu; NEXT="D" ;;
          f) bootScreen; NEXT="f" ;;
          Z) loaderPorts; NEXT="Z" ;;
          U) loaderPassword; NEXT="U" ;;
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
        ;;
      1)
        exec evo.sh
        ;;
      *)
        break
        ;;
    esac
  done
  clear
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
