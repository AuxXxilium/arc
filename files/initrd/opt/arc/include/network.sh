# Get Network Config for Loader
function getnet() {
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  if [ "${ARCPATCH}" = "true" ]; then
    ARCMACNUM=1
    for ETH in ${ETHX}; do
      ARCMAC="$(readModelKey "${MODEL}" "arc.mac${ARCMACNUM}")"
      [ -n "${ARCMAC}" ] && writeConfigKey "mac.${ETH}" "${ARCMAC}" "${USER_CONFIG_FILE}"
      [ -z "${ARCMAC}" ] && break
      ARCMACNUM=$((${ARCMACNUM} + 1))
      ARCMAC=""
    done
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
      MAC=$(cat "${TMP_PATH}/resp")
      [ -z "${MAC}" ] && MAC="$(readConfigKey "mac.${ETH}" "${USER_CONFIG_FILE}")"
      [ -z "${MAC}" ] && MAC="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
      MAC="$(echo "${MAC}" | sed "s/:\|-\| //g")"
      writeConfigKey "mac.${ETH}" "${MAC}" "${USER_CONFIG_FILE}"
      [ ${#MAC} -eq 12 ] && break
      dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Invalid MAC" 0 0
    done
  fi
  # Ask for Macsys
  dialog --clear --backtitle "$(backtitle)" \
    --nocancel --title "Macsys Setting" \
    --menu "Choose an Option\n* Recommended Option" 8 50 0 \
    1 "Hardware - Use Hardware Mac for DSM *" \
    2 "Custom - Use Custom/Fake Mac for DSM" \
  2>"${TMP_PATH}/resp"
  resp=$(cat "${TMP_PATH}/resp")
  [ -z "${resp}" ] && return 1
  if [ ${resp} -eq 1 ]; then
    writeConfigKey "arc.macsys" "hardware" "${USER_CONFIG_FILE}"
  elif [ ${resp} -eq 2 ]; then
    writeConfigKey "arc.macsys" "custom" "${USER_CONFIG_FILE}"
  fi
  MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
}

# Get Amount of NIC
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
# Get actual IP
for ETH in ${ETHX}; do
  IPCON="$(getIP ${ETH})"
  [ -n "${IPCON}" ] && break
done