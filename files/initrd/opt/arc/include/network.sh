# Get Network Config for Loader
function getnet() {
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  if [ "${ARCPATCH}" = "arc" ]; then
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
    dialog --clear --backtitle "$(backtitle)" --title "Mac Setting"\
      --menu "Choose a MAC" 0 0 0 \
      --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && continue
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    MAC="${resp}"
    writeConfigKey "arc.mac1" "${MAC}" "${USER_CONFIG_FILE}"
  elif [ "${ARCPATCH}" = "random" ]; then
    # Generate Random Mac
    MAC=($(generateMacAddress "${MODEL}" 1))
    writeConfigKey "arc.mac1" "${MAC}" "${USER_CONFIG_FILE}"
  elif [ "${ARCPATCH}" = "user" ]; then
    # User Mac
    MAC="$(cat /sys/class/net/eth0/address | sed 's/://g')"
    RET=1
    for N in ${ETH}; do
      dialog --backtitle "$(backtitle)" --title "Mac Setting" \
        --inputbox "Type a custom MAC for ${N}. NIC.\n Eq. 001132123456" 0 0 "${MAC}"\
        2>"${TMP_PATH}/resp"
      RET=$?
      [ ${RET} -ne 0 ] && break 2
      MAC="$(<"${TMP_PATH}/resp")"
      [ -z "${MAC}" ] && MAC="$(readConfigKey "arc.mac${N}" "${USER_CONFIG_FILE}")"
      [ -z "${MAC}" ] && MAC="$(cat /sys/class/net/eth0/address | sed 's/://g')"
      MAC="$(echo "${MAC}" | sed "s/:\|-\| //g")"
      writeConfigKey "arc.mac${N}" "${MAC}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.macsys" "custom" "${USER_CONFIG_FILE}"
      [ ${#MAC} -eq 12 ] && break
      dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Invalid MAC" 0 0
    done
  fi
  # Ask for Macsys
  dialog --clear --backtitle "$(backtitle)" --title "Macsys Setting" \
    --menu "Do you want to apply Mac to NIC?" 7 50 0 \
    1 "No - Do not apply (Fake)Mac" \
    2 "Yes - Apply (Fake)Mac" \
  2>"${TMP_PATH}/resp"
  resp="$(<"${TMP_PATH}/resp")"
  [ -z "${resp}" ] && return 1
  if [ ${resp} -eq 1 ]; then
    writeConfigKey "arc.macsys" "hardware" "${USER_CONFIG_FILE}"
  elif [ ${resp} -eq 2 ]; then
    writeConfigKey "arc.macsys" "custom" "${USER_CONFIG_FILE}"
  fi
  MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
}

# Get Amount of NIC
ETHX=$(ls /sys/class/net/ | grep -v lo || true)
ETH=$(echo ${ETHX} | wc -w)
writeConfigKey "device.nic" "${ETH}" "${USER_CONFIG_FILE}"
# Get actual IP
ARCIP="$(readConfigKey "arc.ip" "${USER_CONFIG_FILE}")"
if [ -n "${ARCIP}" ]; then
  IP="${ARCIP}"
else
  IP="$(getIP)"
fi