# Get SataPortMap for Loader
function getmap() {
# Check for Remap usage
if [ "${REMAP}" -lt 1 ]; then
  # Only load SataPortMap and DiskIdxMap if Sata Controller are loaded
  if [ "${SATACONTROLLER}" -gt 0 ]; then
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
  # Get portmap for remap and config
  if [ "${SATACONTROLLER}" -gt 1 ]; then
    writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAP}" "${USER_CONFIG_FILE}"
  if [ "${SATACONTROLLER}" -gt 0 ] && [ "${SASCONTROLLER}" -gt 0 ]; then
    writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAP}" "${USER_CONFIG_FILE}"
  elif [ "${SATACONTROLLER}" -gt 0 ] && [ "${SCSICONTROLLER}" -gt 0 ]; then
    writeConfigKey "cmdline.SataPortMap" "${SATAPORTMAP}" "${USER_CONFIG_FILE}"
    writeConfigKey "cmdline.DiskIdxMap" "${DISKIDXMAP}" "${USER_CONFIG_FILE}"
  else
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
    deleteConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"
  fi
fi
}

# Check for Controller
SATACONTROLLER=$(lspci -nnk | grep -ie "\[0106\]" | wc -l)
SCSICONTROLLER=$(lspci -nnk | grep -ie "\[0104\]" | wc -l)
SASCONTROLLER=$(lspci -nnk | grep -ie "\[0107\]" | wc -l)

# Launch getmap
getmap