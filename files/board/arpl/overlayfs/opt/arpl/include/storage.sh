# Get SataPortMap for Loader
function getmap() {
  [ -n "SATAPORTMAP" ] && SATAPORTMAP=0
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
    echo -n "${DRIVES}" >> ${TMP_PATH}/drives
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
    echo -n "${DRIVES}" >> ${TMP_PATH}/drives
    done
  fi
  # Write to config
      SATAPORTMAP=$(awk '{print$1}' ${TMP_PATH}/drives)
      if [ "${SATAPORTMAP}" -gt 10 ]; then
        writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
      fi
      if [ "${SATAPORTMAP}" -lt 8 ]; then
        SATAPORTMAP=8
        writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
      fi
}

# Check for Controller
SATAPORTMAP="`readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"`"
SATACONTROLLER=$(lspci -nnk | grep -ie "\[0106\]" | wc -l)
SCSICONTROLLER=$(lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | wc -l)

# Launch getmap
getmap