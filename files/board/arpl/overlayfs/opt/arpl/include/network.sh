# Get Network Config for Loader
function getnet() {
  ARCPATCH="`readConfigKey "arc.patch" "${USER_CONFIG_FILE}"`"
  writeConfigKey "cmdline.netif_num" "${NETNUM}" "${USER_CONFIG_FILE}"
  # Get MAC address
  ETHX=(`ls /sys/class/net/ | grep eth`)  # real network cards list
  for N in $(seq 1 ${#ETHX[@]}); do
    # Get real Mac that is written to config while Init
    MACR="`readConfigKey "device.mac${N}" "${USER_CONFIG_FILE}"`"
    # Write real MAC to cmdline config
    writeConfigKey "cmdline.mac${N}" "${MACR}" "${USER_CONFIG_FILE}"
  done
  if [ "${ARCPATCH}" = "true" ]; then 
    # Delete first Mac from cmdline config
    deleteConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"
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
        writeConfigKey "cmdline.mac1" "${MAC1}" "${USER_CONFIG_FILE}"
        break
      elif [ "${resp}" = "2" ]; then
        writeConfigKey "cmdline.mac1" "${MAC2}" "${USER_CONFIG_FILE}"
        break
      elif [ "${resp}" = "3" ]; then
        writeConfigKey "cmdline.mac1" "${MAC3}" "${USER_CONFIG_FILE}"
        break
      elif [ "${resp}" = "4" ]; then
        writeConfigKey "cmdline.mac1" "${MAC4}" "${USER_CONFIG_FILE}"
        break
      fi
    done
    dialog --backtitle "`backtitle`" \
      --title "Arc Network" --infobox "Set MAC for first NIC" 0 0
    sleep 2
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
        sleep 2
        break
      elif [ "${resp}" = "2" ]; then
        dialog --backtitle "`backtitle`" --title "Arc Network" \
          --infobox "IP/MAC will be changed now!" 0 0
        MACF="`readConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"`"
        MACFN="${MACF:0:2}:${MACF:2:2}:${MACF:4:2}:${MACF:6:2}:${MACF:8:2}:${MACF:10:2}"
        ifconfig eth0 hw ether ${MACFN} >/dev/null 2>&1
        /etc/init.d/S41dhcpcd restart 2>&1 | dialog --backtitle "`backtitle`" \
          --title "Restart DHCP" --progressbox "Renewing IP" 20 70
        sleep 3
        IP=`ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1`
        sleep 2
        break
      fi
    done
  fi
}

# Get actual IP and NETIF_NUM
IP=`ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1`
NETNUM=`lshw -class network -short | grep -ie "eth[0-9]" | wc -l`