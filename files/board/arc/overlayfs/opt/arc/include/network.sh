# Get Network Config for Loader
function getnet() {
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  # Get real Mac that is written to config while Init
  MACR="$(cat /sys/class/net/eth0/address | sed 's/://g')"
  # Write real MAC to cmdline config
  writeConfigKey "arc.mac1" "${MACR}" "${USER_CONFIG_FILE}"
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
    writeConfigKey "arc.mac1" "${MAC}" "${USER_CONFIG_FILE}"
  fi
}

# Get actual IP
IP="$(ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1)"