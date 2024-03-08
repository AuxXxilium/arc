# Get Network Config for Loader
function getnet() {
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  if [ "${ARCPATCH}" = "true" ]; then
      # Ask for Arc Settings
    dialog --clear --backtitle "$(backtitle)" \
      --nocancel --title "Arc Setting" \
      --menu "Choose an Option" 7 50 0 \
      1 "Apply Arc Patch for eth0" \
      2 "Apply Arc Patch for all NIC" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
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
        --nocancel --title "Mac Setting" \
        --menu "Choose a MAC for eth0" 0 0 0 \
        --file "${TMP_PATH}/opts" \
      2>"${TMP_PATH}/resp"
      resp="$(<"${TMP_PATH}/resp")"
      [ -z "${resp}" ] && return 1
      MAC="${resp}"
      writeConfigKey "mac.eth0" "${MAC}" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 2 ]; then
      ARCMACNUM=1
      for ETH in ${ETHX}; do
        ARCMAC="$(readModelKey "${MODEL}" "arc.mac${ARCMACNUM}")"
        [ -n "${ARCMAC}" ] && writeConfigKey "mac.${ETH}" "${ARCMAC}" "${USER_CONFIG_FILE}"
        [ -z "${ARCMAC}" ] && break
        ARCMACNUM=$((${ARCMACNUM} + 1))
      done
    fi
  elif [ "${ARCPATCH}" = "false" ]; then
    for ETH in ${ETHX}; do
      MACS=$(generateMacAddress "${MODEL}" 1)
      writeConfigKey "mac.${ETH}" "${MAC}" "${USER_CONFIG_FILE}"
    done
  elif [ "${ARCPATCH}" = "user" ]; then
    # User Mac
    RET=1
    for ETH in ${ETHX}; do
      MAC="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
      dialog --backtitle "$(backtitle)" --title "Mac Setting" \
        --inputbox "Type a custom MAC for ${ETH}.\n Eq. 001132123456" 0 0 "${MAC}"\
        2>"${TMP_PATH}/resp"
      RET=$?
      [ ${RET} -ne 0 ] && break 2
      MAC="$(<"${TMP_PATH}/resp")"
      [ -z "${MAC}" ] && MAC="$(readConfigKey "mac.${ETH}" "${USER_CONFIG_FILE}")"
      [ -z "${MAC}" ] && MAC="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
      MAC="$(echo "${MAC}" | sed "s/:\|-\| //g")"
      writeConfigKey "mac.${ETH}" "${MAC}" "${USER_CONFIG_FILE}"
      [ ${#MAC} -eq 12 ] && break
      dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Invalid MAC" 0 0
    done
  fi
  if [ "${ARCPATCH}" = "true" ]; then
    # Ask for Macsys
    dialog --clear --backtitle "$(backtitle)" \
      --nocancel --title "Macsys Setting" \
      --menu "Choose an Option\n* Recommended Option" 10 50 0 \
      1 "Arc - Use Arc Mac Settings for DSM *" \
      2 "Hardware - Use Hardware Mac for DSM" \
      3 "Custom - Use Custom Mac for DSM" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      writeConfigKey "arc.macsys" "arc" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 2 ]; then
      writeConfigKey "arc.macsys" "hardware" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 3 ]; then
      writeConfigKey "arc.macsys" "custom" "${USER_CONFIG_FILE}"
    fi
  else
    # Ask for Macsys
    dialog --clear --backtitle "$(backtitle)" \
      --nocancel --title "Macsys Setting" \
      --menu "Choose an Option" 7 50 0 \
      1 "Hardware - Use Hardware Mac for DSM" \
      2 "Custom - Use Custom Mac for DSM" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      writeConfigKey "arc.macsys" "hardware" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 2 ]; then
      writeConfigKey "arc.macsys" "custom" "${USER_CONFIG_FILE}"
    fi
  fi
  MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
}

# Get Amount of NIC
ETHX=$(ls /sys/class/net/ | grep -v lo) || true
# Get actual IP
for ETH in ${ETHX}; do
  IPCON="$(readConfigKey "ip.${ETH}" "${USER_CONFIG_FILE}")"
  [ -z "${IPCON}" ] && IPCON="$(getIP ${ETH})"
  [ -n "${IPCON}" ] && break
done