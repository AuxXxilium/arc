# Get PortMap for Loader
function getmap() {
  # Config for Sata Controller with PortMap to get all drives
  if [ "${REMAP}" == "0" ]; then
    SATAPORTMAP=""
    let DISKIDXMAPIDX=0
    DISKIDXMAP=""
    # Get Number of Drives per Controller
    pcis=$(lspci -nnk | grep -ie "\[0106\]" | awk '{print $1}')
    [ ! -z "$pcis" ]
    # loop through controllers
    for pci in $pcis; do
      # get attached block devices (exclude CD-ROMs)
      DRIVES=$(ls -la /sys/block | fgrep "${pci}" | grep -v "sr.$" | wc -l)
      if [ "${DRIVES}" -gt 8 ]; then
        DRIVES=8
        WARNON=1
      fi
      SATAPORTMAP=$SATAPORTMAP$DRIVES
      DISKIDXMAP=$DISKIDXMAP$(printf "%02x" $DISKIDXMAPIDX)
      let DISKIDXMAPIDX=$DISKIDXMAPIDX+$DRIVES
    done
  fi
  # Config for only Sata Controller with Remap to remove blank drives
  if [ "${REMAP}" == "1" ]; then
    # Clean old files
    rm -f "${TMP_PATH}/ports"
    touch "${TMP_PATH}ports"
    rm -f "${TMP_PATH}/remap"
    touch "${TMP_PATH}remap"
    # Check for VMware
    if [ "$HYPERVISOR" = "VMware" ]; then
      MAXDISKS="`readModelKey "${MODEL}" "disks"`"
      MAXDISKSN=`expr $MAXDISKS + 1`
      echo -n "0>$MAXDISKSN:" >> "${TMP_PATH}/remap"
    fi
    NUMPORTS=0
    newdrive=0
    lastdrive=0
    for PCI in `lspci -nnk | grep -ie "\[0106\]" | awk '{print $1}'`; do
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
        [ ${ATTACH} -eq 1 ] && echo "`expr ${PORT} - 1`" >> "${TMP_PATH}/ports"
        [ ${DUMMY} -eq 1 ]
        NUMPORTS=$((${NUMPORTS}+1))
      done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
    done
    while read line; do
      if [ $line != $newdrive ]; then
        echo -n "$line>$lastdrive:" >> "${TMP_PATH}/remap"
        lastdrive=`expr $lastdrive + 1`
        if [ $line == $newdrive ]; then
          lastdrive=`expr $line + 1`
        fi
      fi
      newdrive=`expr $lastdrive + 1`
    done < <(cat "${TMP_PATH}/ports")
    SATAREMAP=$(awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//')
  fi
  # Config for SCSI/SAS Controller
  SASIDXMAP=0
  # Write map for portmap or remap to config
  if [ "${REMAP}" == "0" ]; then
    if [ "${SATAPORTMAP}" -gt 10 ]; then
      writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
      writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAP}" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    elif [ "${SATAPORTMAP}" -lt 11 ] && [ "$HYPERVISOR" = "VMware" ]; then
      writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
      writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAP}" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    elif [ "${SATAPORTMAP}" -lt 11 ]; then
      deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
      deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    fi
    if [ "${SASCONTROLLER}" -eq 0 ]; then
      deleteConfigKey "cmdline.SasIdxMap" "${USER_CONFIG_FILE}"
    elif [ "${SASCONTROLLER}" -gt 0 ]; then
      writeConfigKey "cmdline.SasIdxMap" "${SASIDXMAP}" "${USER_CONFIG_FILE}"
    fi
  elif [ "${REMAP}" == "1" ]; then
    if [ -n "${SATAREMAP}" ]; then
      writeConfigKey "cmdline.sata_remap" "${SATAREMAP}" "${USER_CONFIG_FILE}"
    else
      deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    fi
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.SasIdxMap" "${USER_CONFIG_FILE}"
  elif [ "${REMAP}" == "3" ]; then
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.SasIdxMap" "${USER_CONFIG_FILE}"
  fi
}

# Check for Controller
SATACONTROLLER=$(lspci -nnk | grep -ie "\[0106\]" | wc -l)
SCSICONTROLLER=$(lspci -nnk | grep -ie "\[0104\]" | wc -l)
SASCONTROLLER=$(lspci -nnk | grep -ie "\[0107\]" | wc -l)