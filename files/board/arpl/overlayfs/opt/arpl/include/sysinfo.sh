###############################################################################
# Shows Systeminfo to user
function sysinfo() {
  # Delete old Sysinfo
  rm -f ${SYSINFO_PATH}
  # Checks for Systeminfo Menu
  CPUINFO=`awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//'`
  VENDOR=`dmidecode -s system-product-name`
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  IPLIST=`ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p'`
  REMAP="`readConfigKey "arc.remap" "${USER_CONFIG_FILE}"`"
  if [ "${REMAP}" == "1" ] || [ "${REMAP}" == "2" ]; then
    PORTMAP="`readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}"`"
    DISKMAP="`readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}"`"
  elif [ "${REMAP}" == "3" ]; then
    PORTMAP="`readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}"`"
  fi
  CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
  BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
  ARCPATCH="`readConfigKey "arc.patch" "${USER_CONFIG_FILE}"`"
  LKM="`readConfigKey "lkm" "${USER_CONFIG_FILE}"`"
  ADDONSINFO="`readConfigEntriesArray "addons" "${USER_CONFIG_FILE}"`"
  MODULESINFO=`kmod list | awk '{print$1}' | awk 'NR>1'`
  MODULESVERSION=`cat "${MODULES_PATH}/VERSION"`
  ADDONSVERSION=`cat "${ADDONS_PATH}/VERSION"`
  LKMVERSION=`cat "${LKM_PATH}/VERSION"`
  TEXT=""
  # Print System Informations
  TEXT+="\n\Z4System:\Zn"
  TEXT+="\nTyp: \Zb"${MACHINE}"\Zn"
  if [ "$MACHINE" = "VIRTUAL" ]; then
  TEXT+="\nHypervisor: \Zb"${HYPERVISOR}"\Zn"
  fi
  TEXT+="\nVendor: \Zb"${VENDOR}"\Zn"
  TEXT+="\nCPU: \Zb"${CPUINFO}"\Zn"
  TEXT+="\nRAM: \Zb"$((RAMTOTAL /1024))"GB\Zn\n"
  # Print Config Informations
  TEXT+="\n\Z4Config:\Zn"
  TEXT+="\nArc Version: \Zb"${ARPL_VERSION}"\Zn"
  TEXT+="\nSubversion: \ZbModules "${MODULESVERSION}"\Zn | \ZbAddons "${ADDONSVERSION}"\Zn | \ZbLKM "${LKMVERSION}"\Zn"
  TEXT+="\nModel: \Zb"${MODEL}"\Zn"
  if [ -n "${CONFDONE}" ]; then
    TEXT+="\nConfig: \ZbComplete\Zn"
  else
    TEXT+="\nConfig: \ZbIncomplete\Zn"
  fi
  if [ -n "${BUILDDONE}" ]; then
    TEXT+="\nBuild: \ZbComplete\Zn"
  else
    TEXT+="\nBuild: \ZbIncomplete\Zn"
  fi
  if [ -f "${BACKUPDIR}/arc-backup.img.gz" ]; then
    TEXT+="\nBackup: \ZbFull Loader\Zn"
  elif [ -f "${BACKUPDIR}/dsm-backup.tar" ]; then
    TEXT+="\nBackup: \ZbDSM Bootimage\Zn"
  elif [ -f "${BACKUPDIR}/user-config.yml" ]; then
    TEXT+="\nBackup: \ZbOnly Config\Zn"
  else
    TEXT+="\nBackup: \ZbNo Backup found\Zn"
  fi
  TEXT+="\nArcpatch: \Zb"${ARCPATCH}"\Zn"
  TEXT+="\nLKM: \Zb"${LKM}"\Zn"
  TEXT+="\nNetwork: \Zb"${NETNUM}" Adapter\Zn"
  TEXT+="\nIP(s): \Zb"${IPLIST}"\Zn"
  if [ "${REMAP}" == "1" ] || [ "${REMAP}" == "2" ]; then
    TEXT+="\nSataPortMap: \Zb"${PORTMAP}"\Zn | DiskIdxMap: \Zb"${DISKMAP}"\Zn"
  elif [ "${REMAP}" == "3" ]; then
    TEXT+="\nSataRemap: \Zb"${PORTMAP}"\Zn"
  elif [ "${REMAP}" == "0" ]; then
    TEXT+="\nPortMap: \Zb"Set by User"\Zn"
  fi
  TEXT+="\nAddons loaded: \Zb"${ADDONSINFO}"\Zn"
  TEXT+="\nModules loaded: \Zb"${MODULESINFO}"\Zn\n"
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS
  TEXT+="\n\Z4Storage:\Zn"
  # Get Information for Sata Controller
  if [ "$SATACONTROLLER" -gt "0" ]; then
    NUMPORTS=0
    for PCI in `lspci -nnk | grep -ie "\[0106\]" | awk '{print$1}'`; do
      NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
      # Get Amount of Drives connected
      SATADRIVES=`ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l`
      TEXT+="\n\Z1SATA Controller\Zn detected:\n\Zb"${NAME}"\Zn\n"
      TEXT+="\Z1Drives\Zn detected:\n\Zb"${SATADRIVES}"\Zn\n"
      TEXT+="\n\ZbPorts: "
      unset HOSTPORTS
      declare -A HOSTPORTS
      while read LINE; do
        ATAPORT="`echo ${LINE} | grep -o 'ata[0-9]*'`"
        PORT=`echo ${ATAPORT} | sed 's/ata//'`
        HOSTPORTS[${PORT}]=`echo ${LINE} | grep -o 'host[0-9]*$'`
      done < <(ls -l /sys/class/scsi_host | fgrep "${PCI}")
      while read PORT; do
        ls -l /sys/block | fgrep -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
        PCMD=`cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd`
        [ "${PCMD}" = "0" ] && DUMMY=1 || DUMMY=0
        [ ${ATTACH} -eq 1 ] && TEXT+="\Z2\Zb"
        [ ${DUMMY} -eq 1 ] && TEXT+="\Z1"
        [ ${DUMMY} -eq 0 ] && [ ${ATTACH} -eq 0 ] && TEXT+="\Zb"
        TEXT+="${PORT}\Zn "
        NUMPORTS=$((${NUMPORTS}+1))
      done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
      TEXT+="\n "
    done
    TEXT+="\n\ZbTotal Ports: \Z2\Zb${NUMPORTS}\Zn\n"
  fi
  # Get Information for SAS Controller
  if [ "$SASCONTROLLER" -gt "0" ]; then
    for PCI in `lspci -nnk | grep -ie "\[0104\]" -ie "\[0107\]" | awk '{print$1}'`; do
      # Get Name of Controller
      NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
      # Get Amount of Drives connected
      SASDRIVES=`ls -la /sys/block | fgrep "${PCI}" | grep -v "sr.$" | wc -l`
      TEXT+="\n\Z1SAS Controller\Zn detected:\n\Zb"${NAME}"\Zn\n"
      TEXT+="\Z1Drives\Zn detected:\n\Zb"${SASDRIVES}"\Zn\n"
    done
  fi
  echo -e ${TEXT} > "${SYSINFO_PATH}"
  TEXT+="\nSysinfo File: \Zb"\\\\${IP}\\arpl\\p1\\sysinfo.yml"\Zn"
  dialog --backtitle "`backtitle`" --title "Arc Sysinfo" --aspect 18 --colors --msgbox "${TEXT}" 0 0
}