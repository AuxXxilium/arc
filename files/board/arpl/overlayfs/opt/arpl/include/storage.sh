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
  # Check for VMware
  if [ "$HYPERVISOR" = "VMware" ]; then
    MAXDISKS="`readModelKey "${MODEL}" "disks"`"
    MAXDISKSN=`expr $MAXDISKS + 1`
    echo -n "0>$MAXDISKSN:" >> "${TMP_PATH}/remap"
  fi
  lastdrive=0
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
  done
  while read line; do
    if [ $line = 1 ] && [ "$HYPERVISOR" = "VMware" ]; then
      lastdrive=`expr $lastdrive - 1`
    fi
    if [ $line != $lastdrive ]; then
      echo -n "$line>$lastdrive:" >> "${TMP_PATH}/remap"
      lastdrive=`expr $lastdrive + 1`
    elif [ $line == $lastdrive ]; then
        lastdrive=`expr $line + 1`
    fi
  done < <(cat "${TMP_PATH}/ports")
  SATAPORTMAPMAX=$(awk '{print$1}' ${TMP_PATH}/drivesmax)
  SATAPORTMAP=$(awk '{print$1}' ${TMP_PATH}/drivescon)
  SATAREMAP=$(awk '{print $1}' "${TMP_PATH}/remap" | sed 's/.$//')
}

# Check for Controller
SATACONTROLLER=$(lspci -nnk | grep -ie "\[0106\]" | wc -l)
SASCONTROLLER=$(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | wc -l)