# Get PortMap for Loader
function detect_drives() {
  local pci_id=$1
  local drive_var=$2
  local class_path=$3
  local grep_pattern=$4
  local sed_pattern=$5

  eval "${drive_var}=0"
  if [ $(lspci -d ::${pci_id} 2>/dev/null | wc -l) -gt 0 ]; then
    for PCI in $(lspci -d ::${pci_id} 2>/dev/null | awk '{print $1}'); do
      PORT=$(ls -l ${class_path} | grep "${PCI}" | awk -F'/' '{print $NF}' | sed "${sed_pattern}" | sort -n 2>/dev/null)
      PORTNUM=$(lsscsi -b | grep -v - | grep "${grep_pattern}${PORT}:" | wc -l)
      eval "${drive_var}=\$((\${${drive_var}} + \${PORTNUM}))"
    done
  fi
}

function show_dialog() {
  dialog --backtitle "$(backtitle)" --title "Sata Portmap" \
    --menu "Choose a Portmap for Sata!?\n* Recommended Option" 8 60 0 \
    1 "DiskIdxMap: Active Ports ${REMAP1}" \
    2 "DiskIdxMap: Max Ports ${REMAP2}" \
    3 "SataRemap: Remove empty Ports ${REMAP3}" \
    4 "AhciRemap: Remove empty Ports (new) ${REMAP4}" \
    5 "Set my own Portmap in Config" \
  2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp=$(cat "${TMP_PATH}/resp")
  [ -z "${resp}" ] && return 1
}

function set_remap() {
  case ${resp} in
    1) writeConfigKey "arc.remap" "acports" "${USER_CONFIG_FILE}" ;;
    2) writeConfigKey "arc.remap" "maxports" "${USER_CONFIG_FILE}" ;;
    3) writeConfigKey "arc.remap" "remap" "${USER_CONFIG_FILE}" ;;
    4) writeConfigKey "arc.remap" "ahci" "${USER_CONFIG_FILE}" ;;
    5) writeConfigKey "arc.remap" "user" "${USER_CONFIG_FILE}" ;;
  esac
}

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
  detect_drives "107" "SASDRIVES" "/sys/class/scsi_host" "\[${PORT}:" "s/host//"

  # SCSI Disks
  detect_drives "100" "SCSIDRIVES" "/sys/class/scsi_host" "\[${PORT}:" "s/host//"

  # Raid Disks
  detect_drives "104" "RAIDDRIVES" "/sys/class/scsi_host" "\[${PORT}:" "s/host//"

  # NVMe Disks
  detect_drives "108" "NVMEDRIVES" "/sys/class/nvme" "\[N:${PORT}:" "s/nvme//"

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
      if [ "${BUS}" = "sata" ] && [ "${MACHINE}" != "Native" ] && [ ${D} -eq 0 ]; then
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

function getmapSelection() {
  # Compute PortMap Options
  SATAPORTMAPMAX=$(awk '{print $1}' "${TMP_PATH}/drivesmax")
  SATAPORTMAP=$(awk '{print $1}' "${TMP_PATH}/drivescon")
  SATAREMAP=$(awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//')
  EXTERNALCONTROLLER=$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")
  ARCMODE=$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")
  
  if [ "${ARCMODE}" = "config" ]; then
    # Show recommended Option to user
    if [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "true" ] && [ "${MACHINE}" = "Native" ]; then
      REMAP2="*"
    elif [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "false" ]; then
      REMAP3="*"
    else
      REMAP1="*"
    fi
  
    if [ "${STEP}" = "storagemap" ]; then
      show_dialog
      set_remap
    else
      show_dialog
      set_remap
    fi
  else
    # Show recommended Option to user
    if [ -n "${SATAREMAP}" ] && [ "${EXTERNALCONTROLLER}" = "true" ] && [ "${MACHINE}" = "Native" ]; then
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