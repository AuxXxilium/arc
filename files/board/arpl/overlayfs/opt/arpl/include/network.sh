# Get Network Config for Loader
function getnet() {
  # Delete old Mac Address from Userconfig
  #deleteConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"
  dialog --backtitle "`backtitle`" \
    --title "Arc Network" --msgbox " ${NETNUM} Adapter dedected" 0 0
  writeConfigKey "cmdline.netif_num"    "${NETNUM}"  "${USER_CONFIG_FILE}"
  if [ "${ARCPATCH}" = "1" ]; then 
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
          writeConfigKey "cmdline.mac1"           "${MAC1}" "${USER_CONFIG_FILE}"
          break
      elif [ "${resp}" = "2" ]; then
          writeConfigKey "cmdline.mac1"           "${MAC2}" "${USER_CONFIG_FILE}"
          break
      elif [ "${resp}" = "3" ]; then
          writeConfigKey "cmdline.mac1"           "${MAC3}" "${USER_CONFIG_FILE}"
          break
      elif [ "${resp}" = "4" ]; then
          writeConfigKey "cmdline.mac1"           "${MAC4}" "${USER_CONFIG_FILE}"
          break
      fi
    done
    dialog --backtitle "`backtitle`" \
      --title "Arc Network" --infobox "Set MAC for first NIC" 0 0
    sleep 2
  elif [ "${ARCPATCH}" = "0" ]; then
    # Install without Arc Patch - Set Hardware Mac Address
    MAC1="`readConfigKey "device.mac1" "${USER_CONFIG_FILE}"`"
    writeConfigKey "cmdline.mac1"           "${MAC1}" "${USER_CONFIG_FILE}"
    dialog --backtitle "`backtitle`" \
      --title "Arc Network" --infobox "Set MAC for all NIC" 0 0
    sleep 2
  fi
  # Set original mac for higher adapter numbers
  if [ "${NETNUM}" -gt 1 ]; then
    COUNT=2
    while true; do
      MACO="`readConfigKey "device.mac${COUNT}" "${USER_CONFIG_FILE}"`"
      writeConfigKey "cmdline.mac${COUNT}" "${MACO}" "${USER_CONFIG_FILE}"
      if [ ${COUNT} -eq ${NETNUM} ]; then
        break
      fi
      COUNT=$((${COUNT}+1))
    done
  fi
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
      IP=`ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1`
      sleep 1
      break
    fi
  done
}