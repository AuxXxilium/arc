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
  SATAPORTMAPMAX=`awk '{print$1}' ${TMP_PATH}/drivesmax`
  SATAPORTMAP=`awk '{print$1}' ${TMP_PATH}/drivescon`
  LASTDRIVE=0
  # Check for VMware
  while read line; do
    if [ "$HYPERVISOR" = "VMware" ] && [ $line = 0 ]; then
      MAXDISKS="`readModelKey "${MODEL}" "disks"`"
      echo -n "$line>$MAXDISKS:" >> "${TMP_PATH}/remap"
    elif [ $line != $LASTDRIVE ]; then
      echo -n "$line>$LASTDRIVE:" >> "${TMP_PATH}/remap"
      LASTDRIVE=`expr $LASTDRIVE + 1`
    elif [ $line = $LASTDRIVE ]; then
        LASTDRIVE=`expr $line + 1`
    fi
  done < <(cat "${TMP_PATH}/ports")
  SATAREMAP=`awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//'`
  # Show recommended Option to user
  if [ "$MACHINE" != "VIRTUAL" ]; then
    if [ -n "${SATAREMAP}" ] && [ "${SASCONTROLLER}" -eq 0 ]; then
      REMAP3="*"
    elif [ -n "${SATAREMAP}" ] && [ "${SASCONTROLLER}" -gt 0 ]; then
      REMAP2="*"
    elif [ -z "${SATAREMAP}" ]; then
      REMAP1="*"
    fi
  elif [ "$MACHINE" = "VIRTUAL" ]; then
    if [ -n "${SATAREMAP}" ] && [ "${SASCONTROLLER}" -eq 0 ]; then
      REMAP3="*"
    elif [ -n "${SATAREMAP}" ] && [ "${SASCONTROLLER}" -gt 0 ]; then
      REMAP1="*"
    elif [ -z "${SATAREMAP}" ]; then
      REMAP1="*"
    fi
  fi
  if [ "$SASCONTROLLER" -gt 0 ]; then
    dialog --backtitle "`backtitle`" --title "Arc Disks" \
      --infobox "SAS Controller dedected!\nUse SataPortMap (active Ports)!" 0 0
    writeConfigKey "arc.remap" "1" "${USER_CONFIG_FILE}"
  else
    # Ask for Portmap
    while true; do
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --menu "SataPortMap or SataRemap?\n* recommended Option" 0 0 0 \
        1 "Use SataPortMap (active Ports) ${REMAP1}" \
        2 "Use SataPortMap (max Ports) ${REMAP2}" \
        3 "Use SataRemap (remove blank Ports) ${REMAP3}" \
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
            --msgbox "SAS Controller detected. Switch to SataPortMap (max Ports)!" 0 0
          writeConfigKey "arc.remap" "2" "${USER_CONFIG_FILE}"
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
  fi
  sleep 1
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
  # Ask for USB Storage
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  USBSTORAGE=`lsblk -do name,tran | awk '$2=="usb"{print $1}' | wc -w`
  if [ "${PLATFORM}" = "broadwellnk" ] && [ "${USBSTORAGE}" -gt 0 ]; then
    while true; do
      dialog --backtitle "`backtitle`" --title "Arc Disks" \
        --menu "USB Disk found.\nMount USB Disk as Internal?" 0 0 0 \
        1 "Yes - Mount as Internal" \
        2 "No - Use as USB Device" \
      2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(<${TMP_PATH}/resp)
      [ -z "${resp}" ] && return
      if [ "${resp}" = "1" ]; then
        writeConfigKey "synoinfo.maxdisks" "24" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.usbportcfg" "0xff0000" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.internalportcfg" "0xffffff" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.usbmount" "true" "${USER_CONFIG_FILE}"
        dialog --backtitle "`backtitle`" --title "Mount USB as Internal" \
        --aspect 18 --msgbox "Mount USB as Internal - successfull!" 0 0
        break
      elif [ "${resp}" = "2" ]; then
        deleteConfigKey "synoinfo.maxdisks" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.usbportcfg" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.internalportcfg" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
        dialog --backtitle "`backtitle`" --title "Mount USB as Internal" \
        --aspect 18 --msgbox "Mount USB as Internal - skipped!" 0 0
        break
      fi
    done
  fi
}

# Check for Controller
SATACONTROLLER=`lspci -nnk | grep -ie "\[0106\]" | wc -l`
writeConfigKey "arc.satacontroller" "${SATACONTROLLER}" "${USER_CONFIG_FILE}"
SASCONTROLLER=`lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | wc -l`
writeConfigKey "arc.sascontroller" "${SASCONTROLLER}" "${USER_CONFIG_FILE}"