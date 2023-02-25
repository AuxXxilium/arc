###############################################################################
# Check for diskconfig and set new if necessary
SATAPORTMAP="`readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"`"
[ -n "SATAPORTMAP" ] && SATAPORTMAP=0
SATACONTROLLER=$(lspci -nnk | grep -ie "\[0106\]" | wc -l)
SCSICONTROLLER=$(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | wc -l)
rm -f ${TMP_PATH}/drives
touch ${TMP_PATH}/drives
sleep 1
# Get Number of Sata Drives
if [ "${SATACONTROLLER}" -gt 0 ]; then
  pcis=$(lspci -nnk | grep -ie "\[0106\]" | awk '{print $1}')
  [ ! -z "$pcis" ]
  # loop through SATA controllers
  for pci in $pcis; do
  # get attached block devices (exclude CD-ROMs)
  DRIVES=$(ls -la /sys/block | fgrep "${pci}" | grep -v "sr.$" | wc -l)
  if [ "${DRIVES}" -gt 8 ]; then
    DRIVES=8
    WARNON=1
  fi
  if [ "${DRIVES}" -gt 0 ]; then
    echo -n "${DRIVES}" >> ${TMP_PATH}/drives
  fi
  done
fi
# Get Number of Raid/SCSI Drives
if [ "${SCSICONTROLLER}" -gt 0 ]; then
  pcis=$(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print $1}')
  [ ! -z "$pcis" ]
  # loop through non-SATA controllers
  for pci in $pcis; do
  # get attached block devices (exclude CD-ROMs)
    DRIVES=$(ls -la /sys/block | fgrep "${pci}" | grep -v "sr.$" | wc -l)
  if [ "${DRIVES}" -gt 8 ]; then
    DRIVES=8
    WARNON=1
  fi
  if [ "${DRIVES}" -gt 0 ]; then
    echo -n "${DRIVES}" >> ${TMP_PATH}/drives
  fi
  done
fi
# Only load config if more than 1 Sata Controller or a Raid/SCSI Controller is dedected
if [ "${SATACONTROLLER}" -gt 1 ] || [ "${SCSICONTROLLER}" -gt 0 ]; then
  # Set SataPortMap for multiple Sata Controller
  if [ "${SATACONTROLLER}" -gt 1 ]; then
    DRIVES=$(awk '{print$1}' ${TMP_PATH}/drives)
    if [ "${DRIVES}" -gt 0 ]; then
      if [ "${DRIVES}" != "${SATAPORTMAP}" ]; then
        writeConfigKey "cmdline.SataPortMap" "${DRIVES}" "${USER_CONFIG_FILE}"
      fi
    fi
  fi
  # Set SataPortMap for multiple Raid/SCSI Controller
  if [ "${SCSICONTROLLER}" -gt 0 ]; then
    DRIVES=$(awk '{print$1}' ${TMP_PATH}/drives)
    if [ "${DRIVES}" != "${SATAPORTMAP}" ]; then
      writeConfigKey "cmdline.SataPortMap" "${DRIVES}" "${USER_CONFIG_FILE}"
    fi
  fi
else
  deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
fi