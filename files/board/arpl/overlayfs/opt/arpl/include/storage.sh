# Get PortMap for Loader
function getmap() {
  # Sata Disks
  if [ ${SATACONTROLLER} -gt 0 ]; then
    # Clean old files
    [ -f "${TMP_PATH}/drivesmax" ] && rm -f "${TMP_PATH}/drivesmax"
    touch "${TMP_PATH}/drivesmax"
    [ -f "${TMP_PATH}/drivescon" ] && rm -f "${TMP_PATH}/drivescon"
    touch "${TMP_PATH}/drivescon"
    [ -f "${TMP_PATH}/ports" ] && rm -f "${TMP_PATH}/ports"
    touch "${TMP_PATH}ports"
    [ -f "${TMP_PATH}/remap" ] && rm -f "${TMP_PATH}/remap"
    touch "${TMP_PATH}remap"
    # Get Information for Sata Controller
    let DISKIDXMAPIDX=0
    DISKIDXMAP=""
    let DISKIDXMAPIDXMAX=0
    DISKIDXMAPMAX=""
    NUMPORTS=0
    if [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
      for PCI in $(lspci -d ::106 | awk '{print $1}'); do
        CONPORTS=0
        MAXPORTS=0
        PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
        for P in ${PORTS}; do
          if lsscsi -b | grep -v - | grep -q "\[${P}:"; then
            if [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" != "0" ]; then
              echo "${P}" >>"${TMP_PATH}/ports"
              CONPORTS=$((${CONPORTS} + 1))
            fi
          fi
          MAXPORTS=$((${MAXPORTS} + 1))
        done
        [ ${MAXPORTS} -gt 8 ] && MAXPORTS=8
        [ ${CONPORTS} -gt 8 ] && CONPORTS=8
        echo -n "${MAXPORTS}" >>"${TMP_PATH}/drivesmax"
        echo -n "${CONPORTS}" >>"${TMP_PATH}/drivescon"
        DISKIDXMAP=$DISKIDXMAP$(printf "%02x" $DISKIDXMAPIDX)
        let DISKIDXMAPIDX=$DISKIDXMAPIDX+$CONPORTS
        DISKIDXMAPMAX=$DISKIDXMAPMAX$(printf "%02x" $DISKIDXMAPIDXMAX)
        let DISKIDXMAPIDXMAX=$DISKIDXMAPIDXMAX+$MAXPORTS
        NUMPORTS=$((${NUMPORTS} + ${CONPORTS}))
        SATADRIVES=${CONPORTS}
      done
      SATAPORTMAPMAX="$(awk '{print$1}' ${TMP_PATH}/drivesmax)"
      SATAPORTMAP="$(awk '{print$1}' ${TMP_PATH}/drivescon)"
      LASTDRIVE=0
      # Check for VMware
      while read -r LINE; do
        if [ "${MACHINE}" = "VMware" ] && [ ${LINE} -eq 0 ]; then
          MAXDISKS="$(readModelKey "${MODEL}" "disks")"
          if [ ${MAXDISKS} -lt ${NUMPORTS} ]; then
            MAXDISKS=${NUMPORTS}
          fi
          echo -n "${LINE}>${MAXDISKS}:" >>"${TMP_PATH}/remap"
        elif [ ${LINE} != ${LASTDRIVE} ]; then
          echo -n "${LINE}>${LASTDRIVE}:" >>"${TMP_PATH}/remap"
          LASTDRIVE=$((${LASTDRIVE} + 1))
        elif [ ${LINE} = ${LASTDRIVE} ]; then
          LASTDRIVE=$((${LINE} + 1))
        fi
      done < <(cat "${TMP_PATH}/ports")
    fi
  fi
  # Check MaxDisks
  # SAS Disks
  if [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
    NUMPORTS=0
    for PCI in $(lspci -d ::107 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
    SASDRIVES=${NUMPORTS}
  fi
  # USB Disks
  if [ $(ls -l /sys/class/scsi_host | grep usb | wc -l) -gt 0 ]; then
    NUMPORTS="0"
    for PCI in $(lspci -d ::c03 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
    USBDRIVES=${NUMPORTS}
  fi
  # NVMe Disks
  if [ $(lspci -d ::108 | wc -l) -gt 0 ]; then
    NUMPORTS=0
    for PCI in $(lspci -d ::108 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/nvme | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[N:${PORT}:" | wc -l)
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
    NVMEDRIVES=${NUMPORTS}
  fi
  # Disk Count
  NUMPORTS=$((${SATADRIVES} + ${SASDRIVES} + ${USBDRIVES} + ${NVMEDRIVES}))
  if [ ${NUMPORTS} -gt 26 ]; then
    WARNON=5
  fi
  TEXT="\Z4Disks found!\Zn\n"
  TEXT+="\n"
  [ -n "${SATADRIVES}" ] && TEXT+="SATA Disks: \Zb${SATADRIVES}\Zn"
  [ -n "${SASDRIVES}" ] && TEXT+="\nSAS Disks: \Zb${SASDRIVES}\Zn"
  [ -n "${USBDRIVES}" ] && TEXT+="\nUSB Disks: \Zb${USBDRIVES}\Zn"
  [ -n "${NVMEDRIVES}" ] && TEXT+="\nNVME Disks: \Zb${NVMEDRIVES}\Zn"
  TEXT+="\n"
  TEXT+="\nTotal Disks: \Zb${NUMPORTS}\Zn"
  dialog --backtitle "$(backtitle)" --colors --title "Arc Disks" \
    --msgbox "${TEXT}" 0 0
  if [ ${SATACONTROLLER} -gt 0 ] && [ "${DT}" != "true" ]; then
    SATAREMAP="$(awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//')"
    # Show recommended Option to user
    if [ -n "${SATAREMAP}" ] && [ ${SASCONTROLLER} -eq 0 ]; then
      REMAP3="*"
    elif [ -n "${SATAREMAP}" ] && [ ${SASCONTROLLER} -gt 0 ] && [ "${MACHINE}" = "NATIVE" ]; then
      REMAP2="*"
    else
      REMAP1="*"
    fi
    # Ask for Portmap
    while true; do
      dialog --backtitle "$(backtitle)" --title "Arc Disks" \
        --menu "SataPortMap or SataRemap?\n* recommended Option" 0 0 0 \
        1 "SataPortMap: Active Ports ${REMAP1}" \
        2 "SataPortMap: Max Ports ${REMAP2}" \
        3 "SataRemap: Remove blank Ports ${REMAP3}" \
        4 "I want to set my own Portmap" \
      2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return 1
      resp=$(<"${TMP_PATH}/resp")
      [ -z "${resp}" ] && return 1
      if [ ${resp} -eq 1 ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Disks" \
          --infobox "Use SataPortMap:\nActive Ports!" 4 40
        writeConfigKey "arc.remap" "acports" "${USER_CONFIG_FILE}"
        break
      elif [ ${resp} -eq 2 ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Disks" \
          --infobox "Use SataPortMap:\nMax Ports!" 4 40
        writeConfigKey "arc.remap" "maxports" "${USER_CONFIG_FILE}"
        break
      elif [ ${resp} -eq 3 ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Disks" \
          --infobox "Use SataRemap:\nRemove blank Drives" 4 40
        writeConfigKey "arc.remap" "remap" "${USER_CONFIG_FILE}"
        break
      elif [ ${resp} -eq 4 ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Disks" \
          --infobox "I want to set my own PortMap!" 4 40
        writeConfigKey "arc.remap" "user" "${USER_CONFIG_FILE}"
        break
      fi
    done
    sleep 1
    # Check Remap for correct config
    REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
    # Write Map to config and show Map to User
    if [ "${REMAP}" = "acports" ]; then
      writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
      writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAP}" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
      dialog --backtitle "$(backtitle)" --title "Arc Disks" \
        --msgbox "Computed Values:\nSataPortMap: ${SATAPORTMAP}\nDiskIdxMap: ${DISKIDXMAP}" 0 0
    elif [ "${REMAP}" = "maxports" ]; then
      writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAPMAX}" "${USER_CONFIG_FILE}"
      writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAPMAX}" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
      dialog --backtitle "$(backtitle)" --title "Arc Disks" \
        --msgbox "Computed Values:\nSataPortMap: ${SATAPORTMAPMAX}\nDiskIdxMap: ${DISKIDXMAPMAX}" 0 0
    elif [ "${REMAP}" = "remap" ]; then
      writeConfigKey "cmdline.sata_remap" "${SATAREMAP}" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
      dialog --backtitle "$(backtitle)" --title "Arc Disks" \
        --msgbox "Computed Values:\nSataRemap: ${SATAREMAP}" 0 0
    elif [ "${REMAP}" = "user" ]; then
      deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
      dialog --backtitle "$(backtitle)" --title "Arc Disks" \
        --msgbox "Usersetting: We don't need this." 0 0
    fi
  fi
}

# Check for Controller
SATACONTROLLER=$(lspci -d ::106 | wc -l)
writeConfigKey "device.satacontroller" "${SATACONTROLLER}" "${USER_CONFIG_FILE}"
SASCONTROLLER=$(lspci -d ::107 | wc -l)
writeConfigKey "device.sascontroller" "${SASCONTROLLER}" "${USER_CONFIG_FILE}"