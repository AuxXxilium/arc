#!/usr/bin/env bash

set -e
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/compat.sh
. ${ARC_PATH}/boot.sh

# Get Loader Disk Bus
[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"
checkBootLoader || die "The loader is corrupted, please rewrite it!"
BUS=$(getBus "${LOADER_DISK}")

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

# Print Title centralized
clear
COLUMNS=${COLUMNS:-50}
BANNER="$(figlet -c -w "$(((${COLUMNS})))" "Arc Loader")"
TITLE="Version:"
TITLE+=" ${ARC_TITLE}"
printf "\033[1;30m%*s\n" ${COLUMNS} ""
printf "\033[1;30m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;34m%*s\033[0m\n" ${COLUMNS} "${BANNER}"
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
TITLE="Boot:"
[ ${EFI} -eq 1 ] && TITLE+=" [UEFI]" || TITLE+=" [BIOS]"
TITLE+=" [${BUS}]"
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

# Check for Config File
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
fi
# Config Init
initConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
initConfigKey "arc" "{}" "${USER_CONFIG_FILE}"
initConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.dynamic" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.ipv6" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.nic" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.offline" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
initConfigKey "bootipwait" "30" "${USER_CONFIG_FILE}"
initConfigKey "directboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "dsmlogo" "true" "${USER_CONFIG_FILE}"
initConfigKey "emmcboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "governor" "performance" "${USER_CONFIG_FILE}"
initConfigKey "hddsort" "false" "${USER_CONFIG_FILE}"
initConfigKey "kernel" "official" "${USER_CONFIG_FILE}"
initConfigKey "kernelload" "power" "${USER_CONFIG_FILE}"
initConfigKey "kernelpanic" "5" "${USER_CONFIG_FILE}"
initConfigKey "odp" "false" "${USER_CONFIG_FILE}"
initConfigKey "pathash" "" "${USER_CONFIG_FILE}"
initConfigKey "paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "sn" "" "${USER_CONFIG_FILE}"
initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
initConfigKey "device" "{}" "${USER_CONFIG_FILE}"
initConfigKey "device.externalcontroller" "false" "${USER_CONFIG_FILE}"
initConfigKey "keymap" "" "${USER_CONFIG_FILE}"
initConfigKey "layout" "" "${USER_CONFIG_FILE}"
initConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
initConfigKey "modblacklist" "evbug,cdc_ether" "${USER_CONFIG_FILE}"
initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
initConfigKey "model" "" "${USER_CONFIG_FILE}"
initConfigKey "modelid" "" "${USER_CONFIG_FILE}"
initConfigKey "network" "{}" "${USER_CONFIG_FILE}"
initConfigKey "platform" "" "${USER_CONFIG_FILE}"
initConfigKey "productver" "" "${USER_CONFIG_FILE}"
initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "rd-compressed" "false" "${USER_CONFIG_FILE}"
initConfigKey "satadom" "2" "${USER_CONFIG_FILE}"
initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
initConfigKey "time" "{}" "${USER_CONFIG_FILE}"
initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
if grep -q "automated_arc" /proc/cmdline; then
  writeConfigKey "automated" "true" "${USER_CONFIG_FILE}"
else
  writeConfigKey "automated" "false" "${USER_CONFIG_FILE}"
fi
[ $(echo "${ARC_VERSION}" | grep -q "s" | wc -l) -gt 0 ] && writeConfigKey "arc.branch" "s" "${USER_CONFIG_FILE}" || writeConfigKey "arc.branch" "" "${USER_CONFIG_FILE}"
[ -f "${PART3_PATH}/automated" ] && rm -f "${PART3_PATH}/automated" >/dev/null
[ -f rm -f "${PART1_PATH}/dynamic" ] && rm -f "${PART1_PATH}/dynamic" >/dev/null
# Check for compatibility
compatboot

# Init Network
ETHX="$(ls /sys/class/net/ 2>/dev/null | grep eth)"
if arrayExistItem "sortnetif:" $(readConfigMap "addons" "${USER_CONFIG_FILE}"); then
  _sort_netif "$(readConfigKey "addons.sortnetif" "${USER_CONFIG_FILE}")"
fi
[ ! -f /var/run/dhcpcd/pid ] && /etc/init.d/S41dhcpcd restart >/dev/null 2>&1 || true
# Read/Write IP/Mac config
for ETH in ${ETHX}; do
  MACR="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g' | tr '[:upper:]' '[:lower:]')"
  IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
  if [ -n "${IPR}" ]; then
    IFS='/' read -r -a IPRA <<<"$IPR"
    ip addr flush dev $ETH
    ip addr add ${IPRA[0]}/${IPRA[1]:-"255.255.255.0"} dev $ETH
    if [ -n "${IPRA[2]}" ]; then
      ip route add default via ${IPRA[2]} dev $ETH
    fi
    if [ -n "${IPRA[3]:-${IPRA[2]}}" ]; then
      sed -i "/nameserver ${IPRA[3]:-${IPRA[2]}}/d" /etc/resolv.conf
      echo "nameserver ${IPRA[3]:-${IPRA[2]}}" >>/etc/resolv.conf
    fi
    sleep 1
  fi
  [ "${ETH::3}" = "eth" ] && ethtool -s ${ETH} wol g 2>/dev/null || true
  [ "${ETH::3}" = "eth" ] && ethtool -K ${ETH} rxhash off 2>/dev/null || true
  initConfigKey "${ETH}" "${MACR}" "${USER_CONFIG_FILE}"
done
ETHN="$(echo ${ETHX} | wc -w)"
writeConfigKey "device.nic" "${ETHN}" "${USER_CONFIG_FILE}"
# No network devices
echo
[ ${ETHN} -le 0 ] && die "No NIC found! - Loader does not work without Network connection."

# Get the VID/PID if we are in USB
VID="0x46f4"
PID="0x0001"

BUSLIST="usb sata scsi nvme mmc xen"
if [ "${BUS}" == "usb" ]; then
  VID="0x$(udevadm info --query property --name "${LOADER_DISK}" | grep ID_VENDOR_ID | cut -d= -f2)"
  PID="0x$(udevadm info --query property --name "${LOADER_DISK}" | grep ID_MODEL_ID | cut -d= -f2)"
elif ! echo "${BUSLIST}" | grep -wq "${BUS}"; then
  die "Loader Disk (${BUS}) is not USB or SATA/SCSI/NVME/eMMC"
fi

# Inform user and check bus
echo -e "Loader Disk: \033[1;34m${LOADER_DISK}\033[0m"
echo -e "Loader Disk Type: \033[1;34m${BUS}\033[0m"

# Save variables to user config file
writeConfigKey "vid" ${VID} "${USER_CONFIG_FILE}"
writeConfigKey "pid" ${PID} "${USER_CONFIG_FILE}"

# Load keymap name
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"

# Loads a keymap if is valid
if [ -n "${LAYOUT}" ] && [ -n "${KEYMAP}" ]; then
  if [ -f "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" ]; then
    echo -e "Loading User Keymap: \033[1;34m${LAYOUT}/${KEYMAP}\033[0m"
    zcat "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" | loadkeys
  fi
fi
echo

# Decide if boot automatically
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
if grep -q "force_arc" /proc/cmdline; then
  echo -e "\033[1;34mStarting Config Mode...\033[0m"
elif grep -q "automated_arc" /proc/cmdline; then
  echo -e "\033[1;34mStarting automated Build Mode...\033[0m"
elif grep -q "update_arc" /proc/cmdline; then
  echo -e "\033[1;34mStarting Update Mode...\033[0m"
elif [ "${BUILDDONE}" == "true" ]; then
  echo -e "\033[1;34mStarting DSM Mode...\033[0m"
  bootDSM
  exit 0
else
  echo -e "\033[1;34mStarting Config Mode...\033[0m"
fi
echo

BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
[ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=30
echo -e "\033[1;34mDetected ${ETHN} NIC.\033[0m \033[1;37mWaiting for Connection:\033[0m"
sleep 3
for ETH in ${ETHX}; do
  COUNT=0
  DRIVER=$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
  while true; do
    if ethtool ${ETH} 2>/dev/null | grep 'Link detected' | grep -q 'no'; then
      echo -e "\r\033[1;37m${DRIVER}:\033[0m NOT CONNECTED"
      break
    fi
    COUNT=$((${COUNT} + 1))
    IP="$(getIP ${ETH})"
    if [ -n "${IP}" ]; then
      SPEED=$(ethtool ${ETH} 2>/dev/null | grep "Speed:" | awk '{print $2}')
      if [[ "${IP}" =~ ^169\.254\..* ]]; then
        echo -e "\r\033[1;37m${DRIVER} (${SPEED}):\033[0m LINK LOCAL (No DHCP server found.)"
      else
        echo -e "\r\033[1;37m${DRIVER} (${SPEED}):\033[0m Access \033[1;34mhttp://${IP}:7681\033[0m to connect to Arc via web interface."
      fi
      break
    fi
    if ! ip link show ${ETH} 2>/dev/null | grep -q 'UP'; then
      echo -e "\r\033[1;37m${DRIVER}:\033[0m DOWN"
      break
    fi
    if [ ${COUNT} -ge ${BOOTIPWAIT} ]; then
      echo -e "\r\033[1;37m${DRIVER}:\033[0m TIMEOUT"
      break
    fi
    sleep 1
  done
done

# Inform user
echo
echo -e "Call \033[1;34marc.sh\033[0m to configure Arc"
echo
echo -e "User config is on \033[1;34m${USER_CONFIG_FILE}\033[0m"
echo -e "Default SSH Root password is \033[1;34marc\033[0m"
echo

mkdir -p "${ADDONS_PATH}"
mkdir -p "${CUSTOM_PATH}"
mkdir -p "${LKMS_PATH}"
mkdir -p "${MODEL_CONFIG_PATH}"
mkdir -p "${MODULES_PATH}"
mkdir -p "${PATCH_PATH}"
mkdir -p "${USER_UP_PATH}"

# Load Arc Overlay
echo -e "\033[1;34mLoading Arc Overlay...\033[0m"

# Check memory and load Arc
RAM=$(free -m | grep -i mem | awk '{print$2}')
if [ ${RAM} -le 3500 ]; then
  echo -e "\033[1;31mYou have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of RAM.\033[0m\n"
  echo -e "\033[1;31mUse arc.sh to proceed. Not recommended!\033[0m\n"
else
 if grep -q "update_arc" /proc/cmdline; then
    update.sh
  else
    arc.sh
  fi
fi

exit 0