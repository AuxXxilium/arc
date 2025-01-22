# Get Network Config for Loader
function getnet() {
  generate_and_write_macs() {
    local patch=$1
    local macs=($(generateMacAddress "${MODEL}" "${ETHN}" "${patch}"))

    for i in $(seq 1 "${ETHN}"); do
      local mac="${macs[$((i - 1))]}"
      writeConfigKey "eth$((i - 1))" "${mac}" "${USER_CONFIG_FILE}"
    done
  }

  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth)
  MODEL=$(readConfigKey "model" "${USER_CONFIG_FILE}")
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  ARCCONF="$(readConfigKey "${MODEL}.serial" "${S_FILE}")"
  ARCMODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"
  ETHN=$(echo "${ETHX}" | wc -w)

  if [ "${ARCPATCH}" = "user" ]; then
    for N in ${ETHX}; do
      while true; do
        dialog --backtitle "$(backtitle)" --title "Mac Setting" \
          --inputbox "Type a custom Mac for ${N} (Eq. 001132a1b2c3).\nA custom Mac will not be applied to NIC!" 8 50 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        MAC=$(cat "${TMP_PATH}/resp")
        [ -z "${MAC}" ] && MAC=$(readConfigKey "${N}" "${USER_CONFIG_FILE}")
        [ -z "${MAC}" ] && MAC=$(cat /sys/class/net/${N}/address 2>/dev/null | sed 's/://g')
        MAC=$(echo "${MAC}" | tr '[:upper:]' '[:lower:]')
        if [ ${#MAC} -eq 12 ]; then
          dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Set Mac for ${N} to ${MAC}!" 5 50
          writeConfigKey "${N}" "${MAC}" "${USER_CONFIG_FILE}"
          break
        else
          dialog --backtitle "$(backtitle)" --title "Mac Setting" --msgbox "Invalid MAC - Try again!" 5 50
        fi
      done
    done
  elif [ "${ARCPATCH}" != "user" ] && [ -n "${ARCCONF}" ]; then
    generate_and_write_macs "${ARCPATCH}"
  else
    generate_and_write_macs "false"
  fi
}

# Get Amount of NIC
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth)
# Get actual IP
for N in ${ETHX}; do
  IPCON="$(getIP "${N}")"
  [ -n "${IPCON}" ] && break || IPCON="noip"
done