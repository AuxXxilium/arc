# Get Network Config for Loader
function getnet() {
  # Delete old Mac Address from Userconfig
  #deleteConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"
  dialog --backtitle "`backtitle`" \
    --title "Arc Network" --msgbox " ${NETNUM} Adapter dedected" 0 0
  ARCPATCH="`readConfigKey "arc.patch" "${USER_CONFIG_FILE}"`"
  if [ "${ARCPATCH}" = "true" ]; then 
    # Install with Arc Patch - Check for model config and set custom Mac Address
    MAC1="`readModelKey "${MODEL}" "arc.mac1"`"
    MAC2="`readModelKey "${MODEL}" "arc.mac2"`"
    MAC3="`readModelKey "${MODEL}" "arc.mac3"`"
    MAC4="`readModelKey "${MODEL}" "arc.mac4"`"
    while true; do
      dialog --clear --backtitle "`backtitle`" \
        --menu "Network: MAC for 1. NIC" 0 0 0 \
        1 "Use MAC1: ${MAC1}" \
        2 "Use MAC2: ${MAC2}" \
        3 "Use MAC3: ${MAC3}" \
        4 "Use MAC4: ${MAC4}" \
      2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(<${TMP_PATH}/resp)
      [ -z "${resp}" ] && return
      if [ "${resp}" = "1" ]; then
        deleteConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"
        writeConfigKey "cmdline.mac1" "${MAC1}" "${USER_CONFIG_FILE}"
        break
      elif [ "${resp}" = "2" ]; then
        deleteConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"
        writeConfigKey "cmdline.mac1" "${MAC2}" "${USER_CONFIG_FILE}"
        break
      elif [ "${resp}" = "3" ]; then
        deleteConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"
        writeConfigKey "cmdline.mac1" "${MAC3}" "${USER_CONFIG_FILE}"
        break
      elif [ "${resp}" = "4" ]; then
        deleteConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"
        writeConfigKey "cmdline.mac1" "${MAC4}" "${USER_CONFIG_FILE}"
        break
      fi
    done
    dialog --backtitle "`backtitle`" \
      --title "Arc Network" --infobox "Set MAC for first NIC" 0 0
    sleep 2
  elif [ "${ARCPATCH}" = "false" ]; then
    dialog --backtitle "`backtitle`" \
      --title "Arc Network" --infobox "Set MAC for all NIC" 0 0
    sleep 2
  fi
  if [ "${ARCPATCH}" = "true" ]; then 
    # Ask for IP rebind
    while true; do
      dialog --clear --backtitle "`backtitle`" \
        --menu "Restart DHCP?" 0 0 0 \
        1 "No - Get new IP on Boot" \
        2 "Yes - Get new IP now" \
      2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(<${TMP_PATH}/resp)
      [ -z "${resp}" ] && return
      if [ "${resp}" = "1" ]; then
        dialog --backtitle "`backtitle`" --title "Arc Network" \
          --infobox "IP/MAC will be changed on first boot!" 0 0
        sleep 1
        break
      elif [ "${resp}" = "2" ]; then
        dialog --backtitle "`backtitle`" --title "Arc Network" \
          --infobox "IP/MAC will be changed now!" 0 0
        MAC1="`readConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"`"
        MACN1="${MAC1:0:2}:${MAC1:2:2}:${MAC1:4:2}:${MAC1:6:2}:${MAC1:8:2}:${MAC1:10:2}"
        ip link set dev eth0 address ${MACN1} 2>&1
        /etc/init.d/S41dhcpcd restart 2>&1 | dialog --backtitle "`backtitle`" \
          --title "Restart DHCP" --progressbox "Renewing IP" 20 70
        sleep 5
        IP=`ip route 2>/dev/null | sed -n 's/.* via .* dev \(.*\)  src \(.*\)  metric .*/\1: \2 /p' | head -1`
        sleep 1
        break
      fi
    done
  fi
}