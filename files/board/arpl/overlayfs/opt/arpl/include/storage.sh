# Get PortMap for Loader
function getmap() {
  # Ask for Portmap
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "SataPortMap or SataRemap?" 0 0 0 \
      1 "Use SataPortMap (controller active Ports)" \
      2 "Use SataPortMap (controller max Ports)" \
      3 "Use SataRemap (remove blank drives)" \
      4 "Set my own Portmap" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "1" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --infobox "Use SataPortMap (active Ports)!" 0 0
      writeConfigKey "arc.remap" "1" "${USER_CONFIG_FILE}"
      break
    elif [ "${resp}" = "2" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --infobox "Use SataPortMap (max Ports)!" 0 0
      writeConfigKey "arc.remap" "2" "${USER_CONFIG_FILE}"
      break
    elif [ "${resp}" = "3" ]; then
      if [ "${SASCONTROLLER}" -gt 0 ]; then
        dialog --backtitle "`backtitle`" --title "Arc Disks" \
          --msgbox "SAS Controller detected. Switch to SataPortMap (active Ports)!" 0 0
        writeConfigKey "arc.remap" "1" "${USER_CONFIG_FILE}"
      else
        dialog --backtitle "`backtitle`" --title "Arc Disks" \
          --infobox "Use SataRemap! (remove blank Drives)" 0 0
        writeConfigKey "arc.remap" "3" "${USER_CONFIG_FILE}"
      fi
      break
    elif [ "${resp}" = "4" ]; then
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --infobox "Set my own PortMap!" 0 0
      writeConfigKey "arc.remap" "0" "${USER_CONFIG_FILE}"
      break
    fi
  done
  sleep 1
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
  for PCI in `lspci -nnk | grep -ie "\[0106\]" | awk '{print $1}'`; do
    NUMPORTS=0
    CONPORTS=0
    NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
    DRIVES=`ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l`
    unset HOSTPORTS
    declare -A HOSTPORTS
    while read LINE; do
      ATAPORT="`echo ${LINE} | grep -o 'ata[0-9]*'`"
      PORT=`echo ${ATAPORT} | sed 's/ata//'`
      HOSTPORTS[${PORT}]=`echo ${LINE} | grep -o 'host[0-9]*$'`
    done < <(ls -l /sys/class/scsi_host | fgrep "${PCI}")
    while read PORT; do
      ls -l /sys/block | fgrep -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
      PCMD=`cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd`
      [ "${PCMD}" = "0" ] && DUMMY=1 || DUMMY=0
      [ ${ATTACH} -eq 1 ] && CONPORTS=$((${CONPORTS}+1)) && echo "`expr ${PORT} - 1`" >> "${TMP_PATH}/ports"
      [ ${DUMMY} -eq 1 ]
      NUMPORTS=$((${NUMPORTS}+1))
    done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
    [ ${NUMPORTS} -gt 8 ] && NUMPORTS=8
    [ ${CONPORTS} -gt 8 ] && CONPORTS=8
    echo -n "${NUMPORTS}" >> ${TMP_PATH}/drivesmax
    echo -n "${CONPORTS}" >> ${TMP_PATH}/drivescon
    DISKIDXMAP=$DISKIDXMAP$(printf "%02x" $DISKIDXMAPIDX)
    let DISKIDXMAPIDX=$DISKIDXMAPIDX+$CONPORTS
    DISKIDXMAPMAX=$DISKIDXMAPMAX$(printf "%02x" $DISKIDXMAPIDXMAX)
    let DISKIDXMAPIDXMAX=$DISKIDXMAPIDXMAX+$NUMPORTS
  done
  SATAPORTMAPMAX=$(awk '{print$1}' ${TMP_PATH}/drivesmax)
  SATAPORTMAP=$(awk '{print$1}' ${TMP_PATH}/drivescon)
  LASTDRIVE=0
  # Check for VMware
  if [ "$HYPERVISOR" = "VMware" ]; then
    MAXDISKS="`readModelKey "${MODEL}" "disks"`"
    MAXDISKSN=`expr $MAXDISKS + 1`
    echo -n "0>$MAXDISKSN:" >> "${TMP_PATH}/remap"
  fi
  while read line; do
    if [ $line = 1 ] && [ "$HYPERVISOR" = "VMware" ]; then
      LASTDRIVE=$((${LASTDRIVE}-1))
    fi
    if [ $line != $LASTDRIVE ]; then
      echo -n "$line>$LASTDRIVE:" >> "${TMP_PATH}/remap"
      LASTDRIVE=$((${LASTDRIVE}+1))
    elif [ $line == $LASTDRIVE ]; then
        LASTDRIVE=$((${line}+1))
    fi
  done < <(cat "${TMP_PATH}/ports")
  SATAREMAP=$(awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//')
  # Check Remap for correct config
  REMAP="`readConfigKey "arc.remap" "${USER_CONFIG_FILE}"`"
  # Write Map to config and show Map to User
  if [ "${REMAP}" == "1" ]; then
    writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAP}" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "SataPortMap: ${SATAPORTMAP} DiskIdxMap: ${DISKIDXMAP}" 0 0
  elif [ "${REMAP}" == "2" ]; then
    writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAPMAX}" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAPMAX}" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "SataPortMap: ${SATAPORTMAPMAX} DiskIdxMap: ${DISKIDXMAPMAX}" 0 0
  elif [ "${REMAP}" == "3" ]; then
    writeConfigKey "cmdline.sata_remap" "${SATAREMAP}" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "SataRemap: ${SATAREMAP}" 0 0
  elif [ "${REMAP}" == "0" ]; then
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --msgbox "We don't need this." 0 0
  fi
}

# Check for Controller
SATACONTROLLER=$(lspci -nnk | grep -ie "\[0106\]" | wc -l)
SASCONTROLLER=$(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | wc -l)