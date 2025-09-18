#!/usr/bin/env bash

echo "Content-type: text/plain"
echo ""

# Debugging output
#echo "Debug: Starting script" >&2

# Read key value from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Return Value
function readConfigKey() {
  RESULT=$(/usr/bin/yq eval '.'${1}' | explode(.)' "${2}" 2>/dev/null)
  [ "${RESULT}" = "null" ] && echo "" || echo "${RESULT}"
}

# Read Entries as map(key=value) from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns map of values
function readConfigMap() {
  /usr/bin/yq eval '.'${1}' | explode(.) | to_entries | map([.key, .value] | join(": ")) | .[]' "${2}" 2>/dev/null
}

# Read an array from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns array/map of values
function readConfigArray() {
  /usr/bin/yq eval '.'${1}'[]' "${2}" 2>/dev/null
}

# Read Entries as array from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns array of values
function readConfigEntriesArray() {
  /usr/bin/yq eval '.'${1}' | explode(.) | to_entries | map([.key])[] | .[]' "${2}" 2>/dev/null
}

# get IP
# 1 - ethN
function getIP() {
  local IP=""
  if [ -n "${1}" ] && [ -d "/sys/class/net/${1}" ]; then
    IP=$(/sbin/ip route show dev "${1}" 2>/dev/null | sed -n 's/.* via .* src \(.*\) metric .*/\1/p' | head -1)
    [ -z "${IP}" ] && IP=$(/sbin/ip addr show "${1}" scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -d'/' -f1 | head -1)
  else
    IP=$(/sbin/ip route show 2>/dev/null | sed -n 's/.* via .* src \(.*\) metric .*/\1/p' | head -1 | awk '{$1=$1};1')
    [ -z "${IP}" ] && IP=$(/sbin/ip addr show scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -d'/' -f1 | head -1)
  fi
  echo "${IP}"
  return 0
}

###############################################################################
# get bus of disk
# 1 - device path
function getBus() {
  local BUS=""
  # usb/ata(ide)/sata/sas/spi(scsi)/virtio/mmc/nvme
  [ -z "${BUS}" ] && BUS=$(/usr/sbin/lsblk -dpno KNAME,TRAN 2>/dev/null | grep "${1} " | awk '{print $2}' | sed 's/^ata$/ide/' | sed 's/^spi$/scsi/') #Spaces are intentional
  # usb/scsi(ide/sata/sas)/virtio/mmc/nvme/vmbus/xen(xvd)
  [ -z "${BUS}" ] && BUS=$(/usr/sbin/lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep "${1} " | awk '{print $2}' | awk -F':' '{print $(NF-1)}' | sed 's/_host//' | sed 's/^.*xen.*$/xen/') # Spaces are intentional
  [ -z "${BUS}" ] && BUS="unknown"
  echo "${BUS}"
  return 0
}

###############################################################################
# sysinfo
function getSysinfo() {
  . /opt/arc/include/consts.sh
  USER_CONFIG_FILE="/mnt/p1/user-config.yml"
  # Memory: Check Memory installed
  RAMTOTAL="$(awk '/MemTotal:/ {printf "%.0f\n", $2 / 1024 / 1024 + 0.5}' /proc/meminfo 2>/dev/null)"
  [ -z "${RAMTOTAL}" ] && RAMTOTAL="8"
  # Check for Hypervisor
  if grep -q "^flags.*hypervisor.*" /proc/cpuinfo; then
    MACHINE="$(lscpu | grep Hypervisor | awk '{print $3}')" # KVM or VMware
  else
    MACHINE="Native"
  fi
  # Check for AES Support
  if ! grep -q "^flags.*aes.*" /proc/cpuinfo; then
    AESSYS="false"
  else
    AESSYS="true"
  fi
  # Check for CPU Frequency Scaling
  CPUFREQUENCIES=$(ls -ltr /sys/devices/system/cpu/cpufreq/* 2>/dev/null | wc -l)
  if [ ${CPUFREQUENCIES} -gt 1 ]; then
    CPUFREQ="true"
  else
    CPUFREQ="false"
  fi
  # Get System Informations
  [ -d /sys/firmware/efi ] && BOOTSYS="UEFI" || BOOTSYS="BIOS"
  USERID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
  CPU="$(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  local b v
  if [ -r /sys/class/dmi/id/product_name ]; then
    b="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    b="$(echo "${b}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  fi
  if [ -z "${b}" ] || echo "${b}" | grep -Eq "O\.E\.M\.|System|To Be Filled By O\.E\.M\."; then
    if [ -r /sys/class/dmi/id/board_name ]; then
      b="$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)"
      b="$(echo "${b}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    fi
  fi
  if [ -r /sys/class/dmi/id/sys_vendor ]; then
    v="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
    v="$(echo "${v}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  fi
  if [ -z "${v}" ] || echo "${v}" | grep -Eq "O\.E\.M\.|System|To Be Filled By O\.E\.M\."; then
    if [ -r /sys/class/dmi/id/board_vendor ]; then
      v="$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || true)"
      v="$(echo "${v}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    fi
  fi
  if [ -n "${v}" ] && [ -n "${b}" ]; then
    BOARD="${v} ${b}"
  elif [ -n "${v}" ]; then
    BOARD="${v}"
  elif [ -n "${b}" ]; then
    BOARD="${b}"
  else
    BOARD="not available"
  fi
  RAMTOTAL="$(awk '/MemTotal:/ {printf "%.0f\n", $2 / 1024 / 1024 + 0.5}' /proc/meminfo 2>/dev/null)"
  [ -z "${RAMTOTAL}" ] && RAMTOTAL="N/A"
  GOVERNOR="$(readConfigKey "governor" "${USER_CONFIG_FILE}")"
  SECURE=$(dmesg 2>/dev/null | grep -i "Secure Boot" | awk -F'] ' '{print $2}')
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  ETHN=$(echo ${ETHX} | wc -w)
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
    DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
    KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
    ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
    ADDONS_RAW="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
    if [ -n "${ADDONS_RAW}" ]; then
      ADDONSINFO="$(echo "${ADDONS_RAW}" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')"
    else
      ADDONSINFO=""
    fi
    REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
    if [ "${REMAP}" = "acports" ] || [ "${REMAP}" = "maxports" ]; then
      PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
      DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" = "remap" ]; then
      PORTMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" = "ahci" ]; then
      AHCIPORTMAP="$(readConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}")"
    fi
    USERCMDLINEINFO_RAW="$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")"
    USERCMDLINEINFO="$(echo "${USERCMDLINEINFO_RAW}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')"
    USERSYNOINFO_RAW="$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")"
    USERSYNOINFO="$(echo "${USERSYNOINFO_RAW}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')"
    BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  fi
  DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
  CONFIGVER="$(readConfigKey "arc.version" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
  USBMOUNT="$(readConfigKey "usbmount" "${USER_CONFIG_FILE}")"
  ARCOFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  HARDDRIVES="$(readConfigKey "device.harddrives" "${USER_CONFIG_FILE}")"
  DRIVES="$(readConfigKey "device.drives" "${USER_CONFIG_FILE}")"
  MODULESINFO="$(/usr/sbin/lsmod | awk -F' ' '{print $1}' | grep -v 'Module' | tr '\n' ' ')"
  MODULESVERSION="$(cat "${MODULES_PATH}/VERSION")"
  ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")"
  LKMVERSION="$(cat "${LKMS_PATH}/VERSION")"
  CONFIGSVERSION="$(cat "${CONFIGS_PATH}/VERSION")"
  PATCHESVERSION="$(cat "${PATCH_PATH}/VERSION")"
  TIMEOUT=5
  # Print System Informations
  TEXT="\n> System: ${MACHINE} | ${BOOTSYS}"
  TEXT+="\n  Board: ${BOARD}"
  TEXT+="\n  CPU: ${CPU}"
  if [ $(lspci -d ::300 | wc -l) -gt 0 ]; then
    GPUNAME=""
    for PCI in $(lspci -d ::300 | awk '{print $1}'); do
      GPUNAME+="$(lspci -s ${PCI} | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')"
    done
    TEXT+="\n  GPU: ${GPUNAME}"
  fi
  TEXT+="\n  Memory: $((${RAMTOTAL}))GB"
  TEXT+="\n  AES: ${AESSYS}"
  TEXT+="\n  CPU Scaling | Governor: ${CPUFREQ} | ${GOVERNOR}"
  TEXT+="\n  Secure Boot: ${SECURE:-not found}"
  TEXT+="\n"
  TEXT+="\n> Network: ${ETHN} NIC"
  for N in ${ETHX}; do
    COUNT=0
    DRIVER="$(ls -ld /sys/class/net/${N}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')"
    MAC="$(cat /sys/class/net/${N}/address 2>/dev/null | sed 's/://g' | tr '[:upper:]' '[:lower:]')"
    while true; do
      if [ -z "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
        TEXT+="\n   ${DRIVER} (${MAC}): DOWN"
        break
      fi
      if [ "0" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
        TEXT+="\n   ${DRIVER} (${MAC}): NOT CONNECTED"
        break
      fi
      if [ ${COUNT} -ge ${TIMEOUT} ]; then
        TEXT+="\n   ${DRIVER} (${MAC}): TIMEOUT"
        break
      fi
      COUNT=$((${COUNT} + 1))
      IP="$(getIP "${N}")"
      if [ -n "${IP}" ]; then
        SPEED="$(/usr/sbin/ethtool ${N} 2>/dev/null | grep "Speed:" | awk '{print $2}')"
        if [[ "${IP}" =~ ^169\.254\..* ]]; then
          TEXT+="\n   ${DRIVER} (${SPEED} | ${MAC}): LINK LOCAL (No DHCP server found.)"
        else
          TEXT+="\n   ${DRIVER} (${SPEED} | ${MAC}): ${IP}"
        fi
        break
      fi
      sleep 1
    done
  done
  # Print Config Informations
  TEXT+="\n\n> Arc: ${ARC_VERSION} (${ARC_BUILD}) ${ARC_BRANCH}"
  TEXT+="\n  Subversion: Addons ${ADDONSVERSION} | Configs ${CONFIGSVERSION} | LKM ${LKMVERSION} | Modules ${MODULESVERSION} | Patches ${PATCHESVERSION}"
  TEXT+="\n  Config | Build: ${CONFDONE} | ${BUILDDONE}"
  TEXT+="\n  Config Version: ${CONFIGVER}"
  TEXT+="\n  Offline Mode: ${ARCOFFLINE}"
  [ "${ARCOFFLINE}" = "true" ] && TEXT+="\n  Offline Mode: ${ARCOFFLINE}"
  if [ "${CONFDONE}" = "true" ]; then
    TEXT+="\n> DSM ${PRODUCTVER} (${BUILDNUM}): ${MODEL}"
    TEXT+="\n  Kernel | LKM: ${KVER} | ${LKM}"
    TEXT+="\n  Platform | DeviceTree: ${PLATFORM} | ${DT}"
    TEXT+="\n  Arc Patch: ${ARCPATCH}"
    TEXT+="\n  Kernelload: ${KERNELLOAD}"
    TEXT+="\n  Directboot: ${DIRECTBOOT}"
    TEXT+="\n  Addons selected: ${ADDONSINFO}"
  else
    TEXT+="\n"
    TEXT+="\n  Config not completed!\n"
  fi
  TEXT+="\n  Modules loaded: ${MODULESINFO}"
  if [ "${CONFDONE}" = "true" ]; then
    [ -n "${USERCMDLINEINFO}" ] && TEXT+="\n  User Cmdline: ${USERCMDLINEINFO}"
    TEXT+="\n  User Synoinfo: ${USERSYNOINFO}"
  fi
  TEXT+="\n"
  TEXT+="\n> Settings"
  if [[ "${REMAP}" = "acports" || "${REMAP}" = "maxports" ]]; then
    TEXT+="\n  SataPortMap | DiskIdxMap: ${PORTMAP} | ${DISKMAP}"
  elif [ "${REMAP}" = "remap" ]; then
    TEXT+="\n  SataRemap: ${PORTMAP}"
  elif [ "${REMAP}" = "ahci" ]; then
    TEXT+="\n  AhciRemap: ${AHCIPORTMAP}"
  elif [ "${REMAP}" = "user" ]; then
    TEXT+="\n  PortMap: User"
    [ -n "${PORTMAP}" ] && TEXT+="\n  SataPortmap: ${PORTMAP}"
    [ -n "${DISKMAP}" ] && TEXT+="\n  DiskIdxMap: ${DISKMAP}"
    [ -n "${PORTREMAP}" ] && TEXT+="\n  SataRemap: ${PORTREMAP}"
    [ -n "${AHCIPORTREMAP}" ] && TEXT+="\n  AhciRemap: ${AHCIPORTREMAP}"
  fi
  if [ "${DT}" = "true" ]; then
    TEXT+="\n  Hotplug: ${HDDSORT}"
  else
    TEXT+="\n  USB Mount: ${USBMOUNT}"
  fi
  TEXT+="\n"
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS // 100=SCSI // c03=USB
  TEXT+="\n> Storage"
  TEXT+="\n  Additional Controller: ${EXTERNALCONTROLLER}"
  TEXT+="\n  Disks | Internal: ${DRIVES} | ${HARDDRIVES}"
  TEXT+="\n"
  # Get Information for Sata Controller
  NUMPORTS=0
  if [ $(lspci -d ::106 2>/dev/null | wc -l) -gt 0 ]; then
    TEXT+="\n  SATA Controller:\n"
    for PCI in $(lspci -d ::106 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://" | awk '{$1=""}1' | awk '{$1=$1};1')
      TEXT+="  ${NAME}\n  Ports: "
      PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      for P in ${PORTS}; do
        if lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep -q "\[${P}:"; then
          if [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" != "0" ]; then
            TEXT+="$(printf "%02d" ${P}) "
            NUMPORTS=$((${NUMPORTS} + 1))
          fi
        fi
      done
    done
  fi
  [ $(lspci -d ::104 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  RAID Controller:\n"
  for PCI in $(lspci -d ::104 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    TEXT+="   ${NAME}\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::107 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  HBA Controller:\n"
  for PCI in $(lspci -d ::107 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    TEXT+="   ${NAME}\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::100 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  SCSI Controller:\n"
  for PCI in $(lspci -d ::100 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/* 2>/dev/null | grep "${PCI}" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    TEXT+="   ${NAME}\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(ls -l /sys/class/scsi_host 2>/dev/null | grep usb | wc -l) -gt 0 ] && TEXT+="\n  USB Controller:\n"
  for PCI in $(lspci -d ::c03 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    TEXT+="   ${NAME}\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(ls -l /sys/block/mmc* 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  MMC Controller:\n"
  for PCI in $(lspci -d ::805 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/mmc* 2>/dev/null | grep "${PCI}" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    TEXT+="   ${NAME}\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::108 2>/dev/null | wc -l) -gt 0 ] && TEXT+="\n  NVME Controller:\n"
  for PCI in $(lspci -d ::108 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/nvme 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[N:${PORT}:" | wc -l)
    TEXT+="   ${NAME}\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  if [ $(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep 'vmbus:acpi' | wc -l) -gt 0 ]; then
    TEXT+="\n  VMBUS Controller:\n"
    NAME="vmbus:acpi"
    PORTNUM=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep 'vmbus:acpi' | wc -l)
    TEXT+="   ${NAME}\n   Disks: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  fi
  TEXT+="\n  Total Disks: ${NUMPORTS}"
  TEXT+="\n"
}

getSysinfo
echo -e "${TEXT}"