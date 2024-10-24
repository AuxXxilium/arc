# Get Network Config for Loader
function getnet() {
  ETHX="$(ls /sys/class/net 2>/dev/null | grep eth)"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  NICPORTS="$(readConfigKey "${MODEL}.ports" "${S_FILE}" 2>/dev/null)"
  if [ "${ARCPATCH}" == "true" ]; then
    ETHN="$(echo ${ETHX} | wc -w)"
    MACS=($(generateMacAddress "${MODEL}" "${ETHN}" "true" | tr '[:upper:]' '[:lower:]'))
    for I in $(seq 1 ${ETHN}); do
      eval MAC${I}="${MACS[$((${I} - 1))]}"
      writeConfigKey "eth$((${I} - 1))" "${MACS[$((${I} - 1))]}" "${USER_CONFIG_FILE}"
    done
  elif [ "${ARCPATCH}" == "false" ]; then
    ETHN="$(echo ${ETHX} | wc -w)"
    MACS=($(generateMacAddress "${MODEL}" "${ETHN}" "false" | tr '[:upper:]' '[:lower:]'))
    for I in $(seq 1 ${ETHN}); do
      eval MAC${I}="${MACS[$((${I} - 1))]}"
      writeConfigKey "eth$((${I} - 1))" "${MACS[$((${I} - 1))]}" "${USER_CONFIG_FILE}"
    done
  elif [ "${ARCPATCH}" == "user" ]; then
    # User Mac
    for ETH in ${ETHX}; do
      while true; do
        MAC="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
        dialog --backtitle "$(backtitle)" --title "Mac Setting" \
          --inputbox "Type a custom MAC for ${ETH} (Eq. 001132abc123)." 7 50 "${MAC}"\
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        MAC=$(cat "${TMP_PATH}/resp")
        [ -z "${MAC}" ] && MAC="$(readConfigKey "${ETH}" "${USER_CONFIG_FILE}")"
        [ -z "${MAC}" ] && MAC="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g')"
        MAC="$(echo "${MAC}" | tr '[:upper:]' '[:lower:]')"
        if [ ${#MAC} -eq 12 ]; then
          writeConfigKey "${ETH}" "${MAC}" "${USER_CONFIG_FILE}"
          break
        else
          dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Invalid MAC - Try again!" 5 50
        fi
      done
    done
  fi
}

# Get Amount of NIC
ETHX="$(ls /sys/class/net 2>/dev/null | grep eth)"
# Get actual IP
for ETH in ${ETHX}; do
  IPCON=$(getIP ${ETH})
  [ -n "${IPCON}" ] && break
done