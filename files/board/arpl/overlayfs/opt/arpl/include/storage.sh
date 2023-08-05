# Get PortMap for Loader
function getmap() {
  # Clean old files
  rm -f "${TMP_PATH}/drivesmax"
  touch "${TMP_PATH}/drivesmax"
  rm -f "${TMP_PATH}/drivescon"
  touch "${TMP_PATH}/drivescon"
  rm -f "${TMP_PATH}/ports"
  touch "${TMP_PATH}ports"
  rm -f "${TMP_PATH}/remap"
  touch "${TMP_PATH}remap"
  # Do the work
  let DISKIDXMAPIDX=0
  DISKIDXMAP=""
  let DISKIDXMAPIDXMAX=0
  DISKIDXMAPMAX=""
  for PCI in $(lspci -nnk | grep -ie "\[0106\]" | awk '{print $1}'); do
    NUMPORTS=0
    CONPORTS=0
    unset HOSTPORTS
    declare -A HOSTPORTS
    while read -r LINE; do
      ATAPORT="$(echo ${LINE} | grep -o 'ata[0-9]*')"
      PORT=$(echo ${ATAPORT} | sed 's/ata//')
      HOSTPORTS[${PORT}]=$(echo ${LINE} | grep -o 'host[0-9]*$')
    done < <(ls -l /sys/class/scsi_host | grep -F "${PCI}")
    while read -r PORT; do
      ls -l /sys/block | grep -F -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
      PCMD=$(cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd)
      [ "${PCMD}" = "0" ] && DUMMY=1 || DUMMY=0
      [ "${ATTACH}" = "1" ] && CONPORTS=$((${CONPORTS}+1)) && echo "$((${PORT}-1))" >>"${TMP_PATH}/ports"
      [ "${DUMMY}" = "1" ]
      NUMPORTS=$((${NUMPORTS}+1))
    done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
    [ "${NUMPORTS}" -gt "8" ] && NUMPORTS=8
    [ "${CONPORTS}" -gt "8" ] && CONPORTS=8
    echo -n "${NUMPORTS}" >>"${TMP_PATH}/drivesmax"
    echo -n "${CONPORTS}" >>"${TMP_PATH}/drivescon"
    DISKIDXMAP=$DISKIDXMAP$(printf "%02x" $DISKIDXMAPIDX)
    let DISKIDXMAPIDX=$DISKIDXMAPIDX+$CONPORTS
    DISKIDXMAPMAX=$DISKIDXMAPMAX$(printf "%02x" $DISKIDXMAPIDXMAX)
    let DISKIDXMAPIDXMAX=$DISKIDXMAPIDXMAX+$NUMPORTS
  done
  SATAPORTMAPMAX="$(awk '{print$1}' ${TMP_PATH}/drivesmax)"
  SATAPORTMAP="$(awk '{print$1}' ${TMP_PATH}/drivescon)"
  LASTDRIVE=0
  # Check for VMware
  while read -r LINE; do
    if [ "${MACHINE}" = "VMware" ] && [ "${LINE}" = "0" ]; then
      MAXDISKS="$(readModelKey "${MODEL}" "disks")"
      echo -n "${LINE}>${MAXDISKS}:" >>"${TMP_PATH}/remap"
    elif [ "${LINE}" != "${LASTDRIVE}" ]; then
      echo -n "${LINE}>${LASTDRIVE}:" >>"${TMP_PATH}/remap"
      LASTDRIVE=$((${LASTDRIVE}+1))
    elif [ "${LINE}" = "${LASTDRIVE}" ]; then
        LASTDRIVE=$((${line}+1))
    fi
  done < <(cat "${TMP_PATH}/ports")
  SATAREMAP="$(awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//')"
  # Show recommended Option to user
  if [ "${MACHINE}" = "NATIVE" ]; then
    if [ -n "${SATAREMAP}" ] && [ "${SASCONTROLLER}" -eq 0 ]; then
      REMAP3="*"
    elif [ -n "${SATAREMAP}" ] && [ "${SASCONTROLLER}" -gt 0 ]; then
      REMAP2="*"
    elif [ -z "${SATAREMAP}" ]; then
      REMAP1="*"
    fi
  elif [ "${MACHINE}" != "NATIVE" ]; then
    if [ -n "${SATAREMAP}" ] && [ "${SASCONTROLLER}" -eq 0 ]; then
      REMAP3="*"
    elif [ -n "${SATAREMAP}" ] && [ "${SASCONTROLLER}" -gt 0 ]; then
      REMAP1="*"
    elif [ -z "${SATAREMAP}" ]; then
      REMAP1="*"
    fi
  fi
  if [ "${SASCONTROLLER}" -gt 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --infobox "SAS Controller dedected!\nUse SataPortMap: Active Ports!" 4 40
    writeConfigKey "arc.remap" "1" "${USER_CONFIG_FILE}"
  else
    # Ask for Portmap
    while true; do
      dialog --backtitle "$(backtitle)" --title "Arc Disks" \
        --menu "SataPortMap or SataRemap?\n* recommended Option" 0 0 0 \
        1 "SataPortMap: Active Ports ${REMAP1}" \
        2 "SataPortMap: Max Ports ${REMAP2}" \
        3 "SataRemap: Remove blank Ports ${REMAP3}" \
        4 "Set my own Portmap" \
      2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      resp=$(<"${TMP_PATH}/resp")
      [ -z "${resp}" ] && return
      if [ "${resp}" = "1" ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Disks" \
          --infobox "Use SataPortMap:\nActive Ports!" 4 40
        writeConfigKey "arc.remap" "1" "${USER_CONFIG_FILE}"
        break
      elif [ "${resp}" = "2" ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Disks" \
          --infobox "Use SataPortMap:\nMax Ports!" 4 40
        writeConfigKey "arc.remap" "2" "${USER_CONFIG_FILE}"
        break
      elif [ "${resp}" = "3" ]; then
        if [ "${SASCONTROLLER}" -gt 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Arc Disks" \
            --infobox "SAS Controller detected.\nSwitch to SataPortMap: Max Ports!" 4 40
          writeConfigKey "arc.remap" "2" "${USER_CONFIG_FILE}"
        else
          dialog --backtitle "$(backtitle)" --title "Arc Disks" \
            --infobox "Use SataRemap:\nRemove blank Drives" 4 40
          writeConfigKey "arc.remap" "3" "${USER_CONFIG_FILE}"
        fi
        break
      elif [ "${resp}" = "4" ]; then
        dialog --backtitle "$(backtitle)" --title "Arc Disks" \
          --infobox "Set my own PortMap!" 4 40
        writeConfigKey "arc.remap" "0" "${USER_CONFIG_FILE}"
        break
      fi
    done
  fi
  sleep 1
  # Check Remap for correct config
  REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
  # Write Map to config and show Map to User
  if [ "${REMAP}" = "1" ]; then
    writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAP}" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --msgbox "SataPortMap: ${SATAPORTMAP} DiskIdxMap: ${DISKIDXMAP}" 0 0
  elif [ "${REMAP}" = "2" ]; then
    writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAPMAX}" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAPMAX}" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --msgbox "SataPortMap: ${SATAPORTMAPMAX} DiskIdxMap: ${DISKIDXMAPMAX}" 0 0
  elif [ "${REMAP}" = "3" ]; then
    writeConfigKey "cmdline.sata_remap" "${SATAREMAP}" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --msgbox "SataRemap: ${SATAREMAP}" 0 0
  elif [ "${REMAP}" = "0" ]; then
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    dialog --backtitle "$(backtitle)" --title "Arc Disks" \
      --msgbox "We don't need this." 0 0
  fi
}

# Check for Controller
SATACONTROLLER=$(lspci -nnk | grep -ie "\[0106\]" | wc -l)
writeConfigKey "arc.satacontroller" "${SATACONTROLLER}" "${USER_CONFIG_FILE}"
SASCONTROLLER=$(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | wc -l)
writeConfigKey "arc.sascontroller" "${SASCONTROLLER}" "${USER_CONFIG_FILE}"