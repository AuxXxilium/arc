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
# Check if a item exists into array
# 1 - Item
# 2.. - Array
# Return 0 if exists
function arrayExistItem() {
  EXISTS=1
  ITEM="${1}"
  shift
  for i in "$@"; do
    [ "${i}" == "${ITEM}" ] || continue
    EXISTS=0
    break
  done
  return ${EXISTS}
}

###############################################################################
# sort netif name
# @1 -mac1,mac2,mac3...
function _sort_netif() {
  local ETHLIST=""
  local ETHX="$(ls /sys/class/net/ 2>/dev/null | grep eth)" # real network cards list
  for ETH in ${ETHX}; do
    local MAC="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g; s/.*/\L&/')"
    local ETHBUS="$(ethtool -i ${ETH} 2>/dev/null | grep bus-info | cut -d' ' -f2)"
    ETHLIST="${ETHLIST}${ETHBUS} ${MAC} ${ETH}\n"
  done
  local ETHLISTTMPM=""
  local ETHLISTTMPB="$(echo -e "${ETHLIST}" | sort)"
  if [ -n "${1}" ]; then
    local MACS="$(echo "${1}" | sed 's/://g; s/,/ /g; s/.*/\L&/')"
    for MACX in ${MACS}; do
      ETHLISTTMPM="${ETHLISTTMPM}$(echo -e "${ETHLISTTMPB}" | grep "${MACX}")\n"
      ETHLISTTMPB="$(echo -e "${ETHLISTTMPB}" | grep -v "${MACX}")\n"
    done
  fi
  local ETHLIST="$(echo -e "${ETHLISTTMPM}${ETHLISTTMPB}" | grep -v '^$')"
  local ETHSEQ="$(echo -e "${ETHLIST}" | awk '{print $3}' | sed 's/eth//g')"
  local ETHNUM="$(echo -e "${ETHLIST}" | wc -l)"
  # sort
  if [ ! "${ETHSEQ}" == "$(seq 0 $((${ETHNUM:0} - 1)))" ]; then
    /etc/init.d/S41dhcpcd stop >/dev/null 2>&1
    /etc/init.d/S40network stop >/dev/null 2>&1
    for i in $(seq 0 $((${ETHNUM:0} - 1))); do
      ip link set dev eth${i} name tmp${i}
    done
    local I=0
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
# Arc Base File download
function updateLoader() {
  idx=0
  while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
    local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ]; then
    (
      echo "Downloading ${TAG}"
      local URL="https://github.com/AuxXxilium/arc/releases/download/${TAG}/update-${TAG}.zip"
      curl -#kL "${URL}" -o "${TMP_PATH}/update.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
      done
      if [ -f "${TMP_PATH}/update.zip" ]; then
        echo -e "Downloading Base Image successful!\nUpdating Base Image..."
        if unzip -oq "${TMP_PATH}/update.zip" -d "${TMP_PATH}"; then
          cp -f "${TMP_PATH}/bzImage-arc" "${PART3_PATH}/bzImage-arc"
          cp -f "${TMP_PATH}/initrd-arc" "${PART3_PATH}/initrd-arc"
          rm -f "${TMP_PATH}/update.zip" >/dev/null
          echo "${TAG}" > "${PART1_PATH}/ARC-BASE-VERSION"
          echo "Successful! -> Rebooting..."
          sleep 2
        else
          echo "Failed to unpack Base Image."
          return 1
        fi
      else
        echo "Failed to download Base Image."
        return 1
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "System" \
      --progressbox "Installing Base Image..." 20 70
  fi
  return 0
}

###############################################################################
# Arc System Files download
function getArcSystem() {
  local DEST_PATH="${PART3_PATH}/system"
  local CACHE_FILE="/tmp/system.zip"
  local DEV="${1}"
  rm -f "${CACHE_FILE}"
  if [ -n "${DEV}" ]; then
    if curl -m 10 --interface "${DEV}" -skL "https://api.github.com/repos/AuxXxilium/arc-system/releases" | jq -r ".[].tag_name" | grep "dev" | sort -rV | head -1; then
      local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-system/releases" | jq -r ".[].tag_name" | grep "dev" | sort -rV | head -1)"
    fi
  elif curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-system/releases" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1; then
    local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-system/releases" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
  fi
  if curl -skL "https://github.com/AuxXxilium/arc-system/releases/download/${TAG}/system-${TAG}.zip" -o "${CACHE_FILE}"; then
    echo "${TAG}" >"${PART1_PATH}/ARC-VERSION"
    # Unzip LKMs
    rm -rf "${DEST_PATH}"
    mkdir -p "${DEST_PATH}"
    unzip "${CACHE_FILE}" -d "${PART3_PATH}" >/dev/null 2>&1
    [ -f "${SYSTEM_PATH}/grub.cfg" ] && cp -f "${SYSTEM_PATH}/grub.cfg" "${USER_GRUB_CONFIG}"
    rm -f "${CACHE_FILE}"
    return 0
  else
    echo -e "Failed to download Arc System Files. Check your network connection.\nYou can restart download with 'init.sh' command."
    return 1
  fi
}