
# Check for Network Adapter
lshw -class network -short > "${TMP_PATH}/netconf"

# Check for Hypervisor
if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
    MACHINE="VIRTUAL"
    HYPERVISOR=$(lscpu | grep Hypervisor | awk '{print $3}')
fi

# Check for Raid/SCSI
if [ $(lspci -nn | grep -ie "\[0100\]" grep -ie "\[0104\]" -ie "\[0107\]" | wc -l) -gt 0 ]; then
  if [ "${MASHINE}" = "VIRTUAL" ]; then
    writeConfigKey "cmdline.SataPortMap" "1" "${USER_CONFIG_FILE}"
  else
    deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
  fi
elif [ $(lspci -nn | grep -ie "\[0101\]" grep -ie "\[0106\]" | wc -l) -gt 0 ]; then
  deleteConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"
fi

# Checks for Systeminfo Menu
TYPEINFO=$(vserver=$(lscpu | grep Hypervisor | wc -l)
          if [ $vserver -gt 0 ]; then echo "VM"; else echo "Native"; fi
          )
CPUINFO=$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')
MEMINFO=$(free -g | awk 'NR==2' | awk '{print $2}')
SCSIPCI=$(lspci -nn | grep -ie "\[0100\]" grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print$1}')
SCSIINFO=$(lspci -s "${SCSIPCI}" | sed "s/\ .*://")
SATAPCI=$(lspci -nn | grep -ie "\[0106\]" | awk '{print$1}')
SATAINFO=$(lspci -s "${SATAPCI}" | sed "s/\ .*://")
MODULESINFO=$(kmod list | awk '{print$1}' | awk 'NR>1')