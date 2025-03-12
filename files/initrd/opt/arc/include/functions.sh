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
  command -v awk >/dev/null 2>&1 || return 1
  command -v cut >/dev/null 2>&1 || return 1
  command -v sed >/dev/null 2>&1 || return 1
  command -v tar >/dev/null 2>&1 || return 1
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
  else
    ARC_MODE="dsm"
  fi
  [ "$(readConfigKey "${MODEL:-SA6400}.serial" "${S_FILE}")" ] && ARC_CONF="true" || true
}


###############################################################################
# Check for NIC and IP
function checkNIC() {
  # Get Amount of NIC
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
        if [[ "${IP}" =~ ^169\.254\..* ]]; then
          echo -e "\r${DRIVER} (${SPEED}): \033[1;37mLINK LOCAL (No DHCP server found.)\033[0m"
        else
          echo -e "\r${DRIVER} (${SPEED}): \033[1;37m${IP}\033[0m"
          [ -z "${IPCON}" ] && IPCON="${IP}"
        fi
        break
      fi
      if [ ${COUNT} -ge ${BOOTIPWAIT} ]; then
        echo -e "\r${DRIVER}: \033[1;37mTIMEOUT\033[0m"
        break
      fi
      sleep 1
    done
  done
  return 0
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
# Generate a number with 6 digits from 1 to 30000
function random() {
  printf "%06d" $((${RANDOM} % 30000 + 1))
}

###############################################################################
# Generate a hexa number from 0x00 to 0xFF
function randomhex() {
  printf "&02X" "$((${RANDOM} % 255 + 1))"
}

###############################################################################
# Generate a random digit (0-9A-Z)
function genRandomDigit() {
  echo {0..9} | tr ' ' '\n' | sort -R | head -1
}

###############################################################################
# Generate a random letter
function genRandomLetter() {
  for i in A B C D E F G H J K L M N P Q R S T V W X Y Z; do
    echo ${i}
  done | sort -R | tail -1
}

###############################################################################
# Generate a random digit (0-9A-Z)
function genRandomValue() {
  for i in 0 1 2 3 4 5 6 7 8 9 A B C D E F G H J K L M N P Q R S T V W X Y Z; do
    echo ${i}
  done | sort -R | tail -1
}

###############################################################################
# Generate a random serial number for a model
# 1 - Model
# 2 - Arc
# Returns serial number
function generateSerial() {
  PREFIX="$(readConfigArray "${1}.prefix" "${S_FILE}" 2>/dev/null | sort -R | tail -1)"
  MIDDLE="$(readConfigArray "${1}.middle" "${S_FILE}" 2>/dev/null | sort -R | tail -1)"
  if [ "${2}" = "true" ]; then
    SUFFIX="arc"
  else
    SUFFIX="$(readConfigKey "${1}.suffix" "${S_FILE}" 2>/dev/null)"
  fi

  local SERIAL="${PREFIX:-"0000"}${MIDDLE:-"XXX"}"
  case "${SUFFIX:-"alpha"}" in
    numeric)
      SERIAL+="$(random)"
      ;;
    alpha)
      SERIAL+="$(genRandomLetter)$(genRandomValue)$(genRandomValue)$(genRandomValue)$(genRandomValue)$(genRandomValue)"
      ;;
    arc)
      SERIAL+="$(readConfigKey "${1}.serial" "${S_FILE}" 2>/dev/null)"
      ;;
  esac

  SERIAL="$(echo "${SERIAL}" | tr '[:lower:]' '[:upper:]')"
  echo "${SERIAL}"
  return 0
}

###############################################################################
# Generate a MAC address for a model
# 1 - Model
# 2 - Amount of MACs to generate
# 3 - Arc MAC
# Returns serial number
function generateMacAddress() {
  MACPRE="$(readConfigKey "${1}.macpre" "${S_FILE}")"
  if [ "${3}" = "true" ]; then
    MACSUF="$(readConfigKey "${1}.mac" "${S_FILE}" 2>/dev/null)"
  else
    MACSUF="$(printf '%02x%02x%02x' $((${RANDOM} % 256)) $((${RANDOM} % 256)) $((${RANDOM} % 256)))"
  fi
  NUM=${2:-1}
  local MACS=""
  for I in $(seq 1 ${NUM}); do
    MACS+="$(printf '%06x%06x' $((0x${MACPRE:-"001132"})) $(($((0x${MACSUF})) + ${I})))"
    [ ${I} -lt ${NUM} ] && MACS+=" "
  done

  MACS="$(echo "${MACS}" | tr '[:upper:]' '[:lower:]')"
  echo "${MACS}"
  return 0
}

###############################################################################
function generate_and_write_serial() {
  local use_patch=$1
  SN="$(generateSerial "${MODEL}" "${use_patch}")"
  writeConfigKey "arc.patch" "${use_patch}" "${USER_CONFIG_FILE}"
  writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
}

###############################################################################
# Validate a serial number for a model
# 1 - Model
# 2 - Serial number to test
# Returns 1 if serial number is invalid
function validateSerial() {
  PREFIX="$(readConfigArray "${1}.prefix" "${S_FILE}" 2>/dev/null)"
  MIDDLE="$(readConfigArray "${1}.middle" "${S_FILE}" 2>/dev/null)"
  SUFFIX="$(readConfigKey "${1}.suffix" "${S_FILE}" 2>/dev/null)"
  P=${2:0:4}
  M=${2:4:3}
  S=${2:7}
  L=${#2}
  if [ ${L} -ne 13 ]; then
    return 1
  fi
  if ! arrayExistItem ${P} ${PREFIX}; then
    return 1
  fi
  if ! arrayExistItem ${M} ${MIDDLE}; then
    return 1
  fi
  case "${SUFFIX:-"alpha"}" in
    numeric)
      if ! echo "${S}" | grep -q "^[0-9]\{6\}$"; then
        return 1
      fi
      ;;
    alpha)
      if ! echo "${S}" | grep -q "^[A-Z][0-9][0-9][0-9][0-9][A-Z]$"; then
        return 1
      fi
      ;;
  esac
  return 0
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
# 1 - key
# 2 - file
function _get_conf_kv() {
  grep "${1}" "${2}" | sed "s|^${1}=\"\(.*\)\"$|\1|g"
}

###############################################################################
# Replace/remove/add values in .conf K=V file
# 1 - name
# 2 - new_val
# 3 - path
function _set_conf_kv() {
  # Delete
  if [ -z "${2}" ]; then
    sed -i "${3}" -e "s/^${1}=.*$//"
    return $?;
  fi

  # Replace
  if grep -q "^${1}=" "${3}"; then
    sed -i "${3}" -e "s\"^${1}=.*\"${1}=\\\"${2}\\\"\""
    return $?
  fi

  # Add if doesn't exist
  echo "${1}=\"${2}\"" >>"${3}"
}

###############################################################################
# sort netif busid
function _sort_netif() {
  local ETHLIST=""
  local ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
  for N in ${ETHX}; do
    local MAC="$(cat "/sys/class/net/${N}/address" 2>/dev/null)"
    local BUS="$(ethtool -i ${N} 2>/dev/null | grep bus-info | cut -d' ' -f2)"
    ETHLIST="${ETHLIST}${BUS} ${MAC} ${N}\n"
  done
  local ETHLISTTMPB="$(echo -e "${ETHLIST}" | sort)"
  local ETHLIST="$(echo -e "${ETHLISTTMPB}" | grep -v '^$')"
  local ETHSEQ="$(echo -e "${ETHLIST}" | awk '{print $3}' | sed 's/eth//g')"
  local ETHNUM="$(echo -e "${ETHLIST}" | wc -l)"

  # sort
  if [ ! "${ETHSEQ}" = "$(seq 0 $((${ETHNUM:0} - 1)))" ]; then
    /etc/init.d/S41dhcpcd stop >/dev/null 2>&1
    /etc/init.d/S40network stop >/dev/null 2>&1
    for i in $(seq 0 $((${ETHNUM:0} - 1))); do
      ip link set dev eth${i} name tmp${i}
    done
    I=0
    for i in ${ETHSEQ}; do
      ip link set dev tmp${i} name eth${I}
      I=$((${I} + 1))
    done
    /etc/init.d/S40network start >/dev/null 2>&1
    /etc/init.d/S41dhcpcd start >/dev/null 2>&1
  fi
  return 0
}

###############################################################################
# get bus of disk
# 1 - device path
function getBus() {
  local BUS=""
  # usb/ata(ide)/sata/sas/spi(scsi)/virtio/mmc/nvme
  [ -z "${BUS}" ] && BUS="$(lsblk -dpno KNAME,TRAN 2>/dev/null | grep "${1} " | awk '{print $2}' | sed 's/^ata$/ide/' | sed 's/^spi$/scsi/')" #Spaces are intentional
  # usb/scsi(ide/sata/sas)/virtio/mmc/nvme/vmbus/xen(xvd)
  [ -z "${BUS}" ] && BUS="$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep "${1} " | awk '{print $2}' | awk -F':' '{print $(NF-1)}' | sed 's/_host//' | sed 's/^.*xen.*$/xen/')" # Spaces are intentional
  [ -z "${BUS}" ] && BUS="unknown"
  echo "${BUS}"
  return 0
}

###############################################################################
# get IP
# 1 - ethN
function getIP() {
  local IP=""
  MACR="$(cat /sys/class/net/${1}/address 2>/dev/null | sed 's/://g')"
  IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
  if [ -n "${IPR}" ]; then
    IFS='/' read -r -a IPRA <<<"${IPR}"
    IP=${IPRA[0]}
  else
    if [ -n "${1}" ] && [ -d "/sys/class/net/${1}" ]; then
      IP=$(ip route show dev ${1} 2>/dev/null | sed -n 's/.* via .* src \(.*\) metric .*/\1/p')
      [ -z "${IP}" ] && IP=$(ip addr show ${1} scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -f1 -d'/' | head -1)
    else
      IP=$(ip route show 2>/dev/null | sed -n 's/.* via .* src \(.*\) metric .*/\1/p' | head -1)
      [ -z "${IP}" ] && IP=$(ip addr show scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -f1 -d'/' | head -1)
    fi
  fi
  echo "${IP}"
  return 0
}

###############################################################################
# get logo of model
# 1 - model
function getLogo() {
  local MODEL="${1}"
  rm -f "${PART3_PATH}/logo.png"
  STATUS=$(curl -skL -m 10 -w "%{http_code}" "https://www.synology.com/api/products/getPhoto?product=${MODEL/+/%2B}&type=img_s&sort=0" -o "${PART3_PATH}/logo.png")
  if [ $? -ne 0 -o ${STATUS:-0} -ne 200 -o ! -f "${PART3_PATH}/logo.png" ]; then
    rm -f "${PART3_PATH}/logo.png"
    return 1
  fi
  convert -rotate 180 "${PART3_PATH}/logo.png" "${PART3_PATH}/logo.png" 2>/dev/null
  magick montage "${PART3_PATH}/logo.png" -background 'none' -tile '3x3' -geometry '350x210' "${PART3_PATH}/logo.png" 2>/dev/null
  convert -rotate 180 "${PART3_PATH}/logo.png" "${PART3_PATH}/logo.png" 2>/dev/null
  return 0
}

###############################################################################
# Find and mount the DSM root filesystem
function findDSMRoot() {
  local DSMROOTS=""
  [ -z "${DSMROOTS}" ] && DSMROOTS="$(mdadm --detail --scan 2>/dev/null | grep -E "name=SynologyNAS:0|name=DiskStation:0|name=SynologyNVR:0|name=BeeStation:0" | awk '{print $2}' | uniq)"
  [ -z "${DSMROOTS}" ] && DSMROOTS="$(lsblk -pno KNAME,PARTN,FSTYPE,FSVER,LABEL | grep -E "sd[a-z]{1,2}1" | grep -w "linux_raid_member" | grep "0.9" | awk '{print $1}')"
  echo "${DSMROOTS}"
  return 0
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
}

###############################################################################
# get logo of model
# 1 - model
function delCmdline() {
  local CMDLINE="$(grub-editenv ${USER_GRUBENVFILE} list 2>/dev/null | grep "^${1}=" | cut -d'=' -f2-)"
  CMDLINE="$(echo "${CMDLINE}" | sed "s/ *${2}//; s/^[[:space:]]*//;s/[[:space:]]*$//")"
  setCmdline "${1}" "${CMDLINE}"
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
  [ ! -f "${USER_GRUBENVFILE}" ] && grub-editenv ${USER_GRUBENVFILE} create
  # echo -e "Rebooting to ${1} mode..."
  grub-editenv ${USER_GRUBENVFILE} set next_entry="${1}"
  exec reboot
}

###############################################################################
# Copy DSM files to the boot partition
# 1 - DSM root path
function copyDSMFiles() {
  if [ -f "${1}/grub_cksum.syno" ] && [ -f "${1}/GRUB_VER" ] && [ -f "${1}/zImage" ] && [ -f "${1}/rd.gz" ]; then
    rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" "${PART2_PATH}/grub_cksum.syno" "${PART2_PATH}/GRUB_VER" >/dev/null
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" >/dev/null
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
  echo -e "Patching zImage..."
  if ${ARC_PATH}/zimage-patch.sh; then
    echo -e "Patching zImage - successful!"
    PVALID="true"
  else
    echo -e "Patching zImage - failed!"
    PVALID="false"
  fi
  if [ "${PVALID}" = "true" ]; then
    # Patch Ramdisk
    echo -e "Patching Ramdisk..."
    if ${ARC_PATH}/ramdisk-patch.sh; then
      echo -e "Patching Ramdisk - successful!"
      PVALID="true"
    else
      echo -e "Patching Ramdisk - failed!"
      PVALID="false"
    fi
  fi
  if [ "${PVALID}" = "false" ]; then
    echo
    echo -e "Please stay patient for Update."
    sleep 5
    exit 1
  elif [ "${PVALID}" = "true" ]; then
    ZIMAGE_HASH="$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print $1}')"
    writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"
    RAMDISK_HASH="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
    writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"
    echo -e "DSM Image patched!"
  fi
}

###############################################################################
# Check NTP and Keyboard Layout
function onlineCheck() {
  REGION="$(curl -m 10 -v "http://ip-api.com/line?fields=timezone" 2>/dev/null | tr -d '\n' | cut -d '/' -f1)"
  TIMEZONE="$(curl -m 10 -v "http://ip-api.com/line?fields=timezone" 2>/dev/null | tr -d '\n' | cut -d '/' -f2)"
  KEYMAP="$(curl -m 10 -v "http://ip-api.com/line?fields=countryCode" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  [ -z "${KEYMAP}" ] && KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
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
    if loadkeys "${KEYMAP:-us}" 2>/dev/null; then
      writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
    else
      KEYMAP="us"
      loadkeys "${KEYMAP}" 2>/dev/null
      writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
    fi
  fi
  if [ "${ARC_BRANCH}" != "dev" ]; then
    NEWTAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
    if [ -n "${NEWTAG}" ]; then
      writeConfigKey "arc.offline" "false" "${USER_CONFIG_FILE}"
      updateOffline
      checkHardwareID
    else
      writeConfigKey "arc.offline" "true" "${USER_CONFIG_FILE}"
    fi
  fi
}

###############################################################################
# Check System
function systemCheck () {
  # Get Loader Disk Bus
  BUS=$(getBus "${LOADER_DISK}")
  [ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"
  # Memory: Check Memory installed
  RAMTOTAL="$(awk '/MemTotal:/ {printf "%.0f\n", $2 / 1024 / 1024 + 0.5}' /proc/meminfo 2>/dev/null)"
  [ -z "${RAMTOTAL}" ] && RAMTOTAL="8"
  # Check for Hypervisor
  MACHINE="$(virt-what 2>/dev/null | head -1)"
  [ -z "${MACHINE}" ] && MACHINE="physical"
  # Check for AES Support
  if grep -q "^flags.*aes.*" /proc/cpuinfo; then
    AESSYS="true"
  else
    AESSYS="false"
  fi
  # Check for CPU Frequency Scaling
  CPUFREQUENCIES=$(ls -l /sys/devices/system/cpu/cpufreq/*/* 2>/dev/null | wc -l)
  if [ ${CPUFREQUENCIES} -gt 0 ]; then
    CPUFREQ="true"
    ACPISYS="true"
  else
    CPUFREQ="false"
    ACPISYS="false"
  fi
  # Check for Arc Patch
  arc_mode
  [ -z "${ARC_CONF}" ] && writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
  getnetinfo
  getdiskinfo
  getmap
}

###############################################################################
# Generate HardwareID
function genHWID () {
  HWID="$(echo $(dmidecode -t 4 | grep ID | sed 's/.*ID://;s/ //g' | head -1) $(ifconfig | grep eth | awk '{print $NF}' | sed 's/://g' | sort | head -1) | sha256sum | awk '{print $1}' | cut -c1-16)" 2>/dev/null
  echo "${HWID}"
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
}

function __umountDSMRootDisk() {
  umount "${TMP_PATH}/mdX"
  rm -rf "${TMP_PATH}/mdX"
}

###############################################################################
# bootwait SSH/Web
function _bootwait() {
  BOOTWAIT="$(readConfigKey "bootwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTWAIT}" ] && BOOTWAIT="5"
  busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WB
  MSG=""
  while [ ${BOOTWAIT} -gt 0 ]; do
    sleep 1
    BOOTWAIT=$((BOOTWAIT - 1))
    MSG="\033[1;33mAccess to SSH/Web will interrupt boot...\033[0m"
    echo -en "\r${MSG}"
    busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
    if ! diff WB WC >/dev/null 2>&1; then
      echo -en "\r\033[1;33mAccess to SSH/Web detected and boot is interrupted.\033[0m\n"
      rm -f WB WC
      return 1
    fi
  done
  rm -f WB WC
  echo -en "\r$(printf "%$((${#MSG} * 2))s" " ")\n"
  return 0
}

###############################################################################
# check and fix the DSM root partition
# 1 - DSM root path
function fixDSMRootPart() {
  if mdadm --detail "${1}" 2>/dev/null | grep -i "State" | grep -iEq "active|FAILED|Not Started"; then
    mdadm --stop "${1}" >/dev/null 2>&1
    mdadm --assemble --scan >/dev/null 2>&1
    fsck "${1}" >/dev/null 2>&1
  fi
}

###############################################################################
# Read Data
function readData() {
  # Get DSM Data from Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  if [ -n "${MODEL}" ]; then
    DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  fi

  # Get Arc Data from Config
  ARC_PATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  HARDWAREID="$(genHWID)"
  USERID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
  EXTERNALCONTROLLER="$(readConfigKey "device.externalcontroller" "${USER_CONFIG_FILE}")"
  SATACONTROLLER="$(readConfigKey "device.satacontroller" "${USER_CONFIG_FILE}")"
  SCSICONTROLLER="$(readConfigKey "device.scsicontroller" "${USER_CONFIG_FILE}")"
  RAIDCONTROLLER="$(readConfigKey "device.raidcontroller" "${USER_CONFIG_FILE}")"
  SASCONTROLLER="$(readConfigKey "device.sascontroller" "${USER_CONFIG_FILE}")"

  # Advanced Config
  ARC_OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  ARC_MAC="$(readConfigKey "arc.mac" "${USER_CONFIG_FILE}")"
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
  SEQUENTIALIO="$(readConfigKey "addons.sequentialio" "${USER_CONFIG_FILE}")"
  ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  RD_COMPRESSED="$(readConfigKey "rd-compressed" "${USER_CONFIG_FILE}")"
  SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
  REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
  if [ "${REMAP}" = "acports" ] || [ "${REMAP}" = "maxports" ]; then
    PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
    DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
  elif [ "${REMAP}" = "remap" ]; then
    PORTMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
  elif [ "${REMAP}" = "ahci" ]; then
    PORTMAP="$(readConfigKey "cmdline.ahci_remap" "${USER_CONFIG_FILE}")"
  elif [ "${REMAP}" = "user" ]; then
    PORTMAP="user"
  fi
  if [[ "${REMAP}" = "acports" || "${REMAP}" = "maxports" ]]; then
    SPORTMAP="SataPortMap: ${PORTMAP} | ${DISKMAP}"
  elif [ "${REMAP}" = "remap" ]; then
    SPORTMAP="SataRemap: ${PORTMAP}"
  elif [ "${REMAP}" = "ahci" ]; then
    SPORTMAP="AHCIRemap: ${PORTMAP}"
  elif [ "${REMAP}" = "user" ]; then
    SPORTMAP=""
    [ -n "${PORTMAP}" ] && SPORTMAP+="SataPortMap: ${PORTMAP}"
    [ -n "${DISKMAP}" ] && SPORTMAP+="DiskIdxMap: ${DISKMAP}"
    [ -n "${PORTREMAP}" ] && SPORTMAP+="SataRemap: ${PORTREMAP}"
    [ -n "${AHCIPORTREMAP}" ] && SPORTMAP+="AHCIRemap: ${AHCIPORTREMAP}"
  fi

  # Get Config/Build Status
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Menu functions
function write_menu() {
  echo "$1 \"$2\" " >>"${TMP_PATH}/menu"
}
    
function write_menu_value() {
  echo "$1 \"$2: \Z4${3:-none}\Zn\" " >>"${TMP_PATH}/menu"
}