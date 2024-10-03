[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" 2>/dev/null && pwd)"

. ${ARC_PATH}/include/base_consts.sh
. ${ARC_PATH}/include/base_configFile.sh

###############################################################################
# Check loader disk
function checkBootLoader() {
  while read KNAME RO; do
    [ -z "${KNAME}" ] && continue
    [ "${RO}" == "0" ] && continue
    hdparm -r0 "${KNAME}" >/dev/null 2>&1 || true
  done <<<$(lsblk -pno KNAME,RO 2>/dev/null)
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
# Just show error message and dies
function die() {
  echo -e "\033[1;41m$@\033[0m"
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
# get bus of disk
# 1 - device path
function getBus() {
  local BUS=""
  # usb/ata(ide)/sata/sas/spi(scsi)/virtio/mmc/nvme
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,TRAN 2>/dev/null | grep "${1} " | awk '{print $2}' | sed 's/^ata$/ide/' | sed 's/^spi$/scsi/') #Spaces are intentional
  # usb/scsi(ide/sata/sas)/virtio/mmc/nvme/vmbus/xen(xvd)
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep "${1} " | awk '{print $2}' | awk -F':' '{print $(NF-1)}' | sed 's/_host//' | sed 's/^.*xen.*$/xen/') # Spaces are intentional
  [ -z "${BUS}" ] && BUS="unknown"
  echo "${BUS}"
  return 0
}

###############################################################################
# get IP
# 1 - ethN
function getIP() {
  local IP=""
  MACR="$(cat /sys/class/net/${1}/address 2>/dev/null | sed 's/://g' | tr '[:upper:]' '[:lower:]')"
  IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
  if [ -n "${IPR}" ]; then
    IFS='/' read -r -a IPRA <<<"${IPR}"
    IP=${IPRA[0]}
  else
    if [ -n "${1}" ] && [ -d "/sys/class/net/${1}" ]; then
      IP=$(ip route show dev ${1} 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p')
      [ -z "${IP}" ] && IP=$(ip addr show ${1} scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -f1 -d'/' | head -1)
    else
      IP=$(ip route show 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1)
      [ -z "${IP}" ] && IP=$(ip addr show scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -f1 -d'/' | head -1)
    fi
  fi
  echo "${IP}"
  return 0
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
# Rebooting
# (based on pocopico's TCRP code)
function rebootTo() {
  local MODES="config recovery junior automated update bios memtest"
  [ -z "${1}" ] && exit 1
  if ! echo "${MODES}" | grep -qw "${1}"; then exit 1; fi
  [ ! -f "${USER_GRUBENVFILE}" ] && grub-editenv ${USER_GRUBENVFILE} create
  # echo -e "Rebooting to ${1} mode..."
  grub-editenv ${USER_GRUBENVFILE} set next_entry="${1}"
  exec reboot
}

###############################################################################
# Arc Files Download
function getArcSystem() {
  local DEST_PATH="${1:-system}"
  local CACHE_FILE="/tmp/system.zip"
  rm -f "${CACHE_FILE}"
  local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-e-system/releases" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
  local STATUS=$(curl -w "%{http_code}" -skL "https://github.com/AuxXxilium/arc-e-system/releases/download/${TAG}/system-${TAG}.zip" -o "${CACHE_FILE}")
  [ ${STATUS} -ne 200 ] && return 1
  # Unzip LKMs
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  unzip "${CACHE_FILE}" -d "${PART3_PATH}" >/dev/null 2>&1
  [ -f "${PART3_PATH}/system/grub.cfg" ] && cp -f "${PART3_PATH}/system/grub.cfg" "${USER_GRUB_CONFIG}"
  rm -f "${CACHE_FILE}"
  return 0
}