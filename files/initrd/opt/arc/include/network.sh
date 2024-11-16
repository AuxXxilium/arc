# Get Network Config for Loader
function getnet() {
  ETHX=$(ip -o link show | awk -F': ' '{print $2}' | grep eth)
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  NICPORTS="$(readConfigKey "${MODEL}.ports" "${S_FILE}" 2>/dev/null)"
  ETHN=$(echo ${ETHX} | wc -w)
  if [ "${ARCPATCH}" == "true" ]; then
    MACS=($(generateMacAddress "${MODEL}" "${ETHN}" "true"))
    for I in $(seq 1 ${ETHN}); do
      eval MAC${I}="${MACS[$((${I} - 1))]}"
      writeConfigKey "eth$((${I} - 1))" "${MACS[$((${I} - 1))]}" "${USER_CONFIG_FILE}"
    done
  elif [ "${ARCPATCH}" == "false" ]; then
    MACS=($(generateMacAddress "${MODEL}" "${ETHN}" "false"))
    for I in $(seq 1 ${ETHN}); do
      eval MAC${I}="${MACS[$((${I} - 1))]}"
      writeConfigKey "eth$((${I} - 1))" "${MACS[$((${I} - 1))]}" "${USER_CONFIG_FILE}"
    done
  elif [ "${ARCPATCH}" == "user" ]; then
    # User Mac
    for N in ${ETHX}; do
      while true; do
        MAC="$(cat /sys/class/net/${N}/address | sed 's/://g' | tr '[:lower:]' '[:upper:]')"
        dialog --backtitle "$(backtitle)" --title "Mac Setting" \
          --inputbox "Type a custom MAC for ${ETH} (Eq. 001132abc123)." 7 50 "${MAC}"\
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        MAC=$(cat "${TMP_PATH}/resp")
        [ -z "${MAC}" ] && MAC="$(readConfigKey "${N}" "${USER_CONFIG_FILE}")"
        [ -z "${MAC}" ] && MAC="$(cat /sys/class/net/${N}/address 2>/dev/null | sed 's/://g' | tr '[:lower:]' '[:upper:]')"
        MAC="$(echo "${MAC}" | tr '[:lower:]' '[:upper:]')"
        if [ ${#MAC} -eq 12 ]; then
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
ETHX="$(ls /sys/class/net 2>/dev/null | grep eth)"
# Get actual IP
for ETH in ${ETHX}; do
  IPCON=$(getIP ${ETH})
  [ -n "${IPCON}" ] && break
done