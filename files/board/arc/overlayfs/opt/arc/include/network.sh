# Get Network Config for Loader
function getnet() {
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  if [ "${ARCPATCH}" = "true" ]; then
    # Set first Mac from cmdline config
    writeConfigKey "arc.mac1" "" "${USER_CONFIG_FILE}"
    # Install with Arc Patch - Check for model config and set custom Mac Address
    [ -f "${TMP_PATH}/opts" ] && rm -f "${TMP_PATH}/opts"
    touch "${TMP_PATH}/opts"
    ARCMACNUM=1
    while true; do
      ARCMAC="$(readModelKey "${MODEL}" "arc.mac${ARCMACNUM}")"
      if [ -n "${ARCMAC}" ]; then
        echo "${ARCMAC} mac${ARCMACNUM}" >>"${TMP_PATH}/opts"
        ARCMACNUM=$((${ARCMACNUM} + 1))
      else
        break
      fi
    done
    dialog --clear --backtitle "$(backtitle)" \
      --menu "Network: MAC for 1. NIC" 0 0 0 \
      --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && continue
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    MAC="${resp}"
  else
    dialog --clear --backtitle "$(backtitle)" --title "Mac Setting" \
      --menu "Use Hardware, Random, Custom MAC?" 0 0 0 \
      1 "Use Hardware MAC" \
      2 "Use Random MAC" \
      3 "Use Custom MAC" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      # Get real Mac
      MAC="$(cat /sys/class/net/eth0/address | sed 's/://g')"
    elif [ ${resp} -eq 2 ]; then
      # Generate Random Mac
      MAC=($(generateMacAddress "${MODEL}" 1))
    elif [ ${resp} -eq 3 ]; then
      # User Mac
      MACR="$(cat /sys/class/net/eth0/address | sed 's/://g')"
      MACF="$(readConfigKey "arc.mac1" "${USER_CONFIG_FILE}")"
      [ -n "${MACF}" ] && MAC=${MACF} || MAC=${MACR}
      RET=1
      while true; do
        dialog --backtitle "$(backtitle)" --title "Mac Setting" \
          --inputbox "Type a custom MAC address of mac1" 0 0 "${MAC}"\
          2>"${TMP_PATH}/resp"
        RET=$?
        [ ${RET} -ne 0 ] && break 2
        MAC="$(<"${TMP_PATH}/resp")"
        [ -z "${MAC}" ] && MAC="$(readConfigKey "arc.mac1" "${USER_CONFIG_FILE}")"
        [ -z "${MAC}" ] && MAC="$(cat /sys/class/net/eth0/address | sed 's/://g')"
        MAC="$(echo "${MAC}" | sed "s/:\|-\| //g")"
        [ ${#MAC} -eq 12 ] && break
        dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Invalid MAC" 0 0
      done
    fi
  fi
  writeConfigKey "arc.mac1" "${MAC}" "${USER_CONFIG_FILE}"
}

# Get actual IP
ARCIP="$(readConfigKey "arc.ip" "${USER_CONFIG_FILE}")"
if [ "${ARCIP}" != "" ]; then
  IP="${ARCIP}"
else
  IP="$(ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1)"
fi