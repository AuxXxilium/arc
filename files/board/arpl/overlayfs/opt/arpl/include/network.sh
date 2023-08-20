# Get Network Config for Loader
function getnet() {
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  writeConfigKey "cmdline.netif_num" "${NETNUM}" "${USER_CONFIG_FILE}"
  # Get MAC address
  for N in $(seq 1 ${#ETHX[@]}); do
    # Get real Mac that is written to config while Init
    MACR="$(readConfigKey "device.mac${N}" "${USER_CONFIG_FILE}")"
    # Write real MAC to cmdline config
    writeConfigKey "cmdline.mac${N}" "${MACR}" "${USER_CONFIG_FILE}"
  done
  if [ "${ARCPATCH}" = "true" ]; then 
    # Set first Mac from cmdline config
    writeConfigKey "cmdline.mac1" "" "${USER_CONFIG_FILE}"
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
    while true; do
      dialog --clear --backtitle "$(backtitle)" \
        --menu "Network: MAC for 1. NIC" 0 0 0 \
        --file "${TMP_PATH}/opts" \
      2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return 1
      resp="$(<"${TMP_PATH}/resp")"
      [ -z "${resp}" ] && return 1
      MAC="${resp}"
      writeConfigKey "cmdline.mac1" "${MAC}" "${USER_CONFIG_FILE}"
      break
    done
    dialog --backtitle "$(backtitle)" \
      --title "Arc Network" --infobox "Set MAC for first NIC" 0 0
    sleep 2
  fi
}

# Get actual IP and NETIF_NUM
IP="$(ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1)"
ETHXNUM=$(ls /sys/class/net/ | grep eth | wc -l) # Amount of NIC
ETHX=($(ls /sys/class/net/ | grep eth))  # Real NIC List