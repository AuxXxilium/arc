# Get PortMap for Loader
function getmap() {
  # Sata Disks
  SATADRIVES=0
  if [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
    # Clean old files
    [ -f "${TMP_PATH}/drivesmax" ] && rm -f "${TMP_PATH}/drivesmax"
    touch "${TMP_PATH}/drivesmax"
    [ -f "${TMP_PATH}/drivescon" ] && rm -f "${TMP_PATH}/drivescon"
    touch "${TMP_PATH}/drivescon"
    [ -f "${TMP_PATH}/ports" ] && rm -f "${TMP_PATH}/ports"
    touch "${TMP_PATH}ports"
    [ -f "${TMP_PATH}/remap" ] && rm -f "${TMP_PATH}/remap"
    touch "${TMP_PATH}/remap"
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
        ATAPORT="$(echo ${LINE} | grep -o 'ata[0-9]*')"
        PORT=$(echo ${ATAPORT} | sed 's/ata//')
        HOSTPORTS[${PORT}]=$(echo ${LINE} | grep -o 'host[0-9]*$')
      done <<<$(ls -l /sys/class/scsi_host | grep -F "${PCI}")
      while read -r PORT; do
        ls -l /sys/block | grep -F -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
        PCMD=$(cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd)
        [ ${PCMD} = 0 ] && DUMMY=1 || DUMMY=0
        [ ${ATTACH} = 1 ] && CONPORTS=$((${CONPORTS} + 1)) && echo "$((${PORT} - 1))" >>"${TMP_PATH}/ports"
        [ ${DUMMY} = 1 ] # Do nothing for now
        NUMPORTS=$((${NUMPORTS} + 1))
      done <<<$(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
      [ ${NUMPORTS} -gt 8 ] && NUMPORTS=8
      [ ${CONPORTS} -gt 8 ] && CONPORTS=8
      echo -n "${NUMPORTS}" >>"${TMP_PATH}/drivesmax"
      echo -n "${CONPORTS}" >>"${TMP_PATH}/drivescon"
      DISKIDXMAP=$DISKIDXMAP$(printf "%02x" $DISKIDXMAPIDX)
      let DISKIDXMAPIDX=$DISKIDXMAPIDX+$CONPORTS
      DISKIDXMAPMAX=$DISKIDXMAPMAX$(printf "%02x" $DISKIDXMAPIDXMAX)
      let DISKIDXMAPIDXMAX=$DISKIDXMAPIDXMAX+$NUMPORTS
      SATADRIVES=$((${SATADRIVES} + ${CONPORTS}))
    done
  fi
  # SAS Disks
  SASDRIVES=0
  if [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::107 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      SASDRIVES=$((${SASDRIVES} + ${PORTNUM}))
    done
  fi
  # SCSI Disks
  SCSIDRIVES=0
  if [ $(lspci -d ::100 | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::100 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      SCSIDRIVES=$((${SCSIDRIVES} + ${PORTNUM}))
    done
  fi
  # Raid Disks
  RAIDDRIVES=0
  if [ $(lspci -d ::104 | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::104 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      RAIDDRIVES=$((${RAIDDRIVES} + ${PORTNUM}))
    done
  fi
  # USB Disks
  USBDRIVES=0
  if [[ -d "/sys/class/scsi_host" && $(ls -l /sys/class/scsi_host | grep usb | wc -l) -gt 0 ]]; then
    for PCI in $(lspci -d ::c03 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      USBDRIVES=$((${USBDRIVES} + ${PORTNUM}))
    done
  fi
  # MMC Disks
  MMCDRIVES=0
  if [[ -d "/sys/class/mmc_host" && $(ls -l /sys/class/mmc_host | grep mmc_host | wc -l) -gt 0 ]]; then
    for PCI in $(lspci -d ::805 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORTNUM=$(ls -l /sys/block/mmc* | grep "${PCI}" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      MMCDRIVES=$((${MMCDRIVES} + ${PORTNUM}))
    done
  fi
  # NVMe Disks
  NVMEDRIVES=0
  if [ $(lspci -d ::108 | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::108 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/nvme | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[N:${PORT}:" | wc -l)
      NVMEDRIVES=$((${NVMEDRIVES} + ${PORTNUM}))
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
}

function getmapSelection() {
  # Check for Sata Boot
  LASTDRIVE=0
  while read -r LINE; do
    if [[ "${BUS}" != "usb" && ${LINE} -eq 0 && "${LOADER_DISK}" = "/dev/sda" ]]; then
      MAXDISKS="$(readModelKey "${MODEL}" "disks")"
      if [ ${MAXDISKS} -lt ${DRIVES} ]; then
        MAXDISKS=${DRIVES}
      fi
      echo -n "${LINE}>${MAXDISKS}:">>"${TMP_PATH}/remap"
    elif [ ! ${LINE} = ${LASTDRIVE} ]; then
      echo -n "${LINE}>${LASTDRIVE}:">>"${TMP_PATH}/remap"
      LASTDRIVE=$((${LASTDRIVE} + 1))
    elif [ ${LINE} = ${LASTDRIVE} ]; then
      LASTDRIVE=$((${LINE} + 1))
    fi
  done <<<$(cat "${TMP_PATH}/ports")
  # Compute PortMap Options
  SATAPORTMAPMAX="$(awk '{print $1}' "${TMP_PATH}/drivesmax")"
  SATAPORTMAP="$(awk '{print $1}' "${TMP_PATH}/drivescon")"
  SATAREMAP="$(awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//')"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  # Show recommended Option to user
  if [[ -n "${SATAREMAP}" && "${EXTERNALCONTROLLER}" = "true" && "${MACHINE}" = "NATIVE" ]]; then
    REMAP2="*"
  elif [[ -n "${SATAREMAP}" && "${EXTERNALCONTROLLER}" = "false" ]]; then
    REMAP3="*"
  else
    REMAP1="*"
  fi
  # Ask for Portmap
  dialog --backtitle "$(backtitle)" --title "Arc Disks" \
    --menu "SataPortMap or SataRemap?\n* Recommended Option" 0 0 0 \
    1 "SataPortMap: Active Ports ${REMAP1}" \
    2 "SataPortMap: Max Ports ${REMAP2}" \
    3 "SataRemap: Remove blank Ports ${REMAP3}" \
    4 "AhciRemap: Remove blank Ports (experimental) ${REMAP4}" \
    5 "I want to set my own Portmap" \
  2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(<"${TMP_PATH}/resp")"
  [ -z "${resp}" ] && return 1
  if [ ${resp} -eq 1 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --infobox "Use SataPortMap:\nActive Ports!" 4 40
    writeConfigKey "arc.remap" "acports" "${USER_CONFIG_FILE}"
  elif [ ${resp} -eq 2 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --infobox "Use SataPortMap:\nMax Ports!" 4 40
    writeConfigKey "arc.remap" "maxports" "${USER_CONFIG_FILE}"
  elif [ ${resp} -eq 3 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --infobox "Use SataRemap:\nRemove blank Drives" 4 40
    writeConfigKey "arc.remap" "remap" "${USER_CONFIG_FILE}"
  elif [ ${resp} -eq 4 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --infobox "Use AhciRemap:\nRemove blank Drives" 4 40
    writeConfigKey "arc.remap" "ahci" "${USER_CONFIG_FILE}"
  elif [ ${resp} -eq 5 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --infobox "I want to set my own PortMap!" 4 40
    writeConfigKey "arc.remap" "user" "${USER_CONFIG_FILE}"
  fi
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
  elif [ "${REMAP}" = "ahci" ]; then
    writeConfigKey "cmdline.ahci_remap" "${SATAREMAP}" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --msgbox "Computed Values:\nAhciRemap: ${SATAREMAP}" 0 0
  elif [ "${REMAP}" = "user" ]; then
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --msgbox "Usersetting: Set your own Values in Userconfig." 0 0
  fi
}

# Check for Controller // 104=RAID // 106=SATA // 107=SAS // 100=SCSI // c03=USB
if [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
  SATACONTROLLER=$(lspci -d ::106 | wc -l)
  writeConfigKey "device.satacontroller" "${SATACONTROLLER}" "${USER_CONFIG_FILE}"
fi
if [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
  SASCONTROLLER=$(lspci -d ::107 | wc -l)
  writeConfigKey "device.sascontroller" "${SASCONTROLLER}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.externalcontroller" "true" "${USER_CONFIG_FILE}"
fi
if [ $(lspci -d ::100 | wc -l) -gt 0 ]; then
  SCSICONTROLLER=$(lspci -d ::100 | wc -l)
  writeConfigKey "device.scsicontroller" "${SCSICONTROLLER}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.externalcontroller" "true" "${USER_CONFIG_FILE}"
fi
if [ $(lspci -d ::104 | wc -l) -gt 0 ]; then
  RAIDCONTROLLER=$(lspci -d ::104 | wc -l)
  writeConfigKey "device.raidcontroller" "${RAIDCONTROLLER}" "${USER_CONFIG_FILE}"
  writeConfigKey "device.externalcontroller" "true" "${USER_CONFIG_FILE}"
fi
