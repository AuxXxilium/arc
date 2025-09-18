[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/consts.sh"
. "${ARC_PATH}/include/configFile.sh"
. "${ARC_PATH}/include/addons.sh"
. "${ARC_PATH}/include/modules.sh"

###############################################################################
# Check loader disk
function checkBootLoader() {
  while read KNAME RO; do
    [ -z "${KNAME}" ] && continue
    [ "${RO}" = "0" ] && continue
    hdparm -r0 "${KNAME}" >/dev/null 2>&1 || true
  done < <(lsblk -pno KNAME,RO 2>/dev/null)
  [ ! -w "${PART1_PATH}" ] && return 1
  [ ! -w "${PART2_PATH}" ] && return 1
  [ ! -w "${PART3_PATH}" ] && return 1
  type -p awk >/dev/null || return 1
  type -p cut >/dev/null || return 1
  type -p sed >/dev/null || return 1
  type -p tar >/dev/null || return 1
  return 0
}

###############################################################################
# Check boot mode
function arc_mode() {
  if grep -q 'automated_arc' /proc/cmdline; then
    ARC_MODE="automated"
  elif grep -q 'update_arc' /proc/cmdline; then
    ARC_MODE="update"
  elif grep -q 'force_arc' /proc/cmdline; then
    ARC_MODE="config"
  elif grep -q "force_junior" /proc/cmdline; then
    ARC_MODE="reinstall"
  elif grep -q "recovery" /proc/cmdline; then
    ARC_MODE="recovery"
  else
    ARC_MODE="dsm"
  fi
}

###############################################################################
# Check for NIC and IP
function checkNIC() {
  # Get Amount of NIC
  local BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT="20"
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  for N in ${ETHX}; do
    COUNT=0
    DRIVER="$(basename "$(realpath "/sys/class/net/${N}/device/driver" 2>/dev/null)" 2>/dev/null)"
    while true; do
      CARRIER=$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)
      if [ "${CARRIER}" = "0" ]; then
        echo -e "\r${DRIVER}: \033[1;37mNOT CONNECTED\033[0m"
        break
      elif [ -z "${CARRIER}" ]; then
        echo -e "\r${DRIVER}: \033[1;37mDOWN\033[0m"
        break
      fi
      COUNT=$((COUNT + 1))
      IP="$(getIP "${N}")"
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${N} 2>/dev/null | awk '/Speed:/ {print $2}')
        if echo "${IP}" | grep -q "^169\.254\."; then
          echo -e "\r${DRIVER} (${SPEED}): \033[1;37mLINK LOCAL (No DHCP server found.)\033[0m"
        else
          echo -e "\r${DRIVER} (${SPEED}): \033[1;37m${IP}\033[0m"
          [ -z "${IPCON}" ] && IPCON="${IP}"
        fi
        break
      fi
      if [ "${COUNT}" -ge "${BOOTIPWAIT}" ]; then
        echo -e "\r${DRIVER}: \033[1;37mTIMEOUT\033[0m"
        break
      fi
      sleep 1
    done
  done
}

###############################################################################
# Just show error message and dies
function die() {
  echo -e "\033[1;41m${*}\033[0m"
  exit 1
}

###############################################################################
# Show error message with log content and dies
function dieLog() {
  echo -en "\n\033[1;41mUNRECOVERY ERROR: "
  cat "${LOG_FILE}"
  echo -e "\033[0m"
  sleep 3
  exit 1
}

###############################################################################
# Check if a item exists into array
# 1 - Item
# 2.. - Array
# Return 0 if exists
function arrayExistItem() {
  EXISTS=1
  ITEM="${1}"
  shift
  for i in "$@"; do
    [ "${i}" = "${ITEM}" ] || continue
    EXISTS=0
    break
  done
  return ${EXISTS}
}

###############################################################################
# Generate a random serial number for a model
# 1 - Arc Patch
# 2 - Model
# Returns serial number
function generateSerial() {
  SERIAL="$(genArc "${1}" "${2}" sn 2>/dev/null)"
  echo "${SERIAL}"
  return
}

###############################################################################
# Generate a MAC address for a model
# 1 - Arc Patch
# 2 - Model
# 3 - Amount
# Returns serial number
function generateMacAddress() {
  MACS="$(genArc "${1}" "${2}" mac "${3}" 2>/dev/null)"
  MACS="$(echo "${MACS}" | tr '[:upper:]' '[:lower:]')"
  echo "${MACS}"
  return
}

###############################################################################
# Check if a item exists into array
# 1 - Item
# 2.. - Array
# Return 0 if exists
function arrayExistItem() {
  EXISTS=1
  ITEM="${1}"
  shift
  for i in "$@"; do
    [ "${i}" = "${ITEM}" ] || continue
    EXISTS=0
    break
  done
  return ${EXISTS}
}

###############################################################################
# Get values in .conf K=V file
# 1 - file
# 2 - key
function _get_conf_kv() {
  grep "^$2=" "$1" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//;s/"$//' 2>/dev/null
  return $?
}

###############################################################################
# Replace/remove/add values in .conf K=V file
# 1 - file
# 2 - key
# 3 - value
function _set_conf_kv() {
  # Delete
  if [ -z "$3" ]; then
    sed -i "/^$2=/d" "$1" 2>/dev/null
    return $?
  fi

  # Replace
  if grep -q "^$2=" "$1" 2>/dev/null; then
    sed -i "s#^$2=.*#$2=\"$3\"#" "$1" 2>/dev/null
    return $?
  fi

  # Add if it doesn't exist
  mkdir -p "$(dirname "$1" 2>/dev/null)" 2>/dev/null
  echo "$2=\"$3\"" >>"$1" 2>/dev/null
  return $?
}

###############################################################################
# sort netif name
# @1 -mac1,mac2,mac3...
function _sort_netif() {
  ETHLIST=""
  for F in /sys/class/net/eth*; do
    [ ! -e "${F}" ] && continue
    local ETH MAC BUS
    ETH="$(basename "${F}")"
    MAC="$(cat "/sys/class/net/${ETH}/address" 2>/dev/null | sed 's/://g; s/.*/\L&/')"
    BUS="$(ethtool -i "${ETH}" 2>/dev/null | grep bus-info | cut -d' ' -f2)"
    ETHLIST="${ETHLIST}${BUS} ${MAC} ${ETH}\n"
  done
  ETHLISTTMPM=""
  ETHLISTTMPB="$(echo -e "${ETHLIST}" | sort)"
  if [ -n "${1}" ]; then
    MACS="$(echo "${1}" | sed 's/://g; s/,/ /g; s/.*/\L&/')"
    for MACX in ${MACS}; do
      ETHLISTTMPM="${ETHLISTTMPM}$(echo -e "${ETHLISTTMPB}" | grep "${MACX}")\n"
      ETHLISTTMPB="$(echo -e "${ETHLISTTMPB}" | grep -v "${MACX}")\n"
    done
  fi
  ETHLIST="$(echo -e "${ETHLISTTMPM}${ETHLISTTMPB}" | grep -v '^$')"
  ETHSEQ="$(echo -e "${ETHLIST}" | awk '{print $3}' | sed 's/eth//g')"
  ETHNUM="$(echo -e "${ETHLIST}" | wc -l)"

  # sort
  if [ ! "${ETHSEQ}" = "$(seq 0 $((${ETHNUM:0} - 1)))" ]; then
    /etc/init.d/S41dhcpcd stop >/dev/null 2>&1
    /etc/init.d/S40network stop >/dev/null 2>&1
    for i in $(seq 0 $((${ETHNUM:0} - 1))); do
      ip link set dev "eth${i}" name "tmp${i}"
    done
    I=0
    for i in ${ETHSEQ}; do
      ip link set dev "tmp${i}" name "eth${I}"
      I=$((I + 1))
    done
    /etc/init.d/S40network start >/dev/null 2>&1
    /etc/init.d/S41dhcpcd start >/dev/null 2>&1
  fi
  return
}

###############################################################################
# get bus of disk
# 1 - device path
function getBus() {
  local BUS=""
  [ -f "/.dockerenv" ] && BUS="docker"
  # usb/ata(ide)/sata/sas/spi(scsi)/virtio/mmc/nvme
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,TRAN 2>/dev/null | grep "${1} " | awk '{print $2}' | sed 's/^ata$/ide/' | sed 's/^spi$/scsi/')
  # usb/scsi(ide/sata/sas)/virtio/mmc/nvme/vmbus/xen(xvd)
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep "${1} " | awk '{split($2,a,":"); if(length(a)>1) print a[length(a)-1]}' | sed 's/_host//' | sed 's/^.*xen.*$/xen/')
  [ -z "${BUS}" ] && BUS="unknown"
  echo "${BUS}"
  return 0
}

###############################################################################
# get IP
# 1 - ethN
function getIP() {
  local IP=""
  if [ -n "${1}" ] && [ -d "/sys/class/net/${1}" ]; then
    IP=$(ip addr show "${1}" scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -d'/' -f1 | head -1)
    [ -z "${IP}" ] && IP=$(ip route show dev "${1}" 2>/dev/null | sed -n 's/.* via .* src \(.*\) metric .*/\1/p' | head -1)
  else
    IP=$(ip addr show scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -d'/' -f1 | head -1)
    [ -z "${IP}" ] && IP=$(ip route show 2>/dev/null | sed -n 's/.* via .* src \(.*\) metric .*/\1/p' | head -1)
  fi
  echo "${IP}"
  return
}

###############################################################################
# Find and mount the DSM root filesystem
function findDSMRoot() {
  local DSMROOTS=""
  [ -z "${DSMROOTS}" ] && DSMROOTS="$(mdadm --detail --scan 2>/dev/null | grep -v "INACTIVE-ARRAY" | grep -E "name=SynologyNAS:0|name=DiskStation:0|name=SynologyNVR:0|name=BeeStation:0" | awk '{print $2}' | uniq)"
  [ -z "${DSMROOTS}" ] && DSMROOTS="$(lsblk -pno KNAME,PARTN,FSTYPE,FSVER,LABEL | grep -E "sd[a-z]{1,2}1" | grep -w "linux_raid_member" | grep "0.9" | awk '{print $1}')"
  echo "${DSMROOTS}"
  return
}

###############################################################################
# Convert Netmask eq. 255.255.255.0 to /24
# 1 - Netmask
function convert_netmask() {
  bits=0
  for octet in $(echo $1| sed 's/\./ /g'); do 
      binbits=$(echo "obase=2; ibase=10; ${octet}"| bc | sed 's/0//g') 
      bits=$((${bits} + ${#binbits}))
  done
  echo "${bits}"
  return
}

###############################################################################
# check Cmdline
# 1 - key name
# 2 - key string
function checkCmdline() {
  return $(grub-editenv ${USER_GRUBENVFILE} list 2>/dev/null | grep "^${1}=" | cut -d'=' -f2- | grep -q "${2}")
}

###############################################################################
# get logo of model
# 1 - key name
# 2 - key string
function setCmdline() {
  [ -z "${1}" ] && return 1
  if [ -n "${2}" ]; then
    grub-editenv ${USER_GRUBENVFILE} set "${1}=${2}"
  else
    grub-editenv ${USER_GRUBENVFILE} unset "${1}"
  fi
  return
}

###############################################################################
# get logo of model
# check Cmdline
# 1 - key name
# 2 - key string
function addCmdline() {
  local CMDLINE="$(grub-editenv ${USER_GRUBENVFILE} list 2>/dev/null | grep "^${1}=" | cut -d'=' -f2-)"
  [ -n "${CMDLINE}" ] && CMDLINE="${CMDLINE} ${2}" || CMDLINE="${2}"
  setCmdline "${1}" "${CMDLINE}"
  return
}

###############################################################################
# get logo of model
# 1 - model
function delCmdline() {
  local CMDLINE="$(grub-editenv ${USER_GRUBENVFILE} list 2>/dev/null | grep "^${1}=" | cut -d'=' -f2-)"
  CMDLINE="$(echo "${CMDLINE}" | sed "s/ *${2}//; s/^[[:space:]]*//;s/[[:space:]]*$//")"
  setCmdline "${1}" "${CMDLINE}"
  return
}

###############################################################################
# check CPU Intel(VT-d)/AMD(AMD-Vi)
function checkCPU_VT_d() {
  lsmod | grep -q msr || modprobe msr 2>/dev/null
  if grep -q "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
    local VT_D_ENABLED=$(rdmsr 0x3a 2>/dev/null)
    [ "$((${VT_D_ENABLED:-0x0} & 0x5))" -eq $((0x5)) ] && return 0
  elif grep -q "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
    local IOMMU_ENABLED=$(rdmsr 0xC0010114 2>/dev/null)
    [ "$((${IOMMU_ENABLED:-0x0} & 0x1))" -eq $((0x1)) ] && return 0
  else
    return 1
  fi
}

###############################################################################
# check BIOS Intel(VT-d)/AMD(AMD-Vi)
function checkBIOS_VT_d() {
  if grep -q "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
    dmesg 2>/dev/null | grep -iq "DMAR-IR.*DRHD base" && return 0
  elif grep -q "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
    dmesg 2>/dev/null | grep -iq "AMD-Vi.*enabled" && return 0
  else
    return 1
  fi
}

###############################################################################
# Rebooting
function rebootTo() {
  local MODES="config recovery junior automated update uefi memtest"
  [ -z "${1}" ] && exit 1
  if ! echo "${MODES}" | grep -wq "${1}"; then exit 1; fi
  [ "${1}" = "automated" ] && echo "arc-${MODEL}-${PRODUCTVER}-${ARC_VERSION}" >"${PART3_PATH}/automated"
  [ ! -f "${USER_GRUBENVFILE}" ] && grub-editenv "${USER_GRUBENVFILE}" create
  grub-editenv "${USER_GRUBENVFILE}" set next_entry="${1}"
  exec reboot
  return
}

###############################################################################
# Copy DSM files to the boot partition
# 1 - DSM root path
function copyDSMFiles() {
  if [ -f "${1}/VERSION" ] && [ -f "${1}/grub_cksum.syno" ] && [ -f "${1}/GRUB_VER" ] && [ -f "${1}/zImage" ] && [ -f "${1}/rd.gz" ]; then
    # Remove old model files
    rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" "${PART2_PATH}/grub_cksum.syno" "${PART2_PATH}/GRUB_VER"
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}"
    # Remove old build files
    rm -f "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null
    # Copy new model files
    cp -f "${1}/grub_cksum.syno" "${PART1_PATH}"
    cp -f "${1}/GRUB_VER" "${PART1_PATH}"
    cp -f "${1}/grub_cksum.syno" "${PART2_PATH}"
    cp -f "${1}/GRUB_VER" "${PART2_PATH}"
    cp -f "${1}/zImage" "${ORI_ZIMAGE_FILE}"
    cp -f "${1}/rd.gz" "${ORI_RDGZ_FILE}"
    return 0
  else
    return 1
  fi
}

###############################################################################
# Livepatch
function livepatch() {
  PVALID="false"
  # Patch zImage
  echo -e ">> patching zImage..."
  if ${ARC_PATH}/zimage-patch.sh; then
    echo -e ">> patching zImage successful!"
    PVALID="true"
  else
    echo -e ">> patching zImage failed!"
    PVALID="false"
  fi
  echo
  if [ "${PVALID}" = "true" ]; then
    # Patch Ramdisk
    echo -e ">> patching Ramdisk..."
    if ${ARC_PATH}/ramdisk-patch.sh; then
      echo -e ">> patching Ramdisk successful!"
      PVALID="true"
    else
      echo -e ">> patching Ramdisk failed!"
      PVALID="false"
    fi
  fi
  echo
  if [ "${PVALID}" = "false" ]; then
    echo -e ">> Please stay patient for Update."
    sleep 5
    exit 1
  elif [ "${PVALID}" = "true" ]; then
    ZIMAGE_HASH="$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print $1}')"
    writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"
    RAMDISK_HASH="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
    writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"
    echo -e ">> DSM Image patched!"
  fi
  return
}

###############################################################################
# Check NTP and Keyboard Layout
function onlineCheck() {
  REGION="$(curl -m 10 -v "http://ip-api.com/line?fields=timezone" 2>/dev/null | tr -d '\n' | cut -d '/' -f1)"
  TIMEZONE="$(curl -m 10 -v "http://ip-api.com/line?fields=timezone" 2>/dev/null | tr -d '\n' | cut -d '/' -f2)"
  KEYMAP="$(curl -m 10 -v "http://ip-api.com/line?fields=countryCode" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  [ -z "${KEYMAP}" ] && KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
  [ -z "${KEYMAP}" ] && KEYMAP="us"
  if [ -n "${REGION}" ] && [ -n "${TIMEZONE}" ]; then
    writeConfigKey "time.region" "${REGION}" "${USER_CONFIG_FILE}"
    writeConfigKey "time.timezone" "${TIMEZONE}" "${USER_CONFIG_FILE}"
  else
    REGION="$(readConfigKey "time.region" "${USER_CONFIG_FILE}")"
    TIMEZONE="$(readConfigKey "time.timezone" "${USER_CONFIG_FILE}")"
  fi
  [ -n "${TIMEZONE}" ] && [ -n "${REGION}" ] && ln -sf "/usr/share/zoneinfo/${REGION}/${TIMEZONE}" /etc/localtime
  LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
  if [ -z "${LAYOUT}" ]; then
    [ -n "${KEYMAP}" ] && KEYMAP="$(echo ${KEYMAP} | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]' | tr -d '[:punct:]' | tr -d '[:digit:]')"
    loadkeys "${KEYMAP}" 2>/dev/null
    writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  fi
  NEWTAG="$(curl -m 10 -skL "${API_URL}" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
  if [ -n "${NEWTAG}" ]; then
    writeConfigKey "arc.offline" "false" "${USER_CONFIG_FILE}"
    checkHardwareID
  else
    writeConfigKey "arc.offline" "true" "${USER_CONFIG_FILE}"
  fi
  return
}

###############################################################################
# Check System
function systemCheck () {
  # Get Loader Disk Bus
  BUS=$(getBus "${LOADER_DISK}")
  [ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"
  # Check for Hypervisor
  MEV="$(virt-what 2>/dev/null | head -1)"
  [ -z "${MEV}" ] && MEV="physical"
  # Check for AES Support
  if grep -q "^flags.*aes.*" /proc/cpuinfo; then
    AESSYS="true"
  else
    AESSYS="false"
  fi
  # Check for CPU Frequency Scaling
  if ls /sys/devices/system/cpu/cpufreq/*/* 1>/dev/null 2>&1; then
    CPUFREQ="true"
  else
    CPUFREQ="false"
  fi
  # Check for Arc Patch
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
  arc_mode
  getnetinfo
  getdiskinfo
  getmap
  return
}

###############################################################################
# Generate HardwareID
function genHWID () {
  CPU_ID="$(dmidecode -t 4 | grep ID | sed 's/.*ID://;s/ //g' | head -1)"
  NIC_MACS=$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort | while read NIC; do
    MAC=$(cat "/sys/class/net/${NIC}/address" 2>/dev/null | sed 's/://g')
    echo "${MAC}"
  done | sort)
  NIC_MAC="$(echo "${NIC_MACS}" | head -1)"
  echo "${CPU_ID} ${NIC_MAC}" | sha256sum | awk '{print $1}' | cut -c1-16
  return
}

###############################################################################
# Check if port is valid
function check_port() {
  if [ -z "${1}" ]; then
    return 0
  else
    if [[ "${1}" =~ ^[0-9]+$ ]] && [ "${1}" -ge 0 ] && [ "${1}" -le 65535 ]; then
      return 0
    else
      return 1
    fi
  fi
}

###############################################################################
# Unmount disks
function __umountNewBlDisk() {
  umount "${TMP_PATH}/sdX1" 2>/dev/null
  umount "${TMP_PATH}/sdX2" 2>/dev/null
  umount "${TMP_PATH}/sdX3" 2>/dev/null
  return
}

function __umountDSMRootDisk() {
  umount "${TMP_PATH}/mdX"
  rm -rf "${TMP_PATH}/mdX"
  return
}

###############################################################################
# bootwait SSH/Web
function _bootwait() {
  BOOTWAIT="$(readConfigKey "bootwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTWAIT}" ] && BOOTWAIT="5"
  busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WB
  MSG=""
  while [ "${BOOTWAIT}" -gt 0 ]; do
    sleep 1
    BOOTWAIT=$((BOOTWAIT - 1))
    MSG="\033[1;33mAccess to SSH/Web will interrupt boot...\033[0m"
    echo -en "\r${MSG}"
    busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
    if ! diff WB WC >/dev/null 2>&1; then
      echo -en "\r\033[1;33mAccess to SSH/Web detected and boot is interrupted. Rebooting to config...\033[0m\n"
      rm -f WB WC
      sleep 5
      rebootTo "config"
    fi
  done
  rm -f WB WC
  echo -en "\r$(printf "%$((${#MSG} * 2))s" " ")\n"
  return
}

###############################################################################
# check and fix the DSM root partition
# 1 - DSM root path
function fixDSMRootPart() {
  if mdadm --detail "${1}" 2>/dev/null | grep -i "State" | grep -iEq "active|FAILED|Not Started"; then
    mdadm --stop "${1}" >/dev/null 2>&1
    mdadm --assemble --scan >/dev/null 2>&1
    T="$(blkid -o value -s TYPE "${1}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
    if [ "${T}" = "btrfs" ]; then
      btrfs check --readonly "${1}" >/dev/null 2>&1
    else
      fsck "${1}" >/dev/null 2>&1
    fi
  fi
  return
}

###############################################################################
# Read Data
function readData() {
  # Get DSM Data from Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  if [ -n "${MODEL}" ]; then
    PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
    DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  fi

  # Get Arc Data from Config
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  HARDWAREID="$(genHWID)"
  USERID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  SATACONTROLLER="$(readConfigKey "device.satacontroller" "${USER_CONFIG_FILE}")"
  SASCONTROLLER="$(readConfigKey "device.sascontroller" "${USER_CONFIG_FILE}")"
  SCSICONTROLLER="$(readConfigKey "device.scsicontroller" "${USER_CONFIG_FILE}")"
  RAIDCONTROLLER="$(readConfigKey "device.raidcontroller" "${USER_CONFIG_FILE}")"
  NVMECONTROLLER="$(readConfigKey "device.nvmecontroller" "${USER_CONFIG_FILE}")"
  MMCCONTROLLER="$(readConfigKey "device.mmccontroller" "${USER_CONFIG_FILE}")"
  USBCONTROLLER="$(readConfigKey "device.usbcontroller" "${USER_CONFIG_FILE}")"

  # Advanced Config
  ARC_OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
  DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
  EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
  USBMOUNT="$(readConfigKey "usbmount" "${USER_CONFIG_FILE}")"
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
  KERNELPANIC="$(readConfigKey "kernelpanic" "${USER_CONFIG_FILE}")"
  GOVERNOR="$(readConfigKey "governor" "${USER_CONFIG_FILE}")"
  STORAGEPANEL="$(readConfigKey "addons.storagepanel" "${USER_CONFIG_FILE}")"
  ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  RD_COMPRESSED="$(readConfigKey "rd-compressed" "${USER_CONFIG_FILE}")"
  SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
  REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"

  # Get Config/Build Status
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"

  # Development Mode
  DEVELOPMENT_MODE="$(readConfigKey "arc.dev" "${USER_CONFIG_FILE}")"

  # Remote Assistance
  REMOTEASSISTANCE="$(readConfigKey "arc.remoteassistance" "${USER_CONFIG_FILE}")"
  if [ "${ARC_MODE}" = "config" ] && [ "${REMOTEASSISTANCE}" = "true" ] && [ ! -f "${TMP_PATH}/remote.lock" ]; then
    remoteAssistance
  fi
  return
}

###############################################################################
# Menu functions
function write_menu() {
  echo "$1 \"$2\" " >>"${TMP_PATH}/menu"
  return
}
    
function write_menu_value() {
  echo "$1 \"$2: \Z4${3:-none}\Zn\" " >>"${TMP_PATH}/menu"
  return
}

################################################################################
# Function to check if a value exists in an array
function is_in_array() {
  local V="$1"
  shift
  local A=("$@")
  for I in "${A[@]}"; do
    if [[ "$I" == "$V" ]]; then
      return 0
    fi
  done
  return 1
}

###############################################################################
# Send a webhook notification
# 1 - webhook url
# 2 - message (optional)
function sendWebhook() {
  local URL="${1}"
  local MSGT="${ARC_TITLE}"
  local MSGC="${2:-"test at $(date +'%Y-%m-%d %H:%M:%S')"}"

  [ -z "${URL}" ] && return 1

  curl -skL -X POST -H "Content-Type: application/json" -d "{\"title\":\"${MSGT}\", \"text\":\"${MSGC}\"}" "${URL}" >/dev/null 2>&1
  return $?
}

###############################################################################
# Send a discord notification
# 1 - userid
# 2 - message (optional)
function sendDiscord() {
  local USERID="${1}"
  local MSGT="${ARC_TITLE}"
  local MSGC="${2:-"test at $(date +'%Y-%m-%d %H:%M:%S')"}"
  [ -z "${USERID}" ] && return 1

  local MESSAGE="**${MSGT}**: ${MSGC}"
  local ENCODED_MSG=$(echo "${MESSAGE}" | jq -sRr @uri)
  curl -skL "https://arc.auxxxilium.tech/notify.php?id=${USERID}&message=${ENCODED_MSG}" >/dev/null 2>&1
  return $?
}

###############################################################################
# Get Board Name
function getBoardName() {
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
  echo "${BOARD}"
  return
}

###############################################################################
# Reset build
function resetBuild() {
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  return
}