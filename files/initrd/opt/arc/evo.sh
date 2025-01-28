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
  NEXT="1"
  while true; do
    rm -f "${TMP_PATH}/menu" "${TMP_PATH}/resp" >/dev/null 2>&1 || true
    write_menu "=" "\Z4===== Main =====\Zn"
    if [ -z "${USERID}" ] && [ "${ARCOFFLINE}" = "false" ]; then
      write_menu_with_color "0" "HardwareID" "${HARDWAREID}"
    fi

    write_menu_with_color "1" "Model" "${MODEL}"

    if [ "${CONFDONE}" = "true" ]; then
      write_menu_with_color "e" "Version" "${PRODUCTVER}"
      write_menu_with_color "=" "DT" "${DT}"
      write_menu_with_color "=" "Platform" "${PLATFORM}"

      if [ -n "${USERID}" ] && [ "${ARCOFFLINE}" = "false" ]; then
        write_menu_with_color "p" "Arc Patch" "${ARCPATCH}"
      elif [ "${ARCOFFLINE}" = "false" ]; then
        write_menu "p" "Arc Patch: \Z4Register HardwareID first\Zn"
      else
        write_menu "p" "SN/Mac Options"
      fi

      if [ "${PLATFORM}" = "epyc7002" ]; then
        CPUINFO="$(cat /proc/cpuinfo | wc -l)"
        if [ ${CPUINFO} -gt 24 ]; then
          write_menu "=" "Custom Kernel should be used for this CPU"
        fi
        write_menu_with_color "K" "Kernel" "${KERNEL}"
      fi

      write_menu "b" "Addons"

      for addon in "cpufreqscaling" "storagepanel" "sequentialio"; do
        if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "${addon}"; then
          case "${addon}" in
            "cpufreqscaling") write_menu_with_color "g" "Scaling Governor" "${GOVERNOR}" ;;
            "storagepanel") write_menu_with_color "P" "StoragePanel" "${STORAGEPANEL:-auto}" ;;
            "sequentialio") write_menu_with_color "Q" "SequentialIO" "${SEQUENTIALIO}" ;;
          esac
        fi
      done

      write_menu "d" "Modules"
      write_menu_with_color "O" "Official Driver Priority" "${ODP}"

      if [ "${DT}" = "false" ] && [ ${SATACONTROLLER} -gt 0 ]; then
        write_menu_with_color "S" "PortMap" "${REMAP}"
        write_menu_with_color "=" "Mapping" "${PORTMAP}"
      fi

      if [ "${DT}" = "true" ]; then
        write_menu_with_color "H" "Hotplug/SortDrives" "${HDDSORT}"
      else
        write_menu_with_color "h" "USB as Internal" "${USBMOUNT}"
      fi
    fi

    write_menu_with_color "c" "Offline Mode" "${ARCOFFLINE}"
    write_menu "9" "Advanced Options"
    write_menu "=" "\Z4===== Diag =====\Zn"
    write_menu "a" "Sysinfo"
    write_menu "A" "Networkdiag"
    write_menu "=" "\Z4===== Misc =====\Zn"
    write_menu "x" "Backup/Restore/Recovery"
    [ "${ARCOFFLINE}" = "false" ] && write_menu "z" "Update Menu"
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
    dialog --clear --default-item ${NEXT} --backtitle "$(backtitle)" --title "Evo UI" --colors \
          --cancel-label "Classic" --help-button --help-label "Exit" \
          --extra-button --extra-label "${EXTRA_LABEL}" \
          --menu "${WEBCONFIG}" 0 0 0 --file "${TMP_PATH}/menu" \
          2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
      0)
        resp=$(cat ${TMP_PATH}/resp)
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
          c) ARCOFFLINE=$([ "${ARCOFFLINE}" = "true" ] && echo 'false' || echo 'true')
            writeConfigKey "arc.offline" "${ARCOFFLINE}" "${USER_CONFIG_FILE}"
            [ "${ARCOFFLINE}" = "false" ] && exec arc.sh
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
