# Get Network Config for Loader
function getnet() {
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  NICPORTS="$(readConfigKey "${MODEL}.ports" "${S_FILE}" 2>/dev/null)"
  ETHN=$(echo ${ETHX} | wc -w)
  if [ "${ARCPATCH}" = "true" ]; then
    MACS=($(generateMacAddress "${MODEL}" "${ETHN}" "true"))
    for I in $(seq 1 ${ETHN}); do
      eval MAC${I}="${MACS[$((${I} - 1))]}"
      writeConfigKey "eth$((${I} - 1))" "\"${MACS[$((${I} - 1))]}\"" "${USER_CONFIG_FILE}"
    done
  elif [ "${ARCPATCH}" = "false" ]; then
    MACS=($(generateMacAddress "${MODEL}" "${ETHN}" "false"))
    for I in $(seq 1 ${ETHN}); do
      eval MAC${I}="${MACS[$((${I} - 1))]}"
      writeConfigKey "eth$((${I} - 1))" "\"${MACS[$((${I} - 1))]}\"" "${USER_CONFIG_FILE}"
    done
  elif [ "${ARCPATCH}" = "user" ]; then
    # User Mac
    for N in ${ETHX}; do
      while true; do
        dialog --backtitle "$(backtitle)" --title "Mac Setting" \
          --inputbox "Type a custom Mac for ${N} (Eq. 001132a1b2c3).\nA custom Mac will not be applied to NIC!" 8 50\
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        MAC=$(cat "${TMP_PATH}/resp")
        [ -z "${MAC}" ] && MAC="$(readConfigKey "${N}" "${USER_CONFIG_FILE}")"
        [ -z "${MAC}" ] && MAC="$(cat /sys/class/net/${N}/address 2>/dev/null | sed 's/://g')"
        MAC="$(echo "${MAC}" | tr '[:upper:]' '[:lower:]')"
        if [ ${#MAC} -eq 12 ]; then
          dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Set Mac for ${N} to ${MAC}!" 5 50
          writeConfigKey "${N}" "${MAC}" "${USER_CONFIG_FILE}"
          break
        else
          dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Invalid MAC - Try again!" 5 50
        fi
      done
    done
  fi
}

# Get Amount of NIC
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
# Get actual IP
for N in ${ETHX}; do
  IPCON="$(getIP "${N}")"
  [ -n "${IPCON}" ] && break
done