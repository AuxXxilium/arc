#!/usr/bin/env bash

set -e
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh

[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"

# Get Loader Disk Bus
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
initConfigKey "arc.bootipwait" "30" "${USER_CONFIG_FILE}"
initConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.custom" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.directboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.dsmlogo" "true" "${USER_CONFIG_FILE}"
initConfigKey "arc.emmcboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.hddsort" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.ipv6" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.kernel" "official" "${USER_CONFIG_FILE}"
initConfigKey "arc.kernelload" "power" "${USER_CONFIG_FILE}"
initConfigKey "arc.kernelpanic" "5" "${USER_CONFIG_FILE}"
initConfigKey "arc.key" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.macsys" "hardware" "${USER_CONFIG_FILE}"
initConfigKey "arc.odp" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.offline" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.sn" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
initConfigKey "device" "{}" "${USER_CONFIG_FILE}"
initConfigKey "device.externalcontroller" "false" "${USER_CONFIG_FILE}"
initConfigKey "gateway" "{}" "${USER_CONFIG_FILE}"
initConfigKey "ip" "{}" "${USER_CONFIG_FILE}"
initConfigKey "keymap" "" "${USER_CONFIG_FILE}"
initConfigKey "layout" "" "${USER_CONFIG_FILE}"
initConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
initConfigKey "mac" "{}" "${USER_CONFIG_FILE}"
initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
initConfigKey "model" "" "${USER_CONFIG_FILE}"
initConfigKey "modelid" "" "${USER_CONFIG_FILE}"
initConfigKey "netmask" "{}" "${USER_CONFIG_FILE}"
initConfigKey "platform" "" "${USER_CONFIG_FILE}"
initConfigKey "productver" "" "${USER_CONFIG_FILE}"
initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "rd-compressed" "false" "${USER_CONFIG_FILE}"
initConfigKey "satadom" "2" "${USER_CONFIG_FILE}"
initConfigKey "static" "{}" "${USER_CONFIG_FILE}"
initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
initConfigKey "time" "{}" "${USER_CONFIG_FILE}"
initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"

# Init Network
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) # real network cards list
if arrayExistItem "sortnetif:" $(readConfigMap "addons" "${USER_CONFIG_FILE}"); then
  _sort_netif "$(readConfigKey "addons.sortnetif" "${USER_CONFIG_FILE}")"
fi
MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
# Write Mac to config
NIC=0
for ETH in ${ETHX}; do
  MACR=$(cat /sys/class/net/${ETH}/address | sed 's/://g')
  if [ -z "${MACR}" ]; then
    MACR="9009d0123456"
  fi
  initConfigKey "mac.${ETH}" "${MACR}" "${USER_CONFIG_FILE}"
  if [ "${MACSYS}" == "custom" ]; then
    MACA="$(readConfigKey "mac.${ETH}" "${USER_CONFIG_FILE}")"
    if [ -n "${MACA}" ] && [ "${MACA}" != "${MACR}" ]; then
      MAC="${MACA:0:2}:${MACA:2:2}:${MACA:4:2}:${MACA:6:2}:${MACA:8:2}:${MACA:10:2}"
      echo "Setting ${ETH} MAC to ${MAC}"
      ip link set dev ${ETH} address ${MAC} >/dev/null 2>&1 || true
      STATICIP="$(readConfigKey "static.${ETH}" "${USER_CONFIG_FILE}")"
      [ "${STATICIP}" == "false" ] && /etc/init.d/S41dhcpcd restart >/dev/null 2>&1 || true
      sleep 2
    fi
  fi
  NIC=$((${NIC} + 1))
done
ETHN=$(ls /sys/class/net/ 2>/dev/null | grep eth | wc -l)
[ ${NIC} -ne ${ETHN} ] && echo -e "\033[1;31mWarning: NIC mismatch (NICs: ${NIC} | Real: ${ETHN})\033[0m"
# Write NIC Amount to config
writeConfigKey "device.nic" "${NIC}" "${USER_CONFIG_FILE}"
# No network devices
echo
[ ${NIC} -le 0 ] && die "No NIC found! - Loader does not work without Network connection."

# Get the VID/PID if we are in USB
VID="0x46f4"
PID="0x0001"

BUSLIST="usb sata scsi nvme mmc"
if [ "${BUS}" == "usb" ]; then
  VID="0x$(udevadm info --query property --name "${LOADER_DISK}" | grep ID_VENDOR_ID | cut -d= -f2)"
  PID="0x$(udevadm info --query property --name "${LOADER_DISK}" | grep ID_MODEL_ID | cut -d= -f2)"
elif ! echo "${BUSLIST}" | grep -wq "${BUS}"; then
  die "Loader disk is not USB or SATA/SCSI/NVME/eMMC DoM"
fi

# Save variables to user config file
writeConfigKey "vid" ${VID} "${USER_CONFIG_FILE}"
writeConfigKey "pid" ${PID} "${USER_CONFIG_FILE}"

# Inform user
echo -e "Loader Disk: \033[1;34m${LOADER_DISK}\033[0m"
echo -e "Loader Disk Type: \033[1;34m${BUS}\033[0m"

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
  boot.sh && exit 0
else
  echo -e "\033[1;34mStarting Config Mode...\033[0m"
fi
echo

BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
[ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=30
echo -e "\033[1;34mDetected ${NIC} NIC.\033[0m \033[1;37mWaiting for Connection:\033[0m"
for ETH in ${ETHX}; do
  IP=""
  STATICIP="$(readConfigKey "static.${ETH}" "${USER_CONFIG_FILE}")"
  ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  DRIVER=$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
  COUNT=0
  while true; do
    ARCIP="$(readConfigKey "ip.${ETH}" "${USER_CONFIG_FILE}")"
    if [ "${STATICIP}" == "true" ] && [ -n "${ARCIP}" ]; then
      /etc/init.d/S41dhcpcd stop >/dev/null 2>&1 || true
      ip addr flush dev ${ETH} 2>/dev/null || true
      NETMASK="$(readConfigKey "netmask.${ETH}" "${USER_CONFIG_FILE}")"
      GATEWAY="$(readConfigKey "gateway.${ETH}" "${USER_CONFIG_FILE}")"
      NAMESERVER="$(readConfigKey "nameserver.${ETH}" "${USER_CONFIG_FILE}")"
      IP=${ARCIP}
      #NETMASK=$(convert_netmask "${NETMASK}")
      ip addr add ${ARCIP}/${NETMASK} dev ${ETH} 2>/dev/null || true
      ip route add default via ${GATEWAY} dev ${ETH} 2>/dev/null || true
      echo "nameserver ${NAMESERVER}" >>/etc/resolv.conf.head 2>/dev/null || true
      /etc/init.d/S40network restart 2>/dev/null || true
      MSG="STATIC"
    else
      IP=$(getIP ${ETH})
      writeConfigKey "static.${ETH}" "false" "${USER_CONFIG_FILE}"
      MSG="DHCP"
    fi
    if ethtool ${ETH} 2>/dev/null | grep 'Link detected' | grep -q 'no'; then
      echo -e "\r\033[1;37m${DRIVER}:\033[0m NOT CONNECTED"
      break
    elif [ -n "${IP}" ]; then
      SPEED=$(ethtool ${ETH} 2>/dev/null | grep "Speed:" | awk '{print $2}')
      writeConfigKey "ip.${ETH}" "${IP}" "${USER_CONFIG_FILE}"
      if [[ "${IP}" =~ ^169\.254\..* ]]; then
        echo -e "\r\033[1;37m${DRIVER} (${SPEED} | ${MSG}):\033[0m LINK LOCAL (No DHCP server found.)"
      else
        echo -e "\r\033[1;37m${DRIVER} (${SPEED} | ${MSG}):\033[0m Access \033[1;34mhttp://${IP}:7681\033[0m to connect to Arc via web."
      fi
      break
    elif [ ${COUNT} -ge ${BOOTIPWAIT} ]; then
      echo -e echo -e "\r\033[1;37m${DRIVER}:\033[0m TIMEOUT"
      break
    fi
    sleep 5
    COUNT=$((${COUNT} + 4))
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